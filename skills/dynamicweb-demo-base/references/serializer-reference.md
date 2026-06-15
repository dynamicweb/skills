# serializer-reference.md

> Install + failure-triage reference for `DynamicWeb.Serializer`. Owns: the **fact the Serializer exists** for any Dynamicweb demo, **how to install it in the demo host** (one-time-per-host DLL drop + config staging), **common failure patterns**, and **versioning / baseline compatibility**.
>
> **Operational baseline-deserialize steps** (POST `/Admin/Api/SerializerDeserialize`, integrity sweep, schema-drift workarounds) are owned by [`../../dynamicweb-swift-demo/references/deserialize-flow.md`](../../dynamicweb-swift-demo/references/deserialize-flow.md). Only Swift demos need that flow — PIM demos start from a blank/fresh DB.
>
> **Tool internals live upstream.** The Serializer ships its own canonical docs at `C:\VibeCode\DynamicWeb.Serializer\docs\` — when this reference disagrees with upstream, upstream wins (the baseline-drift self-diagnosis rule: skill text is the second source of truth). See "Internals — upstream pointer block" below.

## Installation

Three steps. The build is one-time per machine; the DLL copy + config staging are per-host (re-run when scaffolding a new demo host or when the Serializer DLL is rebuilt). Only run these steps on demos that actually need the Serializer — typically Swift demos that will deserialize a baseline. PIM demos that start from a blank DB can skip installation until/unless they later need to serialize their own work back into the vault.

### Step 1 — Build the Serializer DLL (one-time per machine, when source updates)

```powershell
dotnet build C:\VibeCode\DynamicWeb.Serializer\src\DynamicWeb.Serializer\ -c Release
```

Note: The Serializer source root is currently at `C:\VibeCode\DynamicWeb.Serializer\` — this is a fixed path on the developer's machine, not a vault slot (the Serializer is a tool, not reference content). If the path differs on a fresh machine, update this snippet locally and consider whether the Serializer should be relocated under the vault as a future improvement.

### Step 2 — Copy DLL to host's TFM-specific bin folder

For a `dotnet run` host, .NET loads assemblies from `bin/Debug/<TFM>/` of the TARGET project, not from a generic `bin/` root. With the host pinned to `net10.0` (per [`scaffold.md`](scaffold.md) §2.1), the destination is `bin/Debug/net10.0/`:

```powershell
Copy-Item "C:\VibeCode\DynamicWeb.Serializer\src\DynamicWeb.Serializer\bin\Release\net8.0\DynamicWeb.Serializer.dll" `
          "Dynamicweb.Host.Suite\bin\Debug\net10.0\" -Force
```

The DLL is built net8.0 (Serializer ships single-target net8.0 per its csproj). .NET 10's runtime back-loads net8.0 assemblies fine. Restart the host after the copy so the new DLL is picked up. Note: the README and `docs/getting-started.md` still say "copy to `/path/to/your-dw-host/bin/`" — that's the published-deployment shape and does NOT work for local `dotnet run` hosts; always use the TFM subfolder.

### Step 3 — Stage `Files/Serializer.config.json`

The Serializer requires a config at `<host>/wwwroot/Files/Serializer.config.json`. Without one, `/Admin/Api/SerializerDeserialize` returns `Serializer.config.json not found (also checked ContentSync.config.json)`. The Serializer repo ships a canonical Swift 2.2 baseline config at `<serializer>/src/DynamicWeb.Serializer/Configuration/swift2.2-combined.json` — copy that as the starting point:

```powershell
Copy-Item "C:\VibeCode\DynamicWeb.Serializer\src\DynamicWeb.Serializer\Configuration\swift2.2-combined.json" `
          "Dynamicweb.Host.Suite\wwwroot\Files\Serializer.config.json" -Force
```

The shipped config uses the current schema: a single flat `predicates: [...]` list with a per-entry `"mode": "Deploy"|"Seed"` field — see "Deploy vs Seed" below for the schema break vs the legacy `deploy: { predicates: [...] }` shape.

### Verification

After steps 1–3, restart the host. `/Admin/Api/SerializerDeserialize` should respond (a smoke POST with no payload typically returns a structured result with `0 predicates` rather than a 404 / config-missing error). Once installed, baseline content is loaded via [`../../dynamicweb-swift-demo/references/deserialize-flow.md`](../../dynamicweb-swift-demo/references/deserialize-flow.md).

### Deploy vs Seed

Two **conflict strategies** for the same deserialize pipeline, set per predicate (each entry in the flat `predicates: [...]` list carries `"mode": "Deploy"` or `"mode": "Seed"`; the legacy `deploy: { predicates: [...] }` / `seed: { ... }` shape is rejected by `ConfigLoader`).

| Mode | Conflict strategy | Use for |
|---|---|---|
| **Deploy** | Source-wins. Re-deserialize overwrites target. | Developer-owned deployment data: shop structure, item types, VAT rates, country list, payment method definitions. Identical across envs. |
| **Seed** | Field-level merge. YAML fills only fields the target has not set; customer edits preserved across re-deploys. | First-run content: Customer Center welcome copy, FAQ body text, newsletter templates. Bootstrap data that transitions to customer ownership. |

For Swift baseline restore ([`../../dynamicweb-swift-demo/references/deserialize-flow.md`](../../dynamicweb-swift-demo/references/deserialize-flow.md)), only Deploy mode is used. Seed mode is out of scope for the canonical Swift baseline-load flow.

Upstream long-form: `C:\VibeCode\DynamicWeb.Serializer\docs\concepts.md` — "Deploy and Seed modes", "The three-bucket split".

## Vault baseline shape

The vault baseline at `$env:DW_VAULT\serialized-data\Swift2.2\` is **content-only** (as of 2026-05-08 — the historical `_sql/` framework rows were deliberately removed: they silently overwrote framework data hosts had already built via the PIM-skill flow). One top-level subfolder: `_content/`, a mirror tree of the DW area→page→gridRow→paragraph hierarchy, one YAML file per node (folder = page; files = `area.yml`, `page.yml`, `grid-row.yml`, `paragraph-<col>-<n>.yml`). Hosts that need a baseline framework should run [`../../dynamicweb-pim-demo/references/canonical-setup-order.md`](../../dynamicweb-pim-demo/references/canonical-setup-order.md) Steps 1-4 before this deserialize. The runtime contract is [`../../dynamicweb-swift-demo/references/deserialize-flow.md`](../../dynamicweb-swift-demo/references/deserialize-flow.md) §3 "Baseline shape".

## Internals — upstream pointer block

Architecture, source layout, pipeline walkthrough, YAML schema details, strict-mode internals, the identity model (GUID-based `PageUniqueId` identity with per-environment numeric ID resolution), link-resolution passes, runtime exclusions, and the tools folder (`purge-cleandb.sql`, `swift22-cleanup/`, e2e harness, smoke tests, the Swift 2.2 bacpac) are all documented canonically in the upstream repo — **do not rely on a paraphrase here; upstream wins**:

- `C:\VibeCode\DynamicWeb.Serializer\docs\` — README → `concepts.md` → `strict-mode.md` (full warning-source table, override precedence, cache-registry extension recipe) → `link-resolution.md` → `troubleshooting.md` → `configuration.md` → `runtime-exclusions.md` → `sql-tables.md` → `permissions.md` → `cicd.md`
- `C:\VibeCode\DynamicWeb.Serializer\src\DynamicWeb.Serializer\` — source; `Providers\SerializerOrchestrator.cs` is the entry point
- `C:\VibeCode\DynamicWeb.Serializer\tools\` — each tool subfolder carries its own README; the Swift 2.2 bacpac there is the emergency fast-restore alternative to deserialize referenced by `$env:DW_VAULT\INDEX.md`'s `databases` row

Note: `$env:DW_VAULT\dw10source\` is the DW10 clone, NOT the Serializer — Serializer source lives only at the path above.

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

1. Extend the Content predicate `path` so page 3421 is included in Deploy mode.
2. Move the referencing page (or referenced page) into the same mode if they're split across Deploy/Seed.
3. Clean source: null the dangling reference. For Swift 2.2, `tools/swift22-cleanup/01-null-orphan-page-refs.sql` is the canonical fix.
4. Acknowledge the orphan (escape hatch): add the ID to the predicate's `acknowledgedOrphanPageIds` array. Demotes the fatal serialize error to a warning. Remove the entry once the data is clean — leaving acknowledged IDs around silences real future drift.

### "source column [T].[C] not present on target schema"

**Symptom:** `WARNING: source column [EcomShops].[ShopNewField] not present on target schema — skipping`.

**What happened:** Source DW host is on a different `Dynamicweb.Suite` NuGet version than the target. The source has a column the target's `UpdateProvider` hasn't created yet.

**Fix paths:**

1. Align NuGet versions: bump the target's `Dynamicweb.Suite` to match source, `dotnet publish`, restart. DW runs pending `UpdateProvider` classes at startup. (See `references/db-update-recovery.md` if a `UpdateProvider` itself is broken.)
2. Drop the column on source: align downward instead of upward.
3. Accept the drift: the column is silently dropped from MERGE, the rest of the row writes correctly. Lenient mode only.

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

Baseline rolls (the vault's `Swift2.2/` content) happen out-of-band — when Dynamicweb ships a new Swift release, the vault baseline gets re-serialized from a fresh Swift install. The vault's `INDEX.md` `serialized-data` row carries the date stamp; cross-check it against the demo's host DW10 version when triaging schema-drift warnings (the baseline-drift self-diagnosis rule).

## Cross-references

| If you need... | Read |
|---|---|
| Install the Serializer in the demo host (build DLL, copy to bin, stage config) | "Installation" section above |
| Run a baseline content deserialize (Swift demos only) | [`../../dynamicweb-swift-demo/references/deserialize-flow.md`](../../dynamicweb-swift-demo/references/deserialize-flow.md) |
| Post-deserialize integrity checks | [`../../dynamicweb-swift-demo/references/integrity-sweep.md`](../../dynamicweb-swift-demo/references/integrity-sweep.md) |
| Recover from DW10 update-queue bugs (independent of Serializer) | `references/db-update-recovery.md` |
| Serializer internals — architecture, YAML schema, strict mode, link resolution, tools (canonical) | `C:\VibeCode\DynamicWeb.Serializer\docs\` + source ("Internals — upstream pointer block" above) |
