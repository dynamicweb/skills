<#
.SYNOPSIS
    Installs the latest Swift 2 solution onto a fresh Dynamicweb 10 instance.

.DESCRIPTION
    Downloads the latest Swift 2 database, files, and demo data from the Dynamicweb
    downloads portal, imports the database, extracts files, copies the Custom.Mcp
    add-ins payload, writes the bootstrap manifest, and creates the database config.

.PARAMETER TargetServer
    SQL Server instance. Default: localhost.

.PARAMETER TargetDatabase
    Database name. Default: swift2.

.PARAMETER IntegratedSecurity
    Use Windows authentication. Default: true.

.PARAMETER SqlUser
    SQL username if not using Windows authentication.

.PARAMETER SqlPassword
    SQL password if not using Windows authentication.

.PARAMETER FilesPath
    Dynamicweb Files folder path.

.PARAMETER DownloadPath
    Temporary folder for downloads.

.PARAMETER CustomMcpAddInsSourcePath
    Local source folder for the Custom.Mcp add-ins payload copied into
    Files\System\AddIns\Installed\<package-folder>.

.PARAMETER BootstrapSecretTtlMinutes
    How long the generated bootstrap secret remains valid.

.PARAMETER SkipDownload
    Skip downloading if the packages already exist locally.
#>

[CmdletBinding()]
param(
    [string]$TargetServer = "localhost",
    [string]$TargetDatabase = "swift2",
    [bool]$IntegratedSecurity = $true,
    [string]$SqlUser = "",
    [string]$SqlPassword = "",
    [string]$FilesPath = "C:\DwSolutions\Swift2\Files",
    [string]$DownloadPath = "$env:TEMP\dw-swift-install",
    [string]$CustomMcpAddInsSourcePath = "",
    [int]$BootstrapSecretTtlMinutes = 30,
    [switch]$SkipDownload
)

$ErrorActionPreference = "Stop"

$BaseUrl = "https://doc.dynamicweb.com/Admin/Public/Download.aspx?File="
$Downloads = @{
    Database = @{
        Url = "${BaseUrl}/Files/Files/Releases/Swift/Swift-v2.2.0-demo-data/swift2.2.0-20260129-database.zip"
        FileName = "swift2-database.zip"
    }
    Files = @{
        Url = "${BaseUrl}/Files/Files/Releases/Swift/Swift-v2.2.0/Swift_v2.2.0_Files.zip"
        FileName = "swift2-files.zip"
    }
    DemoData = @{
        Url = "${BaseUrl}/Files/Files/Releases/Swift/Swift-v2.2.0-demo-data/swift-demo-data-2.2.0.zip"
        FileName = "swift2-demo-data.zip"
    }
}

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-OK([string]$Message) {
    Write-Host "    OK: $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "    WARN: $Message" -ForegroundColor Yellow
}

function Write-Fail([string]$Message) {
    Write-Host "    FAIL: $Message" -ForegroundColor Red
    exit 1
}

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

function Resolve-CustomMcpAddInsSourcePath {
    param(
        [string]$ExplicitSourcePath
    )

    if ($ExplicitSourcePath) {
        if (-not (Test-Path $ExplicitSourcePath)) {
            Write-Fail "Custom.Mcp add-ins source not found at: $ExplicitSourcePath"
        }

        return $ExplicitSourcePath
    }

    $bundledSourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) "assets\Custom.Mcp.10.0.0"
    if (Test-Path $bundledSourcePath) {
        Write-OK "Using bundled Custom.Mcp add-ins payload: $bundledSourcePath"
        return $bundledSourcePath
    }

    Write-Fail "No Custom.Mcp add-ins payload was found. Supply -CustomMcpAddInsSourcePath or restore the bundled assets folder."
}

function Install-CustomMcpAddIns {
    param(
        [string]$SourcePath,
        [string]$TargetFilesPath,
        [int]$SecretTtlMinutes
    )

    Write-Step "Installing Custom.Mcp add-ins"

    $systemPath = Join-Path $TargetFilesPath "System"
    $addInsTargetPath = Join-Path $systemPath "AddIns"
    $installedTargetPath = Join-Path $addInsTargetPath "Installed"
    $packageFolderName = Split-Path $SourcePath -Leaf
    $packageTargetPath = Join-Path $installedTargetPath $packageFolderName

    if (-not (Test-Path $installedTargetPath)) {
        New-Item -ItemType Directory -Path $installedTargetPath -Force | Out-Null
    }

    if (Test-Path $packageTargetPath) {
        Remove-Item -Path $packageTargetPath -Recurse -Force
    }

    Copy-Item -Path $SourcePath -Destination $installedTargetPath -Recurse -Force
    Write-OK "Custom.Mcp add-ins copied to $packageTargetPath"

    $manifestPath = Join-Path $systemPath "mcp-bootstrap.json"
    $manifest = [ordered]@{
        secret = New-RandomToken 24
        createdUtc = [DateTime]::UtcNow.ToString("o")
        expiresUtc = [DateTime]::UtcNow.AddMinutes($SecretTtlMinutes).ToString("o")
        source = "install-swift2.ps1"
    }

    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
    Write-OK "Bootstrap manifest written to $manifestPath"
    return $manifestPath
}

function Find-SqlPackage {
    $candidates = @(
        "sqlpackage",
        "C:\Program Files\Microsoft SQL Server\160\DAC\bin\sqlpackage.exe",
        "C:\Program Files\Microsoft SQL Server\150\DAC\bin\sqlpackage.exe",
        "C:\Program Files\Microsoft SQL Server\140\DAC\bin\sqlpackage.exe",
        "C:\Program Files (x86)\Microsoft SQL Server\160\DAC\bin\sqlpackage.exe",
        "C:\Program Files (x86)\Microsoft SQL Server\150\DAC\bin\sqlpackage.exe"
    )

    foreach ($candidate in $candidates) {
        try {
            $null = & $candidate /version 2>&1
            if ($LASTEXITCODE -eq 0) {
                return $candidate
            }
        }
        catch {
        }
    }

    try {
        $sqlPackageTool = & dotnet tool list -g 2>&1 | Select-String "microsoft.sqlpackage"
        if ($sqlPackageTool) {
            return "sqlpackage"
        }
    }
    catch {
    }

    return $null
}

function Build-ConnectionString {
    if ($IntegratedSecurity) {
        return "Server=$TargetServer;Database=$TargetDatabase;Trusted_Connection=True;TrustServerCertificate=True;"
    }

    return "Server=$TargetServer;Database=$TargetDatabase;User Id=$SqlUser;Password=$SqlPassword;TrustServerCertificate=True;"
}

function Download-File {
    param(
        [string]$Url,
        [string]$Destination
    )

    if (Test-Path $Destination) {
        Write-OK "Already downloaded: $(Split-Path $Destination -Leaf)"
        return
    }

    Write-Host "    Downloading $(Split-Path $Destination -Leaf)..." -ForegroundColor Gray
    $previousProgressPreference = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    $ProgressPreference = $previousProgressPreference
    Write-OK "Downloaded: $(Split-Path $Destination -Leaf) ($([math]::Round((Get-Item $Destination).Length / 1MB, 1)) MB)"
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  DynamicWeb Swift 2 Installer" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Server   : $TargetServer"
Write-Host "  Database : $TargetDatabase"
Write-Host "  Auth     : $(if ($IntegratedSecurity) { 'Windows' } else { "SQL ($SqlUser)" })"
Write-Host "  Files    : $FilesPath"
Write-Host ""

Write-Step "Checking prerequisites"

$sqlPackage = Find-SqlPackage
if (-not $sqlPackage) {
    $message = @(
        "",
        "sqlpackage is required but not found. Install with one of:",
        "  dotnet tool install -g microsoft.sqlpackage",
        "or:",
        "  winget install Microsoft.SqlPackage",
        "",
        "Then restart your terminal and re-run."
    ) -join "`n"

    Write-Host $message -ForegroundColor Yellow
    Write-Fail "sqlpackage not available"
}

Write-OK "sqlpackage found: $sqlPackage"

if (-not $SkipDownload) {
    Write-Step "Downloading Swift 2 packages from doc.dynamicweb.com"

    if (-not (Test-Path $DownloadPath)) {
        New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
    }

    foreach ($download in $Downloads.Values) {
        Download-File -Url $download.Url -Destination (Join-Path $DownloadPath $download.FileName)
    }
}
else {
    Write-Step "Skipping download and using existing files in $DownloadPath"
}

Write-Step "Extracting database package"

$dbZip = Join-Path $DownloadPath $Downloads.Database.FileName
if (-not (Test-Path $dbZip)) {
    Write-Fail "Database ZIP not found at: $dbZip"
}

$dbExtract = Join-Path $DownloadPath "database"
if (Test-Path $dbExtract) {
    Remove-Item $dbExtract -Recurse -Force
}

Expand-Archive -Path $dbZip -DestinationPath $dbExtract -Force

$bacpacFile = Get-ChildItem -Path $dbExtract -Filter "*.bacpac" -Recurse | Select-Object -First 1
if (-not $bacpacFile) {
    Write-Fail "No .bacpac file found inside $dbZip"
}

Write-OK "BACPAC found: $($bacpacFile.Name)"

Write-Step "Importing BACPAC into '$TargetDatabase' on '$TargetServer'"
Write-Host "    This may take 1-3 minutes..." -ForegroundColor Gray

$connectionString = Build-ConnectionString
$importArgs = @(
    "/Action:Import",
    "/SourceFile:`"$($bacpacFile.FullName)`"",
    "/TargetConnectionString:`"$connectionString`"",
    "/p:CommandTimeout=120"
)

& $sqlPackage @importArgs 2>&1 | ForEach-Object {
    if ($_ -match "error|fail" -and $_ -notmatch "Successfully") {
        Write-Host "    $_" -ForegroundColor Yellow
    }
}

if ($LASTEXITCODE -ne 0) {
    $failureMessage = @(
        "BACPAC import failed. Common causes:",
        "  - Database '$TargetDatabase' already exists (drop it first or use a different name)",
        "  - Cannot connect to '$TargetServer' (check SQL Server is running)",
        "  - Insufficient permissions (need db_creator role)"
    ) -join "`n"

    Write-Fail $failureMessage
}

Write-OK "Database '$TargetDatabase' imported"

Write-Step "Extracting Swift 2 Files folder to: $FilesPath"

if (-not (Test-Path $FilesPath)) {
    New-Item -ItemType Directory -Path $FilesPath -Force | Out-Null
}

$filesZip = Join-Path $DownloadPath $Downloads.Files.FileName
if (-not (Test-Path $filesZip)) {
    Write-Fail "Files ZIP not found at: $filesZip"
}

$filesExtract = Join-Path $DownloadPath "files-temp"
if (Test-Path $filesExtract) {
    Remove-Item $filesExtract -Recurse -Force
}

Expand-Archive -Path $filesZip -DestinationPath $filesExtract -Force

$nestedFiles = Get-ChildItem -Path $filesExtract -Directory -Filter "Files" | Select-Object -First 1
if ($nestedFiles) {
    Copy-Item -Path "$($nestedFiles.FullName)\*" -Destination $FilesPath -Recurse -Force
}
else {
    Copy-Item -Path "$filesExtract\*" -Destination $FilesPath -Recurse -Force
}

Write-OK "Files extracted"

Write-Step "Extracting demo data"

$demoZip = Join-Path $DownloadPath $Downloads.DemoData.FileName
if (Test-Path $demoZip) {
    $demoExtract = Join-Path $DownloadPath "demo-temp"
    if (Test-Path $demoExtract) {
        Remove-Item $demoExtract -Recurse -Force
    }

    Expand-Archive -Path $demoZip -DestinationPath $demoExtract -Force

    $imagesDir = Join-Path $FilesPath "Images"
    if (-not (Test-Path $imagesDir)) {
        New-Item -ItemType Directory -Path $imagesDir -Force | Out-Null
    }

    Copy-Item -Path "$demoExtract\*" -Destination $imagesDir -Recurse -Force
    Write-OK "Demo data extracted to $imagesDir"
}
else {
    Write-Warn "Demo data ZIP not found. Skipping demo data extraction."
}

$resolvedCustomMcpAddInsSourcePath = Resolve-CustomMcpAddInsSourcePath -ExplicitSourcePath $CustomMcpAddInsSourcePath
$bootstrapManifestPath = Install-CustomMcpAddIns -SourcePath $resolvedCustomMcpAddInsSourcePath -TargetFilesPath $FilesPath -SecretTtlMinutes $BootstrapSecretTtlMinutes

Write-Step "Writing GlobalSettings.Database.config"

$dbConfigPath = Join-Path $FilesPath "GlobalSettings.Database.config"
$dbConfigXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Globalsettings>
  <System>
    <Database>
      <Type>ms_sqlserver</Type>
      <SQLServer>$TargetServer</SQLServer>
      <Database>$TargetDatabase</Database>
      <UserName>$SqlUser</UserName>
      <Password>$SqlPassword</Password>
      <IntegratedSecurity>$($IntegratedSecurity.ToString())</IntegratedSecurity>
      <ConnectionString></ConnectionString>
      <ConnectionString2></ConnectionString2>
    </Database>
  </System>
</Globalsettings>
"@

Set-Content -Path $dbConfigPath -Value $dbConfigXml -Encoding UTF8
Write-OK "Database config written to $dbConfigPath"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Swift 2 installation complete!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

$escapedFilesPath = $FilesPath.Replace('\', '\\')
$summaryLines = @(
    "",
    "  Database    : $TargetDatabase on $TargetServer",
    "  Files folder: $FilesPath",
    "  DB config   : $dbConfigPath",
    "  Bootstrap   : $bootstrapManifestPath",
    "",
    "  NEXT STEPS:",
    "  ----------",
    "  1. If you do not have a DW10 application yet, create one:",
    "       dotnet new install Dynamicweb.ProjectTemplates",
    "       mkdir MyProject",
    "       cd MyProject",
    "       dotnet new dw10-suite --name Dynamicweb.Host.Suite",
    "",
    "  2. Point the application to this Files folder.",
    "     In appsettings.json, add:",
    "       `"FilesPath`": `"$escapedFilesPath`"",
    "",
    "     Or set an environment variable:",
    "       `$env:DW_FilesPath = `"$FilesPath`"",
    "",
    "  3. Start the application on .NET 10:",
    "       cd Dynamicweb.Host.Suite",
    "       dotnet run --framework net10.0",
    "",
    "  4. Open the URL shown in the terminal and append /admin to access the backend.",
    "     Install your license when prompted.",
    "",
    "  5. Verify MCP routes are active on .NET 10:",
    "       GET  /admin/mcp            -> 401 Unauthorized",
    "       HEAD /admin/mcp/bootstrap  -> 405 Method Not Allowed",
    "",
    "  6. Call POST /admin/mcp/bootstrap using the secret from:",
    "       $bootstrapManifestPath",
    "",
    "  7. Your Swift 2 site is ready for the dynamicweb-business-solution-agent flow.",
    ""
)

Write-Host ($summaryLines -join "`n")
