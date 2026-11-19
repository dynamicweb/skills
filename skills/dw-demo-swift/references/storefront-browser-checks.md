# Storefront browser checks: the measured selectors and paths

Every ad-hoc storefront check drives the same journey: dismiss the cookie banner, sign in, open a
product list and a product, add to cart, check out, read the receipt. This is that journey on a Swift
storefront with Playwright and Chromium, each selector and path measured on a live site
[dw 10.30.6 · swift 2.5.0]. Paths are for the `en-us` area; another language swaps the prefix. Use a
device descriptor, not a resize, for a phone run ([mobile-pass.md](mobile-pass.md) item 5).

## Contents

- [The journey, step by step](#the-journey-step-by-step)
- [The checkout steps](#the-checkout-steps)
- [Traps](#traps)
- [Cleaning up after a check](#cleaning-up-after-a-check)

## The journey, step by step

| Step | Path or selector | What it shows |
|---|---|---|
| Cookie banner | `#dwCookieModal`; decline `#dwCookieDeclineAll`, accept `#dwCookieAcceptAll` | The choice reloads the page: wait for the load before the next locator, or it fails with "Execution context was destroyed" |
| Sign in | `/en-us/sign-in/sign-in`; fill `main #Username` and `main #Password`, click `main #SignIn` | Scope to `main`: the header carries a sign-in form too. Lands on `/en-us/overview`; the header shows the user's name |
| Product list | `/en-us/shop?GroupID=<groupId>` (or the group's own URL) | Cards `article[data-product-id]`, each with `a.stretched-link` to `/en-us/shop/<group-url>/<product-url>`; a signed-in buyer's card carries `.text-price` and `.js-add-to-cart-button` |
| Empty list | the same page | "No products found" in `main`: the list is assortment-gated (see [Traps](#traps)) |
| Product page | the card link, or `/en-us/shop?ProductID=<productId>` | `h1` is the product name. Price `[data-dw-itemtype="swift-v2_productprice"] .text-price` (and `span[itemprop="price"][content]`) |
| Add to cart | `[data-dw-itemtype="swift-v2_productaddtocart"] button.js-add-to-cart-button`; quantity `#Quantity_<productId>_` | The form's `input[type="submit"]` is `d-none`: click the visible button, never the submit |
| Mini cart | `header a[href="/en-us/cart"]` | Text `Cart <n>`; the add is asynchronous, so read it after about two seconds |
| Cart | `/en-us/cart` | Form `#ordersubmit` (`cartcmd=updateorderlines`) with `input[name="QuantityOrderLine<orderLineId>"]`; remove `a[href*="CartCmd=DelOrderLine"]`; checkout `a[href="/user/checkout"]`; quote `a[href="/user/quotecheckout"]` |
| Receipt | `/user/checkout?CompletedOrderId=<orderId>&CompletedOrderSecret=<secret>` | `main` reads "Thank you for your order" and "Order number <orderId>"; the mini cart is back to `Cart 0` |

An anonymous visitor gets no price and no add-to-cart on this build: the price component renders a
sign-in call to action and the add-to-cart component renders empty, so an anonymous journey ends at the
product page. Every step past it runs signed in.

## The checkout steps

`/user/checkout` is the CartV2 app; each step posts the form `#ordersubmit` through a named submit
button, and the URL stays `/user/checkout`.

| Step | Inputs | Next |
|---|---|---|
| 0 Information | Delivery address radios `input[name="EcomOrderDeliverySelectedAddressId"]`: the value is the user id for "Same as the billing address", or an address-book id | `button[name="CartV2.GotoStep1"]` (DELIVERY) |
| 1 Delivery | Shipping radios `input[name="EcomCartShippingmethodID"]` (value: the shipping method id); delivery date radios `input[name="DeliveryDate"]` | `button[name="CartV2.GotoStep2"]` (PAYMENT) |
| 2 Payment | Payment radios `input[name="EcomCartPaymethodID"]` (value: the payment method id); terms `#EcomOrderCustomerAccepted` | `button[name="CartV2.GotoStep3"]` (PLACE ORDER) |

The payment radios are the methods offered to that visitor: the same set as
`GET /dwapi/ecommerce/payments?LanguageId=&CountryCode=` for the same user, scoped by the method's
customer groups ([checkout-configuration.md](../../dw-commerce-orders/references/checkout-configuration.md)
"Method country binding"). After choosing a radio, let the step settle before ticking the terms: one
measured run timed out on `#EcomOrderCustomerAccepted` and the next passed.

A step that will not advance re-renders with `.alert.alert-warning` whose list items are **empty**: the
messages are blank, so read the step's order debugging log (`EcomOrderDebuggingInfo`, "Field validation
failed for step: <n>") or compare the validation groups' fields with what the step posted.

## Traps

- **Product lists are assortment-gated.** A signed-in user who holds no assortment sees "No products
  found" in every list, while the product page by `?ProductID=` still renders and prices the product.
  An anonymous visitor sees the assortments that allow anonymous users. For a fixture of your own, give
  your own account an assortment: `save_assortments` (inactive), `assign_groups_to_assortment` with
  the fixture's group, `assign_permissions_to_assortment` with the account's user group id,
  `build_assortments`, then activate it ([`recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md)
  "Flag, build and gate an assortment" for the count gate). Never widen a shared assortment. The grant is the `users.accounts` recipe's too, and a buyer whose
  groups hold no grant is answered 404 for those products by the delivery API product read
  ([`dc-scoping.md`](../../dw-commerce-b2b/references/dc-scoping.md) "The grant's shapes").
- **The list reads the index its catalog paragraph names.** After the assortment build the list stayed
  empty, through two recycles, until the index the shop page's catalog paragraph queries was rebuilt;
  on the measured site that was a site-specific repository, not `ProductsFrontend`, and rebuilding
  `ProductsFrontend` changed nothing. Read the paragraph's `IndexQuery` module setting, then
  `build_product_index` and `wait_for_product_index` on that repository.
- **`/dwapi/query` does not show what a signed-in buyer's list shows.** It returned the same products
  with and without the buyer's bearer token; prove a buyer's list in the browser.
- **The checkout reads the user's own address fields, not the address book.** A user with only
  address-book entries is told "You do not have any address yet". Set `address`, `zip`, `city`,
  `country` and `countryCode` on the user (`update_users`); the address book then adds its entries as
  further delivery radios.
- **A cart keeps the customer fields it was created with.** A cart created before the user had an
  address fails the billing validation (customer address, city, zip) with the empty alert above, for
  ever. Start a new cart: delete the old one, or run the history reset of the
  `orders.completed-orders` recipe in `dw-demo-ledger`, which removes the buyer's unnamed carts.
- **Prices are hidden from anonymous visitors**, so a price check runs signed in, and a signed-in price
  is the buyer's own (contract, group or tier row), not the list price.

## Cleaning up after a check

An order a check places is the buyer's, numbered from the series, with no purchase order number. The
history reset of `orders.completed-orders` (a prune step scoped to the buyer) lists it WOULD-DELETE in a
verify run and soft-deletes it with `-Apply`, together with any cart the check left. Run it before the
demo call.
