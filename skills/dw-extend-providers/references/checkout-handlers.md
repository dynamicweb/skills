# Custom checkout handlers

The `CheckoutHandler` contract as measured from the shipped assemblies on DW 10.27/10.28, plus the
four traps that make a correct-looking handler fail silently. Reached from
[SKILL.md](../SKILL.md).

## Contents

- [The base class and where it lives](#the-base-class-and-where-it-lives)
- [Wiring the payment method to the handler](#wiring-the-payment-method-to-the-handler)
- [The callback URL already carries the order id](#the-callback-url-already-carries-the-order-id)
- [The gateway-code column is four characters](#the-gateway-code-column-is-four-characters)
- [An inline card form posts the PAN into the order row](#an-inline-card-form-posts-the-pan-into-the-order-row)
- [Capture: the platform owns the running total](#capture-the-platform-owns-the-running-total)

## The base class and where it lives

The base is **`Dynamicweb.Ecommerce.Cart.CheckoutHandler`** (deriving from
`Dynamicweb.Extensibility.AddIns.ConfigurableAddIn`). It is not in
`Dynamicweb.Ecommerce.Orders.Gateways` — that namespace holds only the capability interfaces,
`CallbackData`, `OrderManager` and two enums.

**`CheckoutHandler` has zero abstract members**, so inheriting it compiles and does nothing, with no
compiler help about which method the platform calls. Override these two:

| Member | Signature | Role |
|---|---|---|
| `BeginCheckout` | `public virtual OutputResult BeginCheckout(Order order, CheckoutParameters parameters)` | The entry point. `CheckoutParameters` carries exactly `ReceiptUrl` and `CancelUrl`. |
| `HandleRequest` | `public virtual OutputResult HandleRequest(Order order)` | The callback leg. |

`StartCheckout`, `Redirect`, `SubmitForm` and `RedirectToCart` are `[Obsolete]` legacy that the
platform **still logs under their old names** — an order log line reading "After StartCheckout" does
not mean your `StartCheckout` ran.

The canonical completion body is `DefaultCheckoutHandler.BeginCheckout`'s, verbatim:

```csharp
try { SetOrderComplete(order, transactionNumber); }
catch (Exception ex) { LogError(order, ex, "..."); }
CheckoutDone(order);
return PassToCart(order);
```

Rendering your own form: `new Dynamicweb.Rendering.Template("eCom7/CheckoutHandler/<name>/Card.cshtml")`,
`SetTag(...)`, then the inherited `Render(order, template)`, returning
`new Dynamicweb.Frontend.ContentOutputResult { Content = html, ContentType = "text/html" }`. The
template path is relative to **`Files/Templates`**, which is not where the Swift design lives, so the
folder chain has to be created. `OutputResult` is abstract with only a `Headers` dictionary; the
concrete types are `ContentOutputResult`, `RedirectOutputResult`, `StreamOutputResult`,
`NoActionOutputResult`, `NotFoundOutputResult`.

Capability interfaces, exact signatures:

| Interface | Members |
|---|---|
| `ISavedCard` | `string UseSavedCard(Order)`, `bool SavedCardSupported(Order)`, `void DeleteSavedCard(int)` |
| `IRemoteCapture` | `OrderCaptureInfo Capture(Order)` |
| `IRemotePartialCapture` | `OrderCaptureInfo Capture(Order, long amount, bool final)`, `bool CaptureSupported(Order)`, `bool SplitCaptureSupported(Order)` |
| `ICancelOrder` | `bool CancelOrder(Order)` |
| `ICheckoutHandlerCallback` | `static abstract Order GetOrderFromCallback(CallbackData)`, `OutputResult HandleCallback(Order, CallbackData)` |

`OrderCaptureInfo(OrderCaptureState state, string message)` with
`enum OrderCaptureState { Success=0, Failed=1, NotCaptured=2, Split=3, Cancel=4 }`.

Implementing `ISavedCard` is enough to turn Swift's own saved-card selector on
(`Ecom:Cart.Paymethod.SupportSavedCard`) with no template change.

## Wiring the payment method to the handler

Resolution is `AddInManager.GetInstance<CheckoutHandler>(payment.CheckoutSystemName)`, so:

- **`EcomPayments.PaymentCheckoutSystemName` holds a .NET type name** — `Namespace.Class, AssemblyName`
  — **not** the `[AddInName]` label.
- **`EcomPayments.PaymentAddInType` is `nvarchar` holding the enum NAME**: `None`, `Gateway` or
  `Checkout`. Writing the integer `2` fails with `Conversion failed when converting the nvarchar
  value 'None' to data type int`. `None` and `Checkout` both resolve a handler; only `Gateway`
  short-circuits before the system-name column is read at all.

Verify the emitted type name from the compiled assembly's metadata before writing it, the same
discipline a scheduled-task registration uses — a wrong name fails silently.

Surface note: these two columns have no MCP tool (`create_payment` / `update_payment` /
`save_payment_methods` cover name, description, active, sorting, code, weights, gateway and terms
code only), so wiring them is Management API `PaymentSave` where the verb reaches them, else `SQL`,
**local-install only**, owing a payment-service flush or a restart.

The tell that the wiring worked is one line in `EcomOrderDebuggingInfo`:
`Passing order to checkout handler: <your type>`.

## The callback URL already carries the order id

`GetBaseUrl(order)` returns, verbatim,
`https://<host>/Default.aspx?ID=<pageid>&CheckoutHandlerOrderID=<order.Id>`. **It is the callback
URL; post your form to it unchanged.**

Appending `"?" + OrderIdRequestName + "=" + order.Id` — the shape every DW9-era example uses — posts
the key twice. Dynamicweb merges the query string and the form collection in `Request[key]`, so
`CheckoutHandler.CheckoutHandlerOrderId` returns `"ORDER21,ORDER21"`, `OrderService.GetById` cannot
resolve it, and the error path logs against a null order. The result is a **completely blank page**:
no headings, no error element, and nothing added to `EcomOrderDebuggingInfo` after the earlier
"After StartCheckout" line. The order sits renumbered from a cart to an `ORDERnn` id with
`Complete=False` and every transaction column empty.

**Diagnostic: read the address bar before reading the code.** A checkout callback that "does
nothing" shows the order-id parameter twice in the URL. The same merge rule makes a **hidden form
field of that name equally fatal** — carry the id in the query string only. The callback key is the
const `CheckoutHandler.OrderIdRequestName`, `"CheckoutHandlerOrderID"`.

## The gateway-code column is four characters

`EcomOrders.OrderTransactionPayGatewayCode` is **`nvarchar(4)`** — sized for the DW9-era four-letter
gateway codes — while its neighbours are `nvarchar(50)`, `nvarchar(255)` and `nvarchar(max)`:

| Column | Width |
|---|---|
| `OrderTransactionPayGatewayCode` | `nvarchar(4)` |
| `OrderTransactionCardNumber` / `OrderTransactionStatus` / `OrderTransactionType` | `nvarchar(50)` |
| `OrderTransactionNumber` | `nvarchar(255)` |
| `OrderTransactionToken` | `nvarchar(max)` |
| `OrderTransactionTokenCheckSum` | `nvarchar(128)` |
| `OrderTransactionValue` | `nchar(2)` |

**Keep the gateway code to four characters.** A longer one makes the final `Orders.Save` inside
`SetOrderComplete` throw `String or binary data would be truncated`, which rolls that whole save
back. The cart-to-order renumber and `Complete = true` happened earlier in the method and are already
persisted, so **the order completes and every transaction column stays empty** — no token, no masked
card number, no card type, no capture info. The customer sees a normal receipt; the only trace is one
`EcomOrderDebuggingInfo` line and one EventViewer entry, and a handler that wraps `SetOrderComplete`
in the try/catch `DefaultCheckoutHandler` itself models turns the throw into silence.

**Assert a gateway integration on the order row, never on the receipt page.** A completed order with
an empty `OrderTransactionToken` is the exact signature of a swallowed save.

Where a longer code is already deployed and cannot be changed, `ALTER TABLE EcomOrders ALTER COLUMN
OrderTransactionPayGatewayCode nvarchar(50) NULL` is a working fallback (the column carries no index
and no constraint) — but it is a platform-schema change, is `SQL` and therefore **local-install
only**, and should be reverted once the code fits.

## An inline card form posts the PAN into the order row

`CheckoutHandler.SetOrderComplete` ends with `order.GatewayResult = GetPostedInfo(order)` —
documented as "returns all posted info as xml string" — then `UpdateGatewayResult` and
`Orders.Save`. **Every field the payment form posted is serialised into
`EcomOrders.OrderGatewayResult` in clear text**, overwriting whatever the handler had put there. For
a hosted gateway that posts nothing sensitive back this is a useful audit trail; for an inline card
form on the merchant's own domain it is a PAN and a CVC at rest, however carefully the handler masked
`OrderTransactionCardNumber`.

**A handler that renders its own card form must ensure the sensitive fields are never POSTED, because
it cannot stop them being persisted.** The reachable pattern needs no platform change:

- give the visible card input **no `name` attribute** — an unnamed input is not submitted;
- post a hidden field of the handler's expected name carrying a **surrogate** built in the browser on
  the form's submit event, preserving only what the handler actually reads: length, any published
  test numbers passed through verbatim, Luhn parity, the first digit and the last four, with the
  middle digits zeroed and one filler digit bumped to restore parity;
- drop the CVC input's `name` entirely where the handler does not read it.

Alternatively override `GetPostedInfo`, which is `protected virtual`.

Verify by grepping `EcomOrders.OrderGatewayResult` for the test PAN after a checkout: zero rows.

## Capture: the platform owns the running total

`OrderService.Capture(order, amountPIP, final)` calls **exactly one** of
`IRemoteCapture.Capture(order)` or `IRemotePartialCapture.Capture(order, amountPIP, final)` — never
both — and then does the accounting itself:

```
if (amountPIP == order.Price.PricePIP + ConvertToPIP(order.ExternalPaymentFee))
      order.CaptureInfo = ((IRemoteCapture)capture).Capture(order)
else  order.CaptureInfo = ((IRemotePartialCapture)capture).Capture(order, amountPIP, final)

if (CaptureInfo.State is Success or Split)
      order.CaptureAmount = order.CaptureAmount + amountPIP / 100.0    // the PLATFORM
      fresh = GetById(order.Id); fresh.CaptureInfo = ...; fresh.CaptureAmount = ...; Save(fresh)
      Notify("DWN_ECOM_ORDER_AFTER_ORDER_CAPTURED", fresh)
```

**A capture handler returns an `OrderCaptureInfo` carrying the state and the message for this call
and touches nothing else.** Any write to `order.CaptureAmount` from the handler is added to on the
way out, so **setting** it stores twice the amount exactly as **accumulating** into it does, while
the handler's own message states the correct figure — which makes the row read like a rounding bug
rather than a contract breach. The fix is the absence of a line; nothing replaces it. Assert it on
the **source** (zero executable assignments to `order.CaptureAmount` in the capture region), because
compiled metadata cannot see a deleted statement.

In the product, capture an order from the order's own screen in the backend; the MCP tool set carries
no capture verb. Outside the product the capture is an Admin API command whose model is stricter than
it looks — see
[dw-data-access `recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md)
("Driving an order capture from outside the product").
