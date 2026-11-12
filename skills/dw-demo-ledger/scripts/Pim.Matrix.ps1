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
        $style=[Globalization.NumberStyles]::Float
        if(-not [decimal]::TryParse($actualText,$style,$culture,[ref]$a) -or -not [decimal]::TryParse($expectedText,$style,$culture,[ref]$e)){return $false}
        return $a -eq $e -and ($Type -ne 'Integer' -or [decimal]::Truncate($a) -eq $a)
    }
    return [string]$Actual -ceq [string]$Expected
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
    if($Aspect -eq 'columns'){
        Assert-LedgerFields @($Observation.categories) @('id','type')
        Assert-LedgerFields @($Observation.columns) @('id','type','typeId','presentation')
        if($Observation.categories.Count -ne 1 -or $Observation.categories[0].id -cne $Matrix.categoryId -or $Observation.categories[0].type -ne 3){$off.Add('Matrix category is absent or is not CategoryType 3.')}
        if($Observation.columns.Count -ne $Matrix.columns.Count){$off.Add('Stored column count differs from the declaration.')}
        foreach($c in $Matrix.columns){
            $matches=@($Observation.columns|Where-Object {$_.id -ceq $c.id})
            if($matches.Count -ne 1 -or $matches[0].type -cne $c.type -or $matches[0].typeId -notin @(1,6,7,8,10,11,12,13,15) -or ($matches[0].type -eq 'List' -and [string]$matches[0].presentation -ne '2')){$off.Add('Column differs: '+$c.id)}
            $scanned++
        }
    }else{
        if($Observation.subjects.Count -ne $Matrix.subjects.Count){$off.Add('Subject enumeration differs.')}
        for($i=0;$i -lt $Matrix.subjects.Count;$i++){
            $s=$Matrix.subjects[$i];$observed=$Observation.subjects[$i]
            if(-not $observed){$off.Add('Subject observation is absent.');continue}
            if($Aspect -eq 'parent-marker'){
                Assert-LedgerFields @($observed.parents) @('fieldId','categoryId','row','value','referenceCategoryId')
                if($observed.parents.Count -ne 1){$off.Add('Expected exactly one parent marker: '+$s.productId)}else{
                    $p=$observed.parents[0]
                    if($p.fieldId -cne $s.ownerFieldId -or $p.categoryId -cne $s.ownerCategoryId -or $p.row -ne 0 -or $null -ne $p.value -or $p.referenceCategoryId -cne $Matrix.categoryId){$off.Add('Parent marker differs: '+$s.productId)}
                }
                $scanned++
            }else{
                Assert-LedgerFields @($observed.cells) @('fieldId','categoryId','row','value','referenceCategoryId')
                if($observed.cells.Count -ne $s.rows.Count*$Matrix.columns.Count){$off.Add('Cell count differs: '+$s.productId)}
                foreach($r in $s.rows){foreach($c in $Matrix.columns){
                    $cells=@($observed.cells|Where-Object {$_.row -eq $r.sortOrder -and $_.fieldId -ceq $c.id -and $_.categoryId -ceq $Matrix.categoryId})
                    if($cells.Count -ne 1 -or $cells[0].referenceCategoryId -or -not (Test-PimMatrixValue $cells[0].value $r.cells[$c.id] $c.type)){$off.Add($s.productId+'/'+$s.variantId+'/'+$s.languageId+':'+$r.sortOrder+':'+$c.id)}
                    $scanned++
                }}
            }
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
    $obs=@{categories=@();columns=@();subjects=@()}
    if($Aspect -eq 'columns'){
        $obs.categories=Read-MatrixSql "SELECT CategoryId id,CategoryType type FROM EcomProductCategory WHERE CategoryId=$category"
        $obs.columns=Read-MatrixSql "SELECT f.FieldId id,t.FieldTypeDW type,f.FieldType typeId,f.FieldPresentationType presentation FROM EcomProductCategoryField f LEFT JOIN EcomFieldType t ON t.FieldTypeId=f.FieldType WHERE f.FieldCategoryId=$category"
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
    }
    return Test-PimMatrixObservation $m $obs $Aspect
}
