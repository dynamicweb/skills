# Query expressions and execution — operators, sorting, paging, inert fields, build verbs

Field-validated DW10 knowledge of **authoring and executing** a product `.query` — expressions,
operators, sorting, result paging, inert index fields, and the build verbs' silent-success failure
modes. The lifecycle verbs (read, copy, name, relocate, delete, cache flush) are in
[`query-authoring.md`](query-authoring.md); the index file itself is owned by
[`index-management.md`](index-management.md).

## Contents

- [Authoring expressions](#authoring-expressions)
- [Operators: what the enum implies vs what matches](#operators-what-the-enum-implies-vs-what-matches)
- [Sorting](#sorting)
- [Reading results: paging that is not paging](#reading-results-paging-that-is-not-paging)
- [Fields that are declared but never populated](#fields-that-are-declared-but-never-populated)
- [Migrating a shop rename — repoint BEFORE the rebuild](#migrating-a-shop-rename--repoint-before-the-rebuild)
- [Build verbs: 200 is not "built"](#build-verbs-200-is-not-built)
- [Trap table](#trap-table)

## Authoring expressions

### Locate by path from the same read that drives the write

`QueryExpressionSave` treats an **unresolvable `Path` as "append"**, so a read-modify-write loop that
fails to match an expression silently creates duplicates instead of updating. Two things make the match
fail:

- **`QueryExpressionsByQueryId` returns the field DISPLAY name in `fieldName` when the field resolves in
  the index, and the raw system name when it does not.** Matching on the system name finds nothing.
- **`QueryExpressionDelete` renumbers the remaining siblings**, so a list of paths read once is stale
  after the first delete — a pre-read cleanup list starts failing partway through.

Rules: take paths from the same read that drives the write; delete **one at a time, re-reading every
round**; and assert the expression **count** before and after any "modify in place" operation — an
in-place edit that changes the count did something else.

### `QueryGroupExpressionSave` cannot create a group

**`Path` on that command is a LOCATOR, never an insertion point.** `Path:"0"` resolves to the ROOT group
and rewrites it in place — so `{Path:"0", Operator:"and", Negate:true}` answers `ok` and wraps every
existing clause in a `NOT`, taking the query from its real result set to the entire catalogue. The
`.query` file then carries `<GroupExpression Operator="And" Negate="True">`. There is no exposed
affordance for adding a child group through that verb; author nested OR/AND structure in the admin UI,
or through a tool that takes a real tree (below).

Snapshot the row count before **and** after every `QueryGroupExpressionSave`, and assert the root group
carries no `Negate` attribute. Recovery is a re-post with `Negate:false` — instant, no rebuild.

### Structure survives only where the surface carries a tree

An MCP-style create verb that takes a flat array of group expressions keeps **only the first group
structurally**: every later group's conditions are merged into the root `And` and its own
`operator`/`negate` are dropped. The written XML shows one flat `<GroupExpression Operator="And">` with
no nesting and no negation — so an intended OR-list becomes an impossible AND (0 rows) and an intended
NOT-group becomes its own positive (0 rows). Both report success.

Use the expression-replacement surface that takes a real tree (groups keyed by `groupKey` /
`parentGroupKey` / `operator` / `negate`, expressions assigned to a group key) for **anything with
alternation or negation**, and reserve the flat create verb for single flat `AND` predicates. Verify by
reading the expressions back and asserting the group shape, then asserting each query's row count
against a recorded expectation.

### `Source=` is decorative and never rewritten

The `.query` XML stores `<FieldExpression Field="X" Source="Y" />`. `QueryExpressionSave` sets `Field`
from the model and **leaves `Source` at whatever the expression was created with**. The query resolves
on `Field`, so nothing breaks — but a field-name migration stays un-greppable, and re-saving does not
clear it. To clear `Source`, **delete the expression and re-add it** at its parent group path; the fresh
write sets `Source = Field`. Guard on the row count (nested OR groups survive a delete-and-re-add of
their children).

### A numeric predicate needs a typed constant

**Every authoring surface writes `Type="System.String"` constants — including the admin query editor.**
The editor's Type dropdown (Code / Constant / Macro / Parameter / Term) selects the value *source*, not
the CLR type, so a numeric Lucene field is always compared against a string term and matches nothing.
The field itself is fine: the same file with `Type="System.Int32"` on the constant returns the expected
rows.

So a numeric predicate is authorable only by writing the `.query` XML by hand. Sequence, given that the
agent account often cannot overwrite files under the site tree:

1. Snapshot the query (expressions, sort, and its `.configuration` contents).
2. Delete it through the query verb — that runs as the app pool and *can* remove the file.
3. Write a NEW file carrying the **same `<Query ID>` and `Name`**, so every dashboard tile, screen-preset
   binding and favourite that keys off the GUID survives.
4. Recreate the `.configuration` sidecar — the delete removed it, and without it the worklist silently
   loses its bound columns and its open-in-edit behaviour.
5. Flush the query cache.

Assert the row count moves **off the degenerate value** (a string constant on a numeric field returns 0
or everything), and assert the configuration reads back non-null.

### `folderPath` on a create is a server-side ABSOLUTE path

A create verb taking `folderPath` wants the **server-side absolute filesystem path** to the SmartSearches
folder. A relative path is neither resolved nor rejected: the save answers `ok` and persists nothing, the
query never appears in a list, and the delete verb has nothing to delete. Always pass the absolute path,
and **assert the query is readable back by name before treating the create as done.**

## Operators: what the enum implies vs what matches

The product index **analyses** `Number` and other string fields, and a comma-separated right-hand side is
matched as one opaque term rather than split into alternatives. Both facts make the intuitive operator
choice the wrong one:

| Predicate shape | What actually happens |
|---|---|
| `Field In "a,b,c"` | Unreliable across builds — on one it matches **zero** (the CSV is one term); on another the platform **normalises it into an Or-group of per-value `Equal` nodes**, so the admin UI shows N hardcoded literals where one compact expression was authored |
| `Field MatchAny "a,b,c"` | matches **zero** — a comma-joined value is a single opaque term no document carries |
| `Field MatchAny "a"` | correct — single-value `MatchAny` is the reliable form |
| `Field Equal "a"` | exact and reliable on an analysed field |
| `Field Contains "a,b"` | analyser-dependent; over-matches on tokenised fields |

**Express alternation as an Or child group of single-value nodes**, authored through the tree-taking
surface. Two consequences worth stating separately:

- **Exact SKU matching needs `Equal`** (or an Or-group of `Equal`s), never `In`/`MatchAny` with a CSV.
- **A literal value list does not belong in a shipped query.** Even where `In` works, the admin UI
  renders the expanded per-value form, so anyone opening the query sees hardcoded literals. Key
  defect worklists on a **steward-set flag field** instead, so the query reads as a rule.

## Sorting

**`QuerySave` persists `SortOrder` verbatim without validating the field against the source index
schema.** An unresolvable sort field is dropped at execution time and the rows come back in natural index
order — while the readback echoes the sort exactly as saved and the admin overview reports a sort
parameter count of 1. Nothing reports an error, so a "worst first" list looks configured and correct.

- Use the index **system** name, including the pipe form for rule-scoped fields (`CompletionRule|<id>`),
  matching the same system-name-on-write rule that governs expression field names.
- The property name a result row projects is **not** a sortable field name.
- Assert monotonicity over the **whole** result set (below), not the first page — a silently dropped sort
  fails that immediately.

## Reading results: paging that is not paging

**The product-query execution verb accepts `PagingSize` and honours no offset at all.** `PageIndex`,
`Page`, `PageNumber`, `PageSize`, `Skip`, `Offset`, `StartIndex` are all accepted (unknown query-string
parameters are ignored rather than rejected) and every one of them returns page 1 — while the model
computes and returns `totalPages`, which makes the endpoint look paged. A harness that walks a result set
page by page re-reads page 1 forever.

- Read the whole set with **`PagingSize` greater than `totalCount`** and evaluate over the full array.
- Guard against a silent re-implementation later: assert that two GETs differing only in `PageIndex`
  return the identical first row — if they ever differ, paging exists and the workaround can go.

**The field-definition verb pages at a default 96 while reporting the real `totalCount`.** A
"does the field exist in this index" membership test therefore reports FALSE for any field that sorts
late — the impossible-looking result where *no* field of a whole family exists. Always pass `PagingSize`,
and assert `data.Count == model.totalCount` **before** any membership test.

## Fields that are declared but never populated

A field can appear in the index field list and in the expression picker and still be written by nothing.
The signature is a predicate that returns either **0 rows or ALL rows whatever polarity you pick**, with
no error:

- **Translation-shaped fields are schema-only when the builder skips translations.** Read the index's
  own settings block before designing any per-language query — the schema extender declares the fields
  regardless of whether the builder populates them.
- **A workflow-state field can be declared and never written.** Simultaneously non-empty (`IsEmpty` → 0)
  and unmatchable by every operator (`Equal`, `MatchAny`, `Contains`, `GreaterThan` → 0) is exactly that
  signature. The id-shaped variants are frequently not index fields at all, so a clause on one is
  silently dropped and the query returns the whole catalogue. Count that data with a SQL-backed widget
  over the products table instead, and accept that such a tile cannot drill through.

**The standing check before shipping any predicate:** `count(field = X) + count(field ≠ X)` equals
`count(no predicate)`, and neither side is degenerate. A field that fails it is inert, whatever the picker
shows.

## Migrating a shop rename — repoint BEFORE the rebuild

The `DATAMODEL_<shop name>` index **field definition** is derived from live shop metadata and renames the
instant the shop save commits; the built **documents** are what lag. That asymmetry decides the order:

- A query left on the **old** token resolves to nothing, and an orphaned `MatchAny` **fails OPEN** — every
  such query matches the whole catalogue for the entire duration of the rebuild.
- A query repointed to the **new** token resolves to a real, currently-empty field and returns 0 — it
  fails CLOSED.

So: **shop save → repoint every `.query` expression and every dynamic-structure level row → full rebuild
→ assert every row count equals its pre-rename snapshot.** Verify the new token against the index field
list afterwards rather than trusting a spaces-to-underscores transform, and grep the repository for the
old token (remembering `Source=` above, which needs a delete-and-re-add to clear).

## Build verbs: 200 is not "built"

Three independent ways a build verb reports success and leaves the index the queries read untouched.

- **`BuildName` is the name of a BUILDER registered on that index, not a free label.** Resolve it from
  `IndexBuildersByRepositoryAndIndexName` — never post a guessed string. An unresolvable `BuildName` has
  been observed to `404`, to `500 "Unable to load build '<name>'"`, **and** to answer `{"status":"ok"}`
  and build nothing, on different hosts and verbs. Since the failure mode is not predictable, resolving
  the name **and** asserting build freshness afterwards is mandatory either way.
- **Build the index the QUERY names.** A solution commonly carries several product index instances, and a
  convenience "rebuild the product index" surface targets its own default (`Products/Products`) while
  every query's `sourceIndex` names a different one (`ProductsBackend|Products.index`). The rebuild then
  never touches what the queries read, so freshly written field values stay invisible across repeated
  rebuilds and a recycle. Read `sourceIndex` off the queries and post
  `BuildIndex {Repository, IndexName, BuildName}` for that one.
- **Instance health is a separate state the verb does not report.** `200 {"status":"ok"}` means the
  request was accepted and ran; the instance can still sit at "Error — no healthy instance is available",
  and repeated builds advance `lastRun` while the status word never changes. Once an index reports a
  blocking repair candidate, the repository-level build is a no-op regardless of `BuildName` — only
  `BuildIndexInstance` targeting the next build target clears it.

Definition of done for any rebuild: read the instance **status** back (verbatim), assert no blocking
repair candidate, assert `lastRun` is newer than the invocation, and then run a query whose predicate
depends on a freshly written field and assert its count moves off "matches everything".

## Trap table

| Symptom | Cause | Do |
|---|---|---|
| A read-modify-write loop creates duplicates | an unresolvable `Path` appends | take paths from the same read that drives the write |
| Row count jumps to the whole catalogue after a group save | `Path:"0"` rewrote the ROOT group; `Negate` inverted everything | snapshot counts around every group save; re-post with `Negate:false` |
| An OR-list or NOT-group returns 0 | a flat create surface dropped the nested group | author through the tree-taking surface |
| A numeric predicate returns 0 or everything | the constant is `System.String` | hand-write the `.query` with a typed constant; recreate the sidecar |
| A `create` answers `ok` and the query does not exist | `folderPath` was relative | pass the absolute server-side path; read it back |
| A sort reads back correctly and the rows are unsorted | the sort field does not resolve in the index | use the index system name; assert monotonicity over the full set |
| Page 2 equals page 1 | the execution verb has no offset | read with `PagingSize > totalCount` |
| A field-existence check reports FALSE impossibly | the field-definition verb pages at 96 | pass `PagingSize`; assert `data.Count == totalCount` |
| Every polarity of a predicate returns 0 or everything | the field is declared but never populated | run the complementary-count check before shipping any predicate |
| A rebuild reports `ok` and nothing changes | wrong `BuildName`, wrong index instance, or a blocking repair candidate | resolve the builder, build the index the query names, read the instance status back |
