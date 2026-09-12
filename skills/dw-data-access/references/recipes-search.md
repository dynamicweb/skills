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

## Getting an authored `.index` file onto a hosted install

The `.index` is XML on disk under `Files/System/Repositories/<Repo>/`, and the filesystem is the only
surface that authors it — no Management API verb and no MCP tool writes an index schema. On a local
install, edit the file in place.

**Surface: Management API, multipart.** On a hosted install where the file archive is not mounted:

```
POST /Admin/Api/Upload        (multipart/form-data, the .index file, targeted at the repo folder)
```

The MCP equivalent is `upload_file` into `Files/System/Repositories/<Repo>/`, which is inside the
in-product surface and is the route to prefer wherever the tool is present; `read_file` and
`list_files` give the round-trip read-back. Reach for the multipart verb only where MCP is absent.

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
