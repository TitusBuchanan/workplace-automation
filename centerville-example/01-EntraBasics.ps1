<#
phase 1 - entra basics (about 1-2 hours)

this is the "make the objects" phase. you're basically getting used to:
  - users
  - groups
  - group membership
  - app registrations (client ids)

what this script does:
  - makes sure 2 groups exist (alpha + beta)
  - makes sure N lab users exist (N = UserCount)
  - adds 1-4 selected users to the target group (alpha by default)
  - makes sure an app registration exists for device code in phase 2

note:
  - if your shell can't see the helper scripts, it will just call graph directly
  - you can re-run it. it won't try to make duplicates on purpose.
#>

[CmdletBinding()]
param(
  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $TenantDomain,

  # optional: prompt for inputs + ask "are you sure?" before changes
  [Parameter()]
  [switch] $Interactive,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $Prefix = 'LAB',

  # how many lab users you want to exist (created if missing)
  # naming: "<prefixLower>.userN@<TenantDomain>" for N=1..UserCount
  [Parameter()]
  [ValidateRange(1, 50)]
  [int] $UserCount = 1,

  # convenience for 1 user: which user number to add (if you don't pass -MemberUpn)
  [Parameter()]
  [ValidateRange(1, 50)]
  [int] $MemberUserNumber = 1,

  # add 1-4 users at a time by number (if you don't pass -MemberUpn)
  [Parameter()]
  [ValidateRange(1, 50)]
  [int[]] $MemberUserNumbers,

  # which group we are adding people into
  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $TargetGroupDisplayName = "$Prefix-Group-Alpha",

  # optional: add a specific upn (not tied to lab.userN naming)
  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $MemberUpn,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $AppDisplayName = "$Prefix-GraphClient"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Prompt-Default([string] $Label, [string] $DefaultValue) {
  $resp = Read-Host "$Label [$DefaultValue]"
  if ([string]::IsNullOrWhiteSpace($resp)) { return $DefaultValue }
  return $resp
}

function Prompt-Int([string] $Label, [int] $DefaultValue, [int] $Min, [int] $Max) {
  while ($true) {
    $resp = Read-Host "$Label [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $DefaultValue }
    $n = 0
    if ([int]::TryParse($resp, [ref]$n) -and $n -ge $Min -and $n -le $Max) { return $n }
    Write-Host "Enter a number between $Min and $Max."
  }
}

function Prompt-YesNo([string] $Question, [bool] $DefaultYes = $true) {
  $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
  while ($true) {
    $resp = Read-Host "$Question $suffix"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $DefaultYes }
    switch ($resp.Trim().ToLowerInvariant()) {
      'y' { return $true }
      'yes' { return $true }
      'n' { return $false }
      'no' { return $false }
      default { Write-Host 'Please enter Y or N.' }
    }
  }
}

function Parse-UserNumberList([string] $Text) {
  # Accepts: "1", "1,2,3", "1 2 3", "1, 2, 3"
  $clean = ($Text -replace '[,]', ' ')
  $parts = $clean.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
  $nums = @()
  foreach ($p in $parts) {
    $n = 0
    if (-not [int]::TryParse($p, [ref]$n)) { throw "Invalid number: $p" }
    $nums += $n
  }
  return $nums
}

function Write-Section([string] $Title) {
  Write-Host ''
  Write-Host ('=' * 70)
  Write-Host $Title
  Write-Host ('=' * 70)
}

function Write-Explain([string] $Text) { Write-Host ('EXPLAIN: ' + $Text) }
function Write-LookFor([string] $Text) { Write-Host ('LOOK FOR: ' + $Text) }

function Get-RepoRoot {
  # Keep this simple and stable: repo root is the parent of entra-learning-lab.
  return (Split-Path -Parent $PSScriptRoot)
}

function Assert-GraphSdk {
  if (-not (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)) {
    throw "Microsoft Graph PowerShell SDK not found. Run Phase 0 first: ./entra-learning-lab/00-BaselineSetup.ps1 -InstallIfMissing"
  }
}

function Ensure-Connected([string[]] $Scopes) {
  $ctx = $null
  try { $ctx = Get-MgContext } catch {}

  $need = ($null -eq $ctx)
  if (-not $need -and $ctx.Scopes) {
    foreach ($s in $Scopes) {
      if ($ctx.Scopes -notcontains $s) { $need = $true; break }
    }
  }
  if ($need) {
    Connect-MgGraph -Scopes $Scopes | Out-Null
  }
}

function Convert-ToMailNickname([string] $DisplayName) {
  $nick = ($DisplayName -replace '[^A-Za-z0-9]', '')
  if ([string]::IsNullOrWhiteSpace($nick)) { $nick = 'LabNick' }
  if ($nick.Length -gt 60) { $nick = $nick.Substring(0, 60) }
  return $nick
}

function New-RandomPassword {
  [CmdletBinding()]
  param(
    [Parameter()]
    [ValidateRange(12, 128)]
    [int] $Length = 20
  )

  $lower = 'abcdefghijkmnopqrstuvwxyz'
  $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
  $digits = '23456789'
  $special = '!@$%*-_+='
  $all = ($lower + $upper + $digits + $special).ToCharArray()

  $rand = New-Object System.Random
  $chars = New-Object System.Collections.Generic.List[char]

  $chars.Add($lower[$rand.Next(0, $lower.Length)])
  $chars.Add($upper[$rand.Next(0, $upper.Length)])
  $chars.Add($digits[$rand.Next(0, $digits.Length)])
  $chars.Add($special[$rand.Next(0, $special.Length)])

  for ($i = $chars.Count; $i -lt $Length; $i++) {
    $chars.Add($all[$rand.Next(0, $all.Length)])
  }

  $shuffled = $chars | Sort-Object { $rand.Next() }
  return -join $shuffled
}

function Ensure-Group([string] $DisplayName) {
  $existing = Get-GroupByDisplayName -DisplayName $DisplayName
  if ($null -ne $existing) { return $existing }

  $body = @{
    displayName     = $DisplayName
    mailEnabled     = $false
    mailNickname    = (Convert-ToMailNickname -DisplayName $DisplayName)
    securityEnabled = $true
    groupTypes      = @()
  } | ConvertTo-Json -Depth 6

  return (Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/groups' -Body $body)
}

function Ensure-User([string] $Upn, [string] $DisplayName, [string] $Password, [string] $UsageLocation = 'US') {
  $existing = Get-UserByUpn -Upn $Upn
  if ($null -ne $existing) { return $existing }

  $mailNick = ($Upn.Split('@')[0] -replace '[^A-Za-z0-9]', '')
  if ([string]::IsNullOrWhiteSpace($mailNick)) { $mailNick = 'labuser' }

  $body = @{
    accountEnabled    = $true
    displayName       = $DisplayName
    mailNickname      = $mailNick
    userPrincipalName = $Upn
    usageLocation     = $UsageLocation
    passwordProfile   = @{
      password = $Password
      forceChangePasswordNextSignIn = $true
    }
  } | ConvertTo-Json -Depth 8

  return (Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/users' -Body $body)
}

function Ensure-LabUsers {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string] $TenantDomain,

    [Parameter(Mandatory = $true)]
    [string] $Prefix,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 50)]
    [int] $UserCount,

    [Parameter()]
    [string] $UsageLocation = 'US'
  )

  $prefixLower = $Prefix.ToLowerInvariant()

  $createdCreds = @()
  $ensured = @()

  for ($i = 1; $i -le $UserCount; $i++) {
    $upn = "$prefixLower.user$i@$TenantDomain"
    $displayName = "$Prefix-User-User$i"

    $existing = Get-UserByUpn -Upn $upn
    if ($null -ne $existing) {
      $ensured += [pscustomobject]@{ Upn = $upn; Id = $existing.id; Created = $false }
      continue
    }

    $tempPassword = New-RandomPassword
    $u = Ensure-User -Upn $upn -DisplayName $displayName -Password $tempPassword -UsageLocation $UsageLocation
    $ensured += [pscustomobject]@{ Upn = $upn; Id = $u.id; Created = $true }
    $createdCreds += [pscustomobject]@{ Upn = $upn; Password = $tempPassword; Id = $u.id }
  }

  return [pscustomobject]@{
    EnsuredUsers = $ensured
    CreatedCredentials = $createdCreds
  }
}

function Ensure-AppRegistration([string] $DisplayName) {
  $filter = "displayName eq '$DisplayName'"
  $uri = "https://graph.microsoft.com/v1.0/applications?`$filter=$([uri]::EscapeDataString($filter))&`$select=id,appId,displayName,isFallbackPublicClient,signInAudience"
  $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
  $existing = @($resp.value) | Select-Object -First 1
  if ($null -ne $existing) { return $existing }

  $body = @{
    displayName = $DisplayName
    signInAudience = 'AzureADMyOrg'
    isFallbackPublicClient = $true
    api = @{ requestedAccessTokenVersion = 2 }
  } | ConvertTo-Json -Depth 8

  return (Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/applications' -Body $body)
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

function Add-UserToGroup([string] $UserId, [string] $GroupId) {
  # Same underlying Graph relationship used in the plan:
  # POST /groups/{id}/members/$ref with an @odata.id directoryObject reference.
  $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/members/`$ref"
  $body = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$UserId" } | ConvertTo-Json -Depth 4

  try {
    Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body | Out-Null
    return $true
  } catch {
    # If already a member, Graph commonly returns 400 “one or more added object references already exist”.
    Write-Host ("NOTE: membership add returned an error (often harmless if already a member): " + $_.Exception.Message)
    return $false
  }
}

try {
  if ($Interactive) {
    Write-Section 'INTERACTIVE MODE'
    Write-Explain 'This mode prompts for inputs and confirms before tenant changes.'

    if (-not $TenantDomain) {
      $TenantDomain = Prompt-Default -Label 'Tenant domain (e.g. Resumellc337.onmicrosoft.com)' -DefaultValue 'Resumellc337.onmicrosoft.com'
    }

    $Prefix = Prompt-Default -Label 'Prefix (naming for lab objects)' -DefaultValue $Prefix
    $UserCount = Prompt-Int -Label 'How many lab users to ensure exist?' -DefaultValue $UserCount -Min 1 -Max 50
    $respNums = Read-Host "Which user number(s) should be added to the group now? (1-4 numbers, e.g. 1 or 1,2,3) [$MemberUserNumber]"
    if ([string]::IsNullOrWhiteSpace($respNums)) {
      $MemberUserNumbers = @($MemberUserNumber)
    } else {
      $MemberUserNumbers = Parse-UserNumberList -Text $respNums
    }

    if ($MemberUserNumbers.Count -lt 1 -or $MemberUserNumbers.Count -gt 4) {
      throw "Please choose between 1 and 4 user numbers."
    }
    foreach ($n in $MemberUserNumbers) {
      if ($n -lt 1 -or $n -gt $UserCount) { throw "User number $n is out of range (1..$UserCount)." }
    }

    # If the user did not explicitly pass these, recompute based on Prefix.
    if (-not $PSBoundParameters.ContainsKey('TargetGroupDisplayName')) {
      $TargetGroupDisplayName = "$Prefix-Group-Alpha"
    }
    if (-not $PSBoundParameters.ContainsKey('AppDisplayName')) {
      $AppDisplayName = "$Prefix-GraphClient"
    }

    $TargetGroupDisplayName = Prompt-Default -Label 'Target group displayName' -DefaultValue $TargetGroupDisplayName
    $AppDisplayName = Prompt-Default -Label 'App registration displayName' -DefaultValue $AppDisplayName

    Write-Host ''
    Write-Host 'About to run Phase 1 with:'
    [pscustomobject]@{
      TenantDomain = $TenantDomain
      Prefix = $Prefix
      UserCount = $UserCount
      MemberUserNumbers = ($MemberUserNumbers -join ',')
      TargetGroupDisplayName = $TargetGroupDisplayName
      AppDisplayName = $AppDisplayName
    } | Format-List

    if (-not (Prompt-YesNo -Question 'Proceed with these changes?' -DefaultYes $true)) {
      Write-Host 'Cancelled.'
      return
    }
  }

  # Normalize MemberUserNumbers:
  if (-not $MemberUserNumbers -or $MemberUserNumbers.Count -eq 0) {
    $MemberUserNumbers = @($MemberUserNumber)
  }
  if ($MemberUserNumbers.Count -lt 1 -or $MemberUserNumbers.Count -gt 4) {
    throw "MemberUserNumbers must contain between 1 and 4 values."
  }
  foreach ($n in $MemberUserNumbers) {
    if ($n -lt 1 -or $n -gt 50) { throw "Invalid MemberUserNumbers value: $n" }
    if (-not $MemberUpn -and $n -gt $UserCount) {
      throw "MemberUserNumbers contains $n which is greater than UserCount ($UserCount). Increase -UserCount or pass -MemberUpn explicitly."
    }
  }

  # If MemberUpn isn't provided, compute a default list of UPNs from the chosen user numbers.
  $memberUpns = @()
  if ($MemberUpn) {
    $memberUpns = @($MemberUpn)
  } else {
    foreach ($n in $MemberUserNumbers) {
      $memberUpns += "$($Prefix.ToLowerInvariant()).user$n@$TenantDomain"
    }
  }

  Assert-GraphSdk

  Write-Section 'PHASE 1: Entra basics'
  Write-Explain 'We will create users/groups (directory objects), then use group membership as a stable target for access decisions and policies.'

  $root = Get-RepoRoot
  Push-Location -LiteralPath $root
  try {
    # Use repo-relative paths (more reliable across shells/environments).
    $groupsScript = Join-Path '.' 'zero-trust-dw-lab/scripts/phase1/New-ZtdwGroups.ps1'
    $usersScript  = Join-Path '.' 'zero-trust-dw-lab/scripts/phase1/New-ZtdwTestUsers.ps1'
    $appScript    = Join-Path '.' 'zero-trust-dw-lab/scripts/phase1/New-ZtdwTestApp.ps1'

    $useHelpers = $true
    foreach ($p in @($groupsScript, $usersScript, $appScript)) {
      $rp = Resolve-Path -Path $p -ErrorAction SilentlyContinue
      if ($null -eq $rp) { $useHelpers = $false; break }
    }

    Write-Section '1A: Create two groups'
    Write-Explain 'Groups are stable policy targets; you change membership instead of rewriting policies.'
    Write-LookFor 'Two groups returned with displayName + id.'
    if ($useHelpers) {
      & $groupsScript -Prefix $Prefix -GroupNames @('Group-Alpha','Group-Beta')
    } else {
      Write-Host "NOTE: Helper scripts not accessible; creating groups directly via Graph..."
      Ensure-Connected -Scopes @('Group.ReadWrite.All')
      (Ensure-Group -DisplayName "$Prefix-Group-Alpha") | Select-Object id,displayName
      (Ensure-Group -DisplayName "$Prefix-Group-Beta")  | Select-Object id,displayName
    }

    Write-Section '1B: Create test users'
    Write-Explain 'Users are directory objects; creating them requires write permission and (usually) admin role.'
    Write-LookFor 'Users created OR an idempotent skip if they already exist.'
    if ($useHelpers) {
      & $usersScript -TenantDomain $TenantDomain -Prefix $Prefix -AddToGroups:$false -ShowGeneratedPasswords
    } else {
      Write-Host "NOTE: Helper scripts not accessible; creating $UserCount users directly via Graph..."
      Ensure-Connected -Scopes @('User.ReadWrite.All')

      $result = Ensure-LabUsers -TenantDomain $TenantDomain -Prefix $Prefix -UserCount $UserCount

      Write-Host ''
      Write-Host "Ensured users ($UserCount total):"
      $result.EnsuredUsers | Format-Table -AutoSize

      if ($result.CreatedCredentials.Count -gt 0) {
        Write-Host ''
        Write-Host 'Generated lab passwords (ONLY for newly created users; store securely):'
        $result.CreatedCredentials | Format-Table -AutoSize
      } else {
        Write-Host ''
        Write-Host 'No new users were created, so no passwords were generated.'
      }

      if (-not $PSBoundParameters.ContainsKey('MemberUpn')) {
        # Use the first selected user number as the default single-member UPN for the membership step.
        $MemberUpn = "$($Prefix.ToLowerInvariant()).user$($MemberUserNumbers[0])@$TenantDomain"
      }
    }

    Write-Section '1C: Add user to group'
    Write-Explain "Group membership writes are a POST to the group's members/`$ref relationship in Microsoft Graph."
    Write-LookFor 'The add call succeeds, then you can verify membership in the portal or with Graph.'

    Ensure-Connected -Scopes @('Group.ReadWrite.All','User.Read.All')

    $g = Get-GroupByDisplayName -DisplayName $TargetGroupDisplayName
    if ($null -eq $g) { throw "Target group not found: $TargetGroupDisplayName" }

    foreach ($upn in $memberUpns) {
      $u = Get-UserByUpn -Upn $upn
      if ($null -eq $u) { throw "Target user not found: $upn" }

      Write-Host "Adding user '$($u.userPrincipalName)' to group '$($g.displayName)'..."
      Add-UserToGroup -UserId $u.id -GroupId $g.id | Out-Null
    }

    Write-Host ''
    Write-Host 'Verify (example):'
    Write-Host "  Get-MgGroupMember -GroupId $($g.id) -All | Select-Object Id"

    Write-Section '1D: Create a simple App Registration'
    Write-Explain 'App registration defines an application identity. The clientId is used by OAuth flows (like device code) to request tokens.'
    Write-LookFor 'App output includes appId (clientId); public client is enabled via isFallbackPublicClient when possible.'
    if ($useHelpers) {
      & $appScript -DisplayName $AppDisplayName
    } else {
      Write-Host "NOTE: Helper scripts not accessible; creating app registration directly via Graph..."
      Ensure-Connected -Scopes @('Application.ReadWrite.All')
      $app = Ensure-AppRegistration -DisplayName $AppDisplayName
      $app | Select-Object displayName,appId,id,isFallbackPublicClient,signInAudience | Format-List
    }
  }
  finally {
    Pop-Location
  }

  Write-Host ''
  Write-Host 'NEXT: Run ./entra-learning-lab/02-DeviceCodeAndGraph.ps1 (use the clientId/appId from above).'
}
catch {
  Write-Host ''
  Write-Host 'ERROR: Phase 1 failed.'
  throw
}

