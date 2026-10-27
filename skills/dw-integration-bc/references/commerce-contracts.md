# Prices, bundles, fulfilment and credit

These are acceptance contracts to implement and prove against the selected ERP. A documented
connector handshake does not establish them. Record unresolved policy with its owner.

## Contents

- [Tier prices and promotions](#tier-prices-and-promotions)
- [Native BC price-list construction](#native-bc-price-list-construction)
- [BC group eligibility in Commerce](#bc-group-eligibility-in-commerce)
- [Phantom bundles](#phantom-bundles)
- [Company and location fulfilment](#company-and-location-fulfilment)
- [On-account subscriptions](#on-account-subscriptions)

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

## Native BC price-list construction

When an approved AL adapter creates native price-list lines, initialise the line with
`Line.CopyFrom(Header, true)` and validate its item, UOM, quantity, amount and dates. On BC29,
`CopyFrom(Header)` alone left the line source as All Customers with a blank source number even
though the header named a customer or group. Read back the line's own source type/number as
well as the header; correct amounts and active status do not prove eligibility.

A repair must be bounded to the owned source references and the exact erroneous source shape.
`Line.CopySourceFrom(Header)` can restore the header source while preserving the existing
amounts and criteria; verify those fields before and after the repair. Never rewrite unknown
agreements because they share a book code.

Keep activation inside a write transaction non-interactive. `Header.Validate(Status, Active)`
entered duplicate resolution and attempted a modal page, which failed and rolled the transaction
back. The measured adapter called native `Price List Management.FindDuplicatePrices` with a
temporary duplicate table, failed on overlaps, called `Line.Verify()`, and then set the verified
lines and header Active with `Modify(true)`. This is a reviewed extension implementation, not a
generic instruction to bypass BC validation. Verify the installed method signatures and prove
both malformed-price rollback and successful source read-back on the target build.

See Microsoft's [Price List Line methods](https://learn.microsoft.com/en-us/dynamics365/business-central/application/base-application/table/microsoft.pricing.pricelist.price-list-line)
and [Price List Management methods](https://learn.microsoft.com/en-us/dynamics365/business-central/application/base-application/codeunit/microsoft.pricing.pricelist.price-list-management).

## BC group eligibility in Commerce

Maintain an explicit BC price-group-code to Commerce user-group-ID map. Derive direct membership
from the canonical BC customer snapshot, then add or remove only that integration-owned price
group membership. Preserve buyer, approver, CSR and account hierarchy memberships. A UserProvider
feed bound by existing `AccessUserID` can update the price-group code without creating users or
replacing their memberships; that code update alone is not an eligibility proof.

For imported group rows, bind `EcomPrices.PriceUserGroupId` to the mapped group and clear unrelated
scope fields through the measured provider. A populated `PriceCustomerPriceGroupId` alone let a
group amount reach an anonymous buyer. Schema availability and a successful import
therefore cannot establish that a price is scoped. Discover the current MCP `save_prices` schema
before using it for a repair; current servers can expose `userGroupId`. The generic scope contract
belongs to [`dw-commerce-b2b`](../../dw-commerce-b2b/SKILL.md). [dw 10.29.8]

Test an anonymous buyer, a group member and an unrelated customer after apply and cache refresh.
When a lower customer agreement masks the group row, temporarily raise that exact owned customer
amount so the group becomes the best applicable price. Confirm only the intended member changes,
then restore the source amount and rerun the same import and buyer controls. This proves group
fallback; quantity/UOM/date boundaries and cart totals remain separate acceptance cases.

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
a company. Resolve whether one selected company both supplies and invoices the whole order, or a
separate seller uses an ERP-owned intercompany/transfer workflow. The first model routes the order
to that supplying seller; the second needs the actual intercompany process. Selecting a foreign
location alone does not establish either model. Agree tax determination, item/customer references,
ship-from/ship-to, shipping cost, currency and the policy when one company cannot supply all lines.

Price ownership is a separate decision. A shared company-owned price book may serve multiple
sellers only with an explicit canonical account/item/UOM/currency map and an agreed final-admission
price contract. Record the price-book company independently from the supplying/invoicing company.

Aggregate customer-facing availability only over the approved physical companies and locations,
using the same item/UOM and availability definition. Retain the physical detail for routing and
reservations. A separate computed stock location can expose the aggregate to a single-location
storefront: select that view explicitly and exclude it from physical-stock sums and ERP admission.
A blank location selection can display the first physical row instead of a total. For indivisible
units, convert and floor availability per company before aggregation; stock in separate companies
cannot combine into one whole case. An inaccessible/stale company is unknown, not zero. Revalidate
the chosen physical source at submission and test the rendered quantity limit. [dw 10.29.8]

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
