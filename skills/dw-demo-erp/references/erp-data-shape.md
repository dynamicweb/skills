# erp-data-shape.md

> Demo-side guide to scoping ERP beats. The vendor-generic ERP↔PIM ownership *shape* — the
> field-by-field ownership table, the contract-price data model, and the "what not to sync" rules —
> lives in [`../../dw-integration-erp/references/ownership-split.md`](../../dw-integration-erp/references/ownership-split.md).
> Read that first; this file keeps only how a
> demo *applies* the shape. Loaded from `dw-demo-erp/SKILL.md` "Where to find things".

## Read the shape first

Before picking a flavor, read the ownership shape in the foundational candidate above. Knowing
which system owns price, stock, descriptions, categories, and assets is what lets you scope the
demo's ERP beats — and it is the same whether you build the mock or the live flavor.

## Applying the shape in a demo

- **Pick the flavor knowing the shape.** The ownership split tells you which fields the ERP would
  write (price/stock/cost/identity) and which the PIM owns (descriptions/assets/facets). The demo's
  "BC sent us this" beats are always ERP-owned fields landing on DW products.

- **Customer-specific contract prices → stage two row sets.** For a "Customer X sees price A,
  Customer Y sees price B" beat, stage TWO pre/post `EcomPrices` row sets in the
  [mock-deltas.md](mock-deltas.md) Step 1 table (or two scheduled batches in the live flavor) — one
  per customer-group price update. The price *data model* (`UserGroupId`/`UserCustomerNumber`,
  resolution via `PriceManager`) is in the foundational candidate.

- **Batch stock is fine for demos.** Stock is the canonical live-integration case, but for a demo,
  batch/scheduled stock works — stage stock post-states in the DB like prices. Only wire live
  per-request integration if the storyline is explicitly "stock is fresh to the second" (rare).

- **Keep the PIM→ERP payload small.** Demos rarely need to push more than the smallest-viable
  payload (see the candidate). Don't model marketing copy / hero assets / facet attributes flowing
  back to the ERP — that's the over-engineering trap, and it costs a customisation-ledger defence.

## Cross-references

- ERP↔PIM ownership shape: [`../../dw-integration-erp/references/ownership-split.md`](../../dw-integration-erp/references/ownership-split.md).
- Wider rule on source/target: [integration-framework.md](integration-framework.md).
- Staging this shape concretely (pre/post table, RESET task): [mock-deltas.md](mock-deltas.md) Step 1.
- PIM-side modelling of categories, attributes, and prices: [`../../dw-demo-pim/references/structural-model.md`](../../dw-demo-pim/references/structural-model.md).
