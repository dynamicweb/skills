# Customer Experience Center surfaces — settings keys, scoping, and what the templates omit

The order-family customer-center apps share one settings vocabulary and one list/detail template
pair, and the places where an instance departs from that are where builds lose time. Measured on
DW 10.28.x with Swift 2.

## Contents

- [The order list and detail view models](#the-order-list-and-detail-view-models)
- [Read the app's OWN settings keys before writing any](#read-the-apps-own-settings-keys-before-writing-any)
- [Nothing rendered vs the empty state: two different bugs](#nothing-rendered-vs-the-empty-state-two-different-bugs)
- [Which apps honour `RetrieveListBasedOn`](#which-apps-honour-retrievelistbasedon)
- [The order list and detail never render the payment method](#the-order-list-and-detail-never-render-the-payment-method)
- [Translation-resolved fields re-render across order history](#translation-resolved-fields-re-render-across-order-history)

## The order list and detail view models

### `OrderListViewModel` — the list

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Ecommerce.Frontend.OrderListViewModel>
```

| Property | Description |
|----------|-------------|
| `Model.Orders` | Collection of orders |
| `Model.PageCount` | Total pages |
| `Model.CurrentPage` | Current page (1-indexed) |

Each order in `Model.Orders`:

| Property | Description |
|----------|-------------|
| `order.Id` | Order ID |
| `order.CreatedAt` | Creation date |
| `order.CustomerName` | Customer display name |
| `order.Price.PriceFormatted` | Total formatted price |
| `order.StateName` | Current order state name |

### List query-string filters

| Parameter | Description |
|-----------|-------------|
| `PageNum` | Page number |
| `PageSize` | Orders per page |
| `SortBy` / `SortOrder` | Sorting |
| `FilterOrderStateId` | Filter by state |
| `FilterFromDate` / `FilterToDate` | Date range |
| `FilterOrderId` | Specific order ID |
| `FilterText` | Free-text search |
| `FilterCustomerName` | Customer name filter |
| `FilterProductId` / `FilterProductNumber` | Product filter |

### `OrderViewModel` — the detail

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Ecommerce.Frontend.OrderViewModel>
```

| Property | Description |
|----------|-------------|
| `Model.Id` | Order ID |
| `Model.CompletedDate` | Completion date |
| `Model.StateName` | Current state |
| `Model.OrderLines` | Collection of order lines |
| `Model.ShippingMethod.Name` | Shipping method name |
| `Model.ShippingFee.PriceWithVatFormatted` | Shipping cost |
| `Model.PaymentMethod.Name` | Payment method name |
| `Model.Price.PriceWithVatFormatted` | Order total |

Each order line:

| Property | Description |
|----------|-------------|
| `line.ProductName` | Product name |
| `line.Quantity` | Ordered quantity |
| `line.TotalPriceWithProductDiscounts.PriceWithVatFormatted` | Line total |
| `line.OrderLineFields` | Custom order line field values |

### `CustomerCenterCmd` commands

```
?CustomerCenterCmd=Reorder&OrderId={OrderId}
?CustomerCenterCmd=QuoteAccept&QuoteId={QuoteId}
```

Change cart state (B2B quote/cart flows):
```html
<form method="post">
    <input name="CustomerCenterCmd" value="cartchangestate" />
    <input name="CartID" value="{CartID}" />
    <input name="StateId" value="{StateId}" />
</form>
```

A request carrying `CustomerCenterCmd` is answered with a redirect that **drops the whole
querystring**, so nothing of your own rides alongside one — see
[`cart-commands.md`](cart-commands.md) "The command's redirect drops your whole querystring".

## Read the app's OWN settings keys before writing any

MCP `set_module_settings` **merges unknown keys into the settings XML without complaint**, so a
wrong guess is stored and looks configured. Read what the app declares first:

```
mcp  get_module_settings  { "paragraphId": <a shipped instance of the same app> }
```

The order-family Customer Experience Center app declares exactly these: `OrderType`,
`RetrieveListBasedOn`, `PageSize`, `SortByField`, `SortOrder`, `OrderListTemplate`,
`DetailTemplate`, `EmailTemplate`, `LedgerType`, `LedgerFlowStates`.

**A ledger-entry instance reads the GENERIC template keys.** With `OrderType = LedgerEntry` the
instance still reads `OrderListTemplate` and `DetailTemplate` like every other order-family
instance; the `LedgerEntryListTemplate` / `LedgerEntryDetailsTemplate` names exist as literals in
the assembly, belong to a different surface, and are **inert here**. Measured on one paragraph with
one set of data: the ledger-specific keys produced a response carrying none of the template's own
markup; the same two file names on the generic keys produced the full invoice list with its
checkboxes, amounts and due dates.

The RMA app is the exception in the family and declares a different block entirely
(`RmaListTemplate`, `RmaDetailTemplate`, `RmaByField`, `SortRma`, `PageSize`) — see
[`rma-and-claims.md`](rma-and-claims.md).

## Nothing rendered vs the empty state: two different bugs

They look identical from the outside — HTTP 200, no error, no log line — and they have opposite
causes:

| Symptom | Meaning | Where to look |
|---|---|---|
| **None of the template's own markup in the response** — not the list, not the "no results" state | the app never resolved a template | the template **setting keys** the app actually declares |
| The template's **empty state** renders | the query returned nothing | the data, the identity clause, the state filter |

Grep the response for a marker that only the template emits. That one check separates the two in
one request, and it is the check that a byte-size comparison alone will not give you.

## Which apps honour `RetrieveListBasedOn`

Measured across one solution's whole customer-center family, two contacts sharing one customer
number, both retrieval modes:

| Surface | Honours `RetrieveListBasedOn=UseCustomerNumber` |
|---|---|
| Open orders, order history | Yes |
| Ledger entries / invoices | Yes |
| Quotes | Yes |
| Saved carts | Yes |
| Favourites | Yes |
| **RMA / returns** | **No** — the app declares no retrieval mode and the list query keys on `EcomOrders.OrderCustomerAccessUserID` |

So on a B2B portal every account surface is shared across the customer number **except** returns,
where a buyer sees only the claims they personally raised. `RetrieveListBasedOn` is accepted into
the RMA paragraph's settings XML and read by nobody, so setting it produces byte-identical
responses and reads as a misconfiguration. If shared-account returns are a requirement, that is a
change order and it belongs in scope, not in the build. Impersonation is still honoured, so a CSR
impersonating the raiser does see them.

## The order list and detail never render the payment method

The shipped `Orders_List.cshtml` and `Orders_Details.cshtml` contain **no reference to
`PaymentMethod`** — their only "Payment" strings are the payment-fee line in the totals. Every
sibling detail template renders it (`@Model.PaymentMethod?.Name` on the cart, quote, invoice and
payment-history details), so the field is available on the view model on the very page that omits
it, and the order detail renders a Shipping Information block with the shipping method in it,
exactly where its payment counterpart is missing.

Consequence for any work that **changes** a payment method on historic orders — a terms migration,
an ERP re-key, a data fix: **there is no customer-facing surface to verify it on**, so an acceptance
criterion written as "the order history reads the new method" cannot be met. Two honest substitutes:
assert the platform's own read (MCP `get_orders_by_ids` over the changed ids) and assert that the
rendered order surfaces are byte-identical before and after — which is a stronger statement about
side effects than the original criterion. Adding the three-line payment-method block from the cart
detail to the order detail is the durable fix where the templates are yours to change.

## Translation-resolved fields re-render across order history

`EcomOrderLines` stores only `OrderLineUnitId` — **there is no snapshotted unit name**. The Unit
column on the customer-center order detail resolves the display name at render time from the unit's
**current** translation, so renaming or translating a unit silently rewrites how every historical
order displays, with no write to `EcomOrders` or `EcomOrderLines` at all.

Generalise it: **any field resolved from a translation at render time is retroactive across order
history.** Before renaming or re-translating such a value, pull the list of orders referencing it
and confirm that changing their historical display is acceptable; if it is not, the point-in-time
value has to be captured onto the order line at creation time, because the platform does not
capture it.
