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

## The Three Main ViewModels

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

- [ViewModelBase](references/viewmodel-base.cs) — the foundation class
- [ParagraphViewModel](references/paragraph-viewmodel.cs) — paragraph rendering context
- [ItemViewModel](references/item-viewmodel.cs) — item field accessors (all methods documented)
- [ItemViewModelExtensions](references/item-viewmodel-extensions.cs) — validation helpers
- [Swift Template: Image](references/swift-image-template.cshtml) — simple image + link pattern
- [Swift Template: Image + Text + Buttons](references/swift-imagetext-template.cshtml) — complex layout with multiple field types
- [Swift Template: Buttons Only](references/swift-buttons-template.cshtml) — focused button rendering

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
