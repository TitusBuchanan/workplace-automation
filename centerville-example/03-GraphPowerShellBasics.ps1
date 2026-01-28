<#
phase 3 - graph powershell basics (about 1-2 hours)

this one is just reps:
  - make sure the graph module is installed
  - connect with the scopes you want
  - run a couple basic queries until it feels normal

run:
  pwsh ./centerville-example/03-GraphPowerShellBasics.ps1 -Prefix "LAB" -InstallIfMissing
#>

[CmdletBinding()]
param(
  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $Prefix = 'LAB',

  [Parameter()]
  [switch] $InstallIfMissing
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Section([string] $Title) {
  Write-Host ''
  Write-Host ('=' * 70)
  Write-Host $Title
  Write-Host ('=' * 70)
}

function Write-Explain([string] $Text) { Write-Host ('EXPLAIN: ' + $Text) }
function Write-LookFor([string] $Text) { Write-Host ('LOOK FOR: ' + $Text) }

function Ensure-GraphModule {
  if (-not (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)) {
    if (-not $InstallIfMissing) {
      throw "Microsoft Graph PowerShell SDK not found. Run: Install-Module Microsoft.Graph -Scope CurrentUser (or re-run with -InstallIfMissing)"
    }
    Write-Host "Installing Microsoft.Graph (CurrentUser)..."
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
  }
}

try {
  Write-Section 'PHASE 3: Graph PowerShell basics'
  Write-Explain 'Graph PowerShell uses delegated OAuth tokens. The scopes you request are not just "strings"—they must be consented and the signed-in user must be authorized.'

  Ensure-GraphModule

  Write-Section '3A: Connect with interview-relevant scopes'
  Write-Explain 'Delegated scopes reflect the signed-in user plus granted consent. If you get errors, check consent + roles + Conditional Access.'
  Write-LookFor 'Get-MgContext shows both scopes.'

  Connect-MgGraph -Scopes @('User.Read.All','Group.ReadWrite.All') | Out-Null
  (Get-MgContext) | Select-Object TenantId,Account,AuthType,Scopes | Format-List

  Write-Section '3B: Query users and groups'
  Write-Explain 'Use OData filters for precise server-side queries. Filter is evaluated by Graph, not by your local PowerShell session.'
  Write-LookFor 'Get-MgUser returns 5 users; Get-MgGroup returns your target group (or empty if it does not exist).'

  Write-Host ''
  Write-Host 'Get-MgUser -Top 5'
  Get-MgUser -Top 5 | Select-Object Id,DisplayName,UserPrincipalName

  $groupName = "$Prefix-Group-Alpha"
  Write-Host ''
  Write-Host "Get-MgGroup -Filter ""displayName eq '$groupName'"""
  Get-MgGroup -Filter "displayName eq '$groupName'" | Select-Object Id,DisplayName

  Write-Host ''
  Write-Host 'Explain-back (60s):'
  Write-Host '  "Connect-MgGraph acquires a delegated token for the scopes I request. Then cmdlets call Graph endpoints; OData -Filter runs server-side so it is efficient and precise."'
  Write-Host ''
  Write-Host 'NEXT: Run ./entra-learning-lab/04-SimulateFailures.ps1'
}
catch {
  Write-Host ''
  Write-Host 'ERROR: Phase 3 failed.'
  throw
}

