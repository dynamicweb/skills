---
name: dw-extend-providers
type: knowledge
group: extend
description: Build providers, notification subscribers, and AddIns for Dynamicweb 10. Triggers: notification subscribers, providers, AddIns, reacting to save/delete events, custom price logic, custom shipping, custom payment, custom authentication. Non-triggers: C# API usage -> dw-extend-csharp-api; scheduled background work -> dw-extend-scheduled-tasks.
---

# Providers and Notification Subscribers

## Notification Subscribers

Notification subscribers are the primary way to react to Dynamicweb events (page save, order created, product deleted, etc.) without modifying core code.

### How to implement

1. Inherit from `NotificationSubscriber` (in `Dynamicweb.Extensibility.Notifications`)
2. Decorate the class with one or more `[Subscribe("DWN_...")]` attributes
3. Override `OnNotify` — cast `args` to the expected args type for the notification

```csharp
using Dynamicweb.Extensibility.Notifications;
using Dynamicweb.Notifications;

[Subscribe(Standard.Page.Saved)]
public class MyPageSavedSubscriber : NotificationSubscriber
{
    public override void OnNotify(string notification, NotificationArgs args)
    {
        var savedArgs = (Standard.Page.SavedArgs)args;
        var page = savedArgs.Page;
        // React to page save
    }

    // Optional: return false to skip this subscriber
    public override bool IsActive => true;

    // Optional: control execution order (higher = later)
    public override int Rank => 0;
}
```

**No registration required.** `NotificationManager.Notify()` discovers all `NotificationSubscriber` subclasses via reflection on startup, filtered by `[Subscribe]` attributes.

### Multiple subscriptions

```csharp
[Subscribe(Ecommerce.Order.BeforeSave)]
[Subscribe(Ecommerce.Order.AfterSave)]
public class OrderAuditSubscriber : NotificationSubscriber
{
    public override void OnNotify(string notification, NotificationArgs args)
    {
        if (notification == Ecommerce.Order.BeforeSave)
        {
            var beforeArgs = (Ecommerce.Order.BeforeSaveArgs)args;
            // Validate before save
        }
        else if (notification == Ecommerce.Order.AfterSave)
        {
            var afterArgs = (Ecommerce.Order.AfterSaveArgs)args;
            // Log after save
        }
    }
}
```

### Cancellable notifications

Some notifications use `CancelableNotificationArgs`. Set `Cancel = true` to abort the operation:

```csharp
[Subscribe(Ecommerce.Order.BeforeDelete)]
public class PreventOrderDeleteSubscriber : NotificationSubscriber
{
    public override void OnNotify(string notification, NotificationArgs args)
    {
        var cancelable = (CancelableNotificationArgs)args;
        cancelable.Cancel = true; // Prevents the delete
    }
}
```

## Key Notification Constants

### Content (`Dynamicweb.Notifications.Standard.Page.*`)

| Constant | When it fires | Args type |
|----------|--------------|----------|
| `Standard.Page.Loaded` | After a page is loaded for rendering | `LoadedArgs(PageView pageview)` |
| `Standard.Page.OnBeforeRenderParagraphs` | Before paragraphs render | `OnBeforeRenderParagraphsArgs(PageView, paragraphs)` |
| `Standard.Page.Saved` | After a page is saved in admin | `PageNotificationArgs(Page, Page?)` |
| `Standard.Page.OnBeforeSave` | Before page save | `PageNotificationArgs(Page)` |
| `Standard.Page.Deleted` | After page deleted | — |
| `Standard.Page.AfterRender` | After page renders to output | `AfterRenderArgs(PageView, Template)` |
| `Standard.Paragraph.Saved` | After paragraph saved | — |
| `Standard.Paragraph.Deleted` | After paragraph deleted | — |

### Ecommerce (`Dynamicweb.Ecommerce.Notifications.Ecommerce.*`)

| Constant | When it fires |
|----------|--------------|
| `Ecommerce.Order.BeforeSave` | Before order save (can validate) |
| `Ecommerce.Order.AfterSave` | After order save |
| `Ecommerce.Order.BeforeDelete` | Before order delete (cancellable) |
| `Ecommerce.Order.AfterDelete` | After order delete |
| `Ecommerce.Order.State.Changed` | Order state transitions |
| `Ecommerce.Cart.Line.Added` | Cart line added |
| `Ecommerce.Cart.Line.Removed` | Cart line removed |
| `Ecommerce.Product.BeforeSave` | Before product save |
| `Ecommerce.Product.AfterSave` | After product save |
| `Ecommerce.Product.BeforeDelete` | Before product delete |
| `Ecommerce.Product.AfterDelete` | After product delete |
| `Ecommerce.Product.ProductWorkflowStateChanged` | Product workflow state changed |
| `Ecommerce.Group.BeforeSave` / `AfterSave` / `Deleted` | Product group operations |

## Providers

Providers replace or extend how a core Dynamicweb subsystem works. Inherit from the appropriate base class, decorate with `[AddInName]`/`[AddInLabel]`, and implement required abstract members.

All providers inherit from `ConfigurableAddIn` (directly or indirectly), giving them the `[AddInParameter]` / `[AddInParameterEditor]` system for admin UI configuration.

### Provider table

| Provider base | Namespace | Use for |
|--------------|-----------|--------|
| `PriceProvider` | `Dynamicweb.Ecommerce.Prices` | Custom pricing logic (override or supplement standard price rules) |
| `CheckoutHandler` | `Dynamicweb.Ecommerce.Cart` | Payment gateway integration |
| `ShippingProvider` | `Dynamicweb.Ecommerce.Cart` | Shipping method / carrier integration |
| `CartCalculationProvider` | `Dynamicweb.Ecommerce.Cart` | Custom cart calculation (taxes, discounts, loyalty) |
| `StockLevelProvider` | `Dynamicweb.Ecommerce.Stocks` | Override stock calculation from external systems |
| `TaxProvider` | `Dynamicweb.Ecommerce.Products.Taxes` | External tax service (AvaTax, Vertex) |
| `FeeProvider` | `Dynamicweb.Ecommerce.Orders` | Manipulate shipping fees on orders |
| `BaseProvider` | `Dynamicweb.DataIntegration` | Custom Integration Framework source/destination |
| `NavigationProvider` | `Dynamicweb.Frontend.NavigationProviders` | Add custom nodes to navigation |
| `UpdateProvider` | `Dynamicweb.Updates` | Database migrations (tables, columns, indexes) |
| `HealthProviderBase` | `Dynamicweb.Diagnostics.Health` | Custom health checks |
| `IndexProviderBase` | `Dynamicweb.Indexing` | Replace Lucene with a different index backend |

### Example: Custom PriceProvider

```csharp
using Dynamicweb.Ecommerce.Prices;
using Dynamicweb.Extensibility.AddIns;

[AddInName("MyCompany.CustomPriceProvider")]
[AddInLabel("Custom Price Provider")]
[AddInDescription("Applies special pricing from an external system.")]
public class CustomPriceProvider : PriceProvider
{
    [AddInParameter("API Endpoint")]
    [AddInParameterEditor(typeof(TextParameterEditor), "")]
    public string ApiEndpoint { get; set; } = "";

    public override PriceInfo FindPrice(PriceContext context, PriceProductSelection selection)
    {
        // Return null to fall through to standard pricing
        // Return a PriceInfo to override
        var externalPrice = CallExternalApi(ApiEndpoint, selection.Product?.Number);
        if (externalPrice == null) return null;

        return new PriceInfo(externalPrice.Value, context.Currency);
    }
}
```

### Example: UpdateProvider (database migrations)

```csharp
using Dynamicweb.Updates;

public sealed class MyCustomUpdateProvider : UpdateProvider
{
    public override IEnumerable<Update> GetUpdates() => new List<Update>
    {
        SqlUpdate.AddTable("a1b2c3d4-...", this, "MyCustomTable", @"
            (
                [Id] [int] IDENTITY(1,1) NOT NULL,
                [Name] nvarchar(200) NULL,
                [CreatedAt] [datetime] NULL,
                CONSTRAINT [PK_MyCustomTable] PRIMARY KEY CLUSTERED ([Id] ASC)
            )"),
        SqlUpdate.AddColumn("b2c3d4e5-...", this, "EcomProducts", "ProductCustomScore", "[decimal](18, 4) NULL"),
    };
}
```

Update IDs must be globally unique GUIDs. Applied migrations are tracked in `dbo.Updates`.

### AddIn Attributes Reference

| Attribute | Purpose |
|-----------|---------|
| `[AddInName("SystemName")]` | Internal system name / key in DB |
| `[AddInLabel("Display Name")]` | Human-readable name shown in admin |
| `[AddInDescription("...")]` | Tooltip/description in admin |
| `[AddInActive(true/false)]` | Whether the AddIn is selectable |
| `[AddInIgnore(true)]` | Hide from UI dropdown (still runnable) |
| `[AddInDeprecated(true)]` | Mark as deprecated |
| `[AddInOrder(n)]` | Sort order in admin dropdowns |

### Parameter Attributes Reference

| Attribute | Purpose |
|-----------|---------|
| `[AddInParameter("Label")]` | UI label for this parameter |
| `[AddInParameterEditor(typeof(EditorType), "options")]` | Editor type + options |
| `[AddInParameterGroup("GroupName")]` | Group parameters visually |
| `[AddInParameterOrder(n)]` | Sort order within group |

**Common editor types:**
- `TextParameterEditor` — text input. Options: `"TextArea=True;style=height:60px;"` for textarea
- `YesNoParameterEditor` — checkbox
- `IntegerParameterEditor` — number input
- `DropDownParameterEditor` — select list

## Discovery and Registration

All providers and subscribers are **discovered automatically via reflection** — no explicit registration in `Program.cs` or `Startup.cs` is needed. Discovery happens through:
- `AddInManager.GetTypes<BaseType>()` — finds all public non-abstract subclasses
- Assembly scanning at startup via the Dynamicweb core

The assembly containing your provider must be loaded at startup. The standard way to ensure this is to reference it from the host project.

## Pitfalls

**Cast exceptions in `OnNotify`** — always check `notification` before casting `args`, especially when subscribing to multiple events.

**`[AddInName]` must be unique** — duplicate system names cause the manager to load only one of the classes.

**Thread safety in providers** — `PriceProvider`, `ShippingProvider`, etc. may be called concurrently. Avoid shared mutable state; use constructor injection or `DependencyResolver` per-call.

**`UpdateProvider` IDs are permanent** — once an update ID has been applied to any DB, changing its ID causes it to run again, potentially corrupting data.

## Next Steps

- **Need to query/write data from within a provider?** See [dw-data-access](../dw-data-access)
- **Need to use Dynamicweb service APIs?** See [dw-extend-csharp-api](../dw-extend-csharp-api)
- **Building a custom Integration Framework provider?** See [dw-integration-framework](../dw-integration-framework)
