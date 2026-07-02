# pack-activation.md

## Contents

- [1. What a feature pack is](#1-what-a-feature-pack-is)
- [2. Prerequisites](#2-prerequisites)
- [3. Pack zip anatomy](#3-pack-zip-anatomy)
- [4. Step 1 — Resolve and unzip the pack from the vault](#4-step-1--resolve-and-unzip-the-pack-from-the-vault)
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
> **without editing the base**. This is the consumer-side install path; the harness gate automates
> the same steps for validation, but a demo builder can install a pack by hand with the recipe here.
>
> **Scope: Swift demos only.** Run this AFTER the base baseline deserialize, never before.

## 1. What a feature pack is

A pack is a released `.zip` under the vault's `feature-packs/<name>/<version>/` slot. It carries three
kinds of thing, each landing in a different place on the host:

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
- The `feature-packs` vault slot synced into `$env:DW_VAULT` (landed by the harness vault-sync; see
  the vault `INDEX.md` `feature-packs` row).

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

## 4. Step 1 — Resolve and unzip the pack from the vault

Resolve the release from the `feature-packs` slot and expand it into a working directory. No hardcoded
literals — the vault root is `$env:DW_VAULT`.

```powershell
$packName = "reordering-pricing"    # the pack you are installing
$packVer  = "1.0.0"
$slot     = "$env:DW_VAULT\feature-packs\$packName\$packVer"
if (-not (Test-Path "$slot\pack.json")) {
  throw "Pack '$packName/$packVer' not found (missing pack.json) at `$slot. Check INDEX.md feature-packs row."
}
# The vault slot already holds the unpacked pack (pack.json at slot root). If you have a release .zip
# instead, expand it first: Expand-Archive -Path <pack>.zip -DestinationPath $slot
```

## 5. Step 2 — Read pack.json

`pack.json` is the manifest that drives the install. Read the fields you need before touching the host:

```powershell
$pack = Get-Content "$slot\pack.json" -Raw | ConvertFrom-Json
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
Copy-Item -Recurse "$slot\src\*" "$dropDir\" -Force
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
if (Test-Path "$slot\templates") {
  Copy-Item -Recurse "$slot\templates\*" "$hostRoot\wwwroot\Files\Templates\" -Force
}
if (Test-Path "$slot\itemtypes") {
  Copy-Item -Recurse "$slot\itemtypes\*" "$hostRoot\wwwroot\Files\System\Items\" -Force
}
```

Track exactly what you copy — removing the pack later deletes exactly these files.

## 8. Step 5 — Deserialize the baseline fragment AFTER the base baseline

The fragment is serializer YAML that lands the pack's data. Stage each mode tree named in
`fragmentModes` into the host's `SerializeRoot`, then POST the deserialize — one POST per mode.

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
foreach ($mode in $pack.fragmentModes) {          # e.g. 'seed', or 'deploy','seed'
  $modeSrc = "$slot\baseline-fragment\$mode"
  if (Test-Path $modeSrc) {
    New-Item -ItemType Directory -Path "$serializeRoot\$mode" -Force | Out-Null
    Copy-Item -Recurse "$modeSrc\*" "$serializeRoot\$mode\" -Force
    $resp = Invoke-RestMethod `
      -Uri "https://localhost:$port/Admin/Api/SerializerDeserialize?mode=$mode" `
      -Method POST -Headers @{ Authorization = "Bearer $token" } -SkipCertificateCheck
  }
}
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
