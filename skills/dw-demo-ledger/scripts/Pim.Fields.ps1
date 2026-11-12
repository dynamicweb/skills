<#
.SYNOPSIS
READ-ONLY. PIM observation helpers; definitions only on import.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. Preserves declared-field and relation assertions without a database write. SQL reads need no cache flush. Caller supplies all paths and connections.
.EXAMPLE
. ./Pim.Fields.ps1
#>
#Requires -Version 7.0
$script:PimAttributeKindTypes = @{
    'measure'      = @(7)
    'decimal'      = @(7)
    'count'        = @(6)
    'choice'       = @(15)
    'multi-choice' = @(15)
    'flag'         = @(3)
    'date'         = @(4, 5)
    'text'         = @(1, 10, 11, 12, 13)
    'code'         = @(1, 10, 11, 12, 13)
    'long-text'    = @(2)
    'rich-text'    = @(14)
    'link'         = @(8)
    'file'         = @(9)
    'range'        = @(16)
    'computed'     = @()
}
# List presentation: 1 radio, 2 dropdown, 3 multi-select list, 4 checkbox list, 5 tag cloud.
$script:PimSinglePresentation = @(1, 2)
$script:PimMultiPresentation  = @(3, 4, 5)
$script:PimTokenPattern = '^[A-Za-z0-9_-]+$'
$script:PimIdLikePattern = '^[A-Za-z0-9_-]+%?$'


function Test-PimOp {
    [CmdletBinding()]
    param([int]$Measured, [string]$Op, [int]$Value)
    switch ($Op) {
        'ge' { return $Measured -ge $Value }
        'le' { return $Measured -le $Value }
        'eq' { return $Measured -eq $Value }
    }
    throw "unknown op '$Op'"
}

function Expand-PimSql {
    [CmdletBinding()]
    param([string]$Sql, $Build)
    foreach ($p in @(@('{lang}', "$($Build.defaultLanguage)"), @('{pimShop}', "$($Build.pimShop)"))) {
        if ($Sql.Contains($p[0])) {
            # An undeclared input is missing evidence (UNVERIFIED); a declared value that is not a plain id stays an error.
            if (-not $p[1]) { throw [InvalidOperationException]::new("token $($p[0]) is not declared in the build file") }
            if ($p[1] -notmatch $script:PimTokenPattern) { throw "token $($p[0]) has no plain-id value in the build file" }
            $Sql = $Sql.Replace($p[0], $p[1])
        }
    }
    if ($Sql.Contains('{inScope}')) {
        $clause = ''
        foreach ($x in @($Build.productScope.exclude)) {
            if (-not $x) { continue }
            if ("$($x.idLike)" -notmatch $script:PimIdLikePattern) { throw "productScope exclusion '$($x.idLike)' is not a plain id prefix" }
            $clause += " AND p.ProductId NOT LIKE N'$($x.idLike)'"
        }
        $Sql = $Sql.Replace('{inScope}', $clause)
    }
    return $Sql
}

function Get-PimStoredField {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Server, [Parameter(Mandatory)][string]$Database)
    $sql = @'
SELECT CAST(f.FieldCategoryId AS nvarchar(100)) + N'|' + CAST(f.FieldId AS nvarchar(100)) + N'|' +
  CAST(ISNULL(f.FieldType,0) AS nvarchar(10)) + N'|' + CAST(ISNULL(f.FieldPresentationType,0) AS nvarchar(10)) + N'|' +
  CAST(ISNULL(f.FieldValueConversionGroupId,0) AS nvarchar(10)) + N'|' + CAST(ISNULL(f.FieldValueConversionPreset,0) AS nvarchar(10)) + N'|' +
  CAST(ISNULL(CAST(f.FieldRequired AS int),0) AS nvarchar(2)) + N'|' + CAST(ISNULL(CAST(f.FieldAllowChangesAcrossLanguages AS int),0) AS nvarchar(2)) + N'|' +
  CAST(ISNULL(CAST(f.FieldAllowChangesAcrossVariants AS int),0) AS nvarchar(2)) + N'|' +
  CAST((SELECT COUNT(*) FROM EcomFieldOption o WHERE o.FieldOptionFieldId IN (N'ProductCategory|' + f.FieldCategoryId + N'|' + f.FieldId, N'ProductCategory|reference_category|' + f.FieldId)) AS nvarchar(10)) + N'|' +
  CAST((SELECT COUNT(*) FROM EcomProductCategoryFieldValue v WHERE v.FieldValueFieldCategoryId = f.FieldCategoryId AND v.FieldValueFieldId = f.FieldId AND ISNULL(CAST(v.FieldValueValue AS nvarchar(max)),N'') <> N'') AS nvarchar(10)) + N'|' +
  CASE WHEN ISNULL(t.FieldTypeProvider,N'') <> N'' THEN N'1' ELSE N'0' END + N'|' +
  CAST((SELECT COUNT(*) FROM EcomProductCategoryFieldGroupValue g WHERE g.FieldValueFieldCategoryId = f.FieldCategoryId AND g.FieldValueFieldId = f.FieldId AND ISNULL(CAST(g.FieldValueValue AS nvarchar(max)),N'') <> N'' AND
    (EXISTS (SELECT 1 FROM EcomGroupProductRelation r WHERE r.GroupProductRelationGroupId = g.FieldValueGroupId) OR
     EXISTS (SELECT 1 FROM EcomGroupRelations c JOIN EcomGroupProductRelation r ON r.GroupProductRelationGroupId = c.GroupRelationsGroupId WHERE c.GroupRelationsParentId = g.FieldValueGroupId))) AS nvarchar(10))
FROM EcomProductCategoryField f LEFT JOIN EcomFieldType t ON t.FieldTypeId = f.FieldType
WHERE f.FieldCategoryId <> N'reference_category'
UNION ALL
SELECT N'|' + CAST(p.ProductFieldSystemName AS nvarchar(100)) + N'|' +
  CAST(ISNULL(p.ProductFieldTypeId,0) AS nvarchar(10)) + N'|' + CAST(ISNULL(p.ProductFieldListPresentationType,0) AS nvarchar(10)) + N'|' +
  CAST(ISNULL(p.ProductFieldValueConversionGroupId,0) AS nvarchar(10)) + N'|' + CAST(ISNULL(p.ProductFieldValueConversionPreset,0) AS nvarchar(10)) + N'|' +
  CAST(ISNULL(CAST(p.ProductFieldRequired AS int),0) AS nvarchar(2)) + N'|' + CAST(ISNULL(CAST(p.ProductFieldAllowChangesAcrossLanguages AS int),0) AS nvarchar(2)) + N'|' +
  CAST(ISNULL(CAST(p.ProductFieldAllowChangesAcrossVariants AS int),0) AS nvarchar(2)) + N'|' +
  CAST((SELECT COUNT(*) FROM EcomFieldOption o WHERE o.FieldOptionFieldId = p.ProductFieldSystemName) AS nvarchar(10)) + N'|-1|' +
  CASE WHEN ISNULL(t.FieldTypeProvider,N'') <> N'' THEN N'1' ELSE N'0' END + N'|0'
FROM EcomProductField p LEFT JOIN EcomFieldType t ON t.FieldTypeId = p.ProductFieldTypeId
'@
    $out = @{}
    foreach ($line in @(Invoke-Sqlcmd-Rows -Server $Server -Database $Database -Query ($sql -replace '\s+', ' '))) {
        $p = "$line".Split('|')
        if ($p.Count -lt 13) { continue }
        $out["$($p[0])|$($p[1])"] = [pscustomobject]@{
            category = $p[0]; field = $p[1]; type = [int]$p[2]; presentation = [int]$p[3]
            unitGroup = [int]$p[4]; unitPreset = [int]$p[5]; required = ($p[6] -eq '1')
            perLanguage = ($p[7] -eq '1'); perVariant = ($p[8] -eq '1'); options = [int]$p[9]
            values = [int]$p[10]; computed = ($p[11] -eq '1'); defaults = [int]$p[12]
        }
    }
    return $out
}

function Test-PimAttributeAspect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('typing', 'units', 'options', 'rules', 'scope', 'values')][string]$Aspect,
        [Parameter(Mandatory)]$Attribute,
        [Parameter(Mandatory)][hashtable]$Stored
    )
    $offenders = @(); $scanned = 0
    foreach ($a in @($Attribute)) {
        $key = "$($a.category)|$($a.field)"
        $s = $Stored[$key]
        $kind = "$($a.kind)"
        switch ($Aspect) {
            'typing' {
                $scanned++
                if (-not $s) { $offenders += "$key is declared and no field with that id is stored"; continue }
                if ($kind -eq 'computed') {
                    if (-not $s.computed) { $offenders += "$key is declared computed and its field type $($s.type) has no provider" }
                    continue
                }
                $ok = $script:PimAttributeKindTypes[$kind]
                if ($ok -notcontains $s.type) { $offenders += "$key is declared $kind and stored as field type $($s.type) (expected $($ok -join ' or '))"; continue }
                if ($kind -eq 'choice' -and $script:PimSinglePresentation -notcontains $s.presentation) {
                    $offenders += "$key is a single choice and its list presentation is $($s.presentation) (expected 1 radio or 2 dropdown)"
                }
                if ($kind -eq 'multi-choice' -and $script:PimMultiPresentation -notcontains $s.presentation) {
                    $offenders += "$key is a multi choice and its list presentation is $($s.presentation) (expected 3 multi-select, 4 checkbox list or 5 tag cloud)"
                }
            }
            'units' {
                if ($kind -ne 'measure') { continue }
                $scanned++
                if (-not $s) { $offenders += "$key is not stored"; continue }
                if ($s.unitGroup -le 0) { $offenders += "$key is a measure in $($a.unit) with no unit group on the field" }
                elseif ($s.unitPreset -le 0) { $offenders += "$key has unit group $($s.unitGroup) and no preset unit" }
            }
            'options' {
                if ($kind -notin 'choice', 'multi-choice') { continue }
                $scanned++
                if (-not $s) { $offenders += "$key is not stored"; continue }
                if ($s.options -lt 2) { $offenders += "$key is a list with $($s.options) option(s); a choice needs at least 2" }
            }
            'rules' {
                if ($a.required -ne $true) { continue }
                $scanned++
                if (-not $s) { $offenders += "$key is not stored"; continue }
                if (-not $s.required) { $offenders += "$key is declared required and the field is not marked required" }
            }
            'scope' {
                if ($a.perLanguage -ne $true -and $a.perVariant -ne $true) { continue }
                $scanned++
                if (-not $s) { $offenders += "$key is not stored"; continue }
                if ($a.perLanguage -eq $true -and -not $s.perLanguage) { $offenders += "$key is declared per language and the field does not allow changes across languages" }
                if ($a.perVariant -eq $true -and -not $s.perVariant) { $offenders += "$key is declared per variant and the field does not allow changes across variants" }
            }
            'values' {
                if ($kind -eq 'computed' -or [string]::IsNullOrEmpty("$($a.category)")) { continue }
                $scanned++
                if (-not $s) { $offenders += "$key is not stored"; continue }
                # A value equal to the data set or data model default is inherited, not stored on the product.
                # A default counts only on a group (or the parent of a group) that holds at least one product.
                if ($s.values -lt 1 -and $s.defaults -lt 1) { $offenders += "$key has no value on any product and no inherited default on a group with products" }
            }
        }
    }
    return @{ scanned = $scanned; offenders = @($offenders) }
}
