# Foundational candidate → dw-data-access

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 instance-access / Management API knowledge, staged here for a future
> fold-up into `dw-data-access`. No demo/customer content. When folded, move this body into
> `dw-data-access` and re-target the pointers in the demo skills. Until then, the demo skills
> reference this file.

## The Management API admin surface

A running Dynamicweb 10 host exposes an admin Management API at `https://localhost:<PORT>/admin/api/`
authenticated with `Authorization: Bearer CLAUDE.xxx` tokens. The interactive spec UI lives at
`/admin/api/docs/`. This surface covers admin operations that the MCP plugin does not expose.

### Admin-endpoint catalog

| Endpoint | Method | Purpose |
|---|---|---|
| `/admin/api/BuildIndex` | POST | Build a Lucene index. Body: `{"Repository":"Products","IndexName":"Products.index","BuildName":"Full","BuildType":"Full"}`. |
| `/admin/api/IndexStatusByRepositoryAndIndexName` | GET | Poll index-build status. Query: `?Repository=<repo>&IndexName=<name>.index` → `{ State: Success\|Warning\|Error, LastRun, ... }`. Poll until `State=Success` with `LastRun` newer than your BuildIndex POST (a stale prior build satisfies a state-only check). No `Status`/`Idle` field exists on 10.26.x models. |
| `/admin/api/InstanceStatusByName` | GET | Poll a single index instance. Query adds `&InstanceName=<instance>` → `{ State, LifecycleState: NeverBuilt\|...\|Completed\|Failed, LastSuccessfulBuild, CurrentCount, TotalCount }`. A never-built index reports index-level `State=Error` while its first build runs — terminal only when `LifecycleState=Failed`. Live JSON is camelCase despite the PascalCase catalog. |
| `/admin/api/ProductCombine` | POST | Product-combine / variant-combination operations. |
| `/admin/api/CacheInformationRefresh` | POST | Clear a specific service cache. Body: `{"CacheTypeName":"Dynamicweb.Ecommerce.Shops.ShopService"}`. |
| `/admin/api/GetServiceCaches` | GET | Enumerate all registered service caches (read-only) — discover cache ids before a targeted refresh. |
| `/admin/api/FeatureManagementToggle` | POST | Toggle a feature flag. Body: `{"FeatureTypeName":"..."}`. |
| `/admin/api/CompletionSettingsSourceById` | GET | Inspect completion-rule usage. Query: `?Id=<ruleId>` (read-only). |

Reach for the Management API before restarting the host when a cache flush is all that's needed —
`CacheInformationRefresh` / `GetServiceCaches` resolve most "stale after a direct mutation" cases
without a host bounce. See [`cache-invalidation.md`](cache-invalidation.md) for which cache each
mutation touches and whether a flush suffices.

### Short command names are not unique — an installed add-in can SHADOW a platform verb

Commands register under a short name, and short-name resolution prefers the add-in. So a solution
carrying a third-party add-in can answer a platform query with the add-in's entity, at `200`, with a
well-formed model of the wrong thing — the failure has no error and no version signal. Observed with a
dealer-portal add-in shadowing the Email-Marketing `Flow*` verbs:

```
GET /Admin/Api/FlowById?Id=1                                       -> the ADD-IN's flow
GET /Admin/Api/Dynamicweb.Marketing.UI.Queries.FlowByIdQuery?Id=1  -> the Marketing flow
```

**When a query returns a plausible model that is the wrong ENTITY, suspect shadowing before suspecting
your payload, and re-call with the fully-qualified type name.** Shadowing is per-command, not per-family —
`FlowStepsByFlowId` and `FlowFolderById` were *not* shadowed in the same install — so qualify the specific
verb that misbehaves rather than rewriting the whole call site. The qualified names come from `api.json`
(or the command class in a DW10 source clone).

### A read model is not a save model — strip the display-only members before posting it back

The natural round-trip (`GET <Entity>ById` → mutate one field → `POST <Entity>Save`) fails on several
entities because the read model carries members the save command cannot deserialize. The response is an
opaque **HTTP 500**, which reads as a server fault rather than a payload defect, and bisecting the model is
the only way to find the culprit. Two members are known offenders — `modelIdentifier` (already required
stripping on `GridRowSave`) and any `*Icon` presentation member:

```
GET EmailById -> POST EmailSave  (verbatim)                        -> 500
  … minus *ProviderFields                                          -> 500
  … with emailLastExportDate nulled                                -> 500
  … minus modelIdentifier AND emailStateIcon                       -> 200
```

**Delete `modelIdentifier` and any presentation-only member (`*StateIcon`, `*Icon`) from the model before
any round-trip save**, and when a `Save` 500s on a verbatim round-trip, bisect the model rather than
hunting the data.

### `EmailsByFilters` treats a missing filter as no-match, and `IsAutomationList` reports a false count

Two filter behaviours on the email grid queries that produce wrong result sets rather than errors:

- **`TopFolderId` and `EmailFolderId` must BOTH be supplied.** A missing `EmailFolderId` is evaluated as
  *no-match*, not as *any* — the query returns an empty or truncated set for a folder that is fine.
- **`IsAutomationList=true` returns EVERY email in the install while reporting `totalCount=0`.** Both
  halves are wrong and they point in opposite directions, so neither the rows nor the count can be trusted
  from that filter. (`EmailNavigationByPath` is similarly unhelpful — it returns `sections=0` even for a
  valid `Path=/Marketing/Email`.)

Query with both ids and verify the returned set against the folder you expect; never size an email
population from a `totalCount` on this surface.

### Discovering admin screens and their backing queries — and the cost of guessing verb names

**There is no navigation API.** `NavigationTree`, `Navigation`, `AdminNavigation`, `Areas` and `ModuleAll`
all answer `400 Unknown query`; admin screens are server-rendered routes and cannot be enumerated
programmatically. The productive trick is one level down:

**Every admin screen route carries a `Type=<query name>` parameter, and that value IS a Management API query
the bearer token can call directly.** So "does this admin screen show data?" is answerable with no browser in
the loop:

```
/Admin/UI/.../<Screen>?…&Type=<QueryName>&QueryContext=Dynamicweb.CoreUI.Data.DataQueryContext
                            ^^^^^^^^^^^^  -> GET /Admin/Api/<QueryName>?…
```

Harvest the route→query map **once**, by driving the real admin under a throwaway account and reading the
route parameters (the same read-only Playwright motion as capturing the SPA's own HTTP calls — see
[`../surface-priority.md`](../surface-priority.md) "Admin UI is verification-only"). Observed shape: several
distinct commerce screens (incomplete orders, subscriptions, ledgers/invoices) all resolve to the **same**
order-list query with different filters, while discounts, vouchers, loyalty and gift cards each name their
own. Row counts from those queries matched the rendered screens exactly, before and after seeding — which is
what makes this a **sanctioned assertion surface** for "the demo's screens are populated".

**Every wrong verb name you try writes an Error row onto the customer's Insights dashboard.** An unresolvable
command name is logged as an `[Application/AddInManager]` Error — the exact counter the owner-facing
Monitoring dashboard shows:

```
Unable to resolve type <GuessedName> with base type Dynamicweb.CoreUI.Data.DataQueryBase
```

One inherited host carried **71 errors/day that were the agents' own fingerprints**, including 122 rows in 11
seconds from a single malformed probe loop, with timestamps clustering exclusively inside prior agent session
windows. So probing is **not free**:

- **Prefer enumerating the API catalogue** (`api.json`) over guessing names one at a time.
- **Batch verb probing and do it EARLY in a session**, then follow it with a log clear before any demo.
- **Never fire write verbs speculatively** while probing a registry.
- Log-clear recipe and the retention gap that lets these accumulate:
  [`tracking-insights.md`](tracking-insights.md) "Nothing ever trims `GeneralLog`".

Related and equally cheap: `HealthProviderChecksByProviderName` and its two siblings serve the Insights
health-provider data over the same bearer, with each check returning the literal SQL it ran
([`tracking-insights.md`](tracking-insights.md) "Health providers are reachable over `/Admin/Api`").

## OpenAPI discovery

The OpenAPI JSON path on a running DW10 host is not officially documented and varies by Swashbuckle
version. Probe it at runtime rather than hardcoding:

> Run in PowerShell, not Bash — Bash interpolation eats `$env:` and `$_` before they reach the script.

```powershell
# Probe the Swagger UI to find the actual OpenAPI JSON URL
$port = (Select-String -Path .\Dynamicweb.Host.Suite\Properties\launchSettings.json -Pattern 'https://localhost:(\d+)' | Select-Object -First 1).Matches[0].Groups[1].Value
$swaggerUiHtml = Invoke-WebRequest -Uri "https://localhost:$port/admin/api/docs/" -UseBasicParsing
# Look for the OpenAPI JSON URL in the swagger-initializer.js or inline script
$specMatch = [regex]::Match($swaggerUiHtml.Content, 'url:\s*"([^"]+)"')
if ($specMatch.Success) { Write-Host "OpenAPI JSON: https://localhost:$port$($specMatch.Groups[1].Value)" }
else { Write-Host "Could not auto-discover; open /admin/api/docs/ in browser and inspect the Network tab." }
```

The probe degrades gracefully — if the regex misses, the Network-tab fallback always works. Port
discovery follows the discover-from-project-files rule (port from `launchSettings.json`, not
hardcoded).

## Reference-path discovery

Instance-specific values are discovered per project from the host's own files — never assumed to
carry across projects.

| Ref | How to find it in the current project |
|---|---|
| Solution root | The working directory (or the parent folder containing `Dynamicweb.Host.Suite/`) |
| Host URL / port | `.mcp.json` at solution root, or `Dynamicweb.Host.Suite/Properties/launchSettings.json` under `applicationUrl` |
| SQL Server | Default `localhost\SQLEXPRESS` on Windows dev boxes; verify via `GlobalSettings.Database.config` connection string |
| DB name | `Dynamicweb.Host.Suite/GlobalSettings.Database.config` — `Database=` or `Initial Catalog=` in the connection string |
| Management API token | Project-specific bearer token of the form `CLAUDE.<hex>`; supplied per project, not reused across projects |
| DW10 source clone | search `src/Features/Ecommerce` for Ecom internals and `Dynamicweb.Products.UI` for admin-UI behaviour; otherwise fall back to https://doc.dynamicweb.dev/ |

Treat any token, port, or path given at runtime as scoped to the project in the current working
directory — hold it in conversation state, not as a global default.

## SQL-direct content seeding — Page / GridRow / Paragraph

> **Retired as a seeding motion — kept as a forensic / teardown schema reference.** "Seed content by
> writing rows directly (SQL-direct, or SQL via `RunSqlScheduledTaskAddIn`) because the API is out of
> reach" is no longer a sanctioned demo recipe. The admin UI is **API-first**: every UI action lands on
> `/Admin/Api`, so if the UI can do it an endpoint exists — capture the SPA's network call (read-only
> Playwright) and replay it (MCP → Management API). **Do not reach for SQL when the API gets hard; file a
> learning instead.** The column schema below stays only to *diagnose* rows that were already SQL-seeded
> (why a hand-INSERTed row renders wrong) and for the narrow, still-sanctioned local-only SQL cases —
> cleanup/teardown and reads — per [`../surface-priority.md`](../surface-priority.md). It is **not** a
> content-authoring path.

**The preferred surface for content is MCP** `save_pages` / `save_grid_rows` / `save_paragraphs` /
`set_item_field_values` — those run the domain services (cache invalidation, `ItemList`/`ItemListRelation`
wiring, sibling links) that raw SQL skips. When MCP doesn't expose an operation, the Management API does
(the admin UI proves the endpoint exists). Repeater/slider children, once thought SQL-only, edit cleanly
through `POST /Admin/Api/ParagraphSave` — see
[`content-modelling.md`](content-modelling.md) §2.

**`save_pages` does not persist `urlName` / `navigationTag` / `hidden` (verified 10.27.x).** Even the
MCP-first path needs a **targeted** SQL touch-up for these three: a page created via `save_pages` lands
with a derived URL slug, no navigation tag, and default visibility **regardless of what you pass** for
those fields. This is the sanctioned "confirmed silent no-op → local SQL fallback" case (round-trip-verify
it): after the MCP create, set `Page.PageUrlName`, the navigation-tag column, and `Page.PageHidden` via SQL
(then restart per the cache rules below). Keep the page's *creation* on MCP/the API — do not fall back to
authoring the whole row in SQL.

**Read side — the ADO.NET single-row indexing footgun silently returns a COLUMN where you expected a
ROW.** This bites the sanctioned use of SQL (verification reads), not the retired one, so it survives the
retirement above. PowerShell unrolls a one-element `DataRow` collection into the `DataRow` itself, and `[0]`
on a `DataRow` indexes its first **column**. A verification read against a one-row result therefore returns
a plausible wrong value — frequently `0` — with no error, and the assert built on it passes or fails for
reasons unrelated to the data:

```powershell
$rows = Invoke-SqlQuery "SELECT PageId, PageName FROM Page WHERE …"   # returns exactly 1 row
$rows[0].PageId        # WRONG — $rows unrolled to the DataRow; [0] is column 0, .PageId then reads off it
@($rows)[0].PageId     # correct — force the array, then index the row
```

**Fix it INSIDE the shared read helper — forcing `@()` at the call site is not a rule that holds.** Four
independent workstreams hit this on the same day against one shared `_sql.ps1`, and each produced a confident
page of wrong output rather than an error: a run of bogus "Invalid column name" errors, a payload posted full
of blanks that invoiced nothing, and a page of zeros printed while the underlying data was perfect. A helper
that returns `@($table.Rows)` is unrolled by PowerShell whenever the result set has exactly one row, so the
guarantee has to live where the unrolling happens. **Return the array from inside the helper (and assert it:
a one-row query returns an array), and read scalars through a dedicated `Sql-Scalar` that returns
`ExecuteScalar` directly.** A verification read that can quietly return `0` is worse than no verification: it
converts "the write did not land" and "my reader is wrong" into the same observation.

**Companion trap on the same helper: never `ConvertTo-Json` a raw `DataRow`.** The object graph behind a
`DataRow` is enormous (table → schema → parent dataset), so the call does not error — it **hangs**, and cost a
five-minute timeout on the run that measured it. Project into a `pscustomobject` with the columns you want
before serialising, and document both traps in the helper header where the next caller will read them.

### `[ordered]@{}` with integer keys indexes by POSITION, not by key

The other silent-wrong-answer trap of the same family, and the more dangerous one because DW ids are integers
and lookup tables keyed on page / paragraph / user ids are the natural shape. **Bare numeric keys in an ordered
dictionary are `Int32`, and `$table[$id]` with an `Int32` hits `OrderedDictionary`'s POSITIONAL indexer**, not
the key indexer. The index is out of range, so it returns `$null` with **no error** — or throws a misleading
"Cannot index into a null array" one line later, pointing at innocent code:

```powershell
$plan = [ordered]@{ 1293 = @{ … }; 1294 = @{ … } }   # keys are Int32
$plan[1293]                                          # asks for the 1,294th ENTRY -> $null
$plan = @{ 1293 = @{ … } }                           # plain hashtable -> keyed lookup, correct
```

Four workstreams hit this in one day. The most dangerous instance was a rename loop that consequently saved
every user with an **unmodified** model: it looked like it worked, printed a plausible line per row, and
changed nothing — and one workstream initially attributed the resulting no-op to an unrelated platform bug and
had to re-prove that bug afterwards with an explicit single-field save. **Quote the keys, use a plain
hashtable, or iterate `.GetEnumerator()`** — and a `-WhatIf` dry run that prints resolved target values is what
catches it, since empty values are the only signal.

### A dot-sourced helper can fail to load while the calling script keeps running

The third member of the silent-wrong-answer family, and the only one whose cause is outside the script. **A
shared SQL helper can be blocked by AMSI as malicious content** — a false positive, almost certainly triggered
by an inline connection string carrying credentials:

```
. .\_sql.ps1
  -> "This script contains malicious content and has been blocked by your antivirus software"
  -> the dot-source fails, the SURROUNDING script keeps running
  -> every call to the helper is "not recognized"; every DB comparison silently reads EMPTY
```

Same helper, same host, **intermittent** — a re-run works. The failure is indistinguishable from real data
drift unless the load is asserted: one verification pass produced four bogus `STALE` verdicts because it had
been comparing against empty strings the whole time.

- **Assert the helper actually loaded, immediately after every dot-source** — a trivial `Sql-Scalar "SELECT 1"`
  probe (or a sentinel variable the helper sets) — and **fail loudly** rather than comparing against empty
  output.
- **Move credentials out of the inline literal** to reduce the false positive.

Same failure shape as the two traps above: a comparison that returns a plausible wrong answer with no error
is worse than no comparison, because it makes "the write did not land" and "my reader is broken" the same
observation.

### Bulk string edits: DW 10 still ships legacy `text` / `ntext` columns

`REPLACE` refuses `ntext` as its first argument, so a straightforward bulk string fix fails on exactly the
tables where long strings live (e.g. `GeneralLog.LogDescription`):

```
UPDATE GeneralLog SET LogDescription = REPLACE(LogDescription, …)
  -> Argument data type ntext is invalid for argument 1 of replace function
```

**`CAST(… AS nvarchar(max))` inside the `REPLACE`** is the fix. Any bulk-content or anonymisation sweep must
name the legacy column types explicitly, or it silently skips the tables it cannot update — and then reports a
clean pass. Assert zero remaining hits in the `ntext` columns as well as the `nvarchar` ones.

### Reachability queries over item tables must be TYPE-filtered on every branch

**Item ids are allocated per item TYPE, not globally**, so an id in one `ItemType_*` table routinely collides
with an unrelated id in another. A `UNION` branch that joins on `PageItemId` (or `ParagraphItemId`) without
also constraining `PageItemType` / `ParagraphItemType` pulls in any item row whose id merely collides with a
page item id — one asset sweep was inflated by ~20 phantom hits that resolved to pages not using those items
at all.

**Every branch of a reachability query needs its own `PageItemType` / `ParagraphItemType` constraint**, not
just the first one. Verify by asserting each resolved hit page actually references the item type being queried
— a sweep whose result set is too large is as wrong as one that is too small, and it is the one that gets
acted on.

### Required NOT-NULL columns — `Page`

DW10 returns 404 for a SQL-inserted Page even when the slug resolves, unless every column below carries
a real value:

```sql
INSERT INTO Page (
    PageAreaId, PageItemType, PageItemId,   -- PageItemId must reference an existing ItemType_<PageItemType> row id
    PageMenuText, PageUrlName,
    PageActive,        -- 1 (in nav) or 0 (Hidden in Menu)
    PageHidden,        -- 0 (routable) or 1 (excluded from routing)
    PageDeleted,       -- 0
    PageMasterType,    -- 1 for content pages
    PageShowInSitemap, -- 1
    PageActiveFrom,    -- any date <= now (e.g. '2026-01-01 00:00:00')
    PageActiveTo,      -- far-future sentinel '2999-12-31 23:59:59'
    PageUniqueId,      -- NEWID()
    PageSort
) VALUES (<areaId>, 'Swift-v2_Page', '<itemId>', '<menu text>', '<url-slug>',
    1, 0, 0, 1, 1, '2026-01-01 00:00:00', '2999-12-31 23:59:59', NEWID(), 1);
```

`PageActiveFrom` / `PageActiveTo` are the silent killers — without them page-resolution treats the row
as scheduled-out and returns 404 even though the slug resolves. The other NOT-NULL columns surface a
more useful `Cannot insert NULL` on first attempt. (`PageActive` vs `PageHidden` semantics — "Hidden in
Menu" vs route availability — are owned by [`swift-building.md`](swift-building.md) §6.)

### Required NOT-NULL columns — `GridRow`

```sql
INSERT INTO GridRow (
    GridRowPageId, GridRowContainer,    -- typically 'Grid'
    GridRowDefinitionId,                -- '1Column' / '2Columns' / '3Columns' / …
    GridRowItemType,                    -- 'Swift-v2_Row' — required; NULL drops the Swift wrapper class
    GridRowSort, GridRowUniqueId        -- NEWID()
) VALUES (<pageId>, 'Grid', '1Column', 'Swift-v2_Row', 1, NEWID());
```

`GridRowDefinitionId` must name a RowDefinition JSON that actually exists under
`Designs/<design>/Grid/Page/RowDefinitions/` — an unknown id renders **nothing, silently** (the row and
all its paragraphs vanish from the page with no error). Enumerate that folder before composing; Swift v2
ships `1Column`–`4Columns`, `6Columns`, the `*Flex` variants and asymmetric `2Columns_*` splits — there
is no `5Columns`.

Layout columns (`GridRowTopSpacing` / `GridRowBottomSpacing` / `GridRowVerticalAlignment` /
`GridRowGapX/Y` / `GridRowColorSchemeId` / `GridRowContainerWidth`) are settable only on this SQL
surface — the MCP `save_grid_rows` model doesn't carry them **and a later MCP save of the same row
silently reverts them**. `ContainerWidth` is the per-row **content width** the Swift row template
renders as `data-dw-container-width`; the MCP model exposes only
`active`/`backgroundImage`/`colorSchemeId`/`container`/`definitionId`/`id`/`itemType`/`pageId`/`sort`,
so a site-wide width change cannot be authored as content through that tool at all. Where a row-level
SQL write is not available, the sanctioned substitute is a CSS override of `--dw-container-width`
**scoped to `main`** — header and footer read the same token, so an unscoped override moves the
chrome with the content. Verify by measured band widths at the target viewports plus zero horizontal
overflow at mobile and desktop, not by the saved value. Write them after all MCP saves of the row, then restart; the ordering rule and cache rows live
in [`cache-invalidation.md`](cache-invalidation.md) "Mixing MCP and SQL on the same rows". NULL spacing
renders as the Swift row-template default (`?? 6` = 6rem top and bottom) — serialize explicit values
when composing a page, or every section ships with ~96px bands.

### Required NOT-NULL columns — `Paragraph`

The most error-prone of the three:

```sql
INSERT INTO Paragraph (
    ParagraphPageId, ParagraphGridRowId,
    ParagraphGridRowColumn,   -- 1-based, NOT 0-based
    ParagraphItemType,        -- 'Swift-v2_Text', 'Swift-v2_Poster', …
    ParagraphItemId,          -- existing row in [ItemType_<ParagraphItemType>]
    ParagraphTemplate,        -- 'Paragraph/Swift-v2_Text/TextLeft.cshtml' — do NOT leave empty
    ParagraphSort, ParagraphUniqueId,   -- NEWID() — uniqueidentifier
    ParagraphGlobalId,        -- 0 — INT despite the "Global" name; not a GUID
    ParagraphValidFrom, ParagraphValidTo,
    ParagraphCreatedDate, ParagraphUpdatedDate,   -- GETDATE()
    ParagraphActive, ParagraphShowParagraph, ParagraphDeleted   -- 1, 1, 0
) VALUES (<pageId>, <gridRowId>, 1, 'Swift-v2_Text', '<itemId>',
    'Paragraph/Swift-v2_Text/TextLeft.cshtml', 1, NEWID(), 0,
    '2026-01-01', '2999-12-31 23:59:59', GETDATE(), GETDATE(), 1, 1, 0);
```

- **`ParagraphGlobalId` is INT-typed despite the name.** Setting it via `NEWID()` (which works for
  `ParagraphUniqueId`) fails with a type-conversion error. Use `0`.
- **`ParagraphTemplate` is the optional-looking column you do NOT want to omit** — leaving it `NULL`/`''`
  invokes Swift's empty-template alphabetical fallback (the hijack symptom + mitigations live in
  [`swift-building.md`](swift-building.md) §4).

### `ItemType_*` rows — pre-seed the item instance

Every Paragraph points at an item instance via `ParagraphItemId` → a row in
`[ItemType_<ParagraphItemType>]`. INSERT the instance row BEFORE the Paragraph, or the paragraph
renders as empty wrapper markup.

```sql
INSERT INTO [ItemType_Swift-v2_Text] (Id, Title, Subtitle, Text, ItemInstanceType)
VALUES ('<newId>', '', '', '<your html or text>', '');   -- ItemInstanceType: '' not NULL
```

- **`ItemInstanceType` is `nvarchar NOT NULL` — use empty string, not NULL.** Several
  `ItemType_Swift-v2_*` tables ship this column; `NULL` fails with `Cannot insert the value NULL into
  column 'ItemInstanceType'`. It's leftover from a legacy shape, normally populated as `''` by the
  admin item editor.
- **`MAX(Id)` on `nvarchar` ID columns lies — use `TRY_CAST`.** `ItemType_Swift-v2_*.Id` and many
  neighbouring DW10 ID columns are `nvarchar` holding integer values, so `MAX(Id)` sorts
  lexicographically (`'9'` beats `'50'`). Allocate ids with:
  ```sql
  DECLARE @nextId int = ISNULL((SELECT MAX(TRY_CAST(Id AS int)) FROM [ItemType_Swift-v2_Page]), 0) + 1;
  INSERT INTO [ItemType_Swift-v2_Page] (Id, ..., ItemInstanceType) VALUES (CAST(@nextId AS nvarchar), ..., '');
  ```
  `TRY_CAST` drops non-numeric ids instead of failing the query; the cast back to nvarchar is required
  because the column is nvarchar. Applies to every `ItemType_*` table.

### Inserting between existing rows — `GridRowSort × 10` slot reservation

To squeeze a new Paragraph/GridRow between siblings, multiply existing sorts by 10 to open slots, then
INSERT at an intermediate value:

```sql
UPDATE GridRow SET GridRowSort = GridRowSort * 10 WHERE GridRowPageId = <pageId>;  -- now 10,20,30
INSERT INTO GridRow (..., GridRowSort, ...) VALUES (..., 25, ...);                  -- insert at 25
```

This sidesteps duplicate-sort ties (DW10 renders ties non-deterministically → inconsistent layout).
Same pattern for `ParagraphSort` within a GridRow.

### Post-INSERT cache rules

- **Restart the host after every batch** — page-resolution + grid-composition caches do not observe
  SQL writes. Bundle multiple INSERTs behind one restart.
- **`GridRowSort` UPDATEs on existing rows DO require a restart** (the page-composition cache holds the
  ordered list) — the one exception to the "UPDATEs on existing rows are live" rule. Bundle the `× 10`
  rewrite + the INSERT + the restart into one operation.
- **Soft-hide flags (`ParagraphShowParagraph = 0` / `ParagraphDeleted = 1`) are unreliable inside
  `@RenderGrid`-nested pages** — for those, CSS-hide is the only lever (see
  [`swift-building.md`](swift-building.md) §5 "ProductListComponentSelector"). For paragraphs NOT inside
  a nested `RenderGrid`, the soft-hide flags work after a restart.

After restart, hit the page once (GET) to warm JIT, then confirm the content renders. If the wrapper
appears but the inner item-type fields are empty, the `ItemType_*` instance row is missing or its `Id`
doesn't match `ParagraphItemId`. See [`cache-invalidation.md`](cache-invalidation.md) for the
post-mutation cache table. Sister required-fields list for `AccessUser` SQL-direct seeding is in
[`dc-scoping.md`](../../../dw-commerce-b2b/references/dc-scoping.md).
