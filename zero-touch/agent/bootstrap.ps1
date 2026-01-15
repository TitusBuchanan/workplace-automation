$ErrorActionPreference = "Stop"

$ApiBase = $env:API_BASE
if (-not $ApiBase) { $ApiBase = "https://api.localhost" }

Param(
    [Parameter(Mandatory = $false)]
    [string]$Token
)

if (-not $Token) {
    if ($env:TOKEN) { $Token = $env:TOKEN }
}

if (-not $Token) {
    Write-Host "Usage: .\bootstrap.ps1 -Token <token>"
    exit 1
}

$facts = @{
    hostname = $env:COMPUTERNAME
    os_type  = "windows"
    arch     = $env:PROCESSOR_ARCHITECTURE
    facts    = @{ ip = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1).IPV4Address.IPAddressToString }
    token    = $Token
}

$body = $facts | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "$ApiBase/enrollment/register" -Body $body -ContentType "application/json"
