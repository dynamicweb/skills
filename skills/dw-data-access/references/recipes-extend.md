# Out-of-product recipes: Extend

This reference holds the out-of-product recipes for extend (providers, notification subscribers and
AddIns: the host restart an install owes, install-state probes, and the commands an AddIn adds):
Management API commands at `/admin/api/...`, host process operations, and direct SQL. The in-product
skills for this area are `dynamo: true` and carry no instruction on those surfaces, so they keep a
one-line pointer here instead of the recipe.

Every recipe names its surface in the repo convention: MCP tools `snake_case` in backticks,
Management API commands `PascalCase` in backticks with the route on first use in this file,
serializer operations by command or by layer and mode, and `SQL` labelled as such in a fenced `sql`
block. Every SQL recipe states three things inline: why the higher surfaces do not cover it, that
it is **local installs only**, and the cache flush or host restart it owes.

## Contents

- [Restart the host and probe an AddIn's install state](#restart-the-host-and-probe-an-addins-install-state)
- [StaticLinkManager requests](#staticlinkmanager-requests)
- [Register a scheduled task by `SQL`](#register-a-scheduled-task-by-sql)

## Restart the host and probe an AddIn's install state

In-product home: [dw-extend-providers](../../dw-extend-providers/SKILL.md)
(`addin-lifecycle.md` §2), which carries the stuck-state signature and the three-way response table.

**Surface: the host process.** After an AppStore install, the pipeline that registers the AddIn's
services has not run until the host process restarts. On a local development host that is a full
`dotnet run` cycle: stop the parent process, not only the child worker, because a bounce of the child
alone may not cold-start. On a hosted install the restart goes to whoever operates the host, since no
MCP tool and no Management API command restarts it. Confirm the restart in the host log: a
`Running pipeline: '<Package>.<Pipeline>'.` line.

**Surface: Management API.** Probe any command the AddIn adds, with bearer auth:

```
POST https://localhost:<PORT>/admin/api/<AddInCommand>
Authorization: Bearer <api-key>
Content-Type: application/json
{"Model":{}}
```

Read the response against the table in `addin-lifecycle.md` §2: `400 Unknown command` means not
installed, `500 TypeInitializationException ... No service for type` means installed and not
restarted, `200 {"status":"ok"}` means working. A hosted install runs the same call against
`https://<host>`.

- **Why the higher surfaces do not cover it**: no MCP tool restarts the host or calls an arbitrary
  AddIn command.
- **The debt it owes**: none; the restart is itself the fix.

## StaticLinkManager requests

In-product home: [dw-extend-providers](../../dw-extend-providers/SKILL.md)
(`addin-lifecycle.md` §3), which carries the settings shape, the save response and the
troubleshooting table.

**Surface: Management API**, available once the package is installed and the host has restarted:

```
GET  /admin/api/StaticLinkAll                                      -- paginated list of all links
GET  /admin/api/StaticLinkById?id=<int>                            -- single link by integer id
GET  /admin/api/StaticLinkByArgumentAndType?Type=<T>&Argument=<A>  -- lookup by (type,argument); idempotency checks
POST /admin/api/StaticLinkSave    body { Model: { Type, Argument, ... } }  -- create or update a link
POST /admin/api/StaticLinkDelete  body { Model: { Id: <int> } }            -- revoke a link
GET  /admin/api/StaticLinkSettings                                 -- AddIn-level config (template, expiration)
POST /admin/api/StaticLinkSettingsSave                             -- update AddIn-level config
```

Query parameter names are case-sensitive: `Type=Product` works, `type=Product` answers `500` with an
`Enum.Parse` failure.

- **Why the higher surfaces do not cover it**: no MCP tool reaches the static-link commands.
- **Hosted installs included**: these are API calls, not SQL.
- **The debt it owes**: none; read a `StaticLinkSave` back through `StaticLinkByArgumentAndType`.

## Register a scheduled task by `SQL`

In-product home: [dw-extend-scheduled-tasks](../../dw-extend-scheduled-tasks/SKILL.md)
(`scheduler-rows-and-runs.md`), which owns the whole row contract, the `TaskBegin` / `TaskNextRun`
semantics and the run bookkeeping.

**Surface: `SQL`, then Management API.** Registering a task by `SQL` is the zero-restart path when
the class is already deployed and no verb reaches the registration. **Local installs only**: on a
hosted install, register through `create_scheduled_task` or `TaskSave` and prove it from
`GET /Admin/Api/Tasks`. `TaskSave` is seen by the running app immediately and owes nothing, so it is
the first choice wherever it reaches.

The rules, and the why — the live rows do not reveal the constraints, so copying one field-by-field
fails on constraints and on defaults:

- **`TaskParentId` is `NULL`, never `0`.** The register is a two-level tree and the scheduler
  enumerates the **parent** list, so `0` means "child of task 0", which does not exist: the task
  never fires and **logs nothing at all**. A working row shows an empty cell in every viewer, and `0`
  is the natural `int` default, which is what makes this easy to copy in.
- **`TaskEnabled = 0` is the kill switch; a far-future next run is not.** Overdue tasks fire at
  **application start**, so a task left enabled with any real schedule column can fire the moment the
  pool restarts. To park a task and keep it out of the scheduler's arithmetic entirely, disable it
  **and** set every schedule column (`TaskMinute`, `TaskHour`, `TaskDay`, `TaskWday`) to `-1`.
- **`POST /Admin/Api/TaskRun` ignores `TaskEnabled` entirely.** So the shape for a destructive or
  environment-resetting task is: registered **disabled**, with a far-future `TaskBegin`, driven
  entirely through `TaskRun` — no enable/disable window in which a clock tick could fire it.
- **Column defaults are not `NULL`.** `TaskLastRun` is `NOT NULL` with no default (seed a sentinel);
  `TaskParam0..4`, `TaskTarget`, `TaskAssembly`, `TaskNamespace`, `TaskClass` and
  `TaskLastException` are **empty strings** on every live row. `TaskComment` is `nvarchar(255)` and
  SQL Server **refuses** rather than trims — rows written through the backend can be longer, because
  the backend truncates for you, so "match what is already there" is not a safe guide. With
  `TaskType = 0`, `TaskMinute` is an **interval in minutes**, not a minute of the hour, and there is
  no calendar-month schedule, so "monthly" is `43200`.
- **`TaskAddInSettings` holds LITERAL XML**, repeating the type name **without** the assembly on the
  root and on every child, while `TaskAddInTypeName` carries the assembly-qualified form. Escape only
  the parameter *value*: XML-escaping the whole document stores a string the add-in loader cannot
  parse, so the task exists, opens in admin, and does nothing.
- **The running scheduler does not re-read the table.** A row written or edited by `SQL` is invisible
  until the register is refreshed, so `TaskRun` answers `404 The task with id: N was not found` for a
  row that demonstrably exists. **The debt it owes:** one
  `POST /Admin/Api/CacheInformationRefresh {"CacheTypeName":"Dynamicweb.Scheduling.TaskService"}`;
  where the flush does not take, an app-pool recycle does.
- **Prove the registration from the task list, not from the INSERT.** `GET /Admin/Api/Tasks` must
  return the task by name — mind the **ten-row default page size**, which is how a freshly added task
  reads as absent on a solution that already has ten.

**The slot lives in `TaskBegin`, not `TaskNextRun`.** The scheduler computes the next run as
`TaskBegin + n x TaskMinute`; `TaskNextRun` is a derived output column that happens to be writable,
so a hand-set value survives exactly until the first recomputation. `TaskStartFromLastRun = 0`
anchors on `TaskBegin`'s clock time, `1` (the shipped default) drifts from the last run's end. Those
semantics stay here and in the in-product reference; no script decides them for you.

**Arbitrary SQL through a scheduled-task add-in is a banned path** and no shipped script registers
one. Where a statement has to run, run it where it is visible and dry-runnable:
[`../scripts/Invoke-DwSqlThenFlush.ps1`](../scripts/Invoke-DwSqlThenFlush.ps1).

**The script:** [`../scripts/Register-DwScheduledTask.ps1`](../scripts/Register-DwScheduledTask.ps1)
writes the row with every rule above enforced, flushes `Dynamicweb.Scheduling.TaskService`, and
verifies from the paged task list. Dry run by default; it refuses an add-in type name that names a
RunSql add-in.

```powershell
pwsh -NoProfile -File scripts/Register-DwScheduledTask.ps1 -TaskName 'Nightly orders export' -AddInTypeName 'Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn, Dynamicweb.DataIntegration' -Parameter @{ Activity = 'Orders export' } -Apply
```

- **Why the higher surfaces do not cover it**: `TaskSave` and `create_scheduled_task` reach most
  registrations; this recipe is for the cases they do not, and for a bulk register.
- **Local installs only** — a hosted install has no `SQL` surface.
- **The debt it owes**: the `Dynamicweb.Scheduling.TaskService` flush above, before claiming the
  registration succeeded.
