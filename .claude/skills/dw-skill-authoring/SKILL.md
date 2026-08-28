---
name: dw-skill-authoring
description: Author, edit, and register skills in this repository — the frontmatter contract, naming, area taxonomy, length budgets, body voice, validation, manifest regeneration, and the PR workflow. Triggers: add a new skill, edit or restructure an existing SKILL.md, write or split a references/ file, register a skill in a bundle, fix a validator warning, manifest drift in CI, prepare a skills-repo PR. Non-triggers: folding a demo-build learning back into a skill -> skills/dw-demo-foldback/SKILL.md; consuming a skill to build a Dynamicweb solution -> the dw-* skills themselves.
---

# Authoring skills in this repo

Maintainer procedure for the `dynamicweb/skills` marketplace. The repo overview and the one
rule that governs every edit — the one-way foundational/demo boundary — live in
[`../../../CLAUDE.md`](../../../CLAUDE.md); read that first, then this for the mechanics.

## Contents

- [Decide the category first](#decide-the-category-first)
- [Naming](#naming)
- [Area taxonomy](#area-taxonomy)
- [SKILL.md frontmatter](#skillmd-frontmatter)
- [MCP dependence (`mcp:` field)](#mcp-dependence-mcp-field)
- [Writing the instruction body](#writing-the-instruction-body)
- [Length budgets and references](#length-budgets-and-references)
- [Shipping scripts](#shipping-scripts)
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
[`dw-demo-foldback`](../../../skills/dw-demo-foldback/SKILL.md).

## Naming

All skills use the `dw-<domain>-<topic>` prefix — folder name, `name:` frontmatter, and the
marketplace `skills` path basename all match exactly. (Only the role *bundles* in
`marketplace.json` carry the `dynamicweb-` prefix.) `<domain>` is an area from the taxonomy
below.

## Area taxonomy

The structure mirrors how DW10 organizes itself, so a skill's name predicts where its knowledge
lives in the docs. Three documentation pillars (the developer journey): **Setup** (install, CLI,
config, upgrade) → **Implementation** (Content, Products/PIM, Commerce on the rendering engine)
→ **Extending** (C# API, providers, AddIns, scheduled tasks). Four implementation directions:
Swift, Core, From Scratch, Headless (`/dwapi/`).

| Area | Pillar | Scope |
|---|---|---|
| `setup` | Setup | Bootstrap a solution, dev environment, configuration, upgrades |
| `render` | Implementation | Template hierarchy, Razor patterns, ViewModels, TemplateTags |
| `swift` | Implementation | Building on the Swift storefront |
| `headless` | Implementation | `/dwapi/` delivery API, decoupled frontends |
| `content` | Implementation | Pages, paragraphs, item types, content modelling, assets |
| `pim` | Implementation | Modelling, variants/BOM, completeness, workflow, localization |
| `commerce` | Implementation | Catalog, orders/checkout/cart, prices/assortments, B2B |
| `search` | Implementation | Indexes, queries, repositories, BuildIndex |
| `users` | Implementation | Users, groups, the Permission entity store |
| `extend` | Extending | Custom backend code, subscribers, scheduled tasks, MCP tools |
| `integration` | Extending | Source/target providers, ERP, BC connector |
| `data` | cross-cutting | Data-access surface priority (API > SQL), cache invalidation |
| `source` | cross-cutting | Navigating the Dynamicweb platform source and documentation |
| `demo` | Presales | The presales demo chain; flow skills with demo-only guardrails |

## SKILL.md frontmatter

```yaml
---
name: dw-<domain>-<topic>
type: <knowledge | flow>
group: <area — pim, search, render, setup, extend, integration, commerce, users, swift, headless, content, data, source, demo>
mcp: <required | optional | none>
description: <one to three sentences. First sentence states what the skill does. Remaining sentences list the exact trigger phrases / conditions that activate it.>
---
```

`type` is `knowledge` for reference-style platform skills and `flow` for skills that drive a
multi-step process (the setup installers and the demo chain). `group` is the skill's area from
the taxonomy above and matches the `<domain>` segment of the name. `mcp` declares the skill's
MCP dependence — see the next section.

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

## MCP dependence (`mcp:` field)

This repo is consumed both by harnesses with a live Dynamicweb MCP connection (Dynamo) and by
plain Claude Code installs that may have none. Every skill declares which world it lives in —
the field is orthogonal to `type`/`group` and flows through to `manifest.json` so consumers
can filter on it:

- **`mcp: required`** — the skill's steps *are* MCP tool calls; it cannot run without the
  server (the demo chain, tool-driven flows like `dw-pim-migrate-dw9`, `dw-swift-page-design`).
  The body must open with a **`## MCP preflight`** section: verify the tools are available,
  and stop — never substitute direct SQL, file edits, or guessed HTTP calls — when they are not.
- **`mcp: optional`** — the knowledge stands alone; MCP tools are the preferred way to apply
  it (most `knowledge` skills that name tools, e.g. `dw-pim-modelling`, `dw-search-indexing`).
  The body must carry a **`## Without MCP`** section stating the standalone path (advisory
  mode, produce payloads/config for the user to apply).
- **`mcp: none`** — pure platform knowledge or an offline flow (`dw-render-*`, `dw-setup-*`,
  `dw-extend-*`, `dw-source-explorer`). No marker section; the skill must read the same
  whether or not an MCP server exists. Note `dw-extend-mcp-tools` is `none`: it teaches
  *writing* MCP tools in C#, which needs no live connection.

The validator enforces the pair: the field must be present and valid, `required` needs its
`## MCP preflight` section, `optional` needs `## Without MCP`, and a marker section that
contradicts the declared level is an error. Keep the marker level in mind on the demo
boundary too — demo skills are all `required`, and a foundational skill never becomes
`required` just to lean on demo scaffolding. The MCP dependence is declared in frontmatter
and body markers, never appended to the `description` — trigger budget stays trigger budget.

## Writing the instruction body

**Phrase instructions positively — say what to do, not just what to avoid.** A model follows
"DO A" more reliably than a bare "don't do B": the prohibition raises B's salience and leaves
the target underspecified. Keep a contrast only when B is the model's natural pull *and* a
predictable failure mode, and prefer the paired form ("serialize with the DW serializer, not a
raw XML export") over a bare "don't". Few-shot bad→good example pairs are exempt. The full rule,
with the test for when contrast earns its place, is in
[`fold-back-workflow.md`](../../../skills/dw-demo-foldback/references/fold-back-workflow.md)
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

## Shipping scripts

A skill may ship runnable code under `skills/<skill>/scripts/`. The layout follows the Agent
Skills specification, which names exactly three optional folders: `scripts/` for executable
code, `references/` for documentation, `assets/` for copy-in templates. Use those names and no
others. A script earns its place when the same operation is re-implemented across engagements,
or already sits in a reference as a fenced block a model must retype correctly every time (the
"encode in a script" corollary above). A one-off recipe stays prose.

**PowerShell 7, single tier.** Every script targets PowerShell 7 and starts with
`#Requires -Version 7.0`, so under Windows PowerShell 5.1 it stops with a one-line message
before the body is parsed. PowerShell 7 is a machine prerequisite, installed by the setup
preflight (`dw-demo-base/references/setup-checks.md`) alongside `git`, `gh` and `node`; a script
never checks or branches on the version itself. Invoke scripts as `pwsh -NoProfile -File`.

**File contract** (one file, `<Verb-Noun>.ps1` or `<Name>.psm1`, approved verbs):

- Comment-based help: `.SYNOPSIS` opens with `READ-ONLY.` or `WRITES: <what>.`;
  `.DESCRIPTION` names the owning reference and the traps the script encodes; one `.PARAMETER`
  per parameter; at least one `.EXAMPLE`.
- `[CmdletBinding(SupportsShouldProcess)]`, an explicit `param()` block,
  `$ErrorActionPreference = 'Stop'`, exit code 0 on success and 1 on failure, error messages
  that say what to fix, no unexplained constants. A write whose blast radius exceeds one row
  runs as `-WhatIf` by default and needs `-Apply`.
- Connection discovery in this order: explicit parameter, then `$env:DW_BASE_URL` /
  `$env:DW_API_TOKEN` / `$env:DW_MCP_TOKEN` / `$env:DW_SQL_CONNECTION`, then the port from
  `Dynamicweb.Host.Suite/Properties/launchSettings.json`, then fail with the one-liner that
  fixes it. No default port, host, path or token anywhere. Secrets come from `$env:` only and
  are masked in every log line.
- Shared code lives in one module, `dw-data-access/scripts/Dw.Api.psm1`, imported
  `$PSScriptRoot`-relative and followed by `Assert-DwConnection`. `dw-setup-install` scripts
  stay self-contained: they run before a host or token exists, in bundles that do not ship
  `dw-data-access`.
- UTF-8 without BOM, free of mojibake; a detector builds its marker strings from code points
  (`[char]0xFFFD`), never from literals.

**Wiring in SKILL.md.** Declare `compatibility: Requires PowerShell 7.x` in the frontmatter of
every skill that ships a script. Add a `## Scripts (scripts/)` table, one row per file,
`| Script | Reads / writes | What it does |`, with a markdown link `[Name.ps1](scripts/Name.ps1)`
so the validator proves the file exists. Every invocation is a fenced
`pwsh -NoProfile -File scripts/Name.ps1 ...` line, with forward slashes, that says whether to
*run* the script or *see* it as reference. The owning reference keeps the rule and the why and
links the script for the how (one lesson, one home).

A script import into another skill's `scripts/` is a hard dependency for bundle closure, the
same as a link into its `references/`. The machine-checkable half of this contract (help block,
`#Requires`, import resolution, secrets, environment literals, encoding, unlinked scripts) is
the validator's job; review enforces the rest. Lifting a script out of a demo build has its own
gates in [`fold-back-workflow.md`](../../../skills/dw-demo-foldback/references/fold-back-workflow.md)
("Step 1c").

## Adding a new skill

1. Create `skills/dw-<domain>-<topic>/SKILL.md` with matching `name:` frontmatter (UTF-8, no BOM).
2. Add `references/`, `assets/`, or `scripts/` subdirectories as needed.
3. Register the skill path in the relevant bundle(s) in `.claude-plugin/marketplace.json`, as a
   `"./skills/dw-<domain>-<topic>"` entry in that bundle's `skills` array.
4. Add an entry to the README skills table and skills section.
5. Run `python3 scripts/validate-skills.py` and fix any errors.
6. Regenerate `manifest.json` with `node scripts/build-manifest.mjs` — Dynamo (the Dynamicweb
   MCP server) fetches it directly, and CI fails the build when it drifts from the skills'
   frontmatter. Any edit to a `description` needs this step too.

## Updating marketplace.json

Skills can appear in more than one bundle — list the same `"./skills/..."` path in each bundle's
`skills` array (no copying or symlinks; sharing is what the `source: "./"` + `strict: false`
pattern is for). Each bundle entry keeps its `source` and `strict: false`. Paths under `skills`
resolve relative to the source root and start with `./`. Bump the `version` under `metadata`
(semver) when skills are added or renamed.

A bundle must be **closed**: every skill it ships may only hard-depend (link into `references/`
or `assets/`, or import from `scripts/`) on skills the same bundle ships. The validator errors on a link that escapes the
bundle — either add the target skill to the bundle or route through its SKILL.md by name.

## Demo skills dependency order

The `dynamicweb-presales` bundle has a hard dependency chain — `dw-demo-base` must run before any
sister skill (`dw-demo-pim`, `dw-demo-swift`, `dw-demo-headless`, `dw-demo-hosted`,
`dw-demo-erp`, `dw-demo-foldback`, `dw-integration-bc`). Sister skill descriptions carry a
"Use AFTER dw-demo-base" marker; preserve it on any edit.

## Validation

`scripts/validate-skills.py` (Python 3, no dependencies) is the structural linter. It **errors**
when `marketplace.json` fails to parse or lacks its top-level schema (`name`, `owner`,
`plugins`), a plugin entry has no `source`, a referenced skill path is missing, a skill's folder
name / `name:` frontmatter / marketplace path disagree, frontmatter fails a strict YAML parse, a
relative link does not resolve, a `description` exceeds 1024 chars, the `mcp` field is missing
or invalid or its body marker section (`## MCP preflight` / `## Without MCP`) does not match
the declared level, a markdown file carries a
UTF-8 BOM or mojibake, or a bundled skill hard-depends on a skill the bundle does not ship. It
**warns** when a description lacks a trigger signal, a SKILL.md body runs past 500 lines or
16,000 characters, or a reference over 100 lines lacks a table of contents.

```powershell
python3 scripts/validate-skills.py       # exit 0 before every commit
node scripts/build-manifest.mjs --check  # manifest.json in sync with frontmatter (CI runs this)
claude plugin validate ./                # deeper check against Claude Code's own plugin schema
```

CI runs the validator and the manifest drift check on every push and PR
(`.github/workflows/manifest-check.yml`).

## The PR workflow

Every change reaches `main` through a pull request — no direct pushes. **One atomic logical
change per PR**: a fold-back of one learning, one new skill, one bundle re-balance, one doc fix. A
change that touches a skill's content, its `marketplace.json` registration, the README table, the
manifest, and the CHANGELOG is still one logical change and belongs in one PR; a second, unrelated
skill edit does not.

1. Branch off `main`: `git checkout -b <type>/<short-topic>`
   (`type` ∈ `feat` / `fix` / `docs` / `chore`).
2. Make the atomic change. Run `python3 scripts/validate-skills.py` — it must exit 0 — and
   `node scripts/build-manifest.mjs`.
3. Update `CHANGELOG.md` and bump `marketplace.json`'s `metadata.version` (semver) in the same
   commit when skills are added/renamed or contracts change.
4. Commit, push the branch, open the PR against `main` with `gh pr create`.
5. Squash-merge after review, so each PR is one atomic commit. Tag a release (`v<X.Y.Z>`) only
   when cutting a version, not per PR.

The **PR title is the commit subject** — name what changed and why. No `Co-Authored-By` lines or
other self-attribution in commit messages or PR bodies.

For folding a demo-build learning back into a skill, the routing, sanitization, and hygiene gates
are owned by
[`dw-demo-foldback`](../../../skills/dw-demo-foldback/SKILL.md) — use that skill, not this
section.
