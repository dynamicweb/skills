# mobile-pass.md

> The mobile pass for a Swift 2.4 demo: how to prove the storefront actually fits the phone canvas, the recurring traps that stretch it, and the Distribution-state caveat that makes most of this a *verification*, not a re-derivation. Companion to [`re-skin.md`](re-skin.md) (the Tier-1 `<customer>_custom.css` slot every fix below lands in) and the visual-QA gate in [`../../dw-demo-base/references/visual-qa.md`](../../dw-demo-base/references/visual-qa.md) (the mechanical breakpoint asserts).
>
> Swift 2.x only — never follow `/swift/swift-1/` URLs.

## Verify first — do NOT re-derive the mobile CSS

**theme-default ≥1.2.0 already ships, structurally, every fix in this file** — mobile mega-menu category strip below lg, `NColumnsFlex`/footer wrap below md, `!important` PLP column bases, force-opened two-column spec rows, logo clamp 210→150px below md. On a current Distribution (consume on `main`; see [`deserialize-flow.md`](deserialize-flow.md)) the mobile pass is a **verification** run, not a re-skin: run the canvas-fit method below, confirm the traps are already handled, and patch only the *delta* your specific catalog/photography introduces. Re-applying an older demo's `<customer>_custom.css` blocks on top of a 1.2.0 theme double-fixes and risks fighting the shipped rules. Only when the demo pins an older theme-default (or a trap below survives at 390) do you author the fix into `<customer>_custom.css` as a Tier-1 item. A demo that predates the fold keeps its own custom CSS — do not copy those blocks to new demos.

**The pass needs a browser runner, and no skill ships one.** Every measurement below reads the live DOM at a device descriptor, so a session with no browser instrument attached cannot run any of it. That case has one correct outcome: record the viewport leg as **UNPROVEN** in the report and name what is missing. A gate run that stamps PASS on an unmeasured viewport leg is the defect the leg exists to catch ([`re-skin.md`](re-skin.md) "An assert that cannot fail is not an assert").

## The debugging method that works

1. **Measure the canvas AND the viewport — three numbers, not one.** `overflow-x: hidden` on `body` hides horizontal stretch from `documentElement.scrollWidth`, so probe **`document.body.scrollWidth`**; but `body.scrollWidth <= innerWidth` alone certifies a broken page too, because once the browser widens the layout viewport to fit unshrinkable content the two are equal **by construction** — measured `body.scrollWidth 652 | innerWidth 652 | requested 390`, a 262px stretch reported as zero. Assert **`innerWidth === requested` AND `body.scrollWidth === innerWidth`** at every descriptor. Measured on one storefront: the canvas was 1356px at 390 and the symptom read as "missing PLP images" — a stretched canvas painting lazy-loaded images in the blank right margin, not a lazy-load bug.
2. **Name the offender by RIGHT EDGE, not by width.** A width-sorted walk reliably names an innocent element: a closed Bootstrap `.offcanvas` is `position: fixed; right: 0` translated off-screen, so its used position resolves against the already-widened scroll area and it tracks the overflow while contributing nothing to it — and at a full viewport wide it outranks the real offender in every width-sorted list. The offender is the element whose **right edge equals `documentElement.scrollWidth`**; anything further right is out of flow and is a symptom. Two readings shortcut the hunt: the same `scrollWidth` at two different device widths means a **fixed-width box in normal flow**, so every responsive suspect is eliminated before any element is opened. Full diagnostic, probe shape and the recurring Swift causes: [`layout-verification.md`](../../dw-swift-building/references/layout-verification.md).
3. **Measure BOTH auth states.** Swift's mobile header renders a different my-account control per auth state — signed in a ~48px initials button, anonymous an anchor carrying a `text-nowrap` label whose min-content is ~123px — so a pass taken signed in does not measure the anonymous document. A signed-in sweep measured 0 on 10/10 checks and the anonymous sweep an hour later measured 71px at 390 and 49px at 412 on the same pages, unchanged in between; both were correct, and **the anonymous control is the wider one**. Every viewport pass owes both states.
4. **Probe with a real device user-agent, not just a 390 viewport.** Dynamicweb serves two different header content pages and selects between them **server-side by user-agent**: a phone UA gets a 2-row (~84px) header carrying `swift-v2_offcanvasnavigation`, a desktop UA **at the same 390px width** gets a 3-row (~177px) header carrying `swift-v2_menurelatedcontent`. A headless run at 390 with the default desktop UA is measuring a document no phone ever receives — that is how a ~94px dead band under the header survived four consecutive design-gate passes that each measured 1px of clearance. Set a real device descriptor on every mobile probe (and keep a desktop-UA control at the same width, because a narrow desktop browser legitimately gets the 3-row header). Any clearance token keyed on a breakpoint rather than on the served DOM is wrong for one of the two documents — the fix is in [`re-skin.md`](re-skin.md) §"Floating / overlay header".
5. **Finish on a real phone.** The emulated 390 pass is necessary but **not sufficient**. A clean 390 pass has missed a per-row alignment bug that a real-device screenshot caught instantly: at 430 the CTA fit inline, at 390 it wrapped — but only on rows with long SKUs, so some pills sat left and some right. Emulator proves the canvas fits; a real device (or at minimum a **390 + 430 screenshot pair**) proves rows stay consistent across the wrap boundary.

## The traps (likelihood order for any Swift 2.4 demo)

Each fix is a Tier-1 `<customer>_custom.css` item **only if the shipped theme doesn't already handle it** — verify against theme-default ≥1.2.0 first (see above).

- **Fixed-width mega-menu.** `swift-v2_menurelatedcontent` renders `.nav-wrapper.megamenu-wrapper` at desktop width on **every** viewport; below lg it stretches the canvas (1282px measured). Constrain it below lg — a scrollable category strip, or replace with a burger/offcanvas nav. This is the single biggest canvas-stretcher; fix it first.
- **`NColumnsFlex` rows don't wrap below md.** Footer / USP rows keep all columns on one line at 390 (a footer row alone has stretched the canvas to 704px). Force wrap below md — wrap should be the *default* for these rows. **Related trap:** changing a row's `definitionId` without also setting `flexibleColumns` (an `int[]`) drops the responsive column classes entirely, silently un-wrapping a row that used to behave.
- **Bootstrap `.flex-fill` beats any flex base without `!important`** — desktop *and* mobile. `flex: 1 1 auto !important` on every grid column means any fixed base you set silently loses; columns grow with content and CTAs land at a different x per row. Enforce column bases with `!important`, give **repeated content fixed dimensions** (thumbnails as 56px squares), and **right-anchor the trailing pill** (`margin-left: auto` + `justify-content: flex-end`) so it aligns right whether it fits inline or wraps — this is what defeats the 430/390 pill-drift.
- **Spec accordions are collapsed by default** and hide the PDP story — the field-display groups render nothing until tapped. Force-open scoped to `swift-v2_productfielddisplaygroupsaccordion`, and restyle `li > strong + span` as two-column spec rows (headless style).
- **Logo lockup width is inline-hardcoded** (~210px `figure`). Clamp to ~150px below md — and style the `figure` / `svg`, **not** `figure img`: inline-SVG logos carry no `<img>` hook, so an `img`-targeted rule silently misses them.
- **A no-crop hero sized to the image aspect-ratio overflows at 390.** Setting the hero band to the photo's own `aspect-ratio` (so nothing is cropped) is fine on desktop and breaks on the phone: at 390 the band is only ~`vw / ratio` tall (~257px for a 1.5:1 image) while the overlaid copy block is ~360px, so a centered grid overlay (`align-content: center`) spills out **both** ends — the H1 pushed off the top, the CTAs landing in the next section. Below ~640px stop overlaying: put the figure in-flow at its own aspect-ratio (grid row 1), let the copy flow beneath it (row 2) on a solid brand surface for legibility, and restore the header clearance so the hero starts below a floating bar. Keep the overlay at ≥640px where the band is tall enough. Verify by measuring, not eyeballing: the subject's `top` must sit below the header's `bottom`, and every CTA must be inside the section.
- **One wide element inside the product long description widens the whole layout viewport.** Swift wraps the long description in `.mw-75ch.d-inline-block`, which sizes to `min(max-content, max-width)` — so a single wide table, `pre` or image inside authored content forces a ~600px box into a 390px viewport, and the element's own `.table-responsive` wrapper cannot rescue it because ITS width is set by that oversized parent. `75ch` is a typographic MAXIMUM, so `@media (max-width: 991.98px) { .mw-75ch { max-width: 100% } }` is strictly correct and belongs upstream in the shipped sheet. Measure the pages that carry authored HTML; every other page on the site can measure exactly 390 while one product page measures 413.
- **An `auto-fit` grid override under Bootstrap `g-col-N` children.** Replacing a Swift row's `repeat(12, 1fr)` with `repeat(auto-fit, minmax(<n>px, 1fr))` while the children keep `g-col-12` manufactures eleven zero-width implicit tracks and still charges the gap between them — a used width of `minmax-floor + 11 × gap` that does not depend on the viewport at all. Keep the span classes and an explicit track count together, or remove both ([`layout-verification.md`](../../dw-swift-building/references/layout-verification.md)).
- **A theme cap written for one slider variant collapses the full-bleed hero to a strip** — see [`re-skin.md`](re-skin.md) §"Overriding Swift/Bootstrap-managed layout" for the scoping rule and the absolute-overlay clipping that follows it at phone widths.
- **Anon B2B "sign in for pricing" CTA lives in `swift-v2_productPRICE`**, not `swift-v2_productaddtocart` (which renders a narrow stub). Selectors targeting the CTA via add-to-cart miss it entirely — target `productPRICE` when styling or probing the anon price affordance.

## The mobile performance pass: read the insight before acting on it

Two rules that keep a Lighthouse-driven perf pass from spending its budget on a no-op.

**A hero preload is a no-op when `lcp-discovery-insight` already scores 1.** The standing advice
("preload the LCP image, its request cannot start until the blocking CSS is down") is wrong about the
mechanism: the preload scanner discovers `<img srcset>` during HTML parse, and blocking CSS delays
**paint**, not **discovery**. Read `lcp-discovery-insight` (`priorityHinted` / `requestDiscoverable` /
`eagerlyLoaded`) and `lcp-breakdown-insight` first. On the measured build all three were already true
and the breakdown was `resourceLoadDelay` 56ms against `elementRenderDelay` 230ms, so the fix was
render-blocking bytes and a preload could have moved the request at most ~133ms earlier while
competing for the same pipe. A mismatched preload also shows up as a **double download**, so assert
the hero is requested exactly once.

**Below-fold EAGER images cost more LCP than every insight row Lighthouse ranks above them.** Standard
`Paragraph/Swift-v2_Slider/CardCoverNavInline.cshtml` emits its card `<img>` with neither
`loading="lazy"` nor a quality override. Four cards sitting at y=1238 on a 390x844 phone, all below the
fold, shipped eager at quality 95: ~150 KB of a ~447 KB critical window, issued at the same millisecond
as the LCP hero, over one 1.6 Mbps pipe. Lighthouse credits the compression saving but **has no audit
that models bandwidth contention from below-fold eager images**, so it ranked "improve image delivery"
last, behind render-blocking and unused CSS. The fix moved mobile Performance 86 to 93 in one step,
LCP 3.60s to 2.73s.

The fix is a **net-new Custom-lane copy** of the standard template (leave the standard file untouched)
adding `loading="lazy" decoding="async"` and a Quality override, with the paragraph repointed via
`ParagraphSave` and the previous template recorded so the change is reversible. Do **not** add
`width`/`height` attributes to a CSS-sized card (`h-100` + a `min-height` with `object-fit: cover`):
the attribute-derived aspect-ratio fights the cover fit. The design gate must scroll-sweep so lazy
images still measure honestly. The layer-side ask, shipping the `loading` attribute in the standard
template, is an upstream request against `theme-default`, not a per-demo edit.

## Gate implication

A single-width pass ships a broken mobile view. The design gate must:

- **Run every mobile assert under a real device UA descriptor** (see method step 3) with a same-width desktop-UA control — otherwise the gate is measuring the desktop header document at phone widths and will certify a layout no phone receives.
- **Assert `innerWidth === the requested width` AND `document.body.scrollWidth === innerWidth` at 390** (body, not documentElement — `overflow-x: hidden` masks the stretch otherwise; and the `innerWidth` leg is what catches a widened layout viewport, which makes the equality trivially true). **Report the element whose right edge equals `documentElement.scrollWidth`** on every failure, so a red row is attributable instead of a bare pixel count. This is the mechanical canvas-fit bar.
- **Run every page in BOTH auth states** (method step 3) — the anonymous header is the wider document, so a signed-in-only pass certifies a layout no visitor receives.
- **Adjudicate overflow by measurement, never from a capture.** A full-page phone screenshot cannot distinguish a genuine stretch from a Bootstrap off-canvas panel parked off-screen by design, and a carried-forward "the canvas stretches" finding taken from a screenshot set has measured as **not reproducing** on 19 of 20 pages while the one real offender sat on a page the screenshots never covered.
- **Take a 390 + 430 screenshot pair** (or finish on a real device) — two widths catch the per-row wrap-state divergence a single width cannot. A storefront has shipped **14/14 portal smoke + all probes green** while a 430/390 pill-alignment bug was still live; only the screenshot pair caught it.

The base visual-QA gate owns the mechanical asserts and the breakpoint discipline — see [`../../dw-demo-base/references/visual-qa.md`](../../dw-demo-base/references/visual-qa.md) ("Breakpoints" + "Definition of done"). This file owns the *why* and the trap catalogue; that file owns the pass/fail.
