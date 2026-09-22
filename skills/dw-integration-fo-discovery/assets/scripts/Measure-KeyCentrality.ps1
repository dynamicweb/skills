<#
.SYNOPSIS
  Rank identifier fields by how central they are to the data model in use — the "find the spine identifier" step.

.DESCRIPTION
  Input: one or more normalized discovery model JSON files (from ConvertFrom-Xpo.ps1 or Export-FoMetadata.ps1).
  Fields are grouped into concepts by, in order of precision: extended data type (XPO/model exports), property LabelId
  (F&O Metadata service — same label across entities = same business concept), then a normalized name (suffixes
  Id/Number/Num/Code stripped, aliases applied so ItemId/ItemNumber or CustAccount/CustomerAccountNumber merge).
  Per concept:
    spread        distinct entities carrying it
    relations     relation / navigation-property edges it participates in
    keynessRate   share of carrying entities where it is part of a unique index / alternate key / entity key
    mandatoryRate share of carrying entities where it is mandatory
    codeUsage     occurrences in X++ / integration code (XPO models only)
    population    from a census file (-Census): share of carrying, sampled entities where fill rate >= 50%
  Score = w.spread*ln(spread+1) + w.relations*ln(relations+1) + w.keyness*keynessRate + w.mandatory*mandatoryRate
        + w.codeUsage*codeUsage + w.population*population*ln(spread+1)
  Noise (RecId, DataAreaId, audit columns, LineNumber, SourceKey, product-dimension ids, …) is excluded; -IncludeSurrogates keeps
  surrogate FKs / enum EDTs. Output: ranked JSON + a Markdown table for the data-model brief.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]]$Model,
  [string]$Census,
  [int]$Top = 25,
  [string]$OutFile = '.\key-centrality.json',
  [ValidateSet('auto','edt','label','name')][string]$GroupBy = 'auto',
  [switch]$IncludeSurrogates,
  [switch]$IncludeDimensions,
  [hashtable]$Aliases = @{ custaccount = 'customeraccount'; invoiceaccount = 'customerinvoiceaccount'; vendaccount = 'vendoraccount'; item = 'item'; itemnumber = 'item'; itemid = 'item'; product = 'item'; productnumber = 'item'; salesid = 'salesorder'; salesorder = 'salesorder'; purchid = 'purchaseorder'; purchaseorder = 'purchaseorder'; inventlocation = 'warehouse'; inventsite = 'site'; party = 'party'; partynumber = 'party'; dataarea = 'legalentity'; legalentity = 'legalentity'; company = 'legalentity' },
  [hashtable]$Weights = @{ spread = 3.0; relations = 2.0; keyness = 3.0; mandatory = 1.5; codeUsage = 0.02; population = 3.0 }
)
$ErrorActionPreference = 'Stop'

$noise = @('RecId','RecVersion','DataAreaId','Partition','ModifiedDateTime','ModifiedBy','ModifiedTransactionId','CreatedDateTime','CreatedBy','CreatedTransactionId','Name','Description','Txt','Notes','Comment','Memo','Status','Type','Code','Id','Key','Value','Origin','Label','LineNum','LineNumber','SourceKey','Qty','Amount','Currency','CurrencyCode','SortOrder','Sequence','Blocked','Active','IsActive','IsDeleted','Dimension','DefaultDimension','InventDimId','Etag','ETag','RowVersion','LanguageId','ExpirationDate','EffectiveDate','ValidFrom','ValidTo','CountryRegionId','TimeZone','TransactionId','Voucher','JournalNumber','DocumentId','FileName','Url','Email','Phone')
$dimensionNoise = @('ProductColorId','ProductSizeId','ProductStyleId','ProductConfigurationId','ProductVersionId','ProductDimension1','ProductDimension2')
$noiseSet = [System.Collections.Generic.HashSet[string]]::new([string[]]($noise + $(if ($IncludeDimensions) { @() } else { $dimensionNoise })), [System.StringComparer]::OrdinalIgnoreCase)

$entities = @()
$codeUsage = @{}
foreach ($m in $Model) {
  $json = Get-Content -LiteralPath $m -Raw | ConvertFrom-Json
  $entities += $json.entities
  if ($json.codeUsage) { foreach ($p in $json.codeUsage.PSObject.Properties) { $codeUsage[$p.Name] = [int]$codeUsage[$p.Name] + [int]$p.Value } }
}
$censusByEntity = @{}
if ($Census) {
  $c = Get-Content -LiteralPath $Census -Raw | ConvertFrom-Json
  foreach ($e in $c.entities) { $censusByEntity[$e.name] = $e }
}

$candidateRx = '(Id|Num|Number|Code|Account|Ref|Key|Serial)$'
function Get-NormalizedName([string]$n) {
  $base = ($n -replace '(Id|Number|Num|Code)$', '').ToLowerInvariant()
  if ($Aliases.ContainsKey($base)) { return $Aliases[$base] }
  if ($Aliases.ContainsKey($n.ToLowerInvariant())) { return $Aliases[$n.ToLowerInvariant()] }
  return $base
}
function Get-GroupKey($fld) {
  switch ($GroupBy) {
    'edt'   { if ($fld.edt) { return "edt:$($fld.edt)" }; return "name:$(Get-NormalizedName $fld.name)" }
    'label' { if ($fld.labelId) { return "label:$($fld.labelId)" }; return "name:$(Get-NormalizedName $fld.name)" }
    'name'  { return "name:$(Get-NormalizedName $fld.name)" }
    default { if ($fld.edt) { return "edt:$($fld.edt)" }; if ($fld.labelId) { return "label:$($fld.labelId)" }; return "name:$(Get-NormalizedName $fld.name)" }
  }
}

$facts = @{}
function Add-Fact([string]$key, [string]$entity, [hashtable]$delta) {
  if (-not $facts.ContainsKey($key)) { $facts[$key] = @{ entities = [System.Collections.Generic.HashSet[string]]::new(); names = @{}; edts = [System.Collections.Generic.HashSet[string]]::new(); relations = 0; keyness = 0; mandatory = 0; populated = 0; censusEntities = 0 } }
  $f = $facts[$key]
  [void]$f.entities.Add($entity)
  $f.names[$delta.name] = [int]$f.names[$delta.name] + 1
  if ($delta.edt) { [void]$f.edts.Add($delta.edt) }
  foreach ($k in 'relations','keyness','mandatory','populated','censusEntities') { $f[$k] += $delta[$k] }
}

foreach ($e in $entities) {
  $ename = $e.name
  $keyFields = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($ix in @($e.indexes)) { if ($ix.unique -or $ix.alternateKey) { foreach ($fn in @($ix.fields)) { [void]$keyFields.Add($fn) } } }
  foreach ($fn in @($e.keys)) { [void]$keyFields.Add($fn) }
  $relFields = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($r in @($e.relations)) { foreach ($p in @($r.fields)) { if ($p.field) { [void]$relFields.Add($p.field) }; if ($p.relatedField) { [void]$relFields.Add($p.relatedField) } } }
  $cens = $censusByEntity[$ename]
  $sampled = ($cens -and $cens.sampled -gt 0)
  foreach ($fld in @($e.fields)) {
    $n = $fld.name
    if ($noiseSet.Contains($n)) { continue }
    if ($n -notmatch $candidateRx -and -not $fld.edt) { continue }
    if ($fld.enum) { continue }
    if (-not $IncludeSurrogates -and $fld.edt -and $fld.edt -match '(RecId|RefRecId)$|^NoYes|^Timezone|DateTime$|Date$|Time$') { continue }
    if (-not $IncludeSurrogates -and -not $fld.edt -and $n -match 'RecId$') { continue }
    if ($fld.type -in 'utcdatetime','date','datetimeoffset','boolean','binary') { continue }
    $pop = 0; $hasCensus = 0
    if ($sampled) { $cf = $cens.fields | Where-Object name -eq $n | Select-Object -First 1; if ($cf) { $hasCensus = 1; if ($cf.fillRate -ge 0.5) { $pop = 1 } } }
    Add-Fact (Get-GroupKey $fld) $ename @{ name = $n; edt = $fld.edt; relations = [int]$relFields.Contains($n); keyness = [int]$keyFields.Contains($n); mandatory = [int][bool]$fld.mandatory; populated = $pop; censusEntities = $hasCensus }
  }
}

$rows = foreach ($k in $facts.Keys) {
  $f = $facts[$k]
  $spread = $f.entities.Count
  if ($spread -lt 2) { continue }
  $names = @($f.names.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { $_.Key })
  $usage = 0; foreach ($nm in $names) { $usage += [int]$codeUsage[$nm] }
  $keyRate = $f.keyness / $spread; $mandRate = $f.mandatory / $spread
  $popRate = if ($f.censusEntities -gt 0) { $f.populated / $f.censusEntities } else { 0 }
  $score = $Weights.spread * [math]::Log($spread + 1) + $Weights.relations * [math]::Log($f.relations + 1) + $Weights.keyness * $keyRate + $Weights.mandatory * $mandRate + $Weights.codeUsage * $usage + $Weights.population * $popRate * [math]::Log($spread + 1)
  [pscustomobject]@{
    key = $k; fieldNames = ($names | Select-Object -First 6) -join ', '; edts = (@($f.edts) -join ', ')
    spread = $spread; relations = $f.relations; keynessRate = [math]::Round($keyRate, 2); mandatoryRate = [math]::Round($mandRate, 2); codeUsage = $usage
    populationEvidence = if ($f.censusEntities -gt 0) { [math]::Round($popRate, 2) } else { $null }; censusEntities = $f.censusEntities
    score = [math]::Round($score, 2)
    entities = (@($f.entities | Sort-Object) -join ', ')
  }
}
$ranked = $rows | Sort-Object score -Descending

$outPath = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutFile)) }
[System.IO.File]::WriteAllText($outPath, ($ranked | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))

$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine('| # | Concept (field names) | Spread | Relations | Key rate | Mandatory rate | Code usage | Population | Score | Carried by |')
[void]$md.AppendLine('|---|---|---|---|---|---|---|---|---|---|')
$i = 0
foreach ($r in ($ranked | Select-Object -First $Top)) {
  $i++
  $label = if ($r.edts) { "$($r.edts) ($($r.fieldNames))" } else { $r.fieldNames }
  $pop = if ($null -ne $r.populationEvidence) { "$($r.populationEvidence) (n=$($r.censusEntities))" } else { 'n/a' }
  $carried = $r.entities; if ($carried.Length -gt 90) { $carried = $carried.Substring(0, 87) + '…' }
  [void]$md.AppendLine("| $i | $label | $($r.spread) | $($r.relations) | $($r.keynessRate) | $($r.mandatoryRate) | $($r.codeUsage) | $pop | $($r.score) | $carried |")
}
$mdPath = [System.IO.Path]::ChangeExtension($outPath, '.md')
[System.IO.File]::WriteAllText($mdPath, $md.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host ("candidates={0} ranked -> {1} and {2}" -f @($ranked).Count, $outPath, $mdPath)
$ranked | Select-Object -First $Top | Format-Table @{n='concept';e={ if ($_.edts) { $_.edts } else { $_.fieldNames } }}, spread, relations, keynessRate, mandatoryRate, codeUsage, populationEvidence, score -AutoSize
