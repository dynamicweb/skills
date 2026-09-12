# Order states, removal, and the cart ↔ quote conversion

The state machine around an order: building a state ladder without corrupting the transition table,
removing an order that a checkout produced, and the two service verbs that move an order between
cart and quote. Measured on DW 10.28.x.

## Contents

- [Building an order-state ladder](#building-an-order-state-ladder)
- [A deleted state's id is re-issued, and its transition rows survive](#a-deleted-states-id-is-re-issued-and-its-transition-rows-survive)
- [Removing an order: cancel first, then delete](#removing-an-order-cancel-first-then-delete)
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
of the ten `EcomOrderStates` mail columns, so in-product a state ladder is MCP create plus the
backend order-states screen for the rest — name that screen rather than promising the tool covers
it. The mail columns themselves are documented in
[`order-notifications.md`](order-notifications.md); the out-of-product completion pass is in
[`recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md) "Building an order-state ladder".

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

**Assert the rule table's integrity explicitly** whenever you touch order states. In-product,
MCP `get_order_states` and MCP `get_order_flows` give both ends: read every state of every flow,
then check that each transition the backend order-flow screen renders names a state that still
exists **and** that both ends sit in the same flow. A transition whose target is missing from
`get_order_states` is a dangling rule. The two-ended integrity query that sees the whole table at
once is out of product: see [`recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md) "A deleted state's id is re-issued".

When a flow is inherited in this state, rebuilding its rule set from scratch behind that assertion
is cheaper than repairing it row by row.

## Removing an order: cancel first, then delete

Use MCP `delete_order`, and MCP `update_orders` + `set_order_state` to cancel. Three separate
things wear one name, and none of them is discoverable from the tools alone:

- **Deleting an order is a SOFT delete.** It sets `OrderDeleted = 1` and moves the state, leaving
  the row in `EcomOrders`. An order count never moves, even on total success — read the deleted
  flag instead, and note that MCP `search_orders` keeps returning the row.
- **A delete refuses a completed order**, quoting its own rule: only orders that are not completed
  and whose capture state is Cancelled may be deleted. That excludes **every order a checkout ever
  produced** — the one class of row a reset has to remove.
- **So the working sequence on a completed order is cancel, then delete.** Move the order into its
  flow's Cancelled state with MCP `set_order_state`, then call MCP `delete_order`. Carts and
  incomplete orders take `delete_order` on their own.

Read the order back with MCP `get_order_by_id` after the pair and assert the state moved; a delete
that silently did nothing looks identical to one that worked.

**A whole-entity order save is not the way round the refusal**: it demands `Currency` and a billing
country before it looks at anything, and it re-prices every line from the live catalogue (see
[`order-lifecycle.md`](order-lifecycle.md) "`OrderSave` on an existing order is a reconciliation
pass"). The out-of-product verb pair, and the key-name trap that makes one payload fail as the
other, are in [`recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md) "Removing an order: `OrderCancel` then `OrderDelete`".

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
true, as an htmx call against the delivery API's cart route with a template header naming the accept
modal — and **that endpoint validates that the order is a CART**, answering 400 for an order that is
neither a cart nor complete and 500 once the template header is added.

A quote is by definition not a cart and not complete, so the endpoint refuses **every** order the
button is ever rendered for. The measured request/response pair is in [`recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md) "Swift 2's
Accept-quote button cannot work on a quote". htmx has nothing to swap, the modal that carries the actual command
never exists, and the command is never posted: the click does nothing at all — no modal, no toast,
no navigation, nothing a user would see. The failure **is** recorded, in the event log, which is
nowhere the user or the developer is looking. The `CustomerCenterCmd=QuoteAccept` command is
likewise inert when posted by hand, in every shape, in both an `AllowOrder=false` state (where
inertness is correct) and an `AllowOrder=true` state (where it is not).

**`QuoteAccept` is the command's one spelling.** `AcceptQuote` reads plausibly and is the spelling a
reader reaches for first; it names nothing. Neither posts a working accept, so the spelling matters
only for reading a captured request — this file is the single home for both facts.

**Use `OrderService.DowngradeToCart` from Razor as the accept path** until the pairing is fixed. A
quote flow whose only documented accept path is a dead button is worse than no accept path, because
the demo and the test both pass by inspection.
