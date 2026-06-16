---
name: dw-render-viewmodels
description: Fetch and shape content using ViewModels in Dynamicweb 10 templates. Triggers: ViewModel patterns, ViewModel properties, data shaping with ViewModels, when to drop to C# API. Non-triggers: TemplateTags syntax -> dw-render-templatetags; template structure and Razor -> dw-render-razor; direct C# API usage -> dw-extend-csharp-api.
---

# ViewModels: Rendering with Model-Based Data Access

ViewModels are the primary way to fetch and shape data for templates in Dynamicweb 10. Unlike TemplateTags which provide direct property access, ViewModels are strongly-typed C# classes that you access through `.` syntax in Razor templates — the modern, maintainable way to build templates.

## Core Concepts

**ViewModelBase** is the foundation. Your models inherit from it and expose properties that Razor templates can access:

```
Paragraph Template (Razor)
    ↓
@inherits ViewModelTemplate<ParagraphViewModel>
    ↓
Model.Item.GetString("FieldName")  ← ViewModel method
    ↓
Rendered output
```

## The Main ViewModels

### ParagraphViewModel
Rendering context for a single paragraph on a page. Contains grid position, container, image data, and the optional `Item` property.

**Key properties:**
- `Container`, `ContainerCount`, `ContainerSort` — grid/placement metadata
- `GridRowColumnCount`, `GridColumnNumber` — layout position
- `Image`, `ImageAlt`, `ImageLink`, `ImageFocalX/Y` — paragraph-level image
- `Item` → the ItemViewModel for this paragraph (if an item is attached)
- `Header`, `Text` — paragraph-level fields
- `ModuleSystemName`, `GetModuleOutput()` — attached modules

**When to use:** Most templates. Paragraphs are the primary rendering unit.

### ItemViewModel
Bridge between item data (from Content, PIM, or custom sources) and templates. The core tool for accessing field values.

**Methods by type:**
- `GetString(systemName)`, `TryGetString(systemName, out string)` — text fields
- `GetBoolean(systemName)` — checkboxes
- `GetInt32(systemName)`, `GetInt64(systemName)`, `GetDecimal(systemName)`, `GetDouble(systemName)` — numbers
- `GetDateTime(systemName)`, `TryGetDateTime(systemName, out DateTime)` — dates
- `GetImageFile(systemName)`, `TryGetImageFile(systemName, out ImageFileViewModel)` — single image
- `GetImageFiles(systemName)`, `TryGetImageFiles(systemName, out IEnumerable<ImageFileViewModel>)` — multiple images
- `GetFile(systemName)`, `GetFiles(systemName)` — file fields
- `GetItem(systemName)`, `GetItems(systemName)` — item relation fields
- `GetButton(systemName)`, `TryGetButton(systemName, out ButtonViewModel)` — buttons
- `GetLink(systemName)`, `TryGetLink(systemName, out LinkViewModel)` — links
- `GetList(systemName)` — dropdown/list fields
- `GetColor(systemName)`, `TryGetColor(systemName, out ColorViewModel)` — color pickers
- `GetGeolocation(systemName)` — geolocation fields
- `GetUser(systemName)`, `GetUsers(systemName)` — user references
- `GetUserGroup(systemName)`, `GetUserGroups(systemName)` — user group references
- `GetValue<T>(systemName)`, `GetRawValue(systemName)` — generic/raw field values

**When to use:** Whenever you need item field data in a template. Always your first choice for type safety.

### Metadata ViewModels
Objects returned by ItemViewModel methods that carry additional data:

- `ImageFileViewModel` — image properties (src, alt, focal points, etc.)
- `FileViewModel` — file/download properties
- `LinkViewModel` — URL, target, label
- `ButtonViewModel` — link + label + style
- `ColorViewModel` — hex color + name
- `ListViewModel` — dropdown options

## The Pattern: Safe Null-Coalescing

ViewModels default to safe values, never throw:

```csharp
// GetString on missing field → null
Model.Item.GetString("NonExistent")  // → null

// TryGet* for optional fields
if (Model.Item.TryGetImageFile("Photo", out var image)) {
    <img src="@image.ToGetImage()" alt="@image.AlternativeText" />
}

// Defaults for primitives
Model.Item.GetInt32("Quantity")  // → 0 if missing/null
```

## Template Example: Text + Image + Buttons

From Swift's `ImageTopTextLeft.cshtml`:

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Frontend.ParagraphViewModel>
@using Dynamicweb.Frontend

@if (Model.Item.TryGetImageFile("Image", out ImageFileViewModel image)) {
    <figure class="m-0 position-relative">
        <img src="@image.ToGetImage()" class="img-fluid" alt="@Model.Item?.GetString("AltText")" />
        @if (Model.Item.TryGetLink("ImageLink", out LinkViewModel link)) {
            <a href="@link.Url" class="stretched-link"></a>
        }
    </figure>
}

<div data-swift-text class="mb-0-last-child">
    @if (Model.Item.TryGetString("Title", out string title)) {
        <h3>@title</h3>
    }
    @if (Model.Item.TryGetString("Text", out string text)) {
        <p>@text</p>
    }
    @if (Model.Item.TryGetButton("FirstButton", out ButtonViewModel btn)) {
        <a href="@btn.Link.Url" class="btn btn-@btn.Style">@btn.Label</a>
    }
</div>
```

**Key patterns:**
- `@inherits ViewModelTemplate<ParagraphViewModel>` — bind the template to the ViewModel type
- `TryGet*` for optional fields — prevents null-reference exceptions
- `Model.Item` — access the item data
- `Model.` properties directly (e.g., `Model.Header`) for paragraph-level fields

## Ecommerce ViewModels

Product catalog apps expose specialized ViewModels for rendering products and lists. Use these in product templates.

### ProductViewModel
Represents a single product with all its data: name, SKU, description, pricing, images, variants, and stock info.

**Performance note:** Most properties are lazy-loaded. Using multiple expensive properties on large product lists (e.g., 100 products) can cause performance issues. On lists, stick to basic properties (`Name`, `Number`, `Price`, `DefaultImage`); load details on the product detail page.

**Key properties:**
- `Id` — product ID (eager loaded, no overhead)
- `VariantId` — variant combination (eager loaded)
- `LanguageId` — language context
- `Name`, `ShortDescription`, `LongDescription` — copy
- `Number` — SKU
- `Price` → `PriceViewModel` with VAT, currency, discount
- `PriceBeforeDiscount` → price before any discount applied
- `DefaultImage` → primary product image (string path)
- `VariantName` — human-readable variant label (e.g., "Red, Large")
- `StockLevel` — quantity available
- `ProductType` — Stock, Service, NonStock
- `NeverOutOfstock` — ignore stock limits if true
- `HasDiscount()` — check if discounted
- `GetProductLink(pageId)` — URL to product detail page
- `FieldDisplayGroups` — custom product fields grouped by category
- `PurchaseQuantityStep`, `PurchaseMinimumQuantity` — order constraints

**When to use:** Product catalog lists, product detail pages, cart/checkout, recommendations.

### ProductListViewModel
Top-level model for a product list page. Contains the current product set, pagination, sorting, facets (filters), and group navigation.

**Key properties:**
- `Products` → list of `ProductViewModel` on current page (null if not requested)
- `Group` → current product group (null for search results)
- `SubGroups` → child groups of current group
- `PageSize`, `PageCount`, `CurrentPage` — pagination state
- `TotalProductsCount` — total products across all pages
- `SortBy`, `SortOrder` — current sort (e.g., "Name", "ASC")
- `FacetGroups` → filter categories and options (null if not requested)
- `SpellCheckerSuggestions` → alternative search terms if few/no results

**When to use:** Product list pages. Iterate over `Products` to render each product; use `FacetGroups` for a filter sidebar; use pagination properties for "Load more" buttons.

### PriceViewModel
Encapsulates pricing with currency formatting, VAT info, and discount handling.

**Key properties:**
- `Price` → `PriceInfo { Value: double, Formatted: string, FormattedNoSymbol: string }`
- `PriceWithVat`, `PriceWithoutVat` → VAT variants
- `Vat` → VAT amount
- `VatPercent` → VAT as percentage
- `Currency` → `CurrencyInfo { Symbol: string, Code: string }`
- `ShowPricesWithVat`, `ReverseChargeForVat` — display flags

**When to use:** Whenever rendering product prices. Always prefer `Price.PriceFormatted` (respects user's locale and VAT rules) over raw `Value`.

## Template Example: Product Grid Card

From Swift's single-product card in a grid:

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Ecommerce.ProductCatalog.ProductViewModel>
@using Dynamicweb.Ecommerce.ProductCatalog

@{
    var product = Model;
    string link = product.GetProductLink(GetPageIdByNavigationTag("Shop"), false);
    string imagePath = product?.DefaultImage?.ToString() ?? string.Empty;
}

<a href="@link" class="text-decoration-none d-block">
    <div class="position-relative">
        <img src="@imagePath" class="img-fluid" alt="@product.Name" />
    </div>
    <div>
        <h3>@product.Name @product.VariantName</h3>
        
        @if (product.HasDiscount())
        {
            <span class="text-decoration-line-through opacity-75">
                @product.PriceBeforeDiscount.PriceFormatted
            </span>
        }
        
        <span class="text-price fw-bold">@product.Price.PriceFormatted</span>
        @if (product.Price.TryGetVatLabel(out string vatLabel)) {
            <small>@Translate(vatLabel)</small>
        }
    </div>
</a>
```

## Template Example: Product List with Facets

From Swift's related-products list (simplified):

```razor
@inherits ViewModelTemplate<ProductListViewModel>
@using Dynamicweb.Ecommerce.ProductCatalog

@foreach (var product in Model.Products)
{
    <tr>
        <td>@product.Number</td>
        <td><a href="@product.GetProductLink(GetPageIdByNavigationTag("Shop"))">@product.Name</a></td>
        <td>@product.Price.PriceFormatted</td>
        <td>
            @if (product.StockLevel > 0) { <span class="text-success">In Stock</span> }
            else { <span class="text-danger">Out of Stock</span> }
        </td>
    </tr>
}

@* Facet sidebar *@
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
                        <input type="checkbox" name="@facet.QueryParameter" value="@option.Value" />
                        @option.Label (@option.Count)
                    </label>
                }
            </div>
        }
    }
}

@* Pagination *@
@for (int p = 1; p <= Model.PageCount; p++)
{
    <a href="?PageNum=@p" class="@(p == Model.CurrentPage ? "active" : "")">@p</a>
}
```

## When to Drop to the C# API

ViewModels are sufficient for 95% of rendering. Reach for `dw-extend-csharp-api` when:

- You need behavior not exposed by the ViewModel (advanced filtering, custom logic)
- You're in a code-behind (`@{ }` block in Razor) and need Services
- The ViewModel method doesn't exist for your use case

Example: custom sorting of items by a computed field:

```csharp
@{
    var unsorted = Model.Item.GetItems("RelatedProducts");
    var sorted = unsorted.OrderBy(i => i.GetString("Priority")).ToList();
}
@foreach (var product in sorted) {
    <!-- render product -->
}
```

## References

**Core ViewModels:**
- [ViewModelBase](references/viewmodel-base.cs) — the foundation class
- [ParagraphViewModel](references/paragraph-viewmodel.cs) — paragraph rendering context
- [ItemViewModel](references/item-viewmodel.cs) — item field accessors (all methods documented)
- [ItemViewModelExtensions](references/item-viewmodel-extensions.cs) — validation helpers

**Ecommerce ViewModels:**
- [ProductViewModel](references/product-viewmodel.cs) — single product with pricing, images, variants
- [ProductListViewModel](references/product-list-viewmodel.cs) — product list page with pagination, filters, facets
- [PriceViewModel](references/price-viewmodel.cs) — currency-aware pricing with VAT

**Template Examples:**
- [Swift Template: Content Image](references/swift-image-template.cshtml) — simple image + link pattern
- [Swift Template: Content Image + Text + Buttons](references/swift-imagetext-template.cshtml) — complex content layout
- [Swift Template: Buttons Only](references/swift-buttons-template.cshtml) — focused button rendering
- [Swift Template: Product Card](references/swift-product-card.cshtml) — single product in grid with pricing
- [Swift Template: Product List with Facets](references/swift-product-list.cshtml) — full list with filters, pagination, stock

## Gotchas

**Null-coalescing on optional items:**
```csharp
Model.Item?.GetString("Field")  // Item might be null on some paragraphs
```

**Image focal points are relative to center:**
```csharp
ImageFocalX = -50   // 50% to the left of center
ImageFocalY = 0     // centered vertically
// Use ImageFocalPositionFromLeft (absolute 0–100) for CSS
```

**TemplateTags and ViewModels don't mix in the same template:**
Choose one binding model per template — switching mid-template breaks type safety.

**RawValue vs GetValue:**
```csharp
GetRawValue("Price")          // → raw DB value (might be string)
GetDecimal("Price")           // → parsed decimal, fallback 0
GetString("Price")            // → ToString() on raw
```

## Next Steps

- **Building templates?** Start with [dw-render-razor](../dw-render-razor) for the Razor foundation
- **Using TemplateTags instead?** See [dw-render-templatetags](../dw-render-templatetags)
- **Need custom business logic?** Move to [dw-extend-csharp-api](../dw-extend-csharp-api)
