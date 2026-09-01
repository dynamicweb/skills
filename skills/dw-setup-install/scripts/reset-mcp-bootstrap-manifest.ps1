<#
.SYNOPSIS
    WRITES: Files/System/mcp-bootstrap.json (a fresh one-time secret + expiry).
    Re-arms the Dynamicweb MCP bootstrap flow.

.DESCRIPTION
    Re-arms the local bootstrap flow by writing Files/System/mcp-bootstrap.json with
    a new secret and expiry time. Use this when the original installer-generated
    manifest has expired and a full re-install is not wanted.
    Owning reference: dw-setup-install/SKILL.md (Error Handling,
    "Bootstrap secret expired").

.PARAMETER FilesPath
    Path to the Dynamicweb Files folder.

.PARAMETER BootstrapSecretTtlMinutes
    Number of minutes before the bootstrap secret expires.

.EXAMPLE
    pwsh -NoProfile -File scripts/reset-mcp-bootstrap-manifest.ps1 -FilesPath "C:\DwSolutions\Swift2\Files"
#>
#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FilesPath,
    [int]$BootstrapSecretTtlMinutes = 30
)

$ErrorActionPreference = "Stop"

function New-RandomToken([int]$ByteCount = 32) {
    $bytes = New-Object byte[] $ByteCount
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        if ($rng) {
            $rng.Dispose()
        }
    }

    return [Convert]::ToBase64String($bytes).Replace('+', 'a').Replace('/', 'b').Replace('=', '')
}

$systemPath = Join-Path $FilesPath "System"
if (-not (Test-Path $systemPath)) {
    throw "Dynamicweb System folder not found at: $systemPath"
}

$manifestPath = Join-Path $systemPath "mcp-bootstrap.json"
$manifest = [ordered]@{
    secret = New-RandomToken 24
    createdUtc = [DateTime]::UtcNow.ToString("o")
    expiresUtc = [DateTime]::UtcNow.AddMinutes($BootstrapSecretTtlMinutes).ToString("o")
    source = "reset-mcp-bootstrap-manifest.ps1"
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host "MCP bootstrap manifest written" -ForegroundColor Green
Write-Host "  Path    : $manifestPath" -ForegroundColor Green
Write-Host "  Expires : $($manifest.expiresUtc)" -ForegroundColor Green
