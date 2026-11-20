# Orchestrators — how a demo build is driven (native command set, standalone floor)

## Contents

- [Build from the library](#build-from-the-library)
- [The build path an orchestrator sequences](#the-build-path-an-orchestrator-sequences)
- [Running modes](#running-modes)
- [Standalone — the lightweight in-skill harness (no orchestrator)](#standalone--the-lightweight-in-skill-harness-no-orchestrator)
- [The native command set](#the-native-command-set)
- [Two kinds of gate (why scaffold is gated without pausing for a human)](#two-kinds-of-gate-why-scaffold-is-gated-without-pausing-for-a-human)
- [Strictness gradient — one human pause, automated quality elsewhere (every mode)](#strictness-gradient--one-human-pause-automated-quality-elsewhere-every-mode)
- [Dispatched sessions: the brief carries the execution authority](#dispatched-sessions-the-brief-carries-the-execution-authority)
- [Model tier — a dial on the orchestrator, never a fork of the skills](#model-tier--a-dial-on-the-orchestrator-never-a-fork-of-the-skills)
- [Delegating the recipe set — the orchestrator keeps the brief](#delegating-the-recipe-set--the-orchestrator-keeps-the-brief)
- [Discovery prompts (impact-analysis input)](#discovery-prompts-impact-analysis-input)
- [Acceptance criteria (the shared definition of PASS)](#acceptance-criteria-the-shared-definition-of-pass)
- ["How to run me" header — the convention every demo skill carries](#how-to-run-me-header--the-convention-every-demo-skill-carries)

A demo build needs two separable things: **domain knowledge** (what to scaffold, how DW10
behaves, the surface-priority rule, the customer-center playbook) and **sequencing** (which
phase runs when, where the human gate sits, when validation fires). The demo skills in this
repo own the first and carry **none** of the second as an enforced contract. The thing that
sequences the phases, holds the gates, and drives the agents is the **orchestrator**, and it is
swappable.

> **Term.** "Orchestrator" is the swappable component that sequences the build. The skills are
> the **substrate** every orchestrator reads. Do not call it a "driver" — that overloads the
> device-driver / browser-driver sense already used in `references/browser-automation.md`.

One orchestrator ships with the skills, plus the no-orchestrator floor:

- **Native command set.** A small set of `/demo:*` slash commands, scaffolded into the
  demo project, sequence the phases and hold the one human gate.
  Self-contained, single-context, single-pass validation.
- **Skills alone, with the lightweight in-skill harness (floor).** No `/demo:*`
  commands — a person or agent invokes the skills by hand. The skills are **not** run blind here:
  each carries a small built-in harness that guards its own canonical flow (ordering + a gate per
  step + a resumable progress artifact). Always available — the skills never require an external
  orchestrator, but they still refuse to skip a step or declare the build done before its gate
  passes. See "Standalone — the lightweight in-skill harness" below.

Every mode reads the **same** SKILL.md files; no skill is rewritten for an orchestrator. A
dispatcher or another agent framework that drives a build is an orchestrator in the same sense:
it sequences the phases below, holds the one human gate, and reads the same acceptance criteria.
Two orchestrators never drive the same build.

## Build from the library

Every orchestrator, and the skills alone, builds the customer-specific content from the recipe
library before it reaches for any prose procedure. A recipe is the proven, replayable form of one
platform function ([`dw-demo-ledger` recipes.md](../../dw-demo-ledger/references/recipes.md)); the
[recipe index](../../dw-demo-ledger/references/recipe-index.md) lists each one with its input
section, what it proves, its modes and what it leaves to hand work. The build is one customer data
file and one command.

### 1. Write the customer data file

One JSON file, validated against
[`recipe-input.schema.json`](../../dw-demo-ledger/assets/recipe-input.schema.json) (start from
[`recipe-input.example.json`](../../dw-demo-ledger/assets/recipe-input.example.json)). Each
section feeds one recipe; a section that is absent is simply not built. Keep it in the demo's
`notes\` folder, never in `customer-context\`, and keep passwords out of it: a user names a
`passwordRef` and the value goes in `DW_RECIPE_SECRETS`.

| Section | Recipe | For a branded demo |
|---|---|---|
| `brand` | `content.design-styles`: fonts, typography, buttons, colour schemes, logo, favicon, header and footer rows | **Mandatory.** From a brand kit: `ConvertFrom-DwBrandKit.ps1 -KitPath <kit>/swift2 -OutPath <file>` |
| `users.accounts` | `users.accounts`: account and staff groups, users with passwords, impersonation | **Mandatory**: one buyer, one representative who may impersonate it |
| `catalogue` | `pim.data-models` (with `pimFolder`), then `pim.identifiers`: groups, products, specs, images, stock | **Mandatory** |
| `prices` | `commerce.customer-prices`: list prices, tiers, group and contract prices | **Mandatory**: the storefront lists a product only once it has a price |
| `content.pages` | `content.pages`: pages, rows, paragraphs, item fields | When the storyline visits a page the edition does not ship |
| `history` | `orders.completed-orders`: numbering, orders, quotes | When the storyline shows a customer centre |
| `pim.workflow` | `pim.workflow`: states, transitions, attached to data models | PIM stories |
| `debrand` | `content.page-seo`: every place a former name shows, replaced | When stock or inherited content names another company. Never put a forbidden text in another section: the set refuses it |
| `build` | none: `areaId`, `defaultLanguage`, `pimShop` the recipes read | Always |
| `brandCopy` | none: the layer generator's storefront copy | When a layer generator builds the delivered copy |

### 2. Deliver, then build what was not delivered

- **Built from blank with a layer generator available** to the operator: generate a rewritten
  copy of the edition's layers from the same data file and deliver it before the first delivery.
  Then run the set exactly as below, with no flag: each recipe recognises what the copy delivered
  (`=` UNCHANGED, or `D` DELIVERED where the copy keys an object its own way) and writes none of
  it again; brand, pages, de-brand, accounts and checkout are still applied. `-LayerDelivered
  <sections>` remains for leaving a section untouched altogether (an MCP-only run cannot tell a
  layer's categories from its own).
- **Otherwise** (an edition delivered as shipped, or a blank site and no generator): run
  `Invoke-DwRecipeSet.ps1 -InputPath <file>` first (writes nothing, lists every WOULD-CREATE), then
  `-Apply`. The set runs the recipes in the index's run order, pays the debts (cache flushes, index
  and assortment builds, one recycle) once, and verifies every recipe again. Exit 0 means every
  object is in place and every probe passed; the last line counts the recipes that passed. A
  `DEBT OPEN recycle` line means the host must be recycled (host-lifecycle.md, or the hosted
  route), then the set is run again without `-Apply`.
- `-Only <ids>` and `-Skip <ids>` narrow a rerun; `-Only <id> -PayDebts -Apply` pays one recipe's
  host debts on their own (an index or assortment build after a hand edit).

### 3. Build by hand only what no recipe covers

This is the orchestrator's part of the chain, at the mid tier or above: the set run itself is
delegated to the small tier ("Delegating the recipe set" below), and the custom work (templates,
what the set reports BLOCKED or planned) stays with the orchestrator. The build ends with a verify
of the set, all PASS, and the brief's checks.

`Find-DwRecipe.ps1 -Function <id>` answers whether a recipe exists for a ledger function; "no
recipe" means build it by hand from the owning skill. The index's "What stays planned" names the
pieces a recipe leaves open (for example favourite lists and order dates, which no MCP or
Management API write reaches). A script written for that hand work is proposed back as a recipe at
fold-back ([`dw-demo-foldback`](../../dw-demo-foldback/SKILL.md)).

### What changes per mode, environment and path

| | What changes |
|---|---|
| Skills alone | The harness records a `recipes` step in `flow-state.json`; its gate is the set's exit 0, and the instructions-used map names the set's report |
| `/demo:*` command set | `/demo:impact` produces the data file with the analysis; `/demo:build` runs the set after sign-off and its validation pass reads the set's summary before the acceptance criteria |
| Local install | `-SolutionPath <solution>` lets the set recycle a loopback host itself; `-AllowSql -SqlServer -Database` adds optional read-only checks |
| Hosted install (URL + API key) | Set `DW_BASE_URL`, `DW_API_TOKEN` and, when the install exposes it, `DW_MCP_TOKEN`; no SQL. A recipe whose index row says hosted `no` reports its blocked steps; the recycle stays OPEN with the hosted route ([`dw-demo-hosted`](../../dw-demo-hosted/SKILL.md)) |
| Path A, YAML brand layer | The brand layer carries the brand: run the set with `-LayerDelivered brand` so `content.design-styles` verifies it, and apply the other sections. A data copy (catalogue, prices, users, history) needs no flag |
| Path B, deliver then tools | Run the set with `-Apply` over the delivered edition |
| Path C, tools only from blank | Run the set with `-Apply`; nothing is layer-delivered |
| MCP tools only (no shell) | Follow each recipe in run order with [recipe-by-hand.md](../../dw-demo-ledger/references/recipe-by-hand.md); a recipe whose index row says MCP-only `no` leaves the named steps for an operator with the Management API |

## The build path an orchestrator sequences

An orchestrator sequences phases; it does not get to invent the build path. **The default path a
demo build takes is the YAML brand layer**: compose the edition that ships the demo content,
author a demo-local brand layer over it, deliver and deserialize, and use the tools only for the
few subjects Deserialize cannot carry. Measured against the alternative on the same brief, the
same starting layer and the same pins, it finished in 60.5 min against 79.3, spent 1.43 M tokens
against 2.03 M, landed 88.02 % of brand values by deserialize against none, rebuilt itself in
176 s, and produced 4 findings against 24.

"Drive the demo build" therefore means: **path A** in
[branded-demo-paths.md](branded-demo-paths.md), with **path B (deserialize first, then tools)**
as the explicit alternative an orchestrator selects, and says it is selecting, when one of that
file's four conditions holds (a small change set, no local compose, a brand that lives in
subjects with no serialized route, or a throwaway nobody will rebuild). Both paths are supported;
the choice is made once, before the first brand write, and recorded in the plan doc. Whichever
path is chosen, the phase order, the gates and the human pause below are unchanged.

## Running modes

| Mode | Orchestrator | Enforcement |
|---|---|---|
| Skills alone | the skill's own lightweight harness | canonical-flow ordering + gate-per-step (refuse to skip / refuse to declare done) + a resumable progress artifact |
| Skills + native command set | `/demo:*` slash commands | the above + one human gate (impact sign-off) + single-pass validate |

## Standalone — the lightweight in-skill harness (no orchestrator)

When the `/demo:*` command set is not driving, the skills are still not run blind.
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
     "gates_passed": ["setup-checks", "scaffold"],
     "instructions_used": {
       "setup-checks": ["dw-demo-base/references/setup-checks.md §1"],
       "scaffold": ["dw-demo-base/references/scaffold.md §3"]
     }
   }
   ```

   **The instructions-used map is the step's "Instructions used:" line.** Record, per step, the skill
   files and sections actually read before acting (not the ones that exist). A human-readable run
   journal carries the same thing as an `Instructions used: <file> <section>` line on every step.
   It is what lets a later fold-back tell a rule that is missing from one that was documented and
   not reached ([`dw-demo-foldback` `fold-back-workflow.md`](../../dw-demo-foldback/references/fold-back-workflow.md)
   Step 1b "Dedup check").

This is the **same** `.demo/<slug>/` state the native command set uses — the native `state.json`
is a superset that adds `phase` and `impact_signed_off`. Running by hand and later adopting the
`/demo:*` commands does not throw the progress away; the command set reads the
artifact the harness already wrote.

The harness is **lightweight on purpose**: no fresh-context agents, no convergence loop, no human
gate beyond what a skill already asks for. It buys ordering + gate discipline + resumability over
pure freeform — and nothing more. For more assurance, promote to the native command set.

## The native command set

Scaffolded by `dw-demo-base` into the demo project's `.claude/commands/demo/` (templates live
in `dw-demo-base/assets/commands/demo/`). Deliberately thin and single-context; it reuses every skill.

```
.claude/commands/demo/
  scaffold.md   # run dw-demo-base + the data-load skill, single-pass health check
  impact.md     # produce impact analysis from dw-demo-base demo-tactics, PAUSE for sign-off
  build.md      # require sign-off; build customer-specific elements; single validate vs acceptance
  status.md     # print phase + next command (read-only)

.demo/<prospect-slug>/
  state.json    # { "phase": "...", "impact_signed_off": false } — native command set only
```

- **`/demo:scaffold <slug>`** — create the slug + `state.json`; run the
  scaffold skills (`dw-demo-base` canonical flow, then `dw-demo-pim` seed for a PIM demo or the
  `dw-demo-swift` deserialize for a Swift demo); single-pass health check (host boots, PIM data
  above threshold, key pages render, Delivery API responds); on a miss, surface and ask; advance
  the phase to `impact`.
- **`/demo:impact`** — produce the impact analysis from `dw-demo-base`
  `references/demo-tactics.md` and the discovery prompts below; **PAUSE for sign-off** via
  `AskUserQuestion`; set `impact_signed_off`; advance to `build`.
- **`/demo:build`** — refuse without `impact_signed_off`; build the
  customer-specific elements (customer-center, pricing, re-skin, integration beats) from the
  signed-off analysis; run **one** validation pass against the acceptance criteria below;
  surface gaps and offer a fix pass; advance to `polish`.
- **`/demo:status`** — read-only; print the current phase and the next command.

The native validation is a **single pass** against the acceptance criteria below, and the
command output states that assurance level.

## Two kinds of gate (why scaffold is gated without pausing for a human)

Strictness here is **not one mechanism but two**, and conflating them is what makes a workflow
either too slow (a human pause everywhere) or too loose (no gate at all):

- **Human sign-off gate.** Execution pauses and waits for the user's explicit OK before
  proceeding. It costs a real wait, so it is spent **once** — at the impact sign-off, the single
  place where a wrong call is expensive to undo.
- **Automated quality gate.** The output is checked against the explicit acceptance criteria
  and the gaps close before the next phase builds on top. **No human waits.** Its strongest form
  is a validate/gap/fix loop: a builder produces the output; a **separate validator with fresh
  context** checks it; the gaps feed back; the builder re-runs; repeat until PASS or a cycle cap.
  A fresh-context validator catches what the builder rationalised past.

**Scaffold and customer build are gated — by the automated gate, not by a human pause.** That is
the point: they stay fast *and* get more reliable. The assurance level of that gate depends on
what drives the build:

- **A dispatcher that runs the build as separate sessions** can supply the loop: a second
  session with fresh context that only validates against the acceptance criteria. Highest
  assurance; use it for high-stakes demos.
- **Native command set** runs a **single** validate pass against the same acceptance criteria,
  then offers a fix pass — no fresh-context validator, no convergence loop. It says so in its
  output.
- **Standalone harness** is lower still: one gate check per canonical step, no validator agent.

The single **human** gate sits only at the impact sign-off, in every mode. Everything else is the
automated gate at whatever assurance the active orchestrator provides.

## Strictness gradient — one human pause, automated quality elsewhere (every mode)

These are the two gates above, placed per phase. The mechanism differs by orchestrator; the shape
does not. Exactly one phase blocks on a human: the impact sign-off.

| Phase | Enforcement | Native command set |
|---|---|---|
| Scaffold | Automated | single-pass health check |
| Impact analysis | **Human sign-off** | `/demo:impact` pause |
| Customer build | Automated | single validate vs acceptance + offered fix |
| Polish | None | freeform |

**Flexibility — a demo is not a product, so the gates have escape hatches.** For a fast throwaway
demo, drop the depth: skip the offered fix pass, or put the small tier on scaffold verification
(see "Model tier" below). The one gate that never lifts is the impact sign-off
— that is the decision a demo lives or dies on. Polish stays free in every mode.

## Dispatched sessions: the brief carries the execution authority

A **dispatched** session is one an orchestrator or a launcher starts from a written brief with no
human at the keyboard. It is non-interactive, and that changes what a brief has to say. **A
question is not a pause, it is the end of the run.** There is nobody to answer it, so the turn
that asks it is the last turn.

The measured failure is not a refusal and not a crash. A brief described what to build in full
detail but never said that the live deploy was authorised. The session ran dozens of turns, spent
real money, exited 0, shipped nothing, and closed its final turn by asking permission to deploy.
The agent behaved correctly: the first outward-facing write to a prospect's demo *should* need
confirmation. Because the session cannot obtain that confirmation, the brief has to supply it up
front.

Every dispatched brief therefore opens with an **EXECUTION AUTHORITY** preamble carrying three
clauses:

1. **The session is non-interactive and a question ends the run.** State it, so the agent
   resolves ambiguity inside the brief's scope instead of asking.
2. **The brief's sign-off IS the deploy authorisation**, with the scope explicitly bounded.
   Name what the authority does *not* cover, so the bound is machine-readable rather than
   implied: the human design sign-off and the host's version-pin file are the two standing
   exclusions (`references/visual-qa.md` owns the first; the second is a host lever, not
   build content).
3. **The run ends on a verdict.** The gate runs last and a FAIL verdict is **emitted**, never
   swallowed by a silent exit. A run that ends without a verdict is a harness failure, not a
   soft outcome (see "Acceptance criteria" below).

Two fixes that look right and are not:

- **"Do not ask questions" is the wrong instruction.** It buys silence by removing the agent's
  ability to refuse work outside the brief. Scope the authority; never blanket it. An agent that
  still refuses out-of-scope work is the behaviour you want to keep.
- **Loosening the permission prompt is not the fix either.** In the measured run the session's own
  permission-denial record was empty: nothing in the harness ever blocked the agent, it chose
  to ask.
  A permission flag cannot repair a brief that never granted the authority.

**A brief does not prescribe a pattern a skill forbids, and an earlier increment is not precedent.**
Each brief tends to cite the last one, so one unsafe shortcut written as "the proven pattern" becomes
the specification of every increment after it, with nobody having decided that. A constraint in a
brief (no build, no restart) states a budget, never an implementation: name the outcome and let the
skills choose the surface. When a brief lists proven patterns, each must pass the skills' rules on
its own, and an executor that finds a brief or prior increment contradicting a skill follows the
skill and says so in its report. Raw SQL in Razor is the measured case: a no-restart budget became
"read it with `Database`", then a listed pattern, then a specified page, though the service layer
was callable from Razor throughout (`dw-demo-swift/references/integrity-sweep.md` Check 7).

The preamble belongs in the **template the dispatcher renders**, so every launched brief carries
it by construction. Per-brief boilerplate is exactly the thing that is missing on the brief that
needs it.

**A branch inherits main's gate-proven stamp.** One authority bound worth stating whenever a
dispatched build consumes a Distribution *branch* rather than `main`: the `layers/INDEX.json`
`gateProven` marker does not travel with branches. A PR branch carries `main`'s stamp, and the
standard preflight asserts only that the marker is present and well formed, so a branch that has
edited layers still reads as gate-proven. Treat the stamp as **unproven** on any branch whose
`layers/**` paths changed after the commit that last wrote it, and say so in the plan rather than
quoting the inherited marker back as proof.

## Model tier — a dial on the orchestrator, never a fork of the skills

A skill is authored **once**, for the least capable model the demo chain is expected to run on.
There are no per-tier variants of a SKILL.md or a reference, and adding them would be a mistake:
skill frontmatter carries no model gate (agents have `model:`; skills do not), so a variant
scheme would rest on convention alone — and a forked recipe drifts the moment one copy is folded
back and the other is not. The corpus already pays for exactly one source of truth per recipe.

The tier decision belongs one layer up, in the orchestrator: the session that drives the build
and the sub-sessions or subagents it starts. These skills name three tiers and no model:

- **top**: the provider's deepest-reasoning model. Design, the brief's unique ask, judging.
- **mid**: the default builder. Builds the brief past the recipe set; the lowest tier that does.
- **small**: the provider's fastest, cheapest model. Mechanical, scripted work.

**Resolve the tiers from your own environment.** A tier is a role, not a product: map it to
whatever the agent you run in offers. Read its model list (its model picker or the option it
takes when starting a subagent or sub-session) and take the fastest, cheapest as small, the
standard general-purpose model as mid, the deepest-reasoning as top. With one model available, every tier is that model.
Non-normative examples: in Claude Code a subagent takes a model through its definition's
`model:` field or the model option of the call that starts it, and `/model` lists the choices;
in the Codex CLI the call that starts a sub-agent takes a `model` (left empty, it inherits the
caller's), a sub-session is `codex exec -m <model> "<brief>"`, and `/model` lists the choices.

Place the tier by the *kind* of work, not by the phase name:

| Work | Tier | Why |
|---|---|---|
| Mechanical sweeps — validator runs, the recipe set run, the integrity sweep, visual-QA detectors, scrub passes | small | the verdict is deterministic; the script holds the judgment, the model only runs it |
| Building the rest of the brief — what the set does not cover, hand-followed recipes, custom templates | mid | the brief and the owning skills are the plan, and the final verify catches drift before the hand-in |
| The fresh-context validator in the automated loop | mid, top for a high-stakes demo | its whole value is catching what the builder rationalised past |
| Impact analysis, the brief's unique ask, brand/taste calls, the visual-QA human sign-off, authoring a fold-back | top | judgment under ambiguity, where no mechanical check exists to fall back on |

Measured on demo builds from blank sites, judged blind [dw 10.30 · swift 2.5]: the small
tier ran the recipe set from a customer data file (verify, apply, pay debts, final verify) on four
builds in 7 to 9 minutes for about 3 US cents each, with no hand writes and the same result as the
larger tiers. Alone it could not build the rest of a brief (it duplicated data, hid prices and
built no custom work). The mid tier built the rest to a good standard; the top tier held one more
acceptance check at about three times the minutes and cost.

The rule that keeps this honest: **what a cheaper model cannot be trusted to remember, encode in
a script or a detector — not in a longer prose rule.** A gate written as a validator holds at
every tier; the same gate written as three more paragraphs of prose holds only at the top one,
and silently stops holding when someone dials the tier down for cost.

## Delegating the recipe set — the orchestrator keeps the brief

The orchestrating session owns the whole brief and the hand-in. The recipe set run is the part to
delegate: it is mechanical, and the small tier runs it as well as any tier for a fraction of the
time and price ("Model tier" above). **Delegating it never ends the orchestrator's own work.** A
hand-over where a second session received only the first one's report was unreliable: once it
repaired what was reported and stopped, leaving the brief's custom work unbuilt. One orchestrating
session that ran or delegated the set and kept ownership of the brief was complete each time.

**Delegating is the default, not an option.** When your agent can start a subagent or sub-session,
the set run goes to one. Run it inline, in the same order and under the same rules, only when your
agent has no such mechanism or the set is one or two sections.

**Name the model in the call that starts the delegate.** Resolve the small tier first ("Model
tier" above), then pass that model explicitly. A subagent started with no model, or an empty one,
inherits the orchestrator's model: that is a second copy of yourself, not a delegation, and it
saves neither time nor price. Measured on two first builds of one brief on two providers
[dw 10.30 · swift 2.5]: both orchestrators had read this section, one ran the set itself on the
top tier and the other started three subagents that all inherited its own model.

**Work while it runs.** Start the delegate in the background where your agent allows it, and use
the wait for what needs no write: read the brief's custom work, the owning skills and the site's
templates. Make no write to the site until the delegate's apply has ended; two writers on one
site invalidate the set's read-backs.

**A dispatched build gets the split from its brief.** This section alone does not make a session
delegate: on two providers, sessions that had read it kept the set run on their own model, twice.
The same sessions, given the paragraph below in the brief that started them, each started a
sub-agent on their provider's small model for the set run [dw 10.30 · swift 2.5]. Whoever starts a
build session (a launcher, a dispatcher, a person) therefore starts it with the brief
[`scripts/New-DwBuildBrief.ps1`](../scripts/New-DwBuildBrief.ps1) prints, with the model ids
resolved as "Model tier" says:

```powershell
pwsh -NoProfile -File <skills>/dw-demo-base/scripts/New-DwBuildBrief.ps1 -OrchestratorModel <mid> -SmallModel <small> [-TopModel <top> -EscalateFor <pieces>] [-DataFile <file> -SkillsPath <skills> -LogFolder <folder>] [-OutFile <brief.md>]
```

It opens with this paragraph, the small model's id named before "the smallest, fastest model your
agent offers", and adds the delegate's run order, the no-write rule and the hand-in below.
`-TopModel` lets the hardest custom pieces go up and has the hand-in name them; `-Phase plan`
prints a read-only planning brief.

> You are the orchestrator. Keep the brief and the custom work yourself. Hand the recipe set run
> (verify, apply once, pay debts, final verify) to a sub-agent on the smallest, fastest model your
> agent offers, and name that model in the call that starts the sub-agent: a call without a model
> inherits yours. Do the same for other mechanical work. In your result, say which model ran the
> recipe set and which model built the rest.

**Say who ran it.** The hand-in names the model that ran the set and the model that built the
rest, so the next build can check the split was real. The delegate passes `-RunBy <its model>` (or
sets `DW_RECIPE_RUN_BY`) to every set run, and the summary prints `run by: <model>`, or
`run by: not stated` when it was left out.

**Give the delegate** (a sub-session or subagent on the small tier):

- the absolute paths of the customer data file, the skills checkout and a folder for its logs and
  reports;
- the environment, set in its process and never pasted into the brief: `DW_BASE_URL`,
  `DW_MCP_TOKEN` or `DW_API_TOKEN`, `DW_RECIPE_SECRETS`, `DW_PERSONA_CREDENTIALS`; plus
  `-SolutionPath <solution>` for a loopback host it may recycle and `-AllowSelfSignedCertificate`
  for a local self-signed one;
- the run order, each run's output saved to a log, with `-ReportPath <folder>/<run>.json` and
  `-RunBy <its model>`:
  1. **verify**: `Invoke-DwRecipeSet.ps1 -InputPath <file>`;
  2. **apply once**: the same with `-Apply`;
  3. **pay debts**: for each `DEBT OPEN` or `DEBT FAIL` line, `-Only <owner> -PayDebts -Apply`
     once;
  4. **final verify**: step 1 again;
- the rules: no write by hand (no MCP write tool, no SQL, no admin UI), no edit to the data file
  or a recipe, no fix and no retry outside that order. A failure is reported, not repaired.

**Demand back**: the log and report path of every run, the final summary table as printed, every
row whose Result is not PASS and every FAIL, OPEN, BLOCKED and `DEBT` line verbatim with its
reason, the last line (`recipe set: <n> of <m> recipes passed`) and each run's exit code.

**Read the report**, then act on it yourself:

| Reported | Means | Orchestrator's next step |
|---|---|---|
| PASS | built, read back and proven | nothing |
| DELIVERED (`D`) | a layer copy delivered it | nothing; never write it again |
| SKIPPED | `-Skip`, or the section lacks a required member | intended: nothing; else fix the input and re-run that recipe |
| BLOCKED (`B`) | no eligible binding, a collision, or a blocked dependency | input or grant: fix it and re-run that recipe; no binding: build it by hand from the owning skill |
| FAIL | an observation disagrees | read the reason; fix the input or the grant and re-run that recipe; a defect in the recipe itself is fold-back material, and the hand build covers it meanwhile |
| OPEN | an observation could not be made, or a debt is unpaid | pay the debt (`-Only <owner> -PayDebts -Apply`, or the recycle it names), then verify that recipe |
| NOT RUN | the run stopped before the recipe | fix the fault the log names and re-run |

**Re-run one recipe instead of fixing by hand**: `Invoke-DwRecipeSet.ps1 -InputPath <file> -Only
<id>`, then with `-Apply`. A hand fix to an object a recipe owns is undone or flagged by the next
apply and leaves the final verify proving the wrong thing; build by hand only what no recipe covers.
Then build the rest of the brief, run the final verify of the set yourself, and run the brief's
checks: that is the hand-in, and it is the orchestrator's.

## Discovery prompts (impact-analysis input)

The impact analysis answers, for this prospect: customer pain; competitive context; the two or
three demo moments that land hardest; SKU mapping; catalog scoping; pricing model; punch-out /
integration touchpoints. These are questions, not sequencing — `/demo:impact` asks them, then
writes the analysis into the sign-off prompt. Keep the customer's own words (see `references/demo-tactics.md`).

## Acceptance criteria (the shared definition of PASS)

Every mode reads these; PASS means the same thing whichever orchestrator produced it. Per phase:

- **Scaffold** — host boots and `/Admin` returns 200; MCP connected (`claude mcp list` shows
  `Connected`, `ToolSearch +dynamicweb` > 200 tools); PIM product count above the demo's
  threshold; the storyline's key pages render; the Delivery API (`/dwapi/`) responds.
- **Customer build** — every demo moment from the signed-off analysis is reachable in the live
  UI; personas log in (floor of 2: one buyer, one CSR); customer-specific pricing resolves in
  the cart; the re-skin reads as the customer's brand; the `CUSTOMISATIONS.md` ledger accounts
  for every custom-code row; the raw-SQL template scan (`dw-demo-swift/references/integrity-sweep.md`
  Check 7) passed on the final templates of every increment that added or changed one.
- **Polish** — no broken links on the storyline path; no placeholder/lorem content on visited
  pages; the demo runs end-to-end in one pass without a dead end; the mechanical visual-QA gate
  passes on every demo-critical page (see `references/visual-qa.md` "Definition of done") **and**
  the design has a human taste sign-off.

**Design asserts arm on the FIRST gate run, not at re-skin time.** Presentability is a property of
every gate run, not of the design workstream. A design leg left unconfigured stamps `SKIP`, the run
reports `PASS`, and the build ships horizontal overflow, skeleton bands and shipped stock copy — the
defect class then surfaces when a human eyeballs the site, which is exactly what a mechanical gate
exists to prevent. From the scaffold gate onward, three legs run against a raw deserialize with no
custom design configuration:

1. **Overflow** — `document.body.scrollWidth === window.innerWidth` AND `window.innerWidth === the requested width`, at desktop and mobile widths. Both readouts: unshrinkable content widens the layout viewport, after which the first comparison holds on a page that renders zoomed out (`dw-demo-base/references/visual-qa.md` "Breakpoints").
2. **Skeleton / empty-band scan** — a band carrying a heading and no content children, or almost no
   text, is a skeleton.
3. **Stock-copy tripwire** — the shipped baseline's own copy strings, grepped against the served HTML.

The detectors and the tripwire list live in
[`../../dw-demo-swift/references/re-skin.md`](../../dw-demo-swift/references/re-skin.md) §"Step 0 — the zero-state pass"; this
list is the acceptance contract that says *when* they run. Expect FAIL on run one against a raw
baseline — the pass is earned by fixing the layer defect and authoring the content, never by leaving
the leg unconfigured.

**The design page set covers every language prefix the build serves.** Chrome copy is longer in some
languages than the one the header was laid out in, so a translated area can carry a constant
horizontal overflow on *every* page while the default-language pages measure clean. A page list of
default-language URLs cannot see it however correct the assert is — and the constant-per-language,
content-independent value is the tell that the cause is chrome rather than any one page. Parameterise
the design page set by the same language prefixes the permission-parity leg already uses.

**Design sign-off — taste stays human without blocking automation.** Mechanical asserts prove
structure (image-band caps, PLP row-presence + content, no overflow/gaps — `references/visual-qa.md`);
they cannot judge visual hierarchy or brand fit, so an all-green mechanical run can still ship a
page that reads wrong. Reserve that judgement as a **stamped, non-blocking** leg rather than a
human pause: the design sign-off check reports **SKIP ("awaiting human sign-off")** until a
sign-off artifact (e.g. `home/<slug>/design-signoff.json` — `{ signed_off_by, ts, notes }`,
written by an approve-design step) exists, then **PASS**. A SKIP is stamped, never a FAIL, so it
records "taste not yet reviewed" without failing the build or forcing an execution pause — the one
*blocking* human gate remains the impact sign-off. The keeper screenshots at both breakpoints are
the artifact the human signs off on.

A demo that needs different criteria edits this list in its own roadmap; the orchestrator reads
the project's copy.

## "How to run me" header — the convention every demo skill carries

Each demo SKILL.md carries a short header stating that, **under an orchestrator the orchestrator
owns sequencing** (the native command invokes it), and
**standalone the skill's own documented order applies**. The header points here. This is how the
skills stay sequencing-free as a contract while remaining usable by hand. The header is a demo-
skill convention only — foundational skills never reference an orchestrator or a demo skill (the
one-way boundary in `CLAUDE.md`).
