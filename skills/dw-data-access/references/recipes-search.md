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
`read_file` and `list_files` do reach it, so the round-trip read-back is in-product even though the write
is not.

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
`GET /Admin/Api/IndexStatusesAll`.

The in-product gate needs neither: pass the full file name including the `.index` extension on every
MCP call, and gate on a **non-zero `documentCount`** rather than on `completed:true`.

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
