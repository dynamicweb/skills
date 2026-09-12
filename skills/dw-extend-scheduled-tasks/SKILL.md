---
name: dw-extend-scheduled-tasks
type: knowledge
group: extend
mcp: none
dynamo: false
description: 'Create and manage scheduled tasks in Dynamicweb 10 including RunSqlScheduledTaskAddIn. Triggers: scheduled tasks, background jobs, RunSqlScheduledTaskAddIn. Non-triggers: notification handling -> dw-extend-providers; MCP tool authoring -> dw-extend-mcp-tools.'
---

# Scheduled Tasks

## Deep reference

| Topic | Where |
|---|---|
| The scheduler itself — which add-in to use for which work (and why `RunSqlScheduledTaskAddIn` is inert on 10.28.x), the `ScheduledTask` row contract for a SQL registration (`TaskParentId` NULL, `TaskMinute` as an interval, the settings XML shape), why `TaskBegin` and not `TaskNextRun` is the slot, running a task on demand with `TaskRun`, what `TaskCheckPrevious` really gates, and where the run history lives on disk | [`references/scheduler-rows-and-runs.md`](references/scheduler-rows-and-runs.md) |

## How Scheduled Tasks Work

Scheduled tasks in Dynamicweb 10 are **Add-Ins** — classes that inherit `BaseScheduledTaskAddIn` and are discovered via reflection. The admin UI reads available add-in types at runtime and lets users configure task schedules, parameters, and logging.

- Each task runs in its own thread on the configured schedule
- A task returns `true` (success) or `false` (failure)
- Logs write to the Log panel in the task editor and to `Files/System/Log/ScheduledTasks` — one file per execution plus a daily rollup. There is no `ScheduledTaskLog` table; see [`references/scheduler-rows-and-runs.md`](references/scheduler-rows-and-runs.md)
- Tasks are stored in the `dbo.ScheduledTask` table; settings are serialized as XML. **The running scheduler does not re-read the table** — a row written or edited by SQL is invisible until the register is refreshed (`TaskSave` is seen immediately; a SQL write needs a `Dynamicweb.Scheduling.TaskService` flush, else a recycle). Overdue tasks fire at application start, so `TaskEnabled = 0` is the kill switch and a far-future next run is not

## Implementing a Scheduled Task

```csharp
using Dynamicweb.Extensibility.AddIns;
using Dynamicweb.Scheduling;

// SDK-style projects default to ImplicitUsings=enable, which puts
// Microsoft.Extensions.Logging's ILogger in global scope. Alias both types to the
// Dynamicweb ones explicitly, in every file that logs, rather than turning
// ImplicitUsings off project-wide.
using DwLogger = Dynamicweb.Logging.ILogger;
using DwLogLevel = Dynamicweb.Logging.LogLevel;
using LogManager = Dynamicweb.Logging.LogManager;

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
        DwLogger logger = LogManager.Current.GetLogger("ScheduledTasks", Task?.LogFileName ?? GetType().Name);
        try
        {
            logger.Log(DwLogLevel.Information, "MyTask started.");
            // Do work here
            logger.Log(DwLogLevel.Information, $"MyTask completed. Setting: {SettingName}");
            return true;
        }
        catch (Exception ex)
        {
            logger.Log(DwLogLevel.Error, "MyTask failed.", ex);
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
| `Task.NextRun` | `DateTime` | Scheduled next execution — **derived** from `TaskBegin` + n × interval, not the source of the slot. Writing it is a one-shot; see [`references/scheduler-rows-and-runs.md`](references/scheduler-rows-and-runs.md) |
| `Task.TaskIntervalType` | enum | Minute, Hour, Day, Week, Month, OneTime |
| `Task.TaskIntervalValue` | `int` | Interval count (e.g., 6 hours) |

## Configuring in Admin

Admin path: **Settings > System > Scheduled Tasks**

1. Click **New Scheduled Task**
2. Select **Task Type** (dropdown — lists all discovered `BaseScheduledTaskAddIn` subclasses by `[AddInLabel]`)
3. Configure the **schedule**: interval type + value (e.g., "Every 1 Hour")
4. Fill in any **parameters** (those declared with `[AddInParameter]`)
5. Click **Save**. The task starts running at the next scheduled interval.

**Run immediately:** Context menu → **Run now**, or headlessly `POST /Admin/Api/TaskRun {"TaskId": <n>}`. Both run the task once regardless of schedule **and regardless of `TaskEnabled`** — which makes "registered disabled, driven only by `TaskRun`" the safe shape for a destructive or resetting job. A run-now also recomputes the next run from `TaskBegin`; both facts are in [`references/scheduler-rows-and-runs.md`](references/scheduler-rows-and-runs.md).

**Log viewer:** Select a task → view the log output inline in the admin or at **Settings > System > Log**.

## Logging Pattern

Always use `Task?.LogFileName` for the log file name so the log entry appears in the correct task's log panel:

```csharp
DwLogger logger = LogManager.Current.GetLogger("ScheduledTasks", Task?.LogFileName ?? GetType().Name);
```

`Dynamicweb.Logging.LogLevel`'s member set is `Trace`, `Debug`, **`Information`**, `Warning`,
`Error`, `Fatal`, `Off`. Spell the informational level `Information` — there is no `Informational`
member, and a file that also has `Microsoft.Extensions.Logging` in scope needs the explicit
`DwLogger` / `DwLogLevel` aliases shown above or both type names are ambiguous.

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
| `RunSqlScheduledTaskAddIn` | Runs an arbitrary SQL statement on a schedule — but **its run result is not evidence its SQL ran**: on a 10.28.x build it bound its parameters, logged `Run returned: True` and wrote nothing. Assert the effect independently, or prefer `JobScheduledTaskAddIn` (below), whose log counts rows; see [`references/scheduler-rows-and-runs.md`](references/scheduler-rows-and-runs.md) |
| `Dynamicweb.Indexing.ScheduledTaskAddIns.RepositoryScheduledTaskAddIn` | Rebuild a Lucene search index (repository + index + build name) |
| `Build Ecommerce Assortment Items` | Rebuild assortment caches |
| `CleanupScheduledTask` | Purge old log entries, temp files |
| `Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn` | Run an Integration Framework activity — the working no-C# route for row movement, including SQL-to-SQL through a `SqlProvider` pair |

## Disabling All Tasks (Safe Mode)

Before upgrading or during a deployment, disable all tasks in SQL:

```sql
UPDATE dbo.ScheduledTask SET TaskEnabled = 0
```

Flush `Dynamicweb.Scheduling.TaskService` afterwards (`POST /Admin/Api/CacheInformationRefresh {"CacheTypeName":"Dynamicweb.Scheduling.TaskService"}`) so the scheduler picks the change up without a restart — the running scheduler does not otherwise re-read the table — and re-enable individually via admin after verifying each task is still valid.

`TaskEnabled = 0` is the switch that matters: it stops the scheduler polling the task, including the pass at application start that fires every overdue task. It does **not** stop a `TaskRun` call or the admin's Run now, which is what makes a disabled row the safe home for a destructive job.

## Pitfalls

**Never treat `RunSqlScheduledTaskAddIn`'s run result as evidence of effect — assert the effect independently.** On a 10.28.x build it bound its parameters, flipped `TaskLastResult` to `True`, left `TaskLastException` empty, and left the target table untouched, down to a bare single-row `INSERT` into an empty table, with a hand-run control and a `JobScheduledTaskAddIn` activity both writing through the same account. Other builds execute correctly, so the rule is verification rather than avoidance: a success signal and a silent no-op are indistinguishable from the task's own result, which also rules the add-in out as a read-verification channel (an `IF ... RAISERROR` assertion passes identically when nothing ran). Prefer `JobScheduledTaskAddIn` over an Integration activity, whose log counts the rows it moved, or your own `BaseScheduledTaskAddIn` where a build and a restart are available; the measurement is in [`references/scheduler-rows-and-runs.md`](references/scheduler-rows-and-runs.md).

> **Content-editing scope guard.** A scheduled task is not a route around a write surface. Take the highest rung of the action ladder that reaches the operation ([dw-data-access](../dw-data-access) owns it): MCP tools first, then the Management API — the admin UI is a SPA over `/Admin/Api`, so if the UI can do it an endpoint exists: capture the SPA's network call and replay it, and file a learning where a surface genuinely seems missing. A task that has to touch a table a storefront reads goes through the domain services in C#, not through a statement; the worked recipe is in [`references/scheduler-rows-and-runs.md`](references/scheduler-rows-and-runs.md).

**`Context.Current` is null inside a scheduled task** — tasks run outside an HTTP request. Use static service facades or `DependencyResolver` for data access, not request context. See [dw-data-access](../dw-data-access).

**`[AddInName]` must be unique** — if two task classes share the same name, one silently shadows the other.

**Task XML parameter storage** — parameters are serialized to XML in the DB. Changing property names after deployment loses the configured values for existing tasks.

**Long-running tasks** — Dynamicweb has no built-in timeout and **no overlap guard**, so a long run can be re-entered at the next tick. Carry your own in-flight flag in a row you own. `TaskCheckPrevious` does not do this: it gates on the previous task in the co-queued `TaskSort` order, not on the row's own previous run — see [`references/scheduler-rows-and-runs.md`](references/scheduler-rows-and-runs.md).

**Deploying the assembly swaps a loaded DLL** — the order is app-pool stop, copy the `.dll` (and `.pdb`), app-pool start, never a recycle, because a draining worker keeps `bin/*.dll` locked. The full deploy loop, including what to check afterwards, is in [dw-setup-cli `addin-install.md`](../dw-setup-cli/references/addin-install.md) ("Copying a host assembly onto a self-hosted IIS install").

**Assembly loading** — the assembly containing your task must be referenced from the host project so it is loaded at startup and discovered by the AddIn scanner.

## Next Steps

- **Querying data inside a task?** See [dw-data-access](../dw-data-access)
- **Calling Dynamicweb service APIs?** See [dw-extend-csharp-api](../dw-extend-csharp-api)
- **Need to react to events instead of polling?** See [dw-extend-providers](../dw-extend-providers)
