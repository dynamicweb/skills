---
name: dw-demo-base
type: flow
group: demo
description: Foundation skill for Dynamicweb 10 demos — scaffolds the dw10-suite host, wires Backend MCP and the localhost TLS bypass, and drops the customisations and customer-context guardrails. Does NOT load a baseline. Use FIRST on any new Dynamicweb demo, when MCP tools fail to load ("Failed to connect", silent tools/list), on a fresh Windows machine, when auditing the customisation budget, when "pinning the platform" for a Distribution-validating scaffold, or when the demo targets a hosted/cloud install reached only by URL + Admin API key (references/online-mode.md). Also owns the orchestrator abstraction (GSD primary vs the native `/demo:*` commands) — "drive the demo build", "GSD vs native" route to references/orchestrator.md — and the maintainer fold-back workflow — "fold this into the skill" routes to references/iterate-plugin.md. Sister skills (dw-demo-pim, dw-demo-swift, dw-demo-headless, dw-demo-erp, dw-integration-bc) are Use AFTER, never standalone. `<demo>\customer-context\` is read-only.
---

# Dynamicweb Demo Base Skill

The foundation skill for any Dynamicweb 10 demo. **Use FIRST** on every new Dynamicweb demo. Sister skills (`dw-demo-pim`, `dw-demo-swift`) inherit the `.mcp.json`, `CUSTOMISATIONS.md`, and TLS bypass that this skill establishes -- they are **Use AFTER**, never standalone.

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

The canonical flow below assumes a **local install** (scaffold + SQL Express on the demo machine). When the engagement instead hands you a **site URL + Admin API bearer key** — a vendor-hosted/cloud install with no machine to scaffold on — fork to [references/online-mode.md](references/online-mode.md), which owns the deltas: which canonical steps to skip, the session-start probe (tool availability on hosted installs is **version-dependent** — MCP may or may not be exposed; always probe, never assume), the Management API recipe pack that substitutes for MCP/SQL recipes, and the shared-install discipline. Moving a demo that was built locally onto a hosted install is a **migration, not a deploy** — a separate playbook with its own failure modes, owned by [references/publish-to-hosted.md](references/publish-to-hosted.md). The always-on rules (surface priority, guarded writes, customer-context, demo philosophy) apply in both modes.

## Canonical end-to-end flow

Walk every step in order — skip none. Each step's reference contains its own verification gate; the skill **refuses to declare setup complete** until every gate passes.

1. **Verify the environment is build-ready** -> [references/setup-checks.md](references/setup-checks.md)
   Probes the `NODE_TLS_REJECT_UNAUTHORIZED` env var, the **.NET 10 SDK** (mandatory — rationale in `../dw-setup-install/references/install-anatomy.md` §2), `Dynamicweb.ProjectTemplates`, the SQL Express service, MSDTC, `git` plus the `gh` CLI (present + authenticated — needed to clone the baseline/pack/theme distribution repos), and that the demo's `<demo-root>\baselines\` folder is writable. Also captures the demo's target **DW10 version** and **Swift version** (the versions prompt — see "Baseline data" below). Posture: verify + opt-in fix for cheap fixes (env var); print-and-link only for install-grade fixes (SDK, SQL Express).

2. **Scaffold the per-demo project** -> [references/scaffold.md](references/scaffold.md)
   `dotnet new dw10-suite --name Dynamicweb.Host.Suite`. The `--name Dynamicweb.Host.Suite` is mandatory; sister-skill path discovery depends on this name. Suite version is whatever the template + `dotnet restore` resolve — version policy is out of scope, **except** a scaffold that validates Distribution content, which must **pin `Dynamicweb.Suite` to the Distribution's `INDEX.json gateProven.dwPlatformVersion`** (floating `10.*` resolves to latest stable and version-coupled layers fail sideways — scaffold.md §2.2).

3. **Wire MCP and fix the two-layer TLS bypass** -> [references/mcp-setup.md](references/mcp-setup.md) + [references/tls-bypass.md](references/tls-bypass.md) + [references/browser-automation.md](references/browser-automation.md)
   Install the user-scope Browser MCP first (`@playwright/mcp`, machine-level and idempotent — its tools are the scaffold's action surface on the admin UI), write `.mcp.json`, apply both TLS-bypass layers, then drive the admin UI via the Browser MCP to create the MCP configuration and capture the shown-once API key (Authentication method = API Key; Claude.ai OAuth is fallback-only; headless code recipe when the UI is unreachable, ask the user only as last resort). The MCP verification gate: `claude mcp list` shows `Connected` AND `ToolSearch +dynamicweb` returns >200 tools.

4. **Drop the guardrail artefacts** -> `references/customisations.md` + `references/customer-context.md`
   Stage `<demo>\CUSTOMISATIONS.md` (the customisation ledger) and ensure the `<demo>\customer-context\` read-only contract is wired into the per-demo `CLAUDE.md`. The `references/audit-customisations.md` recipe produces paste-ready end-of-phase audit content. When running **without GSD**, also copy the native orchestrator commands from `assets/commands/demo/` into the demo project's `.claude/commands/demo/` so `/demo:scaffold|impact|build|status` are available (see [references/orchestrator.md](references/orchestrator.md)).

## Baseline data — explicit non-step

Loading reference content into the project DB is **NOT** part of this skill's canonical flow. Three separate paths follow base, depending on demo type:

- **PIM demo** -> start with a blank/fresh demo DB; the PIM skill's modelling recipes build content from scratch via MCP. No deserialize step. See [`dw-demo-pim/SKILL.md`](../dw-demo-pim/SKILL.md).
- **Swift demo** -> deserialize the **framework-only `base` layer** plus the **`surface-swift` content surface** (the layer that carries ALL Swift content, item-type XMLs, and UrlPath), checked out per-demo into `<demo-root>\distribution\layers\` (see the versions prompt + checkout model below) via the Serializer. Owned end-to-end by [`dw-demo-swift/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) + [`dw-demo-swift/references/integrity-sweep.md`](../dw-demo-swift/references/integrity-sweep.md). Prerequisite: the Serializer is installed per [`references/serializer-reference.md`](references/serializer-reference.md) "Installation".
- **Headless demo** -> deserialize the separate, presentation-agnostic `headless` **surface layer** (its own product line, no shared item-type rows with Swift; checked out per-demo into `<demo-root>\distribution\layers\headless\` like any layer — see the versions prompt + checkout model below) for a Next.js storefront that reads the DW10 Delivery API. Owned by [`dw-demo-headless/references/headless-baseline.md`](../dw-demo-headless/references/headless-baseline.md); backend config in [`headless-backend.md`](../dw-demo-headless/references/headless-backend.md). Same Serializer prerequisite.

The Serializer install steps live in base so any sister skill can pull them; the act of deserializing is Swift- or headless-specific.

### Versions prompt + Distribution clone/checkout

All demo artifacts live in ONE consolidated Distribution repo, cloned per-demo into `<demo-root>\distribution\` — **main IS the version**: consumers pin the latest gate-proven `main` (never a release zip or tag checkout), resolve layers from `layers/INDEX.json` (a retired name resolves loudly to its `supersededBy` successor), and record the resolved commit SHA in `CUSTOMISATIONS.md` as the reproducibility stamp. Before any artifact is fetched, ask the user the **DW10 version** and the **Swift version** (e.g. `2.4`; the current cycle is **Swift 2.4 on DW 10.28.1-PreRelease**) and record both in `CUSTOMISATIONS.md` — the Distribution supports the current latest Swift release only and rolls forward with it. The verbatim clone/resolve recipe, the `gateProven` assertion, and the `$env:DW_DISTRIBUTION_REPO` override live in [references/scaffold.md](references/scaffold.md) §5.

The former standalone demo-theme and feature-pack repos are **archived** — their themes and packs are now theme/feature layers in the Distribution:

| Artifact | Source (in the Distribution clone) | Working tree | Consumed by |
|---|---|---|---|
| Serialized base | `layers/base` (kind base) — **framework-only**: 16 framework SQL sets in `replace/_sql/` (countries, currencies, languages, shops, payments, shippings, VAT, order flow/states, AccessUser), **zero content, zero pages, empty catalog by design** | `<demo-root>\distribution\layers\base\` | [`dw-demo-swift/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) §3 |
| Swift content surface | `layers/surface-swift` (kind surface) — ALL Swift content: both areas (`Swift 2` + `Swift 2 Nederlands`) in `replace/_content/` + `merge/_content/`, `UrlPath` in `replace/_sql/`, and its **own item-type XMLs** (`itemtypes/`, 128 `ItemType_Swift-v2_*.xml`) | `<demo-root>\distribution\layers\surface-swift\` | [`dw-demo-swift/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) §3 |
| Demo catalog + identities *(optional)* | `layers/sample-data` (kind sample-data) — ships ALL demo content as SQL files (`merge/_sql/catalog.sql`: products / groups / prices; `merge/_sql/identities.sql`: buyer + CSR); editions activate it via `sampleData: true` (e.g. `swift-demo`); otherwise author per-demo via the [`dw-demo-pim`](../dw-demo-pim/SKILL.md) recipes | `<demo-root>\distribution\layers\sample-data\` | [`dw-demo-swift/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) §3 |
| Demo theme / style assets | `layers/theme-default` (kind theme — pure disk-overlay `files/`, no serialized DB content). **The ONE presentation layer** — every Swift demo starts from `theme-default` and re-skins on top of it; there is no theme choice and no separate overlay layers (the header-nav affordance CSS ships inside `theme-default`'s `default_custom.css`) | `<demo-root>\distribution\layers\theme-default\` | [`dw-demo-swift/references/styles-assets.md`](../dw-demo-swift/references/styles-assets.md) |
| Feature pack | `layers/<name>` (kind feature) | `<demo-root>\distribution\layers\<name>\` | [`dw-demo-swift/references/pack-activation.md`](../dw-demo-swift/references/pack-activation.md) |
| Swift design package | local clone of `https://github.com/dynamicweb/Swift` (release tag `v<version>.0` — the upstream Swift product still ships releases) | `<demo-root>\dw-swift\` | [`dw-demo-swift/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) "Design-package deploy" |

## Where to find things

| If you need to... | Read this reference |
|---|---|
| How a demo build is **driven** — GSD vs the native `/demo:*` commands, `--standalone`, the strictness gradient, acceptance criteria | references/orchestrator.md |
| Verify a fresh machine is build-ready (incl. the MSDTC check behind AreaCopy `TransactionException`s) | references/setup-checks.md |
| **Build on a hosted/cloud install** (URL + Admin API key only) — the session-start probe, Management API recipe pack, flush-then-restart ladder, inherited-clone remediation | **references/online-mode.md** |
| **Publish an existing local demo onto a hosted install** ("publish this site", "migrate local → hosted") — pre-flight, transport map, id collisions, index rebuild | **references/publish-to-hosted.md** |
| Ask the demo's DW10 + Swift versions; clone/resolve the Distribution per-demo | references/setup-checks.md (versions prompt) + references/scaffold.md §5 |
| Scaffold the project | references/scaffold.md |
| **Pin the platform** for a Distribution-validating scaffold (why floating `10.*` fails sideways); the DB-wizard "Login failed" race | references/scaffold.md §2.2 + §3 |
| **Start / stop / restart the demo host** — durable `Start-Process` recipe, ownership-verified stop, flush-first ladder, `--framework` / `$pid` / apphost-exe launch traps | references/host-lifecycle.md |
| Get MCP working (and verify it) | references/mcp-setup.md |
| Understand the TLS bypass | references/tls-bypass.md |
| Install Browser MCP (`@playwright/mcp`); recover from browser-launch errors | references/browser-automation.md |
| **Read a storefront screenshot critically** — programmatic defect detectors, the interaction pass, the eyeball checklist, symptom→fix routing, per-page definition of done | **references/visual-qa.md** |
| **Sweep for real-person PII and vendor boilerplate** — whole-database string sweep, stock vendor legal copy, locale-shaped patterns. **Blocking pre-demo leg**, hardest on a cloned host | **references/pii-sweep.md** |
| The surface contract — scaffold vs build phases, surfaces per instance type, why SQL-cloning structural trees fails | references/surface-priority.md |
| Generic demo-storytelling tactics (audience framing, one-source-N-shapes, the customer-wording glossary) | references/demo-tactics.md |
| Manage the customisation budget | references/customisations.md |
| Audit customisations at end of phase | references/audit-customisations.md |
| Honor the customer-context read-only contract | references/customer-context.md |
| Recover from silent AddIn install failure (stuck `UpdateManager` queue) | references/db-update-recovery.md |
| **Read, copy, rename, relocate or delete a product `.query`** — authoritative read verb, query-cache flush, `QueryCopy`/`QueryMove`/`QueryDelete` semantics | ../dw-search-indexing/references/query-authoring.md |
| **Express, sort or execute a product `.query`** — expression `Path` traps, OR groups, dropped sorts, paging gaps, builds that answer 200 and build nothing | ../dw-search-indexing/references/query-expressions.md |
| **Seed discounts, vouchers, loyalty rewards or gift cards** — the two coexisting discount engines, v2 payload shapes, voucher constraints | ../dw-commerce-orders/references/promotions-engines.md |
| **Make an Insights dashboard tell the truth** — which tables the widgets read, the traffic-discarding settings, health-provider verbs | ../dw-setup-config/references/tracking-insights.md |
| Run an **in-place platform update** on a demo host — pre-update backup + content-count gate, update-queue mechanics, schema drift | ../dw-setup-upgrade/references/upgrade-mechanics.md |
| Install the DW Serializer; triage Serializer failures; check baseline compatibility | references/serializer-reference.md ("Installation") |
| Serializer internals — upstream pointer block | references/serializer-reference.md |
| Run a Swift baseline deserialize (Swift demos only) | [`dw-demo-swift/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) |
| Verify post-deserialize integrity (Swift demos only) | [`dw-demo-swift/references/integrity-sweep.md`](../dw-demo-swift/references/integrity-sweep.md) |
| **Fold a demo-build learning back into the repo** — route, sanitize, validate, version-bump, PR. Maintainer-only | references/iterate-plugin.md |

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

Claude controls the `Dynamicweb.Host.Suite` host process autonomously — start, stop, restart without asking, announcing each action in one line (authorization removes the *ask*, not the *narration*). **Flush first — a restart is the last resort**: work the cache-flush ladder in [cache-invalidation.md](../dw-data-access/references/cache-invalidation.md) before restarting, and batch the restarts that ARE owed (AddIn deploys, TFM changes, restart-only cache rows) into one per authoring pass. Start durably via `Start-Process` with stdout/stderr redirected to `<demo>\notes\logs\`; stop port-scoped AND ownership-verified (sibling demo hosts share the machine); never force-kill during an index build. The verbatim start/stop recipes and the launch traps (`--no-build`, `--framework`, `$pid`, the apphost exe, silent early exits) live in [references/host-lifecycle.md](references/host-lifecycle.md). This rule is owned here and inherited by every sister skill — a sister skill that pauses to ask "please start the host", restarts where a flush suffices, or kills an unverified process is violating the contract.

## Surface priority for CREATES (always-on rule)

Creating things in DW10 has a strict surface priority, split into two phases by the MCP verification gate. **Scaffold phase** (before the gate): the admin UI via the Browser MCP is an action surface, scoped to the bootstrap one-clicks. **Build phase** (after the gate — and hosted/headless installs from the first request): **MCP first → Management API → direct SQL last resort (local only, sanctioned cases only)**; the admin UI is **verification-only** — every UI click is an Admin API call underneath, so a "UI-only" operation means the endpoint hasn't been found yet. On hosted installs there is no SQL rung: probe for MCP, else Management API, else ask the user ([references/online-mode.md](references/online-mode.md)). The full contract — the surface table, the scaffold ladder, why SQL-cloning structural trees is forbidden — is owned by [references/surface-priority.md](references/surface-priority.md). This rule is owned by this skill and inherited by every sister skill.

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

2. **Customer-context path** (the customer-context read-only contract -- hard abort, no approve branch). Any write to a path containing `customer-context\` (case-insensitive, both separators) aborts and redirects to `<demo>\notes\` or `<demo>\extracts\`. The canonical abort message, path-matching rule, and detection signature live in `references/customer-context.md`.

**Rationale:** Many B2B customers are fleeing heavily-customised legacy commerce/ERP stacks; the customisation budget is itself a pitch beat at the demo's closing slide. Every approved row is a deliberate trade-off; every Cancel/Refactor is a small win.

## Artifact hygiene — the demo root is not a scratchpad (always-on rule)

Ephemeral build evidence (QA screenshots, host logs, Playwright DOM/a11y dumps) has a canonical home under `notes\`; the demo root stays clean. This is the same guarded-write family as the two above — an output-path contract, owned here at base and inherited by every sister skill so every agent writes evidence to the same place instead of defaulting to CWD (the demo root).

1. **Canonical scratch layout under the demo root** — every ephemeral artifact routes to one of these three dirs, named in the verbatim command that produces it:

   | Directory | Holds | Named by |
   |---|---|---|
   | `notes\qa\` | QA screenshots + visual-QA evidence | `references/visual-qa.md`, `references/browser-automation.md` |
   | `notes\logs\` | host stdout/stderr logs | the "Host lifecycle authority" `Start-Process` recipe below |
   | `notes\snapshots\` | Playwright DOM / accessibility dumps | `references/browser-automation.md` |

2. **Root allowlist.** Only these may sit at the demo root: the plan doc (`DEMO-PLAN.md`), `CLAUDE.md`, `CUSTOMISATIONS.md`, `.gitignore`, `.mcp.json`, and directories. Anything else an agent wants to write at root routes to `notes\` instead — the same redirect wording as the customer-context contract ("did you mean `<demo>\notes\`?"). The harness enforces this end-of-phase (see the Foundry root-allowlist check).

3. **Naming rule — name evidence for what it IS.** An evidence dump is named for its content (`admin-a11y-snapshot-*.md`, `home-desktop-*.jpeg`), never for what it was captured *during*. Security-suggestive names for non-secret dumps (e.g. an accessibility snapshot saved as `apikeylist.md`) are forbidden — they read as leaked-secrets files to any human or scanner.

4. **Scaffold `.gitignore`.** The scaffolded demo's `.gitignore` ignores `notes/qa/`, `notes/logs/`, and `notes/snapshots/` (in addition to the existing `notes/credentials.local.md`, `bin/obj`, `wwwroot/Files/System/`) — see `references/scaffold.md` §2.1. Keeper screenshots worth committing are the deliberate exception: copy them out of `notes\qa\` explicitly.

## Personal data and vendor boilerplate — a blocking pre-demo leg (always-on rule)

**A Dynamicweb demo host serves real people's personal data and the platform vendor's own legal copy to a customer audience unless someone removes them.** This is true of an inherited/cloned host *and* of a demo built cleanly from stock Swift content — the vendor's privacy/terms copy, corporate addresses and an internal author mailing list are **stock seed data**, not clone residue. Neither exposure is visible from the admin screens a build normally opens.

Three rules, owned in full by [references/pii-sweep.md](references/pii-sweep.md) — read it before any demo is shown, published, screenshared or handed over:

1. **Renaming the user rows fixes nothing.** Order snapshots, address rows, token labels, log text and JSON merge-field snapshots each hold an independent copy. Enumerate by scanning **every string column**, classify by **sampling the values** (not by table name), fix, then **re-scan** — fixing one layer exposes the next.
2. **Sweep the stock vendor boilerplate too** — privacy / cookie / terms pages, corporate addresses, the email-recipient author list. De-brand the marketing and legal copy; keep genuinely technical vendor references accurate rather than inventing false identifiers.
3. **A term-grep cannot find placeholder data containing none of your terms.** Add locale-*shaped* patterns (foreign dialling codes, foreign postcodes, registration-number formats) and keep the rendered-page eyeball pass as a **required** step.

**Never copy the leaked values forward** — into notes, commits, tickets, transcripts or skill text. Record the *class* and the count; the data itself stays where it is until it is removed.

## Demo philosophy — go deep, not wide

Demo time is short; condensed beats spread. Default to a single deep storyline rather than a broad surface tour — every login, channel, locale, and customer-center section the user has to scan during the live demo is time stolen from the part you actually want to land.

**Default postures (sister skills enforce the specifics):**

- **Logins / personas — floor of 2.** One buyer + one CSR so impersonation has somewhere to land. Don't scaffold a roster of personas you won't have time to log into. Owned by `dw-demo-swift`.
- **Shops / channels — 1 + 1.** One shop plus the channel most relevant to the customer's pitch. Don't add a second channel of equal weight. Owned by `dw-demo-pim`.
- **Locale — single home market.** US-only for a US customer (EN/USD), DE-only for a DACH customer, etc. Add a second language/currency only when the customer's case explicitly demands it. Owned by `dw-demo-pim`.
- **Customer-center sections, paragraph types, page presets — storyline-driven.** Scaffold the ones the storyline actually visits, not the ones the platform supports. Owned by `dw-demo-swift`.

**Product catalogue is the deliberate exception — go deep AND wide there.** Rich product data (variants, BOM bundles, completeness rules, assortments, ample SKUs across categories) is cheap to produce via MCP and makes the demo feel real instead of sketched. The "narrow it down" rule does not apply to product modelling — see `dw-demo-pim` for the modelling depth recipes.

When in doubt: every login / channel / locale / customer-center section must justify itself against demo minutes. A product family does not need to justify itself. Generic storytelling tactics (audience framing, one-source-N-shapes, speak the customer's words): [references/demo-tactics.md](references/demo-tactics.md).

## Sister skills

- **`dw-demo-pim`** -- PIM modelling, structural mental model (shops vs channels, GroupType, repositories, variants, BOM, channels + feeds, assets, product categories), MCP/API/SQL/filesystem decision matrix. **Use AFTER** `dw-demo-base`.
- **`dw-demo-swift`** -- Swift frontend (templates, paragraph types, B2B customer-center scaffolding, baseline deserialize). **Use AFTER** `dw-demo-base`.
- **`dw-demo-erp`** -- ERP integration (source/target rule, DB-staged mock, scenarios-first planning). **Use AFTER** `dw-demo-base`.
- **`dw-integration-bc`** -- live BC connector via ngrok + AppStore connector. **Use AFTER** `dw-demo-base`.

A sibling skill that runs without `dw-demo-base`'s outputs (no `.mcp.json`, no `CUSTOMISATIONS.md`) silently no-ops or produces broken artefacts. The "Use FIRST" routing wording in this skill's description and the "Use AFTER" markers in the sister skills are the inoculation.

## Reference-content layout

Demo artifacts (base, catalog, theme, and feature layers) are checked out per-demo from the Distribution clone into the demo's own `<demo-root>\distribution\` folder — see "Versions prompt + Distribution clone/checkout" above. There is no shared machine-wide vault; each demo consumes the latest gate-proven `main` and records the resolved commit SHA as its reproducibility stamp.

Two read-only reference sources are **local clones**, not downloads, and their location is per-machine — **ask or discover it, never hardcode**:

- **DW10 source** — a local clone of the DW10 source, used for deep schema/internals search (`src/Features/Ecommerce`, `Dynamicweb.Products.UI`, etc.). Where a reference says "search the DW10 source", it means this clone.
- **Swift design package** — a local clone of `https://github.com/dynamicweb/Swift` at the demo's Swift version (`<demo-root>\dw-swift\`), the source of item-type XMLs, templates, styles, and icons for the deserialize.

## Path-resolution rule

Paths in this skill (and sister skills) resolve under the demo's own root (`<demo-root>\baselines\...`) or a per-machine local clone whose location is asked/discovered. Per-machine hardcoded literals (legacy paths under user-specific source folders or sibling solution folders) are a known anti-pattern; the existing `dw-demo-pim` skill still carries some as a cautionary cleanup target.

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




