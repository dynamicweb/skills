---
name: dw-demo-base
type: flow
group: demo
description: Foundation skill for Dynamicweb 10 demos — scaffolds the dw10-suite host, wires Backend MCP and the localhost TLS bypass, and drops the customisations and customer-context guardrails. Does NOT load a baseline. Use FIRST on any new Dynamicweb demo, when MCP tools fail to load ("Failed to connect", silent tools/list), on a fresh Windows machine, when auditing the customisation budget, or when the demo targets a hosted/cloud install reached only by URL + Admin API key (references/online-mode.md). Also owns the maintainer fold-back workflow -- "fold this into the skill", "save this back to the plugin", "publish this update" route to references/iterate-plugin.md. Sister skills (dw-demo-pim, dw-demo-swift, dw-demo-erp, dw-integration-bc) are Use AFTER, never standalone. `<demo>\customer-context\` is read-only.
---

# Dynamicweb Demo Base Skill

The foundation skill for any Dynamicweb 10 demo. **Use FIRST** on every new Dynamicweb demo. Sister skills (`dynamicweb-pim-demo`, `dynamicweb-swift-demo`) inherit the `.mcp.json`, `CUSTOMISATIONS.md`, vault resolution, and TLS bypass that this skill establishes -- they are **Use AFTER**, never standalone.

This SKILL.md is an orchestrator only. Each step of the canonical flow links to a `references/<topic>.md` that owns the verbatim recipe, gotchas, and verification gate for that topic.

## Environment fork â€” local install vs hosted (online) install

The canonical flow below assumes a **local install** (scaffold + SQL Express + vault on the demo machine). When the engagement instead hands you a **site URL + Admin API bearer key** â€” a vendor-hosted/cloud install with no machine to scaffold on â€” fork to [references/online-mode.md](references/online-mode.md), which owns the deltas: which canonical steps to skip, the session-start probe (tool availability on hosted installs is **version-dependent** â€” MCP may or may not be exposed; always probe, never assume), the Management API recipe pack that substitutes for MCP/SQL recipes, and the shared-install discipline. The always-on rules (surface priority, guarded writes, customer-context, demo philosophy) apply in both modes.

## Canonical end-to-end flow

DO NOT skip any step. Each step's reference contains its own verification gate; the skill **refuses to declare setup complete** until every gate passes.

1. **Verify the environment is build-ready** -> [references/setup-checks.md](references/setup-checks.md)
   Probes env vars (`DW_VAULT`, `NODE_TLS_REJECT_UNAUTHORIZED`), the **.NET 10 SDK** (mandatory â€” rationale in `references/scaffold.md` Â§2.1), `Dynamicweb.ProjectTemplates`, the SQL Express service, MSDTC, and the five vault slots from `$env:DW_VAULT\INDEX.md`. Posture: verify + opt-in fix for cheap fixes (env vars); print-and-link only for install-grade fixes (SDK, SQL Express).

2. **Scaffold the per-demo project** -> [references/scaffold.md](references/scaffold.md)
   `dotnet new dw10-suite --name Dynamicweb.Host.Suite`. The `--name Dynamicweb.Host.Suite` is mandatory; sister-skill path discovery depends on this name. Suite version is whatever the template + `dotnet restore` resolve â€” version policy is out of scope for this skill.

3. **Wire MCP and fix the two-layer TLS bypass** -> [references/mcp-setup.md](references/mcp-setup.md) + [references/tls-bypass.md](references/tls-bypass.md) + [references/browser-automation.md](references/browser-automation.md)
   Write `.mcp.json`, apply both TLS-bypass layers, create the admin-UI MCP configuration manually (Authentication method = API Key; Claude.ai OAuth is fallback-only), and install the user-scope Browser MCP (`@playwright/mcp`, machine-level and idempotent). The MCP verification gate: `claude mcp list` shows `Connected` AND `ToolSearch +dynamicweb` returns >200 tools.

4. **Drop the guardrail artefacts** -> `references/customisations.md` + `references/customer-context.md`
   Stage `<demo>\CUSTOMISATIONS.md` (the customisation ledger) and ensure the `<demo>\customer-context\` read-only contract is wired into the per-demo `CLAUDE.md`. The `references/audit-customisations.md` recipe produces paste-ready end-of-phase audit content.

## Baseline data â€” explicit non-step

Loading reference content into the project DB is **NOT** part of this skill's canonical flow. Two separate paths follow base, depending on demo type:

- **PIM demo** -> start with a blank/fresh demo DB; the PIM skill's modelling recipes build content from scratch via MCP. No deserialize step. See [`dynamicweb-pim-demo/SKILL.md`](../dw-demo-pim/SKILL.md).
- **Swift demo** -> deserialize the Swift content baseline from `$env:DW_VAULT\serialized-data\<baseline>\` via the Serializer. Owned end-to-end by [`dynamicweb-swift-demo/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) + [`dynamicweb-swift-demo/references/integrity-sweep.md`](../dw-demo-swift/references/integrity-sweep.md). Prerequisite: the Serializer is installed per [`references/serializer-reference.md`](references/serializer-reference.md) "Installation".

The Serializer install steps live in base so any sister skill can pull them; the act of deserializing is Swift-specific.

## Where to find things

| If you need to... | Read this reference |
|---|---|
| Verify a fresh machine is build-ready (incl. the MSDTC check that AreaCopy `TransactionException`s trace back to) | references/setup-checks.md |
| **Build on a hosted/cloud install** (URL + Admin API key only â€” no scaffold, no SQL, no host restart; Management API create-vs-update semantics, binder shapes, upload, variants, cache-refresh-as-restart, known API gaps) | **references/online-mode.md** |
| Detect vault drift across machines | references/compare-vault.md |
| Scaffold the project | references/scaffold.md |
| Get MCP working (and verify it) | references/mcp-setup.md |
| Understand the TLS bypass | references/tls-bypass.md |
| Install Browser MCP (`@playwright/mcp`) for verification flows; recover from `browserType.launchPersistentContext` / browser-launch errors (Chromium channel fallback, Node driver) | references/browser-automation.md |
| See which vendor skill-repo patterns this plugin adopts vs deviates from | references/vendor-patterns.md |
| Why SQL-cloning structural trees fails; why the admin UI is verification-only (anti-pattern detail behind the surface-priority rule) | references/surface-priority.md |
| Generic demo-storytelling tactics (audience framing, one-source-N-shapes, the customer-wording glossary) | references/demo-tactics.md |
| Manage the customisation budget | references/customisations.md |
| Audit customisations at end of phase | references/audit-customisations.md |
| Honor the customer-context read-only contract | references/customer-context.md |
| Recover from silent AddIn install failure (stuck `UpdateManager` queue) | references/db-update-recovery.md |
| Install `DynamicWeb.Serializer` in the demo host; triage Serializer failure patterns; check baseline compatibility | references/serializer-reference.md ("Installation") |
| Understand Serializer internals â€” these live upstream in the Serializer repo's own docs; the reference carries the pointer block | references/serializer-reference.md ("Internals â€” upstream pointer block") |
| Run a Swift baseline deserialize (Swift demos only) | [`dynamicweb-swift-demo/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) |
| Verify post-deserialize integrity (Swift demos only) | [`dynamicweb-swift-demo/references/integrity-sweep.md`](../dw-demo-swift/references/integrity-sweep.md) |
| **Fold a demo-build learning back into the repo** (route foundational-vs-demo -> sanitize -> validate -> bump `metadata.version` -> atomic commit on a branch -> open PR -> refresh marketplace clone after merge). Maintainer-only, PR-based. | references/iterate-plugin.md |

## Folding demo-build learnings back into the plugin (maintainer-only)

The whole point of authoring these skills locally and publishing them as a versioned plugin is **so demo-build learnings don't decay**. When a non-trivial discovery surfaces mid-demo, capture it back **while the conversation context is still rich** â€” not from notes a week later.

Trigger phrases â€” when the user says any of these mid-demo, route to [references/iterate-plugin.md](references/iterate-plugin.md):

- "fold this into the skill" / "fold this learning back"
- "save this back to the plugin"
- "update the plugin from this demo"
- "publish this update"
- "this is worth keeping â€” add it to the skill"

The reference owns the full workflow end-to-end, including the load-bearing first step: **route the learning before editing** — a platform truth folds *up* into the owning foundational skill (fully sanitized), demo-craft folds into a demo skill, and a learning that needs the customer's name stays demo-local. Every fold lands via a **PR** (one learning = one atomic commit = one PR), never a direct push. It is maintainer-only; consumers of the plugin can ignore it â€” or open a PR.

## Host lifecycle authority

Claude controls the `Dynamicweb.Host.Suite` host process autonomously â€” start, stop, restart without asking. The host going up and down is part of the normal build / deserialize / test / template-edit loop; blocking on the user to run `dotnet run` is friction.

- Start (durable): use PowerShell `Start-Process` so the host survives the spawning subshell, **and redirect stdout/stderr to log files**. A hidden `Start-Process` *without* redirection has proven flaky — the spawned process can exit right after kickoff; redirecting keeps it stable and leaves a startup log to read (e.g. to confirm the TFM line — see `references/scaffold.md` Section 2.1):
  ```
  powershell -Command "Start-Process -FilePath 'dotnet' -ArgumentList 'run','--launch-profile','Dynamicweb.Host.Suite' -WorkingDirectory '<absolute-path-to-Suite>' -WindowStyle Hidden -PassThru -RedirectStandardOutput '<Suite>\out.log' -RedirectStandardError '<Suite>\err.log' | Select-Object -ExpandProperty Id"
  ```
  Returns PID. After kickoff, poll `/Admin` (or `/admin/api/api.json` with bearer) until 200, then proceed.
  **Do NOT** use plain `dotnet run` via Bash `run_in_background:true` â€” when the bash subshell ends, dotnet receives SIGHUP and the host dies after the next idle window. We've seen this fail with exit 127 mid-session.
  - **`--no-build` caveat:** `dotnet run --no-build` launches whatever DLL is already in `bin/`. If a prior `dotnet build` *failed*, you silently run the **stale** binary — and a run you intended as a one-shot maintenance arg can instead boot a normal host and lock the exe. Confirm the last build succeeded before relying on `--no-build`.
- Stop: kill by the **PID returned from Start-Process** when you have it. When you don't, target the host **by its launchSettings port — never by the shared project name**: every demo scaffolds the same `Dynamicweb.Host.Suite` project, so a name / command-line match (`*Dynamicweb.Host.Suite*`) kills *sibling* demos' hosts too. Resolve the PID from the port and stop that:
  ```
  powershell -Command "$p = Get-NetTCPConnection -LocalPort <PORT> -State Listen | Select-Object -ExpandProperty OwningProcess -Unique; if ($p) { Stop-Process -Id $p -Force }"
  ```
  `<PORT>` is the HTTPS port from `Dynamicweb.Host.Suite/Properties/launchSettings.json` (the discover-from-project-files source of truth — see `references/scaffold.md`).
  Use this freely â€” restart is cheap, locked-in-cache state is the bigger risk.
- Visibility â‰  permission: still announce in one line ("starting hostâ€¦", "host up at :31873", "restarting to clear plugin cache"). Authorization removes the *ask*, not the *narration*.

This rule is owned by this skill and inherited by every sister skill (`dynamicweb-pim-demo`, `dynamicweb-swift-demo`, `dynamicweb-pim-for-bc`). A sister skill that pauses mid-flow to ask "please start the host" is violating this contract.

## Surface priority for CREATES (always-on rule)

**Creating things in DW10 has a strict surface priority. Violating it has bitten this skill author multiple times â€” keeping the rule explicit at base level so every sister skill inherits it.**

| Surface | Use for | Why |
|---------|---------|-----|
| 1. **MCP (`dynamicweb-commerce-mcp`)** | **Default â€” try this first for anything that creates a structural row** (pages, paragraphs, areas, products, groups, orders, users, etc.) | Calls DW's domain services. Triggers ALL the bookkeeping a UI click would: ItemRelation cloning, ItemList propagation, sibling-page linking, cache invalidation, index refresh, child-row creation, validation. ~260 tools. |
| 2. **Management API** (`/admin/api/...`) | Fallback when MCP doesn't expose the operation. Usually admin-grade actions: `BuildIndex`, `CacheInformationRefresh`, `FeatureManagementToggle`, anything in `/admin/api/docs/`. | Same DW domain services as MCP, just a different transport. |
| 3. **Admin UI** (Playwright) | **Verification only** â€” navigate, screenshot, DOM-grep to confirm a change landed. Never an action surface. | Every admin-UI click is an Admin API call underneath (the admin SPA is a client of `/admin/api/...`), so a "UI-only" operation means you haven't found the endpoint yet â€” check `/admin/api/docs/` or watch the SPA's network calls. For a genuinely awkward one-click (e.g. AppStore install), ask the user to click manually; don't drive the admin SPA via Playwright to make changes. |
| 4. **Direct SQL** (`sqlcmd ...`) | **LAST RESORT** â€” only for: (a) cleanup/teardown, (b) bulk schema-drift fixes, (c) reading data, (d) cases where you've confirmed all three higher surfaces don't support the operation and a vendor patch is the only alternative. | Bypasses every DW service. Misses bookkeeping. Creates orphans. Corrupts caches. **You will not figure out the full bookkeeping for a non-trivial create via SQL â€” DW does too much per service call.** |

**Pattern to follow:**
1. Try MCP. If the tool name suggests it (e.g. `copy_area`, `copy_page`, `save_pages`), use it.
2. If MCP errors or doesn't expose the operation, try the Management API (`/admin/api/docs/` for the catalogue).
3. If neither seems to expose it, the operation still exists on the Admin API â€” the admin UI is a SPA over `/admin/api/...`. Find the endpoint the UI calls (`/admin/api/docs/`, or watch the network tab while the user clicks once), then call it as surface 2. If endpoint discovery stalls, pause and ask the user to do the one-click manually. Playwright on `/Admin` is verification-only â€” never drive the admin UI to make changes.
4. Only after exhausting 1-3 do you reach for SQL â€” and even then, prefer SQL for cleanup of a previous bad attempt rather than for the create.

Why SQL-cloning structural trees specifically is forbidden (the bookkeeping it misses, the 10-screens-later breakage): [references/surface-priority.md](references/surface-priority.md).

**Hosted/online installs:** surface 4 does not exist and surface 1 is version-dependent (probe first â€” never assume MCP is present or absent). The priority collapses to MCP-if-present â†’ Management API â†’ ask the user; the API recipes that replace the SQL rungs live in [references/online-mode.md](references/online-mode.md).

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

## Demo philosophy â€” go deep, not wide

Demo time is short; condensed beats spread. Default to a single deep storyline rather than a broad surface tour â€” every login, channel, locale, and customer-center section the user has to scan during the live demo is time stolen from the part you actually want to land.

**Default postures (sister skills enforce the specifics):**

- **Logins / personas â€” floor of 2.** One buyer + one CSR so impersonation has somewhere to land. Don't scaffold a roster of personas you won't have time to log into. Owned by `dynamicweb-swift-demo`.
- **Shops / channels â€” 1 + 1.** One shop plus the channel most relevant to the customer's pitch. Don't add a second channel of equal weight. Owned by `dynamicweb-pim-demo`.
- **Locale â€” single home market.** US-only for a US customer (EN/USD), DE-only for a DACH customer, etc. Add a second language/currency only when the customer's case explicitly demands it. Owned by `dynamicweb-pim-demo`.
- **Customer-center sections, paragraph types, page presets â€” storyline-driven.** Scaffold the ones the storyline actually visits, not the ones the platform supports. Owned by `dynamicweb-swift-demo`.

**Product catalogue is the deliberate exception â€” go deep AND wide there.** Rich product data (variants, BOM bundles, completeness rules, assortments, ample SKUs across categories) is cheap to produce via MCP and makes the demo feel real instead of sketched. The "narrow it down" rule does not apply to product modelling â€” see `dynamicweb-pim-demo` for the modelling depth recipes.

When in doubt: every login / channel / locale / customer-center section must justify itself against demo minutes. A product family does not need to justify itself. Generic storytelling tactics (audience framing, one-source-N-shapes, speak the customer's words): [references/demo-tactics.md](references/demo-tactics.md).

## Sister skills

- **`dynamicweb-pim-demo`** -- PIM modelling, structural mental model (shops vs channels, GroupType, repositories, variants, BOM, channels + feeds, assets, product categories), MCP/API/SQL/filesystem decision matrix. **Use AFTER** `dynamicweb-demo-base`.
- **`dynamicweb-swift-demo`** -- Swift frontend (templates, paragraph types, B2B customer-center scaffolding, baseline deserialize). **Use AFTER** `dynamicweb-demo-base`.
- **`dynamicweb-erp-demo`** -- ERP integration (source/target rule, DB-staged mock, scenarios-first planning). **Use AFTER** `dynamicweb-demo-base`.
- **`dynamicweb-pim-for-bc`** -- live BC connector via ngrok + AppStore connector. **Use AFTER** `dynamicweb-demo-base`.

A sibling skill that runs without `dynamicweb-demo-base`'s outputs (no `.mcp.json`, no `CUSTOMISATIONS.md`, no resolved `$env:DW_VAULT`) silently no-ops or produces broken artefacts. The "Use FIRST" routing wording in this skill's description and the "Use AFTER" markers in the sister skills are the inoculation.

## Vault layout

The on-disk vault at `$env:DW_VAULT` (default `C:\VibeCode\dw-vault\`) is the single source of truth for reference content. Read `$env:DW_VAULT\INDEX.md` to discover slots; never hardcode paths. The five slots are `dw10source/`, `samples/`, `databases/`, `docs/`, `serialized-data/`.

## Path-resolution rule

Every path in this skill (and sister skills) resolves via `$env:DW_VAULT` joined with a slot name from `INDEX.md`. Per-machine hardcoded literals (legacy paths under user-specific source folders or sibling solution folders) are a known anti-pattern; the existing `dynamicweb-pim-demo` skill still carries some as a cautionary cleanup target.

## Discover-from-project-files rule

Port, DB name, and Management API bearer token vary per project. Read them from project files and chat -- never hardcode.

| What | Where to read it |
|---|---|
| HTTPS port + host URL | `Dynamicweb.Host.Suite/Properties/launchSettings.json` (`applicationUrl`, HTTPS profile) |
| Database name | `Dynamicweb.Host.Suite/GlobalSettings.Database.config` (`Database=` or `Initial Catalog=`) |
| **MCP API key** (Authorization header for `/admin/mcp`) | Generated once in the admin UI (Settings â†’ Integration â†’ MCP configurations); full capture + storage contract in `references/mcp-setup.md` Steps 3-3b and 6. |
| **Management API bearer token** (Authorization header for `/admin/api/...`) | Captured via `AskUserQuestion` from chat (format `CLAUDE.<hex>`); storage contract (per-demo Claude memory, never env vars, never committed) is canonical in `references/mcp-setup.md` Step 6. |

## Baseline-drift self-diagnosis rule

When grep results in skill text contradict the live vault, consider "the baseline has rolled since this skill was authored" as a candidate cause. Cross-check `$env:DW_VAULT\INDEX.md`'s version stamp before assuming the skill is correct. Reality wins; the skill is the second source of truth.




