<#
.SYNOPSIS
  Convert an AX 2009/2012 XPO export (AOT project) into the normalized discovery model JSON
  consumed by Measure-KeyCentrality.ps1.

.DESCRIPTION
  Parses TABLE / VIEW / CLASS / QUERY / EXTENDEDTYPE elements. For each table: fields (name, base type,
  ExtendedDataType, Mandatory), indexes (name, fields, unique), relations (REFERENCES / RELATIONS blocks),
  and origin classification by name prefix. Views and queries contribute the tables they join.
  Classes contribute "code usage" counts: how often each known table/field identifier appears in X++ source.

.PARAMETER Path       One or more .xpo files.
.PARAMETER OutFile    Destination JSON (default: .\model.xpo.json).
.PARAMETER PrefixMap  Hashtable prefix -> origin label, longest prefix wins. Example:
                      @{ 'XYZ' = 'isv:<vendor>'; 'ABC' = 'custom'; 'INT' = 'integration-footprint' }
                      Unmatched names starting with a 2-5 char uppercase run get prefix=<run>, origin='unknown';
                      well-known standard AX prefixes map to 'standard'.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]]$Path,
  [string]$OutFile = '.\model.xpo.json',
  [hashtable]$PrefixMap = @{}
)
$ErrorActionPreference = 'Stop'

# Standard AX application prefixes (non-exhaustive; enough to classify the common core).
$standardPrefixes = @('Cust','Vend','Invent','Sales','Purch','Ledger','Dir','Logistics','Ecom','EcoRes','Proj','Prod','Bom','Smm','Hcm','Wrk','Whs','Ret','Tax','Bank','Asset','Cat','Price','Mcr','Sys','Batch','Num','Company','DataArea','Party','Dimension','Wms','Trade','Route','Unit','Inter','Markup','Agreement','Doc','Info','Address','Currency','Exchange','Cost','Budget','Cash','Fixed','Payment','Return','Rma','Serv','Case','Web','Print','Report')

function Get-Origin([string]$name) {
  $hit = $PrefixMap.Keys | Where-Object { $name.StartsWith($_, [System.StringComparison]::Ordinal) } | Sort-Object Length -Descending | Select-Object -First 1
  if ($hit) { return [pscustomobject]@{ prefix = $hit; origin = $PrefixMap[$hit] } }
  foreach ($p in $standardPrefixes) { if ($name.StartsWith($p, [System.StringComparison]::Ordinal)) { return [pscustomobject]@{ prefix = $p; origin = 'standard' } } }
  if ($name -cmatch '^([A-Z]{2,5}_?)(?=[A-Z][a-z])') { return [pscustomobject]@{ prefix = $Matches[1]; origin = 'unknown' } }
  return [pscustomobject]@{ prefix = ''; origin = 'unknown' }
}

$tables = [ordered]@{}
$views = @()
$queries = @()
$edts = @()
$classes = @()

foreach ($file in $Path) {
  $text = Get-Content -LiteralPath $file -Raw
  $elements = $text -split '\*\*\*Element: '
  foreach ($el in $elements) {
    if (-not $el) { continue }
    $kind = ($el -split "`r?`n", 2)[0].Trim()
    switch ($kind) {
      'DBT' {
        if ($el -notmatch '(?m)^\s*TABLE #(\S+)') { continue }
        $tname = $Matches[1]
        $t = [ordered]@{ name = $tname; kind = 'table'; label = $null; saveDataPerCompany = $true; titleFields = @(); fields = @(); indexes = @(); relations = @(); origin = (Get-Origin $tname) }
        if ($el -match '(?m)^\s*Label\s+#(\S+)') { $t.label = $Matches[1] }
        if ($el -match '(?m)^\s*SaveDataPerCompany\s+#No') { $t.saveDataPerCompany = $false }
        foreach ($m in [regex]::Matches($el, '(?m)^\s*TitleField[12]\s+#(\S+)')) { $t.titleFields += $m.Groups[1].Value }
        # FIELDS
        if ($el -match '(?s)FIELDS\r?\n(.*?)\r?\n\s*ENDFIELDS') {
          $fblock = $Matches[1]
          foreach ($fm in [regex]::Matches($fblock, '(?s)FIELD #(\S+)\r?\n\s*(\w+)\r?\n\s*PROPERTIES(.*?)ENDPROPERTIES')) {
            $props = $fm.Groups[3].Value
            $edt = if ($props -match 'ExtendedDataType\s+#(\S+)') { $Matches[1] } else { $null }
            $enum = if ($props -match 'EnumType\s+#(\S+)') { $Matches[1] } else { $null }
            $t.fields += [ordered]@{
              name = $fm.Groups[1].Value; type = $fm.Groups[2].Value.ToLower(); edt = $edt; enum = $enum
              mandatory = [bool]($props -match 'Mandatory\s+#Yes'); allowEdit = -not ($props -match 'AllowEdit\s+#No')
            }
          }
        }
        # INDICES
        # AX2012 XPO index syntax: "#IdxName" line, PROPERTIES block, INDEXFIELDS block of "#Field" lines.
        if ($el -match '(?s)\n\s*INDICES\r?\n(.*?)\r?\n\s*ENDINDICES') {
          foreach ($im in [regex]::Matches($Matches[1], '(?s)^\s*#(\S+)\r?\n\s*PROPERTIES(.*?)ENDPROPERTIES\s*INDEXFIELDS(.*?)ENDINDEXFIELDS', 'Multiline')) {
            $ifields = @([regex]::Matches($im.Groups[3].Value, '#(\S+)') | ForEach-Object { $_.Groups[1].Value })
            $t.indexes += [ordered]@{ name = $im.Groups[1].Value; fields = $ifields; unique = [bool]($im.Groups[2].Value -match 'AllowDuplicates\s+#No'); alternateKey = [bool]($im.Groups[2].Value -match 'AlternateKey\s+#Yes') }
          }
        }
        # RELATIONS (AX2012 REFERENCES block and legacy RELATIONS block)
        foreach ($rb in @('REFERENCES','RELATIONS')) {
          if ($el -match "(?s)$rb\r?\n(.*?)\r?\n\s*END$rb") {
            foreach ($rm in [regex]::Matches($Matches[1], '(?s)REFERENCE #(\S+)\r?\n\s*PROPERTIES(.*?)ENDPROPERTIES(.*?)(?=REFERENCE #|\z)')) {
              $rprops = $rm.Groups[2].Value
              $rtable = if ($rprops -match 'Table\s+#(\S+)') { $Matches[1] } else { $null }
              $pairs = @()
              foreach ($pm in [regex]::Matches($rm.Groups[3].Value, '(?s)Field\s+#(\S+).*?RelatedField\s+#(\S+)')) { $pairs += [ordered]@{ field = $pm.Groups[1].Value; relatedField = $pm.Groups[2].Value } }
              if ($rtable) { $t.relations += [ordered]@{ name = $rm.Groups[1].Value; table = $rtable; fields = $pairs } }
            }
          }
        }
        $tables[$tname] = $t
      }
      'VIE' {
        if ($el -notmatch '(?m)^\s*VIEW #(\S+)') { continue }
        $vname = $Matches[1]
        $used = @([regex]::Matches($el, '(?m)^\s*Table\s+#(\S+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $views += [ordered]@{ name = $vname; kind = 'view'; tables = $used; origin = (Get-Origin $vname) }
      }
      'QUE' {
        if ($el -notmatch '(?m)^\s*QUERY #(\S+)') { continue }
        $qname = $Matches[1]
        $used = @([regex]::Matches($el, '(?m)^\s*Table\s+#(\S+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $queries += [ordered]@{ name = $qname; kind = 'query'; tables = $used; origin = (Get-Origin $qname) }
      }
      { $_ -in 'DBE','EDT','DBX' } {
        # DBE = base enum (ENUMTYPE), EDT/DBX exports = extended data types (EXTENDEDTYPE).
        foreach ($em in [regex]::Matches($el, '(?m)^\s*(EXTENDEDTYPE|ENUMTYPE) #(\S+)')) {
          $edts += [ordered]@{ name = $em.Groups[2].Value; kind = $em.Groups[1].Value.ToLower(); origin = (Get-Origin $em.Groups[2].Value) }
        }
      }
      'CLS' {
        if ($el -notmatch '(?m)^\s*CLASS #(\S+)') { continue }
        $classes += [ordered]@{ name = $Matches[1]; source = $el; origin = (Get-Origin $Matches[1]) }
      }
    }
  }
}

# Code-usage census: count identifier occurrences of every table name and every distinct field name in X++ class bodies.
$allFieldNames = @($tables.Values | ForEach-Object { $_.fields | ForEach-Object { $_.name } } | Sort-Object -Unique)
$identifierUsage = [ordered]@{}
$corpus = ($classes | ForEach-Object { $_.source }) -join "`n"
foreach ($id in (@($tables.Keys) + $allFieldNames | Sort-Object -Unique)) {
  if ($id.Length -lt 4) { continue }
  $n = [regex]::Matches($corpus, "(?i)\b$([regex]::Escape($id))\b").Count
  if ($n -gt 0) { $identifierUsage[$id] = $n }
}
# Also count well-known identifier shapes referenced in code but not defined in this XPO (external tables the footprint reads).
foreach ($m in [regex]::Matches($corpus, '\b([A-Z][A-Za-z0-9]{3,})(?:Table|Trans|Line|Jour|Journal|Header|Master|Id)\b')) {
  $id = $m.Value
  if (-not $identifierUsage.Contains($id)) { $identifierUsage[$id] = 0 }
  $identifierUsage[$id]++
}

$model = [ordered]@{
  source = [ordered]@{ kind = 'xpo'; files = @($Path | ForEach-Object { [System.IO.Path]::GetFileName($_) }) }
  entities = @($tables.Values)
  views = $views
  queries = $queries
  extendedDataTypes = $edts
  classes = @($classes | ForEach-Object { [ordered]@{ name = $_.name; origin = $_.origin; lines = ($_.source -split "`n").Count } })
  codeUsage = $identifierUsage
}
$json = $model | ConvertTo-Json -Depth 8
$outPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutFile))
if ([System.IO.Path]::IsPathRooted($OutFile)) { $outPath = $OutFile }
[System.IO.File]::WriteAllText($outPath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host ("tables={0} views={1} queries={2} edts={3} classes={4} codeIdentifiers={5} -> {6}" -f $tables.Count, $views.Count, $queries.Count, $edts.Count, $classes.Count, $identifierUsage.Count, $outPath)
