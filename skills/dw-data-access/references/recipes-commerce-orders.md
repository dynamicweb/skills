# Out-of-product recipes: Commerce orders and order states

This reference holds the out-of-product recipes for orders and order states: the state ladder, order
removal, the SQL-then-flush order, priced demo orders, stored totals, order dates, and a test order
placed from a seeded cart. The surfaces are a driven
storefront checkout, Management API commands at `/admin/api/...`, and direct SQL. The in-product skill
for this area, `dw-commerce-orders`, is `dynamo: true` and keeps a one-line pointer here instead of the
recipe. The other commerce recipes are in [`recipes-commerce.md`](recipes-commerce.md).

Every recipe names its surface, and every SQL recipe states inline why the higher surfaces do not cover
it, that it is **local installs only**, and the cache flush or host restart it owes.

## Contents

- [Priced demo orders: place them through the storefront checkout](#priced-demo-orders-place-them-through-the-storefront-checkout)
- [Repairing stored totals after an MCP line write](#repairing-stored-totals-after-an-mcp-line-write)
- [Backdating an order: SQL keyed on the minted id, written last, then a recycle](#backdating-an-order-sql-keyed-on-the-minted-id-written-last-then-a-recycle)
- [Reverting a test order placed from a seeded cart](#reverting-a-test-order-placed-from-a-seeded-cart)
- [Building an order-state ladder](#building-an-order-state-ladder)
- [A deleted state's id is re-issued, and its transition rows survive](#a-deleted-states-id-is-re-issued-and-its-transition-rows-survive)
- [Removing an order: `OrderCancel` then `OrderDelete`](#removing-an-order-ordercancel-then-orderdelete)
- [Order the SQL write and the cache flush](#order-the-sql-write-and-the-cache-flush)
- [Swift 2's Accept-quote button cannot work on a quote](#swift-2s-accept-quote-button-cannot-work-on-a-quote)

## Priced demo orders: place them through the storefront checkout

**Surface: the storefront checkout**, driven by a browser signed in as each buyer.

An order built with MCP tools carries no trustworthy stored totals [mcp 0.4.4]. `create_orders`
(`orderType: "Cart"`), then `add_products`, then `convert_cart_to_order` stored an order whose order
total and every line price were 0; `force_price_recalculation` returned a computed total and saved
nothing; `update_order_line` did not change it; and `validate_order_prices` compared the stored 0 with
itself and reported the order valid. The checkout runs the price provider for the signed-in buyer, so
the order it places carries that buyer's prices, fees and VAT. It works on hosted installs too.

1. Per buyer: sign in, add the lines through the cart with a browser User-Agent and redirects followed
   ([`recipes-commerce.md`](recipes-commerce.md) "Two gates every scripted cart command must pass").
2. Walk the steps posting each radio's parsed `name` attribute, accept the terms, complete.
3. **Untick card saving in the driver.** A stored card minted by the payment step has no administrative
   delete on any surface; only the cardholder can remove it on the storefront.
4. Assert on the order, never on a line: `get_orders_by_ids` shows a non-zero order total equal to the
   sum of the line totals plus fees.

The checkout converts the buyer's context cart in place, so a buyer whose seeded cart must survive is
not the buyer to place orders with (see "Reverting a test order placed from a seeded cart", below).

- **Why the higher surfaces do not cover it**: the MCP order tools persist no priced totals, and no tool
  saves a recalculation.
- **The debt it owes**: none; the checkout writes through the domain services.

## Repairing stored totals after an MCP line write

MCP `update_order_line` writes the unit price only. Measured over 17 calls, a line at quantity 2 and new
unit price 241.90 kept its line total of 102.00, and the order totals stayed at 153.00 and 195.00, so the
order showed unit prices that multiplied to neither its lines nor its total. `add_products` leaves the
same gap where it writes a price. Management API `OrderRecalculate` is not a proven repair: it re-saves
the cached order and reverts any SQL written behind it (`dw-commerce-orders`, `order-lifecycle.md`, "A
re-saving verb reverts raw-SQL edits").

**Re-place the order through the storefront** (above) wherever that is acceptable. Where the order must be
kept, re-total it:

**Surface: `SQL`.**

```sql
-- product lines only: an order carrying discount or fee lines is re-placed, not patched.
UPDATE EcomOrderLines
SET OrderLinePriceWithoutVAT = OrderLineUnitPriceWithoutVAT * OrderLineQuantity,
    OrderLinePriceWithVAT    = OrderLineUnitPriceWithVAT    * OrderLineQuantity
WHERE OrderLineOrderId = '<orderId>';

UPDATE o
SET o.OrderPriceBeforeFeesWithoutVAT = s.WithoutVat, o.OrderPriceBeforeFeesWithVAT = s.WithVat,
    o.OrderPriceWithoutVAT = s.WithoutVat, o.OrderPriceWithVAT = s.WithVat
FROM EcomOrders o
CROSS APPLY (SELECT SUM(OrderLinePriceWithoutVAT) AS WithoutVat, SUM(OrderLinePriceWithVAT) AS WithVat
             FROM EcomOrderLines WHERE OrderLineOrderId = o.OrderId) s
WHERE o.OrderId = '<orderId>';
```

Add the order's shipping and payment fees to `OrderPriceWithoutVAT` / `OrderPriceWithVAT` where it carries
any. `OrderTotalPrice` was also left stale on the measured run: set it the way a checkout-placed order on
the same install carries it, by comparing one.

- **Why the higher surfaces do not cover it**: no MCP tool saves a re-total, and the Management API
  recalculation re-saves the cached entity.
- **Local installs only**: on a hosted install, re-place the order through the storefront checkout
  (above); no MCP tool or Management API verb persists a re-total.
- **The debt it owes**: a Management API `CacheInformationRefresh` of
  `Dynamicweb.Ecommerce.Orders.OrderService`, in the order given in "Order the SQL write and the cache
  flush" (below), and nothing may re-save the order afterwards. Read the totals back with
  `get_orders_by_ids`.

## Backdating an order: SQL keyed on the minted id, written last, then a recycle

No MCP tool writes `OrderDate`: `update_orders` has no date member [mcp 0.4.4]. No Management API verb
sets a creation timestamp either: `OrderSave` mints its own id and stamps the current time over any date
it is sent. Spreading demo orders over a date range is therefore SQL, keyed on the id the platform minted
(read it back from the save response or a list query, never the id you sent).

**Surface: `SQL`.**

```sql
-- write it LAST: any later save of the order (OrderRecalculate, OrderSave, an MCP order update)
-- writes the cached date back over the row.
UPDATE EcomOrders SET OrderDate = '<yyyy-mm-ddThh:mm:ss>' WHERE OrderId = '<minted order id>';
```

- **Why the higher surfaces do not cover it**: no tool and no verb carries a writable order date.
- **Local installs only**: on a hosted install the orders keep their placement time.
- **The debt it owes**: an **application-pool recycle**. Measured [dw 10.28.10]: after the update, the
  customer center's order list kept showing the placement times until the recycle, because the order
  service holds order objects in process. The admin grids and a Management API order read turn over on
  their own within minutes; the storefront list did not. An `OrderService` `CacheInformationRefresh` is
  the lighter flush the general SQL sequence uses, but it was not the measured fix here.

Sequence: every API write first, the date update last, then the recycle, and nothing re-saves the orders
afterwards. Verify on the buyer's order list in the customer center, not on the row.

## Reverting a test order placed from a seeded cart

Checkout converts the context cart's own `EcomOrders` row into the order (`dw-commerce-orders`,
`cart-commands.md`, "Checkout converts the context cart row in place"). A test order placed by a buyer
whose seeded cart was the context cart has consumed that cart, so MCP `delete_order` on the test order
deletes the seeded cart for good. Prefer a buyer whose context cart is disposable. Where the seeded cart
has to come back:

**Surface: `SQL`.**

```sql
-- BEFORE the checkout: snapshot the cart row, its lines and the owner's pointer.
SELECT * INTO #cart_before  FROM EcomOrders     WHERE OrderId = '<cartId>';
SELECT * INTO #lines_before FROM EcomOrderLines WHERE OrderLineOrderId = '<cartId>';
SELECT AccessUserId, AccessUserCartId INTO #pointer_before FROM AccessUser WHERE AccessUserId = <buyerId>;
```

After the checkout, diff the converted row against the snapshot and restore the cart-identity columns by
`UPDATE`, never by `DELETE`. The measured revert set `OrderCart = 1`, restored the original
`OrderStateId`, `OrderShippingMethodId` and `OrderPaymentMethodId`, cleared the custom order fields the
checkout had written, and re-pointed the buyer's `AccessUserCartId` at the row. Restore anything else the
diff shows the checkout stamped, the order id and the completion flag and date included, and assert the
`EcomOrders` row count is back where the snapshot left it.

- **Why the higher surfaces do not cover it**: no tool or verb turns an order back into a cart, and the
  only removal tool deletes the asset.
- **Local installs only**: on a hosted install, re-seed the cart instead, by adding the lines through the
  storefront cart as the buyer, and take the before and after reads with `get_orders_by_ids` and
  `get_order_lines`.
- **The debt it owes**: the measured revert of the order columns needed no flush. The `AccessUserCartId`
  write is a User-row write, which [`recipes-commerce.md`](recipes-commerce.md) "The active-cart pointer
  is adopted with no ownership check" treats as owing a recycle or a user-service flush: sign in as the
  buyer and recycle if the cart does not come back.

Measured once, on an earlier Swift 2 release; on the current build, compare the cart row's identity
before and after one checkout before relying on the snapshot shape.

## Building an order-state ladder

MCP `create_order_state` reaches no column beyond the ones it names: it has no parameter for
`AllowEdit`, `AllowOrder` or any of the ten `EcomOrderStates` mail columns. A full state ladder is
therefore MCP create, then a `SQL` pass over the remaining columns, then a Management API
`CacheInformationRefresh` (at `/admin/api/CacheInformationRefresh`) of
`Dynamicweb.Ecommerce.Orders.OrderStateService` — and `…Orders.OrderFlowService` when the flow
moved. SQL because no verb writes those columns; **local installs only** (a hosted install has no
write path for them, so an online build asks the user); it owes the flush named
above.

Verify by re-reading `EcomOrderStates` for the flow and asserting both the new ids and a gapless
sort order, then asserting the state name as the storefront order list renders it.

## A deleted state's id is re-issued, and its transition rows survive

`delete_order_state` leaves dangling `EcomOrderStateRules` rows, and the id generator re-issues a
deleted state's id into any flow, so the dangling rules become valid-looking cross-flow
transitions. Nothing surfaces this. A two-ended `LEFT JOIN` is the only check that sees it:

```sql
-- read-only integrity gate; run it in the same transaction as the state writes.
-- SQL because no verb reads the rule table; local installs only (a hosted install reads both ends
-- with get_order_states and get_order_flows); owes no flush (read-only).
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
