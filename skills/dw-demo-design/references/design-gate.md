# The design gate — arming it on run one

> Rung 7 of the presentability ladder. Owns the runnable design profile
> ([`../assets/gate.config.template.json`](../assets/gate.config.template.json)) and the
> discipline for editing it.

## Contents

- [Why an asset and not more prose](#why-an-asset-and-not-more-prose)
- [The arming rule](#the-arming-rule)
- [Wiring it up](#wiring-it-up)
- [Two calibrations you must not skip](#two-calibrations-you-must-not-skip)
- [What the profile asserts today](#what-the-profile-asserts-today)
- [What it does NOT assert — named harness gaps](#what-it-does-not-assert--named-harness-gaps)
- [Proving a key is live](#proving-a-key-is-live)
- [Threshold discipline](#threshold-discipline)

## Why an asset and not more prose

The acceptance criteria in
[`../../dw-demo-base/references/orchestrator.md`](../../dw-demo-base/references/orchestrator.md)
**already** require a mechanical visual-QA gate on every demo-critical page, and
[`../../dw-demo-base/references/visual-qa.md`](../../dw-demo-base/references/visual-qa.md) already
carries the detectors and the reading discipline. Nothing about that prose is wrong, and restating
it changes nothing:

> "a gate written as a validator holds at every tier; the same gate written as three more
> paragraphs of prose holds only at the top one."

What was missing is the **executable** form — a runnable profile that arms with no per-demo
authoring. That is what this file ships.

## The arming rule

**Arm the design leg before the first gate run of the demo, not at the re-skin pass.**

A leg configured only once someone starts styling reports SKIP for the entire first half of the
build. That is how a raw deserialize carrying horizontal overflow on every page, skeleton-card
bands, an empty FAQ and stock copy site-wide reaches an overall PASS: the legs that ran measured
liveness, and the leg that would have measured presentability was not configured. The defect class
then surfaces one or more briefs later, found by a human eyeballing the site — the exact failure
mode a mechanical gate exists to end.

**The first armed run is supposed to FAIL.** That is the point. A profile that goes green against
an un-customised baseline is measuring nothing.

## Wiring it up

1. Copy [`../assets/gate.config.template.json`](../assets/gate.config.template.json) to the demo
   root as `gate.config.json`.
2. Replace every `<...>` token: slug, base URL, area URL segment, hero category, hero SKU, and the
   customer stylesheet filename.
3. Set `design.runnerPath` to the design-probe runner the harness ships.
4. Run the gate. Record the failures — they are rungs 1-6's worklist, in priority order.

Keys prefixed with `_` are notes and are ignored by the runner. Keep them: a threshold with no
recorded reason is indistinguishable from a weakened one six weeks later.

## Two calibrations you must not skip

**1. A viewport is not a device.** Dynamicweb picks the header **server-side by user-agent**. A
390x844 viewport driven with the default headless desktop UA renders a document no phone user ever
receives. Four consecutive gate PASSes were measured against the wrong document that way, and a
mobile header height was then correctly fitted to a page nobody sees. The template spreads a
Playwright **device descriptor** (UA + `isMobile` + `hasTouch` + DPR) *before* the explicit
geometry, so the geometry still wins — and asserts `expectMobileHeader` against the **served
artefact** (the offcanvas-nav marker), not against the setting that was requested. If the server
ever stops UA-sniffing, or a later edit drops the descriptor, that fails loudly instead of
silently reverting the whole gate to the desktop page.

**2. Scan `textContent`, not `innerText`.** `innerText` is render-aware and omits collapsed
accordion panels and inactive tabs — which is exactly where stock copy lives. On one measured page
`innerText` returned 2,270 chars with 0 matches while `textContent` returned 9,544 with 7.
Attribute values appear in neither, which is why `\bplaceholder\b` is safe in the design regex and
unsafe in a markup scan.

## What the profile asserts today

Always-on in the runner, no config needed:

| Assert | Catches |
|---|---|
| `overflowX` — `documentElement.scrollWidth <= clientWidth` at every viewport and page | horizontal overflow, with the widest offender named |
| image band height vs `maxBandHeightFraction` | a hero or card image eating the viewport |
| stretched images (rendered aspect diverging >15% from natural with `object-fit: fill`) | squashed thumbnails |
| section gaps vs `sectionGapThreshold` | dead whitespace where a paragraph was deleted |
| `placeholderRegex` over rendered text | stock copy, corporate ipsum, generic filler |
| PLP `rowSelector` + `minRows` + per-row `requiredFields` | a PLP with the right card count and no thumbnail, SKU or price on any of them |
| mojibake signature | double-encoded UTF-8 in live copy |

Config-driven, all armed by the template:

| Key | Asserts |
|---|---|
| `cookies` | consent pre-seeded, so screenshots are of the page and not of the consent dialog |
| `mobileMarker` + `expectMobileHeader` | the served document matches the device that asked for it |
| `clearance` | header-bottom to first-content-top, as a relationship rather than a pixel |
| `contrast` | WCAG AA on links, buttons and CTAs |
| `ctas` | the CTA exists **and is button-shaped** (height, width, background/border, contrast) |
| `requiredSections` | named PDP sections present **and rendered tall enough to hold content** |
| `docHeight` | one component rendering the page to absurd length |
| `textOverlap` | colliding text rects |
| `cssom` | each shipped stylesheet block actually **parsed** into `document.styleSheets` |

## What it does NOT assert — named harness gaps

These are runner changes, not config. **Do not add a key for them to the config and assume it
runs** — an unread key is a config that reads as armed and executes nothing, which is worse than
an honest gap. Name the gap here; implement it in the runner; then add the key.

| Gap | Why it matters | Shape when implemented |
|---|---|---|
| **Image resolution** — no probe asserts that an `<img>` returns 200 | A referenced-but-missing hero survives every leg. Worse, the stretched-image probe explicitly skips any image with `naturalWidth === 0`, so a **broken** image is excluded from the one probe that looks at images at all. This is why missing imagery can survive an all-green run | every `<img>` rendered in `main` resolves 200; report the failing `src` |
| **Alt text** | Zero alt text ships on the stock surface, and nothing observes it | every `main img` has a non-empty `alt` |
| **Empty bands** | An accordion, slider or post-list container with zero children renders as skeletons under a real heading and passes presence, geometry, gap and text checks simultaneously | for each such container in `main`, count item children; fail on zero |
| **Brand tripwire** | The vendor wordmark and the vendor favicon are the two surfaces read before any content, and neither is text the placeholder regex can see (the favicon is an attribute) | header/footer contain no vendor wordmark; `link[rel~="icon"]` / `link[rel="apple-touch-icon"]` do not resolve under the vendor design-package assets folder |
| **Mobile canvas measure** | `overflowX` reads `documentElement`. Swift ships `overflow-x: hidden` on `body`, which clips that measure — a document stretched to well over the viewport at 390 can still report zero overflow | additionally assert `document.body.scrollWidth <= innerWidth` at mobile, and finish at **390 and 430** (a CTA that fits inline at 430 but wraps at 390 leaves rows inconsistently anchored) |

The first four are the executable form of `references/zero-state.md`'s assert reference; the fifth
is the calibration `visual-qa.md` already documents in prose.

## Proving a key is live

**Never write a note asserting a guard you have not read in the config this session.** A comment
claiming a tripwire that does not exist is worse than no comment: a live stylesheet once carried a
comment asserting a clearance guard that had never been added to the config — it had been added to
a one-off run script and the comment recorded the *intent* as though it were standing. The same
defect then recurred on two more pages, each fixed by hand, while every gate leg stayed green.

Two techniques, both cheap:

- **Observe it fail.** Before trusting a new assert, break the thing it guards and watch the leg
  go red. An assertion never observed to fail is not evidence.
- **Self-test the detectors.** Inject known-bad markup on every run — a lorem string, an
  overlapping text pair, a zero-height CTA — and require the detectors to fire on it. That is the
  only check that catches a detector which silently stopped matching after a DOM change.

And the corollary worth acting on: **the same fix applied by hand on a fourth page is the tell that
it belongs in the config, not in a run script.**

## Threshold discipline

- **A raised threshold carries its reason, in the config, next to the number.** `0.85 -> 1.08` on
  `maxBandHeightFraction` is either a deliberate full-bleed hero or a weakened assert, and nothing
  but the note distinguishes them.
- **Never relax an assert to make room for a new one.** When adding a key, state explicitly that
  nothing was weakened, narrowed, deleted or re-thresholded — and mean it.
- **An assert that fires on good copy is a broken assert, not a strict one.** Retire the single
  colliding alternative and record why; do not weaken the band.
- **A workaround block must name the condition that retires it.** A threshold fitted around a
  known layer defect should say which layer version removes the need for it.
