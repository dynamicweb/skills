# pack-activation.md

## Contents

- [1. What a feature pack is](#1-what-a-feature-pack-is)
- [2. Prerequisites](#2-prerequisites)
- [3. Pack folder anatomy](#3-pack-folder-anatomy)
- [4. Step 1 — Check out the feature layer from the Distribution](#4-step-1--check-out-the-feature-layer-from-the-distribution)
- [5. Step 2 — Read layer.json](#5-step-2--read-layerjson)
- [6. Step 3 — Source-drop the .cs and build the host](#6-step-3--source-drop-the-cs-and-build-the-host)
- [7. Step 4 — Copy disk overlays](#7-step-4--copy-disk-overlays)
- [8. Step 5 — Deserialize the layer fragment AFTER the base layer](#8-step-5--deserialize-the-layer-fragment-after-the-base-layer)
- [9. Step 6 — Restart and verify](#9-step-6--restart-and-verify)
- [10. Activation model (why this order)](#10-activation-model-why-this-order)
- [11. Removing a pack](#11-removing-a-pack)
- [12. Known per-pack notes](#12-known-per-pack-notes)

> Install a feature layer into a demo host that already has the `base` layer deserialized
> (per [`deserialize-flow.md`](deserialize-flow.md)). A pack layers a self-contained capability —
> source code, disk-overlay templates/item types, and a data fragment — onto the base Swift layer
> **without editing the base**. This is the consumer-side install path; the pack publisher's
> automated validation gate runs the same steps before a release ships, but a demo builder can
> install a pack by hand with the recipe here.
>
> **Scope: Swift demos only.** Run this AFTER the base layer deserialize, never before.

## 1. What a feature pack is

A pack is a **feature layer** — `layers/<name>/` (kind `feature`) in the Distribution repo
(`justdynamics/Truvio.Commerce.Distribution`), pinned by the annotated tag `layers/<name>/<semver>`
(or composed into an `editions/<name>` tag). It lives in the demo's Distribution checkout at
`<demo-root>\distribution\layers\<name>\`; the pin is the checked-out tag, recorded in
`CUSTOMISATIONS.md`. A pack carries three kinds of thing, each landing in a different place on the host:

- **`.cs` source** — compiles INTO the demo host's own build (source-drop, never a separate DLL).
- **Disk overlays** — Razor templates and item-type XML that live on disk under `wwwroot\Files`.
- **A layer fragment** — serializer YAML (data only, zero custom code) that deserializes ON TOP
  of the base layer, adding the pack's rows and pages.

**Packs are catalog-self-sufficient.** Each pack ships its **own demo products** (keyed `PACK-<NAME>-*`)
in its layer fragment, and **never references base catalog rows** — because the
scaffolding-only `base` layer ships **no sample catalog** (see
[`deserialize-flow.md`](deserialize-flow.md) §3), a pack that leaned on base products would have
no data to act on. So a pack's behaviors have their own products even against an empty-catalog
base. A pack never edits base layer YAML. If a change would require rewriting base content, it
is a base-layer improvement, not a pack.

## 2. Prerequisites

- A running demo host (`Dynamicweb.Host.Suite`) with the `base` layer already deserialized
  and green per [`deserialize-flow.md`](deserialize-flow.md) — the fragment's FK targets (areas and
  framework rows) must already exist. The fragment ships its own products, so it does **not** depend on
  base catalog rows (there are none on the scaffolding-only base layer).
- The Serializer installed in the host (same one-time install the deserialize flow depends on).
- A Management API bearer token captured in the current conversation (format `CLAUDE.<hex>`; keep it
  in conversation state, never write it to a file).
- The feature layer present in the demo's Distribution checkout
  (`justdynamics/Truvio.Commerce.Distribution` by default; overridable via `$env:DW_DISTRIBUTION_REPO`)
  at `<demo-root>\distribution\layers\<name>\`, `layer.json` at the folder root — deserialize-flow §3
  already cloned the Distribution; §4 below checks out the layer's tag if it is not in the current
  snapshot. The pin is the checked-out tag.

## 3. Pack folder anatomy

The feature layer (`layers/<name>/` in the Distribution) has everything at its root (no wrapper folder):

```
layers/<name>/                     # a feature layer in the Distribution clone
├── layer.json                     # manifest — layer identity, kind, modes, ledger, config rows
├── README.md                      # human notes
├── src/                           # .cs source ONLY (no .csproj, no .dll)
│   └── *.cs
├── templates/                     # disk-overlay Razor (e.g. Designs/Swift-v2/...; may be empty)
├── itemtypes/                     # disk-overlay item-type definitions (may be empty)
├── merge/                         # present when layer.json fragmentModes contains "merge"
│   ├── merge-manifest.json
│   ├── _sql/<Table>/<key>.yml
│   └── _content/<Area>/<page path>/page.yml       # optional page fragment
└── replace/                       # present when fragmentModes contains "replace"
    ├── replace-manifest.json
    ├── _sql/<Table>/<key>.yml
    └── _content/<Area>/<page path>/page.yml       # optional page fragment
```

The mode trees (`merge/` + `replace/`) sit **at the layer root** (no `baseline-fragment/` wrapper) and
ship **only** the modes named in `layer.json` `fragmentModes`; each carries its own hand-authored
manifest. A pack that ships no code has an empty `src/`; a pack that ships no overlays still keeps the
`templates/` and `itemtypes/` folders present. A pack's own demo products live under
`merge/_sql/EcomProducts/` keyed `PACK-<NAME>-*` — the pack is catalog-self-sufficient (§1), so its
behaviors have data even against the empty-catalog base.

## 4. Step 1 — Check out the feature layer from the Distribution

The Distribution was already cloned by [`deserialize-flow.md`](deserialize-flow.md) §3 into
`<demo-root>\distribution\`, so the feature layer is normally already present at
`<demo-root>\distribution\layers\<name>\`. Pin a specific pack version by checking out its tag
`layers/<name>/<semver>` (or pin an `editions/<name>` tag that composes base + this pack at proven
versions — the preferred demo pin). No hardcoded machine-wide literals — everything lands under the demo root.

```powershell
$packName = "reordering-pricing"    # the feature layer you are installing
$demoRoot = (Get-Location).Path     # the demo project root
$dist     = "$demoRoot\distribution"          # the Distribution checkout (from deserialize-flow §3)
$packDir  = "$dist\layers\$packName"
if (-not (Test-Path "$packDir\layer.json")) {
  # Not in the current snapshot — clone if needed, then check out the layer's latest tag.
  # (Prefer pinning an edition that composes base + this pack.) Override with $env:DW_DISTRIBUTION_REPO.
  $repo = if ($env:DW_DISTRIBUTION_REPO) { $env:DW_DISTRIBUTION_REPO } else { "justdynamics/Truvio.Commerce.Distribution" }
  if (-not (Test-Path "$dist\.git")) { git clone "https://github.com/$repo" $dist }
  $tag = git -C $dist tag --list "layers/$packName/*" |
    Sort-Object { [version]($_ -replace "^layers/$packName/",'') } -Descending | Select-Object -First 1
  git -C $dist checkout $tag
  Write-Host "Checked out $tag — record it in CUSTOMISATIONS.md (the pin)"
}
```

## 5. Step 2 — Read layer.json

`layer.json` is the manifest that drives the install. Read the fields you need before touching the host:

```powershell
$pack = Get-Content "$packDir\layer.json" -Raw | ConvertFrom-Json
$pack.name; $pack.version; $pack.kind; $pack.swiftVersion   # confirm this host's Swift version matches
$pack.fragmentModes                                 # which mode trees to deserialize (merge / replace)
$pack.csLedger                                      # every src/*.cs file + how it registers
$pack.configRows                                    # rows that must exist after install (your verify list)
$pack.customCode                                    # compile-optional provider declaration — read BEFORE §6 (it may let you skip the build entirely)
```

Confirm the host's Swift version matches the layer's `swiftVersion` — a layer proves the version it
claims. If your host's version does not match, stop; the layer is not certified for it.

### The `customCode` declaration — the compile is opt-in

The **base layer is zero custom code** — that constraint is unchanged. A **feature layer MAY ship a
declared, compile-optional provider**: the `.cs` under `src/` is not mandatory to get value from the
layer. `layer.json` states this machine-readably in a **`customCode` block** — **what works without
compiling vs. what the compile adds**:

```jsonc
"customCode": {
  "compileOptional": true,
  "providers": [
    { "file": "src/QtyTierPriceProvider.cs", "registers": "IPriceProvider",
      "worksWithoutCompile": "Contract price (per-customer EcomPrices row) resolves via the native default provider — zero code.",
      "requiresCompileFor": "Quantity-tier enforcement (PriceQuantity > 0 rows), which the stock cart ignores until this provider is compiled in." }
  ]
}
```

**Read this block before §6.** If the demo only needs what every `worksWithoutCompile` covers, **skip
the source-drop + build entirely** — install the layer data-only (overlays + fragment, §7–§8) and stop.
The §6 compile is the **opt-in** step you take *only* when the storyline needs a `requiresCompileFor`
behavior. Record the choice in `CUSTOMISATIONS.md`: the compile is a **declared** customisation-budget
line item (named in `layer.json`), not an ad-hoc controller — that is exactly the boundary the
zero-custom-code base preserves while letting a feature layer offer more when a demo asks for it.

**Worked example — `reordering-pricing`.** Contract pricing (the per-customer price a buyer sees at cart
time) is **native default-provider behavior and needs no compile** — the zero-code headline; author the
per-customer `EcomPrices` row (`PriceUserCustomerNumber`) and it resolves
([`../../dw-demo-base/references/foundational/commerce-b2b.md`](../../dw-demo-base/references/foundational/commerce-b2b.md) "Customer-scoped contract prices"). **Quantity-tier enforcement** (bulk-break
pricing off `PriceQuantity > 0` rows) is what the shipped `IPriceProvider` adds — the stock cart ignores
tier rows until the provider is compiled in
([`../../dw-demo-base/references/foundational/commerce-catalog.md`](../../dw-demo-base/references/foundational/commerce-catalog.md) §2.11). So: install `reordering-pricing` **data-only** to demo contract
pricing; run the §6 opt-in compile **only** when the demo must show qty-tier enforcement.

## 6. Step 3 — Source-drop the .cs and build the host

Packs ship **source only**. The `.cs` files compile into the host's own compilation unit via the
SDK-style implicit `**/*.cs` glob. Copy them to the host's `Layers\<name>\` folder, then build.

```powershell
$hostRoot = "Dynamicweb.Host.Suite"
$dropDir  = "$hostRoot\Layers\$packName"
New-Item -ItemType Directory -Path $dropDir -Force | Out-Null
Copy-Item -Recurse "$packDir\src\*" "$dropDir\" -Force
# Stop the host BEFORE building — a running host locks its exe/DLLs on Windows.
dotnet build $hostRoot -c Debug
```

Drop `.cs` under `Packs\<name>\`, never under `wwwroot\` — the host csproj excludes `wwwroot\Files`
from compilation, so pack code placed there would never build. A pack ships no `.csproj` and no
`.dll`; if you find either in the zip, the pack is malformed — do not install it.

## 7. Step 4 — Copy disk overlays

Templates and item types are disk-overlay files. Copy them into the host's `wwwroot\Files` tree so the
Razor resolver and item-type loader find them.

```powershell
if (Test-Path "$packDir\templates") {
  Copy-Item -Recurse "$packDir\templates\*" "$hostRoot\wwwroot\Files\Templates\" -Force
}
if (Test-Path "$packDir\itemtypes") {
  Copy-Item -Recurse "$packDir\itemtypes\*" "$hostRoot\wwwroot\Files\System\Items\" -Force
}
```

Track exactly what you copy — removing the pack later deletes exactly these files.

## 8. Step 5 — Deserialize the layer fragment AFTER the base layer

The fragment is serializer YAML that lands the pack's data. Stage each mode tree named in
`fragmentModes` into the host's `SerializeRoot`, then POST the deserialize — one POST per mode.

> **STAGE THE FRAGMENT ISOLATED — say it loudly.** A `POST /Admin/Api/SerializerDeserialize?mode=<m>`
> deserializes **everything in `SerializeRoot/<m>/`**, not just the files you copied in. If the base
> layer's trees are still sitting in `SerializeRoot/replace/` and `SerializeRoot/merge/` from the
> §"deserialize-flow.md" run, dropping the fragment alongside them **re-deserializes the base too** —
> and the base `replace` pass is **source-wins**, so it re-applies the base layer's framework rows and
> starter content **on top of whatever you have since authored** (brand areas, edited pages), silently
> reverting your per-demo work. The fragment install turns into a base-layer re-import. (The base
> ships no sample catalog, so nothing "resurrects" catalog-side — the damage is to your authored
> framework/content.) **Park or clear the base trees first, stage the fragment alone, deserialize, then
> restore the base trees** (or just delete the staged fragment). Never POST a deserialize against a
> `SerializeRoot` whose contents you have not just verified are fragment-only.

```powershell
# Bind the running host's HTTPS port and a Management API token BEFORE the loop.
# $token is the CLAUDE.hex captured in the current conversation (see §2); $port is
# the port the host is listening on. Guard both so a copy-paste never POSTs to an
# empty URI (`https://localhost:/...`) or sends a bare `Bearer ` header.
$port  = 5001                               # the running host's HTTPS port
$token = "<CLAUDE.hex from conversation>"   # Management API token captured in §2
if (-not $token -or $token -like '<*') { throw 'Capture a Management API token (CLAUDE.hex) first' }
if (-not $port)  { throw 'Set $port to the running host HTTPS port first' }

$serializeRoot = "$hostRoot\wwwroot\Files\System\Serializer\SerializeRoot"
# ISOLATE: park any base-layer trees out of SerializeRoot so the deserialize sees ONLY the fragment.
$parked = "$hostRoot\wwwroot\Files\System\Serializer\_parked-base"
if (Test-Path $serializeRoot) {
  New-Item -ItemType Directory -Path $parked -Force | Out-Null
  Get-ChildItem $serializeRoot -Directory | Move-Item -Destination $parked -Force
}
foreach ($mode in $pack.fragmentModes) {          # e.g. 'merge', or 'replace','merge'
  $modeSrc = "$packDir\$mode"
  if (Test-Path $modeSrc) {
    New-Item -ItemType Directory -Path "$serializeRoot\$mode" -Force | Out-Null
    Copy-Item -Recurse "$modeSrc\*" "$serializeRoot\$mode\" -Force
    $resp = Invoke-RestMethod `
      -Uri "https://localhost:$port/Admin/Api/SerializerDeserialize?mode=$mode" `
      -Method POST -Headers @{ Authorization = "Bearer $token" } -SkipCertificateCheck
    Remove-Item -Recurse -Force "$serializeRoot\$mode"   # clear the staged fragment before the next mode
  }
}
# RESTORE the parked base trees so a later base re-serialize/deserialize still has them.
if (Test-Path $parked) { Get-ChildItem $parked -Directory | Move-Item -Destination $serializeRoot -Force; Remove-Item $parked -Force }
```

Keep strict mode on (the default) — the fragment must land cleanly against the base graph. `merge`
mode is destination-wins (existing rows preserved, new rows inserted — the natural additive fragment
mode); `replace` mode is source-wins (updates matching keys). The fragment's own manifest defines its
predicates, so a fragment only ever touches the rows and pages it ships.

## 9. Step 6 — Restart and verify

If the pack ships a NEW orderable product (a fragment `EcomProducts` row), restart the host after the
fragment deserialize — the product-catalog cache is built at startup, so a late-seeded product is not
orderable until the next start. Then confirm the install:

- **Config rows exist.** For each `layer.json` `configRows` entry, run its `EXISTS` probe (e.g.
  `SELECT 1 FROM <table> WHERE <where>`) and confirm the row is present.
- **Behavior works.** Exercise the pack's frontend path (an anonymous or signed-in GET of the page it
  ships) and confirm the declared behavior — a marker file appears, a body pattern renders, or a cart
  line carries the pack's price.

A pack that compiles and whose fragment lands but whose behavior never fires is the composition-failure
case — verify behavior, not just presence.

## 10. Activation model (why this order)

The order — source-drop + build, then overlays, then fragment-after-base — follows from how each piece
loads:

- **Code compiles into the host.** There is no separate pack assembly; the `.cs` becomes part of the
  host build. That is why the host must rebuild before the pack's types can run.
- **The fragment is additive and lands last.** Its FK targets (areas, framework rows) must already
  exist, so the base layer deserializes first and the fragment strictly after. The fragment ships
  its own products (base catalog is empty), and never rewrites base YAML — it only adds its own keyed
  rows and pages.
- **Overlays are disk truth.** Templates and item-type XML resolve from disk per request, so they must
  be on disk before the frontend renders the pack's pages.

## 11. Removing a pack

Removal is the mirror of install, tracked exactly — delete the `.cs` you dropped under `Packs\<name>\`,
delete the overlay files you copied into `wwwroot\Files`, delete the fragment rows keyed by what the
fragment inserted (its `_sql` filenames are the row keys; its `_content` pages key by page unique id),
rebuild the host, and restart. Because the fragment only ever added its own keyed rows, a keyed delete
returns the host to its pre-pack state without touching base content.

## 12. Known per-pack notes

Pack-specific behaviors and known limitations to expect after install:

- **subscription-orders** ships its own **disabled** `Place recurring orders` scheduled task in its
  fragment. It arrives disabled deliberately — enable it only when the demo actually exercises
  recurring-order generation, so an idle demo host never fires it. Confirm the task exists (a
  `configRows` probe) and leave it disabled unless the storyline needs it.
- **reordering-pricing** ships a **compile-optional `IPriceProvider`** (see §5 "The `customCode`
  declaration"): **contract pricing works zero-code** (native default provider) and **quantity-tier
  enforcement requires the §6 opt-in compile**. Install data-only unless the demo needs qty-tier
  behavior. It also carries a documented **quick-order known-limitation**: after install the
  quick-order surface may need a **deactivate → reactivate** cycle (toggle it off, then on) before it
  picks up the pack's pricing behavior. This is expected; note it in the demo's `CUSTOMISATIONS.md`
  and cycle the surface as part of the post-install verify (§9) rather than treating it as a failure.
