---
name: dw-commerce-catalog
type: knowledge
group: commerce
description: 'Render product catalogs and assortments in Dynamicweb 10. Triggers: ProductListViewModel, catalog display, assortment rendering. Non-triggers: product workflow -> dw-pim-workflow; orders and checkout -> dw-commerce-orders.'
---

# Product Catalog Rendering

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

## Search Index Setup

A product index is required for the Product Catalog app to serve results.

1. Go to **Settings > System > Repositories** → create or open a repository
2. Add a new **Index** with Balancer: `ActivePassive` (serves from live while rebuilding passive)
3. Add **two instances** (A and B) using `LuceneIndexProvider`
4. Create a **Build configuration** selecting `ProductIndexBuilder`
5. Configure **fields** using `ProductIndexSchemaExtender` or `ConfigurableProductIndexSchemaExtender`
6. Add a **Query** and optionally **Facet groups** under the index
7. Click **Build**

**Field rules for facets:**
- Fields used as facets must be Indexed = Yes and Analyzed = No (analyzed fields split multi-word values into tokens, breaking facet grouping)
- Use **Grouping fields** for range-based facets (e.g., price brackets: "0-200", "200-500")

**Auto-rebuild triggers:**
- On product save (configure on the channel's Advanced Information tab)
- After integration job (configure in activity settings)
- On schedule (use the "Build repository index" scheduled task)

Note: auto-rebuild on save does NOT remove deleted products from the index. Only a full rebuild handles deletions.

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
