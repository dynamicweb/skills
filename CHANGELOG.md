# Changelog

All notable changes to the Dynamicweb Skills plugin are recorded here. The
`version` field in `.claude-plugin/marketplace.json` tracks these entries.

## [3.3.6]

### Changed
- **Split `dw-headless-delivery/SKILL.md` under the 500-line budget** (569 → 104 lines). The
  SKILL.md had grown into a flat `/dwapi/` endpoint catalog. Moved the endpoint-family listings
  (Content, Products, Cart, Checkout, Orders, Users, Favorites, Internationalisation, Loyalty
  Points, Forms, Query, Connectivity) verbatim into a new `references/endpoint-reference.md` (with
  a top-of-file table of contents), and kept the gateway concepts in SKILL.md — authentication,
  the headless architecture rules, and a routing table that links each family to its section in
  the reference. No endpoint content was lost or changed.

## [3.3.5]

### Changed
- **Trimmed the `dw-demo-base` description under the 1024-char frontmatter limit** (1093 → 984
  chars). The activation description had grown past the hard cap and risked truncation by
  frontmatter parsers. Dropped redundant route-phrases ("register the skills to GSD", "what runs
  the build", "publish this update") and an explanatory parenthetical; every distinct trigger
  concept — scaffolding, MCP-load failure symptoms, fresh-machine/online modes, the orchestrator
  and fold-back routes, sister-skill ordering, and the read-only `customer-context` contract — is
  preserved.

## [3.3.4]

### Changed
- **Recast bare prohibitions as positive (or paired) instructions across the skill set.** Models
  follow "do A" more reliably than a bare "don't do B" — a bare prohibition raises B's salience and
  leaves the target underspecified. Converted bare directive prohibitions to positive form where the
  target was obvious, and to the paired "do A, not B" form where B is the model's natural pull (raw
  SQL on core tables, URL-parsing to identify a product, disabling strict mode, auto-fixing a
  User-scope mutation, starting new templates on TemplateTags, etc.). The flagship case is
  `dw-demo-swift/references/dw10-canonical-surfaces.md`, whose nine `NEVER:` bullets each now name
  the canonical surface alongside the boundary. Already-paired negations, descriptive prose, few-shot
  anti-pattern blocks, and hard one-way contracts were left as-is.
- **Encoded the principle in the authoring guidance** so new skills and fold-backs follow it: a
  "Phrase instructions positively" rule in `dw-demo-base/references/iterate-plugin.md` (with the test
  for when contrast earns its place, and the few-shot exemption) and a pointer to it from
  `CLAUDE.md`. Applied the rule to the guidance's own prohibitions too.

## [3.3.3]

### Changed
- **Stripped "time-noise" from the skills — wall-clock/effort claims and inline date stamps an LLM
  can't use (sweep across ~25 demo-skill reference files).** Two classes removed: (1) subjective
  duration/effort flourishes (`~30 seconds on a warm SQL Express`, `don't burn a half-day`,
  `you've wasted hours`, `saves time`, `classic time-sink`, `Pay the 15 minutes`) — the actionable
  rule is kept, the time estimate dropped; (2) inline prose date markers (`(verified 2026-05-21)`,
  `(validated DW 10.25.x, 2026-06-10)`, `Superseded 2026-05-08:`, `A 2026-06 demo audit found`) —
  the date already lives in `git log`; where a marker also carried a build version (`DW 10.25.x`)
  the version is preserved and only the date dropped. Dates that are *data* (SQL literals, JSON
  example payloads, the `CUSTOMISATIONS.md` ledger column the audit regex keys on) are untouched,
  as are functional durations (script timeout bounds, schedule intervals, cache TTLs, presenter
  pacing).
- **Added the guardrail to `dw-demo-base/references/iterate-plugin.md`** so folds don't reintroduce
  it: the scrub table now has a "Wall-clock duration / effort claims" row and a strengthened
  "Session-relative time AND inline date stamps" row (resolve to *nothing* — the date is in `git
  log`), and the provenance-citation rule now names roles, never individuals **or** dates.

## [3.3.2]

### Changed
- **Documented the index-build-reads-through-cache ordering trap for SQL product-data writes
  (`dw-demo-pim/references/cache-invalidation.md`).** The cache table had no row for direct SQL
  edits to `EcomProducts` translatable fields, and nothing warned that the Lucene index builder
  reads product data *through* the live `ProductService` cache. Symptom: after translating a
  catalogue into a new ecommerce language via SQL and rebuilding the index, PDP + PLP stayed in the
  default language — because `BuildIndex` ran while the product cache was stale and baked the old
  values in. Added the table row + a dedicated section stating the correct order (write →
  flush/restart → *then* BuildIndex; reindex-then-restart is wrong), and a note that MCP
  `patch_products_safe` with a non-default `languageId` was observed to echo the translation but not
  persist it (verify the DB row; SQL was the reliable write surface).

## [3.3.1]

### Changed
- **Reversed the Backend MCP AddIn install order — NuGet `PackageReference` is now the default,
  the admin AppStore the last resort (`dw-demo-base/references/scaffold.md` §2.1/§2.1c, and the
  surface-priority table in `dw-demo-base/SKILL.md`).** The prior wording called the AppStore the
  "canonical" route and NuGet the headless "alternative" — backwards for an agent-driven build. The
  `PackageReference` route is deterministic, scriptable, and idempotent (a csproj edit), registers the
  AddIn at host startup, and sidesteps the virtualized AppStore "Available apps" grid that Playwright
  can't drive reliably; it also aligns with the standing rule that the admin UI is verification-only,
  never an action surface. The AppStore is now framed as the fallback for when the host csproj can't be
  edited, to be clicked manually rather than driven via Playwright. The MCP *config*-creation ordering
  in `mcp-setup.md` is deliberately left admin-UI-first, because its scriptable alternative is brittle
  reflection into an internal type (`McpConfigurationService.LinkToken`).

## [3.3.0]

### Added
- **Orchestrator abstraction for presales demo builds — `dw-demo-base/references/orchestrator.md`
  plus a native `/demo:*` command set.** Separates the demo skills (domain-knowledge *substrate*)
  from the thing that *drives* a build through its phases — now named the **orchestrator** (the
  industry term; "driver" was rejected to avoid overloading the device-/browser-driver sense). Two
  orchestrators are supported behind a common substrate: **GSD (primary)** — its discuss → plan →
  execute → verify → review → ship pipeline injects the skills into fresh-context agents, with the
  verifier loop and audit-fix; and a **native command set (floor)** — `/demo:scaffold`,
  `/demo:impact`, `/demo:build`, `/demo:status`, scaffolded into the demo project's
  `.claude/commands/demo/` (templates in `dw-demo-base/assets/commands/demo/`). The native commands
  detect GSD (`.planning/` or a `/gsd-*` surface) and defer to it unless passed `--standalone`, so
  the two never drive the same build. One human gate in both modes — the impact sign-off; everything
  else is automated (GSD's convergence loop, or the native single-pass validate against shared
  acceptance criteria). Names the **two gate types** explicitly — a single human sign-off vs the
  automated **validate/gap/buff loop** (builder → fresh-context validator → gap feedback → re-run
  until PASS/cap) — so scaffold and customer build are gated *without* a human pause; documents the
  per-mode assurance ladder and the throwaway-demo escape hatches; and flags the GSD upstream split
  (GSD Core / Open GSD) to verify agent type names and `/gsd-update` before wiring.
- **Lightweight in-skill harness for fully standalone runs (the floor).** With no GSD and no
  `/demo:*` commands, the demo skills are no longer run blind: each guards its own canonical flow —
  walk it in order, gate every step (refuse to skip or to declare the build done before a gate
  passes), and persist progress to a resumable `.demo/<slug>/flow-state.json` artifact that the
  native `state.json` and GSD both read as a superset. Lightweight on purpose — ordering + gate
  discipline + resumability, nothing heavier; promote to the native command set or GSD for real
  assurance.
- **The `agent_skills` keystone — `dw-demo-base/assets/agent_skills.config.json`.** Registers the
  demo skills to GSD agent types, keyed to the **real** agent type names in this install
  (`gsd-project-researcher`, `gsd-phase-researcher`, `gsd-planner`, `gsd-executor`, `gsd-verifier`).
  No skill is rewritten for either orchestrator; both read the same `SKILL.md` files.
- **3-phase roadmap template — `dw-demo-base/assets/ROADMAP.template.md`** (scaffold → customer
  build → polish), with the strictness gradient and acceptance criteria per phase.
- **Per-skill "how to run me" header** on every demo skill (`dw-demo-base`, `dw-demo-pim`,
  `dw-demo-swift`, `dw-demo-erp`, `dw-integration-bc`): the skill holds knowledge, not sequencing;
  an orchestrator owns the phase order, and standalone the skill's own order applies. Disambiguated
  the legacy "this SKILL.md is an orchestrator" nav phrasing to "nav layer" so the term is reserved
  for the build orchestrator.

## [3.2.4]

### Added
- **Invoking internal DW services by reflection — DI-timing constraint in
  `dw-extend-csharp-api/SKILL.md`.** Folded from a headless DW10 install. Adds a "last resort" subsection
  to the service-access patterns: some DW services are `internal` (no compile-time type) but resolvable
  from the DI container at runtime, and reflection-invoking one only works **inside the built host after
  `app.UseDynamicweb()` has run** — from a standalone console/utility process the container is
  uninitialised and the call fails on `Microsoft.Extensions.DependencyInjection.Abstractions`. Shows the
  `Assembly.Load` → `GetType` → resolve-from-`app.Services` → `MethodInfo.Invoke` pattern, flags it as
  version-fragile, and steers callers to public facades / `DependencyResolver` when a public surface exists.

## [3.2.3]

### Added
- **Headless MCP token + configuration binding (`McpConfigurationService.LinkToken`) in
  `dw-demo-base/references/mcp-setup.md`.** Folded from a headless DW10 install. New
  "Step 3 (headless alternative)" documents creating the API token in code
  (`TokenService.TryCreateToken` with an `ApiTokenRequestModel`, returning the unhashed `CLAUDE.<secret>`
  bearer) and the MCP configuration row (`AllowEverything = 1`) when the admin UI isn't reachable — and the
  load-bearing gotcha: a raw `McpConfigurationCredential` insert does **not** satisfy the auth path (still
  401), so the token must be bound via the internal `McpConfigurationService.LinkToken(configId, tokenId,
  user)` invoked by reflection from the live `app.Services`, followed by a host restart (the MCP config is
  cached at startup). Carries a brittleness warning (internal type, version-fragile) steering callers back
  to the admin-UI route when it's reachable. Step 6's binding note updated for consistency.

## [3.2.2]

### Added
- **Headless Backend MCP AddIn install via NuGet PackageReference in `dw-demo-base/references/scaffold.md`
  (new §2.1c).** Folded from a headless DW10 install. The canonical flow installs the MCP AddIn through
  the admin AppStore; when the admin UI isn't reachable (fully headless build / automated provisioning),
  add `<PackageReference Include="Dynamicweb.MCP" Version="…" />` to the host csproj instead — the AddIn
  registers at host startup and `/admin/mcp` goes from 404 to live with no AppStore click. Records that
  the net10 TFM requirement (§2.1) still applies, that this also sidesteps the virtualized AppStore
  "Available apps" grid (which Playwright struggles to drive), and that the beta-track package version must
  match the resolved Suite version. §2.1 cross-reference updated.

## [3.2.1]

### Changed
- **Port-targeted host control + stable host start in `dw-demo-base`.** Folded from a headless
  DW10 install. The "Host lifecycle authority" stop command matched the shared
  `Dynamicweb.Host.Suite` project name (`*Dynamicweb.Host.Suite*`), so stopping one demo's host
  killed *sibling* demos' hosts too — every demo scaffolds that same project name. Stop now
  targets the host by its launchSettings **port** (`Get-NetTCPConnection -LocalPort`), and the
  same fix replaces the name-only kill in the `references/scaffold.md` ring-swap process-lock
  gotcha. The durable-start guidance now **redirects stdout/stderr to log files** (a hidden
  `Start-Process` without redirection proved flaky — the process exits after kickoff), and adds a
  `dotnet run --no-build` caveat (a failed prior build means `--no-build` silently launches the
  stale DLL and can lock the exe).

## [3.2.0]

### Added
- **`manifest.json` + `scripts/build-manifest.mjs` — a generated skill index for the Dynamicweb MCP server ("Dynamo").**
  Dynamo fetches a single `manifest.json` from the repo root to auto-discover skills (grouped by
  `type` then `group`, one-sentence `description` per skill, `path` to each `SKILL.md`). The
  generator (Node, no dependencies) derives the manifest from each skill's frontmatter; `--check`
  mode fails CI on drift via `.github/workflows/manifest-check.yml`. Claude Code behaviour is
  unchanged — it still loads skills through `marketplace.json`. Layout kept flat.

### Changed
- **Added `type` (`knowledge`/`flow`) and `group` frontmatter to every skill.** Nine skills are
  flows (the setup-install/upgrade, swift-building, extend-mcp-tools, and the demo chain); the rest
  are knowledge.
- **Fixed four mislabeled descriptions** whose text had been copied from unrelated agent skills:
  `dw-pim-modelling` (was an enrichment description), `dw-pim-workflow` (was a solution-assistant
  description), `dw-pim-completeness` (was a dashboards description), and `dw-search-indexing` (was a
  product-query description) now describe what their bodies actually cover.
- **Tightened skill lead sentences** so each is a single intent-bearing sentence with no mid-sentence
  periods (Dynamo shows the description up to the first `.`). Corrected stale `dynamicweb-*` sister
  references in the demo skills to the real `dw-*` names.

### Renamed
- **`dw-tbd-source-explorer` → `dw-source-explorer`** (the `tbd` placeholder is resolved). Updated the
  folder, frontmatter `name`, `marketplace.json` path, and README.

## [3.1.4]

### Added
- **Checkout reads the billing address from the user profile, not from `UserAddress` records — in `dw-demo-swift/references/customer-center.md` §4.**
  A recurring 2026-06 build symptom: a buyer seeded with `save_user_addresses` (Billing + Shipping
  `UserAddress`) but a blank profile address could not complete checkout — checkout showed "no address
  selected" on the billing side and the step would not advance. Root cause is stock Swift, not the demo:
  `eCom7/CartV2/Step/InformationUser.cshtml` gates the Continue button on `addressString`, built solely
  from `UserManagement:User.Address/Zip/City`, and `Helpers/AddressUser.cshtml`'s "Same as billing
  address" option reads those same profile fields; the default Shipping `UserAddress` still pre-selects
  for delivery, which is why only the billing side looks empty. Fix: populate the profile address too
  (`update_users` / the `AccessUser` columns), mirroring the Billing `UserAddress`, for every buyer
  persona. Sharpened the previously-incomplete "addresses come from `save_user_addresses`" claim in place
  and updated the SKILL.md routing row.
- **Customer-specific pricing + buyer-dashboard gating in `dw-demo-swift/references/customer-center.md`.**
  Continues the 2026-06 customer-experience build. (1) New §9 on contract / "customer-card" pricing:
  `save_prices`'s `customerGroupId` writes `PriceCustomerGroupId`, which the frontend price resolver does
  **not** match against a logged-in user's groups — the price silently never applies; the reliable scope is
  `PriceUserCustomerNumber` (the account's customer number). Lowest matching price wins (not priority);
  customer prices resolve **live in the cart/checkout**, not on PLP/PDP (index context); prices are cached
  (restart to apply); and `force_price_recalculation` recomputes without a frontend price context so it's
  not a valid test. (2) §6 extended with the inverse gate — hiding the buyer's Account sections from a pure
  CSR persona — and the load-bearing rule that frontend permission resolution takes the **highest** level
  across a user's identities, so you deny the broad role + grant the customer group rather than denying the
  staff group. SKILL.md routing row updated.

## [3.1.3]

### Added
- **Customer-experience seeding + account-type specifics in `dw-demo-swift/references/customer-center.md`.**
  A 2026-06 build that seeded the CSR/account section directly (MCP + SQL) instead of from a
  customer-flavoured baseline hit three stock filters that silently hide correct data, none previously
  documented: (1) `CSR/Accounts/` lists only groups flagged `AccessUserUserAndGroupType = 'SystemAccount'`
  (a group made via `save_user_groups` lands plain, so the page reads empty while its users still show
  under `CSR/Users/`); (2) placed orders appear in "My orders" only when `EcomOrders.OrderComplete = 1`,
  and favorites seeded via SQL need empty-string (not NULL) `ProductVariantId` / `Note` /
  `ProductReferenceUrl` / `UnitId`; (3) the §6 permission gate, when its `Permission` rows are written via
  SQL rather than the admin UI, needs a security-cache refresh/restart to take effect and resolves grants
  by role/group, not by individual user id. SKILL.md routing row updated to surface seeding + the
  "looks empty" symptoms.

## [3.1.2]

### Added
- **Component-first gate in `dw-demo-swift/references/paragraphs.md`.** Swift ships a standard component
  for most PLP/PDP/navigation needs, but the default reflex on a "make the UI do X" request was to author
  or override a `.cshtml` — which accrues off-baseline code a Serializer re-deploy drops, and (on a
  2026-06-21 build) produced a hand-rolled category-banner hero that errored twice when
  `Swift-v2_ProductListGroupPoster` already does exactly that. The reference now leads with a mandatory
  gate (enumerate the standard components → classify the change as place / configure / override / new →
  pick the lowest tier) plus a "common need → standard component" catalogue (group poster/image, subgroup
  nav grid/list/slider, component slider for related/similar, field-display accordion, BOM). Generalises
  the existing "Don't customise this paragraph" callouts; SKILL.md routing row updated to surface it.

## [3.1.1]

### Fixed
- **Browser MCP screenshots no longer land in the demo solution root.** `browser_take_screenshot`
  writes relative filenames against the MCP server's working directory, which is the folder Claude
  Code was launched from — so a verification flow with bare filenames littered the demo repo root
  (~40 stray `.jpeg` files in one build). `dw-demo-base/references/browser-automation.md` now adds a
  "Where screenshots land" section and a `--output-dir` install flag: pin a neutral machine-level
  scratch dir at user scope (cross-demo plumbing, so it must NOT be any one demo's folder), and pass
  an absolute `<demo>\notes\playwright\` filename for keeper shots. The one-line install in
  `mcp-setup.md` carries the same `--output-dir` flag.

## [3.1.0]

### Changed
- **New way of working: every change lands via PR.** Replaced the `## No PRs` rule in
  `CLAUDE.md` with a PR-based workflow — branch off the integration branch (`v2` until it
  merges to `main`), one atomic logical change per PR, validate + version-bump + docs in the
  same commit, squash-merge. The `## Commits` note now ties the commit subject to the PR title
  and keeps the no-`Co-Authored-By` rule.
- **Made the foundational-vs-demo split explicit and one-way.** Added a "Skill categories"
  section to `CLAUDE.md`: foundational skills are vendor-generic and carry zero demo/customer
  content and no links into demo skills; demo skills (`dw-demo-*` + `dw-integration-bc`) build
  on foundational ones; learnings flow demo → foundational only via the sanitized fold-back.
- **Rewrote the maintainer fold-back** (`skills/dw-demo-base/references/iterate-plugin.md`) for
  the migrated repo and the new model. It now targets `dynamicweb/skills` (was
  `justdynamics/dynamicweb-commerce-demo`), bumps the single `metadata.version` in
  `marketplace.json` (the old dual-manifest `plugin.json` rule is retired), runs
  `python3 scripts/validate-skills.py` (was `scripts/validate.py`), uses the current `dw-*`
  skill names, and lands every fold via a PR with the leak-catch window before merge. Added a
  load-bearing first step that routes each learning foundational-vs-demo. The Step 1a
  sanitization and Step 1b content-hygiene gates are preserved. Updated the matching fold-back
  row and section in `dw-demo-base/SKILL.md`.

## [3.0.1]

### Fixed
- **Made the marketplace installable on released Claude Code** (verified against 2.1.181 and
  `claude plugin validate`). Three blockers:
  - `marketplace.json` used a `"marketplace": { ... }` wrapper, leaving the required top-level
    `name` and `owner` undefined so the loader could not parse it. Flattened to top-level
    `name` / `owner` / `plugins`, with `description` and `version` under `metadata`.
  - Plugin entries listed only `skills: [paths]` with no `source`, so there was nothing to
    fetch and install failed. Each of the six bundles now declares `"source": "./"` +
    `"strict": false` and curates its skills via the path list — the
    marketplace-root-source pattern, which is exactly what lets bundles share skills.
  - Stripped the UTF-8 BOM from all 41 BOM-carrying markdown files under `skills/`.
- **Refreshed `README.md` and `CLAUDE.md`** to the current `dw-*` skill layout and six role
  bundles (`dynamicweb-setup` / `frontend` / `commerce` / `backend` / `developer` /
  `presales`), and to the current install commands (`claude plugin marketplace add` /
  `claude plugin install`).

### Added
- `validate-skills.py` now enforces the marketplace top-level schema (`name`/`owner`/
  `plugins`), requires a `source` on every plugin entry, resolves `./`-prefixed skill paths,
  and rejects any markdown file that begins with a UTF-8 BOM.

## [2.1.0]

### Changed
- **Removed the retired "Truvio" codename** across all skills, references, templates, the
  MCP server name (`dynamicweb-commerce-mcp`), and env-var names (`DYNAMICWEB_*`). Fixed the
  broken `truvio-*` skill cross-references and the `../`-depth errors in cross-skill
  reference links they were masking. Renamed `truvio-connector-settings.md` ->
  `dynamicweb-connector-settings.md`.
- **Standardized every SKILL.md description** to the `first sentence + Triggers: +
  Non-triggers:` convention, with non-triggers routed to the correct sibling skill.
- **Role rebalance:** moved `dynamicweb-business-solution-agent` from the `dynamicweb-user`
  bundle to `dynamicweb-implementer` (it is a heavy installer/orchestrator, not an
  end-user tool). The `dynamicweb-user` bundle is now `pim-enrichment` + `pim-query`.

### Fixed
- `dynamicweb-mcp-tool-creator` no longer points at the non-existent
  `dynamicweb-tool-picker` skill; it now directs tool documentation to the Dynamicweb.MCP
  project's own catalog/README.
- Stripped a stray UTF-8 BOM from `dynamicweb-mcp-tool-creator/SKILL.md`.

### Added
- `scripts/validate-skills.py` — structural linter (marketplace integrity, name/folder/path
  agreement, relative-link resolution, codename purge check, description-signal warnings).
- Authoring/validation guidance in `CLAUDE.md` and this `CHANGELOG.md`.

## [2.0.0]
- Baseline: 15 skills bundled into 4 role plugins (developer, implementer, user, presales).
