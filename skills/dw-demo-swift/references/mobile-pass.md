# mobile-pass.md

> The mobile pass for a Swift 2.4 demo: how to prove the storefront actually fits the phone canvas, the recurring traps that stretch it, and the Distribution-state caveat that makes most of this a *verification*, not a re-derivation. Companion to [`re-skin.md`](re-skin.md) (the Tier-1 `<customer>_custom.css` slot every fix below lands in) and the visual-QA gate in [`../../dw-demo-base/references/visual-qa.md`](../../dw-demo-base/references/visual-qa.md) (the mechanical breakpoint asserts).
>
> Swift 2.x only — never follow `/swift/swift-1/` URLs.

## Verify first — do NOT re-derive the mobile CSS

**theme-default ≥1.2.0 already ships, structurally, every fix in this file** — mobile mega-menu category strip below lg, `NColumnsFlex`/footer wrap below md, `!important` PLP column bases, force-opened two-column spec rows, logo clamp 210→150px below md. On a current Distribution (consume on `main`; see [`deserialize-flow.md`](deserialize-flow.md)) the mobile pass is a **verification** run, not a re-skin: run the canvas-fit method below, confirm the traps are already handled, and patch only the *delta* your specific catalog/photography introduces. Re-applying the marine `<customer>_custom.css` blocks on top of a 1.2.0 theme double-fixes and risks fighting the shipped rules. Only when the demo pins an older theme-default (or a trap below survives at 390) do you author the fix into `<customer>_custom.css` as a Tier-1 item. `marine-demo` keeps its own custom CSS because it predates the fold — do not copy it to new demos.

## The debugging method that works

1. **Measure the canvas, not the viewport.** `overflow-x: hidden` on `body` hides horizontal stretch from naive probes — a stretched document reads as "fine" to a viewport check. Probe **`document.body.scrollWidth`** (NOT `document.documentElement.scrollWidth` — the `<html>` element is clipped by the body's `overflow-x`) at **390** and **1440**; pass = exactly viewport-wide (`body.scrollWidth <= innerWidth`). On marine the canvas was **1356px at 390** and the symptom read as "missing PLP images" — it was a stretched canvas with broken lazy-load painting in the blank right margin, not a lazy-load bug.
2. **Find the widest offender, iteratively.** Walk `[...document.querySelectorAll('*')].filter(e => e.scrollWidth > innerWidth)` and fix the **widest first** — each fix uncovers the next. Marine's chain was mega-menu (1282px) → footer rowflex (704px) → PLP SKU column (298px). Do not batch-guess; the widest element is the one actually setting the canvas width.
3. **Finish on a real phone.** The emulated 390 pass is necessary but **not sufficient**. Marine's 390 pass missed a per-row alignment bug a real-device screenshot caught instantly: at 430 the CTA fit inline, at 390 it wrapped — but only on rows with long SKUs, so some pills sat left and some right. Emulator proves the canvas fits; a real device (or at minimum a **390 + 430 screenshot pair**) proves rows stay consistent across the wrap boundary.

## The traps (likelihood order for any Swift 2.4 demo)

Each fix is a Tier-1 `<customer>_custom.css` item **only if the shipped theme doesn't already handle it** — verify against theme-default ≥1.2.0 first (see above).

- **Fixed-width mega-menu.** `swift-v2_menurelatedcontent` renders `.nav-wrapper.megamenu-wrapper` at desktop width on **every** viewport; below lg it stretches the canvas (1282px on marine). Constrain it below lg — a scrollable category strip, or replace with a burger/offcanvas nav. This is the single biggest canvas-stretcher; fix it first.
- **`NColumnsFlex` rows don't wrap below md.** Footer / USP rows keep all columns on one line at 390 (marine's footer alone stretched the canvas to 704px). Force wrap below md — wrap should be the *default* for these rows. **Related trap:** changing a row's `definitionId` without also setting `flexibleColumns` (an `int[]`) drops the responsive column classes entirely, silently un-wrapping a row that used to behave.
- **Bootstrap `.flex-fill` beats any flex base without `!important`** — desktop *and* mobile. `flex: 1 1 auto !important` on every grid column means any fixed base you set silently loses; columns grow with content and CTAs land at a different x per row. Enforce column bases with `!important`, give **repeated content fixed dimensions** (thumbnails as 56px squares), and **right-anchor the trailing pill** (`margin-left: auto` + `justify-content: flex-end`) so it aligns right whether it fits inline or wraps — this is what defeats the 430/390 pill-drift.
- **Spec accordions are collapsed by default** and hide the PDP story — the field-display groups render nothing until tapped. Force-open scoped to `swift-v2_productfielddisplaygroupsaccordion`, and restyle `li > strong + span` as two-column spec rows (headless style).
- **Logo lockup width is inline-hardcoded** (~210px `figure`). Clamp to ~150px below md — and style the `figure` / `svg`, **not** `figure img`: inline-SVG logos carry no `<img>` hook, so an `img`-targeted rule silently misses them.
- **Anon B2B "sign in for pricing" CTA lives in `swift-v2_productPRICE`**, not `swift-v2_productaddtocart` (which renders a narrow stub). Selectors targeting the CTA via add-to-cart miss it entirely — target `productPRICE` when styling or probing the anon price affordance.

## Gate implication

A single-width pass ships a broken mobile view. The design gate must:

- **Assert `document.body.scrollWidth <= innerWidth` at 390** (body, not documentElement — `overflow-x: hidden` masks the stretch otherwise). This is the mechanical canvas-fit bar.
- **Take a 390 + 430 screenshot pair** (or finish on a real device) — two widths catch the per-row wrap-state divergence a single width cannot. Marine shipped **14/14 portal smoke + all probes green** while the 430/390 pill-alignment bug was still live; only the screenshot pair caught it.

The base visual-QA gate owns the mechanical asserts and the breakpoint discipline — see [`../../dw-demo-base/references/visual-qa.md`](../../dw-demo-base/references/visual-qa.md) ("Breakpoints" + "Definition of done"). This file owns the *why* and the trap catalogue; that file owns the pass/fail.
