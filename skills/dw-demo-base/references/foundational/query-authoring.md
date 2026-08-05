# Foundational candidate → dw-search-indexing

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 knowledge of the `Query*` Management API verbs —
> reading, copying, naming, relocating, expressing and executing a `.query` — staged here for a
> future fold-up into `dw-search-indexing`. No demo/customer content. The index *file* side (schema,
> builders, facets, the rebuild recipe) is owned by [`search-indexing.md`](search-indexing.md); this
> file owns the query lifecycle verbs; expression authoring and execution are in
> [`query-expressions.md`](query-expressions.md).

## Contents

- [Which read verb is authoritative](#which-read-verb-is-authoritative)
- [Flush the query cache without a restart](#flush-the-query-cache-without-a-restart)
- [Lifecycle: copy, name, relocate, delete](#lifecycle-copy-name-relocate-delete)
- [Trap table](#trap-table)

Expressions, operators, sorting, result paging and the build verbs are in the sibling file
[`query-expressions.md`](query-expressions.md).

## Which read verb is authoritative

A query has **two backing stores** — the `.query` XML file on disk and a sibling `.configuration`
record — and three read verbs project different mixtures of them. They disagree, permanently, and
whichever one you happen to call decides what you believe:

| Verb | Projects | Authoritative for |
|---|---|---|
| `QueryById?Id=<guid>` | the `.query` FILE | file-backed properties: `fileName`, `folderPath`, `sortOrder`, expressions |
| `QueryOverviewById?Id=<guid>` | the merged query + configuration record | a seed model for `QuerySave` |
| `QueryConfigurationByQueryId?QueryId=<guid>` | the `.configuration` record | completeness rules and languages, screen presets, append/open flags |

- **The read verb is `QueryConfigurationByQueryId`, not `QueryConfigurationById`** — the Management
  API dispatches on the query CLASS name, and the parameter here is `QueryId`, not the model's own
  `Id`. Every `*ById` spelling answers `400 Unknown query`, and passing `Id=` to the correct verb
  answers `400 "QueryId: The value is required."`. The save side *is* `QueryConfigurationSave`, which
  is what makes the asymmetry easy to miss.
- **Configuration properties read stale from `QueryById`.** `appendCompletionExpressions` and the
  completeness language set live in the configuration, so the file-backed reader returns the default —
  frequently the exact opposite of what was saved. Assert configuration values against
  `QueryConfigurationByQueryId` only.
- **`QueryOverviewById` exposes `completenessLanguages` (empty) beside the configuration's
  `completionLanguages` (populated)** — two names for one concept, one of which is always wrong.
- **`isProductQuery` writes `true` and reads back `false` from every verb.** Do not gate anything on it.
- **Seed a `QuerySave` model from `QueryOverviewById`, never from `QueryById`** — the file-backed
  reader's stale values get written back over a correct configuration otherwise.

## Flush the query cache without a restart

`QueryHelper.InitQueriesCache` populates a static dictionary from `SmartSearches` first, then
`Repositories`, and never removes entries. **No `CacheInformationRefresh` type name reaches it**: that
command resolves an `ICacheStorage` implementor, every implementor is an entity service, and none owns
the `Searching:Queries` key. A restart is nevertheless **not** required.

**`GET /Admin/Api/QueryById?Id=<a GUID that does not exist>` re-initialises the cache as a side
effect.** `QueryHelper.GetQueryById` re-runs `InitQueriesCache` on a cache **miss**, so the throwaway
GUID always misses and always refreshes. The `400 "Unable to load query parameters for query type:
QueryById"` it answers is expected — it comes from the model being null *after* the refresh ran. Any
call that reaches `QueryHelper.GetAllQueries` (for example opening a widget's Query dropdown) does the
same unconditionally.

**Why it is needed:** the `Query*` verbs update the cache themselves (`QueryMove`, `QuerySave` call
`SetQueryToCache`), but a **raw file rename or move through the file verbs does not** — the cache keeps
the old `fileName`, and the next `QuerySave` writes the file back to the OLD path. Flush between a file
operation and the next query verb.

Definition of done: rename a `.query` through the file verbs, assert `QueryById.model.fileName` still
reports the OLD name, flush, assert it reports the NEW name. No recycle, no version bump.

## Lifecycle: copy, name, relocate, delete

### Minting a properly named copy

`QueryCopy` always produces `Copy of <QueryName>` for **both** the file and the `Name` attribute, and
`QuerySave` **never renames the file** — it saves to `query.FileName` for an existing `Id`, so the
on-disk name and the `Name` attribute can legally diverge. `QuerySave` also runs a duplicate-name guard
that checks the *filesystem*: if a file already carries the target name it returns
`400 "A query with the same name already exists"` — which fires against the query's **own** file when
the rename happened first. Order the operations so the guard cannot see itself:

1. `QueryCopy {Id, FilePath, QueryName}` — yields `Copy of <name>` and a new GUID.
2. `QuerySave` the intended `Name` **while the file is still called `Copy of …`** — no file carries the
   target name yet, so the guard passes.
3. Rename **both** siblings through the file verbs: the `.query` **and** its `.configuration`.
4. Flush the query cache (above).

Recovery when the rename already happened: rename the pair to a temporary name, flush, `QuerySave` the
`Name`, rename back, flush. Assert the cached `fileName` follows each rename *before* the `QuerySave`,
or the save lands on the old path.

Definition of done: both files carry the intended base name, the file's own `Name` attribute equals it,
`QueryById` returns that name and the new `fileName`, and the row count is unchanged from the source.

### Relocating — `QueryMove`, never a file move

`POST /Admin/Api/QueryMove {Id, FilePath}` where `FilePath` is the destination **folder** (virtual, e.g.
`/Files/System/SmartSearches/Ecommerce/Shared/<subfolder>`). It refuses same-place and existing-target,
creates the destination folder if absent (no folder-create verb needed), moves the `.query`, moves the
`.configuration` sibling, updates `query.FileName` and writes the cache.

- **The `.configuration` sibling is resolved by the query file's base name** — a raw filesystem move
  strands it, silently dropping the list/edit screen presets, completeness rules and languages, and the
  append/open flags.
- **MOVE, never COPY.** A GUID present in both trees resolves to the `Repositories` copy (it loads
  second and overwrites), so a "copy to Shared" leaves the original winning and the relocation inert.
- Subfolders of `Shared` are legal and render as tree nodes.
- For a query that is both feed-backing and widget-backing, **split it**: `QueryCopy` a feed-only twin
  with a new GUID at the repository root and repoint the feed at it, then `QueryMove` the original GUID
  to Shared.

Per move, assert: source gone, destination `.query` **and** `.configuration` present, `folderPath` under
the shared path, result count unchanged, and **zero GUIDs present in both trees**.

### Deleting

**`QueryDelete` resolves by GUID, so a duplicate-GUID pair can remove the sibling file instead of — or
as well as — the named one.** A sweep that deletes by GUID therefore removes files it has not reached
yet, and the loop then fails on a missing file. Inventory `Query ID`s and **assert uniqueness before
deleting anything**, re-stat every file immediately before touching it, and write the loop to tolerate a
file vanishing underneath it.

Deleting a query also removes its `.configuration` sidecar. Anything that keyed off the query's screen
presets or completeness binding loses it silently — recreate the sidecar whenever a delete-and-rewrite
is used to edit a file in place.

## Trap table

| Symptom | Cause | Do |
|---|---|---|
| `400 Unknown query: QueryConfigurationById` | the read verb is `QueryConfigurationByQueryId` | use it, with `QueryId=` |
| Two readers disagree about the same query | file-backed vs configuration-backed projections | read configuration values from `QueryConfigurationByQueryId` only |
| `QuerySave` writes to the old path after a file rename | the query cache still holds the old `fileName` | flush with a throwaway-GUID `QueryById` GET |
| `400 "A query with the same name already exists"` on its own file | the guard checks the filesystem; the rename happened first | save the `Name` before renaming the files |
| A relocated query's presets and completeness rules vanish | the `.configuration` sibling was stranded by a raw file move | relocate with `QueryMove` |
| A deleted query takes an unrelated file with it | `QueryDelete` resolves by GUID | assert GUID uniqueness before any sweep |
| `Description` on a repository query never persists | the repository `.query` XML has no `Description` element | narrate on the widget subtitle instead |
