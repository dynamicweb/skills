# The four parts of a screen — data model, query, command, screen

Compile-verified skeletons for list, edit and overview screens, and the `IIdentifiable` round-trip that makes a row openable. Reached from [SKILL.md](../SKILL.md).

## Contents

- [A query for one record](#a-query-for-one-record)
- [The edit screen](#the-edit-screen)
- [The overview screen](#the-overview-screen)
- [The list screen is the hub](#the-list-screen-is-the-hub)

Every screen you build is the same four pieces. All skeletons below are compile-verified against
`Dynamicweb.Application.UI` 10.28.9.

**The model** — one property per column or field. `[ConfigurableProperty]` is what makes it addressable
by the UI.

```csharp
using System.Globalization;
using Dynamicweb.CoreUI.Data;
using Dynamicweb.CoreUI.Data.Validation;

public sealed class WidgetDataModel : DataViewModelBase, IIdentifiable
{
    [ConfigurableProperty]
    public int Id { get; set; }

    [ConfigurableProperty]
    [Required]
    public string Name { get; set; } = "";

    [ConfigurableProperty]
    public int Stock { get; set; }

    public string GetId() => Id.ToString(CultureInfo.InvariantCulture);
}
```

> **Implement `IIdentifiable` from the start**, even for a list-only screen. A plain `DataViewModelBase`
> is enough for a list, but the moment you add an edit or overview screen you need a by-id query, and
> `DataQueryIdentifiableModelBase<TModel, TKey>` constrains `TModel` to `IIdentifiable`. Adding it later
> means touching the model, its queries and its screens at once.
>
> **How identity travels.** `IIdentifiable` is one half of a round trip: the model serialises its identity
> to a *string* the UI can carry in a URL or a list row, and the query parses it back into a typed key.
>
> ```text
> model.GetId() → "42" → query.ModelIdentifier → TryParseIdentifier → SetKey(42)
> ```
>
> `GetId()` and `SetKey()` must therefore be inverses. If `GetId()` produces something
> `TryParseIdentifier` cannot parse into `TKey`, the framework simply does not call `SetKey` — no
> exception — so the query keeps its default key and loads the wrong record or none. For a composite
> identity (`"shopId:productId"`), override the `virtual TryParseIdentifier`; `OnGetData` is
> `internal sealed` and cannot be replaced.

**The query** — reads source data and maps it to the model. The second type parameter is the *source*
type, not the model.

```csharp
using System.Collections.Generic;
using System.Linq;
using Dynamicweb.CoreUI.Data;

public sealed class WidgetsQuery : DataQueryListBase<WidgetDataModel, string>
{
    protected override IEnumerable<string> GetListItems()
        => new[] { "Left-handed widget", "Right-handed widget" };

    protected override IEnumerable<WidgetDataModel> MapModels(IEnumerable<string> items)
        => items.Select(x => new WidgetDataModel { Name = x, Stock = x.Length });
}
```

**The command** — anything that writes. Validate with attributes; return a `CommandResult`.

```csharp
using Dynamicweb.CoreUI.Data;
using Dynamicweb.CoreUI.Data.Validation;

public sealed class WidgetDeleteCommand : CommandBase
{
    [Required]
    public int Id { get; set; }

    public override CommandResult Handle()
        => new() { Status = CommandResult.ResultType.Ok };
}
```

**The screen** — what renders in the workspace.

```csharp
using System.Collections.Generic;
using Dynamicweb.CoreUI.Data;
using Dynamicweb.CoreUI.Lists;
using Dynamicweb.CoreUI.Lists.ViewMappings;
using Dynamicweb.CoreUI.Screens;

public sealed class WidgetListScreen : ListScreenBase<WidgetDataModel>
{
    protected override string GetScreenName() => "Widgets";

    protected override IEnumerable<ListViewMapping> GetViewMappings() => new ListViewMapping[]
    {
        new RowViewMapping
        {
            Columns = new List<ModelMapping>
            {
                CreateMapping(m => m.Name),
                CreateMapping(m => m.Stock),
            }
        }
    };
}
```

## A query for one record

Edit and overview screens are fed by a single-model query, not a list query.

```csharp
using System.Linq;
using Dynamicweb.CoreUI.Data;

public sealed class WidgetByIdQuery : DataQueryIdentifiableModelBase<WidgetDataModel, int>
{
    public int Id { get; set; }

    public override WidgetDataModel? GetModel()
        => WidgetStore.Find(Id) is { } w
            ? new WidgetDataModel { Id = w.Id, Name = w.Name, Stock = w.Stock }
            : null;

    protected override void SetKey(int key) => Id = key;
}
```

## The edit screen

`EditScreenBase<TModel>` needs three things: a name, a save command, and a layout. Note the save command
is `CommandBase<TModel>` — the **generic** base, not the plain `CommandBase` a list action uses.

```csharp
using System.Collections.Generic;
using Dynamicweb.CoreUI.Data;
using Dynamicweb.CoreUI.Screens;

public sealed class WidgetEditScreen : EditScreenBase<WidgetDataModel>
{
    protected override string GetScreenName() => "Edit widget";

    protected override CommandBase<WidgetDataModel>? GetSaveCommand() => new WidgetSaveCommand();

    protected override void BuildEditScreen()
    {
        AddComponents("General", new LayoutWrapper[]
        {
            new LayoutWrapper("Details",
            [
                EditorFor(m => m.Name),
                EditorFor(m => m.Stock),
            ])
        });
    }

    // Optional: per-field behaviour, e.g. make a field read-only
    protected override IEnumerable<EditorMapping> GetEditorMappings() => new List<EditorMapping>
    {
        CreateMapping(m => m.Id) with { ReadOnlyPredicate = m => true }
    };
}
```

The matching save command reads the posted model with `GetModel()`:

```csharp
public sealed class WidgetSaveCommand : CommandBase<WidgetDataModel>
{
    public override CommandResult Handle()
    {
        var model = GetModel();
        if (model is null)
            return new CommandResult { Status = CommandResult.ResultType.Invalid, Message = "No model" };

        WidgetStore.Save(model.Id, model.Name, model.Stock);
        return new CommandResult { Status = CommandResult.ResultType.Ok, Message = "Widget saved" };
    }
}
```

`CommandResult.Message` is shown to the user as a toast, so write it for them. Only fields you added an
`EditorFor` for are rendered; `[Required]` on the model surfaces as the field's required marker.

## The overview screen

`OverviewScreenBase<TModel>` assembles widgets around one record. `Model` is the record the bound query
returned.

```csharp
using Dynamicweb.CoreUI.Displays.Widgets;
using Dynamicweb.CoreUI.Layout;
using Dynamicweb.CoreUI.Screens;

public sealed class WidgetOverviewScreen : OverviewScreenBase<WidgetDataModel>
{
    protected override string GetScreenName() => "Widget overview";

    protected override void BuildOverviewScreen()
    {
        AddWidget(new Widget
        {
            Label = Model?.Name ?? "Widget",
            Component = new ListDisplay<WidgetListScreen, WidgetDataModel>(new WidgetsQuery())
            {
                EnableEditing = false,
                ListNavigateAction = null
            }
        }, Group.GroupWidth.Col_12);
    }
}
```

A widget's `Component` can be a list, a graph, an info card, and its `ContextMenu` can carry actions —
`new ContextMenu().WithActionNode(ActionBuilder.Edit<WidgetEditScreen>(new WidgetByIdQuery { Id = id }))`
is how Dynamicweb's own overview screens link to their edit screen.

## The list screen is the hub

This is the shape Dynamicweb's own screens use, and getting it wrong produces an odd UI. **One tree node
points at the list screen; the edit and overview screens hang off the list**, not off nodes of their own.
Three overrides on `ListScreenBase<T>` do it:

```csharp
// Row click -> the overview for that record
protected override ActionBase? GetListItemPrimaryAction(WidgetDataModel model)
{
    ArgumentNullException.ThrowIfNull(model, nameof(model));
    return NavigateScreenAction.To<WidgetOverviewScreen>().With(new WidgetByIdQuery { Id = model.Id });
}

// Per-row "..." menu -> edit and delete
protected override IEnumerable<ActionGroup>? GetListItemContextActions(WidgetDataModel model)
{
    var query = new WidgetByIdQuery { Id = model.Id };
    return new ActionGroup[]
    {
        new()
        {
            Nodes =
            [
                ActionBuilder.Edit<WidgetEditScreen>(query),
                ActionBuilder.Delete(
                    new WidgetDeleteCommand { Id = model.Id },
                    "Delete widget?",
                    $"Do you want to delete '{model.Name}'?")
            ]
        }
    };
}

// The "+" affordance -> usually a slide-over create screen
protected override ActionNode GetItemCreateAction() => new()
{
    Icon = Icon.Plus,
    Name = "New widget",
    NodeAction = OpenSlideOverAction.To<WidgetCreateScreen>()
};
```

`ActionBuilder` lives in `Dynamicweb.Application.UI.Helpers` — not in the `CoreUI.Actions` namespaces
where the rest of this belongs. `ActionBuilder.Delete` wraps itself in a confirm dialog for you.

Verified on a live solution: one node → list; row click → that record's overview; the row's `...` menu
showing **Edit** and **Delete**; and Save on the edit screen writing through the save command and showing
its `CommandResult.Message` as a toast.

**Three naming rules, all enforced at runtime rather than by the compiler:**

| Base type | Class name must end in |
|---|---|
| `AreaBase` | `Area` |
| `ActionBase` | `Action` |
| `DataViewModelBase` | `Model` |
