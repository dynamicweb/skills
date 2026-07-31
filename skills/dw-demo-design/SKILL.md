---
name: dw-demo-design
type: flow
group: demo
description: 'Dynamicweb 10 demo presentability — the ordered ladder that takes a freshly deserialized Swift baseline from stock-Swift to a site that reads as this customer''s. Owns the post-baseline zero-state pass (stock-copy tripwires, the item-type `defaultValue` trap, empty-band disposition, brand surfaces), and routes the rest of the ladder to its existing owners. Triggers: "the baseline is loaded, now make it presentable", "the demo looks amateur / unfinished / like a template", stock lorem or eco copy on a customer page, "Swift" in the header/footer/browser tab, skeleton cards, an empty FAQ or slider band, a PDP section that renders a whole product-list page, missing alt text, arming the design gate on run one. Non-triggers: loading the baseline / paragraph mechanics -> dw-demo-swift; host setup/MCP/TLS -> dw-demo-base; PIM data -> dw-demo-pim. Use AFTER dw-demo-swift Step 0 (baseline deserialized, area bound, host serving pages).'
---

# Dynamicweb Demo Design Skill

The hardest phase of a demo build is not loading the baseline and not writing custom code. It is
the phase between them: **making a loaded baseline look like this customer's site.** That phase
had knowledge but no spine — the material was spread across seven references in two skills, every
one of them reachable only from a lookup table, i.e. optional by placement. This skill is the
spine. It owns the ordered ladder and the one rung nobody had written down (zero-state); the
other rungs keep their existing owners and are routed to from here.

**Use AFTER** [`../dw-demo-swift/SKILL.md`](../dw-demo-swift/SKILL.md) Step 0 — assumes the
baseline is deserialized, the area is bound, and the host serves pages.

## How to run me

This skill holds an ordered flow, not a knowledge book. The **orchestrator** owns phase
sequencing — GSD injects this skill into its agents, or the native `/demo:*` command set invokes
it; standalone, the skill's own lightweight harness guards the rung order and persists progress to
`.demo/<slug>/flow-state.json`. The orchestrator abstraction is owned by
[`../dw-demo-base/references/orchestrator.md`](../dw-demo-base/references/orchestrator.md), whose
**Polish** acceptance criterion is what this ladder exists to satisfy.

## The rule this whole skill descends from

> **A field you never wrote renders plausible stock copy. The absence of a defect is not evidence
> of content.**

Swift ships demo copy in the `defaultValue` attribute of nine of its most-used content item types.
A paragraph created — or re-saved — without an explicit value for those fields inherits them, so a
page can look authored while carrying nothing anyone wrote for this customer. Nothing errors,
nothing renders empty, and a liveness gate goes green. That is why the zero-state pass is **rung 1
of a numbered ladder and not a row in a lookup table**: it is not troubleshooting, it is a build
step that must run on every demo, and it must run again after any bulk paragraph save.

## The presentability ladder (walk in order, gate each rung)

Each rung has an owner and an assert. Do not advance on a rung whose assert has not been observed
to pass. Rungs 1-3 are content truth; 4-6 are design; 7-8 are proof.

| # | Rung | Owner | Gate |
|---|---|---|---|
| **1** | **Zero-state pass** — strip the stock, resolve the empty bands, de-brand the chrome | **[references/zero-state.md](references/zero-state.md)** | tripwire regex returns 0 hits across every demo-critical page, in `textContent`; no empty band; no `Swift` wordmark or favicon |
| **2** | **Content replacement** — real copy in every field the storyline visits, modelled one field per editor concern | [`../dw-demo-swift/references/content-modeling.md`](../dw-demo-swift/references/content-modeling.md) | every visited page's headings and body come from the customer's own material; no field left to its default |
| **3** | **Imagery** — where product and content images actually come from | **[references/product-imagery.md](references/product-imagery.md)** (the source); [`../dw-demo-swift/references/asset-organisation.md`](../dw-demo-swift/references/asset-organisation.md) (where they go) | every `<img>` on a demo-critical page resolves 200; hero-category PLP >= 80% real images; every remaining card shows the **branded** fallback, never the stock grey tile |
| **4** | **Theme tokens** — palette, typography, buttons, radius, shadow | [`../dw-demo-swift/references/styles-assets.md`](../dw-demo-swift/references/styles-assets.md) + [`../dw-demo-swift/references/re-skin.md`](../dw-demo-swift/references/re-skin.md) | the palette swap is complete across every notation (a swap is multi-file and multi-notation — `re-skin.md`) |
| **5** | **Chrome and rhythm** — header that reads as a menu, section gaps, band caps | [`../dw-demo-swift/references/header-menu.md`](../dw-demo-swift/references/header-menu.md) + [`../dw-demo-swift/references/re-skin.md`](../dw-demo-swift/references/re-skin.md) | top nav nodes have children (a childless bar is a data gap, not a CSS defect); no band over the height cap; no dead gap over the section-gap threshold |
| **6** | **Mobile pass** — fit the phone canvas | [`../dw-demo-swift/references/mobile-pass.md`](../dw-demo-swift/references/mobile-pass.md) | `document.body.scrollWidth <= innerWidth` at 390 **and** 430, measured with a real mobile device descriptor |
| **7** | **Mechanical asserts** — the whole ladder, re-proven by machine on every run | **[references/design-gate.md](references/design-gate.md)** + [`assets/gate.config.template.json`](assets/gate.config.template.json); detectors and reading discipline in [`../dw-demo-base/references/visual-qa.md`](../dw-demo-base/references/visual-qa.md) | the design leg runs and reports PASS/FAIL — never SKIP — from the **first** gate run of the demo, and that first run is *supposed* to FAIL |
| **8** | **Human taste sign-off** — stamped, non-blocking | [`../dw-demo-base/references/orchestrator.md`](../dw-demo-base/references/orchestrator.md) "Design sign-off" | a sign-off artifact exists; until it does the leg stamps SKIP, never FAIL |

### Why the order is the order

- **1 before 2.** Replacing copy on a page that still carries stock bands means authoring around
  furniture that is about to be deleted. Strip first, then write.
- **1 before 4.** Theme tokens applied over stock content produce a well-branded template. The
  prospect reads the copy before the palette.
- **1 again after any bulk save.** A single grid-row save re-applies item-type defaults to
  paragraphs whose fields were blanked by hand. Rung 1's assert is the only thing that catches
  it, which is why it is an assert and not a checklist.
- **7 from run one, not from the re-skin pass.** A gate that arms its design leg only once
  someone starts styling measures liveness for the whole first half of the build. The design leg
  must be configured before the first gate run, so that run FAILs honestly on a raw deserialize.

## Rung 7 is an asset, not a paragraph

The acceptance criteria in `orchestrator.md` **already** demand a mechanical visual-QA gate on
every demo-critical page, and `visual-qa.md` already carries the detectors. Nothing about the
prose is wrong. What is missing is the **executable** form: a runnable design profile that arms
from run one with no per-demo authoring. Restating the criterion in more prose changes nothing —
`orchestrator.md` says so itself:

> "a gate written as a validator holds at every tier; the same gate written as three more
> paragraphs of prose holds only at the top one."

So the fix for a rung that keeps getting skipped is always the same shape: ship the artifact the
gate reads, not another sentence telling someone to write one. That artifact is
[`assets/gate.config.template.json`](assets/gate.config.template.json); the discipline for editing
it is [references/design-gate.md](references/design-gate.md).

## Known gaps (named, so they are not rediscovered)

Five presentability asserts have no probe in the runner and therefore cannot be armed by config
alone: **image resolution** (a referenced-but-missing image survives every leg), **alt text**,
**empty-band child counts**, the **brand tripwire** (wordmark and favicon), and the **mobile canvas
measure** (`body.scrollWidth`, which `overflow-x: hidden` hides from a `documentElement` check).
They are named with their implementation shape in
[references/design-gate.md](references/design-gate.md) "What it does NOT assert". Do not add config
keys for them until the runner reads them — an unread key is a config that looks armed and executes
nothing.

## Sister skills

- **`dw-demo-base`** — foundation (Use FIRST). Owns setup, MCP, guardrails, the orchestrator
  abstraction, and `visual-qa.md`.
- **`dw-demo-swift`** — Swift frontend (Use BEFORE this skill). Owns the baseline deserialize,
  paragraph and template mechanics, and the reference files rungs 2-6 route to. This skill never
  duplicates them; it orders them.
- **`dw-demo-pim`** — product data. Rung 3's imagery attaches to products PIM owns.

## Inherited from dw-demo-base

The customisations-ledger preflight, the read-only `customer-context\` contract, the
path-resolution rule and the surface-priority rule all apply here unchanged and are not restated
— see [`../dw-demo-base/SKILL.md`](../dw-demo-base/SKILL.md). Rung 1 in particular is
**configuration and content work, not custom code**: blanking a stock field and deleting a stock
paragraph are API writes, and neither needs a `.cs` file.
