# Layout verification — the checks a markup assert cannot make

> Four classes of Swift 2 layout defect are invisible to every HTTP-level and DOM-presence check:
> horizontal overflow, an element that is present but unclickable, an anchor whose colour is decided
> by a name rather than by its background, and a band that renders nothing while still costing
> height. Each one needs a browser-side measurement, and each has a probe shape that names the
> offender instead of returning a bare number. Companion to
> [`grid-rows-and-binding.md`](grid-rows-and-binding.md) (the row-level causes) and
> [`component-system-and-reskin.md`](component-system-and-reskin.md) (the override slot every fix lands in).
>
> Swift 2.x only — never follow `/swift/swift-1/` URLs.

## Contents

- [Why these four need a browser](#why-these-four-need-a-browser)
- [Horizontal overflow — read THREE numbers, not one](#horizontal-overflow--read-three-numbers-not-one)
- [Name the offender by RIGHT EDGE, never by width](#name-the-offender-by-right-edge-never-by-width)
- [Measure every auth state — the header is a different document](#measure-every-auth-state--the-header-is-a-different-document)
- [The overflow causes that recur in Swift 2](#the-overflow-causes-that-recur-in-swift-2)
- [Visually hidden means `overflow: hidden` — `clip-path` does not contain overflow](#visually-hidden-means-overflow-hidden--clip-path-does-not-contain-overflow)
- [Hit testing — a stretched row link swallows every control inside it](#hit-testing--a-stretched-row-link-swallows-every-control-inside-it)
- [Contrast — measure the rendered pair, not the declared token](#contrast--measure-the-rendered-pair-not-the-declared-token)
- [The gate's minimum browser leg](#the-gates-minimum-browser-leg)

## Why these four need a browser

All four defects ship a page that answers 200 with `dw-error` 0, contains every element the content
asserts name, and is wrong. A full-page screenshot does not adjudicate them either — it can
manufacture a defect that does not exist (a closed off-canvas panel parked off-screen looks
identical to a stretched canvas) and it hides the ones that matter (an unclickable control looks
perfect). The instrument is a headless browser reading computed geometry, driven at a real device
descriptor.

## Horizontal overflow — read THREE numbers, not one

The single-number check is wrong in both directions, and both failures have shipped.

- `document.documentElement.scrollWidth` alone is masked by `overflow-x: hidden` on `body`.
- `document.body.scrollWidth` alone misses the case where the offending content is unshrinkable:
  **once the browser widens the layout viewport to fit it, `scrollWidth == innerWidth` by
  construction**, and the difference reads as zero. Measured: `body.scrollWidth 652 |
  window.innerWidth 652 | requested 390` — a 262px stretch, reported as no overflow. A page in this
  state renders visibly zoomed out on a phone.

**Assert both relationships at every configured viewport:**

```js
// requested = the width of the device descriptor the probe was launched with
const ok = window.innerWidth === requested
        && document.body.scrollWidth === window.innerWidth;
```

`innerWidth === requested` is the leg that catches the widened layout viewport; the scrollWidth
equality is the leg that catches ordinary overflow. Either one alone certifies a broken page.

**Read `scrollWidth` at two different device widths before hunting.** The same number at both
(for example 461 at a 390 viewport and at a 412 one) means the offender is a **fixed-width box in
normal flow**, not a responsive one — that single reading eliminates every responsive suspect before
any element is opened.

## Name the offender by RIGHT EDGE, never by width

A probe that sorts candidates by width, or by "furthest right edge", reliably names an innocent
element. Bootstrap's `.offcanvas-end` is `position: fixed; right: 0; transform: translateX(100%)`,
so when the document already overflows, its used position resolves against the widened scroll area:
its LEFT edge lands exactly on `documentElement.scrollWidth` and its right edge is
`scrollWidth + its own width`. It tracks the overflow perfectly while contributing nothing to it,
and because a closed drawer is a full viewport wide it outranks the real offender in any
width-sorted or right-edge-sorted list. Investigating the drawer — its width, its `position: fixed`,
its transform — is a dead end every time.

**The offender is the element whose right edge EQUALS `documentElement.scrollWidth`.** Anything
reaching further right than `scrollWidth` is out of flow and is a symptom. In the measured case the
drawer reported a right edge of 851 and the real offender was a 131px header nav item whose right
edge was exactly 461, the scroll width.

Have the probe report, per failing page and viewport: the requested width, `innerWidth`,
`documentElement.scrollWidth`, and the tag/class/id of the element whose right edge equals the
scroll width. A bare pixel delta is not attributable and sends the pass to the wrong element.

## Measure every auth state — the header is a different document

Swift's `swift-v2_myaccount` paragraph renders two structurally different controls. Signed in it is
a ~48px icon button carrying the user's initials; anonymous it is an anchor carrying an avatar plus
a literal text label in a `.text-nowrap` box, min-content ~123px. The header's top row is one flex
container at `max-width: calc(100% - 32px)` with `gap: 16px`, so ~83px of unbreakable label text is
the whole difference between fitting at 390 and a viewport-independent overflow.

**An overflow pass taken in one auth state is a measurement of that state's header, not of the
site's** — a signed-in sweep measured 0 on ten page-by-device checks, and the anonymous sweep an
hour later measured 71px at 390 and 49px at 412 on the same five pages, unchanged in between. Both
were correct. **The anonymous control is the wider one**, so the anonymous pass is the one a
signed-in pass cannot substitute for. Every viewport pass owes both states.

## The overflow causes that recur in Swift 2

- **A Bootstrap `g-col-N` span over an `auto-fit` grid.** Overriding a Swift row's
  `grid-template-columns` to `repeat(auto-fit, minmax(<n>px, 1fr))` while the children still carry
  `g-col-12` makes the grid manufacture eleven zero-width implicit tracks **and still charge the gap
  between them**: the child's used width becomes `minmax-floor + 11 × column-gap`, a constant that
  does not depend on the viewport at all (measured 180 + 11×32 = 532px inside a 358px parent).
  **Keep Bootstrap's span classes and an explicit track count together, or remove both** — the two
  systems disagree about how many tracks exist. The same family: bare `1fr` tracks in a responsive
  override where the base rule used `minmax(0, 1fr)`, which floors each track at the item's
  min-content.
- **A reading-measure utility on authored content.** Swift wraps the product long description in
  `.mw-75ch.d-inline-block`. An inline-block is sized to `min(max-content, max-width)` and
  `.mw-75ch` is `max-width: 75ch` (~600px), so one wide element inside it — a table, a `pre`, a wide
  image — forces a 600px box into a 390px viewport, and the element's own `.table-responsive`
  wrapper cannot rescue it because ITS width is being set by that oversized parent. `75ch` is a
  typographic MAXIMUM, never a minimum, so capping it at the column width on small screens is
  strictly correct: `@media (max-width: 991.98px) { .mw-75ch { max-width: 100%; } }`. The horizontal
  scroll then goes back to `.table-responsive`, where it belongs.
- **An unbreakable string** (a long e-mail address, a part number) — `overflow-wrap` on the
  container, and `min-width: 0` on grid children so a track can shrink below its content.

Reject `overflow-x: hidden` on `body` as a fix in all three cases: it hides the symptom, leaves the
content unreachable, and blinds the probe that would have caught the next one.

## Visually hidden means `overflow: hidden` — `clip-path` does not contain overflow

**A visually-hidden label needs `overflow: hidden` on the 1×1 box.** `clip-path` (and the legacy
`clip`) crop **painting** only: they create no scroll container and contain no scrollable overflow,
so a 1×1 box holding 83px of `white-space: nowrap` text still contributes those 83px to every
ancestor's scroll width. Absolute positioning makes it strictly worse than leaving the label
visible, because the label leaves normal flow and the row stops accounting for it at all.

Measured on one page at two device widths, injecting one variant at a time and reading
`documentElement.scrollWidth`:

| Variant | 390 viewport | 412 viewport |
|---|---|---|
| Label left visible in flow | 394 (4px over) | 412 (0) |
| `clip` + `clip-path`, no `overflow` | 409 (19px over) | 430 (18px over) |
| `clip-path` only | 409 | 430 |
| `overflow: hidden` + `clip-path` | **390 (0)** | **412 (0)** |
| `overflow: hidden` + `clip` + `clip-path` | **390 (0)** | **412 (0)** |

The accessible name survives in every variant and the label's own `element.scrollWidth` stays 83, so
`overflow: hidden` costs nothing in accessibility terms and is the only thing that contains the box.
Use it:

```css
.visually-hidden-label {
  position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
  overflow: hidden; clip-path: inset(50%); white-space: nowrap; border: 0;
}
```

**Answer the "overflow clips my panel" worry by SCOPE, not by dropping `overflow`.** The rule
belongs on a 1×1 label span with no descendants; it must never be written against a header ancestor
that a megamenu or off-canvas panel has to escape. A guard that forbids `overflow` anywhere inside
a header subtree bans the containment and permits the overflow it exists to prevent — scope the
guard to the ancestors panels escape through, and assert the label variant separately.

Rejected: `display: none` and `font-size: 0` (both damage the accessible name); `text-indent:
-9999px` (moves the overflow to the left, where a `scrollWidth` assert happens not to see it in LTR
— luck, not containment).

## Hit testing — a stretched row link swallows every control inside it

A Swift card's click-through affordance is an absolutely-positioned anchor covering the whole row
(the stretched-link pattern). **Anything added inside that row — a disclosure, a quantity input, a
secondary button — sits visually inside the markup and UNDER the anchor in hit-testing order.** The
element is genuinely present, correctly styled and not `display: none`, so every DOM-level assert is
green while a real click navigates to the product instead of doing the control's job.

**The probe is `document.elementFromPoint()` at the centre of the control: it must return the
control (or its own descendant), not the row link.** Pair it with a dispatched click and assert the
control's own state changed.

The fix that works keeps the rest of the row clickable:

```css
.card__col--interactive { position: relative; z-index: 2; pointer-events: none; }
.card__col--interactive details { pointer-events: auto; }   /* only the control takes the click */
```

Lifting the whole column out of the link's stacking order is not the fix — it stops that column
opening the product, which is also wrong.

## Contrast — measure the rendered pair, not the declared token

A contrast defect survives every HTTP assert and every markup assert, and a person reading a
screenshot is the only thing that has caught it without a probe. Compute the ratio from the
**rendered** foreground and the **effective** background (walk ancestors until a non-transparent
background is found, and multiply the declared alpha by every ancestor `opacity`), for every text
and anchor pair in the states the demo shows. The recurring Swift cause is a row whose declared
colour scheme no longer matches its painted background — see
[`grid-rows-and-binding.md`](grid-rows-and-binding.md) §"Anchor colour comes from the row's DECLARED
scheme".

## The gate's minimum browser leg

Per configured page, per device descriptor, and **per auth state**:

1. `innerWidth === requested` **and** `body.scrollWidth === innerWidth`; on failure, report the
   element whose right edge equals `documentElement.scrollWidth`.
2. `elementFromPoint(centre)` returns the element itself for every control added inside a stretched-
   link card.
3. Page height, or per-section height, for any page where empty bands are a known risk.
4. Contrast ratio for every text/anchor pair on a row whose background is painted by project CSS.

A single-width, single-state, markup-only pass certifies pages that are measurably broken; these
four are what it misses.
