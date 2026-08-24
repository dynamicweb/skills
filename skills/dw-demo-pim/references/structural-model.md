# structural-model.md

> The structural mental model for a Dynamicweb 10 PIM demo build. The platform facts live in the
> foundational skills' references; this file is a **router** — it points each topic at its
> foundational reference and keeps only the demo-build deltas (naming conventions, which beats to
> stage). Read the linked reference before modelling; come back here for the demo framing. Loaded from the PIM demo SKILL.md "Where to find things" table.

## Where each structural topic lives now

| Topic | Foundational reference (platform fact) | Demo delta (kept below) |
|---|---|---|
| §2.1 Shop types enum + `ProductActive` vs relation gating + admin-nav | [`pim-modelling.md`](../../dw-pim-modelling/references/structural-model.md) §2.1 | SHOP1 / SHOP-DATA naming |
| §2.2 Group types (DataModelFolder / DataModel) | [`pim-modelling.md`](../../dw-pim-modelling/references/structural-model.md) §2.2 | — |
| §2.3 Catalog vs Channel group trees + slug cache | [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.3 | per-channel naming |
| §2.3a Native "Publish to channel" action | [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.3a | fire publish as a beat |
| §2.4 Repositories / indexes / queries + `ProductIndexSchemaExtender` | [`index-management.md`](../../dw-search-indexing/references/index-management.md) | — |
| §2.5 / §2.5a Variants (multi- and single-axis) | [`pim-modelling.md`](../../dw-pim-modelling/references/structural-model.md) §2.5 / §2.5a | — |
| §2.6 Bundles (BOM) | [`pim-modelling.md`](../../dw-pim-modelling/references/structural-model.md) §2.6 | — |
| §2.7 Channels + Feeds | [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.7 | — |
| §2.8 Product Categories + Fields internals | [`pim-modelling.md`](../../dw-pim-modelling/references/structural-model.md) §2.8 | — |
| §2.8 `reference_category` blank-panel gotcha | [`pim-completeness.md`](../../dw-pim-completeness/references/rules-and-dashboards.md) | planted-gap framing → [governance.md](governance.md) |
| §2.9 Assortments ≠ Channels | [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.9 | — |
| §2.10 Assets (`EcomDetails` + `DetailLanguageId`) | [`pim-modelling.md`](../../dw-pim-modelling/references/structural-model.md) §2.10 | — |
| §2.11 Pricing — tier rows ignored by stock cart | [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.11 | cheat-sheet caveat (below) |
| §2.12 Dynamic Workspaces — projections not storage | [`pim-modelling.md`](../../dw-pim-modelling/references/structural-model.md) §2.12 | workflow-state Inbox beat |

## Demo deltas — naming, beats, cheat-sheet caveats

These are the demo-build specifics layered on top of the platform facts above. They assume a fresh
DB built via MCP (no baseline deserialize).

### Shop / channel naming (demo convention)

- The DW ship-default commerce shop is `SHOP1` (ShopType=1) — rename it to the brand, don't create a duplicate (platform rule: [`pim-modelling.md`](../../dw-pim-modelling/references/structural-model.md) §2.1).
- Use `SHOP-DATA` (ShopType=4) as the DataStructure shop that owns the taxonomy + product home. In a **PIM-first** build there is no `SHOP1` at all — `SHOP-DATA` is the only product home until publish; an empty Groups/Channels tab on a product is the visible "in PIM, in no channel" signal you can point at on screen.
- Give each Channel (ShopType=3) a `CH-<TARGET>` id and its OWN group tree — one channel is usually enough to land the shop-vs-channel pedagogy beat (see SKILL.md "Demo philosophy").

### "Fire publish as a beat"

The native "Publish to channel" action ([`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.3a) is a demo *moment*, not just a data op: select the hero SKU, fire the action live, switch to the channel/storefront and show it appear. Seed everything else via SQL/MCP, but stage this one transition through the real admin action so the audience watches "PIM → live channel" happen — and so the `ShopUrlDataProvider` cache flushes the right way (raw SQL would leave URLs 404ing until a restart).

### Pricing tier-row cheat-sheet caveat

When the demo keeps `EcomPrices` tier rows for the PDP display table, note on the demo cheat-sheet that **cart shows base price** — tier prices are illustrative unless you ship the `IPriceProvider` escape hatch or ERP-pre-graduated rows ([`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.11). Don't make qty-break-at-cart-time the closing beat unless one of those is in place. If the storyline wants the customer-group-aware pricing beat, scaffold it on the user-group side (see `dw-demo-swift` DC pattern).
