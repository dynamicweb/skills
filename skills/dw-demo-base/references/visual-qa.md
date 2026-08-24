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

An assert earns its green only once it has been **observed to fail** against a state known to violate it — an unsatisfiable assert (a selector keyed on a substring the platform never emits, e.g. `[data-dw-itemtype*="productdescription"]` against `swift-v2_productlongdescription`) is indistinguishable from a passing one. Smoke-test every new assert against a page known to satisfy it AND one known to violate it, and have the runner log, per assert, any selector that matched zero elements on every page in the run.

Four reusable detector specs:

- **`doc-height`.** Rendered height is invisible to present/aligned/parsed asserts — a 9,476px section satisfies "exists and is ≥ 40px tall" *harder* than the correct 133px one (a mobile page hit 15,416px while 187/187 asserts were green). Assert `document.documentElement.scrollHeight` per page per viewport against a cap set comfortably above the tallest legitimate page; prove the cap fires by re-running it below the current maximum.
- **`cta-shape`.** Assert positively, by selector + count + measured shape — never the absence of a string (absence-of-text asserts are unfalsifiable: green when the fix landed *and* when nothing was ever there). Match ≥ `minCount` elements, each satisfying `height >= 40`, `width >= 44`, and (background alpha > 0.05 OR border ≥ 1px), plus optional `minContrast` — separating "CTA missing" from "CTA not button-shaped", naming each offender with measured size and reason. Key it on the actual conversion controls (`main [data-dw-button]`, a marked text-CTA container), never an href pattern — stretched-links and title links are deliberately invisible affordances that get their own *present-but-invisible* assert, never a background nudged over the alpha threshold.
- **`textOverlap`.** Geometry asserts never catch illegible text. Per list row, assert the title rect does NOT intersect the sibling description rect AND title line-count ≤ 2 (configurable), at every configured viewport, emitting both bounding boxes so a regression is diffable. Verify it on a deliberately-starved row (`flex: 0 0 <px>; flex-shrink: 0` on the description) before trusting it.
- **Contrast in BOTH accent directions.** A brand accent plays FILL (accent background needing a readable label) and TEXT-ON-LIGHT (accent as foreground against the page); lightening the token keeps one role and breaks the other, systemically (`.btn-outline-primary { --bs-btn-color: var(--dw-color-button-primary) }` inherits it). Enumerate both: (a) accent-as-background → measure its label against it; (b) accent-as-colour → measure the accent against the nearest non-transparent **ancestor** background. Drive the sweep off the gate's own selector set, re-run after any accent-token change, and measure the **EFFECTIVE** alpha — declared alpha × every ancestor `opacity` (`.opacity-75` takes `.78` to `.585`). Fix with a dedicated dark ink token for outline/text uses, never per-button overrides ([`../../dw-demo-swift/references/re-skin.md`](../../dw-demo-swift/references/re-skin.md) §"Colour contrast").

Other ways a green assert has lied — claim → fix:

- **A CSSOM marker proves parsing, not ownership** (a later block can re-establish a deleted block's selector) → scope the marker to the block's sentinel-pair byte range, or key it on a rule the block uniquely owns; two-way test it.
- **A band-height assert never measures the framed subject** (a top-anchored `object-fit: cover` crop passes the cap while cropping the subject off the bottom) → add a subject bbox (luminance scan) and assert `subject.top > band.top` and `subject.bottom < band.bottom` at every viewport.
- **CSS clipping and rect-based overlap asserts are incompatible** — clipping is paint, not layout: rows scrolled out of a `max-height` + `overflow-y: auto` container still lay out in flow, producing phantom overlaps no human sees (no CSS workaround exists) → report the conflict and leave the assert honestly red; narrowing a detector to clear your own red is the anti-pattern the gate exists to prevent.
- **A flat top-level-section sort is blind to grid columns** (DW emits columns as `div`; stacked at mobile, a populated gallery reads as a 600px dead band — a gap at one orientation only is the tell) → skip any pair whose gap lies inside an already-counted ancestor's box; never reshape a correct page to satisfy the instrument.
- **An `innerText` content tripwire is blind to collapsed accordions and inactive tabs** — exactly where CMS boilerplate lives → scan `innerText` PLUS stripped body `textContent`; don't key on "lorem" (stock Swift filler is verb-opener ipsum: "Holisticly", "Phosfluorescently"); report the match offset.
- **Mojibake detection must match the double-encode signature, not U+FFFD** (a double encode — U+2019 rendered as the three-codepoint run U+00E2 U+20AC U+2122, `what&acirc;&euro;&trade;s` — is valid text; no replacement character ever appears) → match a Latin-1 lead (Â/Ã/â/ã) immediately followed by a Latin-1-supplement or CP1252-decoded punctuation continuation, keep U+FFFD as one alternative only, and fixture-test the regex on every run.
- **A comment asserting a guard that does not exist is worse than no comment** (a claimed assert lived only in a one-off run script; the defect recurred on four pages under all-green gates) → propose the guard to the gate **config**, never describe it in a comment; a fix applied by hand on a fourth page is the tell that it belongs in the config. The paint-aware assert that closed it: `paintedTop = footerTop + min(0, parseFloat(getComputedStyle(footer, "::before").top))`, ≥ 8px clearance ([`../../dw-demo-swift/references/re-skin.md`](../../dw-demo-swift/references/re-skin.md) §"Section-boundary decoration").
- **"Did not overflow" is not "did not wrap"** — a `flex-wrap: wrap` header rail fails by consuming a second ROW while `overflowX` correctly reads 0 → assert the rail row count (distinct rounded `y` of rail children == 1) or fail an unexplained header-height step per breakpoint; give an overlay-header clearance branch a header-height-derived floor; widen the measured viewport set beyond 1440 + 390 (the 992–1400 band went unasserted).
- **Present in the served HTML is not visible** (a CSS-hidden column passed 22 content assertions) → for each `[data-dw-itemtype^="swift-v2_"]` element assert `getBoundingClientRect().height > 0`; diagnose via CDP `CSS.getMatchedStylesForNode`, never `el.matches()` (`:has()`/`:not()` arguments **throw** in Chromium; the swallowed exception reports "no rule matches") ([`../../dw-demo-swift/references/re-skin.md`](../../dw-demo-swift/references/re-skin.md) §"Selector reach").

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
| Horizontal scrollbar; slider arrow at/past the viewport edge | `NavigationPlacement: slider-nav-outside-expand` on a full-width slider | [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §3 symptom table |
| Canvas stretched at 390 (`bodyCanvas` > 0) while `overflowX` reads 0; "missing PLP images" / blank right margin on mobile | Fixed-width mega-menu / non-wrapping `NColumnsFlex` row / `.flex-fill` beating a fixed base — stretch hidden behind body `overflow-x:hidden` | [`../../dw-demo-swift/references/mobile-pass.md`](../../dw-demo-swift/references/mobile-pass.md) (trap catalogue + Tier-1 fixes) |
| Uniform oversized whitespace bands between sections | GridRow `NULL` spacing → Swift 6rem default; layout columns are SQL-only and reverted by later MCP saves | [`management-api-and-sql.md`](../../dw-data-access/references/management-api-and-sql.md) "SQL-direct content seeding" + [`cache-invalidation.md`](../../dw-data-access/references/cache-invalidation.md) |
| Towering image band / slider cover-card eating the fold (`tall` detector) | Stock image component has no serialized height field; a tall crop renders full column-width height, uncapped | theme-CSS cap (`aspect-ratio` + `max-height` + `object-fit: cover`), Tier-1 in [`dw-demo-swift/re-skin.md`](../../dw-demo-swift/references/re-skin.md) |
| PLP list renders zero rows behind HTTP 200 (`empty`/`missing` finding) | Empty or not-yet-repopulated index, or a mis-scoped shop; 200 proves the shell, not the fill | [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) + [`index-management.md`](../../dw-search-indexing/references/index-management.md) (rebuild/repopulate the index) |
| ~192px dead grey band inside a section | Bootstrap `.ratio` aspect-ratio token vs CSS custom-property | [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §3 |
| Blank image wells in a `fullPage` capture | Lazy-load, page not scroll-swept — measurement artifact, not a defect | [`browser-automation.md`](browser-automation.md) verify-flow step 5 |
| Blank cells in spec/attribute components (admin shows values) | Stored list-field value is the display name, not `FieldOptionValue` | [`dw-pim-modelling/references/structural-model.md`](../../dw-pim-modelling/references/structural-model.md) §2.8 |
| Razor error block where a section should be | Plain label string seeded into a `ButtonData` field | [`modelling-discipline.md`](../../dw-content-modelling/references/modelling-discipline.md) Management-API editing section |
| Component renders a heading over an empty shell | `DisplayGroups` given product-category ids instead of display-group system names | [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §3 |
| Second element missing from a grid section | Standard `Swift-v2_Row` columns render exactly one paragraph | [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §2 |
| A whole section renders nothing, silently | Unknown `GridRowDefinitionId` | [`management-api-and-sql.md`](../../dw-data-access/references/management-api-and-sql.md) |
| Facet/sort/load-more chrome leaking into a slider | Service page's app paragraph left on the shop-default list template | [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §1 |
| Group/page missing from navigation entirely | Primary-shop resolution or `PageActive`/`PageHidden` coupling | [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.3 / [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §6 |

A finding that matches no row is new knowledge: fix it, then fold it back (`iterate-plugin.md`) — that is how every row above got here.

## The fix loop

Findings are data/content defects — fix them through the build-phase action surfaces (MCP → Admin API → SQL last resort, per [`surface-priority.md`](surface-priority.md); this file changes nothing about Playwright staying verification-only). Then:

1. Apply the fix, plus the cache flush / restart its recipe demands ([`cache-invalidation.md`](../../dw-data-access/references/cache-invalidation.md)).
2. Re-navigate cold, re-run the detectors, re-screenshot at both breakpoints.
3. Compare against the *previous* shot — confirm the finding is gone AND nothing regressed beside it.

Batch at most a handful of fixes between re-checks, and never declare a page done from a pre-fix screenshot.

## Definition of done (per demo-critical page)

The detectors above are the **mechanical gate**, not a checklist the agent may skip — every one of them is deterministic, so run them as a hard pass/fail before any eyeballing. The eyeball checklist and interaction pass sit on top; they never substitute for a clean detector run.

- Detectors: `overflowX` 0, `broken`/`stretched`/`tall` empty, no unexplained gap > 120px, console free of errors, no 404 assets. No image band taller than the configured fraction of the viewport (`tall`).
- **Mobile canvas fit:** `bodyCanvas` 0 at 390 — `document.body.scrollWidth <= innerWidth` (measure body, not documentElement; `overflow-x:hidden` masks a stretched canvas from the `overflowX` check). Screenshot pair at **390 and 430** so per-row wrap-state divergence (pills left- vs right-anchored across the wrap boundary) is visible — a single-width pass ships it. Swift trap catalogue + fixes: [`../../dw-demo-swift/references/mobile-pass.md`](../../dw-demo-swift/references/mobile-pass.md).
- PLP pages: row count ≥ the demo's `minRows` AND every row carries its required-field selectors (thumbnail / SKU / price / add-to-cart) — an empty or field-short list behind HTTP 200 is a failure, not a pass.
- **Size, legibility and colour — not just presence:** `doc-height` under its cap at every viewport (an unbounded component is invisible to every other assert), no title/description rect intersection on list rows, and a contrast sweep clean in **both** accent directions. Each of these must have been observed to fail once — see "Assert design rules" above.
- **Theme gate:** the page `<head>` emits all three `Files/System/Styles/{ColorSchemes,Buttons,Typography}` links and the computed body font is the theme's, not the browser's serif fallback. A serif-fallback page renders "almost right" and still fails — that is the silent Style-asset empty-state (`component-system-and-reskin.md` §7 in dw-swift-building); the full-page screenshot must read as a *designed* page before the host counts as ready.
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
