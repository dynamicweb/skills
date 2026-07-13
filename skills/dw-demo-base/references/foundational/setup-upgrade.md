# Foundational candidate → dw-setup-upgrade

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 update-queue / schema-migration recovery knowledge,
> staged here for a future fold-up into `dw-setup-upgrade`. No demo/customer content. When folded,
> move this body into `dw-setup-upgrade` and re-target the pointers in the demo skills. Until then,
> the demo skills reference this file.

This is the platform-level "the `UpdateManager` queue is stuck and AddIn installs silently roll back"
recovery knowledge: how `UpdateManager.ExecuteUpdates()` works, why a single failing migration blocks
every AddIn install, the `Updates`-table recovery procedure, and the manual schema patch when the
shipped CREATE itself is buggy.

## How the update queue blocks AddIn installs

When a DW10 host reaches a state where `UpdateManager.ExecuteUpdates()` fails on a missing schema
object, every AddIn install (Backend MCP, any AppStore app, any plugin) **silently rolls back** — the
install POST returns 200 but the underlying `CommandResult` carries the failure. The admin UI shows no
error, the configuration menu the app was supposed to add never appears, and `/admin/<app>` endpoints
return 404. `UpdateManager.ExecuteUpdates()` re-runs the entire queued update set on first request, and
a single failing update keeps the whole queue from ever completing.

EventViewer logs at `wwwroot/Files/System/Log/EventViewer/*.log` are the only signal.

There are **two distinct failure modes** with two different fixes. Triage carefully — applying the
wrong fix wastes a host restart.

## Symptom

1. AppStore install (or any AddIn install) appears to do nothing — no UI confirmation, the menu the app
   should add never appears, expected admin endpoints return 404.
2. EventViewer contains repeated `Update failed: <guid> Dynamicweb.<...>UpdateProvider. SqlException`
   entries.
3. `POST /Admin/Api/AddinInstall` returns 200 but the install never finalises.

Read GlobalSettings to discover the DB:

```powershell
$cfg = [xml](Get-Content "<host>/wwwroot/Files/GlobalSettings.Database.config")
$db = $cfg.Globalsettings.System.Database.Database
$server = $cfg.Globalsettings.System.Database.SQLServer
$cs = "Server=$server;Database=$db;Integrated Security=True;TrustServerCertificate=True"
```

## Triage — Mode A vs Mode B

Find the failing UpdateIds in EventViewer (`Update failed: <guid> ...`), then check whether they are
recorded as run, and whether the prerequisite CREATE TABLE update is itself recorded:

```powershell
$c = New-Object System.Data.SqlClient.SqlConnection $cs; $c.Open()
$cmd = $c.CreateCommand()
$cmd.CommandText = "SELECT COUNT(*) FROM Updates WHERE UpdateId IN ('<guid1>', '<guid2>')"
"FailingUpdateIdsRecorded = $($cmd.ExecuteScalar())"
# The failing ALTER messages name a table — search the DW source for its CREATE:
#   Select-String -Path "<dw10source>\src\**\*.cs" -Pattern "AddTable.*<TableName>" -SimpleMatch
# yields a line like: SqlUpdate.AddTable("<create-table-guid>", this, "<TableName>", """ ... """)
$cmd.CommandText = "SELECT COUNT(*) FROM Updates WHERE UpdateId = '<create-table-guid>'"
"CreateTableUpdateRecorded = $($cmd.ExecuteScalar())"
$c.Close()
```

| Failing ALTER recorded? | CREATE TABLE recorded? | Failure mode | Fix |
|:---:|:---:|:---|:---|
| No | No | **Queue-stuck.** Updates re-run but never get past the failing one. The failing GUID retries forever, never gets recorded, blocks AppStore install. | **Mode A** (clear `Updates`, restart) |
| No | No, AND the CREATE TABLE SQL in source has a self-contradiction (e.g. PK references a column not in the column list) | **Buggy CREATE.** Mode A doesn't help — re-running just re-fails on the same broken CREATE. The DW source itself is wrong. | **Mode B** (manual schema patch) |
| Yes | Yes | Schema is consistent with `Updates`; the AddIn install is failing for a different reason — investigate per the AddIn's own diagnostics. | — |

To distinguish A vs B, read the CREATE TABLE source from the relevant `<Feature>UpdateProvider.cs` and
inspect for inconsistencies — particularly **PK constraint columns that don't match the column list**
(the most common shape, usually left over from a column-rename migration where the legacy column name
got baked into the PK declaration).

## Mode A — Queue-stuck recovery (canonical forum procedure)

Clear the `Updates` table and recycle the host so `UpdateManager.ExecuteUpdates()` re-runs the entire
queue against the existing schema. CREATE TABLE updates use `IF NOT EXISTS` guards, so existing tables
are not disturbed; only missing ones get created.

1. **Stop the host** — it *must* be down, since `DELETE FROM Updates` against a live host races the
   running update manager.
2. **Clear `Updates`** — either admin UI **Settings → Database → SQL Firehose** running
   `DELETE FROM Updates;`, or direct SQL `DELETE FROM Updates` over the `$cs` connection above.
3. **Restart the host.** `UpdateManager.ExecuteUpdates()` re-runs every queued update on first request —
   CREATE TABLE statements create only missing tables; ALTER TABLE statements that previously failed now
   find their target and succeed.
4. **Verify** the previously-missing object now exists and no new "Update failed" entries appear after
   the restart timestamp:

   ```powershell
   $cmd.CommandText = "SELECT COUNT(*) FROM sys.tables WHERE name = '<TableName>'"
   "<TableName> exists = $($cmd.ExecuteScalar())"
   ```

If the table is still missing after a clean restart → this is Mode B.

## Mode B — Manual schema patch (when the CREATE itself is buggy)

When the source CREATE TABLE statement is self-contradictory (e.g. PK references a column not in the
column list), `UpdateManager` fails every run and Mode A doesn't help. The fix is to manually create
the table with a corrected schema, then let `IF NOT EXISTS` skip the broken CREATE on the next run.

1. **Reconstruct the corrected schema.** Read the broken CREATE from the relevant provider in the DW10
   source. Compare its column list against its PK constraint columns. Usually one of:
   - **PK references a renamed column** — look for a later `sp_rename` SqlUpdate in the same provider;
     your manual CREATE should use the new name in both the column list AND the PK.
   - **Typo in PK** — if no rename exists, use the closest matching column from the column list.
2. **Stop the host.**
3. **Apply the corrected CREATE** directly via SqlClient (no `IF NOT EXISTS` — you want it to succeed,
   and the table doesn't exist yet). Copy the column list verbatim from the broken update; correct only
   the PK columns to match.
4. **Mark the broken CREATE update as already-run.** *Critical and easy to miss:* an
   `IF NOT EXISTS (...) CREATE TABLE ...` does **not** short-circuit a syntactically-broken CREATE —
   SQL Server validates the constraint definition at parse time (error 1911) regardless of the IF
   condition, so the broken update keeps failing on every replay even with the table now present. Break
   the cycle by inserting the broken UpdateId into `Updates` so `UpdateManager` skips it (repeat for any
   sibling updates that are also hard-broken, e.g. an INDEX update with the same wrong column reference):

   ```powershell
   $cmd.CommandText = "INSERT INTO Updates (UpdateId, UpdateProviderName, UpdateTime) VALUES ('<broken-create-guid>', 'Dynamicweb.<Feature>.Updates.<Provider>UpdateProvider', GETUTCDATE())"
   $cmd.ExecuteNonQuery() | Out-Null
   ```

5. **Restart the host.** On startup `UpdateManager` retries the queue, skips the now-recorded broken
   CREATE, and subsequent ADD COLUMN updates find their target (the manually-created table) and succeed.
   AddIn install registration completes cleanly.
6. **Verify** the failing ALTER UpdateIds now appear in `Updates`, and the column count equals
   columnsInOriginalCreate + addColumnUpdates.
7. **Report upstream.** A buggy CREATE in a standard provider is a Dynamicweb upstream bug. File via
   Service Desk with the failing UpdateId(s), the SQL error, the contradictory CREATE excerpt, the
   corrected schema you applied, and the DW10 / template version. Every later host on the same template
   version hits the same wall.

### Worked-bug shape (template-version dependent)

Some `Dynamicweb.ProjectTemplates` versions ship a buggy CREATE for `EcomConsolidatedOrderPayments` in
`EcommerceUpdateProvider.cs`: the PK constraint references `ConsolidatedOrderPaymentPaidByOrderId` while
the column list defines `ConsolidatedOrderPaymentPaidOrderId` (no "By"). A later `sp_rename` would have
renamed the column if the table existed, but the table never gets created. The Mode B corrected PK uses
`ConsolidatedOrderPaymentPaidOrderId` (matching the column list); the broken-CREATE UpdateId and its
cluster-index UpdateId are then marked already-run.

## When this recipe is NOT the right fix

- **Update fails because of permissions** (e.g. `db_ddladmin` missing on the SQL user). Neither A nor B
  helps — clearing/recreating just retries the same permission failure. Fix the SQL grant first.
- **The DB has real data and the failing update is a DESTRUCTIVE migration.** Mode A re-runs everything
  including data migrations; on a populated DB this can corrupt. Mode A is safe only on a fresh DB with
  no real data. For a populated/production DB, talk to Dynamicweb Service Desk first.

## In-place platform update — the pre-update backup + content-count gate

Before ANY in-place platform update on a host whose DB content is not regenerable (a
`Dynamicweb.Suite` version bump, a design/item-type re-deploy, an update cycle that runs
deserializes against the live DB), take two snapshots:

```sql
SELECT COUNT(*) FROM ItemList;          -- and ItemListRelation
BACKUP DATABASE [<db>] TO DISK = '<path>\<db>-pre-update.bak';
```

After the update, **the counts must match the snapshot**. `ItemList` / `ItemListRelation` rows
back every repeatable-item component (slider slides, accordion items, named lists) and their loss
renders as silent empty bands, not errors — an in-place update cycle has been observed to leave
`ItemList`, `ItemListRelation`, `ItemNamedItemList`, and the `ItemType_*_Item` child tables empty
with no error surfaced anywhere, and without a backup the only recovery is re-authoring the
content by hand. Treat a count mismatch as a stop-the-line failure: restore the backup, then
isolate which update step dropped the rows before re-running.

## Schema-drift across NuGet versions (Serializer / migration crossover)

When a deserialize or cross-host data move warns `source column [T].[C] not present on target schema —
skipping`, the source DW host is on a different `Dynamicweb.Suite` NuGet version than the target: the
source has a column the target's `UpdateProvider` hasn't created yet. The platform-level fix is to align
versions and let DW run the pending migrations at startup:

1. **Align NuGet versions** — bump the target's `Dynamicweb.Suite` to match source, `dotnet publish`,
   restart. **DW runs pending `UpdateProvider` classes at startup**, creating the missing columns. (If a
   `UpdateProvider` itself is broken, that's the Mode A / Mode B path above.)
2. Or align downward — drop the column on source instead.
3. Or accept the drift — the column is silently dropped from the MERGE, the rest of the row writes
   correctly (lenient mode only).

## Sources

- [Update Script — official doc (DW 9.14+ "Delete all from Updates" procedure)](https://doc.dynamicweb.com/get-started/introduction/installation/update-script)
- [Forum: error when creating the shipping method (Mode A canonical example)](https://doc.dynamicweb.com/forum/development/error-when-creating-the-shipping-method?PID=1605)
- [Forum: Set up Dynamic Web on localhost (rerun-update procedure)](https://doc.dynamicweb.com/forum/development/set-up-dynamic-web-on-localhost?PID=1605)
- DW source: the relevant `<Feature>UpdateProvider.cs` (read this when triaging a feature's update failures)
