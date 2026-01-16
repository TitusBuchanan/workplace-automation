<#
  Get-EndpointExperienceMetrics.ps1

  Collects basic endpoint health/performance signals using built-in PowerShell/CIM.
  Intended for Intune (SYSTEM, non-interactive).

  Returns a simple PowerShell object with metrics. Each section is best-effort;
  errors are captured into the returned object instead of breaking the run.
#>

param(
  [switch] $IncludePendingUpdateCount,
  [string] $LogPath = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'WorkplaceAutomation\EndpointExperience\Logs\experience.jsonl' } else { Join-Path $PSScriptRoot 'experience.jsonl' })
)

Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'Write-ExperienceLog.ps1')

function Test-PendingReboot {
  [CmdletBinding()]
  param()

  $reasons = @()

  try {
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
      $reasons += 'CBSRebootPending'
    }
  } catch {}

  try {
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
      $reasons += 'WindowsUpdateRebootRequired'
    }
  } catch {}

  try {
    $v = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    if ($null -ne $v.PendingFileRenameOperations) {
      $reasons += 'PendingFileRenameOperations'
    }
  } catch {}

  try {
    $v2 = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Updates' -Name 'UpdateExeVolatile' -ErrorAction SilentlyContinue
    if ($null -ne $v2.UpdateExeVolatile -and [int]$v2.UpdateExeVolatile -ne 0) {
      $reasons += 'UpdateExeVolatile'
    }
  } catch {}

  [pscustomobject]@{
    Pending = ($reasons.Count -gt 0)
    Reasons = $reasons
  }
}

function Get-WindowsUpdateInfo {
  [CmdletBinding()]
  param(
    [Parameter()]
    [switch] $IncludePendingUpdateCount
  )

  $info = [ordered]@{
    WuauservStatus         = $null
    WuauservStartType      = $null
    RebootPending          = $null
    RebootPendingReasons   = @()
    LastDetectSuccessTime  = $null
    LastInstallSuccessTime = $null
    PendingUpdateCount     = $null
    Errors                 = @()
  }

  try {
    $svc = Get-Service -Name 'wuauserv' -ErrorAction Stop
    $info.WuauservStatus = $svc.Status.ToString()
  } catch {
    $info.Errors += "wuauserv service: $($_.Exception.Message)"
  }

  try {
    $svcCim = Get-CimInstance -ClassName Win32_Service -Filter "Name='wuauserv'" -ErrorAction Stop
    $info.WuauservStartType = $svcCim.StartMode
  } catch {
    $info.Errors += "wuauserv start type: $($_.Exception.Message)"
  }

  try {
    $pending = Test-PendingReboot
    $info.RebootPending = [bool]$pending.Pending
    $info.RebootPendingReasons = @($pending.Reasons)
  } catch {
    $info.Errors += "pending reboot: $($_.Exception.Message)"
  }

  try {
    $detect = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect' -ErrorAction Stop
    if ($detect.LastSuccessTime) { $info.LastDetectSuccessTime = [datetime]$detect.LastSuccessTime }
  } catch {}

  try {
    $install = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install' -ErrorAction Stop
    if ($install.LastSuccessTime) { $info.LastInstallSuccessTime = [datetime]$install.LastSuccessTime }
  } catch {}

  if ($IncludePendingUpdateCount) {
    try {
      # Best-effort: can be slow or blocked by policy.
      $session = New-Object -ComObject 'Microsoft.Update.Session'
      $searcher = $session.CreateUpdateSearcher()
      $result = $searcher.Search("IsInstalled=0 and Type='Software'")
      $info.PendingUpdateCount = [int]$result.Updates.Count
    } catch {
      $info.Errors += "pending update count: $($_.Exception.Message)"
    }
  }

  [pscustomobject]$info
}

function Get-TeamsProcessInfo {
  [CmdletBinding()]
  param()

  $names = @('Teams', 'ms-teams', 'MSTeams', 'Teams2')
  $procs = @()
  foreach ($n in $names) {
    try {
      $procs += Get-Process -Name $n -ErrorAction SilentlyContinue
    } catch {}
  }

  $unique = @($procs | Sort-Object -Property Id -Unique)

  [pscustomobject]@{
    IsRunning     = ($unique.Count -gt 0)
    ProcessCount  = $unique.Count
    ProcessNames  = @($unique | Select-Object -ExpandProperty ProcessName -Unique)
    ExampleCpuSec = ($unique | Select-Object -First 1 -ExpandProperty CPU -ErrorAction SilentlyContinue)
  }
}

function Get-EndpointExperienceMetrics {
  [CmdletBinding()]
  param(
    [Parameter()]
    [switch] $IncludePendingUpdateCount,

    [Parameter()]
    [string] $LogPath = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'WorkplaceAutomation\EndpointExperience\Logs\experience.jsonl' } else { Join-Path $PSScriptRoot 'experience.jsonl' })
  )

  $errors = @()

  $metrics = [ordered]@{
    CollectedAt       = (Get-Date)
    ComputerName      = $env:COMPUTERNAME
    LastBootTime      = $null
    UptimeDays        = $null
    CpuLoadPercent    = $null
    MemoryUsedPercent = $null
    MemoryTotalGB     = $null
    MemoryFreeGB      = $null
    SystemDrive       = $env:SystemDrive
    SystemDriveFreeGB = $null
    SystemDriveFreePct= $null
    FixedDisks        = @()
    WindowsUpdate     = $null
    Teams             = $null
    Errors            = $errors
  }

  try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $boot = $os.LastBootUpTime
    $metrics.LastBootTime = $boot
    $metrics.UptimeDays = [math]::Round(((Get-Date) - $boot).TotalDays, 2)

    $totalKb = [double]$os.TotalVisibleMemorySize
    $freeKb = [double]$os.FreePhysicalMemory
    if ($totalKb -gt 0) {
      $usedPct = (($totalKb - $freeKb) / $totalKb) * 100
      $metrics.MemoryUsedPercent = [math]::Round($usedPct, 1)
      $metrics.MemoryTotalGB = [math]::Round(($totalKb / 1MB), 2) # KB -> GB
      $metrics.MemoryFreeGB = [math]::Round(($freeKb / 1MB), 2)
    }
  } catch {
    $errors += "OS/memory/boot: $($_.Exception.Message)"
  }

  try {
    $cpus = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
    $loads = @($cpus | Where-Object { $null -ne $_.LoadPercentage } | Select-Object -ExpandProperty LoadPercentage)
    if ($loads.Count -gt 0) {
      $metrics.CpuLoadPercent = [int][math]::Round(($loads | Measure-Object -Average).Average, 0)
    }
  } catch {
    $errors += "CPU: $($_.Exception.Message)"
  }

  try {
    $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
    foreach ($d in $disks) {
      $size = [double]$d.Size
      $free = [double]$d.FreeSpace
      $freePct = $null
      if ($size -gt 0) { $freePct = [math]::Round(($free / $size) * 100, 1) }

      $diskObj = [pscustomobject]@{
        DriveLetter   = $d.DeviceID
        VolumeName    = $d.VolumeName
        SizeGB        = if ($size -gt 0) { [math]::Round(($size / 1GB), 2) } else { $null }
        FreeGB        = if ($free -ge 0) { [math]::Round(($free / 1GB), 2) } else { $null }
        FreePercent   = $freePct
      }
      $metrics.FixedDisks += $diskObj

      if ($d.DeviceID -eq $metrics.SystemDrive) {
        $metrics.SystemDriveFreeGB = $diskObj.FreeGB
        $metrics.SystemDriveFreePct = $diskObj.FreePercent
      }
    }
  } catch {
    $errors += "Disk: $($_.Exception.Message)"
  }

  try {
    $metrics.WindowsUpdate = Get-WindowsUpdateInfo -IncludePendingUpdateCount:$IncludePendingUpdateCount
  } catch {
    $errors += "Windows Update: $($_.Exception.Message)"
  }

  try {
    $metrics.Teams = Get-TeamsProcessInfo
  } catch {
    $errors += "Teams: $($_.Exception.Message)"
  }

  try {
    Write-ExperienceLog -Level INFO -Message 'Collected endpoint experience metrics.' -Data @{
      ComputerName = $metrics.ComputerName
      UptimeDays   = $metrics.UptimeDays
      CpuLoadPct   = $metrics.CpuLoadPercent
      MemUsedPct   = $metrics.MemoryUsedPercent
      SysDriveFree = $metrics.SystemDriveFreePct
    } -LogPath $LogPath
  } catch {}

  [pscustomobject]$metrics
}

# If executed directly, output metrics to stdout (useful for local testing/logging).
if ($MyInvocation.InvocationName -ne '.') {
  Get-EndpointExperienceMetrics -IncludePendingUpdateCount:$IncludePendingUpdateCount -LogPath $LogPath
}

