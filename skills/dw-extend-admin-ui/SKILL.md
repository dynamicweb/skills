---
name: dw-extend-admin-ui
type: flow
group: extend
mcp: none
dynamo: false
description: 'Extend the Dynamicweb 10 administration interface from your own assembly — list, edit and overview screens, an area in the sidebar, nodes in an area tree, entries in an existing Actions menu, and injectors into screens you do not own. Triggers: add a screen to the admin, ListScreen, EditScreen, OverviewScreen, ScreenInjector, an area or tree node in the sidebar, add a button or Actions-menu entry to an existing screen, change a screen someone else owns, my screen compiles and installs but never renders, an injected action renders dimmed and inert. Non-triggers: providers, notification subscribers and scheduled tasks -> dw-extend-providers; the C# API and Services layer for non-UI code -> dw-extend-csharp-api; getting the built assembly onto a solution -> dw-setup-cli; frontend templates and Razor -> dw-render-razor.'
---

You are extending the Dynamicweb 10 admin interface (the "backend") from your own assembly in a customer
solution. This skill owns the route from requirement to a change **verified working on the solution**.
Committing and raising a PR belong to the surrounding work-item workflow, not here.

Dynamicweb's own documentation explains the concepts well and is kept current — this skill does not repeat
it. Read [Custom UI](https://doc.dynamicweb.dev/documentation/extending/administration-ui/index.html) and
[Screen architecture](https://doc.dynamicweb.dev/documentation/extending/administration-ui/screenconcept.html)
for the model. What follows is the operational layer: which building block to reach for, skeletons that
compile, and how to prove the change actually took effect.

## Step 1 — Route the task before writing anything

**One question decides the whole approach: do you own the screen?**

| What you need | Building block | Why |
|---|---|---|
| A screen for **your own** data | Subclass a screen type + your own area/nodes | You control the screen, so build it |
| Add fields, columns or widgets to a **Dynamicweb or third-party** screen | **Screen injector** | You cannot subclass a core screen and have Dynamicweb use yours instead |
| Only an extra action on an existing screen | Action-menu item | Lighter than an injector |
| A layout the built-in screen types cannot express | Custom `ScreenType` with your own Razor views | Last resort — most work, most to maintain |

Getting this wrong is expensive: subclassing a core screen compiles, deploys, and then simply never
renders, because nothing routes to your subclass. If the screen belongs to someone else, it is an
injector.

**Which screen type**, once you know it is yours:

| Screen type | Use for |
|---|---|
| `ListScreenBase<TModel>` | browsing a collection in a table |
| `EditScreenBase<...>` | editing one record through a tabbed form |
| `OverviewScreenBase<TModel>` | a summary of one record, assembled from widgets |

`GridEditScreen` and `PromptScreen` also exist — see the
[screen types](https://doc.dynamicweb.dev/documentation/extending/administration-ui/screentypes/listscreen.html)
docs.

## Step 2 — Project setup

One package reference is enough. `Dynamicweb.Application.UI` transitively brings `Dynamicweb.CoreUI`,
`Dynamicweb.Core`, `Dynamicweb.Ecommerce` and the rest — ten packages in total.

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Dynamicweb.Application.UI" Version="10.*" />
  </ItemGroup>
</Project>
```

> **Never build against a newer version than the solution runs.** `Version="10.*"` resolves to the latest
> *stable* and excludes prereleases, which is why it is the right default — do not "helpfully" change it
> to `10.*-*`. An assembly built against newer Dynamicweb assemblies than the host has **fails to load
> silently**: `dw install` still reports success, and nothing appears in the admin. See the dw-setup-cli skill.

## Step 3 — The four parts of a screen

A screen is a data model, a query, a command and the screen class itself. Every screen type follows
that shape, and the part that trips people up is the `IIdentifiable` round-trip: the string a row
hands out has to survive being parsed back into a key, or the row opens onto nothing.

The contract and compile-verified skeletons for all three screen types are in
[references/screen-anatomy.md](references/screen-anatomy.md).

## Step 4 — Making it reachable

A screen nobody can navigate to is invisible. Give it an area, a section and a node.

> **Namespace trap:** `AreaBase` lives in `Dynamicweb.CoreUI.Application`, while everything else here is
> in `Dynamicweb.CoreUI.Navigation`. Miss that one using and the compiler reports a confusing generic
> constraint failure on your section (`CS0311`) rather than a missing type.

```csharp
using System.Collections.Generic;
using System.Linq;
using Dynamicweb.CoreUI.Actions.Implementations;
using Dynamicweb.CoreUI.Application;   // AreaBase
using Dynamicweb.CoreUI.Icons;
using Dynamicweb.CoreUI.Navigation;

// The class name MUST end in "Area" — AreaBase's constructor throws
// InvalidOperationException otherwise. It is a runtime failure, not a compile error.
public sealed class AcmeArea : AreaBase
{
    public AcmeArea()
    {
        Name = "Acme";
        Icon = Icon.Truck;
        Sort = 90;              // after the built-in areas
    }
}

public sealed class WidgetSection : NavigationSection<AcmeArea>
{
    public WidgetSection(NavigationContext context) : base(context)
    {
        Name = "Widgets";
        Sort = 10;
    }
}

public sealed class WidgetNodeProvider : NavigationNodeProvider<WidgetSection>
{
    public override IEnumerable<NavigationNode> GetRootNodes()
    {
        yield return new NavigationNode
        {
            Name = "All widgets",
            Id = "Acme_Widgets",            // stable, unique
            Icon = Icon.Folder,
            Sort = 10,
            NodeAction = NavigateScreenAction.To<WidgetListScreen>().With(new WidgetsQuery())
        };
    }

    public override IEnumerable<NavigationNode> GetSubNodes(NavigationNodePath parentNodePath)
        => Enumerable.Empty<NavigationNode>();
}
```

> **`.With(query)` is not optional.** A node action of just `NavigateScreenAction.To<TScreen>()` compiles,
> deploys, and navigates — and the screen then renders its chrome (title, breadcrumb, action menu) with
> **"No results found — There are no records to display"**. There is no error anywhere; the screen simply
> has no data source. Verified by hitting it: the same node with `.With(new WidgetsQuery())` renders the
> rows immediately.

Icon names are members of the `Icon` type and are **not** free text — `Icon.List`, for instance, does not
exist. Let IntelliSense complete them rather than guessing.

To hang your section off a *built-in* area instead of your own, use that area's type as the generic
argument (`NavigationSection<ProductsArea>`).

## Steps 4b and 5 — extending what you do not own

You can add to someone else's area tree, drop an entry into an existing Actions menu, and inject
into a screen you do not own — without forking any of it. Each has its own silent-failure mode: a
node whose action forgets `.With(query)` renders "No results found" with no error, and an
`ActionGroup` given only a `Title` renders dimmed and inert.

The mechanisms and those traps are in
[references/injectors-and-navigation.md](references/injectors-and-navigation.md).

## Step 6 — Deploy

There is no registration step: `AddInManager` discovers areas, sections, node providers, screens, queries,
commands and injectors automatically. That convenience is also the trap — nothing tells you when
discovery failed.

```bash
dotnet build -c Release
dw install ./bin/Release/net10.0/Acme.AdminUi.dll --output json \
  --host <solution> --apiKey "$(cat ~/.dw-apikey)"
```

Omit `-q`: a queued install defers activation to the next recycle, so your screen will not appear until
then. See the dw-setup-cli skill for the full command reference.

## Step 7 — Verify (mandatory)

**`dw install` reporting `ok: true` means the file was uploaded and the API accepted it. It is not
evidence that your code loaded, and it is never evidence that your screen works.**

Verify in this order — each step rules out a different failure:

**1. Did the assembly load?** Check `/Files/System/Log/AddInManager/TypeLoadErrors.log`. A version
mismatch appears there as `MyAddIn (Context) ReflectionTypeLoadException Could not load file or assembly
'Dynamicweb.Core, Version=...'`. The `(Context)` suffix is normal — add-ins load into their own
`AssemblyLoadContext`. No entry naming your assembly means it loaded.

**2. Did your area register?** This one *is* checkable over the API, without an admin login. The
`NavigationByPath` query resolves an area by the path segment `/{ClassNameWithoutAreaSuffix}` — so
`AcmeArea` is reachable at `/Acme`:

```bash
curl -s -H "Authorization: Bearer $KEY"   "https://<host>/Admin/Api/NavigationByPath?Path=/Acme"
```

Tested before and after a deploy: beforehand it returns HTTP 500
`Unable to resolve area from path: /Acme`; afterwards HTTP 200 with `title` set to your area's `Name`.
That single call proves `AddInManager` found your `AreaBase` subclass in the deployed assembly, which is
the part most likely to have failed.

> **It does not verify sections or nodes.** `sections` and `nodes` come back empty from that endpoint even
> for a core area like `/Content`, at any path depth — the navigation tree needs an authenticated admin
> user context that an API key does not carry. Do not read empty arrays as "my section is missing".

**3. Does the screen render?** Open the admin, navigate to your node, and look at it. For sections, nodes
and the screen itself this is the only real test — and it is worth doing, because the two most common
failures at this stage (an empty list, a node that leads nowhere) produce no error at all.

The whole chain in this skill has been verified this way on a live 10.29.1 solution: an area appeared in
the sidebar at its `Sort` position, its section and node rendered in the tree, and the node opened a list
screen showing the rows its query returned, with the columns from `GetViewMappings()`.

**4. Did anything throw?** Errors during rendering land in the `GeneralLog` **table**, not in a file.
Query it over the Management API with the `LogEventByFilters` query, narrowing with `QueryAction`,
`QueryCategory` and `Level`:

```bash
curl -s -H "Authorization: Bearer $DW_API_KEY"   "https://<solution>/Admin/Api/LogEventByFilters?Level=Error"
```

Read that log before theorising. A silent screen usually has an exception behind it, and three wrong
theories are cheaper to avoid than to disprove.

If the node is missing but the assembly loaded, suspect the routing decision from Step 1 — a screen
subclassing a core screen, or a node provider whose section type does not match a real area.

## Common mistakes

| Symptom | Cause |
|---|---|
| Screen deploys but never renders | Subclassed a core screen instead of using an injector |
| `CS0311` on your `NavigationSection<>` | Missing `using Dynamicweb.CoreUI.Application;` so `AreaBase` did not resolve |
| `CS0117: 'Icon' does not contain a definition for ...` | Invented an icon name |
| Nothing appears, no error anywhere | Built against newer packages than the solution runs — check `TypeLoadErrors.log` |
| Screen opens but says "No results found" | Node action has no query bound — add `.With(new YourQuery())` |
| Change appears only after a recycle | Installed with `-q` |
| Someone else's screen breaks after your deploy | Injector threw; add the shape and null checks |

## Reference

- [Custom UI landing](https://doc.dynamicweb.dev/documentation/extending/administration-ui/index.html)
- [Screen architecture](https://doc.dynamicweb.dev/documentation/extending/administration-ui/screenconcept.html)
- [Creating custom screens](https://doc.dynamicweb.dev/documentation/extending/administration-ui/screens.html)
- [Screen injectors](https://doc.dynamicweb.dev/documentation/extending/administration-ui/screen-injectors.html)
- [Area list](https://doc.dynamicweb.dev/documentation/extending/administration-ui/arealist.html) ·
  [Area tree](https://doc.dynamicweb.dev/documentation/extending/administration-ui/areatree.html) ·
  [Action menu](https://doc.dynamicweb.dev/documentation/extending/administration-ui/action-menu.html)

Reading real implementations beats guessing: `Dynamicweb.Application.UI` in the platform source holds 123
screens, 139 queries and 103 commands. `LicenseFeatureListScreen` and `OAuthClientDeleteCommand` are good
minimal examples.
