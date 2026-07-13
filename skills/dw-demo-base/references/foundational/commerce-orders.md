# Foundational candidate → dw-commerce-orders

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 order-completion / customer-number seeding knowledge, staged here for a future
> fold-up into `dw-commerce-orders`. No demo/customer content. When folded, move this body into
> `dw-commerce-orders` and re-target the pointers in the demo skills. Until then, the demo skills
> reference this file.

## Order completion: created orders default to carts, not completed orders

`mcp__dynamicweb-commerce-mcp__create_orders` seeds rows into `EcomOrders` with `OrderComplete=0` —
i.e. **carts**, not completed orders. Surfaces that list order history (the account-side Orders
paragraph, CSR order-impersonation views) filter on `OrderComplete=1` and silently skip the cart
rows. The symptom is "I created N orders but the My Orders tab is empty," not an error.

When the rows are meant to be order *history* (not in-progress carts), backfill the flag in one SQL
after `create_orders` returns:

```powershell
sqlcmd -S "<dwserver>" -d <dwdb> -E -Q `
  "UPDATE EcomOrders SET OrderComplete = 1 WHERE OrderComplete = 0 AND OrderCart = 0 AND OrderID LIKE 'ORDER%'"
```

Scope the `WHERE` precisely enough to skip rows that are intentionally carts. The
`mcp__dynamicweb-commerce-mcp__complete_order` tool exists and works on individual orders, but it
runs the full price-recalc + workflow chain per call — slow for bulk seeding and able to fail when
pricing has unresolved currency / country gaps. Direct `UPDATE` is the right tool for bulk
completion; reserve `complete_order` for flows where the side-effects (workflow, email, inventory)
are intended.

## OrderCustomerNumber is not set by create_orders

The account-side Orders paragraph resolves order history via a `UseCustomerNumber` lookup against the
user's `AccessUserCustomerNumber`. `create_orders` populates `OrderCustomerAccessUserId` but **not**
`OrderCustomerNumber`, so B2B account-side displays render empty until it is backfilled:

```sql
UPDATE o
SET OrderCustomerNumber = u.AccessUserCustomerNumber
FROM EcomOrders o
JOIN AccessUser u ON u.AccessUserID = o.OrderCustomerAccessUserId
WHERE o.OrderCustomerNumber IS NULL OR o.OrderCustomerNumber = '';
```

## Area-currency filters order history

Account-side order lists filter by the **area's current currency**, not the order's stored
currency. If the `Area` row defaults to one currency/country and orders are seeded in another, the
order list renders empty silently. Align the area's default currency to the seeded
`OrderCurrencyCode` (or seed orders in the area's default) **before** backfilling completion.

## Order-line prices: seed after the currency restart, then backfill totals

`add_products` (the order-line seeding tool) writes **only the unit-price columns**
(`OrderLineUnitPriceWithoutVAT`/`WithVAT`) — it computes neither the line totals
(`OrderLinePriceWithoutVAT`/`WithVAT`) nor the order totals. And the unit price you pass is not
always the one that lands:

- **Change the default currency → restart → THEN seed.** A changed default currency only
  materializes on restart; order lines seeded before that restart can land with unit prices
  **×100** (a two-decimal exponent artifact — e.g. an explicit `12.50` stored as `1250`).
- **Qty-tier `EcomPrices` rows silently reprice seeded lines.** A line whose product/quantity
  matches a tier row is repriced to the tier price, ignoring the explicit `unitPriceWithoutVat`
  passed to the tool.
- **After seeding, run a sanity sweep + backfill in SQL:** flag any
  `OrderLineUnitPriceWithoutVAT` above a plausible maximum and ÷100-normalize it; then backfill
  the line totals (unit × quantity into `OrderLinePriceWithoutVAT`/`WithVAT`) and the order
  totals (`OrderPriceWithVAT`, `OrderPriceWithoutVAT`, `OrderPriceBeforeFees*`).

**Verify:** seed one order post-restart with an explicit price; assert
`OrderLineUnitPriceWithoutVAT` equals the requested value and the account-side order list shows a
non-zero total after an `OrderService` cache flush.

## SQL backfills vs runtime subscribers

The bulk SQL backfills above (`OrderComplete=1`, `OrderCustomerNumber`, and the related
`AccessUserPassword` seeding) are correct for **seed data** — the fastest path to populate from a
clean slate. For **runtime** flows (orders placed by users on the storefront, password resets), the
canonical DW10 paths differ:

- `OrderCustomerNumber`: a `[Subscribe(Order.BeforeSave)]` subscriber copies `user.CustomerNumber`
  to `order.CustomerNumber`.
- `OrderComplete=1`: setting `order.Complete = true` + `Services.Orders.Save(order)` auto-stamps
  `CompletedDate` (`Order.cs:250-271`); or call `complete_order`.
- `AccessUserPassword`: `UserManagementServices.Users.ChangePassword(user, pw)` +
  `Services.Users.Save(user)` (`UserService.cs:430,439`). `AuthenticationManager.cs:184` also
  auto-rehashes plaintext seeds on first successful login.

The `Order.BeforeSave` subscriber is a `.cs` file — a `NotificationSubscriber` ships unprompted, with
no config-surface prompt.

## The canonical order read surface

- **Read customer orders**: `Services.Orders.GetCustomerOrdersByType(int customerId, string shopIds,
  OrderType, int recurringOrderId, string customerNumber, string orderContextIds, DateTime fromDate,
  bool includeImpersonation, bool isCart, bool includeUserAndSecondaryUserIds)` (dw10source
  `Orders/OrderRepository.cs:1905`).
- **Search**: `Services.Orders.GetOrdersBySearch(OrderSearchFilter filter)`
  (`OrderRepository.cs:1196`).
- Both return `Order` aggregates with `.OrderLines` materialised.
- **Read customer orders via `Services.Orders.GetCustomerOrdersByType(...)`, never a hand-rolled
  multi-subquery `EcomOrders`/`EcomOrderLines` SQL chain in Razor.**

## CSR sales-on-behalf — impersonation mechanics

Customer 360 / sales-on-behalf is a differentiator only if the CSR can do it without custom code. The
stock customer-center CSR section already supports impersonation, mixed-source order viewing, cart
isolation, and one-click exit — the vendor-generic mechanics below are what make it work.

### The impersonation flow

The CSR-driven impersonation entrypoint is the **Users** page (lists individual users across accounts,
each row's actions menu has the "Impersonate" link), *not* the **Accounts** page (lists customer
groups/companies — by design a directory, "View account users"/"Edit account" only, no impersonate
button). Both share the `UserGroups` web-app module but render different views. The Impersonate link
uses the stock module command:

```
?NowImpersonating=true&DWExtranetSecondaryUserSelector=<targetUserId>&Redirect=<post-impersonation-url>
```

It sets the `Dynamicweb.Ecommerce.Customers.User.ImpersonatedUser` session value; the switch-back link
is `?DwExtranetRemoveSecondaryUser=1`. While impersonating, the customer's order list renders through
the same `Account/Orders/` paragraph (same template, same `OrderSource` discriminator), a header
banner ("Viewing as …") appears, and the cart shown is the impersonated customer's, not the CSR's. A
mixed-source-orders requirement (badge by source channel) maps onto this 1:1 — the badge text is
whatever the order's `OrderSource` column holds; rendering is paragraph-driven, no controller changes.

**Why the Accounts page can be empty while Users is populated.** The Accounts page's `UserGroups`
module filters by `ListGroupType` (stock = `SystemAccount`). An account group appears under Accounts
**only when its `AccessUser` row carries `AccessUserUserAndGroupType = 'SystemAccount'`**. A group made
via `save_user_groups` lands with that column NULL, so it never lists under Accounts even though its
members show under Users. Fix: set the flag on the account group, then refresh the security cache
(restart is the reliable way). Do **not** switch the module to `ListGroupType=''` to list everything —
that surfaces internal staff groups as if they were customer accounts.

### `AccessUserSecondaryRelation` — the impersonation grant

The session flow only fires if the DB knows *this CSR* may impersonate *this customer*. That lives in
one table:

| Column | Meaning |
| --- | --- |
| `AccessUserSecondaryRelationUserId` | The **impersonator** (the CSR) |
| `AccessUserSecondaryRelationSecondaryUserId` | The **customer** being impersonated |
| `AccessUserSecondaryRelationAutoId` | Surrogate key |

The naming is counter-intuitive ("Secondary user" reads as a sub-user, the opposite of DW's
interpretation). Verified direction (DW10 admin labels): the CSR's profile "Users this user can
impersonate" lists rows where the CSR's id is in `UserId`; the customer's profile "Users that can
impersonate this user" lists rows where the customer's id is in `SecondaryUserId`. A single grant:

```sql
INSERT INTO AccessUserSecondaryRelation
    (AccessUserSecondaryRelationUserId,            -- CSR id
     AccessUserSecondaryRelationSecondaryUserId)   -- customer id
VALUES (<csr_user_id>, <customer_user_id>);
```

**Symptom of wrong direction:** the impersonation bar is empty and the customer's admin profile shows
the CSR under "Users that can impersonate this user". Swap the two ids. Don't trust the column name;
trust the screen label.

**Required follow-up — not picked up live.** After the SQL change: (1) **rebuild the Secondary user
index** (the lookup is index-backed); (2) **clear the user/system cache** (DW caches `AccessUser`
objects in process). Both are triggerable from admin UI or the admin API (UI buttons wrap the same
endpoints) — Settings → Indexing (index) and Settings → System info → Cache (cache). If the bar still
doesn't list the customer after both, re-check the column direction, then check the CSR's
`AccessUserType` doesn't have the bit-16 *Service* flag (Service-flagged users are filtered out of
standard form-login flows).

## Reorder a past order — built in, but it APPENDS to an existing active cart

DW10 ships two zero-code surfaces that copy a past order's lines into the cart, repricing at
today's prices. **No backend code, no custom controller, no MCP tool:**

```
/Default.aspx?ID=<cart-service-page-id>&cartcmd=copyorder&orderid=<order-id>&redirect=true
<orders-page-url>?CustomerCenterCmd=Reorder&OrderId=<order-id>
```

The first is the cart command (`ID` = the cart service / cart-handling page id; `orderid` = the order
to copy — stock Order paragraphs expose `Model.Order.Id`; `redirect=true` returns to the cart). The
second is the customer-center command processed by the order-list paragraph's own page — verified on
DW 10.26 appending the order's lines with quantities merged per product/variant. **Related cart
commands** (`cartcmd=add` / `remove` / `delete` / `empty` / `update`) all flow through the same
handler as the first form.

**Both surfaces append to the session's ACTIVE cart and silently no-op when there is none** — neither
creates a cart, no error is rendered or logged, and valid order lines make no difference. The trap in
a demo script: a Reorder click right after checkout (the cart was just emptied) does nothing on
stage. Put any line in the cart first (a normal add-to-cart creates the cart) or place the reorder
beat before checkout. A Reorder button is one line of Razor in an Order-detail content-layout — no
`.cs`, no preflight.

## Seeding the CSR/account section's demo data

When you seed customer-experience data yourself (MCP `create_orders` + `add_products`, or SQL) instead
of relying on a flavoured baseline, stock filters silently hide otherwise-correct data:

- **Placed orders only show in "My orders" when `EcomOrders.OrderComplete = 1`** (and
  `OrderCompletedDate`). See "Order completion" above. Quotes/carts list by their own discriminators
  (`OrderIsQuote`, `OrderCart`) and don't need this.
- **Favorites seeded via SQL:** `EcomCustomerFavoriteProducts` has NOT-NULL `ProductVariantId`, `Note`,
  `ProductReferenceUrl`, `UnitId` — pass empty strings, never NULL. The list header is one
  `EcomCustomerFavoriteLists` row per user (`IsDefault = 1` for the default). The storefront reads it
  via `Pageview.User.GetFavoriteLists()`. There is no MCP tool for favorites — SQL-only.
- **Stock checkout reads the billing address from the user-*profile* fields, not from `UserAddress`
  records.** A buyer seeded with `save_user_addresses` (a Billing + Shipping `UserAddress`) but a blank
  profile address (`AccessUser.Address/Zip/City`) cannot complete checkout — stock
  `eCom7/CartV2/Step/InformationUser.cshtml` renders the "Continue" button only when an `addressString`
  built from `UserManagement:User.Address/Zip/City` is non-empty, and "Same as billing" reads those
  same profile fields. The default Shipping `UserAddress` still pre-selects, so the symptom reads as
  "no address selected" on the billing side only. Fix: populate the profile address too (`update_users`
  with `address/zip/city/state/country/countryCode`, mirroring the Billing `UserAddress`). Seed both
  for every buyer.

(Gating the CSR section away from non-CSR users — and gating buyer dashboards away from the CSR — is the
Permission entity store's job; see [`users-permissions.md`](users-permissions.md) §15. DC-scoped buyer
catalogs/shipping that a CSR impersonates onto are [`commerce-b2b.md`](commerce-b2b.md).)
