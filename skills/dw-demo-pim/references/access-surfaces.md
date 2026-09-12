# access-surfaces.md

> The PIM-specific application of the action ladder, plus the per-project reference paths a PIM demo
> leans on. Loaded from `dw-demo-pim/SKILL.md` "Where to find things".

## The ladder, applied to PIM work

The ranking of surfaces — MCP tools, then the Management API at `/admin/api/...`, then the serializer,
then direct SQL as a local-only last resort with the admin UI as verification only — is foundational
and owned by [`dw-data-access`](../../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance".
Read it there; it is not restated here. The demo-phase deltas (scaffold vs build, the bootstrap
one-clicks, Browser MCP scope) are in
[`../../dw-demo-base/references/surface-priority.md`](../../dw-demo-base/references/surface-priority.md).

**Take the highest rung that reaches the PIM task — speed is not the tie-breaker.** What that means
per rung, in PIM work:

| Rung | PIM operations it owns | PIM-specific notes |
|---|---|---|
| 1 MCP (`dynamicweb-commerce-mcp`) | Creating and updating products, groups, variant groups and options, data models, field and category definitions, prices, assortments — `create_products`, `patch_products_safe`, `save_groups`, `create_variant_combinations` | Rich schemas and read-modify-write, so untouched fields survive. Tokens expire mid-session; re-auth with `/mcp`. |
| 2 Management API (`/admin/api/...`, bearer) | The admin-grade PIM actions MCP does not wrap: `BuildIndex`, `IndexStatus`, `CacheInformationRefresh`, `FeatureManagementToggle`, `CompletionSettingsSourceById`, rule-usage inspection | Spec UI at `/admin/api/docs/`. Reach for `CacheInformationRefresh` before restarting the host for a cache flush. Catalog and the OpenAPI-discovery probe: [`management-api-and-sql.md`](../../dw-data-access/references/management-api-and-sql.md). |
| 3 Serializer | Loading a whole catalog, data-model tree or index definition from a layer, and moving PIM content between installs | Prefer a layer over a several-hundred-call MCP loop, and whenever product/group ids must survive the move. Dry-run first. |
| 4 Direct SQL (`sqlcmd -S <server> -E -d <db>`) | Cleanup and teardown of a bad load, reads and census queries, bulk schema-drift repair that rungs 1-3 provably do not expose | **Local installs only** — a hosted PIM instance has no SQL rung at all. Every SQL step states why rungs 1-3 do not cover it and the flush or restart it owes ([`cache-invalidation.md`](cache-invalidation.md)). Schemas are discoverable via `INFORMATION_SCHEMA.COLUMNS`. Never SQL-clone a structural tree, and never use SQL because it is quicker to type. |

**Structural PIM fixes belong on rung 1 or 2, not on SQL.** A group re-parent, a variant-group
rewiring, a field moving between global and category storage and a data-model change all carry
relation, index and completeness bookkeeping the create path performs and a raw `UPDATE` does not.

**The filesystem is not a rung on this ladder — it is a different store.** Repositories, queries, feed
templates and index definitions live as XML/cshtml/xslt files under
`wwwroot/Files/System/Repositories/` and `wwwroot/Files/Templates/`; copying a `.query` or `.index`
file from a Swift reference installation is a file operation, and it needs the matching `BuildIndex`
on rung 2 before the change is visible.

## Management API + OpenAPI discovery + per-project reference paths

The Management API admin-endpoint catalog (BuildIndex, IndexStatus, CacheInformationRefresh, GetServiceCaches, FeatureManagementToggle, CompletionSettingsSourceById), the runtime OpenAPI-discovery probe, and the per-project discovery table (host URL/port, SQL Server, DB name, API token) are vendor-generic platform facts — see [`management-api-and-sql.md`](../../dw-data-access/references/management-api-and-sql.md).

Two reference sources this demo skill leans on (per-project):

| Ref | How to find it in the current project |
|---|---|
| Swift `base` layer (per-demo checkout) | `<demo-root>\distribution\layers\base\` — the demo's checkout of the canonical swift/2.3 `base` layer (a `config/replace/merge` tree, from the Distribution repo `justdynamics/Truvio.Commerce.Distribution`). Its serialized index XML is the copy-paste source for `Products.index` definitions. |
| DW10 source clone | a local clone of the DW10 source (location per machine — ask/discover, never hardcode) — search `src/Features/Ecommerce` for Ecom internals and `Dynamicweb.Products.UI` for admin UI behavior. Otherwise fall back to https://doc.dynamicweb.dev/ |

When the user gives you a token, port, or path in chat, treat it as scoped to the project in the current working directory — save it in conversation state, not as a global default.
