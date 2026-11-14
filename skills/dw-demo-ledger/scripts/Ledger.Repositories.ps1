<#
.SYNOPSIS
READ-ONLY. Repository definition observations from the local Files root: facet fields and query constants.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. Reads the .facets, .query and .index XML
under Files/System/Repositories without building or querying an index. XML DTDs and external
entities are refused (Read-LedgerXml), and every path stays under the supplied Files root.
files-facet-analyzed joins each facet to its source query, the query to its source index, and the
facet field to that index's declaration or to a field the index's schema extender generates, as the
binding's arguments.generated table states it for the release. A field it cannot resolve to a known
Analyzed flag is an offender, never skipped. files-query-constant-macros reports each
ConstantExpression whose value has the macro shape Namespace.Something:Field.
.EXAMPLE
. ./Ledger.Repositories.ps1
Get-LedgerRepositoryObservation -Binding $binding -FilesPath $files
#>
#Requires -Version 7.0
$script:LedgerMacroShape='^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+:[A-Za-z_][A-Za-z0-9_]*$'
function Get-LedgerRepositoryRelative {
    # The Files-relative path with forward slashes, for an offender row. Never an absolute machine path.
    param([string]$FilesPath,[string]$Path)
    return [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($FilesPath),$Path).Replace('\','/')
}
function Resolve-LedgerRepositoryItem {
    # A Source element names a repository folder and an item file in it; both are single plain names.
    param([string]$FilesPath,$Source)
    if($null -eq $Source){return $null}
    $repository=$Source.GetAttribute('Repository');$item=$Source.GetAttribute('Item')
    foreach($name in @($repository,$item)){
        if([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\/:*?"<>|]' -or $name -in @('.','..')){return $null}
    }
    $path=Resolve-LedgerPath $FilesPath "System/Repositories/$repository/$item"
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $null}
    if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw [InvalidOperationException]::new('Linked file scope is unavailable.')}
    return $path
}
function Get-LedgerGeneratedAnalyzed {
    # The Analyzed state of a field an extender generates: $true, $false, or the rule name the caller resolves.
    param($Generated,[string[]]$Extenders,[string]$Field)
    foreach($extender in $Extenders){
        if(-not $Generated.ContainsKey($extender)){continue}
        $table=$Generated[$extender]
        if($table.fields -and $table.fields.ContainsKey($Field)){return ,@($table.fields[$Field],$extender)}
    }
    foreach($extender in $Extenders){
        if(-not $Generated.ContainsKey($extender)){continue}
        $table=$Generated[$extender]
        if(-not $table.prefixes){continue}
        $best=$null
        foreach($prefix in $table.prefixes.Keys){if($Field.StartsWith($prefix,[StringComparison]::Ordinal) -and $Field.Length -gt $prefix.Length -and ($null -eq $best -or $prefix.Length -gt $best.Length)){$best=$prefix}}
        if($null -ne $best){return ,@($table.prefixes[$best],$extender)}
    }
    return $null
}
function Get-LedgerFacetAnalyzedObservation {
    param($Binding,[string]$FilesPath,[string[]]$Files)
    $generated=if($Binding.arguments -and $Binding.arguments.generated -is [Collections.IDictionary]){$Binding.arguments.generated}else{throw 'files-facet-analyzed needs arguments.generated.'}
    foreach($extender in $generated.Keys){foreach($part in @('fields','prefixes')){
        $table=$generated[$extender][$part]
        if($null -ne $table){foreach($value in $table.Values){if($value -isnot [bool] -and $value -cnotin @('default-fields','default-fields-if-text')){throw 'Generated field states are true, false, default-fields or default-fields-if-text.'}}}
    }}
    # DoNotAnalyzeDefaultFields turns every default-field rule off. An unstated key is not assumed.
    $defaults=Get-LedgerSettingFact $FilesPath '/Globalsettings/Ecom/Indexing/DoNotAnalyzeDefaultFields'
    $offenders=[Collections.Generic.List[object]]::new();$scanned=0;$indexes=@{}
    foreach($file in $Files){
        $doc=Read-LedgerXml $file;$where=Get-LedgerRepositoryRelative $FilesPath $file
        $facets=@($doc.SelectNodes('/Facets/Facet'))
        $index=$null;$why=$null
        $query=Resolve-LedgerRepositoryItem $FilesPath $doc.SelectSingleNode('/Facets/Source')
        if(-not $query){$why='its source query does not resolve under System/Repositories'}
        else{
            $indexPath=Resolve-LedgerRepositoryItem $FilesPath (Read-LedgerXml $query).SelectSingleNode('/Query/Source')
            if(-not $indexPath){$why='its source query names no index that resolves under System/Repositories'}
            else{
                if(-not $indexes.ContainsKey($indexPath)){
                    $ix=Read-LedgerXml $indexPath;$declared=@{}
                    foreach($node in @($ix.SelectNodes('/Index/Schema/Fields/Field|/Index/Schema/Fields/Grouping|/Index/Schema/Fields/Copy'))){
                        $name=$node.GetAttribute('SystemName').Trim();if(-not $name){continue}
                        $parsed=$false;$value=$node.GetAttribute('Analyzed').Trim()
                        # A name declared twice with different flags is not one fact.
                        $state=if([bool]::TryParse($value,[ref]$parsed)){$parsed}else{'unstated'}
                        $declared[$name]=if($declared.ContainsKey($name) -and "$($declared[$name])" -cne "$state"){'unstated'}else{$state}
                    }
                    $extenders=@($ix.SelectNodes('/Index/Schema/Fields/Extension')|ForEach-Object {$_.GetAttribute('Type').Split(',')[0].Trim()}|Where-Object {$_})
                    $indexes[$indexPath]=@{declared=$declared;extenders=$extenders}
                }
                $index=$indexes[$indexPath]
            }
        }
        foreach($facet in $facets){
            $scanned++
            $field=$facet.GetAttribute('Field').Trim();$name=$facet.GetAttribute('Name')
            $offender=[ordered]@{facets=$where;facet=$name;field=$field;reason=$null}
            if(-not $field){$offender.reason='The facet names no field.'}
            elseif(-not $index){$offender.reason="The field cannot be resolved: $why."}
            elseif($index.declared.ContainsKey($field)){
                $state=$index.declared[$field]
                if($state -is [string]){$offender.reason='The index declares the field without an explicit Analyzed flag.'}
                elseif($state){$offender.reason='The index declares the field Analyzed="true".'}
            } else {
                $rule=Get-LedgerGeneratedAnalyzed $generated $index.extenders $field
                if($null -eq $rule){$offender.reason='The field is neither declared in the source index nor a generated field of its schema extender, so its Analyzed flag is unknown.'}
                elseif($rule[0] -is [bool]){if($rule[0]){$offender.reason="$($rule[1]) generates the field analysed."}}
                elseif($defaults -eq $true){}
                elseif($null -eq $defaults){$offender.reason="$($rule[1]) analyses the field unless /Globalsettings/Ecom/Indexing/DoNotAnalyzeDefaultFields is true, and no GlobalSettings layer states that key."}
                elseif($rule[0] -eq 'default-fields'){$offender.reason="$($rule[1]) generates the field analysed: /Globalsettings/Ecom/Indexing/DoNotAnalyzeDefaultFields is false."}
                else{$offender.reason="$($rule[1]) analyses the field when its value type is text and /Globalsettings/Ecom/Indexing/DoNotAnalyzeDefaultFields is false, as it is here; the field's value type, and whether the field exists at all, are not in Files."}
            }
            if($offender.reason){$offenders.Add($offender)}
        }
    }
    return @{value=$offenders.Count;scanned=$scanned;offenders=$offenders.ToArray();complete=$true}
}
function Get-LedgerQueryMacroObservation {
    param([string]$FilesPath,[string[]]$Files)
    $offenders=[Collections.Generic.List[object]]::new()
    foreach($file in $Files){
        $doc=Read-LedgerXml $file;$where=Get-LedgerRepositoryRelative $FilesPath $file
        foreach($node in @($doc.SelectNodes('//ConstantExpression'))){
            $value=$node.GetAttribute('Value').Trim()
            if($value -cmatch $script:LedgerMacroShape){$offenders.Add([ordered]@{query=$where;value=$value;reason='A macro-shaped value is stored as a constant and is compared as literal text.'})}
        }
    }
    return @{value=$offenders.Count;scanned=@($Files).Count;offenders=$offenders.ToArray();complete=$true}
}
function Get-LedgerRepositoryObservation {
    param($Binding,[string]$FilesPath)
    $files=Get-LedgerLocalFiles $Binding $FilesPath
    switch($Binding.handler){
        'files-facet-analyzed' {return Get-LedgerFacetAnalyzedObservation $Binding $FilesPath $files}
        'files-query-constant-macros' {return Get-LedgerQueryMacroObservation $FilesPath $files}
        default {throw 'No registered repository observation handler.'}
    }
}
