# Out-of-product recipes — Search

This reference holds the out-of-product recipes for search (indexes, repositories, index instances, queries and index builds): Management API
commands at `/admin/api/...`, serializer layers, and direct SQL. The in-product skills for this
area are `dynamo: true` and carry no instruction on those surfaces, so they keep a one-line pointer
here instead of the recipe.

Every recipe names its surface in the repo convention: MCP tools `snake_case` in backticks,
Management API commands `PascalCase` in backticks with the route on first use in this file,
serializer operations by command or by layer and mode, and `SQL` labelled as such in a fenced `sql`
block. Every SQL recipe states three things inline — why the higher surfaces do not cover it, that
it is **local installs only**, and the cache flush or host restart it owes.

## Contents

- [Getting an authored `.index` file onto a hosted install](#getting-an-authored-index-file-onto-a-hosted-install)
- [Re-running an index build on the Management API](#re-running-an-index-build-on-the-management-api)
- [Storefront facets are three files under the repository folder](#storefront-facets-are-three-files-under-the-repository-folder)
- [Resolving the builder before posting `BuildIndex`](#resolving-the-builder-before-posting-buildindex)
- [Building a two-instance index such as Files](#building-a-two-instance-index-such-as-files)
- [Finding query GUIDs present in both query trees](#finding-query-guids-present-in-both-query-trees)
- [Currency integrity check before an index build](#currency-integrity-check-before-an-index-build)
- [Flushing the query cache with a missed `QueryById` read](#flushing-the-query-cache-with-a-missed-querybyid-read)
- [Relocating a query with `QueryMove`](#relocating-a-query-with-querymove)
- [Filling an empty query `Source` element](#filling-an-empty-query-source-element)

## Getting an authored `.index` file onto a hosted install

The `.index` is XML on disk under `Files/System/Repositories/<Repo>/`, and the filesystem is the only
surface that authors it — no Management API verb and no MCP tool writes an index schema. On a local
install, edit the file in place.

**Surface: Management API, multipart.** On a hosted install where the file archive is not mounted:

```
POST /Admin/Api/Upload        (multipart/form-data, the .index file, targeted at the repo folder)
```

**`upload_file` cannot do this.** The tool restricts writes to `/Files/Images` (media) and
`/Files/Files/Integration` (integration source files) and refuses everything else, template and config
locations explicitly included — so the repository folder has no in-product write surface at all.
`read_file` and `list_files` do not reach it either: both are restricted to `/Files/System/Styles`,
`/Files/Templates` and `/Files/Images`, so neither the write nor the read-back is in-product.

Either way the schema rules stay invisible from every read surface: `BuildIndex` answers
`{"status":"ok"}`, `IndexStatusesByRepository` answers "All instances are fine", and
`FieldDefinitionBasesByRepositoryAndIndexName` lists the field exactly as declared — while the field
is not in the index at all.

## Re-running an index build on the Management API

MCP `build_product_index`, `wait_for_product_index` and `get_product_index_status` default
`indexName` to `Products`, while the real repository index file is `Products.index`. The default
therefore addresses a nonexistent index and **succeeds vacuously**: `wait_for_product_index` answers
`{"completed":true,"message":"Full index build completed"}` with the index untouched, and the status
comes back `{"status":"Idle"}` carrying no `documentCount` and no `lastBuild`.

**Surface: Management API.** The same wrong name here does not succeed vacuously:

```
POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full","BuildType":"Full"}
```

A wrong `IndexName` answers not-found, which makes this the confirming re-run for a build that
"worked" through MCP and changed nothing — worth doing before suspecting the schema. Gate on
`GET /Admin/Api/IndexStatusesAll`. It is also the build a restore owes: restored instance files are
not served until a Full build runs ([dw-search-indexing](../../dw-search-indexing/SKILL.md)
`index-management.md` §"Restored index files are not served until a Full build runs").

The in-product gate needs neither: pass the full file name including the `.index` extension on every
MCP call, and gate on a **non-zero `documentCount`** rather than on `completed:true`.

The enforced flush-build-poll form is the [`Build-DwProductIndex.ps1`](../scripts/Build-DwProductIndex.ps1)
script: the cache flush, the non-blocking POST, the freshness-guarded poll, the Error-vs-first-build
distinction and the 10.28.x status-verb fallback. The contract it implements is stated in the
`dw-search-indexing` skill's index-management reference.

## Storefront facets are three files under the repository folder

A PLP filter sidebar is **file-only work**. No MCP tool and no Management API verb edits a facet or an
index schema: the query tools (`get_index_queries`, `get_index_query_expressions`,
`replace_index_query_expressions`, `delete_index_query_expressions`, `delete_index_queries`) reach the
query's *expressions* and nothing else. A branded catalogue that inherits the shipped facets therefore
renders **no filter sidebar at all** while every structural assert passes — 200, a full card count, no
error markup, an index build reporting success — because the facets are defined over fields the new data
has no values for.

**Surface: the filesystem** (local install), or the multipart upload verb above (hosted). Three files
under `Files/System/Repositories/<Repo>/`, one entry each per facet:

| File | The entry a facet needs |
|---|---|
| `Products.index` | one `<Field Source="…" Name="<X>_Facet" SystemName="<X>_Facet" Analyzed="false"/>` inside `<Schema><Fields>` |
| `Products.query` | one `<Parameter Name="<X>" Type="System.String[]"/>` plus one `<BinaryExpression Operator="In">` binding the `<X>_Facet` field expression to the `<X>` parameter |
| `Products.facets` | one `<Facet Name="…" Field="<X>_Facet" QueryParameter="<X>">` block |

**The `Source` attribute spells the two kinds of custom field differently**, and the wrong spelling fails
silently — the facet renders nothing, the build still answers success with a full document count:

| Field kind | `Source` spelling |
|---|---|
| Category field | the fully qualified authoring name, `ProductCategory|<Category>|<field>` |
| Global custom product field | `CustomField_<systemName>` — the **bare system name resolves to nothing** |

**A `<Field>` takes exactly one `Source`.** An attribute modelled on several categories (the same
measurement declared on three of them) cannot be faceted as one field without a copy field or a duplicated
scalar; plan the data model with that in mind rather than discovering it at facet time.

- **Why the higher surfaces do not cover it** — no tool and no verb reaches a facet or an index schema.
- **Local installs only** for the in-place edit; hosted installs use the multipart upload above.
- **The debt it owes** — a full index rebuild, then a PLP fetch asserting both the facet buckets and one
  filtered URL returning the expected product count. The rebuild alone is not the assert.

## Resolving the builder before posting `BuildIndex`

In-product home: [dw-search-indexing](../../dw-search-indexing/SKILL.md) `index-management.md`
§"Repositories, Indexes, and Queries", which carries why an unresolvable builder name is not
predictable (`404`, `500 "Unable to load build '<name>'"`, or `200` that builds nothing).

**Surface: Management API.** Read the builders registered inside the index file, then post the build
with a `BuildName` taken from that list and the index FILE name, extension included:

```
GET  /admin/api/IndexBuildersByRepositoryAndIndexName?Repository=Products&IndexName=Products.index
POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full","BuildType":"Full"}
```

The sibling index reads do not share parameter names, and the wrong one answers
`400 "Unable to load query parameters"`, which reads as a missing verb:

| Verb | Parameter names |
|---|---|
| `IndexByRepositoryAndName` | `Repository` + `IndexName` |
| `IndexBuildersByRepositoryAndIndexName` | `Repository` + `IndexName` |
| `IndexInstancesByRepositoryAndIndex` | `RepositoryName` + `IndexName` |

A full build outruns a 120s client timeout, so fire the POST and verify out of band on
`IndexStatusesAll` (see "Re-running an index build on the Management API" above).

- **Why the higher surfaces do not cover it**: `build_product_index` and `wait_for_product_index`
  take `repositoryName`, `indexName` and optional `productIds`, and no builder name, so a builder
  other than the tool's default has no in-product route and the builder list has no MCP read.
- **Hosted installs included**: these are API calls, not SQL.
- **The debt it owes**: flush the product caches before the build after any value write, and assert a
  non-zero document count afterwards.

## Building a two-instance index such as Files

In-product home: [dw-search-indexing](../../dw-search-indexing/SKILL.md) `index-management.md`
§"The Files index: `StartFolder` is the library, and keywords live in the file".

**Surface: Management API.** Index instances build one at a time: each `BuildIndex` call rebuilds only
the currently-offline instance and then swaps, so a two-instance index needs two calls, and the gate
is the status read, never the build response:

```
POST /admin/api/BuildIndex {"Repository":"<Repo>","IndexName":"Files.index","BuildName":"<builder from the index file>"}
POST /admin/api/BuildIndex {"Repository":"<Repo>","IndexName":"Files.index","BuildName":"<builder from the index file>"}
GET  /admin/api/IndexStatusesAll     -> success / "All instances are fine" for the repository
```

Resolve `<Repo>` and the builder name as in the section above. Precreate the index `StartFolder`
directory first: on a fresh clone the build otherwise fails with `Directory '...' does not exist` and
the whole index reports no healthy instance.

- **Why the higher surfaces do not cover it**: `build_product_index` and `get_product_index_status`
  are documented for the product index only; no MCP tool is documented to build or read a Files index.
- **Hosted installs included**: these are API calls, not SQL.
- **The debt it owes**: none beyond the second call and the status gate.

## Finding query GUIDs present in both query trees

In-product home: [dw-search-indexing](../../dw-search-indexing/SKILL.md) `index-management.md`
§"Dashboard query location", which carries the cache-overwrite mechanism and the fix.

**Surface: the filesystem** (local install). Lines present in both sorted lists are the duplicates:

```bash
grep -h 'Query ID=' wwwroot/Files/System/Repositories/Products/**/*.query | sort > /tmp/repo.txt
grep -h 'Query ID=' wwwroot/Files/System/SmartSearches/Ecommerce/Shared/**/*.query | sort > /tmp/shared.txt
diff /tmp/repo.txt /tmp/shared.txt  # identical lines = duplicates
```

- **Why the higher surfaces do not cover it**: `list_files` and `read_file` are restricted to
  `/Files/System/Styles`, `/Files/Templates` and `/Files/Images`, so neither query tree is readable
  in-product.
- **Local installs only**: on a hosted install no verified read surface lists both trees, so the
  comparison goes to the user.
- **The debt it owes**: none, it is read-only; the fix (`QueryMove` or a delete) owes the query cache
  flush below.

## Currency integrity check before an index build

In-product home: [dw-search-indexing](../../dw-search-indexing/SKILL.md) `index-management.md`
§"Currency integrity is an index-build precondition".

**Surface: `SQL`**, read-only. Both counts must be `0` before a product index build:

```sql
SELECT COUNT(*) FROM EcomCurrencies WHERE CurrencyRate = 0;                    -- must be 0
SELECT COUNT(*) FROM EcomCountries c                                           -- must be 0
 WHERE c.CountryCurrencyCode NOT IN (SELECT CurrencyCode FROM EcomCurrencies);
```

- **Why the higher surfaces do not cover it**: they do, by hand. `get_currencies` returns every
  currency with its rate and `get_countries` every top-level country with its currency, and comparing
  the two lists is the same check; the SQL is the set-based form of it.
- **Local installs only**: on a hosted install, run the comparison over `get_currencies` and
  `get_countries`.
- **The debt it owes**: none, it is read-only. The fix writes currencies through `CurrencySave`, never
  raw SQL, because currencies are cache-coupled.

## Flushing the query cache with a missed `QueryById` read

In-product home: [dw-search-indexing](../../dw-search-indexing/SKILL.md) `query-authoring.md`
§"Flush the query cache without a restart", which carries why no `CacheInformationRefresh` type name
reaches the `Searching:Queries` cache.

**Surface: Management API.** A read of a GUID that does not exist misses the cache and re-runs the
cache initialisation:

```
GET /admin/api/QueryById?Id=<a GUID that does not exist>
-> 400 "Unable to load query parameters for query type: QueryById"   (expected; the refresh already ran)
```

Run it between a file rename or move and the next `Query*` verb, then assert that `QueryById` on the
real id reports the new `fileName`.

- **Why the higher surfaces do not cover it**: no MCP tool is documented to refresh the query cache.
- **Hosted installs included**: this is an API call, not SQL.
- **The debt it owes**: none; it is the flush. No recycle and no restart.

## Relocating a query with `QueryMove`

In-product home: [dw-search-indexing](../../dw-search-indexing/SKILL.md) `query-authoring.md`
§"Relocating", which carries what the verb moves and the per-move asserts.

**Surface: Management API.** `FilePath` names the destination folder, not a file:

```
POST /admin/api/QueryMove {"Id":"<query GUID>","FilePath":"/Files/System/SmartSearches/Ecommerce/Shared/<subfolder>"}
```

- **Why the higher surfaces do not cover it**: `create_or_update_product_queries` takes a
  `folderPath`, but its description documents no move of an existing query and nothing about the
  `.configuration` sibling, so it is not a substitute for the move.
- **Hosted installs included**: this is an API call, not SQL.
- **The debt it owes**: none for the cache (the verb writes it); assert zero GUIDs present in both
  trees afterwards.

## Filling an empty query `Source` element

MCP `create_or_update_product_queries` saves the `.query` XML with `<Source Repository="" Item="" />`
left empty. A query with an empty source reads no index, so fill the element before the index build.

**Surface: the filesystem** (local install). Open the saved `.query` file under
`wwwroot/Files/System/Repositories/<repository>/` and set both attributes: `Repository` to the
repository name and `Item` to the index file the query reads (for the product repository,
`Products` and `Products.index`).

- **Why the higher surfaces do not cover it**: no MCP tool writes a `.query` file, and `list_files`
  and `read_file` are restricted to `/Files/System/Styles`, `/Files/Templates` and `/Files/Images`,
  so the repository folder is neither writable nor readable in-product.
- **Local installs only**: no verified hosted write reaches the repository folder for a `.query`
  file, so on a hosted install the fix goes to the user.
- **The debt it owes**: the query cache flush in "Flushing the query cache with a missed
  `QueryById` read" above, then the index build.
