<#
  Invoke-ExperienceScoring.ps1

  Converts endpoint metrics into a simple Digital Experience Score (0–100)
  and a health state (Healthy / Warning / Critical).

  Intune Detection mode:
  - Exit 0 when Healthy
  - Exit 1 when Critical (remediation required)
#>

param(
  [switch] $AsIntuneDetection,
  [switch] $IncludePendingUpdateCount,
  [string] $LogPath = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'WorkplaceAutomation\EndpointExperience\Logs\experience.jsonl' } else { Join-Path $PSScriptRoot 'experience.jsonl' })
)

Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'Write-ExperienceLog.ps1')
. (Join-Path $PSScriptRoot 'Get-EndpointExperienceMetrics.ps1')

function Invoke-ExperienceScoring {
  [CmdletBinding()]
  param(
    [Parameter()]
    [object] $Metrics,

    [Parameter()]
    [string] $LogPath = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'WorkplaceAutomation\EndpointExperience\Logs\experience.jsonl' } else { Join-Path $PSScriptRoot 'experience.jsonl' })
  )

  if ($null -eq $Metrics) {
    $Metrics = Get-EndpointExperienceMetrics -LogPath $LogPath
  }

  $score = 100
  $reasons = New-Object System.Collections.Generic.List[string]

  # Disk free space (system drive)
  if ($null -ne $Metrics.SystemDriveFreePct) {
    $pct = [double]$Metrics.SystemDriveFreePct
    $freeGb = $Metrics.SystemDriveFreeGB

    if (($pct -lt 5) -or ($null -ne $freeGb -and [double]$freeGb -lt 5)) {
      $score -= 40; $reasons.Add('System drive critically low on free space (<5% or <5GB).')
    }
    elseif (($pct -lt 10) -or ($null -ne $freeGb -and [double]$freeGb -lt 10)) {
      $score -= 25; $reasons.Add('System drive low on free space (<10% or <10GB).')
    }
    elseif ($pct -lt 15) {
      $score -= 10; $reasons.Add('System drive free space below 15%.')
    }
  } else {
    $score -= 10; $reasons.Add('Unable to read system drive free space.')
  }

  # Memory pressure
  if ($null -ne $Metrics.MemoryUsedPercent) {
    $m = [double]$Metrics.MemoryUsedPercent
    if ($m -ge 90) { $score -= 25; $reasons.Add('Memory utilization is very high (>=90%).') }
    elseif ($m -ge 80) { $score -= 15; $reasons.Add('Memory utilization is high (>=80%).') }
    elseif ($m -ge 70) { $score -= 5; $reasons.Add('Memory utilization is elevated (>=70%).') }
  } else {
    $score -= 5; $reasons.Add('Unable to read memory utilization.')
  }

  # CPU load (point-in-time)
  if ($null -ne $Metrics.CpuLoadPercent) {
    $c = [double]$Metrics.CpuLoadPercent
    if ($c -ge 90) { $score -= 20; $reasons.Add('CPU load is very high (>=90%).') }
    elseif ($c -ge 80) { $score -= 10; $reasons.Add('CPU load is high (>=80%).') }
    elseif ($c -ge 70) { $score -= 5; $reasons.Add('CPU load is elevated (>=70%).') }
  } else {
    $score -= 5; $reasons.Add('Unable to read CPU load.')
  }

  # Uptime (practical stability signal)
  if ($null -ne $Metrics.UptimeDays) {
    $u = [double]$Metrics.UptimeDays
    if ($u -ge 30) { $score -= 10; $reasons.Add('Device uptime is 30+ days (restart may improve stability).') }
    elseif ($u -ge 14) { $score -= 5; $reasons.Add('Device uptime is 14+ days (restart may improve stability).') }
  }

  # Windows Update status
  if ($null -ne $Metrics.WindowsUpdate) {
    if ($Metrics.WindowsUpdate.WuauservStartType -eq 'Disabled') {
      $score -= 20; $reasons.Add('Windows Update service is disabled.')
    } elseif ($Metrics.WindowsUpdate.WuauservStatus -and $Metrics.WindowsUpdate.WuauservStatus -ne 'Running') {
      $score -= 10; $reasons.Add("Windows Update service is not running ($($Metrics.WindowsUpdate.WuauservStatus)).")
    }

    if ($Metrics.WindowsUpdate.RebootPending -eq $true) {
      $score -= 20; $reasons.Add('Pending reboot detected (Windows Update / servicing).')
    }
  } else {
    $score -= 5; $reasons.Add('Unable to read Windows Update status.')
  }

  # Teams process health (informational; avoid penalizing devices with no user session)
  if ($null -ne $Metrics.Teams -and $Metrics.Teams.IsRunning -and $Metrics.Teams.ProcessCount -ge 10) {
    $score -= 5; $reasons.Add('Teams has many running processes (possible stuck state).')
  }

  if ($score -lt 0) { $score = 0 }
  if ($score -gt 100) { $score = 100 }

  $health =
    if ($score -ge 80) { 'Healthy' }
    elseif ($score -ge 60) { 'Warning' }
    else { 'Critical' }

  $result = [pscustomobject]@{
    Score       = [int][math]::Round($score, 0)
    HealthState = $health
    Reasons     = @($reasons)
    Metrics     = $Metrics
  }

  try {
    Write-ExperienceLog -Level INFO -Message 'Calculated endpoint experience score.' -Data @{
      Score       = $result.Score
      HealthState = $result.HealthState
      Reasons     = $result.Reasons
    } -LogPath $LogPath
  } catch {}

  $result
}

if ($MyInvocation.InvocationName -ne '.') {
  $metrics = Get-EndpointExperienceMetrics -IncludePendingUpdateCount:$IncludePendingUpdateCount -LogPath $LogPath
  $score = Invoke-ExperienceScoring -Metrics $metrics -LogPath $LogPath

  if ($AsIntuneDetection) {
    if ($score.HealthState -eq 'Healthy') { exit 0 }
    if ($score.HealthState -eq 'Critical') { exit 1 }
    # Warning: not in scope for remediation trigger; treat as no-remediate.
    exit 0
  }

  $score
}

