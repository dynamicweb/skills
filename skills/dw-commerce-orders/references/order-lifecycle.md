# Order lifecycle internals — seeding, saves, invoices, subscriptions, CSR impersonation

Field-validated DW10 order knowledge: what `create_orders` actually writes, the platform-owns-the-id
rule on every `*Save`, the re-save-reverts-SQL trap and the flush-then-touch ordering that makes a SQL
touch-up survive, invoices as `EcomOrders` rows, subscriptions, reorder mechanics, and CSR
sales-on-behalf impersonation.

Sibling references in this skill: [`cart-commands.md`](cart-commands.md),
[`checkout-configuration.md`](checkout-configuration.md),
[`order-states-and-quotes.md`](order-states-and-quotes.md),
[`order-notifications.md`](order-notifications.md),
[`customer-center-surfaces.md`](customer-center-surfaces.md),
[`rma-and-claims.md`](rma-and-claims.md), [`promotions-engines.md`](promotions-engines.md).

## Contents

- [Order completion: created orders default to carts](#order-completion-created-orders-default-to-carts-not-completed-orders)
- [OrderCustomerNumber is not set by create_orders](#ordercustomernumber-is-not-set-by-create_orders)
- [Area-currency filters order history](#area-currency-filters-order-history)
- [Order-line prices: seed after the currency restart](#order-line-prices-seed-after-the-currency-restart-then-backfill-totals)
- [The platform OWNS ids and timestamps](#the-platform-owns-ids-and-timestamps--a-save-discards-the-ones-you-send)
- [A re-saving verb reverts raw-SQL edits](#a-re-saving-verb-reverts-raw-sql-edits--orderrecalculate-writes-the-cached-order-back)
- [`GetOrderList` inner-joins `EcomShops`](#getorderlist-inner-joins-ecomshops--orders-on-a-deleted-shop-vanish-from-every-commerce-grid)
- [An invoice is an `EcomOrders` row](#an-invoice-is-an-ecomorders-row--and-invoicesave-requires-orderstateid)
- [Subscriptions have no create verb](#subscriptions-have-no-create-verb--the-shape-is-one-flag-plus-an-ecomrecurringorder-row)
- [RMA and claims live in their own reference](#rma-and-claims-live-in-their-own-reference)
- [SQL backfills vs runtime subscribers](#sql-backfills-vs-runtime-subscribers)
- [The canonical order read surface](#the-canonical-order-read-surface)
- [CSR sales-on-behalf — impersonation mechanics](#csr-sales-on-behalf--impersonation-mechanics)
- [Reorder a past order](#reorder-a-past-order--built-in-but-it-appends-to-an-existing-active-cart)
- [Seeding the CSR/account section's data](#seeding-the-csraccount-sections-data)

## Order completion: created orders default to carts, not completed orders

`create_orders` seeds rows into `EcomOrders` with `OrderComplete=0` —
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
`complete_order` tool exists and works on individual orders, but it
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

**On a CREATE, `OrderSave` and `InvoiceSave` mint their own id from the `EcomNumbers` counters (`ORDER`,
`LEDGERENTRIES`) and discard `Model.Id`.** The create/update switch is **`model.AutoId < 1`**, so this is
conditioned on `AutoId` and not on `Id`: a model round-tripped from `GetOrderById` carries a real `AutoId`
and **updates in place** (measured, row count 430 to 430), while a hand-built model with `AutoId` unset
mints a new row no matter what `Id` it carries. They also ignore a caller-supplied date and stamp *now*;
`RmaCommentSave` ignores `Model.Created` the same way, and `Model.reference` does not persist through
`OrderSave` at all. So **any follow-up SQL keyed on the id or reference you sent addresses nothing** — and it
does so silently, updating zero rows with no error. One pass built twelve invoices with correct due dates,
keyed its follow-up SQL on the invoice numbers it had supplied, and shipped twelve rows all stamped with the
same creation minute and none linked to a source order. The row count was never checked; the defect was caught
by looking at the rendered screen.

- **After any `*Save`, read the id back from the response or a list query** — never assume the id you sent is
  the id that exists. Where the two keys must be reconciled, join through the list query that carries both
  (`InvoiceList` returns `id` = the minted ledger id **and** `invoiceNumber` = yours).
- **No verb anywhere in the order / invoice / RMA families can set a creation timestamp.** Backdating
  seeded data is therefore raw SQL **keyed on the minted id** — a sanctioned exception, and the only shape
  that works.
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
  behind it. **API writes first, SQL last, never re-save afterwards.** The discount family's instance of
  the same mechanism is in [`promotions-engines.md`](promotions-engines.md).
- **The related read-side behaviour needs no intervention.** Immediately after a write the grids serve the
  cached order model, but it turns over on its own within a couple of minutes and `GetOrderById` reads
  through to current values — **no recycle and no cache-bust verb is needed**, so do not add one to the
  recipe and do not read the brief staleness as a failed write.

Assert it: seeded order dates still match the intended backdated values **after the full build sequence
completes**, not after the SQL step.

### The SQL write is not only invisible to the cached service — the next save DESTROYS it

Staging a value on an order with an `UPDATE` and then running code that should react to it fails twice
over, and the second failure is the expensive one. The reading code loads the order through
`OrderService.GetById`, a **read-through cache**, so it holds the pre-`UPDATE` entity — the familiar
stale read. It then does what almost every order-touching path does, `Services.Orders.Save(order)`, and
**that save writes the whole cached entity back over the row**, reverting the column the SQL had set. A
`SELECT` immediately after the `UPDATE` says the write succeeded; a `SELECT` after the next unrelated API
save says it never happened. No error, no warning, no log line on either side. That is materially worse
than a stale read, because a stale read at least leaves the database telling the truth.

**Every SQL touch on a DW-cached table is a write, then a flush of the owning service, then the code
that reads it — and nothing may re-save the entity afterwards.** The ordered sequence is in
[`recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md) "Order the SQL write and the cache flush".

Both halves of that sequence are load-bearing, and they were measured on the same solution days apart.
**Skip the flush** and the staged value is read stale and then erased by the next save. **Do the flush**
and the write survives and is the shipped path: a bulk repoint of an order column by SQL followed by the
`OrderService` flush read back correctly through the platform's own read (MCP `get_orders_by_ids`) on
every changed row, with the rendered customer-center surfaces byte-identical before and after — which is
itself the proof that nothing else moved. **Local installs only**; a hosted install has no SQL rung, so
the operation has to be expressed through the Admin API verb that owns the column or not at all. The
per-entity flush table is in
[`cache-invalidation.md`](../../dw-data-access/references/cache-invalidation.md).

## `OrderSave` on an existing order is a reconciliation pass against live platform state

Editing one cosmetic string on a settled order through the sanctioned `/Admin/Api/OrderSave` path moved
**11 columns when exactly 1 was requested**, with HTTP 200 and `successful: true`. Three mechanisms
compose, and none of them warns:

- **`OrderSaveCommand.Handle()` unconditionally calls `Services.Orders.ForcePriceRecalculation(order)`
  immediately before `Services.Orders.Save()`.** Recalculation prices every line from the **LIVE
  catalogue**, so any order line whose SKU has since left `EcomProducts` re-prices to **0**. Measured on
  one historical order: unit price 18.16 to 0.00, `OrderPriceWithVAT` / `WithoutVAT` /
  `PriceBeforeFees*` all 18.16 to 0.00, on a SKU with zero rows in `EcomProducts` (22 of the 27 rows in
  that batch carried the same dead SKU).
- **`ShippingAndPaymentHelper.GetAvailableShippingMethods` filters on `model.DeliveryCountryCode` and
  BLANKS `model.ShippingMethodId` when the current method is not in the available list**, so a blank
  delivery country strips a real, active, unrestricted shipping method (`SHIP6`/FedEx to `""`, name and
  description with it).
- **`ValidateModel` refuses an empty `CustomerCountryCode`** (`400 {"CustomerCountryCode":["Billing
  country should be set."]}`), so the caller is FORCED to write a country it did not intend to change
  just to reach the save at all.

**Do not use `OrderSave` to edit a cosmetic field on a historical order.** Where a company or name string
on a settled order must change, the honest options are (a) a targeted SQL `UPDATE` on that string column
with **no** subsequent `OrderSave` or `OrderRecalculate` (either one re-zeroes it), or (b) saving only
orders whose every line SKU still resolves in `EcomProducts` AND whose delivery country is set. Restoring
afterwards through `OrderSave` is not available: the same recalculation re-zeroes it, and a shipping
method deleted from `EcomShippings` cannot be put back.

### `GetOrderById` returns RESOLVED DEFAULTS, so a full-state graft materialises fields the row never had

The read is not a faithful snapshot. The `Order` to `OrderDataModel` mapping **resolves a default payment
method** (the `EcomMethodCountryRelation` row with `MethodCountryRelIsDefault=1` for the resolved country)
into `model.paymentMethodId` when the order has none, and `OrderSaveCommand` then does
`order.PaymentMethodId = model.PaymentMethodId` unconditionally. Measured on a cart whose
`EcomOrders.OrderPaymentMethodId` was empty in the database: the GET model carried `"PAY2"`, and a save
that mutated only `customerCompany` persisted `OrderPaymentMethodId = "PAY2"` and
`OrderPaymentMethod = "Invoice"` to the row. The control (a cart whose row already carried `PAY2`) showed
no payment movement on the identical call. **The GET-change-one-field-POST idiom is therefore NOT an
identity operation on the untouched fields**, and blanking the field before the POST does not help: the
model has no null or omit semantics, and an empty string is itself a write.

**The safe idiom is a measured pre-flight plus a full-column post-diff:**

1. Before the save, pull the row with SQL and the model with the `*ById` verb, and **fail on any column
   where they disagree outside the intended set.** Every disagreement is a field the save will silently
   rewrite.
2. Pre-flight the recalculation hazards: every `EcomOrderLines.OrderLineProductId` resolves in
   `EcomProducts`, `OrderCustomerCountryCode` and `OrderDeliveryCountryCode` are both non-empty, and the
   current `OrderShippingMethodId` exists in `EcomShippings`.
3. After the save, diff **all 181 `EcomOrders` columns plus the order lines** and fail the run if any
   column outside the intended set moved.

Comparing only the fields you changed is exactly the check that misses this class of defect. Where a
shell cart carries only resolved defaults worth painting on, `OrderDelete` beats a graft.

(Note the read parameter: `GET /Admin/Api/GetOrderById?OrderId=<id>`, because `Id` answers 400.)

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

## RMA and claims live in their own reference

The whole return-merchandise surface — which surface creates a claim that the customer center can
see, the `EcomNumbers` claim-number counter, the three-write state rename, the persistent
`ReturnMerchandiseAuthorizationService` cache that every raw-SQL write owes a flush to, the
ViewModel-driven customer-center app, and the notification mail's own tag set — is in
[`rma-and-claims.md`](rma-and-claims.md).

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

**`EcomOrders.OrderTotalPrice` is a dead legacy column on 10.28: it reads `0.0` on a perfectly good
order.** Three orders placed through the real storefront checkout all showed `OrderTotalPrice 0.0` in SQL
while the receipt, the cart and the customer centre all showed the correct totals, which reads as a
pricing failure at order-conversion time. The live totals are **`OrderPriceWithVAT` /
`OrderPriceWithoutVAT`** (API `totalPriceWithVat` / `totalPriceWithoutVat`), and line amounts are
`OrderLineUnitPriceWithVAT` / `OrderLinePriceWithVAT`. **Never assert on `OrderTotalPrice`**; where a
`0.0` renders correctly on the storefront, this column is the explanation, not a defect.

**MCP `search_orders` cannot see a quote at all, under any filter.** A Dynamicweb quote is an `EcomOrders`
row with `OrderIsQuote=1` AND `OrderCart=1` (`orderType: "Cart"`), and `search_orders` excludes carts, so
searches by `userId`, by `stateId` and by `textSearch` all returned the real orders and never the quote
that the admin Quotes tab and `get_orders_by_ids` both show in full. It reads exactly like "the quote did
not reach the admin". **Read quotes with `get_orders_by_ids`, or through the admin UI Commerce → Orders →
Quotes tab** (click through the tab; the deep route does not resolve cold). Draw no conclusion about
quotes from a `search_orders` result.

**MCP `create_order_state` takes `orderType` as a STRING and `color` as hex.** The wrong type on either
answers a bare `"An error occurred invoking 'create_order_state'"` with nothing naming the offending
property. `orderType` is one of `Order` | `Quote` | `Cart` | `Recurringorder` | `LedgerEntry`, while
`EcomOrderStates.OrderStateOrderType` **stores an integer**, so reading the table and echoing its value
back is precisely what fails. `color` must be a hex literal (`#F59E0B`); the dashboard-widget palette
names (`orange`, `lightBlue`) are rejected here. The same verb UPDATES when an existing id is supplied,
which is how a shipped flow's states get re-spaced into a new pipeline. Verify by re-reading
`EcomOrderStates` for the flow and asserting both the new ids and a gapless `sortOrder`, then assert the
state name rendered in the storefront order list.

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

**`Redirect` takes a RELATIVE URL and is used verbatim** — `Redirect=Default.aspx%3FId%3D<pageId>`,
percent-encoded because it carries a querystring of its own; the shipped templates build it as
`Uri.EscapeDataString("Default.aspx?Id=" + pageId)`. Every neighbouring parameter in that link is a
bare id, so `Redirect=Id=<n>` is the natural guess and it redirects to `/Id=<n>`, which 404s — **after
the identity switch has already succeeded**, leaving the session impersonating somebody on a
not-found page with nothing in the response naming the cause. Going back does not undo it.

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

**Required follow-up, not picked up live.** After the SQL change: (1) **rebuild the Secondary user
index** (the lookup is index-backed); (2) **clear the user/system cache** (DW caches `AccessUser`
objects in process).

The rebuild is a **two-call** sequence, because `BuildIndex` hard-requires a `BuildName` that the index
model does not expose. Resolve the builder first, then build:

```
GET  /Admin/Api/IndexBuildersByRepositoryAndIndexName?Repository=Secondary%20users&IndexName=Users.index
     -> name "Users", assemblyQualifiedName Dynamicweb.Security.UserManagement.Indexing.UserIndexBuilder
POST /Admin/Api/BuildIndex {"Repository":"Secondary users","IndexName":"Users.index","BuildName":"Users"}
     -> ok;  IndexStatusesAll then reports "Secondary users|Users.index" state=success
```

`IndexByRepositoryAndName` returns only counts (`balancerTypeName`, `schemaExtenderFieldsCount`,
`indexFieldsCount`) and **no builds collection**, so the build name is not discoverable from it, and
`BuildIndex` without `BuildName` answers `400 {"BuildName":["The value is required."]}` although the
OpenAPI schema marks all three properties as plain optional strings. Note also the parameter-name split
across sibling queries: `IndexByRepositoryAndName` and `IndexBuildersByRepositoryAndIndexName` take
**`Repository` + `IndexName`**, while `IndexInstancesByRepositoryAndIndex` takes **`RepositoryName` +
`IndexName`** — the wrong one answers `400 "Unable to load query parameters"`
([`index-management.md`](../../dw-search-indexing/references/index-management.md)).

The cache half is triggerable from the admin UI or the admin API (the UI buttons wrap the same
endpoints): Settings → System info → Cache. If the bar still
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
a scripted walkthrough: a Reorder click right after checkout (the cart was just emptied) does nothing.
Put any line in the cart first (a normal add-to-cart creates the cart) or place the reorder step
before checkout. A Reorder button is one line of Razor in an Order-detail content-layout — no
`.cs`, no preflight.

## Seeding the CSR/account section's data

When you seed customer-experience data yourself (MCP `create_orders` + `add_products`, or SQL) instead
of relying on pre-provisioned baseline content, stock filters silently hide otherwise-correct data:

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
Permission entity store's job; see
[`page-gating.md`](../../dw-users-permissions/references/page-gating.md) §15. DC-scoped buyer
catalogs/shipping that a CSR impersonates onto are
[`dc-scoping.md`](../../dw-commerce-b2b/references/dc-scoping.md).)
