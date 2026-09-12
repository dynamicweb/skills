# Measured gaps in the MCP tool surface

Where an MCP tool's model is narrower than the domain service behind it, and what the honest
verification channel is in each case. The mechanism — the tool's model is a subset, and nothing says
which columns fall outside it — is stated once in
[`backend-mcp-server.md`](backend-mcp-server.md) §5; this file is the catalogue.

Measured on Swift 2.2 / DW 10.28.x. Each row names the surface that does reach the data, in the order
of the action ladder: an MCP tool, then the Management API verb, then `SQL` — which is
**local-install only** and owes the cache flush or host restart its table carries in the
`dw-data-access` skill's post-mutation cache reference.

## Contents

- [Write-only fields: what a save accepts and no read returns](#write-only-fields-what-a-save-accepts-and-no-read-returns)
- [Read-only fields: what a read returns and no save reaches](#read-only-fields-what-a-read-returns-and-no-save-reaches)
- [Entities with no tool at all](#entities-with-no-tool-at-all)
- [Deletes that are not referentially complete](#deletes-that-are-not-referentially-complete)
- [Known-broken tools, version-pinned](#known-broken-tools-version-pinned)

## Write-only fields: what a save accepts and no read returns

| Entity | Field the save accepts | Why no read-back | Verification channel |
|---|---|---|---|
| Shop | `relatedLanguages[]`, `defaultLanguageId` (MCP `save_shops`) | Neither `get_shop` nor `get_shops` projects language-relation data into the response at all — a before/after diff of those tools shows only the data-model hierarchy | The `EcomShopLanguageRelation` rows themselves. `SQL` read; the write is also `SQL` where no verb reaches it |

Verifying a shop-language change by re-reading through the same tool family is not a weak test, it is
no test: the field never appears in the response.

## Read-only fields: what a read returns and no save reaches

| Entity | Field | Behaviour | Verification / write channel |
|---|---|---|---|
| Order | **custom order field values** | `get_order_by_id` surfaces only the standard order fields (`purchaseOrderNumber`, `requisition`, `reference`). Custom order-field values are absent from the response entirely, so a persisted custom field reads as "not written" | `SQL` against `EcomOrders` — the storage columns are real columns. This is the sanctioned proof channel for custom order-field persistence until the tool's model is extended |

## Entities with no tool at all

| Data | Tools that look like they cover it | What they actually cover | Reachable surface |
|---|---|---|---|
| `EcomShippings.ShippingUserGroups`, `EcomPayments.PaymentUserGroups`, and the method↔country relations in `EcomMethodCountryRelation` | `create_shipping` / `update_shipping` / `save_shipping_methods`; `create_payment` / `update_payment` / `save_payment_methods` | Name, description, active, sorting, code, weights, gateway and terms code — the method entity's own row columns, never the join table and never the group-restriction columns | `SQL`. This matters more than it sounds: a method with **no country relation never renders at checkout**, and the group restriction is the only native lever for group-driven payment visibility, so the load-bearing half of a checkout-visibility setup is entirely outside the tool surface |
| `EcomStockLocationTranslations`, `EcomDetailsGroupTranslation` | the translation family (`save_unit_translation`, `set_option_translations`, and the group / country / currency / region / payment / shipping / VAT-group verbs) | Everything except these two entities — there is no translation verb for either, in either direction, and `get_stock_locations` is read-only | `SQL`, guarded with `NOT EXISTS` on the target language row. A stock location whose name is stranded under another language reads back as an empty `name` from `get_stock_locations`, which looks like missing data rather than a missing translation |

## Deletes that are not referentially complete

**MCP `delete_products` removes the `EcomProducts` row and leaves its relations dangling.** Measured
on a 284-product delete that returned `succeeded: 284, failed: 0`: 284 `EcomGroupProductRelation` rows
and 14 `EcomProductCategoryFieldValue` rows still pointed at ids that no longer existed, with no error
and no warning.

**Sweep both tables by `SQL` after any bulk `delete_products`, before re-importing** — a re-import
onto dangling relation rows produces products that appear in groups they were never assigned to.
Assert the sweep on counts: products, group relations, category field values and related-product rows
back at their pre-delete baseline.

## Known-broken tools, version-pinned

| Tool | Behaviour | Status |
|---|---|---|
| `force_price_recalculation` | Returns `An error occurred invoking 'force_price_recalculation'.` with no further detail and with no argument supplied | Not root-caused. **On Swift 2.2 / 10.28.x, do not plan a build sequence around it.** A full index rebuild picks up newly written price rows without it, so a rebuild is the available substitute where price rows have changed |
