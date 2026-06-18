# Changelog

All notable changes to the Dynamicweb Skills plugin are recorded here. The
`version` field in `.claude-plugin/marketplace.json` tracks these entries.

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
