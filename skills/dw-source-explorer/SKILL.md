---
name: dw-source-explorer
type: knowledge
group: source
mcp: none
dynamo: false
description: 'Find Dynamicweb API internals and extension points from NuGet package metadata, the release changelog and the public GitHub repositories. Triggers: find classes/methods, understand implementation before coding. MCP tool implementation -> dw-extend-mcp-tools.'
---

# Dynamicweb Source Explorer

## Deep reference

| Topic | Where |
|---|---|
| Assembly introspection — the "grep first, reflect second" discipline (reflection answers "does it exist", never "why is it not selected") and the `MetadataReader` recipe for listing an installed AddIn's `*Query`/`*Command` endpoint surface without loading the assembly | [`references/assembly-introspection.md`](references/assembly-introspection.md) |

## Purpose

Find what Truvio Commerce (powered by Dynamicweb) exposes to code: which classes, methods,
services and extension points exist in a given version, and what changed between versions. The
platform source is not public, so the answer comes from what is published: the NuGet packages,
the release changelog, the documentation and a handful of public repositories.

## When to Use

- Before creating a new MCP tool, to find the right Dynamicweb API to wrap
- When a tool is failing and you need to understand the internal behavior
- When you need to discover what services, entities, or extension points exist
- When documentation on `doc.dynamicweb.dev` is insufficient and you need the exact surface of a version

## What is public and what is not

**The platform source (`Dynamicweb`, `Dynamicweb.Core`, `Dynamicweb.Ecommerce` and the other
platform assemblies) is not on public GitHub.** Reading it needs access granted by Dynamicweb.
Measured 2026-11-12 with unauthenticated requests to `api.github.com/repos/dynamicweb/<repo>`:
`dynamicweb-core` and `dynamicweb-ecommerce` answer 404, and `DynamicWeb` is the feature-request
repository (`.github`, `LICENSE`, `README.md`, no code). Do not build a
`raw.githubusercontent.com` URL to a platform class: it returns 404, and a guess at the
implementation is not a finding. When a question can only be settled by the implementation, say
so and ask whoever has that access.

Work down the public routes in this order.

### 1. NuGet package metadata (the exact API surface of a version)

Every platform assembly ships on nuget.org with its XML documentation file. The package is a zip:
download it, unpack it, and read the assembly with `MetadataReader`, which lists types and members
without loading the assembly or its dependencies
([`references/assembly-introspection.md`](references/assembly-introspection.md) explains why
`Assembly.LoadFrom` fails here).

```powershell
$id = 'Dynamicweb.Ecommerce'; $version = '<version the solution runs>'; $work = '<empty work folder>'
$lower = $id.ToLowerInvariant()
Invoke-WebRequest "https://api.nuget.org/v3-flatcontainer/$lower/$version/$lower.$version.nupkg" -OutFile "$work\$lower.zip"
Expand-Archive "$work\$lower.zip" "$work\$lower" -Force
$dll = Get-ChildItem "$work\$lower\lib" -Recurse -Filter "$id.dll" | Select-Object -First 1

Add-Type -AssemblyName System.Reflection.Metadata -ErrorAction SilentlyContinue
$stream = [System.IO.File]::OpenRead($dll.FullName)
try {
  $pe = [System.Reflection.PortableExecutable.PEReader]::new($stream)
  $mr = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($pe)
  foreach ($h in $mr.TypeDefinitions) {
    $td = $mr.GetTypeDefinition($h)
    $name = '{0}.{1}' -f $mr.GetString($td.Namespace), $mr.GetString($td.Name)
    if ($name -ne 'Dynamicweb.Ecommerce.Products.ProductService') { continue }   # or print every $name
    $td.GetMethods() | ForEach-Object {
      $m = $mr.GetMethodDefinition($_)
      if ($m.Attributes -band [System.Reflection.MethodAttributes]::Public) { $mr.GetString($m.Name) }
    } | Sort-Object -Unique
  }
} finally { $pe.Dispose(); $stream.Dispose() }
```

- `https://api.nuget.org/v3-flatcontainer/<lowercase id>/index.json` lists the published versions.
  Take the version from the solution (its `.csproj` or the installed assembly), never from memory.
- `<Assembly>.xml` next to the DLL holds the summaries and parameter descriptions of the public
  members: search it for the member name.
- Run the same recipe on two versions and compare the output to see what a release added or
  removed.
- Metadata answers "does it exist and what is its signature". It does not answer "what does the
  body do" or "why is this provider not selected"; see the reference before concluding a
  capability is missing.

### 2. The release changelog API

`https://devopsservice.dynamicweb-cms.com/api/documentation/release/detailedinfo/<n>` answers
without authentication with a JSON array of releases, each with `version`, `isReleased` and
`workItems` (`title`, `id`, `type`, `area`). `<n>` is a number that selects a release line, `1`
being the newest; on 2026-11-12, `1` held the 10.30 line and `2` the 10.29 line. Read the
`version` values in the answer to confirm which line you got, since the numbering shifts when a
new line ships. A version string in place of the number answers 400. Use it to find the work
item behind a behavior change, then confirm the change in the package metadata.

### 3. The documentation

`doc.dynamicweb.dev` carries the API reference and the extensibility guides. The lookup
discipline is in `dw-source-doc-lookup`.

### 4. Public repositories under `github.com/dynamicweb`

These are public and hold code (unauthenticated org listing, 2026-11-12; default branch `main`
on each). They cover the storefront, the tooling and some providers, not the platform.

| Repository | Contains |
|------------|----------|
| `Swift` | The Swift 2 design: Razor templates, item types and its project file |
| `swift-demo-data` | The `Files` content of the Swift demo |
| `BasicDesign` | A basic design: templates for content, navigation, ecommerce and users |
| `CLI` | The `dw` command line tool |
| `CheckoutHandlers.AuthorizeNetApi`, `CheckoutHandlers.KlarnaCheckout` | Checkout handler providers in C# |
| `Shipping.UPS` | A shipping provider in C# |
| `DataIntegration.LiveIntegration` | The live integration add-in in C# |
| `Samples` | Extensibility samples in C# |
| `Summit2022_APILandscape`, `Summit2022_ExtendingTheUI` | Conference samples for the APIs and the administration UI |
| `NetStandardIntellisenseProject` | A project that gives template IntelliSense |

The provider repositories are the closest public example of how a provider or add-in is written
against the platform. The listing changes: read
`https://api.github.com/orgs/dynamicweb/repos?per_page=100` before relying on a name, and treat a
404 as "not public", not as a typo to work around.

Reading them:

```
https://api.github.com/repos/dynamicweb/{repo}/contents/{path}           # directory listing
https://raw.githubusercontent.com/dynamicweb/{repo}/main/{path-to-file}  # one file
```

The unauthenticated GitHub API allows 60 requests an hour; raw file fetches do not count against
it. Code search (`api.github.com/search/code`) requires authentication.

## Key Namespaces by Area

| Area | Namespace | Package |
|------|-----------|---------|
| Products | `Dynamicweb.Ecommerce.Products` | `Dynamicweb.Ecommerce` |
| Orders | `Dynamicweb.Ecommerce.Orders` | `Dynamicweb.Ecommerce` |
| Pricing | `Dynamicweb.Ecommerce.Prices` | `Dynamicweb.Ecommerce` |
| Discounts | `Dynamicweb.Ecommerce.Products.Discounts` | `Dynamicweb.Ecommerce` |
| Categories | `Dynamicweb.Ecommerce.Products.Categories` | `Dynamicweb.Ecommerce` |
| Shops | `Dynamicweb.Ecommerce.Shops` | `Dynamicweb.Ecommerce` |
| Content/Pages | `Dynamicweb.Content` | `Dynamicweb` |
| Users | `Dynamicweb.Security` | `Dynamicweb` |
| Indexing | `Dynamicweb.Indexing` | `Dynamicweb.Core` |
| Extensibility | `Dynamicweb.Extensibility` | `Dynamicweb.Core` |

## Exploration Workflow

### Finding the Right API for a New Tool

1. **Start with the Services layer** -- Dynamicweb exposes static service facades:
   ```
   Dynamicweb.Ecommerce.Services.Products
   Dynamicweb.Ecommerce.Services.Orders
   Dynamicweb.Ecommerce.Services.Languages
   Dynamicweb.Ecommerce.Services.Shops
   ```
   List the members of the `Dynamicweb.Ecommerce.Services` type from the package metadata to see
   every service the version carries.

2. **Read the service type** -- list its public methods from the metadata and read their
   summaries in the XML documentation file.

3. **Check the entity class** -- its public properties are the domain model (e.g. `Product`,
   `Order`).

4. **Look at existing tools in this project** -- check `*/Tools/` and `*/Services/` for patterns already established.

### Understanding an Entity's Properties

1. List the entity type's members from the package metadata
2. Look for public properties (these are what your model should map)
3. Check for `Save()` methods or service methods that persist the entity
4. Read the XML documentation for special behavior (computed properties, required fields); what
   it does not state, measure on a running solution rather than assume

### Finding Extension Points

1. List the types in `Dynamicweb.Extensibility` and the abstract `*Provider` types in the relevant namespace
2. Read a public provider (`CheckoutHandlers.*`, `Shipping.UPS`) for a complete implementation,
   including its `[AddInName]` and `[AddInParameter]` attributes

## Common Patterns in the Dynamicweb API

### Static Service Facades
```csharp
// Most CRUD operations go through static facades:
Dynamicweb.Ecommerce.Services.Products.GetProductById(id, variantId, languageId);
Dynamicweb.Ecommerce.Services.Products.Save(product, groupId, variantId, languageId);
```

### ServiceLocator for DI Services
```csharp
// For services registered in DI:
var queryService = ServiceLocator.Current.GetInstance<IQueryService>();
```

### CommandBuilder for SQL
```csharp
// For direct SQL (used in Configuration/Database/):
var cmd = new CommandBuilder();
cmd.Add("SELECT * FROM MyTable WHERE Id = @id");
cmd.AddParameter("@id", id);
var reader = Database.CreateDataReader(cmd);
```

## Tips

- Pin every lookup to the version the solution runs; a member present in the newest package may not exist there.
- A provider repository's `.csproj` names the platform package versions it was built against.
- State where a finding came from (package and version, changelog work item, documentation page, repository file) so the next reader can repeat it.
