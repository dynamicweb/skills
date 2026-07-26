---
name: dw-skill-authoring
description: Author, edit, and register skills in this repository — the frontmatter contract, naming, length budgets, body voice, validation, and the PR workflow. Triggers: add a new skill, edit or restructure an existing SKILL.md, write or split a references/ file, register a skill in a bundle, fix a validator warning, prepare a skills-repo PR. Non-triggers: folding a demo-build learning back into a skill -> skills/dw-demo-base/references/iterate-plugin.md; consuming a skill to build a Dynamicweb solution -> the dw-* skills themselves.
---

# Authoring skills in this repo

Maintainer procedure for the `dynamicweb/skills` marketplace. The repo overview and the one
rule that governs every edit — the one-way foundational/demo boundary — live in
[`../../../CLAUDE.md`](../../../CLAUDE.md); read that first, then this for the mechanics.

## Contents

- [Decide the category first](#decide-the-category-first)
- [Naming](#naming)
- [SKILL.md frontmatter](#skillmd-frontmatter)
- [Writing the instruction body](#writing-the-instruction-body)
- [Length budgets and references](#length-budgets-and-references)
- [Adding a new skill](#adding-a-new-skill)
- [Updating marketplace.json](#updating-marketplacejson)
- [Demo skills dependency order](#demo-skills-dependency-order)
- [Validation](#validation)
- [The PR workflow](#the-pr-workflow)

## Decide the category first

Every skill is either **foundational** (vendor-generic platform knowledge — setup, render,
content, pim, commerce, search, users, extend, integration, data-access, source-explorer) or
**demo** (the presales chain: `dw-demo-base` and its sisters, plus `dw-integration-bc`).

Settle which one before writing a line: the category decides whether demo/customer content and
links into `dw-demo-*` are allowed in the file at all. The rule and its three clauses are in
[`../../../CLAUDE.md`](../../../CLAUDE.md) ("The one-way boundary"). Learnings travel demo →
foundational only, sanitized, through
[`skills/dw-demo-base/references/iterate-plugin.md`](../../../skills/dw-demo-base/references/iterate-plugin.md).

## Naming

All skills use the `dw-<domain>-<topic>` prefix — folder name, `name:` frontmatter, and the
marketplace `skills` path basename all match exactly. (Only the role *bundles* in
`marketplace.json` carry the `dynamicweb-` prefix.)

## SKILL.md frontmatter

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

The `description` is the **activation signal** — it is matched against the user's request at
runtime, and it is the only part of the skill the model sees before deciding to load it. Treat
it as the skill's interface, not its summary. Third person, this shape:

1. **First sentence** — what the skill does.
2. **`Triggers:`** — the phrases / conditions / error symptoms that should activate it.
3. **`Non-triggers:`** — adjacent cases that belong to a sibling skill, each routed with
   `-> dw-<other-skill>`.

Example (`dw-pim-completeness`):

```
description: Configure Dynamicweb 10 product completeness — completion rules, completeness scoring, and query-driven automatic workflows. Triggers: create completion rules, assign rules to data models or product groups, understand completeness scoring, set up completeness-driven query movement. Non-triggers: manual workflow states -> dw-pim-workflow; the Data Model schema -> dw-pim-modelling.
```

Demo skills additionally carry a `Use AFTER dw-demo-base` marker. Keep descriptions on a single
line and within the **1024-character** cap — parsers truncate past it, silently dropping trigger
coverage (the validator errors over the cap). A description crowding the cap is a signal the
skill owns too many unrelated routes; split the skill rather than compressing the triggers.

## Writing the instruction body

**Phrase instructions positively — say what to do, not just what to avoid.** A model follows
"DO A" more reliably than a bare "don't do B": the prohibition raises B's salience and leaves
the target underspecified. Keep a contrast only when B is the model's natural pull *and* a
predictable failure mode, and prefer the paired form ("serialize with the DW serializer, not a
raw XML export") over a bare "don't". Few-shot bad→good example pairs are exempt. The full rule,
with the test for when contrast earns its place, is in
[`iterate-plugin.md`](../../../skills/dw-demo-base/references/iterate-plugin.md)
("Phrase instructions positively").

**Spend hard prohibitions where a violation is unrecoverable, not on procedure.** A capable
model handles a stated goal and its context; what it cannot recover from is a write that left
the machine — publishing, customer data, a destructive DB or file operation, a bypassed gate.
Those get the explicit rule. Ordering, tidiness, and style preferences get the target state and
the reason, and the model's judgment does the rest.

**Author for the least capable model the skill is expected to run on — once.** These skills ship
to whoever installs the bundle, on whatever model they happen to be running, so there are no
per-tier variants of a SKILL.md or a reference; a forked recipe drifts the moment one copy is
folded back and the other is not. Choosing a cheaper or stronger model for a given step is the
*orchestrator's* dial, not the skill's — see
[`orchestrator.md`](../../../skills/dw-demo-base/references/orchestrator.md) ("Model tier"). The
corollary shapes what you write here: **what a cheaper model cannot be trusted to remember,
encode in a script or a detector, not in a longer prose rule.** A gate written as a validator
holds at every tier; the same gate written as three more paragraphs holds only at the top one.

**Concrete commands beat prose.** Include the exact `dotnet`, `git`, `Invoke-RestMethod`,
`sqlcmd`, or PowerShell snippet that worked — a runnable line instructs more precisely than a
paragraph describing it.

**Keep dates out of the body.** The date lives in `git log`. No "today", no "(verified <date>)".
Provenance citations name roles, never individuals — "per the Dynamicweb vendor architect".

## Length budgets and references

Keep a **SKILL.md body under ~500 lines *and* under ~16,000 characters** — past either it is
doing reference work, so split the overflow into `references/<topic>.md` and link to it (the
validator warns over both). A SKILL.md should read as a nav layer over its references, not a
manual.

The character budget is the one that matters, and it exists because the line budget is gameable:
a body of 300 long table rows costs more context than 490 short ones, so a SKILL.md can sit
inside the line budget while injecting three times the tokens. ~16,000 chars is roughly 4k
tokens — the ceiling for something whose whole job is to route.

Any `references/` file over **100 lines** gets a **top-of-file table of contents** — a
`## Contents` block linking to its sections. It survives the partial-preview reads Claude does
when reaching a reference through a link, and gives the model a map of the file (the validator
warns when it is missing). Keep references one level deep from SKILL.md.

**Encoding**: author every markdown file as UTF-8 without a BOM and free of double-encoded UTF-8
(mojibake). The validator errors on both — see CLAUDE.md for why. If a paste looks corrupted,
repair it with `ftfy.fix_encoding` rather than hand-editing character by character.

## Adding a new skill

1. Create `skills/dw-<domain>-<topic>/SKILL.md` with matching `name:` frontmatter (UTF-8, no BOM).
2. Add `references/`, `assets/`, or `scripts/` subdirectories as needed.
3. Register the skill path in the relevant bundle(s) in `.claude-plugin/marketplace.json`, as a
   `"./skills/dw-<domain>-<topic>"` entry in that bundle's `skills` array.
4. Add an entry to the README skills table and skills section.
5. Run `python3 scripts/validate-skills.py` and fix any errors before committing.

## Updating marketplace.json

Skills can appear in more than one bundle — list the same `"./skills/..."` path in each bundle's
`skills` array (no copying or symlinks; sharing is what the `source: "./"` + `strict: false`
pattern is for). Each bundle entry keeps its `source` and `strict: false`. Paths under `skills`
resolve relative to the source root and start with `./`. Bump the `version` under `metadata`
(semver) when skills are added or renamed.

## Demo skills dependency order

The `dynamicweb-presales` bundle has a hard dependency chain — `dw-demo-base` must run before any
sister skill (`dw-demo-pim`, `dw-demo-swift`, `dw-demo-erp`, `dw-integration-bc`). Sister skill
descriptions carry a "Use AFTER dw-demo-base" marker; preserve it on any edit.

## Validation

`scripts/validate-skills.py` (Python 3, no dependencies) is the structural linter. It **errors**
when `marketplace.json` fails to parse or lacks its top-level schema (`name`, `owner`,
`plugins`), a plugin entry has no `source`, a referenced skill path is missing, a skill's folder
name / `name:` frontmatter / marketplace path disagree, frontmatter fails a strict YAML parse, a
relative link does not resolve, a `description` exceeds 1024 chars, or a markdown file carries a
UTF-8 BOM or mojibake. It **warns** when a description lacks a trigger signal, a SKILL.md body
runs past 500 lines or 16,000 characters, or a reference over 100 lines lacks a table of contents.

```powershell
python3 scripts/validate-skills.py     # exit 0 before every commit
claude plugin validate ./              # deeper check against Claude Code's own plugin schema
```

To run it at the start of every session so structural breakage surfaces immediately, add this
`SessionStart` hook to `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "python3 \"$CLAUDE_PROJECT_DIR/scripts/validate-skills.py\"" } ] }
    ]
  }
}
```

## The PR workflow

Every change reaches the integration branch through a pull request — no direct pushes to `v2`
(the active integration branch) or `main`. **One atomic logical change per PR**: a fold-back of
one learning, one new skill, one bundle re-balance, one doc fix. A change that touches a skill's
content, its `marketplace.json` registration, the README table, and the CHANGELOG is still one
logical change and belongs in one PR; a second, unrelated skill edit does not.

1. Branch off the integration branch: `git checkout -b <type>/<short-topic>`
   (`type` ∈ `feat` / `fix` / `docs` / `chore`).
2. Make the atomic change. Run `python3 scripts/validate-skills.py` — it must exit 0.
3. Update `CHANGELOG.md` and bump `marketplace.json`'s `metadata.version` (semver) in the same
   commit when skills are added/renamed or contracts change.
4. Commit, push the branch, open the PR against the integration branch with `gh pr create`.
5. Squash-merge after review, so each PR is one atomic commit. Tag a release (`v<X.Y.Z>`) only
   when cutting a version, not per PR.

The **PR title is the commit subject** — name what changed and why. No `Co-Authored-By` lines or
other self-attribution in commit messages or PR bodies.

For folding a demo-build learning back into a skill, the routing, sanitization, and hygiene gates
are owned by
[`iterate-plugin.md`](../../../skills/dw-demo-base/references/iterate-plugin.md) — use that
workflow, not this section.
