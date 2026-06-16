# mock-deltas.md

> Canonical recipe for mocking an ERP without a live tenant: the demo data starts in the **post-delta state**, staged directly in the database, with a single scheduled task to reset between demos. Loaded from `dynamicweb-erp-demo/SKILL.md` "Where to find things". Use when the demo handover doesn't include BC tenant access.

## The mental model

There is **no live wire**. There is no file polling daemon, no JSON inbox, no human firing deltas during the demo. Instead:

- The DB is pre-staged into the **post-BC-sync state** â€” every value that BC would have written (price, stock, reorder, lifecycle state, etc.) is already in `EcomProducts` as if the delta arrived overnight.
- The demo narrates *"BC sent us this; look at the result."* Evidence is the data, the action-rule definition, and the email template â€” not a live trigger.
- **One** scheduled task (Settings â†’ System â†’ Scheduled tasks â†’ `<Demo> RESET to clean state`) flips everything back to the canonical starting state via a SQL subtask. The presenter clicks "Run now" between demos.

The model is intentionally one-direction (BC â†’ PIM). The PIM â†’ BC enrichment story is told via a single static field-mapping artefact checked into the demo solution. No JSON inboxes, no folder structure, no in-demo firing protocol.

## When to use this flavor

| Constraint | DB-staged mock (this file) | Live BC ([`dynamicweb-pim-for-bc`](../../dw-integration-bc/SKILL.md)) |
|---|---|---|
| Demo handed off to a partner with no BC credentials | **Yes** (only viable option) | No |
| Demo laptop has no internet | **Yes** | No (ngrok needs internet) |
| Customisation budget tight (customisations ledger) | **Yes** â€” uses the built-in `RunSqlScheduledTaskAddIn`, zero custom code | Live adds `ForwardedHeaders` + AppStore connector configuration |
| Customer asks "does this really sync with BC?" | No (it's a model) | **Yes** |

Choose one and stick with it. Mixing flavors forces the audience to track two integration models in parallel.

## The recipe

### Step 1 â€” Decide the post-sync state per scenario

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

### Step 2 â€” Stage the DB

Build one PowerShell + SQL script at `<demo>/.planning/stage-and-reset.ps1` that applies the post-sync state on first run. Run it once before authoring the runbook so the demo data matches the storyline.

Reference implementation: `<demo>/.planning/stage-and-reset.ps1` (build-time tooling â€” adapt per demo).

### Step 3 â€” Register the RESET scheduled task

Use the built-in `Dynamicweb.Scheduling.ScheduledTaskAddIns.RunSqlScheduledTaskAddIn` (in `Dynamicweb.Core`). No customisation needed â€” this addin ships with DW10 and accepts a `SQL Query` text parameter + a `Log debugging info` bool.

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

### Step 4 â€” Tell the outbox story without a JSON inbox

PIM â†’ BC enrichment is the "we send descriptive data to the ERP" beat. Tell it via a single static artefact in the demo solution. Pick **one**:

1. **Field-mapping markdown** â€” `<demo>/notes/pim-to-bc-mapping.md` with the PIM systemName â†’ BC field-path table. Presenter opens during the relevant beat.
2. **Single sample outbox JSON** â€” `<demo>/notes/sample-pim-to-bc.json`, never moved, never fired. Presenter shows it as a sample of what BC would receive.

Don't both. Don't build a `bc-deltas/outbox/` folder structure.

### Step 5 â€” Wire the demo flow

Every BC-driven beat in the runbook narrates the post-state and points to evidence â€” never a live trigger. Scenario template (Sc.4 â€” auto-offline on stock-zero):

> **Beat 1 â€” Open BM-HANDLEBAR.** Product detail shows `ProductStock=0`, `g_bc_reorder='no'`, lifecycle = Offline. *"BC's overnight sync delivered the stock-zero / no-reorder signal. The PIM action rule fired and took the product offline automatically."*
>
> **Beat 2 â€” Open Settings â†’ Actions â†’ Rules.** Show the rule definition (`stock=0 AND g_bc_reorder='no' â†’ Offline + email`). *"This is what executed."*
>
> **Beat 3 â€” Open `Templates/Mail/<demo>-auto-offline.cshtml`.** Show the template that would have been rendered. Narrate the recipient field.

No live fire. No JSON file open. Data + rule + template tell the story.

### Step 6 â€” Between demos: RESET + BuildIndex

1. Settings â†’ System â†’ Scheduled tasks â†’ `<Demo> RESET to clean state` â†’ **Run task now**.
2. Wait for green status (one SQL transaction, sub-second).
3. Settings â†’ Search â†’ Repositories â†’ Products â†’ BuildIndex (or `POST /admin/api/BuildIndex` with the management API bearer). Required because raw SQL UPDATEs don't trigger `ShopAutoBuildIndex` â€” dashboard tiles lag until the index rebuilds.

## Do not

- Don't build a `bc-deltas/{inbox,outbox,applied}/` folder structure. (Previous version of this recipe did. The demo became dependent on Claude reading JSON live, presenters got the "fire the delta" interaction wrong on stage, and audiences had to imagine a synthetic "delta arrived" event that wasn't visible anywhere.)

## Cross-references

- [integration-framework.md](integration-framework.md) â€” the always-on "ERP is source/target, not channel/feed" rule.
- [erp-data-shape.md](erp-data-shape.md) â€” generic ERPâ†”PIM field-ownership table for authoring the post-sync state in Step 1.
- [scenarios-first-planning.md](scenarios-first-planning.md) â€” design the BC-driven scenarios before staging the DB.
- Live BC alternative: [`dynamicweb-pim-for-bc`](../../dw-integration-bc/SKILL.md).
- Reference implementation: `<demo>/.planning/stage-and-reset.ps1` (2026-05-21 pivot from JSON-files to DB-staged).


