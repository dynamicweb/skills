# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude plugin containing 15 skills for Dynamicweb 10. The repo is markdown and
configuration files — no build system and no runtime code. The one piece of tooling is
`scripts/validate-skills.py`, a structural linter (see "Validation" below).

## Key files

- `.claude-plugin/marketplace.json` — the plugin registry. Defines 4 role bundles (`dynamicweb-developer`, `dynamicweb-implementer`, `dynamicweb-user`, `dynamicweb-presales`), each referencing skill paths.
- `skills/<skill-name>/SKILL.md` — the skill definition. YAML frontmatter (`name`, `description`) plus the instruction body.
- `skills/<skill-name>/references/*.md` — reference material loaded by the skill at runtime.
- `skills/<skill-name>/assets/` — template files the skill scaffolds onto disk.
- `skills/<skill-name>/scripts/` — PowerShell scripts invoked by the skill.

## Authoring rules

### Naming

All skills use the `dynamicweb-` prefix — folder name, `name:` frontmatter, and marketplace path must all match exactly.

### SKILL.md frontmatter

```yaml
---
name: dynamicweb-<slug>
description: <one to three sentences. First sentence states what the skill does. Remaining sentences list the exact trigger phrases / conditions that activate it.>
---
```

The `description` field is the activation signal — it is matched against the user's request at runtime. Write it in the third person using this shape:

1. **First sentence** — what the skill does.
2. **`Triggers:`** — the phrases / conditions / error symptoms that should activate it.
3. **`Non-triggers:`** — adjacent cases that belong to a sibling skill, each routed with `-> dynamicweb-<other-skill>`.

Example (`dynamicweb-pim-dashboard`):

```
description: Create and configure Dynamicweb 10 dashboards and widgets using MCP tools. Triggers: create a dashboard, add or configure widgets, build query-backed count widgets. Non-triggers: building the underlying product query -> dynamicweb-pim-query; designing the PIM data model -> dynamicweb-pim-solution-assistant.
```

Demo skills additionally carry a `Use AFTER dynamicweb-demo-base` marker (see below). Keep
descriptions on a single line.

### Adding a new skill

1. Create `skills/dynamicweb-<slug>/SKILL.md` with matching `name:` frontmatter.
2. Add `references/`, `assets/`, or `scripts/` subdirectories as needed.
3. Register the skill path in the relevant plugin(s) in `.claude-plugin/marketplace.json`.
4. Add an entry to the README skills table and skills section.
5. Run `python3 scripts/validate-skills.py` and fix any errors before committing.

### Updating marketplace.json

Skills can appear in more than one plugin. Paths are relative from the repo root (`skills/dynamicweb-<slug>`). The `version` field in the `marketplace` block should be bumped (semver) when skills are added or renamed.

### Demo skills dependency order

The `dynamicweb-presales` skills have a hard dependency chain — `dynamicweb-demo-base` must run before any sister skill (`dynamicweb-pim-demo`, `dynamicweb-swift-demo`, `dynamicweb-erp-demo`, `dynamicweb-pim-for-bc`). Sister skill descriptions carry a "Use AFTER dynamicweb-demo-base" marker; preserve this on any edits.

## Validation

`scripts/validate-skills.py` (Python 3, no dependencies) is the structural linter. It checks
that `marketplace.json` parses and every referenced skill path exists; that each skill's
folder name, `name:` frontmatter, and marketplace path agree; that every relative link in
`SKILL.md`/`references` resolves; and that the retired "truvio" codename appears nowhere. It
warns (without failing) when a description lacks a trigger signal.

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
