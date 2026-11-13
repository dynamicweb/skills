<#
.SYNOPSIS
READ-ONLY. Compare declared matrix columns, parent markers and every stored cell.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/matrix-fields.md. Local integrated SQL
SELECT only. The negative control alters an in-memory observation, never a target.
.EXAMPLE
. ./Pim.Matrix.ps1
#>
#Requires -Version 7.0
function Get-PimMatrixDeclaration {
    param($Build)
    $m=Get-LedgerField $Build 'expected.matrix'
    if(-not $m.categoryId -or $m.columns -isnot [array] -or $m.columns.Count -lt 1 -or $m.columns.Count -gt 6 -or $m.subjects -isnot [array] -or $m.subjects.Count -lt 1){throw [InvalidOperationException]::new('Nonempty matrix scope and one to six columns are required.')}
    $ids=@{};foreach($c in $m.columns){
        if(-not $c.id -or $ids.ContainsKey($c.id) -or $c.type -notin @('Text','Integer','Double','Link','List')){throw [InvalidOperationException]::new('Invalid or duplicate matrix column.')}
        $ids[$c.id]=$true
    }
    $subjects=@{};foreach($s in $m.subjects){
        foreach($key in @('productId','variantId','languageId','ownerCategoryId','ownerFieldId')){
            if(-not $s.ContainsKey($key) -or $s[$key] -isnot [string] -or ($key -ne 'variantId' -and -not $s[$key])){throw [InvalidOperationException]::new('Explicit product, variant, language and owning field are required.')}
        }
        $key=@($s.productId,$s.variantId,$s.languageId)|ConvertTo-Json -Compress
        if($subjects.ContainsKey($key) -or $s.ownerCategoryId -ceq $m.categoryId){throw [InvalidOperationException]::new('Duplicate subject or ambiguous matrix owner.')};$subjects[$key]=$true
        if($s.rows -isnot [array] -or $s.rows.Count -lt 1){throw [InvalidOperationException]::new('Empty matrices cannot prove applied values.')}
        for($i=0;$i -lt $s.rows.Count;$i++){
            $r=$s.rows[$i]
            if($r.sortOrder -isnot [long] -and $r.sortOrder -isnot [int]){throw [InvalidOperationException]::new('Row order must be an integer.')}
            if($r.sortOrder -ne $i -or $r.cells -isnot [Collections.IDictionary] -or $r.cells.Count -ne $ids.Count){throw [InvalidOperationException]::new('Rows must be zero based and declare exactly every column.')}
            foreach($c in $m.columns){
                if(-not $r.cells.Contains($c.id) -or $null -eq $r.cells[$c.id] -or $r.cells[$c.id] -is [bool] -or $r.cells[$c.id] -is [Collections.IEnumerable] -and $r.cells[$c.id] -isnot [string] -or "$($r.cells[$c.id])" -eq ''){throw [InvalidOperationException]::new('Each declared cell needs an explicit nonempty scalar value.')}
            }
        }
    }
    return $m
}
function Test-PimMatrixValue {
    param($Actual,$Expected,[string]$Type)
    if($null -eq $Actual){return $false}
    if($Type -in @('Integer','Double')){
        $a=[decimal]0;$e=[decimal]0;$culture=[Globalization.CultureInfo]::InvariantCulture
        $actualText=[Convert]::ToString($Actual,$culture);$expectedText=[Convert]::ToString($Expected,$culture)
        # The stored text is read as the platform writes it: a sign, digits and a decimal point.
        # Padding and an exponent (" 4e0 ") are another stored representation, not the same cell.
        $stored=[Globalization.NumberStyles]::AllowLeadingSign -bor [Globalization.NumberStyles]::AllowDecimalPoint
        if(-not [decimal]::TryParse($actualText,$stored,$culture,[ref]$a) -or -not [decimal]::TryParse($expectedText,[Globalization.NumberStyles]::Float,$culture,[ref]$e)){return $false}
        return $a -eq $e -and ($Type -ne 'Integer' -or [decimal]::Truncate($a) -eq $a)
    }
    return [string]$Actual -ceq [string]$Expected
}
function Get-PimMatrixSubjectKey {
    param($Row)
    return ("$($Row.productId)","$($Row.variantId)","$($Row.languageId)") -join '/'
}
function Format-PimMatrixValue {
    param($Value)
    if($null -eq $Value){return 'none'}
    return "'"+[Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture)+"'"
}
function Test-PimMatrixObservation {
    param($Matrix,$Observation,[ValidateSet('columns','parent-marker','cells','negative-control')][string]$Aspect)
    $off=[Collections.Generic.List[string]]::new();$scanned=0
    if($Aspect -eq 'negative-control'){
        $green=Test-PimMatrixObservation $Matrix $Observation 'cells'
        if($green.value -ne 1){return $green}
        $red=$Observation|ConvertTo-Json -Depth 60|ConvertFrom-Json -AsHashtable
        # A guaranteed different value, including for numeric cells, tests this same comparator.
        $red.subjects[0].cells[0].value=[string]$red.subjects[0].cells[0].value+'__ledger_altered_cell__'
        $changed=Test-PimMatrixObservation $Matrix $red 'cells'
        return @{value=[int]($changed.value -eq 0);scanned=$green.scanned;offenders=@();complete=$true}
    }
    $declared=@{};foreach($s in $Matrix.subjects){$declared[(Get-PimMatrixSubjectKey $s)]=$s}
    if($Aspect -eq 'columns'){
        Assert-LedgerFields @($Observation.categories) @('id','type')
        Assert-LedgerFields @($Observation.columns) @('id','type','typeId','presentation')
        if($Observation.categories.Count -ne 1 -or $Observation.categories[0].id -cne $Matrix.categoryId -or $Observation.categories[0].type -ne 3){$off.Add('Matrix category is absent or is not CategoryType 3.')}
        if($Observation.columns.Count -ne $Matrix.columns.Count){$off.Add("Stored column count differs from the declaration: observed $($Observation.columns.Count), expected $($Matrix.columns.Count).")}
        foreach($c in $Matrix.columns){
            $matches=@($Observation.columns|Where-Object {$_.id -ceq $c.id})
            if($matches.Count -ne 1 -or $matches[0].type -cne $c.type -or $matches[0].typeId -notin @(1,6,7,8,10,11,12,13,15) -or ($matches[0].type -eq 'List' -and [string]$matches[0].presentation -ne '2')){
                $seen=if($matches.Count -eq 1){"$($matches[0].type) (type id $($matches[0].typeId), presentation $(Format-PimMatrixValue $matches[0].presentation))"}else{"$($matches.Count) column(s)"}
                $off.Add("Column differs: $($c.id): observed $seen, expected $($c.type)")
            }
            $scanned++
        }
        # The owner field is a Matrix field linked to this matrix category; only the platform makes that link.
        Assert-LedgerFields @($Observation.owners) @('categoryId','id','type','matrixCategoryId')
        foreach($owner in @($Matrix.subjects|ForEach-Object {"$($_.ownerCategoryId)|$($_.ownerFieldId)"}|Sort-Object -Unique)){
            $cat,$field=$owner.Split('|',2)
            $rows=@($Observation.owners|Where-Object {$_.categoryId -ceq $cat -and $_.id -ceq $field})
            if($rows.Count -ne 1){$off.Add("Owner field $cat/$($field): observed $($rows.Count) definition(s), expected 1");continue}
            if($rows[0].type -cne 'Matrix' -or $rows[0].matrixCategoryId -cne $Matrix.categoryId){
                $off.Add("Owner field $cat/$($field): observed type $(Format-PimMatrixValue $rows[0].type) linked to $(Format-PimMatrixValue $rows[0].matrixCategoryId), expected 'Matrix' linked to '$($Matrix.categoryId)'")
            }
            $scanned++
        }
    }else{
        if($Observation.subjects.Count -ne $Matrix.subjects.Count){$off.Add('Subject enumeration differs.')}
        for($i=0;$i -lt $Matrix.subjects.Count;$i++){
            $s=$Matrix.subjects[$i];$observed=$Observation.subjects[$i]
            if(-not $observed){$off.Add('Subject observation is absent.');continue}
            if($Aspect -eq 'parent-marker'){
                Assert-LedgerFields @($observed.parents) @('fieldId','categoryId','row','value','referenceCategoryId')
                if($observed.parents.Count -ne 1){$off.Add("Expected exactly one parent marker: $($s.productId): observed $($observed.parents.Count)")}else{
                    $p=$observed.parents[0]
                    if($p.fieldId -cne $s.ownerFieldId -or $p.categoryId -cne $s.ownerCategoryId -or $p.row -ne 0 -or $null -ne $p.value -or $p.referenceCategoryId -cne $Matrix.categoryId){
                        $off.Add("Parent marker differs: $($s.productId): observed $($p.categoryId)/$($p.fieldId) row $($p.row) value $(Format-PimMatrixValue $p.value) reference $(Format-PimMatrixValue $p.referenceCategoryId), expected $($s.ownerCategoryId)/$($s.ownerFieldId) row 0 value none reference '$($Matrix.categoryId)'")
                    }
                }
                $scanned++
            }else{
                Assert-LedgerFields @($observed.cells) @('fieldId','categoryId','row','value','referenceCategoryId')
                if($observed.cells.Count -ne $s.rows.Count*$Matrix.columns.Count){$off.Add("Cell count differs: $($s.productId): observed $($observed.cells.Count), expected $($s.rows.Count*$Matrix.columns.Count)")}
                foreach($r in $s.rows){foreach($c in $Matrix.columns){
                    $cells=@($observed.cells|Where-Object {$_.row -eq $r.sortOrder -and $_.fieldId -ceq $c.id -and $_.categoryId -ceq $Matrix.categoryId})
                    if($cells.Count -ne 1 -or $cells[0].referenceCategoryId -or -not (Test-PimMatrixValue $cells[0].value $r.cells[$c.id] $c.type)){
                        $seen=if($cells.Count -eq 1){Format-PimMatrixValue $cells[0].value}else{"$($cells.Count) cell(s)"}
                        $off.Add($s.productId+'/'+$s.variantId+'/'+$s.languageId+':'+$r.sortOrder+':'+$c.id+": observed $seen, expected $(Format-PimMatrixValue $r.cells[$c.id])")
                    }
                    $scanned++
                }}
            }
        }
        # The whole matrix category, not only the declared subjects: rows on an undeclared product,
        # variant or language, and a marker in another owner field, are seen here.
        if($Aspect -eq 'parent-marker'){
            Assert-LedgerFields @($Observation.markers) @('productId','variantId','languageId','categoryId','fieldId','markers')
            $total=0
            foreach($m in $Observation.markers){
                $key=Get-PimMatrixSubjectKey $m;$s=$declared[$key];$total+=[int]$m.markers
                if(-not $s){$off.Add("Undeclared parent marker: $key in $($m.categoryId)/$($m.fieldId): observed $($m.markers), expected 0");continue}
                if($m.categoryId -cne $s.ownerCategoryId -or $m.fieldId -cne $s.ownerFieldId){$off.Add("Parent marker in another owner field: $key in $($m.categoryId)/$($m.fieldId), expected $($s.ownerCategoryId)/$($s.ownerFieldId)")}
            }
            if($total -ne $Matrix.subjects.Count){$off.Add("Markers referencing '$($Matrix.categoryId)': observed $total, expected $($Matrix.subjects.Count)")}
        }else{
            Assert-LedgerFields @($Observation.census) @('productId','variantId','languageId','cells')
            $total=0
            foreach($row in $Observation.census){
                $key=Get-PimMatrixSubjectKey $row;$total+=[int]$row.cells
                if(-not $declared.ContainsKey($key)){$off.Add("Undeclared matrix rows: $($key): observed $($row.cells) cell(s), expected 0")}
            }
            $want=0;foreach($s in $Matrix.subjects){$want+=$s.rows.Count*$Matrix.columns.Count}
            if($total -ne $want){$off.Add("Cells in '$($Matrix.categoryId)': observed $total, expected $want")}
        }
    }
    return @{value=[int]($scanned -gt 0 -and $off.Count -eq 0);scanned=$scanned;offenders=$off.ToArray();complete=$true}
}
function Get-PimMatrixObservation {
    param([string]$Aspect,$Build,[string]$Server,[string]$Database)
    $m=Get-PimMatrixDeclaration $Build
    function Quote-MatrixSql([string]$Value){return "N'"+$Value.Replace("'","''")+"'"}
    function Read-MatrixSql([string]$Query){
        # SQL can emit no JSON row for an empty result. COALESCE makes a completed
        # empty read explicit, so absence FAILs instead of becoming UNVERIFIED.
        $json=@(Invoke-Sqlcmd-Rows -Server $Server -Database $Database -Query ("SELECT COALESCE(($Query FOR JSON PATH, INCLUDE_NULL_VALUES),N'[]')")) -join ''
        if(-not $json){throw [InvalidOperationException]::new('No complete SQL JSON observation.')}
        return ,(ConvertFrom-Json -InputObject $json -AsHashtable -NoEnumerate)
    }
    $category=Quote-MatrixSql $m.categoryId
    $obs=@{categories=@();columns=@();owners=@();subjects=@();markers=@();census=@()}
    $identity='FieldValueProductId productId,FieldValueProductVariantId variantId,FieldValueProductLanguageId languageId'
    $group='FieldValueProductId,FieldValueProductVariantId,FieldValueProductLanguageId'
    if($Aspect -eq 'columns'){
        $obs.categories=Read-MatrixSql "SELECT CategoryId id,CategoryType type FROM EcomProductCategory WHERE CategoryId=$category"
        $obs.columns=Read-MatrixSql "SELECT f.FieldId id,t.FieldTypeDW type,f.FieldType typeId,f.FieldPresentationType presentation FROM EcomProductCategoryField f LEFT JOIN EcomFieldType t ON t.FieldTypeId=f.FieldType WHERE f.FieldCategoryId=$category"
        foreach($owner in @($m.subjects|ForEach-Object {"$($_.ownerCategoryId)|$($_.ownerFieldId)"}|Sort-Object -Unique)){
            $cat,$field=$owner.Split('|',2)
            $obs.owners+=@(Read-MatrixSql "SELECT o.FieldCategoryId categoryId,o.FieldId id,t.FieldTypeDW type,o.FieldMatrixAttributeGroupId matrixCategoryId FROM EcomProductCategoryField o LEFT JOIN EcomFieldType t ON t.FieldTypeId=o.FieldType WHERE o.FieldCategoryId=$(Quote-MatrixSql $cat) AND o.FieldId=$(Quote-MatrixSql $field)")
        }
    }else{
        foreach($s in $m.subjects){
            $product=Quote-MatrixSql $s.productId;$variant=Quote-MatrixSql $s.variantId;$lang=Quote-MatrixSql $s.languageId
            $owner=Quote-MatrixSql $s.ownerCategoryId;$field=Quote-MatrixSql $s.ownerFieldId
            $select='SELECT FieldValueFieldId fieldId,FieldValueFieldCategoryId categoryId,FieldValueSortOrder [row],FieldValueValue value,FieldValueReferenceCategoryId referenceCategoryId FROM EcomProductCategoryFieldValue'
            $where=" WHERE FieldValueProductId=$product AND FieldValueProductVariantId=$variant AND FieldValueProductLanguageId=$lang"
            $subject=@{parents=@();cells=@()}
            if($Aspect -eq 'parent-marker'){$subject.parents=Read-MatrixSql ($select+$where+" AND FieldValueFieldCategoryId=$owner AND FieldValueFieldId=$field")}
            else{$subject.cells=Read-MatrixSql ($select+$where+" AND FieldValueFieldCategoryId=$category")}
            $obs.subjects+=,$subject
        }
        if($Aspect -eq 'parent-marker'){
            $obs.markers=Read-MatrixSql "SELECT $identity,FieldValueFieldCategoryId categoryId,FieldValueFieldId fieldId,COUNT(*) markers FROM EcomProductCategoryFieldValue WHERE FieldValueReferenceCategoryId=$category GROUP BY $group,FieldValueFieldCategoryId,FieldValueFieldId"
        }else{
            $obs.census=Read-MatrixSql "SELECT $identity,COUNT(*) cells FROM EcomProductCategoryFieldValue WHERE FieldValueFieldCategoryId=$category GROUP BY $group"
        }
    }
    return Test-PimMatrixObservation $m $obs $Aspect
}
