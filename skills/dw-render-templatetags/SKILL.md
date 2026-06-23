---
name: dw-render-templatetags
type: knowledge
group: render
description: Build templates using TemplateTags to access content properties directly in Dynamicweb 10. Triggers: TemplateTags syntax, direct property access in templates, TemplateTag patterns. Non-triggers: ViewModel-based rendering -> dw-render-viewmodels; template structure and Razor fundamentals -> dw-render-razor.
---

# TemplateTags: Legacy String-Based Binding

**TemplateTags are the legacy template binding system.** They use string-based lookups to retrieve data. While **new templates should use ViewModels** (see [dw-render-viewmodels](../dw-render-viewmodels/SKILL.md)), TemplateTags remain in production templates, especially in customer center, order, and RMA workflows.

## Core Concept

TemplateTags retrieve data via string-based method calls on context objects. The string path identifies the property:

```html
<!-- TemplateTags (legacy) -->
@GetString("Ecom:RMA.ID")                        <!-- Simple string property -->
@GetBoolean("Ecom:CustomerCenter.RMA.HasAddContent")  <!-- Boolean check -->
@GetDate("Ecom:RMA.Date")                        <!-- Date property -->
@GetInteger("Ecom:CustomerCenter.Paging.NumPages")    <!-- Numeric value -->
@GetLoop("RMATypes")                             <!-- Iterate over collection -->
```

Compare to **ViewModels (modern)**:

```html
<!-- ViewModels (modern) -->
@Model.RMA.ID                                    <!-- Direct property access -->
@Model.RMA.HasAddContent                         <!-- Type-safe, compiler checked -->
@Model.RMA.Date                                  <!-- DateTime object -->
@Model.Paging.NumPages                           <!-- Strongly typed -->
@foreach (var type in Model.RmaTypes)            <!-- Enumerable loop -->
```

## Accessor Methods

### GetString()

Retrieve a string property:

```html
<h1>@GetString("Ecom:RMA.ID")</h1>

<p>Request Type: @GetString("Ecom:RMA.Type.Name")</p>

<!-- Within a loop -->
@foreach (LoopItem order in GetLoop("Orders"))
{
    <span>@order.GetString("Ecom:Order.ID")</span>
    <span>@order.GetString("Ecom:Order.Status")</span>
}
```

**Property paths are case-sensitive.** A typo like `"Ecom:Order.id"` (lowercase) silently returns empty, not an error.

### GetBoolean()

Retrieve a boolean flag:

```html
@if (GetBoolean("Ecom:CustomerCenter.RMA.HasAddContent"))
{
    <div>Content available for editing</div>
}

@if (GetBoolean("Ecom:RMA.OrderID.IsSetFromRequest"))
{
    <!-- Order ID was provided in the request -->
}
```

### GetDate()

Retrieve a DateTime:

```html
<!-- Get the date -->
@{
    DateTime rmaDate = GetDate("Ecom:RMA.Date");
    string formatted = rmaDate.TimeOfDay.Ticks > 0 
        ? rmaDate.ToString() 
        : rmaDate.ToString(Pageview.Area.CultureInfo.DateTimeFormat.ShortDatePattern);
}

<td>@formatted</td>
```

**Important:** Check `.TimeOfDay.Ticks > 0` to distinguish between a date (midnight, `Ticks == 0`) and a datetime (with time component). This pattern is common in TemplateTags templates because date/datetime aren't always explicitly distinguished.

### GetInteger()

Retrieve a numeric value:

```html
@{
    int totalPages = GetInteger("Ecom:CustomerCenter.Paging.NumPages");
    int currentPage = GetInteger("Ecom:CustomerCenter.Paging.CurrentPage");
}

<p>Page @currentPage of @totalPages</p>
```

### GetLoop()

Iterate over a collection. Returns a `List<LoopItem>`:

```html
@foreach (LoopItem savedCard in GetLoop("SavedCards"))
{
    string cardName = savedCard.GetString("Ecom:SavedCard.Name");
    string cardNumber = savedCard.GetString("Ecom:SavedCard.Identifier");
    string cardType = savedCard.GetString("Ecom:SavedCard.CardType");
    
    <tr>
        <td>@cardName</td>
        <td>@cardNumber</td>
        <td>@cardType</td>
    </tr>
}
```

Each `LoopItem` has the same accessor methods: `.GetString()`, `.GetBoolean()`, `.GetDate()`, `.GetInteger()`.

## Real-World Patterns

### Nested Loops

Access nested collections:

```html
@foreach (LoopItem order in GetLoop("Orders"))
{
    <div>
        <h3>Order @order.GetString("Ecom:Order.ID")</h3>
        
        <!-- Nested loop for order lines -->
        @foreach (LoopItem line in order.GetLoop("OrderLines"))
        {
            <p>
                Product: @line.GetString("Ecom:OrderLine.ProductName")
                Price: @line.GetString("Ecom:OrderLine.Price")
            </p>
        }
    </div>
}
```

### Conditional Display

Common patterns in customer center templates:

```html
@if (GetBoolean("Ecom:CustomerCenter.RMA.HasRMAOrderLines"))
{
    <section class="p-3">
        @foreach (LoopItem orderline in GetLoop("RMAOrderLines"))
        {
            string productId = orderline.GetString("Ecom:RMA:OrderLine.ProductID");
            string productName = orderline.GetString("Ecom:RMA:OrderLine.ProductName");
            string price = orderline.GetString("Ecom:RMA:OrderLine.Price");
            
            <article>
                <h4>@productName</h4>
                <span>@price</span>
            </article>
        }
    </section>
}
else
{
    <p>No items available for this request</p>
}
```

### Building Dynamic Form Names

TemplateTags often construct form field names dynamically using `ParagraphID`:

```html
@{
    string paragraphId = GetString("ParagraphID");
    string orderIdFieldName = paragraphId + "RMAOrderID";
    string commentFieldName = paragraphId + "RMAComment";
}

<select name="@orderIdFieldName">
    @foreach (LoopItem order in GetLoop("Orders"))
    {
        <option value="@order.GetString("Ecom:Order.ID")">
            @order.GetString("Ecom:Order.Status")
        </option>
    }
</select>

<textarea name="@commentFieldName" rows="3"></textarea>
```

The `ParagraphID` ensures field names are unique across multiple instances of the same paragraph on a page.

### State Transitions

Render different UI based on state:

```html
@{
    bool hasAddContent = GetBoolean("Ecom:CustomerCenter.RMA.HasAddContent");
    bool hasCancelContent = GetBoolean("Ecom:CustomerCenter.RMA.HasCancelContent");
    
    string title = "View request";
    if (hasCancelContent) title = "Cancel request";
    if (hasAddContent) title = "Create new request";
}

<h1>@title</h1>

@if (hasAddContent)
{
    <!-- Show form to create new request -->
    <form action="@GetString("Ecom:CustomerCenter.RMA.AddURL")" method="post">
        <!-- ... -->
    </form>
}
else if (hasCancelContent)
{
    <!-- Show form to cancel request -->
    <form action="@GetString("Ecom:RMA.CancelURL")" method="post">
        <!-- ... -->
    </form>
}
else
{
    <!-- Show read-only view of existing request -->
    <table>
        <tr>
            <td>Request ID</td>
            <td>@GetString("Ecom:RMA.ID")</td>
        </tr>
    </table>
}
```

## Using TemplateTags in HTML Attributes

A common challenge: **double quotes in both Razor string syntax and HTML attributes**. When you embed a TemplateTags value in an HTML attribute, quote nesting becomes tricky.

### Problem: Quote Collision

```html
<!-- ❌ This breaks — nested quotes confuse the parser -->
<a href="@GetString("Ecom:Order.Link")">Order</a>
                   ^                  ^
              Both use double quotes
```

The parser sees the first `"` after `GetString(` as the end of the Razor expression, breaking the attribute.

### Solution: Use Single Quotes for Attributes

**Swap the quote types** — use single quotes for the HTML attribute and double quotes for the method call:

```html
<!-- ✓ This works — outer single, inner double -->
<a href='@GetString("Ecom:Order.Link")'>Order</a>

<!-- Or assign to variable first (also works) -->
@{
    string orderLink = GetString("Ecom:Order.Link");
}
<a href="@orderLink">Order</a>
```

### Real-World Example

From Swift's SavedCardList template:

```html
<!-- ✓ Single quotes on data attribute, double in GetString -->
<a href='@savedCardUrl' class='d-block text-decoration-none'>
    <span>@cardName</span>
</a>

<!-- ✓ Or build the variable first -->
@{
    string deleteUrl = savedCard.GetString("Ecom:CustomerCenter.SavedCards.DeleteUrl");
    string formAction = GetString("Ecom:RMA.AddURL");
}

<form action="@formAction" method="post">
    <!-- form content -->
</form>

<a href="@deleteUrl" class="btn btn-link">@Translate("Delete")</a>
```

### When to Use Each Pattern

| Pattern | When to Use |
|---------|------------|
| `<a href='@GetString(...)'...>` | Quick, single attribute with value |
| `@{ var x = GetString(...); }` then `<a href="@x">` | Multiple attributes or complex logic |
| Single quotes throughout | Consistent, avoids quote nesting entirely |

### Avoiding XSS: HTML Encoding

**Always HTML-encode** user-supplied values in attributes to prevent injection:

```html
<!-- ✓ Safe — Razor auto-encodes in attributes -->
<input value='@GetString("User.Name")'>

<!-- ❌ Unsafe in attribute context — could break out with quotes -->
<div title='@GetString("User.Description")'>

<!-- ✓ Safer — explicitly encode if in doubt -->
<div title='@System.Net.WebUtility.HtmlEncode(GetString("User.Description"))'>
```

Razor **auto-encodes** when you use `@expression` directly in an attribute, but it's safer to be explicit when the value contains user input or dynamic content.

## LoopItem Accessors

Within a loop, `LoopItem` provides the same accessor methods as the top-level context:

```html
@foreach (LoopItem item in GetLoop("Items"))
{
    <!-- All of these work on LoopItem: -->
    string text = item.GetString("Property.Name");
    bool flag = item.GetBoolean("Property.Flag");
    DateTime date = item.GetDate("Property.Date");
    int count = item.GetInteger("Property.Count");
    
    <!-- Even nested loops -->
    @foreach (LoopItem nested in item.GetLoop("NestedItems"))
    {
        <span>@nested.GetString("Name")</span>
    }
}
```

## Gotchas and Anti-Patterns

**Case sensitivity.** Property names in strings are case-sensitive:

```html
<!-- This works -->
@GetString("Ecom:Order.ID")

<!-- This silently returns empty -->
@GetString("Ecom:Order.id")    ❌ No error, no value
```

**No compile-time checking.** Typos go undetected:

```html
<!-- Both look valid, but only one works -->
@GetString("Ecom:RMA.ID")            ✓ Works
@GetString("Ecom:RMA.RequestID")     ❌ Silent fail, no error
```

**Performance:** TemplateTags loads all data upfront, no lazy-loading. Large loops with many properties accessed can be slow compared to ViewModels.

**Date/DateTime ambiguity.** Always check `.TimeOfDay.Ticks` if you need to distinguish:

```html
@{
    DateTime date = GetDate("Ecom:RMA.Date");
    if (date.TimeOfDay.Ticks > 0)
    {
        <!-- Has time component -->
        @date.ToString()
    }
    else
    {
        <!-- Date only, format without time -->
        @date.ToString(Pageview.Area.CultureInfo.DateTimeFormat.ShortDatePattern)
    }
}
```

**Loop variable scope.** Variables declared in a loop are local to that loop:

```html
@foreach (LoopItem item in GetLoop("Items"))
{
    string name = item.GetString("Name");  <!-- Scoped to loop -->
}

<!-- This won't work - name is out of scope -->
<p>@name</p>  ❌
```

## Example: Customer Card Management

Real-world TemplateTags template from Swift's SavedCardList:

```html
@using System.Collections.Generic
@inherits Dynamicweb.Rendering.RazorTemplateBase<...>

@{ 
    List<LoopItem> savedCardsLoop = GetLoop("SavedCards");
}

<div id="SavedCardList">
    <header class="px-2 py-3 border-bottom">
        <h1>@Pageview.CurrentParagraph.Item["Title"]</h1>
    </header>

    @if (!GetBoolean("Ecom:CustomerCenter.SavedCards.EmptyList"))
    {
        <table class="table table-striped">
            <thead>
                <tr>
                    <th>@Translate("Card Name")</th>
                    <th>@Translate("Card no")</th>
                    <th>@Translate("Card Type")</th>
                </tr>
            </thead>
            <tbody>
                @foreach (LoopItem savedCard in savedCardsLoop)
                {
                    string cardName = savedCard.GetString("Ecom:SavedCard.Name");
                    string cardNumber = savedCard.GetString("Ecom:SavedCard.Identifier");
                    string cardType = savedCard.GetString("Ecom:SavedCard.CardType");
                    string cardUrl = savedCard.GetString("Ecom:CustomerCenter.SavedCards.MessagesUrl");
                    string deleteUrl = savedCard.GetString("Ecom:CustomerCenter.SavedCards.DeleteUrl");

                    <tr>
                        <td><a href="@cardUrl">@cardName</a></td>
                        <td><a href="@cardUrl">@cardNumber</a></td>
                        <td><a href="@cardUrl">@cardType</a></td>
                        <td><a href="@deleteUrl">@Translate("Delete")</a></td>
                    </tr>
                }
            </tbody>
        </table>

        @if (GetBoolean("Ecom:CustomerCenter.RMA.Paging.Show"))
        {
            <div class="p-3 mt-3">
                <ul class="pagination">
                    @for (int page = 1; page <= GetInteger("Ecom:CustomerCenter.Paging.NumPages"); page++)
                    {
                        string isActive = (page == GetInteger("Ecom:CustomerCenter.Paging.CurrentPage")) ? "active" : "";
                        <li class="page-item @isActive">
                            <a class="page-link" href="javascript:goToPage(@page);">@page</a>
                        </li>
                    }
                </ul>
            </div>
        }
    }
    else
    {
        <div class="alert alert-info">@Translate("No saved cards found")</div>
    }
</div>
```

**Key TemplateTags patterns here:**
- `GetLoop("SavedCards")` to iterate collection
- `GetString()` on loop item for text properties
- `GetBoolean()` for conditional display
- `GetInteger()` for pagination
- String concatenation for dynamic URLs and field names

## When to Use TemplateTags (and When Not To)

| Scenario | Recommendation |
|----------|-----------------|
| New template | **Use ViewModels** — better IDE support, type safety, lazy-loading |
| Existing legacy templates | Keep TemplateTags until migration opportunity (refactoring, redesign) |
| Customer center / RMA workflows | TemplateTags common here; consider migration to ViewModels for new features |
| Performance-critical lists | **Use ViewModels** — lazy-loading avoids loading unnecessary data |
| Quick one-off fix | TemplateTags acceptable if modifying existing TemplateTags template |
| New feature in modern codebase | **Use ViewModels** — consistency, maintainability, IDE support |

## Comparison with ViewModels

| Aspect | TemplateTags | ViewModels |
|--------|--------------|-----------|
| **Syntax** | `GetString("Ecom:Order.ID")` | `@Model.Order.ID` |
| **Type safety** | None — strings can typo silently | Compiler checked |
| **IDE support** | No IntelliSense | Full IntelliSense |
| **Performance** | All data loaded upfront | Lazy-loaded on access |
| **Learning curve** | Memorize string paths | Direct C# properties |
| **Status** | Legacy, being phased out | Modern, recommended |

## Next Steps

- **For modern templates:** Use [dw-render-viewmodels](../dw-render-viewmodels/SKILL.md) and ItemViewModel, ProductViewModel patterns.
- **For Razor fundamentals:** See [dw-render-razor](../dw-render-razor/SKILL.md) for template structure, syntax, and nesting.
- **Migrating TemplateTags to ViewModels:** Define a new ViewModel class matching the properties you access via strings, then refactor the template to inherit from `ViewModelTemplate<YourViewModel>`.
