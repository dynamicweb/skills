# Out-of-product recipes — Commerce

This reference holds the out-of-product recipes for commerce (orders, carts, checkout, RMA and claims, discounts and vouchers, catalog publishing): Management API
commands at `/admin/api/...`, serializer layers, and direct SQL. The in-product skills for this
area are `dynamo: true` and carry no instruction on those surfaces, so they keep a one-line pointer
here instead of the recipe.

Every recipe names its surface in the repo convention, and every SQL recipe states inline why the
higher surfaces do not cover it, that it is **local installs only**, and the cache flush or host
restart it owes. RMA and claims: [`recipes-commerce-rma.md`](recipes-commerce-rma.md).

## Contents

**Orders and order states**

- [Building an order-state ladder](#building-an-order-state-ladder)
- [A deleted state's id is re-issued, and its transition rows survive](#a-deleted-states-id-is-re-issued-and-its-transition-rows-survive)
- [Removing an order: `OrderCancel` then `OrderDelete`](#removing-an-order-ordercancel-then-orderdelete)
- [Order the SQL write and the cache flush](#order-the-sql-write-and-the-cache-flush)
- [Swift 2's Accept-quote button cannot work on a quote](#swift-2s-accept-quote-button-cannot-work-on-a-quote)

**Carts**

- [Two gates every scripted cart command must pass](#two-gates-every-scripted-cart-command-must-pass)
- [`archive` does not archive — it clears the active-cart pointer](#archive-does-not-archive--it-clears-the-active-cart-pointer)
- [The active-cart pointer is adopted with no ownership check](#the-active-cart-pointer-is-adopted-with-no-ownership-check)

**Checkout configuration**

- [Method country binding is what decides whether checkout can complete](#method-country-binding-is-what-decides-whether-checkout-can-complete)
- [Counting an assortment's built item set](#counting-an-assortments-built-item-set)
- [The v2 discount engine needs a global-settings activation](#the-v2-discount-engine-needs-a-global-settings-activation)
- [The method save models carry the countries and the fees the MCP tools do not](#the-method-save-models-carry-the-countries-and-the-fees-the-mcp-tools-do-not)
- [`ShippingSave` takes two fee sources, and the flat-rate recipe](#shippingsave-takes-two-fee-sources-and-the-flat-rate-recipe)
- [Writing `EcomValidation*` rows by hand](#writing-ecomvalidation-rows-by-hand)
- [Order-LINE fields need no storage column — but they need a relation row](#order-line-fields-need-no-storage-column--but-they-need-a-relation-row)
- [The zero-value "add a card" journey needs one global setting](#the-zero-value-add-a-card-journey-needs-one-global-setting)

**Catalog**

- [`ProductHidden` is enforced in SQL and unwritable by every API](#producthidden-is-enforced-in-sql-and-unwritable-by-every-api)
- [The two stock tables: asserting the aggregate matches the locations](#the-two-stock-tables-asserting-the-aggregate-matches-the-locations)

**Order capture**

- [Driving an order capture from outside the product](#driving-an-order-capture-from-outside-the-product)

---

- [Census the customer numbers of one account's contacts](#census-the-customer-numbers-of-one-accounts-contacts)

# Orders and order states

## Building an order-state ladder

MCP `create_order_state` reaches no column beyond the ones it names: it has no parameter for
`AllowEdit`, `AllowOrder` or any of the ten `EcomOrderStates` mail columns. A full state ladder is
therefore MCP create, then a `SQL` pass over the remaining columns, then a Management API
`CacheInformationRefresh` (at `/admin/api/CacheInformationRefresh`) of
`Dynamicweb.Ecommerce.Orders.OrderStateService` — and `…Orders.OrderFlowService` when the flow
moved. SQL because no verb writes those columns; **local installs only**; it owes the flush named
above.

Verify by re-reading `EcomOrderStates` for the flow and asserting both the new ids and a gapless
sort order, then asserting the state name as the storefront order list renders it.

## A deleted state's id is re-issued, and its transition rows survive

`delete_order_state` leaves dangling `EcomOrderStateRules` rows, and the id generator re-issues a
deleted state's id into any flow, so the dangling rules become valid-looking cross-flow
transitions. Nothing surfaces this. A two-ended `LEFT JOIN` is the only check that sees it:

```sql
-- read-only integrity gate; run it in the same transaction as the state writes.
-- SQL because no verb reads the rule table; local installs only; owes no flush (read-only).
SELECT COUNT(*) FROM EcomOrderStateRules r
LEFT JOIN EcomOrderStates f ON f.OrderStateId = r.OrderStateRuleFromState
LEFT JOIN EcomOrderStates t ON t.OrderStateId = r.OrderStateRuleToState
WHERE f.OrderStateId IS NULL OR t.OrderStateId IS NULL OR f.OrderFlowId <> t.OrderFlowId;
-- must be 0
```

When a flow is inherited in this state, rebuilding its rule set from scratch behind that assertion
is cheaper than repairing it row by row.

## Removing an order: `OrderCancel` then `OrderDelete`

MCP `delete_order`, and MCP `update_orders` + `set_order_state`, are rung 1 for this and reach the
same domain service. The Management API pair below is the equivalent when MCP is absent. The two
verbs bind different key names, and neither error names the offending field:

```
POST /admin/api/OrderDelete {"OrderId":"…"}   -> {"status":"invalid","message":"No items selected"}
POST /admin/api/OrderDelete {"OrderIds":[…]}  -> {"status":"invalid","message":"No items selected"}
POST /admin/api/OrderDelete {"Ids":["…"]}     -> bound

-- the working pair for a completed order
POST /admin/api/OrderCancel {"Id":"<orderId>"}    -> ok
POST /admin/api/OrderDelete {"Ids":["<orderId>"]} -> ok   (OrderDeleted = 1, state moved)
```

`OrderCancel` binds the singular `Id`; `OrderDelete` binds the plural `Ids`. Reusing one payload
for the other fails with `"Selected order is not found. The order id: ."`, whose empty id is the
only clue that the key name was wrong. Carts and incomplete orders take `OrderDelete` on their own.

A raw `UPDATE` of `OrderDeleted` is not the way round the completed-order refusal: the write is
invisible to the cached `OrderService` and the next save of that cached entity destroys it.

## Order the SQL write and the cache flush

Every SQL touch on a DW-cached table follows this sequence, and both halves are load-bearing:

```
UPDATE …                                            -- the SQL write
POST /admin/api/CacheInformationRefresh             -- flush the owning service by verb
     {"CacheTypeName":"Dynamicweb.Ecommerce.Orders.OrderService"}
… then run anything that touches the entity, and let nothing re-save it afterwards.
```

Skip the flush and the staged value is read stale and then erased by the next save. Do the flush
and the write survives: a bulk repoint of an order column by SQL followed by the `OrderService`
flush read back correctly through MCP `get_orders_by_ids` on every changed row. **Local installs
only**; a hosted install has no SQL rung, so the operation has to be expressed through the verb
that owns the column or not at all. The per-entity flush table is in
[`cache-invalidation.md`](cache-invalidation.md).

## Swift 2's Accept-quote button cannot work on a quote

The shipped quotes-list template's Accept action is an htmx `hx-get` against the delivery API route
`/dwapi/ecommerce/carts/<order secret>` with a template header naming the accept modal, and that
endpoint validates that the order is a cart:

```
GET /dwapi/ecommerce/carts/<secret>
  -> 400  "The cart is not a cart but not completed. IsCart: False Complete: False IsProcessingCheckout: False."
GET /dwapi/ecommerce/carts/<secret>  + the template header
  -> 500  "Model is required for view model templates."   (and one event-log entry per attempt)
```

A quote is by definition not a cart and not complete, so the endpoint refuses every order the
button is ever rendered for.

---

# Carts

## Two gates every scripted cart command must pass

A scripted cart proof needs a browser User-Agent and redirect-following — not necessarily a
browser. The add family is refused outright for a "bot" User-Agent, and `curl` and `wget` are both
in the platform's own match list, so the command still runs, the cart row is created and the 302 is
issued while zero order lines are added:

```
POST /Default.aspx  (default curl UA)   ID=<n>&cartcmd=setmulti&ProductLoopCounter1=1&ProductID1=SKU-0001&Quantity1=3
  -> 302; a cart is created for the signed-in user; 0 rows in EcomOrderLines
the same request with -A "Mozilla/5.0 … Chrome/… Safari/537.36"
  -> 302; the cart carries SKU-0001 x3
```

`curl -L` turns the final checkout POST's receipt redirect into an HTTP 411; `curl --post301
--post302` preserves the body.

## `archive` does not archive — it clears the active-cart pointer

`CartService.ClearCart` drops the session cart key, removes `EcomCustomerDataLoaded`, and runs
`UPDATE AccessUser SET AccessUserCartID = NULL WHERE AccessUserID = <id>`. That is its entire
effect on the database — it is the platform's own repair for a poisoned pointer, below.

## The active-cart pointer is adopted with no ownership check

Until the platform discards a pointer whose owner does not match, normalise the pointers so that
every `AccessUserCartId` is NULL or a cart the user actually owns:

```sql
-- local installs only. No verb writes AccessUserCartId (CartCmd=archive clears one pointer,
-- for the signed-in user only), and the User object is cached: this write owes ONE
-- application-pool recycle, or a CacheInformationRefresh of the user service.
UPDATE u SET u.AccessUserCartId = NULL
FROM AccessUser u
LEFT JOIN EcomOrders o
       ON o.OrderId = u.AccessUserCartId AND o.OrderCustomerAccessUserId = u.AccessUserId
WHERE u.AccessUserCartId IS NOT NULL AND o.OrderId IS NULL;
```

Assert it per persona: the `DynamicwebEcomCart<userId>` cookie is absent for a user who owns no
cart, and a rendered cart total matches only carts whose `OrderCustomerAccessUserId` equals that
user.

---

# Checkout configuration

## Method country binding is what decides whether checkout can complete

Prefer MCP `save_shipping_methods` / `save_payment_methods` with `countryRelationKeys`, which write
the relation rows through the domain service; Management API `ShippingSave` / `PaymentSave` are the
same operation one rung down.

Writing the relation rows directly (`EcomMethodCountryRelation`) is legitimate only when neither
surface is in play, and carries one schema trap: **`MethodCountryRelRegionCode` is `NOT NULL`**,
unlike every other optional column on that table. A country-only relation with no region
restriction must supply `''`, not `NULL`; `NULL` terminates the whole `INSERT` and nothing in the
shape of the table hints at it. That write is **local installs only** and owes an order-method
cache flush before the storefront reflects it.

## Counting an assortment's built item set

`check_assortment_product_access` answers `true` for every product, every user and anonymous alike, so
it cannot be used to confirm an assortment's scope, and no tool projects the materialised item set. The
in-product membership read is `get_assortments_by_product` on an in-scope and an out-of-scope product;
the **count** is out of product.

**Surface: `SQL`.**

```sql
SELECT COUNT(*) FROM EcomAssortmentItems WHERE AssortmentItemAssortmentId = '<assortmentId>';
SELECT COUNT(*) FROM EcomAssortmentShopRelations WHERE AssortmentShopRelationAssortmentId = '<assortmentId>';
```

An item count equal to the whole catalogue is the signature of a shop relation on the assortment: the
build unions the relation sets, so one shop relation replaces the intended scope. The second query is
how a shop relation is confirmed present after `remove_shops_from_assortment` reported removing it —
that tool is write-inert, so the assortment is deleted and rebuilt rather than repaired.

- **Why the higher surfaces do not cover it** — no tool projects the built item set, and the only access
  read answers `true` unconditionally.
- **Local installs only** — on a hosted install, compare the storefront catalogue rendered to a holder
  against the one rendered to a non-holder.
- **The debt it owes** — none; these are reads.

## The v2 discount engine needs a global-settings activation

Rows written by the v2 (Adjustments) discount tools land in `EcomDiscounts` and are **read by nothing at
cart time** until the new discount experience is activated in the host's global settings. The baseline
ships no activation block, so on a stock host a correctly conditioned, correctly rewarded, active
discount leaves the signed-in cart at full list price with no error anywhere in the chain — while a
customer-number contract price in the same cart resolves correctly, which makes it read as a
mis-configured discount rather than a dormant engine.

**Surface: host configuration** (`GlobalSettings`), then a **host restart**. Confirm before building:
the Ecommerce global-settings file carries no discount-experience key on an unactivated host — a grep
for the discount term returns only the order-line organisation setting.

- **Why the higher surfaces do not cover it** — no MCP tool and no Management API verb activates the
  engine, and no read reports that it is dormant; `get_adjustment_discount` serves the rows back
  either way.
- **Local installs only** — on a hosted install this is a request to whoever owns the host.
- **The debt it owes** — a host restart, then the only valid proof: sign in as a member of the
  conditioned group, add a product with a known list price, and read the **cart line amount**.

## The method save models carry the countries and the fees the MCP tools do not

MCP `save_shipping_methods` carries only `id`, `name`, `description`, `active`, `allowAnonymousUsers`,
`eligibleForFreeShipping`, `serviceSystemName`, `code`, `agentCode`, `agentServiceCode`, `minWeight`,
`maxWeight`, `freeFeeAmount` and `sorting`; `save_payment_methods` carries only `id`, `name`,
`description`, `active`, `code`, `termsCode`, `gatewayId`, `checkoutSystemName`, `allowAnonymousUsers`
and `sorting`. Neither has `countryRelationKeys`, `feeRulesSource` or `defaultFee`, and the reads are
just as narrow. The Management API save models do carry them, so country binding and fees are an
out-of-product step on this MCP line (or an admin-screen edit in product).

```
POST /admin/api/ShippingSave
{ "model": { "Id": "<id>", "Name": "<name>", "Description": "…", "Active": true, "Sorting": 1,
             "DefaultFee": 9.50, "FreeFeeAmount": 0, "EligibleForFreeShipping": false,
             "CountryRelationKeys": ["<code>", "<code>"], "FeeRulesSource": "matrix",
             "MaxWeight": 0, "AllowAnonymousUsers": true } }
```

Two shape rules, both measured: **the `model` wrapper is mandatory** (omitting it answers
`400 Command.Model cannot be null`), and **`Name` is mandatory on every save**, including one that
only means to add country relations (a model of `Id` plus `CountryRelationKeys` answers
`400 Name: The value is required`). `PaymentSave` takes the same wrapper and the same mandatory name.
Read the echo back: it carries the relation keys, the fee source and the default fee.

- **Why the higher surfaces do not cover it** — the MCP models are a narrower projection, on both the
  write and the read side.
- **Hosted installs included** — this is an API call, not SQL.
- **The debt it owes** — none; both go through the domain service. Gate on the rendered delivery step
  showing a non-zero option count for the target country.

## `ShippingSave` takes two fee sources, and the flat-rate recipe

MCP `save_shipping_methods` is rung 1 for name, description, activation and sorting; it does not carry
the fee fields. The Management API equivalent:

```
POST /admin/api/ShippingSave
{ …, "feeRulesSource": "matrix", "maxWeight": 0, "defaultFee": 18.50,
     "countryRelationKeys": [ … ] }
-> ok.  EcomShippings.ShippingFeeRulesSource = 2, ShippingPriceOverMaxWeight = 18.50, no EcomFees rows
```

`EcomShippings.ShippingFeeRulesSource` has exactly two API strings on 10.28.x: `provider` (1) and
`matrix` (2). Anything else throws inside the invocation and surfaces as a bare
`HTTP 500 "Exception has been thrown by the target of an invocation"` with no field name.

## Writing `EcomValidation*` rows by hand

There is no admin UI for validation groups and no MCP tool or Management API verb reaches these
three tables at all, so the rows are written directly. **Local installs only**; the cart app picks
the rows up on the next request with no flush, but a paragraph-settings change alongside it owes
the usual paragraph cache turnover. `ValidationFieldType` takes the C# **enum member NAME** as a
string (`CustomOrderField`, `StandardOrderField`, `OrderLineField`), `ValidationRuleType` the
**fully-qualified** rule class name, and every `*AutoId` column is `IDENTITY` — never supply one.

```sql
INSERT INTO EcomValidationGroups
  (ValidationGroupId, ValidationGroupName, ValidationGroupDoNotValidateIfAllFieldsAreEmpty)
VALUES ('VALIDATIONGROUP10', 'Checkout', 0);

INSERT INTO EcomValidations
  (ValidationId, ValidationGroupId, ValidationFieldName, ValidationUseAndOperator, ValidationFieldType)
VALUES ('VALIDATION30', 'VALIDATIONGROUP10', '<CustomOrderFieldSystemName>', 1, 'CustomOrderField');

INSERT INTO EcomValidationRules
  (ValidationRuleId, ValidationRuleValidationId, ValidationRuleType, ValidationRuleParameters)
VALUES ('VALIDATIONRULE30', 'VALIDATION30',
        'Dynamicweb.Ecommerce.Orders.Validation.Rules.RequiredRule', '0');
```

Bind the group to the cart app's `ValidationGroups` setting and list the individual validation ids
in `SelectedValidations`. Prove it by submitting the step with the field empty and asserting the
step blocks.

## Order-LINE fields need no storage column — but they need a relation row

The definition is an `EcomOrderLineFields` row (`OrderLineFieldSystemName`, `OrderLineFieldName`,
`OrderLineFieldLength`). `SQL`, because no MCP tool and no Management API verb creates one;
**local installs only**; flush `Dynamicweb.Ecommerce.Orders.OrderService` and
`…Orders.OrderLineFieldService` with Management API `CacheInformationRefresh` afterwards. The
second row, `EcomOrderLineFieldGroupRelation` for the shop, is written the same way. Both rows are
load-bearing: a definition alone is inert, and the value entry is materialised when the order line
is created, from the relation set as it stood at that moment — so add the relation first, then
re-add the line.

## The zero-value "add a card" journey needs one global setting

One write turns the journey on. No MCP tool reaches global settings:

```
POST /admin/api/GlobalSettingSave
{"Model":{"key":"/Globalsettings/Ecom/Cart/DoNotDeleteCartsWithZeroOrderlines","value":"True"}}
GET  /admin/api/GlobalSettingByKey?key=/Globalsettings/Ecom/Cart/DoNotDeleteCartsWithZeroOrderlines
  -> {"value":"True"}
```

The setting is absent from a stock `GlobalSettings.config`, and therefore `False`.

---

# Catalog

## `ProductHidden` is enforced in SQL and unwritable by every API

No API surface exposes the column and there is no admin control, so SQL is the only write path on
DW 10.28.x:

```sql
-- read: how many products the listing will count and not render
SELECT COUNT(*) FROM EcomProducts WHERE ProductHidden = 1;

-- the only write path: no API surface exposes the column, and there is no admin control.
-- Local installs only. Afterwards, invalidate the product cache — an MCP patch_products_safe
-- no-op on the affected ids is enough, and no application-pool recycle is needed.
UPDATE EcomProducts SET ProductHidden = 0 WHERE ProductHidden = 1;
```

## The two stock tables: asserting the aggregate matches the locations

```sql
-- read-only invariant; snapshot it BEFORE any check that places its own order,
-- or the check fails on its own side effect. SQL because no verb aggregates the two
-- tables against each other; local installs only; owes no flush (read-only).
SELECT COUNT(*) FROM (
  SELECT p.ProductId
  FROM EcomProducts p
  LEFT JOIN EcomStockUnit su ON su.StockUnitProductId = p.ProductId
  GROUP BY p.ProductId, p.ProductStock
  HAVING ISNULL(SUM(su.StockUnitQuantity), 0) <> p.ProductStock
) d;   -- must be 0
```

## Driving an order capture from outside the product

Surface: Management API `OrderCapture` via `POST /Admin/Api/OrderCapture`. The MCP tool set carries
no capture verb, so in the product the capture is done from the order's screen in the backend; this
is the headless route. The handler-side contract it drives — `OrderService.Capture` calling exactly
one of `IRemoteCapture` / `IRemotePartialCapture` and owning `order.CaptureAmount` itself — is in
`dw-extend-providers`, `references/checkout-handlers.md` ("Capture: the platform owns the running
total"), where that skill ships.

The model needs **both `Currency` and `CurrencyCode`**.
`{"Model":{"id":"ORDER32"},"CaptureAmount":5.00}` is rejected with
`{"":["Model validation failed"],"Currency":["The value is required."]}`, and a lower-cased
`"currency"` is rejected identically. The working body:

```json
{"Model":{"id":"ORDER32","Currency":"USD","CurrencyCode":"USD"},"CaptureAmount":5.00}
```

Read the capture back from the order rather than from the command's response: the platform stamps
`CaptureAmount` and `CaptureInfo` on a freshly loaded order and fires
`DWN_ECOM_ORDER_AFTER_ORDER_CAPTURED` after the handler returns.

## Census the customer numbers of one account's contacts

In-product home: [dw-commerce-b2b](../../dw-commerce-b2b/SKILL.md) (`account-shape.md`, "A
per-contact suffix makes account-wide delivery addresses a silent no-op").

Account-wide delivery addresses resolve by string equality on `AccessUserCustomerNumber`, so a
per-contact suffix turns the feature off with no error, warning or log entry. In-product the census
is `get_users_by_group_id` on the account group (or `get_users_by_customer_numbers` on the account's
own number) and a comparison of the `customerNumber` values that come back. Where the whole install
must be swept at once, the `SQL` form answers in one query; it is read-only, owes no flush, and runs
anywhere the database is reachable rather than on local installs only.

```sql
SELECT AccessUserCustomerNumber, COUNT(*)
FROM AccessUser WHERE AccessUserType = 5
GROUP BY AccessUserCustomerNumber;
```

If every contact has its own value, the feature cannot work and no setting will fix it.
