---
name: dw-extend-csharp-api
description: Use the C# API and Dynamicweb.Services for custom backend code in Dynamicweb 10. Triggers: C# API, Services.*, Pageview.*, custom business logic, how to call Dynamicweb APIs, Context.Current, UserContext. Non-triggers: ViewModel patterns -> dw-render-viewmodels; notification handling -> dw-extend-providers; scheduled tasks -> dw-extend-scheduled-tasks.
---

# Dynamicweb 10 C# API

## Service Access Patterns

Dynamicweb exposes its domain services via three equivalent patterns. Use whichever is most natural for the context:

### Static service facades (most common)

```csharp
// Content
Dynamicweb.Content.Services.Pages.GetPage(pageId);
Dynamicweb.Content.Services.Areas.GetArea(areaId);
Dynamicweb.Content.Services.Items.GetItem(itemType, itemId);
Dynamicweb.Content.Services.Paragraphs.GetParagraphById(paragraphId);

// Ecommerce
Dynamicweb.Ecommerce.Services.Products.GetProductById(id, variantId, languageId);
Dynamicweb.Ecommerce.Services.ProductGroups.GetGroup(groupId);
Dynamicweb.Ecommerce.Services.Orders.GetById(orderId);
Dynamicweb.Ecommerce.Services.Assortments.GetAssortment(assortmentId);
Dynamicweb.Ecommerce.Services.Languages.GetLanguage(languageId);
Dynamicweb.Ecommerce.Services.Shops.GetShop(shopId);
Dynamicweb.Ecommerce.Services.Variants.GetVariantGroup(variantGroupId);

// Users
Dynamicweb.Security.UserManagement.UserManagementServices.Users.GetUserById(userId);
Dynamicweb.Security.UserManagement.UserManagementServices.UserGroups.GetGroupById(groupId);
```

### DI container (preferred in new code)

```csharp
using Dynamicweb.Extensibility.Dependencies;

var productService = DependencyResolver.Current.GetRequiredService<ProductService>();
var pageService = DependencyResolver.Current.GetRequiredService<PageService>();
```

### Legacy service locator (still present in older code)

```csharp
using Dynamicweb.Extensibility;

var service = ServiceLocator.Current.GetInstance<ISomeService>();
```

## Context API

### `Dynamicweb.Context.Current`

The HTTP request context. In Razor templates and notification subscribers:

```csharp
var queryId = Dynamicweb.Context.Current?.Request.QueryString["ID"];
var formValue = Dynamicweb.Context.Current?.Request.Form["MyField"];
Dynamicweb.Context.Current?.Response.Redirect("/some-path");
```

### `PageView.Current()`

The page rendering context. Use inside content modules, notifications, and Razor:

```csharp
var pageView = Dynamicweb.Frontend.PageView.Current();
int pageId = pageView?.ID ?? 0;
int areaId = pageView?.AreaID ?? 0;
var page = pageView?.Page;        // Dynamicweb.Content.Page
var area = pageView?.Area;        // Dynamicweb.Content.Area
var user = pageView?.User;        // current frontend user
bool isVisualEditor = pageView?.IsVisualEditorMode ?? false;
```

Look up a page by navigation tag:

```csharp
var shopPage = Dynamicweb.Content.Services.Pages
    .GetPageByNavigationTag(areaId, "shop");
```

### `UserContext.Current`

```csharp
using Dynamicweb.Security.UserManagement;

var user = UserContext.Current.User;          // null if anonymous
bool loggedIn = UserContext.Current.IsLoggedOn;
int userId = UserContext.Current.UserId;

// Impersonation (B2B CSR)
var impersonating = UserContext.Current.ImpersonatingUser;
```

### Ecommerce context

```csharp
var cart = Dynamicweb.Ecommerce.Common.Context.Cart;         // current cart Order
string languageId = Dynamicweb.Ecommerce.Common.Context.LanguageID;
```

## Key Service Methods

### `PageService`

```csharp
var service = Dynamicweb.Content.Services.Pages;

Page? page = service.GetPage(pageId);
Page? byTag = service.GetPageByNavigationTag(areaId, "shop");
IEnumerable<Page> children = service.GetPagesByParentID(parentId);
PageCollection allInArea = service.GetPagesByAreaID(areaId);
IEnumerable<Page> ancestors = service.GetAncestors(pageId, includingSelf: true);
Page saved = service.SavePage(page);
service.DeletePage(pageId);
```

### `ProductService`

```csharp
var service = Dynamicweb.Ecommerce.Services.Products;

Product? p = service.GetProductById("PROD1", variantId: null, "LANG1");
IEnumerable<Product> byGroup = service.GetProductsByGroupId("GROUP1", onlyActive: true, "LANG1", useAssortments: false);
Product? byNumber = service.GetProductByNumber("SKU-123", "LANG1");

// Save
service.Save(product);

// Set a custom field value
service.SetProductFieldValue(product, "CustomFieldSystemName", newValue);
object? val = service.GetProductFieldValue(product, "CustomFieldSystemName");
```

### `UserService`

```csharp
var service = Dynamicweb.Security.UserManagement.UserManagementServices.Users;

User? user = service.GetUserById(userId);
User? byEmail = service.GetUserByEmailAddress("user@example.com");
IEnumerable<User> inGroup = service.GetUsersByGroupId(groupId);

service.Save(user);
service.ChangePassword(user, "NewPassword");
service.AddGroupRelations(user, new[] { someGroup });
service.RemoveGroupRelations(user, new[] { someGroup });
```

### `OrderService`

```csharp
var service = Dynamicweb.Ecommerce.Services.Orders;

Order? order = service.GetById(orderId);
// See dw-commerce-orders for full order management
```

## Common Ecommerce Services Reference

| Property | Service class | Common methods |
|---------|--------------|----------------|
| `Services.Products` | `ProductService` | GetProductById, Save, Delete, GetProductsByGroupId |
| `Services.ProductGroups` | `GroupService` | GetGroup, GetToplevelGroups, GetGroups, Save, Delete |
| `Services.Orders` | `OrderService` | GetById, Save, Delete |
| `Services.Assortments` | `AssortmentService` | GetAssortment, Save, Delete |
| `Services.Languages` | `LanguageService` | GetLanguage, GetLanguages |
| `Services.Shops` | `ShopService` | GetShop, GetShops |
| `Services.Variants` | `VariantService` | GetVariantGroup, GetVariantOption |
| `Services.Currencies` | `CurrencyService` | GetCurrency, GetCurrencies |
| `Services.Countries` | `CountryService` | GetCountry, GetCountries |
| `Services.Payments` | `PaymentService` | GetPayment, GetPayments |
| `Services.Shippings` | `ShippingService` | GetShipping, GetShippings |
| `Services.Discounts` | `DiscountService` | GetDiscount, GetDiscounts |
| `Services.Assortments` | `AssortmentService` | GetAssortment, Save |
| `Services.Feeds` | `FeedService` | GetFeed, GetFeeds |
| `Services.CompletionRules` | `CompletionRuleService` | GetCompletionRule, GetCompletionRules |

## Razor Code-Behind Pattern

In Razor templates, write custom logic inside `@{ }` blocks. Access services the same way:

```razor
@using Dynamicweb.Content
@using Dynamicweb.Ecommerce

@{
    int pageId = Dynamicweb.Context.Current != null
        ? Dynamicweb.Converter.ToInt32(Dynamicweb.Context.Current.Request.QueryString["ID"])
        : 0;

    var page = Services.Pages.GetPage(pageId);
    var products = Services.Products.GetProductsByGroupId("MYGROUP", onlyActive: true, "LANG1", false);
}

<h1>@page?.Title</h1>
@foreach (var product in products)
{
    <p>@product.Name — @product.DefaultPrice</p>
}
```

## Pitfalls

**`Context.Current` is null in background/scheduled tasks** — use `PageView.GetPageviewByPageID()` or create a `BackgroundContext` with `Context.CreateContext(settings)` instead.

**`PageView.Current()` returns null outside of a page render** — always null-check or use `?.` syntax.

**Services are not thread-safe for writes** — do not share a service instance across threads for Save/Delete operations. Each call to `Services.Products` creates a new instance, which is safe.

**Don't use raw SQL for Ecommerce data** — always use the service layer. Raw SQL bypasses caching and notification firing. See [dw-data-access](../dw-data-access) for when raw SQL is appropriate.

**Product language** — always pass an explicit `languageId` to `GetProductById`. Passing an empty string or null returns the product in the default language, which may not match the current visitor's language.

## Next Steps

- **Need to react to data changes?** Use notifications — see [dw-extend-providers](../dw-extend-providers)
- **Need database access / caching?** See [dw-data-access](../dw-data-access)
- **Rendering with ViewModels?** See [dw-render-viewmodels](../dw-render-viewmodels)
