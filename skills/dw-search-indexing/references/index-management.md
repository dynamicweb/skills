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
- [Authoring a `.index` file — the rules no API surface reports](#authoring-a-index-file--the-rules-no-api-surface-reports)
- [The user index publishes a password hash and the whole impersonation graph](#the-user-index-publishes-a-password-hash-and-the-whole-impersonation-graph)
- [MCP product query payload contract](#mcp-product-query-payload-contract)
- [Dashboard query location — Shared ONLY](#dashboard-query-location--shared-only-never-duplicate-to-repositories)
- [Channel isolation is a QUERY-time filter](#channel-isolation-is-a-query-time-filter-not-an-index-time-one)
- [Currency integrity is an index-build precondition](#currency-integrity-is-an-index-build-precondition--dividebyzeroexception-names-neither-the-currency-nor-the-country)
- [A NULL-price variant row drops every variant document from the build](#a-null-price-variant-row-drops-every-variant-document-from-the-build)
- [An `Analyzed="false"` field facets as ONE term](#an-analyzedfalse-field-facets-as-one-term)
- [The Files index: `StartFolder` is the library, and keywords live in the file](#the-files-index-startfolder-is-the-library-and-keywords-live-in-the-file)
- [Recovery recipe: Rebuild Products index](#recovery-recipe-rebuild-products-index)

## Repositories, Indexes, and Queries — file-based

- **Repository** = folder under `wwwroot/Files/System/Repositories/<RepoName>/`
- **Index** = `.index` XML file inside the repo folder (build via management API `POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full"}`). **`IndexName` is the index FILE name (`Products.index`, extension included) and `BuildName` names a BUILDER registered inside that XML — not a free label.** Resolve it from `IndexBuildersByRepositoryAndIndexName` rather than posting a guess: an unresolvable `BuildName` has been observed to answer `404`, to answer `500 "Unable to load build '<name>'"`, **and** to answer `200 {"status":"ok"}` and build nothing, on different hosts and verbs. The first two read as "the verb is unavailable" rather than "the argument is wrong"; the third reads as success. Because the failure mode is not predictable, resolving the builder **and** asserting build freshness afterwards is mandatory either way — see [`query-expressions.md`](query-expressions.md) "Build verbs: 200 is not 'built'" for the two sibling traps (building an index the queries do not read, and an instance that never recovers). The `Name`-attribute gotcha below is the same one-value-two-meanings hazard on the file side. A full build also outruns a 120s client timeout, so fire it and verify out of band (see "Recovery recipe" below). **The query-parameter NAMES are not uniform across the sibling index queries, and the wrong one answers `400 "Unable to load query parameters"`, which reads as a missing verb:** `IndexByRepositoryAndName` and `IndexBuildersByRepositoryAndIndexName` take **`Repository` + `IndexName`**, while `IndexInstancesByRepositoryAndIndex` takes **`RepositoryName` + `IndexName`**. Copy the parameter names per verb rather than generalising from the one that worked last.
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

  Then rebuild: `POST /admin/api/BuildIndex {Repository:Products, IndexName:Products.index, BuildName:Full, BuildType:Full}`. **Symptom check:** `numHits must be > 0` on the PLP/PDP always means the index holds **zero documents**, whatever the build reported. A schema the extender never populated is one way to get there; a build that ran before the content landed is the other, and the preconditions below separate them. Check the document count first, then the schema. The data on disk is the diagnostic: a healthy Products index segment is ~270 KB at 30 docs; 53 bytes means the schema accepted zero documents.
- MCP `create_or_update_product_queries` saves `.query` XML but leaves `<Source Repository="" Item="" />` empty — fix via `sed` or patch the file before index build.
- **Name the repository, then prove the build drained and the index holds documents.** Five
  preconditions sit behind an empty product listing, all silent when absent, and the build call
  reports success through every one of them. In order, alongside the primary-instance rule:
  1. **Pass BOTH `repositoryName` AND `indexName` — each default addresses nothing.**
     `get_product_index_status`, `build_product_index` and `wait_for_product_index` default
     `repositoryName` and `indexName` to the literal `Products`, and neither validates that the name
     resolves to a folder under `Files/System/Repositories/` or to an index file inside it. Take the
     repository name from the catalogue paragraph itself — `get_module_settings` on the paragraph
     returns its `IndexQuery` path (`/Files/System/Repositories/<repo>/Products.query`) — and pass
     `indexName` as the **file name including the `.index` suffix** (`Products.index`).
     Measured on DW 10.28.x with MCP 0.4.4: `{repositoryName}` alone answers
     `{"repositoryName":"<repo>","indexName":"Products","isBuilding":false,"status":"Idle"}` — a bare
     `Idle` with **no `documentCount` member at all**; adding `{"indexName":"Products.index"}` answers
     the full payload with `lastBuildCompleted`, `documentCount` and `indexState`. **A status response
     carrying no `documentCount` member means the pair addressed nothing** — fix the arguments rather
     than falling back to the completed state.
  2. **The repository has a `Build+Index.task` file.** The build is drained by a task file inside the
     repository folder (`Files/System/Repositories/<repo>/Build+Index.task`, an
     `IndexBuilderTaskProvider` entry naming the index and the build). With the file missing,
     `build_product_index` answers *queued* and succeeds, `get_product_index_status` never advances,
     and an agent polling as instructed concludes the build is slow. `get_index_repositories` shows
     the repository; read the folder to confirm the file. Absent → nothing will ever drain.
  3. **The repository task handler is enabled.** The drain itself is a scheduled task, and it is a
     DB row on the host — no layer ships or asserts it, so a host with it disabled fails exactly
     like a host with no task file. `get_scheduled_tasks` shows the repository task handler and
     whether it is enabled; disabled or missing → `run_scheduled_task_now` for a one-off drain, and
     say that the schedule needs fixing. Find the row by `name` equal to `Repository task handler`
     and gate on `enabled`. Measured members on DW 10.28.x with MCP 0.4.4: `id`, `name`, `enabled`,
     `intervalMinutes`, `addInTypeName` (the task class), `schedule`, `lastRun`, `lastRunState` and
     `timeoutSeconds`.
  4. **The first build after any deserialize or fixture load is explicit.** The task file repeats on
     an interval measured in hours, typically a day, so a host whose last drained build predates the
     content load serves an empty index until the next tick — and then self-heals, which is what
     makes this intermittent and easy to misattribute on a retest the following day. Run
     `build_product_index` + `wait_for_product_index` for the named repository **after** the content
     is in, and never count the scheduled drain as the first build.
  5. **Assert `documentCount` greater than zero, not a completed state.** Call
     `get_product_index_status` with both `repositoryName` and `indexName` (precondition 1) — that
     pair is what makes `documentCount` present at all. `get_product_index_status`
     reporting `Completed` with zero documents is the failure, not the success, and the build's own
     status artefact says so first: a green run whose total count is `0` while products exist in the
     catalogue is the signal, and it finishes in milliseconds because there was nothing to index.
     A zero-document index cannot serve a query **at all** — the collector is sized from the reader's
     document count and rejects a hit count of 0, so the catalogue app throws
     `numHits must be > 0` and the frontend writes that exception into the page body **inside an
     HTTP 200 response**. The on-disk tell is as cheap: instance directories exist under
     `Files/System/Indexes/<repo>/…` carrying only `segments.gen` / `segments_N` of a few dozen
     bytes, with no payload files. Compare the build's last successful timestamp against the
     deserialize and fail when the build predates it.

- Rebuild the index after ANY product/group/channel mutation.

## Authoring a `.index` file — the rules no API surface reports

The `.index` is XML on disk under `Files/System/Repositories/<Repo>/`, and **the filesystem is the
only surface that authors it** — no Management API verb and no MCP tool writes an index schema. That
path is inside the file archive, so write it with `upload_file` and read it back with `read_file`;
the admin file manager is the same edit from a screen. Outside the product, on a host whose archive
is not mounted, see dw-data-access `recipes-search.md` §Getting an authored `.index` file onto a
hosted install. Every rule in this table is invisible from the read surfaces:
`BuildIndex` answers `{"status":"ok"}`, `IndexStatusesByRepository` answers "All instances are fine",
and `FieldDefinitionBasesByRepositoryAndIndexName` lists the field exactly as declared — while the
field is not in the index at all.

| Rule | What it means in the file |
|---|---|
| **`Field/@Source` takes the raw database COLUMN name; `Copy/@Sources` takes index field SYSTEM names.** Two different namespaces on two neighbouring elements | The builder fills each `IndexDocument` straight off its own `SELECT *` using `IDataRecord.GetName()`, so a document key is the column name (`AccessUserCustomerNumber`), while a copy field composes already-named index fields (`CustomerNumber`). A wrong `Source` drops the field silently: no exception, nothing in `Files/System/Log`, nothing in the build status. The shipped `Products.index` teaches the wrong rule by accident, because its `Source` values (`ProductName`, `ProductNumber`, `ManufacturerName`) are valid as *both* a column name and a system name |
| **A `Copy` field may declare `Analyzer` and `Boost`, exactly like a direct `Field`** | `IndexHelper.FillIndexWithSchema` reads `Type`, `Name`, `SystemName`, `Analyzer`, `Boost`, `Indexed`, `Stored`, `Analyzed` and `Facetable` off the XML, and `CopyFieldDefinition` derives from `FieldDefinitionBase`. This is the shape a boosted exact-match search field relies on: an **analysed** copy field over the identifier columns, carrying its own high boost |
| **`Skip*` settings are read at BUILD time and live on the `<Build>` nodes** | `SkipOrderhistory`, `SkipPrices`, `SkipStock` and their siblings sit on the `<Build>` nodes inside one `<Builds>` element — **not** on the two `<Instance>` nodes, which is where people look first and which carry no settings at all. Because the builder consumes them, flipping one and running a single Full build republishes the field into every instance of a live index **with no app-pool restart**: on 10.28.x the worker process was untouched across the change. Budget a Full build, not a deploy window |
| **An `<Extension>`-declared field cannot be overridden from the file** | The platform schema extenders (`ProductIndexSchemaExtender`, `UserIndexSchemaExtender`) declare their fields with their own `stored`/`indexed` flags, and field configuration in the `.index` does not override them — the builder writes what the extender declares. Design around the extender's field list rather than trying to reshape it |
| **A custom product field reaches the index as stored payload, not as a predicate** | Declaring it as a `Field` or a `Copy` does not make it filterable — see ["Fields that are declared but never populated"](query-expressions.md#fields-that-are-declared-but-never-populated) for the full rule and the check that catches it before a paragraph is built on one |
| **`<Index Name>` includes the `.index` extension** | Covered above under the Name-attribute gotcha; the same value is what every build surface wants |

**`BoughtWithProducts` is a query field, not a ViewModel member.** Turning `SkipOrderhistory` off and
running a Full build genuinely publishes it into every instance — but no `ProductViewModel` member
exposes it, and the shipped consumers all emit a hidden `BoughtWithProductIds` form input, i.e. they
feed a repository **query parameter** and need a Product Catalog surface to run that query. The field
is designed to be searched, not read, so the flag is necessary and not sufficient: plan the second
catalog surface in the same breath, or compute the co-occurrence over the order lines directly, which
is the same source data the field is derived from.

**Assert an index schema against the Lucene DIRECTORY, never against the API.** Open the instance
directory read-only with the site's own Lucene.Net and enumerate `MultiFields.GetFields`; that is the
only probe that sees what the index really holds. Through the API the two states are
indistinguishable: `IndexDocumentsByInstance` never shows a `stored="false"` field either, so "the
field is missing" and "the field is not stored" read identically, and an audit through that verb
under-reports the schema in both directions. A field-count assertion off the directory (`51` indexed
fields where the schema declares 51) is the cheap standing form.

**There is no backend free-text or wildcard search setting to configure on 10.28.x.**
`GlobalSettings.config` carries no free-text or wildcard key, and the shipped assemblies expose no
search-behaviour key under `/Globalsettings/Ecom/...` — the only indexing keys are
`Ecom/Indexing/DoNotStoreDefaultFields` and `Ecom/Indexing/DoNotAnalyzeDefaultFields`, which are
index-build flags. An acceptance criterion written against "Areas > Products > Advanced configuration
> General free-text search options" cannot be met; record it as not-applicable and tune relevance
through analyzers and field boosts in the `.index` instead.

## The user index publishes a password hash and the whole impersonation graph

`UserIndexSchemaExtender` is the shipped schema every user index is built on, and two facts about
its field list decide how a user repository may be used.

**Every user document carries `UserPassword` — the complete hash from `AccessUserPassword`, stored
and indexed — and there is no switch.** The field comes from the extender, not from the `.index`, so
file-level field configuration does not remove it. A built user index therefore places one
offline-crackable hash per account in `Files/System/Indexes/<Repo>/...` — under the web root, on the
same volume as the file area, and readable through Admin API `IndexDocumentsByInstance`. Consequences
to apply whenever a user index is stood up:

- **Treat `Files/System/Indexes` as sensitive** on any solution that has one: it is routinely backed
  up, synced to a staging environment, and shipped alongside a database copy. Mitigation today is
  environmental (directory ACLs, excluding the index folder from copies), not configurable.
- **Verify the index files are not web-reachable** — on a stock install every `/Files/System/...`
  path answers 404 anonymously; assert that rather than assume it, and re-assert after any change to
  static-file handling.
- **A template over user documents names the fields it renders.** Never loop a document and emit
  what it holds: the hash is in the same document as the display fields.

**The extender also publishes the impersonation graph, both directions, group-expanded — and it is
queryable.** The impersonator's document carries `CanImpersonate`, the target's carries
`CanBeImpersonatedBy`, each already expanded through group inheritance by the builder. Both are
**numeric** fields, so a permission-scoped user picker is one query arm (`In` against
`CanBeImpersonatedBy` with the acting user's id plus the granting group ids) rather than an unscoped
read post-filtered in Razor. Two things to know before building on it:

- **Numeric fields need a typed right-hand side** — `System.Int32` / `System.Int32[]` — or the arm
  matches nothing and fails closed. The rule and the diagnostics are in
  [`query-expressions.md`](query-expressions.md#a-numeric-predicate-needs-a-typed-constant).
- **A group-held grant reaches only the members of the granted groups.** An impersonator who also
  holds direct user rows sees strictly more than another member of the same group does. The admin UI
  cannot show that asymmetry; the index can, so measure the scope per acting identity rather than
  reasoning from the group grant.

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
        { "field": "ProductShortDescription", "operator": "Equal", "value": "__empty__" }
      ],
      "expressions": []
    }
  ]
}
```

Hard constraints:
- `sourceIndex` is `RepositoryName|IndexName` — a pipe, no spaces (discover valid values via `get_product_queries`). **It also names the index a rebuild must target**: a convenience "build the product index" surface builds its own default pair, not this one ([`query-expressions.md`](query-expressions.md) "Build verbs")
- every `value` is a string. **Do not author an `IsEmpty` arm.** On the Lucene provider on 10.28.x
  the operator parses and matches nothing, so a backlog query built on it reads zero and looks like a
  fully enriched catalogue
  ([`query-expressions.md`](query-expressions.md#operators-what-the-enum-implies-vs-what-matches)).
  Express "has no value" positively: set `EmptyStringReplacement` on the index to a sentinel
  (`__empty__` above) and filter on the sentinel with `Equal`, per
  [`../SKILL.md`](../SKILL.md) "NULL values". Assert the row count of any emptiness arm either way
- **exactly one item in `groupExpressions` — a second group is not preserved.** Later groups' conditions are merged into the root `And` and their own `operator`/`negate` are dropped, so an intended OR-list or NOT-group is written as a flat `And` and returns 0 rows with `success: true`. Anything with alternation or negation goes through the expression-replacement surface that takes a real tree ([`query-expressions.md`](query-expressions.md) "Authoring expressions")
- `folderPath` — the virtual path above is the shape that has been validated on a local install. **On at least one cloud host the same verb requires the server-side ABSOLUTE filesystem path and silently no-ops on anything else** (answering `ok`, persisting nothing). Whichever form you pass, read the query back by name before treating the create as done; that assert is what makes the difference invisible
- the MCP model supports only **constant** test values — for Parameter, Macro, Term, or Code test values, say so explicitly and recommend the Dynamicweb admin UI
- completion wiring: integer rule IDs in `configuration.completionRules`, language ID strings in `configuration.completionLanguages`

Typical editorial backlog queries, all on the sentinel-plus-`Equal` shape: `active_missing_short_description` (`ProductIsActive Equal True` + `ProductShortDescription Equal "__empty__"`), `active_missing_images` (image field `Equal "__empty__"`), `low_stock_active` (`ProductStock LessThan "5"`), `incomplete_products` (completion rule IDs + languages attached). The sentinel is whatever `EmptyStringReplacement` is set to on the index — read it before authoring, and assert a non-zero count on a catalogue known to have gaps. Remember the saved `.query` leaves `<Source Repository="" Item="" />` empty — patch it before the index build (see above).

### Custom product fields index as `CustomField_<SystemName>`

**Authoring side versus index side — one field, two names.** The pipe form `ProductCategory|<Cat>|<Field>` is the *authoring/value* system name (from [`structural-model.md`](../../dw-pim-modelling/references/structural-model.md) §2.8): it is what a value write and a completion-rule definition name, and it is correct there — see [`dw-pim-completeness/references/rules-and-dashboards.md`](../../dw-pim-completeness/references/rules-and-dashboards.md) step 4. This section is the *index* side.

A **custom** product field (a category field or a custom `EcomProductField`, as opposed to a standard one) lands in the Lucene index under the field name **`CustomField_<SystemName>`** — e.g. a custom field `RoomType` is queryable/facetable as `CustomField_RoomType`, not as `RoomType`, and not as `ProductCategory|<Cat>|RoomType` in an index predicate or a facet. Referencing it by any other plausible pattern **fails silently** — the facet renders empty and the query returns nothing, with **no error** to point at the wrong name. When a facet you added is defined but always empty, check the index field name is `CustomField_<SystemName>` first. Confirm the exact indexed name against the built segment (or the index schema's field list) rather than guessing the casing/prefix.

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

## A NULL-price variant row drops every variant document from the build

**`ProductIndexBuilder.HandlePrices` throws `InvalidCastException` Int32 to Double on a variant
`EcomProducts` row whose `ProductPrice` is NULL**, and the exception is caught **per document**: the
master indexes normally, every variant document is silently dropped, and the build reports success. The
only trace is one log line per dropped row:

```
Error processing prices. System.InvalidCastException: Unable to cast object of type
System.Int32 to type System.Double
   at ...ProductIndexBuilder.HandlePrices
Error process prices (AutoID: <the variant rows' auto ids>)
```

- **Adding an `EcomPrices` row for the variant does not stop it**: the throw is on the product row's own
  NULL `ProductPrice`, not on the absence of a price row.
- Storefront symptom: the master renders on the PLP with its variant combinations attached while the PDP
  shows **no variant selector**, so a size-ladder product looks like a single un-sized product. Deleting
  the combinations removes the log noise and the selector alike.
- MCP `create_variant_combinations` materialises variant rows with `ProductPrice` NULL, which is how a
  catalogue arrives in this state. On DW 10.28.x those rows cannot be filled through the API at all (see
  [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.14).
- **Count the documents, not the build status.** Assert the built document count against masters plus
  variants; a build that silently drops every variant still answers `state: success`.

## An `Analyzed="false"` field facets as ONE term

Decide the facet's SOURCE field before the index is written. A field indexed as
`<Field Source="ProductCategory|<cat>|<field>" Analyzed="false">` is a single term, so the facet gets
exactly one bucket per distinct **cell**. On a multi-value PIM text field that is one giant checkbox:
a pipe-joined fitment cell (`Machine A (SKU) | Machine B (SKU)`) facets as the whole string rather
than one value per machine. `EcomProductCategoryField` `FieldType = 11` (plain Text) carries no
multi-value semantics of its own; the pipe separator is a display convention, not structure.

Setting `Analyzed="true"` on the pipe-joined field is **not** the fix: an analysed field tokenises on
whitespace, so the facet buckets word fragments ("Snapper", "T42", "(SNTR1900-42)") instead of whole
labels. Two honest options:

- **Source the facet from a separate SINGLE-valued field** and keep the multi-value field display-only.
  Know the consequence: an item that fits several machines is then reachable only through its primary
  value in that facet.
- **Use a genuine multi-value field type.** `EcomProductCategoryField.FieldType` has options beyond 11
  (1, 2, 3, 6, 7, 8, 12, 15 and 25 are all in gate-proven use) and `EcomFieldOption` exists for option
  lists.

**Assert the facet's VALUE COUNT, not that the facet renders.** A single-term regression shows as a
facet with exactly one enormous checkbox, which a presence assert passes. Assert the expected bucket
count per facet and the product count behind at least one filtered URL. Not corruption, by the way:
Swift wraps a facet value containing a comma in brackets, `value="[Controls, Steering &amp; Seat]"`.

## The Files index: `StartFolder` is the library, and keywords live in the file

**The index's `StartFolder` IS the asset library.** A Files index rooted at
`Files/<StartFolder>` indexes that folder recursively, and the shipped asset-library page is a Query
Publisher paragraph over the repository's `.query` + `.facets` with two axes: `DirectoryRelativePath`
and `IPTCKeywords`. So the **folder names are the primary facet** — name the folders the way a reader
should see them (`Brand logos`, `Equipment photography`, `Sell sheets`), because that list is the
facet list.

**Keyword metadata has no row in the database — the index reads it out of the file.** `Files.index`
maps `IPTCKeywords` from the source `IPTC|Keywords`, and on 10.28.x `INFORMATION_SCHEMA` carries no
file-metadata table at all. The durable home for a DAM keyword is therefore the binary: write a
Photoshop 3.0 IRB into an APP13 JPEG segment — identifier `Photoshop 3.0\0`, 8BIM resource type
`0x0404` (IPTC-IIM), IIM record `2:25` (Keywords) written **once per keyword**, each value
even-padded — then rebuild the Files index. That one write satisfies both surfaces: the Lucene facet
renders live options, and the asset-detail offcanvas IPTC panel populates, because it reads back
through `Dynamicweb.Imaging.Image.GetMetadataFromFile`. Take a negative control first (before the
write the keyword facet has zero options while the folder facet is fully populated), so a rebuild
that addressed nothing cannot be mistaken for a metadata failure.

**PNG carries no IPTC**, so a PNG-only folder can never have keyword options — which is the second
reason the folder facet has to be the primary axis and keywords the secondary one.

On a fresh clone the Files index build fails outright with `Directory 'Files\Digital assets' does not
exist`, and the whole index goes to error / "no healthy instance", which then reads as a broken
repository. The builder requires the `StartFolder` directory; a fresh clone does not ship it.
Precreate it before the first build (`mkdir "Files/Digital assets"`), or scope the build to the
repositories the demo actually serves. Two rebuilds are needed afterwards, because index instances build one at a time: each
`BuildIndex` call rebuilds only the currently-offline instance and then swaps, so a two-instance index
reports a partial state until the second call. Gate on `GET /Admin/Api/IndexStatusesAll` reporting
success / "All instances are fine" per repository, never on the `BuildIndex` response.

## Recovery recipe: Rebuild Products index

After any mutation that touches products, groups, categories, fields, completeness rules, or queries, the Lucene index must be rebuilt — otherwise dashboard widget counts stay stale and product queries return zero rows.

> **FLUSH BEFORE YOU BUILD — this is not optional after a VALUE write.** The index builder reads
> product + category-field data *through* the `ProductService` / `ProductCategoryFieldValueService` /
> `ProductCategoryService` caches. If you mutated a product/category **value** this session — via
> Direct SQL **or MCP `patch_products_safe` / `update_products` / a freshly-`create_category_fields`
> value** — those caches are stale and a rebuild **bakes the old (often empty) value into the index**.
> Symptom: `get_products_by_query` / a dashboard widget returns 0 or stale while `get_products_by_ids`
> and the DB are correct. That is an un-flushed read-through cache, **not** an "index quirk", and a
> host restart is NOT a reliable fix (the `dotnet run` parent/child trap means the bounce may not
> cold-start). Run the flush step below first, then build, then re-verify.

Run the enforced form — [`Build-DwProductIndex.ps1`](../../dw-data-access/scripts/Build-DwProductIndex.ps1),
an out-of-product script owned by [`dw-data-access`](../../dw-data-access/SKILL.md) — which carries
the flush-build-poll mechanics (the cache flush, the non-blocking POST, the freshness-guarded poll,
the Error-vs-first-build distinction, and the 10.28.x status-verb fallback). In-product the rebuild
is MCP `build_product_index` followed by `wait_for_product_index`.

The contract the script implements, kept here because extensions must honor it:

- `synchronous: true` in the BuildIndex body does NOT actually block — the POST returns before the
  build finishes, so treating a 2xx as "built" indexes against a stale/empty segment. Always poll.
- DW 10.26.x contract: no `Status`/`Idle` field — `State: Success|Warning|Error` on the index
  query, `LifecycleState: NeverBuilt|...|Completed|Failed` on the instance query. Live JSON is
  camelCase (the api.json catalog declares PascalCase); PowerShell access is case-insensitive.
- A never-built index reports `State=Error` while its FIRST build is still writing — treat Error
  as terminal only when the instance query's `LifecycleState` is `Failed`; otherwise keep polling.

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
