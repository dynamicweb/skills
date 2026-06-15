# sql-direct-seeding.md

> Required-field reference for Page / GridRow / Paragraph SQL-direct INSERTs when MCP / admin UI / Management API are out of reach (bulk demo seed flows, headless agents, sister-demo replay scripts). Cross-references [`templates.md`](templates.md), [`paragraphs.md`](paragraphs.md), and [`../../truvio-pim-demo/references/cache-invalidation.md`](../../truvio-pim-demo/references/cache-invalidation.md) for the post-INSERT restart rules.
>
> **This is the SQL-fallback surface.** The preferred surface for content seeding is MCP `save_pages` / `save_grid_rows` / `save_paragraphs` — those invalidate caches inline and don't require the field disciplines below. Read [`../../truvio-demo-base/SKILL.md` "Surface priority for CREATES"](../../truvio-demo-base/SKILL.md) before reaching for SQL. This file is the rulebook for the cases where you have already decided SQL is the right surface (bulk seeds, MCP token expiry mid-batch, no MCP available).

## When this file applies

- You're seeding many Pages / GridRows / Paragraphs in one batch and MCP round-trips are prohibitively slow.
- MCP session died mid-batch and the remaining rows need to land via SQL fallback.
- A sister-demo replay script needs to drop pages into a fresh host before the MCP session is even warm.
- An item type does not have a corresponding MCP surface (rare, but does happen for newer or project-prefixed `<Prefix>_*` types until you register the type via admin).

Everything below assumes you've already chosen SQL. If you're still deciding, escalate to MCP first.

## Required NOT-NULL columns — `Page` row

DW10 returns 404 for a SQL-inserted Page even when the slug resolves correctly, unless every column below carries a real value (2026-05-13):

```sql
INSERT INTO Page (
    PageAreaId,                -- existing AreaId
    PageItemType,              -- e.g. 'Swift-v2_Page'
    PageItemId,                -- must reference an existing ItemType_<PageItemType> row id
    PageMenuText,
    PageUrlName,
    PageActive,                -- 1 (visible in nav) or 0 (Hidden in Menu); see templates.md "Page state flags"
    PageHidden,                -- 0 (routable) or 1 (excluded from frontend routing entirely)
    PageDeleted,               -- 0
    PageMasterType,            -- 1 for content pages
    PageShowInSitemap,         -- 1 (or 0 if intentionally excluded)
    PageActiveFrom,            -- e.g. '2026-05-13 00:00:00' — any date <= now
    PageActiveTo,              -- '2999-12-31 23:59:59' — sentinel far-future
    PageUniqueId,              -- NEWID()
    PageSort
) VALUES (
    <areaId>, 'Swift-v2_Page', '<itemId>', '<menu text>', '<url-slug>',
    1, 0, 0, 1, 1,
    '2026-05-13 00:00:00', '2999-12-31 23:59:59', NEWID(), 1
);
```

The `PageActiveFrom` / `PageActiveTo` columns are the silent killers — without them DW's page-resolution treats the row as scheduled-out and returns 404 even though the slug resolves. The other NOT-NULL columns surface a more useful `Cannot insert NULL` error on first attempt.

**Post-INSERT.** Restart the host — page-resolution cache does not observe SQL-direct INSERTs (2026-05-13). See [`../../truvio-pim-demo/references/cache-invalidation.md`](../../truvio-pim-demo/references/cache-invalidation.md) for the cache table. After restart, hit the page once to warm JIT, then continue seeding.

## Required NOT-NULL columns — `GridRow` row

```sql
INSERT INTO GridRow (
    GridRowPageId,             -- existing Page.PageId
    GridRowContainer,          -- typically 'Grid'
    GridRowDefinitionId,       -- '1Column' / '2Columns' / '3Columns' / etc.
    GridRowItemType,           -- 'Swift-v2_Row'
    GridRowSort,
    GridRowUniqueId            -- NEWID()
) VALUES (
    <pageId>, 'Grid', '1Column', 'Swift-v2_Row', 1, NEWID()
);
```

**`GridRowItemType = 'Swift-v2_Row'`** is required — leaving it NULL renders the row without its expected Swift wrapper class and breaks any custom CSS keyed off `[data-dw-itemtype="swift-v2_row"]`. Restart needed (same cache rule as Page).

## Required NOT-NULL columns — `Paragraph` row

Most error-prone of the three — DW10's `Paragraph` schema has more NOT-NULL columns than the other content tables, and a handful (`ParagraphGlobalId`, `ParagraphValidFrom/To`, `ParagraphTemplate`) trip up demo seeders the first time (2026-05-13):

```sql
INSERT INTO Paragraph (
    ParagraphPageId,
    ParagraphGridRowId,        -- existing GridRow.GridRowId
    ParagraphGridRowColumn,    -- 1-based, NOT 0-based
    ParagraphItemType,         -- 'Swift-v2_Text', 'Swift-v2_Poster', 'Swift-v2_Feature', etc.
    ParagraphItemId,           -- existing row in [ItemType_<ParagraphItemType>] table
    ParagraphTemplate,         -- 'Paragraph/Swift-v2_Text/TextLeft.cshtml' — see "Empty ParagraphTemplate" pitfall below
    ParagraphSort,
    ParagraphUniqueId,         -- NEWID() — uniqueidentifier
    ParagraphGlobalId,         -- 0 — INT despite the "Global" name; not a GUID
    ParagraphValidFrom,        -- '2026-05-13'
    ParagraphValidTo,          -- '2999-12-31 23:59:59'
    ParagraphCreatedDate,      -- GETDATE()
    ParagraphUpdatedDate,      -- GETDATE()
    ParagraphActive,           -- 1
    ParagraphShowParagraph,    -- 1
    ParagraphDeleted           -- 0
) VALUES (
    <pageId>, <gridRowId>, 1,
    'Swift-v2_Text', '<itemId>',
    'Paragraph/Swift-v2_Text/TextLeft.cshtml',
    1, NEWID(), 0,
    '2026-05-13', '2999-12-31 23:59:59',
    GETDATE(), GETDATE(),
    1, 1, 0
);
```

**`ParagraphGlobalId` is INT-typed despite the name.** Setting it via `NEWID()` (which works for `ParagraphUniqueId`) fails with a column-type conversion error. Use `0` unless you have a real cross-area paragraph reference to bind to.

**`ParagraphTemplate` is the optional-looking column you do NOT want to omit** — leaving it `NULL` or `''` invokes Swift's empty-template alphabetical fallback; the hijack symptom + mitigations live in [`paragraphs.md` "Empty `ParagraphTemplate` resolves to the first cshtml alphabetically"](paragraphs.md).

**Post-INSERT.** Restart the host. Observed every time during the seed flow: SQL-direct Paragraph INSERTs do not render until the page-composition cache is flushed (2026-05-13).

## `ItemType_*` rows — pre-seeding the paragraph's item instance

Every Paragraph row points at an existing item instance via `ParagraphItemId` referencing a row in `[ItemType_<ParagraphItemType>]`. INSERT the item instance row BEFORE the Paragraph row, or the Paragraph renders as empty wrapper markup (the inner item-type fields resolve via `Model.Item.GetValue<>` which returns null for missing instance rows).

```sql
INSERT INTO [ItemType_Swift-v2_Text] (
    Id,                        -- new id; see "MAX(Id) lies" below
    Title, Subtitle, Text,     -- the item-type's content fields
    ItemInstanceType           -- '' (empty string, NOT NULL) — see below
) VALUES (
    '<newId>', '', '', '<your html or text>', ''
);
```

### `ItemInstanceType` is `nvarchar NOT NULL` — use empty string, not NULL

Several `ItemType_Swift-v2_*` tables ship with `ItemInstanceType nvarchar NOT NULL`. SQL inserts with `NULL` fail with `Cannot insert the value NULL into column 'ItemInstanceType'`. **Use empty string `''` instead** (2026-05-13). Affects: `ItemType_Swift-v2_ProductStock`, `ItemType_Swift-v2_RowFlex`, and most `Swift-v2_*` item types — the column is leftover from a legacy DW shape and is normally populated by the admin item editor as empty string on save.

### `MAX(Id)` on `nvarchar` ID columns lies — use `TRY_CAST`

`ItemType_Swift-v2_*.Id` and many neighbouring DW10 ID columns are `nvarchar` despite holding integer values. `SELECT MAX(Id) FROM [ItemType_Swift-v2_Page]` returns `'9'` even when `'50'` exists, because the sort is lexicographic (2026-05-13). Use:

```sql
DECLARE @nextId int = ISNULL((SELECT MAX(TRY_CAST(Id AS int))
                              FROM [ItemType_Swift-v2_Page]), 0) + 1;
INSERT INTO [ItemType_Swift-v2_Page] (Id, ..., ItemInstanceType) VALUES (CAST(@nextId AS nvarchar), ..., '');
```

The `TRY_CAST` form drops non-numeric ids (rare but legal) instead of failing the query. The cast back to nvarchar for INSERT is required because the column is nvarchar. This pattern applies to every `ItemType_*` table; pattern-copy it into any seed script that allocates new ids.

## Inserting between existing rows — `GridRowSort × 10` slot reservation

To squeeze a new Paragraph or GridRow between existing siblings (e.g. inserting `ProductStock` between `ProductPrice` and `ProductVariantSelector` on a PDP component-source page), the cleanest path is to multiply existing sorts by 10 to create slots, then INSERT at an intermediate value (2026-05-13):

```sql
-- Open up slots between existing rows
UPDATE GridRow
SET GridRowSort = GridRowSort * 10
WHERE GridRowPageId = <pageId>;

-- Existing rows now at 10, 20, 30 — insert the new row at 25
INSERT INTO GridRow (..., GridRowSort, ...) VALUES (..., 25, ...);
```

This sidesteps the "duplicate sort" issue — DW10 renders ties in non-deterministic order, which surfaces as inconsistent page layout across renders. Same pattern applies to `ParagraphSort` within a GridRow.

**Cache rule.** `GridRowSort` UPDATEs on existing rows DO require a host restart (the page-composition cache holds the ordered list and won't re-sort until reload). This is the one exception to the "UPDATEs on existing rows are live" rule from [`../../truvio-pim-demo/references/cache-invalidation.md`](../../truvio-pim-demo/references/cache-invalidation.md). Bundle the `* 10` rewrite + the INSERT + the restart into one operation.

## Soft-hide vs full delete — neither is observed reliably

`ParagraphShowParagraph = 0` / `ParagraphDeleted = 1` are unreliable inside `@RenderGrid`-nested pages — the canonical rule + the CSS-hide lever live in [`paragraphs.md` "ProductListComponentSelector caches even harder"](paragraphs.md). For paragraphs NOT inside a nested `RenderGrid`, the soft-hide flags work after a host restart (same cache rule as INSERTs).

## Verification after SQL-direct seeding

After every batch of Page / GridRow / Paragraph SQL INSERTs:

1. **Restart the host** — page-resolution + grid-composition caches do not observe SQL writes. The bounce is ~30 seconds on a warm SQL Express; bundle multiple INSERTs + one restart, not per-INSERT restarts.
2. **Hit the page once** with a GET request to warm JIT.
3. **Confirm in the browser** that the new content renders. If the Paragraph wrapper appears but the inner item-type fields are empty, the `ItemType_*` instance row is missing or its `Id` doesn't match `ParagraphItemId`.
4. **Run the post-deserialize integrity sweep** if the seed was substantial enough to plausibly break invariants — see [`integrity-sweep.md`](integrity-sweep.md).

## Cross-references

- [`templates.md`](templates.md) "Page state flags" — `active` vs `hidden` vs `published` semantics for the `PageActive` / `PageHidden` columns above.
- [`paragraphs.md`](paragraphs.md) — Swift's stock paragraph types, the empty-`ParagraphTemplate` alphabetical-fallback hazard, the `ProductListComponentSelector` cache rule, the Bootstrap `.ratio` aspect-ratio pitfall.
- [`../../truvio-pim-demo/references/cache-invalidation.md`](../../truvio-pim-demo/references/cache-invalidation.md) — post-mutation cache table covering every row type above.
- [`../../truvio-demo-base/SKILL.md` "Surface priority for CREATES"](../../truvio-demo-base/SKILL.md) — the MCP-first rule. SQL is the fallback, not the default.
- [`b2b-dc-pattern.md`](b2b-dc-pattern.md) "AccessUser NOT NULL columns that easily get skipped" — sister required-fields list for `AccessUser` SQL-direct INSERTs (DC group seeding).
