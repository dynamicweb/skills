---
name: dw-render-razor
type: knowledge
group: render
description: Build template hierarchies and Razor patterns in Dynamicweb 10 — the foundation for all rendering. Triggers: template structure under Files/Templates/Designs/, Razor syntax, canonical render surfaces. Non-triggers: fetching data with ViewModels -> dw-render-viewmodels; using TemplateTags -> dw-render-templatetags; designing page/item types -> dw-content-modelling.
---

# Razor Templates: Foundation for Rendering

All templates in Dynamicweb 10 are **Razor templates** (`.cshtml` files). Razor is a templating syntax that embeds C# directly into HTML, allowing you to generate dynamic content on the server before sending it to the browser.

## Core Concepts

### Template Hierarchy

Templates live under `Files/Templates/Designs/<YourDesign>/` and follow a folder structure organized by template type and feature area:

```
Files/Templates/Designs/Swift-v2/
├── Paragraph/                    ← Page paragraph templates (content building blocks)
│   ├── Swift-v2_Image/
│   │   └── Plain.cshtml
│   ├── Swift-v2_TextAndImage/
│   │   └── ImageTopTextLeft.cshtml
│   └── Swift-v2_Button/
│       └── ButtonCenter.cshtml
├── eCom/                         ← E-commerce templates (product pages, lists)
│   ├── ProductPage.cshtml
│   └── ProductList.cshtml
├── Navigation/                   ← Navigation and menu templates
│   ├── Header.cshtml
│   └── Footer.cshtml
├── Forms/                        ← Form templates
├── Custom/                       ← Custom item templates (for extensibility)
└── Master.cshtml                 ← Site-wide wrapper (optional)
```

Dynamicweb renders pages by **nesting** templates: the Master template wraps page templates, which include paragraph/item templates. This hierarchy keeps concerns separated — navigation in Master, content in page templates, specific component logic in paragraph templates.

### Razor Syntax

All templates use standard Razor syntax:

```html
<!-- C# expressions -->
<h1>@Model.Title</h1>

<!-- Loops -->
@foreach (var item in Model.Items)
{
    <div>@item.Name</div>
}

<!-- Conditionals -->
@if (Model.IsVisible)
{
    <p>@Model.Description</p>
}

<!-- Safe null-coalescing -->
<p>@(Model.Text ?? "No text provided")</p>

<!-- Method calls -->
<img src="@GetImageUrl(Model.DefaultImage)" alt="@Model.Name">
```

Helper methods like `GetImageUrl()`, `Translate()`, and `GetPageIdByNavigationTag()` are available in all templates — these are Dynamicweb built-ins.

## Two Binding Patterns

Dynamicweb provides **two ways** to bind data to templates:

### 1. ViewModels (Recommended)

**ViewModels** are the modern, type-safe approach. You inherit from a specific ViewModel class (e.g., `ProductViewModel`, `ParagraphViewModel`), and access properties directly via `@Model`:

```html
@inherits ViewModelTemplate<ProductViewModel>

<h1>@Model.Name</h1>
<p>Price: @Model.Price.Price.Formatted</p>

@foreach (var variant in Model.Variants ?? new List<VariantViewModel>())
{
    <button>@variant.Name</button>
}
```

**Advantages:**
- **Type-safe** — compiler catches property name typos
- **IntelliSense support** — your IDE suggests properties as you type
- **Performance** — Dynamicweb lazy-loads only the properties you access
- **Clear contract** — the template's requirements are explicit in the `@inherits` line
- **Modern** — actively maintained and recommended by Dynamicweb

**When to use:** All new templates. All paragraph/item rendering. When building product pages, content lists, or any data-driven UI.

Examples: See [dw-render-viewmodels](../dw-render-viewmodels/SKILL.md) for comprehensive ViewModel patterns, including ItemViewModel, ParagraphViewModel, ProductViewModel, and ProductListViewModel.

### 2. TemplateTags (Legacy)

**TemplateTags** are the older, string-based approach. You access data via helper methods like `GetString()` and `GetLoop()`:

```html
<h1>@GetString("Product.Name")</h1>
<p>Price: @GetString("Product.Price")</p>

@foreach (var item in GetLoop("Product.Variants"))
{
    <button>@item.GetString("Name")</button>
}
```

**Disadvantages:**
- **No type safety** — typos in string keys cause silent failures
- **No IntelliSense** — you must remember property paths by heart
- **Performance overhead** — retrieves all data, doesn't lazy-load
- **Being phased out** — new features are added to ViewModels, not TemplateTags

**When to use:** Only when working with legacy templates that predate ViewModels. Do not start new templates with TemplateTags.

For TemplateTags details, see [dw-render-templatetags](../dw-render-templatetags/SKILL.md).

## Template Structure Basics

### Master Template

The Master template wraps your entire site. It typically includes:

```html
@inherits ViewModelTemplate<PageViewModel>

<!DOCTYPE html>
<html>
<head>
    <title>@Model.Title</title>
</head>
<body>
    @RenderHeader()              <!-- Custom method or included file -->
    
    @RenderBody()                <!-- Child page content inserted here -->
    
    @RenderFooter()              <!-- Custom method or included file -->
</body>
</html>
```

### Page Template

Page templates inherit from a page-specific ViewModel and render sections:

```html
@inherits ViewModelTemplate<PageViewModel>

<main class="page-content">
    <h1>@Model.Title</h1>
    
    @if (Model.Paragraphs != null)
    {
        @foreach (var paragraph in Model.Paragraphs)
        {
            @RenderParagraph(paragraph)   <!-- Delegate to paragraph template -->
        }
    }
</main>
```

### Paragraph/Item Template

The smallest unit — renders one instance of a paragraph or custom item:

```html
@inherits ViewModelTemplate<ParagraphViewModel>

<section class="paragraph paragraph-@Model.ModuleSystemName">
    @if (Model.Item != null)
    {
        <h3>@Model.Item.GetString("Title")</h3>
        <p>@Model.Item.GetString("Description")</p>
    }
</section>
```

## Common Patterns

### Safe Property Access

Always guard against null values:

```html
<!-- TryGet pattern (ViewModels) -->
@if (Model.TryGetImageFile("HeroImage", out var file))
{
    <img src="@file.Path" alt="Hero">
}

<!-- Null-coalescing (both) -->
<p>@(Model.Description ?? "No description")</p>

<!-- Ternary operator -->
<p class="@(Model.IsActive ? "active" : "inactive")">Status</p>
```

### Translatable Strings

Use `Translate()` to support multi-language sites:

```html
<label>@Translate("Product Price")</label>
<button>@Translate("Add to Cart")</button>
```

### Building URLs

Use `GetPageIdByNavigationTag()` to link to other pages:

```html
<a href="@GetUrl(GetPageIdByNavigationTag("Shop"))">
    Shop
</a>

<a href="@GetUrl(GetPageIdByNavigationTag("Product"), "id=@Model.Id")">
    View Product
</a>
```

### Looping with Index

When you need the current loop position:

```html
@{
    var items = Model.Items ?? new List<ItemViewModel>();
}

@for (int i = 0; i < items.Count; i++)
{
    <div class="item item-@i">
        @items[i].Name
    </div>
}
```

## Deciding Between ViewModels and TemplateTags

| Scenario | Use |
|----------|-----|
| New template, modern codebase | **ViewModels** |
| Existing legacy templates | **TemplateTags** (for now; migrate over time) |
| Mixed data sources (some dynamic, some static HTML) | **ViewModels** for dynamic parts, plain HTML for static |
| Performance-sensitive list rendering (100+ items) | **ViewModels** (lazy-loading) |
| Need type safety and IDE support | **ViewModels** |
| Quick prototype or one-off template | **ViewModels** (saves time debugging typos) |

## Gotchas

**Null reference exceptions**: Always check `Model != null` at the start of data-driven templates. A missing ViewModel binding will cause silent failures or exceptions.

**Invalid Razor syntax**: Razor has strict rules about `@` escaping. If you need a literal `@`, escape it as `@@`.

**RenderBody() only once**: If you call `@RenderBody()` multiple times in a Master template, content renders multiple times (usually unintended). Only call it once.

**Case sensitivity in TemplateTags**: Property names in `GetString("Product.Name")` are case-sensitive. Typos cause silent failures.

**Loop variable scope**: Loop variables (from `@foreach`) are local to that loop. Don't try to reference them outside the loop block.

## Next Steps

- **For ViewModel-based rendering:** See [dw-render-viewmodels](../dw-render-viewmodels/SKILL.md) for ItemViewModel, ParagraphViewModel, ProductViewModel examples, and when to drop to C# APIs.
- **For TemplateTags (legacy):** See [dw-render-templatetags](../dw-render-templatetags/SKILL.md).
- **For data modeling:** See [dw-content-modelling](../dw-content-modelling/SKILL.md) to design the pages/items/fields that feed these templates.
