<#
phase 0 - mac setup / quick sanity check (15-20 min)

this script is just here to make sure your mac can actually talk to microsoft graph.
if later phases fail, this helps you tell the difference between:
  - "my local setup is broken"
  - "my tenant permissions / consent is the problem"

run:
  pwsh ./centerville-example/00-MacSetUpForGraph.ps1 -InstallIfMissing

what you want to see:
  - connect-mggraph works
  - get-mgcontext shows the tenant + account + scopes
#>

[CmdletBinding()]
param(
  # installs microsoft.graph for your user (only if it's missing)
  [switch] $InstallIfMissing
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# tiny helpers so the output isn't a wall of text
function Write-Section([string] $Title) {
  Write-Host ''
  Write-Host ('=' * 70)
  Write-Host $Title
  Write-Host ('=' * 70)
}

function Write-Explain([string] $Text) {
  Write-Host ('EXPLAIN: ' + $Text)
}

function Assert-GraphModule {
  if (-not (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)) {
    if (-not $InstallIfMissing) {
      throw "Microsoft Graph PowerShell SDK not found. Run: Install-Module Microsoft.Graph -Scope CurrentUser (or re-run with -InstallIfMissing)"
    }

    Write-Host "Installing Microsoft.Graph (CurrentUser)..."
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
  }
}

try {
  Write-Section 'PHASE 0: Baseline setup'
  Write-Explain "Graph PowerShell is an API client. Connect-MgGraph gets a delegated token for requested scopes; Get-MgContext shows what you actually got."

  Assert-GraphModule

  Write-Host ''
  Write-Host 'Connecting with minimal scope: User.Read'
  Connect-MgGraph -Scopes 'User.Read' | Out-Null

  Write-Host ''
  Write-Host 'Context (what you actually have):'
  $ctx = Get-MgContext
  $ctx | Select-Object TenantId,Account,ClientId,AuthType,Scopes | Format-List

  Write-Host ''
  Write-Host 'LOOK FOR: TenantId present, Account present, Scopes includes User.Read.'
  Write-Host 'NEXT: Run ./entra-learning-lab/01-EntraBasics.ps1'
}
catch {
  Write-Host ''
  Write-Host 'ERROR: Phase 0 failed.'
  throw
}

