# Prices, bundles, fulfilment and credit

These are acceptance contracts to implement and prove against the selected ERP. A documented
connector handshake does not establish them. Record unresolved policy with its owner.

## Tier prices and promotions

BC owns MSRP/base, customer-group and customer-specific tiers. Agree the applicable-price
selection with the ERP owner, including quantity breaks, dates, UOM, variant, currency,
tax-inclusion and rounding. BC's best-price calculation is not universally a simple
customer-over-group-over-base override. If a business requires that hierarchy, prove it in BC
or document the agreed Commerce resolver. Never treat a blank BC currency as an arbitrary
storefront currency; resolve company LCY first.

Import base tiers or call the supported live price operation; Commerce owns marketing
promotions and vouchers. Define stacking once. Preserve price source, original base,
applied discount and final line amount so BC can reconcile the amount accepted by the buyer.
Prove base, group, customer, quantity boundary, expiry, currency/UOM, promotion and combined
cases. Round-trip a price change, then restore it and verify the same buyer's PDP and cart.

## Phantom bundles

Keep the marketing bundle in Commerce, with explicit component SKU, variant, UOM and quantity
multipliers. Expand to real BC items before order export; keep the bundle parent for display
and audit, and export only the component product lines. Allocate bundle price and marketing
discount deterministically across components in currency minor units, placing any rounding
remainder on one declared line. Component quantities and totals must match the cart and invoice.

Prove repeated components, a component already in the cart, variant/UOM, quantity two, a bundle
promotion, out-of-stock component and a partial shipment/refund. Preserve the component lineage
and price snapshot on each recurrence; define when a subscription adopts a changed bundle.
An operational assembly in BC remains a different model with ERP-owned BOM semantics.

## Company and location fulfilment

The selling company owns the customer, credit and order. Each fulfilment location belongs to
a company. Cross-company fulfilment needs an ERP-owned intercompany, transfer or sourcing
workflow; selecting a location in another company is not a complete implementation.
Agree invoice issuer, item/customer cross-reference, tax determination, legal ship-from/ship-to,
source shipping cost, currency and what happens when one order spans two sources.

Aggregate customer-facing availability only over the approved fulfilment companies and locations,
using the same item/UOM and availability definition. Keep company/location detail behind the total
for routing and reservations. Prevent double counting a company total plus its location rows.
An inaccessible/stale company is unknown, not zero. Revalidate the chosen source at submission.

## On-account subscriptions

The standard customer API exposes `creditLimit`, `balanceDue` and `blocked`. Those facts alone
do not implement a credit admission decision: open orders, unposted invoices, pending attempts,
reservations and currency can change exposure. Obtain the ERP owner's live credit operation
or implement an approved BC extension contract; do not invent a standard credit endpoint.

Request: selling company, bill-to account, currency, total including tax/shipping, recurrence
attempt ID and intended posting date. Response: allow/hold/reject, reason, decision ID, expiry
and exposure version/reservation semantics. BC must atomically enforce or recheck the decision
when accepting the order. The subscription worker calls it on every attempt and retries the same
idempotency key after a timeout. Test allowed, exceeded, blocked, expired, unavailable and
concurrent attempts. Zero limit means the ERP policy says what it means, not automatically zero credit.

Sources: [BC sales price rules](https://learn.microsoft.com/en-us/dynamics365/business-central/sales-how-record-sales-price-discount-payment-agreements),
[customer API facts](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/resources/dynamics_customer),
[BC intercompany](https://learn.microsoft.com/en-us/dynamics365/business-central/intercompany-manage).
