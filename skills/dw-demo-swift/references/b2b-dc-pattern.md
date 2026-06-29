# b2b-dc-pattern.md

> The canonical Dynamicweb 10 B2B pattern for any portal where pricing, stock, shipping methods, or shipping fees vary by Distribution Center (DC) — vendor-blessed (Dynamicweb architecture guidance). **This is the standard B2B mechanic in DW10, not an upgrade path:** treat it as the default scaffold for any wholesale / B2B-distributor demo that touches DC-aware behavior. Customers expect it; framing it as bespoke would invent friction DW10 doesn't have.

The mechanic — **one AccessUser group per Stock Location**, which natively unlocks DC-scoped
Assortments + Shipping methods + Shipping fees + cart-time pricing without custom code — plus the
naming convention, user assignment, surface guidance (MCP-first; the `AccessUser` NOT-NULL column
list for SQL fallback), the admin-tree typed-group filter, and the verification flow are owned by the
`dw-commerce-b2b` foundational skill — staged in
[`commerce-b2b.md`](../../dw-demo-base/references/foundational/commerce-b2b.md) ("The DC-as-user-group
pattern"). Read that before scaffolding DC groups.

## When not to use this pattern

- **Single-DC demos** — if the customer is single-DC and the storyline doesn't lean on "different
  buyer sees different stock", don't scaffold DC groups. One Assortment is fine. Adding the DC mechanic
  to a demo that doesn't need it is wasted complexity (and wasted customisation-budget signal in the
  closing slide, even though zero customisations were technically added).
- **B2C demos** — the DC-as-group pattern presupposes accounts-with-customer-numbers. Anonymous-buyer
  / B2C demos don't have the user-group hook to scope on.

For everything in between (multi-DC B2B with named buyer accounts), this is the default.

## Cross-references

- [`commerce-b2b.md`](../../dw-demo-base/references/foundational/commerce-b2b.md) — the full mechanic,
  naming, assignment, and verification.
- [`commerce-catalog.md`](../../dw-demo-base/references/foundational/commerce-catalog.md) §2.9 —
  Assortments structural model (customer access ≠ Channels); §2.11 — the stock cart ignores
  `PriceQuantity > 0` tier rows; ERP-pre-graduated rows are the production pattern for qty-aware DC
  pricing.
- [`customer-center.md`](customer-center.md) — the stock Swift CSR section for sales-on-behalf, layered
  on top of the DC pattern when a CSR persona impersonates DC buyers.
