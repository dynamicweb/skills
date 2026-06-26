# Orchestrators — how a demo build is driven (GSD primary, native floor)

A demo build needs two separable things: **domain knowledge** (what to scaffold, how DW10
behaves, the surface-priority rule, the customer-center playbook) and **sequencing** (which
phase runs when, where the human gate sits, when validation fires). The demo skills in this
repo own the first and carry **none** of the second as an enforced contract. The thing that
sequences the phases, holds the gates, and drives the agents is the **orchestrator**, and it is
swappable.

> **Term.** "Orchestrator" is the swappable component that sequences the build. The skills are
> the **substrate** both orchestrators read. Do not call it a "driver" — that overloads the
> device-driver / browser-driver sense already used in `references/browser-automation.md`.

Two orchestrators are supported, plus the no-orchestrator floor:

- **GSD (primary).** GSD's pipeline (discuss → plan → execute → verify → review → ship) drives
  the build and injects these skills into its agents. Fresh-context agents, a verifier loop, and
  audit-fix give the highest assurance. Use it for large or high-stakes demos.
- **Native command set (floor).** A small set of `/demo:*` slash commands, scaffolded into the
  demo project, sequence the phases and hold the one human gate when GSD is absent.
  Self-contained, single-context, single-pass validation.
- **Skills alone, with the lightweight in-skill harness (floor).** No GSD and no `/demo:*`
  commands — a person or agent invokes the skills by hand. The skills are **not** run blind here:
  each carries a small built-in harness that guards its own canonical flow (ordering + a gate per
  step + a resumable progress artifact). Always available — the skills never require an external
  orchestrator, but they still refuse to skip a step or declare the build done before its gate
  passes. See "Standalone — the lightweight in-skill harness" below.

Both orchestrators read the **same** SKILL.md files; no skill is rewritten for either path. The
native command set detects GSD and steps aside when it is present, so the two never drive the
same build.

## Running modes

| Mode | Orchestrator | Enforcement |
|---|---|---|
| Skills alone | the skill's own lightweight harness | canonical-flow ordering + gate-per-step (refuse to skip / refuse to declare done) + a resumable progress artifact |
| Skills + native command set | `/demo:*` slash commands | the above + one human gate (impact sign-off) + single-pass validate |
| Skills + GSD | GSD pipeline | the above + fresh-context agents + gates + validate/gap/buff loop |

## Standalone — the lightweight in-skill harness (no orchestrator)

When neither GSD nor the `/demo:*` command set is driving, the skills are still not run blind.
Each demo skill carries a **lightweight orchestration harness** of its own — enough to guard the
canonical flow, far less than a full orchestrator. It is the floor, and it is always on. Three
rules plus one artifact:

1. **Walk the canonical flow in order.** Each demo skill documents its canonical step order
   (`dw-demo-base`'s end-to-end flow; the sister skills' prerequisites). The harness follows that
   order and does not jump ahead.
2. **Gate every step before advancing.** Each canonical step owns a verification gate. The
   harness runs the gate and **refuses to advance — or to declare the build done — until the gate
   passes**, exactly as `dw-demo-base` already refuses to declare setup complete with a failing
   gate. A miss surfaces and pauses; it never silently advances.
3. **Persist progress to a small artifact.** The harness writes one lightweight file —
   `.demo/<slug>/flow-state.json` — recording which canonical steps and gates have passed. This
   survives a context reset: a fresh agent reads the artifact and resumes at the first unchecked
   step instead of re-running or skipping work. The shape is deliberately minimal:

   ```json
   {
     "slug": "<prospect-slug>",
     "flow": "dw-demo-base",
     "steps": { "setup-checks": "pass", "scaffold": "pass", "mcp-setup": "pending" },
     "gates_passed": ["setup-checks", "scaffold"]
   }
   ```

This is the **same** `.demo/<slug>/` state the native command set uses — the native `state.json`
is a superset that adds `phase` and `impact_signed_off`. Running by hand and later adopting the
`/demo:*` commands or GSD does not throw the progress away; the heavier orchestrator reads the
artifact the harness already wrote.

The harness is **lightweight on purpose**: no fresh-context agents, no convergence loop, no human
gate beyond what a skill already asks for. It buys ordering + gate discipline + resumability over
pure freeform — and nothing more. For real assurance, promote to the native command set or GSD.

## Detection and deference (the native command set steps aside for GSD)

Every native `/demo:*` command runs this check first:

1. **Detect GSD** — is there a `.planning/` directory, or a `commands/gsd/` (a `/gsd-*`
   command surface)?
2. **If GSD is present and `--standalone` was NOT passed** — print the recommended `/gsd-*`
   flow for this phase (see the reuse mapping below) plus a one-line note that GSD gives
   fresh-context agents and the convergence loop, then **exit without acting**. The two
   orchestrators must never drive the same build.
3. **If GSD is absent (or `--standalone` was passed)** — run the native sequence.

`--standalone` is the override that forces the native path even when GSD is installed (a fast
throwaway demo, or deliberately staying single-context).

## The native command set

Scaffolded by `dw-demo-base` into the demo project's `.claude/commands/demo/` (templates live
in `dw-demo-base/assets/commands/demo/`). Deliberately thin and single-context; it mirrors the
GSD phase shape and reuses every skill.

```
.claude/commands/demo/
  scaffold.md   # detect GSD -> defer; else run dw-demo-base + the data-load skill, single-pass health check
  impact.md     # produce impact analysis from dw-demo-base demo-tactics, PAUSE for sign-off
  build.md      # require sign-off; build customer-specific elements; single validate vs acceptance
  status.md     # print phase + next command (read-only)

.demo/<prospect-slug>/
  state.json    # { "phase": "...", "impact_signed_off": false } — native mode only
```

- **`/demo:scaffold <slug> [--standalone]`** — create the slug + `state.json`; run the
  scaffold skills (`dw-demo-base` canonical flow, then `dw-demo-pim` seed for a PIM demo or the
  `dw-demo-swift` deserialize for a Swift demo); single-pass health check (host boots, PIM data
  above threshold, key pages render, Delivery API responds); on a miss, surface and ask; advance
  the phase to `impact`.
- **`/demo:impact [--standalone]`** — produce the impact analysis from `dw-demo-base`
  `references/demo-tactics.md` and the discovery prompts below; **PAUSE for sign-off** via
  `AskUserQuestion`; set `impact_signed_off`; advance to `build`.
- **`/demo:build [--standalone]`** — refuse without `impact_signed_off`; build the
  customer-specific elements (customer-center, pricing, re-skin, integration beats) from the
  signed-off analysis; run **one** validation pass against the acceptance criteria below;
  surface gaps and offer a fix pass; advance to `polish`.
- **`/demo:status`** — read-only; print the current phase and the next command.

The native validation is a **single pass**, not GSD's multi-cycle loop. It reads the **same**
acceptance criteria, so PASS means the same thing in both modes — the native command output
states the assurance level so the user knows GSD is the stronger orchestrator for high-stakes demos.

## The keystone — register the demo skills to GSD agents

In GSD mode, merge an `agent_skills` block into the project's `.planning/config.json`. Each
path is a directory containing a `SKILL.md`; GSD reads them into each agent at spawn. The
template ships at `dw-demo-base/assets/agent_skills.config.json`. Grounded against the **real**
GSD agent type names in this install (a fork may differ — list the install's actual agent types
and re-key):

```json
{
  "agent_skills": {
    "gsd-project-researcher": ["skills/dw-demo-base"],
    "gsd-phase-researcher":   ["skills/dw-demo-base"],
    "gsd-planner":            ["skills/dw-demo-base", "skills/dw-demo-pim"],
    "gsd-executor":           ["skills/dw-demo-base", "skills/dw-demo-pim", "skills/dw-demo-swift", "skills/dw-demo-erp", "skills/dw-integration-bc"],
    "gsd-verifier":           ["skills/dw-demo-base", "skills/dw-demo-swift"]
  }
}
```

Path resolution: the `skills/dw-demo-*` paths resolve against wherever this plugin is installed
(e.g. `~/.claude/plugins/marketplaces/dynamicweb-skills/skills/...`) or a local clone. Rewrite
them to that absolute base before GSD spawns agents. The native command set reads the same skill
directories directly through the installed plugin — no rewrite needed there.

## Reuse mapping (GSD mode) — reuse GSD primitives, do not rebuild them

| Demo need | GSD primitive | What the skills add |
|---|---|---|
| A demo for a prospect | `/gsd-new-project` → PROJECT.md + ROADMAP.md | the 3-phase roadmap template (`assets/ROADMAP.template.md`): scaffold → customer build → polish |
| Decide impact, then sign off | `/gsd-discuss-phase` → CONTEXT.md + approval gate | `dw-demo-base` demo-tactics + discovery prompts on the planner; acceptance criteria derive from CONTEXT.md |
| Scaffold host + DB + PIM + frontend | plan → execute → verify | `dw-demo-base` + `dw-demo-pim`/`dw-demo-swift` on the executor |
| Auto-iterate to quality | verifier loop + `/gsd-audit-fix` + `--bounce` | the acceptance criteria below |
| Customer-specific context | another phase, plan → execute → verify | `dw-demo-swift` (customer-center, pricing, re-skin), `dw-demo-erp`/`dw-integration-bc` (integration beats) |
| Polish | `/gsd-quick`, `/gsd-fast`, `/gsd-verify-work` | nothing |

## Strictness gradient — one human pause, automated quality elsewhere (both modes)

The mechanism differs by orchestrator; the shape does not. Exactly one phase blocks on a human:
the impact sign-off.

| Phase | Enforcement | GSD | Native |
|---|---|---|---|
| Scaffold | Automated | execute → verify → `VERIFICATION.md`; `/gsd-audit-fix` | single-pass health check |
| Impact analysis | **Human sign-off** | discuss CONTEXT.md + approval gate | `/demo:impact` pause |
| Customer build | Automated | plan `--bounce` → execute → verify | single validate vs acceptance + offered fix |
| Polish | None | `/gsd-quick` / `/gsd-fast` / `/gsd-verify-work` | freeform |

## Discovery prompts (impact-analysis input — shared by both orchestrators)

The impact analysis answers, for this prospect: customer pain; competitive context; the two or
three demo moments that land hardest; SKU mapping; catalog scoping; pricing model; punch-out /
integration touchpoints. These are questions, not sequencing — the planner (GSD) or
`/demo:impact` (native) asks them, then writes the analysis into CONTEXT.md (GSD) or the
sign-off prompt (native). Keep the customer's own words (see `references/demo-tactics.md`).

## Acceptance criteria (the shared definition of PASS)

Both orchestrators read these; PASS means the same thing whether GSD's verifier loop or the
native single pass produced it. Per phase:

- **Scaffold** — host boots and `/Admin` returns 200; MCP connected (`claude mcp list` shows
  `Connected`, `ToolSearch +dynamicweb` > 200 tools); PIM product count above the demo's
  threshold; the storyline's key pages render; the Delivery API (`/dwapi/`) responds.
- **Customer build** — every demo moment from the signed-off analysis is reachable in the live
  UI; personas log in (floor of 2: one buyer, one CSR); customer-specific pricing resolves in
  the cart; the re-skin reads as the customer's brand; the `CUSTOMISATIONS.md` ledger accounts
  for every custom-code row.
- **Polish** — no broken links on the storyline path; no placeholder/lorem content on visited
  pages; the demo runs end-to-end in one pass without a dead end.

A demo that needs different criteria edits this list in its own roadmap; the orchestrator reads
the project's copy, so both orchestrators stay in agreement.

## "How to run me" header — the convention every demo skill carries

Each demo SKILL.md carries a short header stating that, **under an orchestrator the orchestrator
owns sequencing** (GSD injects the skill into an agent; the native command invokes it), and
**standalone the skill's own documented order applies**. The header points here. This is how the
skills stay sequencing-free as a contract while remaining usable by hand. The header is a demo-
skill convention only — foundational skills never reference an orchestrator or a demo skill (the
one-way boundary in `CLAUDE.md`).
