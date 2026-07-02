# Foundational candidate → dw-search-indexing

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 product index / repositories / queries knowledge, staged here for a future
> fold-up into `dw-search-indexing`. No demo/customer content. When folded, move this body into
> `dw-search-indexing` and re-target the pointers in the demo skills. Until then, the demo skills
> reference this file.

## Repositories, Indexes, and Queries — file-based

- **Repository** = folder under `wwwroot/Files/System/Repositories/<RepoName>/`
- **Index** = `.index` XML file inside the repo folder (build via management API `POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full"}`)
- **Queries** = `.query` XML files with `<Query ID="guid">` and `<Source Repository="..." Item="..." />`. Query placement rules are SUBTLE:
  - Queries used by **feeds** (`EcomFeed.FeedIndexQueryId`) must live DIRECTLY in the repository root folder: `wwwroot/Files/System/Repositories/<RepoName>/*.query`. **Subfolders are NOT scanned for feed resolution** — admin will show "query does not exist" on the feed if the .query file is in a subfolder.
  - Queries used by **dashboards/widgets** (referenced by GUID) must live in `wwwroot/Files/System/SmartSearches/Ecommerce/Shared/` (or a subfolder of it) — **never GUID-duplicated to `Repositories/<RepoName>/<subfolder>/`**. GUID-collision mechanism + recovery: "Dashboard query location — Shared ONLY" below.
  - Admin "Queries" UI under Products → Queries → Shared queries shows all queries in the SmartSearches/Shared tree. Feed queries are visible in a separate Repository-based surface (Settings → Integration → Repositories → Products).
  - Rule of thumb: **feed-backing queries → `Files/System/Repositories/<RepoName>/` root. Dashboard-backing queries → `Files/System/SmartSearches/Ecommerce/Shared/` only. Never both.**
- Product index builder: `Dynamicweb.Ecommerce.Indexing.ProductIndexBuilder, Dynamicweb.Ecommerce`. Instances use `Dynamicweb.Indexing.Lucene.LuceneIndexProvider`.
- **Hand-author the index — do NOT copy `ProductsBackend/Products.index` or `ProductsFrontend/Products.index` from the github Swift repo.** Those reference Swift's demo custom fields (per-vertical facet fields, dimension facets, etc.) that fail to build against any other product catalogue with `field not found in products` (the index builder validates every field reference against `EcomProductCategoryField`). A Swift content baseline is content-only and ships no Repositories tree — there's nothing to copy from there either. For a hybrid PIM-data + Swift-frontend solution: hand-write the `.index` listing only standard product fields plus 5-10 relevant `ProductCategory|<Cat>|<FieldId>` per category — not the full custom-field set. Use `ProductIndexBuilder.DefaultSettings` in the dw10 source as the structural template.
- **Name-attribute gotcha:** the `<Index Name="..."/>` attribute inside `Products.index` MUST equal the file name **including the `.index` extension** — i.e. `Name="Products.index"`, not `Name="Products"`. The error on mismatch is the misleading `"Index file not found: ...\Products"` even though the file IS at `...\Products.index`; the Lucene resolver uses the `Name` attribute as the lookup key.
- **`ProductIndexSchemaExtender` is load-bearing — a hand-written index without it builds successfully and serves zero hits.** The default DW catalog frontend resolves products via `ProductQueryHelper.GetProductsAutoIdsFromIndexQuery`, which expects a battery of stock fields (`AutoID`, `LanguageID`, `ParentGroupIDs`, `ShopIDs`, `Active`, `freetext`, `ProductName_Search`, `Manufacturer_Facet`, `PriceRange`, etc.). If your `<Fields>` block lists only your custom fields, **every PLP / PDP throws `System.ArgumentOutOfRangeException: numHits must be > 0` from `Lucene.Net.Search.TopScoreDocCollector.Create`** — `BuildIndex` returns `state=success` and the Lucene segment files on disk are 53 bytes (empty). With the extender wired, the segment grows to hundreds of KB for the same product count. Inline the extender inside `<Schema><Fields>` so the builder auto-injects the stock catalog fields alongside your custom ones:

  ```xml
  <Schema>
    <Fields>
      <Extension Type="Dynamicweb.Ecommerce.Indexing.ProductIndexSchemaExtender, Dynamicweb.Ecommerce" />
      <!-- your 5-10 specific ProductCategory|<Cat>|<FieldId> fields here -->
    </Fields>
  </Schema>
  ```

  Then rebuild: `POST /admin/api/BuildIndex {Repository:Products, IndexName:Products.index, BuildName:Full, BuildType:Full}`. **Symptom check:** if PLP/PDP render `numHits must be > 0` and the index built `state=success`, this is the cause — not a missing query file, not a missing `Products.query`, not a paragraph misconfiguration. The data on disk is the diagnostic: a healthy Products index segment is ~270 KB at 30 docs; 53 bytes means the schema accepted zero documents.
- MCP `create_or_update_product_queries` saves `.query` XML but leaves `<Source Repository="" Item="" />` empty — fix via `sed` or patch the file before index build.
- Rebuild the index after ANY product/group/channel mutation.

## MCP product query payload contract

`create_or_update_product_queries` takes a `ProductQueryModel`. Omit `id` when creating; provide `id` when updating. Discover fields first — `get_standard_fields`, `get_product_category_fields`, `get_macro_fields` — and use only the returned field system names. If completeness matters, load real rule IDs from `get_completion_rules`.

Canonical shape (dashboard-backing queries go in the Shared tree — see location rules above):

```json
{
  "name": "active_missing_short_description",
  "sourceIndex": "EcommerceRepository|EcommerceIndex",
  "folderPath": "/Files/System/SmartSearches/Ecommerce/Shared",
  "configuration": {
    "completionRules": [],
    "completionLanguages": []
  },
  "groupExpressions": [
    {
      "operator": "And",
      "negate": false,
      "rootExpressions": [
        { "field": "ProductIsActive", "operator": "Equal", "value": "True" },
        { "field": "ProductShortDescription", "operator": "IsEmpty", "value": "" }
      ],
      "expressions": []
    }
  ]
}
```

Hard constraints:
- `sourceIndex` is `RepositoryName|IndexName` — a pipe, no spaces (discover valid values via `get_product_queries`)
- every `value` is a string; `IsEmpty` uses `value: ""`
- exactly one item in `groupExpressions`
- the MCP model supports only **constant** test values — for Parameter, Macro, Term, or Code test values, say so explicitly and recommend the Dynamicweb admin UI
- completion wiring: integer rule IDs in `configuration.completionRules`, language ID strings in `configuration.completionLanguages`

Typical editorial backlog queries: `active_missing_short_description` (`ProductIsActive=True` + `ProductShortDescription IsEmpty`), `active_missing_images` (image field `IsEmpty`), `low_stock_active` (`ProductStock LessThan "5"`), `incomplete_products` (completion rule IDs + languages attached). Remember the saved `.query` leaves `<Source Repository="" Item="" />` empty — patch it before the index build (see above).

## Dashboard query location — Shared ONLY, never duplicate to Repositories

For dashboard widget queries, put each `.query` + `.configuration` file in **exactly one** place:

**`/Files/System/SmartSearches/Ecommerce/Shared/`** (or a subfolder of it).

Do **NOT** also place a GUID-identical copy under `/Files/System/Repositories/Products/<subfolder>/`. Feed queries at `/Files/System/Repositories/Products/` root (e.g. integration/feed `.query` files) are a separate category — they're resolved by repository+filename for `EcomFeed.FeedIndexQueryId` and must stay at the repo root.

**Why it matters** (a DW10 bug):

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

**Fix**: delete the Repositories-side dashboard duplicates (NOT feed queries at repo root). Then **restart the host** — the `Searching:Queries` cache in `Cache.Current` is NOT exposed via `CacheInformationRefresh`, and `InitQueriesCache` never removes entries, only adds/overwrites. Deleting files from disk alone leaves stale entries in memory until restart. No MCP tool flushes this — plan the restart cost into your fix window. See [`cache-invalidation.md`](cache-invalidation.md) for the post-mutation cache table.

**Does widget drill-through need the query in `Repositories`?** No. Widgets look up queries by GUID through the global cache, which is populated from SmartSearches. Drill-through navigation uses `ProductListNodePathProvider.GetPath` which requires the query's `FolderPath` to start with `SharedQueriesPath` — so Shared is actually the REQUIRED location for drill-through to work at all. Repositories is wrong on both fronts.

## Recovery recipe: Rebuild Products index

After any mutation that touches products, groups, categories, fields, completeness rules, or queries, the Lucene index must be rebuilt — otherwise dashboard widget counts stay stale and product queries return zero rows.

> **FLUSH BEFORE YOU BUILD — this is not optional after a VALUE write.** The index builder reads
> product + category-field data *through* the `ProductService` / `ProductCategoryFieldValueService` /
> `ProductCategoryService` caches. If you mutated a product/category **value** this session — via
> Direct SQL **or MCP `patch_products_safe` / `update_products` / a freshly-`create_category_fields`
> value** — those caches are stale and a rebuild **bakes the old (often empty) value into the index**.
> Symptom: `get_products_by_query` / a dashboard widget returns 0 or stale while `get_product_by_id`
> and the DB are correct. That is an un-flushed read-through cache, **not** an "index quirk", and a
> host restart is NOT a reliable fix (the `dotnet run` parent/child trap means the bounce may not
> cold-start). Run the flush step below first, then build, then re-verify. Full rationale:
> [`cache-invalidation.md` "index-build-reads-through-cache ordering trap"](cache-invalidation.md).

> Run in PowerShell, not Bash — Bash interpolation eats `$env:` and `$_` before they reach the script.

```powershell
# $port and $token come from project-file discovery (launchSettings.json + chat).
# $token works for BOTH the MCP endpoint and /admin/api (same bearer key).

# STEP 0 — flush the caches the index builder reads through (skip ONLY for pure structural
# CREATEs via MCP save_*/assign_*; ALWAYS run after any patch_products_safe / SQL value write).
foreach ($svc in @(
  'Dynamicweb.Ecommerce.Products.ProductService',
  'Dynamicweb.Ecommerce.Products.Categories.ProductCategoryFieldValueService',
  'Dynamicweb.Ecommerce.Products.Categories.ProductCategoryService'
)) {
  Invoke-RestMethod -Uri "https://localhost:$port/admin/api/CacheInformationRefresh" `
    -Method POST -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
    -Body (@{ CacheTypeName = $svc } | ConvertTo-Json) -SkipCertificateCheck | Out-Null
}

$buildResp = Invoke-RestMethod `
  -Uri "https://localhost:$port/admin/api/BuildIndex" `
  -Method POST `
  -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
  -Body (@{ Repository = "Products"; IndexName = "Products.index"; BuildName = "Full" } | ConvertTo-Json) `
  -SkipCertificateCheck

# Poll the index status query until Success with a fresh build timestamp (15-min timeout).
# DW 10.26.x contract: no Status/Idle field — State: Success|Warning|Error on the index query,
# LifecycleState: NeverBuilt|...|Completed|Failed on the instance query. Live JSON is camelCase
# (the api.json catalog declares PascalCase); PowerShell access is case-insensitive.
# A never-built index reports State=Error while its FIRST build is still writing — treat Error
# as terminal only when the instance query's LifecycleState is Failed; otherwise keep polling.
$posted = Get-Date
$deadline = (Get-Date).AddMinutes(15)
do {
  Start-Sleep -Seconds 5
  $status = Invoke-RestMethod `
    -Uri "https://localhost:$port/admin/api/IndexStatusByRepositoryAndIndexName?Repository=Products&IndexName=Products.index" `
    -Headers @{ Authorization = "Bearer $token" } `
    -SkipCertificateCheck
  Write-Host ("State: " + $status.Model.State + "  LastRun: " + $status.Model.LastRun)
} while (-not ($status.Model.State -eq 'Success' -and [datetime]$status.Model.LastRun -gt $posted) -and (Get-Date) -lt $deadline)

if ($status.Model.State -eq 'Success' -and [datetime]$status.Model.LastRun -gt $posted) { Write-Host "BuildIndex Full complete." -ForegroundColor Green }
else { Write-Warning "BuildIndex did not reach a fresh Success within 15 minutes" }
```

The freshness comparison against `$posted` is load-bearing: a prior run's successful build satisfies a
state-only check, so a state check without the timestamp guard can "pass" on a stale index. Repository
and index names are solution-specific — read them from `wwwroot/Files/System/Repositories/` instead of
assuming `Products` (a stock Swift solution ships `ProductsFrontend`/`ProductsBackend`).

**Always re-verify after a value write** — run a `get_products_by_query` against a query that filters
on the field you just changed and confirm the count matches what you set. If it is still 0/stale, you
either skipped STEP 0 or flushed the wrong cache — do **not** rebuild again blindly, do **not** label
it an index quirk; flush the three services above and rebuild once more. (Building before flushing is
the #1 cause of "the dashboard widget shows 0 but the data is right".)

If the build fails or never reaches a fresh Success, check that the index file exists at `wwwroot/Files/System/Repositories/Products/Products.index` and that the Repository name matches the index file's containing folder. The completeness/governance consumers of this index live in [`pim-completeness.md`](pim-completeness.md); the post-mutation cache rules live in [`cache-invalidation.md`](cache-invalidation.md).
