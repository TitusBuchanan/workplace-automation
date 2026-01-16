<#
  Invoke-EndpointSelfHeal.ps1

  Runs a small set of safe remediations when HealthState is Critical.
  Intended for Intune Proactive Remediations (SYSTEM, non-interactive).
#>

param(
  [switch] $IncludePendingUpdateCount,
  [string] $LogPath = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'WorkplaceAutomation\EndpointExperience\Logs\experience.jsonl' } else { Join-Path $PSScriptRoot 'experience.jsonl' })
)

Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'Write-ExperienceLog.ps1')
. (Join-Path $PSScriptRoot 'Get-EndpointExperienceMetrics.ps1')
. (Join-Path $PSScriptRoot 'Invoke-ExperienceScoring.ps1')

function Get-UserProfilePaths {
  [CmdletBinding()]
  param()

  $root = Join-Path $env:SystemDrive 'Users'
  if (-not (Test-Path -LiteralPath $root)) { return @() }

  $excluded = @('Public', 'Default', 'Default User', 'All Users')

  Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
    Where-Object { $excluded -notcontains $_.Name } |
    Select-Object -ExpandProperty FullName
}

function Remove-SafePathContents {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string] $RootPath,

    [Parameter(Mandatory = $true)]
    [string] $TargetPath
  )

  # Guardrail: only delete within the expected root.
  try {
    $rootFull = [System.IO.Path]::GetFullPath($RootPath)
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)

    if (-not $targetFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
      return [pscustomobject]@{ Removed = $false; Reason = 'Target path is outside allowed root.' }
    }

    if (-not (Test-Path -LiteralPath $targetFull)) {
      return [pscustomobject]@{ Removed = $false; Reason = 'Path not found.' }
    }

    Remove-Item -LiteralPath $targetFull -Recurse -Force -ErrorAction Stop
    return [pscustomobject]@{ Removed = $true; Reason = 'Removed.' }
  }
  catch {
    return [pscustomobject]@{ Removed = $false; Reason = $_.Exception.Message }
  }
}

function Restart-TeamsBestEffort {
  [CmdletBinding()]
  param(
    [string] $LogPath
  )

  $names = @('Teams', 'ms-teams', 'MSTeams', 'Teams2')
  $killed = 0
  $exePath = $null

  foreach ($n in $names) {
    try {
      $procs = Get-Process -Name $n -ErrorAction SilentlyContinue
      foreach ($p in $procs) {
        try {
          if ($null -eq $exePath) {
            try {
              if ($p.Path -and (Test-Path -LiteralPath $p.Path)) { $exePath = $p.Path }
            } catch {}
          }
          Stop-Process -Id $p.Id -Force -ErrorAction Stop
          $killed++
        } catch {}
      }
    } catch {}
  }

  # Best-effort restart: starting as SYSTEM may not surface UI in the user session.
  $startAttempted = $false
  $startError = $null
  if ($exePath -and (Test-Path -LiteralPath $exePath)) {
    try {
      Start-Process -FilePath $exePath -ErrorAction Stop | Out-Null
      $startAttempted = $true
    } catch {
      $startAttempted = $true
      $startError = $_.Exception.Message
    }
  }

  Start-Sleep -Seconds 3

  $stillRunning = $false
  foreach ($n in $names) {
    try {
      if (Get-Process -Name $n -ErrorAction SilentlyContinue) {
        $stillRunning = $true
        break
      }
    } catch {}
  }

  Write-ExperienceLog -Level INFO -Message 'Teams restart (best-effort) executed.' -Data @{
    ProcessesStopped = $killed
    StartAttempted   = $startAttempted
    StartExePath     = $exePath
    StartError       = $startError
    Note             = 'Running as SYSTEM: Teams UI restart may still require user session; this step is best-effort.'
    TeamsRunningPost = $stillRunning
  } -LogPath $LogPath

  [pscustomobject]@{
    ProcessesStopped = $killed
    StartAttempted   = $startAttempted
    StartExePath     = $exePath
    StartError       = $startError
    TeamsRunningPost = $stillRunning
  }
}

function Invoke-IntunePolicySync {
  [CmdletBinding()]
  param(
    [string] $LogPath
  )

  $started = New-Object System.Collections.Generic.List[object]
  $errors = New-Object System.Collections.Generic.List[string]

  try {
    $base = '\Microsoft\Windows\EnterpriseMgmt\'
    $tasks = @(Get-ScheduledTask -TaskPath $base -ErrorAction SilentlyContinue)
    if ($tasks.Count -eq 0) {
      # Some environments only expose GUID subfolders; fall back to enumerating and filtering.
      $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like "$base*" })
    }

    # Prefer PushLaunch if present; otherwise run a small set of common enrollment client schedules.
    $preferredNames = @('PushLaunch', 'Schedule #3 created by enrollment client', 'Schedule #1 created by enrollment client')

    $grouped = $tasks | Group-Object -Property TaskPath
    foreach ($g in $grouped) {
      $taskPath = $g.Name
      $candidates = @($g.Group)

      $selected = $null
      foreach ($n in $preferredNames) {
        $selected = $candidates | Where-Object { $_.TaskName -eq $n } | Select-Object -First 1
        if ($null -ne $selected) { break }
      }

      if ($null -eq $selected) {
        # Fallback: run any task with 'Push' in name.
        $selected = $candidates | Where-Object { $_.TaskName -match 'Push' } | Select-Object -First 1
      }

      if ($null -ne $selected) {
        try {
          $beforeInfo = $null
          try { $beforeInfo = Get-ScheduledTaskInfo -TaskName $selected.TaskName -TaskPath $selected.TaskPath -ErrorAction Stop } catch {}

          Start-ScheduledTask -TaskName $selected.TaskName -TaskPath $selected.TaskPath -ErrorAction Stop
          Start-Sleep -Seconds 2

          $afterInfo = $null
          try { $afterInfo = Get-ScheduledTaskInfo -TaskName $selected.TaskName -TaskPath $selected.TaskPath -ErrorAction Stop } catch {}

          $started.Add([pscustomobject]@{
            Task     = "$($selected.TaskPath)$($selected.TaskName)"
            Before   = if ($beforeInfo) { @{ LastRunTime = $beforeInfo.LastRunTime; LastTaskResult = $beforeInfo.LastTaskResult } } else { $null }
            After    = if ($afterInfo) { @{ LastRunTime = $afterInfo.LastRunTime; LastTaskResult = $afterInfo.LastTaskResult } } else { $null }
            Verified = if ($beforeInfo -and $afterInfo) { ($afterInfo.LastRunTime -ne $beforeInfo.LastRunTime) } else { $null }
          })
        } catch {
          $errors.Add("$($selected.TaskPath)$($selected.TaskName): $($_.Exception.Message)")
        }
      }
    }
  }
  catch {
    $errors.Add($_.Exception.Message)
  }

  Write-ExperienceLog -Level INFO -Message 'Triggered Intune policy sync (scheduled task best-effort).' -Data @{
    StartedTasks = @($started)
    Errors       = @($errors)
  } -LogPath $LogPath

  [pscustomobject]@{
    StartedTasks = @($started)
    Errors       = @($errors)
  }
}

function Clear-TeamsCache {
  [CmdletBinding()]
  param(
    [string] $LogPath
  )

  $results = New-Object System.Collections.Generic.List[object]
  $profiles = Get-UserProfilePaths

  foreach ($profile in $profiles) {
    $targets = @()

    # Classic Teams cache locations (per-user)
    $targets += Join-Path $profile 'AppData\Roaming\Microsoft\Teams\Cache'
    $targets += Join-Path $profile 'AppData\Roaming\Microsoft\Teams\Code Cache'
    $targets += Join-Path $profile 'AppData\Roaming\Microsoft\Teams\GPUCache'
    $targets += Join-Path $profile 'AppData\Roaming\Microsoft\Teams\IndexedDB'
    $targets += Join-Path $profile 'AppData\Roaming\Microsoft\Teams\Local Storage'
    $targets += Join-Path $profile 'AppData\Roaming\Microsoft\Teams\tmp'
    $targets += Join-Path $profile 'AppData\Roaming\Microsoft\Teams\blob_storage'
    $targets += Join-Path $profile 'AppData\Roaming\Microsoft\Teams\databases'
    $targets += Join-Path $profile 'AppData\Roaming\Microsoft\Teams\Service Worker\CacheStorage'

    # New Teams (MSIX) cache locations (per-user)
    $targets += Join-Path $profile 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache'
    $targets += Join-Path $profile 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\TempState'

    foreach ($t in $targets) {
      $r = Remove-SafePathContents -RootPath $profile -TargetPath $t
      if ($r.Removed -or $r.Reason -ne 'Path not found.') {
        $results.Add([pscustomobject]@{
          UserProfile = $profile
          Target      = $t
          Removed     = $r.Removed
          Result      = $r.Reason
        })
      }
    }
  }

  Write-ExperienceLog -Level INFO -Message 'Teams cache cleanup completed (safe per-user paths only).' -Data @{
    Entries = @($results)
  } -LogPath $LogPath

  @($results)
}

function Invoke-BasicDiskCleanup {
  [CmdletBinding()]
  param(
    [string] $LogPath
  )

  $before = $null
  try {
    $before = Get-EndpointExperienceMetrics -LogPath $LogPath
  } catch {}

  $targets = New-Object System.Collections.Generic.List[string]

  # System temp
  $targets.Add((Join-Path $env:windir 'Temp'))

  # SYSTEM temp (usually under Windows\Temp or system profile)
  if ($env:TEMP) { $targets.Add($env:TEMP) }

  # Per-user temp
  foreach ($profile in (Get-UserProfilePaths)) {
    $targets.Add((Join-Path $profile 'AppData\Local\Temp'))
  }

  $deletedCount = 0
  $deleteErrors = New-Object System.Collections.Generic.List[string]

  foreach ($t in @($targets | Select-Object -Unique)) {
    try {
      if (-not (Test-Path -LiteralPath $t)) { continue }
      Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
          Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
          $deletedCount++
        } catch {
          $deleteErrors.Add("$($_.FullName): $($_.Exception.Message)")
        }
      }
    } catch {
      $deleteErrors.Add("$t: $($_.Exception.Message)")
    }
  }

  $after = $null
  try {
    $after = Get-EndpointExperienceMetrics -LogPath $LogPath
  } catch {}

  Write-ExperienceLog -Level INFO -Message 'Basic disk cleanup completed (safe temp locations only).' -Data @{
    DeletedItemsCount = $deletedCount
    Errors            = @($deleteErrors)
    SysDriveFreePctBefore = $before.SystemDriveFreePct
    SysDriveFreePctAfter  = $after.SystemDriveFreePct
    SysDriveFreeGBBefore  = $before.SystemDriveFreeGB
    SysDriveFreeGBAfter   = $after.SystemDriveFreeGB
  } -LogPath $LogPath

  [pscustomobject]@{
    DeletedItemsCount = $deletedCount
    Errors            = @($deleteErrors)
    Before            = $before
    After             = $after
  }
}

function Invoke-EndpointSelfHeal {
  [CmdletBinding()]
  param(
    [Parameter()]
    [switch] $IncludePendingUpdateCount,

    [Parameter()]
    [string] $LogPath = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'WorkplaceAutomation\EndpointExperience\Logs\experience.jsonl' } else { Join-Path $PSScriptRoot 'experience.jsonl' })
  )

  $beforeMetrics = Get-EndpointExperienceMetrics -IncludePendingUpdateCount:$IncludePendingUpdateCount -LogPath $LogPath
  $beforeScore = Invoke-ExperienceScoring -Metrics $beforeMetrics -LogPath $LogPath

  Write-ExperienceLog -Level INFO -Message 'Self-heal starting.' -Data @{
    HealthState = $beforeScore.HealthState
    Score       = $beforeScore.Score
    Reasons     = $beforeScore.Reasons
  } -LogPath $LogPath

  if ($beforeScore.HealthState -ne 'Critical') {
    Write-ExperienceLog -Level INFO -Message 'Health is not Critical; no remediations executed.' -Data @{
      HealthState = $beforeScore.HealthState
      Score       = $beforeScore.Score
    } -LogPath $LogPath

    return [pscustomobject]@{
      RemediationsExecuted = $false
      Before              = $beforeScore
      After               = $beforeScore
    }
  }

  $actions = [ordered]@{}

  $actions.TeamsRestart = Restart-TeamsBestEffort -LogPath $LogPath
  $actions.IntuneSync   = Invoke-IntunePolicySync -LogPath $LogPath
  $actions.TeamsCache   = Clear-TeamsCache -LogPath $LogPath
  $actions.DiskCleanup  = Invoke-BasicDiskCleanup -LogPath $LogPath

  $afterMetrics = Get-EndpointExperienceMetrics -IncludePendingUpdateCount:$IncludePendingUpdateCount -LogPath $LogPath
  $afterScore = Invoke-ExperienceScoring -Metrics $afterMetrics -LogPath $LogPath

  Write-ExperienceLog -Level INFO -Message 'Self-heal completed.' -Data @{
    Before = @{ Score = $beforeScore.Score; HealthState = $beforeScore.HealthState }
    After  = @{ Score = $afterScore.Score; HealthState  = $afterScore.HealthState }
  } -LogPath $LogPath

  [pscustomobject]@{
    RemediationsExecuted = $true
    Actions              = [pscustomobject]$actions
    Before               = $beforeScore
    After                = $afterScore
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  Invoke-EndpointSelfHeal -IncludePendingUpdateCount:$IncludePendingUpdateCount -LogPath $LogPath | Out-Null
  exit 0
}

