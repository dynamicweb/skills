# MCP query tools — PIM product queries and repository index queries

The MCP-tool-level contract for authoring and executing a `.query` file, at the layer normal
agent tool calls operate on. This is the companion to [query-authoring.md](query-authoring.md)
and [query-expressions.md](query-expressions.md), which document the same query family at the
raw Admin Management-API layer (`Query*`/`QueryExpression*` HTTP verbs) with their own set of
field-validated landmines — read those when working against that surface directly (e.g.
building a demo host). This file covers the MCP tool surface a normal agent has access to.

## Contents

- [Product query vs repository index query — get this right first](#product-query-vs-repository-index-query--get-this-right-first)
- [Tool map](#tool-map)
- [The read–edit–verify loop (mandatory for every expression change)](#the-readeditverify-loop-mandatory-for-every-expression-change)
- [Value types — macros are not constants](#value-types--macros-are-not-constants)
- [Worked example: user-assortment visibility](#worked-example-user-assortment-visibility)
- [Index must be built before queries return data](#index-must-be-built-before-queries-return-data)
- [Facets bind to query parameters](#facets-bind-to-query-parameters)
- [Deleting a query safely](#deleting-a-query-safely)
- [Dashboard binding](#dashboard-binding)
- [Query configuration (admin UI settings)](#query-configuration-admin-ui-settings)

## Product query vs repository index query — get this right first

These are two different things, and confusing them is how the wrong query gets edited or
deleted:

- **Product query (PIM)** — lives in the PIM smart-search folder, shown on the **Products >
  Queries** screen. Managed by the `*_product_quer*` tools (`get_product_queries`,
  `create_or_update_product_queries`, `delete_product_queries`,
  `*_product_query_expressions`).
- **Repository index query** — lives under a **repository** (e.g. **ProductsFrontend** drives
  the storefront product list; also Content/Files). Shown in the Repositories tree, not the
  Products > Queries screen. Managed by the `*_index_quer*` tools (`get_index_queries`,
  `delete_index_queries`, `*_index_query_expressions`). Each result reports its `Repository`.

They share the same `.query` file format but differ in **location, accessor, UI surface, and
purpose**. The product-query tools are scoped to PIM and will REFUSE an id that resolves to a
repository index query (and vice versa) — so if a tool says "this is a repository index query,
use the index-query tools", switch tool families, don't fight it. When the user points at
something in the Repositories tree (ProductsFrontend › … › a query), that is an **index
query** — use `get_index_queries`.

Note: adding a condition with `create_or_update_product_queries` does NOT corrupt or
restructure a query — it is a safe add-only merge (see below). Adding an expression is not a
risky operation.

## Tool map

| Intent | Tool |
|---|---|
| List queries, names, IDs, completion rules (PIM) | `get_product_queries` |
| Inspect one query's exact expression tree (PIM) | `get_product_query_expressions` |
| Create a new query / rename / change source index / completion config (PIM) | `create_or_update_product_queries` |
| ADD a condition without touching anything else (PIM) | `create_or_update_product_queries` (add-only merge) |
| Restructure: change AND/OR grouping, move conditions, rewrite the tree (PIM) | `replace_product_query_expressions` |
| Remove specific conditions (PIM) | `delete_product_query_expressions` |
| Delete a whole product query (PIM, requires id **+** exact name) | `delete_product_queries` |
| List / edit / delete a **repository index query** (e.g. ProductsFrontend storefront) | `get_index_queries`, `*_index_query_expressions`, `delete_index_queries` |
| Rebuild the product index | `build_product_index` |
| Check build state / last run / doc count | `get_product_index_status` |
| Block until a build finishes (max 300s) | `wait_for_product_index` |

**`create_or_update_product_queries` is ADD-ONLY for expressions.** It never removes or moves
persisted conditions and never changes the root group's operator. If the user wants anything
removed, regrouped, or "cleaned up", use `replace_product_query_expressions` or
`delete_product_query_expressions` instead. Never claim a condition was removed after calling
the add-only tool — it was not.

## The read–edit–verify loop (mandatory for every expression change)

Identical discipline for both query families — NodeKeys are positional and shift after every
change:

1. **Read**: call `get_product_query_expressions(queryId)` (or `get_index_query_expressions`
   for an index query). It returns groups (`GroupKey`/`ParentGroupKey`; root = GroupKey 0,
   ParentGroupKey -1) and conditions with positional `NodeKey`s.
2. **Edit**:
   - Targeted removal → `delete_product_query_expressions(queryId, nodeKeys)` (or the index
     equivalent).
   - Anything structural → `replace_product_query_expressions(queryId, groups, expressions)`
     (or `replace_index_query_expressions`): send the COMPLETE desired tree. Keep existing
     conditions by referencing their `SourceNodeKey` (this preserves their exact typed
     values — required for Term and Code conditions, which cannot be recreated). Define new
     conditions with Field/Operator/ValueType/Value. Anything not referenced is removed.
3. **Verify**: call the `get_*_query_expressions` read again and confirm the tree matches the
   intent before reporting done. NodeKeys are positional and shift after every change — never
   reuse keys from an earlier read.

## Value types — macros are not constants

Every condition value has a `ValueType`:

- **Constant** — literal text/number ("100", "Active").
- **Macro** — evaluated at query time, e.g. `Dynamicweb.UserManagement.Context:AssortmentIDs`.
  Anything of the form `Namespace.Something:Field` is a macro. A macro saved as Constant is
  compared as literal text and silently never matches — this is a classic "the filter does
  nothing" bug.
- **Parameter** — bound to a request parameter by name.
- **Term / Code** — typed/index-schema-bound values that can only be preserved via
  `SourceNodeKey`, never created. If the user needs a new Term/Code condition, direct them to
  the query editor UI.

Discover available macros with `get_macro_fields`. Confirm referenced fields exist on the index
schema (`get_standard_fields`) — a query referencing a renamed or removed field silently
returns zero matches.

## Worked example: user-assortment visibility

Goal: show products that either have no assortment or match one of the user's assortments.
Wrong shape (excludes everything): both conditions ANDed at root. Correct shape — one OR-group
under the root AND:

- groups: `[(GroupKey 0, ParentGroupKey -1, Operator And), (GroupKey 1, ParentGroupKey 0,
  Operator Or)]`
- expressions:
  - `(GroupKey 1, Field 'AssortmentIDs', Operator IsEmpty)`
  - `(GroupKey 1, Field 'AssortmentIDs', Operator MatchAny, ValueType 'Macro', Value
    'Dynamicweb.UserManagement.Context:AssortmentIDs')`
- plus every other pre-existing condition re-referenced by `SourceNodeKey` into GroupKey 0.

Use `MatchAny` (not `Equal`) when both sides can hold multiple IDs.

## Index must be built before queries return data

A query reads from an index. If the index has never been built, or is stale after a schema/
field change, queries return zero or wrong results even when the expression is correct. The
reliable order:

1. `build_product_index` to (re)build.
2. `wait_for_product_index` (or poll `get_product_index_status`) until it reports complete
   with a non-zero document count.
3. Only then trust query results.

`build_product_index` handles the already-running case gracefully — it will not start a second
concurrent build.

## Facets bind to query parameters

Storefront facets pass selected values into the query via **named parameters**. A facet feeds
a specific parameter name (e.g. a `Color` facet → a `Color` parameter on the query). If a query
is edited so the parameter it expects no longer exists, the matching facet stops filtering.
When changing a query that backs facets, confirm the parameter names the facets rely on are
preserved.

## Deleting a query safely

`delete_product_queries` (and `delete_index_queries`) take **id + exact current name** per
query. The server re-reads the query and refuses the delete if the name does not match, then
read-back-verifies that it is gone (`Verified`). So:

1. List first (`get_product_queries` / `get_index_queries`) and copy the id **and** the exact
   name of the query the user named.
2. If the user's name does not appear in the list, STOP and confirm — never delete a different
   query as a substitute.
3. Pass id + name together. If the result is `Success:false` (name mismatch or wrong scope),
   report it; do not retry against a different query.

Deleting the **ProductsFrontend** storefront query breaks product listings — call this out
before deleting anything under that repository.

## Dashboard binding

A widget pointing at a missing or renamed query goes blank without warning. When renaming or
deleting a query, list its bindings first and update them in the same batch of changes.

## Query configuration (admin UI settings)

`create_or_update_product_queries` persists the query's full configuration through its
`Configuration` object, and `get_product_queries` returns it. Besides completion rules/
languages it covers the PIM query-screen settings: `OpenProductDirectlyInEditMode`,
`UseCompletenessRulesToLimitResults` (see [dw-pim-completeness](../../dw-pim-completeness)),
the grid-edit include flags (`IncludeAllLanguagesInEdit`, `IncludeMasterProductsInEdit`,
`IncludeVariantsInEdit`), `EditScreenLanguageIds`, and the view preset IDs. Every field is
preserve-on-omit: send only the setting to change (leave the rest null); send an empty array
to clear a list. To flip just one toggle, read the query first to confirm the other values,
then send a `Configuration` with only that field set.
