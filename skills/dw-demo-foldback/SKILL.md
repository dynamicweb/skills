---
name: dw-demo-foldback
type: flow
group: demo
mcp: none
dynamo: false
description: 'Fold demo learnings into skills as sanitized PRs. Triggers: fold back a learning, save a demo fix to the plugin. General skill authoring -> dw-skill-authoring. Use AFTER dw-demo-base.'
---

# Folding a demo-build learning back into the skills repo

When a demo build surfaces a non-trivial learning — a workaround, a gotcha, a corrected surface
order, a missing prereq — this is how it becomes durable knowledge instead of a note that rots.

Fold it back **while the demo's context is still in the conversation**, not from notes a week
later. The full workflow — every step, gate, and recovery path — is owned by
[references/fold-back-workflow.md](references/fold-back-workflow.md).

**Use AFTER [`dw-demo-base`](../dw-demo-base/SKILL.md).** Write access to the `dynamicweb/skills`
repo makes this a maintainer flow; without it the workflow is identical and lands as an outside PR.

## The shape of it

1. **Route the learning** — foundational skill or demo skill? This decides everything downstream,
   because the two categories have different content rules.
   **Platform knowledge only:** a lesson about how Dynamicweb behaves folds into the skill that
   owns the topic. A lesson about how another system behaves (an ERP's API, a tunnel, a hosting
   panel) does not fold into this repo: reduce it to the one line Dynamicweb needs from that
   system, or leave it in the demo's own notes. The rule is "Scope: the platform, not the systems
   around it" in the repo's `CLAUDE.md`.
2. **Sanitize before drafting** — strip customer/engagement specifics, personal names, and
   session-relative time markers. A learning that needs the customer's name to make sense is
   demo-specific and is not folded up.
3. **Pass the content-hygiene gate** — rewrite in place rather than appending; retire the old
   recipe rather than leaving both loadable; keep dates in `git log`, not in the body.
4. **Edit, validate, bump, PR** — `python3 scripts/validate-skills.py` exits 0, `CHANGELOG.md` and
   `metadata.version` move in the same commit, one atomic change on a branch, squash-merged.

## A script written during a build is proposed as a recipe

A generic one-off script a build needed (it creates, updates or checks platform objects from the
customer's data, and nothing in it needs the customer's name) is not folded back as a script and
not left in the demo folder. It is proposed as a recipe in
[`dw-demo-ledger`](../dw-demo-ledger/SKILL.md), so the next build runs it through
`Invoke-DwRecipeSet.ps1` and an MCP-only agent can follow it by hand:

- **A function no recipe covers** (`Find-DwRecipe.ps1 -Function <id>` says "no recipe"): a new
  recipe at `assets/recipes/<area>/<id>.json`, with its input section added to the input schema.
- **A gap in an existing recipe** (a step the recipe leaves planned or does not have, such as an
  assortment grant the buyer needed): a step or a binding on that recipe.
- **A host primitive** (an index build, an assortment build, a flush, a recycle): not a recipe.
  It is a debt of the recipe whose change owes it; on its own it runs as
  `Invoke-DwRecipeSet.ps1 -Only <id> -PayDebts -Apply`.

A recipe must meet this checklist before it is proposed (the contract is
[recipes.md](../dw-demo-ledger/references/recipes.md) "Adding or promoting a recipe"):

1. Data only: every call is a named MCP tool or Management API command with its arguments; no
   code, no host, URL, path, credential or customer name (the validator refuses them).
2. Each binding cites the reference that documents its shape, and the shape was measured on a host
   (`tools/list`, then a real call). A step with no MCP or Management API write is `planned` with
   the measured reason, never invented; SQL only reads.
3. Every object is found by a natural key, so a second apply writes nothing; every write is read
   back.
4. `debts` names what a change owes; `dependsOn` names the recipes whose objects it needs.
5. Probes prove behaviour (what a visitor or a buyer is served), not only what is stored.
6. Proven before it is merged: verify (WOULD-CREATE), apply, verify (UNCHANGED, probes pass),
   apply again (nothing written, no debt run) and an `-McpOnly` run, recorded in `provenOn`, with
   the platform facts it ran into in `traps`.
7. `python scripts/validate-skills.py`, `python scripts/validate_recipes.py --write-index` (the
   recipe index) and the recipe Pester suites are green.

## The rule that makes it safe

**Learnings flow demo → foundational only, and only sanitized.** A foundational skill must read as
if no demo ever existed: no engagement slugs, no customer or personal names, no
presales-scaffolding assumptions, and no link back into a `dw-demo-*` skill. Demo skills may build
on foundational ones; never the reverse.

That one-way boundary is what keeps the foundational corpus reusable, and it is the thing this
workflow exists to enforce — a fold-back that carries customer specifics upward is the failure
mode, not a shortcut.

## Before you start

The workflow needs the absolute path to a local clone of `dynamicweb/skills`. It resolves from
`$env:DYNAMICWEB_SKILLS_REPO`, then a user-scope `reference` memory, then by asking — see
[references/fold-back-workflow.md](references/fold-back-workflow.md) "Step 0".
