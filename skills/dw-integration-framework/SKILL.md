---
name: dw-integration-framework
type: knowledge
group: integration
mcp: optional
description: 'Understand Dynamicweb 10 Integration Framework architecture and patterns, and set up, run, schedule, or diagnose a Data Integration activity through the MCP tools. Triggers: Integration Framework, external systems, source/target providers, import/export products/users/orders via CSV/XML/Excel/OData, a failed or hanging integration activity. Non-triggers: ERP specifics -> dw-integration-erp; Business Central -> dw-integration-bc.'
---

# Integration Framework

## Without MCP

The knowledge here stands alone; the Dynamicweb MCP tools it names are the preferred way to
apply it. When no Dynamicweb MCP server is connected, work in advisory mode — explain,
review, or produce payloads and configuration for the user to apply — and do not substitute
direct SQL, file edits, or guessed HTTP calls for those tool calls.

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

## The three integration approaches (by name)

The framework supports three approaches, distinguished by *when* the data moves:

1. **Ad-hoc activities** — run on demand (a manual import/export of a data set, one execution at a time).
2. **Batch (scheduled) integration** — activities run by scheduled tasks at fixed intervals
   (hourly / daily / weekly), moving accumulated changes on each run.
3. **Live (real-time) integration** — retrieves data from a remote system in real time, e.g. live
   prices or stock states. The remote system is queried per request rather than on a schedule, so
   the displayed value is always current.

The same activity shape (source provider + destination provider + field mapping) underlies all three;
only the trigger differs — manual, scheduled, or per-request. In the DW docs' terms, an
**integration provider** is "a piece of software for moving data between Dynamicweb and an external
data source, like an XML file, a CSV file or an SQL database", and an activity requires two of them:
a source provider matching the data source and a destination provider matching the data destination.

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

## Setting Up Activities via MCP Tools

Everything above describes the admin-UI mechanics; this is the same concept model driven
through MCP tools instead.

**Concept model, mapped to tools:**
- **Activity** — one import/export job, identified as `group\name`. List with
  `get_integration_activities`, inspect with `get_integration_activity`.
- **Providers** — where data comes from and goes to. Both sides are providers; discover them
  with `get_integration_providers`, their settings with `get_integration_provider_parameters`,
  and the tables/columns they expose with `get_integration_provider_schema`.
- **Mappings** — source table → destination table, then column → column. **Key columns**
  (`IsKey`) decide insert-vs-update: without a key, every run inserts duplicates.
  **Conditionals** filter rows. Manage with `get_integration_activity_mappings` /
  `save_integration_activity_mapping`.
- **Endpoints** — authenticated remote requests (OAuth S2S, Basic, Bearer, ...), grouped in
  collections that can share authentication. The OData provider references an endpoint by id.
  Manage with `get_integration_endpoints` / `save_integration_endpoint`, verify with
  `test_integration_endpoint`.
- **Runs & logs** — `run_integration_activity` QUEUES a run (asynchronous — a queued result is
  not a completed run). Poll `get_integration_activity_status`; verify the outcome in
  `get_integration_activity_logs`. Row counts appear only as log text.
- **Schedules** — `schedule_integration_activity` binds a scheduled task to the activity
  (manage further with the scheduled-task tools — see
  [dw-extend-scheduled-tasks](../dw-extend-scheduled-tasks)).

**Choosing a destination provider for imports:**
- **Ecom provider** — ecommerce data with conveniences: auto-creates missing IDs, language
  rows, groups, manufacturers. First choice for product imports; costs ~3x the memory of the
  Dynamicweb provider.
- **Dynamicweb provider** — generic access to the whole database. Precise but manual:
  relation tables (e.g. group-product relations) must be mapped explicitly.
- **User / Order providers** — users and orders, with domain settings (user key field, "export
  not yet exported orders", order state after export).
- **OData provider** — reads/writes a remote OData API via an endpoint. Source modes: full
  replication vs **delta** (changed-since-last-run; never deletes; first run falls back to
  full).
- **SQL / XML / CSV / Excel providers** — external databases and files. File providers resolve
  paths under `/Files`.

**Flow: file import (CSV/XML/Excel → Dynamicweb/Ecom):**
1. `get_integration_providers`, then `get_integration_provider_parameters` for the file
   provider — identify the source-file/folder parameters.
2. If the source file doesn't exist in the archive yet, upload it to
   `/Files/Files/Integration` (the archive folder integration file providers read from) — pass
   the resulting virtual path to the provider's source parameter.
3. `create_integration_activity` with the file provider as source and Ecom/Dynamicweb as
   destination.
4. `get_integration_provider_schema` for both sides of the new activity, then
   `save_integration_activity_mapping` per table: map columns, mark the natural key (e.g.
   `ProductNumber`) `IsKey=true`.
5. `run_integration_activity` (confirm first), poll `get_integration_activity_status`, verify
   in `get_integration_activity_logs`.

**Flow: endpoint-driven ERP sync (e.g. Business Central OData):**
1. `save_integration_endpoint` — URL, collection, and inline authentication (OAuth S2S needs
   client id, tenant id, client secret). `test_integration_endpoint` before going further.
2. `create_integration_activity` with the OData provider as source (its endpoint parameter
   takes the endpoint id) and Ecom/Dynamicweb/User as destination; map with
   `save_integration_activity_mapping`.
3. Run once manually and verify, then `schedule_integration_activity` for the recurring sync.
4. Dependent activities (customers before orders, groups before products) must run in
   dependency order — schedule them accordingly.

**Flow: diagnose a failed run:**
1. `get_integration_activity_status` — still running? failed? when did it last succeed?
2. `get_integration_activity_logs` — the error lines usually name the offending table, column,
   or remote error; page back for context, or read the previous run's log to compare.
3. Typical causes: authentication expired (test the endpoint), schema drift (a mapped column
   no longer exists — re-check with `get_integration_provider_schema`), bad source data (see
   rules below), or the remote system rate-limiting.

**Rules:**
- Explicitly set IDs in imported data (ProductID etc.) may contain ONLY letters and digits —
  spaces, commas, dots, or special characters break the import.
- **Excel provider source path**: splitting the file across "Source folder" (folder path) +
  "Source file" (file name) — the split the parameter labels suggest — can fail validation
  with "Excel file '...' does not exist" even when the file is really there. If that happens,
  put the FULL virtual path (e.g. `/Files/Files/Integration/order_for_customer.xlsx`) in
  "Source file" and leave "Source folder" empty; re-validate before concluding the file is
  genuinely missing.
- Never claim a run succeeded from a queued result: the log is the evidence.
- `deleteRowsMissingFromSource` and "remove missing" options are destructive — enable only
  when the source is the complete truth for that table.
- After a product import, storefront lists driven by index queries show new products only
  after the repository index rebuilds — if products are "missing," check the index (see
  [dw-search-indexing](../dw-search-indexing)) before blaming the import.
- Do not guess provider parameter names or table/column names — read them with the provider
  tools; the save tools reject unknown names and list valid candidates.
- If `get_integration_provider_schema` comes back with zero tables for an *existing*
  activity's file-based source (CSV/XML/Excel) right after uploading or replacing that source
  file, don't conclude the schema is unreadable: call it with the activity id (not a
  reconstructed provider-type-name + parameters guess, which is exactly where the Excel path
  pitfall above bites) and retry once. `save_integration_activity_mapping` reads the same live
  schema at save time and can succeed even when a prior schema read looked empty.

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
