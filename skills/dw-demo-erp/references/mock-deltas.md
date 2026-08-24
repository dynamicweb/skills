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
- **One** scheduled task (Settings → System → Scheduled tasks → `<Demo> RESET to clean state`) flips everything back to the canonical starting state via a SQL subtask. The presenter clicks "Run now" between demos.

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
| 2 — `RunSqlScheduledTaskAddIn` | one SQL transaction | an **admin screen**, and the demo needs a between-runs RESET | none (built-in add-in) |
| 3 — a real Integration Framework activity | a `SqlProvider` source over a staged table into an `EcomProvider` destination | the **STOREFRONT** — a PDP, a PLP, a cart line | none (configuration; no provider class to write) |

**A raw-SQL write cannot drive a storefront-visible beat.** The Ecommerce price and product caches
are read-through and a SQL `UPDATE` bypasses every domain-service hook that invalidates them, so the
PDP keeps rendering the old value indefinitely — repeated reads after the transaction committed all
returned the pre-write price. Touching `ProductUpdated` does not help either: it is not a cache key. Only two things
clear it: a write through a domain surface (option 3), or an explicit `CacheInformationRefresh` sweep
over the Ecommerce product/price service caches as a named step in the runbook. **So option 2's RESET
restores DATA only** — pair it with a cache-invalidating step whenever the storefront is the oracle.

Option 3 is not custom code. The recipe's older wording ("no provider class is registered") conflated
*no CUSTOM provider* with *no activity*: DW10 ships both `SqlProvider` and `EcomProvider`, so an
activity over them is configuration, it costs nothing on the customisations ledger, and it stays fully
DB-staged — no files, no tenant, no network. It also gives the demo a **visible source/target pair**
to open on screen, which is the whole point of narrating an integration.

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

Use the built-in `Dynamicweb.Scheduling.ScheduledTaskAddIns.RunSqlScheduledTaskAddIn` (in `Dynamicweb.Core`). No customisation needed — this addin ships with DW10 and accepts a `SQL Query` text parameter + a `Log debugging info` bool.

Idempotent SQL insert with hex-encoded XML settings (dodges all escaping):

```powershell
$resetSql = @'
UPDATE EcomProducts SET ProductStock=5, ProductWorkflowStateId=4, ProductActive=1, g_bc_reorder='yes', g_lifecycle_state='active' WHERE ProductId='PROD7' AND ProductLanguageId='LANG1' AND ProductVariantId='';
UPDATE EcomProducts SET ProductPrice=249.0 WHERE ProductId='PROD1' AND ProductLanguageId='LANG1' AND ProductVariantId='';
-- ... one UPDATE per "Pre" row from Step 1 ...
'@

$sqlEsc = $resetSql -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
$type = 'Dynamicweb.Scheduling.ScheduledTaskAddIns.RunSqlScheduledTaskAddIn'
$xml = @"
<?xml version=`"1.0`" encoding=`"utf-8`"?>
<Parameters addin=`"$type`">
  <Parameter addin=`"$type`" name=`"SQL Query`" value=`"$sqlEsc`" />
  <Parameter addin=`"$type`" name=`"Log debugging info`" value=`"True`" />
</Parameters>
"@
$bytes = [System.Text.Encoding]::Unicode.GetBytes($xml)
$hex   = '0x' + (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')

@"
SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM ScheduledTask WHERE TaskName=N'<Demo> RESET to clean state')
  INSERT INTO ScheduledTask
    (TaskName, TaskBegin, TaskEnd, TaskLastRun, TaskNextRun, TaskEnabled, TaskType,
     TaskMinute, TaskHour, TaskDay, TaskWday,
     TaskAddInTypeName, TaskAddInSettings, TaskComment,
     TaskCheckPrevious, TaskSort, TaskStartFromLastRun, TaskLastResult)
  VALUES
    (N'<Demo> RESET to clean state',
     GETDATE(), '9999-12-31', '2000-01-01', '9999-12-31', 1, 0,
     0, 0, 0, 0,
     'Dynamicweb.Scheduling.ScheduledTaskAddIns.RunSqlScheduledTaskAddIn, Dynamicweb.Core',
     CAST($hex AS NVARCHAR(MAX)),
     N'Resets demo data to canonical starting state. Click Run now between demos. Rebuild the Products index afterwards.',
     0, 0, 0, 1);
"@ | sqlcmd -S "<server>" -d <db> -E
```

`TaskNextRun='9999-12-31'` keeps the task enabled but never auto-fires; the presenter triggers it from the admin UI.

**NOT NULL columns** in `ScheduledTask` that bite if you forget: `TaskLastRun`, `TaskNextRun`, `TaskMinute`, `TaskHour`, `TaskDay`, `TaskWday`, `TaskStartFromLastRun`.

Three rules make the difference between a registered task and one the app cannot see:

- **`TaskAddInSettings` holds LITERAL XML.** Escape only the *parameter value* (as `$sqlEsc` does
  above) and leave the surrounding document's own markup intact. XML-escaping the whole document
  stores a string the add-in loader cannot parse — the task exists, opens in admin, and does nothing.
  The hex-encoded `CAST(… AS NVARCHAR(MAX))` above is a SQL-insertion device, not an escaping one: the
  bytes it carries are the literal document.
- **A SQL-inserted `ScheduledTask` row is invisible to the running app until a recycle.** The
  scheduled-task service caches its task collection at application start, so
  `POST /Admin/Api/TaskRun {TaskId:<n>}` answers **404 "The task with id: N was not found"** for a row
  that demonstrably exists. **Prefer registering through `TaskSave`**, which the running app sees
  immediately; when the SQL path is the only option, recycle before claiming registration succeeded.
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
direction (apply / reset). The job XML lands under `Files/Integration/jobs/<activity>.xml`.

Two destination settings carry the safety of the whole beat:

- **`UpdateOnlyExistingProducts=True`** — the activity updates the catalogue, never invents rows.
- **`UseStrictPrimaryKeyMatching=True`** — a key that does not resolve fails rather than fanning out.

Because the write goes through `EcomProvider`, the domain services invalidate their own caches: the
PDP reflects the new price on the next request with no manual flush. That is the entire reason this
option exists.

### 3. Bind each activity to a scheduled task

The add-in is `Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn, Dynamicweb.DataIntegration`,
and its **only** property is `Activity`. Guessing at a namespace burns a cycle for no reason — read the
assembly's TypeDef table if the FQN is ever in doubt (technique in
[`../../dw-demo-base/references/foundational/source-explorer.md`](../../dw-demo-base/references/foundational/source-explorer.md)).
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

## Do not

- Don't build a `bc-deltas/{inbox,outbox,applied}/` folder structure. (Previous version of this recipe did. The demo became dependent on Claude reading JSON live, presenters got the "fire the delta" interaction wrong on stage, and audiences had to imagine a synthetic "delta arrived" event that wasn't visible anywhere.)

## Cross-references

- [integration-framework.md](integration-framework.md) — the always-on "ERP is source/target, not channel/feed" rule.
- [erp-data-shape.md](erp-data-shape.md) — generic ERP↔PIM field-ownership table for authoring the post-sync state in Step 1.
- [scenarios-first-planning.md](scenarios-first-planning.md) — design the BC-driven scenarios before staging the DB.
- Live BC alternative: [`dw-integration-bc`](../../dw-integration-bc/SKILL.md).
- Reference implementation: `<demo>/.planning/stage-and-reset.ps1` (pivot from JSON-files to DB-staged).


