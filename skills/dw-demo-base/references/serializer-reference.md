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
> **Tool internals live upstream.** The Serializer ships its own canonical docs at `$env:DW_SERIALIZER_REPO\docs\` — when this reference disagrees with upstream, upstream wins (the baseline-drift self-diagnosis rule: skill text is the second source of truth). See "Internals — upstream pointer block" below.

## Installation

Resolve the repo first (Step 0), then build, copy, stage. The build is one-time per machine; the DLL copy + config staging are per-host (re-run when scaffolding a new demo host or when the Serializer DLL is rebuilt). Only run these steps on demos that actually need the Serializer — typically Swift demos that will deserialize a baseline. PIM demos that start from a blank DB can skip installation until/unless they later need to serialize their own work.

### Step 0 — Resolve the Serializer repo (never hardcode the path or the DLL filename)

The Serializer repo location is machine-specific, and its folder and assembly name have changed across releases — resolve both instead of hardcoding either. Set `$env:DW_SERIALIZER_REPO` (User scope, same dual-set env-var pattern documented in `references/setup-checks.md` §4) to the local clone root, and derive the project folder and DLL filename from the repo itself. A hardcoded directory fails at build time when the repo is renamed; a hardcoded DLL filename fails the copy step even when the directory resolves — the assembly filename follows the csproj `AssemblyName`, which renames with the product. (The Serializer is a tool — a per-machine local clone, its location asked/discovered, never hardcoded.)

```powershell
if (-not $env:DW_SERIALIZER_REPO -or -not (Test-Path "$env:DW_SERIALIZER_REPO\src")) {
  throw "DW_SERIALIZER_REPO not set (or not a Serializer clone). Point it at the local Serializer repo root."
}
$serializerProj = Get-ChildItem "$env:DW_SERIALIZER_REPO\src" -Directory | Select-Object -First 1
```

### Step 1 — Build the Serializer DLL (one-time per machine, when source updates)

```powershell
dotnet build $serializerProj.FullName -c Release
```

### Step 2 — Copy DLL to host's TFM-specific bin folder

For a `dotnet run` host, .NET loads assemblies from `bin/Debug/<TFM>/` of the TARGET project, not from a generic `bin/` root. With the host pinned to `net10.0` (per [`foundational/setup-install.md`](foundational/setup-install.md) §2), the destination is `bin/Debug/net10.0/`:

```powershell
$dll = Get-ChildItem "$($serializerProj.FullName)\bin\Release\net8.0" -Filter '*Serializer*.dll' |
       Select-Object -First 1   # derive the filename — it follows the csproj AssemblyName
Copy-Item $dll.FullName "Dynamicweb.Host.Suite\bin\Debug\net10.0\" -Force
```

The DLL is built net8.0 (Serializer ships single-target net8.0 per its csproj). .NET 10's runtime back-loads net8.0 assemblies fine. Restart the host after the copy so the new DLL is picked up. Note: the README and `docs/getting-started.md` still say "copy to `/path/to/your-dw-host/bin/`" — that's the published-deployment shape and does NOT work for local `dotnet run` hosts; always use the TFM subfolder.

### Step 3 — Stage `Files/System/Serializer/Serializer.config.json`

The Serializer requires a config at `<host>/wwwroot/Files/System/Serializer/Serializer.config.json` (version-sensitive — see the path note below). Without one, `/Admin/Api/SerializerDeserialize` returns `Serializer.config.json not found (also checked ContentSync.config.json)`. The Serializer repo ships a canonical Swift 2.2 baseline config in the project's `Configuration\` folder — copy that as the starting point:

```powershell
$cfgDir = "Dynamicweb.Host.Suite\wwwroot\Files\System\Serializer"
New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
Copy-Item "$($serializerProj.FullName)\Configuration\swift2.2-combined.json" `
          "$cfgDir\Serializer.config.json" -Force
```

**Path note (version-sensitive).** On DW **10.27.4** + Serializer engine **0.6.8-beta** the engine reads the config from `Files/System/Serializer/Serializer.config.json`. Older installs staged it at the `Files/` root (`Files/Serializer.config.json`); the engine's actual read location is what wins, so stage it where the running engine looks. Confirm the location on a given host by where the engine creates `SerializeRoot/` — it lands under `Files/System/Serializer/`, alongside the config (the deserialize flow reads `Files/System/Serializer/SerializeRoot/<deploy|seed>/`).

The shipped config uses the current schema: a single flat `predicates: [...]` list with a per-entry `"mode": "Deploy"|"Seed"` field — see "Deploy vs Seed" below for the schema break vs the legacy `deploy: { predicates: [...] }` shape.

### Verification

After steps 1–3, restart the host. `/Admin/Api/SerializerDeserialize` should respond (a smoke POST with no payload typically returns a structured result with `0 predicates` rather than a 404 / config-missing error). Once installed, baseline content is loaded via [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md).

### Replace vs Merge (aliases of Deploy/Seed)

Two **conflict strategies** for the same deserialize pipeline, set per predicate (each entry in the flat `predicates: [...]` list carries `"mode": "Deploy"` or `"mode": "Seed"` — the `DeploymentMode` enum names, unchanged in config). Engine `v0.6.9-beta`+ additionally accepts **`replace`** (= Deploy, source-wins) and **`merge`** (= Seed, field-level) as aliases at the `?mode=` endpoint and as the layer mode-dir names `replace/` + `merge/`; the predicate `"mode"` field keeps the enum spelling. (The legacy `deploy: { predicates: [...] }` / `seed: { ... }` shape is rejected by `ConfigLoader`.)

| Mode (dir / alias) | `"mode"` field | Conflict strategy | Use for |
|---|---|---|---|
| **replace** | `Deploy` | Source-wins. Re-deserialize overwrites target. | Developer-owned deployment data: shop structure, item types, VAT rates, country list, payment method definitions. Identical across envs. |
| **merge** | `Seed` | Field-level merge. YAML fills only fields the target has not set; customer edits preserved across re-deploys. | First-run content: Customer Center welcome copy, FAQ body text, newsletter templates. Bootstrap data that transitions to customer ownership. |

For Swift `base` layer restore ([`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md)), the meaningful pass is **replace**; the **merge** pass runs but the base ships no catalog, so it lands nothing (see deserialize-flow §4).

Upstream long-form: `$env:DW_SERIALIZER_REPO\docs\concepts.md` — "Deploy and Seed modes", "The three-bucket split".

## Baseline shape

The legacy content-only baseline (`Swift2.2`) shape had **no `_sql/`** (the historical `_sql/` framework rows were deliberately removed: they silently overwrote framework data hosts had already built via the PIM-skill flow). One top-level subfolder: `_content/`, a mirror tree of the DW area→page→gridRow→paragraph hierarchy, one YAML file per node (folder = page; files = `area.yml`, `page.yml`, `grid-row.yml`, `paragraph-<col>-<n>.yml`). Hosts that need a baseline framework should run [`../../dw-demo-pim/references/canonical-setup-order.md`](../../dw-demo-pim/references/canonical-setup-order.md) Steps 1-4 before this deserialize. The runtime contract is [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) §3 "Baseline shape".

## Internals — upstream pointer block

Architecture, source layout, pipeline walkthrough, YAML schema details, strict-mode internals, the identity model (GUID-based `PageUniqueId` identity with per-environment numeric ID resolution), link-resolution passes, runtime exclusions, and the tools folder (`purge-cleandb.sql`, `swift22-cleanup/`, e2e harness, smoke tests, the Swift 2.2 bacpac) are all documented canonically in the upstream repo — **do not rely on a paraphrase here; upstream wins**:

- `$env:DW_SERIALIZER_REPO\docs\` — README → `concepts.md` → `strict-mode.md` (full warning-source table, override precedence, cache-registry extension recipe) → `link-resolution.md` → `troubleshooting.md` → `configuration.md` → `runtime-exclusions.md` → `sql-tables.md` → `permissions.md` → `cicd.md`
- `$env:DW_SERIALIZER_REPO\src\<project>\` — source (the single project folder under `src\`); `Providers\SerializerOrchestrator.cs` is the entry point
- `$env:DW_SERIALIZER_REPO\tools\` — each tool subfolder carries its own README. **DB fast-restore (escape-hatch alternative to deserialize)** is a per-machine local artifact: if you keep a clean-DB bacpac / `.mdf` snapshot on the box, note its location in the demo's own notes and restore from there — there is no shared vault slot for it. A bacpac copy inside the Serializer repo's tools folder is a development convenience, not a canonical resolution target.

Note: the DW10 source clone (a per-machine local clone, location asked/discovered) is NOT the Serializer — Serializer source lives only under `$env:DW_SERIALIZER_REPO`.

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
| Serializer internals — architecture, YAML schema, strict mode, link resolution, tools (canonical) | `$env:DW_SERIALIZER_REPO\docs\` + source ("Internals — upstream pointer block" above) |


