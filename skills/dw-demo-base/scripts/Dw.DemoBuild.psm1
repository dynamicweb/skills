<#
.SYNOPSIS
WRITES: nothing on import; helpers generate files and checkpoints when called.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. Imports do not connect or write.
Config rejects unknown keys and branding blocks before a build can mutate anything.
.EXAMPLE
Import-Module ./scripts/Dw.DemoBuild.psm1
#>
#Requires -Version 7.0
param()
$ErrorActionPreference = 'Stop'

function Read-DwBuildConfig {
    param([Parameter(Mandatory)][string]$ConfigPath)
    $c = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json -AsHashtable
    # Branding is not a base build step: it follows the build with dw-demo-swift.
    foreach ($key in 'brand','storefront','personas','catalogue') {
        if ($c.ContainsKey($key)) { throw "Config key $key is branding. The scripted base build only scaffolds a running base; brand it afterwards with dw-demo-swift." }
    }
    $allowed = 'slug','customer','edition','installMcpBeforeStart'
    foreach ($key in $c.Keys) { if ($key -notin $allowed) { throw "Unknown config key: $key" } }
    if ($c.slug -notmatch '^[a-z][a-z0-9-]{1,47}$') { throw 'slug must be 2-48 lowercase letters, digits or hyphens, starting with a letter.' }
    if ($c.customer -isnot [hashtable] -or [string]::IsNullOrWhiteSpace($c.customer.name)) { throw 'customer.name is required.' }
    if ($c.customer.name.Length -gt 120) { throw 'customer.name exceeds 120 characters.' }
    foreach ($key in $c.customer.Keys) { if ($key -notin 'name','country','currency','language') { throw "Unknown config key: customer.$key" } }
    foreach ($key in 'country','currency','language') {
        if ($c.customer[$key] -and $c.customer[$key] -ne @{country='US';currency='USD';language='en-US'}[$key]) {
            throw "$key changes require the agent localization phase; this edition build supports US/USD/en-US."
        }
    }
    if ($c.edition -and $c.edition -ne 'swift-demo') { throw 'Only the swift-demo edition is supported by this build.' }
    if ($c.ContainsKey('installMcpBeforeStart') -and $c.installMcpBeforeStart -isnot [bool]) { throw 'installMcpBeforeStart must be boolean.' }
    if (-not $c.ContainsKey('installMcpBeforeStart')) { $c.installMcpBeforeStart = $true }
    if (-not $c.edition) { $c.edition = 'swift-demo' }
    return $c
}

function Write-DwBuildJson {
    param([string]$Path, $Value)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    if([IO.Path]::GetFileName($Path) -eq 'flow-state.json'){
        $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        $Value | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $temporary -Encoding utf8NoBOM
        [IO.File]::Move($temporary,$Path,$true)
        return
    }
    $Value | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function Get-DwBuildPaths {
    param([string]$DemoRoot)
    $root = [IO.Path]::GetFullPath($DemoRoot)
    if ($root -match '(^|[\\/])customer-context([\\/]|$)') { throw 'customer-context is read-only.' }
    @{ Root=$root; Host=(Join-Path $root 'Dynamicweb.Host.Suite'); Files=(Join-Path $root 'Dynamicweb.Host.Suite/wwwroot/Files'); Distribution=(Join-Path $root 'distribution'); Notes=(Join-Path $root 'notes'); Release=(Join-Path $root 'notes/distribution-release.json') }
}

function Invoke-DwBuildCommand {
    param([string]$Command,[string[]]$Arguments,[int]$TimeoutSeconds=3600,[switch]$CaptureOutput)
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=(Get-Command $Command -ErrorAction Stop).Source
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    try {
        $null=$process.Start()
        $stdout=$process.StandardOutput.ReadLineAsync();$stderr=$process.StandardError.ReadLineAsync()
        $outOpen=$true;$errOpen=$true;$captured=[Collections.Generic.List[string]]::new()
        $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while(-not $process.HasExited -or $outOpen -or $errOpen){
            if($outOpen -and $stdout.IsCompleted){
                $line=$stdout.GetAwaiter().GetResult()
                if($null -eq $line){$outOpen=$false}else{Write-Host $line;$captured.Add($line);$stdout=$process.StandardOutput.ReadLineAsync()}
            }
            if($errOpen -and $stderr.IsCompleted){
                $line=$stderr.GetAwaiter().GetResult()
                if($null -eq $line){$errOpen=$false}else{Write-Host $line;$stderr=$process.StandardError.ReadLineAsync()}
            }
            if([DateTime]::UtcNow -ge $deadline){
                if(-not $process.HasExited){$process.Kill($true)}
                $null=$process.WaitForExit(5000)
                throw "$Command exceeded $TimeoutSeconds seconds. Only this command's child tree was stopped; check the runtime and local logs."
            }
            Start-Sleep -Milliseconds 50
        }
        if($process.ExitCode -ne 0){throw "$Command failed with exit $($process.ExitCode)."}
        if($CaptureOutput){return ($captured -join "`n")}
    } finally {$process.Dispose()}
}

function Get-DwBuildConnection {
    param([string]$SqlServer,[string]$Database)
    if (-not $SqlServer -or $Database -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{1,100}$') { throw 'Pass a SQL server and a safe database name.' }
    $b = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $b['Data Source']=$SqlServer; $b['Initial Catalog']=$Database; $b['TrustServerCertificate']=$true
    if ([bool]$env:DW_SQL_USER -ne [bool]$env:DW_SQL_PASSWORD) { throw 'Set both DW_SQL_USER and DW_SQL_PASSWORD, or neither for Windows authentication.' }
    if ($env:DW_SQL_USER -and $env:DW_SQL_PASSWORD) {
        $b['User ID']=$env:DW_SQL_USER; $b['Password']=$env:DW_SQL_PASSWORD
    } else { $b['Integrated Security']=$true }
    Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Sql.Local.psm1') -ErrorAction Stop
    Assert-DwSqlLocal -ConnectionString $b.ConnectionString | Out-Null
    $b.ConnectionString
}

function Get-DwBuildRows {
    param([string]$ConnectionString,[string]$Sql,[hashtable]$Parameters=@{})
    $cn=[System.Data.SqlClient.SqlConnection]::new($ConnectionString)
    try {
        $cn.Open(); $cmd=$cn.CreateCommand(); $cmd.CommandText=$Sql; $cmd.CommandTimeout=120
        foreach ($k in $Parameters.Keys) { $null=$cmd.Parameters.AddWithValue("@$k",$Parameters[$k]) }
        $reader=$cmd.ExecuteReader(); $rows=[Collections.Generic.List[object]]::new()
        while ($reader.Read()) { $row=@{}; for($i=0;$i -lt $reader.FieldCount;$i++) { $row[$reader.GetName($i)]=$reader.GetValue($i) }; $rows.Add($row) }
        return ,$rows.ToArray()
    } finally { $cn.Dispose() }
}

function Get-DwBuildTokenHash {
    param([Parameter(Mandatory)][string]$Bearer)
    $parts=$Bearer.Split('.',2)
    if($parts.Count -ne 2 -or $parts[0] -notmatch '^[A-Z][A-Z0-9]{2,15}$' -or $parts[1].Length -lt 32){throw 'Invalid local API-key format.'}
    $digest=[Security.Cryptography.SHA512]::HashData([Text.Encoding]::UTF8.GetBytes($parts[1]+'DwSecret'))
    $parts[0]+'.'+[Convert]::ToHexString($digest).ToLowerInvariant()
}

function Initialize-DwBuildAccess {
    param([Parameter(Mandatory)]$Connection,[Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)][string]$ApiBearer,[Parameter(Mandatory)][string]$McpBearer)
    # Local fresh-restore rung only. Caller owns the database and requires a stopped host.
    $cmd=$Connection.CreateCommand();$cmd.Transaction=$Transaction;$cmd.CommandTimeout=120
    $cmd.CommandText=@'
IF OBJECT_ID('McpConfiguration') IS NULL
 CREATE TABLE McpConfiguration (
  McpConfigurationId int IDENTITY PRIMARY KEY,
  McpConfigurationName nvarchar(255) NOT NULL,
  McpConfigurationTokenId int NULL,
  McpConfigurationCreatedDate datetime NOT NULL DEFAULT GETUTCDATE(),
  McpConfigurationUpdatedDate datetime NULL,
  McpConfigurationAllowEverything bit NOT NULL DEFAULT 0);
IF OBJECT_ID('McpConfigurationCredential') IS NULL
 CREATE TABLE McpConfigurationCredential (
  McpConfigurationCredentialId int IDENTITY PRIMARY KEY,
  McpConfigurationCredentialConfigurationId int NOT NULL,
  McpConfigurationCredentialTokenId int NOT NULL,
  McpConfigurationCredentialDcrClientId nvarchar(255) NULL,
  McpConfigurationCredentialRedirectUris nvarchar(max) NULL,
  McpConfigurationCredentialCreatedDate datetime NOT NULL DEFAULT GETUTCDATE());
DECLARE @apiId int,@tokenId int,@configId int;
SELECT @apiId=AccessUserTokenId FROM AccessUserToken WHERE AccessUserTokenHash=@api;
IF @apiId IS NULL BEGIN
 INSERT AccessUserToken (AccessUserTokenHash,AccessUserTokenUserId,AccessUserTokenDeviceId,AccessUserTokenName,AccessUserTokenDescription,AccessUserTokenCreatedDate,AccessUserTokenExpiryDate,AccessUserTokenType,AccessUserTokenClientId,AccessUserTokenClientSecretHash)
 VALUES (@api,2,'','Scripted demo API','',GETUTCDATE(),'9999-12-31T23:59:59.997',0,'','');
 SET @apiId=SCOPE_IDENTITY();
END;
SELECT @tokenId=AccessUserTokenId FROM AccessUserToken WHERE AccessUserTokenHash=@mcp;
IF @tokenId IS NULL BEGIN
 INSERT AccessUserToken (AccessUserTokenHash,AccessUserTokenUserId,AccessUserTokenDeviceId,AccessUserTokenName,AccessUserTokenDescription,AccessUserTokenCreatedDate,AccessUserTokenExpiryDate,AccessUserTokenType,AccessUserTokenClientId,AccessUserTokenClientSecretHash)
 VALUES (@mcp,2,'','Scripted demo MCP','',GETUTCDATE(),'9999-12-31T23:59:59.997',0,'','');
 SET @tokenId=SCOPE_IDENTITY();
END;
SELECT @configId=McpConfigurationCredentialConfigurationId FROM McpConfigurationCredential WHERE McpConfigurationCredentialTokenId=@tokenId;
IF @configId IS NULL BEGIN
 INSERT McpConfiguration (McpConfigurationName,McpConfigurationTokenId,McpConfigurationAllowEverything)
 VALUES ('Scripted local demo',NULL,1);
 SET @configId=SCOPE_IDENTITY();
 INSERT McpConfigurationCredential (McpConfigurationCredentialConfigurationId,McpConfigurationCredentialTokenId)
 VALUES (@configId,@tokenId);
END;
IF (SELECT COUNT(*) FROM AccessUserToken WHERE AccessUserTokenId IN (@apiId,@tokenId) AND AccessUserTokenUserId=2 AND AccessUserTokenType=0)<>2
 THROW 50000,'Local token assertion failed.',1;
IF NOT EXISTS(SELECT 1 FROM McpConfiguration c JOIN McpConfigurationCredential k ON c.McpConfigurationId=k.McpConfigurationCredentialConfigurationId WHERE c.McpConfigurationId=@configId AND c.McpConfigurationAllowEverything=1 AND k.McpConfigurationCredentialTokenId=@tokenId)
 THROW 50000,'Local MCP credential binding assertion failed.',1;
SELECT @configId;
'@
    $null=$cmd.Parameters.AddWithValue('@api',(Get-DwBuildTokenHash $ApiBearer))
    $null=$cmd.Parameters.AddWithValue('@mcp',(Get-DwBuildTokenHash $McpBearer))
    [int]$cmd.ExecuteScalar()
}

Export-ModuleMember -Function *-DwBuild*
