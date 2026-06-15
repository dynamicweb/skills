# Customer-context read-only contract

The `<demo>\customer-context\` directory holds intro-call materials, customer-supplied artefacts, transcripts, and reference documents that must **NEVER** be modified by demo-build automation. Pre-flight check on any path containing `customer-context\` (case-insensitive) is a **HARD ABORT** -- no Approve+log branch, no override. Customer-context writes are never necessary; if a transformation is needed, write the transformed output to `<demo>\notes\` or `<demo>\extracts\` instead.

This file is the long-form contract for **the customer-context read-only contract**. The orchestrator's summary -- including the canonical abort message -- lives in `SKILL.md` "Two guarded-writes"; see also the sister contract `references/customisations.md` (the customisations-ledger preflight) which shares the *same mental model* -- write-time preflight on a path glob -- with three branches instead of one.

## 1. Why this rule exists

Customer trust is built from day one. The customer-context folder holds the artefacts that the customer (or sales prep) handed over: intro-call notes, project-alignment summaries, sample data files, email threads. If any of those files appears in `git status` as "modified" after a demo build, the customer's mental model of "they got our material and modified it without asking" is the trust-killing signal -- bigger than any technical bug.

The detection signature is `git status customer-context/` showing changes after a demo build. Prevention is the hard-abort preflight below.

## 2. Customer-context contents (read by skill, never written)

Skills are allowed to **READ** customer-context (e.g., to understand the customer's terminology, their data shape, their stated pains). For terminology specifically, the "Speak the customer's words" tactic in `references/demo-tactics.md` turns that read into a `<demo>\notes\wording.md` glossary applied across all demo copy. A typical `<demo>\customer-context\` folder contains a mix of these document types -- the exact filenames are project-specific:

- Intro-call notes / transcript exports (e.g., as a `.md` or transcript export from a meeting tool)
- Project-alignment decks (e.g., `.pptx` summarising the prospect's stated pains and stack)
- Sample customer-of-customer files (e.g., spreadsheets the customer ships with their accounts -- per-account product portfolios, pricing extracts)
- Email-thread exports (`.msg` / `.eml`) covering the pre-demo conversation
- Any other artefact the customer or sales prep handed over verbatim

Reading these is fine. Writing to ANY of them is the abort condition. **Reading them by-passing strict tools (e.g., binary `Get-Content -AsByteStream`) is also reading; the rule is about writes only.**

## 3. Write-time preflight (mandatory, hard abort)

Before writing any file whose path contains `customer-context\` (case-insensitive), abort with the canonical abort message -- it lives in `SKILL.md` "Two guarded-writes" (the customer-context guarded write). Do not paraphrase it from here.

This is a **hard abort**, not an opt-in fix. There is no `Approve+log` branch. (The customisations-ledger preflight has three options because customisations are sometimes necessary; customer-context writes are never necessary.)

## 4. Path-matching rule

Match on the literal substring `customer-context\` (case-insensitive). Both forward-slash (`customer-context/`) and backslash (`customer-context\`) variants are recognised. False positives bias toward over-aborting (e.g., a user-named file like `notes/customer-context-summary.md` matches by contained substring) -- accepted: bias toward over-aborting is the correct safety direction.

Implementation note for executors -- pseudo-code for the preflight check (Claude reads `SKILL.md` and applies this rule before any Write/Edit tool call):

```powershell
# (?i) makes the match case-insensitive; [/\\] accepts both separator styles.
if ($targetPath -match '(?i)customer-context[/\\]') {
  throw "ABORT (customer-context read-only contract): write to customer-context\ folder is forbidden. Suggest <demo>\notes\ or <demo>\extracts\ instead."
}
```

Edge cases the rule deliberately accepts:
- A file at `<demo>\notes\customer-context-summary.md` matches by contained substring -- aborted. The user can rename it to `<demo>\notes\customer-summary.md` to dodge the substring; this is intentional friction (the whole point is to make customer-context-related writes a deliberate decision).
- A file at `<demo>\customer-context-archive\foo.md` matches and is aborted. The user can use `<demo>\extracts\customer-archive\foo.md` instead.
- A file at `<demo>\customer-contextx\foo.md` does NOT match (no separator after the substring). Accepted -- the rule is about the literal folder name.

## 5. Three-place rule communication (skill-composition mitigation)

The rule is communicated in **three** structurally-inescapable places so the convention survives skill composition:

1. `truvio-demo-base/SKILL.md` body -- the "Two guarded-writes" section. This is the skill orchestrator's summary; any agent loading the skill sees it.
2. The per-demo `<demo>\CLAUDE.md` dropped at scaffold time -- so subsequent skills (PIM, Swift, future) inherit the rule via the project's `CLAUDE.md`. This is the cross-skill inheritance mechanism.
3. This file -- long-form rationale + path-matching rule.

A future skill that does not read `SKILL.md` still has `CLAUDE.md` as a fallback. A future tool that ignores `CLAUDE.md` still has the `SKILL.md` body. **Defense in depth via redundancy.**

## 6. Per-demo CLAUDE.md drop at scaffold time

At scaffold time, append the following block to `<demo>\CLAUDE.md` (create the file if it doesn't exist; this complements any project-level `CLAUDE.md` guidance):

```markdown
## Customer-context read-only contract

The `customer-context\` directory in this demo solution is **read-only by skill convention**. Any write to a path containing `customer-context\` is a hard abort. Reading is fine; writing is forbidden. If you need to transform or extract content, write the output to `<demo>\notes\` or `<demo>\extracts\`.

Source: `truvio-demo-base/references/customer-context.md` (the customer-context read-only contract).
```

Recipe to drop the block (idempotent -- append only if the marker line is absent):

```powershell
$claudeMd = Join-Path (Get-Location) "CLAUDE.md"
$marker = "## Customer-context read-only contract"
$existing = if (Test-Path $claudeMd) { Get-Content $claudeMd -Raw } else { "" }
if ($existing -notmatch [regex]::Escape($marker)) {
  $block = @"

$marker

The ``customer-context\`` directory in this demo solution is **read-only by skill convention**. Any write to a path containing ``customer-context\`` is a hard abort. Reading is fine; writing is forbidden. If you need to transform or extract content, write the output to ``<demo>\notes\`` or ``<demo>\extracts\``.

Source: ``truvio-demo-base/references/customer-context.md`` (the customer-context read-only contract).
"@
  Add-Content -Path $claudeMd -Value $block -Encoding UTF8
  Write-Host "Appended customer-context contract to: $claudeMd"
} else {
  Write-Host "CLAUDE.md already contains the customer-context contract; skipped."
}
```

The double-backtick fences in the here-string are because the inner Markdown uses single backticks for inline code; PowerShell's backtick is the escape character, so doubling is required to render a single literal backtick.

## 7. Detection signature for bypass

End-of-phase / end-of-build verification: `git status customer-context/` shows zero changes. Any change indicates a bypass of the read-only contract -- investigate before continuing.

```powershell
# Run from the solution root, end of every phase.
$changes = git status --porcelain "customer-context/"
if ($changes) {
  Write-Host "BYPASS DETECTED: customer-context\ folder has changes:" -ForegroundColor Red
  $changes | ForEach-Object { Write-Host "  $_" }
  Write-Host "Investigate before declaring the phase complete (customer-context read-only contract violation)."
} else {
  Write-Host "OK: customer-context\ folder is unmodified (read-only contract holds)."
}
```

This is a defense-in-depth check: the convention-based preflight assumes Claude reads `SKILL.md` / `CLAUDE.md` and follows the rule. If a future model bypasses the preflight, this audit catches the residue post-hoc -- before it reaches the customer.

## 8. Cross-references

- `SKILL.md` "Two guarded-writes" section names this file and owns the canonical abort message.
- `references/customisations.md` has the *related* preflight pattern with three branches; this file has the *same mental model* with one branch (hard abort).
- Bypass detection: `git status customer-context/` shows changes after a demo build.
- Skill-composition risk (a sister skill loaded without this file): the three-place rule communication + per-demo `CLAUDE.md` drop is the mitigation.
