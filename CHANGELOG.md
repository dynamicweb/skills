# Changelog

All notable changes to the Dynamicweb Skills plugin are recorded here. The
`version` field in `.claude-plugin/marketplace.json` tracks these entries.

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
