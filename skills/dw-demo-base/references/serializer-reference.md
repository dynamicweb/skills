# serializer-reference.md

## Contents

- [Installation](#installation)
- [Baseline shape](#baseline-shape)
- [Internals — upstream pointer block](#internals--upstream-pointer-block)
- [Common failure patterns and diagnostics](#common-failure-patterns-and-diagnostics)
- [Versioning and baseline-format compatibility](#versioning-and-baseline-format-compatibility)
- [Cross-references](#cross-references)

> Install + failure-triage reference for the DW Serializer. Owns: the **fact the Serializer exists** for any Dynamicweb demo, **how to install it in the demo host** (one-time-per-host DLL drop + config staging), **common failure patterns**, and **versioning / baseline compatibility**.
>
> **Operational baseline-deserialize steps** (POST `/Admin/Api/SerializerDeserialize`, integrity sweep, schema-drift workarounds) are owned by [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md). Only Swift demos need that flow — PIM demos start from a blank/fresh DB.
>
> **The engine installs from a public NuGet package, not a repo clone.** The Serializer ships as the public NuGet package **`Truvio.Commerce.Serializer`** (**0.6.9-beta or newer**) — add it as a `PackageReference` to the host and restore. There is **no `$env:DW_SERIALIZER_REPO` clone step** and none is required to deserialize; a partner reproduces the whole flow from the package alone. A local clone of the engine repo is **optional**, and only for internals deep-dives — see "Internals — upstream pointer block" below. When this reference disagrees with the engine's published docs, the published docs win (the baseline-drift self-diagnosis rule: skill text is the second source of truth).

## Installation

Add the NuGet package (Step 1), then stage the config (Step 2). Both are per-host — re-run when scaffolding a new demo host or when bumping the engine version. Only run these steps on demos that actually need the Serializer — typically Swift demos that will deserialize a baseline. PIM demos that start from a blank DB can skip installation until/unless they later need to serialize their own work.

### Step 1 — Add the `Truvio.Commerce.Serializer` NuGet package to the host

The engine is the public NuGet package **`Truvio.Commerce.Serializer`** (pin **0.6.9-beta or newer** — the version that ships the `?mode=replace` / `?mode=merge` endpoint aliases and the flat `predicates` config schema this file documents). Add it as a `PackageReference` to `Dynamicweb.Host.Suite` and restore — the engine assembly flows into the host build automatically, so there is **no manual DLL build and no copy into `bin/Debug/<TFM>/`**:

```powershell
dotnet add Dynamicweb.Host.Suite package Truvio.Commerce.Serializer --prerelease   # resolves 0.6.9-beta+
dotnet restore Dynamicweb.Host.Suite
```

Pin an exact version in the csproj (`<PackageReference Include="Truvio.Commerce.Serializer" Version="0.6.9-beta" />`) so a demo reproduces on the same engine it was proven against; bump it deliberately when adopting a newer engine. Restart the host after the restore so the new assembly is loaded. (The package targets net8.0; .NET 10's runtime back-loads net8.0 assemblies fine — no TFM juggling, because NuGet resolves the assembly into the host's own build output.)

### Step 2 — Stage `Files/System/Serializer/Serializer.config.json`

The Serializer requires a config at `<host>/wwwroot/Files/System/Serializer/Serializer.config.json` (version-sensitive — see the path note below). Without one, `/Admin/Api/SerializerDeserialize` returns `Serializer.config.json not found (also checked ContentSync.config.json)`. The predicate config ships **with the layer being deserialized** — the `base` layer carries it under its `config/` tree (`distribution\layers\base\config\swift-2.3.json`); stage that as the starting point (or author one per the flat-`predicates` schema documented in "Replace vs Merge" below):

```powershell
$cfgDir = "Dynamicweb.Host.Suite\wwwroot\Files\System\Serializer"
New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
# The base layer's checked-out config tree (see deserialize-flow.md §3 for the Distribution checkout).
Copy-Item "distribution\layers\base\config\swift-2.3.json" `
          "$cfgDir\Serializer.config.json" -Force
```

**Path note (version-sensitive).** On DW **10.27.4** + Serializer engine **0.6.8-beta** the engine reads the config from `Files/System/Serializer/Serializer.config.json`. Older installs staged it at the `Files/` root (`Files/Serializer.config.json`); the engine's actual read location is what wins, so stage it where the running engine looks. Confirm the location on a given host by where the engine creates `SerializeRoot/` — it lands under `Files/System/Serializer/`, alongside the config (the deserialize flow reads `Files/System/Serializer/SerializeRoot/<deploy|seed>/`).

The shipped config uses the current schema: a single flat `predicates: [...]` list with a per-entry `"mode": "Deploy"|"Seed"` field — see "Deploy vs Seed" below for the schema break vs the legacy `deploy: { predicates: [...] }` shape.

### Verification

After steps 1–2, restart the host. `/Admin/Api/SerializerDeserialize` should respond (a smoke POST typically returns a structured result with `0 predicates` rather than a 404 / config-missing error). Once installed, baseline content is loaded via [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md).

### Replace vs Merge (aliases of Deploy/Seed)

Two **conflict strategies** for the same deserialize pipeline, set per predicate (each entry in the flat `predicates: [...]` list carries `"mode": "Deploy"` or `"mode": "Seed"` — the `DeploymentMode` enum names, unchanged in config). Engine `v0.6.9-beta`+ additionally accepts **`replace`** (= Deploy, source-wins) and **`merge`** (= Seed, field-level) as aliases at the `?mode=` endpoint and as the layer mode-dir names `replace/` + `merge/`; the predicate `"mode"` field keeps the enum spelling. (The legacy `deploy: { predicates: [...] }` / `seed: { ... }` shape is rejected by `ConfigLoader`.)

**Always pass `?mode=` explicitly on 0.6.9 — both passes.** A mode-less `POST /Admin/Api/SerializerDeserialize` on engine 0.6.9-beta targets the **legacy `deploy` folder** rather than `SerializeRoot/replace/`, and returns **HTTP 400 `deploy contains no YAML files`** against a layer that stages `replace/`+`merge/`. Run `?mode=replace` first, then `?mode=merge` — never a bare POST. The two-pass sequence + snippet is owned by [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) §4.

| Mode (dir / alias) | `"mode"` field | Conflict strategy | Use for |
|---|---|---|---|
| **replace** | `Deploy` | Source-wins. Re-deserialize overwrites target. | Developer-owned deployment data: shop structure, item types, VAT rates, country list, payment method definitions. Identical across envs. |
| **merge** | `Seed` | Field-level merge. YAML fills only fields the target has not set; customer edits preserved across re-deploys. | First-run content: Customer Center welcome copy, FAQ body text, newsletter templates. Bootstrap data that transitions to customer ownership. |

For Swift `base` layer restore ([`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md)), the meaningful pass is **replace**; the **merge** pass runs but the base ships no catalog, so it lands nothing (see deserialize-flow §4).

Upstream long-form: the engine's published docs — `concepts.md` "Deploy and Seed modes" / "The three-bucket split" (in the `Truvio.Commerce.Serializer` project repo, optional to clone — see the Internals pointer block).

## Baseline shape

The legacy content-only baseline (`Swift2.2`) shape had **no `_sql/`** (the historical `_sql/` framework rows were deliberately removed: they silently overwrote framework data hosts had already built via the PIM-skill flow). One top-level subfolder: `_content/`, a mirror tree of the DW area→page→gridRow→paragraph hierarchy, one YAML file per node (folder = page; files = `area.yml`, `page.yml`, `grid-row.yml`, `paragraph-<col>-<n>.yml`). Hosts that need a baseline framework should run [`../../dw-demo-pim/references/canonical-setup-order.md`](../../dw-demo-pim/references/canonical-setup-order.md) Steps 1-4 before this deserialize. The runtime contract is [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) §3 "Baseline shape".

## Internals — upstream pointer block

Architecture, source layout, pipeline walkthrough, YAML schema details, strict-mode internals, the identity model (GUID-based `PageUniqueId` identity with per-environment numeric ID resolution), link-resolution passes, runtime exclusions, and the tools folder (`purge-cleandb.sql`, `swift22-cleanup/`, e2e harness, smoke tests, the Swift 2.2 bacpac) are all documented canonically in the engine's own repository — **do not rely on a paraphrase here; the engine docs win**. Installing the demo host does **not** require this clone (the NuGet package alone deserializes); clone it **only** for an internals deep-dive. If you keep a local clone (set `$env:DW_SERIALIZER_REPO` to its root, User scope, per `references/setup-checks.md` §4), these are the canonical entry points:

- `docs\` — README → `concepts.md` → `strict-mode.md` (full warning-source table, override precedence, cache-registry extension recipe) → `link-resolution.md` → `troubleshooting.md` → `configuration.md` → `runtime-exclusions.md` → `sql-tables.md` → `permissions.md` → `cicd.md`
- `src\<project>\` — source (the single project folder under `src\`); `Providers\SerializerOrchestrator.cs` is the entry point
- `tools\` — each tool subfolder carries its own README. **DB fast-restore (escape-hatch alternative to deserialize)** is a per-machine local artifact: if you keep a clean-DB bacpac / `.mdf` snapshot on the box, note its location in the demo's own notes and restore from there — there is no shared vault slot for it. A bacpac copy inside the engine repo's tools folder is a development convenience, not a canonical resolution target.

Note: the DW10 platform source clone is NOT the Serializer — the Serializer source lives only in the `Truvio.Commerce.Serializer` repo (the one the NuGet package is published from), and cloning it is optional.

Two operational facts worth keeping in mind without loading upstream docs:

- **Strict-mode default**: Cli / Api entry points default strict-mode **on**; AdminUi defaults off. Request parameter overrides config value overrides entry-point default. The Swift deserialize flow forbids disabling strict mode for API callers — `?strictMode=false` is a deliberate override of the safety contract.
- **Failure response shape**: when strict mode escalates, the API returns a non-2xx whose body starts `Deserialization failed: Strict mode: N warning(s) escalated to failure:` followed by one `- <verbatim warning>` line per accumulated warning. Read the body — each warning prefix maps to a failure pattern below; do not retry blindly.

## Common failure patterns and diagnostics

### "FK orphan on EcomGroupId" (or any FK warning)

**Symptom:** `WARNING: Could not re-enable FK constraints for [EcomShopGroupRelation]: ... FOREIGN KEY constraint "DW_FK_..."`.

**What happened:** A SqlTable predicate wrote rows whose FK column points at a parent row that doesn't exist on the target.

**Diagnostics:**

```sql
-- Substitute the actual FK columns + tables from the warning
SELECT r.*
FROM [EcomShopGroupRelation] r
WHERE NOT EXISTS (
  SELECT 1 FROM [EcomShops] s WHERE s.ShopId = r.ShopGroupShopId
);
```

**Fix paths:**

1. Clean source: delete the orphan row from the source DB and re-serialize. For Swift 2.2 reference, `tools/swift22-cleanup/06-delete-orphan-ecomshopgrouprelation.sql` is the canonical fix.
2. Exclude offending rows: add a `where` clause to the predicate that filters them out.
3. Include the missing parent: extend the parent table's predicate so the parent row gets serialized first.

### "Unresolvable page ID 3421 in link"

**Symptom:** Strict-mode body contains `Unresolvable page ID N in link`.

**What happened:** Source YAML references page N via `Default.aspx?ID=N`, but page N's `PageUniqueId` isn't in the target's `PageGuidCache` (page wasn't deserialized — wrong predicate path, wrong mode, or stale baseline).

**Diagnostics:**

```sql
-- Find the referencing field on the source DB
SELECT * FROM [ItemType_Swift-v2_Logo]
WHERE Link LIKE '%Default.aspx?%=3421%';
```

**Fix paths:**

1. Extend the Content predicate `path` so page 3421 is included in Replace mode.
2. Move the referencing page (or referenced page) into the same mode if they're split across Deploy/Seed.
3. Clean source: null the dangling reference. For Swift 2.2, `tools/swift22-cleanup/01-null-orphan-page-refs.sql` is the canonical fix.
4. Acknowledge the orphan (escape hatch): add the ID to the predicate's `acknowledgedOrphanPageIds` array. Demotes the fatal serialize error to a warning. Remove the entry once the data is clean — leaving acknowledged IDs around silences real future drift.

### "source column [T].[C] not present on target schema"

**Symptom:** `WARNING: source column [EcomShops].[ShopNewField] not present on target schema — skipping`.

**What happened:** Source DW host is on a different `Dynamicweb.Suite` NuGet version than the target. The source has a column the target's `UpdateProvider` hasn't created yet.

**Fix paths:**

1. Align NuGet versions: bump the target's `Dynamicweb.Suite` to match source, `dotnet publish`, restart. DW runs pending `UpdateProvider` classes at startup. (This NuGet-alignment / startup-migration crossover is platform-generic — owned by [`foundational/setup-upgrade.md`](foundational/setup-upgrade.md) "Schema-drift across NuGet versions"; see it too if a `UpdateProvider` itself is broken.)
2. Drop the column on source: align downward instead of upward.
3. Accept the drift: the column is silently dropped from MERGE, the rest of the row writes correctly. Lenient mode only.

**Area-column drift specifically (older baseline → newer host).** When the offending column is on `[Area]` (e.g. an `area.yml` captured on an older platform), the predicate's `excludeAreaColumns` setting does NOT help — it governs serialize-OUT (which Area columns get *written*), not deserialize-IN. Strip the offending column from the **staged** `Files/System/Serializer/SerializeRoot/deploy/_content/<Area>/area.yml` (never the downloaded original under `baselines\`) and re-POST. See the deserialize flow's §3 note: [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md).

### "template 'T' not found at Files/Templates/T"

**Symptom:** `WARNING: template 'eCom_Catalog' not found at Files/Templates/eCom_Catalog.cshtml`.

**What happened:** YAML references a page-layout / grid-row / item-type template that isn't on the target's filesystem. Templates ship as filesystem state (Swift git clone), not DB state.

**Fix paths:**

1. Deploy the missing template alongside the DLL (filesystem rsync / git pull / Azure Files sync).
2. Null the stale reference on source. For Swift 2.2, `tools/swift22-cleanup/05-null-stale-template-refs.sql` covers three known-stale templates (`1ColumnEmail`, `2ColumnsEmail`, `Swift-v2_PageNoLayout.cshtml`).

## Versioning and baseline-format compatibility

The Serializer's API surface (Management API commands, predicate shape, YAML format) is **stable for the current release line** (per upstream README). Config schema and runtime-exclusion defaults may evolve before 1.0.

### How to tell if a baseline is too old

Three signals:

1. **`SourcePageId` missing** from page YAML → baseline pre-dates the Serializer's cross-environment link-rewriting support. Re-serialize from a current Serializer version.
2. **Legacy `deploy: { predicates: [...] }` / `seed: { ... }` config shape** → older config schema. ConfigLoader rejects with a clear error pointing at the current flat `predicates: [...]` list with per-predicate `"mode": "Deploy" | "Seed"`. Migrate the config; YAML payloads are unchanged.
3. **`UpdateVersion_ecom.xml` style update tracking** → pre-DW-9.14 era. Not a Serializer issue per se; affects the host DW10's update-manager queue (see `references/db-update-recovery.md`).

### How baselines roll

Baseline rolls happen out-of-band — when Dynamicweb ships a new Swift release, the `base` layer gets re-serialized from a fresh Swift install and published as a new annotated tag `layers/base/<semver>` in the Distribution repo (`justdynamics/Truvio.Commerce.Distribution`). The demo pins the exact **tag** it checked out. That tag is the stamp; cross-check it against the demo's host DW10 version when triaging schema-drift warnings (the baseline-drift self-diagnosis rule).

## Cross-references

| If you need... | Read |
|---|---|
| Install the Serializer in the demo host (build DLL, copy to bin, stage config) | "Installation" section above |
| Run a baseline content deserialize (Swift demos only) | [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) |
| Post-deserialize integrity checks | [`../../dw-demo-swift/references/integrity-sweep.md`](../../dw-demo-swift/references/integrity-sweep.md) |
| Recover from DW10 update-queue bugs (independent of Serializer) | `references/db-update-recovery.md` |
| Install the engine into the host | NuGet `Truvio.Commerce.Serializer` (0.6.9-beta+) — "Installation" Step 1 above (no repo clone) |
| Serializer internals — architecture, YAML schema, strict mode, link resolution, tools (canonical) | the `Truvio.Commerce.Serializer` engine repo `docs\` + source — an **optional** clone ("Internals — upstream pointer block" above) |


