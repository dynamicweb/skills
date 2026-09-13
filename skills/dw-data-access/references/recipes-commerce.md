# Out-of-product recipes — Commerce

This reference holds the out-of-product recipes for commerce (orders, carts, checkout, RMA and claims, discounts and vouchers, catalog publishing): Management API
commands at `/admin/api/...`, serializer layers, and direct SQL. The in-product skills for this
area are `dynamo: true` and carry no instruction on those surfaces, so they keep a one-line pointer
here instead of the recipe.

Every recipe names its surface in the repo convention, and every SQL recipe states inline why the
higher surfaces do not cover it, that it is **local installs only**, and the cache flush or host
restart it owes. RMA and claims: [`recipes-commerce-rma.md`](recipes-commerce-rma.md). Orders and order
states, order totals, order dates and a test order placed from a seeded cart:
[`recipes-commerce-orders.md`](recipes-commerce-orders.md).

## Contents

**Carts**

- [Two gates every scripted cart command must pass](#two-gates-every-scripted-cart-command-must-pass)
- [`archive` does not archive — it clears the active-cart pointer](#archive-does-not-archive--it-clears-the-active-cart-pointer)
- [The active-cart pointer is adopted with no ownership check](#the-active-cart-pointer-is-adopted-with-no-ownership-check)

**Checkout configuration**

- [Method country binding is what decides whether checkout can complete](#method-country-binding-is-what-decides-whether-checkout-can-complete)
- [Counting an assortment's built item set](#counting-an-assortments-built-item-set)
- [Removing one assortment permission: `remove_permissions_from_assortment` is write-inert](#removing-one-assortment-permission-remove_permissions_from_assortment-is-write-inert)
- [The v2 discount engine needs a global-settings activation](#the-v2-discount-engine-needs-a-global-settings-activation)
- [The method save models carry the fees the MCP tools do not](#the-method-save-models-carry-the-fees-the-mcp-tools-do-not)
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

No MCP tool binds a method to a country. The `save_shipping_methods` and `save_payment_methods`
models carry no `countryRelationKeys` (the property lists are in "The method save models carry the fees
the MCP tools do not", below), so a relation set is written out of product or on the method's admin
screen.

**Management API `ShippingSave` / `PaymentSave` are not a proven route for the relation set.** On one
measured run [dw 10.28.10 · mcp 0.4.4] both accepted `countryRelationKeys` for six methods, answered
success and wrote nothing: `EcomMethodCountryRelation` held only the relations the methods already had,
the four shipping methods had none, and the signed-in checkout rendered one payment radio with an empty
value and no shipping-method group at all, while every MCP method read passed. The request body of that
run was not recorded, so it is one measurement and not proof that no API route exists: re-probe with a
full-model round trip and the row read-back below before relying on either answer.

The route known to land is `SQL` on `EcomMethodCountryRelation`, with one schema trap:
**`MethodCountryRelRegionCode` is `NOT NULL`**, unlike every other optional column on that table. A
country-only relation with no region restriction supplies `''`, not `NULL`; `NULL` terminates the whole
`INSERT`, and nothing in the shape of the table hints at it.

```sql
INSERT INTO EcomMethodCountryRelation
  (MethodCountryRelMethodId, MethodCountryRelCountryId, MethodCountryRelRegionCode)
VALUES ('<methodId>', '<countryCode>', '');
```

- **Why the higher surfaces do not cover it**: the MCP models have no relation member, and the
  Management API saves were measured accepting the keys and persisting nothing.
- **Local installs only**: on a hosted install, set the relations on each method's admin screen.
- **The debt it owes**: an order-method cache flush before the storefront reflects it.

Whatever the surface, two asserts close the step and both are mandatory. First, read
`EcomMethodCountryRelation` back and find one row per method per target country. Second, drive a
signed-in checkout for a buyer in that country to the payment step and count the named method radios
(`EcomCartShippingmethodID`, `EcomCartPaymethodID`): each step needs at least one with a non-empty
value. `get_shipping_methods` and `get_payment_methods` project no relation set and pass either way.

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

## Removing one assortment permission: `remove_permissions_from_assortment` is write-inert

MCP `remove_permissions_from_assortment` answers `{"succeeded":<n>,"failed":0,"errors":[]}` and deletes
nothing: `EcomAssortmentPermissions` is byte-identical afterwards, `get_assortment_permissions` still
returns the grant, and the user keeps resolving to the assortment. Its counterpart
`assign_permissions_to_assortment` writes correctly. In product, the repair is to delete the assortment
and rebuild it without the grant; removing the one row is out of product.

**Surface: `SQL`.**

```sql
DELETE FROM EcomAssortmentPermissions
WHERE AssortmentId = '<assortmentId>' AND AssortmentPermissionEntityId = <userOrGroupId>;
```

- **Why the higher surfaces do not cover it**: the only delete tool reports success and writes nothing,
  and the in-product alternative replaces the whole assortment.
- **Local installs only**: on a hosted install, delete and rebuild the assortment.
- **The debt it owes**: one application-pool recycle, because the User object caches its assortment
  ids. Then assert with `get_assortment_ids_by_user` on a member's USER id (a group id answers `[]`
  whatever the grants are) that the assortment is gone from the list.

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

## The method save models carry the fees the MCP tools do not

MCP `save_shipping_methods` carries only `id`, `name`, `description`, `active`, `allowAnonymousUsers`,
`eligibleForFreeShipping`, `serviceSystemName`, `code`, `agentCode`, `agentServiceCode`, `minWeight`,
`maxWeight`, `freeFeeAmount` and `sorting`; `save_payment_methods` carries only `id`, `name`,
`description`, `active`, `code`, `termsCode`, `gatewayId`, `checkoutSystemName`, `allowAnonymousUsers`
and `sorting`. Neither has `countryRelationKeys`, `feeRulesSource` or `defaultFee`, and the reads are
just as narrow. The Management API save models carry `DefaultFee` and `FeeRulesSource`, so fees are an
out-of-product step on this MCP line (or an admin-screen edit in product). The same models accept
`CountryRelationKeys`, but that write was measured persisting nothing: see "Method country binding"
above.

```
POST /admin/api/ShippingSave
{ "model": { "Id": "<id>", "Name": "<name>", "Description": "…", "Active": true, "Sorting": 1,
             "DefaultFee": 9.50, "FreeFeeAmount": 0, "EligibleForFreeShipping": false,
             "FeeRulesSource": "matrix", "MaxWeight": 0, "AllowAnonymousUsers": true } }
```

Two shape rules, both measured: **the `model` wrapper is mandatory** (omitting it answers
`400 Command.Model cannot be null`), and **`Name` is mandatory on every save**, including one that
only means to add country relations (a model of `Id` plus `CountryRelationKeys` answers
`400 Name: The value is required`). `PaymentSave` takes the same wrapper and the same mandatory name.
The echo is the request model, not a post-write read: assert the fee columns on `EcomShippings` and
any relation on `EcomMethodCountryRelation`.

- **Why the higher surfaces do not cover it** — the MCP models are a narrower projection, on both the
  write and the read side.
- **Hosted installs included** — this is an API call, not SQL.
- **The debt it owes**: none for the fee fields; both go through the domain service. Gate on the
  rendered delivery step showing a non-zero option count for the target country.

## `ShippingSave` takes two fee sources, and the flat-rate recipe

MCP `save_shipping_methods` is rung 1 for name, description, activation and sorting; it does not carry
the fee fields. The Management API equivalent:

```
POST /admin/api/ShippingSave
{ …, "feeRulesSource": "matrix", "maxWeight": 0, "defaultFee": 18.50 }
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
