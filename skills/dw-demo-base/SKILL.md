---
name: dw-demo-base
type: flow
group: demo
description: Foundation skill for Dynamicweb 10 demos — scaffolds the dw10-suite host, wires Backend MCP and the localhost TLS bypass, and drops the customisations and customer-context guardrails. Does NOT load a baseline. Use FIRST on any new Dynamicweb demo, when MCP tools fail to load ("Failed to connect", silent tools/list), on a fresh Windows machine, when auditing the customisation budget, or when the demo targets a hosted/cloud install reached only by URL + Admin API key (references/online-mode.md). Also owns the orchestrator abstraction (GSD primary vs the native `/demo:*` commands) — "drive the demo build", "run the demo natively", "GSD vs native" route to references/orchestrator.md — and the maintainer fold-back workflow — "fold this into the skill", "save this back to the plugin" route to references/iterate-plugin.md. Sister skills (dw-demo-pim, dw-demo-swift, dw-demo-headless, dw-demo-erp, dw-integration-bc) are Use AFTER, never standalone. `<demo>\customer-context\` is read-only.
---

# Dynamicweb Demo Base Skill

The foundation skill for any Dynamicweb 10 demo. **Use FIRST** on every new Dynamicweb demo. Sister skills (`dynamicweb-pim-demo`, `dynamicweb-swift-demo`) inherit the `.mcp.json`, `CUSTOMISATIONS.md`, and TLS bypass that this skill establishes -- they are **Use AFTER**, never standalone.

This SKILL.md is a nav layer only. Each step of the canonical flow links to a `references/<topic>.md` that owns the verbatim recipe, gotchas, and verification gate for that topic.

## How to run me

This skill holds **domain knowledge**, not build sequencing. The thing that sequences the
phases and holds the gates is the **orchestrator**, and it is swappable:

- **Under GSD** — GSD injects this skill into its agents and owns the phase order (register it
  via the `agent_skills` block in `assets/agent_skills.config.json`).
- **Under the native command set** — the `/demo:*` slash commands (scaffolded into the demo
  project) invoke this skill and hold the one human gate.
- **Standalone** — no GSD, no `/demo:*` commands: the skill's own **lightweight harness** guards
  the canonical flow below (walk it in order, gate every step, persist progress to
  `.demo/<slug>/flow-state.json`, refuse to declare done before a gate passes).

The orchestrator abstraction (modes, GSD detection / deference, `--standalone`, the strictness
gradient, acceptance criteria) is owned by [references/orchestrator.md](references/orchestrator.md).
Every sister demo skill carries the same "how to run me" header and defers to that reference.

## Environment fork — local install vs hosted (online) install

The canonical flow below assumes a **local install** (scaffold + SQL Express on the demo machine). When the engagement instead hands you a **site URL + Admin API bearer key** — a vendor-hosted/cloud install with no machine to scaffold on — fork to [references/online-mode.md](references/online-mode.md), which owns the deltas: which canonical steps to skip, the session-start probe (tool availability on hosted installs is **version-dependent** — MCP may or may not be exposed; always probe, never assume), the Management API recipe pack that substitutes for MCP/SQL recipes, and the shared-install discipline. The always-on rules (surface priority, guarded writes, customer-context, demo philosophy) apply in both modes.

## Canonical end-to-end flow

Walk every step in order — skip none. Each step's reference contains its own verification gate; the skill **refuses to declare setup complete** until every gate passes.

1. **Verify the environment is build-ready** -> [references/setup-checks.md](references/setup-checks.md)
   Probes the `NODE_TLS_REJECT_UNAUTHORIZED` env var, the **.NET 10 SDK** (mandatory — rationale in `references/foundational/setup-install.md` §2), `Dynamicweb.ProjectTemplates`, the SQL Express service, MSDTC, the `gh` CLI (present + authenticated — needed to download baseline/pack/theme releases), and that the demo's `<demo-root>\baselines\` folder is writable. Also captures the demo's target **DW10 version** and **Swift version** (the versions prompt — see "Baseline data" below). Posture: verify + opt-in fix for cheap fixes (env var); print-and-link only for install-grade fixes (SDK, SQL Express).

2. **Scaffold the per-demo project** -> [references/scaffold.md](references/scaffold.md)
   `dotnet new dw10-suite --name Dynamicweb.Host.Suite`. The `--name Dynamicweb.Host.Suite` is mandatory; sister-skill path discovery depends on this name. Suite version is whatever the template + `dotnet restore` resolve — version policy is out of scope for this skill.

3. **Wire MCP and fix the two-layer TLS bypass** -> [references/mcp-setup.md](references/mcp-setup.md) + [references/tls-bypass.md](references/tls-bypass.md) + [references/browser-automation.md](references/browser-automation.md)
   Install the user-scope Browser MCP first (`@playwright/mcp`, machine-level and idempotent — its tools are the scaffold's action surface on the admin UI), write `.mcp.json`, apply both TLS-bypass layers, then drive the admin UI via the Browser MCP to create the MCP configuration and capture the shown-once API key (Authentication method = API Key; Claude.ai OAuth is fallback-only; headless code recipe when the UI is unreachable, ask the user only as last resort). The MCP verification gate: `claude mcp list` shows `Connected` AND `ToolSearch +dynamicweb` returns >200 tools.

4. **Drop the guardrail artefacts** -> `references/customisations.md` + `references/customer-context.md`
   Stage `<demo>\CUSTOMISATIONS.md` (the customisation ledger) and ensure the `<demo>\customer-context\` read-only contract is wired into the per-demo `CLAUDE.md`. The `references/audit-customisations.md` recipe produces paste-ready end-of-phase audit content. When running **without GSD**, also copy the native orchestrator commands from `assets/commands/demo/` into the demo project's `.claude/commands/demo/` so `/demo:scaffold|impact|build|status` are available (see [references/orchestrator.md](references/orchestrator.md)).

## Baseline data — explicit non-step

Loading reference content into the project DB is **NOT** part of this skill's canonical flow. Three separate paths follow base, depending on demo type:

- **PIM demo** -> start with a blank/fresh demo DB; the PIM skill's modelling recipes build content from scratch via MCP. No deserialize step. See [`dynamicweb-pim-demo/SKILL.md`](../dw-demo-pim/SKILL.md).
- **Swift demo** -> deserialize the Swift content baseline downloaded per-demo into `<demo-root>\baselines\<baseline>\` (see the versions prompt + download model below) via the Serializer. Owned end-to-end by [`dynamicweb-swift-demo/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) + [`dynamicweb-swift-demo/references/integrity-sweep.md`](../dw-demo-swift/references/integrity-sweep.md). Prerequisite: the Serializer is installed per [`references/serializer-reference.md`](references/serializer-reference.md) "Installation".
- **Headless demo** -> deserialize the separate, presentation-agnostic `headless/2.3` baseline (its own product line, no shared item-type rows with Swift; downloaded per-demo into `<demo-root>\baselines\` like any baseline — see the versions prompt + download model below) for a Next.js storefront that reads the DW10 Delivery API. Owned by [`dynamicweb-headless-demo/references/headless-baseline.md`](../dw-demo-headless/references/headless-baseline.md); backend config in [`headless-backend.md`](../dw-demo-headless/references/headless-backend.md). Same Serializer prerequisite.

The Serializer install steps live in base so any sister skill can pull them; the act of deserializing is Swift- or headless-specific.

### Versions prompt + per-demo artifact download

Demo artifacts are **not** kept in a shared machine-wide vault. Each demo downloads exactly the versions it targets into its own `<demo-root>\baselines\` folder, so two demos on the same machine can pin different versions without collision. Before any artifact is fetched, ask the user two things (record both in the demo's `CUSTOMISATIONS.md` for reproducibility):

1. **DW10 version** — the platform version the demo host runs (drives baseline/pack compatibility checks).
2. **Swift version** — e.g. `2.3` (drives the baseline/theme release tags and the Swift design-package clone tag `v<version>.0`).

**Tag resolution — release tags carry the patch digit.** The user answers a *minor* version (`2.3`); actual release tags are full semver (`swift/2.3.1`, `swift/2.3.0`). Never `gh release download swift/2.3` literally — resolve the **latest patch for the requested minor** first, then download that tag:

```powershell
$minor = "2.3"  # from the versions prompt
$tag = gh release list --repo <owner/repo> --limit 100 --json tagName -q '.[].tagName' |
  Where-Object { $_ -like "swift/$minor.*" } |
  Sort-Object { [version]($_ -replace '^swift/','') } -Descending |
  Select-Object -First 1
if (-not $tag) { throw "No swift/$minor.* release found — check the repo's Releases page." }
gh release download $tag --repo <owner/repo> --dir "<demo-root>\baselines\_dl"
```

Record the RESOLVED tag (not just the minor) in `CUSTOMISATIONS.md` — that exact tag is the demo's reproducibility pin. The same latest-patch rule applies to theme release tags; feature-pack tags (`packs/<name>/<version>`) are picked as full versions directly.

With those answers, artifacts resolve per-demo from the ecosystem distribution repos:

| Artifact | Source (default) | Lands at | Fetched by |
|---|---|---|---|
| Serialized baseline | `https://github.com/justdynamics/Truvio.Commerce.Serializer.Baselines` — packages under `packages/<product>/<version>/` on main; per-package release tags | `<demo-root>\baselines\<baseline>\` | [`dynamicweb-swift-demo/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) §3 |
| Demo theme / style assets | `https://github.com/justdynamics/Truvio.Commerce.DemoThemes` — release zips tagged `swift/<version>` (per-theme) | `<demo-root>\baselines\themes\` | [`dynamicweb-swift-demo/references/styles-assets.md`](../dw-demo-swift/references/styles-assets.md) |
| Feature pack | `https://github.com/justdynamics/Truvio.Commerce.FeaturePacks` — releases tagged `packs/<name>/<version>` | `<demo-root>\baselines\feature-packs\<name>\<version>\` | [`dynamicweb-swift-demo/references/pack-activation.md`](../dw-demo-swift/references/pack-activation.md) |
| Swift design package | local clone of `https://github.com/dynamicweb/Swift` (tag `v<version>.0`) | `<demo-root>\dw-swift\` | [`dynamicweb-swift-demo/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) "Design-package deploy" |

Downloads use the `gh` CLI (`gh release download`) — hence the setup-checks probe that `gh` is present and authenticated. The baseline and feature-pack source repos each default to the URL above and are overridable per machine via `$env:DW_BASELINE_REPO` / `$env:DW_PACKS_REPO` (owner/name form) when a team mirrors or forks the distribution.

## Where to find things

| If you need to... | Read this reference |
|---|---|
| Understand how a demo build is **driven** — the orchestrator abstraction (GSD primary vs the native `/demo:*` command set), GSD detection / deference + `--standalone`, the `agent_skills` keystone, the strictness gradient, and the shared acceptance criteria | references/orchestrator.md |
| Verify a fresh machine is build-ready (incl. the MSDTC check that AreaCopy `TransactionException`s trace back to) | references/setup-checks.md |
| **Build on a hosted/cloud install** (URL + Admin API key only — no scaffold, no SQL, no host restart; Management API create-vs-update semantics, binder shapes, upload, variants, cache-refresh-as-restart, known API gaps) | **references/online-mode.md** |
| Ask the demo's DW10 + Swift versions and download baselines/themes/packs per-demo | "Versions prompt + per-demo artifact download" above + references/setup-checks.md |
| Scaffold the project | references/scaffold.md |
| Get MCP working (and verify it) | references/mcp-setup.md |
| Understand the TLS bypass | references/tls-bypass.md |
| Install Browser MCP (`@playwright/mcp`) for verification flows; recover from `browserType.launchPersistentContext` / browser-launch errors (Chromium channel fallback, Node driver) | references/browser-automation.md |
| **Read a storefront screenshot critically** — programmatic defect detectors (horizontal overflow, broken/stretched images, whitespace bands), the interaction pass for dead controls, the per-screenshot eyeball checklist, symptom→fix routing, and the per-page definition of done. Run on every demo-critical page before declaring it polished. | **references/visual-qa.md** |
| See which vendor skill-repo patterns this plugin adopts vs deviates from | references/vendor-patterns.md |
| The surface contract — scaffold vs build phases, the surfaces per instance type (local / hosted / headless), why SQL-cloning structural trees fails, why the admin UI is verification-only during the build | references/surface-priority.md |
| Generic demo-storytelling tactics (audience framing, one-source-N-shapes, the customer-wording glossary) | references/demo-tactics.md |
| Manage the customisation budget | references/customisations.md |
| Audit customisations at end of phase | references/audit-customisations.md |
| Honor the customer-context read-only contract | references/customer-context.md |
| Recover from silent AddIn install failure (stuck `UpdateManager` queue) | references/db-update-recovery.md |
| Install the DW Serializer in the demo host; triage Serializer failure patterns; check baseline compatibility | references/serializer-reference.md ("Installation") |
| Understand Serializer internals — these live upstream in the Serializer repo's own docs; the reference carries the pointer block | references/serializer-reference.md ("Internals — upstream pointer block") |
| Run a Swift baseline deserialize (Swift demos only) | [`dynamicweb-swift-demo/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) |
| Verify post-deserialize integrity (Swift demos only) | [`dynamicweb-swift-demo/references/integrity-sweep.md`](../dw-demo-swift/references/integrity-sweep.md) |
| **Fold a demo-build learning back into the repo** (route foundational-vs-demo -> sanitize -> validate -> bump `metadata.version` -> atomic commit on a branch -> open PR -> refresh marketplace clone after merge). Maintainer-only, PR-based. | references/iterate-plugin.md |

## Folding demo-build learnings back into the plugin (maintainer-only)

The whole point of authoring these skills locally and publishing them as a versioned plugin is **so demo-build learnings don't decay**. When a non-trivial discovery surfaces mid-demo, capture it back **while the conversation context is still rich** — not from notes a week later.

Trigger phrases — when the user says any of these mid-demo, route to [references/iterate-plugin.md](references/iterate-plugin.md):

- "fold this into the skill" / "fold this learning back"
- "save this back to the plugin"
- "update the plugin from this demo"
- "publish this update"
- "this is worth keeping — add it to the skill"

The reference owns the full workflow end-to-end, including the load-bearing first step: **route the learning before editing** — a platform truth folds *up* into the owning foundational skill (fully sanitized), demo-craft folds into a demo skill, and a learning that needs the customer's name stays demo-local. Every fold lands via a **PR** (one learning = one atomic commit = one PR), never a direct push. It is maintainer-only; consumers of the plugin can ignore it — or open a PR.

## Host lifecycle authority

Claude controls the `Dynamicweb.Host.Suite` host process autonomously — start, stop, restart without asking. Blocking on the user to run `dotnet run` is friction.

**Flush first — a restart is the last resort, not the default.** Nearly every "my change doesn't show" symptom is a stale cache with a flush surface, and flushing keeps the warm state a restart throws away. Work the ladder in [references/foundational/cache-invalidation.md](references/foundational/cache-invalidation.md) "When a mutation doesn't show up": (1) the **targeted** `CacheInformationRefresh` named in its post-mutation table → (2) the **bulk flush** (`GET /admin/api/GetServiceCaches` → `POST /admin/api/CacheInformationsRefresh {"Ids":[...]}`) — the same substitution hosted installs are required to use for every "restart required" row → (3) restart only when the symptom survives both flushes or the cache is documented as not service-exposed (e.g. `Searching:Queries`). Restarts that ARE owed (AddIn/`Custom.Mcp` deploys, TFM changes, restart-only cache rows) get **batched — one restart per authoring pass** (the MCP-first → SQL-last → one-restart rule), never one per mutation — and verified to have actually cold-started (the `dotnet run` parent/child trap: killing the parent can leave the real host running with its caches intact).

- Start (durable): use PowerShell `Start-Process` so the host survives the spawning subshell, **and redirect stdout/stderr to log files**. A hidden `Start-Process` *without* redirection has proven flaky — the spawned process can exit right after kickoff; redirecting keeps it stable and leaves a startup log to read (e.g. to confirm the TFM line — see `references/foundational/setup-install.md` §2):
  ```
  powershell -Command "Start-Process -FilePath 'dotnet' -ArgumentList 'run','--launch-profile','Dynamicweb.Host.Suite' -WorkingDirectory '<absolute-path-to-Suite>' -WindowStyle Hidden -PassThru -RedirectStandardOutput '<Suite>\out.log' -RedirectStandardError '<Suite>\err.log' | Select-Object -ExpandProperty Id"
  ```
  Returns PID. After kickoff, poll `/Admin` (or `/admin/api/api.json` with bearer) until 200, then proceed.
  **Do NOT** use plain `dotnet run` via Bash `run_in_background:true` — when the bash subshell ends, dotnet receives SIGHUP and the host dies after the next idle window. We've seen this fail with exit 127 mid-session.
  - **`--no-build` caveat:** `dotnet run --no-build` launches whatever DLL is already in `bin/`. If a prior `dotnet build` *failed*, you silently run the **stale** binary — and a run you intended as a one-shot maintenance arg can instead boot a normal host and lock the exe. Confirm the last build succeeded before relying on `--no-build`.
  - **Launch through `dotnet run` only — the apphost exe under `bin/` is not a launch surface.** Starting `bin\Debug\<TFM>\Dynamicweb.Host.Suite.exe` directly boots a host that serves pages but is silently **degraded**: item-based paragraphs fall back to defaults (stock logo/text instead of configured content), every product list renders empty, and nothing is logged — the symptom reads as data loss or broken permissions and costs hours of misdiagnosis. If a running host shows that symptom set, check how it was started before debugging anything else.
  - **Silent early exits while sibling DW hosts run:** a freshly started demo host that disappears minutes after start with no exception and no shutdown line in its log — while other DW10 hosts run on the same machine — should be retested with the sibling hosts stopped before any deeper diagnosis. On demo day, run only the demo's own host and confirm sustained uptime (browse a product list and a cart page) before presenting.
- Stop — **port-scoped AND ownership-verified; assume sibling demo hosts are running on this machine.** Kill by the **PID returned from Start-Process** when you have it. When you don't, resolve the PID from **THIS demo's launchSettings port** and confirm the owning process's command line points at THIS demo's solution folder before stopping it — every demo scaffolds the same `Dynamicweb.Host.Suite` project, so a name / command-line match (`*Dynamicweb.Host.Suite*`, `Stop-Process -Name dotnet`, killing every `dotnet` PID) kills *sibling* demos' hosts:
  ```powershell
  $port = <PORT>   # HTTPS port from THIS demo's Dynamicweb.Host.Suite/Properties/launchSettings.json
  $p = Get-NetTCPConnection -LocalPort $port -State Listen | Select-Object -ExpandProperty OwningProcess -Unique
  if ($p) {
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$p").CommandLine
    if ($cmd -like "*<absolute-path-to-THIS-demo>*") { Stop-Process -Id $p -Force }
    else { Write-Warning "Port $port is owned by: $cmd — NOT this demo's host. Re-check the port; do not kill." }
  }
  ```
  `<PORT>` is the HTTPS port from `Dynamicweb.Host.Suite/Properties/launchSettings.json` (the discover-from-project-files source of truth — see `references/scaffold.md`). The ownership check costs one command and is what keeps a two-agent, two-host machine safe; a warning from it means the port assumption is wrong — rediscover the port from THIS demo's project files, never widen the kill.
- Visibility ≠ permission: still announce in one line ("starting host…", "host up at :31873", "restarting to clear plugin cache"). Authorization removes the *ask*, not the *narration*.

This rule is owned by this skill and inherited by every sister skill (`dynamicweb-pim-demo`, `dynamicweb-swift-demo`, `dynamicweb-pim-for-bc`). A sister skill that pauses mid-flow to ask "please start the host" is violating this contract — and so is one that restarts the host where the cache table names a flush, or stops a process it hasn't verified as this demo's own.

## Surface priority for CREATES (always-on rule)

**Creating things in DW10 has a strict surface priority, split into two phases by the MCP verification gate. Violating it has bitten this skill author multiple times — keeping the rule explicit at base level so every sister skill inherits it.**

**Scaffold phase** (local installs, before the MCP verification gate passes): the build surfaces don't exist yet — creating them is the point. The admin UI driven via the Browser MCP (Playwright) **is an action surface** here, scoped to the bootstrap one-clicks: create the MCP configuration + capture the shown-once API key, create the Management API key, AppStore install when the csproj route is closed, portal downloads. Ladder: script/CLI/filesystem → Admin API (when a bearer exists) → admin UI via Browser MCP → headless code recipe → ask the user (only when every automated surface is unreachable). Detail: [references/surface-priority.md](references/surface-priority.md).

**Build phase** (after the gate — and hosted/headless installs from the first request):

| Surface | Use for | Why |
|---------|---------|-----|
| 1. **MCP (`dynamicweb-commerce-mcp`)** | **Default — try this first for anything that creates a structural row** (pages, paragraphs, areas, products, groups, orders, users, etc.) | Calls DW's domain services. Triggers ALL the bookkeeping a UI click would: ItemRelation cloning, ItemList propagation, sibling-page linking, cache invalidation, index refresh, child-row creation, validation. ~260 tools. |
| 2. **Management API** (`/admin/api/...`) | Fallback when MCP doesn't expose the operation. Usually admin-grade actions: `BuildIndex`, `CacheInformationRefresh`, `FeatureManagementToggle`, anything in `/admin/api/docs/`. | Same DW domain services as MCP, just a different transport. |
| 3. **Direct SQL** (`sqlcmd ...`, local installs only) | **LAST RESORT** — only for: (a) cleanup/teardown, (b) bulk schema-drift fixes, (c) reading data, (d) cases where you've confirmed both higher surfaces don't support the operation and a vendor patch is the only alternative. | Bypasses every DW service. Misses bookkeeping. Creates orphans. Corrupts caches. **You will not figure out the full bookkeeping for a non-trivial create via SQL — DW does too much per service call.** |

The **admin UI is verification-only during the build** — navigate, screenshot, DOM-grep to confirm a change landed. Every admin-UI click is an Admin API call underneath (the admin SPA is a client of `/admin/api/...`), so a "UI-only" operation means the endpoint hasn't been found yet. (The Backend MCP AddIn install is a scaffold-phase concern — the deterministic default is a NuGet `PackageReference`; see [references/foundational/extend-mcp-tools.md](references/foundational/extend-mcp-tools.md) §1. AppStore is its last resort, not its first.)

**Pattern to follow (build phase):**
1. Try MCP. If the tool name suggests it (e.g. `copy_area`, `copy_page`, `save_pages`), use it.
2. If MCP errors or doesn't expose the operation, work the Management API — the operation exists there. Discover the endpoint via the `/admin/api/docs/` catalogue, the `dw10source` command classes, or read-only Playwright network watching (`mcp__playwright__browser_network_requests`), then call it as surface 2.
3. Local installs only: after 1-2 are exhausted, reach for SQL — and even then, prefer SQL for cleanup of a previous bad attempt rather than for the create.

Why SQL-cloning structural trees specifically is forbidden (the bookkeeping it misses, the 10-screens-later breakage), plus the full phase × instance-type matrix: [references/surface-priority.md](references/surface-priority.md). The platform mechanism the discipline rests on — what an MCP create's domain-service call actually does (ItemRelation cloning, ItemList propagation, cache/index refresh) and why the admin UI is a SPA over `/admin/api/...` — is in [references/foundational/extend-mcp-tools.md](references/foundational/extend-mcp-tools.md) §5.

**Hosted/online installs:** there is no scaffold phase (credentials are handed over) and surface 3 does not exist — no SQL, ever. Surface 1 is version-dependent (probe first — never assume MCP is present or absent). The priority collapses to MCP-if-present → Management API → ask the user for the rare operation neither exposes; the API recipes that replace the SQL rungs live in [references/online-mode.md](references/online-mode.md).

This rule is owned by this skill and inherited by every sister skill.

## Two guarded-writes (always-on rules)

These are mandatory write-time preflight rules. They share one mental model -- "guarded write triggered by path glob" -- with two glob patterns and two outcomes.

1. **Custom code path** (the customisations-ledger preflight -- three branches). Before writing any file matching:
   - `Dynamicweb.Host.Suite/Controllers/**/*.cs`
   - `Providers/**`
   - `*Controller.cs`

   **Invoke `AskUserQuestion`** with this exact shape:
   > "This adds a custom controller. Reason? Add to `CUSTOMISATIONS.md`? [Approve+log / Refactor instead / Cancel]"

   - **Approve+log** -> append a date-prefixed row to `<demo>\CUSTOMISATIONS.md` and proceed.
   - **Refactor instead** -> abort the write; suggest configuration / extension points.
   - **Cancel** -> abort.

   See `references/customisations.md` for the ledger template, the audit recipe, and what does NOT count as a customisation.

2. **Customer-context path** (the customer-context read-only contract -- hard abort, no approve branch). Before writing any file whose path contains `customer-context\` (case-insensitive):

   > "ABORT -- this would write to a read-only customer-context folder. The `customer-context\` directory holds intro-call materials, call summaries, and customer-supplied artefacts that must not be modified by demo-build automation. Did you mean `<demo>\notes\` (your own working notes) or `<demo>\extracts\` (transformed/derived data extracted FROM customer-context)?"

   See `references/customer-context.md` for the long-form rationale.

**Rationale:** Many B2B customers are fleeing heavily-customised legacy commerce/ERP stacks; the customisation budget is itself a pitch beat at the demo's closing slide. Every approved row is a deliberate trade-off; every Cancel/Refactor is a small win.

## Demo philosophy — go deep, not wide

Demo time is short; condensed beats spread. Default to a single deep storyline rather than a broad surface tour — every login, channel, locale, and customer-center section the user has to scan during the live demo is time stolen from the part you actually want to land.

**Default postures (sister skills enforce the specifics):**

- **Logins / personas — floor of 2.** One buyer + one CSR so impersonation has somewhere to land. Don't scaffold a roster of personas you won't have time to log into. Owned by `dynamicweb-swift-demo`.
- **Shops / channels — 1 + 1.** One shop plus the channel most relevant to the customer's pitch. Don't add a second channel of equal weight. Owned by `dynamicweb-pim-demo`.
- **Locale — single home market.** US-only for a US customer (EN/USD), DE-only for a DACH customer, etc. Add a second language/currency only when the customer's case explicitly demands it. Owned by `dynamicweb-pim-demo`.
- **Customer-center sections, paragraph types, page presets — storyline-driven.** Scaffold the ones the storyline actually visits, not the ones the platform supports. Owned by `dynamicweb-swift-demo`.

**Product catalogue is the deliberate exception — go deep AND wide there.** Rich product data (variants, BOM bundles, completeness rules, assortments, ample SKUs across categories) is cheap to produce via MCP and makes the demo feel real instead of sketched. The "narrow it down" rule does not apply to product modelling — see `dynamicweb-pim-demo` for the modelling depth recipes.

When in doubt: every login / channel / locale / customer-center section must justify itself against demo minutes. A product family does not need to justify itself. Generic storytelling tactics (audience framing, one-source-N-shapes, speak the customer's words): [references/demo-tactics.md](references/demo-tactics.md).

## Sister skills

- **`dynamicweb-pim-demo`** -- PIM modelling, structural mental model (shops vs channels, GroupType, repositories, variants, BOM, channels + feeds, assets, product categories), MCP/API/SQL/filesystem decision matrix. **Use AFTER** `dynamicweb-demo-base`.
- **`dynamicweb-swift-demo`** -- Swift frontend (templates, paragraph types, B2B customer-center scaffolding, baseline deserialize). **Use AFTER** `dynamicweb-demo-base`.
- **`dynamicweb-erp-demo`** -- ERP integration (source/target rule, DB-staged mock, scenarios-first planning). **Use AFTER** `dynamicweb-demo-base`.
- **`dynamicweb-pim-for-bc`** -- live BC connector via ngrok + AppStore connector. **Use AFTER** `dynamicweb-demo-base`.

A sibling skill that runs without `dynamicweb-demo-base`'s outputs (no `.mcp.json`, no `CUSTOMISATIONS.md`) silently no-ops or produces broken artefacts. The "Use FIRST" routing wording in this skill's description and the "Use AFTER" markers in the sister skills are the inoculation.

## Reference-content layout

Demo artifacts (baselines, themes, feature packs) are downloaded per-demo into the demo's own `<demo-root>\baselines\` folder — see "Versions prompt + per-demo artifact download" above. There is no shared machine-wide vault; each demo owns the exact versions it targets.

Two read-only reference sources are **local clones**, not downloads, and their location is per-machine — **ask or discover it, never hardcode**:

- **DW10 source** — a local clone of the DW10 source, used for deep schema/internals search (`src/Features/Ecommerce`, `Dynamicweb.Products.UI`, etc.). Where a reference says "search the DW10 source", it means this clone.
- **Swift design package** — a local clone of `https://github.com/dynamicweb/Swift` at the demo's Swift version (`<demo-root>\dw-swift\`), the source of item-type XMLs, templates, styles, and icons for the deserialize.

## Path-resolution rule

Paths in this skill (and sister skills) resolve under the demo's own root (`<demo-root>\baselines\...`) or a per-machine local clone whose location is asked/discovered. Per-machine hardcoded literals (legacy paths under user-specific source folders or sibling solution folders) are a known anti-pattern; the existing `dynamicweb-pim-demo` skill still carries some as a cautionary cleanup target.

## Discover-from-project-files rule

Port, DB name, and Management API bearer token vary per project. Read them from project files and chat -- never hardcode.

| What | Where to read it |
|---|---|
| HTTPS port + host URL | `Dynamicweb.Host.Suite/Properties/launchSettings.json` (`applicationUrl`, HTTPS profile) |
| Database name | `Dynamicweb.Host.Suite/GlobalSettings.Database.config` (`Database=` or `Initial Catalog=`) |
| **MCP API key** (Authorization header for `/admin/mcp`) | Generated once in the admin UI (Settings → Integration → MCP configurations); full capture + storage contract in `references/mcp-setup.md` Steps 3-3b and 6. |
| **Management API bearer token** (Authorization header for `/admin/api/...`) | Captured via `AskUserQuestion` from chat (format `CLAUDE.<hex>`); storage contract (per-demo Claude memory, never env vars, never committed) is canonical in `references/mcp-setup.md` Step 6. |

## Baseline-drift self-diagnosis rule

When grep results in skill text contradict the live baseline, consider "the baseline has rolled since this skill was authored" as a candidate cause. Cross-check the downloaded baseline's release tag / version against the demo's Swift version before assuming the skill is correct. Reality wins; the skill is the second source of truth.




