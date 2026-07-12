# deserialize-flow.md

## Contents

- [1. Prerequisites](#1-prerequisites)
- [Design-package deploy (before any deserialize)](#design-package-deploy-before-any-deserialize)
- [2. Step 0 — Discover project context](#2-step-0--discover-project-context)
- [3. Step 1 — Stage baseline YAML from the demo's baselines folder](#3-step-1--stage-baseline-yaml-from-the-demos-baselines-folder)
- [4. Step 2 — POST against running host](#4-step-2--post-against-running-host)
- [5. Strict-mode contract](#5-strict-mode-contract)
- [6. Identity model](#6-identity-model)
- [7. Post-deserialize host restart guidance](#7-post-deserialize-host-restart-guidance)
- [8. Mandatory next step](#8-mandatory-next-step)
- [9. Known schema-drift workaround (Swift 2.4 layers ↔ DW10)](#9-known-schema-drift-workaround-swift-24-layers--dw10)

> Deserialize the Swift layers (framework-only `base` + the `surface-swift` content surface) from the demo's own `<demo-root>\distribution\layers\` checkout into the per-demo project DB. Uses the DW Serializer + Management API. Strict mode is on by default — failures surface as `CumulativeStrictModeException`. Always followed by [`integrity-sweep.md`](integrity-sweep.md).
>
> **Scope: Swift demos only.** PIM demos start from a blank/fresh DB and skip this flow entirely. This file is owned by `dynamicweb-swift-demo`; the underlying Serializer install + background reference live in `dynamicweb-demo-base/references/serializer-reference.md`.

## 1. Prerequisites

`dynamicweb-demo-base` setup is complete:

- [`../../dw-demo-base/references/setup-checks.md`](../../dw-demo-base/references/setup-checks.md) is green (NODE_TLS_REJECT_UNAUTHORIZED, .NET SDK, ProjectTemplates, SQL Express all probed and resolved).
- The Distribution has been **checked out** (`justdynamics/Truvio.Commerce.Distribution` by default; overridable via `$env:DW_DISTRIBUTION_REPO`) at an annotated tag — usually an edition tag like `editions/swift-demo/<semver>`, which pins the `base` + `surface-swift` + `sample-data` + theme layers together — into the demo's own `distribution\` folder (see §3 — the staging snippet clones + checks out on first run). The pin is the checked-out tag, recorded in `CUSTOMISATIONS.md`.
- [`../../dw-demo-base/references/scaffold.md`](../../dw-demo-base/references/scaffold.md) produced a running `Dynamicweb.Host.Suite` (port reachable, host responds at `/admin`).
- [`../../dw-demo-base/references/mcp-setup.md`](../../dw-demo-base/references/mcp-setup.md) verification gate passed (`claude mcp list` shows `dynamicweb-commerce-mcp ✓ Connected` AND in-conversation `ToolSearch +dynamicweb` returns >200 tools).
- **The DW Serializer is installed in the host** per [`../../dw-demo-base/references/serializer-reference.md`](../../dw-demo-base/references/serializer-reference.md) "Installation" section (DLL built + copied to `bin/Debug/net10.0/`, `Files/System/Serializer/Serializer.config.json` staged, host restarted). This is a one-time-per-host step.
- A Management API bearer token has been captured via `AskUserQuestion` in the current conversation. Format: `CLAUDE.<hex>`. Token lives in conversation state, never persisted to disk. Do not write the token to any file.

If any of those are unmet, return to the relevant reference before attempting a deserialize. A deserialize against a half-wired host is the fastest way to corrupt a demo's state silently.

## Design-package deploy (before any deserialize)

The surface's content predicates reference `Swift-v2_*` item types. Their XML definitions ship **with the `surface-swift` layer itself** (`layers/surface-swift/itemtypes/` — 128 `ItemType_Swift-v2_*.xml` files); copy those into the host's `wwwroot/Files/System/Items/` as part of staging (§3). The **Swift design package clone** still supplies everything else on disk — Designs, Styles, icons. Deploy both BEFORE running the deserialize — without the item-type XMLs on disk every page row fails with `Unable to resolve the item type. The item cannot be saved.` (see §9.1).

**Source.** A local clone of `https://github.com/dynamicweb/Swift` (the demo's Swift release tag, e.g. `v2.4.0`). Clone it into `<demo-root>\dw-swift\`, or reuse an existing local clone if one is already on the machine.

**Build first.** The repo ships only source SCSS/JS — `Assets/css/` and `Assets/js/` are gitignored. Run `npm install` then `npm run build` in the Swift clone BEFORE copying assets (`node_modules/` is per-machine — rebuild on each machine). Verify post-build: `Files/Templates/Designs/Swift-v2/Assets/css/swift.css` (~340KB) and `Assets/js/swift.js` (~45KB) plus `Assets/lib/` (Bootstrap/htmx/Alpine vendored deps, 200+ JS files) all exist on disk. Skipping the build leaves the storefront unstyled — pages render text-only with broken layout because every Swift template references `/Files/Templates/Designs/Swift-v2/Assets/css/swift.css` which 404s.

**Copy list.**

From the **`surface-swift` layer** (`<demo-root>\distribution\layers\surface-swift\`) to the host's `wwwroot/`:

- `itemtypes/*.xml` → `Files/System/Items/` (the 128 item-type definitions the content predicates need — the surface owns them; they are no longer sourced from the design-package clone)

From the **Swift clone** (`<demo-root>\dw-swift\`) to the host's `wwwroot/`:

- `Files/Templates/Designs/Swift-v2/`
- `Files/System/Styles/`
- `Files/Images/Icons/` (~80 SVGs incl. `Flags/` and `LoginProviders/` — the set integrity-sweep Check 6 verifies; verified present in the Swift clone. These stock icons are also what `theme-default`'s opt-in nav icons bind to — see [`header-menu.md`](header-menu.md))

**Repositories skip rule.** For `Files/System/Repositories/`, copy **everything EXCEPT `ProductsBackend/` and `ProductsFrontend/`** — those two index Swift's bike-demo custom fields (`PlantHardiness`, `BikeFrameSize`, plant/bike-specific facets, etc.). Copying them into a host whose products use a different data-model causes `BuildIndex` Full to fail with "field not found in products" — the index builder validates every field reference against the live `EcomProductCategoryField` table. The other Swift-shipped indexes (`Content/`, `Files/`, `Post/`, `Secondary users/`) are demo-data-agnostic — they index Pages/Files/blog Posts/Users via standard fields plus item-type fields that DO resolve cleanly; copy those alongside. Hand-write a per-demo Products index targeting the demo's actual data-model fields instead — see [`../../dw-demo-pim/references/canonical-setup-order.md`](../../dw-demo-pim/references/canonical-setup-order.md) Step 16. (For PIM-data + Swift-frontend hybrid demos with N categories × M custom fields each, pick 5-10 demo-relevant fields per category for the index — not the full set; index size is rarely the constraint, but maintenance and admin-UI clarity are.)

**Catalog-paragraph path rewrite (run AFTER the deserialize).** The `eCom_ProductCatalog` paragraphs from the Swift baseline reference `/Files/System/Repositories/ProductsFrontend/Products.query` and `Products.facets` in their `ParagraphModuleSettings` XML. Those paths point into the bike-demo repos you skipped — the Catalog module silently renders an empty product list when the paths break. After authoring your per-demo `Products.query` + `Products.facets` (sourced from `Repository="Products"`, with parameters matching your facet fields), bulk-rewrite the paragraph references via SQL:

```sql
UPDATE Paragraph SET ParagraphModuleSettings =
  REPLACE(REPLACE(ParagraphModuleSettings,
    '/Files/System/Repositories/ProductsFrontend/', '/Files/System/Repositories/Products/'),
    '/Files/System/Repositories/ProductsBackend/',  '/Files/System/Repositories/Products/')
WHERE ParagraphModuleSettings LIKE '%ProductsFrontend%' OR ParagraphModuleSettings LIKE '%ProductsBackend%';
```

Restart the host so the paragraph-settings cache reloads. Touched paragraphs are typically the Shop module on Page "Shop", an Express-Buy module, and the Search field's QueryPublisher.

**Card-template path mismatch in `Swift-v2_ProductComponentSlider`.** Swift v2.3.0 ships card templates (`Card.cshtml`, `CardCover.cshtml`, `CardCoverFull.cshtml`, `CardCoverNavInline.cshtml`) at `Files/Templates/Designs/Swift-v2/Paragraph/Swift-v2_Slider/`, but the slider's `RenderRazorTemplate` resolver looks for them at the legacy path `Files/Templates/Paragraph/<filename>`. Symptom: slider div renders the inline error `Template file not found (in RenderRazorTemplate()): ...\Files\Templates\\Paragraph\CardCoverNavInline.cshtml` (note the literal `\\`). Fix: copy the four card files to `Files/Templates/Paragraph/` so the legacy resolver path resolves: `Copy-Item "<host>/wwwroot/Files/Templates/Designs/Swift-v2/Paragraph/Swift-v2_Slider/*.cshtml" "<host>/wwwroot/Files/Templates/Paragraph/" -Force`. No host restart needed — Razor template resolution is per-request.

## 2. Step 0 — Discover project context

The flow needs three values per project. Read them, never hardcode (the discover-from-project-files rule).

### 2.1 `$port` — HTTPS port from `launchSettings.json`

Use the same snippet documented in [`../../dw-demo-base/references/mcp-setup.md`](../../dw-demo-base/references/mcp-setup.md) Section 1 (port-discovery from `Dynamicweb.Host.Suite/Properties/launchSettings.json`). That reference is the single source of truth for port discovery; do not duplicate it here.

After running that snippet, `$port` is populated for use in Section 4 and downstream.

### 2.2 `$db` — Database name from `GlobalSettings.Database.config`

```powershell
$cfg = Get-Content "Dynamicweb.Host.Suite/GlobalSettings.Database.config" -Raw
if ($cfg -match '(?:Database|Initial Catalog)\s*=\s*([^;"<]+)') {
  $db = $Matches[1].Trim()
} else {
  $db = Split-Path -Leaf (Get-Location)  # fallback per PIM-skill discovery rule
}
Write-Host "Discovered DB: $db"
```

### 2.3 `$token` — Management API bearer token (via `AskUserQuestion`)

Captured via `AskUserQuestion` in the current conversation. Format: `CLAUDE.<hex>`. Keep in conversation state only; never persist. The token is a credential and must not be committed, logged to a file, or echoed into a transcript that survives the session.

## 3. Step 1 — Stage baseline YAML from the demo's baselines folder

Layer path resolution: every layer path resolves under the demo's own `<demo-root>\distribution\layers\<name>\` folder — the per-demo checkout of the Distribution repo (`justdynamics/Truvio.Commerce.Distribution` by default; overridable via `$env:DW_DISTRIBUTION_REPO`) at the pin tag. No hardcoded machine-wide literals.

**The Serializer reads from `Dynamicweb.Host.Suite/wwwroot/Files/System/Serializer/SerializeRoot/<replace|merge>/`** (joined from `outputDirectory: "Serializer"` in `Files/System/Serializer/Serializer.config.json` + `outputSubfolder` per mode). The demo's `distribution\layers\base\` folder is the **checked-out/staging copy only** — the deserialize endpoint never reads it. The snippet below copies `layers\base\` INTO `SerializeRoot/`; that copy step is what makes the content visible. Skipping the copy (or pointing the flow at `layers\base\` directly) silently no-ops — any "121 updated" you then see comes from whatever else is already in `SerializeRoot/replace/` (typically a previous serialize roundtripping itself). Verified during a Swift2 baseline import — the original recipe pointed at the source tree and silently no-op'd.

**Layer shape — the base split (Swift 2.4).** The staging story is a **two-layer composition**, not a single base tree:

- **`base` (kind base) is FRAMEWORK-ONLY.** A replace-only tree (`fragmentModes: ["replace"]`): `replace/_sql/` ships 16 framework SQL sets (EcomCountries, EcomCountryText, EcomCurrencies, EcomLanguages, EcomShops, EcomShopGroupRelation, EcomShopLanguageRelation, EcomPayments, EcomShippings, EcomMethodCountryRelation, EcomVatGroups, EcomVatCountryRelations, EcomOrderFlow, EcomOrderStates, EcomOrderStateRules, AccessUser) plus the machine-readable `base.contract.json` and SQL-predicate config. It ships **zero content, zero pages, zero item types, zero catalog** — a `base`-only deserialize lands an empty storefront skeleton by design.
- **`surface-swift` (kind surface) carries ALL Swift content.** Both areas (`Swift 2` + `Swift 2 Nederlands`) in `replace/_content/` and `merge/_content/`, `UrlPath` in `replace/_sql/`, and its **own item-type XMLs** (`itemtypes/` — 128 `ItemType_Swift-v2_*.xml`). Content-scoped contract bits (content areas, langPrefix, navDepth obligation, page anchors, protected item types) live in its `surface.contract-notes.json`.
- **`sample-data` (kind sample-data) ships ALL demo content as SQL:** `merge/_sql/catalog.sql` (products / groups / prices) + `merge/_sql/identities.sql` (buyer + CSR). Editions activate it via `sampleData: true` (e.g. `swift-demo`); otherwise author the catalog **per-demo** via the PIM modelling recipes ([`../../dw-demo-pim/SKILL.md`](../../dw-demo-pim/SKILL.md)) — do not expect base or surface to supply products (each demo tailors its own catalog rather than inheriting a pre-baked store).

**Composition order: base → sample-data catalog → content surface(s) → feature fragments.** Features FK into surface-carried areas, so the surface must land before any feature fragment. The surface's area YAML hardcodes `"AreaEcomShopId": "SHOP1"` and `"AreaEcomCountryCode": "DE"` as **string FKs** that resolve against the framework rows the base pass lands. **Mode-semantics warning for PIM-curated hosts:** framework rows travel in `replace`, and `replace` is **source-wins** — the base layer's SHOP1/DE/EUR/LANG1 rows UPDATE matching rows already in the target. A host with hand-curated framework rows is therefore NOT automatically preserved: review (and if needed trim) `replace/_sql/` against the target's curated framework data before deserializing.

**Version facts (current cycle):** Swift **2.4** on DW **10.28.1-PreRelease** — the editions (`swift-demo`, `base-only`, `headless-demo`, `dap-portal`) are attested proven on that pair; a stable-release re-prove is pending. The Distribution supports the latest Swift release only and rolls forward with it.

```powershell
$demoRoot = (Get-Location).Path                    # the demo project root
$dist     = "$demoRoot\distribution"               # the demo's own Distribution checkout
if (-not (Test-Path "$dist\.git")) {
  # Clone the single Distribution repo and check out the pin tag (usually an edition tag —
  # see base SKILL "Tag resolution"). Defaults to the Distribution repo; override per
  # machine with $env:DW_DISTRIBUTION_REPO (owner/name).
  $repo = if ($env:DW_DISTRIBUTION_REPO) { $env:DW_DISTRIBUTION_REPO } else { "justdynamics/Truvio.Commerce.Distribution" }
  git clone "https://github.com/$repo" $dist
  $tag = git -C $dist tag --list "editions/swift-demo/*" |
    Sort-Object { [version]($_ -replace '^editions/swift-demo/','') } -Descending | Select-Object -First 1
  git -C $dist checkout $tag                          # the whole snapshot; base + surface-swift + sample-data + ... all present
  Write-Host "Checked out $tag — record it in CUSTOMISATIONS.md (the reproducibility pin)"
}
$serializeRoot = "Dynamicweb.Host.Suite/wwwroot/Files/System/Serializer/SerializeRoot"
# Stage BOTH layers' mode trees: base (framework-only, replace/ only) + surface-swift
# (replace/ + merge/ — all content + UrlPath). The trees are disjoint, so they overlay cleanly.
foreach ($layer in 'base','surface-swift') {
  foreach ($mode in 'replace','merge') {
    if (Test-Path "$dist\layers\$layer\$mode") {
      New-Item -ItemType Directory -Path "$serializeRoot/$mode" -Force | Out-Null
      Copy-Item -Recurse "$dist\layers\$layer\$mode\*" "$serializeRoot/$mode/" -Force
    }
  }
}
# Also copy the surface's item-type XMLs BEFORE deserializing (the content predicates need them):
Copy-Item "$dist\layers\surface-swift\itemtypes\*.xml" `
  "Dynamicweb.Host.Suite/wwwroot/Files/System/Items/" -Force
# The base+surface deserialize lands framework + all Swift content and an EMPTY catalog — run the
# sample-data layer's merge/_sql (activated via an edition's sampleData: true), or author
# the catalog per-demo via dw-demo-pim.
```

**Pre-import: re-serialize before merging baseline YAML.** If the target host has any pre-existing predicates (e.g. `"Content - <ExistingArea>"`), POST `/Admin/Api/SerializerSerialize` FIRST so the replace folder reflects current DB state. Otherwise the deserialize will revert any in-DB changes you made since the last serialize (we hit this in practice: a recent area-rename via API was reverted by re-applying stale YAML for the old area name). After serializing, also delete any folders in `_content/` whose name matches a stale area name — `Serialize` writes the current name's folder but does NOT clean the old one (e.g. `_content/<old-area-name>/` survives a rename to `_content/<new-area-name>/`).

**Renaming an Area re-slugs its frontend URLs.** The area name drives the URL segment, so renaming an Area changes the public URL of every page under it — any bookmark / link / cheat-sheet URL built against the old slug then 404s. Settle the area name **before** publishing links or building the demo's URL list, not after; if a rename is unavoidable late, re-capture the affected URLs.

**Predicate config: each `_content/<AreaName>/` folder needs a matching predicate.** Add a content predicate to `Files/System/Serializer/Serializer.config.json` per area you want imported:
```json
{
  "name": "Content - <Area Name>",
  "providerType": "Content",
  "areaId": <numeric area id in target DB>,
  "path": "/", "pageId": 0,
  "excludes": [], "serviceCaches": [], "xmlColumns": [],
  "excludeFields": [], "excludeXmlElements": [], "excludeAreaColumns": [],
  "includeFields": [], "resolveLinksInColumns": [], "acknowledgedOrphanPageIds": []
}
```
**`areaId` must be > 0** — the validator rejects `0` with `"deploy.predicates[N] is missing required field 'areaId' (must be > 0)"`. For NEW areas not yet in target (e.g. importing Swift2.2's "Swift 2" area onto a host that doesn't have it), pre-create a stub area first via `POST /admin/api/AreaSave` with `Id: 0, Name: "<area name>", ItemType: "Swift-v2_Master", LayoutTemplate: "Designs/Swift-v2/Swift-v2_Page.cshtml"` (and other Swift defaults), capture the assigned numeric id from the response, set the predicate's `areaId` to it, then deserialize. The deserialize will populate the area's pages + paragraphs from the YAML; GUID identity ensures the YAML's `areaId: <GUID>` survives the local numeric-id assignment.

**`excludeAreaColumns` governs serialize-OUT, not deserialize-IN.** The `excludeAreaColumns` field in the predicate above controls which `Area` columns get *written to* `area.yml` when you serialize; it does NOT suppress `source column [Area].[<col>] not present on target schema` drift when *applying* an `area.yml` captured on an older platform to a newer host. Setting it has no effect on an inbound deserialize. Working recovery when an older baseline's `area.yml` carries a column the newer host's schema no longer has: strip the offending column lines from the **staged** copy (`Files/System/Serializer/SerializeRoot/replace/_content/<Area>/area.yml`), never from the checked-out original under `distribution\layers\base\`, then re-POST. Baselines captured on older DW versions can legitimately carry a few such Area columns on a newer host — see the failure-pattern entry in [`../../dw-demo-base/references/serializer-reference.md`](../../dw-demo-base/references/serializer-reference.md) ("source column ... not present on target schema").

**Restart the host after editing `Serializer.config.json`** — config is loaded at startup, not on each request.

**Strategy note (verified during a Swift2 baseline import):** Two strategies were considered —

- **(a)** Copy YAML directly into `Dynamicweb.Host.Suite/wwwroot/Files/System/Serializer/SerializeRoot/replace/` (this snippet — verified working).
- **(b)** Configure `Files/System/Serializer/Serializer.config.json` `outputDirectory` to point at `<demo-root>\distribution\layers\base\` directly. Faster (no copy), but the running host's serialize would also write back into the checked-out layer copy — contaminating your pristine reference of what the repo shipped at that tag. Not recommended; (a) is the canonical approach.

**Single canonical layer paths:** `layers/base` (framework-only) and `layers/surface-swift` (all Swift content) resolve under `<demo-root>\distribution\layers\`. Per-demo customer-flavoured catalogs are authored on top (via the `sample-data` layer, the `swift-demo` edition, or dw-demo-pim), never by forking the base or surface layers. Legacy content-only `Swift2.2` baselines and the pre-split "scaffolding-only base" (content inside `layers/base`) predate this model and are no longer the default.

## 4. Step 2 — POST against running host

**Two POSTs — both with an explicit `?mode=`, replace first then merge.** On engine **0.6.9-beta** each pass must name its mode: `?mode=replace` then `?mode=merge`. **Do NOT rely on a bare `POST /Admin/Api/SerializerDeserialize`** — on 0.6.9 a mode-less POST targets the **legacy `deploy` folder** (not `SerializeRoot/replace/`), and against a layer that stages `replace/`+`merge/` it returns **HTTP 400 `deploy contains no YAML files`**. Pass `?mode=replace` explicitly for the first pass so the engine reads `SerializeRoot/replace/`. (The engine also accepts the legacy `Deploy`/`Seed` names as aliases for `replace`/`merge`.) With base + surface-swift staged (§3), the replace pass lands the base's framework `_sql/` plus the surface's areas/pages/UrlPath (source-wins); the merge pass applies the surface's `merge/_content/` rows. Neither layer carries a catalog — the storefront comes up with an **empty catalog by design**; that is expected, not a missing-products failure. Run the `sample-data` layer's `merge/_sql` (activated via the `swift-demo` edition's `sampleData: true`) or author the catalog per-demo via [`../../dw-demo-pim/SKILL.md`](../../dw-demo-pim/SKILL.md). (The two-POST mechanic still matters generally: feature-pack fragments deserialize in `merge` mode — see [`pack-activation.md`](pack-activation.md).)

```powershell
# Pass 1 — Replace (?mode=replace is REQUIRED on 0.6.9; a bare POST hits the legacy deploy
# folder and 400s "deploy contains no YAML files"). Lands framework + content, source-wins.
$replace = Invoke-RestMethod `
  -Uri "https://localhost:$port/Admin/Api/SerializerDeserialize?mode=replace" `
  -Method POST `
  -Headers @{ Authorization = "Bearer $token" } `
  -SkipCertificateCheck

# Pass 2 — Merge (catalog / field-level). ?mode=merge is REQUIRED — omitting it never runs Merge.
$merge = Invoke-RestMethod `
  -Uri "https://localhost:$port/Admin/Api/SerializerDeserialize?mode=merge" `
  -Method POST `
  -Headers @{ Authorization = "Bearer $token" } `
  -SkipCertificateCheck
# Strict mode is on by default for API callers (per Serializer README).
# Each pass returns HTTP 200 with 0 failed predicates on success.
# On failure: HTTP 4xx with CumulativeStrictModeException details (read the body — it's the diagnostic).
```

(A content-only legacy `Swift2.2` baseline ships no `merge/` tree, so the second POST is a no-op there. Neither `base` nor `surface-swift` ships a sample catalog, so the merge pass lands no products — the catalog comes from `sample-data` or is authored per-demo, never deserialized from base/surface.)

**Keep strict mode on; never disable it** by passing a `strictMode` query parameter or body field set to a falsy value. Strict mode is the first line of defence (FK orphans, missing templates, cache failures, schema drift). Disabling it produces a deserialized DB that *looks* succeeded but is silently inconsistent — the deserialize-blind failure mode in its purest form.

If the POST returns 4xx with a `CumulativeStrictModeException` body, the body itself is the diagnostic. Read the listed FK orphans / missing templates / schema drift entries; the fix is almost always upstream (the baseline YAML), not on the host. Cross-check the checked-out `base` layer's tag against the host's DW10 version (the baseline-drift self-diagnosis rule).

## 5. Strict-mode contract

For internals (where each category is detected in source), see [`../../dw-demo-base/references/serializer-reference.md`](../../dw-demo-base/references/serializer-reference.md).

Strict mode raises four categories of failure as `CumulativeStrictModeException`:

1. **FK orphans** — references to GUIDs that don't exist in the deserialized graph.
2. **Missing templates** — `EcomFeed` / `EcomShop` rows referencing template paths that don't exist on disk.
3. **Cache failures** — DW caches that fail to invalidate or rebuild during the deserialize.
4. **Schema drift** — YAML schemas that don't match the current DW10 EF model.

The integrity sweep ([`integrity-sweep.md`](integrity-sweep.md)) — specifically Check 1 (delegated to strict mode) and Check 4 (template-reference walk) — adds defense-in-depth. Strict mode covers most cases; the sweep covers DW10-specific completeness rules and GUID dedup that strict mode does not detect.

## 6. Identity model

GUID-based identity. Cross-environment `Default.aspx?ID=N` rewriting is handled by Serializer automatically — `ID=` query parameters in YAML are resolved against the destination DB's GUID-to-numeric-id mapping at deserialize time, so the same baseline can be deployed to a fresh DB or to one with existing rows without manual ID surgery.

Use **`replace`** mode for the base deserialize (base overwrites target). **`merge`** mode is for additive cases — out of scope here; the merge-mode contract is documented in the Serializer README + [`../../dw-demo-base/references/serializer-reference.md`](../../dw-demo-base/references/serializer-reference.md), and a follow-up reference can be authored if a per-demo additive seeding step is needed.

## 7. Post-deserialize host restart guidance

Serializer invalidates caches as part of the strict-mode contract — host restart is **not** mandatory. **BUT** a `BuildIndex` afterwards **IS** mandatory (post-deserialize index staleness) — run it by the `.index` Build Name, twice for a 2-instance index, per [`integrity-sweep.md`](integrity-sweep.md) Check 5.

If a host restart turns out to be necessary in practice (for a category not covered by strict mode's cache-invalidation contract), document it in the per-demo `CUSTOMISATIONS.md` so the deviation is visible to the next deserialize on this machine.

### Mandatory consumer obligation — bind the area's commerce columns (DW 10.28+)

After the deserialize (and before declaring the storefront correct), **bind `AreaEcomShopId`, `AreaEcomCurrencyId`, and `AreaEcomLanguageId` explicitly on every content area, then restart the host**. This was always documented as a consumer obligation; on **DW 10.28+ it is mandatory in practice**: the platform resolves an **unbound** area's currency from the area **CULTURE**, not from `CurrencyIsDefault` — an `en-US`-culture area silently prices in **USD** (currency-conversion surprises in cart/checkout on a EUR demo), even though EUR is the default currency. Bind the area currency explicitly; never rely on the fallback:

```sql
UPDATE Area SET AreaEcomShopId = 'SHOP1', AreaEcomCurrencyId = 'EUR', AreaEcomLanguageId = 'LANG1'
WHERE AreaId = <area>;  -- then restart the host (Area rows materialise at startup)
```

### Site root `/` 404s after deserialize — bind `AreaDomain` + `AreaFrontpage` (DW 10.27.x)

A clean deserialize can still leave the **site root (`/`) returning 404** even though every page exists and resolves under its own path — the area just has no root binding. On **DW 10.27.x the root binding is two `Area` columns**, set on the area the root should serve:

- **`Area.AreaDomain`** — the host the area answers on (e.g. `localhost`, or `localhost:<port>`).
- **`Area.AreaFrontpage`** — the numeric page id that `/` renders.

**There is no `AreaDns` table on 10.27.x** — do not look for one; the older DNS-binding table is gone and the binding lives on the `Area` row itself. Set both columns (`UPDATE Area SET AreaDomain = N'localhost', AreaFrontpage = <homePageId> WHERE AreaId = <area>`), then **restart the host** — `Area` rows are materialised at startup, so the new root binding is not live until the bounce (see [`../../dw-demo-base/references/foundational/cache-invalidation.md`](../../dw-demo-base/references/foundational/cache-invalidation.md), the `Area`-row row). These binding columns are per-environment and excluded from serialization, so they arrive unset on a fresh host — set them at provisioning, don't expect them from the baseline.

## 8. Mandatory next step

After this flow returns 2xx, **immediately run [`integrity-sweep.md`](integrity-sweep.md)**. The skill refuses to declare deserialize complete until the sweep passes.

**Also bind the area's commerce columns** (§7 "Mandatory consumer obligation") — `AreaEcomShopId` / `AreaEcomCurrencyId` / `AreaEcomLanguageId` explicitly per area + host restart; on DW 10.28+ an unbound area derives its currency from the area culture (en-US → USD), not `CurrencyIsDefault`.

**Also bind the site root** (§7 "Site root `/` 404s after deserialize") as an explicit post-deserialize step: `AreaDomain` / `AreaFrontpage` are per-environment and excluded from serialization, so `/` 404s until you set them — `UPDATE Area SET AreaDomain = N'localhost', AreaFrontpage = <homePageId> WHERE AreaId = <area>` (or the Management API equivalent), **then restart the host** (Area rows materialise at startup). The integrity sweep's done-condition includes `/` returning 200.

The sweep is the second line of defence for the failures strict mode does not catch:

- `reference_category` parent row presence (Check 2).
- Query GUID dedup across `Repositories/` vs `SmartSearches/Shared/` (Check 3).
- Defense-in-depth on top of strict mode (Checks 1 and 4).
- `BuildIndex` (by the `.index` Build Name, twice for 2-instance indexes) + wait for a fresh successful build on every instance (Check 5).

## 9. Known schema-drift workaround (Swift 2.4 layers ↔ DW10)

The `base` layer ships framework `_sql/` in its `replace/` tree (unlike the content-only `Swift2.2` baselines), but **no catalog `_sql/`** — it is framework-only, zero sample products (see §3). Re-verify the framework `_sql/`-era drift points against a host when adopting a new Swift cycle — the two workarounds below were retired under the content-only shape and may re-apply while framework `_sql/` ships.

Superseded (content-only era): the `EcomCurrencies.CurrencyUseCurrencyCodeForFormat` column-strip and the `EcomShopGroupRelation/GROUP253$$SHOP19.yml` orphan-YAML workarounds were retired when the baseline dropped `_sql/`. With framework `_sql/` shipping again, confirm during a host deserialize whether either recurs; reconstruct specifics from git history if needed.

### 9.1 — Content predicates require Swift v2 item-type XMLs

The surface's `Content - Swift 2 (...)` predicates reference item types like `Swift-v2_Master`, `Swift-v2_PageProperties`, `Swift-v2_HomePage`, etc. — XML files that ship **with the `surface-swift` layer** (`itemtypes/`, copied to `Files/System/Items/` during staging — see §3). If the XMLs are not yet on disk, the Content predicates fail with `Unable to resolve the item type. The item cannot be saved.` for every page. Fix: copy the surface's `itemtypes/*.xml` and run §"Design-package deploy (before any deserialize)" above (including the ProductsBackend/ProductsFrontend skip rule stated there), then re-run the deserialize unmodified.

Superseded: deploy-design-first is the only viable path — the former Approach A ("strip Content predicates") no longer applies with a content-only baseline, and running with strict mode off remains forbidden per §4.

### 9.2 — Verified clean outcome (legacy content-only Swift2.2 baseline)

For a content-only baseline against a PIM-set-up host (SHOP1 + DE + EUR + LANG1 already present), the deserialize POST returns **HTTP 200 with 0 failed predicates**. Counts will be in the shape: ~640 content rows created/updated (one Area row "Swift 2", ~50 Pages, ~150 grid-rows, ~440 paragraphs — exact numbers depend on baseline version), 0 framework rows touched. Verify post-deserialize:
- `SELECT COUNT(*) FROM Areas` → +1 (the new "Swift 2" area)
- `SELECT COUNT(*) FROM Page` → ~+50
- Existing PIM data (products, manufacturers, catalog groups, data models, custom field values, EcomDetails image/asset rows) → **untouched**

Note (Swift 2.4 split): unlike the content-only `Swift2.2` baseline described in this §9.2, the framework-only `base` layer legitimately touches framework rows (`EcomShops`, `EcomCurrencies`, `EcomCountries`, …) via its `replace/_sql/` pass — that is expected, not a reversion. Neither base nor surface ships catalog rows (zero EcomProducts/Groups/Prices), so the deserialize leaves the catalog empty by design; the catalog comes from `sample-data` or is authored per-demo via `dw-demo-pim`. Capture the base+surface replace counts from a host run and record them here once verified.


