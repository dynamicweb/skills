---
name: dynamicweb-source-explorer
description: Browse Dynamicweb source code from GitHub repositories to understand internal APIs, classes, and patterns. Use when you need to understand how a Dynamicweb API works internally, find the right classes/methods to use, or discover extension points before building MCP tools.
---

# Dynamicweb Source Explorer

## Purpose

Navigate the Dynamicweb open-source repositories on GitHub to understand internal APIs, discover available classes/methods, and find implementation patterns. This replaces the need for a local Dynamicweb source checkout.

## When to Use

- Before creating a new MCP tool, to find the right Dynamicweb API to wrap
- When a tool is failing and you need to understand the internal behavior
- When you need to discover what services, entities, or extension points exist
- When documentation on `doc.dynamicweb.dev` is insufficient and you need source-level understanding

## Dynamicweb GitHub Repositories

The Dynamicweb platform source code is split across multiple repositories under `https://github.com/dynamicweb/`:

| Repository | NuGet Package | Contains |
|------------|---------------|----------|
| `dynamicweb` | `Dynamicweb` | Core platform: content, pages, areas, users, security |
| `dynamicweb-core` | `Dynamicweb.Core` | Base utilities, extensibility, caching, logging |
| `dynamicweb-ecommerce` | `Dynamicweb.Ecommerce` | Products, categories, orders, pricing, discounts, shops |

### Key Namespaces by Area

| Area | Namespace | Typical Location |
|------|-----------|------------------|
| Products | `Dynamicweb.Ecommerce.Products` | `dynamicweb-ecommerce/src/Dynamicweb.Ecommerce/Products/` |
| Orders | `Dynamicweb.Ecommerce.Orders` | `dynamicweb-ecommerce/src/Dynamicweb.Ecommerce/Orders/` |
| Pricing | `Dynamicweb.Ecommerce.Prices` | `dynamicweb-ecommerce/src/Dynamicweb.Ecommerce/Prices/` |
| Discounts | `Dynamicweb.Ecommerce.Products.Discounts` | `dynamicweb-ecommerce/src/Dynamicweb.Ecommerce/Products/Discounts/` |
| Categories | `Dynamicweb.Ecommerce.Products.Categories` | `dynamicweb-ecommerce/src/Dynamicweb.Ecommerce/Products/Categories/` |
| Shops | `Dynamicweb.Ecommerce.Shops` | `dynamicweb-ecommerce/src/Dynamicweb.Ecommerce/Shops/` |
| Content/Pages | `Dynamicweb.Content` | `dynamicweb/src/Dynamicweb/Content/` |
| Users | `Dynamicweb.Security` | `dynamicweb/src/Dynamicweb/Security/` |
| Indexing | `Dynamicweb.Indexing` | `dynamicweb-core/src/Dynamicweb.Core/Indexing/` |
| Extensibility | `Dynamicweb.Extensibility` | `dynamicweb-core/src/Dynamicweb.Core/Extensibility/` |

## How to Browse Source

### Using WebFetch on GitHub

Fetch raw source files directly:
```
https://raw.githubusercontent.com/dynamicweb/{repo}/main/{path-to-file}
```

Example -- read the Product class:
```
https://raw.githubusercontent.com/dynamicweb/dynamicweb-ecommerce/main/src/Dynamicweb.Ecommerce/Products/Product.cs
```

### Using GitHub API for Directory Listing

List files in a directory:
```
https://api.github.com/repos/dynamicweb/{repo}/contents/{path}
```

Example -- list files in the Products directory:
```
https://api.github.com/repos/dynamicweb/dynamicweb-ecommerce/contents/src/Dynamicweb.Ecommerce/Products
```

### Using GitHub Search

Search across a repository:
```
https://api.github.com/search/code?q={query}+repo:dynamicweb/{repo}
```

Example -- find all classes implementing `IDiscount`:
```
https://api.github.com/search/code?q=IDiscount+repo:dynamicweb/dynamicweb-ecommerce
```

## Exploration Workflow

### Finding the Right API for a New Tool

1. **Start with the Services layer** -- Dynamicweb exposes static service facades:
   ```
   Dynamicweb.Ecommerce.Services.Products
   Dynamicweb.Ecommerce.Services.Orders
   Dynamicweb.Ecommerce.Services.Languages
   Dynamicweb.Ecommerce.Services.Shops
   ```
   Browse `https://api.github.com/repos/dynamicweb/dynamicweb-ecommerce/contents/src/Dynamicweb.Ecommerce/Services` to see all available service classes.

2. **Read the service interface** -- most services have an interface (e.g., `IProductService`) that documents available methods.

3. **Check the entity class** -- understand the domain model properties and methods (e.g., `Product.cs`, `Order.cs`).

4. **Look at existing tools in this project** -- check `*/Tools/` and `*/Services/` for patterns already established.

### Understanding an Entity's Properties

1. Fetch the entity class from GitHub
2. Look for public properties (these are what your model should map)
3. Check for `Save()` methods or service methods that persist the entity
4. Note any special behavior (computed properties, required fields, validation)

### Finding Extension Points

1. Search for `AddInManager`, `Provider`, or `abstract class` in the relevant namespace
2. Check `Dynamicweb.Extensibility` for base classes and attributes
3. Look for `[AddInName]`, `[AddInParameter]` attributes on existing implementations

## Common Patterns in Dynamicweb Source

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

- GitHub API has rate limits (60 requests/hour unauthenticated). Batch your exploration.
- Raw file fetching (`raw.githubusercontent.com`) does not count against the API rate limit.
- If a repository structure is unclear, start with the `.csproj` file to see the namespace root.
- The `main` branch is the default for all Dynamicweb repositories.
- NuGet package versions in this project's `.csproj` correspond to tagged releases in the GitHub repos.
