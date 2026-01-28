<#
phase 4 - simulate failures (about 60-90 min)

this is the "break it on purpose" phase.
the goal is to get used to what failures look like for real:
  - 403 when you don't have the right scopes/permissions
  - (optional) conditional access blocking sign-in

run:
  pwsh ./centerville-example/04-SimulateFailures.ps1 -TenantDomain "contoso.onmicrosoft.com" -Prefix "LAB"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string] $TenantDomain,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $Prefix = 'LAB',

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $TargetGroupDisplayName = "$Prefix-Group-Alpha",

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $MemberUpn,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $CaPolicyName = "$Prefix-CA-RequireCompliantDevice",

  # set this if you want the script to actually create a CA policy (graph beta)
  [Parameter()]
  [switch] $CreateConditionalAccessPolicy
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

function Ensure-GraphSdk {
  if (-not (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)) {
    throw "Microsoft Graph PowerShell SDK not found. Run Phase 0 first: ./entra-learning-lab/00-BaselineSetup.ps1 -InstallIfMissing"
  }
}

function Get-GroupByDisplayName([string] $DisplayName) {
  $filter = "displayName eq '$DisplayName'"
  $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=$([uri]::EscapeDataString($filter))&`$select=id,displayName"
  $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
  return @($resp.value) | Select-Object -First 1
}

function Get-UserByUpn([string] $Upn) {
  $filter = "userPrincipalName eq '$Upn'"
  $uri = "https://graph.microsoft.com/v1.0/users?`$filter=$([uri]::EscapeDataString($filter))&`$select=id,displayName,userPrincipalName"
  $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
  return @($resp.value) | Select-Object -First 1
}

function Try-AddUserToGroup([string] $UserId, [string] $GroupId) {
  $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/members/`$ref"
  $body = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$UserId" } | ConvertTo-Json -Depth 4
  Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body | Out-Null
}

try {
  if (-not $MemberUpn) {
    $MemberUpn = "ztdw.helpdesk@$TenantDomain"
  }

  Ensure-GraphSdk

  Write-Section 'PHASE 4: Simulate failures'
  Write-Explain 'This phase teaches what failures look like and how to reason about them with evidence.'

  Write-Section '4A: Missing scope → observe a 403'
  Write-Explain '401 = token missing/invalid. 403 = token valid, but not authorized (missing scopes/roles or blocked by policy).'
  Write-LookFor 'A 403 / insufficient privileges when attempting a write with only read scopes.'

  # we intentionally omit Group.ReadWrite.All so the write should fail
  Connect-MgGraph -Scopes @('User.Read.All') | Out-Null

  $g = Get-GroupByDisplayName -DisplayName $TargetGroupDisplayName
  if ($null -eq $g) { throw "Target group not found: $TargetGroupDisplayName" }

  $u = Get-UserByUpn -Upn $MemberUpn
  if ($null -eq $u) { throw "Target user not found: $MemberUpn" }

  Write-Host "Attempting to add '$($u.userPrincipalName)' to '$($g.displayName)' with ONLY User.Read.All..."
  try {
    Try-AddUserToGroup -UserId $u.id -GroupId $g.id
    Write-Host 'Unexpected: write succeeded. (If you are already connected with higher scopes, run Disconnect-MgGraph and retry.)'
  }
  catch {
    Write-Host ''
    Write-Host 'EXPECTED FAILURE (capture this for interview debugging):'
    Write-Host $_.Exception.Message
  }

  Write-Host ''
  Write-Host 'Explain-back (60s):'
  Write-Host '  "A 403 means auth succeeded but authorization failed—either missing delegated scopes, missing directory role, or blocked by Conditional Access."'

  Write-Section '4B: Conditional Access (require compliant device)'
  Write-Explain 'Conditional Access is enforced at sign-in/token issuance. A compliant-device requirement can block tokens from unmanaged devices.'
  Write-LookFor 'Policy object exists and targets your test group. If you cannot test device compliance, treat this as a simulation and explain expected behavior.'

  if ($CreateConditionalAccessPolicy) {
    Write-Host ''
    Write-Host 'Switching to Graph beta profile for Conditional Access policy CRUD...'
    Select-MgProfile -Name beta

    # CA policy CRUD needs its own permission
    Connect-MgGraph -Scopes @('Policy.ReadWrite.ConditionalAccess') | Out-Null

    $targetGroupId = $g.id

    $policyBody = @{
      displayName = $CaPolicyName
      state = 'enabled'
      conditions = @{
        users = @{
          includeGroups = @($targetGroupId)
        }
        applications = @{
          includeApplications = @('All')
        }
      }
      grantControls = @{
        operator = 'AND'
        builtInControls = @('compliantDevice')
      }
    }

    Write-Host "Creating Conditional Access policy: $CaPolicyName"
    $created = New-MgIdentityConditionalAccessPolicy -BodyParameter $policyBody
    $created | Select-Object Id,DisplayName,State | Format-List

    Write-Host ''
    Write-Host 'Test idea (simulate if needed):'
    Write-Host '  - Put a test user into the targeted group'
    Write-Host '  - Attempt device code sign-in from an unmanaged device/session'
    Write-Host '  - Observe token issuance/sign-in failure; capture the error + sign-in logs'
  } else {
    Write-Host ''
    Write-Host 'Skipped CA policy creation. Re-run with -CreateConditionalAccessPolicy to actually create it.'
  }

  Write-Host ''
  Write-Host 'NEXT (optional): Run ./centerville-example/extras/05-Rehearse.ps1'
}
catch {
  Write-Host ''
  Write-Host 'ERROR: Phase 4 failed.'
  throw
}

