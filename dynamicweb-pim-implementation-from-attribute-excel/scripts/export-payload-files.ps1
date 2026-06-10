param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true)]
    [string]$ShopName,

    [string[]]$OmitGroupIds = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonScript = Join-Path $scriptDir "export_payload_files.py"

$arguments = @(
    $pythonScript,
    "--path", $Path,
    "--output-dir", $OutputDir,
    "--shop-name", $ShopName
)

foreach ($groupId in $OmitGroupIds) {
    $arguments += @("--omit-group-id", $groupId)
}

& python @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Python payload export failed with exit code $LASTEXITCODE."
}
