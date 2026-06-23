---
name: dw-extend-scheduled-tasks
type: knowledge
group: extend
description: Create and manage scheduled tasks in Dynamicweb 10 including RunSqlScheduledTaskAddIn. Triggers: scheduled tasks, background jobs, RunSqlScheduledTaskAddIn. Non-triggers: notification handling -> dw-extend-providers; MCP tool authoring -> dw-extend-mcp-tools.
---

# Scheduled Tasks

## How Scheduled Tasks Work

Scheduled tasks in Dynamicweb 10 are **Add-Ins** — classes that inherit `BaseScheduledTaskAddIn` and are discovered via reflection. The admin UI reads available add-in types at runtime and lets users configure task schedules, parameters, and logging.

- Each task runs in its own thread on the configured schedule
- A task returns `true` (success) or `false` (failure)
- Logs write to the Log panel in the task editor and to `/Files/System/Log/`
- Tasks are stored in the `dbo.ScheduledTask` table; settings are serialized as XML

## Implementing a Scheduled Task

```csharp
using Dynamicweb.Extensibility.AddIns;
using Dynamicweb.Logging;
using Dynamicweb.Scheduling;

[AddInName("MyCompany.MyTask")]
[AddInLabel("My Scheduled Task")]
[AddInDescription("Does something on a recurring basis.")]
public class MyScheduledTask : BaseScheduledTaskAddIn
{
    [AddInParameter("Setting Name")]
    [AddInParameterEditor(typeof(TextParameterEditor), "")]
    public string SettingName { get; set; } = "";

    [AddInParameter("Enable Feature")]
    [AddInParameterEditor(typeof(YesNoParameterEditor), "")]
    public bool EnableFeature { get; set; }

    public override bool Run()
    {
        ILogger logger = LogManager.Current.GetLogger("ScheduledTasks", Task?.LogFileName ?? GetType().Name);
        try
        {
            logger.Log(LogLevel.Informational, "MyTask started.");
            // Do work here
            logger.Log(LogLevel.Informational, $"MyTask completed. Setting: {SettingName}");
            return true;
        }
        catch (Exception ex)
        {
            logger.Log(LogLevel.Error, "MyTask failed.", ex);
            return false;
        }
    }
}
```

## The `Task` Property

Inside `Run()`, `this.Task` provides access to the runtime task configuration:

| Property | Type | Description |
|----------|------|-------------|
| `Task.ID` | `int` | Database ID of this task instance |
| `Task.Name` | `string` | Human-readable name configured in admin |
| `Task.LogFileName` | `string` | Log file path prefix for this task |
| `Task.IsEnabled` | `bool` | Whether the task is enabled |
| `Task.LastRun` | `DateTime` | Timestamp of previous execution |
| `Task.NextRun` | `DateTime` | Scheduled next execution |
| `Task.TaskIntervalType` | enum | Minute, Hour, Day, Week, Month, OneTime |
| `Task.TaskIntervalValue` | `int` | Interval count (e.g., 6 hours) |

## Configuring in Admin

Admin path: **Settings > System > Scheduled Tasks**

1. Click **New Scheduled Task**
2. Select **Task Type** (dropdown — lists all discovered `BaseScheduledTaskAddIn` subclasses by `[AddInLabel]`)
3. Configure the **schedule**: interval type + value (e.g., "Every 1 Hour")
4. Fill in any **parameters** (those declared with `[AddInParameter]`)
5. Click **Save**. The task starts running at the next scheduled interval.

**Run immediately:** Context menu → **Run now** — runs the task once regardless of schedule.

**Log viewer:** Select a task → view the log output inline in the admin or at **Settings > System > Log**.

## Logging Pattern

Always use `Task?.LogFileName` for the log file name so the log entry appears in the correct task's log panel:

```csharp
ILogger logger = LogManager.Current.GetLogger("ScheduledTasks", Task?.LogFileName ?? GetType().Name);
```

Log levels: `LogLevel.Informational`, `LogLevel.Warning`, `LogLevel.Error`, `LogLevel.Debug`.

## AddIn Parameter Editors

| Editor type | Renders as | Options example |
|------------|-----------|----------------|
| `TextParameterEditor` | Text input | `""` |
| `TextParameterEditor` | Textarea | `"TextArea=True;style=height:80px;"` |
| `YesNoParameterEditor` | Checkbox | `""` |
| `IntegerParameterEditor` | Number field | `""` |
| `DropDownParameterEditor` | Select list | `"first=None@;second=Option1@value1;third=Option2@value2"` |

## Built-in Task Types

These ship with the platform and are available without custom code:

| Task type | Purpose |
|-----------|---------|
| `RunSqlScheduledTaskAddIn` | Run an arbitrary SQL statement on a schedule |
| `Build repository index` | Rebuild a Lucene search index |
| `Build Ecommerce Assortment Items` | Rebuild assortment caches |
| `CleanupScheduledTask` | Purge old log entries, temp files |
| `DataIntegration.RunIntegrationActivityAddIn` | Run an Integration Framework activity |

## Disabling All Tasks (Safe Mode)

Before upgrading or during a deployment, disable all tasks in SQL:

```sql
UPDATE dbo.ScheduledTask SET TaskEnabled = 0
```

Re-enable individually via admin after verifying each task is still valid.

## Pitfalls

**`Context.Current` is null inside a scheduled task** — tasks run outside an HTTP request. Use static service facades or `DependencyResolver` for data access, not request context. See [dw-data-access](../dw-data-access).

**`[AddInName]` must be unique** — if two task classes share the same name, one silently shadows the other.

**Task XML parameter storage** — parameters are serialized to XML in the DB. Changing property names after deployment loses the configured values for existing tasks.

**Long-running tasks** — Dynamicweb does not have a built-in timeout, but long tasks can overlap with the next scheduled interval. Use a flag or DB record to detect if a previous run is still active.

**Assembly loading** — the assembly containing your task must be referenced from the host project so it is loaded at startup and discovered by the AddIn scanner.

## Next Steps

- **Querying data inside a task?** See [dw-data-access](../dw-data-access)
- **Calling Dynamicweb service APIs?** See [dw-extend-csharp-api](../dw-extend-csharp-api)
- **Need to react to events instead of polling?** See [dw-extend-providers](../dw-extend-providers)
