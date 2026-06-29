# DB update recovery — unstick the `UpdateManager` queue

When a Backend MCP (or any AppStore) AddIn install appears to do nothing — POST returns 200, the
configuration menu never appears, `/admin/<app>` returns 404 — and `wwwroot/Files/System/Log/EventViewer/*.log`
shows repeated `Update failed: <guid> ...UpdateProvider. SqlException` entries, the DW10 update queue is
stuck and every AddIn install is silently rolling back.

**The full recovery procedure is platform-generic and owned by
[`foundational/setup-upgrade.md`](foundational/setup-upgrade.md):** the `UpdateManager.ExecuteUpdates()`
mechanics, the Mode A (clear `Updates`, restart) vs Mode B (manual schema patch for a buggy shipped
CREATE) triage, the worked `EcomConsolidatedOrderPayments` bug, and the "when this is NOT the right fix"
cases. Work that reference for the mechanics.

## Demo-specific note — Mode A is safe on a demo host

The one caveat in `setup-upgrade.md` that matters for a demo build: Mode A re-runs the entire update
queue, which on a **populated/production** DB can corrupt data via a destructive migration. **For a
Dynamicweb demo, the DB is always fresh and never holds real customer data at this stage** — baseline
deserialization happens *after* this skill's setup gates pass — so the "fresh DB" path applies and Mode
A is safe to run without the production-DB precautions. Reach for Mode A first when the triage points to
a queue-stuck (not buggy-CREATE) failure.
