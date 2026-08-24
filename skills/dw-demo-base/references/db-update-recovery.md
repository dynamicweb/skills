# DB update recovery — unstick the `UpdateManager` queue

When a Backend MCP (or any AppStore) AddIn install appears to do nothing — POST returns 200, the
configuration menu never appears, `/admin/<app>` returns 404 — and `wwwroot/Files/System/Log/EventViewer/*.log`
shows repeated `Update failed: <guid> ...UpdateProvider. SqlException` entries, the DW10 update queue is
stuck and every AddIn install is silently rolling back.

**The full recovery procedure is platform-generic and owned by
[`../../dw-setup-upgrade/references/upgrade-mechanics.md`](../../dw-setup-upgrade/references/upgrade-mechanics.md):** the `UpdateManager.ExecuteUpdates()`
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

## Getting the restart this recovery needs — `changeversion.txt` is a version pin, NOT a recycle lever

Mode A ends in "restart the app", and on a cloud-hosted demo you have no process to bounce. Work the control
files in `Files/System/CloudHosting/` (canonical table: [`dw-setup-config`](../../dw-setup-config/SKILL.md)) —
but **`changeversion.txt` is not one of your restart options.**

`changeversion.txt` holds the **release-ring / runtime pin the hosting watcher consumes**, not a restart nonce.
Identical content is ignored — no recycle at all — and **any changed value is a real version migration**. So
"rotate the token to force a recycle" is a version-change recipe in disguise: it moves the host off its pinned
ring, and someone has to notice and revert it. **This supersedes any earlier guidance that the token "must
change" to be effective.**

- Only ever write the host's own pinned ring value, and only when a version change is genuinely intended.
  Record that value in the demo ledger and make the recycle helper **throw** on any other token.
- A forced recycle needs a hosting-side bounce (`recycle.txt` / `restart.txt`). Those are a Dynamicweb Cloud
  watcher affordance: the platform *consumes* the file, so if it is still on disk after upload the watcher is
  not running and **no self-service recycle exists on that host** — a recipe that depends on one is blocked,
  not merely slow. Say so rather than reaching for the version pin.
