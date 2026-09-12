# Completeness rules and governance dashboards — internals, traps, recovery

Field-validated DW10 knowledge: the `reference_category` mechanic, the 7-condition "rules don't show" checklist, the real dashboard areas, clickable vs dead-end widget types, MCP payload contracts, and recovery SQL.

## Contents

- [`reference_category` — the load-bearing template category](#reference_category--the-load-bearing-template-category)
- [Nothing scores until a four-gate chain is satisfied](#nothing-scores-until-a-four-gate-chain-is-satisfied)
- [Completeness rules — why they sometimes "don't show"](#completeness-rules--why-they-sometimes-dont-show)
- [Completion rule API traps: probing, the auto rule, and deleting](#completion-rule-api-traps-probing-the-auto-rule-and-deleting)
- [Dashboards — only 7 real areas, don't invent](#dashboards--only-7-real-areas-dont-invent)
- [Clickable widgets — don't pick dead widget types](#clickable-widgets--dont-pick-dead-widget-types)
- [The widget envelope: what each widget honours and discards](#the-widget-envelope-what-each-widget-honours-and-discards)
- [MCP payload contracts — dashboards + widgets](#mcp-payload-contracts--dashboards--widgets)
- [Building dashboards + widgets via MCP — three blockers](#building-dashboards--widgets-via-mcp--three-blockers-that-look-like-nothing-rendered)
- [Recovery recipe: Seed `reference_category` parent row](#recovery-recipe-seed-reference_category-parent-row)

## `reference_category` — the load-bearing template category

Dynamicweb uses a hidden "template" category `reference_category` (`CategoryType=2`) to power every admin UI rule/completeness lookup. You need two one-time rows per DATABASE (steps 1-2) plus four rows per FIELD (steps 3-5; step 5 is two translation rows) to be complete:

1. The parent `EcomProductCategory` row for `reference_category` with `CategoryType=2` (seed ONCE per database)
2. The parent `EcomProductCategoryTranslation` row for `reference_category` (also once per database, per language)
3. One `EcomProductCategoryField` row with `FieldCategoryId='reference_category'` (mirror of the concrete field)
4. One `EcomProductCategoryField` row in the concrete category (e.g. `<CategoryName>Attributes`)
5. Both translations in `EcomProductCategoryFieldTranslation` (one for the mirror, one for the concrete field)

Missing step 1 causes the most-misleading failure in DW: rules validate, assignments persist, API returns correct data, but the product/group completeness panels in admin render empty. See "Recovery recipe: Seed `reference_category` parent row" below for the SQL. The category/field storage internals (`EcomProductCategory`, `EcomProductCategoryField`, `EcomFieldOption`, `EcomProductCategoryFieldValue`, the `ProductCategory|<Cat>|<Field>` system-name format) live in [dw-pim-modelling structural-model.md](../../dw-pim-modelling/references/structural-model.md) §2.8.

## Nothing scores until a four-gate chain is satisfied

On DW 10.28, completeness scores nothing until four gates are all satisfied, **in this order**. Every
gate fails silently, and the symptom at each one is identical: rules created, groups bound, index
rebuilt clean, and `completeness` still reads `0` or `N/A`. Walk them in order rather than re-running the
rebuild.

| # | Gate | What must be true, and how it lies |
|---|---|---|
| 1 | **Feature flag** | Feature Management lists "Completeness feature" **twice** (one row marked deprecated), which looks like two independent toggles. `Dynamicweb.Products.UI.CompletenessFeature` is `[Obsolete]` but **both classes derive the same persistence key**, so toggling either flips both. There is one flag. See "The flag has two scopes" below before touching it. |
| 2 | **Index fields** | `CompletionRule\|<id>` numeric index fields **require the Completeness feature flag ON**, not just `SkipCompletionRules=False`. With the flag off the declared fields never populate, however many full rebuilds run, and completeness is unusable as a query filter term. |
| 3 | **Index builder** | **`ProductIndexBuilder SkipCompletionRules=False`, and ABSENT means True.** With the flags on, nine rules bound and every index rebuilt clean, the nine `CompletionRule\|<id>` fields appeared in the index **SCHEMA** while **zero** of 488 documents carried a value. **Schema presence is not evidence**: assert document values, never the schema. |
| 4 | **Read context** | `completeness` is **not a stored product attribute**. It is computed against whatever completion rules the READ CONTEXT selects, so `ProductById` with no rule context reports `0` for a verifiably 100%-complete product, which reads as "the rebuild did not work". |
| 4b | **Read context, refined** | Opening the product **from a query** supplies that context only if the **query configuration carries `CompletionRules`**. The percentage comes from the query config, not from the group bindings: a query with an empty rule list still shows `N/A`. This is the answer to gate 4 inside the editor. |

**The flag has two scopes, and they pull in opposite directions.** State which path you are on before
deciding:

- **The admin calculation path stays OFF.** The beta calculation path behind the flag is buggy; the
  stable legacy path runs with the flag off and supports rules, group assignments, API evaluation and the
  admin UI panels. A "rules don't show" symptom is never fixed by the flag (it is almost always the
  `reference_category` parent row, step 1 of the next section).
- **The index term requires the flag ON.** `CompletionRule|<id>` fields only populate with the flag on,
  so every dashboard, worklist and query that filters on completeness needs it. A demo built on
  completeness-driven queries cannot run with the flag off.
- Either way, **do not auto-toggle it**. `FeatureManagementToggle` cascades across both the Ecommerce and
  deprecated `Products.UI` variants and does not reliably land in the intended state. Ask the user to set
  it in the admin UI, and read it back.

### Append-time filter semantics

- **`AppendCompletionExpressions` IS the "Exclude products with 100% completeness" checkbox.** There is
  no separate property, and the exclusion should not be spelled out by hand. A query that carries
  completion rules with the helper's default `AppendCompletionExpressions=true` is **already** excluding
  complete products.
- **The append is NOT `< 100`, it is `NOT(rule == 100)`.** A document with **no value at all** for the
  rule therefore **PASSES** it. Hand-writing the obvious-looking shape
  `CompletionRule|<id> >= 0 AND < 100` collapsed a 45-row result to 0.

### Completeness has no per-language dimension

`CompletionLanguages` changes nothing in a query: `ENU+ESU+FRC` returns exactly the same products as
`ENU` alone. The appended expression is built from `CompletionRule|<id>`, one per-product index value,
and the language list never reaches it. A translation-gap worklist cannot be built from completeness;
query the translated fields per language instead.

## Completeness rules — why they sometimes "don't show"

Rules surface in admin UI in three places: on each product (Data Completeness panel), on each catalog group ("Completion rules" tab), and implicitly through governance widgets. For all three to work:

1. **`reference_category` must exist as a full parent + child set.** This is where admin UI resolves every rule field. Required order when seeding from scratch: 1a parent category row (`CategoryType=2`) → 1b parent translation → 1c mirror every concrete-category field row into `reference_category` (with `FieldCategoryId='reference_category'`) → 1d mirror every concrete-category field TRANSLATION row. For the SQL, run the idempotent ["Recovery recipe: Seed `reference_category` parent row"](#recovery-recipe-seed-reference_category-parent-row) below — it covers 1a + 1b with `IF NOT EXISTS` guards and explains the 1c/1d mirrors.
   Missing the 1a parent row is the #1 cause of "rule is defined and assigned but no panel renders on the product." `Settings → Completeness Rules` list still works and the `ProductCompletenessRulesByProductId` API still returns correct data — that's what makes this so misleading.
2. **Rule exists** — row in `EcomCompletionRules` with field system names pipe-separated in `EcomCompletionRuleProductFields`. Use the full format `ProductCategory|<CategoryId>|<FieldId>`, not the bare field id. Verify via `get_completion_rules` or direct SQL.
3. **Rule assigned to a catalog group** — comma-separated rule IDs in `EcomGroups.GroupCompletionRules` **plus** matching languages in `GroupCompletionLanguageIds`. Assignments to data-model groups (GroupType=2) do nothing; they must be on the catalog groups (GroupType=0) that products actually live in.
4. **Query field names match the index format** — product queries filtering by a category field must use the **full** system name `ProductCategory|<CategoryId>|<FieldId>`. The bare field id silently matches nothing in Lucene even though SQL sees values. The `FieldExpression Field="..."` attribute in the .query XML is where this lives.
5. **Index flushed *and* rebuilt after any of the above changed** — `POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full"}`. Without a rebuild, dashboard counts stay stale and queries return 0. **And if you populated the completeness FIELD VALUES on products via MCP `patch_products_safe` (or SQL), you MUST flush `ProductService` + `ProductCategoryFieldValueService` + `ProductCategoryService` via `CacheInformationRefresh` BEFORE the rebuild** — the builder reads those values through the cache and will otherwise index the empty pre-patch state, so the governance widget shows 0 failing even when products genuinely fail. This is the read-through-cache ordering trap: flush the services first, then rebuild, and treat a "0 failing" widget after a bulk patch as this ordering bug, not an index quirk.
6. **Host restart after rule changes via raw SQL** — `CompletionRuleService` and `ProductCategoryService` cache in `ServiceCache`. MCP `create_or_update_completeness_rules` / `assign_completion_rules_to_groups` invalidate their slice. Direct SQL INSERT does NOT. Restart the host, or save any rule once from admin UI to force a cache reload.
7. **`Completeness feature` flag** (under Settings → Feature management) is scoped by which path you are on, and it is **never** the fix for "rules don't show" (that is almost always the `reference_category` parent row in step 1). For the **admin calculation path** keep it OFF: the stable legacy path runs with the flag off and supports rules, group assignments, API evaluation and the admin UI panels, while the flag activates a buggy beta calculation path. For **completeness as an index query term** it must be ON, because `CompletionRule|<id>` index fields populate only with the flag on. Both scopes and the rest of the chain are in ["Nothing scores until a four-gate chain is satisfied"](#nothing-scores-until-a-four-gate-chain-is-satisfied). Do not auto-call `FeatureManagementToggle` either way: it cascades across both the Ecommerce and deprecated Products.UI variants and does not reliably land in the intended state. Ask the user to set it in the admin UI and read it back.

Quick diagnosis when rules "don't show":
- No Data Completeness panel on a product but Settings → Completeness Rules shows correct usage counts? → step 1 (parent `EcomProductCategory` row missing).
- Rules page shows the rule with empty "fields" column? → step 1c/1d (field mirrors missing).
- Widget count stuck at 0 despite obvious failures? → step 4 (wrong field-name format in query) or step 5 (no rebuild).
- Widget renders but clicking does nothing? → wrong widget type (`ScalarSqlCountWidget` — see clickability table below), OR backing query has a bad GUID reference.
- Rule field assignments disappear on admin-UI save? → step 1 again — orphan fields get invalidated and dropped at save time.

## Completion rule API traps: probing, the auto rule, and deleting

**A missing required parameter on `ProductCompletenessRulesByProductId` answers 500, not 400.** The
binder leaves `languageId` an empty string and the handler dereferences it, so the `ArgumentException`
escapes as an unhandled 500 instead of reaching the model-validation layer that produces the normal 400.
A 500 right after a feature-flag flip reads as "the host is broken" and sends the reader at the
infrastructure, when the verb works and a parameter was simply omitted:

```
GET /Admin/Api/ProductCompletenessRulesByProductId?ProductId=<id>
  -> 500 {"title":"The value cannot be an empty string. (Parameter 'languageId')","status":500}
Same 500 for &LanguageId=ENU, &languageId=ENU, &ProductLanguage=ENU, &LangId=ENU.
Only &ProductLanguageId=ENU works -> 200.
```

Parameter spelling is not shared across the family: `ProductById` binds `Id`,
`ProductCompletenessRulesByProductId` binds `ProductId` + `ProductLanguageId`, and neither accepts the
other's spelling. **Triage any verb probe by its failure mode:**

| Response | Meaning |
|---|---|
| `"Unknown query: 'X'"` | The verb does not exist |
| `"Unable to load query parameters for query type"` | The verb EXISTS, the parameter names are wrong |
| HTTP 500 `ArgumentException` naming a parameter | The verb exists and that named parameter bound empty: supply it |

Re-probe with the named parameter before reporting a host problem. (The dispatcher strips a trailing
`Query`/`Command` from the class name but NOT a leading `Get`, so `GetLanguagesQuery` is the verb
`GetLanguages`.)

**`CompletenessOnAllCategoryFields` injects a phantom rule id `0` and creates no rule row.** Enabling
"Completeness on all Datamodel attributes" on a data-model group makes the group's `completionRules` read
back as `[0, 1025]` instead of `[1025]`. The auto rule is **virtual**: the read model prepends a synthetic
id `0` representing "every attribute on the datamodel category", and nothing is written to
`EcomCompletionRules` (`CompletionRuleAll` totalCount unchanged before and after, no id `0` row) while the
`EcomGroups.GroupCompletionRules` column still holds the literal `1025`. The API read model and the
persisted column disagree.

- **Never round-trip that read model back through `DataModelGroupSave`** without stripping the `0`: the
  save would persist a rule id that matches no row and no `CompletionRule|<id>` index field.
- Set the bit by a whole-model `DataModelGroupSave` (a 30-property round-trip changing that one property
  leaves the other 28 byte-identical), then verify by SQL on `GroupCompletenessOnAllCategoryFields`, not
  by the echoed `completionRules`.
- `ProductCatalogGroupSave` is the WRONG verb here: its model has no `completenessOnAllCategoryFields` at
  all, so the save silently drops the setting.

**`CompletionRuleDelete` leaves dangling rule ids behind, and the detach verb cannot reach language-only
group rows.** `CompletionRuleDelete` never nulls `EcomGroups.GroupCompletionRules`, so deleting a rule
always leaves dangling ids; normally the detach verb hides that. But a catalogue group with **no row in
the default language** (only DAN/DEU/FRA/NLD rows, say) is invisible to every group-scoped verb, because
they all resolve a group through its default-language row:

```
POST /Admin/Api/CompletionRuleRemoveFromGroup {"GroupId":"<G>","Id":<ruleId>}
  -> 404 {"status":"notFound","message":"The group with the id <G> does not exist"}
     ... while SELECT GroupId, GroupLanguageId FROM EcomGroups WHERE GroupId='<G>' returns four rows
```

**Detach bindings BEFORE deleting a rule, and verify the detach against SQL rather than trusting the
verb.** After any completeness-rule deletion this must return 0:

```sql
SELECT COUNT(*) FROM EcomGroups
 WHERE ISNULL(GroupCompletionRules,'') <> ''
   AND GroupCompletionRules NOT IN (SELECT CAST(EcomCompletionRuleId AS varchar) FROM EcomCompletionRules);
```

For language-only orphan group rows the API offers no reachable channel, so the remaining dangling ids
are cleared through the sanctioned scheduled-task SQL runner
(`UPDATE EcomGroups SET GroupCompletionRules='' WHERE GroupCompletionRules='<deletedRuleId>'`), then a
host restart or a rule save from admin to reload `CompletionRuleService`.

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

**Rule of thumb for every governance metric**: there should be a backing product query in `wwwroot/Files/System/SmartSearches/Ecommerce/Shared/*.query`, and the widget should be a `Repository*Widget` that references its GUID. That gives you both the count AND a click path. If you catch yourself reaching for SQL widgets, first ask "could I express this as a product query?" — almost always yes, via `MatchAny` / `Equal` expressions on the indexed fields. Assert the row count of
any `IsEmpty` arm before shipping it — on the Lucene provider on 10.28.x that operator can parse and
match nothing (see [dw-search-indexing](../../dw-search-indexing/references/query-expressions.md#operators-what-the-enum-implies-vs-what-matches)),
so a "missing description" tile can read zero because the operator is inert rather than because the
data is complete. Save shared queries in the Shared folder ONLY — never GUID-duplicate a .query file into the Repositories folder; duplicate GUIDs collide and break query resolution (see [dw-search-indexing](../../dw-search-indexing/SKILL.md)).

## The widget envelope: what each widget honours and discards

Most per-widget properties on the DW 10.28 stock set are accepted and discarded, so a dashboard reads as
correctly configured while rendering something else. Build count tiles from `RepositoryCountWidget` over
a **narrowed query** and accept the rest of this envelope as it is:

| Surface | Verdict | Detail |
|---|---|---|
| Query counter drill-down | **Works, gated on query file location** | The tile becomes `cursor:pointer` and navigates once the backing `.query` files live under `Files/System/SmartSearches/Ecommerce/Shared/`. A reflection pass over `DashboardOverviewScreen` / `NumberComponent` reports the tile body as `cursor:auto` and the card markup as Edit + Delete only, which is a **false negative**: the selector is filesystem-gated, not absent. Test the rendered board, not the assembly. |
| `RepositoryCountWidget` count | **Honours the query PREDICATE, ignores the query CONFIG** | The widget counts index **documents** (product × variant × language layer) while `ProductsByIndexQuery` returns distinct default-language masters, so an un-narrowed tile drifts from 1% on single-language part queries to 3x-6.5x on channel or workflow queries. Narrow the query itself on `LanguageID` + `VariantID` and tile equals list. Query *configuration* (`AppendCompletionExpressions`, Parameters) is not applied: put every constraint in the predicate. |
| `ProductCountWidget` `Shop` parameter | **Inert** | `ShopParameterEditor` round-trips into the widget XML and the counter never applies it: `Shop=""` and three distinct shop ids all returned the same 12072, and the unit stays the hardcoded string "Products". A per-channel product count is **not** achievable with the stock counter; use `RepositoryCountWidget` over a shop-narrowed query. |
| `DashboardConfigurationSave.AvailableForAdmin` | **Write-only** | Echoes back `true`, the next read says `false`. There is nowhere to store it: the `Dashboard` table is `{DashboardID, DashboardType, DashboardPath, DashboardUserId, DashboardTitle}` plus `DashboardAccessUserRelation`. Grant a dashboard through the access relation instead (blocker 1 below). |
| `DashboardWidgetSave.IconId` | **Per widget TYPE, not per instance** | `IconId` is a property on `DashboardWidgetDataModel` so the save accepts it, and the read model returns the **type default** for every instance. Nine query counters given nine distinct icons all render `uil-calculator`, a wall of identical icons. Do not design a board that relies on per-tile icons. |
| Threshold conditions | **Literal operators only** | `ThresholdCountWidget` stores the conditions as the operator strings themselves (`GreaterThanThresholdCondition = ">"`). Use `>` `>=` `<` `<=` `==`. Word forms such as `"GreaterThan"` save cleanly, are unrecognised, are skipped rather than rejected, and the tile never changes colour. |
| Widget read verbs | **Two verbs, one of them a palette** | Placed widgets live under `DashboardWidgetsByTypeAndPath` → `model.data`, with `parameters` as a **raw XML string**. `DashboardWidgets?DashboardType=…&Path=…` is the **ADD palette**: it answers `model.dashboard.widgets=[]` plus six objects with ids `-1..-6` carrying no `widgetSystemName`, so they cannot be passed to `DashboardWidgetAdd`. |

The one-sentence build rule: the stock widget set cannot express per-channel counts, per-instance icons,
sums or averages; build count tiles from `RepositoryCountWidget` over a query narrowed on `LanguageID` +
`VariantID` (plus `ShopIDs` for a channel), colour them from the real `WidgetColor` member names, and use
literal operators for thresholds.

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
| `WidgetType` | `Count` | `Sum` and `Avg` are accepted and ignored, see below |
| `RepositoryField` | field system name | accepted and ignored |

**No stock widget on this platform shows a sum or an average, so an inventory-value tile cannot be built
honestly.** Two independent measurements:

- **`RepositoryCountWidget` accepts `WidgetType=Sum`/`Avg` and renders a COUNT.** `get_widget_parameters`
  lists `WidgetType` and `RepositoryField`, `add_widgets_to_dashboards` accepts them, and the tile then
  renders the query row count with no error and no warning. Five probe tiles over a 452-row query
  (`Sum`/Stock, `SUM`/Stock, `Sum`/stock, `Average`/Price, `Avg`/Price) all rendered **452** against a
  truth of `Sum(Stock)=105278` and `Avg(Price)=223.03`; both fields are valid index fields, so the field
  names were not the problem. `get_dashboard_widgets` does not return instance parameters, so the
  configuration still looks correct on read-back.
- **`ScalarSqlCountWidget` renders only a COUNT.** Despite its free-text `SqlQuery` parameter, anything
  other than a count evaluates to **`null`**: `SELECT COUNT(*) …` renders the right number, while
  `SELECT 1`, `SELECT SUM(1) FROM EcomProducts`, `SELECT CAST(SUM(ProductStock) AS INT)` and
  `SELECT ISNULL(CAST(SUM(ProductStock) AS INT),-1)` all render `null`. It is not a type problem, a NULL
  problem, or a bad column name.

Consequences for a dashboard design:

- Treat `RepositoryCountWidget` as a **counter only**, and use `ScalarSqlCountWidget` for counts a
  product query cannot express (accepting that it has no drill-through, see the clickability table above).
- A `Sum(Price)` figure would be the sum of unit list prices, one of each, which scales with row count
  and reads as a count. **Never title such a tile "catalogue value" or "inventory value".** True
  inventory value is `SUM(Price × Stock)`, a product of two fields that no widget can express:
  `RepositoryCountWidget` applies one scalar op to ONE index field, there is no precomputed value field
  in the product index, and `ScalarSqlCountWidget` returns null for the SQL that would compute it.
- If a money figure is required, either title the tile for what it actually measures or leave the claim
  out. **Render the board and read the tile number back**, asserting it against an independent read of
  the same figure, never against the widget config; a tile showing `null` must never ship.

## Building dashboards + widgets via MCP — three blockers that look like "nothing rendered"

A dashboard built with `create_dashboards` + `add_widgets_to_dashboards` can be fully correct in the `Dashboard` / `DashboardWidget` tables (and returned by `get_dashboards`) yet show **nothing useful** in admin. Three independent causes, each with a clean fix:

1. **A dashboard created without `userIds` is invisible.** `create_dashboards` leaves `DashboardUserId` NULL and creates **no `DashboardAccessUserRelation` row**, so the admin Settings → Dashboards list shows "No results" and the area renders the **built-in default** dashboard, not yours. Fix: pass `userIds` on create, **or** insert the access relation for the target admin user with one row flagged default (`DashboardAccessUserRelation(DashboardRelationDashboardId, DashboardRelationUserId, DashboardRelationDefault)` — set `Default=1` on the one that should be the landing view). This table is read per-request (no cache), so the change is live on the next dashboard-tree fetch; no restart. Multiple dashboards of the same area are valid — they become switchable under the area's *Dashboard* node once each has an access relation.

2. **`RepositoryGridWidget` / `RepositoryListWidget` render blank rows until you set the column Sources.** `RepositoryGridWidget` takes `Column1..Column5` (+ `Width1..Width5`); `RepositoryListWidget` takes `TitleField` / `HintField` / `RightField`. With none set, the grid draws the right number of rows but every **cell is empty** — the "blank lines" symptom. The `Source` value is the **index field system name, and the product index uses SHORT names** — `Name`, `Number`, `DefaultPrice`, `VariantID`, `LanguageID`, `ShopIDs` — NOT `ProductName` / `ProductNumber` (those silently resolve to nothing, same as any unknown field). Discover an unknown field name empirically: an `Equal` filter on the wrong name returns the whole base set (filter dropped), the right name filters — e.g. `Number Equal "<sku>"` returns one product, `ProductNumber Equal "<sku>"` returns everything.

3. **Widget colour is a named-token enum, not hex or Bootstrap names.** `ColorParameterEditor` (base accent) and `Threshold*Color` are type `WidgetColor`; an unrecognised value is silently coerced to `None`. The full `Dynamicweb.Dashboard.Widgets.WidgetColor` enum is **`None`, `White`, `Red`, `Orange`, `Yellow`, `DarkGreen`, `LightGreen`, `DarkBlue`, `LightBlue`, `Purple`, `Pink`, `Grey`** (British spelling). Hex (`#2E7D32`), Bootstrap names (`Success`/`Danger`/`Primary`), and the bare `Green`/`Blue`/`Gray` forms are not members and coerce to `None`. The colour renders as the card **background**: light tokens give a subtle pastel with dark text; `Orange`/`Red` give a stronger fill with white text, so use the `Light*` tokens for healthy/neutral KPIs and reserve `Red`/`Orange` for the gap counts where loudness is the point.

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

After seeding, you also need to mirror every concrete-category field row into `reference_category` (with `FieldCategoryId='reference_category'`) plus their translations — see "Completeness rules" above for the 4-rows-per-field pattern. Then rebuild the Products index (`POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full"}` — see [dw-search-indexing](../../dw-search-indexing/SKILL.md)) so completeness widgets pick up the new parent.

If you mutated rules via raw SQL rather than MCP, also restart the host — `CompletionRuleService` and `ProductCategoryService` ServiceCache rows don't reload on raw SQL.
