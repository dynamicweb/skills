# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude plugin marketplace of skills for Dynamicweb 10, bundled by role. The repo is
markdown and configuration files — no build system and no runtime code. The one piece of
tooling is `scripts/validate-skills.py`, a structural linter (see "Validation" below).

## Key files

- `.claude-plugin/marketplace.json` — the plugin registry. Defines 6 role bundles (`dynamicweb-setup`, `dynamicweb-frontend`, `dynamicweb-commerce`, `dynamicweb-backend`, `dynamicweb-developer`, `dynamicweb-presales`). Each entry uses `"source": "./"` + `"strict": false` and curates the bundle via a `skills` array of paths into `skills/`. The top level requires `name` (string), `owner` (object), and `plugins` (array); `description`/`version` live under `metadata`.
- `skills/<skill-name>/SKILL.md` — the skill definition. YAML frontmatter (`name`, `description`) plus the instruction body.
- `skills/<skill-name>/references/*.md` — reference material loaded by the skill at runtime.
- `skills/<skill-name>/assets/` — template files the skill scaffolds onto disk.
- `skills/<skill-name>/scripts/` — PowerShell scripts invoked by the skill.

## Authoring rules

### Naming

All skills use the `dw-<domain>-<topic>` prefix — folder name, `name:` frontmatter, and the
marketplace `skills` path basename must all match exactly. (Only the role *bundles* in
`marketplace.json` carry the `dynamicweb-` prefix.) Skill files must be saved as UTF-8
**without a BOM** — a leading BOM defeats some frontmatter parsers and the validator rejects it.

### SKILL.md frontmatter

```yaml
---
name: dw-<domain>-<topic>
description: <one to three sentences. First sentence states what the skill does. Remaining sentences list the exact trigger phrases / conditions that activate it.>
---
```

The `description` field is the activation signal — it is matched against the user's request at runtime. Write it in the third person using this shape:

1. **First sentence** — what the skill does.
2. **`Triggers:`** — the phrases / conditions / error symptoms that should activate it.
3. **`Non-triggers:`** — adjacent cases that belong to a sibling skill, each routed with `-> dw-<other-skill>`.

Example (`dw-pim-completeness`):

```
description: Create and configure Dynamicweb 10 dashboards and widgets using MCP tools. Triggers: create a dashboard, add or configure widgets, build query-backed count widgets. Non-triggers: building the underlying product query -> dw-search-indexing; designing the PIM data model -> dw-pim-workflow.
```

Demo skills additionally carry a `Use AFTER dw-demo-base` marker (see below). Keep
descriptions on a single line.

### Adding a new skill

1. Create `skills/dw-<domain>-<topic>/SKILL.md` with matching `name:` frontmatter (UTF-8, no BOM).
2. Add `references/`, `assets/`, or `scripts/` subdirectories as needed.
3. Register the skill path in the relevant bundle(s) in `.claude-plugin/marketplace.json`, as a `"./skills/dw-<domain>-<topic>"` entry in that bundle's `skills` array.
4. Add an entry to the README skills table and skills section.
5. Run `python3 scripts/validate-skills.py` and fix any errors before committing.

### Updating marketplace.json

Skills can appear in more than one bundle — list the same `"./skills/..."` path in each
bundle's `skills` array (no copying or symlinks; sharing is what the `source: "./"` +
`strict: false` pattern is for). Each bundle entry must keep its `source` and `strict: false`.
Paths under `skills` are resolved relative to the source root and start with `./`. Bump the
`version` under `metadata` (semver) when skills are added or renamed.

### Demo skills dependency order

The `dynamicweb-presales` bundle has a hard dependency chain — `dw-demo-base` must run before any sister skill (`dw-demo-pim`, `dw-demo-swift`, `dw-demo-erp`, `dw-integration-bc`). Sister skill descriptions carry a "Use AFTER dw-demo-base" marker; preserve this on any edits.

## Validation

`scripts/validate-skills.py` (Python 3, no dependencies) is the structural linter. It checks
that `marketplace.json` parses and has the required top-level schema (`name`, `owner`,
`plugins`), that every plugin entry has a `source` and every referenced skill path exists;
that each skill's folder name, `name:` frontmatter, and marketplace path agree; that every
relative link in `SKILL.md`/`references` resolves; that no markdown file begins with a UTF-8
BOM; and that the retired "truvio" codename appears nowhere. It warns (without failing) when a
description lacks a trigger signal.

For a deeper check against Claude Code's own plugin schema, also run `claude plugin validate ./`.

Run it before committing:

```
python3 scripts/validate-skills.py
```

To run it automatically at the start of every Claude Code session (so structural breakage
surfaces immediately), add this `SessionStart` hook to `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "python3 \"$CLAUDE_PROJECT_DIR/scripts/validate-skills.py\"" } ] }
    ]
  }
}
```

Record notable changes (skills added/renamed, role-bundle moves, structural changes) in
`CHANGELOG.md`, and bump `marketplace.json`'s `version` accordingly.

## No PRs

Commit and push directly to the working branch. Do not open pull requests.

## Commits

Do not add `Co-Authored-By` lines or any other self-attribution to commit messages.
