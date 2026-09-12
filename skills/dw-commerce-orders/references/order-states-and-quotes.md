# Order states, removal, and the cart ↔ quote conversion

The state machine around an order: building a state ladder without corrupting the transition table,
removing an order that a checkout produced, and the two service verbs that move an order between
cart and quote. Measured on DW 10.28.x.

## Contents

- [Building an order-state ladder](#building-an-order-state-ladder)
- [A deleted state's id is re-issued, and its transition rows survive](#a-deleted-states-id-is-re-issued-and-its-transition-rows-survive)
- [Removing an order: `OrderCancel` then `OrderDelete`](#removing-an-order-ordercancel-then-orderdelete)
- [`UpdateCartToQuote` and `DowngradeToCart` — what each leaves to the caller](#updatecarttoquote-and-downgradetocart--what-each-leaves-to-the-caller)
- [Swift 2's Accept-quote button cannot work on a quote](#swift-2s-accept-quote-button-cannot-work-on-a-quote)

## Building an order-state ladder

MCP `create_order_state` creates and, when an existing id is supplied, **updates** — which is how a
shipped flow's states get re-spaced into a new pipeline. Two argument shapes are not guessable and
a wrong one answers a bare `"An error occurred invoking 'create_order_state'"` naming no property:

- **`orderType` is a STRING**: `Order` | `Quote` | `Cart` | `Recurringorder` | `LedgerEntry`.
  `EcomOrderStates.OrderStateOrderType` **stores an integer**, so reading the table and echoing its
  value back is precisely what fails.
- **`color` is a hex literal** (`#F59E0B`). The dashboard-widget palette names are rejected here.

**The tool reaches no other state column.** It has no parameter for `AllowEdit`, `AllowOrder` or any
of the ten `EcomOrderStates` mail columns, so a full state ladder is always MCP create + a SQL pass
+ an Admin API `CacheInformationRefresh` of `Dynamicweb.Ecommerce.Orders.OrderStateService` (and
`…Orders.OrderFlowService` when the flow moved). That SQL is **local-install only**; the mail
columns themselves are documented in [`order-notifications.md`](order-notifications.md).

Verify by re-reading `EcomOrderStates` for the flow and asserting both the new ids and a gapless
sort order, then asserting the state name as the storefront order list renders it.

## A deleted state's id is re-issued, and its transition rows survive

Two gaps compose into a corrupt transition table that is invisible in every UI and every read verb:

- **MCP `delete_order_state` removes the state and not the transitions that reference it**, so a
  deleted state leaves dangling `EcomOrderStateRules` rows that nothing surfaces.
- **The id generator will re-issue a deleted state's id, into any flow.** It picks `OS` + the new
  identity value and falls back to the **lowest free** `OSn` when that is taken, and it consults
  `EcomOrderStateRules` not at all. Measured: a solution carrying two rules pointing at a deleted
  quote-flow state was handed that exact id for a brand-new **order-flow** state, at which point
  the two dangling rules became valid-looking cross-flow transitions.

**Assert the rule table's integrity explicitly** whenever you touch order states — a two-ended
`LEFT JOIN` is the only check that sees it:

```sql
-- read-only integrity gate; run it in the same transaction as the state writes
SELECT COUNT(*) FROM EcomOrderStateRules r
LEFT JOIN EcomOrderStates f ON f.OrderStateId = r.OrderStateRuleFromState
LEFT JOIN EcomOrderStates t ON t.OrderStateId = r.OrderStateRuleToState
WHERE f.OrderStateId IS NULL OR t.OrderStateId IS NULL OR f.OrderFlowId <> t.OrderFlowId;
-- must be 0
```

When a flow is inherited in this state, rebuilding its rule set from scratch behind that assertion
is cheaper than repairing it row by row.

## Removing an order: `OrderCancel` then `OrderDelete`

Three separate things wear one name, and none of them is discoverable from either verb alone:

- **`OrderDelete` is a SOFT delete.** It sets `OrderDeleted = 1` and moves the state, leaving the
  row in `EcomOrders`. A `COUNT(*)` assertion never moves, even on total success — filter on
  `OrderDeleted` instead.
- **It refuses a completed order**, quoting its own rule: only orders that are not completed and
  whose capture state is Cancelled may be deleted. That excludes **every order a checkout ever
  produced** — the one class of row a reset has to remove.
- **The two verbs bind different key names.** `OrderDelete` binds the plural `Ids`; `OrderCancel`
  binds the singular `Id`. Reusing the payload fails with
  `"Selected order is not found. The order id: ."`, whose empty id is the only clue that the key
  name was wrong.

```
POST /Admin/Api/OrderDelete {"OrderId":"…"}   -> {"status":"invalid","message":"No items selected"}
POST /Admin/Api/OrderDelete {"OrderIds":[…]}  -> {"status":"invalid","message":"No items selected"}
POST /Admin/Api/OrderDelete {"Ids":["…"]}     -> bound

-- the working pair for a completed order
POST /Admin/Api/OrderCancel {"Id":"<orderId>"}   -> ok
POST /Admin/Api/OrderDelete {"Ids":["<orderId>"]} -> ok   (OrderDeleted = 1, state moved)
```

Carts and incomplete orders take `OrderDelete` on their own.

**`OrderSave` is not the way round it**: it is a whole-entity save that demands `Currency` and a
billing country before it looks at anything, and it re-prices every line from the live catalogue
(see [`order-lifecycle.md`](order-lifecycle.md) "`OrderSave` on an existing order is a
reconciliation pass"). Neither is a raw `UPDATE` of `OrderDeleted`: the write is invisible to the
cached `OrderService` and the next save of that cached entity destroys it.

## `UpdateCartToQuote` and `DowngradeToCart` — what each leaves to the caller

`Dynamicweb.Ecommerce.Services.Orders` carries the platform's own cart/quote pair. Both are callable
from Razor with no C# project, and both are currently the supported server-side conversion:

**`OrderService.UpdateCartToQuote(order)`**

- **Mints a new id** (`QUOTE<n>`). Worth having: hand-flipping the two booleans and saving also
  works and leaves the quote wearing its cart's id, which is not a number anyone can hand a
  customer as a quotation.
- **Sets `IsQuote`.**
- **Does not clear `IsCart`** on the in-memory order, so the very next `Save` writes `OrderCart=1`
  back onto a quote — a row that is simultaneously a cart and a quote, which nothing else on the
  platform produces. **Set `order.IsCart = false` explicitly before the save.**
- **Does not move `AccessUser.AccessUserCartId`**, so the pointer still names an order that is no
  longer a cart and the next add-to-cart re-opens the quote. Clear it by hand.

**`OrderService.DowngradeToCart(order)` is not the inverse it looks like.**

- It **mints a new cart id and RENAMES the original order to it**, keeping that order's lines.
- It **inserts a fresh COPY of the quote under the old quote id**, with new order lines. The counts
  go up by one order and one line, and the dealer keeps the quote as a record while getting the
  cart.
- It sets neither `IsCart` nor the user's cart pointer; set both explicitly.

**Consequence for any bookkeeping row keyed on the order id: write it against the id the order had
BEFORE the call.** After a downgrade, the id you were holding names the **cart**, and the quote that
survives is a different row that happens to wear the old name — so a row recording "this quote
became that cart", written after the call, lands on the cart and loses the link, and looks correct
in every read that does not join back to `EcomOrders`.

Note also what a conversion deliberately does **not** carry: a per-line value held in the order-line
field blob (a quoted or marked-up price, say) never reaches `OrderLineUnitPrice`, so a site whose
price provider handles prices exclusively re-prices the converted cart from its own rules and the
quoted number cannot reach a cart even by accident.

## Swift 2's Accept-quote button cannot work on a quote

The shipped quotes-list template renders an Accept-quote action whenever the state's `AllowOrder` is
true, as an htmx `hx-get` against `/dwapi/ecommerce/carts/<order secret>` with a template header
naming the accept modal — and **that delivery endpoint validates that the order is a CART**:

```
GET /dwapi/ecommerce/carts/<secret>
  -> 400  "The cart is not a cart but not completed. IsCart: False Complete: False IsProcessingCheckout: False."
GET /dwapi/ecommerce/carts/<secret>  + the template header
  -> 500  "Model is required for view model templates."   (and one event-log entry per attempt)
```

A quote is by definition not a cart and not complete, so the endpoint refuses **every** order the
button is ever rendered for. htmx has nothing to swap, the modal that carries the actual command
never exists, and the command is never posted: the click does nothing at all — no modal, no toast,
no navigation, nothing a user would see. The failure **is** recorded, in the event log, which is
nowhere the user or the developer is looking. The `CustomerCenterCmd=QuoteAccept` command is
likewise inert when posted by hand, in every shape, in both an `AllowOrder=false` state (where
inertness is correct) and an `AllowOrder=true` state (where it is not).

**Use `OrderService.DowngradeToCart` from Razor as the accept path** until the pairing is fixed. A
quote flow whose only documented accept path is a dead button is worse than no accept path, because
the demo and the test both pass by inspection.
