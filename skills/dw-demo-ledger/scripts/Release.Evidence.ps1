<#
.SYNOPSIS
READ-ONLY. Collect general package, changelog and database-schema evidence.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/release-process.md. Writes downloaded
public evidence only to an explicit cache directory. SQL uses integrated auth and
INFORMATION_SCHEMA SELECTs on explicitly local servers. No feature-keyword search.
Evidence is written with ordered members, so the same content gives the same bytes, and a
retained capture is never overwritten by different content. A retained changelog capture
replaces the public changelog request.
.EXAMPLE
. ./Release.Evidence.ps1
Get-ReleasePackageEvidence -Package Dynamicweb.Ecommerce -Version $version -Directory $cache
#>
#Requires -Version 7.0
. (Join-Path $PSScriptRoot 'Release.Metadata.ps1')
. (Join-Path $PSScriptRoot 'Ledger.Sql.ps1')
function ConvertTo-ReleaseOrdered {
    # Object members in ordinal name order at every depth: the same content always serialises to the same bytes.
    param($Value)
    if ($Value -is [Collections.IDictionary] -or $Value -is [Management.Automation.PSCustomObject]) {
        $source=if ($Value -is [Collections.IDictionary]) { $Value } else { $map=@{}; foreach ($p in $Value.PSObject.Properties) { $map[$p.Name]=$p.Value }; $map }
        $keys=[string[]]@($source.Keys); [Array]::Sort($keys,[StringComparer]::Ordinal)
        $ordered=[ordered]@{}; foreach ($key in $keys) { $ordered[$key]=ConvertTo-ReleaseOrdered $source[$key] }
        return $ordered
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) { return ,@(foreach ($item in $Value) { ConvertTo-ReleaseOrdered $item }) }
    return $Value
}
function ConvertTo-ReleaseJson {
    param($Value)
    return (ConvertTo-Json -InputObject (ConvertTo-ReleaseOrdered $Value) -Depth 80)+"`n"
}
function Write-ReleaseEvidenceJson {
    param([string]$Path,$Value)
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Path),(ConvertTo-ReleaseJson $Value),[Text.UTF8Encoding]::new($false))
}
function Save-ReleaseEvidence {
    # Captured evidence is written once. The same content again is left alone; different content is refused.
    param([string]$Path,$Value)
    if (Test-Path -LiteralPath $Path) {
        $retained=ConvertTo-ReleaseJson (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate)
        if ($retained -ceq (ConvertTo-ReleaseJson $Value)) { return }
        throw "Retained evidence '$(Split-Path -Leaf $Path)' differs from the new capture and is not overwritten. Rerun from the retained file, or collect into a new evidence directory."
    }
    Write-ReleaseEvidenceJson $Path $Value
}
function Get-ReleasePackageEvidence {
    param([string]$Package,[string]$Version,[string]$Directory)
    if ($Package -notmatch '^[A-Za-z0-9.]+$' -or $Version -notmatch '^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?$') { throw 'Invalid package identity.' }
    $id=$Package.ToLowerInvariant(); $versionId=$Version.ToLowerInvariant()
    $folder=Join-Path $Directory "$id/$versionId"; $null=New-Item -ItemType Directory -Force -Path $folder
    $url="https://api.nuget.org/v3-flatcontainer/$id/$versionId/$id.$versionId.nupkg"
    $archive=Join-Path $folder 'package.nupkg'
    if (-not (Test-Path -LiteralPath $archive)) { Invoke-WebRequest -Uri $url -OutFile $archive -TimeoutSec 90 }
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $matches=@($zip.Entries | Where-Object { $_.FullName -match '^lib/[^/]+/[^/]+\.dll$' -and $_.Name -ieq ($Package+'.dll') } | Sort-Object FullName)
        if (-not $matches.Count) { throw "Package $Package $Version has no matching library assembly." }
        # Metadata only; record the selected TFM instead of inferring runtime compatibility.
        $entry=$matches[0]; $dll=Join-Path $folder $entry.Name
        $inputStream=$entry.Open(); $outputStream=[IO.File]::Create($dll)
        try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
        $metadata=Read-ReleaseAssemblyMetadata $dll
        $record=@{package=$Package;version=$Version;source=$url;packageDigest='sha256:'+(Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
            assemblyDigest='sha256:'+(Get-FileHash $dll -Algorithm SHA256).Hash.ToLowerInvariant();entry=$entry.FullName;metadata=$metadata}
        Write-ReleaseEvidenceJson (Join-Path $folder 'metadata.json') $record
        return $record
    } finally { $zip.Dispose() }
}
function Get-ReleaseChangelogEvidence {
    # With -ChangelogFile the retained capture is the evidence and no request is made.
    param([string]$Version,[string]$Directory,[string]$ChangelogFile,[string]$ExpectedDigest)
    $target=[version](($Version -split '-')[0])
    $milestone=$target.ToString(2)
    $capture=Join-Path $Directory 'changelog-response.json'
    $basicUrl='https://devopsservice.dynamicweb-cms.com/api/release/dw10/release/basicinfo'
    if ($ChangelogFile) {
        $retained=(Resolve-Path -LiteralPath $ChangelogFile).Path
        $releases=Get-Content -LiteralPath $retained -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate
        if ($retained -ne [IO.Path]::GetFullPath($capture)) { Save-ReleaseEvidence $capture $releases }
        $url='retained capture';$basicUrl=$null;$digestFile=$retained
    } else {
        $rings=Invoke-RestMethod -Uri $basicUrl -TimeoutSec 45
        $ring=0
        for ($i=0;$i -lt $rings.Count;$i++) { if ($rings[$i].latestReleaseName -eq "milestones/$milestone") { $ring=$i+1; break } }
        if (-not $ring) { throw "Target milestone $milestone is not in the public changelog ring listing; pass the retained capture as -ChangelogFile instead of guessing a ring." }
        $url="https://devopsservice.dynamicweb-cms.com/api/documentation/release/detailedinfo/$ring"
        $releases=Invoke-RestMethod -Uri $url -TimeoutSec 45
        # The listing that chose the ring is evidence too, and neither capture replaces an earlier, different one.
        Save-ReleaseEvidence (Join-Path $Directory 'changelog-rings.json') $rings
        Save-ReleaseEvidence $capture $releases
        $digestFile=$capture
    }
    $digest='sha256:'+(Get-FileHash -LiteralPath $digestFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ExpectedDigest -and $ExpectedDigest -ne $digest) { throw "The changelog capture has digest $digest, not the recorded $ExpectedDigest." }
    $selected=@($releases | Where-Object { $_.version -match '^\d+\.\d+\.\d+$' -and ([version]$_.version).ToString(2) -eq $milestone -and [version]$_.version -le $target })
    if (-not $selected.Count) { throw 'Changelog capture holds no release in the requested target milestone.' }
    return @{source=$url;ringListing=$basicUrl;milestone=$milestone;targetVersion=$Version;releases=$selected;responseDigest=$digest}
}
function Get-ReleaseSchemaEvidence {
    param([string]$Server,[string]$Database,[string]$BaseUrl,[string]$Version)
    $observed=$null
    if ($BaseUrl) {
        $descriptor=Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+'/admin/api/api.json') -TimeoutSec 30
        $observed=[string]$descriptor.info.version
        if (($observed -split '\+')[0] -ne $Version) { throw 'Database evidence host descriptor differs from the requested version; capture the correct baseline.' }
    }
    $columnsQuery='SELECT TABLE_SCHEMA AS [schema],TABLE_NAME AS [table],COLUMN_NAME AS [name],DATA_TYPE AS [type],IS_NULLABLE AS nullable,CHARACTER_MAXIMUM_LENGTH AS maxLength FROM INFORMATION_SCHEMA.COLUMNS ORDER BY TABLE_SCHEMA,TABLE_NAME,ORDINAL_POSITION FOR JSON PATH'
    $keysQuery="SELECT k.TABLE_SCHEMA AS [schema],k.TABLE_NAME AS [table],k.COLUMN_NAME AS [name],k.ORDINAL_POSITION AS ordinal FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE k INNER JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS c ON c.CONSTRAINT_NAME=k.CONSTRAINT_NAME AND c.CONSTRAINT_SCHEMA=k.CONSTRAINT_SCHEMA WHERE c.CONSTRAINT_TYPE='PRIMARY KEY' ORDER BY k.TABLE_SCHEMA,k.TABLE_NAME,k.ORDINAL_POSITION FOR JSON PATH"
    $columns=(@(Invoke-Sqlcmd-Rows -Server $Server -Database $Database -Query $columnsQuery) -join '') | ConvertFrom-Json -AsHashtable
    $keys=(@(Invoke-Sqlcmd-Rows -Server $Server -Database $Database -Query $keysQuery) -join '') | ConvertFrom-Json -AsHashtable
    # Which database this is, without a machine name: two captures with one sourceId are a before and after of the same database.
    $sourceId='sha256:'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes("$Server/$Database".ToLowerInvariant()))).ToLowerInvariant()
    $provenance=@{database=$Database;sourceId=$sourceId;hostVersionVerified=[bool]$BaseUrl}
    return @{schema=1;requestedVersion=$Version;observedVersion=$observed;source='INFORMATION_SCHEMA.COLUMNS and KEY_COLUMN_USAGE';capturedAt=[DateTimeOffset]::UtcNow.ToString('o');provenance=$provenance;columns=@($columns);primaryKeys=@($keys)}
}
