<#
phase 6 - quick review (optional)

this is the quick "muscle memory" lap:
  - connect
  - run 2 quick queries
  - run device code once and hit /me

run:
  pwsh ./centerville-example/extras/06-QuickReview.ps1 -TenantId "contoso.onmicrosoft.com" -ClientId "<clientId>" -Prefix "LAB"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string] $TenantId,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string] $ClientId,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $Prefix = 'LAB'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Section([string] $Title) {
  Write-Host ''
  Write-Host ('=' * 70)
  Write-Host $Title
  Write-Host ('=' * 70)
}

try {
  Write-Section 'PHASE 6: Quick review (muscle memory)'

  Write-Host '1) Connect-MgGraph -Scopes "User.Read.All","Group.ReadWrite.All"'
  Connect-MgGraph -Scopes @('User.Read.All','Group.ReadWrite.All') | Out-Null
  (Get-MgContext) | Select-Object TenantId,Account,Scopes | Format-List

  Write-Host ''
  Write-Host '2) Get-MgUser -Top 5'
  Get-MgUser -Top 5 | Select-Object DisplayName,UserPrincipalName

  $groupName = "$Prefix-Group-Alpha"
  Write-Host ''
  Write-Host "3) Get-MgGroup -Filter ""displayName eq '$groupName'"""
  Get-MgGroup -Filter "displayName eq '$groupName'" | Select-Object Id,DisplayName

  Write-Host ''
  Write-Host '4) Device code flow + GET /me'
  pwsh ./centerville-example/02-DeviceCodeAndGraph.ps1 -TenantId $TenantId -ClientId $ClientId -CallGraph

  Write-Host ''
  Write-Host 'Explain-back (60s):'
  Write-Host '  "Problem → mechanism → how I debug."'
}
catch {
  Write-Host ''
  Write-Host 'ERROR: Phase 6 failed.'
  throw
}

