<#
.SYNOPSIS
    WRITES: stages the replace/ and merge/ trees of several Distribution layers into
    one SerializeRoot, with ONE merged <mode>-manifest.json per mode, and optionally
    the union Serializer.config.json. Dry run by default; -Apply to write.

.DESCRIPTION
    The mechanical half of the staging step in
    dw-demo-swift/references/deserialize-flow.md section 3 (the rule and the why stay
    there). A composable port of the manifest merge in the Foundry edition composer,
    reduced to what a demo build stages by hand. Pure file and JSON work: no host, no
    SQL, no token. Traps encoded:
      - MANIFEST CLOBBER: every layer's <mode>/ tree carries its own
        <mode>-manifest.json at the same relative path, so a per-layer copy leaves
        only the LAST layer's manifest on disk. Deserialize reads the manifest, not
        the config, so the run then covers that one layer and still reports 0 failed.
        This script never copies a manifest; it merges the entries[] of every
        layer's manifest, in the order given, and writes one manifest per mode.
      - Replace entries dedup by entryId, the LATER layer wins (source-wins), with a
        warning naming both layers. Merge entries are additive; an entryId two
        layers contribute is a warning, because each copy re-applies the same YAML.
      - A document path two layers ship is last-wins on disk in EITHER mode, so it
        is reported as an override, never overwritten silently.
      - Only schemaVersion 2 manifests are merged; anything else stops the run.
      - -AreaId remaps every hardcoded source areaId (manifest entries, the
        content/area-<n> token in entryId, and Content predicates in the config) to
        the local target area, instead of relying on the target area id matching
        the id the layer was serialized from.
    Asserts, per mode: the merged entry count equals the sum of the layers' entries
    minus replace overrides, and every file a manifest names exists (in the layer
    before the copy, under SerializeRoot after it). A failed assert exits 1.

    Item-type XMLs and templates are NOT staged here (they do not collide the same
    way); the owning reference stages them, then owes a host restart before the
    first dry run.

.PARAMETER DistributionRoot
    The Distribution checkout that holds layers/. Mandatory; no default path.

.PARAMETER Layer
    Layer names in composition order (base first). Mandatory. Pass comma-joined
    under pwsh -File: -Layer base,surface-swift

.PARAMETER SerializeRoot
    Target folder, the host's wwwroot/Files/System/Serializer/SerializeRoot.
    Mandatory. Its replace/ and merge/ subfolders are created when missing.

.PARAMETER SerializerConfigPath
    Where the union of every layer's config/*.json is written, normally the host's
    wwwroot/Files/System/Serializer/Serializer.config.json. Omitted = no config is
    written (the plan still reports the union count).

.PARAMETER AreaId
    The local target area id. 0 (the default) leaves every areaId as shipped.

.PARAMETER Apply
    Write. Without it the script prints the plan and writes nothing.

.EXAMPLE
    pwsh -NoProfile -File scripts/Merge-DwLayerManifests.ps1 -DistributionRoot C:\demo\distribution -Layer base,surface-swift -SerializeRoot C:\demo\Dynamicweb.Host.Suite\wwwroot\Files\System\Serializer\SerializeRoot

.EXAMPLE
    pwsh -NoProfile -File scripts/Merge-DwLayerManifests.ps1 -DistributionRoot C:\demo\distribution -Layer base,surface-swift -SerializeRoot <root> -SerializerConfigPath <config> -AreaId 3 -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$DistributionRoot,
    [Parameter(Mandatory = $true)][string[]]$Layer,
    [Parameter(Mandatory = $true)][string]$SerializeRoot,
    [string]$SerializerConfigPath,
    [int]$AreaId = 0,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'

$layersDir = Join-Path $DistributionRoot 'layers'
if (-not (Test-Path -LiteralPath $layersDir -PathType Container)) {
    throw "No layers/ folder under $DistributionRoot; pass the Distribution checkout root as -DistributionRoot."
}
$Layer = @($Layer | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($name in $Layer) {
    if (-not (Test-Path -LiteralPath (Join-Path $layersDir $name) -PathType Container)) {
        throw "Layer '$name' not found under $layersDir; read the layer names from layers/INDEX.json."
    }
}

function Read-Json([string]$Path) {
    Get-Content -Raw -LiteralPath $Path -Encoding utf8 | ConvertFrom-Json -DateKind String
}

# Deep-union an exclude map ({ itemType: [names] }) into an ordered accumulator.
function Merge-ExcludeMap($Acc, $Incoming) {
    if (-not $Incoming) { return }
    foreach ($prop in $Incoming.PSObject.Properties) {
        if (-not $Acc.Contains($prop.Name)) { $Acc[$prop.Name] = [System.Collections.Generic.List[string]]::new() }
        foreach ($v in @($prop.Value)) { if ($Acc[$prop.Name] -notcontains "$v") { $Acc[$prop.Name].Add("$v") } }
    }
}
function ConvertTo-PlainMap($Acc) {
    $out = [ordered]@{}
    foreach ($k in $Acc.Keys) { $out[$k] = @($Acc[$k].ToArray()) }
    $out
}

# Rewrite one entry's areaId (and the area token in its entryId) to -AreaId.
function Set-EntryArea($Entry) {
    if ($AreaId -le 0) { return }
    if ($Entry.PSObject.Properties.Name -notcontains 'areaId' -or $null -eq $Entry.areaId) { return }
    $src = [int]$Entry.areaId
    $Entry.areaId = $AreaId
    if ($Entry.PSObject.Properties.Name -contains 'entryId') {
        $Entry.entryId = "$($Entry.entryId)" -replace "area-$src(?=$|/)", "area-$AreaId"
    }
}

$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$modes = @('replace', 'merge')
$plan = [ordered]@{}
$copies = [System.Collections.Generic.List[object]]::new()

foreach ($mode in $modes) {
    $st = @{
        entries = [System.Collections.Generic.List[object]]::new(); index = @{}; owner = @{}
        exclF = [ordered]@{}; exclX = [ordered]@{}; fileOwner = @{}; sum = 0; overrides = 0; layers = [ordered]@{}
    }
    foreach ($name in $Layer) {
        $src = Join-Path (Join-Path $layersDir $name) $mode
        if (-not (Test-Path -LiteralPath $src -PathType Container)) { continue }
        $manPath = Join-Path $src "$mode-manifest.json"
        $count = 0
        if (Test-Path -LiteralPath $manPath -PathType Leaf) {
            $man = Read-Json $manPath
            if ("$($man.schemaVersion)" -ne '2') { throw "$manPath has schemaVersion '$($man.schemaVersion)'; this script merges schemaVersion 2 only." }
            Merge-ExcludeMap $st.exclF $man.excludeFieldsByItemType
            Merge-ExcludeMap $st.exclX $man.excludeXmlElementsByType
            foreach ($e in @($man.entries | Where-Object { $_ })) {
                foreach ($f in @($e.files)) {
                    if ($f -and -not (Test-Path -LiteralPath (Join-Path $src $f) -PathType Leaf)) { $failures.Add("$name/$mode manifest names a missing file: $f") }
                }
                Set-EntryArea $e
                $id = "$($e.entryId)"
                if ($mode -eq 'replace' -and $id -and $st.index.ContainsKey($id)) {
                    $warnings.Add("replace override: entry '$id' from $name wins over $($st.owner[$id])")
                    $st.entries[$st.index[$id]] = $e; $st.owner[$id] = $name; $st.overrides++
                } else {
                    if ($id -and $mode -eq 'merge' -and $st.owner.ContainsKey($id)) {
                        $warnings.Add("merge duplicate: entry '$id' is contributed by $($st.owner[$id]) and $name; each copy re-applies the same YAML")
                    }
                    if ($id) { $st.index[$id] = $st.entries.Count; $st.owner[$id] = $name }
                    $st.entries.Add($e)
                }
                $count++
            }
        } else {
            $warnings.Add("$name/$mode has no $mode-manifest.json; its files are staged but no entry deserializes them")
        }
        $st.sum += $count
        $st.layers[$name] = $count
        foreach ($file in Get-ChildItem -LiteralPath $src -Recurse -File) {
            if ($file.FullName -eq $manPath) { continue }
            $rel = $file.FullName.Substring($src.Length).TrimStart('\', '/')
            if ($st.fileOwner.ContainsKey($rel)) {
                $warnings.Add("$mode file override: '$rel' from $name wins over $($st.fileOwner[$rel]) (staging is last-wins on disk)")
            }
            $st.fileOwner[$rel] = $name
            $copies.Add([pscustomobject]@{ From = $file.FullName; To = Join-Path (Join-Path $SerializeRoot $mode) $rel })
        }
    }
    if ($st.entries.Count -ne ($st.sum - $st.overrides)) {
        $failures.Add("$mode merged $($st.entries.Count) entries, expected $($st.sum) minus $($st.overrides) overrides")
    }
    $plan[$mode] = [ordered]@{
        perLayer = $st.layers; sumOfLayers = $st.sum; replaceOverrides = $st.overrides; merged = $st.entries.Count
        manifest = [ordered]@{
            schemaVersion = 2; mode = $mode; writtenAtUtc = (Get-Date).ToUniversalTime().ToString('o'); complete = $true
            excludeFieldsByItemType = (ConvertTo-PlainMap $st.exclF); excludeXmlElementsByType = (ConvertTo-PlainMap $st.exclX)
            entries = @($st.entries.ToArray())
        }
    }
}

# Union of every layer's config/*.json: predicates in order (same mode+name: later
# layer wins), exclude maps deep-unioned, scalar keys first-seen.
$cfg = [ordered]@{}; $preds = [System.Collections.Generic.List[object]]::new(); $predIndex = @{}
$cfgExclF = [ordered]@{}; $cfgExclX = [ordered]@{}; $cfgFiles = 0
foreach ($name in $Layer) {
    $dir = Join-Path (Join-Path $layersDir $name) 'config'
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    foreach ($cf in Get-ChildItem -LiteralPath $dir -File -Filter '*.json' | Sort-Object Name) {
        $cfgFiles++
        $c = Read-Json $cf.FullName
        foreach ($p in $c.PSObject.Properties) {
            if ($p.Name -like '_*' -or $p.Name -in 'predicates', 'excludeFieldsByItemType', 'excludeXmlElementsByType') { continue }
            if (-not $cfg.Contains($p.Name)) { $cfg[$p.Name] = $p.Value }
        }
        Merge-ExcludeMap $cfgExclF $c.excludeFieldsByItemType
        Merge-ExcludeMap $cfgExclX $c.excludeXmlElementsByType
        foreach ($p in @($c.predicates | Where-Object { $_ })) {
            if ($AreaId -gt 0 -and $p.providerType -eq 'Content' -and $null -ne $p.areaId) { $p.areaId = $AreaId }
            $key = "$("$($p.mode)".ToLowerInvariant())|$($p.name)"
            if ($p.name -and $predIndex.ContainsKey($key)) {
                $warnings.Add("config override: predicate '$($p.mode)/$($p.name)' from $name wins over an earlier layer")
                $preds[$predIndex[$key]] = $p
            } else {
                if ($p.name) { $predIndex[$key] = $preds.Count }
                $preds.Add($p)
            }
        }
    }
}
if ($cfgFiles -gt 0) {
    $cfg['excludeFieldsByItemType'] = ConvertTo-PlainMap $cfgExclF
    $cfg['excludeXmlElementsByType'] = ConvertTo-PlainMap $cfgExclX
    $cfg['predicates'] = @($preds.ToArray())
}

foreach ($w in $warnings) { Write-Warning $w }
$summary = [ordered]@{
    layers = $Layer; areaId = $AreaId; applied = [bool]$Apply
    replace = [ordered]@{ perLayer = $plan.replace.perLayer; merged = $plan.replace.merged; overrides = $plan.replace.replaceOverrides }
    merge = [ordered]@{ perLayer = $plan.merge.perLayer; merged = $plan.merge.merged }
    configPredicates = $preds.Count; filesToStage = $copies.Count; warnings = $warnings.Count; failures = @($failures)
}
if ($failures.Count -gt 0) {
    $summary | ConvertTo-Json -Depth 6
    throw "Staging plan failed $($failures.Count) assert(s); nothing written. Fix the layer checkout before staging."
}
if (-not $Apply) {
    $summary | ConvertTo-Json -Depth 6
    Write-Host 'DRY RUN (default): nothing written. Re-run with -Apply to stage.'
    exit 0
}
if (-not $PSCmdlet.ShouldProcess("$SerializeRoot ($($copies.Count) files, 2 manifests)", 'stage layers')) { exit 0 }

foreach ($c in $copies) {
    New-Item -ItemType Directory -Force -Path (Split-Path $c.To -Parent) | Out-Null
    Copy-Item -LiteralPath $c.From -Destination $c.To -Force
}
foreach ($mode in $modes) {
    if ($plan[$mode].sumOfLayers -eq 0 -and $plan[$mode].merged -eq 0) { continue }
    $modeDir = Join-Path $SerializeRoot $mode
    New-Item -ItemType Directory -Force -Path $modeDir | Out-Null
    $out = Join-Path $modeDir "$mode-manifest.json"
    $plan[$mode].manifest | ConvertTo-Json -Depth 64 | Set-Content -LiteralPath $out -Encoding utf8NoBOM
    # Post-write asserts: the manifest on disk is the merged one, and every file it names is staged.
    $back = Read-Json $out
    if (@($back.entries).Count -ne $plan[$mode].merged) { $failures.Add("$out holds $(@($back.entries).Count) entries, expected $($plan[$mode].merged)") }
    foreach ($e in @($back.entries)) {
        foreach ($f in @($e.files)) {
            if ($f -and -not (Test-Path -LiteralPath (Join-Path $modeDir $f) -PathType Leaf)) { $failures.Add("$mode manifest names a file that is not staged: $f") }
        }
    }
}
if ($SerializerConfigPath -and $cfgFiles -gt 0) {
    New-Item -ItemType Directory -Force -Path (Split-Path $SerializerConfigPath -Parent) | Out-Null
    $cfg | ConvertTo-Json -Depth 64 | Set-Content -LiteralPath $SerializerConfigPath -Encoding utf8NoBOM
}
$summary.failures = @($failures)
$summary | ConvertTo-Json -Depth 6
if ($failures.Count -gt 0) { throw "Staged, but $($failures.Count) post-write assert(s) failed; do not deserialize." }
exit 0
