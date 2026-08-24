# Index and repository management — files, placement rules, builds, recovery

Field-validated DW10 knowledge of the product index / repositories / queries file layer: where
`.index` and `.query` files live, the schema-extender requirement, the MCP query payload contract,
the GUID-duplication bug, channel isolation, currency preconditions, and the full rebuild recipe.
The `Query*` **verbs** are owned by two sibling files: [`query-authoring.md`](query-authoring.md)
(reading, copying, naming, relocating, deleting, and the restart-free cache flush) and
[`query-expressions.md`](query-expressions.md) (expressions, operators, sorting, result paging,
inert index fields, and the build verbs' silent-success failure modes). This file owns the index
and repository side.

## Contents

- [Repositories, Indexes, and Queries — file-based](#repositories-indexes-and-queries--file-based)
- [MCP product query payload contract](#mcp-product-query-payload-contract)
- [Dashboard query location — Shared ONLY](#dashboard-query-location--shared-only-never-duplicate-to-repositories)
- [Channel isolation is a QUERY-time filter](#channel-isolation-is-a-query-time-filter-not-an-index-time-one)
- [Currency integrity is an index-build precondition](#currency-integrity-is-an-index-build-precondition--dividebyzeroexception-names-neither-the-currency-nor-the-country)
- [Recovery recipe: Rebuild Products index](#recovery-recipe-rebuild-products-index)

## Repositories, Indexes, and Queries — file-based

- **Repository** = folder under `wwwroot/Files/System/Repositories/<RepoName>/`
- **Index** = `.index` XML file inside the repo folder (build via management API `POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full"}`). **`IndexName` is the index FILE name (`Products.index`, extension included) and `BuildName` names a BUILDER registered inside that XML — not a free label.** Resolve it from `IndexBuildersByRepositoryAndIndexName` rather than posting a guess: an unresolvable `BuildName` has been observed to answer `404`, to answer `500 "Unable to load build '<name>'"`, **and** to answer `200 {"status":"ok"}` and build nothing, on different hosts and verbs. The first two read as "the verb is unavailable" rather than "the argument is wrong"; the third reads as success. Because the failure mode is not predictable, resolving the builder **and** asserting build freshness afterwards is mandatory either way — see [`query-expressions.md`](query-expressions.md) "Build verbs: 200 is not 'built'" for the two sibling traps (building an index the queries do not read, and an instance that never recovers). The `Name`-attribute gotcha below is the same one-value-two-meanings hazard on the file side. A full build also outruns a 120s client timeout, so fire it and verify out of band (see "Recovery recipe" below).
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
- `sourceIndex` is `RepositoryName|IndexName` — a pipe, no spaces (discover valid values via `get_product_queries`). **It also names the index a rebuild must target**: a convenience "build the product index" surface builds its own default pair, not this one ([`query-expressions.md`](query-expressions.md) "Build verbs")
- every `value` is a string; `IsEmpty` uses `value: ""`
- **exactly one item in `groupExpressions` — a second group is not preserved.** Later groups' conditions are merged into the root `And` and their own `operator`/`negate` are dropped, so an intended OR-list or NOT-group is written as a flat `And` and returns 0 rows with `success: true`. Anything with alternation or negation goes through the expression-replacement surface that takes a real tree ([`query-expressions.md`](query-expressions.md) "Authoring expressions")
- `folderPath` — the virtual path above is the shape that has been validated on a local install. **On at least one cloud host the same verb requires the server-side ABSOLUTE filesystem path and silently no-ops on anything else** (answering `ok`, persisting nothing). Whichever form you pass, read the query back by name before treating the create as done; that assert is what makes the difference invisible
- the MCP model supports only **constant** test values — for Parameter, Macro, Term, or Code test values, say so explicitly and recommend the Dynamicweb admin UI
- completion wiring: integer rule IDs in `configuration.completionRules`, language ID strings in `configuration.completionLanguages`

Typical editorial backlog queries: `active_missing_short_description` (`ProductIsActive=True` + `ProductShortDescription IsEmpty`), `active_missing_images` (image field `IsEmpty`), `low_stock_active` (`ProductStock LessThan "5"`), `incomplete_products` (completion rule IDs + languages attached). Remember the saved `.query` leaves `<Source Repository="" Item="" />` empty — patch it before the index build (see above).

### Custom product fields index as `CustomField_<SystemName>`

A **custom** product field (a category field or a custom `EcomProductField`, as opposed to a standard one) lands in the Lucene index under the field name **`CustomField_<SystemName>`** — e.g. a custom field `RoomType` is queryable/facetable as `CustomField_RoomType`, not as `RoomType`, not as `ProductCategory|<Cat>|RoomType` (that pipe form is the *authoring/value* system name from [`structural-model.md`](../../dw-pim-modelling/references/structural-model.md) §2.8, not the *index* name). Referencing it by any other plausible pattern **fails silently** — the facet renders empty and the query returns nothing, with **no error** to point at the wrong name. When a facet you added is defined but always empty, check the index field name is `CustomField_<SystemName>` first. Confirm the exact indexed name against the built segment (or the index schema's field list) rather than guessing the casing/prefix.

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

**Diagnosis tell — read the frame ABOVE `GetQueryFolderPath` and the `Type=` in the URL first.** A 500 with `System.NotSupportedException` at `ProductListNodePathProvider.GetQueryFolderPath` has two distinct causes and they need different answers:

- **`Type=FavoriteQueries` in the URL, with `QueryFolderNavigationNodePathProvider` in the frame above** — a stock platform bug, not your query tree. `FavoriteQueriesQuery.MakeListModel()` returns a **compile-time-constant** `FolderPath` of `…/SmartSearches/Ecommerce/Favorites`, which matches neither the shared nor the personal path `GetQueryFolderPath` accepts, so the throw is unconditional and no `.query` file placement can cause or cure it. It reproduces on an untouched tree and only when the screen renders as an area-container load (deep link / full area refresh) — reaching "My favorites" by the in-app anchor renders fine. Grepping for duplicate GUIDs here finds nothing and burns the window.
- **Any other `Type=`, reached from the Shared queries tree** — this is the GUID-duplication case below. Grep the two folders:
```bash
grep -h 'Query ID=' wwwroot/Files/System/Repositories/Products/**/*.query | sort > /tmp/repo.txt
grep -h 'Query ID=' wwwroot/Files/System/SmartSearches/Ecommerce/Shared/**/*.query | sort > /tmp/shared.txt
diff /tmp/repo.txt /tmp/shared.txt  # identical lines = duplicates
```

**Fix**: relocate with `QueryMove` (which carries the `.configuration` sibling and updates the cache) or delete the Repositories-side dashboard duplicates — NOT feed queries at repo root. Then **flush the query cache; a restart is not required.** The `Searching:Queries` cache is genuinely not reachable through `CacheInformationRefresh` (no `ICacheStorage` implementor owns that key) and `InitQueriesCache` never removes entries — but `QueryHelper.GetQueryById` re-runs `InitQueriesCache` on a cache **miss**, so `GET /Admin/Api/QueryById?Id=<a GUID that does not exist>` re-initialises it as a side effect. The `400` it answers is expected. Full recipe, and the ordering trap that makes it necessary (the file verbs do not update the cache, so the next `QuerySave` writes back to the old path), in [`query-authoring.md`](query-authoring.md) "Flush the query cache without a restart".

**Does widget drill-through need the query in `Repositories`?** No. Widgets look up queries by GUID through the global cache, which is populated from SmartSearches. Drill-through navigation uses `ProductListNodePathProvider.GetPath` which requires the query's `FolderPath` to start with `SharedQueriesPath` — so Shared is actually the REQUIRED location for drill-through to work at all. Repositories is wrong on both fronts.

## Channel isolation is a QUERY-time filter, not an index-time one

**The lever that keeps non-shoppable products off the storefront is the query's own shop filter, not
`ShopsToIndex` on the builder.** The shipped storefront queries carry a mandatory
`MatchAny(ShopIDs, <shop-context macro>)` binary expression, and each area is bound to one shop — so a
product whose only shop is a different shop can never match a storefront query even when a nightly full
build indexed it. `ShopsToIndex` only controls how BIG the index is.

Two consequences worth stating plainly:

- **An empty `ShopsToIndex` is not a defect to fix reflexively.** It is normal on stock solutions and it
  is not an open leak; treat it as an index-size choice.
- **The way to make products non-shoppable is a separate shop/channel plus the query-level `ShopIDs`
  filter the storefront already ships** — not a builder setting.

Prove isolation by what the storefront **renders**, not by an index setting or a substring check: assert
zero products in the LISTING on every search and PLP surface for the excluded channel, with a calibrated
control (a probe that returns a known non-zero count for a shoppable group) so a silently broken probe
cannot read as a pass.

## Currency integrity is an index-build precondition — `DivideByZeroException` names neither the currency nor the country

**Price calculation divides by the currency rate, so a currency with rate `0` — or an `EcomCountries` row
pointing at a currency that does not exist at all — crashes the product index build.** The exception is
opaque: `DivideByZeroException` "Error processing prices" during the build, fired by both the scheduled build
and a `BuildIndex` POST, naming **neither** the offending currency **nor** the country. It reads as a corrupt
product and it lands on the Monitoring dashboard as a steady daily error count.

Two independent causes produce the identical exception, which is why fixing only the one the error *seems* to
point at leaves it firing:

```sql
SELECT COUNT(*) FROM EcomCurrencies WHERE CurrencyRate = 0;                    -- must be 0
SELECT COUNT(*) FROM EcomCountries c                                           -- must be 0
 WHERE c.CountryCurrencyCode NOT IN (SELECT CurrencyCode FROM EcomCurrencies);
```

One host carried a zero rate on all 16 language rows of a single currency **and** three countries pointing at
currencies that had never been created. Clearing both took the build from 30 errors/day to a clean full
rebuild with zero `DivideByZero` and zero `NullReference` across the whole log.

- **Write currencies through `CurrencySave`, never raw SQL** — currencies are cache-coupled.
- **`CurrencyByCode` answers `400`.** Read the model from `CurrenciesAll`, and use `CurrencyNew` to get the
  blank create model.
- **Functional check beyond the log:** price a cart line in **every** currency the solution exposes. A
  currency that silently threw before will price cleanly after.
- Make this a **precondition of the build**, not a symptom to chase: no zero rates, and every
  `EcomCountries` currency code exists.

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
> cold-start). Run the flush step below first, then build, then re-verify.

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
# `synchronous: true` in the BuildIndex body does NOT actually block — the POST returns before the
# build finishes regardless, so treating a 2xx as "built" indexes against a stale/empty segment.
# ALWAYS poll the instance/index status below; never rely on the request to be synchronous.
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

**On 10.28.x the build is genuinely synchronous and outlives the client, so a timeout is not a failure.**
A `Repository='Products'` Full build routinely exceeds a 120s HTTP client timeout while completing
normally — the timeout severs the **response**, not the build. Catch it, do not retry (a retry queues a
second full rebuild behind a succeeding one), and poll instead. The status verb on 10.28.x is
**`IndexStatusesAll`**; the singular `IndexStatus` and `GetIndexes` answer `400 Unknown query`, which is
what produced the earlier reading that no status command existed on that version. The polling loop below is
unchanged in shape — only the status verb is version-dependent, so read it from `api.json` rather than
assuming either name.

The freshness comparison against `$posted` is load-bearing: a prior run's successful build satisfies a
state-only check, so a state check without the timestamp guard can "pass" on a stale index. Repository
and index names are solution-specific — read them from `wwwroot/Files/System/Repositories/` instead of
assuming `Products` (a stock Swift solution ships `ProductsFrontend`/`ProductsBackend`).

**Always re-verify after a value write** — run a `get_products_by_query` against a query that filters
on the field you just changed and confirm the count matches what you set. If it is still 0/stale, you
either skipped STEP 0 or flushed the wrong cache — do **not** rebuild again blindly, do **not** label
it an index quirk; flush the three services above and rebuild once more. (Building before flushing is
the #1 cause of "the dashboard widget shows 0 but the data is right".)

If the build fails or never reaches a fresh Success, check that the index file exists at `wwwroot/Files/System/Repositories/Products/Products.index` and that the Repository name matches the index file's containing folder. The completeness/governance consumers of this index live in [`rules-and-dashboards.md`](../../dw-pim-completeness/references/rules-and-dashboards.md).
