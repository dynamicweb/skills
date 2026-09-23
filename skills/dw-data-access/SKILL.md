---
name: dw-data-access
type: knowledge
group: data
mcp: optional
dynamo: false
compatibility: Requires PowerShell 7.x
description: 'Choose DW10 data-access surfaces and caching patterns. Triggers: MCP vs Management API vs serializer vs SQL, action ladder, cache invalidation, SQL gotchas. C# coding -> dw-extend-csharp-api.'
---

# Data Access in Dynamicweb 10

## Without MCP

This skill is not served to the in-product agent, so the whole action ladder is available. The MCP
tools it names are rung 1 and the preferred way to apply it. With no MCP server connected, drop
**one** rung, not to SQL: the Management API at `/admin/api/...` reaches the same domain services
over a different transport, and the serializer carries bulk, id-preserving loads. Direct SQL is the
last rung, is local-install only, and owes a cache flush or restart. When no rung reaches the
operation, work in advisory mode. The full ladder is the next section, and this skill owns it for
the whole corpus — including the in-product agent's own, much narrower surface, which is stated
here so the rest of the corpus can see what it may not ask for.

## Surfaces into a Dynamicweb instance — the action ladder

Four surfaces change a Dynamicweb 10 instance from outside the process. They are **ranked, not
interchangeable**: each rung down does less of the platform's own bookkeeping. Take the highest rung
that reaches the operation, and name that rung in the recipe.

| Rung | Surface | Names look like | Use it for |
|---|---|---|---|
| 1 | **MCP tools** (Dynamicweb MCP server; 600+ on MCP 0.4.4 with a FullAccess key, fewer on a scoped one — read `tools/list`, never a printed count) | `snake_case` — `save_pages`, `patch_products_safe` | The default for anything that creates or mutates a structural row. Calls DW's domain services, so relation wiring, cache invalidation, index refresh and validation all fire. |
| 2 | **Management/Admin API** (`/admin/api/...`, bearer) | `PascalCase` — `ParagraphSave`, `BuildIndex` | The same domain services over a different transport. Use it when MCP does not expose the operation, and for admin-grade actions MCP never wraps (`CacheInformationRefresh`, `FeatureManagementToggle`). The `dw command` CLI is this rung over a different transport, not a surface of its own. |
| 3 | **Serializer** (`Deserialize`, layer `replace`/`merge` trees) | `PascalCase` verb, layer paths | Bulk, id-preserving loads and cross-install moves. **A layer beats a rung-1 or rung-2 loop** as soon as the write is bulk (hundreds of rows, a whole content tree) or ids and relations must survive. Dry-run (`IsDryRun`) first. |
| 4 | **Direct SQL** | `sqlcmd` / `Invoke-Sqlcmd` / T-SQL | **Last resort, local installs only.** Sanctioned cases: cleanup/teardown, bulk schema-drift fixes, reads, and operations proven absent from rungs 1-3. Bypasses every service. |

**Which surfaces exist, per instance type:**

Headless and Dynamo are different things and do not share a column. A **headless** install is an
ordinary instance whose frontend is decoupled; it keeps every rung. **Dynamo** is the agent running
*inside* the product: its whole surface is the MCP tool set plus read/write under `Files/`.

| Surface | Local install | Hosted (cloud) | Headless | Dynamo (in-product) |
|---|---|---|---|---|
| 1 MCP tools | Present | **Probe first** — version-dependent; primary when present | Probe first | **The only action surface** |
| 2 Management API | Present | Present — **the floor** when MCP is absent | Present | **Absent** |
| 3 Serializer | Present if the AddIn is installed | Present if installed; engine versions must match | Present if installed | **Absent** |
| 4 Direct SQL | Present | **Does not exist** | **Does not exist** | **Absent** |
| Read/write under `Files/` | Present | Through the file archive | Through the file archive | **Present** — the second and last surface |
| Admin UI | **Verification only** | Verification only | n/a | The user's own screen: **name it, never drive it** |
| Ask the user | When rungs 1-3 genuinely cannot reach it | When rungs 1-3 cannot reach it — there is no SQL floor | Same | **The only fallback**: no tool, no rung — stop and say which screen does it |

A skill marked `dynamo: true` therefore carries no instruction outside that last column. Where an
operation needs a lower rung, the recipe lives here (`references/recipes-<area>.md`) and the
in-product skill keeps a one-line pointer to it.

**Rules that hold at every rung:**

- **The admin UI is not an action surface.** It is a SPA client of `/admin/api/...`; every click is a
  rung-2 call. "This exists only in the UI" means the endpoint has not been found yet. **When a
  surface looks closed:** check `/admin/api/docs/`, then **capture the admin UI's own HTTP call** —
  drive the admin *read-only*, read the network traffic, replay it. Reading the SPA's traffic is
  verification-grade; clicking Save is not.
- **A verb-registry negative proves a verb absent, never a capability absent.** Enumerating the
  registries and finding no `X*` command proves that *name* is missing, nothing more: some writes have
  no command of their own and ride inside a parent entity's save payload. Guessing command names is not
  free either — each unresolvable name writes an `[Application/AddInManager]` error row onto the
  customer-visible Insights dashboard, so batch the probing.
- **Success is not proof.** Rung 1-2 writes can return `ok` and silently drop part of the input, and
  read verbs then serve a cached model that agrees with the lie. Round-trip through a different
  surface, the stored row, or the rendered page.
- **Ordering when rungs must mix:** all rung 1-2 writes first, then the SQL touch-up, and nothing
  re-saves the entity afterwards. Any command that re-saves an entity (*recalculate* commands included)
  writes DW's **cached** model back over whatever SQL wrote behind it.
- **A SQL recipe states three things**: why rungs 1-3 do not cover the operation, that it is **local
  installs only**, and the cache flush or host restart it owes —
  [`references/cache-invalidation.md`](references/cache-invalidation.md) carries the per-mutation table.
- **Never SQL-clone a structural tree** (Area / Page / Paragraph / GridRow / Item). The create path
  carries sibling-link bookkeeping, item-instance cloning, localization overlays, ItemList relations
  and hidden-flag rules a raw `INSERT ... SELECT` gets partly right and then breaks ten screens later.

## Reading the host's versions

Do this once per session, before any recipe whose facts are version-specific, and keep the result as
the session's `hostVersions` note. Four vendor axes: the Dynamicweb release, the MCP add-in, the
serializer add-in, and the Swift tag, plus the hosting ring the Dynamicweb release is served from,
which is what an outward compatibility claim is actually made against.

**Full host** (any rung 1-4 surface available):

1. **Dynamicweb release** — `GET /admin/api/api.json` (rung 2) and read `info.version`. The descriptor
   is served without the bearer check, so this read proves nothing about the key: prove a key on a
   command endpoint such as `McpConfigurationAll`, which answers 401 to any key but the host's own
   [dw 10.28.10]. `info.version` is the running platform build, not the NuGet package version and not
   the hosting ring.
2. **Hosting ring**: read it, never infer it from the release number. Two places carry it, and
   which one applies depends on how the solution is hosted:
   - **VM-style install**: resolve the `Application\bin` symlink and read its target under
     `F:\Domains\Applications\DW10\<Ring>\bin`. The `<Ring>` folder names the ring and the
     runtime together: `R1-NET10` is ring 1 on .NET 10, while a plain `R1` folder is ring 1 on the
     older runtime. Record both halves; the runtime half is the axis the .NET 10 rollout moves.
   - **Hosted site**: read `Files/System/CloudHosting/changeversion.txt`. It holds one ring token,
     `R1` through `R4`, and it is the ring the platform serves the solution from. Nothing else in
     the Files tree states the ring.

   When neither is readable (no symlink to resolve, no `changeversion.txt`, or no read access to
   either), the ring is **unknown** and is recorded as `null`. Never guess it: a ring is not
   derivable from `info.version`, from the Swift tag, or from how new the build looks.
3. **App versions** — list the folder names under `Files/System/AddIns/Installed/`. Each is
   `<id>.<version>`, so the serializer is the folder starting `Truvio.Commerce.Serializer.` and the
   MCP add-in the folder starting `Truvio.Commerce.MCP.`. A `Dynamicweb.MCP.` folder, which many hosts
   still report, is the add-in's retired **predecessor** (listed under the app's `predecessors` in
   `worksOn`), not the same app under another id: record it by name, and read a host that carries
   only the predecessor as **below the MCP floor**, never as matching it and never as an absent
   optional app. A missing folder under the id and every predecessor means the add-in is not
   installed, which is an answer, not an error.
4. **Swift tag** — read `Files/System/Truvio/swift.stamp.json` and take its `tag`/`version`. When the
   file is absent the site carries no Swift marker at all: ask the user which Swift release the
   solution tracks and record the answer. Never infer it from a template folder name.

**MCP-only** (the in-product agent, and any session with rung 1 alone): `list_files` on
`Files/System/AddIns/Installed` gives the app versions the same way, and `read_file` on the Swift
stamp gives the Swift tag. `read_file` on `Files/System/CloudHosting/changeversion.txt` gives the
ring on a hosted site; a VM-style install has no such file, and the `Application\bin` symlink is
outside the Files tree, so the ring reads as `null` there. The platform release is not readable this
way — record that axis as `unknown`. Record `unknown` for any axis you cannot read, and never guess one.

**Then compare.** The skills' own compatibility statement ships in `manifest.json` as `worksOn`: a
`floor` per axis (what the corpus claims to work on) and `measured` (the host its facts were last
observed on). The `dw` axis also carries `ring` and `tfm`: the hosting ring and framework the corpus
was proven on. Compare the host's ring against it as context, not as a gate; a ring mismatch is
worth naming in the note, and a ring of `null` suppresses the comparison entirely. An app in `worksOn` matches the host folder under its `id` only; a folder under one
of its `predecessors` is below the floor (the MCP case above). Compare the numeric version core: an add-in folder can carry a
pre-release suffix (`-BETA`, `-beta`) that neither the floor nor `measured` shows, so strip it for the
comparison and keep it in the `hostVersions` note. For each axis that read as a concrete version,
compare the host against the floor:

- host below the floor → **warn the user before acting**: name the axis, the host version and the
  floor, and say that recipes may reference behavior the host does not have.
- host at or above the floor, but not equal to `measured` → proceed; treat any step that fails in a
  version-shaped way as a re-measure candidate, and file it rather than working around it silently.
- axis `unknown` → proceed, and suppress floor warnings for that axis only.

An add-in whose `required` flag is false is not a blocker: its floor applies only to the skills that
cover it, and the scope is stated in `worksOn` beside the app.

## In-process C#: Service API vs the Database class

| Use case | Approach |
|----------|----------|
| Reading/writing Ecommerce, Content, User data | **Service API** — handles caching, notification firing, type safety |
| Custom tables you own | **`Database` static class** — direct SQL for custom data |
| Reporting / large aggregate queries | **`Database` static class** — services load full objects; SQL is more efficient for aggregates |
| Cross-domain joins not possible via API | **`Database` static class** with read-only queries |

**Use the Service API for writes to Ecommerce core tables** (EcomProducts, EcomOrders, etc.), never raw SQL — raw SQL bypasses cache invalidation and notification subscribers.

## Database Static Class

`Dynamicweb.Data.Database` provides the SQL access layer. All methods accept either a raw SQL string or a `CommandBuilder`.

### Reading with a DataReader

```csharp
using Dynamicweb.Data;

var cb = new CommandBuilder();
cb.Add("SELECT PageID, PageName FROM Page WHERE PageActive = {0}", true);

using IDataReader dr = Database.CreateDataReader(cb);
while (dr.Read())
{
    int id = Converter.ToInt32(dr["PageID"]);
    string name = dr["PageName"]?.ToString() ?? "";
}
```

### Reading into a DataSet

```csharp
var cb = new CommandBuilder();
cb.Add("SELECT * FROM MyCustomTable WHERE Status = {0}", "Active");
DataSet ds = Database.CreateDataSet(cb);

foreach (DataRow row in ds.Tables[0].Rows)
{
    string value = row["ColumnName"]?.ToString() ?? "";
}
```

### Scalar Query

```csharp
var cb = new CommandBuilder();
cb.Add("SELECT COUNT(*) FROM EcomProducts WHERE ProductActive = {0}", true);
int count = Converter.ToInt32(Database.ExecuteScalar(cb));
```

### Write (Insert / Update / Delete)

```csharp
var cb = new CommandBuilder();
cb.Add("INSERT INTO MyCustomTable (Name, CreatedAt) VALUES ({0}, {1})", "Test", DateTime.UtcNow);
Database.ExecuteNonQuery(cb);
```

### CommandBuilder Parameter Syntax

`CommandBuilder` uses positional `{0}`, `{1}`, … placeholders that are mapped to parameterized SQL (`@p0`, `@p1`, …) — **never string-interpolated**, so SQL injection is not possible:

```csharp
cb.Add("WHERE Name LIKE {0}", "%" + searchTerm + "%"); // Safe: searchTerm goes as @p0
```

Multiple `Add()` calls append to the same SQL string:

```csharp
var cb = new CommandBuilder();
cb.Add("SELECT * FROM MyCustomTable");
cb.Add(" WHERE Active = {0}", true);
if (filterByName)
    cb.Add(" AND Name = {0}", name);
cb.Add(" ORDER BY CreatedAt DESC");
```

### Using `Converter` for Safe Type Conversion

`Dynamicweb.Converter` handles null values and type coercions from `DataReader` columns:

```csharp
int id = Converter.ToInt32(dr["MyInt"]);       // null → 0
bool flag = Converter.ToBoolean(dr["MyBit"]);  // null → false
double val = Converter.ToDouble(dr["MyDecimal"]);
DateTime dt = Converter.ToDateTime(dr["MyDate"]);
```

## Caching

`Dynamicweb.Caching.Cache.Current` implements `ICacheManager` and provides the platform cache shared across all modules.

### Basic Cache Read-Through Pattern

```csharp
using Dynamicweb.Caching;

const string cacheKey = "MyCompany.MyKey";

if (!Cache.Current.TryGet(cacheKey, out MyObject? value))
{
    value = LoadExpensiveData();
    Cache.Current.Set(cacheKey, value, CacheItemPolicy.DefaultStoragePolicy);
}

return value;
```

### Cache Policies

| Policy | Expiry |
|--------|-------|
| `CacheItemPolicy.DefaultStoragePolicy` | 10 minutes sliding expiration |
| `new CacheItemPolicy { SlidingExpiration = TimeSpan.FromMinutes(n) }` | Custom sliding |
| `new CacheItemPolicy { AbsoluteExpiration = DateTimeOffset.UtcNow.AddHours(1) }` | Absolute expiration |

### Cache Invalidation

```csharp
Cache.Current.Remove(cacheKey);
```

Invalidate on data change — subscribe to a notification (e.g., `Standard.Page.Saved`) and remove the relevant cache key in `OnNotify`. See [dw-extend-providers](../dw-extend-providers).

### Cache Key Design

Use namespaced keys to avoid collision between modules:

```csharp
string key = $"MyCompany.Products.{languageId}.{groupId}";
```

## Transactions

```csharp
using Dynamicweb.Data;

using var transaction = Database.CreateTransaction();
try
{
    var cb1 = new CommandBuilder();
    cb1.Add("UPDATE MyTable SET Status = {0} WHERE ID = {1}", "Done", id1);
    Database.ExecuteNonQuery(cb1, transaction);

    var cb2 = new CommandBuilder();
    cb2.Add("INSERT INTO MyLog (Message) VALUES ({0})", "Updated");
    Database.ExecuteNonQuery(cb2, transaction);

    transaction.Commit();
}
catch
{
    transaction.Rollback();
    throw;
}
```

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [Dw.Api.psm1](scripts/Dw.Api.psm1) | Writes nothing on import; each function states its own | The shared Dynamicweb connection module, READ half: `Connect-Dw`/`Assert-DwConnection` (discovery + load sentinel), `Invoke-DwApi` (+ `Remove-DwDisplayOnlyMember` for round-trip saves), `Invoke-DwMcp`/`Get-DwMcpTools` (JSON-RPC handshake, SSE, pagination), `Get-DwSqlRows`/`Get-DwSqlScalar` (array-safe, DataRow-free reads; LOCAL installs only — no remote SQL path exists by design), `Clear-DwServiceCache`, `Set-DwDbConnectionTrust`, `Get-DwConnection`. Plus the paged read half: `Invoke-DwQuery` (walks every page, reconciles against `totalCount`, refuses a repeated page), the 429/read-5xx retry with backoff inside `Invoke-DwApi`, `Get-DwTaskLastRun`/`Invoke-DwTaskRun` (poll the task's own last-run for a CHANGE, never a wall clock), `Test-DwPageProbe` (reads the body: a compile error answers 200), `Get-DwServedFileHash`, `Get-DwSqlCount` (a blank is not a zero), `ConvertTo-DwApiValue`, `Get-DwCategoryFieldSort`, `Get-DwBrowserUserAgent` (the one documented UA) |
| [Dw.Api.Write.psm1](scripts/Dw.Api.Write.psm1) | Writes; every verb is a reported dry run until `-Apply` | The WRITE half, a separate file so no one script co-locates read, upload, delete and settings-rewrite: `Remove-DwUser`, `Remove-DwGroup`, `Remove-DwDynamicStructure` (ids as STRINGS, the structure by its unique-id GUID, every delete proved by a read-back), `Set-DwGlobalSetting` + `Assert-DwGlobalSettingNode` (a by-key read is never proof; the effect probe is mandatory), `Send-DwFile` (explicit destination name, size poll, served-bytes hash), `Clear-DwRecycleBin` (subset of an expected id set, never a count delta). It refuses arbitrary SQL through a scheduled task and the whole admin-account lifecycle |
| [tests/Dw.Api.Tests.ps1](scripts/tests/Dw.Api.Tests.ps1) | Read-only | Hermetic Pester coverage for both modules: paging concatenation, retry and backoff, the payload fence, the count contract, and that every write verb is a no-op that issues no request without `-Apply`. `pwsh -NoProfile -c "Invoke-Pester -Path skills/dw-data-access/scripts/tests/Dw.Api.Tests.ps1"` |
| [Build-DwProductIndex.ps1](scripts/Build-DwProductIndex.ps1) | Writes: rebuilds a Lucene index (flushes product caches first) | The enforced flush-build-poll form with the freshness guard, the Error-vs-first-build distinction, the 10.28.x status-verb fallback, and `-Passes 2` for multi-instance indexes; never re-fires on a timeout. The contract it implements is owned by `dw-search-indexing` ("index-management"); in-product the same rebuild is MCP `build_product_index` |
| [Invoke-DwMojibakeCensus.ps1](scripts/Invoke-DwMojibakeCensus.ps1) | Read-only (optionally writes a JSON census) | Double-encoded-UTF-8 census per table.column: broken markers vs healthy typography, U+FFFD contexts as escaped spans; markers built from code points. Local installs only |
| [Dw.Sql.Local.psm1](scripts/Dw.Sql.Local.psm1) | Writes nothing on import; `Invoke-DwSqlNonQuery` / `Invoke-DwSqlScalarWrite` write | The one local-only SQL non-query path, kept out of `Dw.Api.psm1` (which ships reads only). Parameters are bound, never string-built; `$null` binds as `DBNull` so the `TaskParentId` NULL-not-0 rule holds; `Assert-DwSqlLocal` parses the server out of the connection string and refuses anything that is not this machine |
| [Copy-DwIntegrationJob.ps1](scripts/Copy-DwIntegrationJob.ps1) | Writes: one new Integration Framework job file (dry run by default) | The UTF-16LE copy/decode/re-point/round-trip/diff/GUID-remint sequence. Refuses a source without the `FF FE` BOM, re-mints every `<mapping uid>`, diffs decoded-vs-decoded, and re-reads the written bytes before reporting success. The doubled `Files\Files` root and the false-clean grep are in [`references/recipes-integration.md`](references/recipes-integration.md) |
| [Test-DwJobSchema.ps1](scripts/Test-DwJobSchema.ps1) | Read-only | Validates a job file (or a whole jobs folder) on the DECODED text: encoding, mapped columns absent from the `<Schema>` snapshot, the `SqlColumn`-vs-plain destination shape, connection nodes written under a UI alias, an empty connection node on a SqlProvider source, a shared mapping uid, and a credential in a connection node |
| [Register-DwScheduledTask.ps1](scripts/Register-DwScheduledTask.ps1) | Writes: one `ScheduledTask` row, then a cache flush (dry run by default) | The multi-column row contract enforced — `TaskParentId` NULL not 0, every schedule column `-1`, registered disabled, literal settings XML, the `Dynamicweb.Scheduling.TaskService` flush and the paged verification read. Refuses a RunSql add-in type. `TaskBegin`/`TaskNextRun` semantics stay in [`references/recipes-extend.md`](references/recipes-extend.md) |
| [Invoke-DwSqlThenFlush.ps1](scripts/Invoke-DwSqlThenFlush.ps1) | Writes: the given SQL, then the named cache flushes (dry run by default) | The `UPDATE` -> flush -> touch order made unskippable: refuses to run without a `-CacheTypeName` (or a justified `-NoFlush`), `-ListCaches` enumerates the registered names, and a rejected flush fails the run rather than leaving a committed write behind a live stale cache |
| [Invoke-DwAssortmentBuild.ps1](scripts/Invoke-DwAssortmentBuild.ps1) | Writes: flags, builds and optionally activates an assortment (dry run by default) | Flag, build, poll `get_assortments_for_build` until drained, count the built items, and activate only on a non-zero count. Carries the array-of-request-objects body shape and refuses `-ActivateWhenNonEmpty` with `-SkipCountGate`, because activating a zero-item assortment takes the whole catalogue away from everyone who holds it |
| [Set-DwPermission.ps1](scripts/Set-DwPermission.ps1) | Writes: one entity grant via `PermissionSave` (dry run by default) | The nested `{Model:{...}}` body, the string `Key`, the four-part `\|$\|` composite identifier, and the read-back with `SubName` OMITTED (passing `""` returns an empty `data` array). Takes the level by name and prints the number, because `1` is `None`, a denial |
| [Test-DwPageGating.ps1](scripts/Test-DwPageGating.ps1) | Read-only | Signs a GRANTED and a DENIED persona in on their own cookie sessions, fetches the page BY ID, and compares rendered body sizes — one persona is refused, and equal bodies are reported as a broken check rather than a pass |
| [Test-DwImpersonationGrant.ps1](scripts/Test-DwImpersonationGrant.ps1) | Read-only | Reads `AccessUserSecondaryRelation` in BOTH directions and names which one it found (the wrong direction is silent), then reports the `Users.index` state so a grant is not called live while the index still answers from the pre-write documents |

Scripts in other skills import it `$PSScriptRoot`-relative and assert the load (see the fenced
form below); the traps it encodes are documented in
[`references/management-api-and-sql.md`](references/management-api-and-sql.md), which also states
every rule the two modules enforce in prose, so nothing is learnable only by reading a script.

The read half and the write half are two files on purpose: endpoint protection scores the verbs a
script co-locates, and one file that reads, uploads, deletes users and rewrites settings is the
shape that gets quarantined. Import the write half only where you write; it imports the read half
itself. Two verb families are refused outright and have no shipped script: arbitrary SQL executed
through a scheduled task, and admin-account creation, deletion or backend-access revocation. Do
those by hand on the admin Users screen.

```powershell
Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Api.psm1') -Force -ErrorAction Stop
Assert-DwConnection
```

## Deep references

Out-of-product recipes harvested from the in-product skills live one per area. Each names its
surface per the repo convention (MCP `snake_case`, Management API `PascalCase` with the route,
serializer by command or by layer and mode, `SQL` in a fenced block).

| Area | Reference | Reach for it when |
|---|---|---|
| Versions | [Reading the host's versions](#reading-the-hosts-versions) (above) | Before any version-specific recipe: read the four vendor axes off the host and compare them with the manifest's `worksOn` |
| Commerce | [references/recipes-commerce.md](references/recipes-commerce.md) | Carts, checkout, discounts, catalog publishing — below rung 1 |
| Commerce — RMA | [references/recipes-commerce-rma.md](references/recipes-commerce-rma.md) | Claims, RMA states, the RMA service flush — below rung 1 |
| Commerce: orders | [references/recipes-commerce-orders.md](references/recipes-commerce-orders.md) | Order states, order removal, priced demo orders, stored totals, order dates, reverting a converted cart: below rung 1 |
| Extend | [references/recipes-extend.md](references/recipes-extend.md) | AddIn restarts, install-state probes, StaticLinkManager requests, registering a scheduled task by SQL: below rung 1 |
| Integration | [references/recipes-integration.md](references/recipes-integration.md) | Integration Framework activities: an activity is a file, not a row — copying, validating and binding one to a task: below rung 1 |
| Content | [references/recipes-content.md](references/recipes-content.md) | Pages, paragraphs, grid rows, item types, language layers — below rung 1 |
| PIM | [references/recipes-pim.md](references/recipes-pim.md) | Products, groups, variants, completeness, product translation — below rung 1 |
| Users | [references/recipes-users.md](references/recipes-users.md) | Users, groups, permissions, page gating — below rung 1 |
| Search | [references/recipes-search.md](references/recipes-search.md) | Indexes, repositories, queries, index builds — below rung 1 |
| Swift | [references/recipes-swift.md](references/recipes-swift.md) | Swift 2 re-skin, template and asset work that leaves `Files/` — below rung 1 |

- [references/management-api-and-sql.md](references/management-api-and-sql.md) — the `/admin/api/` Management API surface (admin-endpoint catalog, `BuildIndex`/`IndexStatus`, `CacheInformationRefresh`/`GetServiceCaches`), verb shadowing by installed add-ins, the read-model-is-not-a-save-model trap (`modelIdentifier`/`*Icon` stripping), admin-screen `Type=` query discovery, OpenAPI/reference-path discovery, PowerShell SQL-read footguns (`DataRow` unrolling, `[ordered]@{}` integer keys, AMSI-blocked helpers), and the SQL-direct Page/GridRow/Paragraph required-column schema (kept for forensics and the narrow sanctioned SQL cases).
- [references/cache-invalidation.md](references/cache-invalidation.md) — the post-mutation cache table: which cache each mutation touches, which surface flushes it, and when a host restart is owed. Covers the edit-vs-insert rule for content tables, the UPDATE, flush, then touch ordering (the next API save of a cached entity erases a SQL write made behind it), the per-entity three-pattern taxonomy (self-invalidating, recycle clears it, needs an API touch), the raw-SQL `AccessUser` split-brain, and the index-build-reads-through-cache ordering trap (flush-then-rebuild).
- [references/sql-direct-gotchas.md](references/sql-direct-gotchas.md) — writing the SQL statement itself when SQL is the sanctioned rung: XML documents stored in `nvarchar(max)` columns (`Paragraph.ParagraphModuleSettings`, "implicit conversion from data type xml"), IDENTITY allocation surviving a rolled-back dry run ("the dry run printed different ids"), and the prove-then-commit pattern; a batch compiled as a whole ("Invalid column name" on the column being added: `GO`, or `EXEC()` inside one transaction), silent truncation of an `N''` literal chain and of a too-small variable, nesting block comments ("Missing end comment mark"), the reserved `LineNo` and the inclusive `RESTART WITH`, and a `/Files/...` path rewritten by Git Bash.

## Pitfalls

**A serializer `merge` of a table that has no primary key deletes the host's rows in that table.** Symptom: a delivery that carries one row of a table reports `N created, 0 failed`, nothing errors and strict mode stays quiet, but every row the host already held in that table is gone afterwards — and child rows that key on them are left orphaned, because a child table that *does* have a primary key is upserted normally. Cause: the SqlTable provider picks its write strategy from the key metadata before it reads the mode, and a table with no primary key is written truncate-and-insert in **every** mode, `merge` included. The only key source it consults is the table's PRIMARY KEY constraint, so an identity column or a unique index does not rescue it. Confirm a suspect table with `SELECT OBJECTPROPERTY(OBJECT_ID('<table>'), 'TableHasPrimaryKey')` — `0` is a heap and unsafe to merge. On DW 10.28 the heaps that matter are **`DynamicStructures`** (Dynamic Workspaces) and **`Languages`**; a stock full-sync predicate set names both, so copying one and running a `merge` takes out every workspace or every language the payload does not carry. Until the engine fix lands — it resolves a key for a keyless table and adds a per-entry `keyColumns` field to say so explicitly — treat a heap as **`replace`-only and opt-in**: drop its predicate from the composed config before delivering onto a host that owns rows in it, dry-run (`IsDryRun`) and count the table's rows before and after, and write the row set with rung 1 or rung 2 instead when the host's rows must survive.

**Never use `Dynamicweb.Data.Database` for Ecommerce core writes** — use `Dynamicweb.Ecommerce.Services.Products.Save(product)`, `Orders.Save(order)`, etc. Raw SQL bypasses caching and notification subscribers.

**Don't use string interpolation for SQL** — always use `CommandBuilder` parameters. String concatenation enables SQL injection.

**`DataReader` must be disposed** — always wrap with `using`. Failing to dispose holds the DB connection open.

**`DataSet` for large result sets is expensive** — prefer `CreateDataReader` for high-volume reads; `CreateDataSet` loads everything into memory.

**Context.Current is null in scheduled tasks** — the `Database` static class works fine in background tasks; no request context is needed.

**Column names are case-sensitive** — `dr["PageID"]` and `dr["Pageid"]` are different. Always use the exact column name as defined in the DB schema.

## Next Steps

- **Need to call Dynamicweb domain APIs?** See [dw-extend-csharp-api](../dw-extend-csharp-api)
- **Running SQL on a schedule?** See [dw-extend-scheduled-tasks](../dw-extend-scheduled-tasks)
- **Invalidating cache from a notification?** See [dw-extend-providers](../dw-extend-providers)
