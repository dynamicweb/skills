# Foundational candidate → dw-setup-config (tracking, Insights & health providers)

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 visitor-tracking, Insights-dashboard, health-provider and
> log-retention knowledge, staged here for a future fold-up into `dw-setup-config`. No demo/customer content.
> When folded, move this body into `dw-setup-config` and re-target the pointers in the demo skills. Until
> then, the demo skills reference this file.
>
> Read this before promising a customer *any* number on an Insights dashboard. The Marketing tiles read a
> table most people never look at, live tracking on 10.28.x cannot produce the shape those tiles imply, and
> the Monitoring error counter the owner is told to trust counts your own API typos.

## Contents

- [Insights reads `Tracking*` — `Statv2*` is a decoy](#insights-reads-tracking--statv2-is-a-decoy)
- [Nothing reaches the tracking tables until `DoNotTrackConnectionCloseHeader` is off](#nothing-reaches-the-tracking-tables-until-donottrackconnectioncloseheader-is-off)
- [Live tracking on 10.28.x can never record a second view or a returning visitor](#live-tracking-on-1028x-can-never-record-a-second-view-or-a-returning-visitor)
- [`Tracking/Level` ships a value the enum does not contain](#trackinglevel-ships-a-value-the-enum-does-not-contain)
- [Never create a table whose name starts with `TrackingSession`](#never-create-a-table-whose-name-starts-with-trackingsession)
- [Health providers are reachable over `/Admin/Api` — and each check returns its own SQL](#health-providers-are-reachable-over-adminapi--and-each-check-returns-its-own-sql)
- [`ContentDataHealthProvider` 500s on every partially-contained database](#contentdatahealthprovider-500s-on-every-partially-contained-database)
- [Monitoring's "Recent task runs" Status column is derived from history, not from `TaskEnabled`](#monitorings-recent-task-runs-status-column-is-derived-from-history-not-from-taskenabled)
- [Nothing ever trims `GeneralLog` or `ScheduledTaskExecution`](#nothing-ever-trims-generallog-or-scheduledtaskexecution)
- [Cross-references](#cross-references)

## Insights reads `Tracking*` — `Statv2*` is a decoy

An empty **Insights → Marketing insights** dashboard invites the obvious fix of populating `Statv2Session` /
`Statv2*`. That changes nothing: the DW9 statistics engine survives in the DW10 schema, is disabled
(`/Globalsettings/System/Statistics/DisableStatistics = True`) and **no widget reads it**.

Every Marketing widget resolves through the shared visitor SQL helper in `Dynamicweb.Insights.UI.dll` and
queries **`TrackingSession` / `TrackingView` / `TrackingEvent` at query time**. There is no aggregation job and
no materialised cache, so inserted rows appear on the **next page load**.

- **The shared valid-session filter is `TrackingSessionBotType = 0 AND TrackingSessionExcluded = 0`**, plus
  `AND TrackingSessionAreaId = @areaId` only when a website is selected in the picker. Anything that fails
  those two predicates is invisible while still occupying a row.
- **`TrackingSessionPingBackReceived` is NOT in the read filter** — rows count whether or not the JS beacon
  ever fired. Do not seed it as though it gated visibility.
- Traffic-source ordinals: `0` Campaign, `1` Organic search, `2` Referral, `3` Direct, `4` Other. The date
  picker keys are ordinal-prefixed (`040_Last-7-days` is the default) — compose them, don't guess labels.

Assert it the cheap way: insert one `TrackingSession` + `TrackingView` pair and confirm the Visits tile moves
on the next dashboard read; insert a `Statv2Session` row and confirm **nothing** moves.

## Nothing reaches the tracking tables until `DoNotTrackConnectionCloseHeader` is off

`/Globalsettings/System/Tracking/DoNotTrackConnectionCloseHeader` **ships `True`**. Any host behind a proxy or
terminator that sets `Connection: close` on every request therefore matches the exclusion rule on **100% of
traffic** — and because `StoreNotTrackedVisits` defaults `False`, the excluded visit is not persisted at all.
The result is a site with tracking switched on that has recorded zero visits, ever, with no row, no log line
and no counter anywhere in the admin indicating that anything was dropped.

**Diagnostic ladder for an empty tracking table:**

1. Set `StoreNotTrackedVisits = True` temporarily, drive one real browser hit, and read
   `TrackingSessionExcludedReason` on the resulting row — the reason names the rule verbatim.
2. Set `DoNotTrackConnectionCloseHeader = False`. The same URLs then land with `TrackingSessionExcluded = 0`
   and correct area, page, referrer domain and device type.
3. Put step 2 on the **bring-up checklist for every hosted/proxied demo host** — it is a precondition, not a
   fix. On an ACL-locked host both settings need the two-step save/persist recipe in
   [`../online-mode.md`](../online-mode.md) "GlobalSettings on an ACL-locked host".

## Live tracking on 10.28.x can never record a second view or a returning visitor

**`TrackingHandlerMiddleware` writes its cookies after the response has started, and the failure is
completely silent.** The middleware is `await Next(context)` *then* `ExecuteTracker()` — registered early but
doing its work on the unwind, many middlewares after the one that writes the body. By then
`Response.HasStarted` is true, so appending `Set-Cookie` throws "Headers are read-only, response has already
started". The catch calls the tracker's own logger, which returns immediately because
`/Globalsettings/System/Tracking/LoggingEnabled` defaults `False`. Nothing is buffered, nothing defers via
`OnStarting`, so **no setting fixes it**.

Consequences to plan around, not to debug:

- Every navigation in one browser context mints a **distinct visitor GUID**. Views-per-visit is permanently
  `1.0`; `VisitorIsReturning` and `PingBackReceived` are never `1`.
- **Turning `LoggingEnabled` on is the diagnostic** — the "An error occurred when setting cookies" rows appear
  from that moment and are absent for every prior day, which is how the silence is proven rather than assumed.
- **A demo that needs a coherent Marketing dashboard must generate its session/view rows directly** rather
  than expecting live browsing to produce them. Real traffic can only ever contribute single-view visits.

## `Tracking/Level` ships a value the enum does not contain

`/Globalsettings/System/Tracking/Level` ships a stock value that is **not a member of `TrackingLevel`**
(`All=0`, `DoNotTrackDevicesAndUnknownBots=1`, `DoNotTrackUndetectedDevices=2`). The parse fails and falls
back silently to `0 = All`. No error is logged and no admin screen flags the mismatch.

**The stored value cannot be trusted as read.** The effective level is `All` unless the key holds `0`, `1` or
`2`. Assert the parse rather than the string if a demo makes any claim about bot/device filtering.

## Never create a table whose name starts with `TrackingSession`

The live tracking table is resolved by name ordering:
`SELECT TOP 1 name FROM sys.tables WHERE name LIKE 'TrackingSession%' ORDER BY name DESC`. With
`TableTimeInterval = None` (the usual demo-host setting) the live names are the plain ones — so **any sibling
that sorts higher silently becomes the table every Insights widget reads**. A backup or staging table named
`TrackingSession_bak` or `TrackingSession<date>` wins that `ORDER BY`.

Prefix backups and staging copies with anything that is **not** `Tracking` (`bak_…`, `<slug>_…`), and assert
`sys.tables` holds exactly one name matching `TrackingSession%` on a demo host.

## Health providers are reachable over `/Admin/Api` — and each check returns its own SQL

The obvious route (`/Admin/UI/Insights/HealthProviderCheckList?ProviderName=<type>`) needs a **browser
session** and 302s to the login form even with a valid bearer — which reads as "health work needs a throwaway
admin browser instrument". It does not. Three plain Management API queries serve the same data and the bearer
satisfies all three:

```
GET /Admin/Api/HealthProviderChecksByProviderName?ProviderName=<type>&PagingSize=200
GET /Admin/Api/HealthProviderCheckByProviderName?ProviderName=<type>&Id=<n>
GET /Admin/Api/HealthProviderCheckDetailsByProviderName?ProviderName=<type>&Id=<n>&PagingSize=<n>
```

**Each check returns `checkWhatWasRun` — the literal SQL the provider executed.** That is the lever: read the
failing check's own query, run it yourself, and fix the rows it names instead of guessing what "failing" means.
One pass took an Ecommerce provider from 10 failing checks of 32 to 0 of 32 that way.

- **`HealthProviderCheckDetailsByProviderName` answers `400` for some ids.** Fall back to executing that
  check's own `checkWhatWasRun` directly rather than treating the 400 as a dead verb.
- Providers are discovered by **reflection**; there is no config gate, so a single broken provider cannot be
  hidden or disabled (see the next section).
- Make "the Ecommerce health provider reports zero failing checks" a pre-sign-off assertion — it is cheap and
  it is a screen presenters open.

## `ContentDataHealthProvider` 500s on every partially-contained database

A known platform defect scoped to **partially contained** SQL Server databases. SQL Server pins the *catalog*
collation of a partially contained database to `Latin1_General_100_CI_AS_KS_WS_SC` regardless of the database
collation. `ContentDataHealthProvider` compares `INFORMATION_SCHEMA.TABLES.TABLE_NAME` (`sysname`, catalog
collation) against `Page.PageItemType` (database collation) with `=` and **no `COLLATE` clause**, so the
comparison can never succeed:

```
Cannot resolve the collation conflict between "Latin1_General_100_CI_AS"
and "Latin1_General_100_CI_AS_KS_WS_SC" in the equal to operation.
```

Non-contained databases take the catalog collation from their own database collation and never hit it.

- **Symptom:** the Content check list returns HTTP 500, and the provider writes a steady stream of
  `[Application/Database]` + `[Application/AdminController]` Error rows per day onto the **customer-visible**
  Monitoring dashboard.
- **Prove the data is clean with a `COLLATE DATABASE_DEFAULT` replay** of the provider's own query on both
  sides of the comparison (`Page.PageItemType`, `Paragraph.ParagraphItemType`, `ItemList.ItemListItemType`).
  A clean replay is the evidence that the 500 is the provider's bug, not broken content.
- **Do not "fix" it at the root.** `ALTER DATABASE SET CONTAINMENT = NONE` orphans contained database users —
  including the site's own connection-string user — and takes the site down. Re-collating the three columns
  needs index drops and risks new implicit conflicts. Patching the assembly is not an option.
- **The durable answer is provisioning:** assert `containment = 0` for the demo database at provisioning time
  so a demo is never built on a partially contained DB, and raise the missing `COLLATE DATABASE_DEFAULT` with
  the vendor.

## Monitoring's "Recent task runs" Status column is derived from history, not from `TaskEnabled`

A newly created, correctly configured scheduled task reads **Disabled** on the Monitoring widget — precisely
at the moment you are trying to confirm the task you just created is live. The widget derives Status from run
history; a task whose `TaskNextRun` still equals `TaskBegin` (i.e. that has never yet fired on the scheduler)
renders Disabled even with `ScheduledTask.TaskEnabled = 1` and a valid `nextRun`.

**Assert `TaskById(id).enabled` and `nextRun > now` instead of scraping the widget**, and do not re-create or
"re-fix" a task on the strength of that column. Task creation semantics (the re-anchoring daily task, the
toggling `TaskToggleActive`, the `Id=0`-creates-every-call trap) are owned by
[`../../../dw-demo-swift/references/sql-direct-seeding.md`](../../../dw-demo-swift/references/sql-direct-seeding.md)
"Scheduled-task creation semantics".

## Nothing ever trims `GeneralLog` or `ScheduledTaskExecution`

**There is no default retention on either table**, and the built-in logs-cleanup scheduled task cannot supply
it: that add-in only clears *file* logs and shadow edits, and on an ACL-locked host even those steps fail with
`UnauthorizedAccessException`. So a site accumulates rows for its entire life. An inherited demo opened its
Monitoring dashboard on hundreds of errors and thousands of events in 24h, off tables holding six figures of
rows going back more than a year.

Any demo that will be shown **from the admin UI** needs an explicit daily log-clear task:

- **Batch the delete** — `DELETE TOP (5000)` in a loop. A first run over several hundred thousand rows will
  otherwise blow the command timeout or hold a long lock. Measured shape: first run seconds-scale, every
  subsequent run sub-second, fully idempotent.
- **Wipe `GeneralLog` completely; trim `ScheduledTaskExecution` to ~2 days** so the *Recent task runs* panel
  stays populated instead of rendering empty.
- **Leave `CommandLog` alone** — it is the API audit trail and has FK children.
- Gate on it: a demo host has the daily task, and `GeneralLog` error count in the last 24h is `0` at the start
  of business. That single assertion is what keeps the owner-visible error tile honest.

Note the interaction with API probing: every unresolvable Management API verb name writes an
`[Application/AddInManager]` Error row onto this same dashboard — see
[`data-access.md`](data-access.md) "Discovering admin screens and their backing queries".

## Cross-references

- [`data-access.md`](data-access.md) — the Management API surface, verb discovery, and the cost of guessing
  verb names against a customer-visible dashboard.
- [`../online-mode.md`](../online-mode.md) — hosted/cloned-host posture: the GlobalSettings apply-vs-persist
  split that a tracking-settings change runs into, and the clone-remediation playbook that clears the error
  volume this file's Monitoring counters report.
- [`../../../dw-demo-swift/references/dashboard-seeding.md`](../../../dw-demo-swift/references/dashboard-seeding.md)
  — seeding the *backend* Marketing dashboards (email send/click history) and the demo clock that keeps
  seeded dates current.
