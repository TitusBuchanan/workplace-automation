<#
phase 5 - explain + rehearse (optional)

this isn't code practice, it's talking practice.
use this to prep your 60-second answers and not ramble.

run:
  pwsh ./centerville-example/extras/05-Rehearse.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Section([string] $Title) {
  Write-Host ''
  Write-Host ('=' * 70)
  Write-Host $Title
  Write-Host ('=' * 70)
}

function Prompt([string] $Title, [string[]] $Bullets) {
  Write-Host ''
  Write-Host $Title
  foreach ($b in $Bullets) { Write-Host ("  - " + $b) }
}

try {
  Write-Section 'PHASE 5: Explain & rehearse'

  Prompt 'How to structure every 60-second answer (template)' @(
    'Start with the problem (what you were trying to do).'
    'Explain the mechanism (how Entra/Graph handles it).'
    'Explain evidence/debug steps (what you check when it fails).'
    'End with the outcome (what good looks like).'
  )

  Write-Section '5A: 60-second plain-English explanations (write these out)'

  Prompt 'Users & groups' @(
    'Users are directory identities; groups are stable targets for access decisions.'
    'You manage risk by changing membership rather than rewriting policies.'
    'Evidence: user object, group object, membership links (members/$ref).'
  )

  Prompt 'App registration vs enterprise app' @(
    'App registration defines the app identity (clientId/appId).'
    'Enterprise app/service principal is the tenant instance used for sign-in/assignments.'
    'Evidence: app registration object vs service principal object; clientId; permissions/consent.'
  )

  Prompt 'Device code flow' @(
    'Used when the device/app cannot host a browser.'
    'App gets a device code, user signs in elsewhere, app polls token endpoint.'
    'Evidence: token_type, expires_in, scope, and Graph error payloads if /me fails.'
  )

  Prompt 'Graph PowerShell SDK (scopes/consent)' @(
    'Connect-MgGraph requests delegated scopes; consent + roles determine what''s allowed.'
    'Use least privilege: request only what you need.'
    'Evidence: Get-MgContext scopes; Graph error status codes and messages.'
  )

  Prompt 'Failures: 401 vs 403 + Conditional Access' @(
    '401: token missing/invalid or wrong audience.'
    '403: token valid but not authorized (missing scope/role or blocked by policy).'
    'Conditional Access is enforced at sign-in/token issuance and can block tokens unless conditions are met.'
  )

  Write-Section '5B: Mock interview prompts (run 2 rounds)'
  Prompt 'Round 1 (short + factual)' @(
    'Why did I get a 403 from Graph?'
    'What''s the difference between an app registration and an enterprise app?'
    'When would you use device code flow?'
    'How do you prove what permissions your token has?'
  )

  Prompt 'Round 2 (debug-focused; add evidence you would collect)' @(
    'Show Get-MgContext scopes and explain consent.'
    'Explain expected token audience (aud) and scopes (scp).'
    'Describe what you''d check in sign-in logs for Conditional Access blocks.'
  )

  Write-Host ''
  Write-Host 'NEXT (optional): Run ./centerville-example/extras/06-QuickReview.ps1'
}
catch {
  Write-Host ''
  Write-Host 'ERROR: Phase 5 failed.'
  throw
}

