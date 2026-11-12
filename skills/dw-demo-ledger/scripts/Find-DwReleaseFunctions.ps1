<#
.SYNOPSIS
READ-ONLY. Scan two DW versions; writes raw evidence and unreviewed candidates.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/release-process.md. Reads public NuGet
packages with metadata tables only, the target milestone changelog and local database
schemas. Does not execute package code, change hosts or approve candidates. An existing
OutFile is refused so the original scan cannot be overwritten after review.
.PARAMETER BeforeVersion
Exact earlier platform package version.
.PARAMETER AfterVersion
Exact later platform package version.
.PARAMETER EvidenceDirectory
Local cache/output directory for package bytes and captured schema evidence.
.PARAMETER OutFile
New local JSON path for the raw, unreviewed scan.
.PARAMETER SqlServer
Explicit local SQL server for schema SELECTs.
.PARAMETER BeforeDatabase
Earlier database; unused when BeforeSchemaFile is provided.
.PARAMETER AfterDatabase
Later database; unused when AfterSchemaFile is provided.
.PARAMETER BeforeBaseUrl
Earlier host descriptor used to verify the schema capture version.
.PARAMETER AfterBaseUrl
Later host descriptor used to verify the schema capture version.
.PARAMETER BeforeSchemaFile
Previously captured schema evidence, for a host that has since been upgraded.
.PARAMETER AfterSchemaFile
Previously captured later schema evidence.
.PARAMETER Packages
Exact package IDs at both versions, by default Dynamicweb, Core and Ecommerce.
.EXAMPLE
pwsh -NoProfile -File scripts/Find-DwReleaseFunctions.ps1 -BeforeVersion $a -AfterVersion $b -EvidenceDirectory $cache -OutFile $raw -SqlServer $server -BeforeDatabase $dbA -AfterDatabase $dbB -BeforeBaseUrl $urlA -AfterBaseUrl $urlB
#>
#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BeforeVersion,[Parameter(Mandatory)][string]$AfterVersion,
      [Parameter(Mandatory)][string]$EvidenceDirectory,[Parameter(Mandatory)][string]$OutFile,
      [string]$SqlServer,[string]$BeforeDatabase,[string]$AfterDatabase,[string]$BeforeBaseUrl,[string]$AfterBaseUrl,
      [string]$BeforeSchemaFile,[string]$AfterSchemaFile,[string[]]$Packages=@('Dynamicweb','Dynamicweb.Core','Dynamicweb.Ecommerce'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Release.Evidence.ps1')
. (Join-Path $PSScriptRoot 'Release.Compare.ps1')
try {
    if (Test-Path -LiteralPath $OutFile) { throw 'Raw scan output already exists; choose a new path to preserve pre-review evidence.' }
    if ([version]$BeforeVersion -ge [version]$AfterVersion) { throw 'BeforeVersion must precede AfterVersion.' }
    $null=New-Item -ItemType Directory -Force -Path $EvidenceDirectory
    $states=@()
    foreach ($side in @(@{version=$BeforeVersion;database=$BeforeDatabase;url=$BeforeBaseUrl;schema=$BeforeSchemaFile},@{version=$AfterVersion;database=$AfterDatabase;url=$AfterBaseUrl;schema=$AfterSchemaFile})) {
        $schema=if ($side.schema) { Get-Content -LiteralPath $side.schema -Raw | ConvertFrom-Json -AsHashtable } else { Get-ReleaseSchemaEvidence -Server $SqlServer -Database $side.database -BaseUrl $side.url -Version $side.version }
        if ($schema.requestedVersion -ne $side.version) { throw 'Retained database schema names a different version.' }
        Write-ReleaseEvidenceJson (Join-Path $EvidenceDirectory ('schema-'+$side.version+'.json')) $schema
        $packagesForVersion=@(foreach ($package in $Packages) { Get-ReleasePackageEvidence -Package $package -Version $side.version -Directory $EvidenceDirectory })
        $states+=@{version=$side.version;packages=$packagesForVersion;database=$schema}
    }
    $notes=Get-ReleaseChangelogEvidence -Version $AfterVersion -Directory $EvidenceDirectory
    $candidates=@(Compare-ReleaseEvidence -Before $states[0] -After $states[1] -Changelog $notes)
    $report=@{schema=1;status='unreviewed';generatedAt=[DateTimeOffset]::UtcNow.ToString('o');before=$BeforeVersion;after=$AfterVersion
        method='All public-type additions/removals, added enum values, added FeatureBase subclasses, database columns/keys and target milestone work items; no feature-keyword filter.'
        inputs=@(foreach ($state in $states) { @{version=$state.version;packages=@($state.packages | ForEach-Object { @{package=$_.package;source=$_.source;version=$_.version;packageDigest=$_.packageDigest;assemblyDigest=$_.assemblyDigest;entry=$_.entry;assemblyVersion=$_.metadata.version;typeCount=$_.metadata.types.Count} });schemaDigest='sha256:'+(Get-FileHash (Join-Path $EvidenceDirectory ('schema-'+$state.version+'.json')) -Algorithm SHA256).Hash.ToLowerInvariant();schemaObservedVersion=$state.database.observedVersion} })
        changelog=$notes;candidates=$candidates;errors=@()}
    Write-ReleaseEvidenceJson $OutFile $report
    Write-Output ("Saved {0} unreviewed candidates." -f $candidates.Count)
    exit 0
} catch { Write-Error ('Release scan failed: '+$_.Exception.Message) -ErrorAction Continue; exit 1 }
