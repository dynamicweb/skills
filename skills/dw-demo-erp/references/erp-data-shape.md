# erp-data-shape.md

> The generic ERP <-> PIM data shape that recurs across Dynamicweb demos, regardless of mock vs live flavor. Loaded from `dynamicweb-erp-demo/SKILL.md` "Where to find things". Use this before you decide which flavor to pick -- knowing the shape helps you scope the demo's ERP beats.

## The ownership split

Every ERP <-> PIM integration in a Dynamicweb demo settles on the same general ownership split. The ERP owns transactional data; the PIM owns descriptive/marketing data. The interesting beats live at the boundary: a few fields that conceptually belong to both, and a handful where the demo has to make a deliberate choice.

| Field group | Owned by ERP (writes to DW) | Owned by PIM (writes to ERP) | Notes |
|---|---|---|---|
| Identity | ProductNumber / SKU | -- | ERP allocates; PIM reflects. |
| Pricing | `EcomPrices` rows (defaultPrice, currency-specific, customer-specific contract prices) | -- | Price is BC's system of record. PIM displays read-only. |
| Stock | `EcomStockUnit` rows / stock level per location | -- | Often live integration (per-request) rather than batch -- prices and stock are the canonical "live integration" use cases per DW docs. |
| Cost / vendor | `EcomProducts.ProductCost`, vendor item no, vendor no | -- | BC's accounting wants these; PIM rarely surfaces them on storefront. |
| Reorder / lifecycle | `bc_reorder` (or equivalent), discontinued flag | `lifecycle_state` (PIM-derived, can be driven by action rules reacting to ERP-side changes) | The classic interplay: ERP sets reorder=no, PIM action rule sets lifecycle=offline, frontend hides the product. |
| Identifiers (external) | EAN / GTIN, manufacturer part no | -- | Often arrives in ERP first (from procurement) and sync forward to PIM. |
| Descriptive data | -- | ProductName, ShortDescription, LongDescription, marketing copy | PIM is system of record; ERP gets a sparse version for accounting reports. |
| Marketing / hero assets | -- | Asset references (`EcomAssets`, hero image, gallery, video) | PIM-only; never sync these to ERP. ERP rarely renders them. |
| Attributes / facets | -- | `ProductCategory|<Cat>|<field>` rows (filterable spec attributes, certifications, dimensions) | PIM-curated; ERP may receive a flat sparse mapping (see example below) for product-category code only. |
| Categorisation | (sometimes) `Item.Item Category Code` -- BC-side accounting category | `EcomGroupProductRelation` -- merchandising category tree | These are NOT the same hierarchy. PIM merchandises by customer-facing tree; ERP categorises by procurement/accounting tree. Map between them, don't fuse them. |
| Unit of measure | Base unit (STUKS, PCS, KG, M) | -- | ERP-owned because of accounting/inventory tracking. |
| Weight / dimensions | (often) shipping weight in ERP for freight calculation | (often) product weight in PIM for spec table | Same number; two owners. Decide once per demo. |

## Customer-specific contract prices

A recurring beat in B2B demos: the ERP holds per-customer-group contract prices (not just defaultPrice). DW10 models these via:

- `EcomPrices.UserCustomerNumber` or `EcomPrices.UserGroupId` (price rows scoped to a customer or customer group)
- `EcomPrices.CurrencyCode`, `EcomPrices.Quantity` (tier breaks)

The ERP writes these rows; the PIM displays read-only. Frontend pricing resolution is via `Dynamicweb.Ecommerce.Prices.PriceManager` (use the real API, not URL parsing or raw SQL -- see [`../dw-demo-swift/references/dw10-canonical-surfaces.md`](../../dw-demo-swift/references/dw10-canonical-surfaces.md)).

For B2B demos that need to demo "Customer X sees price A, Customer Y sees price B", stage TWO pre/post row sets in the [mock-deltas.md](mock-deltas.md) Step 1 table (or two scheduled batches in live flavor) -- one per customer-group price update.

## Stock and the live-integration case

Stock is the canonical "live integration" use case per DW docs (see the quote in [integration-framework.md](integration-framework.md)). In the mock flavor, stock post-states are staged in the DB just like prices. In the live flavor, the AppStore connector polls stock on a schedule OR offers a live-integration endpoint that the storefront calls per-request (PDP load = stock check call to BC).

For demos, batch / scheduled stock works fine -- you don't need to wire live per-request integration unless the demo storyline explicitly is "stock is fresh to the second" (rare).

## What NOT to sync to the ERP

A common over-engineering trap. Do NOT sync the following to BC:

- Marketing copy, hero images, gallery assets -- ERP can't render them and doesn't want them in its accounting DB.
- Customer-facing category tree (merchandising) -- ERP has its own accounting category tree; conflating them confuses both systems.
- PIM-curated attribute values for facets / filters -- ERP rarely wants these; if you must, sync only a flat subset (e.g. EAN + weight) and document the sparse mapping explicitly in the static field-mapping artefact ([mock-deltas.md](mock-deltas.md) Step 4).
- Storefront-only flags like "featured", "new arrival", lifecycle states purely derived from PIM-side rules -- ERP doesn't need these and won't act on them.

The smallest-viable PIM->ERP payload is usually: ProductNumber, ProductName, manufacturerId/vendorNo, EAN/GTIN, unit, primaryGroup (accounting code), and weight. That's enough for BC to create an Item row that can be sold; everything else is PIM-side decoration.

## Cross-references

- Wider rule on source/target: [integration-framework.md](integration-framework.md).
- Staging this shape concretely (pre/post table, RESET task): [mock-deltas.md](mock-deltas.md) Step 1.
- PIM-side modelling of categories, attributes, and prices: [`../dw-demo-pim/references/structural-model.md`](../../dw-demo-pim/references/structural-model.md).
- Frontend price resolution (use `PriceManager`, not raw SQL): [`../dw-demo-swift/references/dw10-canonical-surfaces.md`](../../dw-demo-swift/references/dw10-canonical-surfaces.md).


