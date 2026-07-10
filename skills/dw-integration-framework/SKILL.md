---
name: dw-integration-framework
type: knowledge
group: integration
description: 'Understand Dynamicweb 10 Integration Framework architecture and patterns. Triggers: Integration Framework, external systems, source/target providers. Non-triggers: ERP specifics -> dw-integration-erp; Business Central -> dw-integration-bc.'
---

# Integration Framework

## Architecture Overview

The Integration Framework moves data between Dynamicweb and external systems via **Activities**. Each activity has a **Source** (reads data) and a **Destination** (writes data), connected by a **mapping** (field-level translation between source and destination schemas).

```
External system / API
        ↓
    Source Provider (ISource + ISourceReader)
        ↓
    Table/Column Mapping  ←→  Column scripting (Append, Constant, Substring, etc.)
        ↓
Destination Provider (IDestination + IDestinationWriter)
        ↓
    Dynamicweb DB / API / External system
```

## Admin: Creating and Running Activities

Admin path: **Integration > Activities**

### Create an Activity

1. Click **New custom activity** (or use a blueprint for standard scenarios)
2. **General tab:** Name, Group, "Create mappings at runtime" checkbox (auto-maps columns with the same name)
3. **Source tab:** Select and configure the source provider
4. **Destination tab:** Select and configure the destination provider
5. **Notification tab:** Email on completion/failure
6. **Cache tab:** Cache services to clear after the run
7. **Repository index tab:** Search indexes to rebuild after the run

### Configure Mappings

After creating the activity:
1. Click **New table mapping** — pick source table and destination table
2. Set **key columns** (used for upsert logic; defaults to primary key, override with e.g., `ProductNumber`)
3. Add **column mappings** manually or via "Add multiple column mappings"
4. Set **conditionals** per table mapping (filter which source rows are processed)
5. Optionally apply **scripting** to individual column mappings (Append, Constant, Substring, Prepend, etc.)
6. Set **null handling** per column: Default (type default), Constant value, or Skip row

### Running Activities

- **Run now** — from the Activity Info widget in admin
- **Scheduled** — via Settings > Scheduled Tasks → `DataIntegration.RunIntegrationActivityAddIn` task
- **Triggered from code** — `ActivityService.RunActivity(activityId)`

**Logs** are stored in `/Files/System/Log/Data integration/` as `_lastrun.log` and `_lastrunresult.log`.

Activity XML (job definitions) is stored in `/Files/Files/Integration/jobs/{activityFolder}/{jobName}.xml` and can be copied between solutions.

## Built-in Source/Destination Providers

| Provider | Direction | Use for |
|---------|----------|--------|
| SQL Provider | Both | Read/write Dynamicweb or any SQL Server DB |
| OData Source Provider | Source | Read from OData v4 APIs (ERP, BC, etc.) |
| CSV Provider | Both | Flat file import/export |
| XML Provider | Both | XML file import/export |
| JSON Provider | Source | JSON API import |
| HTTP Provider | Source | Generic HTTP endpoint |
| Product Provider | Destination | Import products into the DW product catalog |
| Order Provider | Source | Export orders from DW |

## Building a Custom Provider

Providers are C# classes that implement `ISource`, `IDestination`, or both. All providers inherit from `BaseProvider` (`Dynamicweb.DataIntegration.BaseProvider`).

### Class Skeleton

```csharp
using Dynamicweb.DataIntegration;
using Dynamicweb.DataIntegration.Integration;
using Dynamicweb.DataIntegration.Integration.Interfaces;
using Dynamicweb.Extensibility.AddIns;

[AddInName("MyCompany.MyProvider")]
[AddInLabel("My Custom Provider")]
[AddInDescription("Reads data from the My API.")]
public class MyProvider : BaseProvider, ISource, IDestination
{
    // Source tab parameters
    [AddInParameter("API Endpoint")]
    [AddInParameterEditor(typeof(TextParameterEditor), "")]
    [AddInParameterGroup("Source")]
    public string ApiEndpoint { get; set; } = "";

    // Destination tab parameters
    [AddInParameter("Write Timeout")]
    [AddInParameterEditor(typeof(IntegerParameterEditor), "")]
    [AddInParameterGroup("Destination")]
    public int WriteTimeoutSeconds { get; set; } = 30;

    private Schema _schema;

    // Lifecycle
    public override void Initialize() { /* setup connections */ }
    public override void Close() { /* cleanup */ }

    public override bool RunJob(Job job)
    {
        ReplaceMappingConditionalsWithValuesFromRequest(job);
        foreach (Mapping mapping in job.Mappings)
        {
            if (!mapping.Active) continue;
            using var reader = GetReader(mapping);
            using var writer = GetWriter(mapping);
            while (!reader.IsDone())
            {
                var row = reader.GetNext();
                writer.Write(row);
            }
        }
        return true;
    }

    // Serialization
    public override string Serialize()
    {
        var xDoc = new XDocument(new XElement("Parameters",
            CreateParameterNode(GetType(), "ApiEndpoint", ApiEndpoint)));
        return xDoc.ToString();
    }
}
```

### ISource — Schema and Reader

```csharp
public Schema GetSchema() => _schema ?? (_schema = GetOriginalSourceSchema());

public Schema GetOriginalSourceSchema()
{
    var schema = new Schema();
    var table = schema.AddTable("MyData");
    table.AddColumn(new Column("Id", typeof(int), table, isPrimaryKey: true, isNew: false));
    table.AddColumn(new Column("Name", typeof(string), table, isPrimaryKey: false, isNew: false));
    table.AddColumn(new Column("Value", typeof(decimal), table, isPrimaryKey: false, isNew: false));
    return schema;
}

public ISourceReader GetReader(Mapping mapping) => new MySourceReader(ApiEndpoint, mapping);

public void SaveAsXml(XmlTextWriter writer)
{
    writer.WriteElementString("ApiEndpoint", ApiEndpoint);
    GetSchema().SaveAsXml(writer);
}

public string ValidateSourceSettings() => ""; // empty = valid; any string = error message
```

### ISourceReader

```csharp
public class MySourceReader : ISourceReader
{
    private IEnumerator<Dictionary<string, object>> _enumerator;
    private Dictionary<string, object> _current;
    private bool _done;

    public MySourceReader(string endpoint, Mapping mapping)
    {
        var data = FetchData(endpoint); // returns IEnumerable<Dictionary<string,object>>
        _enumerator = data.GetEnumerator();
        _done = !_enumerator.MoveNext();
        _current = _done ? null : _enumerator.Current;
    }

    public Dictionary<string, object> GetNext()
    {
        var result = _current;
        _done = !_enumerator.MoveNext();
        _current = _done ? null : _enumerator.Current;
        return result;
    }

    public bool IsDone() => _done;
    public void Dispose() => _enumerator?.Dispose();
}
```

### IDestinationWriter

```csharp
public class MyDestinationWriter : IDestinationWriter
{
    public Mapping Mapping { get; }

    public MyDestinationWriter(Mapping mapping) { Mapping = mapping; }

    public void Write(Dictionary<string, object> row)
    {
        foreach (var colMapping in Mapping.GetColumnMappings())
        {
            if (!colMapping.Active) continue;
            string destCol = colMapping.DestinationColumn.Name;
            object value = colMapping.ConvertInputValueToOutputValue(row[colMapping.SourceColumn.Name]);
            // Write `value` to `destCol`
        }
    }

    public void Close() { /* flush / commit */ }
}
```

## Column Mapping Scripting

Column mappings support transformations at the mapping layer:

| Script type | Purpose |
|------------|--------|
| `Constant` | Replace the source value with a fixed constant |
| `Append` | Append a string to the source value |
| `Prepend` | Prepend a string to the source value |
| `Substring` | Extract a portion of the source value |
| `New Guid` | Generate a new GUID (ignores source value) |
| `Current time` | Replace with current timestamp |
| `Invert` | Invert a boolean |
| `Code` | C# expression evaluated at runtime (via `ScriptTypeProvider`) |

### Custom ScriptTypeProvider

```csharp
using Dynamicweb.DataIntegration.Providers.ScriptTypeProvider;

[AddInLabel("URL Encode")]
public class UrlEncodeScriptProvider : ScriptTypeProvider<string>
{
    protected override string GetValueTyped(object? input)
        => Uri.EscapeDataString(input?.ToString() ?? "");
}
```

## Mapping Conditionals

Filter which source rows to process using expressions on the table mapping:

| Operator | Description |
|----------|-------------|
| `Equals` | Exact match |
| `Contains` | Substring match |
| `In` | Value is in a comma-separated list |
| `Less than` / `Greater than` | Numeric/date comparison |

Context-sensitive values in conditionals and scripting:
- `@Request(key)` — HTTP request value
- `@Session(key)` — session value
- `@User(property)` — current user property
- `@Page(property)` — current page property
- `@Code(...)` — inline C# expression

## Activity Groups

Activities can be organized in groups (folders). Groups can inherit source/destination configuration, and subgroups override inherited settings. Groups are just folders in the XML storage at `/Files/Files/Integration/jobs/`.

## Pitfalls

**`RunJob` is only called when the provider is the Destination** — the framework calls `LoadSettings` on the Source, then `RunJob` on the Destination. If your provider is used as both, implement both correctly.

**Schema changes after first run** — if a provider's schema changes after mappings have been created, existing mappings may break. The `OverwriteSourceSchemaToOriginal()` / `OverwriteDestinationSchemaToOriginal()` methods handle schema refresh, but saved column mappings may reference columns that no longer exist.

**`ReplaceMappingConditionalsWithValuesFromRequest(job)` must be called in RunJob** — this replaces `@Request()` / `@Session()` / `@User()` tokens in conditional expressions. Forgetting this call leaves tokens unreplaced.

**Activity XML can be copied between solutions** — useful for moving tested activities from staging to production. Copy the XML file; re-configure provider credentials in admin after paste.

## Next Steps

- **ERP-specific integration?** See [dw-integration-erp](../dw-integration-erp)
- **Business Central connector?** See [dw-integration-bc](../dw-integration-bc)
- **Triggering activities from code?** See [dw-extend-providers](../dw-extend-providers)
- **Custom scheduled trigger?** See [dw-extend-scheduled-tasks](../dw-extend-scheduled-tasks)
