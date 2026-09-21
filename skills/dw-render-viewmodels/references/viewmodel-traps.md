# View-model properties: nullable, and not what the name says

Two failure shapes that are invisible in review and expensive in production: a property whose value
is legally `null` on a row anyone can reach, and a property whose name promises something the value
is not. Both are read through the **view model surface** in a `.cshtml` template.

## Contents

- [1. Nullable properties and the blast radius rule](#1-nullable-properties-and-the-blast-radius-rule)
- [2. Properties whose name is not their meaning](#2-properties-whose-name-is-not-their-meaning)

## 1. Nullable properties and the blast radius rule

**A null on one row takes down the whole surface, not the row.** A catalogue template that fans out
over a result set renders inside one compiled unit, so a `NullReferenceException` on card twelve
replaces cards one through twelve with a `dw-error` dump — at **HTTP 200, with the site chrome
intact**. A gate that checks status codes and byte counts sees nothing wrong; the page is often
*larger* than the healthy one.

**So guard every nullable dereference in any template that loops**, even where the same file writes
the guarded form elsewhere:

```cshtml
@* every dereference, not just the ones on the visible path *@
string imagePath = product?.DefaultImage?.Value ?? string.Empty;
```

| Property | Null when | Guard |
|---|---|---|
| `product.DefaultImage` | the product has no image — legal, and reachable by searching for or favouriting any product | `product?.DefaultImage?.Value` |
| `product.Price` | no price resolves for the user, currency or assortment | `product?.Price?.PriceFormatted` |
| `product.ReplacementProduct` | no replacement is configured on a discontinued product | `p?.ReplacementProduct?.…` |
| `Model.Item` | the paragraph has no item attached | `Model.Item?.GetString("Field")` |

Two shipped Swift 2.2 templates dereference `product.DefaultImage.Value` with no guard and are worth
auditing on any solution running them, because each turns one image-less product into a whole dead
surface:

- `eCom/ProductCatalog/ExpressBuySearchResponse.cshtml` — the out-of-stock modal iterates **every**
  product in the result set and builds its thumbnail unguarded, twenty lines above the same file's
  own guarded form. One image-less product in the results returns zero rows for that search term
  while other terms work, which reads as a search or indexing fault, not a template fault.
- `eCom/CustomerExperienceCenter/Favorites/List/FavoriteLists.cshtml` — both thumbnail blocks, twice
  each. Adding one image-less product to a list kills the whole favourites page.

**Bisect to confirm:** restore the single unguarded expression and the failure returns for the same
search term; re-guard it alone and the surface comes back. That is what distinguishes a template
defect from a data or index problem.

**Assert on the content, not the status.** A storefront check for these surfaces counts rendered
rows and `dw-error` nodes in the served markup; status code and byte size cannot see the failure.

## 2. Properties whose name is not their meaning

| Property | What it actually holds | Use instead |
|---|---|---|
| `MediaViewModel.Name` | the **detail id** from `EcomDetails` (e.g. a document's system identifier) | `MediaViewModel.DisplayName` — this is where `EcomDetails.DetailsName`, the friendly name, surfaces. The shipped `ProductMediaTable` template uses `DisplayName` with a filename fallback: `Path.GetFileNameWithoutExtension(...)` when `DisplayName` is empty |
| `product.StockLevel` | a stock **level label** (a string) | `product.Stock` for the quantity; compare `StockLevel` only against label values |
| `product.ManufacturerName` | the manufacturer relation flattened to one string | there is no `Manufacturer` navigation property to reach instead |
| `product.DefaultUnit` / `product.DefaultUnitName` | neither resolves on `ProductViewModel` | `product.PriceUnitDescription`, a custom field via `product.GetField("…")`, or a static string in the layout |
| `product.ProductFieldValues` | lives on the underlying `Dynamicweb.Ecommerce.Products.Product` **entity**, not the view model; reading it off a view model renders raw Razor source as page text on the PDP | resolve the entity — see [`template-compilation.md`](../../dw-render-razor/references/template-compilation.md) §2 |

The document-card case is the one that ships quietly: a media table bound to `Name` renders the
detail ids next to every asset and looks like a data-entry problem in the PIM, where the friendly
name is in fact already stored.

## Cross-references

- [`template-compilation.md`](../../dw-render-razor/references/template-compilation.md) — which
  members exist on which template base, and why a null dereference surfaces as page text.
- [dw-commerce-catalog](../../dw-commerce-catalog/SKILL.md) — catalogue rendering and pricing read
  surfaces.
- [dw-pim-modelling](../../dw-pim-modelling/SKILL.md) — where `EcomDetails` asset names are
  maintained.
