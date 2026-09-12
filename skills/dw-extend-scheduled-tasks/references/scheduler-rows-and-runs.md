# The scheduler: row contract, slots, on-demand runs, and where the history lives

Everything about a `ScheduledTask` row that the admin UI hides and the column names mislead
about. Reached from [SKILL.md](../SKILL.md); read that first for the add-in class itself.

Measured on DW 10.28.x with the platform scheduler in-process (no OS task, no external runner).

## Contents

- [Choosing the add-in: what actually runs your work](#choosing-the-add-in-what-actually-runs-your-work)
- [Clearing an indexed PIM field from a task](#clearing-an-indexed-pim-field-from-a-task)
- [The ScheduledTask row contract](#the-scheduledtask-row-contract)
- [The slot lives in TaskBegin, not TaskNextRun](#the-slot-lives-in-taskbegin-not-tasknextrun)
- [Running a task on demand](#running-a-task-on-demand)
- [TaskCheckPrevious is a co-queued failure gate](#taskcheckprevious-is-a-co-queued-failure-gate)
- [Where the run history lives](#where-the-run-history-lives)

## Choosing the add-in: what actually runs your work

| Work | Add-in | Surface notes |
|---|---|---|
| Anything a storefront or the backend reads (PIM fields, orders, users, prices) | your own `BaseScheduledTaskAddIn` in C# | Calls the domain services, so caches invalidate and notifications fire. Costs a build and a host restart to deploy. |
| Row movement between tables or systems with no C# | `Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn` over an Integration activity | Runs a saved activity; logs row counts per table and ends `Job succeeded.` Needs no build and no restart. |
| Rebuilding an index | `Dynamicweb.Indexing.ScheduledTaskAddIns.RepositoryScheduledTaskAddIn` | Takes repository, index and build name — see [dw-search-indexing](../../dw-search-indexing/SKILL.md). |
| Arbitrary SQL against a table nothing caches | `RunSqlScheduledTaskAddIn` — **its run result is not evidence of effect** | See below. |

**Never treat `RunSqlScheduledTaskAddIn`'s run result as evidence that its SQL ran. Assert the
effect independently** — the rows it should have written — or use a `JobScheduledTaskAddIn` activity
instead, whose own log reports the rows it moved per table.

On a 10.28.x build the add-in was measured binding its parameters, firing, logging
`Method ...RunSqlScheduledTaskAddIn, Dynamicweb.Core.Run returned: True` and setting `TaskLastResult`
`True` with an empty `TaskLastException` — while executing **no SQL at all**. Three attempts: the
real `MERGE`, a bare single-row `INSERT` into an empty table, and the same `INSERT` with the settings
`addin=` attribute written as the `[AddInName]` value instead of the type name. The identical
statement run by hand wrote its rows, and a `JobScheduledTaskAddIn` activity wrote to the same table
through the same account seconds later, so the account, the connection and the table were all sound.
The add-in demonstrably reads its own configuration and knows how to fail — a malformed settings blob
sets `TaskLastResult False` with an `XmlException` from
`ConfigurableAddIn.LoadParametersFromXml` — it simply never reports having run nothing.

Other builds have been measured executing correctly, so the honest rule is the verification one
above rather than "this add-in never runs". The consequence is the same either way: a success signal
and a silent no-op are indistinguishable from the task's own result, which makes the add-in unusable
as its own proof — including for the assertion-SQL diagnostic (`IF (<condition>) RAISERROR(...)`,
reading `Success` as the assertion passing), whose silent-failure mode is exactly the outcome it is
used to rule out.

**Prefer `JobScheduledTaskAddIn` over a `SqlProvider` source and destination for SQL-shaped
background work** (no C#, no restart, and a row count in the log). Where a build and a restart are
available, a `BaseScheduledTaskAddIn` in C# is stronger still, because it can call the domain
services that a raw statement cannot.

## Clearing an indexed PIM field from a task

Raw SQL against a table a storefront reads is two caches short: `ProductService` serves a
read-through copy of the product, and the Lucene index holds a third copy. The recipe that makes a
nightly field change visible everywhere, all public API:

```csharp
public sealed class PriceNoticeExpiryTaskAddIn : Dynamicweb.Scheduling.BaseScheduledTaskAddIn
{
    public override bool Run()
    {
        // SELECT only: global fields are real columns on EcomProducts, so the scan is cheap.
        //   SELECT ProductId, ProductVariantId, ProductLanguageId FROM EcomProducts
        //    WHERE PriceIncreaseEffectiveDate < CAST(GETDATE() AS date)
        foreach (var key in FindExpired())
        {
            var p = Services.Products.GetProductById(key.ProductId, key.VariantId, key.LanguageId);
            Services.Products.SetProductFieldValue(p, "PriceIncreaseEffectiveDate", null);
            Services.Products.SetProductFieldValue(p, "PriceIncreaseNoticeText", string.Empty);
            Services.Products.Save(p);
        }
        if (cleared > 0)
            Dynamicweb.Indexing.IndexHelper.BuildIndexInstances("Products", "Products.index", "Partial");
        return true;
    }
}
```

Three things that are not guessable:

- `SetProductFieldValue` takes the field **system name** and an `object`: `null` clears a date,
  `string.Empty` clears a text.
- `IndexHelper.BuildIndexInstances(repository, indexName, buildName)` is exactly what
  `RepositoryScheduledTaskAddIn` calls. The repository/index pair is the solution's
  `RepositoryIndex` setting **split at the first dot** (`Products.Products.index` →
  `"Products"`, `"Products.index"`), and the build name is the `<Build Name="...">` element in
  the `.index` file (commonly `Full` and `Partial`, where `Partial` carries `Action="Update"`).
- Declare **no** `[AddInParameter]`s on a task whose configuration must survive a rename:
  parameters serialise into `TaskAddInSettings` by property name, so a parameterless add-in cannot
  lose its configuration to a later refactor.

## The ScheduledTask row contract

Registering a task by SQL is the zero-restart path when the class is already deployed. The live
rows do not reveal the constraints, so copying one field-by-field fails on constraints and on
defaults:

| Column | Rule |
|---|---|
| `TaskParentId` | **`NULL`, never `0`.** The register is a two-level tree — `Dynamicweb.Scheduling.TaskService` exposes `GetParentTasks()` alongside `GetTasksByParentId(int)` and the scheduler enumerates the **parent** list. `0` means "child of task 0", which does not exist, so the task never fires and **logs nothing at all**: `TaskLastRun` stays at its sentinel and `TaskLastResult` stays `NULL` through every tick. A working row shows an empty cell in every viewer, and `0` is the natural `int` default, which is what makes this easy to copy in. |
| `TaskComment` | `nvarchar(255)`, and SQL Server **refuses** rather than trims: `String or binary data would be truncated`. Rows written through the backend can be longer, because the backend truncates for you — so "match what is already there" is not a safe guide. |
| `TaskLastRun` | `NOT NULL` with no default. Seed a sentinel (`'1900-01-01'`; shipped rows use `'2000-01-01'`). |
| `TaskParam0..4`, `TaskTarget`, `TaskAssembly`, `TaskNamespace`, `TaskClass`, `TaskAddInSettings`, `TaskLastException` | **empty strings** on every live row, not `NULL`. A `NULL`-heavy `INSERT` is wrong on all of them. |
| `TaskMinute` (with `TaskType = 0`) | An **interval in minutes**, not a minute of the hour. Shipped rows read `5`, `60`, `1440`. There is no calendar-month schedule, so "monthly" is `43200`. |
| `TaskAddInTypeName` | Assembly-qualified: `Namespace.Type, AssemblyName`. |
| `TaskAddInSettings` | Repeats the type name **without** the assembly, on the root and on every child: `<Parameters addin="Ns.Type"><Parameter addin="Ns.Type" name="X" value="Y" /></Parameters>`. |

**The running scheduler does not re-read the table.** A row written or edited by `SQL` — a new task,
or a schedule change on a task that has run correctly for a week — is invisible until the register
is refreshed, so `POST /Admin/Api/TaskRun` answers `404 The task with id: N was not found` for a row
that demonstrably exists. Two ways to refresh it, in order:

1. **Register through `TaskSave`** where the verb reaches what you need. The running app sees a
   `TaskSave` immediately and nothing else is owed.
2. **Flush the register** after a `SQL` write:
   `POST /Admin/Api/CacheInformationRefresh {"CacheTypeName":"Dynamicweb.Scheduling.TaskService"}`.
   The task **list** is a service cache, not an immutable app-start snapshot: a corrected row fired
   on the very next tick after this flush, with no host restart. Where the flush does not take, an
   app-pool recycle does. Only the per-task run bookkeeping behaves as though it were snapshotted.

Either way, **prove the registration from the task list rather than from the INSERT** —
`GET /Admin/Api/Tasks` must return the task by name; mind the ten-row default page size, which is
how a freshly added task reads as absent on a solution that already has ten.

**`TaskEnabled = 0` is the kill switch; a far-future `TaskNextRun` is not.** Overdue tasks fire at
application start, so a task left enabled with any real schedule column can fire the moment the pool
restarts, whatever `TaskNextRun` says — and `TaskNextRun` is derived anyway (see below). To park a
task, disable it; to park it and still keep it out of the scheduler's arithmetic entirely, set every
schedule column to `-1` as well.

Surface note: `ScheduledTask` and `ScheduledTaskFolder` carry no MCP tool and no Management API save
verb, so a programmatic registration is `SQL` and is **local-install only**; it owes the
`TaskService` flush above. On a hosted install, register the task through the admin UI instead.

One shipped add-in worth correcting while you are here: the saved-card expiration task is
`Dynamicweb.Ecommerce.Cart.ScheduledTaskAddIns.PaymentCardExpirationNotificationScheduledTaskAddIn,
Dynamicweb.Ecommerce` — the **`Cart`** namespace, not `Orders.ScheduledTaskAddIns`. Its
`EmailTemplate` parameter is `[Required]` and resolves **by file name inside a fixed folder**,
`/Templates/eCom/ScheduledTasks/PaymentCardExpiration`, which does not exist on a Swift solution
(there is no `eCom` folder at the `Templates` root at all — the Swift templates live under
`Templates/Designs/Swift-v2/eCom`), so the whole folder chain has to be created first. The template
is a ViewModel template over `Dynamicweb.Ecommerce.Frontend.PaymentCardExpirationEmailViewModel`.

## The slot lives in TaskBegin, not TaskNextRun

The scheduler computes the next run as **`TaskBegin` + n × `TaskMinute`**. `TaskNextRun` is a
derived output column that happens to be writable, so a hand-set value survives exactly until the
first recomputation and is then overwritten with `TaskBegin`'s clock time.

**Set `TaskBegin` to the slot you want** — any date, the right time of day — and let `TaskNextRun`
be computed. Registering several tasks with `TaskBegin = GETDATE()` and hand-computed `TaskNextRun`
values puts a latent defect in every one of them: the rows read back correctly, they fire at the
hand-set times, and an audit reading `TaskNextRun` confirms the plan — until the first recomputation
moves them all to whatever second the inserts ran. Tasks inserted seconds apart share a `TaskBegin`
to the second, so a staggered chain collapses into a simultaneous one, silently, with
`TaskLastResult True` on every row.

`TaskStartFromLastRun` decides which clock survives:

- **`0` — anchor.** `TaskNextRun` recomputes from `TaskBegin`'s fixed clock time, so the slot never
  moves regardless of when or how often the task actually ran. Use this for anything that must hold
  a nightly slot, with `TaskBegin` anchored to a past timestamp at the target time of day.
- **`1` — drift, and the shipped default on every stock row.** `TaskNextRun` is computed as
  `lastRunEnd + interval`, so the slot walks forward by each run's duration and any off-schedule run
  drags the next scheduled one with it.

With `TaskStartFromLastRun = 0` and `TaskBegin` in the past, a one-off early run can be pulled by
writing `TaskNextRun` alone; the daily anchor survives it untouched.

## Running a task on demand

`POST /Admin/Api/TaskRun {"TaskId": <n>}` is the run-now surface. Two facts about it:

- **It ignores `TaskEnabled` entirely.** It resolves the task, invokes the add-in and stamps
  `TaskLastRun` / `TaskLastResult` exactly as an unattended fire would, and the row stays disabled
  throughout — measured across ten calls on three disabled tasks, each advancing `TaskLastRun` with
  result `True` and an empty exception. `TaskEnabled` governs the scheduler's own polling and
  nothing else. So the right shape for a destructive or environment-resetting task is to **register
  it disabled with a far-future `TaskBegin` and drive it entirely through `TaskRun`** — no
  enable/disable window in which a clock tick could fire it, and, because `TaskBegin` is already in
  the future, an on-demand run has no schedule side effect either.
- **It recomputes the schedule**, per the section above: an on-demand run of a task whose
  `TaskBegin` is in the past re-plans it onto `TaskBegin`'s clock time. Demonstrating a task
  therefore moves it, unless `TaskBegin` already carries the intended slot.

`Task.GetActivationUrl` is not a second run-now route. It still formats the DW9-era path
`{0}/Admin/Public/WebServices/IntegrationV2/ScheduledTaskRunner.aspx?taskId={1}&token={2}`, and DW10
mounts no handler there: the request reaches the application and falls through to the platform's own
branded 404 page with or without a valid token. `TaskRun` is the only headless trigger.

## TaskCheckPrevious is a co-queued failure gate

The column name reads like an overlap guard. It is not one, and **there is no overlap guard**.

- **"Previous" means the previous task in the co-queued `TaskSort` order**, not the row's own
  previous run and not the previous task by id. The admin label is "Run if previous task executed
  successfully", and the documented recipe is: give every task in the sequence the **same begin
  time** so they queue together, order them with `TaskSort`, then set the flag on each task after
  the first.
- **A flagged task with no queued predecessor runs normally.** Measured on a task with `TaskSort 0`
  and no other task sharing its begin time: the flag was set by a one-column `UPDATE` plus a
  `TaskService` flush, and the next unattended tick fired with `TaskLastResult True` and an empty
  exception, with the same three-line log shape as an unflagged control in the same window. Setting
  the flag on a solution whose tasks all have distinct begin times is therefore a statement of
  intent, safe to make.
- **A gated skip is never logged.** Four days of task logs on a solution carrying the flag contain
  no skip line of any kind, so an absent run and a clean run are indistinguishable in the task log.

For a task whose next tick can arrive while its own previous run is still in flight, carry your own
in-flight flag in a row you own.

## Where the run history lives

**There is no `ScheduledTaskLog` table** — `OBJECT_ID('ScheduledTaskLog')` is `NULL`. The history is
on disk, under `Files/System/Log/ScheduledTasks`: one file per task execution, named
`<task name><timestamp>_<taskId>.log`, plus **one rollup per day**. Read the daily rollup first: it
is the only file that aggregates `ERROR` lines across tasks.

Reasoning about task reliability from the database reaches the opposite of the truth, and the
reasoning is sound — it is the premise that is missing. `TaskLastException` is empty and
`TaskLastEventId` is `0` on every row of a solution that has never thrown inside a task, which is
indistinguishable from "this platform records no exceptions". On one solution the folder held 933
files and eight `ERROR` lines that nothing else on the build had ever surfaced, including a SQL
login timeout that killed a task execution outright.

Two more things about that stream:

- **A per-run log is three lines** — `task execution started`, `Method <addin>.Run returned: True`,
  `task execution finished` — with no row counts. Row counts for an Integration activity live
  separately, in `Files/System/Log/DataIntegration/<Activity><timestamp>_<taskId>.log`, ending
  `Job succeeded.`
- **The in-process `KeepAliveService` logs into the same stream under the same `ScheduledTasks`
  category**, so its failures read as task failures until you read the message. Its presence is also
  easy to miss from the other direction: looking for an OS scheduled task and finding none does not
  mean the solution has no keep-alive.
