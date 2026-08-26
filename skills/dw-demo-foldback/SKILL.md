---
name: dw-demo-foldback
type: flow
group: demo
description: 'Fold a demo-build learning back into the dynamicweb/skills repo as a sanitized, atomic pull request. Triggers: "fold this into the skill", "fold this learning back", "save this back to the plugin", "update the plugin from this demo", "publish this update", "this is worth keeping — add it to the skill". Use AFTER dw-demo-base, while the demo''s context is still in the conversation — the workflow routes the learning foundational-vs-demo, strips customer/demo specifics, validates, bumps the version, and opens the PR. Non-triggers: authoring or restructuring a skill from scratch -> the repo''s own dw-skill-authoring skill; recording a customisation in the demo ledger -> dw-demo-base references/customisations.md.'
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
2. **Sanitize before drafting** — strip customer/engagement specifics, personal names, and
   session-relative time markers. A learning that needs the customer's name to make sense is
   demo-specific and is not folded up.
3. **Pass the content-hygiene gate** — rewrite in place rather than appending; retire the old
   recipe rather than leaving both loadable; keep dates in `git log`, not in the body.
4. **Edit, validate, bump, PR** — `python3 scripts/validate-skills.py` exits 0, `CHANGELOG.md` and
   `metadata.version` move in the same commit, one atomic change on a branch, squash-merged.

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
