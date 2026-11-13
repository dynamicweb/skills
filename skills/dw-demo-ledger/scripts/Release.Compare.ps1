<#
.SYNOPSIS
READ-ONLY. Propose function candidates from general release evidence.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/release-process.md. Pure comparison
over captured inputs. Every addition and removal is retained for review; no feature
names, keywords, work-item IDs or database column names are privileged.
.EXAMPLE
. ./Release.Compare.ps1
Compare-ReleaseEvidence -Before $a -After $b -Changelog $notes
#>
#Requires -Version 7.0
. (Join-Path $PSScriptRoot 'Release.Metadata.ps1')
function Compare-ReleaseEvidence {
    param($Before,$After,$Changelog)
    $candidates=[Collections.Generic.List[object]]::new()
    foreach ($package in $After.packages) {
        $old=@($Before.packages | Where-Object package -eq $package.package)
        if ($old.Count -ne 1) { throw 'Both versions must contain each requested package exactly once.' }
        $oldTypes=@{}; foreach ($type in $old[0].metadata.types) { $oldTypes[$type.name]=$type }
        $newTypes=@{}; foreach ($type in $package.metadata.types) { $newTypes[$type.name]=$type }
        foreach ($type in $package.metadata.types | Where-Object public) {
            if (-not $oldTypes.ContainsKey($type.name) -or -not $oldTypes[$type.name].public) {
                $candidates.Add(@{id='type:'+$type.name;kind='public-type';change='added';name=$type.name;package=$package.package;source=$package.source;evidence=@{base=$type.base;assemblyDigest=$package.assemblyDigest}})
            }
            foreach ($constant in $type.constants) {
                $oldConstants=if ($oldTypes.ContainsKey($type.name)) { @($oldTypes[$type.name].constants.name) } else { @() }
                if ($constant.name -notin $oldConstants) { $candidates.Add(@{id='enum:'+$type.name+'.'+$constant.name;kind='enum-value';change='added';name=$type.name+'.'+$constant.name;package=$package.package;source=$package.source;evidence=@{value=$constant.value}}) }
            }
        }
        foreach ($type in $old[0].metadata.types | Where-Object public) {
            if (-not $newTypes.ContainsKey($type.name) -or -not $newTypes[$type.name].public) { $candidates.Add(@{id='type:'+$type.name;kind='public-type';change='removed';name=$type.name;package=$package.package;source=$package.source}) }
        }
    }
    $oldFlags=@(Get-ReleaseFeatureTypes $Before.packages)
    foreach ($flag in @(Get-ReleaseFeatureTypes $After.packages)) {
        if ($flag -notin $oldFlags) { $candidates.Add(@{id='flag:'+$flag;kind='feature-class';change='added';name=$flag;source='Package metadata FeatureBase ancestry';evidence=@{base='FeatureBase'}}) }
    }
    $aColumns=@{}; foreach ($column in $Before.database.columns) { $aColumns[$column.schema+'.'+$column.table+'.'+$column.name]=$column }
    $bColumns=@{}; foreach ($column in $After.database.columns) { $bColumns[$column.schema+'.'+$column.table+'.'+$column.name]=$column }
    foreach ($key in @($bColumns.Keys | Sort-Object)) {
        $change=if (-not $aColumns.ContainsKey($key)) { 'added' } elseif (($aColumns[$key] | ConvertTo-Json -Compress) -ne ($bColumns[$key] | ConvertTo-Json -Compress)) { 'changed' }
        if ($change) { $candidates.Add(@{id='column:'+$key;kind='database-column';change=$change;name=$key;source=$After.database.source;evidence=$bColumns[$key]}) }
    }
    foreach ($key in @($aColumns.Keys | Sort-Object)) {
        if (-not $bColumns.ContainsKey($key)) { $candidates.Add(@{id='column:'+$key;kind='database-column';change='removed';name=$key;source=$Before.database.source;evidence=$aColumns[$key]}) }
    }
    $tables=@(@($Before.database.primaryKeys)+@($After.database.primaryKeys) | ForEach-Object { $_.schema+'.'+$_.table } | Sort-Object -Unique)
    foreach ($table in $tables) {
        $a=@($Before.database.primaryKeys | Where-Object { $_.schema+'.'+$_.table -eq $table } | Sort-Object ordinal | ForEach-Object name)
        $b=@($After.database.primaryKeys | Where-Object { $_.schema+'.'+$_.table -eq $table } | Sort-Object ordinal | ForEach-Object name)
        if (($a -join '|') -ne ($b -join '|')) { $candidates.Add(@{id='primary-key:'+$table;kind='primary-key';change='changed';name=$table;source=$After.database.source;evidence=@{before=$a;after=$b}}) }
    }
    # One row per work item: an item listed under several releases keeps its first release and names them all.
    $items=[ordered]@{}
    foreach ($release in $Changelog.releases) {
        foreach ($item in $release.workItems) {
            $id='work-item:'+$item.id
            if ($items.Contains($id)) { $items[$id].evidence.versions+=$release.version; continue }
            $items[$id]=@{id=$id;kind='release-work-item';change='review';name=$item.title;source=$Changelog.source;evidence=@{version=$release.version;versions=@($release.version);released=$release.isReleased;type=$item.type;area=$item.area}}
        }
    }
    foreach ($row in $items.Values) { $row.evidence.versions=@($row.evidence.versions | Select-Object -Unique); $candidates.Add($row) }
    # Ordinal order, so the same evidence gives the same sequence on every machine.
    $ordered=[Collections.Generic.SortedDictionary[string,Collections.Generic.List[object]]]::new([StringComparer]::Ordinal)
    foreach ($row in $candidates) {
        $key=$row.kind+[char]0+$row.id+[char]0+$row.change+[char]0+$row.package
        if (-not $ordered.ContainsKey($key)) { $ordered[$key]=[Collections.Generic.List[object]]::new() }
        $ordered[$key].Add($row)
    }
    return @(foreach ($rows in $ordered.Values) { $rows })
}
