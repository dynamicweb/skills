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
`GridRowGapX/Y` / `GridRowColorSchemeId`) are settable only on this SQL surface — the MCP
`save_grid_rows` model doesn't carry them **and a later MCP save of the same row silently reverts
them**. Write them after all MCP saves of the row, then restart; the ordering rule and cache rows live
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
[`commerce-b2b.md`](commerce-b2b.md).
