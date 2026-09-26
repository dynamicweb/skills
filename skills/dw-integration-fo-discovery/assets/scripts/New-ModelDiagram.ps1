<#
.SYNOPSIS
  Mermaid diagram of the data model in use, organized by where the clarification questions should go:
  ring 1 = the spine (home entity of every central key) - ask lifecycle, identifier origin, ownership;
  ring 2 = populated entities keyed by the spine, grouped per module - ask what filled / empty fields mean;
  ring 3 = ISV / custom entities that exist without rows - ask "still in use?".
  Standard entities that are schema-only are counted, not drawn.

.DESCRIPTION
  Inputs are the three discovery files: model.odata.json or model.xpo.json (structure, origin, keys, relations),
  census.json (rows, fill rates, errors) and key-centrality.json (ranked concepts). Output: <OutFile>.md with the
  fenced diagram, a legend that maps each ring to its question owners, and a node table; <OutFile>.mmd holds the
  bare diagram for tools that render Mermaid from a file. Relations drawn as solid arrows come from the model's
  navigation properties / table relations; dotted arrows are inferred from a shared spine key field and carry
  "· inferred" - confirm those with the customer, do not present them as facts. Labels avoid characters the Mermaid
  flowchart lexer rejects in edge text (parentheses, pipes, brackets).

.EXAMPLE
  & New-ModelDiagram.ps1 -Model .\model.odata.json -Census .\census.json -Centrality .\key-centrality.json -OutFile .\data-model.md
  & New-ModelDiagram.ps1 ... -Include '^(SalesQuotationHeaderV2|ReturnOrderHeaderV2)$' -TopConcepts 14 -MaxAdjacent 30
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Model,
  [Parameter(Mandatory)][string]$Census,
  [Parameter(Mandatory)][string]$Centrality,
  [string]$OutFile = '.\data-model.md',
  [int]$TopConcepts = 12,
  [int]$MaxAdjacent = 24,
  [int]$MaxPerModule = 6,
  [int]$MaxEmpty = 8,
  [string]$Include = '^$',
  [string]$Exclude = '(Bi|CDR|CDS|AI)Entity$|ForAI$|Copilot|Mobile|DualWrite|PayInt|Attachment|Note$|Totals|Tmp|Staging|ReadOnly$|^(Aggregated|Bundle|BusinessDocument|CLMIntegration|Sensor|Ess|D365|DV|ProductNumberIdentified)|Internal|Cache|Foundation|_',
  # scope keys (company, site, warehouse, worker, address …) and finance plumbing (journals, tax, ledger) never form the spine
  [string]$SkipConcepts = 'Company|DataArea|LegalEntity|Site|Warehouse|Line ?number|Personnel|Worker|Address|Zip|Country|State|Currency|RefTable|SourceSystem|Store|Terminal|Register|Position|Job|Department|OperatingUnit|Sequence|Journal|Tax|Ledger|MainAccount|Engineering|Dimension|Voucher|Batch|InventTrans|LotId',
  [ValidateSet('LR','TB')][string]$Direction = 'LR',
  [string[]]$ModuleMap = @(
    '^(Purch|Vend|VRM|ProductReceipt|RequestForQuotation)=Procurement',
    '^(FixedAsset|Asset(Book|Trans|Group))=Finance',
    '^DocumentProj=Projects & production',
    '^(Sales|Return|CustomerPayment|CustInvoice|Invoice|FreeText|Rebate|GUP|Price|Trade)=Sales & invoicing',
    '^(Cust|Customer|Contact|DirParty|Party)=Customers & parties',
    '^(Released|Product|Item|EcoRes|Catalog|Category|Barcode|Attribute)=Products / PIM',
    '^(Invent|Warehouse|OnHand|Site|WHS|Wms|Location|Tracking|Planned|Quality|Req|Demand|Forecast)=Inventory & planning',
    '^(Proj|Prod|BOM|Route)=Projects & production',
    '^(Retail|Channel|Store|Terminal)=Retail / commerce',
    '^(Service|SMA|Warranty|Asset|Maintenance)=Service & warranty',
    '^(Ledger|Budget|Tax|Bank|Dimension|Fiscal)=Finance')
)
$ErrorActionPreference = 'Stop'
$inv = [cultureinfo]::InvariantCulture
function N0([object]$n) { if ($null -eq $n) { return '-' }; return ([int64]$n).ToString('N0', $inv) }
function Id([string]$s) { return ($s -replace '[^A-Za-z0-9_]', '_') }
function BaseName([string]$s) { return ($s -replace 'V\d+', '') }
function ModuleOf([string]$name) {
  foreach ($m in $ModuleMap) { $rx, $mod = $m -split '=', 2; if ($name -cmatch $rx) { return $mod } }
  return 'Other'
}

# ---- load ----
# note: parameters are [string]-typed and PowerShell variable names are case-insensitive — never assign the parsed objects to $model / $census
$mdl = Get-Content -Raw -Encoding utf8 $Model | ConvertFrom-Json
$entities = @($mdl.entities | Where-Object { $_.name })
$byName = @{}; foreach ($e in $entities) { $byName["$($e.name)"] = $e }
$cns = Get-Content -Raw -Encoding utf8 $Census | ConvertFrom-Json
$rows = @{}; $fills = @{}; $errors = @{}
foreach ($c in @($cns.entities | Where-Object { $_.name })) {
  if ($c.error) { $errors["$($c.name)"] = $c.error; continue }
  $rows[$c.name] = [int64]$c.rows
  if ($c.fields) { $full = @($c.fields | Where-Object { $_.fillRate -ge 0.9 }).Count; $fills[$c.name] = "$full/$($c.fields.Count)" }
}
$ranking = @(Get-Content -Raw -Encoding utf8 $Centrality | ConvertFrom-Json)

function Origin($e) { if ($e.origin -and $e.origin.origin) { return "$($e.origin.origin)" }; return 'standard' }
function Prefix($e) { if ($e.origin -and $e.origin.prefix) { return "$($e.origin.prefix)" }; return '' }
function KeyFields($e) {
  if ($e.keys) { return @($e.keys | ForEach-Object { "$_" }) }
  $u = @($e.indexes | Where-Object { $_.unique -or $_.alternateKey } | ForEach-Object { $_.fields } | ForEach-Object { "$_" })
  return $u
}
function FieldNames($e) { return @($e.fields | ForEach-Object { "$($_.name)" }) }
function IsDrawable([string]$n) { return ($byName.ContainsKey($n) -and -not ($n -cmatch $Exclude)) -or ($n -cmatch $Include) }

# ---- ring 1: spine homes ----
# match the skip list on the concept's label and its leading (canonical) field name only — an alias such as TaxInventVATItemId or InterCompanySalesId must not drop the item / sales-order concept
$concepts = @($ranking | Where-Object { $lead = "$($_.fieldNames)" -split ',\s*' | Select-Object -First 1; -not (("$($_.key) $lead") -cmatch $SkipConcepts) } | Select-Object -First $TopConcepts)
$spine = [ordered]@{}   # entity name -> @{ keys=[set of field names]; concepts=[labels] }
foreach ($c in $concepts) {
  $cfields = @(($c.fieldNames -split ',\s*') | Where-Object { $_ })
  $cents = @(($c.entities -split ',\s*') | Where-Object { $_ -and (IsDrawable $_) -and $rows[$_] -gt 0 })
  # home = the entity whose business key IS the concept field (keys minus dataAreaId == one concept field): the master/header.
  # child tables carry the parent key inside a composite key and score lower; name length breaks ties (CustomerV3 beats CustomerV3Something).
  $scored = foreach ($n in $cents) {
    $e = $byName[$n]; $k = @((KeyFields $e) | Where-Object { $_ -ne 'dataAreaId' })
    $keyHit = @($cfields | Where-Object { $k -contains $_ })
    if (-not $keyHit) { continue }
    $exact = ($k.Count -eq 1)
    $catW = switch ("$($e.category)") { 'Master' { 3 } 'Document' { 2 } 'Reference' { 1 } default { 0 } }
    $verW = if ($n -match 'V(\d+)$') { [int]$Matches[1] / 100 } else { 0 }
    $lineW = if ($n -match 'Line') { 4 } else { 0 }   # headers/masters over lines when both carry the key
    [pscustomobject]@{ name = $n; score = ($(if ($exact) { 20 } else { 5 }) + $catW + [Math]::Log10([Math]::Max(1, $rows[$n])) + $verW - $lineW - ($n.Length / 100)); keys = $keyHit; fields = $cfields }
  }
  $homeEnt = $scored | Sort-Object score -Descending | Select-Object -First 1
  if (-not $homeEnt) { continue }
  # collapse versions: keep one node per base name
  $dup = $spine.Keys | Where-Object { (BaseName $_) -eq (BaseName $homeEnt.name) } | Select-Object -First 1
  if ($dup) { $homeEnt = [pscustomobject]@{ name = $dup; keys = $homeEnt.keys; fields = $cfields } }
  if (-not $spine.Contains($homeEnt.name)) { $spine[$homeEnt.name] = @{ keys = [System.Collections.Generic.List[string]]::new(); fields = [System.Collections.Generic.List[string]]::new(); label = $c.key -replace '^(label|edt|name):', '' } }
  foreach ($k in $homeEnt.keys) { if (-not $spine[$homeEnt.name].keys.Contains($k)) { $spine[$homeEnt.name].keys.Add($k) } }
  foreach ($f in $cfields) { if (-not $spine[$homeEnt.name].fields.Contains($f)) { $spine[$homeEnt.name].fields.Add($f) } }
}
$spineFields = [System.Collections.Generic.HashSet[string]]::new([string[]]@($spine.Values | ForEach-Object { $_.fields }), [System.StringComparer]::OrdinalIgnoreCase)

# ---- ring 2: populated entities carrying spine keys ----
$spineBases = @($spine.Keys | ForEach-Object { BaseName $_ })
$cand = foreach ($e in $entities) {
  $n = $e.name
  if ($spine.Contains($n) -or ($spineBases -contains (BaseName $n)) -or -not (IsDrawable $n) -or -not ($rows[$n] -gt 0)) { continue }
  $fn = FieldNames $e
  $hits = @((FieldNames $e) | Where-Object { $spineFields.Contains($_) } | Select-Object -Unique)
  $homesHit = @($spine.Keys | Where-Object { $s = $_; @($spine[$s].fields | Where-Object { $fn -contains $_ }).Count -gt 0 }).Count
  $forced = $n -cmatch $Include
  if (-not $hits -and -not $forced) { continue }
  $catW = switch ("$($e.category)") { 'Master' { 2 } 'Document' { 2 } 'Transaction' { 1 } default { 0 } }
  $isvW = if ((Origin $e) -ne 'standard') { 5 } else { 0 }
  [pscustomobject]@{ name = $n; base = (BaseName $n); module = (ModuleOf $n); ver = $(if ($n -match 'V(\d+)$') { [int]$Matches[1] } else { 0 }); score = ($homesHit * 3 + [Math]::Log10([Math]::Max(1, $rows[$n])) + $catW + $isvW + $(if ($forced) { 100 } else { 0 }) - ($n.Length / 100)); hits = $hits }
}
# one node per base name (highest version); then round-robin across modules (best of each module per round, at most
# -MaxPerModule each) so a busy module such as procurement cannot crowd the product or customer side out of the picture
$perBase = @($cand | Group-Object base | ForEach-Object { $_.Group | Sort-Object ver, score -Descending | Select-Object -First 1 })
$queues = @{}; foreach ($g in ($perBase | Group-Object module)) { $queues[$g.Name] = [System.Collections.Generic.List[object]]@($g.Group | Sort-Object score -Descending | Select-Object -First $MaxPerModule) }
$adjacent = [System.Collections.Generic.List[object]]::new()
while ($adjacent.Count -lt $MaxAdjacent -and ($queues.Values | Where-Object { $_.Count -gt 0 })) {
  foreach ($m in ($queues.Keys | Sort-Object)) {
    if ($adjacent.Count -ge $MaxAdjacent) { break }
    if ($queues[$m].Count -gt 0) { $adjacent.Add($queues[$m][0]); $queues[$m].RemoveAt(0) }
  }
}
$adjacent = @($adjacent)

# ---- ring 3: non-standard entities without rows ----
$empty = @($entities | Where-Object { (Origin $_) -ne 'standard' -and -not $spine.Contains($_.name) -and ($adjacent.name -notcontains $_.name) -and -not ($rows[$_.name] -gt 0) } |
  Sort-Object { $_.fields.Count } -Descending | Select-Object -First $MaxEmpty)
$emptyStandard = @($cns.entities | Where-Object { -not $_.error -and [int64]$_.rows -eq 0 }).Count
$notReadable = $errors.Count

# ---- edges ----
$selected = [System.Collections.Generic.HashSet[string]]::new([string[]]@(@($spine.Keys) + @($adjacent.name) + @($empty.name)), [System.StringComparer]::Ordinal)
$edges = [ordered]@{}
foreach ($n in $selected) {
  $e = $byName[$n]; if (-not $e) { continue }
  foreach ($r in @($e.relations)) {
    $t = "$($r.table)"
    if (-not $selected.Contains($t) -or $t -eq $n) { continue }
    $lab = (@($r.fields | ForEach-Object { "$($_.field)" } | Where-Object { $_ -and $_ -ne 'dataAreaId' }) -join '+')
    # arrows always point at the referenced entity: a 'Multiple' navigation lists children of $n, so the child is the source
    $from = $n; $to = $t
    if ("$($r.cardinality)" -eq 'Multiple') { $from = $t; $to = $n }
    $k = "$from>$to"; $k2 = "$to>$from"
    if (-not $edges.Contains($k) -and -not $edges.Contains($k2)) { $edges[$k] = @{ from = $from; to = $to; label = $lab; inferred = $false } }
  }
}
foreach ($a in $adjacent) {
  foreach ($s in $spine.Keys) {
    $shared = @($a.hits | Where-Object { $spine[$s].fields -contains $_ } | Select-Object -First 1)
    if (-not $shared) { continue }
    $k = "$($a.name)>$s"; $k2 = "$s>$($a.name)"
    if ($edges.Contains($k) -or $edges.Contains($k2)) { continue }
    # no parentheses in pipe-delimited edge text — Mermaid's flowchart lexer rejects them
    $edges[$k] = @{ from = $a.name; to = $s; label = "$($shared[0]) · inferred"; inferred = $true }
  }
}

# ---- render ----
function NodeLabel([string]$n, [bool]$isSpine) {
  $e = $byName[$n]
  $parts = [System.Collections.Generic.List[string]]::new()
  $org = if ($e) { Origin $e } else { 'standard' }
  $head = if ($org -ne 'standard') { "$($org.ToUpper()) $(Prefix $e) · $n" } else { $n }
  $parts.Add($head)
  if ($rows.ContainsKey($n)) { $parts.Add("rows " + (N0 $rows[$n])) } elseif ($errors.ContainsKey($n)) { $parts.Add('not readable') } else { $parts.Add('rows 0') }
  if ($isSpine -and $spine[$n].keys.Count) { $parts.Add('key ' + ($spine[$n].keys -join '+')) }
  if ($fills.ContainsKey($n)) { $parts.Add("filled $($fills[$n]) fields") }
  return ($parts -join '<br/>')
}
$L = [System.Collections.Generic.List[string]]::new()
$L.Add("flowchart $Direction")
$L.Add('  subgraph R1["1 · SPINE — ask: lifecycle of one record, who issues the identifier, which system owns it"]')
$L.Add('    direction TB')
foreach ($n in $spine.Keys) { $L.Add("    $(Id $n)[""$(NodeLabel $n $true)""]:::spine") }
$L.Add('  end')
$L.Add('  subgraph R2["2 · POPULATED AROUND THE SPINE — ask: what do the filled fields mean, why are the empty ones empty"]')
$L.Add('    direction TB')
$groups = $adjacent | Group-Object { ModuleOf $_.name } | Sort-Object Name
$gi = 0
foreach ($g in $groups) {
  $gi++
  $L.Add("    subgraph M$gi[""$($g.Name)""]")
  foreach ($a in ($g.Group | Sort-Object { $rows[$_.name] } -Descending)) {
    $cls = if ((Origin $byName[$a.name]) -ne 'standard') { 'isv' } else { 'adj' }
    $L.Add("      $(Id $a.name)[""$(NodeLabel $a.name $false)""]:::$cls")
  }
  $L.Add('    end')
}
$L.Add('  end')
$L.Add('  subgraph R3["3 · PRESENT, NO ROWS — ask only for ISV/custom: still in use, or can the integration ignore it?"]')
$L.Add('    direction TB')
if ($empty.Count) { foreach ($e in $empty) { $L.Add("    $(Id $e.name)[""$(NodeLabel $e.name $false)""]:::empty") } }
else { $L.Add("    R3note[""no ISV/custom entity without rows<br/>$(N0 $emptyStandard) standard entities schema-only (not drawn)<br/>$(N0 $notReadable) not readable""]:::empty") }
$L.Add('  end')
foreach ($ed in $edges.Values) {
  $arrow = if ($ed.inferred) { '-.->' } else { '-->' }
  $lab = if ($ed.label) { "|$($ed.label)|" } else { '' }
  $L.Add("  $(Id $ed.from) $arrow$lab $(Id $ed.to)")
}
$L.Add('  classDef spine fill:#fde68a,stroke:#b45309,stroke-width:2px,color:#1f2937')
$L.Add('  classDef adj fill:#dbeafe,stroke:#1d4ed8,color:#1f2937')
$L.Add('  classDef isv fill:#fecaca,stroke:#b91c1c,stroke-width:2px,color:#1f2937')
$L.Add('  classDef empty fill:#f3f4f6,stroke:#9ca3af,stroke-dasharray:4 3,color:#4b5563')
$mmd = $L -join "`n"

$md = [System.Collections.Generic.List[string]]::new()
$md.Add('# Data model in use — where the questions go')
$md.Add('')
$md.Add("Generated from ``$(Split-Path -Leaf $Model)``, ``$(Split-Path -Leaf $Census)`` and ``$(Split-Path -Leaf $Centrality)``. Spine = home entity of the top $TopConcepts non-scope concepts in key centrality; ring 2 = the $($adjacent.Count) most connected populated entities carrying a spine key; ring 3 = ISV/custom entities without rows. Solid arrows are model relations; dotted arrows are inferred from a shared key field and must be confirmed.")
$md.Add('')
$md.Add('| Ring | Colour | What it holds | Question shape (see synthesis-brief.md) | Owner |')
$md.Add('|---|---|---|---|---|')
$md.Add('| 1 Spine | amber | one home entity per central key | walk through the life of one record; where is the identifier assigned; which system owns it | process owner |')
$md.Add('| 2 Populated | blue (red = ISV/custom) | entities keyed by the spine, grouped per module | what does field X record, who fills it; why is Y empty on this entity but filled on its sibling | ERP admin / key user |')
$md.Add('| 3 Present, no rows | grey dashed | ISV/custom schema without data | still in use anywhere, or can the integration ignore it | ERP admin / ISV partner |')
$md.Add('')
$md.Add('```mermaid')
$md.Add($mmd)
$md.Add('```')
$md.Add('')
$md.Add('| Ring | Module | Entity | Origin | Rows | Spine keys carried | Filled fields |')
$md.Add('|---|---|---|---|---|---|---|')
foreach ($n in $spine.Keys) { $md.Add("| 1 | $(ModuleOf $n) | ``$n`` | $(Origin $byName[$n]) | $(N0 $rows[$n]) | $($spine[$n].keys -join ', ') | $($fills[$n]) |") }
foreach ($a in ($adjacent | Sort-Object { ModuleOf $_.name }, { -$rows[$_.name] })) { $md.Add("| 2 | $(ModuleOf $a.name) | ``$($a.name)`` | $(Origin $byName[$a.name]) | $(N0 $rows[$a.name]) | $($a.hits -join ', ') | $($fills[$a.name]) |") }
foreach ($e in $empty) { $md.Add("| 3 | $(ModuleOf $e.name) | ``$($e.name)`` | $(Origin $e) $(Prefix $e) | 0 | | |") }
$md.Add('')
$md.Add("Not drawn: $(N0 $emptyStandard) standard entities with schema and no rows; $(N0 $notReadable) entities not readable (see 00-access.md); populated entities outside the top $MaxAdjacent by connectivity (raise ``-MaxAdjacent`` or force with ``-Include``).")

$mdPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)   # PowerShell location, not the process cwd
$mmdPath = [System.IO.Path]::ChangeExtension($mdPath, '.mmd')
[System.IO.File]::WriteAllText($mdPath, ($md -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($mmdPath, $mmd + "`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "spine=$($spine.Count) adjacent=$($adjacent.Count) empty=$($empty.Count) edges=$($edges.Count) -> $mdPath, $mmdPath"
