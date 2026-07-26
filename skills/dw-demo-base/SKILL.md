---
name: dw-demo-base
type: flow
group: demo
description: 'Foundation skill for Dynamicweb 10 demos — scaffolds the dw10-suite host, wires Backend MCP and the localhost TLS bypass, and drops the customisations and customer-context guardrails. Does NOT load a baseline. Use FIRST on any new Dynamicweb demo, when MCP tools fail to load ("Failed to connect", silent tools/list), on a fresh Windows machine, when auditing the customisation budget, or when "pinning the platform" for a Distribution-validating scaffold. Also owns the orchestrator abstraction (GSD primary vs the native `/demo:*` commands) — "drive the demo build", "GSD vs native" route to references/orchestrator.md —. Sister skills (dw-demo-pim, dw-demo-swift, dw-demo-headless, dw-demo-erp, dw-integration-bc) are Use AFTER, never standalone. `<demo>\customer-context\` is read-only. Non-triggers: a hosted/cloud install reached only by URL + Admin API key -> dw-demo-hosted; folding a demo-build learning back into the repo -> dw-demo-foldback.'
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

The canonical flow below assumes a **local install** (scaffold + SQL Express on the demo machine). When the engagement instead hands you a **site URL + Admin API bearer key** — a vendor-hosted/cloud install with no machine to scaffold on — the build forks to [`dw-demo-hosted`](../dw-demo-hosted/SKILL.md), which owns both hosted paths: building directly on a hosted install, and publishing a locally-built demo onto one (a **migration, not a deploy**, with its own failure modes). Come back here for the guardrails — the always-on rules (surface priority, guarded writes, customer-context, demo philosophy) apply unchanged in both modes.

## Canonical end-to-end flow

Walk every step in order — skip none. Each step's reference contains its own verification gate; the skill **refuses to declare setup complete** until every gate passes.

1. **Verify the environment is build-ready** -> [references/setup-checks.md](references/setup-checks.md)
   Probes the `NODE_TLS_REJECT_UNAUTHORIZED` env var, the **.NET 10 SDK** (mandatory — rationale in `references/foundational/setup-install.md` §2), `Dynamicweb.ProjectTemplates`, the SQL Express service, MSDTC, `git` plus the `gh` CLI (present + authenticated — needed to clone the baseline/pack/theme distribution repos), and that the demo's `<demo-root>\baselines\` folder is writable. Also captures the demo's target **DW10 version** and **Swift version** (the versions prompt — see "Baseline data" below). Posture: verify + opt-in fix for cheap fixes (env var); print-and-link only for install-grade fixes (SDK, SQL Express).

2. **Scaffold the per-demo project** -> [references/scaffold.md](references/scaffold.md)
   `dotnet new dw10-suite --name Dynamicweb.Host.Suite`. The `--name Dynamicweb.Host.Suite` is mandatory; sister-skill path discovery depends on this name. Suite version is whatever the template + `dotnet restore` resolve — version policy is out of scope, **except** a scaffold that validates Distribution content, which must **pin `Dynamicweb.Suite` to the Distribution's `INDEX.json gateProven.dwPlatformVersion`** (floating `10.*` resolves to latest stable and version-coupled layers fail sideways — scaffold.md §2.2).

3. **Wire MCP and fix the two-layer TLS bypass** -> [references/mcp-setup.md](references/mcp-setup.md) + [references/tls-bypass.md](references/tls-bypass.md) + [references/browser-automation.md](references/browser-automation.md)
   Install the user-scope Browser MCP first (`@playwright/mcp`, machine-level and idempotent — its tools are the scaffold's action surface on the admin UI), write `.mcp.json`, apply both TLS-bypass layers, then drive the admin UI via the Browser MCP to create the MCP configuration and capture the shown-once API key (Authentication method = API Key; Claude.ai OAuth is fallback-only; headless code recipe when the UI is unreachable, ask the user only as last resort). The MCP verification gate: `claude mcp list` shows `Connected` AND `ToolSearch +dynamicweb` returns >200 tools.

4. **Drop the guardrail artefacts** -> `references/customisations.md` + `references/customer-context.md`
   Stage `<demo>\CUSTOMISATIONS.md` (the customisation ledger) and ensure the `<demo>\customer-context\` read-only contract is wired into the per-demo `CLAUDE.md`. The `references/audit-customisations.md` recipe produces paste-ready end-of-phase audit content. When running **without GSD**, also copy the native orchestrator commands from `assets/commands/demo/` into the demo project's `.claude/commands/demo/` so `/demo:scaffold|impact|build|status` are available (see [references/orchestrator.md](references/orchestrator.md)).

## Baseline data — explicit non-step

Loading reference content into the project DB is **NOT** part of this skill's canonical flow. Three separate paths follow base, depending on demo type:

- **PIM demo** -> start with a blank/fresh demo DB; the PIM skill's modelling recipes build content from scratch via MCP. No deserialize step. See [`dynamicweb-pim-demo/SKILL.md`](../dw-demo-pim/SKILL.md).
- **Swift demo** -> deserialize the **framework-only `base` layer** plus the **`surface-swift` content surface** (the layer that carries ALL Swift content, item-type XMLs, and UrlPath), checked out per-demo into `<demo-root>\distribution\layers\` (see the versions prompt + checkout model below) via the Serializer. Owned end-to-end by [`dynamicweb-swift-demo/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) + [`dynamicweb-swift-demo/references/integrity-sweep.md`](../dw-demo-swift/references/integrity-sweep.md). Prerequisite: the Serializer is installed per [`references/serializer-reference.md`](references/serializer-reference.md) "Installation".
- **Headless demo** -> deserialize the separate, presentation-agnostic `headless` **surface layer** (its own product line, no shared item-type rows with Swift; checked out per-demo into `<demo-root>\distribution\layers\headless\` like any layer — see the versions prompt + checkout model below) for a Next.js storefront that reads the DW10 Delivery API. Owned by [`dynamicweb-headless-demo/references/headless-baseline.md`](../dw-demo-headless/references/headless-baseline.md); backend config in [`headless-backend.md`](../dw-demo-headless/references/headless-backend.md). Same Serializer prerequisite.

The Serializer install steps live in base so any sister skill can pull them; the act of deserializing is Swift- or headless-specific.

### Versions prompt + Distribution clone/checkout

Before any artifact is fetched, ask the user the **DW10 version** and the **Swift version**, and
record both in the demo's `CUSTOMISATIONS.md`. Every artifact then resolves from the demo's own
Distribution checkout — `git clone` / `git pull --ff-only` on `origin/main`, layers resolved
through `layers/INDEX.json`, never a release zip and never a tag. **Main IS the version.**

The clone model, the `gateProven` assertion, the retired -> `supersededBy` resolution, the
resolved-SHA record, and the artifact-source table are owned by
[references/distribution-checkout.md](references/distribution-checkout.md).

## Where to find things

| If you need to... | Read this reference |
|---|---|
| Understand how a demo build is **driven** — the orchestrator abstraction (GSD primary vs the native `/demo:*` command set), GSD detection / deference + `--standalone`, the `agent_skills` keystone, the strictness gradient, and the shared acceptance criteria | references/orchestrator.md |
| Verify a fresh machine is build-ready (incl. the MSDTC check that AreaCopy `TransactionException`s trace back to) | references/setup-checks.md |
| **Build on, or publish onto, a hosted/cloud install** (URL + Admin API key only — no scaffold, no SQL; the session-start probe, the Management API recipe pack, lying-success verification, the flush-then-restart ladder; and for a publish: pre-flight, transport map, clean-room deserialize, id collisions, index rebuild) | **[`dw-demo-hosted`](../dw-demo-hosted/SKILL.md)** |
| Ask the demo's DW10 + Swift versions and check out the Distribution layers/editions per-demo | references/distribution-checkout.md + references/setup-checks.md |
| Scaffold the project | references/scaffold.md |
| **Pin the platform** — which `Dynamicweb.Suite` version a Distribution-validating scaffold must use (pin to `INDEX.json gateProven.dwPlatformVersion`; why floating `10.*` fails sideways), plus the multi-target `--framework` / `$pid` host-launch traps and the DB-wizard "Login failed" race | references/scaffold.md §2.2 + §3 + references/host-lifecycle.md |
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
| Run an **in-place platform update** on an existing demo host (`Dynamicweb.Suite` bump, design/item-type re-deploy): the mandatory pre-update `BACKUP DATABASE` + `ItemList` content-count gate, update-queue mechanics, schema-drift across NuGet versions | references/foundational/setup-upgrade.md |
| Install the DW Serializer in the demo host; triage Serializer failure patterns; check baseline compatibility | references/serializer-reference.md ("Installation") |
| Understand Serializer internals — these live upstream in the Serializer repo's own docs; the reference carries the pointer block | references/serializer-reference.md ("Internals — upstream pointer block") |
| Run a Swift baseline deserialize (Swift demos only) | [`dynamicweb-swift-demo/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) |
| Verify post-deserialize integrity (Swift demos only) | [`dynamicweb-swift-demo/references/integrity-sweep.md`](../dw-demo-swift/references/integrity-sweep.md) |
| **Fold a demo-build learning back into the repo** (route foundational-vs-demo -> sanitize -> validate -> bump `metadata.version` -> atomic commit on a branch -> open PR -> refresh marketplace clone after merge). Maintainer-only, PR-based. | **[`dw-demo-foldback`](../dw-demo-foldback/SKILL.md)** |

## Folding demo-build learnings back into the plugin (maintainer-only)

The whole point of authoring these skills locally and publishing them as a versioned plugin is **so demo-build learnings don't decay**. When a non-trivial discovery surfaces mid-demo, capture it back **while the conversation context is still rich** — not from notes a week later.

"Fold this into the skill" / "fold this learning back" / "save this back to the plugin" / "publish this update" route to [`dw-demo-foldback`](../dw-demo-foldback/SKILL.md), which owns the workflow end-to-end — including the load-bearing first step: **route the learning before editing**. A platform truth folds *up* into the owning foundational skill (fully sanitized), demo-craft folds into a demo skill, and a learning that needs the customer's name stays demo-local. Every fold lands via a **PR** (one learning = one atomic commit = one PR), never a direct push.

## Host lifecycle authority

Claude controls the `Dynamicweb.Host.Suite` host process autonomously — start, stop, restart
without asking. Blocking on the user to run `dotnet run` is friction. Announce each action in one
line ("starting host…", "host up at :31873"); authorization removes the *ask*, not the narration.

**Flush before restarting.** Nearly every "my change doesn't show" symptom is a stale cache with a
flush surface, and flushing keeps warm state a restart throws away — work the targeted → bulk →
restart ladder in [references/foundational/cache-invalidation.md](references/foundational/cache-invalidation.md).
Restarts that are genuinely owed get batched: one per authoring pass.

Start durably via `Start-Process` with logs under `<demo>\notes\logs\`; stop **port-scoped and
ownership-verified**, because every demo on the machine scaffolds the same project name and a
name-matched kill takes out a sibling demo's host. The commands, the launch traps (`--no-build`
staleness, `--framework` on a multi-target host, the read-only `$pid` variable, the degraded
apphost-exe boot), and the never-force-kill-mid-index-build rule are owned by
[references/host-lifecycle.md](references/host-lifecycle.md).

This rule is owned by this skill and inherited by every sister skill. A sister skill that pauses
mid-flow to ask "please start the host" is violating this contract — and so is one that restarts
where the cache table names a flush, or stops a process it has not verified as this demo's own.

## Surface priority for CREATES (always-on rule)

**Creating things in DW10 has a strict surface priority, and the build phase admits no
exceptions:** MCP (`dynamicweb-commerce-mcp`) first for anything that creates a structural row →
Management API (`/admin/api/...`) when MCP does not expose the operation → direct SQL only on a
local install, only as a last resort, and in practice only for cleanup or reads. MCP and the
Management API call DW's domain services, so they trigger the bookkeeping a UI click would
(ItemRelation cloning, ItemList propagation, cache invalidation, index refresh, validation); SQL
bypasses all of it and leaves orphans that surface ten screens later.

The **admin UI is verification-only during the build** — navigate, screenshot, DOM-grep to confirm
a change landed. Every admin-UI click is an Admin API call underneath, so a "UI-only" operation
means the endpoint has not been found yet.

The **scaffold phase** is the one exception: before the MCP verification gate passes, the build
surfaces do not exist yet, so the admin UI via the Browser MCP *is* an action surface for the
bootstrap one-clicks (MCP configuration + shown-once API key, Management API key, AppStore
install, portal downloads).

**Hosted/online installs** have no scaffold phase and no surface 3 — no SQL, ever — and surface 1
is version-dependent, so probe rather than assume ([`dw-demo-hosted`](../dw-demo-hosted/SKILL.md)).

The phase × instance-type matrix, the scaffold-phase ladder, the SQL-cloning anti-pattern, and the
silent-no-op verification rule are owned by [references/surface-priority.md](references/surface-priority.md).
The platform mechanism underneath — what an MCP create's domain-service call actually does — is in
[references/foundational/extend-mcp-tools.md](references/foundational/extend-mcp-tools.md) §5.

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

## Artifact hygiene — the demo root is not a scratchpad (always-on rule)

Ephemeral build evidence (QA screenshots, host logs, Playwright DOM/a11y dumps) has a canonical home under `notes\`; the demo root stays clean. This is the same guarded-write family as the two above — an output-path contract, owned here at base and inherited by every sister skill so every agent writes evidence to the same place instead of defaulting to CWD (the demo root).

1. **Canonical scratch layout under the demo root** — every ephemeral artifact routes to one of these three dirs, named in the verbatim command that produces it:

   | Directory | Holds | Named by |
   |---|---|---|
   | `notes\qa\` | QA screenshots + visual-QA evidence | `references/visual-qa.md`, `references/browser-automation.md` |
   | `notes\logs\` | host stdout/stderr logs | the `Start-Process` recipe in [references/host-lifecycle.md](references/host-lifecycle.md) |
   | `notes\snapshots\` | Playwright DOM / accessibility dumps | `references/browser-automation.md` |

2. **Root allowlist.** Only these may sit at the demo root: the plan doc (`DEMO-PLAN.md`), `CLAUDE.md`, `CUSTOMISATIONS.md`, `.gitignore`, `.mcp.json`, and directories. Anything else an agent wants to write at root routes to `notes\` instead — the same redirect wording as the customer-context contract ("did you mean `<demo>\notes\`?"). The harness enforces this end-of-phase (see the Foundry root-allowlist check).

3. **Naming rule — name evidence for what it IS.** An evidence dump is named for its content (`admin-a11y-snapshot-*.md`, `home-desktop-*.jpeg`), never for what it was captured *during*. Security-suggestive names for non-secret dumps (e.g. an accessibility snapshot saved as `apikeylist.md`) are forbidden — they read as leaked-secrets files to any human or scanner.

4. **Scaffold `.gitignore`.** The scaffolded demo's `.gitignore` ignores `notes/qa/`, `notes/logs/`, and `notes/snapshots/` (in addition to the existing `notes/credentials.local.md`, `bin/obj`, `wwwroot/Files/System/`) — see `references/scaffold.md` §2.1. Keeper screenshots worth committing are the deliberate exception: copy them out of `notes\qa\` explicitly.

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
- **`dw-demo-hosted`** -- hosted/cloud installs reached only by URL + Admin API key: building directly on one, and publishing a locally-built demo onto one. **Use AFTER** `dynamicweb-demo-base`.
- **`dw-demo-foldback`** -- folding a demo-build learning back into the skills repo as a sanitized, atomic PR. **Use AFTER** `dynamicweb-demo-base`.

A sibling skill that runs without `dynamicweb-demo-base`'s outputs (no `.mcp.json`, no `CUSTOMISATIONS.md`) silently no-ops or produces broken artefacts. The "Use FIRST" routing wording in this skill's description and the "Use AFTER" markers in the sister skills are the inoculation.

## Reference-content layout

Demo artifacts (base, catalog, theme, and feature layers) are checked out per-demo from the Distribution clone into the demo's own `<demo-root>\distribution\` folder — see [references/distribution-checkout.md](references/distribution-checkout.md). There is no shared machine-wide vault; each demo consumes the latest gate-proven `main` and records the resolved commit SHA as its reproducibility stamp.

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

When grep results in skill text contradict the live baseline, consider "the baseline has rolled since this skill was authored" as a candidate cause. Cross-check the checked-out `base` layer's `swiftVersion` (from its `layer.json`) against the demo's Swift version before assuming the skill is correct. Reality wins; the skill is the second source of truth.




