# Foundational candidate → dw-integration-erp

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 ERP↔PIM data-ownership knowledge,
> staged here for a future fold-up into `dw-integration-erp`. No demo/customer content.
> When folded, move this body into `dw-integration-erp` (it is richer than that skill's
> current high-level ownership table) and re-target the pointers in the demo skills to it.
> Until then, the demo skills reference this file. Do not add demo specifics here.

## The ERP ↔ PIM ownership split

Every ERP↔PIM integration settles on the same general ownership split: the ERP owns
transactional data; the PIM owns descriptive/marketing data. The interesting cases live at the
boundary — a few fields that conceptually belong to both.

| Field group | Owned by ERP (writes to DW) | Owned by PIM (writes to ERP) | Notes |
|---|---|---|---|
| Identity | ProductNumber / SKU | — | ERP allocates; PIM reflects. |
| Pricing | `EcomPrices` rows (defaultPrice, currency-specific, customer-specific contract prices) | — | Price is the ERP's system of record. PIM displays read-only. |
| Stock | `EcomStockUnit` rows / stock level per location | — | Often live integration (per-request) rather than batch — prices and stock are the canonical "live integration" use cases per DW docs. |
| Cost / vendor | `EcomProducts.ProductCost`, vendor item no, vendor no | — | The ERP's accounting wants these; PIM rarely surfaces them on storefront. |
| Reorder / lifecycle | `bc_reorder` (or equivalent), discontinued flag | `lifecycle_state` (PIM-derived, can be driven by action rules reacting to ERP-side changes) | The classic interplay: ERP sets reorder=no, PIM action rule sets lifecycle=offline, frontend hides the product. |
| Identifiers (external) | EAN / GTIN, manufacturer part no | — | Often arrives in the ERP first (from procurement) and syncs forward to PIM. |
| Descriptive data | — | ProductName, ShortDescription, LongDescription, marketing copy | PIM is system of record; ERP gets a sparse version for accounting reports. |
| Marketing / hero assets | — | Asset references (`EcomAssets`, hero image, gallery, video) | PIM-only; never sync these to the ERP. |
| Attributes / facets | — | `ProductCategory|<Cat>|<field>` rows (filterable spec attributes, certifications, dimensions) | PIM-curated; the ERP may receive a flat sparse mapping for product-category code only. |
| Categorisation | (sometimes) `Item.Item Category Code` — ERP-side accounting category | `EcomGroupProductRelation` — merchandising category tree | These are NOT the same hierarchy. PIM merchandises by customer-facing tree; ERP categorises by procurement/accounting tree. Map between them, don't fuse them. |
| Unit of measure | Base unit (STUKS, PCS, KG, M) | — | ERP-owned because of accounting/inventory tracking. |
| Weight / dimensions | (often) shipping weight in ERP for freight calculation | (often) product weight in PIM for spec table | Same number; two owners. Decide ownership once per solution. |

## Customer-specific contract prices (the data model)

The ERP commonly holds per-customer-group contract prices, not just `defaultPrice`. DW10 models
these via:

- `EcomPrices.UserCustomerNumber` or `EcomPrices.UserGroupId` — price rows scoped to a customer or customer group
- `EcomPrices.CurrencyCode`, `EcomPrices.Quantity` — currency and quantity-tier breaks

The ERP writes these rows; the PIM displays them read-only. Frontend pricing resolution goes
through `Dynamicweb.Ecommerce.Prices.PriceManager` — use the API, not URL parsing or raw SQL.

## What NOT to sync back to the ERP

A common over-engineering trap. Do not push the following to the ERP:

- Marketing copy, hero images, gallery assets — the ERP can't render them and doesn't want them in its accounting DB.
- The customer-facing merchandising category tree — the ERP has its own accounting category tree; conflating them confuses both systems.
- PIM-curated attribute values for facets / filters — the ERP rarely wants these; if you must, sync only a flat subset (e.g. EAN + weight) and document the sparse mapping explicitly.
- Storefront-only flags ("featured", "new arrival") and lifecycle states derived purely from PIM-side rules — the ERP doesn't need them and won't act on them.

The smallest-viable PIM→ERP payload is usually: ProductNumber, ProductName, manufacturerId/vendorNo,
EAN/GTIN, unit, primaryGroup (accounting code), and weight — enough for the ERP to create an Item
row that can be sold; everything else is PIM-side decoration.

## Sync direction is an ERP-side mapping choice

The DW10 connector API surface is **direction-agnostic** — the same endpoints serve both ways, and
the actual direction is configured on the ERP side via its column mapping, not on the DW side:

- **ERP → PIM** (ERP is master): the ERP pushes item changes (create/update). PIM acts as the
  publishing layer. Common where the ERP's item master is canonical.
- **PIM → ERP** (PIM is master): the ERP pulls product reads on a schedule. PIM is canonical; the
  ERP consumes. Common where the PIM team owns master data and the ERP is purely operational.
- **Mixed** (most orgs): the ERP owns some fields (price, stock), PIM owns others (descriptions,
  hero images, category attributes). Field-level direction is set in the ERP's mapping config. This
  is the same ownership split tabulated above.

The DW-side endpoints support all three transparently — the API shape is identical; only the ERP's
mapping decides who writes what.

## The connector won't pull rows until column mappings are saved

A first-integration stuck state that is **vendor-generic**, not specific to any one ERP: the ERP-side
connector will not materialise/pull product rows until at least one column mapping is saved on the
ERP side. A green "Test Connection" is not enough; the field schema being fetched is not enough; the
language picker being filled is not enough.

Without a saved mapping, the connector sits in a **discovery-only loop** — it repeatedly polls the
license, settings, field-schema, languages, and product-count endpoints, but never calls the
"ids-by-last-modified" or "product-by-id" endpoints. The product list on the ERP side stays empty
even though the count endpoint returns a non-zero total. The connector needs the mapping before it
knows how to materialise an item locally; until then, fetching ids is pointless.

The canonical fingerprint, watched on the wire (count-and-schema calls only, never an ids/by-id
call), is the **missing-mapping signature** — the first thing to check whenever an ERP connector
"connects but shows nothing". A minimal mapping (identity + name, e.g. `No. → ProductNumber` and
`Description → ProductName`) is enough to unblock the pull; flesh out the rest after rows are flowing.
The mapping is ERP-side configuration and does not write back to PIM.
