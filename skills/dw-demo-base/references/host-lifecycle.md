# Host lifecycle authority — start, stop, restart the demo host

Claude controls the `Dynamicweb.Host.Suite` host process autonomously — start, stop, restart without asking. Blocking on the user to run `dotnet run` is friction. This rule is owned by `dw-demo-base` and inherited by every sister skill (`dw-demo-pim`, `dw-demo-swift`, `dw-integration-bc`). A sister skill that pauses mid-flow to ask "please start the host" is violating this contract — and so is one that restarts the host where the cache table names a flush, or stops a process it hasn't verified as this demo's own.

**The enforced form is [`../scripts/Restart-DwHost.ps1`](../scripts/Restart-DwHost.ps1)** — use it rather than retyping the recipes below; it encodes the ownership check, the index-build guard, the lock, the durable start, and the readiness poll in one place. The recipes and traps below stay because they are the contract the script implements (and what you fall back on where the script is not available).

## Flush first — a restart is the last resort, not the default

Nearly every "my change doesn't show" symptom is a stale cache with a flush surface, and flushing keeps the warm state a restart throws away. Work the ladder in [cache-invalidation.md](../../dw-data-access/references/cache-invalidation.md) "When a mutation doesn't show up": (1) the **targeted** `CacheInformationRefresh` named in its post-mutation table → (2) the **bulk flush** (`GET /admin/api/GetServiceCaches` → `POST /admin/api/CacheInformationsRefresh {"Ids":[...]}`) — the same substitution hosted installs are required to use for every "restart required" row → (3) restart only when the symptom survives both flushes or the cache is documented as not service-exposed (e.g. `Searching:Queries`). Restarts that ARE owed (AddIn/`Custom.Mcp` deploys, TFM changes, restart-only cache rows) get **batched — one restart per authoring pass** (the MCP-first → SQL-last → one-restart rule), never one per mutation — and verified to have actually cold-started (the `dotnet run` parent/child trap: killing the parent can leave the real host running with its caches intact).

## Start (durable)

Use PowerShell `Start-Process` so the host survives the spawning subshell, **and redirect stdout/stderr to log files under `<demo>\notes\logs\`** (the canonical log home — see SKILL.md "Artifact hygiene"; never anchor the logs at the Suite folder or the demo root). A hidden `Start-Process` *without* redirection has proven flaky — the spawned process can exit right after kickoff; redirecting keeps it stable and leaves a startup log to read (e.g. to confirm the TFM line — see `../../dw-setup-install/references/install-anatomy.md` §2):

```
powershell -Command "Start-Process -FilePath 'dotnet' -ArgumentList 'run','--launch-profile','Dynamicweb.Host.Suite' -WorkingDirectory '<absolute-path-to-Suite>' -WindowStyle Hidden -PassThru -RedirectStandardOutput '<demo>\notes\logs\host-out.log' -RedirectStandardError '<demo>\notes\logs\host-err.log' | Select-Object -ExpandProperty Id"
```

Returns PID. After kickoff, poll `/Admin` (or `/admin/api/api.json` with bearer) until 200, then proceed.

**Do NOT** use plain `dotnet run` via Bash `run_in_background:true` — when the bash subshell ends, dotnet receives SIGHUP and the host dies after the next idle window. We've seen this fail with exit 127 mid-session.

- **`--no-build` caveat:** `dotnet run --no-build` launches whatever DLL is already in `bin/`. If a prior `dotnet build` *failed*, you silently run the **stale** binary — and a run you intended as a one-shot maintenance arg can instead boot a normal host and lock the exe. Confirm the last build succeeded before relying on `--no-build`.
- **Multi-target host → `dotnet run` needs `--framework`.** A single-target net10 pin (`scaffold.md` §2.1) sidesteps this, but a **multi-target** scaffold (`<TargetFrameworks>net8.0;net10.0</TargetFrameworks>`, e.g. the DemoAgent harness host) makes bare `dotnet run` **block on first boot** with a framework-ambiguity error — nothing starts, no log. Add `'--framework','<tfm>'` to the `ArgumentList` (the DemoAgent harness boots `net8.0`; a host that must load the Backend MCP AddIn uses `net10.0` — §2.1). Pin single-target where you can; pass `--framework` where you can't.
- **Never capture the PID into `$pid`.** `$pid` is a PowerShell **read-only automatic variable** (the current shell's own process id); `$pid = (Start-Process … -PassThru).Id` throws `Cannot overwrite variable pid because it is read-only or constant`. Use any other name (`$hostPid`). The `Select-Object -ExpandProperty Id` form above avoids it — a hand-rolled `$pid = …` capture is the trap.
- **Launch through `dotnet run` only — the apphost exe under `bin/` is not a launch surface.** Starting `bin\Debug\<TFM>\Dynamicweb.Host.Suite.exe` directly boots a host that serves pages but is silently **degraded**: item-based paragraphs fall back to defaults (stock logo/text instead of configured content), every product list renders empty, and nothing is logged — the symptom reads as data loss or broken permissions and costs hours of misdiagnosis. If a running host shows that symptom set, check how it was started before debugging anything else.
- **Silent early exits while sibling DW hosts run:** a freshly started demo host that disappears minutes after start with no exception and no shutdown line in its log — while other DW10 hosts run on the same machine — should be retested with the sibling hosts stopped before any deeper diagnosis. On demo day, run only the demo's own host and confirm sustained uptime (browse a product list and a cart page) before presenting.

## Stop — port-scoped AND ownership-verified

Assume sibling demo hosts are running on this machine. Kill by the **PID returned from Start-Process** when you have it. When you don't, resolve the PID from **THIS demo's launchSettings port** and confirm the owning process's command line points at THIS demo's solution folder before stopping it — every demo scaffolds the same `Dynamicweb.Host.Suite` project, so a name / command-line match (`*Dynamicweb.Host.Suite*`, `Stop-Process -Name dotnet`, killing every `dotnet` PID) kills *sibling* demos' hosts:

```powershell
$port = <PORT>   # HTTPS port from THIS demo's Dynamicweb.Host.Suite/Properties/launchSettings.json
$p = Get-NetTCPConnection -LocalPort $port -State Listen | Select-Object -ExpandProperty OwningProcess -Unique
if ($p) {
  $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$p").CommandLine
  if ($cmd -like "*<absolute-path-to-THIS-demo>*") { Stop-Process -Id $p -Force }
  else { Write-Warning "Port $port is owned by: $cmd — NOT this demo's host. Re-check the port; do not kill." }
}
```

`<PORT>` is the HTTPS port from `Dynamicweb.Host.Suite/Properties/launchSettings.json` (the discover-from-project-files source of truth — see `scaffold.md`). The ownership check costs one command and is what keeps a two-agent, two-host machine safe; a warning from it means the port assumption is wrong — rediscover the port from THIS demo's project files, never widen the kill.

**Never force-kill during an index build.** A `Stop-Process -Force` mid-`BuildIndex` corrupts the index instance being written — leaving a "blocking repair candidate" / "must be recovered" state that a single rebuild does not clear (the recovery recipe is `dw-demo-swift/references/integrity-sweep.md` Check 5). Before stopping the host, confirm no Lucene build is in flight (`GET /admin/api/IndexStatusByRepositoryAndIndexName` — not `Running`); if one is, let it finish or use a graceful stop, and only force-kill a host that is genuinely wedged.

## Visibility ≠ permission

Still announce in one line ("starting host…", "host up at :31873", "restarting to clear plugin cache"). Authorization removes the *ask*, not the *narration*.
