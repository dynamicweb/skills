# deserialize-flow.md

> Deserialize a Swift content baseline from `$env:DW_VAULT\serialized-data\<baseline>\` into the per-demo project DB. Uses `DynamicWeb.Serializer` + Management API. Strict mode is on by default â€” failures surface as `CumulativeStrictModeException`. Always followed by [`integrity-sweep.md`](integrity-sweep.md).
>
> **Scope: Swift demos only.** PIM demos start from a blank/fresh DB and skip this flow entirely. This file is owned by `dynamicweb-swift-demo`; the underlying Serializer install + background reference live in `dynamicweb-demo-base/references/serializer-reference.md`.

## 1. Prerequisites

`dynamicweb-demo-base` setup is complete:

- [`../../dw-demo-base/references/setup-checks.md`](../../dw-demo-base/references/setup-checks.md) is green (DW_VAULT, NODE_TLS_REJECT_UNAUTHORIZED, .NET SDK, ProjectTemplates, SQL Express, vault slot inventory all probed and resolved).
- [`../../dw-demo-base/references/scaffold.md`](../../dw-demo-base/references/scaffold.md) produced a running `Dynamicweb.Host.Suite` (port reachable, host responds at `/admin`).
- [`../../dw-demo-base/references/mcp-setup.md`](../../dw-demo-base/references/mcp-setup.md) verification gate passed (`claude mcp list` shows `dynamicweb-commerce-mcp âœ“ Connected` AND in-conversation `ToolSearch +dynamicweb` returns >200 tools).
- **DynamicWeb.Serializer is installed in the host** per [`../../dw-demo-base/references/serializer-reference.md`](../../dw-demo-base/references/serializer-reference.md) "Installation" section (DLL built + copied to `bin/Debug/net10.0/`, `Files/Serializer.config.json` staged, host restarted). This is a one-time-per-host step.
- A Management API bearer token has been captured via `AskUserQuestion` in the current conversation. Format: `CLAUDE.<hex>`. Token lives in conversation state, never persisted to disk. Do not write the token to any file.

If any of those are unmet, return to the relevant reference before attempting a deserialize. A deserialize against a half-wired host is the fastest way to corrupt a demo's state silently.

## Design-package deploy (before any deserialize)

The baseline's content predicates reference `Swift-v2_*` item types whose XML definitions ship with the **Swift design package**, NOT with the data baseline. Deploy the design package BEFORE running the deserialize â€” without the XMLs on disk every page row fails with `Unable to resolve the item type. The item cannot be saved.` (see Â§9.1).

**Source.** The `dw-swift` vault slot at `$env:DW_VAULT\dw-swift\` (local clone of `https://github.com/dynamicweb/Swift` v2.3.0+; if missing, clone it there).

**Build first.** The repo ships only source SCSS/JS â€” `Assets/css/` and `Assets/js/` are gitignored. Run `npm install` then `npm run build` in `$env:DW_VAULT\dw-swift\` BEFORE copying assets (`node_modules/` is per-machine and not vault-transferred â€” rebuild on each machine). Verify post-build: `Files/Templates/Designs/Swift-v2/Assets/css/swift.css` (~340KB) and `Assets/js/swift.js` (~45KB) plus `Assets/lib/` (Bootstrap/htmx/Alpine vendored deps, 200+ JS files) all exist on disk. Skipping the build leaves the storefront unstyled â€” pages render text-only with broken layout because every Swift template references `/Files/Templates/Designs/Swift-v2/Assets/css/swift.css` which 404s.

**Copy list.** From `$env:DW_VAULT\dw-swift\` to the host's `wwwroot/`:

- `Files/System/Items/*.xml` (the item-type definitions the content predicates need)
- `Files/Templates/Designs/Swift-v2/`
- `Files/System/Styles/`

**Repositories skip rule.** For `Files/System/Repositories/`, copy **everything EXCEPT `ProductsBackend/` and `ProductsFrontend/`** â€” those two index Swift's bike-demo custom fields (`PlantHardiness`, `BikeFrameSize`, plant/bike-specific facets, etc.). Copying them into a host whose products use a different data-model causes `BuildIndex` Full to fail with "field not found in products" â€” the index builder validates every field reference against the live `EcomProductCategoryField` table. The other Swift-shipped indexes (`Content/`, `Files/`, `Post/`, `Secondary users/`) are demo-data-agnostic â€” they index Pages/Files/blog Posts/Users via standard fields plus item-type fields that DO resolve cleanly; copy those alongside. Hand-write a per-demo Products index targeting the demo's actual data-model fields instead â€” see [`../../dw-demo-pim/references/canonical-setup-order.md`](../../dw-demo-pim/references/canonical-setup-order.md) Step 16. (For PIM-data + Swift-frontend hybrid demos with N categories Ã— M custom fields each, pick 5-10 demo-relevant fields per category for the index â€” not the full set; index size is rarely the constraint, but maintenance and admin-UI clarity are.)

**Catalog-paragraph path rewrite (run AFTER the deserialize).** The `eCom_ProductCatalog` paragraphs from the Swift baseline reference `/Files/System/Repositories/ProductsFrontend/Products.query` and `Products.facets` in their `ParagraphModuleSettings` XML. Those paths point into the bike-demo repos you skipped â€” the Catalog module silently renders an empty product list when the paths break. After authoring your per-demo `Products.query` + `Products.facets` (sourced from `Repository="Products"`, with parameters matching your facet fields), bulk-rewrite the paragraph references via SQL:

```sql
UPDATE Paragraph SET ParagraphModuleSettings =
  REPLACE(REPLACE(ParagraphModuleSettings,
    '/Files/System/Repositories/ProductsFrontend/', '/Files/System/Repositories/Products/'),
    '/Files/System/Repositories/ProductsBackend/',  '/Files/System/Repositories/Products/')
WHERE ParagraphModuleSettings LIKE '%ProductsFrontend%' OR ParagraphModuleSettings LIKE '%ProductsBackend%';
```

Restart the host so the paragraph-settings cache reloads. Touched paragraphs are typically the Shop module on Page "Shop", an Express-Buy module, and the Search field's QueryPublisher.

**Card-template path mismatch in `Swift-v2_ProductComponentSlider`.** Swift v2.3.0 ships card templates (`Card.cshtml`, `CardCover.cshtml`, `CardCoverFull.cshtml`, `CardCoverNavInline.cshtml`) at `Files/Templates/Designs/Swift-v2/Paragraph/Swift-v2_Slider/`, but the slider's `RenderRazorTemplate` resolver looks for them at the legacy path `Files/Templates/Paragraph/<filename>`. Symptom: slider div renders the inline error `Template file not found (in RenderRazorTemplate()): ...\Files\Templates\\Paragraph\CardCoverNavInline.cshtml` (note the literal `\\`). Fix: copy the four card files to `Files/Templates/Paragraph/` so the legacy resolver path resolves: `Copy-Item "<host>/wwwroot/Files/Templates/Designs/Swift-v2/Paragraph/Swift-v2_Slider/*.cshtml" "<host>/wwwroot/Files/Templates/Paragraph/" -Force`. No host restart needed â€” Razor template resolution is per-request.

## 2. Step 0 â€” Discover project context

The flow needs three values per project. Read them, never hardcode (the discover-from-project-files rule).

### 2.1 `$port` â€” HTTPS port from `launchSettings.json`

Use the same snippet documented in [`../../dw-demo-base/references/mcp-setup.md`](../../dw-demo-base/references/mcp-setup.md) Section 1 (port-discovery from `Dynamicweb.Host.Suite/Properties/launchSettings.json`). That reference is the single source of truth for port discovery; do not duplicate it here.

After running that snippet, `$port` is populated for use in Section 4 and downstream.

### 2.2 `$db` â€” Database name from `GlobalSettings.Database.config`

```powershell
$cfg = Get-Content "Dynamicweb.Host.Suite/GlobalSettings.Database.config" -Raw
if ($cfg -match '(?:Database|Initial Catalog)\s*=\s*([^;"<]+)') {
  $db = $Matches[1].Trim()
} else {
  $db = Split-Path -Leaf (Get-Location)  # fallback per PIM-skill discovery rule
}
Write-Host "Discovered DB: $db"
```

### 2.3 `$token` â€” Management API bearer token (via `AskUserQuestion`)

Captured via `AskUserQuestion` in the current conversation. Format: `CLAUDE.<hex>`. Keep in conversation state only; never persist. The token is a credential and must not be committed, logged to a file, or echoed into a transcript that survives the session.

## 3. Step 1 â€” Stage baseline YAML from vault

Vault path resolution: every baseline path resolves through `$env:DW_VAULT` (base's path-resolution rule). No hardcoded literals.

**The Serializer reads from `Dynamicweb.Host.Suite/wwwroot/Files/System/Serializer/SerializeRoot/<deploy|seed>/`** (joined from `outputDirectory: "Serializer"` in `Files/Serializer.config.json` + `outputSubfolder` per mode). It does NOT read from a project-root `baselines/` folder. A `baselines/` copy is invisible to the deserialize endpoint and any "121 updated" you see comes from whatever else is already in `SerializeRoot/deploy/` (typically a previous serialize roundtripping itself). Verified during a Swift2 baseline import â€” the original recipe pointed at `baselines/` and silently no-op'd.

**Baseline shape â€” content-only.** The canonical Swift2.2 vault baseline contains ONLY `_content/` (Area + pages + grid-rows + paragraphs + master items, ~640 YAML files). It does **NOT** ship `_sql/`. Framework data (shops, currencies, countries, languages, manufacturers, payments, shippings, VAT groups) must already exist in the target DB before this deserialize runs. The area's YAML hardcodes `"AreaEcomShopId": "SHOP1"` and `"AreaEcomCountryCode": "DE"` as **string FKs** â€” they resolve against whatever rows have those surrogate ids in target. A PIM-set-up host (`dynamicweb-pim-demo`'s blank-DB flow that creates SHOP1, DE, EUR, LANG1) is therefore a clean baseline target â€” the deserialize lands content additively without conflicting with the PIM-curated framework. Hosts missing the framework must run the relevant `dynamicweb-pim-demo` setup steps (`canonical-setup-order.md` Steps 1-4) first.

```powershell
$baseline = "Swift2.2"  # or a customer-flavoured "<demo>-base" baseline once it has been derived (see $env:DW_VAULT\INDEX.md serialized-data row for available baselines)
if (-not (Test-Path "$env:DW_VAULT\serialized-data\$baseline\_content")) {
  throw "Baseline '$baseline' not found (or missing _content/) at `$env:DW_VAULT\serialized-data\$baseline`. Check INDEX.md serialized-data row."
}
$deployRoot = "Dynamicweb.Host.Suite/wwwroot/Files/System/Serializer/SerializeRoot/deploy"
New-Item -ItemType Directory -Path "$deployRoot/_content" -Force | Out-Null
Copy-Item -Recurse "$env:DW_VAULT\serialized-data\$baseline\_content\*" "$deployRoot/_content/" -Force
# Note: no `_sql/` to copy â€” current baseline is content-only by design.
# If a future baseline reintroduces `_sql/`, add the corresponding copy + framework-conflict reasoning back.
```

**Pre-import: re-serialize before merging vault YAML.** If the target host has any pre-existing predicates (e.g. `"Content - <ExistingArea>"`), POST `/Admin/Api/SerializerSerialize` FIRST so the deploy folder reflects current DB state. Otherwise the deserialize will revert any in-DB changes you made since the last serialize (we hit this in practice: a recent area-rename via API was reverted by re-applying stale YAML for the old area name). After serializing, also delete any folders in `_content/` whose name matches a stale area name â€” `Serialize` writes the current name's folder but does NOT clean the old one (e.g. `_content/<old-area-name>/` survives a rename to `_content/<new-area-name>/`).

**Predicate config: each `_content/<AreaName>/` folder needs a matching predicate.** Add a content predicate to `Files/Serializer.config.json` per area you want imported:
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
**`areaId` must be > 0** â€” the validator rejects `0` with `"deploy.predicates[N] is missing required field 'areaId' (must be > 0)"`. For NEW areas not yet in target (e.g. importing Swift2.2's "Swift 2" area onto a host that doesn't have it), pre-create a stub area first via `POST /admin/api/AreaSave` with `Id: 0, Name: "<area name>", ItemType: "Swift-v2_Master", LayoutTemplate: "Designs/Swift-v2/Swift-v2_Page.cshtml"` (and other Swift defaults), capture the assigned numeric id from the response, set the predicate's `areaId` to it, then deserialize. The deserialize will populate the area's pages + paragraphs from the YAML; GUID identity ensures the YAML's `areaId: <GUID>` survives the local numeric-id assignment.

**Restart the host after editing `Serializer.config.json`** â€” config is loaded at startup, not on each request.

**Strategy note (verified during a Swift2 baseline import):** Two strategies were considered â€”

- **(a)** Copy YAML directly into `Dynamicweb.Host.Suite/wwwroot/Files/System/Serializer/SerializeRoot/deploy/` (this snippet â€” verified working).
- **(b)** Configure `Files/Serializer.config.json` `outputDirectory` to point at `$env:DW_VAULT\serialized-data\<baseline>\` directly. Faster (no copy), but the running host's serialize would also write back into the vault â€” destination contamination risk. Not recommended; (a) is the canonical approach.

**Single canonical Swift2.2 path:** `$baseline = "Swift2.2"` resolves to `$env:DW_VAULT\serialized-data\Swift2.2\` â€” the single canonical generic baseline. Per-demo customer-flavoured baselines (named `<demo>-base/` by convention) live alongside `Swift2.2/` in the same `serialized-data/` slot once they have been derived; both share this flow.

## 4. Step 2 â€” POST against running host

```powershell
$resp = Invoke-RestMethod `
  -Uri "https://localhost:$port/Admin/Api/SerializerDeserialize" `
  -Method POST `
  -Headers @{ Authorization = "Bearer $token" } `
  -SkipCertificateCheck
# Strict mode is on by default for API callers (per Serializer README).
# On failure: HTTP 4xx with CumulativeStrictModeException details.
```

**Keep strict mode on; never disable it** by passing a `strictMode` query parameter or body field set to a falsy value. Strict mode is the first line of defence (FK orphans, missing templates, cache failures, schema drift). Disabling it produces a deserialized DB that *looks* succeeded but is silently inconsistent â€” the deserialize-blind failure mode in its purest form.

If the POST returns 4xx with a `CumulativeStrictModeException` body, the body itself is the diagnostic. Read the listed FK orphans / missing templates / schema drift entries; the fix is almost always upstream (the baseline YAML), not on the host. Cross-check `$env:DW_VAULT\INDEX.md`'s `serialized-data` row version stamp to confirm the baseline version matches the host's DW10 version (the baseline-drift self-diagnosis rule).

## 5. Strict-mode contract

For internals (where each category is detected in source), see [`../../dw-demo-base/references/serializer-reference.md`](../../dw-demo-base/references/serializer-reference.md).

Strict mode raises four categories of failure as `CumulativeStrictModeException`:

1. **FK orphans** â€” references to GUIDs that don't exist in the deserialized graph.
2. **Missing templates** â€” `EcomFeed` / `EcomShop` rows referencing template paths that don't exist on disk.
3. **Cache failures** â€” DW caches that fail to invalidate or rebuild during the deserialize.
4. **Schema drift** â€” YAML schemas that don't match the current DW10 EF model.

The integrity sweep ([`integrity-sweep.md`](integrity-sweep.md)) â€” specifically Check 1 (delegated to strict mode) and Check 4 (template-reference walk) â€” adds defense-in-depth. Strict mode covers most cases; the sweep covers DW10-specific completeness rules and GUID dedup that strict mode does not detect.

## 6. Identity model

GUID-based identity. Cross-environment `Default.aspx?ID=N` rewriting is handled by Serializer automatically â€” `ID=` query parameters in YAML are resolved against the destination DB's GUID-to-numeric-id mapping at deserialize time, so the same baseline can be deployed to a fresh DB or to one with existing rows without manual ID surgery.

Use **`Deploy`** mode for the baseline deserialize (baseline overwrites target). **`Seed`** mode is for additive cases â€” out of scope here; the Seed-mode contract is documented in the Serializer README + [`../../dw-demo-base/references/serializer-reference.md`](../../dw-demo-base/references/serializer-reference.md), and a follow-up reference can be authored if a per-demo additive seeding step is needed.

## 7. Post-deserialize host restart guidance

Serializer invalidates caches as part of the strict-mode contract â€” host restart is **not** mandatory. **BUT** `BuildIndex` Full afterwards **IS** mandatory (post-deserialize index staleness) â€” see [`integrity-sweep.md`](integrity-sweep.md) Check 5.

If a host restart turns out to be necessary in practice (for a category not covered by strict mode's cache-invalidation contract), document it in the per-demo `CUSTOMISATIONS.md` so the deviation is visible to the next deserialize on this machine.

## 8. Mandatory next step

After this flow returns 2xx, **immediately run [`integrity-sweep.md`](integrity-sweep.md)**. The skill refuses to declare deserialize complete until the sweep passes.

The sweep is the second line of defence for the failures strict mode does not catch:

- `reference_category` parent row presence (Check 2).
- Query GUID dedup across `Repositories/` vs `SmartSearches/Shared/` (Check 3).
- Defense-in-depth on top of strict mode (Checks 1 and 4).
- `BuildIndex` Full + wait-for-Idle (Check 5).

## 9. Known schema-drift workaround (Swift 2.2 baseline â†” DW10)

With the **content-only** baseline shape, one drift point remains.

Superseded: the baseline ships no `_sql/`, so the former `EcomCurrencies.CurrencyUseCurrencyCodeForFormat` column-strip workaround is obsolete â€” reconstruct from git history if a future baseline reintroduces `_sql/`.
Superseded: same for the former `EcomShopGroupRelation/GROUP253$$SHOP19.yml` orphan-YAML workaround.

### 9.1 â€” Content predicates require Swift v2 item-type XMLs

The baseline's `Content - Swift 2 (...)` predicates reference item types like `Swift-v2_Master`, `Swift-v2_PageProperties`, `Swift-v2_HomePage`, etc. â€” XML files that ship with the **Swift design package**, NOT with the data baseline. If the XMLs are not yet on disk, the Content predicates fail with `Unable to resolve the item type. The item cannot be saved.` for every page. Fix: run Â§"Design-package deploy (before any deserialize)" above (including the ProductsBackend/ProductsFrontend skip rule stated there), then re-run the deserialize unmodified.

Superseded: deploy-design-first is the only viable path â€” the former Approach A ("strip Content predicates") no longer applies with a content-only baseline, and running with strict mode off remains forbidden per Â§4.

### 9.2 â€” Verified clean outcome (content-only)

For a content-only baseline against a PIM-set-up host (SHOP1 + DE + EUR + LANG1 already present), the deserialize POST returns **HTTP 200 with 0 failed predicates**. Counts will be in the shape: ~640 content rows created/updated (one Area row "Swift 2", ~50 Pages, ~150 grid-rows, ~440 paragraphs â€” exact numbers depend on baseline version), 0 framework rows touched. Verify post-deserialize:
- `SELECT COUNT(*) FROM Areas` â†’ +1 (the new "Swift 2" area)
- `SELECT COUNT(*) FROM Page` â†’ ~+50
- Existing PIM data (products, manufacturers, catalog groups, data models, custom field values, EcomDetails image/asset rows) â†’ **untouched**

If the deserialize reports any `EcomShopGroupRelation` / `EcomCurrencies` / `EcomCountries` predicate touching rows, the baseline has reverted to the legacy `_sql/`-shipping shape â€” re-read this file's top-of-Â§3 "Baseline shape" note and reconcile.


