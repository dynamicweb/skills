# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude plugin marketplace of skills for Dynamicweb 10, bundled by role. The repo is
markdown and configuration files — no build system and no runtime code. The one piece of
tooling is `scripts/validate-skills.py`, a structural linter; run it before every commit.

**Authoring or editing a skill?** The frontmatter contract, naming, length budgets, body voice,
validation, and the PR workflow live in the `dw-skill-authoring` skill
(`.claude/skills/dw-skill-authoring/SKILL.md`). This file carries only what governs *every*
edit regardless of what you are doing.

## Key files

- `.claude-plugin/marketplace.json` — the plugin registry. Defines 6 role bundles (`dynamicweb-setup`, `dynamicweb-frontend`, `dynamicweb-commerce`, `dynamicweb-backend`, `dynamicweb-developer`, `dynamicweb-presales`). Each entry uses `"source": "./"` + `"strict": false` and curates the bundle via a `skills` array of paths into `skills/`. The top level requires `name` (string), `owner` (object), and `plugins` (array); `description`/`version` live under `metadata`.
- `skills/<skill-name>/SKILL.md` — the skill definition. YAML frontmatter (`name`, `description`) plus the instruction body.
- `skills/<skill-name>/references/*.md` — reference material loaded by the skill at runtime.
- `skills/<skill-name>/assets/` — template files the skill scaffolds onto disk.
- `skills/<skill-name>/scripts/` — PowerShell scripts invoked by the skill.

## The one-way boundary (foundational vs demo)

Every skill is one of two kinds, and the boundary is load-bearing:

- **Foundational skills** — every `dw-<domain>-<topic>` skill that is *not* a demo skill
  (setup, render, content, pim, commerce, search, users, extend, integration, data-access,
  source-explorer). Vendor-generic, reusable Dynamicweb 10 platform knowledge. They ship in the
  role bundles that implementers and developers install.
- **Demo skills** — the presales chain: `dw-demo-base` and its sisters (`dw-demo-pim`,
  `dw-demo-swift`, `dw-demo-erp`) plus the `dw-integration-bc` connector demo. These scaffold
  live presales demos and carry the demo-only guardrails (the customisations ledger, the
  read-only `customer-context/` contract, the maintainer fold-back).

The dependency direction is **one-way and enforced**:

1. **Foundational skills contain zero demo- or customer-specific content** — no engagement
   slugs, customer/brand/personal names, session-relative time markers, or presales-scaffolding
   assumptions. They read as if no demo ever existed.
2. **Foundational skills never reference or depend on a demo skill.** Demo skills build on
   foundational ones; never the reverse. A `references/` link or routing row from a foundational
   skill into `dw-demo-*` is a boundary violation.
3. **Learnings flow demo → foundational only via the sanitized fold-back** (see
   `skills/dw-demo-base/references/iterate-plugin.md`). A demo-build discovery that is durable
   and vendor-generic is folded *up* into the right foundational skill, stripped of all
   demo/customer specifics first. A discovery that needs the customer's name to make sense is
   demo-specific and stays in that demo's own notes.

Decide which category a file is in before editing it; that decides whether demo/customer content
and demo-skill links are allowed there at all.

## Encoding

Markdown here is authored as **UTF-8 without a BOM** and free of **double-encoded UTF-8
(mojibake)** — the `â€"`/`Â§` corruption you get when text is pasted from a mis-decoded source, a
recurring fold-back hazard. A leading BOM defeats some frontmatter parsers, so the skill silently
fails to load. The validator errors on both.

## Contributing: every change lands via PR

No direct pushes to `v2` (the active integration branch) or `main` — everything lands through a
pull request, **one atomic logical change per PR**, squash-merged. Record notable changes in
`CHANGELOG.md` and bump `marketplace.json`'s `metadata.version` accordingly. The PR title becomes
the commit subject. Do not add `Co-Authored-By` lines or any other self-attribution to commit
messages or PR bodies.

Full branch/validate/version/PR sequence: `dw-skill-authoring` ("The PR workflow"). Folding a
demo-build learning back into a skill has its own workflow with sanitization gates:
`skills/dw-demo-base/references/iterate-plugin.md`.
