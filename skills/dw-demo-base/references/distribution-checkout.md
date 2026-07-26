# Distribution checkout — the versions prompt, layer resolution, and where each artifact comes from

## Contents

- [Clone model — main IS the version](#clone-model--main-is-the-version)
- [The versions prompt](#the-versions-prompt)
- [Layer resolution — read INDEX.json, never resolve a git tag](#layer-resolution--read-indexjson-never-resolve-a-git-tag)
- [Artifact sources](#artifact-sources)

Everything a demo consumes — layers, editions, the Swift design package — resolves from the
demo's own Distribution checkout. This reference owns that resolution. The routing decision
that precedes it (PIM / Swift / headless path) stays in
[`../SKILL.md`](../SKILL.md) "Baseline data".

## Clone model — main IS the version

Demo artifacts are **not** kept in a shared machine-wide vault. All of them live in ONE consolidated Distribution repo (its URL is per-machine — a default plus the `$env:DW_DISTRIBUTION_REPO` override, below), consumed by **`git clone` + `git pull --ff-only` on `origin/main`** — never a release zip, never a tag checkout. The clone holds `layers/<name>/` (each a layer with a `kind` = base | catalog | feature | theme | surface | sample-data), `editions/<name>.json` (named, gate-proven compositions of layers), and **`layers/INDEX.json`** — the distribution's machine-readable **layer index**, the source of truth for what layers exist, their kind/version/status, and what any retired name was superseded by. **Main IS the version:** consumers pin the latest gate-proven `main`, not a frozen tag. The Distribution supports the current latest Swift release only and rolls forward with it, so there is no re-consumable old state to pin — annotated tags survive as provenance/audit history, never a consumer checkout target. Each demo clones into its own `<demo-root>\distribution\` folder, so two demos on the same machine stay isolated. Reproducibility is the resolved **commit SHA** recorded in `CUSTOMISATIONS.md` (forensics), not a tag. Before any artifact is fetched, ask the user two things (record both in the demo's `CUSTOMISATIONS.md`).

## The versions prompt


1. **DW10 version** — the platform version the demo host runs (drives layer compatibility checks).
2. **Swift version** — e.g. `2.4` (drives the Swift design-package clone tag `v<version>.0`). The Distribution supports the **current latest Swift release only** and rolls forward with it; the current cycle is **Swift 2.4 on DW 10.28.1-PreRelease** (editions attested there; stable re-prove pending).

## Layer resolution — read INDEX.json, never resolve a git tag

**Read `INDEX.json`, never resolve a git tag.** Clone the Distribution once, or `git pull --ff-only` an existing clone up to `origin/main`; then read `layers/INDEX.json`. Assert its `gateProven` block is present — that marker is what says `main` is at a gate-proven tip, not mid-release — and resolve each layer/edition you need from the **live `layers` entries** (`status: active` or `deprecated`). Verify the checked-out `layer.json`'s `swiftVersion` matches the versions prompt (each layer declares the Swift release it targets — the Distribution tracks one at a time, latest-only). If a name you reach for is absent from `layers`, look it up under `retired`: a retired entry names its **`supersededBy`** successor — resolve to that successor, never the dead name (a retired reference must resolve loudly to its successor, never to silence):

```powershell
$repo = if ($env:DW_DISTRIBUTION_REPO) { $env:DW_DISTRIBUTION_REPO } else { "<owner>/<distribution-repo>" }
$dist = "<demo-root>\distribution"
if (Test-Path "$dist\.git") {
  git -C $dist pull --ff-only origin main         # main IS the version — fast-forward to the gate-proven tip
} else {
  git clone "https://github.com/$repo" $dist       # one repo — all layers + editions + INDEX.json live here
}
$index = Get-Content "$dist\layers\INDEX.json" -Raw | ConvertFrom-Json
if (-not $index.gateProven) { throw "INDEX.json has no gateProven marker — main is not at a gate-proven tip; do not consume." }
# Resolve a layer from the live index (retired -> follow supersededBy, never the dead name):
$name  = "surface-swift"                            # the layer (or edition) the demo composes
$entry = $index.layers | Where-Object { $_.name -eq $name }
if (-not $entry) {
  $tomb = $index.retired | Where-Object { $_.name -eq $name }
  if ($tomb) { throw "Layer '$name' is RETIRED -> use $($tomb.supersededBy)" } else { throw "Layer '$name' not in INDEX.json" }
}
# Consume $dist\layers\$name\ ; verify (Get-Content "$dist\layers\$name\layer.json" | ConvertFrom-Json).swiftVersion
# equals the versions-prompt answer (e.g. 2.4.0).
```

Record the resolved **commit SHA** (`git -C $dist rev-parse HEAD`) in `CUSTOMISATIONS.md` — that SHA is the demo's forensic reproducibility stamp (a later rebuild pulls `main` and reads the current `INDEX.json`; the SHA says which gate-proven tip this demo was built against). The clone contains every live layer at that commit; read whichever `layers/<name>/` dirs the edition composes.

## Artifact sources

With those answers, artifacts resolve from the demo's Distribution checkout. The former standalone demo-theme and feature-pack repos are **archived** — their themes and packs are now theme/feature layers in the Distribution:

| Artifact | Source (in the Distribution clone) | Working tree | Consumed by |
|---|---|---|---|
| Serialized base | `layers/base` (kind base) — **framework-only**: 16 framework SQL sets in `replace/_sql/` (countries, currencies, languages, shops, payments, shippings, VAT, order flow/states, AccessUser), **zero content, zero pages, empty catalog by design** | `<demo-root>\distribution\layers\base\` | [`dynamicweb-swift-demo/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) §3 |
| Swift content surface | `layers/surface-swift` (kind surface) — ALL Swift content: both areas (`Swift 2` + `Swift 2 Nederlands`) in `replace/_content/` + `merge/_content/`, `UrlPath` in `replace/_sql/`, and its **own item-type XMLs** (`itemtypes/`, 128 `ItemType_Swift-v2_*.xml`) | `<demo-root>\distribution\layers\surface-swift\` | [`dynamicweb-swift-demo/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) §3 |
| Demo catalog + identities *(optional)* | `layers/sample-data` (kind sample-data) — ships ALL demo content as SQL files (`merge/_sql/catalog.sql`: products / groups / prices; `merge/_sql/identities.sql`: buyer + CSR); editions activate it via `sampleData: true` (e.g. `swift-demo`); otherwise author per-demo via the [`dw-demo-pim`](../../dw-demo-pim/SKILL.md) recipes | `<demo-root>\distribution\layers\sample-data\` | [`dynamicweb-swift-demo/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) §3 |
| Demo theme / style assets | `layers/theme-default` (kind theme — pure disk-overlay `files/`, no serialized DB content). **The ONE presentation layer** — every Swift demo starts from `theme-default` and re-skins on top of it; there is no theme choice and no separate overlay layers (the header-nav affordance CSS ships inside `theme-default`'s `default_custom.css`) | `<demo-root>\distribution\layers\theme-default\` | [`dynamicweb-swift-demo/references/styles-assets.md`](../../dw-demo-swift/references/styles-assets.md) |
| Feature pack | `layers/<name>` (kind feature) | `<demo-root>\distribution\layers\<name>\` | [`dynamicweb-swift-demo/references/pack-activation.md`](../../dw-demo-swift/references/pack-activation.md) |
| Swift design package | local clone of `https://github.com/dynamicweb/Swift` (release tag `v<version>.0` — the upstream Swift product still ships releases) | `<demo-root>\dw-swift\` | [`dynamicweb-swift-demo/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) "Design-package deploy" |

Cloning uses `git` (hence the setup-checks probe that `git` is present, plus `gh` authenticated so a private Distribution repo clones over HTTPS via the gh credential helper). The Distribution repo defaults to the URL above and is overridable per machine via `$env:DW_DISTRIBUTION_REPO` (owner/name form) when a team mirrors or forks it.
