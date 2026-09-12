---
name: dw-commerce-orders
type: knowledge
group: commerce
mcp: optional
dynamo: true
description: 'Handle orders, checkout, and cart functionality in Dynamicweb 10, investigate an order/cart/payment/shipment, and create or audit a discount or voucher. Triggers: order management, checkout flow, cart handling, pricing, find/troubleshoot an order or payment, create a discount/promotion/voucher/coupon. Non-triggers: product catalog -> dw-commerce-catalog; B2B patterns -> dw-commerce-b2b.'
---

# Orders, Checkout, and Cart

## Without MCP

The knowledge here stands alone; the Dynamicweb MCP tools it names are the way to apply it, and
in-product they are the only way — the MCP tool set plus read/write under `Files/` is the whole
surface these steps may use. When no tool covers the operation, **stop and tell the user**, naming
the admin screen that performs it, rather than substituting a guessed HTTP call, a file edit
outside `Files/`, or SQL. The Management API, the serializer and direct SQL exist only outside the
product, are never a step in this skill, and are owned by
[`dw-data-access`](../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance".

## Order Lifecycle

Orders move through configurable **Order Flows**: `Settings > Areas > Commerce > Order Management > Order Flows`. A flow is a named set of states (e.g., Received → Picked → Shipped → Completed). Each state has a name, description, color, a Default flag (applied to newly created orders), and optional notification email configuration.

Orders can be created by:
- Cart checkout
- Subscription auto-generation
- Quote conversion (`AcceptQuote` command)
- External import (ERP/POS)

**Cancellation operations:**
- **Cancel** — uncaptured orders only; cancels payment authorizations and returns stock
- **Delete** — a **soft** delete (`OrderDeleted = 1`, the row stays in `EcomOrders`) that refuses a
  completed order. `OrderCancel {Id}` then `OrderDelete {Ids}` is the working pair — note the
  singular/plural key split — see [references/order-states-and-quotes.md](references/order-states-and-quotes.md)
- **Refund** — full or partial; requires a refund-capable payment provider

## Shopping Cart App

The **Shopping Cart** app handles the checkout flow. Key configuration settings:

| Setting | Description |
|---------|-------------|
| Channel | Ecommerce channel for this cart |
| Context cart | Shared cart across multiple pages |
| Checkout to quote | Convert checkout submission to a quote instead of an order |
| Steps | Multi-step checkout configuration (each step has a label and template) |
| Notification emails | Emails sent on order creation |
| Field validation | Stock check, Terms & Conditions, custom validation |
| User management | Apply user details to order, create user account during checkout |

**Step structure:** One step must be designated the **Checkout step** (system step that converts cart to order; no template). Steps before collect info; the step after is the Receipt step.

## Checkout Form Fields

All checkout data is submitted via a form with `id="ordersubmit"`. These are the standard field names:

### Billing

```html
<input name="EcomOrderCustomerCompany" />
<input name="EcomOrderCustomerFirstName" />
<input name="EcomOrderCustomerSurname" />
<input name="EcomOrderCustomerEmail" />
<input name="EcomOrderCustomerAddress" />
<input name="EcomOrderCustomerZip" />
<input name="EcomOrderCustomerCity" />
<input name="EcomOrderCustomerCountry" />    <!-- ISO country code -->
<input name="EcomOrderCustomerVatRegNumber" />
<input name="EcomOrderCustomerEAN" />
```

### Delivery

```html
<input name="EcomOrderDeliveryFirstName" />
<input name="EcomOrderDeliveryAddress" />
<input name="EcomOrderDeliveryZip" />
<input name="EcomOrderDeliveryCity" />
<input name="EcomOrderDeliveryCountry" />
```

### Payment and Shipping

```html
<!-- Radio buttons: one per payment method.
     NOTE the asymmetry: the element id carries "Paymentmethod",
     the POSTED NAME is EcomCartPaymethodID. Shipping is not symmetrical. -->
<input type="radio" name="EcomCartPaymethodID"
       id="EcomCartPaymentmethodID_{PaymentMethodID}"
       value="{PaymentMethodID}" />

<!-- Radio buttons: one per shipping method -->
<input type="radio" name="EcomCartShippingmethodID"
       id="EcomCartShippingmethodID_{ShippingMethodID}"
       value="{ShippingMethodID}" />
```

### Other Cart Fields

```html
<input name="EcomOrderCustomerVoucher" />
<input name="EcomOrderPointsToUse" />
<input name="EcomOrderGiftCardCode" />
<input name="EcomOrderSubscribeToNewsletter" value="True" />
<input name="EcomOrderCustomerAccepted" value="True" />   <!-- Terms & Conditions -->
<input name="EcomRecurringOrderCreate" value="True" />
<input name="EcomOrderSavedCardCreate" value="True" />
```

**Custom order line fields:** post `OrderLineFieldValue_<orderLineId>_<systemName>` on
`cartcmd=updateorderlines`, after the line exists and after the field has a shop/group relation row.
The full write path is in [references/checkout-configuration.md](references/checkout-configuration.md).

## Cart Commands

Trigger via URL parameter `?CartCmd=` or as a hidden form field `<input name="CartCmd" value="..." />`.

**Two gates every scripted cart command must pass:** send a **browser User-Agent** (the add family
is refused outright for `curl`/`wget`, and still creates the cart row) and **follow redirects** (the
`Default.aspx?ID=` form 301s before the command runs). The command's own 302 then rebuilds the URL
from the page id, so **no parameter of your own survives alongside a cart command**.

### Product Commands

| Command | Required params | Optional params |
|---------|----------------|----------------|
| `add` | `productid` | `variantid`, `cartid`, `unitid`, `Quantity` |
| `addmulti` | `productid`, `Quantity` | Multiple products |
| `setmulti` | `ProductLoopCounter<n>`, `ProductID<n>`, `Quantity<n>` | **SETS** the quantity rather than adding; `0` deletes the line; a duplicate product in one post is last-row-wins |
| `incorderline` / `decorderline` / `delorderline` | `key` (orderline key) | — |
| `updateorderlines` | `QuantityOrderLine{ID}` for each line | `OrderLineFieldValue_<orderLineId>_<systemName>` |
| `emptycart` / `deleteallorderlines` | — | — |

### Cart Object Commands

| Command | Required params | Notes |
|---------|----------------|-------|
| `archive` | — | **Clears the user's active-cart pointer** — it archives nothing; `EcomOrders` has no archived column |
| `copyExtended` | `CartName`, `CartUserId` | Copies the **session's ACTIVE cart** — `CartId` is not read. The only ownership move |
| `createnew` | — | Needs `SetActive=true`, or the new cart never becomes the session's |
| `setcart` | `Cartid` | Selects a cart; **never transfers one**, and does not clear the previous holder's pointer |
| `setdiscount` | `OrderDiscount` or `OrderDiscountPercentage` | Requires impersonation rights |
| `setname` | `CartName` | Writes `OrderDisplayName` — there is no cart-name column |
| `loadorder` | `OrderId` | Load a previous order as cart |

Full contracts, the ownership traps and the cart-page-is-a-write rule:
[references/cart-commands.md](references/cart-commands.md).

## Payment Methods

Admin path: **Settings > Areas > Commerce > Order Management > Payment**

| Tab | Settings |
|-----|---------|
| General | Name, Active, Description |
| Countries | Restrict to specific countries |
| Provider | Select a CheckoutHandler add-in |
| Fees | Fixed or percentage fee, with optional free-above threshold |
| Other | Frontend user groups, icons |

**Fee specificity rule:** A country-restricted fee overrides a global fee for the same payment method.

## Shipping Methods

Admin path: **Settings > Commerce > Order Management > Shipping**

| Tab | Settings |
|-----|---------|
| Provider | GLS, Shipmondo, or other shipping provider add-in |
| Fees | Matrix: weight/volume/user/product/country/currency/zip rules |
| Availability | Countries, Frontend user groups, Product/Group inclusions/exclusions, Weight limits |

## OrderViewModel / OrderListViewModel

The customer-center order list and detail render through
`Dynamicweb.Ecommerce.Frontend.OrderListViewModel` and `OrderViewModel`. Their property sets, the
query-string filters the list honours, and the `CustomerCenterCmd` commands are in
[references/customer-center-surfaces.md](references/customer-center-surfaces.md).

## Investigating an Order

For "find/troubleshoot/report on this order, cart, invoice, payment, or shipment" — read-only.
Walk the ladder and stop as soon as the answer is in hand:

1. **Identify** — resolve the order from input. Order ID, secret, customer email, or external
   reference are all valid entry points.
2. **Header** — read shop, customer, total, currency, `StateId`, created date, `Complete`
   (a cart is `Complete = false`; an order is `Complete = true` — the same table holds both).
3. **Lines** — read `OrderLine` rows for product, quantity, unit price, line discounts. Most
   "wrong total" questions resolve here.
4. **Customer** — read the customer record only when the question concerns who placed it,
   addresses, or contact details.
5. **Payment** — read the payment record for state, method, captured amount, gateway
   reference.
6. **Shipment** — read shipment/track-and-trace records for carrier, tracking, dispatched
   status.
7. **History** — walk `OrderState` history for "when did X change" (see
   [dw-data-audit-trail](../dw-data-audit-trail) for the general audit-log approach).

Common questions and the right step: "Where is order N?" → 1 then 2. "Why is the total
wrong?" → 2 and 3. "Has it shipped?" → 6. "Did the payment go through?" → 5. "Who changed the
status?" → 7.

**Writes are out of scope for an investigation.** If it concludes a write is needed (refund,
status change, line edit), stop and propose the write on its own — do not chain a write onto
an investigation request.

## Discounts and Vouchers

For "create, edit, expire, or audit a discount, promotion, voucher, coupon, or campaign
code" — the modern discount model is the **Adjustments engine**, separating three entities:

- **Discount** — `Id`, `Name`, `Active`, `Priority` (lowest runs first; null runs last),
  `Final` (stops further discount evaluation when applied).
- **Conditions** — when the discount applies (e.g. a voucher condition with a single coupon
  code or a batch list).
- **Rewards** — what the discount does, ordered within a discount.

Classify the request along three axes before any write:

1. **Reward type** — order-level, product-level, shipping, or buy-X-get-Y.
2. **Trigger** — automatic (condition matches on cart) or coupon-protected.
3. **Scope** — shop, country, currency, customer group, product group, time window. Missing
   scope is the most common cause of an over-applied discount.

If more than one axis is unclear, batch all of them into a single clarifying question rather
than asking one at a time.

**Read before write** — read an existing discount in the same shop and copy `Priority`,
`Final`, and the conventional condition shape; confirm IDs of shop, currency, customer group,
product group the conditions reference; for voucher batches, read the existing batch to copy
prefix, length, character set, usage limit, and expiry.

**Required field shortlist.** Most discount writes need at minimum: name, reward type and
amount, condition with shop scope, active flag, valid-from/valid-to. Set `Priority`
deliberately — leaving it null means "runs last," which can interact badly with `Final`
discounts above it.

**Vouchers vs single codes.** A single voucher code is one row tied to one discount; a voucher
list/batch generates many codes and tracks usage per code. Confirm batch size, per-code usage
limit, and expiry before generating a batch — undoing a generated batch is messy.

**Confirm before writing.** Name the discount and shop, state reward/scope/validity window.
For voucher batches, the summary MUST include batch size and expiry — that is the value being
approved.

**Recovery.** A failure on currency or customer-group reference almost always means the
discount targeted a different shop than its scope. Re-read the shop's allowed currencies and
groups before retrying. The full engine internals (the two coexisting discount engines, v2
condition/reward payload shapes, voucher constraints) are in
[references/promotions-engines.md](references/promotions-engines.md).

## Where to find things

| Reference | Load it for |
|---|---|
| [references/order-lifecycle.md](references/order-lifecycle.md) | what `create_orders` writes, the platform-owns-ids-and-timestamps rule on every `*Save`, the re-save-reverts-raw-SQL trap and the **UPDATE → flush → touch** ordering, `GetOrderById` returning resolved defaults, the `GetOrderList` inner join on `EcomShops`, invoices, subscriptions, the order read surface, reorder, CSR impersonation, account seeding |
| [references/cart-commands.md](references/cart-commands.md) | `CartCmd` / `CustomerCenterCmd` contracts — the bot-User-Agent refusal, the querystring-dropping redirect, `setmulti` semantics, `archive` / `copyExtended` / `setcart` / `createnew`, the cross-user cart pointer, and "rendering the cart page is a write" |
| [references/checkout-configuration.md](references/checkout-configuration.md) | method country binding, `ShippingSave` fee sources and the flat-rate recipe, the posted payment/shipping field names, validation groups (no admin UI), the 1970 date sentinel, order-line fields, saved payment cards, the zero-value add-a-card journey |
| [references/order-states-and-quotes.md](references/order-states-and-quotes.md) | building a state ladder, the re-issued state id and dangling transition rows, `OrderCancel` + `OrderDelete`, `UpdateCartToQuote` / `DowngradeToCart`, the dead Accept-quote button |
| [references/order-notifications.md](references/order-notifications.md) | three mail settings and their three resolution roots, the template failure that is mailed to the customer, the page-route confirmation body, cart-flow mail, asserting on Queue UNION Badmail |
| [references/customer-center-surfaces.md](references/customer-center-surfaces.md) | the apps' declared settings keys, nothing-rendered vs the empty state, which apps honour `RetrieveListBasedOn`, the omitted payment method, translation-resolved fields |
| [references/rma-and-claims.md](references/rma-and-claims.md) | creating a claim the customer center can see, claim numbering, state renames, the RMA service cache flush, the ViewModel-driven RMA app, the RMA notification mail |
| [references/promotions-engines.md](references/promotions-engines.md) | the two coexisting discount engines (and which verb writes the one the admin screen reads), the voucher grid's legacy-row projection, v2 condition/reward payload shapes, voucher code constraints, the encrypted gift-card code |

## Pitfalls

**Form must have `id="ordersubmit"`** — the Shopping Cart app binds to this ID. A missing or different ID prevents checkout submission from working.

**`EcomOrderCustomerCountry` expects ISO code** — passing a display name ("Germany") instead of the code ("DE") causes country lookup to fail.

**Payment/shipping availability** — a method whose country-relation set does not contain the order's delivery country is filtered out, and the step then renders **zero options, no error and no empty state**, so checkout silently cannot complete. Payment often masks it: the shipped payment methods may already relate to the target country while none of the shipping methods do. Assert a non-zero delivery-option count for the target country.

**Quote vs order** — "Checkout to quote" on the Shopping Cart app changes the checkout step output. The quote appears under Commerce > Quotes, not Commerce > Orders.

## Next Steps

- **Setting up assortments or B2B flows?** See [dw-commerce-b2b](../dw-commerce-b2b)
- **Displaying the product catalog?** See [dw-commerce-catalog](../dw-commerce-catalog)
- **Custom checkout handler / payment gateway?** See [dw-extend-providers](../dw-extend-providers)
- **Reacting to order events in code?** See [dw-extend-providers](../dw-extend-providers)
