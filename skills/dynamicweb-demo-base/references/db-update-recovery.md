# DB update recovery — unstick the `UpdateManager` queue

When a DW10 host reaches a state where `UpdateManager.ExecuteUpdates()` fails on a missing schema object, every AddIn install (Backend MCP, any AppStore app, any plugin) **silently rolls back** — the install POST returns 200 but the underlying CommandResult contains the failure. The admin UI shows no error, the configuration menu the app was supposed to add never appears, and `/admin/<app>` endpoints return 404.

EventViewer logs at `wwwroot/Files/System/Log/EventViewer/*.log` are the only signal.

There are **two distinct failure modes**, with two different fixes. Triage carefully — applying the wrong fix wastes a host restart.

---

## Symptom

1. AppStore install (or any AddIn install) appears to do nothing — no UI confirmation, the menu the app is supposed to add never appears, expected admin endpoints return 404.
2. EventViewer contains repeated `Update failed: <guid> Dynamicweb.<...>UpdateProvider. SqlException` entries.
3. `POST /Admin/Api/AddinInstall` returns 200 but the install never finalises.

Read GlobalSettings to discover the DB:

```powershell
$cfg = [xml](Get-Content "Dynamicweb.Host.Suite/wwwroot/Files/GlobalSettings.Database.config")
$db = $cfg.Globalsettings.System.Database.Database
$server = $cfg.Globalsettings.System.Database.SQLServer
$cs = "Server=$server;Database=$db;Integrated Security=True;TrustServerCertificate=True"
```

---

## Triage

Find the failing UpdateIds in EventViewer (`Update failed: <guid> ...`), then check whether they're recorded as run:

```powershell
$c = New-Object System.Data.SqlClient.SqlConnection $cs
$c.Open()
$cmd = $c.CreateCommand()
$cmd.CommandText = "SELECT COUNT(*) FROM Updates WHERE UpdateId IN ('<guid1>', '<guid2>')"
"FailingUpdateIdsRecorded = $($cmd.ExecuteScalar())"
$c.Close()
```

Then check whether the prerequisite CREATE TABLE update is itself recorded. The failing ALTER messages name a table — search the DW source vault for it:

```powershell
# Replace <TableName> with the table from the EventViewer "Cannot find the object" message
Select-String -Path "$env:DW_VAULT\dw10source\src\**\*.cs" -Pattern "AddTable.*<TableName>" -SimpleMatch
```

The match returns the line in `<Provider>UpdateProvider.cs` like:
`SqlUpdate.AddTable("<create-table-guid>", this, "<TableName>", """ ... """)`

Then check whether the `<create-table-guid>` is in `Updates`:

```powershell
$cmd.CommandText = "SELECT COUNT(*) FROM Updates WHERE UpdateId = '<create-table-guid>'"
"CreateTableUpdateRecorded = $($cmd.ExecuteScalar())"
```

| Failing ALTER recorded? | CREATE TABLE recorded? | Failure mode | Fix |
|:---:|:---:|:---|:---|
| No | No | **Queue-stuck.** Updates re-run but never get past the failing one. Failing GUID retries forever, never gets recorded, blocks AppStore install. | **Mode A** (clear `Updates`, restart) |
| No | No, AND the CREATE TABLE SQL in source has a self-contradiction (e.g. PK references a column not in the column list) | **Buggy CREATE.** Mode A doesn't help — re-running the queue just re-fails on the same broken CREATE. The DW source itself is wrong. | **Mode B** (manual schema patch) |
| Yes | Yes | Schema is consistent with `Updates`; the AddIn install is failing for a different reason. Out of scope for this recipe — investigate per the AddIn's own diagnostics. | — |

To distinguish A vs B, read the CREATE TABLE source from `EcommerceUpdateProvider.cs` (or the relevant provider) and inspect for inconsistencies — particularly **PK constraint columns that don't match the column list** (the most common shape of this bug, often left over from a column-rename migration where the legacy column name got baked into the PK declaration).

---

## Mode A — Queue-stuck recovery (canonical forum procedure)

The forum-canonical fix is **clear the `Updates` table and recycle the host** so `UpdateManager.ExecuteUpdates()` re-runs the entire queue against the existing schema. CREATE TABLE updates use `IF NOT EXISTS` guards, so existing tables are not disturbed; only missing ones get created.

### Step A1 — Stop the host

```powershell
$dwPid = (Get-Process -Name "Dynamicweb.Host.Suite" -ErrorAction SilentlyContinue |
          Where-Object { $_.Path -match '<demo-folder-name>' }).Id
if ($dwPid) { Stop-Process -Id $dwPid -Force }
```

(The host *must* be down — `DELETE FROM Updates` against a live host races against the running update manager.)

### Step A2 — Clear the `Updates` table

Two routes; pick whichever is reachable.

**Route A — Admin UI (ask the user to run it; when admin is responsive):**

- Admin → **Settings → Database → SQL Firehose**
- Run: `DELETE FROM Updates;`

**Route B — Direct SQL (when admin is wedged):**

```powershell
$c = New-Object System.Data.SqlClient.SqlConnection $cs
$c.Open()
$cmd = $c.CreateCommand()
$cmd.CommandText = "SELECT COUNT(*) FROM Updates"
$before = $cmd.ExecuteScalar()
$cmd.CommandText = "DELETE FROM Updates"
$deleted = $cmd.ExecuteNonQuery()
$c.Close()
Write-Host "Cleared $deleted update records (was $before)."
```

### Step A3 — Restart the host

Per the host-lifecycle authority rule (SKILL.md), Claude controls this.

```powershell
Start-Process dotnet -ArgumentList "run --launch-profile Dynamicweb.Host.Suite" `
  -WorkingDirectory "Dynamicweb.Host.Suite"
```

`UpdateManager.ExecuteUpdates()` re-runs every queued update on first request. CREATE TABLE statements create only missing tables; ALTER TABLE statements that previously failed now find their target and succeed.

### Step A4 — Verify

The previously-missing object now exists, AND no new "Update failed" entries appear in EventViewer after the restart timestamp:

```powershell
$cmd.CommandText = "SELECT COUNT(*) FROM sys.tables WHERE name = '<TableName>'"
"<TableName> exists = $($cmd.ExecuteScalar())"
```

If the table is still missing → this is Mode B. Continue below.

---

## Mode B — Manual schema patch (when the CREATE itself is buggy)

When the source CREATE TABLE statement is self-contradictory (e.g. PK references a column not in the column list), `UpdateManager` will fail every time you run it. Mode A doesn't help. The fix is to manually create the table with a corrected schema, then let `IF NOT EXISTS` skip the broken CREATE on the next run.

### Step B1 — Reconstruct the corrected schema

Read the broken CREATE from `EcommerceUpdateProvider.cs` (or the relevant provider) in the dw10source vault. Compare its column list against its PK constraint columns. The fix is usually one of:

- **PK references a renamed column.** Look for a later `sp_rename` SqlUpdate in the same provider that renames the old column to a new name. Your manual CREATE should use the new name in both the column list AND the PK.
- **Typo in PK.** If no rename update exists, the PK column is just a typo — use the closest matching column from the column list.

### Step B2 — Stop the host (same as A1)

### Step B3 — Apply the corrected CREATE

Use the corrected column list + PK directly via SqlClient. Do NOT use `IF NOT EXISTS` here — you want this to succeed, and the table doesn't exist yet:

```powershell
$c = New-Object System.Data.SqlClient.SqlConnection $cs
$c.Open()
$cmd = $c.CreateCommand()
$cmd.CommandText = @"
CREATE TABLE [<TableName>] (
    -- column list copied verbatim from the broken update
    [<col1>] <type> ...,
    [<col2>] <type> ...,
    ...,
    CONSTRAINT [<PK_constraint_name>] PRIMARY KEY <CLUSTERED|NONCLUSTERED>
    (
        -- PK columns CORRECTED to match the column list
        [<col_with_corrected_name>] ASC,
        ...
    )
);
"@
$cmd.ExecuteNonQuery() | Out-Null
$c.Close()
```

### Step B4 — Mark the broken CREATE update as already-run

**Critical and easy to miss:** `IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '<TableName>')` does **not** short-circuit a syntactically-broken `CREATE TABLE` inside it. SQL Server validates the CREATE's constraint definition (e.g. PK columns must exist in the column list) at parse time — error 1911 fires regardless of whether the IF condition is true. So even with the table now existing, the broken update keeps failing on every queue replay.

To break the cycle, insert the broken UpdateId into `Updates` so `UpdateManager` skips it. Repeat for any sibling updates that are *also* hard-broken (e.g. an INDEX update with the same wrong column reference):

```powershell
$c = New-Object System.Data.SqlClient.SqlConnection $cs
$c.Open()
$cmd = $c.CreateCommand()
$cmd.CommandText = @"
INSERT INTO Updates (UpdateId, UpdateProviderName, UpdateTime)
VALUES ('<broken-create-guid>', 'Dynamicweb.<Feature>.Updates.<Provider>UpdateProvider', GETUTCDATE())
"@
$cmd.ExecuteNonQuery() | Out-Null
$c.Close()
```

(If a sibling hard-broken update was somehow already recorded by a partial replay — e.g. the row's PK violates `PK_Updates` on insert — that's fine, it just means it's already marked.)

### Step B5 — Restart the host (same as A3)

On startup, `UpdateManager` retries the queue. The broken CREATE's UpdateId is now in `Updates` → DW skips it entirely. Subsequent ADD COLUMN updates find their target (the manually-created table) and succeed. AddIn install registration completes cleanly.

### Step B6 — Verify (same as A4) plus ALTER outcomes

The failing ALTER UpdateIds should now appear in `Updates`, and the column count on the table should equal columnsInOriginalCreate + addColumnUpdates:

```powershell
$cmd.CommandText = "SELECT COUNT(*) FROM Updates WHERE UpdateId IN ('<failing-guid-1>', '<failing-guid-2>', ...)"
"PreviouslyFailing-now-recorded = $($cmd.ExecuteScalar())"

$cmd.CommandText = "SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('<TableName>')"
"ColumnCount = $($cmd.ExecuteScalar())"
```

### Step B7 — Report upstream

A buggy CREATE in `EcommerceUpdateProvider.cs` (or any of the standard providers) is a Dynamicweb upstream bug, not project-local. File via Service Desk with: the failing UpdateId(s), the SQL error message, the contradictory CREATE excerpt from the source, the corrected schema you applied, and the DW10 / template version (read from the host's csproj or Suite NuGet metadata). Future demo machines on the same template version will hit the same wall — a documented upstream fix saves every later setup.

---

## Known-as-of-2026-05 example

Hosts scaffolded from `Dynamicweb.ProjectTemplates` 1.26.0 (i.e. the `Dynamicweb.Suite` version that template + `dotnet restore` resolved as of 2026-05) ship a buggy CREATE for `EcomConsolidatedOrderPayments` in `EcommerceUpdateProvider.cs`: the PK constraint references `ConsolidatedOrderPaymentPaidByOrderId` while the column list defines `ConsolidatedOrderPaymentPaidOrderId` (no "By"). A later `sp_rename` update would have renamed `PaidByOrderId` → `PaidOrderId` if the table existed, but the table never gets created. AppStore "Backend MCP" install hits this on first install attempt.

Mode B fix: corrected PK uses `ConsolidatedOrderPaymentPaidOrderId` (matching the column list). Step B4 then marks UpdateIds `2bcced05-2b99-4a17-8c8c-af359d28fdd8` (the broken CREATE) as already-run; the cluster-index UpdateId `8df89410-14cf-44f7-85ea-5797af36937f` is typically already recorded from a prior partial replay.

---

## When this whole recipe is NOT the right fix

- **Update fails because of permissions** (e.g. `db_ddladmin` missing on the SQL user). Neither A nor B helps — clearing/recreating just retries the same permission failure. Fix the SQL grant first.
- **The DB has real customer data and the failing update is a DESTRUCTIVE migration.** Mode A re-runs everything including data migrations; on a populated DB this can corrupt. For Truvio demo work the DB is always fresh and never has real customer data at this stage (baseline deserialization happens *after* this skill's setup gates pass), so the "fresh demo DB" path applies and Mode A is safe. For production, talk to Dynamicweb Service Desk first.

---

## Sources

- [Update Script — official doc (DW 9.14+ "Delete all from Updates" procedure)](https://doc.dynamicweb.com/get-started/introduction/installation/update-script)
- [Forum: error when creating the shipping method (mid-sequence update failure → safe-to-rerun confirmation, Mode A canonical example)](https://doc.dynamicweb.com/forum/development/error-when-creating-the-shipping-method?PID=1605)
- [Forum: Set up Dynamic Web on localhost (rerun-update procedure discussion)](https://doc.dynamicweb.com/forum/development/set-up-dynamic-web-on-localhost?PID=1605)
- DW source: `$env:DW_VAULT\dw10source\src\Features\Ecommerce\Dynamicweb.Ecommerce\Updates\EcommerceUpdateProvider.cs` (read this when triaging Ecom update failures)
