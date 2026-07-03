# pack-activation.md

## Contents

- [1. What a feature pack is](#1-what-a-feature-pack-is)
- [2. Prerequisites](#2-prerequisites)
- [3. Pack zip anatomy](#3-pack-zip-anatomy)
- [4. Step 1 — Download and unzip the pack release](#4-step-1--download-and-unzip-the-pack-release)
- [5. Step 2 — Read pack.json](#5-step-2--read-packjson)
- [6. Step 3 — Source-drop the .cs and build the host](#6-step-3--source-drop-the-cs-and-build-the-host)
- [7. Step 4 — Copy disk overlays](#7-step-4--copy-disk-overlays)
- [8. Step 5 — Deserialize the baseline fragment AFTER the base baseline](#8-step-5--deserialize-the-baseline-fragment-after-the-base-baseline)
- [9. Step 6 — Restart and verify](#9-step-6--restart-and-verify)
- [10. Activation model (why this order)](#10-activation-model-why-this-order)
- [11. Removing a pack](#11-removing-a-pack)

> Install a feature pack into a demo host that already has the `swift-2.3` baseline deserialized
> (per [`deserialize-flow.md`](deserialize-flow.md)). A pack layers a self-contained capability —
> source code, disk-overlay templates/item types, and a data fragment — onto the base Swift baseline
> **without editing the base**. This is the consumer-side install path; the pack publisher's
> automated validation gate runs the same steps before a release ships, but a demo builder can
> install a pack by hand with the recipe here.
>
> **Scope: Swift demos only.** Run this AFTER the base baseline deserialize, never before.

## 1. What a feature pack is

A pack is a released `.zip` (release tag `packs/<name>/<version>`) from the feature-pack distribution
repo your team designates. It carries three kinds of thing, each landing in a different place on the host:

- **`.cs` source** — compiles INTO the demo host's own build (source-drop, never a separate DLL).
- **Disk overlays** — Razor templates and item-type XML that live on disk under `wwwroot\Files`.
- **A baseline fragment** — serializer YAML (data only, zero custom code) that deserializes ON TOP
  of the base baseline, adding the pack's rows and pages.

A pack never edits base baseline YAML. If a change would require rewriting base content, it is a
baseline improvement, not a pack.

## 2. Prerequisites

- A running demo host (`Dynamicweb.Host.Suite`) with the `swift-2.3` baseline already deserialized
  and green per [`deserialize-flow.md`](deserialize-flow.md) — the fragment's FK targets (products,
  areas, framework rows) must already exist.
- The Serializer installed in the host (same one-time install the deserialize flow depends on).
- A Management API bearer token captured in the current conversation (format `CLAUDE.<hex>`; keep it
  in conversation state, never write it to a file).
- The pack release downloaded from the feature-pack distribution repo
  (`justdynamics/Truvio.Commerce.FeaturePacks` by default; overridable via `$env:DW_PACKS_REPO`) and
  unpacked into the demo's own `baselines\feature-packs\<name>\<version>\` folder, `pack.json` at the
  folder root — see §4, which downloads it on first run.

## 3. Pack zip anatomy

The release `.zip` unpacks with everything at the root (no wrapper folder):

```
<pack-name>/                       # zip root
├── pack.json                      # manifest — pack identity, modes, ledger, config rows
├── README.md                      # human notes
├── src/                           # .cs source ONLY (no .csproj, no .dll)
│   └── *.cs
├── templates/                     # disk-overlay Razor (e.g. Designs/Swift-v2/...; may be empty)
├── itemtypes/                     # disk-overlay item-type definitions (may be empty)
└── baseline-fragment/             # serializer YAML fragment — data only
    ├── seed/                      # present when pack.json fragmentModes contains "seed"
    │   ├── seed-manifest.json
    │   ├── _sql/<Table>/<key>.yml
    │   └── _content/<Area>/<page path>/page.yml   # optional page fragment
    └── deploy/                    # present when fragmentModes contains "deploy"
        ├── deploy-manifest.json
        ├── _sql/<Table>/<key>.yml
        └── _content/<Area>/<page path>/page.yml   # optional page fragment
```

`baseline-fragment/` ships **only** the mode trees named in `pack.json` `fragmentModes`; each mode
tree carries its own hand-authored manifest. A pack that ships no code has an empty `src/`; a pack
that ships no overlays still keeps the `templates/` and `itemtypes/` folders present.

## 4. Step 1 — Download and unzip the pack release

Download the pack's release `.zip` from the feature-pack distribution repo
(`justdynamics/Truvio.Commerce.FeaturePacks` by default) and expand it into the demo's own
`baselines\feature-packs\` folder. No hardcoded machine-wide literals — everything lands under the
demo root.

```powershell
$packName = "reordering-pricing"    # the pack you are installing
$packVer  = "1.0.0"
$demoRoot = (Get-Location).Path     # the demo project root
$packDir  = "$demoRoot\baselines\feature-packs\$packName\$packVer"
if (-not (Test-Path "$packDir\pack.json")) {
  # Download the pack release (tag packs/<name>/<version>) from the feature-pack
  # distribution repo, then unzip so pack.json sits at the folder root.
  # Defaults to the ecosystem repo; override per machine with $env:DW_PACKS_REPO (owner/name).
  $repo = if ($env:DW_PACKS_REPO) { $env:DW_PACKS_REPO } else { "justdynamics/Truvio.Commerce.FeaturePacks" }
  New-Item -ItemType Directory -Path $packDir -Force | Out-Null
  gh release download "packs/$packName/$packVer" --repo $repo --pattern '*.zip' --dir $packDir
  Expand-Archive -Path "$packDir\*.zip" -DestinationPath $packDir -Force
  Remove-Item "$packDir\*.zip"
}
# If you were handed a release .zip directly instead, expand it the same way:
# Expand-Archive -Path <pack>.zip -DestinationPath $packDir
```

## 5. Step 2 — Read pack.json

`pack.json` is the manifest that drives the install. Read the fields you need before touching the host:

```powershell
$pack = Get-Content "$packDir\pack.json" -Raw | ConvertFrom-Json
$pack.name; $pack.version; $pack.swiftCompatRange   # confirm this host's Swift version is in range
$pack.fragmentModes                                 # which mode trees to deserialize (seed / deploy)
$pack.csLedger                                      # every src/*.cs file + how it registers
$pack.configRows                                    # rows that must exist after install (your verify list)
```

Confirm the host's Swift version is listed in `swiftCompatRange` — a pack proves the versions it
claims. If your host's version is not in range, stop; the pack is not certified for it.

## 6. Step 3 — Source-drop the .cs and build the host

Packs ship **source only**. The `.cs` files compile into the host's own compilation unit via the
SDK-style implicit `**/*.cs` glob. Copy them to the host's `Packs\<name>\` folder, then build.

```powershell
$hostRoot = "Dynamicweb.Host.Suite"
$dropDir  = "$hostRoot\Packs\$packName"
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

## 8. Step 5 — Deserialize the baseline fragment AFTER the base baseline

The fragment is serializer YAML that lands the pack's data. Stage each mode tree named in
`fragmentModes` into the host's `SerializeRoot`, then POST the deserialize — one POST per mode.

> **STAGE THE FRAGMENT ISOLATED — say it loudly.** A `POST /Admin/Api/SerializerDeserialize?mode=<m>`
> deserializes **everything in `SerializeRoot/<m>/`**, not just the files you copied in. If the base
> baseline's trees are still sitting in `SerializeRoot/deploy/` and `SerializeRoot/seed/` from the
> §"deserialize-flow.md" run, dropping the fragment alongside them **re-deserializes the base seed too** —
> and on a host you have since **re-contented** (purged the sample catalog, authored brand data), the seed
> pass **resurrects the entire purged sample catalog** on top of your brand content. The fragment install
> silently turns into a base-baseline re-import. **Park or clear the base trees first, stage the fragment
> alone, deserialize, then restore the base trees** (or just delete the staged fragment). Never POST a
> deserialize against a `SerializeRoot` whose contents you have not just verified are fragment-only.

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
# ISOLATE: park any base-baseline trees out of SerializeRoot so the deserialize sees ONLY the fragment.
$parked = "$hostRoot\wwwroot\Files\System\Serializer\_parked-base"
if (Test-Path $serializeRoot) {
  New-Item -ItemType Directory -Path $parked -Force | Out-Null
  Get-ChildItem $serializeRoot -Directory | Move-Item -Destination $parked -Force
}
foreach ($mode in $pack.fragmentModes) {          # e.g. 'seed', or 'deploy','seed'
  $modeSrc = "$packDir\baseline-fragment\$mode"
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

Keep strict mode on (the default) — the fragment must land cleanly against the base graph. `seed`
mode is destination-wins (existing rows preserved, new rows inserted — the natural additive fragment
mode); `deploy` mode is source-wins (updates matching keys). The fragment's own manifest defines its
predicates, so a fragment only ever touches the rows and pages it ships.

## 9. Step 6 — Restart and verify

If the pack ships a NEW orderable product (a fragment `EcomProducts` row), restart the host after the
fragment deserialize — the product-catalog cache is built at startup, so a late-seeded product is not
orderable until the next start. Then confirm the install:

- **Config rows exist.** For each `pack.json` `configRows` entry, run its `EXISTS` probe (e.g.
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
- **The fragment is additive and lands last.** Its FK targets (base products, areas, framework rows)
  must already exist, so the base baseline deserializes first and the fragment strictly after. The
  fragment never rewrites base YAML — it only adds its own keyed rows and pages.
- **Overlays are disk truth.** Templates and item-type XML resolve from disk per request, so they must
  be on disk before the frontend renders the pack's pages.

## 11. Removing a pack

Removal is the mirror of install, tracked exactly — delete the `.cs` you dropped under `Packs\<name>\`,
delete the overlay files you copied into `wwwroot\Files`, delete the fragment rows keyed by what the
fragment inserted (its `_sql` filenames are the row keys; its `_content` pages key by page unique id),
rebuild the host, and restart. Because the fragment only ever added its own keyed rows, a keyed delete
returns the host to its pre-pack state without touching base content.
