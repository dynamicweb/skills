---
name: dw-extend-mcp-tools
description: Step-by-step guide for adding new MCP tools to the Dynamicweb.MCP project -- tool classes, services, models, and route handlers. Triggers: create a new MCP tool or domain area, add services/models/route handlers to Dynamicweb.MCP, expose a new operation over MCP. Non-triggers: understanding existing Dynamicweb APIs before coding -> dynamicweb-source-explorer; using existing MCP tools to query products -> dynamicweb-pim-query.
---

# MCP Tool Creator

## Purpose

Guide the creation of new MCP tools in this project, following the established patterns and conventions. Ensures correct attribute usage, permission levels, model design, and Dynamicweb API integration.

## Before You Start

1. Read the CLAUDE.md file for project architecture overview.
2. Identify which domain the new tool belongs to (Products, Commerce, Content, or a new domain).
3. Determine which Dynamicweb APIs are needed -- browse the Dynamicweb source on GitHub (`https://github.com/dynamicweb`) or use the `dynamicweb-source-explorer` skill to find the right APIs.

## Workflow

### 1. Understand the Requirement

Clarify:
- What operation does the tool perform? (CRUD, query, assignment, etc.)
- What Dynamicweb entities are involved?
- What permission level is appropriate? (`Read`, `Write`, `Create`, `Delete`)
- What inputs and outputs does the tool need?

### 2. Find the Dynamicweb APIs

Before writing any code, identify the Dynamicweb APIs that will back the tool:
- Browse the relevant Dynamicweb NuGet package source on GitHub
- Check existing services in `*/Services/` for patterns already used
- Use `Dynamicweb.Ecommerce.Services.*` static facades when available
- Use `ServiceLocator.Current.GetInstance<T>()` for dependency-injected services

### 3. Create or Extend Models

Location: `{Domain}/Models/`

**Conventions:**
- `{Entity}Model` -- read/response model (returned from tools)
- `{Entity}CreateModel` -- input for creation tools
- `{Entity}UpdateModel` -- input for full-update tools
- `{Entity}PatchModel` / `{Entity}PatchRequest` -- input for partial-update tools (use `Maybe<T>` or `*WasProvided` pattern for true partial semantics)
- `{Entity}DeleteRequest` -- input for delete tools when more than a simple ID is needed
- Add `[Description("...")]` on the class and on each property -- this is what MCP clients show to users
- **Keep models flat (1 level deep)** -- Copilot Studio and ChatGPT cannot parse nested objects
- Use `FromDomain(DynamicwebEntity)` static factory methods to convert from Dynamicweb entities to models
- Use `ApplyToDomain(DynamicwebEntity)` instance methods to apply model values to Dynamicweb entities

**Example:**
```csharp
using System.ComponentModel;

namespace Dynamicweb.MCP.Products.Models;

[Description("Represents a widget configuration.")]
public sealed class WidgetModel
{
    [Description("Unique identifier.")]
    public string Id { get; set; } = "";

    [Description("Display name.")]
    public string Name { get; set; } = "";

    public static WidgetModel FromDomain(SomeDynamicwebType entity) => new()
    {
        Id = entity.Id,
        Name = entity.Name
    };
}
```

### 4. Create or Extend the Service

Location: `{Domain}/Services/`

**Conventions:**
- Services are `internal sealed class` (not static)
- Services wrap Dynamicweb API calls and return models or `BulkResponse<T>` / `PagedResponse<T>`
- Use `Dynamicweb.Ecommerce.Services.*` static facades for product/commerce operations
- Use `ServiceLocator.Current.GetInstance<T>()` for indexed/queryable services
- Bulk operations follow the try/catch-per-item pattern with `BulkResponse`:

```csharp
internal sealed class MyService
{
    public BulkResponse<MyModel> CreateItems(List<MyCreateModel> items)
    {
        int success = 0, failed = 0;
        List<string> errors = [];
        List<MyModel> results = [];

        foreach (var item in items ?? [])
        {
            try
            {
                // Call Dynamicweb API
                var entity = new SomeDynamicwebType();
                item.ApplyToDomain(entity);
                SomeDynamicwebService.Save(entity);
                results.Add(MyModel.FromDomain(entity));
                success++;
            }
            catch (Exception ex)
            {
                failed++;
                errors.Add(ex.Message);
            }
        }

        return new BulkResponse<MyModel> { Succeeded = success, Failed = failed, Items = results, Errors = errors };
    }
}
```

### 5. Create the Tool Class

Location: `{Domain}/Tools/`

**Required attributes on the class:**
- `[McpServerToolType]`

**Required attributes on each method:**
- `[McpServerTool]` or `[McpServerTool(Title = "Human Readable Name")]`
- `[McpToolPermission(McpToolPermissionLevel.Read|Write|Create|Delete)]`
- `[Description("Clear description of what the tool does and what it returns.")]`

**Optional attributes:**
- `[McpServerTool(UseStructuredContent = true)]` -- for tools returning complex objects (recommended for lists/bulk responses)

**Conventions:**
- Tool classes are `public static class` with `[McpServerToolType]`
- Service instances are `private static readonly` fields
- Method names become snake_case tool names: `GetProducts` -> `get_products`
- Class name minus "Tools" suffix = tool group name: `ProductTools` -> "Product"
- **Never return void** -- always return a result object or string
- Use default parameter values for optional parameters
- Add `[Description("...")]` on parameters too
- For tools that need MCP server context (progress notifications), accept `McpServer server` and `RequestContext<CallToolRequestParams> context` as parameters

**Permission level guide:**
| Operation | Level | Naming convention |
|-----------|-------|-------------------|
| Read/list/get/search | `Read` | `Get*`, `List*`, `Search*` |
| Update/patch/assign | `Write` | `Update*`, `Patch*`, `Assign*` |
| Create/save | `Create` | `Create*`, `Save*` |
| Delete/remove | `Delete` | `Delete*`, `Remove*` |

**Example:**
```csharp
using Dynamicweb.MCP.Configuration;
using Dynamicweb.MCP.Core.Responses;
using Dynamicweb.MCP.Products.Models;
using ModelContextProtocol.Server;
using System.ComponentModel;

namespace Dynamicweb.MCP.Products.Tools;

[McpServerToolType]
public static class WidgetTools
{
    private static readonly WidgetService WidgetService = new();

    [McpServerTool(Title = "Get Widgets")]
    [McpToolPermission(McpToolPermissionLevel.Read)]
    [Description("Returns all available widgets.")]
    public static List<WidgetModel> GetWidgets()
    {
        return WidgetService.GetAll();
    }

    [McpServerTool(UseStructuredContent = true, Title = "Create Widgets")]
    [McpToolPermission(McpToolPermissionLevel.Create)]
    [Description("Creates one or more widgets. Returns a BulkResponse with counts and created items.")]
    public static BulkResponse<WidgetModel> CreateWidgets(List<WidgetCreateModel> widgets)
    {
        return WidgetService.Create(widgets);
    }
}
```

### 6. Add Route Handlers (Optional -- REST API)

Only if the tool should also be exposed as a REST endpoint alongside MCP.

Location: `{Domain}/RouteHandlers/`

Register in the domain's `IServiceApi` implementation (e.g., `ProductsServiceApi.cs`).

### 7. Document the new tools

Record the new tools in the Dynamicweb.MCP project's own tool catalog/README so they are
discoverable by consumers:
- Find the matching group table (or create a new group section if none fits)
- Add a row per tool: `| \`tool_name\` | Short "use when" phrase |`
- Keep entries alphabetical within each group

### 8. Verify

After creating all files:
- Run `dotnet build` to check for compilation errors
- Verify the tool appears in the MCP tool list (the `McpToolRegistry` discovers it automatically via reflection)
- Test with an MCP client to confirm the tool works end-to-end

## Checklist

- [ ] Models have `[Description]` on class and all properties
- [ ] Models are flat (no nested complex objects) for broad client compatibility
- [ ] Service uses try/catch-per-item for bulk operations
- [ ] Service returns `BulkResponse<T>` or `PagedResponse<T>` (never void)
- [ ] Tool class has `[McpServerToolType]`
- [ ] Every tool method has `[McpServerTool]` + `[McpToolPermission]` + `[Description]`
- [ ] Permission level matches the operation type
- [ ] Method parameters have `[Description]` attributes
- [ ] `dotnet build` passes
- [ ] New tools documented in the Dynamicweb.MCP project tool catalog/README


