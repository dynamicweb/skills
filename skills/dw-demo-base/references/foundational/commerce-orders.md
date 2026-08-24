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

## The platform OWNS ids and timestamps — a `*Save` discards the ones you send

**`OrderSave` and `InvoiceSave` mint their own id from the `EcomNumbers` counters (`ORDER`,
`LEDGERENTRIES`) and discard `Model.Id`.** They also ignore a caller-supplied date and stamp *now*;
`RmaCommentSave` ignores `Model.Created` the same way, and `Model.reference` does not persist through
`OrderSave` at all. So **any follow-up SQL keyed on the id or reference you sent addresses nothing** — and it
does so silently, updating zero rows with no error. One pass built twelve invoices with correct due dates,
keyed its follow-up SQL on the invoice numbers it had supplied, and shipped twelve rows all stamped with the
same creation minute and none linked to a source order. The row count was never checked; the defect was caught
by looking at the rendered screen.

- **After any `*Save`, read the id back from the response or a list query** — never assume the id you sent is
  the id that exists. Where the two keys must be reconciled, join through the list query that carries both
  (`InvoiceList` returns `id` = the minted ledger id **and** `invoiceNumber` = yours).
- **No verb anywhere in the order / invoice / RMA families can set a creation timestamp.** Demo backdating is
  therefore raw SQL **keyed on the minted id** — a sanctioned exception, and the only shape that works.
- Neighbouring shapes measured on the same pass: `OrderSave` validates the billing address, so a model without
  `customerCountryCode` answers `400 {"CustomerCountryCode":["Billing country should be set."]}`; and
  `OrderRecalculate` takes **`OrderId`, singular** — passing `Ids` answers
  `400 {"OrderId":["The value is required."]}`.

Assert it: every seeded order/invoice row is reachable by the id returned in its own save response, and
`OrderReference` / `OrderDate` match the intended values after the SQL pass.

## A re-saving verb reverts raw-SQL edits — `OrderRecalculate` writes the CACHED order back

`OrderRecalculate` does not just re-total. **It re-saves the entire entity from Dynamicweb's cached state**,
which predates any SQL written behind the API — so it silently reverts the backdate/tag/reference pass that
the section above makes mandatory. No error, no warning; eight orders reverted to creation-time dates and
empty references on the run that measured it.

```
FAILS:  OrderNew -> OrderSave -> OrderLineAddProductsBySKU -> SQL line qty -> SQL backdate+tag -> OrderRecalculate
WORKS:  OrderNew -> OrderSave -> OrderLineAddProductsBySKU -> SQL line qty -> OrderRecalculate -> SQL backdate+tag
                                                                                  (and nothing re-saves after)
```

- **The rule generalises past orders:** *any* API verb that re-saves an entity reverts raw-SQL edits made
  behind it. **API writes first, SQL last, never re-save afterwards** — stated once for every surface in
  [`../surface-priority.md`](../surface-priority.md) "Silent no-ops on write surfaces". The discount family's
  instance of the same mechanism is in [`promotions-engines.md`](promotions-engines.md).
- **The related read-side behaviour needs no intervention.** Immediately after a write the grids serve the
  cached order model, but it turns over on its own within a couple of minutes and `GetOrderById` reads
  through to current values — **no recycle and no cache-bust verb is needed**, so do not add one to the
  recipe and do not read the brief staleness as a failed write.

Assert it: seeded order dates still match the intended backdated values **after the full build sequence
completes**, not after the SQL step.

## `GetOrderList` inner-joins `EcomShops` — orders on a deleted shop vanish from every Commerce grid

**`GetOrderList` only returns rows whose `OrderShopId` resolves in `EcomShops`.** Orders carrying a shop id
that no longer exists are not missing — they are **invisible**, and no count, warning or discrepancy anywhere
in the admin UI reveals it. The Incomplete-orders screen read `0` while ten rows in `EcomOrders` satisfied its
exact predicate.

The arithmetic across three grids proves the join exactly: on one host the complete-orders SQL count split as
`live-shop + blank + dead-shop`, and the grid rendered exactly `live-shop + blank`. Blank `OrderShopId` rows
**do** render; only rows naming a shop that is absent from `EcomShops` disappear.

**Any order backfill must write an `OrderShopId` that exists in `EcomShops`, or leave it blank.** Gate it:

```sql
SELECT COUNT(*) FROM EcomOrders
 WHERE OrderShopId <> '' AND OrderShopId NOT IN (SELECT ShopId FROM EcomShops);   -- must be 0
```

This is a good candidate for the Ecommerce health provider to surface — worth raising with the vendor.

## An invoice is an `EcomOrders` row — and `InvoiceSave` requires `OrderStateId`

**There is no `EcomInvoice*` table.** An invoice is an `EcomOrders` row flagged `OrderIsLedgerEntry=1` with
`OrderLedgerType=Invoice`, plus `OrderIsPayable`, `OrderDueDate` and `OrderParentOrderId` pointing at the
source order. `InvoiceSave` wraps all of that.

- **`OrderStateId` is validated as REQUIRED at runtime although the OpenAPI schema marks it an ordinary
  optional string.** A model built faithfully from the published schema answers
  `400 {"OrderStateId":["OrderStateId is required"]}`.
- **The Ledgers grid's `Number` column shows the ledger ORDER id, not the invoice number** — the invoice
  number appears only in `InvoiceList` and on the detail view. Reconcile the two keys through `InvoiceList`
  (see the id rule above).
- **Any recent-orders harvest on a site with ledger rows needs `ISNULL(OrderIsLedgerEntry,0)=0`** — otherwise
  it counts invoices as orders. This bites sibling scripts (award/report/dashboard passes) that were written
  before invoices existed on the install.

Assert `InvoiceList` and the Ledgers grid agree on count, and that each invoice resolves to its source order
via `OrderParentOrderId`.

## Subscriptions have no create verb — the shape is one flag plus an `EcomRecurringOrder` row

The Subscriptions screen cannot be populated through a create command: the only recurring verb in the whole
catalogue is `OrderCancelRecurring`. Subscriptions are not a first-class creatable entity — they are a
two-part shape, and both parts matter:

- **`EcomOrders.OrderIsRecurringOrderTemplate = 1`** alone puts a row on the Subscriptions grid (this is what
  makes a one-part seed look successful).
- **An `EcomRecurringOrder` row** (`UserID`, `BaseOrderID`, `StartDate`, `EndDate`, `Interval`,
  `IntervalUnit`, `LastDelivery`) is what makes it *functional* — after which
  `FutureDeliveriesByRecurringOrderId` computes the forward schedule.

`RecurringOrderIntervalUnit` is an enum: **`0`=days, `1`=weeks, `2`=months, `3`=years**, confirmed by observed
delivery spacing. The proof that a seed is a working subscription rather than four rows in a table is the
engine deriving the schedule: four seeded subscriptions produced 5 / 18 / 4 / 12 forward deliveries from their
own start/end/interval, and the rendered screen showed "Every 1 months" / "Every 3 months" / "Every 6 months"
correctly. **Assert `FutureDeliveriesByRecurringOrderId` returns a non-empty schedule for every seeded
subscription.**

## The RMA read path is a persistent service cache that raw SQL cannot invalidate — and `RmaList` masks it

`RmaList` queries SQL directly; **`RmaById` / `RmaComments` serve a persistent
`ReturnMerchandiseAuthorizationService` cache that no SQL write invalidates.** After a SQL backdate the list
grid shows the new dates while the detail view keeps serving the pre-SQL object graph — including rows that
were deleted. **The correct-looking list is what hides the stale detail**, which is why this reads as a
rendering bug rather than a cache.

```
POST CacheInformationRefresh
{ "CacheTypeName": "Dynamicweb.Ecommerce.Orders.ReturnMerchandiseAuthorization.ReturnMerchandiseAuthorizationService" }
```

- **Any raw-SQL write to RMA data must be followed by that flush** — no recycle needed.
- **Match FULL type names when hunting a cache id.** Filtering the ~96-entry cache list with `-match "rma"`
  also matches `inteRMAtional`, `infoRMAtion` and `foRMAt`; the substring hunt is what makes the right entry
  hard to find.
- **Consequence for scheduled work: a SQL-only task cannot call that verb**, so a nightly date shift leaves
  the RMA detail view stale by design until the cache turns over. Say so when designing the beat rather than
  debugging it later.

Assert `RmaById` returns the same `CreatedAt` as the `RmaList` row after a SQL edit **plus** the flush.

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

(Discounts, vouchers, loyalty rewards and gift cards are their own surface — two coexisting discount
engines, a voucher grid fed by the legacy one, and an encrypted gift-card code — and live in
[`promotions-engines.md`](promotions-engines.md).)

(Gating the CSR section away from non-CSR users — and gating buyer dashboards away from the CSR — is the
Permission entity store's job; see [`users-permissions.md`](users-permissions.md) §15. DC-scoped buyer
catalogs/shipping that a CSR impersonates onto are [`dc-scoping.md`](../../../dw-commerce-b2b/references/dc-scoping.md).)
