# Visual QA — reading a screenshot critically

A page that renders is not a page that is done. The recurring polish gaps on demo storefronts — oversized whitespace bands, misaligned or stretched images, dead slider arrows, horizontal scrollbars — are all visible in a screenshot *when you hunt for them*. This file owns the hunt: the programmatic detectors to run before eyeballing, the checklist to read every screenshot against, the interaction pass a static screenshot cannot replace, and the routing table from visual symptom to owning fix. The verify-flow mechanics (login, walk, where screenshots land) stay in [`browser-automation.md`](browser-automation.md); this file owns what *done* looks like.

## Contents

- [The mindset rule](#the-mindset-rule)
- [Breakpoints — capture both, always](#breakpoints--capture-both-always)
- [Programmatic detectors — run before eyeballing](#programmatic-detectors--run-before-eyeballing)
- [PLP list — assert rows AND per-row content](#plp-list--assert-rows-and-per-row-content)
- [Authoring detector scripts — traps that pass silently](#authoring-detector-scripts--traps-that-pass-silently)
- [Interaction pass — a screenshot cannot verify behaviour](#interaction-pass--a-screenshot-cannot-verify-behaviour)
- [The eyeball checklist](#the-eyeball-checklist)
- [Symptom → owning fix (route findings, don't re-diagnose)](#symptom--owning-fix-route-findings-dont-re-diagnose)
- [The fix loop](#the-fix-loop)
- [Definition of done (per demo-critical page)](#definition-of-done-per-demo-critical-page)

## The mindset rule

Treat every screenshot as a **defect hunt, not a confirmation**. An entity-count check ("N order rows visible") proves the data landed; it says nothing about polish. Score each demo-critical page against this file before declaring it done — "it renders" is the bar for seeding; **"nothing left to fix" is the bar for a demo**.

Order of operations per page: scroll-sweep (lazy-load — see `browser-automation.md` verify-flow step 5) → programmatic detectors → interaction pass → screenshot at both breakpoints → eyeball checklist → route findings → fix → re-run. The detectors go first because they are deterministic and catch exactly the defects eyes skim past in a thumbnail-sized render of a long page.

## Breakpoints — capture both, always

Capture and check at minimum two widths via `browser_resize`: **desktop (1440 or 1920)** and **mobile (390)**. Most overflow, stacking, and touch-target defects only exist at one of the two — a desktop-only pass routinely ships a broken mobile view, and demos get projected at both.

## Programmatic detectors — run before eyeballing

One `browser_evaluate` call returns the mechanical findings. Adjust the section selector to the page's actual container structure when the generic one returns nothing useful:

```js
() => {
  const de = document.documentElement, vw = de.clientWidth;
  const out = { overflowX: Math.max(0, de.scrollWidth - vw), offenders: [], broken: [], stretched: [], tall: [], gaps: [] };
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

`tall` catches the recurring oversized image band — a portrait crop or slider cover-card rendered at full column-width height, uncapped, so it dominates the fold. It is a **distinct** finding from `stretched`: the aspect ratio is correct, the band is simply too tall. The stock image components carry no serialized height field, so a swapped-in photo reproduces it on every demo. The durable fix is a theme-CSS cap (`aspect-ratio` + `max-height` + `object-fit: cover` on the image wrapper and the slider cover-card), a Tier-1 re-skin item — route to `dw-demo-swift/references/re-skin.md`. Tune `bandCap` to the band the demo wants (a full-bleed hero legitimately fills the fold; a content-band image should not).

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

## Authoring detector scripts — traps that pass silently

When these detectors move from an ad-hoc `browser_evaluate` into a scripted probe runner, three authoring traps each degrade to **"nothing to check" and report a false green** — the worst failure a gate can have, because it looks like success. A probe run that emits **zero probes must never be reported as PASS** — treat an empty probe set as a failure, so a mis-wired runner surfaces instead of silently passing.

- **Playwright `page.evaluate` passes exactly one argument to the page function.** Calling `evaluate(fn, a, b, c)` throws "Too many arguments"; if that throw is caught as a page-load failure, every page assert is skipped and the leg passes with zero probes. Pass a single options object — `evaluate(fn, { rowSelector, minRows, bandCap })` — and destructure it inside.
- **PowerShell `ConvertTo-Json` unwraps a single-element array to a scalar.** A one-page probe config serializes `"pages": "/x"` (string) and a one-entry map as an object, so a JS `Array.isArray()` guard sees no pages and runs zero asserts. On the JS consumer side, normalise scalar-or-array — `const arr = v => v == null ? [] : Array.isArray(v) ? v : [v];` — so a single page or viewport is never dropped. (Force an array at the PowerShell edge with the unary `,` operator or `@(...)` when you control both ends.)
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
| Uniform oversized whitespace bands between sections | GridRow `NULL` spacing → Swift 6rem default; layout columns are SQL-only and reverted by later MCP saves | [`foundational/data-access.md`](foundational/data-access.md) "SQL-direct content seeding" + [`foundational/cache-invalidation.md`](foundational/cache-invalidation.md) |
| Towering image band / slider cover-card eating the fold (`tall` detector) | Stock image component has no serialized height field; a tall crop renders full column-width height, uncapped | theme-CSS cap (`aspect-ratio` + `max-height` + `object-fit: cover`), Tier-1 in [`dw-demo-swift/re-skin.md`](../../dw-demo-swift/references/re-skin.md) |
| PLP list renders zero rows behind HTTP 200 (`empty`/`missing` finding) | Empty or not-yet-repopulated index, or a mis-scoped shop; 200 proves the shell, not the fill | [`foundational/commerce-catalog.md`](foundational/commerce-catalog.md) + [`foundational/search-indexing.md`](foundational/search-indexing.md) (rebuild/repopulate the index) |
| ~192px dead grey band inside a section | Bootstrap `.ratio` aspect-ratio token vs CSS custom-property | [`foundational/swift-building.md`](foundational/swift-building.md) §3 |
| Blank image wells in a `fullPage` capture | Lazy-load, page not scroll-swept — measurement artifact, not a defect | [`browser-automation.md`](browser-automation.md) verify-flow step 5 |
| Blank cells in spec/attribute components (admin shows values) | Stored list-field value is the display name, not `FieldOptionValue` | [`foundational/pim-modelling.md`](foundational/pim-modelling.md) §2.8 |
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
- PLP pages: row count ≥ the demo's `minRows` AND every row carries its required-field selectors (thumbnail / SKU / price / add-to-cart) — an empty or field-short list behind HTTP 200 is a failure, not a pass.
- **Theme gate:** the page `<head>` emits all three `Files/System/Styles/{ColorSchemes,Buttons,Typography}` links and the computed body font is the theme's, not the browser's serif fallback. A serif-fallback page renders "almost right" and still fails — that is the silent Style-asset empty-state (`foundational/swift-building.md` §7); the full-page screenshot must read as a *designed* page before the host counts as ready.
- Interaction pass: every visible control changes state when used.
- Eyeball checklist: pass at desktop AND mobile widths.
- Keeper screenshots (both breakpoints) saved under `<demo>\notes\qa\` (the canonical QA-evidence home — see `SKILL.md` "Artifact hygiene"; never the demo root).
- **Human sign-off on taste.** The mechanical gate proves structure (caps, rows, no overflow/gaps); it cannot judge hierarchy or brand fit, so an all-green run can still read wrong. Reserve one human decision on the keeper screenshots as the last step. Under an orchestrator this is a stamped sign-off leg (see [`orchestrator.md`](orchestrator.md) "Acceptance criteria"); standalone it is an explicit "does this read as the customer's brand?" review before the page counts as done. Taste stays human without blocking the mechanical gate.
