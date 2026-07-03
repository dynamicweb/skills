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

### Skill categories: foundational vs demo (strict one-way)

Every skill is one of two kinds, and the boundary is load-bearing:

- **Foundational skills** — every `dw-<domain>-<topic>` skill that is *not* a demo skill
  (setup, render, content, pim, commerce, search, users, extend, integration, data-access,
  source-explorer). These are vendor-generic, reusable Dynamicweb 10 platform knowledge.
  They ship in the role bundles that implementers and developers install.
- **Demo skills** — the presales chain: `dw-demo-base` and its sisters (`dw-demo-pim`,
  `dw-demo-swift`, `dw-demo-erp`) plus the `dw-integration-bc` connector demo. These scaffold
  live presales demos and carry the demo-only guardrails (the customisations ledger, the
  read-only `customer-context/` contract, the maintainer fold-back).

The dependency direction is **one-way and enforced**:

1. **Foundational skills must contain zero demo- or customer-specific content** — no
   engagement slugs, customer/brand/personal names, session-relative time markers, or
   presales-scaffolding assumptions. They must read as if no demo ever existed.
2. **Foundational skills must never reference or depend on a demo skill.** Demo skills may
   build on foundational ones; never the reverse. A `references/` link or routing row from a
   foundational skill into `dw-demo-*` is a boundary violation.
3. **Learnings flow demo → foundational only via the sanitized fold-back** (see
   `skills/dw-demo-base/references/iterate-plugin.md`). A demo-build discovery that is durable
   and vendor-generic gets folded *up* into the right foundational skill, stripped of all
   demo/customer specifics first. A discovery that needs the customer's name to make sense is
   demo-specific and is **not** folded — it stays in that demo's own notes.

When adding or editing a skill, first decide which category it is; that decides whether
demo/customer content and demo-skill links are even allowed in it.

### Naming

All skills use the `dw-<domain>-<topic>` prefix — folder name, `name:` frontmatter, and the
marketplace `skills` path basename must all match exactly. (Only the role *bundles* in
`marketplace.json` carry the `dynamicweb-` prefix.) Skill files must be saved as UTF-8
**without a BOM** — a leading BOM defeats some frontmatter parsers and the validator rejects it.

### SKILL.md frontmatter

```yaml
---
name: dw-<domain>-<topic>
type: <knowledge | flow>
group: <area — pim, search, render, setup, extend, integration, commerce, users, swift, headless, content, data, source, demo>
description: <one to three sentences. First sentence states what the skill does. Remaining sentences list the exact trigger phrases / conditions that activate it.>
---
```

`type` is `knowledge` for reference-style platform skills and `flow` for skills that drive a
multi-step process (the setup installers and the demo chain). `group` is the skill's area from
the naming taxonomy (see `dynamicweb-skills-structure.md`) and matches the `<domain>` segment
of the name.

The `description` field is the activation signal — it is matched against the user's request at runtime. Write it in the third person using this shape:

1. **First sentence** — what the skill does.
2. **`Triggers:`** — the phrases / conditions / error symptoms that should activate it.
3. **`Non-triggers:`** — adjacent cases that belong to a sibling skill, each routed with `-> dw-<other-skill>`.

Example (`dw-pim-completeness`):

```
description: Configure Dynamicweb 10 product completeness — completion rules, completeness scoring, and query-driven automatic workflows. Triggers: create completion rules, assign rules to data models or product groups, understand completeness scoring, set up completeness-driven query movement. Non-triggers: manual workflow states -> dw-pim-workflow; the Data Model schema -> dw-pim-modelling.
```

Demo skills additionally carry a `Use AFTER dw-demo-base` marker (see below). Keep
descriptions on a single line, and within the **1024-character** frontmatter cap — parsers
truncate past it, silently dropping trigger coverage (the validator errors over the cap).

### Writing the instruction body

Phrase instructions positively — state what to do, not just what to avoid. A model follows
"DO A" more reliably than a bare "don't do B" (the prohibition raises B's salience and leaves
the target underspecified). Keep a contrast only when B is the model's natural pull and a
predictable failure mode, and prefer the paired form ("serialize with the DW serializer, not a
raw XML export") over a bare "don't". Few-shot bad→good example pairs are exempt. The full
rule, with the test for when contrast earns its place, lives in
`skills/dw-demo-base/references/iterate-plugin.md` ("Phrase instructions positively").

### Length budgets and references

Keep a **SKILL.md body under ~500 lines** — past that it is doing reference work, so split the
overflow into `references/<topic>.md` and link to it (the validator warns over 500). A SKILL.md
should read as a nav layer over its references, not a manual.

Any `references/` file over **100 lines** gets a **top-of-file table of contents** — a
`## Contents` block linking to its sections. It survives the partial-preview reads Claude does
when reaching a reference through a link, and gives the model a map of the file (the validator
warns when it is missing). Keep references one level deep from SKILL.md.

### Encoding

Author every markdown file as **UTF-8 without a BOM** and free of **double-encoded UTF-8
(mojibake)** — the `â€"`/`Â§` corruption you get when text is pasted from a mis-decoded source
(a common fold-back hazard). The validator errors on both. If a paste looks corrupted, repair it
with `ftfy.fix_encoding` before committing rather than hand-editing character by character.

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
relative link in `SKILL.md`/`references` resolves; that each `description` is within the
1024-char cap; and that no markdown file begins with a UTF-8 BOM or contains double-encoded UTF-8
(mojibake). It warns (without failing) when a description lacks a trigger signal, a SKILL.md body
runs past 500 lines, or a reference over 100 lines lacks a table of contents.

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

## Contributing: every change lands via PR

All changes reach the integration branch through a pull request — **no direct pushes** to
`v2` (the active integration branch) or `main`. This is the standing way of working; it
replaces the earlier "push directly, no PRs" rule.

**One atomic logical change per PR.** A PR is a single, self-contained, reviewable unit: a
fold-back of one learning, one new skill, one bundle re-balance, one doc fix. Don't bundle
unrelated edits. If a change touches a skill's content, its `marketplace.json` registration,
the README table, and the CHANGELOG, those all belong in the *same* PR — they are one logical
change — but a second, unrelated skill edit does not.

Workflow:

1. Branch off the current integration branch (`v2` until it merges to `main`, then `main`):
   `git checkout -b <type>/<short-topic>` (`type` ∈ `feat` / `fix` / `docs` / `chore`).
2. Make the atomic change. Run `python3 scripts/validate-skills.py` — it must exit 0.
3. Update `CHANGELOG.md` and bump `marketplace.json`'s `metadata.version` (semver) in the
   same commit when skills are added/renamed or contracts change.
4. Commit (see "Commits" below), push the branch, and open a PR targeting the integration
   branch with `gh pr create`.
5. Merge after review. **Squash-merge** so each PR is one atomic commit on the integration
   branch. Tag a release (`v<X.Y.Z>`) on the integration branch only when cutting a version,
   not per PR.

## Commits

Each PR squash-merges to one atomic commit, so the **PR title is the commit subject** — make
it name what changed and why. Do not add `Co-Authored-By` lines or any other self-attribution
to commit messages or PR bodies.
