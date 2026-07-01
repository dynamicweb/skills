# Foundational candidate → dw-pim-completeness

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 completeness-rules + governance-dashboards knowledge, staged here for a future
> fold-up into `dw-pim-completeness`. No demo/customer content. When folded, move this body into
> `dw-pim-completeness` and re-target the pointers in the demo skills. Until then, the demo skills
> reference this file.

## `reference_category` — the load-bearing template category

Dynamicweb uses a hidden "template" category `reference_category` (`CategoryType=2`) to power every admin UI rule/completeness lookup. You need two one-time rows per DATABASE (steps 1-2) plus four rows per FIELD (steps 3-5; step 5 is two translation rows) to be complete:

1. The parent `EcomProductCategory` row for `reference_category` with `CategoryType=2` (seed ONCE per database)
2. The parent `EcomProductCategoryTranslation` row for `reference_category` (also once per database, per language)
3. One `EcomProductCategoryField` row with `FieldCategoryId='reference_category'` (mirror of the concrete field)
4. One `EcomProductCategoryField` row in the concrete category (e.g. `<CategoryName>Attributes`)
5. Both translations in `EcomProductCategoryFieldTranslation` (one for the mirror, one for the concrete field)

Missing step 1 causes the most-misleading failure in DW: rules validate, assignments persist, API returns correct data, but the product/group completeness panels in admin render empty. See "Recovery recipe: Seed `reference_category` parent row" below for the SQL. The category/field storage internals (`EcomProductCategory`, `EcomProductCategoryField`, `EcomFieldOption`, `EcomProductCategoryFieldValue`, the `ProductCategory|<Cat>|<Field>` system-name format) live in [`pim-modelling.md`](pim-modelling.md) §2.8.

## Completeness rules — why they sometimes "don't show"

Rules surface in admin UI in three places: on each product (Data Completeness panel), on each catalog group ("Completion rules" tab), and implicitly through governance widgets. For all three to work:

1. **`reference_category` must exist as a full parent + child set.** This is where admin UI resolves every rule field. Required order when seeding from scratch: 1a parent category row (`CategoryType=2`) → 1b parent translation → 1c mirror every concrete-category field row into `reference_category` (with `FieldCategoryId='reference_category'`) → 1d mirror every concrete-category field TRANSLATION row. For the SQL, run the idempotent ["Recovery recipe: Seed `reference_category` parent row"](#recovery-recipe-seed-reference_category-parent-row) below — it covers 1a + 1b with `IF NOT EXISTS` guards and explains the 1c/1d mirrors.
   Missing the 1a parent row is the #1 cause of "rule is defined and assigned but no panel renders on the product." `Settings → Completeness Rules` list still works and the `ProductCompletenessRulesByProductId` API still returns correct data — that's what makes this so misleading.
2. **Rule exists** — row in `EcomCompletionRules` with field system names pipe-separated in `EcomCompletionRuleProductFields`. Use the full format `ProductCategory|<CategoryId>|<FieldId>`, not the bare field id. Verify via `get_completion_rules` or direct SQL.
3. **Rule assigned to a catalog group** — comma-separated rule IDs in `EcomGroups.GroupCompletionRules` **plus** matching languages in `GroupCompletionLanguageIds`. Assignments to data-model groups (GroupType=2) do nothing; they must be on the catalog groups (GroupType=0) that products actually live in.
4. **Query field names match the index format** — product queries filtering by a category field must use the **full** system name `ProductCategory|<CategoryId>|<FieldId>`. The bare field id silently matches nothing in Lucene even though SQL sees values. The `FieldExpression Field="..."` attribute in the .query XML is where this lives.
5. **Index flushed *and* rebuilt after any of the above changed** — `POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full"}`. Without a rebuild, dashboard counts stay stale and queries return 0. **And if you populated the completeness FIELD VALUES on products via MCP `patch_products_safe` (or SQL), you MUST flush `ProductService` + `ProductCategoryFieldValueService` + `ProductCategoryService` via `CacheInformationRefresh` BEFORE the rebuild** — the builder reads those values through the cache and will otherwise index the empty pre-patch state, so the governance widget shows 0 failing even when products genuinely fail. This is the read-through-cache ordering trap; full recipe + the "do not call it an index quirk" note in [`search-indexing.md`](search-indexing.md) "Recovery recipe: Rebuild Products index" and [`cache-invalidation.md`](cache-invalidation.md).
6. **Host restart after rule changes via raw SQL** — `CompletionRuleService` and `ProductCategoryService` cache in `ServiceCache`. MCP `create_or_update_completeness_rules` / `assign_completion_rules_to_groups` invalidate their slice. Direct SQL INSERT does NOT. Restart the host, or save any rule once from admin UI to force a cache reload.
7. **`Completeness feature` flag** (under Settings → Feature management) **must stay OFF — never toggle it from Claude**. It activates a buggy beta calculation path. The stable legacy path runs when the flag is OFF and supports everything needed: rules, group assignments, API evaluation, admin UI panels. If the flag appears ON during a session, ask the user to disable it via admin UI — do NOT auto-call `FeatureManagementToggle`, which cascades across both the Ecommerce and deprecated Products.UI variants and does not reliably land in OFF state. The correct fix for a "rules don't show" symptom is elsewhere in this list (almost always the `reference_category` parent row in step 1), never the flag.

Quick diagnosis when rules "don't show":
- No Data Completeness panel on a product but Settings → Completeness Rules shows correct usage counts? → step 1 (parent `EcomProductCategory` row missing).
- Rules page shows the rule with empty "fields" column? → step 1c/1d (field mirrors missing).
- Widget count stuck at 0 despite obvious failures? → step 4 (wrong field-name format in query) or step 5 (no rebuild).
- Widget renders but clicking does nothing? → wrong widget type (`ScalarSqlCountWidget` — see clickability table below), OR backing query has a bad GUID reference.
- Rule field assignments disappear on admin-UI save? → step 1 again — orphan fields get invalidated and dropped at save time.

## Dashboards — only 7 real areas, don't invent

`get_dashboard_areas` returns extra names (`pim-overview`, `pim-channel`, …) that DW will *accept* when you create a dashboard but that do **not** correspond to a navigable admin UI section. Dashboards assigned to those phantom areas never render.

The only 7 dashboard areas that map to actual admin navigation sections are:

**Products, Apps, Commerce, Email, Marketing Insights, Monitoring, Users**

Rules:
- Always create PIM dashboards under `Products` — that's the main PIM dashboard area (it's the landing dashboard shown when the user opens the Products module from the main nav, NOT a per-product tab).
- You cannot create new areas — the set is fixed by the admin UI's main navigation.
- If the MCP `get_dashboard_areas` returns more than the 7 above, ignore the extras. They're historical registrations without UI routes.
- When a dashboard exists in SQL (`Dashboard` table) but doesn't appear in admin, check `DashboardType` first — wrong area = invisible dashboard.

## Clickable widgets — don't pick dead widget types

A PIM governance dashboard lives or dies on the "click the count, land on the offenders" drill-through. Widget choice controls whether that works:

| Widget type | Clickable / drillable? | Use for |
|---|---|---|
| `Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryCountWidget` | **Yes** — clicking the count opens the filtered product list from the backing query | Per-rule / per-blocker counts |
| `Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryGridWidget` | **Yes** — each row links to the product | "Offender list" surface — show the exact SKUs that are failing |
| `Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryListWidget` | **Yes** | Title / hint pairs from a query |
| `Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryFacetWidget` | **Yes** — facet filters are clickable | Catalog-by-category breakdowns |
| `Dynamicweb.Products.UI.Dashboard.Widgets.LastChangedProductsWidget` | **Yes** | Recent edits |
| `Dynamicweb.Insights.UI.Dashboard.Widgets.ScalarSqlCountWidget` | **NO — dead end** | Avoid for governance dashboards. It renders a bare number with NO drill-through. Only use when there's no queryable surrogate (e.g. counting rows in a non-product table). |
| `Dynamicweb.Insights.UI.Dashboard.Widgets.SqlGridWidget` | No | Same — dead end for drill-through |

**Rule of thumb for every governance metric**: there should be a backing product query in `wwwroot/Files/System/SmartSearches/Ecommerce/Shared/*.query`, and the widget should be a `Repository*Widget` that references its GUID. That gives you both the count AND a click path. If you catch yourself reaching for SQL widgets, first ask "could I express this as a product query?" — almost always yes, via `IsEmpty` / `MatchAny` / `Equal` expressions on the indexed fields. The query-location rule (Shared ONLY, never GUID-duplicate to Repositories) and its GUID-collision failure mode live in [`search-indexing.md`](search-indexing.md).

## MCP payload contracts — dashboards + widgets

Call order: `get_dashboard_areas` → `get_dashboards` (check for an existing dashboard) → `create_dashboards` (note the returned `Id`) → `get_available_widgets` (exact `SystemName` — never guess) → `get_widget_parameters` per widget type → `add_widgets_to_dashboards`. The dashboard must exist first; widget payloads need a real persisted dashboard `Id`.

`CreateDashboardModel` (input to `create_dashboards`, as an array) — always pass `userIds`, or the dashboard is invisible in admin (blocker 1 below):

```json
{
  "dashboardType": "Products",
  "path": null,
  "title": "Product Quality Dashboard",
  "userIds": [1]
}
```

`AddWidgetModel` (input to `add_widgets_to_dashboards`, as an array):

```json
{
  "dashboardId": 7,
  "widgetSystemName": "Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryCountWidget",
  "title": "Missing Descriptions",
  "columns": 4,
  "order": null,
  "parameters": {
    "Query": "active_missing_short_description",
    "WidgetType": "Count"
  }
}
```

`RepositoryCountWidget` parameters:

| Parameter | Values | Notes |
|-----------|--------|-------|
| `Query` | query system name | must match an existing saved query |
| `WidgetType` | `Count`, `Sum`, `Avg` | `Sum` and `Avg` also require `RepositoryField` |
| `RepositoryField` | field system name | only needed for `Sum` and `Avg` |

## Building dashboards + widgets via MCP — three blockers that look like "nothing rendered"

A dashboard built with `create_dashboards` + `add_widgets_to_dashboards` can be fully correct in the `Dashboard` / `DashboardWidget` tables (and returned by `get_dashboards`) yet show **nothing useful** in admin. Three independent causes, each with a clean fix:

1. **A dashboard created without `userIds` is invisible.** `create_dashboards` leaves `DashboardUserId` NULL and creates **no `DashboardAccessUserRelation` row**, so the admin Settings → Dashboards list shows "No results" and the area renders the **built-in default** dashboard, not yours. Fix: pass `userIds` on create, **or** insert the access relation for the target admin user with one row flagged default (`DashboardAccessUserRelation(DashboardRelationDashboardId, DashboardRelationUserId, DashboardRelationDefault)` — set `Default=1` on the one that should be the landing view). This table is read per-request (no cache — see [`cache-invalidation.md`](cache-invalidation.md)), so the change is live on the next dashboard-tree fetch; no restart. Multiple dashboards of the same area are valid — they become switchable under the area's *Dashboard* node once each has an access relation.

2. **`RepositoryGridWidget` / `RepositoryListWidget` render blank rows until you set the column Sources.** `RepositoryGridWidget` takes `Column1..Column5` (+ `Width1..Width5`); `RepositoryListWidget` takes `TitleField` / `HintField` / `RightField`. With none set, the grid draws the right number of rows but every **cell is empty** — the "blank lines" symptom. The `Source` value is the **index field system name, and the product index uses SHORT names** — `Name`, `Number`, `DefaultPrice`, `VariantID`, `LanguageID`, `ShopIDs` — NOT `ProductName` / `ProductNumber` (those silently resolve to nothing, same as any unknown field). Discover an unknown field name empirically: an `Equal` filter on the wrong name returns the whole base set (filter dropped), the right name filters — e.g. `Number Equal "<sku>"` returns one product, `ProductNumber Equal "<sku>"` returns everything.

3. **Widget colour is a named-token enum, not hex or Bootstrap names.** `ColorParameterEditor` (base accent) and `Threshold*Color` are type `WidgetColor`; an unrecognised value is silently coerced to `None`. Valid tokens: **`White`, `Red`, `Yellow`, `Orange`, `Purple`, `Pink`, `LightGreen`, `DarkGreen`, `LightBlue`, `DarkBlue`** (and `None`). Hex (`#2E7D32`), Bootstrap names (`Success`/`Danger`/`Primary`), and bare `Green`/`Blue`/`Gray` all coerce to `None`. The colour renders as the card **background**: light tokens give a subtle pastel with dark text; `Orange`/`Red` give a stronger fill with white text — so use the `Light*` tokens for healthy/neutral KPIs and reserve `Red`/`Orange` for the gap counts where loudness is the point.

**Ordering note:** `add_widgets_to_dashboards` re-normalises the `order` field by appending after the widgets already on the dashboard — your `order` values are not honoured against pre-existing widgets. To land a drill-down grid **below** the KPI counts, add the counts first and the grid last (or remove + re-add the grid after the counts so it appends to the end).

## Recovery recipe: Seed `reference_category` parent row

When the symptom is "completeness rule defined and assigned but no panel renders on the product", the cause is almost always the missing `reference_category` parent row in `EcomProductCategory` (`CategoryType=2`).

> Run in PowerShell, not Bash — Bash interpolation eats `$env:` and `$_` before they reach the script.

```powershell
# Seed reference_category parent + translation, idempotent (WHERE NOT EXISTS guards).
# $db is the database name discovered from project files (GlobalSettings.Database.config).
$seedSql = @"
IF NOT EXISTS (SELECT 1 FROM EcomProductCategory WHERE CategoryId = 'reference_category' AND CategoryType = 2)
  INSERT INTO EcomProductCategory (CategoryId, CategoryProductProperties, CategoryType)
  VALUES ('reference_category', 0, 2);

IF NOT EXISTS (SELECT 1 FROM EcomProductCategoryTranslation
               WHERE CategoryTranslationCategoryId = 'reference_category'
                 AND CategoryTranslationLanguageId = 'LANG1')
  INSERT INTO EcomProductCategoryTranslation
    (CategoryTranslationCategoryId, CategoryTranslationLanguageId, CategoryTranslationCategoryName)
  VALUES ('reference_category', 'LANG1', 'Reference category');
"@

$tmp = New-TemporaryFile
$seedSql | Set-Content -Path $tmp.FullName -Encoding UTF8
sqlcmd -S "localhost\SQLEXPRESS" -E -d $db -i $tmp.FullName
Remove-Item $tmp.FullName
```

After seeding, you also need to mirror every concrete-category field row into `reference_category` (with `FieldCategoryId='reference_category'`) plus their translations — see "Completeness rules" above for the 4-rows-per-field pattern. Then rebuild the Products index ([`search-indexing.md`](search-indexing.md)) so completeness widgets pick up the new parent.

If you mutated rules via raw SQL rather than MCP, also restart the host — `CompletionRuleService` and `ProductCategoryService` ServiceCache rows don't reload on raw SQL. See [`cache-invalidation.md`](cache-invalidation.md) for the post-mutation cache table.
