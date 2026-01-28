<#
phase 2 - device code + first graph call (about 1-2 hours)

this is the "what connect-mggraph is doing behind the scenes" part:
  - call /devicecode
  - keep polling /token until you finish signing in
  - look at token_type / expires_in / scope
  - use that token to call graph (GET /me)

run:
  pwsh ./centerville-example/02-DeviceCodeAndGraph.ps1 -TenantId "contoso.onmicrosoft.com" -ClientId "<clientId>" -CallGraph
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
  [string[]] $Scopes = @('User.Read'),

  [Parameter()]
  [switch] $CallGraph,

  # turn this on if you *want* it to fail (so you can see a real auth error)
  [Parameter()]
  [switch] $SimulateFailure
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

function Invoke-DeviceCode {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string] $TenantId,
    [Parameter(Mandatory = $true)]
    [string] $ClientId,
    [Parameter(Mandatory = $true)]
    [string] $Scope
  )

  $deviceCodeUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode"
  return Invoke-RestMethod -Method POST -Uri $deviceCodeUri -ContentType 'application/x-www-form-urlencoded' -Body @{
    client_id = $ClientId
    scope     = $Scope
  }
}

function Invoke-TokenPoll {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string] $TenantId,
    [Parameter(Mandatory = $true)]
    [string] $ClientId,
    [Parameter(Mandatory = $true)]
    [string] $DeviceCode,
    [Parameter()]
    [int] $PollIntervalSeconds = 5,
    [Parameter()]
    [int] $TimeoutSeconds = 600
  )

  $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

  while ((Get-Date) -lt $deadline) {
    try {
      return Invoke-RestMethod -Method POST -Uri $tokenUri -ContentType 'application/x-www-form-urlencoded' -Body @{
        grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
        client_id   = $ClientId
        device_code = $DeviceCode
      }
    }
    catch {
      # powershell throws different exception shapes depending on version.
      # all we really want is the json body so we can read "authorization_pending".
      $body = $null
      $resp = $null

      # sometimes the json is already right here (common on ps7)
      try {
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
          $body = $_.ErrorDetails.Message
        }
      } catch {}

      try { $resp = $_.Exception.Response } catch {}
      if ($null -ne $resp) {
        # httpresponsemessage path (ps7)
        try {
          if ($resp.Content) {
            $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
          }
        } catch {}

        # webresponse path (older powershell)
        if (-not $body) {
          try {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $body = $reader.ReadToEnd()
          } catch {}
        }
      }

      # last resort: sometimes the exception message contains the json already
      if (-not $body) {
        try { $body = $_.Exception.Message } catch {}
      }

      if (-not $body) { throw }

      $err = $body | ConvertFrom-Json -ErrorAction Stop

      if ($err.error -eq 'authorization_pending') {
        Start-Sleep -Seconds $PollIntervalSeconds
        continue
      }
      if ($err.error -eq 'slow_down') {
        Start-Sleep -Seconds ($PollIntervalSeconds + 5)
        continue
      }

      throw "Token polling failed: $($err.error) - $($err.error_description)"
    }
  }

  throw "Timed out waiting for device code authentication after $TimeoutSeconds seconds."
}

try {
  Write-Section 'PHASE 2: Device code auth & Graph'
  Write-Explain 'Device code flow is used when the device/app cannot easily host a browser. The app polls the token endpoint until the user completes sign-in elsewhere.'
  Write-LookFor 'You will see token_type, expires_in, scope (but not the raw token), then optionally a successful GET /me.'

  $requestedScopes =
    if ($SimulateFailure) { @('NotAReal.Scope') }
    else { $Scopes }

  # v2 scopes are space-delimited. We also request openid/profile/offline_access for realism.
  $scopeString = (@('openid', 'profile', 'offline_access') + $requestedScopes) -join ' '

  $dc = Invoke-DeviceCode -TenantId $TenantId -ClientId $ClientId -Scope $scopeString

  Write-Host ''
  Write-Host '=== DEVICE CODE SIGN-IN ==='
  Write-Host $dc.message
  Write-Host ''

  $tok = Invoke-TokenPoll -TenantId $TenantId -ClientId $ClientId -DeviceCode $dc.device_code

  # DO NOT print the token itself by default; print metadata you can use to reason about failures.
  [pscustomobject]@{
    token_type  = $tok.token_type
    expires_in  = $tok.expires_in
    scope       = $tok.scope
  }

  if ($CallGraph) {
    $headers = @{ Authorization = "Bearer $($tok.access_token)" }
    $me = Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=displayName,userPrincipalName,id' -Headers $headers

    Write-Host ''
    Write-Host '=== GRAPH /me ==='
    $me | Select-Object displayName,userPrincipalName,id
  }

  Write-Host ''
  Write-Host 'Explain-back (60s):'
  Write-Host '  "The device gets a device_code and user_code from /devicecode, the user signs in on another device, then the app polls /token until it receives a Bearer access token for the requested scopes."'
  Write-Host ''
  Write-Host 'NEXT: Run ./entra-learning-lab/03-GraphPowerShellBasics.ps1'
}
catch {
  Write-Host ''
  Write-Host 'ERROR: Phase 2 failed.'
  throw
}

