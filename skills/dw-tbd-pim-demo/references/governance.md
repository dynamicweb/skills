# governance.md

> PIM governance gotchas + recovery recipes. Loaded from `~/.claude/skills/dynamicweb-pim-demo/SKILL.md` "Where to find things" table. Mirrors the shape of `dynamicweb-demo-base/references/integrity-sweep.md` — sequential sections, fenced PowerShell recipes inline next to their cause-explanation. The recovery recipes (seed `reference_category`, rebuild Products index) live in this file rather than as standalone `.ps1` files under `scripts/` — recipes always run inside Claude with port + DB in conversation state from base's discover-from-project-files rule.

## Dashboards — only 7 real areas, don't invent

`get_dashboard_areas` returns extra names (`pim-overview`, `pim-channel`, …) that DW will *accept* when you create a dashboard but that do **not** correspond to a navigable admin UI section. Dashboards assigned to those phantom areas never render.

The only 7 dashboard areas that map to actual admin navigation sections are:

**Products, Apps, Commerce, Email, Marketing Insights, Monitoring, Users**

Rules:
- Always create PIM dashboards under `Products` — that's the main PIM dashboard area (it's the landing dashboard shown when the user opens the Products module from the main nav, NOT a per-product tab).
- You cannot create new areas — the set is fixed by the admin UI's main navigation.
- If the MCP `get_dashboard_areas` returns more than the 7 above, ignore the extras. They're historical registrations without UI routes.
- When a dashboard exists in SQL (`Dashboard` table) but doesn't appear in admin, check `DashboardType` first — wrong area = invisible dashboard.

## Clickable widgets are the demo — don't pick dead widget types

A PIM governance demo lives or dies on the "click the red number, land on the offenders" drill-through moment. Widget choice controls whether that works:

| Widget type | Clickable / drillable? | Use for |
|---|---|---|
| `Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryCountWidget` | **Yes** — clicking the count opens the filtered product list from the backing query | Per-rule / per-blocker counts |
| `Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryGridWidget` | **Yes** — each row links to the product | "Offender list" surface — show the exact SKUs that are failing |
| `Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryListWidget` | **Yes** | Title / hint pairs from a query |
| `Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryFacetWidget` | **Yes** — facet filters are clickable | Catalog-by-category breakdowns |
| `Dynamicweb.Products.UI.Dashboard.Widgets.LastChangedProductsWidget` | **Yes** | Recent edits |
| `Dynamicweb.Insights.UI.Dashboard.Widgets.ScalarSqlCountWidget` | **NO — dead end** | Avoid for governance demos. It renders a bare number with NO drill-through. Only use when there's no queryable surrogate (e.g. counting rows in a non-product table). |
| `Dynamicweb.Insights.UI.Dashboard.Widgets.SqlGridWidget` | No | Same — dead end for drill-through |

**Rule of thumb for every governance metric**: there should be a backing product query in `wwwroot/Files/System/SmartSearches/Ecommerce/Shared/*.query`, and the widget should be a `Repository*Widget` that references its GUID. That gives you both the count AND a click path. If you catch yourself reaching for SQL widgets, first ask "could I express this as a product query?" — almost always yes, via `IsEmpty` / `MatchAny` / `Equal` expressions on the indexed fields.

## Dashboard query location — Shared ONLY, never duplicate to Repositories

For dashboard widget queries, put each `.query` + `.configuration` file in **exactly one** place:

**`/Files/System/SmartSearches/Ecommerce/Shared/`** (or a subfolder of it).

Do **NOT** also place a GUID-identical copy under `/Files/System/Repositories/Products/<subfolder>/`. Feed queries at `/Files/System/Repositories/Products/` root (e.g. `Tributech.query`, `BC.query`, `GPL.query`) are a separate category — they're resolved by repository+filename for `EcomFeed.FeedIndexQueryId` and must stay at the repo root.

**Why it matters** (DW10 bug I hit on 2026-04-23, demo day minus 1):

`QueryHelper.InitQueriesCache` (in `Dynamicweb.Core`) populates the cache from `SmartSearches` first, then `Repositories`, and **overwrites on GUID collision**:
```csharp
result = InitQueriesCache(SystemInformation.MapPath(SMARTSEARCH_QUERY_VIRTUAL_PATH), cache);  // 1st
// ...
result = InitQueriesCache(repositoriesPath, cache) && result;                                  // 2nd — overwrites
// Inside: cache[query.ID] = query;  ← Repositories copy wins
```

So if the same query GUID exists in both locations, `QueryHelper.GetQueryById(guid)` returns the **Repositories** copy. When the admin Products tree renders the Shared queries node, each query's delete action calls `QueryByIdQuery.GetModel()` → gets back the Repositories copy → its `FolderPath` is `/Files/System/Repositories/Products/<subfolder>` → `ProductListNodePathProvider.GetQueryFolderPath()` throws `NotSupportedException` (it only accepts paths starting with `SharedQueriesPath` or `MyQueriesPath`) → the entire Shared queries tree 500s with a `NavigationByPathQuery` error. Same code path also breaks widget drill-through, since clicking a widget routes through `GetQueryFolderPath`.

**Diagnosis tell**: if admin Products → Queries → Shared queries returns a 500 with `System.NotSupportedException` at `ProductListNodePathProvider.GetQueryFolderPath`, grep for duplicate GUIDs across the two folders — that's almost always it:
```bash
grep -h 'Query ID=' wwwroot/Files/System/Repositories/Products/**/*.query | sort > /tmp/repo.txt
grep -h 'Query ID=' wwwroot/Files/System/SmartSearches/Ecommerce/Shared/**/*.query | sort > /tmp/shared.txt
diff /tmp/repo.txt /tmp/shared.txt  # identical lines = duplicates
```

**Fix**: delete the Repositories-side dashboard duplicates (NOT feed queries at repo root). Then **restart the host** — the `Searching:Queries` cache in `Cache.Current` is NOT exposed via `CacheInformationRefresh`, and `InitQueriesCache` never removes entries, only adds/overwrites. Deleting files from disk alone leaves stale entries in memory until restart. No MCP tool flushes this — plan the restart cost into your fix window. See [cache-invalidation.md](cache-invalidation.md) for the post-mutation cache table.

**Does widget drill-through need the query in `Repositories`?** No. Widgets look up queries by GUID through the global cache, which is populated from SmartSearches. Drill-through navigation uses `ProductListNodePathProvider.GetPath` which requires the query's `FolderPath` to start with `SharedQueriesPath` — so Shared is actually the REQUIRED location for drill-through to work at all. Repositories is wrong on both fronts.

## Completeness rules — why they sometimes "don't show"

Rules surface in admin UI in three places: on each product (Data Completeness panel), on each catalog group ("Completion rules" tab), and implicitly through governance widgets. For all three to work:

1. **`reference_category` must exist as a full parent + child set.** This is where admin UI resolves every rule field. Required order when seeding from scratch: 1a parent category row (`CategoryType=2`) → 1b parent translation → 1c mirror every concrete-category field row into `reference_category` (with `FieldCategoryId='reference_category'`) → 1d mirror every concrete-category field TRANSLATION row. For the SQL, run the idempotent ["Recovery recipe: Seed `reference_category` parent row"](#recovery-recipe-seed-reference_category-parent-row) below — it covers 1a + 1b with `IF NOT EXISTS` guards and explains the 1c/1d mirrors.
   Missing the 1a parent row is the #1 cause of "rule is defined and assigned but no panel renders on the product." `Settings → Completeness Rules` list still works and the `ProductCompletenessRulesByProductId` API still returns correct data — that's what makes this so misleading.
2. **Rule exists** — row in `EcomCompletionRules` with field system names pipe-separated in `EcomCompletionRuleProductFields`. Use the full format `ProductCategory|<CategoryId>|<FieldId>`, not the bare field id. Verify via `get_completion_rules` or direct SQL.
3. **Rule assigned to a catalog group** — comma-separated rule IDs in `EcomGroups.GroupCompletionRules` **plus** matching languages in `GroupCompletionLanguageIds`. Assignments to data-model groups (GroupType=2) do nothing; they must be on the catalog groups (GroupType=0) that products actually live in.
4. **Query field names match the index format** — product queries filtering by a category field must use the **full** system name `ProductCategory|<CategoryId>|<FieldId>`. The bare field id silently matches nothing in Lucene even though SQL sees values. The `FieldExpression Field="..."` attribute in the .query XML is where this lives.
5. **Index rebuilt after any of the above changed** — `POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full"}`. Without a rebuild, dashboard counts stay stale and queries return 0.
6. **Host restart after rule changes via raw SQL** — `CompletionRuleService` and `ProductCategoryService` cache in `ServiceCache`. MCP `create_or_update_completeness_rules` / `assign_completion_rules_to_groups` invalidate their slice. Direct SQL INSERT does NOT. Restart the host, or save any rule once from admin UI to force a cache reload.
7. **`Completeness feature` flag** (under Settings → Feature management) **must stay OFF — never toggle it from Claude**. It activates a buggy beta calculation path. The stable legacy path runs when the flag is OFF and supports everything needed: rules, group assignments, API evaluation, admin UI panels. If the flag appears ON during a session, ask the user to disable it via admin UI — do NOT auto-call `FeatureManagementToggle`, which cascades across both the Ecommerce and deprecated Products.UI variants and does not reliably land in OFF state. The correct fix for a "rules don't show" symptom is elsewhere in this list (almost always the `reference_category` parent row in step 1), never the flag.

Quick diagnosis when rules "don't show":
- No Data Completeness panel on a product but Settings → Completeness Rules shows correct usage counts? → step 1 (parent `EcomProductCategory` row missing).
- Rules page shows the rule with empty "fields" column? → step 1c/1d (field mirrors missing).
- Widget count stuck at 0 despite obvious failures? → step 4 (wrong field-name format in query) or step 5 (no rebuild).
- Widget renders but clicking does nothing? → wrong widget type (`ScalarSqlCountWidget` — see clickability table above), OR backing query has a bad GUID reference.
- Rule field assignments disappear on admin-UI save? → step 1 again — orphan fields get invalidated and dropped at save time.

## Recovery recipe: Seed `reference_category` parent row

When the symptom is "completeness rule defined and assigned but no panel renders on the product", the cause is almost always the missing `reference_category` parent row in `EcomProductCategory` (`CategoryType=2`). Run this PowerShell inside Claude Code; port + DB are in conversation state from base's discover-from-project-files rule.

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

After seeding, you also need to mirror every concrete-category field row into `reference_category` (with `FieldCategoryId='reference_category'`) plus their translations — see §Completeness rules above for the 4-rows-per-field pattern. Then rebuild the Products index (next recipe) so completeness widgets pick up the new parent.

If you mutated rules via raw SQL rather than MCP, also restart the host — `CompletionRuleService` and `ProductCategoryService` ServiceCache rows don't reload on raw SQL. See [cache-invalidation.md](cache-invalidation.md) for the post-mutation cache table.

## Recovery recipe: Rebuild Products index

After any mutation that touches products, groups, categories, fields, completeness rules, or queries, the Lucene index must be rebuilt — otherwise dashboard widget counts stay stale and product queries return zero rows.

> Run in PowerShell, not Bash — Bash interpolation eats `$env:` and `$_` before they reach the script.

```powershell
# $port and $token come from project-file discovery (launchSettings.json + chat).
$buildResp = Invoke-RestMethod `
  -Uri "https://localhost:$port/admin/api/BuildIndex" `
  -Method POST `
  -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
  -Body (@{ Repository = "Products"; IndexName = "Products.index"; BuildName = "Full" } | ConvertTo-Json) `
  -SkipCertificateCheck

# Poll IndexStatus until Idle (15-min timeout)
$deadline = (Get-Date).AddMinutes(15)
do {
  Start-Sleep -Seconds 5
  $status = Invoke-RestMethod `
    -Uri "https://localhost:$port/admin/api/IndexStatus" `
    -Headers @{ Authorization = "Bearer $token" } `
    -SkipCertificateCheck
  Write-Host ("IndexStatus: " + $status.Status)
} while ($status.Status -ne 'Idle' -and (Get-Date) -lt $deadline)

if ($status.Status -ne 'Idle') { Write-Warning "BuildIndex did not reach Idle within 15 minutes" }
else { Write-Host "BuildIndex Full complete." -ForegroundColor Green }
```

If the build fails or never reaches Idle, check that the index file exists at `wwwroot/Files/System/Repositories/Products/Products.index` and that the Repository name matches the index file's containing folder. See [cache-invalidation.md](cache-invalidation.md) for related cache rules.

## Preflight: audit standard ProductField inventory before creating customs

DW10 ships ~50 standard `ProductField` system names, hardcoded in `dw10source/src/Features/Ecommerce/Dynamicweb.Ecommerce/Products/ProductField.cs` `FieldSystemName` class. These map to actual columns on `EcomProducts` and are wired through the entire stack (ProductListScreen, completion rules, indexes, feeds, BC connector). Creating a custom field that duplicates a standard creates two distinct failure modes:

1. **Exact-name duplicate.** A custom `EcomProductField` row with `ProductFieldSystemName` matching a standard (e.g. `ProductWeight`, `ProductHeight`, `ProductWidth`, `ProductDepth`, `ProductVolume`, `ProductEAN`) causes two definitions of the same field. Edit screens and field-picker UIs may render twice; some lookups pick the first by autoid (unpredictable across solutions). Always pure duplication, never useful.
2. **Alias duplicate.** A custom field with a *different* SystemName but storing the same semantic value (e.g. `g_ean` next to standard `ProductEAN`; `g_weight_kg` next to `ProductWeight`; `g_height_cm` next to `ProductHeight`). Splits data across two columns. Completion rules, feeds, and integrations have to pick one — usually pick the custom (since that's why it was added) — and the standard column appears empty. BC connector and most off-the-shelf integrations key off the standard, so the data silently never reaches them.

**Preflight rule (do this BEFORE creating any custom field):**

Compare the proposed SystemName against the standard set. The full list is in `ProductField.FieldSystemName` constants — load it once and grep before each `create_product_fields` MCP call or SQL insert. The semantic-overlap set (the ones most often duplicated by alias) covers physical dimensions (Weight, Height, Width, Depth, Volume), identifiers (EAN, Number, ManufacturerID), pricing (Price, Cost, PriceType), stock (Stock, StockGroupID, NeverOutOfStock), content (Name, ShortDescription, LongDescription, MetaTitle/Description/Keywords/Canonical/Url), images (ImageDefault, ImageSmall, ImageMedium, ImageLarge, Images), workflow (WorkflowStateId, Active, Discontinued, ReplacementProductId, DiscontinuedAction), and audit (Created, Updated, Type, DefaultShopID, DefaultUnitID, ExpectedDelivery). If you need one of these, **use the standard**.

Legitimate customs to keep: anything genuinely demo-specific that has no standard equivalent — e.g. ERP-sync hints (`g_bc_reorder`), action-rule routing fields (`g_notify_email` for auto-offline mail recipient), free-text supplier (different from the `ProductManufacturerID` select), lifecycle-state mirrors used by external automation. Use a consistent prefix (`g_` is a common convention) so the legitimate customs are visually distinct from accidental standard-overlap mistakes.

## Recovery recipe: collapse a custom field back into its standard

When a demo's PIM has already accumulated standard-field duplicates (typical after rushed initial modelling), fold each custom back into its standard before continuing. Order matters: backfill data, rewire references, then drop the custom — never delete first.

```sql
-- 1) Backfill the standard column from the custom where the standard is empty.
UPDATE EcomProducts SET ProductEAN    = g_ean        WHERE g_ean        IS NOT NULL AND g_ean        <> '' AND (ProductEAN    IS NULL OR ProductEAN    = '');
UPDATE EcomProducts SET ProductWeight = g_weight_kg  WHERE g_weight_kg  > 0 AND (ProductWeight IS NULL OR ProductWeight = 0);
-- ...repeat per duplicated dimension/identifier...

-- 2) Rewire completion-rule references from custom SystemName to standard.
UPDATE EcomCompletionRules
SET EcomCompletionRuleProductFields =
      REPLACE(REPLACE(EcomCompletionRuleProductFields, 'g_weight_kg', 'ProductWeight'), 'g_ean', 'ProductEAN')
WHERE EcomCompletionRuleProductFields LIKE '%g_ean%'
   OR EcomCompletionRuleProductFields LIKE '%g_weight_kg%';

-- 3) Delete the duplicate EcomProductField rows (BOTH exact-name + alias).
DELETE FROM EcomProductField
 WHERE ProductFieldSystemName IN
   ('ProductWeight','ProductHeight','ProductWidth','ProductDepth','ProductVolume',
    'g_ean','g_weight_kg','g_height_cm','g_width_cm','g_length_cm');

-- 4) Drop the custom columns from EcomProducts. Drop their default constraints first
--    (auto-named, vary per install) so the DROP COLUMN doesn't fail with msg 5074.
DECLARE @def nvarchar(200), @sql nvarchar(500);
DECLARE colcur CURSOR FOR
  SELECT dc.name FROM sys.default_constraints dc
   JOIN sys.columns c ON c.default_object_id = dc.object_id
  WHERE c.object_id = OBJECT_ID('EcomProducts')
    AND c.name IN ('g_ean','g_weight_kg','g_height_cm','g_width_cm','g_length_cm');
OPEN colcur; FETCH NEXT FROM colcur INTO @def;
WHILE @@FETCH_STATUS = 0 BEGIN
  SET @sql = 'ALTER TABLE EcomProducts DROP CONSTRAINT [' + @def + ']';
  EXEC sp_executesql @sql;
  FETCH NEXT FROM colcur INTO @def;
END
CLOSE colcur; DEALLOCATE colcur;

ALTER TABLE EcomProducts DROP COLUMN g_ean;
ALTER TABLE EcomProducts DROP COLUMN g_weight_kg;
-- ...one per dropped column...

-- 5) Clean any UnifiedPermission grants that referenced the now-deleted SystemNames.
DELETE FROM UnifiedPermission
 WHERE PermissionName = 'ProductField'
   AND PermissionKey IN ('g_ean','g_weight_kg','g_height_cm','g_width_cm','g_length_cm');
```

Then flush `ProductFieldService`, `ProductService`, `CompletionRuleService`, `PermissionService` and trigger a Full `BuildIndex` (see ["Recovery recipe: Rebuild Products index"](#recovery-recipe-rebuild-products-index) above).

**Completion-rule regex note**: `EcomCompletionRules` uses a comma-separated SystemName list (`EcomCompletionRuleProductFields`), not regex. Rule "completeness" is a field-has-value check, not a pattern match. `EcomValidationRules` is a separate table for input-validation patterns and is independent — touch that only if a custom field carried a regex pattern (`FieldValidationPattern` on `EcomProductCategoryField`) that needs replicating on the standard.
