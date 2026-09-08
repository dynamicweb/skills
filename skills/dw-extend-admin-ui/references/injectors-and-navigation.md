# Extending what you do not own — injectors, tree nodes and Actions menus

Adding to someone else's screen, area tree or Actions menu without forking it, and the silent-failure modes each one has. Reached from [SKILL.md](../SKILL.md).

## Contents

- [Extending navigation and menus you do not own](#extending-navigation-and-menus-you-do-not-own)
- [Step 5 — Extending a screen you do not own](#step-5-extending-a-screen-you-do-not-own)

## Extending navigation and menus you do not own

**A section on someone else's area.** Point `NavigationSection<TArea>` at their area type, then provide a
node provider for your section. Override `ShouldShow()` to hide it conditionally — on a license feature,
or on whether any relevant data exists.

**A node under someone else's node.** You do not have to own a node to add children to it: the framework
collects nodes from *all* providers targeting a section. Target their **section**, return nothing from
`GetRootNodes()`, and answer only when the parent path matches the node you want to extend.

```csharp
public sealed class ContentSettingsExtensionNodeProvider : NavigationNodeProvider<AreasSection>
{
    private const string ContentSettingsRootId = "Content_Settings";

    public override IEnumerable<NavigationNode> GetRootNodes() => [];

    public override IEnumerable<NavigationNode> GetSubNodes(NavigationNodePath parentNodePath)
    {
        if (parentNodePath is null)
            yield break;

        if (string.Equals(parentNodePath.Last, ContentSettingsRootId, StringComparison.OrdinalIgnoreCase))
        {
            yield return new NavigationNode
            {
                Name = "Acme widgets",
                Id = "Acme_InjectedSettingsNode",
                Icon = Icon.Sync,
                Sort = 200,          // high Sort -> after the built-in children
                NodeAction = NavigateScreenAction.To<WidgetListScreen>().With(new WidgetsQuery())
            };
        }
    }
}
```

Verified: this places the node under Dynamicweb's own **Settings → Areas → Content** node, after its
built-in children. `AreasSection` is `NavigationSection<SettingsArea>` in `Dynamicweb.Application.UI`.

> Built-in node IDs follow a `{Prefix}_{Name}` convention (`Content_Settings`, `Content_Styles`), but they
> are an implementation detail of the assembly that owns them and can change between versions. Targeting
> your own nodes is safe; targeting built-in ones is best-effort.

**An entry in someone else's Actions menu.** Use the specialised injector bases rather than the plain
`ScreenInjector<T>`:

| Override | Where it appears |
|---|---|
| `ListScreenInjector<TScreen, TRowModel>.GetScreenActions()` | the screen's toolbar / Actions menu |
| `ListScreenInjector<TScreen, TRowModel>.GetListItemActions(model)` | a row's context menu |
| `ListScreenInjector<TScreen, TRowModel>.GetCell(propertyName, model)` | a single cell's rendering |
| `EditScreenInjector<TScreen, TModel>.GetScreenActions()` | an edit screen's Actions menu |
| `EditScreenInjector<TScreen, TModel>.GetEditor(propertyName, model)` | one field's editor |

```csharp
public sealed class ApiKeyListActionInjector : ListScreenInjector<ApiKeyListScreen, ApiKeyDataModel>
{
    public override IEnumerable<ActionGroup>? GetScreenActions() => new ActionGroup[]
    {
        new()
        {
            Name = "AcmeActions",       // see the warning below
            Title = "Acme",
            Nodes =
            [
                new ActionNode
                {
                    Name = "Go to Acme widgets",
                    Icon = Icon.Truck,
                    Sort = 500,
                    NodeAction = NavigateScreenAction.To<WidgetListScreen>().With(new WidgetsQuery())
                }
            ]
        }
    };
}
```

Verified end-to-end: the entry renders in the Actions menu of Dynamicweb's own API Keys list alongside
their "Manage columns", and clicking it navigates to the target screen.

> **Set `ActionGroup.Name` — this one bites.** Verified by A/B on a live solution: with only a `Title`,
> the injected group rendered **dimmed and clicking it did nothing**. Adding `Name = "AcmeActions"` and
> redeploying made the very same entry navigate correctly. `Name` is the group's logical name and
> "affects selection-dependency on lists", so a nameless group is treated as requiring a row selection
> and stays inert until one exists. There is no error and no log entry — the item simply looks slightly
> greyed and ignores clicks.

**Action types** for any `NodeAction`:

```csharp
NavigateScreenAction.To<TScreen>().With(query)
RunCommandAction.For(new MyCommand()).WithReloadOnSuccess(ReloadType.Workspace)
ConfirmAction.For(innerAction, "Title?", "Body text")
OpenSlideOverAction.To<TScreen>().With(query).WithOnSelectAction(...)
```

For a bulk action driven by a multi-select, the command must accept the selected ids — use
`RunCommandAction.ForCommandAndProperty<TCommand>(c => c.Ids)` so the framework knows it operates on a
selection. And keep `GetListItemContextActions(model)` cheap: it runs once per row, so use what is
already on `model` rather than querying.

## Step 5 — Extending a screen you do not own

`ScreenInjector<TScreen>` hooks into a screen as it is built. Two virtual methods:

- `OnBefore(TScreen screen)` — before the content is built
- `OnAfter(TScreen screen, UiComponentBase content)` — after, to post-process the component tree

```csharp
using Dynamicweb.CoreUI;
using Dynamicweb.CoreUI.Layout;
using Dynamicweb.CoreUI.Screens;

public sealed class OrderEditScreenInjector : ScreenInjector<OrderEditScreen>
{
    public override void OnAfter(OrderEditScreen screen, UiComponentBase content)
    {
        if (content is not ScreenLayout layout)
            return;

        if (layout.Root is TabContainer tabs)
            tabs.GetOrAddTab("Acme").Section.AddGroup(/* widget or list display */);

        if (content.TryGet<Section>(out var section))
        {
            // add widgets to the existing section
        }
    }
}
```

The pattern in Dynamicweb's own injectors is defensive throughout: bail out unless the component tree is
the shape you expect, and check `screen.Model` for null. Copy that habit — an injector that throws breaks
someone else's screen.

`EditScreenInjector<TScreen, TModel>` and `ListScreenInjector<TScreen, TRowModel>` are specialised bases
for field- and cell-level work.
