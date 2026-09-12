# serializer-reference.md

## Contents

- [Installation](#installation)
- [Invocation — one shape](#invocation--one-shape-mode-in-the-json-body)
- [Baseline shape](#baseline-shape)
- [Internals — upstream pointer block](#internals--upstream-pointer-block)
- [Common failure patterns and diagnostics](#common-failure-patterns-and-diagnostics)
- [Versioning and baseline-format compatibility](#versioning-and-baseline-format-compatibility)
- [Cross-references](#cross-references)

> Install + failure-triage reference for the DW Serializer. Owns: the **fact the Serializer exists** for any Dynamicweb demo, **how to install it in the demo host** (one-time-per-host DLL drop + config staging), **common failure patterns**, and **versioning / baseline compatibility**.
>
> **Operational baseline-deserialize steps** (POST `/Admin/Api/SerializerDeserialize`, integrity sweep, schema-drift workarounds) are owned by [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md). Only Swift demos need that flow — PIM demos start from a blank/fresh DB.
>
> **The engine installs from a public NuGet package, not a repo clone.** The Serializer ships as the public NuGet package **`Truvio.Commerce.Serializer`** — add it as a `PackageReference` to the host and restore. **Never install a version copied out of a document, including this one.** The authoritative floor is `minSerializerVersion` in the Distribution's `layers/base/base.contract.json` on `main`; install the latest published engine release at or above it ("Installation" Step 1). There is **no `$env:DW_SERIALIZER_REPO` clone step** and none is required to deserialize; a partner reproduces the whole flow from the package alone. A local clone of the engine repo is **optional**, and only for internals deep-dives — see "Internals — upstream pointer block" below. When this reference disagrees with the engine's published docs, the published docs win (the baseline-drift self-diagnosis rule: skill text is the second source of truth).

## Installation

Add the NuGet package (Step 1), then stage the config (Step 2). Both are per-host — re-run when scaffolding a new demo host or when bumping the engine version. Only run these steps on demos that actually need the Serializer — typically Swift demos that will deserialize a baseline. PIM demos that start from a blank DB can skip installation until/unless they later need to serialize their own work.

### Step 1 — Add the `Truvio.Commerce.Serializer` NuGet package to the host

**Read the engine floor from the Distribution before installing anything.** The layers declare, machine-readably, the oldest engine that can deserialize them. An engine below that floor cannot load them at all — the failure is a rejected run, not a degraded one. Read the floor from the checked-out Distribution on `main` (see [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) §3 for the checkout):

```powershell
# The floor is data, not a constant. Whatever main declares is the authority — not this file.
$floor = (Get-Content "distribution\layers\base\base.contract.json" -Raw |
          ConvertFrom-Json).minSerializerVersion
$floor   # the floor typically trails the published engine by a release or two
```

Then install the **latest published release at or above `$floor`** as a `PackageReference` on `Dynamicweb.Host.Suite` and restore — the engine assembly flows into the host build automatically, so there is **no manual DLL build and no copy into `bin/Debug/<TFM>/`**:

```powershell
dotnet add Dynamicweb.Host.Suite package Truvio.Commerce.Serializer --prerelease   # latest release
dotnet restore Dynamicweb.Host.Suite
# Assert the resolved version is at or above $floor before going any further.
dotnet list Dynamicweb.Host.Suite package --include-prerelease |
  Select-String "Truvio.Commerce.Serializer"
```

Pin **the version the restore actually resolved** in the csproj (`<PackageReference Include="Truvio.Commerce.Serializer" Version="<resolved>" />`) so a demo reproduces on the engine it was proven against; re-read the floor and re-resolve when adopting a newer engine or a newer Distribution `main`.

**Platform floor — the engine binds to Dynamicweb 10.28.x.** The package compiles against the `DynamicwebVersion` pin in its own csproj (a 10.28.1 prerelease on the current release line), and the app-store install filter compares the host's DW version against that pin, so a host on an older ring (10.27.x) is never offered the package and the assembly never loads there. Bring the host to 10.28.x **before** installing the engine; Serializer endpoints that 404 on a 10.27.x host are this, not a missing config.

Restart the host after the restore so the new assembly is loaded. (The package targets net8.0; .NET 10's runtime back-loads net8.0 assemblies fine — no TFM juggling, because NuGet resolves the assembly into the host's own build output.)

### Step 2 — Stage `Files/System/Serializer/Serializer.config.json`

The Serializer requires a config at `<host>/wwwroot/Files/System/Serializer/Serializer.config.json` (see the path note below). Without one, `/Admin/Api/SerializerDeserialize` returns `Serializer.config.json not found (also checked ContentSync.config.json)`. The predicate config ships **with the layer being deserialized** — the `base` layer carries it under its `config/` tree, one file per Swift release (`distribution\layers\base\config\swift-<version>.json` — take the one the checked-out base's `swiftVersion` names, never a filename copied from a document); stage that as the starting point (or author one per the flat-`predicates` schema documented in "Replace vs Merge" below):

```powershell
$cfgDir = "Dynamicweb.Host.Suite\wwwroot\Files\System\Serializer"
New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
# The base layer's checked-out config tree (see deserialize-flow.md §3 for the Distribution checkout).
# Resolve the filename from the layer, not from this file.
$swift = (Get-Content "distribution\layers\base\base.contract.json" -Raw |
          ConvertFrom-Json).swiftVersion
Copy-Item "distribution\layers\base\config\swift-$($swift -replace '\.\d+$','').json" `
          "$cfgDir\Serializer.config.json" -Force
```

**Path note.** The engine reads the config from `Files/System/Serializer/Serializer.config.json`. Older installs staged it at the `Files/` root (`Files/Serializer.config.json`); the engine's actual read location is what wins, so stage it where the running engine looks. Confirm the location on a given host by where the engine creates `SerializeRoot/` — it lands under `Files/System/Serializer/`, alongside the config (the deserialize flow reads `Files/System/Serializer/SerializeRoot/<replace|merge>/`).

The config is a single flat `predicates: [...]` list with a per-entry `"mode"` field spelled `Replace` or `Merge` (see "Replace vs Merge" below).

**Validate the staged config with one call before deserializing anything:** `GET /Admin/Api/SerializerSettings` must return 200 with a non-empty `predicatesSummary`. On a config the loader rejects, *every* Serializer call 500s — including this read-only one — so a config authored for the wrong engine major is indistinguishable from a broken install until you make this probe.

### Verification

After steps 1–2, restart the host. `/Admin/Api/SerializerDeserialize` should respond (a smoke POST typically returns a structured result with `0 predicates` rather than a 404 / config-missing error). Once installed, baseline content is loaded via [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md).

### Replace vs Merge (the predicate `mode` enum)

Two **conflict strategies** for the same deserialize pipeline, set per predicate. On every engine at or above the Distribution floor the predicate `"mode"` field takes **`"Replace"` or `"Merge"`**, and the mode for a *run* travels in the JSON body of `SerializerDeserialize` ("Invocation — one shape" below). `IsDryRun` reports the `created / updated / skipped / failed` counts without writing — use it before every hosted deserialize.

*Tombstone: `"Deploy"` / `"Seed"` were the predicate enum on engines below the current floor — `ConfigLoader.ValidatePredicates` now throws `Unknown mode 'Deploy' for predicate '<name>' — valid values: Replace, Merge`, so a config carrying them 500s **every** Serializer call, the read-only `GET /Admin/Api/SerializerSettings` included.*

When a layer ships a config, check its `mode` spelling before staging it — a config the loader rejects is indistinguishable from a broken install until that `SerializerSettings` probe is made. (The legacy `deploy: { predicates: [...] }` / `seed: { ... }` *shape* is rejected by `ConfigLoader` too.)

### Invocation — one shape (`Mode` in the JSON body)

**There is one invocation shape: a flat JSON body carrying `Mode`.** `SerializerDeserialize` is a
flat (non-`Model`-wrapped) POST command whose `Mode` property defaults to `Replace` rather than being
explicit-required, so `{"IsDryRun":true}` alone runs a Replace dry run and **an empty `{}` body
executes a LIVE REPLACE against the target**. Always send `Mode`; never send `{}`. Body forms, on
10.28.x:

```
POST https://<host>/Admin/Api/SerializerDeserialize      Authorization: Bearer <api-token>

{"IsDryRun": true,  "Mode": "Replace"}     # dry run, replace tree
{"IsDryRun": true,  "Mode": "Merge"}       # dry run, merge tree
{"IsDryRun": false, "Mode": "Replace"}     # real run
{"IsDryRun": false, "Mode": "Merge"}       # real run
```

`StrictMode` (bool) and `QuarantineUnresolvableLinks` (bool) ride in the same body. Mode values parse
case-insensitively into the engine's `SerializerMode` enum; write them Pascal-case. The canonical
two-pass call — replace first, then merge — is:

```powershell
foreach ($m in @("Replace", "Merge")) {
  $body = @{ Mode = $m; IsDryRun = $false } | ConvertTo-Json
  Invoke-RestMethod -Uri "https://<host>/Admin/Api/SerializerDeserialize" -Method POST `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType "application/json" -Body $body -SkipCertificateCheck
}
```

Run it dry first (`IsDryRun = $true`) and read the entry count, per "Read the ENTRY COUNT" below.

*Tombstone: `?mode=replace` / `?mode=merge` on the query string. The engine still reads a `?mode=`
parameter, but only as a fallback when the body leaves `Mode` at its `Replace` default — a query
parameter can therefore never override a body `Mode`, and a call that sets both is ambiguous to read
and silently body-wins. Send `Mode` in the body and nothing on the query string.*

The response is `{"status":"ok"|"error","message":"..."}`; on a strict-mode
escalation the HTTP code is 400 with `status:"error"` and the escalated warnings inline in `message`,
which names the failing `entryId`, so read `message` rather than the code alone. Same transport rules
as the rest of the surface: queries are GET, commands are POST, a wrong verb is a 400 "Unknown
command" / "Unknown query" and never a 404. Command bodies are `{"Model":{...}}`-wrapped for models
(`AreaSave`) and **flat** for simple commands (`BuildIndex`, `SerializerDeserialize`); the wrapping
error is literally `{"Command.Model":["Command.Model cannot be null"]}`.

**Dry-run CONTENT counts under-report by design; only `failed > 0` gates.** A dry run cannot create
parents, so every child whose parent would not yet exist is deferred rather than counted. A
`content/area-<id>` entry reporting 11 created / 30 skipped against a 77-page tree is not a broken
composition: the real run created all 77 pages and 104 paragraphs (dry Replace 724 created / 8 updated
/ 64 skipped / 0 failed over 19 entries, real Replace 984 / 10 / 33 / 0). Content counts in a dry run
are a lower bound, not a prediction. Gate the dry run on `failed == 0` and the absence of escalated
strict-mode warnings.

**Read the ENTRY COUNT as well — it is not a count, it is the blast radius.** `failed == 0` is
necessary and not sufficient: a dry run reporting `94 created, 252 updated, 680 skipped, 0 failed
across 19 entries` is a perfectly healthy-looking line describing a run that is about to rewrite
nineteen entries of somebody else's baseline. Match the entry count, and the entry ids, against what
you intended to run, every time, before the real run. The mechanism that makes this the load-bearing
readout is next.

**Deserialize is driven by the MANIFEST under `SerializeRoot`, not by the config predicates.**
`SerializerDeserialize` resolves what to run from `SerializeRoot/<mode>/<mode>-manifest.json` and
walks the entries it finds there. `predicates` and `outputDirectory` in `Serializer.config.json`
govern **serialize** (and validation) only — on the deserialize path `outputDirectory` is not
consulted at all, so the engine reads the default `Files/System/Serializer/SerializeRoot` regardless
of where the config points, and it does so across an app-pool restart. A config narrowed to one
predicate, with the layer tree correctly staged under a private root, therefore dry-ran all nineteen
entries of an unrelated baseline — including a `content/area-<id>` entry with 188 updates that a real
run would have written over six phases of content edits. It reported `0 failed` while being
completely wrong about what it would write. (Same family as the `Mode` default above: an input the
caller believes is authoritative is ignored, and the silent default is the widest possible blast
radius.)

**To deserialize ONE entry, swap the manifest — narrowing the config does nothing.** The proven
staging recipe, which a composer script should own end to end:

1. Build the rewritten layer tree in the **workspace**, never in place under `SerializeRoot`.
2. Assert the staged set both ways: every file the manifest names exists on disk, **and** no staged
   file is missing from the manifest.
3. Back up the three live files — `SerializeRoot/<mode>/<mode>-manifest.json`, the mode tree's own
   `_content/templates.manifest.yml`, and `Serializer.config.json`. **Guard the manifest backup with
   `entries.length > 1`**, so a re-stage cannot overwrite the baseline backup with the already-staged
   one-entry manifest.
4. Copy the tree in and swap both manifests and the config.
5. Dry-run and **read the entry count**: exactly one entry, named, with zero mentions of any other
   area. That is the gate; `0 failed` is not.
6. Run, then unstage: delete the staged tree, restore the three files, and **assert
   `SerializeRoot` is byte-for-byte back** (file count, manifest entry count, config predicate
   count), throwing if it is not.

Between stage and unstage the manifest carries exactly one entry, so a Replace run can only reach
that entry. Prove the containment with a before/after measurement on an area the run must not touch
(pages, paragraphs and grid rows identical on both sides).

**A run reads only its own mode subfolder.** `Mode: "Replace"` walks `SerializeRoot/replace/`, `Mode: "Merge"` walks `SerializeRoot/merge/`; a missing subfolder returns `Mode subfolder not found: <path>` and an empty one returns `<path> contains no YAML files`. Both are staging faults, not engine faults. The two-pass *sequence* in a Swift build is owned by [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) §4; the call shape is owned here.

| Mode (dir / alias) | `"mode"` field | Conflict strategy | Use for |
|---|---|---|---|
| **replace** | `Replace` | Source-wins. Re-deserialize overwrites target. | Developer-owned deployment data: shop structure, item types, VAT rates, country list, payment method definitions. Identical across envs. |
| **merge** | `Merge` | Field-level merge. YAML fills only fields the target has not set; customer edits preserved across re-deploys. | First-run content: Customer Center welcome copy, FAQ body text, newsletter templates. Bootstrap data that transitions to customer ownership. |

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

### Strict-mode false positives — a 400 whose warnings describe no defect

Strict mode escalates *every* warning, so a run that writes correctly can still answer 400. Before
treating a 400 as a payload defect, check the escalated warning list against this table: when every
listed warning is one of these, the run is sound and the response code carries no information.

| Escalated warning | Fires when | Why it is a false positive | Do this |
|---|---|---|---|
| `Warning: Area with ID <n> not found. Skipping entry 'content/area-<n>...'` | A **dry run** (`IsDryRun: true`) whose replace tree would create that area for the first time. The run reports `0 failed` and every `content/area-<n>` entry reports `C0 U0 S0 F0`. | The content provider resolves the target area by id *before* applying `area.yml`. A dry run never writes, so the area cannot come into existence mid-run and the provider takes its skip branch; the live path instead logs `Area created: ID=`. On an empty target the preview of a first-ever content import is structurally incapable of returning 200. | Confirm the escalated list contains **only** this warning, then proceed to the live run with the same body and `IsDryRun: false`. The live run returns 200 and creates the area. Assert: with `SELECT COUNT(*) FROM Area` = 0 the dry run 400s on this warning alone, and the live run answers 200 with `SELECT COUNT(*) FROM Area` = 1. |
| `WARNING: Missing grid-row template: '<n>Column...Email'` | A merge pass over content that carries newsletter/email grid rows, on a host where the definition file does exist under `Files/Templates/Designs/Swift-v2/Grid/Email/RowDefinitions/`. The run itself reports `0 failed`, and the warning repeats once per content entry processed after the newsletter pages, so its multiplicity carries no information. | The engine's grid-row template resolver scans only `Grid/Page/RowDefinitions/`, so every definition that lives under `Grid/Email/RowDefinitions/` is unfindable to it while being perfectly resolvable to the frontend. | Verify the named `.json` exists under some `Grid/*/RowDefinitions/` folder, then accept the run. Assert: every `definitionId` used anywhere in the composed `SerializeRoot` has a matching `.json` under some `Designs/Swift-v2/Grid/*/RowDefinitions/`; when that holds and the response reports `0 failed`, a `Missing grid-row template` escalation is a PASS. Do **not** null the reference on the source and do **not** turn strict mode off to get past it. |

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
2. Move the referencing page (or referenced page) into the same mode if they're split across the replace/merge modes.
3. Clean source: null the dangling reference. For Swift 2.2, `tools/swift22-cleanup/01-null-orphan-page-refs.sql` is the canonical fix.
4. Acknowledge the orphan (escape hatch): add the ID to the predicate's `acknowledgedOrphanPageIds` array. Demotes the fatal serialize error to a warning. Remove the entry once the data is clean — leaving acknowledged IDs around silences real future drift.

### "source column [T].[C] not present on target schema"

**Symptom:** `WARNING: source column [EcomShops].[ShopNewField] not present on target schema — skipping`.

**What happened:** Source DW host is on a different `Dynamicweb.Suite` NuGet version than the target. The source has a column the target's `UpdateProvider` hasn't created yet.

**Fix paths:**

1. Align NuGet versions: bump the target's `Dynamicweb.Suite` to match source, `dotnet publish`, restart. DW runs pending `UpdateProvider` classes at startup. (This NuGet-alignment / startup-migration crossover is platform-generic — owned by [`../../dw-setup-upgrade/references/upgrade-mechanics.md`](../../dw-setup-upgrade/references/upgrade-mechanics.md) "Schema-drift across NuGet versions"; see it too if a `UpdateProvider` itself is broken.)
2. Drop the column on source: align downward instead of upward.
3. Accept the drift: the column is silently dropped from MERGE, the rest of the row writes correctly. Lenient mode only.

**Area-column drift specifically (older baseline → newer host).** When the offending column is on `[Area]` (e.g. an `area.yml` captured on an older platform), the predicate's `excludeAreaColumns` setting does NOT help — it governs serialize-OUT (which Area columns get *written*), not deserialize-IN. Strip the offending column from the **staged** `Files/System/Serializer/SerializeRoot/deploy/_content/<Area>/area.yml` (never the downloaded original under `baselines\`) and re-POST. See the deserialize flow's §3 note: [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md).

### "template 'T' not found at Files/Templates/T"

**Symptom:** `WARNING: template 'eCom_Catalog' not found at Files/Templates/eCom_Catalog.cshtml`.

**What happened:** YAML references a page-layout / grid-row / item-type template that isn't on the target's filesystem. Templates ship as filesystem state (Swift git clone), not DB state.

**Fix paths:**

1. Deploy the missing template alongside the DLL (filesystem rsync / git pull / Azure Files sync).
2. Null the stale reference on source, once you have confirmed the file really is absent. For the legacy Swift 2.2 cleanup set, `tools/swift22-cleanup/05-null-stale-template-refs.sql` nulls three references (`1ColumnEmail`, `2ColumnsEmail`, `Swift-v2_PageNoLayout.cshtml`). The two email ones are **not** stale on a current design tree — their definitions ship under `Grid/Email/RowDefinitions/` and the engine merely fails to look there (see "Strict-mode false positives" above). Running that cleanup against a current baseline deletes live references; check the disk before nulling anything.

## Versioning and baseline-format compatibility

The Serializer's API surface (Management API commands, predicate shape, YAML format) is **stable for the current release line** (per upstream README). Config schema and runtime-exclusion defaults may evolve before 1.0.

### Reading the engine floor

The floor is **`minSerializerVersion` in `layers/base/base.contract.json` on the Distribution's `main`**, and it is the only version statement to act on. A base that raises the floor does so because it ships something older engines drop or reject (for example the YAML-carried page/grid-row/paragraph `permissions:` blocks), so an engine below the floor produces a run that is rejected outright or, worse, silently missing what the floor was raised for. Read it, install the latest release at or above it, record the resolved version alongside the Distribution commit SHA in the demo's own notes. Both floors are gates: this one, and the platform floor in "Installation" Step 1.

### How to tell if a baseline is too old

Three signals:

1. **`SourcePageId` missing** from page YAML → baseline pre-dates the Serializer's cross-environment link-rewriting support. Re-serialize from a current Serializer version.
2. **Legacy `deploy: { predicates: [...] }` / `seed: { ... }` config shape, or `Deploy`/`Seed` `mode` spellings** → older config schema. ConfigLoader rejects both in favour of the flat `predicates: [...]` list with `Replace`/`Merge` modes. Migrate the config; YAML payloads are unchanged ("Replace vs Merge" above).
3. **`UpdateVersion_ecom.xml` style update tracking** → pre-DW-9.14 era. Not a Serializer issue per se; affects the host DW10's update-manager queue (see `../../dw-setup-upgrade/references/db-update-recovery.md`).

### How baselines roll

Baseline rolls happen out-of-band — when Dynamicweb ships a new Swift release, the `base` layer gets re-serialized from a fresh Swift install and lands on the Distribution repo's `main` (annotated tags are cut as provenance/audit history, not a consumer checkout target). The demo consumes the latest gate-proven `main` and records the resolved **commit SHA**. That SHA is the stamp; cross-check the checked-out `base` layer's `swiftVersion` against the demo's host DW10 version when triaging schema-drift warnings (the baseline-drift self-diagnosis rule).

## Cross-references

| If you need... | Read |
|---|---|
| Install the Serializer in the demo host (build DLL, copy to bin, stage config) | "Installation" section above |
| Run a baseline content deserialize (Swift demos only) | [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) |
| Call `SerializerDeserialize` (the one body shape, both passes) | "Invocation — one shape" above |
| Post-deserialize integrity checks | [`../../dw-demo-swift/references/integrity-sweep.md`](../../dw-demo-swift/references/integrity-sweep.md) |
| Recover from DW10 update-queue bugs (independent of Serializer) | `../../dw-setup-upgrade/references/db-update-recovery.md` |
| Install the engine into the host | NuGet `Truvio.Commerce.Serializer`, latest release at or above the Distribution's `minSerializerVersion` floor — "Installation" Step 1 above (no repo clone) |
| Serializer internals — architecture, YAML schema, strict mode, link resolution, tools (canonical) | the `Truvio.Commerce.Serializer` engine repo `docs\` + source — an **optional** clone ("Internals — upstream pointer block" above) |


