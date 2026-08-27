---
name: dw-commerce-catalog
type: knowledge
group: commerce
mcp: optional
description: 'Render product catalogs and assortments in Dynamicweb 10, and convert or set a product price in a specific currency through the MCP tools. Triggers: ProductListViewModel, catalog display, assortment rendering, convert an amount between currencies, set a price in a non-default currency. Non-triggers: product workflow -> dw-pim-workflow; orders and checkout -> dw-commerce-orders.'
---

# Product Catalog Rendering

## Without MCP

The knowledge here stands alone; the Dynamicweb MCP tools it names are the preferred way to
apply it. When no Dynamicweb MCP server is connected, work in advisory mode — explain,
review, or produce payloads and configuration for the user to apply — and do not substitute
direct SQL, file edits, or guessed HTTP calls for those tool calls.

## App and Template Overview

The **Product Catalog** app is added to a paragraph on any content page. Templates live in `Designs\YourDesign\Ecom\ProductCatalog\` and there are four template types:

| Template type | ViewModel | When loaded |
|--------------|-----------|------------|
| List | `ProductListViewModel` | Default view — group or search results |
| Details | `ProductViewModel` | `ProductId` is present in the URL |
| Feed | `ProductListViewModel` | `feed=true` in URL |
| Compare | — | `compare=true` and `productnumber` in URL |

## ProductListViewModel

`Dynamicweb.Ecommerce.ProductCatalog.ProductListViewModel` — top-level model for list templates.

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Ecommerce.ProductCatalog.ProductListViewModel>
@using Dynamicweb.Ecommerce.ProductCatalog
```

**Key properties:**

| Property | Type | Description |
|----------|------|-------------|
| `Model.Products` | `IEnumerable<ProductViewModel>` | Products on current page |
| `Model.Group` | `ProductGroupViewModel` | Current product group (null for search results) |
| `Model.SubGroups` | `IEnumerable<ProductGroupViewModel>` | Child groups of current group |
| `Model.TotalProductsCount` | `int` | Total products across all pages |
| `Model.PageSize` | `int` | Products per page |
| `Model.PageCount` | `int` | Total pages |
| `Model.CurrentPage` | `int` | Current page number (1-indexed) |
| `Model.SortBy` | `string` | Active sort field (e.g., `"Name"`) |
| `Model.SortOrder` | `string` | `"ASC"` or `"DESC"` |
| `Model.FacetGroups` | `IEnumerable<FacetGroupViewModel>` | Filter categories and options |
| `Model.SpellCheckerSuggestions` | `IEnumerable<string>` | Alternative search terms |
| `Model.IsSearchResult` | `bool` | True if triggered by a search query |

### Iterating Products

```razor
@foreach (var product in Model.Products)
{
    <div class="product-card">
        <a href="@product.GetProductLink(GetPageIdByNavigationTag("Shop"))">
            <img src="@product.DefaultImage" alt="@product.Name" />
            <h3>@product.Name</h3>
            <span>@product.Price.PriceFormatted</span>
        </a>
    </div>
}
```

### Facet Sidebar

```razor
@if (Model.FacetGroups != null)
{
    @foreach (var facetGroup in Model.FacetGroups)
    {
        @foreach (var facet in facetGroup.Facets)
        {
            <div class="filter-group">
                <h5>@facet.Name</h5>
                @foreach (var option in facet.Options)
                {
                    <label>
                        <input type="checkbox" name="@facet.QueryParameter"
                               value="@option.Value"
                               checked="@option.Selected" />
                        @option.Label (@option.Count)
                    </label>
                }
            </div>
        }
    }
}
```

URL syntax for multi-value facets: `&Color=[Red],[Blue]`. For values containing commas or slashes, always wrap in `[brackets]`.

### Pagination

```razor
@for (int p = 1; p <= Model.PageCount; p++)
{
    <a href="?PageNum=@p" class="@(p == Model.CurrentPage ? "active" : "")">@p</a>
}
```

## ProductViewModel

`Dynamicweb.Ecommerce.ProductCatalog.ProductViewModel` — single product model used by Detail templates and each item in `Model.Products`.

**Key properties:**

| Property | Type | Notes |
|----------|------|-------|
| `Id` | `string` | Product ID |
| `VariantId` | `string` | Variant combination ID |
| `Name` | `string` | Product name |
| `Number` | `string` | SKU / product number |
| `ShortDescription` | `string` | Short description |
| `LongDescription` | `string` | Full description (HTML) |
| `DefaultImage` | `string` | Primary image path |
| `Price` | `PriceViewModel` | Current price with formatting and VAT |
| `PriceBeforeDiscount` | `PriceViewModel` | Original price (before discount) |
| `Prices` | `IEnumerable<PriceListViewModel>` | Volume/quantity price tiers |
| `StockLevel` | `double` | Available stock quantity |
| `NeverOutOfstock` | `bool` | Ignore stock limits if true |
| `VariantName` | `string` | Human-readable variant label (e.g. "Red, Large") |
| `ProductType` | enum | Stock, Service, NonStock |
| `FieldDisplayGroups` | `IEnumerable` | Custom product fields grouped by category |
| `PurchaseQuantityStep` | `int` | Step increment for quantity input |
| `PurchaseMinimumQuantity` | `int` | Minimum order quantity |

```csharp
product.HasDiscount()           // true if discounted
product.GetProductLink(pageId)  // URL to product detail page
```

### Volume/Tier Prices

```razor
@foreach (var tier in product.Prices)
{
    <tr>
        <td>@tier.Quantity+</td>
        <td>@tier.Price.PriceWithVatFormatted</td>
        <td>@tier.UnitId</td>
    </tr>
}
```

## Product Catalog App Settings

| Section | Key settings |
|---------|-------------|
| **Index** | Select a Repository Query and Facet group(s) |
| **Display** | Products per page, pagination style |
| **Templates** | Select List/Details/Compare/Feed templates |
| **Product Properties** | Toggle which ViewModel properties to include (skip expensive ones for lists) |
| **Spell Check** | Enable and configure did-you-mean suggestions |

**"Use group sort in group context"** — when `GroupID` is in the URL, uses the sort order defined on the product group instead of the query's default sort.

## Currency Conversion

Setting or converting a price in a specific currency has one rule above the rest: **never
convert in your head; use the tool.** For ANY currency conversion, call `convert_currency`
(`amount`, `fromCurrencyCode`, `toCurrencyCode`). It reads this solution's live, configured
rates and applies Dynamicweb's exact engine formula, so the answer matches the storefront.
Report the number it returns.

**Do not compute conversions by hand, and never use rate numbers from documentation examples
as if they were this solution's rates.** Illustrative doc values are concept-only; the real
rates live on the solution and are usually completely different. Using doc numbers gives a
confidently wrong answer — the single most common failure here.

**Default currency means no conversion.** If the requested currency IS the solution's default
currency, do not convert — just set the product's default price (`defaultPrice` via
`patch_products_safe`) to the amount given. Do not run rate math and do not create a
`save_prices` row. Only convert — and only then touch exchange rates — when the target
currency is **different** from the default. "Set the price to 4999" with no currency named
means 4999 in the default currency.

**How it works.** The default currency is the reference; every currency's `Rate` is relative
to it. Find the default with `get_currencies` → the entry where `IsDefault = true`. Read rates;
never assume them. Dynamicweb's engine converts with exactly:

```
convertedAmount = amount * fromCurrency.Rate / toCurrency.Rate
```

That is what `convert_currency` returns. Worked example with live rates EUR `100` (default),
DKK `15`: 4999 DKK → EUR = `4999 * 15 / 100 = 749.85 EUR`; 100 EUR → DKK = `100 * 100 / 15 ≈
666.67 DKK`. (Documentation describing this relationship in prose can read inverted relative
to the engine, and its example numbers are never this solution's rates — trust
`convert_currency` and the solution's real `Rate` values instead.)

**Procedure:** identify the target currency (equals default → set `defaultPrice` and stop, no
conversion) → convert with `convert_currency(amount, from, to)` (report the rounded amount and
the rates used, for transparency) → write, if setting the price, with `save_prices` as a price
row carrying the target `CurrencyCode` (`save_prices` does **not** convert — give it the
already-converted amount).

**Sanity checks:**
- `save_prices` and `patch_products_safe` perform no automatic conversion; `convert_currency`
  does the math, those tools store what they're given.
- A currency with `Rate = 0` cannot be a conversion target — `convert_currency` refuses it. Fix
  the rate first.
- If rates look unrealistic for the pair (e.g. EUR `100` default and DKK `15`, implying 1 DKK ≈
  0.15 EUR), the solution's currency setup is likely misconfigured — say so plainly rather
  than silently emitting a nonsensical price.
- Don't explain a result with rate logic when no conversion happened (target was the default
  currency) — state that the default price was set directly.

When editing currency definitions with `save_currencies`, remember a currency's `Rate` is
relative to the default currency in this base-rate model, not a plain market-style "1 target =
x default" factor — convert a market rate into this model before saving.

## Search Index Setup

A product index is required for the Product Catalog app to serve results. The full setup (repository → index → instances → build configuration → fields → query → build), facet field rules, and auto-rebuild triggers live in [dw-search-indexing](../dw-search-indexing).

## Deep reference

[references/catalog-publishing.md](references/catalog-publishing.md) — the field-validated catalog internals: Catalog-vs-Channel group trees (the published-to story), the native "Publish to channel" action, channels + feeds (and the `/dwapi/feeds/{id}` URL shape), assortments-vs-channels, the pricing traps (tier rows not honored by the stock cart, the canonical price read surface, customer-specific contract prices), and the Management API chains for variants (no SQL), product relations, images, and shops — including the `ShopSave` `UsageType` trap and the create-vs-update verb split.

## Pitfalls

**Expensive ViewModel properties on lists** — `StockLevel`, `Prices`, `FieldDisplayGroups`, and image collections hit the database per product. Disable unused properties in the app's Product Properties settings for list templates.

**Set facet fields to non-analyzed** — an analyzed facet field splits values like "Light Blue" into "light" and "blue", corrupting facet display and filtering.

**Search index out of sync after deletes** — only full rebuilds remove deleted products. An Update build does not detect deletions.

**`Model.FacetGroups` is null** — if the app is not configured with a facet group in its Index settings, `FacetGroups` is null (not an empty list). Always null-check before iterating.

## Next Steps

- **Setting up the search index?** See [dw-search-indexing](../dw-search-indexing)
- **Building checkout flows?** See [dw-commerce-orders](../dw-commerce-orders)
- **B2B assortment scoping?** See [dw-commerce-b2b](../dw-commerce-b2b)
- **Rendering with ViewModels?** See [dw-render-viewmodels](../dw-render-viewmodels)
- **Cache invalidation after mutations (what to flush, when a restart is owed)?** See [dw-data-access](../dw-data-access/SKILL.md)
