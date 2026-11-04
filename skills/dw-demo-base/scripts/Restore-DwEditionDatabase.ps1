<#
.SYNOPSIS
WRITES: a NEW local database imported from the verified bacpac, and existing user passwords.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. SQL is local installs only. The host
does not exist on the higher API surfaces yet. Password repair precedes first startup, so no
cache flush is owed. A database not owned by this build is always refused, never dropped.
.PARAMETER DemoRoot
Demo root with the release receipt.
.PARAMETER SqlServer
Local SQL Server with Windows authentication.
.PARAMETER Database
New database name.
.PARAMETER Apply
Import and repair; otherwise preview.
.EXAMPLE
pwsh -NoProfile -File scripts/Restore-DwEditionDatabase.ps1 -DemoRoot $demo -SqlServer $server -Database $db -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$DemoRoot,[Parameter(Mandatory)][string]$SqlServer,[Parameter(Mandatory)][string]$Database,[switch]$Apply)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Sql.Local.psm1') -Force
try {
    $p=Get-DwBuildPaths $DemoRoot; $conn=Get-DwBuildConnection $SqlServer $Database
    $launchPath=Join-Path $p.Host 'Properties/launchSettings.json'
    if(Test-Path $launchPath){
        $launch=Get-Content -Raw $launchPath | ConvertFrom-Json
        $hostPort=([uri]$launch.profiles.'Dynamicweb.Host.Suite'.applicationUrl).Port
        if(Get-NetTCPConnection -LocalPort $hostPort -State Listen -ErrorAction SilentlyContinue){throw 'Stop the owned host before restore or credential repair. These SQL writes must precede startup.'}
    }
    $master=Get-DwBuildConnection $SqlServer 'master'
    $r=Get-Content -Raw $p.Release | ConvertFrom-Json
    if (-not $Apply -or -not $PSCmdlet.ShouldProcess($Database,'Import new database and set scrubbed passwords')) { Write-Host 'Plan: import NEW database, repair administrator and three persona passwords before startup.'; exit 0 }
    $marker=Join-Path $p.Notes 'database-owned.json'
    $exists=(Get-DwBuildRows $master 'SELECT DB_ID(@db) AS id' @{db=$Database})[0].id -isnot [DBNull]
    if ($exists -and -not (Test-Path $marker)) { throw 'Database already exists and is not owned by this build. Choose a new name.' }
    if ($exists) {
        $owned=Get-Content -Raw $marker | ConvertFrom-Json
        if ($owned.database -ne $Database -or $owned.server -ne $SqlServer -or $owned.sha256 -ne $r.bacpac.sha256) { throw 'Existing database receipt does not match this build.' }
    } else {
        if ((Get-FileHash $r.bacpacPath -Algorithm SHA256).Hash -ne $r.bacpac.sha256) { throw 'Bacpac changed after resolution.' }
        Invoke-DwBuildCommand sqlpackage @('/Action:Import',"/SourceFile:$($r.bacpacPath)","/TargetConnectionString:$conn",'/p:CommandTimeout=300')
        Write-DwBuildJson $marker @{database=$Database;server=$SqlServer;sha256=$r.bacpac.sha256}
    }
    $secretPath=Join-Path $p.Notes 'build-secrets.local.json'
    $secrets=if(Test-Path $secretPath){Get-Content -Raw $secretPath | ConvertFrom-Json -AsHashtable}else{@{}}
    foreach ($entry in @(@{id=2;env='DW_ADMIN_PASSWORD'},@{id=100101;env='DW_BUYER_PASSWORD'},@{id=100102;env='DW_CSR_PASSWORD'},@{id=100103;env='DW_ACCOUNT_ADMIN_PASSWORD'})) {
        $key=[string]$entry.id; $value=[Environment]::GetEnvironmentVariable($entry.env)
        if ($value) {$secrets[$key]=$value}
        if (-not $secrets[$key]) { $secrets[$key]=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(18))+'!a7' }
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA512]::HashData([Text.Encoding]::UTF8.GetBytes($secrets[$key]+'DwSecret'))).ToLowerInvariant()
        $sql='UPDATE AccessUser SET [AccessUserPassword]=@hash, AccessUserActive=1, AccessUserPasswordDate=GETDATE() WHERE AccessUserID=@id'
        $n=Invoke-DwSqlNonQuery -ConnectionString $conn -Sql $sql -Parameters @{hash=$hash;id=$entry.id}
        if($n -ne 1){throw "Expected one credential row for id $key, got $n."}
    }
    # The stock wizard can seed Admin separately; avoid a duplicate username on id 2.
    $admins=Get-DwBuildRows $conn "SELECT AccessUserID FROM AccessUser WHERE AccessUserUserName='Admin' AND AccessUserID<>2"
    if ($admins.Count -gt 0) { $null=Invoke-DwSqlNonQuery -ConnectionString $conn -Sql "UPDATE AccessUser SET AccessUserUserName='SeedAdmin',AccessUserActive=0 WHERE AccessUserUserName='Admin' AND AccessUserID<>2" }
    $n=Invoke-DwSqlNonQuery -ConnectionString $conn -Sql "UPDATE AccessUser SET AccessUserUserName='Admin' WHERE AccessUserID=2"
    if($n -ne 1){throw 'Administrator rename failed.'}
    Write-DwBuildJson $secretPath $secrets
    $lines=@('# Local credentials','','Admin username: Admin','')
    foreach($key in $secrets.Keys){$lines+="User id ${key}: $($secrets[$key])"}
    Set-Content (Join-Path $p.Notes 'credentials.local.md') $lines -Encoding utf8NoBOM
    Write-Host 'Restored database credentials repaired: four rows. Secrets stored locally, never printed.'
    exit 0
} catch { Write-Error $_ -ErrorAction Continue; exit 1 }
