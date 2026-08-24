# Visual QA — reading a screenshot critically

A page that renders is not a page that is done. The recurring polish gaps on demo storefronts — oversized whitespace bands, misaligned or stretched images, dead slider arrows, horizontal scrollbars — are all visible in a screenshot *when you hunt for them*. This file owns the hunt: the programmatic detectors to run before eyeballing, the checklist to read every screenshot against, the interaction pass a static screenshot cannot replace, and the routing table from visual symptom to owning fix. The verify-flow mechanics (login, walk, where screenshots land) stay in [`browser-automation.md`](browser-automation.md); this file owns what *done* looks like.

## Contents

- [The mindset rule](#the-mindset-rule)
- [Breakpoints — capture both, always](#breakpoints--capture-both-always)
- [Programmatic detectors — run before eyeballing](#programmatic-detectors--run-before-eyeballing)
- [PLP list — assert rows AND per-row content](#plp-list--assert-rows-and-per-row-content)
- [Assert design rules — what a green assert does not prove](#assert-design-rules--what-a-green-assert-does-not-prove)
- [Authoring detector scripts — traps that pass silently](#authoring-detector-scripts--traps-that-pass-silently)
- [Interaction pass — a screenshot cannot verify behaviour](#interaction-pass--a-screenshot-cannot-verify-behaviour)
- [The eyeball checklist](#the-eyeball-checklist)
- [Symptom → owning fix (route findings, don't re-diagnose)](#symptom--owning-fix-route-findings-dont-re-diagnose)
- [The fix loop](#the-fix-loop)
- [Definition of done (per demo-critical page)](#definition-of-done-per-demo-critical-page)
- [The eyeball pass is also the PII pass](#the-eyeball-pass-is-also-the-pii-pass)

## The mindset rule

Treat every screenshot as a **defect hunt, not a confirmation**. An entity-count check ("N order rows visible") proves the data landed; it says nothing about polish. Score each demo-critical page against this file before declaring it done — "it renders" is the bar for seeding; **"nothing left to fix" is the bar for a demo**.

Order of operations per page: scroll-sweep (lazy-load — see `browser-automation.md` verify-flow step 5) → programmatic detectors → interaction pass → screenshot at both breakpoints → eyeball checklist → route findings → fix → re-run. The detectors go first because they are deterministic and catch exactly the defects eyes skim past in a thumbnail-sized render of a long page.

## Breakpoints — capture both, always

Capture and check at minimum two widths via `browser_resize`: **desktop (1440 or 1920)** and **mobile (390)**. Most overflow, stacking, and touch-target defects only exist at one of the two — a desktop-only pass routinely ships a broken mobile view, and demos get projected at both.

**On mobile, measure the *canvas*, not the viewport.** `overflow-x: hidden` on `body` — which Swift ships — hides horizontal stretch from a viewport check: a document stretched to 1356px at 390 still reports a clipped `documentElement`. Assert **`document.body.scrollWidth <= innerWidth` at 390** (the detector below carries `bodyCanvas` for exactly this). And a single 390 pass is not enough for per-row alignment: a CTA that fits inline at 430 but wraps at 390 — only on rows with long content — leaves some trailing pills left-anchored and some right. **Screenshot at 390 AND 430** (or finish on a real device); two widths catch the wrap-state divergence one width cannot. The Swift-specific canvas-stretch traps (fixed-width mega-menu, non-wrapping `NColumnsFlex` rows, `.flex-fill` beating fixed bases) and their fixes live in [`../../dw-demo-swift/references/mobile-pass.md`](../../dw-demo-swift/references/mobile-pass.md).

## Programmatic detectors — run before eyeballing

One `browser_evaluate` call returns the mechanical findings. Adjust the section selector to the page's actual container structure when the generic one returns nothing useful:

```js
() => {
  const de = document.documentElement, vw = de.clientWidth;
  // overflowX reads documentElement; bodyCanvas reads body.scrollWidth — the latter is the ONLY one that
  // survives `overflow-x:hidden` on body (Swift ships it), which masks a stretched canvas from de.scrollWidth.
  const out = { overflowX: Math.max(0, de.scrollWidth - vw), bodyCanvas: Math.max(0, document.body.scrollWidth - vw), offenders: [], broken: [], stretched: [], tall: [], gaps: [] };
  const vh = window.innerHeight, bandCap = 0.85 * vh; // 0.85 = the demo's configured band-cap fraction
  // 1. Horizontal-overflow offenders — the element whose right edge IS the scrollbar
  for (const el of document.querySelectorAll('body *')) {
    const r = el.getBoundingClientRect();
    if (r.width > 0 && (r.right > vw + 1 || r.left < -1))
      out.offenders.push({ tag: el.tagName, cls: String(el.className).slice(0, 60), right: Math.round(r.right) });
  }
  // 2. Broken + distorted images (only valid AFTER the scroll-sweep)
  for (const img of document.images) {
    if (!img.complete || img.naturalWidth === 0) { out.broken.push(img.currentSrc || img.src); continue; }
    const r = img.getBoundingClientRect();
    if (r.width > 20 && r.height > 20) {
      const nat = img.naturalWidth / img.naturalHeight, ren = r.width / r.height;
      if (Math.abs(nat - ren) / nat > 0.15 && getComputedStyle(img).objectFit === 'fill')
        out.stretched.push(img.currentSrc || img.src);
      // Oversized band — a tall crop rendered full-height (object-fit:cover, no cap) dominates the fold.
      // This is a DIFFERENT defect from `stretched`: aspect is fine, the band is just too tall.
      const wrap = img.closest('figure, picture') || img, wr = wrap.getBoundingClientRect();
      if (Math.max(r.height, wr.height) > bandCap)
        out.tall.push({ src: (img.currentSrc || img.src).slice(-60), px: Math.round(Math.max(r.height, wr.height)), cap: Math.round(bandCap) });
    }
  }
  // 3. Whitespace bands — gaps between consecutive top-level sections
  const secs = [...document.querySelectorAll('main > *, main section')]
    .map(s => s.getBoundingClientRect()).filter(r => r.height > 0).sort((a, b) => a.top - b.top);
  for (let i = 1; i < secs.length; i++) {
    const gap = Math.round(secs[i].top - secs[i - 1].bottom);
    if (gap > 120) out.gaps.push({ afterSectionIndex: i - 1, px: gap });
  }
  out.offenders = out.offenders.slice(0, 10); out.broken = out.broken.slice(0, 10); out.tall = out.tall.slice(0, 10);
  return out;
}
```

`tall` catches the recurring oversized image band — a portrait crop or slider cover-card rendered at full column-width height, uncapped, so it dominates the fold. It is a **distinct** finding from `stretched`: the aspect ratio is correct, the band is simply too tall. The stock image components carry no serialized height field, so a swapped-in photo reproduces it on every demo. The durable fix is a theme-CSS cap (`aspect-ratio` + `max-height` + `object-fit: cover` on the image wrapper and the slider cover-card), a Tier-1 re-skin item — route to `dw-demo-swift/references/re-skin.md`. Tune `bandCap` to the band the demo wants (a full-bleed hero legitimately fills the fold; a content-band image should not). Note that `tall` measures the **band**, not the subject framed inside it — a top-anchored cover-crop can pass it while the subject is clipped off the bottom edge; see "Assert design rules" below.

Pair it with two tool calls that catch the invisible failures:

- `browser_console_messages` — a template NRE or JS exception often renders as a *silently missing section* with no visual trace at all.
- `browser_network_requests` — 404s on images/CSS/JS explain "works on my walk" pages that break on a cold load.

Any non-empty finding is a defect until proven otherwise (the one sanctioned exception: `broken` images on a page that was **not** scroll-swept are a measurement artifact — sweep and re-run, per `browser-automation.md`).

## PLP list — assert rows AND per-row content

A list-mode product-list page (PLP) can return HTTP 200 while rendering **zero product rows** — an empty index, a not-yet-repopulated segment, a mis-scoped shop. HTTP 200 is the *seeding* bar ("it renders"); a **filled** list is the *demo* bar, and nothing catches the gap between them unless you assert it. Make row-presence and per-row content a mechanical check on every PLP, never an eyeball:

```js
(sel) => {
  const rows = [...document.querySelectorAll(sel.rowSelector)];
  const missing = rows.map((row, i) => ({
    i, absent: sel.fieldSelectors.filter(f => !row.querySelector(f))
  })).filter(r => r.absent.length);
  return { rows: rows.length, minRows: sel.minRows, empty: rows.length < sel.minRows, missing: missing.slice(0, 10) };
}
```

Feed it the page's real selectors (e.g. `{ rowSelector: '.list-item', minRows: 1, fieldSelectors: ['.thumbnail', '.sku', '.price', '[data-add-to-cart]'] }`). `empty: true` (fewer than `minRows`) or any `missing` entry is a **named finding**, never a pass: an empty or field-short list ships a broken demo behind a green status code. This makes the eyeball checklist's "product grid rendering zero tiles" row deterministic.

## Assert design rules — what a green assert does not prove

An assert earns its green only once it has been **observed to fail** against a state known to violate it. Everything below is a way a green assert lied on a page a human could see was wrong.

- **Observe every assert fail once — an unsatisfiable assert is indistinguishable from a passing one.** Selectors keyed on an item-type substring the platform never emits are unsatisfiable, not strict: `[data-dw-itemtype*="productdescription"]` cannot match `swift-v2_productlongdescription` ("productdescription" is not a substring of it), and a `*documents*` item type may not exist on the platform at all. Those four required-section asserts stayed RED for a full brief cycle and no amount of restoring content could turn them green; the mirror case — an assert that has never once been RED — is the dangerous one. Smoke-test a new assert against a page known to **satisfy** it *and* one known to violate it, and have the runner log, per assert, whether its selector matched zero elements on **every** page in the run.
- **Assert positively, by selector + count + measured shape; never the absence of a string.** A redesign was signed off on `count("Discover more") == 0`, which passed because the live copy read differently — the searched string was never going to appear — while all seven primary conversion CTAs were 19px underlined text links at contrast 1.14. Absence-of-text asserts are unfalsifiable: green when the fix landed *and* when nothing was ever there. Use a `cta-shape` assert instead — the group must match ≥ `minCount` elements AND every element must satisfy `height >= 40`, `width >= 44`, and (background alpha > 0.05 OR border ≥ 1px), plus an optional `minContrast`. It separates "the CTA is MISSING" (count short) from "the CTA is not button-shaped" (shape fail) and names each offender with its measured size and reason.
- **Key shape asserts on the conversion control, not on an href pattern.** `main a[href*="/shop/<category>/"]` conflates "the primary CTA" with "any anchor pointing at a product": a stretched-link over a figure and a model-name link inside an `h2` are deliberately invisible affordances that can never be button-shaped, so a planned image-and-title-link improvement had to be **cancelled** to keep the gate green. Narrow the selector to the actual controls (`main [data-dw-button]`, a marked text-CTA container) and give the invisible affordance its own *present-but-invisible* assert. Never satisfy the letter of a shape assert by handing a stretched-link a background alpha just over the threshold — that defeats the purpose the assert exists for.
- **A CSSOM marker proves parsing, not ownership.** A marker matched as a bare selector string against the whole document CSSOM stays green when its own block is deleted and a **later** block re-establishes the identical selector for a different purpose — the assert is honest about parsing and silent about attribution, so the next reader concludes a deleted block is live. Scope the marker to the byte range between the named sentinel pair in the fetched source, or point each marker at a rule the block still uniquely owns. Two-way test: deleting the owned rule must turn it red, and the same selector added by an unrelated later block must not turn it green.
- **Rendered height is invisible to present/aligned/parsed asserts — page height needs its own assert.** `required-section` ("exists and is ≥ 40px tall") is satisfied *harder* by a 9,476px section than by a correct 133px one; `section-gap` measures the space *between* sections, never the size *of* one; `overflowX` only measures X; a CSSOM census only proves rules parsed. One component rendered 9,476px tall and pushed a mobile page to 15,416px while **187 of 187** design asserts were green — found by hand-measuring, which is the failure the gate exists to end. Add `doc-height`: `document.documentElement.scrollHeight` per page per viewport against a cap set comfortably above the tallest legitimate page (fitting it just above today's maximum guarantees it gets quietly raised later). Prove the cap fires by re-running it below the current maximum.
- **A band-height assert never measures the framed subject.** Asserting the image *band* against a viewport fraction passes a top-anchored `object-fit: cover` crop that keeps the band under the cap while cropping the subject off the bottom edge — the measurement log records the poster box and `object-position` and no subject box at all. Add a subject bbox (luminance scan for the subject's topmost and bottommost row in a central band) and assert `subject.top > band.top` and `subject.bottom < band.bottom` at every viewport, so the geometry leg measures what the eye judges.
- **Geometry asserts never catch illegible text.** Band heights, section gaps and no-horizontal-scroll all pass on a list row whose product name wraps one word per line and paints across the description — three consecutive PASS runs (34 asserts) stepped over a row that had been broken for two days. Add a per-row legibility assert: the title rect must NOT intersect the sibling description rect AND the title line-count ≤ 2 (configurable), at every configured viewport, emitting both bounding boxes so a regression is diffable. Verify it on a deliberately-starved row (`flex: 0 0 <px>; flex-shrink: 0` on the description) before trusting it. The human sign-off leg is about taste and is not a substitute — this is a mechanical regression guard.
- **CSS clipping and rect-based overlap asserts are incompatible.** Clipping is a **paint** operation, not a layout one: rows scrolled out of a `max-height` + `overflow-y: auto` container still lay out in normal flow, so `getBoundingClientRect` reports them thousands of px down the document, straight through every section below — capping one 36-row component produced 13 desktop / 26 mobile phantom overlaps that no human can see. *A rect is not proof a pixel was painted* — the mirror of "bytes in a file are not proof a rule parsed". No CSS workaround exists: `content-visibility: auto` + `contain-intrinsic-size` measured **worse** (rows collapse to intrinsic size and pack more of them into the detector's midpoint bucket), `contain: paint|strict` does not remove descendant layout rects, and `display: none` on the overflow rows contradicts a "complete and scrollable" brief. Report the conflict and leave the assert honestly red; narrowing a detector to clear your own red assert is the anti-pattern the gate exists to prevent.
- **A flat top-level-section sort is blind to grid columns.** A detector that selects `main > *, main section`, flattens, sorts by `top` and differences consecutive rects never matches grid **columns** (Dynamicweb emits them as `div`) while it *does* match the nested sections inside a column — despite the doc comment saying "top-level sections". At desktop the columns sit side by side and nothing shows; at mobile they stack, so the space between one column's last nested row and the next matched section reads as a 600px dead band that is really a fully-populated gallery `div` nobody measured. **A gap that appears at one orientation only is the tell.** Fix the detector — honour the documented top-level contract, or skip any pair whose gap lies inside an already-counted ancestor's box — and never reshape a correct page to satisfy the instrument.
- **An `innerText` content tripwire is blind to collapsed accordions and inactive tabs** — which is exactly where CMS boilerplate lives. `document.body.innerText` is render-aware: on one PDP it returned 2,270 chars with 0 matches while `textContent` returned 9,544 with 7, and all the filler sat in the hidden part. Scan `innerText` **plus** body `textContent` with `script/style/template/noscript` stripped. Do not key the pattern on the word "lorem" either — stock Swift filler is verb-opener ipsum ("Holisticly", "Phosfluorescently", "Objectively") containing no "lorem" at all. Attribute values appear in *neither* text source, so the wider scan does not reintroduce the `placeholder=` false positive; report the match offset so a regression is diffable.
- **Mojibake detection must match the double-encode signature, not U+FFFD.** A paragraph rendering `what&acirc;&euro;&trade;s next` to every visitor contains **zero** replacement characters: the corruption is U+2019 encoded as UTF-8 then decoded as CP1252 and re-encoded, producing the three-codepoint run U+00E2 U+20AC U+2122. A replacement character only appears when a decoder gives up; a double encode is perfectly valid text and never produces one. Match the signature — a Latin-1 lead (A-circumflex / A-tilde / a-circumflex / a-tilde) *immediately* followed by a Latin-1-supplement continuation or a CP1252-decoded General-Punctuation character — and keep U+FFFD as one alternative, never the whole test. Fixture-test the regex inside the runner on every run (known double-encodes must all fire; correctly-encoded accented prose, em dashes and a real U+2019 must not), so a future edit that defangs it fails the leg.
- **Never write a comment asserting a guard you have not read in the config THIS session — a comment claiming a tripwire that does not exist is worse than no comment.** A live stylesheet comment asserted that "the wave-clearance assert measures the PAINTED top" of a footer divider. No such assert existed. A second comment 2,600 lines further down said so correctly — "there is no gate assert for it … which is exactly why this survived four PASSes" — so the file contradicted itself, and the FALSE claim was the one an author meets first, at the top of the block that owns the surface. The guard had been real once: it was added to a per-run verification **script**, not to the gate config, and the comment recorded the *intent* as though it were standing. Once that run ended the assert never ran again, and the same defect recurred on a third and a fourth page, each fixed by hand while every gate leg stayed green. **If you want the guard, propose it to the config — do not describe it in a comment.** The corollary is a signal to act on: *the same fix applied by hand on a fourth page is the tell that it belongs in the config and not in a run script*. Re-read the config's actual key list before writing any such claim (a typical design key set is `cssom / clearance / contrast / ctas / computed / requiredSections / docHeight / textOverlap / sectionGapThreshold / placeholderRegex / maxBandHeightFraction` — note there is no paint-clearance key in it), and remember that a text-less pseudo-element is invisible to *both* a `textOverlap` detector scoped to `main` and to any box-model check, because the box model reads the boundary as flush. The assert that closes it is paint-aware: `paintedTop = footerTop + min(0, parseFloat(getComputedStyle(footer, "::before").top))`, requiring ≥ 8px to the lowest painting element inside `main`, at every viewport and page — verified by observing it fail on the pre-fix sheet before trusting it green. (The CSS-side fix and the negative-`top` mechanism: [`../../dw-demo-swift/references/re-skin.md`](../../dw-demo-swift/references/re-skin.md) §"Section-boundary decoration".)
- **"Did not overflow" is not "did not wrap" — a flex rail fails by consuming a second ROW, on an axis no overflow assert measures.** A header rail that exceeds its width budget is `flex-wrap: wrap`, so `document.scrollWidth` never exceeds `clientWidth` and `overflowX` reads **0** in both the correct and the broken state; the header silently grows ~44-49px and pushes content underneath itself. The clearance assert that would have caught it is skipped in exactly this case: an overlay header (`position: absolute` AND background alpha < 0.5) is classified into a branch enforcing only the upper bound (gap ≤ 24) and **not** the `min: -2` floor, because an overlay header legitimately sits over its hero — while a wrapped header drives the non-hero pages to a gap of about **-43**, i.e. 43px of content occluded, with the leg green. Assert the **rail row count** directly (collect the distinct rounded `y` of the rail column children, require 1) or record header height per breakpoint and fail an unexplained step change of roughly one rail-row; if you keep the overlay branch, give it a header-height-derived floor instead of no floor. Do not tighten the `overflowX` assert — the value is correctly 0, the page genuinely does not overflow. **And widen the measured viewport set**: on the run that produced this, a 12-width sweep found the header already rendering two rows at every width from 1400 down to 992 (150.08-155.25px) on a live site whose design pages were only ever measured at 1440 and 390 — the entire 992-1400 band, including a 1366-wide laptop, was unasserted at any width.
- **Present in the served HTML is not visible — assert a non-zero box per paragraph.** A content assertion counting strings in HTML cannot see a CSS-hidden element: one four-column band shipped rendering three of four people, with the fourth fully present (correct item-type wrapper, heading and copy, 22 content assertions green) computing `display: none`, width 0, height 0. For each `[data-dw-itemtype^="swift-v2_"]` element in the DOM of a gate-probed page assert `getBoundingClientRect().height > 0`. Run the CSS side of that diagnosis through CDP `CSS.getMatchedStylesForNode`, never `el.matches()` — a `:has()`/`:not()` argument **throws** in Chromium and the swallowed exception makes a naive audit report "no rule matches" on a demonstrably hidden element (mechanism and the authoring rule: [`../../dw-demo-swift/references/re-skin.md`](../../dw-demo-swift/references/re-skin.md) §"Selector reach").
- **A contrast sweep must enumerate both accent directions or it is decorative.** A brand accent plays at least two roles: **FILL** (a solid accent background needing a readable label) and **TEXT-ON-LIGHT** (the accent as a foreground colour, which must itself be dark enough against the page). Lightening the token keeps the fill role and breaks the text role — and because Bootstrap sets `.btn-outline-primary { --bs-btn-color: var(--dw-color-button-primary) }`, *every* outline-primary control inherits it, so it is a systemic regression, not one button (measured: 7.21:1 as a fill label, 2.31:1 as text on the page background). A sweep that enumerates elements whose **background** resolves to the accent and then checks their label structurally cannot reach accent-as-colour — it reported 0 failures while the gate reported 4. Enumerate both: (a) accent-as-background → measure its label against it; (b) accent-as-colour → resolve the nearest non-transparent **ancestor** background and measure the accent against that. Drive the sweep off the gate's own selector set so sweep and gate cannot disagree, re-run after any accent-token change, and assert 0 failures in both directions. The fix is a dedicated dark ink token for outline/text uses, leaving the light token fill-only — not darkening the brand colour, and not per-button overrides (the token is inherited, so it leaks back on the next new button). **Measure the EFFECTIVE alpha, not the declared one** — an ancestor opacity utility multiplies it (Bootstrap's `.opacity-75` on Swift's accordion body takes a declared `.78` to `.585`), so the failing colour is emergent and appears in no sheet, and darkening the declared colour can make the composite *worse*; the sweep should resolve declared alpha × every ancestor `opacity` before it reports a ratio ([`../../dw-demo-swift/references/re-skin.md`](../../dw-demo-swift/references/re-skin.md) §"Colour contrast").

## Authoring detector scripts — traps that pass silently

When these detectors move from an ad-hoc `browser_evaluate` into a scripted probe runner, three authoring traps each degrade to **"nothing to check" and report a false green** — the worst failure a gate can have, because it looks like success. A probe run that emits **zero probes must never be reported as PASS** — treat an empty probe set as a failure, so a mis-wired runner surfaces instead of silently passing.

- **Playwright `page.evaluate` passes exactly one argument to the page function.** Calling `evaluate(fn, a, b, c)` throws "Too many arguments"; if that throw is caught as a page-load failure, every page assert is skipped and the leg passes with zero probes. Pass a single options object — `evaluate(fn, { rowSelector, minRows, bandCap })` — and destructure it inside.
- **PowerShell `ConvertTo-Json` unwraps a single-element array to a scalar.** A one-page probe config serializes `"pages": "/x"` (string) and a one-entry map as an object, so a JS `Array.isArray()` guard sees no pages and runs zero asserts. On the JS consumer side, normalise scalar-or-array — `const arr = v => v == null ? [] : Array.isArray(v) ? v : [v];` — so a single page or viewport is never dropped. (Force an array at the PowerShell edge with the unary `,` operator or `@(...)` when you control both ends.)
- **A `curl`-shaped image probe measures the JPEG — `GetImage.ashx` content-negotiates on the `Accept` header.** `/Admin/Public/GetImage.ashx?…&format=webp` returns `image/jpeg` when the request sends no `Accept`, *despite* `format=webp`, so a size check scripted outside a browser reports the unoptimised bytes and mis-ranks the image work — a hero measured 834,313 bytes `image/jpeg` with no header and 341,522 bytes `image/webp` with `Accept: image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8` on the identical URL. That reads as "`format=webp` is ignored and the optimisation made things worse". **Send a browser-shaped `Accept` header on every payload measurement**, and confirm in-browser that the intended `srcset` candidate is the one that wins (correct natural dimensions on the selected width).
- **PowerShell variable names are case-insensitive, so a local that is a case-variant of a parameter silently aliases it.** `param($Body); … $body = …` overwrites the parameter — `$body` *is* `$Body`. Name the local distinctly (`$respBody`, `$reqBody`), never a re-cased copy of a declared parameter. The collision is invisible at a glance and blanks the value rather than erroring.

## Interaction pass — a screenshot cannot verify behaviour

A slider whose arrows do nothing looks perfect in a static shot. For every interactive control visible on the page — slider/carousel arrows, tabs, accordions, variant selectors, add-to-cart — **click it once and assert something changed** (a class/`aria-*` attribute flips, the visible slide index moves, the cart badge increments, a panel expands). One interaction per component type per page is enough to catch dead wiring; a control that changes nothing is a finding even when it *renders* flawlessly.

## The eyeball checklist

Read each screenshot against these — every "no" is a finding to route:

| Check | A failure looks like |
|---|---|
| **Vertical rhythm** — are gaps between sections consistent? | One band 2–3× its neighbours (the classic 6rem-default stripe); sections touching with no breathing room |
| **Alignment** — do stacked sections, card grids, and headings share grid lines? | A card row with ragged left edges or unequal card heights; one section indented differently from every other |
| **Images** — crops sensible, aspect ratios consistent per row, heights capped, no letterboxing inside tiles? | A decapitated product subject; one portrait tile in a landscape row; a towering image band or slider cover-card that eats the whole fold; a logo stretched wide; grey empty wells |
| **Text** — complete and real? | Truncation mid-word, copy overflowing its card, lorem/placeholder strings, untranslated resource keys, headings in the wrong visual size order |
| **Edges** — padding at the viewport, no horizontal scrollbar in frame? | Content flush against the screen edge; a scrollbar track visible at the bottom of the shot |
| **Controls** — inside their containers and styled? | An arrow poking past the section edge; a browser-default button among styled ones; a CTA with no hover affordance |
| **Consistency** — one visual system? | Two different button styles for the same action; a section in a color scheme no other section uses; mixed corner radii on cards |
| **Empty shells** — every component has a body? | A heading with nothing under it; a spec table with blank value cells; a product grid rendering zero tiles |

## Symptom → owning fix (route findings, don't re-diagnose)

Most recurring findings have a *known* cause with a documented fix — route there instead of debugging from scratch:

| Finding | Likely cause | Fix lives in |
|---|---|---|
| Horizontal scrollbar; slider arrow at/past the viewport edge | `NavigationPlacement: slider-nav-outside-expand` on a full-width slider | [`foundational/swift-building.md`](foundational/swift-building.md) §3 symptom table |
| Canvas stretched at 390 (`bodyCanvas` > 0) while `overflowX` reads 0; "missing PLP images" / blank right margin on mobile | Fixed-width mega-menu / non-wrapping `NColumnsFlex` row / `.flex-fill` beating a fixed base — stretch hidden behind body `overflow-x:hidden` | [`../../dw-demo-swift/references/mobile-pass.md`](../../dw-demo-swift/references/mobile-pass.md) (trap catalogue + Tier-1 fixes) |
| Uniform oversized whitespace bands between sections | GridRow `NULL` spacing → Swift 6rem default; layout columns are SQL-only and reverted by later MCP saves | [`foundational/data-access.md`](foundational/data-access.md) "SQL-direct content seeding" + [`foundational/cache-invalidation.md`](foundational/cache-invalidation.md) |
| Towering image band / slider cover-card eating the fold (`tall` detector) | Stock image component has no serialized height field; a tall crop renders full column-width height, uncapped | theme-CSS cap (`aspect-ratio` + `max-height` + `object-fit: cover`), Tier-1 in [`dw-demo-swift/re-skin.md`](../../dw-demo-swift/references/re-skin.md) |
| PLP list renders zero rows behind HTTP 200 (`empty`/`missing` finding) | Empty or not-yet-repopulated index, or a mis-scoped shop; 200 proves the shell, not the fill | [`foundational/commerce-catalog.md`](foundational/commerce-catalog.md) + [`foundational/search-indexing.md`](foundational/search-indexing.md) (rebuild/repopulate the index) |
| ~192px dead grey band inside a section | Bootstrap `.ratio` aspect-ratio token vs CSS custom-property | [`foundational/swift-building.md`](foundational/swift-building.md) §3 |
| Blank image wells in a `fullPage` capture | Lazy-load, page not scroll-swept — measurement artifact, not a defect | [`browser-automation.md`](browser-automation.md) verify-flow step 5 |
| Blank cells in spec/attribute components (admin shows values) | Stored list-field value is the display name, not `FieldOptionValue` | [`dw-pim-modelling/references/structural-model.md`](../../dw-pim-modelling/references/structural-model.md) §2.8 |
| Razor error block where a section should be | Plain label string seeded into a `ButtonData` field | [`foundational/content-modelling.md`](foundational/content-modelling.md) Management-API editing section |
| Component renders a heading over an empty shell | `DisplayGroups` given product-category ids instead of display-group system names | [`foundational/swift-building.md`](foundational/swift-building.md) §3 |
| Second element missing from a grid section | Standard `Swift-v2_Row` columns render exactly one paragraph | [`foundational/swift-building.md`](foundational/swift-building.md) §2 |
| A whole section renders nothing, silently | Unknown `GridRowDefinitionId` | [`foundational/data-access.md`](foundational/data-access.md) |
| Facet/sort/load-more chrome leaking into a slider | Service page's app paragraph left on the shop-default list template | [`foundational/swift-building.md`](foundational/swift-building.md) §1 |
| Group/page missing from navigation entirely | Primary-shop resolution or `PageActive`/`PageHidden` coupling | [`foundational/commerce-catalog.md`](foundational/commerce-catalog.md) §2.3 / [`foundational/swift-building.md`](foundational/swift-building.md) §6 |

A finding that matches no row is new knowledge: fix it, then fold it back (`iterate-plugin.md`) — that is how every row above got here.

## The fix loop

Findings are data/content defects — fix them through the build-phase action surfaces (MCP → Admin API → SQL last resort, per [`surface-priority.md`](surface-priority.md); this file changes nothing about Playwright staying verification-only). Then:

1. Apply the fix, plus the cache flush / restart its recipe demands ([`foundational/cache-invalidation.md`](foundational/cache-invalidation.md)).
2. Re-navigate cold, re-run the detectors, re-screenshot at both breakpoints.
3. Compare against the *previous* shot — confirm the finding is gone AND nothing regressed beside it.

Batch at most a handful of fixes between re-checks, and never declare a page done from a pre-fix screenshot.

The detectors above are the **mechanical gate**, not a checklist the agent may skip — every one of them is deterministic, so run them as a hard pass/fail before any eyeballing. The eyeball checklist and interaction pass sit on top; they never substitute for a clean detector run.

- Detectors: `overflowX` 0, `broken`/`stretched`/`tall` empty, no unexplained gap > 120px, console free of errors, no 404 assets. No image band taller than the configured fraction of the viewport (`tall`).
- **Mobile canvas fit:** `bodyCanvas` 0 at 390 — `document.body.scrollWidth <= innerWidth` (measure body, not documentElement; `overflow-x:hidden` masks a stretched canvas from the `overflowX` check). Screenshot pair at **390 and 430** so per-row wrap-state divergence (pills left- vs right-anchored across the wrap boundary) is visible — a single-width pass ships it. Swift trap catalogue + fixes: [`../../dw-demo-swift/references/mobile-pass.md`](../../dw-demo-swift/references/mobile-pass.md).
- PLP pages: row count ≥ the demo's `minRows` AND every row carries its required-field selectors (thumbnail / SKU / price / add-to-cart) — an empty or field-short list behind HTTP 200 is a failure, not a pass.
- **Size, legibility and colour — not just presence:** `doc-height` under its cap at every viewport (an unbounded component is invisible to every other assert), no title/description rect intersection on list rows, and a contrast sweep clean in **both** accent directions. Each of these must have been observed to fail once — see "Assert design rules" above.
- **Theme gate:** the page `<head>` emits all three `Files/System/Styles/{ColorSchemes,Buttons,Typography}` links and the computed body font is the theme's, not the browser's serif fallback. A serif-fallback page renders "almost right" and still fails — that is the silent Style-asset empty-state (`foundational/swift-building.md` §7); the full-page screenshot must read as a *designed* page before the host counts as ready.
- Interaction pass: every visible control changes state when used.
- Eyeball checklist: pass at desktop AND mobile widths.
- Keeper screenshots (both breakpoints) saved under `<demo>\notes\qa\` (the canonical QA-evidence home — see `SKILL.md` "Artifact hygiene"; never the demo root).
- **Human sign-off on taste.** The mechanical gate proves structure (caps, rows, no overflow/gaps); it cannot judge hierarchy or brand fit, so an all-green run can still read wrong. Reserve one human decision on the keeper screenshots as the last step. Under an orchestrator this is a stamped sign-off leg (see [`orchestrator.md`](orchestrator.md) "Acceptance criteria"); standalone it is an explicit "does this read as the customer's brand?" review before the page counts as done. Taste stays human without blocking the mechanical gate.
- **PII / vendor-boilerplate clean** on every page that carries prose — see the section below.

## The eyeball pass is also the PII pass

The rendered-page read is the **only** instrument that catches a class of defect no detector and no term-grep can: **placeholder and vendor residue that matches none of your search terms.** A vocabulary-driven sweep over a whole corpus reported clean while a placeholder phone number in the platform vendor's home locale sat on the contact block of a US company, on two live legal pages, in every language layer.

So when you walk a page for polish, read it for **provenance** as well:

- **Legal / contact / about pages** — is this the customer's privacy, cookie and terms copy, or the platform vendor's? Vendor legal copy is **stock seed data**, present on cleanly built demos, and it names the vendor's own third-party data processors as though they were the customer's.
- **Contact blocks** — dialling codes, postcodes, street suffixes and registration-number formats from the wrong country.
- **Any page naming a person** — testimonials, author bylines, sample orders. On an inherited host these are frequently **real people**.

Anything found here routes to [`pii-sweep.md`](pii-sweep.md), which owns the method (whole-database string sweep → classify by sampling values → fix → re-scan) and is a **blocking pre-demo leg**, not a polish item. The relationship is the same as the mechanical-gate-vs-taste split above: the sweep catches volume and hidden layers, the eyeball catches what matches no pattern anyone thought to write, and neither substitutes for the other.

**Do not paste what you find into notes, screenshots-with-captions or commit messages** — record the class and the count.
