---
name: dw-data-write-effects
type: knowledge
group: data
mcp: optional
dynamo: true
description: 'What a write to a Dynamicweb 10 instance actually leaves behind — how to prove it landed, and which mutations owe a follow-up MCP call before anything downstream reflects them. Triggers: the save returned ok but the value did not change, the product list or search results are stale after an edit, prices or assortments did not update, index says done but the row is missing, verify a write landed, which rebuild does this change need. Non-triggers: choosing the surface to act through, cache flushing by verb, host restarts and SQL ordering -> dw-data-access; catalog and price modelling -> dw-commerce-catalog; index and query design -> dw-search-indexing.'
---

# Write effects: proving a write landed, and what it owes afterwards

Two facts about Dynamicweb 10 writes decide whether an edit is actually finished. First, a
successful call is not evidence that the data changed. Second, some writes update everything that
reads them and some leave a derived structure stale until a second call rebuilds it.

Everything here is expressed as MCP tool calls, because the MCP tool set plus read/write under
`Files/` is the whole surface these steps may use.

## Without MCP

The knowledge here stands alone; the Dynamicweb MCP tools it names are the way to apply it, and
in-product they are the only way — the MCP tool set plus read/write under `Files/` is the whole
surface these steps may use. When no tool covers the operation, **stop and tell the user**, naming
the admin screen that performs it, rather than substituting a guessed HTTP call, a file edit
outside `Files/`, or SQL. The Management API, the serializer and direct SQL exist only outside the
product, are never a step in this skill, and are owned by
[`dw-data-access`](../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance".

## Success is not proof — round-trip every write

A write tool can return a success payload and still have dropped part of the input: a field the
save model does not carry, a value the domain service normalized away, a relation that needed a
different call. The read that follows can then serve a cached model that agrees with the lie,
because it was populated from the same request.

**Round-trip through something other than the write's own response.** After a write:

1. Read the entity back with a *different* tool than the one that wrote it — `get_products_by_ids`
   or `get_products_by_sku` after `update_products`, `get_pages_by_ids` after `save_pages`,
   `get_item_field_values` after `set_item_field_values`. (MCP 0.4.4 registers the **batch** by-id
   getters and no singular `*_by_id` form for pages, products or users; read `tools/list` and use
   what is there.)
2. Compare the **stored value**, field by field, against what was sent. A field that is absent
   from the read is not "defaulted" — it is unwritten.
3. For anything a visitor sees, read it once more through the surface the visitor uses —
   `get_products_by_query` or `get_products_by_search_filter` for catalog data,
   `fetch_frontend_page_html` for a rendered page.

When the read disagrees with the write, the write is the thing that failed. Do not re-send the
same payload hoping for a different result; find the field the save model does not carry, and say
so.

## Self-invalidating writes vs writes that owe a follow-up

Most writes through the MCP tools call the platform's own domain services, so the caches those
services own are invalidated as part of the call. A short list of writes feeds a **derived
structure** that is built on a schedule or on demand, and that structure stays stale until a
second tool call rebuilds it.

| The write | What goes stale | The follow-up |
|---|---|---|
| Product create, update, delete, group assignment, field or data-model change | The product index — search, filtered listings, and every query that reads through it | `build_product_index`, then `wait_for_product_index`; `get_product_index_status` reports progress and completion. **Read the caution below before trusting the rebuild.** |
| Assortment membership: products, groups, shops, users or permissions on an assortment | The materialized assortment, so the customer still sees the old catalog | `flag_assortments_for_rebuild`, then `build_assortments` |
| Price rows, currency changes, price-affecting discount or customer-group edits | Computed prices on products and carts | `force_price_recalculation` |
| Country, region, or VAT-country relation edits | The country cache behind address, tax and shipping lookups | `clear_country_cache` (or `clear_countries_cache_by_keys` for named entries) |

Two rules make this usable:

- **Order matters: write everything, then rebuild once.** Batch the writes, then issue the
  follow-up. A rebuild issued between writes indexes a half-written state, and the next write
  invalidates it again.
- **A rebuild is not instant and not a proof.** `build_product_index` returning means the build was
  *accepted*. Poll `get_product_index_status`, or block on `wait_for_product_index`, and then
  re-read the data through a query tool before reporting the change as done.
- **Name the repository, and end on the document count.** All three index tools default
  `repositoryName` to the literal `Products` and neither validates it, so on a host without that
  repository the status call answers `Idle` with no error while the repository the storefront reads
  is empty. Pass `repositoryName` explicitly, taken from the catalogue paragraph's own `IndexQuery`
  path (`get_module_settings`), and assert `documentCount` greater than zero — a completed build
  with zero documents is the failure, not the success, because a zero-document index cannot serve a
  query at all and the storefront renders the exception inside an HTTP 200 page. The preconditions
  behind a build that never drains — the task file, the task handler, and the explicit first build
  after a content load — are owned by the `dw-search-indexing` skill, reference
  `index-management.md`.

### The product rebuild reads through caches the write does not flush

**A product index rebuild can index pre-write values, and it reports success either way.** On this
platform line the index builder reads product and category data through the `ProductService`,
`ProductCategoryFieldValueService` and `ProductCategoryService` caches, and an MCP product write does
not flush them. This fires on the MCP patch surface, not only on out-of-product writes: patch a
field, call `build_product_index`, poll to completion, and the index can still serve the old value
while everything reports done. The correct order is **write, flush, rebuild, re-verify**.

**No MCP tool flushes those caches.** In product, that makes the flush the one step of this table
you cannot take yourself. So: after a product write and before the rebuild, **tell the user to flush
from the admin — Settings → System info → Cache — and wait for that** before calling
`build_product_index`. If the rebuild has already run, flush and rebuild again. Never report the
change as live on the strength of a completed rebuild alone; re-read the value through
`get_products_by_query` or `get_products_by_search_filter` and say plainly when the read still
disagrees. The mechanism, the affected services and the out-of-product flush verb are in
[`dw-data-access/references/cache-invalidation.md`](../dw-data-access/references/cache-invalidation.md).

Every other write in this table is flushed by the tool that made it. **Everything not in this table
is self-invalidating through the tool that wrote it, with that one read-through exception.** Cache
flushing by verb, host restarts, and the ordering rules for mixed surfaces are out of scope here and
belong to [`dw-data-access`](../dw-data-access/SKILL.md).

## Never clone a structural tree outside the create path

Copying an Area, Page, Paragraph, GridRow or Item by duplicating its rows produces something that
looks right and is broken. The create path carries sibling-link bookkeeping, item-instance cloning,
localization overlays, ItemList relations and hidden-flag rules that a row-level copy gets partly
right and then breaks screens later.

Use the tools that own the copy: `copy_area`, `copy_page`, `copy_paragraph`, `copy_payment_method`,
`copy_shipping_method`, and `create_language_version` for a localized tree. When no copy tool exists for
the entity, create it through its own create tool and set the fields — or stop and name the admin
screen that copies it. A structural tree assembled any other way is a defect that surfaces long
after the session that made it.
