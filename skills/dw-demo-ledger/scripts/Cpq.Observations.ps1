<#
.SYNOPSIS
READ-ONLY. Compare version-scoped CPQ observations with independent declarations.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/cpq-observations.md. Requires Cpq.Json.ps1.
Missing scope or unsupported semantics returns incomplete evidence, never a passing count.
.PARAMETER Expected
Independent build.expected.cpq declaration. Never generate it from the target being checked.
.PARAMETER Snapshot
Complete normalized observation; SQL reader only supplies stored facts, not runtime outcomes.
.EXAMPLE
Test-CpqObservation -Aspect conditions.dialect -Expected $declared -Snapshot $read
#>
#Requires -Version 7.0
function Test-CpqObservation {
    param([string]$Aspect,$Expected,$Snapshot)
    $off=[Collections.Generic.List[object]]::new();$scanned=0;$complete=$true
    try {
        if(-not $Expected -or -not $Snapshot -or $Snapshot.complete -ne $true){throw [InvalidOperationException]::new('Incomplete CPQ scope.')}
        if($Expected.modelId -le 0 -or $Expected.versionId -le 0 -or $Snapshot.modelId -ne $Expected.modelId -or $Snapshot.versionId -ne $Expected.versionId){throw [InvalidOperationException]::new('Unbound model/version observation.')}
        $rows=$Snapshot.rows
        foreach($table in @('CPQModel','CPQModelVersion','CPQGroup','CPQInput','CPQInputRule','CPQBOMRule','CPQPriceRule','CPQRouteRule','CPQModelVariable','CPQOutputRule','CPQOutputAction')){
            if($rows[$table] -isnot [array]){throw [InvalidOperationException]::new('Missing complete table scope.')}
        }
        if($rows.CPQModel.Count -ne 1 -or $rows.CPQModel[0].ModelId -ne $Expected.modelId -or $rows.CPQModelVersion.Count -ne 1 -or $rows.CPQModelVersion[0].ModelVersionId -ne $Expected.versionId -or $rows.CPQModelVersion[0].ModelVersionModelId -ne $Expected.modelId){throw [InvalidOperationException]::new('Observed model/version ownership is not established.')}
        $inputs=@($rows.CPQInput | ForEach-Object {$_.InputName});$variables=@($rows.CPQModelVariable | ForEach-Object {$_.ModelVariableName});$groups=@($rows.CPQGroup | ForEach-Object {$_.GroupName})
        $conditionFields=@{CPQGroup='GroupCondition';CPQInputRule='InputRuleConditions';CPQBOMRule='BOMRuleConditions';CPQPriceRule='Conditions';CPQRouteRule='RouteRuleConditions';CPQOutputRule='OutputRuleConditions'}
        switch($Aspect) {
            'installation.schema' {
                $schema=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../assets/cpq-columns.json') -Raw | ConvertFrom-Json -AsHashtable
                if($Snapshot.schema -isnot [array]){throw [InvalidOperationException]::new('Missing schema inventory.')}
                foreach($table in $schema.Keys){foreach($column in $schema[$table].Keys){
                    $scanned++;$found=@($Snapshot.schema | Where-Object {$_.TABLE_NAME -ceq $table -and $_.COLUMN_NAME -ceq $column})
                    if($found.Count -ne 1 -or $found[0].DATA_TYPE -cne $schema[$table][$column]){$off.Add(@{table=$table;column=$column;reason='Missing, ambiguous or wrong SQL type.'})}
                }}
            }
            'conditions.dialect' {
                foreach($table in $conditionFields.Keys){foreach($row in $rows[$table]){
                    $field=$conditionFields[$table]
                    if(-not $row.Contains($field)){throw [InvalidOperationException]::new('Missing condition field.')}
                    # An empty condition states nothing to judge; it is not a subject.
                    if([string]::IsNullOrWhiteSpace($row[$field])){continue}
                    $scanned++
                    try{Assert-CpqConditions $row[$field] $inputs $variables $groups}catch{$off.Add(@{table=$table;field=$field;reason='Invalid condition shape, operator or reference.'})}
                }}
            }
            'input-rules.loader' {
                foreach($rule in $rows.CPQInputRule){
                    foreach($key in @('InputRuleEnabled','InputRuleType','InputRuleSeq','InputRuleGroupId')){if(-not $rule.Contains($key)){throw [InvalidOperationException]::new('Incomplete rule row.')}}
                    if(-not $rule.InputRuleEnabled){continue};$scanned++
                    $g=@($rows.CPQGroup | Where-Object {$_.GroupId -eq $rule.InputRuleGroupId})
                    $seq=@($rows.CPQInputRule | Where-Object {$_.InputRuleEnabled -and $_.InputRuleGroupId -eq $rule.InputRuleGroupId -and $_.InputRuleSeq -eq $rule.InputRuleSeq})
                    if($rule.InputRuleType -cne 'CPQOptions' -or $g.Count -ne 1 -or $g[0].GroupMode -cne 'input_rule' -or $g[0].GroupEnabled -ne $true -or $null -eq $rule.InputRuleSeq -or $seq.Count -ne 1){$off.Add(@{id=$rule.InputRuleId;reason='Wrong loader, disabled/wrong group or ambiguous order.'})}
                }
            }
            'inputs.declaration' {
                if($Expected.inputs -isnot [array] -or -not $Expected.inputs.Count){throw [InvalidOperationException]::new('Declare exact stored inputs independently.')}
                $fields=@('InputName','InputGroupId','InputType','InputRequired','InputVisible','InputReadOnly','InputEnabled','InputSeq','InputDefaultValue','InputOptions','InputSettings')
                if($rows.CPQInput.Count -ne $Expected.inputs.Count){$off.Add(@{reason='Input scope differs.'})}
                foreach($want in $Expected.inputs){
                    $scanned++;$found=@($rows.CPQInput | Where-Object {$_.InputName -ceq $want.InputName})
                    if($found.Count -ne 1){$off.Add(@{reason='Missing or duplicate input.'});continue}
                    foreach($key in $fields){
                        if(-not $want.Contains($key) -or -not $found[0].Contains($key)){throw [InvalidOperationException]::new('Incomplete input declaration/projection.')}
                        $a=$want[$key];$b=$found[0][$key]
                        if($key -in @('InputOptions','InputSettings')){$a=Read-CpqValue $a;$b=Read-CpqValue $b}
                        if((ConvertTo-CpqObservationJson $a) -cne (ConvertTo-CpqObservationJson $b)){$off.Add(@{input=$want.InputName;field=$key;reason='Stored input differs.'})}
                    }
                }
            }
            'model-versions.integrity' {
                if($rows.CPQModel.Count -ne 1 -or $rows.CPQModel[0].ModelId -ne $Expected.modelId -or $rows.CPQModelVersion.Count -ne 1 -or $rows.CPQModelVersion[0].ModelVersionId -ne $Expected.versionId -or $rows.CPQModelVersion[0].ModelVersionModelId -ne $Expected.modelId){$off.Add(@{reason='Model/version ownership differs.'})}
                if(-not $Expected.children){throw [InvalidOperationException]::new('Declare child identities independently.')}
                $keys=@{CPQGroup='GroupId';CPQInput='InputId';CPQInputRule='InputRuleId';CPQBOMRule='BOMRuleId';CPQPriceRule='CPQPriceRuleId';CPQRouteRule='RouteRuleId';CPQModelVariable='ModelVariableId';CPQOutputRule='OutputRuleId';CPQOutputAction='OutputActionId'}
                foreach($table in $keys.Keys){
                    if($Expected.children[$table] -isnot [array]){throw [InvalidOperationException]::new('Incomplete child declaration.')}
                    $actual=@($rows[$table] | ForEach-Object {$_[$keys[$table]]} | Sort-Object);$want=@($Expected.children[$table] | Sort-Object)
                    $scanned+=$actual.Count
                    if((ConvertTo-CpqObservationJson $actual) -cne (ConvertTo-CpqObservationJson $want)){$off.Add(@{table=$table;reason='Declared child identities differ.'})}
                }
                foreach($names in @(@{values=$inputs},@{values=$variables},@{values=$groups})){
                    if(@($names.values | Where-Object {[string]::IsNullOrWhiteSpace($_)}).Count -or @($names.values | Sort-Object -Unique).Count -ne $names.values.Count){$off.Add(@{reason='Missing or duplicate symbolic names.'})}
                }
                foreach($g in $rows.CPQGroup){
                    if($g.GroupModelVersionId -ne $Expected.versionId -or ([string]$g.GroupParentId -notin @('','0') -and $g.GroupParentId -notin $rows.CPQGroup.GroupId)){$off.Add(@{reason='Group ownership or parent differs.'})}
                    $visited=[Collections.Generic.HashSet[string]]::new();$cursor=$g
                    while($cursor -and [string]$cursor.GroupParentId -notin @('','0')){
                        if(-not $visited.Add([string]$cursor.GroupId)){$off.Add(@{reason='Cyclic group parent.'});break}
                        $cursor=@($rows.CPQGroup | Where-Object {$_.GroupId -eq $cursor.GroupParentId})[0]
                    }
                }
                foreach($table in $keys.Keys){foreach($row in $rows[$table]){
                    foreach($key in $row.Keys){
                        if($key -match 'GroupId$' -and $key -ne 'GroupId' -and $row[$key] -notin $rows.CPQGroup.GroupId){$off.Add(@{table=$table;reason='Child has another group.'})}
                        if($key -match 'ModelVersionId$' -and $row[$key] -ne $Expected.versionId){$off.Add(@{table=$table;reason='Child has another version.'})}
                        if($key -match 'Conditions$|^GroupCondition$|Actions(?:Else)?$|BomItems$|RouteItems$|DataParameters$|^(Margin|Discount)$'){
                            try{
                                $value=$row[$key]
                                if($key -notin @('Margin','Discount')){$value=Read-CpqValue $value}
                                Assert-CpqReferences $value $inputs $variables $groups
                            }catch{$off.Add(@{table=$table;field=$key;reason='Malformed JSON or unresolved reference.'})}
                        }
                    }
                }}
            }
            'bom.references' {
                if($rows.EcomProducts -isnot [array]){throw [InvalidOperationException]::new('Catalogue identifiers unavailable.')}
                foreach($rule in $rows.CPQBOMRule){
                    foreach($line in (Read-CpqValue $rule.BOMRuleBomItems)){
                        $scanned++
                        if($line.no -notin $rows.EcomProducts.ProductNumber -or $line.type -cne 'Item'){$off.Add(@{reason='Unknown SKU or BOM item type.'})}
                        try{Assert-CpqReferences $line $inputs $variables $groups}catch{$off.Add(@{reason='Unresolved BOM expression.'})}
                    }
                }
                # Static references alone cannot prove dynamic quantities or non-overlap.
                $complete=$false
            }
            'lookups.scope' {
                foreach($input in $rows.CPQInput | Where-Object {$_.InputDataSource}){
                    $scanned++
                    try{Assert-CpqReferences (Read-CpqValue $input.InputDataParameters) $inputs $variables $groups}catch{$off.Add(@{reason='Invalid lookup parameters or references.'})}
                }
                # Do not execute stored SQL or bless free-text templates as typed parameters.
                $complete=$false
            }
            'page.binding' {
                if(-not $Expected.page -or -not $Snapshot.pageScope){throw [InvalidOperationException]::new('Complete page/navigation/tab/theme projection unavailable.')}
                $scanned=1
                if((ConvertTo-CpqObservationJson $Expected.page) -cne (ConvertTo-CpqObservationJson $Snapshot.pageScope)){$off.Add(@{reason='Page version, navigation, tabs or theme differ.'})}
            }
            'pricing.scope' {
                if(-not $Expected.pricing -or -not $Snapshot.pricing){throw [InvalidOperationException]::new('Price context unavailable.')}
                foreach($key in @('shopId','languageId','currency','priceBasis','customerContext','decimalPlaces','rounding')){
                    if(-not $Expected.pricing.Contains($key) -or -not $Snapshot.pricing.Contains($key)){throw [InvalidOperationException]::new('Price context not observed.')}
                    $scanned++
                    if((ConvertTo-CpqObservationJson $Expected.pricing[$key]) -cne (ConvertTo-CpqObservationJson $Snapshot.pricing[$key])){$off.Add(@{field=$key;reason='Price context differs.'})}
                }
            }
            'installation.loaded' {
                if($Snapshot.loadedAssemblies -isnot [array] -or $Expected.assemblies -isnot [array] -or -not $Expected.assemblies.Count){throw [InvalidOperationException]::new('Runtime-loaded hashes unavailable.')}
                $scanned=$Expected.assemblies.Count
                $actual=@($Snapshot.loadedAssemblies | Sort-Object name);$want=@($Expected.assemblies | Sort-Object name)
                if((ConvertTo-CpqObservationJson $actual) -cne (ConvertTo-CpqObservationJson $want) -or @($actual.name | Sort-Object -Unique).Count -ne $actual.Count){$off.Add(@{reason='Loaded identities differ or duplicate.'})}
            }
            'erp.requirements' {
                if(-not $Expected.erp -or -not $Snapshot.erp){throw [InvalidOperationException]::new('ERP configuration unavailable.')}
                $scanned=1
                if((ConvertTo-CpqObservationJson $Expected.erp) -cne (ConvertTo-CpqObservationJson $Snapshot.erp)){$off.Add(@{reason='Declared connector/company/endpoint differs.'})}
            }
            default {throw [InvalidOperationException]::new('No stored observation for this behavioural check.')}
        }
    } catch [InvalidOperationException] {$complete=$false}
    catch {$off.Add(@{reason='Malformed stored observation.'})}
    return @{complete=$complete;scanned=$scanned;offenders=@($off.ToArray());value=@{subjects=$scanned;invalid=$off.Count}}
}
function Get-CpqLedgerObservation {
    param($Check,$Build,[string]$Server,[string]$Database)
    $expected=$Build.expected.cpq
    if(-not $expected){throw [InvalidOperationException]::new('Declare build.expected.cpq.')}
    $snapshot=Get-CpqSqlSnapshot $Server $Database $expected.modelId $expected.versionId
    return Test-CpqObservation $Check.id.Substring(4) $expected $snapshot
}
