---
name: dw-data-access
type: knowledge
group: data
mcp: optional
dynamo: false
compatibility: Requires PowerShell 7.x
description: 'Choose the surface to act on a Dynamicweb 10 instance through, and the data-access and caching patterns inside it. Triggers: the action ladder, which surface, MCP vs Management API vs serializer vs SQL, data access, API vs SQL, cache invalidation, SQL gotchas. Non-triggers: C# API usage -> dw-extend-csharp-api; specific domain logic -> domain-specific skills.'
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
| 3 | **Serializer** (`SerializerDeserialize`, layer `replace`/`merge` trees) | `PascalCase` verb, layer paths | Bulk, id-preserving loads and cross-install moves. **A layer beats a rung-1 or rung-2 loop** as soon as the write is bulk (hundreds of rows, a whole content tree) or ids and relations must survive. Dry-run (`IsDryRun`) first. |
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
| [Dw.Api.psm1](scripts/Dw.Api.psm1) | Writes nothing on import; each function states its own | The shared Dynamicweb connection module: `Connect-Dw`/`Assert-DwConnection` (discovery + load sentinel), `Invoke-DwApi` (+ `Remove-DwDisplayOnlyMember` for round-trip saves), `Invoke-DwMcp`/`Get-DwMcpTools` (JSON-RPC handshake, SSE, pagination), `Get-DwSqlRows`/`Get-DwSqlScalar` (array-safe, DataRow-free reads; LOCAL installs only — no remote SQL path exists by design), `Clear-DwServiceCache`, `Set-DwDbConnectionTrust` |
| [Build-DwProductIndex.ps1](scripts/Build-DwProductIndex.ps1) | Writes: rebuilds a Lucene index (flushes product caches first) | The enforced flush-build-poll form with the freshness guard, the Error-vs-first-build distinction, the 10.28.x status-verb fallback, and `-Passes 2` for multi-instance indexes; never re-fires on a timeout. The contract it implements is owned by `dw-search-indexing` ("index-management"); in-product the same rebuild is MCP `build_product_index` |
| [Invoke-DwMojibakeCensus.ps1](scripts/Invoke-DwMojibakeCensus.ps1) | Read-only (optionally writes a JSON census) | Double-encoded-UTF-8 census per table.column: broken markers vs healthy typography, U+FFFD contexts as escaped spans; markers built from code points. Local installs only |

Scripts in other skills import it `$PSScriptRoot`-relative and assert the load (see the fenced
form below); the traps it encodes are documented in
[`references/management-api-and-sql.md`](references/management-api-and-sql.md).

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
| Commerce | [references/recipes-commerce.md](references/recipes-commerce.md) | Orders, carts, checkout, discounts, catalog publishing — below rung 1 |
| Commerce — RMA | [references/recipes-commerce-rma.md](references/recipes-commerce-rma.md) | Claims, RMA states, the RMA service flush — below rung 1 |
| Content | [references/recipes-content.md](references/recipes-content.md) | Pages, paragraphs, grid rows, item types, language layers — below rung 1 |
| PIM | [references/recipes-pim.md](references/recipes-pim.md) | Products, groups, variants, completeness, product translation — below rung 1 |
| Users | [references/recipes-users.md](references/recipes-users.md) | Users, groups, permissions, page gating — below rung 1 |
| Search | [references/recipes-search.md](references/recipes-search.md) | Indexes, repositories, queries, index builds — below rung 1 |
| Swift | [references/recipes-swift.md](references/recipes-swift.md) | Swift 2 re-skin, template and asset work that leaves `Files/` — below rung 1 |

- [references/management-api-and-sql.md](references/management-api-and-sql.md) — the `/admin/api/` Management API surface (admin-endpoint catalog, `BuildIndex`/`IndexStatus`, `CacheInformationRefresh`/`GetServiceCaches`), verb shadowing by installed add-ins, the read-model-is-not-a-save-model trap (`modelIdentifier`/`*Icon` stripping), admin-screen `Type=` query discovery, OpenAPI/reference-path discovery, PowerShell SQL-read footguns (`DataRow` unrolling, `[ordered]@{}` integer keys, AMSI-blocked helpers), and the SQL-direct Page/GridRow/Paragraph required-column schema (kept for forensics and the narrow sanctioned SQL cases).
- [references/cache-invalidation.md](references/cache-invalidation.md) — the post-mutation cache table: which cache each mutation touches, which surface flushes it, and when a host restart is owed. Covers the edit-vs-insert rule for content tables, the UPDATE, flush, then touch ordering (the next API save of a cached entity erases a SQL write made behind it), the per-entity three-pattern taxonomy (self-invalidating, recycle clears it, needs an API touch), the raw-SQL `AccessUser` split-brain, and the index-build-reads-through-cache ordering trap (flush-then-rebuild).
- [references/sql-direct-gotchas.md](references/sql-direct-gotchas.md) — writing the SQL statement itself when SQL is the sanctioned rung: XML documents stored in `nvarchar(max)` columns (`Paragraph.ParagraphModuleSettings`, "implicit conversion from data type xml"), IDENTITY allocation surviving a rolled-back dry run ("the dry run printed different ids"), and the prove-then-commit pattern.

## Pitfalls

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
