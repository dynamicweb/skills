# b2b-dc-pattern.md

> The canonical Dynamicweb 10 B2B pattern for any portal where pricing, stock, shipping methods, or shipping fees vary by Distribution Center (DC) — vendor-blessed (Dynamicweb architecture guidance). **This is the standard B2B mechanic in DW10, not an upgrade path:** treat it as the default scaffold for any wholesale / B2B-distributor demo that touches DC-aware behavior. Customers expect it; framing it as bespoke would invent friction DW10 doesn't have.

The mechanic — **one AccessUser group per Stock Location**, which natively unlocks DC-scoped
Assortments + Shipping methods + Shipping fees + cart-time pricing without custom code — plus the
naming convention, user assignment, surface guidance (MCP-first; the `AccessUser` NOT-NULL column
list for SQL fallback), the admin-tree typed-group filter, and the verification flow are owned by the
`dw-commerce-b2b` foundational skill — staged in
[`commerce-b2b.md`](../../dw-demo-base/references/foundational/commerce-b2b.md) ("The DC-as-user-group
pattern"). Read that before scaffolding DC groups.

## Hiding prices from anonymous visitors is a **template-level** gate only

The area's `AnonymousUsers` setting (a value containing `price`) is enforced in the **rendering** templates —
`Swift-v2_ProductPrice.cshtml` checks `anonymousUsersLimitations.Contains("price")` — **not** in the product
data handed to the page. The analytics / ecommerce tracking payload is built from the *unfiltered* product
object, so the anonymous HTML still ships the list price: a `clickProductLink('<productid>', …, '<currency>',
'<list price>', '0.00')` call sits in the same page whose visible price cell renders only a locked
"Dealer price" label. Anyone with devtools reads the withheld number. GA4 `dataLayer` pushes leak the same way.

- **Any demo that sells "prices hidden from anonymous" as its commercial contract must assert the payload, not
  the pixels.** Gate assert: fetch every PLP and PDP anonymously and assert (a) the signed-in price string
  appears nowhere in the body, and (b) every `clickProductLink` / `dataLayer` price argument is `0` or absent.
  A visual check of the price cell proves nothing here.
- **The fix belongs where the payload is built**, not in the template: the analytics product mapping must
  consult the same hide-price predicate the price template uses and emit `0` — or omit the price node — when
  prices are gated. Until that lands, treat it as a known leak and say so in the run notes.

## Driving the cart in an automated probe

Two Swift shapes break naive cart automation, and both make a perfectly healthy cart look broken:

- **The visible add-to-cart control is `<button type="button">`; the form's `input[type=submit]` renders at
  0×0.** The obvious selector (`form button[type=submit]`, `[name=cartcmd]`) matches the hidden 0-height element
  and the click is a no-op — the page does nothing and the run reports a broken checkout path. Select **by
  rendered height (> 10px) inside `[data-dw-itemtype="swift-v2_productaddtocart"]`**, never by `type=submit` or
  `name=cartcmd`. (The hidden inputs alongside it carry `cartcmd=add`, `ProductId`, `Quantity`.)
- **The cart page has no per-line delete control** — lines are `div`s, not table rows, so "find the row, click
  its delete button" finds nothing. Removal goes through the page's single `cartcmd=updateorderlines` form:
  set `QuantityOrderLine<OrderLineId>` to `0` and submit.
- **A probe that adds to a live demo cart must restore it.** A working smoke test otherwise pollutes a cart a
  prospect may be shown minutes later. Assert the cart count increments by exactly 1 after clicking the visible
  button, then zero the affected order line and assert the count returns to its starting value; exit non-zero if
  either leg fails. Retry the cart navigation — it can `ERR_ABORT` while a mini-cart POST redirect is in flight.

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
