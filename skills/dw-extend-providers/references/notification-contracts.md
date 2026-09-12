# Notification contracts: who raises what, and which ones can refuse

What a notification's args actually let you do, and which code path raises it. Both are decided in
the platform's IL and neither is derivable from the constant's name. Measured on DW 10.27/10.28.
Reached from [SKILL.md](../SKILL.md).

## Contents

- [Cancellation is per notification, not a platform guarantee](#cancellation-is-per-notification-not-a-platform-guarantee)
- [The user before-save notification cannot veto, and does not cover the password](#the-user-before-save-notification-cannot-veto-and-does-not-cover-the-password)
- [Cart validation is raised at the checkout step only](#cart-validation-is-raised-at-the-checkout-step-only)
- [Which product-catalog notification is the detail page](#which-product-catalog-notification-is-the-detail-page)
- [Order.AfterSave fires on every save of a completed order](#orderaftersave-fires-on-every-save-of-a-completed-order)
- [A page-loaded subscriber can redirect, invisibly to every content API](#a-page-loaded-subscriber-can-redirect-invisibly-to-every-content-api)

## Cancellation is per notification, not a platform guarantee

`NotificationManager.Notify` wraps every `OnNotify` in a try/catch that logs "The notification
subscriber threw an unexpected error" and continues, so **throwing from a subscriber vetoes
nothing**. The only way to refuse an operation is an args type that carries a refusal member **and a
caller that reads it back**. Both halves vary per notification:

| Notification family | Refusal member | Read back by the caller? |
|---|---|---|
| Cart (`Ecom7CartAfterOrderValidation`, `Ecom7CartBeforeCheckoutHandler`) | `IList<ValidationError> ValidationErrors`; `CancelableNotificationArgs.Cancel` | Yes — `Cart.Frontend` reads `ValidationErrors` after the notify |
| Order delete (`Ecommerce.Order.BeforeDelete`) | `CancelableNotificationArgs.Cancel` | Yes |
| User save (`DWN_UM_USER_ONBEFORE_SAVE`) | **none** — the args carry one member | n/a |

Check the args type before designing a guard around a notification. Where the hook cannot refuse, the
rule has to sit upstream (a route or permission gate) or replace the service through DI.

## The user before-save notification cannot veto, and does not cover the password

`Dynamicweb.Security.UserManagement.Notifications.Notifications.UserOnBeforeSave`
(`"DWN_UM_USER_ONBEFORE_SAVE"`) raises `UserNotificationArgs`, whose whole surface is
`public User Subject { get; }` — no `Cancel`, no `CancelExecution`, no `StopExecution`, no
`ValidationErrors` — and `UserService.Save` reads nothing back.

The remaining lever looks sound: `Subject` is the same `User` instance `Save` is about to persist, so
restoring the protected fields from the stored row makes the save a no-op. **For profile fields this
works. For the password it does not.** With such a guard live and logging that it fired, a scripted
password-change POST inside an impersonated session still changed the stored hash: the
`UserChangePassword` module does not persist the password through the `Save` whose before-save
notification carries `Subject`.

Two consequences:

- **Prove a credential claim with a before/after hash read**, never with a rendered refusal. The same
  response can carry the guard's refusal block *and* the module's own "Password changed" success
  alert.
- **Read the stored values with raw `SQL`** (local-install only, read-only, nothing owed) rather than
  `UserService.GetUserById`, which hands back the very instance being mutated.

Saved cards have no notification at all: a sweep of every const string in the shipped assemblies
finds no card-related notification name, and `PaymentCardRepository`'s IL contains no `Notify` call.
A guard on card minting has to live inside the checkout handler that mints it — see
[`checkout-handlers.md`](checkout-handlers.md).

## Cart validation is raised at the checkout step only

`Ecommerce.Cart.AfterOrderValidation` (`"Ecom7CartAfterOrderValidation"`), args
`AfterOrderValidationArgs { Order Order; IList<ValidationError> ValidationErrors }`, is raised **only
where an order would actually be placed**. Posting an intermediate CartV2 step with the rule violated
advances to the next step and the subscriber never runs; submitting the checkout step fires it and
the page renders the subscriber's own message with no order handed to the handler.

So a conditional rule that no `EcomValidations` row can express — one field required because of
another field's value — is enforceable here, but:

- **Write the acceptance criterion as "the order cannot be placed", not "the step does not
  advance"**, or a correct implementation reads as a failure.
- **To gate an intermediate step**, use a real `EcomValidations` rule bound to that step (see
  [`pricing-fees-and-validation.md`](pricing-fees-and-validation.md)), or
  `Ecom7CartBeforeCheckoutHandler` / `BeforeOrderValidationArgs.Cancel`.
- `ValidationError` is a **struct with public fields** `ErrorMessage` and `ValidationField`, not
  properties. `ValidationField.GetFieldBySystemName` resolves a custom order field.

## Which product-catalog notification is the detail page

`Dynamicweb.Ecommerce.ProductCatalog.ProductCatalogFrontend` raises three notifications from three
separate methods, and only the raiser distinguishes them:

| Notification | Raised from | Args |
|---|---|---|
| `DWN_PRODUCT_CATALOG_VIEW_MODEL_OnBeforeContent` | `GetModuleContent` | module content |
| `DWN_PRODUCT_CATALOG_VIEW_MODEL_OnBeforeProductListRender` | `RenderProductList` | the **list** path |
| `DWN_PRODUCT_CATALOG_VIEW_MODEL_OnBeforeProductRender` | `RenderProduct` | the **detail** path — `OnBeforeProductRenderArgs { string ProductId; string VariantId; ProductViewModelSettings ModelSettings; Template Template }`, all settable |

`Ecommerce.Product.BeforeRender` (`"DWN_ECOM_PRODUCT_BEFORE_RENDER"`) carries only the `Product` and
is raised from neither of these.

**Subscribe a per-view write — recently viewed, a view counter, a personalisation signal — to
`OnBeforeProductRender`**, which is the detail path by construction. The list-path notification
fires once per card, so a 12-card listing writes 12 rows and an unfiltered catalogue writes one per
product. Measured: three detail views wrote exactly three rows, a re-view moved the timestamp
without adding a fourth, and a 12-card list page wrote none.

Give the backing table a **unique index on (user, product)** so a re-view is an update; without it a
trim-to-N silently keeps duplicates.

## Order.AfterSave fires on every save of a completed order

`Ecommerce.Order.AfterSave` is raised by an order-state pass, a gateway capture writing
`OrderCaptureInfo`, an `OrderRecalculate`, and an ERP status import — not only by the order being
placed. **Anything accrued or emitted from this notification needs a durable, out-of-process
idempotency key.** A process-local `ConcurrentDictionary` of order ids passes a single-session test
and is lost on every app-pool recycle and worker swap.

For the loyalty case specifically, the ledger itself is the durable guard — see
[dw-extend-csharp-api](../../dw-extend-csharp-api/SKILL.md), "Loyalty points".

## A page-loaded subscriber can redirect, invisibly to every content API

A `NotificationSubscriber` on `Standard.Page.Loaded` can redirect the request, which makes a page
**alive, active, not deleted and unreachable**. Nothing in the content model, the page tree, or any
MCP or Management API read reflects that — a subscriber is invisible to all of them.

**Before concluding a content placement failed, assert the page id you are SERVED**, not the id you
requested. On the current Swift edition the served id is `document.body`'s `data-dw-page-id`; it is
the only thing on the response that says which page you actually got. "The paragraph is on page N"
and "the visitor sees page N" are independent facts, and only the second one matters.

The same rule runs the other way for an audit: "which pages can this user reach" has to include the
`Standard.Page.Loaded` subscribers, not only permissions and the page tree.
