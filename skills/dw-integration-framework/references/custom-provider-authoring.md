# Building a custom Integration Framework provider

## Contents

- [Class skeleton](#class-skeleton)
- [ISource: schema and reader](#isource--schema-and-reader)
- [ISourceReader](#isourcereader)
- [IDestinationWriter](#idestinationwriter)
- [Custom ScriptTypeProvider](#custom-scripttypeprovider)
- [Authoring pitfalls](#authoring-pitfalls)

> C# authoring for a provider the shipped set does not cover. Reach for it only after
> [`provider-behaviour.md`](provider-behaviour.md) shows no shipped provider fits: a shipped
> provider plus a source XSLT covers most of what looks like it needs code, and a custom class
> costs a compile and a deploy. Loaded from the SKILL.md "Where to find things" row.


Providers are C# classes that implement `ISource`, `IDestination`, or both. All providers inherit from `BaseProvider` (`Dynamicweb.DataIntegration.BaseProvider`).

## Class Skeleton

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

## ISource — Schema and Reader

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

## ISourceReader

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

## IDestinationWriter

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

## Custom ScriptTypeProvider

```csharp
using Dynamicweb.DataIntegration.Providers.ScriptTypeProvider;

[AddInLabel("URL Encode")]
public class UrlEncodeScriptProvider : ScriptTypeProvider<string>
{
    protected override string GetValueTyped(object? input)
        => Uri.EscapeDataString(input?.ToString() ?? "");
}
```

## Authoring pitfalls

**`RunJob` is only called when the provider is the Destination** — the framework calls `LoadSettings` on the Source, then `RunJob` on the Destination. If your provider is used as both, implement both correctly.

**`ReplaceMappingConditionalsWithValuesFromRequest(job)` must be called in `RunJob`** — it replaces `@Request()` / `@Session()` / `@User()` tokens in conditional expressions. Without the call the tokens reach the conditional unreplaced.

**Schema changes after first run** — a provider's schema is snapshotted into the job file, so saved column mappings can reference columns that no longer exist. `OverwriteSourceSchemaToOriginal()` / `OverwriteDestinationSchemaToOriginal()` refresh it. The reader-facing consequences of that snapshot are in [`job-file-format.md`](job-file-format.md#the-schema-block-is-a-snapshot-not-a-live-read).

**Make the writer's own failure legible.** The shipped providers report a missing key, a wrong column element or a suppressed row as an exception from deep inside a writer, which sends the reader to the wrong end of the job. A custom writer that names the mapping, the table and the column it refused costs nothing and is the difference between a five-minute fix and a bisect.
