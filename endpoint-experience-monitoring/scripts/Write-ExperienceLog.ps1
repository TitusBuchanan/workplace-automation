<#
  Write-ExperienceLog.ps1

  Lightweight JSONL logger for Intune-friendly scripts (non-interactive).
  - Default log location: C:\ProgramData\WorkplaceAutomation\EndpointExperience\Logs\experience.jsonl
  - Best-effort: logging failures should not break detection/remediation.
#>

Set-StrictMode -Version 2.0

function Write-ExperienceLog {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('INFO', 'WARN', 'ERROR')]
    [string] $Level,

    [Parameter(Mandatory = $true)]
    [string] $Message,

    [Parameter()]
    [object] $Data,

    [Parameter()]
    [string] $LogPath = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'WorkplaceAutomation\EndpointExperience\Logs\experience.jsonl' } else { Join-Path $PSScriptRoot 'experience.jsonl' })
  )

  try {
    $logDir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path -LiteralPath $logDir)) {
      New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    $entry = [ordered]@{
      timestamp = (Get-Date).ToString('o')
      level     = $Level
      message   = $Message
    }

    if ($null -ne $Data) {
      $entry.data = $Data
    }

    $json = ($entry | ConvertTo-Json -Depth 8 -Compress)
    Add-Content -LiteralPath $LogPath -Value $json -Encoding UTF8
  }
  catch {
    # Best-effort logging: do not throw from here.
  }
}

