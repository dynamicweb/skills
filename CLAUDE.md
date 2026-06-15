# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude plugin containing 15 skills for Dynamicweb 10. There is no build system, no tests, and no code to run — the entire repo is markdown and configuration files.

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

The `description` field is the activation signal — it is matched against the user's request at runtime. Write it in the third person, be explicit about triggers and non-triggers, and include the "Use when…" / "Non-triggers:" pattern used by the existing skills.

### Adding a new skill

1. Create `skills/dynamicweb-<slug>/SKILL.md` with matching `name:` frontmatter.
2. Add `references/`, `assets/`, or `scripts/` subdirectories as needed.
3. Register the skill path in the relevant plugin(s) in `.claude-plugin/marketplace.json`.
4. Add an entry to the README skills table and skills section.

### Updating marketplace.json

Skills can appear in more than one plugin. Paths are relative from the repo root (`skills/dynamicweb-<slug>`). The `version` field in the `marketplace` block should be bumped (semver) when skills are added or renamed.

### Demo skills dependency order

The `dynamicweb-presales` skills have a hard dependency chain — `dynamicweb-demo-base` must run before any sister skill (`dynamicweb-pim-demo`, `dynamicweb-swift-demo`, `dynamicweb-erp-demo`, `dynamicweb-pim-for-bc`). Sister skill descriptions carry a "Use AFTER dynamicweb-demo-base" marker; preserve this on any edits.

## No PRs

Commit and push directly to the working branch. Do not open pull requests.

## Commits

Do not add `Co-Authored-By` lines or any other self-attribution to commit messages.
