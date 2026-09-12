# What the shipped Swift 2 templates do, and what they do not

> Measured behaviour of templates that ship with Swift 2 — the guards one file has and its sibling
> does not, the fields a surface never renders, the markup contracts a consumer has to match, and the
> prices the markup carries whether or not the page displays them. Each entry names the shipped file,
> so a build can decide between a net-new Custom-lane copy and a stated limitation. Companion to
> [`component-system-and-reskin.md`](component-system-and-reskin.md) §9 (the never-edit-standard-templates
> doctrine and the allowed override slot).
>
> Version-pinned where the behaviour is build-specific. Swift 2.x only — never follow
> `/swift/swift-1/` URLs.

## Contents

- [How to use this file](#how-to-use-this-file)
- [Templates that do not compile on DW 10.29 / .NET 10](#templates-that-do-not-compile-on-dw-1029--net-10)
- [The product-search dropdown crashes on a catalogue with no product images](#the-product-search-dropdown-crashes-on-a-catalogue-with-no-product-images)
- [The order list and order detail never render the payment method](#the-order-list-and-order-detail-never-render-the-payment-method)
- [A price-hidden buyer: the price is not displayed, and it IS delivered](#a-price-hidden-buyer-the-price-is-not-displayed-and-it-is-delivered)
- [A currency-symbol census cannot express "this buyer sees no prices"](#a-currency-symbol-census-cannot-express-this-buyer-sees-no-prices)
- [The Express Buy feed's row contract](#the-express-buy-feeds-row-contract)

## How to use this file

Every entry below is a shipped-file behaviour, not a misconfiguration, so the routes are the same
three each time: state the limitation and stop; ship a **net-new Custom-lane copy** of the template
and repoint the paragraph at it (leaving the standard file untouched); or, where the defect is in an
upstream file every solution inherits, raise it upstream and carry the trap row until the fix ships.
Editing the standard file in place is the one route that is never right —
[`component-system-and-reskin.md`](component-system-and-reskin.md) §9 owns that rule.

## Templates that do not compile on DW 10.29 / .NET 10

**Two shipped Swift 2.4.0 templates call `System.Web.HttpUtility`, a legacy `System.Web` API that
does not exist under DW 10.29 / .NET 10, so they fail to compile:**

- `QueryPublisher/Post/PostPagination.cshtml`
- `UserManagement/CreateProfile/ManageUsersInviteEmail.cshtml`

**The two failure modes are not equally visible, and that is the point.** When the failing call sits
in markup a visitor is looking at, the **uncompiled Razor source itself reaches the response** — the
post-list page serves raw Razor text instead of the pagination control, and it is not a `dw-error`
block, so an error-block count reads clean. When it sits in a template nobody watches render — an
invitation e-mail — the same compile failure produces no visible symptom at all: no error page, no
`dw-error`, just a missing or broken mail.

Rewrite both onto the ASP.NET Core equivalent, or take the fix from the upstream theme once it
ships. **Sweep for the API rather than for the two file names**:
`grep -r "System.Web" Templates/Designs/Swift-v2/` — and check the result of any template that
renders into a mail or a background job by reading what it produced, never by the absence of an
error block. A third occurrence in the legacy `Designs/Swift/` (Swift v1) tree is unused on a Swift 2
solution; leave it alone.

## The product-search dropdown crashes on a catalogue with no product images

`eCom/ProductCatalog/List/ProductSearchDropdownResponse.cshtml` dereferences
`suggestion.DefaultImage.Value` **unguarded**, so it throws `System.NullReferenceException` for every
search term that matches at least one product on a catalogue whose products carry no default image
(`EcomProducts.ProductImageSmall` / `ProductImageLarge` empty). A term with **zero** hits renders
fine, which is why the defect survives URL sweeps: the hosting page answers 200 and the dropdown is
an XHR nothing had exercised.

The shipped sibling `ExpressBuySearchResponse.cshtml` already writes `product?.DefaultImage?.Value`
— Swift treats the field as nullable in one file and not in the other, so the null guard is the
shipped intent. **Render the thumbnail only when there is one and reserve its slot otherwise**, in a
net-new copy; that is one `@if` and no other change to the product loop.

**Exercise every XHR surface in the sweep, not only page URLs**, and exercise the search with a term
that MUST match. A zero-hit term proves nothing about the matching path.

## The order list and order detail never render the payment method

Under `eCom/CustomerExperienceCenter/Orders/`, `List/Orders_List.cshtml` and
`Detail/Orders_Details.cshtml` contain **no reference to `PaymentMethod`** (their only "Payment"
strings are the payment-FEE line in the totals). Every sibling detail template renders it:
`Carts_Details`, `Quotes_Details`, `Invoices_Details` and `PaymentHistory_Details` all print
`Model.PaymentMethod?.Name`, and the developer cheat-sheet template prints its id, description, code
and terms code too. The field is on the view model of the very page that omits it, and the omission
is in the only two surfaces a buyer looks at after the order exists. The detail page does render a
Shipping Information block with the shipping method, right where the payment counterpart would go.

Two consequences worth planning around:

- **Any change to the payment method on existing orders has no customer-facing surface to verify it
  on.** A terms migration, an ERP re-key or a data fix will otherwise be written against an
  acceptance criterion ("the order history reads *Charge on Account*") that cannot be met. Prove it
  at the platform layer instead — read the orders back through the order service after flushing its
  cache — and assert the rendered order surfaces are **byte-identical** before and after, which is a
  stronger statement about side effects than the rendered-text criterion would have been.
- The display fix is a net-new copy of `Orders_Details.cshtml` carrying the same block
  `Carts_Details.cshtml` already has, beside the existing Shipping Method block, plus optionally a
  column on the list.

## A price-hidden buyer: the price is not displayed, and it IS delivered

**A price-hidden or price-on-request role cannot be satisfied by template guards alone in Swift 2.**
The guard pattern — a group test wrapped round every money OUTPUT — is the reasonable one and it is
complete for output. Two shipped components carry the resolved, customer-specific price in markup
that is **not output**, so no output guard reaches them and a tags-stripped census cannot see them:

| Carrier | Shipped component | Shape |
|---|---|---|
| `ProductPrice` hidden input | `Swift-v2_ProductAddToCart`, on the PDP **and** on every product card | `<input type="hidden" name="ProductPrice" value="39.95">` |
| `ProductDiscount` hidden input | same | `<input type="hidden" name="ProductDiscount" value="0.00">` |
| `data-product-price` attribute | the product card wrapper (analytics / tag-manager) | `data-product-price="28.95" data-product-discount="0.00" data-product-currency="USD"` |

The fields exist for the mini-cart's optimistic render and for analytics, and the value is the
resolved price for that buyer — on a per-branch or per-customer priced catalogue, their own price.
A list page therefore delivers the whole price list for its segment, twice per product, while a
fifteen-surface audit reports zero currency strings: **the audit and the leak have exactly
complementary blind spots**, which is how both can be true at once.

- **State the claim honestly: "no price is DISPLAYED", not "no price is delivered."** That is a
  defensible position for a demo or an MVP, and it should be a stated position rather than something
  a prospect's developer finds with view-source.
- **A solution that needs the stronger claim has to reach the markup**: omit the two hidden inputs
  and the card attribute when the price is not displayed, which means forking two shipped components
  (and changes add-to-cart behaviour for every persona — the cart service must re-resolve the price
  server-side anyway, for correctness).
- The usual architectural prescription for the stronger claim — a `ProductViewModel` subclass bound
  by AddIn name plus a second catalogue app instance — **does not bind on 10.28**, so the honest
  answer today is template guards plus the component edit, not a view model.

## A currency-symbol census cannot express "this buyer sees no prices"

**A `notContains ["$"]` assert can never pass on a Swift product list page**, however perfectly the
page behaves: the shipped `PriceRange` facet renders its bands as literal currency text in both
`value` and `data-filter-value`, identically for every visitor including one who is shown no prices
at all (36 dollar signs measured on a clean page, every one a facet option label). The currency
symbol is not a marker of a price on that page.

**Anchor the census on the decimal, not on the symbol**, and pair it with a byte floor:

```
/\$\s?[0-9][0-9,]*\.[0-9]{2}/
```

Measured on the same URLs in the same hour: price-hidden buyer 0 unique matches on the list page and
0 on order history; control buyer 17 and 45. That is a real discrimination, and "does not contain a
dollar sign" is not. The floor matters because a zero-match assert is satisfied perfectly by a denial
body, an empty render or a 500 — assert a minimum response size in the same check.

Know what the census still cannot see: the attribute and hidden-input carriers above have no
currency symbol at all, so a text-anchored regex reads zero on a page that ships every price. A
census that answers "does this buyer see money" needs a **second metric over the RAW HTML** for
attribute and form-value carriers, exactly as it already needs one for bare decimals, because a
no-symbol price formatter defeats a symbol-only count.

## The Express Buy feed's row contract

Swift's Express Buy page in feed mode is the assortment-scoped product lookup a
"type an item number" surface should reuse — reusing it is the right call, because it inherits
scoping instead of re-implementing it. Two things about it defeat a consumer written from
assumption:

- **The response is HTML, not JSON**, so there is no schema to fail against.
- **It works only at the page's FRIENDLY url.** The `/Default.aspx?ID=<n>&feed=true` form 301s to the
  friendly url and **loses feed mode**: the request is then served by the normal page template, which
  throws `Template file not found … ExpressBuySearchResponse.cshtml` into `Templates/Errors` and
  returns a full page (55 KB against 8 KB for the identical query at the friendly url).

The row shape, measured off the wire:

```html
<article class="… product js-replacement-product" data-product-counter="1">
  <input class="productId" …>  <input class="productVariantId" …>
  <… class="productNumber">SKU</…>   <… class="js-product-name">Name</…>
```

**The ids live in CHILD INPUTS.** There is no `data-product-id`, `data-variant-id` or
`data-product-number` attribute anywhere on the article, and no `.product-name` class; the only
id-shaped attribute present is `data-product-counter`, which is an index.

**Why a guessed selector is so expensive here: it fails CLOSED and in the shape of the correct
negative.** A consumer written against the attribute form parses the document successfully, matches
zero articles, and reports every item number as out of range — which is exactly what a genuine
assortment rejection produces. Typing a SKU that must be rejected confirms it; typing an unknown SKU
confirms it; the feature is broken and every obvious test passes.

**Test a lookup surface with a value that MUST resolve, not only with values that must not.** The
control set that discriminates is four cases: in range for this buyer, in range only for this
buyer's scope, in range only for a different scope (0 rows), and non-existent (0 rows) — plus the
same out-of-scope value as a buyer who is scoped to it, which must return rows.
