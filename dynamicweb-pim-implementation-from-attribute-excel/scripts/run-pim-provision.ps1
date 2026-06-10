param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true)]
    [string]$ShopName,

    [string]$ServerName = "jfa",

    [string[]]$OmitGroupIds = @(),

    [int]$CreateTimeout = 240,

    [int]$ReadTimeout = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonScript = Join-Path $scriptDir "run-pim-provision.py"

$arguments = @(
    $pythonScript,
    "--path", $Path,
    "--output-dir", $OutputDir,
    "--shop-name", $ShopName,
    "--server-name", $ServerName,
    "--create-timeout", $CreateTimeout,
    "--read-timeout", $ReadTimeout
)

foreach ($groupId in $OmitGroupIds) {
    $arguments += @("--omit-group-id", $groupId)
}

& python @arguments
if ($LASTEXITCODE -ne 0) {
    throw "PIM provisioning failed with exit code $LASTEXITCODE."
}
