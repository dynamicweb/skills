# Cart commands — what `CartCmd` and `CustomerCenterCmd` actually do

The cart-command vocabulary is DW9-era, appears in almost no shipped Swift 2 template, and several
of its verbs do something narrower — or different — from what their names say. Everything below was
read out of `CartHandler.CatchCart` / `CartService` and then measured on DW 10.28.x with Swift 2.

Surface: these are **frontend commands**, posted as `?CartCmd=<cmd>` / `?CustomerCenterCmd=<cmd>`
or as a hidden form field against a page that hosts a cart app. They are not MCP tools: MCP
(`get_order_lines`, `delete_order_line`, …) reads and writes cart *data*, and nothing on any surface
reaches the session cart itself. The out-of-product recipes for this area are in
[`recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md) "Carts".

## Contents

- [Two gates every scripted cart command must pass](#two-gates-every-scripted-cart-command-must-pass)
- [The command's redirect drops your whole querystring](#the-commands-redirect-drops-your-whole-querystring)
- [`setmulti` sets quantities, and a duplicate product is last-row-wins](#setmulti-sets-quantities-and-a-duplicate-product-is-last-row-wins)
- [`archive` does not archive — it clears the active-cart pointer](#archive-does-not-archive--it-clears-the-active-cart-pointer)
- [`copyExtended` ignores `CartId`, and `createnew` needs `SetActive`](#copyextended-ignores-cartid-and-createnew-needs-setactive)
- [`setcart` selects a cart; it never transfers one](#setcart-selects-a-cart-it-never-transfers-one)
- [The active-cart pointer is adopted with no ownership check](#the-active-cart-pointer-is-adopted-with-no-ownership-check)
- [A NULL pointer means "no ACTIVE cart", not "no cart"](#a-null-pointer-means-no-active-cart-not-no-cart)
- [Rendering the cart page is a WRITE](#rendering-the-cart-page-is-a-write)
- [A cart created through MCP never becomes a login-restored context cart](#a-cart-created-through-mcp-never-becomes-a-login-restored-context-cart)

## Two gates every scripted cart command must pass

**Send a browser User-Agent, and follow redirects.** Both gates are silent and both leave evidence
that reads as success.

1. **The add family is refused outright for a "bot" User-Agent.**
   `CartService.AddOrderLinesInternal` opens with a User-Agent test against the literal
   `bot|crawler|baiduspider|80legs|ia_archiver|voyager|curl|wget|yahoo! slurp|mediapartners-google`
   and returns having added nothing when it matches. **`curl` and `wget` are in that list**, so a
   scripted proof of a cart command fails by default. The surrounding command still runs, so the
   **cart row is created**, the 302 is issued, and nothing is written to `EcomOrderDebuggingInfo`
   or the event log. A probe that checks "did a cart appear" therefore reports success on a
   request that added zero order lines. Assert on order lines — MCP `get_order_lines` on the cart —
   never on the cart's existence.

2. **A `cartcmd` on the `Default.aspx?ID=<n>` form of the URL is answered with a 301 to the
   search-friendly URL BEFORE the command executes.** A client that does not follow redirects
   performs no command at all and still gets a plausible response.

So a scripted cart proof needs a browser User-Agent and redirect-following — **not necessarily a
browser**. The measured request pairs, and the redirect flag that costs the receipt body, are in
[`recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md) "Two gates every scripted cart command must pass".

## The command's redirect drops your whole querystring

Any request carrying `CartCmd` or `CustomerCenterCmd` is executed and then answered with a 302 to a
URL **rebuilt from the page id alone**. Traced end to end:
`GET /Default.aspx?ID=<n>&CartID=…&CartCmd=setcart&MyOwnParam=…` → 301 to the friendly URL with
the full querystring → **302 to `/Default.aspx?ID=<n>`, querystring gone** → 301 to the friendly
URL → 200. The redirect itself is correct (it stops a refresh re-running the command) but it is
lossy, and nothing says so. The command works, so the request looks successful, and only your own
companion value vanishes.

**Nothing of your own can ride alongside a platform cart command.** Two shapes that work:

- **Write first, then redirect into the command.** Handle a request carrying *no* platform command,
  write your own data (for example a rejection reason onto `order.Comment` via
  `Services.Orders.Save`), then `Response.Redirect` into the `CustomerCenterCmd` URL. This ordering
  also puts your value on the order *before* the state change raises its notification mail, so the
  mail can carry it.
- **Chain multi-command flows in the browser** — same-origin fetches plus a navigation. A
  multi-hop chain (`setcart` → `copyExtended` → `setcart` → checkout) cannot be driven with
  server-side redirects at all, because every hop loses the marker saying which hop you are on.

## `setmulti` sets quantities, and a duplicate product is last-row-wins

`setmulti` is the only command that posts an N-row quick-order pad in one request. It appears in no
shipped Swift template, so its contract is not discoverable from the frontend.

`HandleMultiOrderLines` enumerates the form and takes every key **starting with**
`ProductLoopCounter`; **that key's VALUE is the row suffix**. For suffix `<n>` the builder reads:

```
ProductLoopCounter<n>=<n> & ProductID<n> & VariantID<n> & UnitID<n>
                          & StockLocationID<n> & Amount<n> & Quantity<n> & Type<n>
(plus the unsuffixed wishListID)
```

Per row it finds the existing order line for the same product and then:

| Posted quantity | Effect |
|---|---|
| `0` | the line is **removed** (unless `DoNotDeleteOrderLinesWithZeroQuantity` is set) |
| non-zero, line exists | `OrderLineHandler` with the **posted** quantity — a **SET**, not an add |
| non-zero, no line | a new order line is added |

Two behaviours are not guessable and both are destructive if assumed wrong:

- **It SETS rather than adds.** Posting `Quantity1=3` then `Quantity1=5` for the same product
  leaves the line at **5**, not 8.
- **A duplicate product in one post is last-row-wins.** Rows `1=3` and `2=7` for the same product
  in one request leave the line at **7**, not 10 and not 3, silently. **A quick-order pad that
  lets a buyer type the same item number twice must de-duplicate before posting** — the platform
  will not tell it.

Rows are processed in form order, and unlike most cart surfaces `setmulti` does **not** no-op
without an active cart: the add family calls `CartService.CreateCart` first. The zero-quantity
delete makes `setmulti` the natural command behind an editable order grid, not only an entry pad.

## `archive` does not archive — it clears the active-cart pointer

`CartHandler.CatchCart` routes `archive` to `CartService.ClearCart`, whose entire effect is to drop
the session cart key, remove `EcomCustomerDataLoaded`, and null the user's active-cart pointer.
There is nothing for it to write: **`EcomOrders` has no archived column** — the cart identity columns are `OrderCart`,
`OrderStateId`, `OrderCustomerAccessUserId`, `OrderSecondaryUserId`, `OrderDisplayName`,
`OrderReference` and `OrderIsRecurringOrderTemplate`. Measured against a named three-line cart:
zero row delta in `EcomOrders` and `EcomOrderLines`, `OrderCart` still 1, name and lines intact,
the cart still listed on the saved-carts page, and the only change is that the user no longer has
an active cart. **A UI that labels this "Archive" is lying.**

**Model archiving as a cart-flow order state**, with no code: create a state on the cart flow
(`orderType: "Cart"`, `allowOrder: false`) and set it through the platform's own
`?CustomerCenterCmd=cartchangestate&CartId=<id>&StateId=<state>`. The cart keeps `OrderCart=1`,
its name and its lines; the customer-center list template filters that state out of the default
view and can render it under an Archived chip with a Restore action and no checkout action, and a
CSR instance on impersonation ids inherits the same filter.

`archive` is still useful for exactly what it does: it is **the platform's own repair for a
poisoned `AccessUserCartId` pointer** (below).

## `copyExtended` ignores `CartId`, and `createnew` needs `SetActive`

| Command | Reads | Behaviour |
|---|---|---|
| `copyExtended` | `CartName` (falls back to the source's `DisplayName`), `CartUserId` (falls back to the source's `CustomerAccessUserId`) | Copies **the session's ACTIVE cart**. The string `CartId` does not appear in `CatchCart` at all. Builds a new order with `IsCart`, `DisplayName`, `ShopId` and `CustomerAccessUserId`, copies the customer/delivery block, stamps `SecondaryUserId` from the impersonating user, copies every product line, saves. The source cart is not touched. |
| `setname` | `CartName` | Writes `order.DisplayName` and saves. **There is no cart-name column — `OrderDisplayName` IS the cart name**, so a saved-cart UI reads and sorts on it. |
| `createnew` | `CartName`, `OrderContextId`, `SetActive`, `CartUserId` | Passes `SetActive` straight into `CartService.CreateCart`. **Without `SetActive=true` the new cart is created but never becomes the session's**, so a "save this cart and start a fresh one" flow appears to do nothing. |

**To copy a specific cart, `CartCmd=setcart` it first.** Swift 2's own shipped saved-carts template
builds `?cartcmd=copyExtended&CartId=<id>&CartUserID=<id>&CartName=Copy_of_<id>` and the platform
copies whichever cart is active instead — a live defect in the shipped template, not a
configuration mistake.

`/Globalsettings/Ecom/Cart/Cmd/EnableExtendedCopy` **does not gate `copyExtended`**. The check is
`enabled ? true : (cartCmd == "copyExtended")`, so for `copyExtended` the extended flag is true
either way; the node's real job is to make the **plain `copy`** command behave like `copyExtended`.
Its absence from a stock `GlobalSettings.config` is not why a Copy button appears inert.

## `setcart` selects a cart; it never transfers one

`setcart` is a pointer move on **the poster's own** `AccessUser` row and nothing else.
`EcomOrders.OrderCustomerAccessUserId` and `OrderCustomerName` are untouched, and the previous
holder's `AccessUserCartId` is **not** cleared — so after a "take over this cart" click, two users
point at one cart, which is exactly the state the ownership trap below warns about, manufactured by
the platform's own command.

It matters beyond hygiene: **`Order.CustomerAccessUserId` is the only user identity an order
carries**, so every notification subscriber asking "who is buying", and every rule keyed on that
user's groups, keeps answering with the original owner. Measured on a B2B approval flow: an
approver made a colleague's released cart active, walked the real checkout, and was refused by a
subscriber with the *requester's* rule — and the refusal rolled the cart back out of the state the
approver had just put it in.

**`copyExtended&CartUserID=<new owner>` is the only ownership move**, and because it copies the
active cart (above) a real hand-over is a three-command chain: `setcart` the source →
`copyExtended` with the new owner → `setcart` the copy. Measured on the resulting order, the copy
**carries** the original's delivery address, custom order fields, lines and total, and **loses**
`OrderCustomerName` / `OrderCustomerEmail`, because the checkout Information step rewrites those
from the signed-in user — so the order records the new owner and the original requester is not on
it anywhere.

## The active-cart pointer is adopted with no ownership check

`CartService.LoadCart` reads the string in `AccessUser.AccessUserCartId` and adopts that order row
as the context cart **without comparing `EcomOrders.OrderCustomerAccessUserId` to the signed-in
user**. A brand-new browser profile signing in as one buyer is handed another buyer's cart —
contents, totals and all — and an empty cookie jar does not help, because the pointer is on the
user row, not in a cookie. There is no fallback either: a **dangling** pointer (an id that no
longer exists) yields **no cart at all**, even when the user demonstrably owns another one, so the
read is a raw pointer dereference rather than a query.

Second-order damage: with the cart app set to apply user details and the adopted cart at
`OrderHasSetUserDetails=0`, the new session then **overwrites the cart's customer identity** —
`OrderCustomerAccessUserId`, user name, name, email, company, city, region and number — so the
cart is stolen, not shared. If the adopted cart already had `OrderHasSetUserDetails=1` the original
owner is kept instead, and the resulting **order** is stamped with the wrong user.

No platform override exists: MCP `get_module_settings` on the checkout paragraph returns
`ShopSelector`, `CartSelector`, `SetUserDetailsRadio` and `OnReEnterRadio` and nothing about cart
ownership. **The only in-product repair is the platform's own `CartCmd=archive`**, which clears the
pointer for the signed-in user and one user at a time; there is no MCP tool for the column, so a
bulk normalisation is out of product — see [`recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md) "The active-cart pointer is adopted with
no ownership check" for the sweep that nulls every pointer not backed by a cart the user owns.

Assert it per persona: the `DynamicwebEcomCart<userId>` cookie is **absent** for a user who owns no
cart, and a rendered cart total matches only carts whose `OrderCustomerAccessUserId` equals that
user.

## A NULL pointer means "no ACTIVE cart", not "no cart"

Clearing `AccessUserCartId` does **not** give a persona a clean cart: the session re-resolves the
user's existing cart on the next cart operation, and signing out and back in does not change it.
Measured — pointer NULL in the database and user cache flushed, and the very next add-to-cart
landed in the user's previous cart.

**To get a genuinely new cart for a user whose existing cart must not be touched, copy it against
themselves:**

```
GET …?cartcmd=copyExtended&CartUserID=<their own id>&CartName=<probe name>
GET …?CartID=<the new cart id>&CartCmd=setcart
```

A copy is a read of the original, so the exemplar stays byte-identical throughout.

## Rendering the cart page is a WRITE

A plain authenticated GET of the cart page **recalculates the order and persists the header**.
`OrderModified` moves with it, and on a solution with an exclusive price provider every render
re-resolves prices and writes the result back. The lines, the total and the state are untouched,
which is why a failing header checksum looks so much like data corruption. Three consequences:

- **It is a repair.** MCP `delete_order_line` removes a line without recalculating the order, so
  the total stays stale until something re-saves it — and on a build where `OrderRecalculate` is
  banned (see [`order-lifecycle.md`](order-lifecycle.md) "A re-saving verb reverts raw-SQL edits"),
  loading the owner's cart page is the available recalculation route.
- **It erases an out-of-band display name.** A cart named by writing `EcomOrders.OrderDisplayName`
  survives only until the owner next loads their cart page. **Name a cart through
  `CartCmd=setname`** if the name has to persist, and re-assert it after any walk that touches the
  cart page.
- **An order-header checksum on a CART is not a "this cart was untouched" invariant.** Assert the
  order **lines'** checksum, the line count, the total and the state instead — those are stable
  across renders and are what the invariant actually means. The same caution applies to
  `OrderModified` in any diff or audit view: on a cart it tracks reads, not edits.

## A cart created through MCP never becomes a login-restored context cart

A cart created with MCP `create_orders` (`orderType: "Cart"`, correct `userId`, shop, language and
currency) is listed under the user's saved carts and is **never attached as the context cart at
login** — no `DynamicwebEcomCart<userId>` cookie is issued. Matching the cart-state columns that a
browser-created cart carries (`OrderContextId`, `OrderStateId`, `OrderCartV2StepIndex`,
`OrderCheckoutPageID`, `OrderHasSetUserDetails`, `OrderShippingCountrySelection`,
`OrderVisitorSessionId`) does not change it, and neither does `cartcmd=copyExtended`: the restore
keys off session/visitor linkage that only live site activity establishes.

**Produce a restorable cart with real storefront session activity** — a browser-driven add-to-cart
(browser User-Agent and redirects followed, per the two gates above) — and treat an MCP-created
cart as saved-cart data only.
