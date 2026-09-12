# mock-deltas.md

## Contents

- [The mental model](#the-mental-model)
- [When to use this flavor](#when-to-use-this-flavor)
- [Three ways to execute the mock](#three-ways-to-execute-the-mock)
- [The recipe](#the-recipe)
- [Option 3 — DB-staged plus a real Integration Framework activity](#option-3--db-staged-plus-a-real-integration-framework-activity)
- [Do not](#do-not)
- [Cross-references](#cross-references)

> Canonical recipe for mocking an ERP without a live tenant: the demo data starts in the **post-delta state**, staged directly in the database, with a single scheduled task to reset between demos. Loaded from `dw-demo-erp/SKILL.md` "Where to find things". Use when the demo handover doesn't include BC tenant access.

## The mental model

There is **no live wire**. There is no file polling daemon, no JSON inbox, no human firing deltas during the demo. Instead:

- The DB is pre-staged into the **post-BC-sync state** — every value that BC would have written (price, stock, reorder, lifecycle state, etc.) is already in `EcomProducts` as if the delta arrived overnight.
- The demo narrates *"BC sent us this; look at the result."* Evidence is the data, the action-rule definition, and the email template — not a live trigger.
- **One** scheduled task (Settings → System → Scheduled tasks → `<Demo> RESET to clean state`) flips everything back to the canonical starting state through an Integration activity. It is registered DISABLED and driven with `POST /Admin/Api/TaskRun`, which ignores `TaskEnabled`, so it can never fire on a clock tick mid-demo.

The model is intentionally one-direction (BC → PIM). The PIM → BC enrichment story is told via a single static field-mapping artefact checked into the demo solution. No JSON inboxes, no folder structure, no in-demo firing protocol.

## When to use this flavor

| Constraint | DB-staged mock (this file) | Live BC ([`dw-integration-bc`](../../dw-integration-bc/SKILL.md)) |
|---|---|---|
| Demo handed off to a partner with no BC credentials | **Yes** (only viable option) | No |
| Demo laptop has no internet | **Yes** | No (ngrok needs internet) |
| Customisation budget tight (customisations ledger) | **Yes** — built-in add-ins and shipped providers only, zero custom code | Live adds `ForwardedHeaders` + AppStore connector configuration |
| Customer asks "does this really sync with BC?" | No (it's a model) | **Yes** |

Choose one and stick with it. Mixing flavors forces the audience to track two integration models in parallel.

## Three ways to execute the mock

The DB-staged flavor still has to answer *"what actually runs?"*. Three options, and the deciding
question is **what the beat's evidence is**:

| Option | What runs | Use when the evidence is | Cost |
|---|---|---|---|
| 1 — narrate the staged state | nothing; the data is already post-sync | an **admin screen** (product detail, action rule, mail template) | none |
| **3 — a real Integration Framework activity** | a `SqlProvider` source over a staged table into an `EcomProvider` (or `SqlProvider`) destination, bound to a task through `JobScheduledTaskAddIn` | the **STOREFRONT** — a PDP, a PLP, a cart line — **and any RESET** | none (configuration; no provider class to write) |
| 2 — `RunSqlScheduledTaskAddIn` | one SQL statement, *if* it executes | an admin screen, when the effect is asserted independently after every run | none (built-in add-in), plus the verification below |

**Option 3 is the default, including for the RESET.** It is not custom code: DW10 ships both
`SqlProvider` and `EcomProvider`, so an activity over them is configuration, it costs nothing on the
customisations ledger, and it stays fully DB-staged — no files, no tenant, no network. It also gives
the demo a **visible source/target pair** to open on screen, which is the whole point of narrating an
integration, and its activity log reports per-table row counts that a runbook can assert.

**A raw-SQL write cannot drive a storefront-visible beat.** The Ecommerce price and product caches
are read-through and a SQL `UPDATE` bypasses every domain-service hook that invalidates them, so the
PDP keeps rendering the old value indefinitely — repeated reads after the transaction committed all
returned the pre-write price. Touching `ProductUpdated` does not help either: it is not a cache key. Only two things
clear it: a write through a domain surface (option 3), or an explicit `CacheInformationRefresh` sweep
over the Ecommerce product/price service caches as a named step in the runbook. **So option 2's RESET
restores DATA only** — pair it with a cache-invalidating step whenever the storefront is the oracle.
A raw write to a cached aggregate is also destroyed by the next API save of that entity, not merely
read stale, so the ordering is always UPDATE → flush → touch; see
[dw-data-access](../../dw-data-access/references/cache-invalidation.md).

**`RunSqlScheduledTaskAddIn` reports success and silence identically.** On 10.28.x it has been
measured binding its parameters, firing, logging `Run returned: True` and setting `TaskLastResult`
True while executing **no SQL at all** — with the same statement writing rows when run by hand, and
a `JobScheduledTaskAddIn` activity writing to the same table through the same account seconds later.
Malformed settings *are* reported (an unescaped `<` in the blob sets `TaskLastResult` False with an
`XmlException` from `LoadParametersFromXml`), which is exactly what makes the silent case
misleading: the add-in demonstrably reads its configuration and demonstrably knows how to fail, and
still never reports that it ran nothing. So **never treat this add-in's run result as evidence** —
assert the effect (a row count, a checksum, a rendered page) after every run, or use option 3, whose
log counts the rows it moved.

**A raw-SQL write cannot drive a storefront-visible beat either.** The Ecommerce price and product
caches are read-through and a SQL `UPDATE` bypasses every domain-service hook that invalidates them,
so the PDP keeps rendering the old value indefinitely. Touching `ProductUpdated` does not help: it is
not a cache key. Two things clear it — a write through a domain surface, or an explicit
`CacheInformationRefresh` over the Ecommerce product and price service caches as a named runbook
step. **So an option-2 RESET restores DATA only**, and only when it ran.

## The recipe

### Step 1 — Decide the post-sync state per scenario

For each BC-driven scenario beat, write down: which products, which fields, the pre and post values. Example:

| Scenario | Product | Field | Pre | Post |
|---|---|---|---|---|
| Sc.4 auto-offline | PROD7 (BM-HANDLEBAR) | `ProductStock` | 5 | 0 |
| Sc.4 auto-offline | PROD7 | `g_bc_reorder` | 'yes' | 'no' |
| Sc.4 auto-offline | PROD7 | `g_lifecycle_state` | 'active' | 'offline' |
| Sc.4 auto-offline | PROD7 | `ProductWorkflowStateId` | 4 | 5 |
| Sc.4 auto-offline | PROD7 | `ProductActive` | 1 | 0 |
| Sc.5 price update | PROD1 | `ProductPrice` | 249.00 | 229.00 |
| Sc.5 price update | PROD2 | `ProductPrice` | 449.00 | 459.00 |

The "Post" column is what's in the DB at demo start. The "Pre" column is what RESET sets it back to.

### Step 2 — Stage the DB

Build one PowerShell + SQL script at `<demo>/.planning/stage-and-reset.ps1` that applies the post-sync state on first run. Run it once before authoring the runbook so the demo data matches the storyline.

Reference implementation: `<demo>/.planning/stage-and-reset.ps1` (build-time tooling — adapt per demo).

### Step 3 — Register the RESET scheduled task

**Bind the task to an Integration Framework activity** (`JobScheduledTaskAddIn`, option 3) wherever
the reset can be expressed as a restore from a staged baseline table — its log counts the rows it
moved, so the run is self-evidencing. The `ScheduledTask` row shape below is the same either way.

The built-in `Dynamicweb.Scheduling.ScheduledTaskAddIns.RunSqlScheduledTaskAddIn` (in
`Dynamicweb.Core`) accepts a `SQL Query` text parameter and a `Log debugging info` bool and needs no
customisation — but see the option-2 warning above: its success signal does not distinguish "ran the
SQL" from "ran nothing", so a task built on it needs an independent effect assertion after every run.

The `ScheduledTask` row itself still has to be registered. Idempotent SQL insert with hex-encoded XML
settings (dodges all escaping) — the settings document below carries whatever parameters the chosen
add-in declares:

```powershell
# The activity that restores the "Pre" column of the Step 1 table, by name.
$activity = '<Demo> RESET to clean state'

$esc  = { param($s) $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' }
# The settings document repeats the type name WITHOUT the assembly, on the root and on every
# child; TaskAddInTypeName below carries the assembly-qualified form. Read the parameter names
# off the add-in's own metadata rather than guessing them.
$type = 'Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn'
$xml = @"
<?xml version=`"1.0`" encoding=`"utf-8`"?>
<Parameters addin=`"$type`">
  <Parameter addin=`"$type`" name=`"<parameter name from the add-in's metadata>`" value=`"$(& $esc $activity)`" />
</Parameters>
"@
$bytes = [System.Text.Encoding]::Unicode.GetBytes($xml)
$hex   = '0x' + (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')

@"
SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM ScheduledTask WHERE TaskName=N'<Demo> RESET to clean state')
  INSERT INTO ScheduledTask
    (TaskName, TaskParentId, TaskBegin, TaskEnd, TaskLastRun, TaskNextRun, TaskEnabled, TaskType,
     TaskMinute, TaskHour, TaskDay, TaskWday,
     TaskAddInTypeName, TaskAddInSettings, TaskComment,
     TaskCheckPrevious, TaskSort, TaskStartFromLastRun, TaskLastResult)
  VALUES
    (N'<Demo> RESET to clean state', NULL,
     '2099-01-01 03:30', '9999-12-31', '1900-01-01', '2099-01-01 03:30', 0, 0,
     1440, 0, 0, 0,
     'Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn, Dynamicweb.DataIntegration',
     CAST($hex AS NVARCHAR(MAX)),
     N'Resets demo data to canonical starting state. Drive it with TaskRun between demos. Rebuild the Products index afterwards.',
     0, 0, 0, NULL);
"@ | sqlcmd -S "<server>" -d <db> -E
```

**A presenter-triggered task sets EVERY schedule column to `-1`** — `TaskMinute`, `TaskHour`,
`TaskDay`, `TaskWday` — as well as `TaskNextRun = '9999-12-31'`. That is the shape the platform's own
shipped tasks use, and it survives any number of pool restarts without firing.

A far-future `TaskNextRun` on its own is **not** a kill switch. DW re-evaluates overdue tasks at
application start and fires them, so a task carrying a "realistic" nightly minute/hour pair
self-fires about a minute after anything recycles the pool — and a demo reset that writes
`app_offline` is exactly that trigger. The symptom is unrequested runs appearing in the history the
presenter shows on screen, plus drift in any assertion that counts executions. **Carry the nightly
cadence in the task name, the task comment, the folder description and a staged
`ScheduledTaskExecution` history**, never in a live minute/hour pair; then only presenter-fired runs
land on top of the staged history, and the execution count after a reset is an exact assertion.

When the presenter fires the task on demand, `POST /Admin/Api/TaskRun {"TaskId":<n>}` ignores `TaskEnabled` entirely, so the row can stay disabled and still run on request without any schedule side effect.

**`TaskParentId` must be `NULL`, never `0`** — the scheduler enumerates the parent list, so a `0`
makes the task invisible with no log line anywhere. `TaskComment` is `nvarchar(255)` and SQL Server
refuses rather than trims; `TaskLastRun` is NOT NULL; `TaskParam0..4`, `TaskTarget`, `TaskAssembly`,
`TaskNamespace`, `TaskClass`, `TaskAddInSettings` and `TaskLastException` are empty strings on every
live row, not NULL; and `TaskMinute` with `TaskType = 0` is an interval in minutes.

Three rules make the difference between a registered task and one the app cannot see:

- **`TaskAddInSettings` holds LITERAL XML.** Escape only the *parameter value* (as `$sqlEsc` does
  above) and leave the surrounding document's own markup intact. XML-escaping the whole document
  stores a string the add-in loader cannot parse — the task exists, opens in admin, and does nothing.
  The hex-encoded `CAST(… AS NVARCHAR(MAX))` above is a SQL-insertion device, not an escaping one: the
  bytes it carries are the literal document.
- **Every SQL write to the schedule is invisible to the running app until the task list is
  flushed or the pool recycles — inserts and updates alike.** The scheduler serves the
  `ScheduledTask` schedule from the `Dynamicweb.Scheduling.TaskService` cache and never re-reads
  it on its own, so `POST /Admin/Api/TaskRun {TaskId:<n>}` answers **404 "The task with id: N was
  not found"** for a SQL-inserted row that demonstrably exists, and a `TaskNextRun` rewritten by
  SQL is ignored even on a task that has been firing correctly for a week; a pool with no idle
  timeout and no periodic restart never picks any of it up. `POST /Admin/Api/CacheInformationRefresh
  {"CacheTypeName":"Dynamicweb.Scheduling.TaskService"}` makes the row live on the next tick with
  no recycle. **Register and re-schedule through `TaskSave`**, which the running app sees
  immediately; when the SQL path is the only option, flush (or recycle) before claiming
  registration succeeded.
- **Prove registration from the task list, not from the INSERT.** `GET /Admin/Api/Tasks` must return
  the task by name — mind the 10-row default page size, which is how a freshly added task reads as
  absent on a host that already has ten.

Verify a run rather than a click: `POST /Admin/Api/TaskRun`, then assert the entity's own
`TaskLastRun` **advanced past a value captured before the trigger** and `TaskLastException` is empty.
`TaskRun` is asynchronous, so a fixed wall-clock window is not an assertion.

### Step 4 — Tell the outbox story without a JSON inbox

PIM → BC enrichment is the "we send descriptive data to the ERP" beat. Tell it via a single static artefact in the demo solution. Pick **one**:

1. **Field-mapping markdown** — `<demo>/notes/pim-to-bc-mapping.md` with the PIM systemName → BC field-path table. Presenter opens during the relevant beat.
2. **Single sample outbox JSON** — `<demo>/notes/sample-pim-to-bc.json`, never moved, never fired. Presenter shows it as a sample of what BC would receive.

Don't both. Don't build a `bc-deltas/outbox/` folder structure.

### Step 5 — Wire the demo flow

Every BC-driven beat in the runbook narrates the post-state and points to evidence — never a live trigger. Scenario template (Sc.4 — auto-offline on stock-zero):

> **Beat 1 — Open BM-HANDLEBAR.** Product detail shows `ProductStock=0`, `g_bc_reorder='no'`, lifecycle = Offline. *"BC's overnight sync delivered the stock-zero / no-reorder signal. The PIM action rule fired and took the product offline automatically."*
>
> **Beat 2 — Open Settings → Actions → Rules.** Show the rule definition (`stock=0 AND g_bc_reorder='no' → Offline + email`). *"This is what executed."*
>
> **Beat 3 — Open `Templates/Mail/<demo>-auto-offline.cshtml`.** Show the template that would have been rendered. Narrate the recipient field.

No live fire. No JSON file open. Data + rule + template tell the story.

### Step 6 — Between demos: RESET, cache flush, BuildIndex

1. Settings → System → Scheduled tasks → `<Demo> RESET to clean state` → **Run task now** — and confirm the **OK dialog** it opens. The task does not fire until the confirmation is accepted; a dismissed dialog leaves no visible trace, which reads as "the reset silently failed".
2. The run executes on the scheduler's next poll (typically under a minute), not synchronously with the click. Verify by the task's **Last run** timestamp flipping to now + green status (one SQL transaction, sub-second once it fires) — not by the click itself.
3. **Flush the Ecommerce product/price service caches.** A SQL RESET restores the DB and nothing else: the storefront keeps serving the pre-RESET price from a read-through cache that the transaction never invalidated, so the *next* rehearsal opens on stale values. `POST /Admin/Api/CacheInformationRefresh` per Ecommerce product/price service cache (enumerate them with `GET /Admin/Api/GetServiceCaches`), then re-read a rendered PDP as the check. An option-3 activity does this for you — that is the reason to prefer it for any storefront beat.
4. Settings → Search → Repositories → Products → BuildIndex (or `POST /admin/api/BuildIndex` with the management API bearer). Required because raw SQL UPDATEs don't trigger `ShopAutoBuildIndex` — dashboard tiles lag until the index rebuilds.

Definition of done for the reset is a **rendered** read, not a SQL read: fetch the PDP of a product the
RESET touched and assert the pre-state value is on the page.

**Keep exactly one RESET task.** Abandoned earlier registrations leave near-identical siblings in the task list ("`<Demo> RESET…`" vs "`<Demo> Demo RESET…`"), and a presenter under stage pressure will run the stale one. Delete superseded copies as part of Step 3's idempotent re-registration.

## Option 3 — DB-staged plus a real Integration Framework activity

For a demo that must **run** the sync on camera, or whose evidence is the storefront. Everything
stays in the database; the only additions are two staging tables and configuration.

### 1. Stage two tables, not one

| Table | Holds |
|---|---|
| `<Demo>SyncExtract` | the **post**-sync state — what the ERP "sent" |
| `<Demo>SyncBaseline` | the **pre**-sync state — what RESET restores |

Both live in the solution's own database, so the `SqlProvider` source needs no external connection.
Key them on the product number the catalogue actually uses.

### 2. Build two activities

Source `Dynamicweb.DataIntegration.Providers.SqlProvider.SqlProvider` over the staging table →
destination `Dynamicweb.DataIntegration.Providers.EcomProvider.EcomProvider`. One activity per
direction (apply / reset). The job XML lands on disk at
`<wwwroot>/Files/Files/Integration/jobs/<activity>.xml` — note the doubled `Files\Files`, and that
the file name **is** the activity name the task binds to. Encoding, the `<Schema>` block and the
column element shapes are owned by
[`../../dw-integration-framework/references/job-file-format.md`](../../dw-integration-framework/references/job-file-format.md).

Two destination settings carry the safety of the whole beat:

- **`UpdateOnlyExistingProducts=True`** — the activity updates the catalogue, never invents rows.
- **`UseStrictPrimaryKeyMatching=True`** — a key that does not resolve fails rather than fanning out.

Because the write goes through `EcomProvider` the domain services invalidate the caches behind
price and product rows, so the PDP reflects the new price on the next request with no manual flush.
That is the entire reason this option exists.

**The one gap: extended and global product fields.** A run that writes those columns leaves the
read-through cache in front of `ProductService` stale even with cache clearing enabled, and a
scheduled activity inherits that silently — so wire
`POST /Admin/Api/CacheInformationRefresh {"CacheTypeName":"Dynamicweb.Ecommerce.Products.ProductService"}`
into the task chain for any activity whose product-field effect must be visible. Details in
[`../../dw-integration-framework/references/provider-behaviour.md`](../../dw-integration-framework/references/provider-behaviour.md#ecomprovider-as-a-destination).

### 3. Bind each activity to a scheduled task

The add-in is `Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn, Dynamicweb.DataIntegration`,
and its **only** property is `Activity`. Guessing at a namespace burns a cycle for no reason — read the
assembly's TypeDef table if the FQN is ever in doubt (technique in
[`../../dw-source-explorer/references/assembly-introspection.md`](../../dw-source-explorer/references/assembly-introspection.md)).
Its settings obey the same **literal-XML** and **visible-only-after-registration** rules as Step 3.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Parameters addin="Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn, Dynamicweb.DataIntegration">
  <Parameter addin="Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn, Dynamicweb.DataIntegration"
             name="Activity" value="<activity name>" />
</Parameters>
```

Keep both tasks in **one folder** so the presenter sees the pair as one integration story. Preserve
the folder id on any later save — a task save that defaults `FolderId` re-roots the task at the top of
the list.

### 4. Prove the cycle A → B → A

The staged pair only earns its place if the reset is exact:

- Every product row the activity touches moves on the apply run and comes back **byte-identical** on
  the reset run.
- A **checksum over the contract-price rows** (row count and sum, per customer-group scope) is
  identical at all three hops — apply must not disturb group-scoped pricing, and reset must not
  reconstruct it.
- The rendered PDP shows the new value after apply and the original after reset, read from the page
  rather than from SQL.

Two ordering rules make a reset chain single-pass rather than "run it twice and hope", and both are
owned by
[`../../dw-integration-framework/references/provider-behaviour.md`](../../dw-integration-framework/references/provider-behaviour.md#restores-and-resets-built-on-activities):
**purge the entities the session created before restoring the tables**, and **scope every reset by a
marker column the generator stamps** rather than by an id list or a date. The second one has teeth
here in particular: an integration key is the "already processed" flag, so a reset that nulls it
re-arms the integration and the next export sweeps the whole seeded history.

## Do not

- Don't build a `bc-deltas/{inbox,outbox,applied}/` folder structure. (Previous version of this recipe did. The demo became dependent on Claude reading JSON live, presenters got the "fire the delta" interaction wrong on stage, and audiences had to imagine a synthetic "delta arrived" event that wasn't visible anywhere.)

## Cross-references

- [integration-framework.md](integration-framework.md) — the always-on "ERP is source/target, not channel/feed" rule.
- [erp-data-shape.md](erp-data-shape.md) — generic ERP↔PIM field-ownership table for authoring the post-sync state in Step 1.
- [scenarios-first-planning.md](scenarios-first-planning.md) — design the BC-driven scenarios before staging the DB.
- Live BC alternative: [`dw-integration-bc`](../../dw-integration-bc/SKILL.md).
- Reference implementation: `<demo>/.planning/stage-and-reset.ps1` (pivot from JSON-files to DB-staged).


