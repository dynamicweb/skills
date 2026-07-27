# re-skin.md

> Customer-themed re-skin recipe for a Swift 2 baseline. Defaults to the configuration-only path (admin UI Visual Editor + theme tokens -- see [admin-ui-authoring.md](admin-ui-authoring.md)). Escalation ladder when configuration falls short: (1) project-scoped CSS overrides at `Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css` consuming the `--dw-*` variables Dynamicweb generates from admin; (2) layout-only `.cshtml` content-layouts for tailored screens; (3) controller/provider `.cs` triggers base's customisations-ledger preflight ([dynamicweb-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md)).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Contents

- [What this file owns vs. what moved to the foundational skill](#what-this-file-owns-vs-what-moved-to-the-foundational-skill)
- [Pitfall index](#pitfall-index)
- [The escalation ladder](#the-escalation-ladder)
- [The `<customer>_custom.css` naming hard rule](#the-customer_customcss-naming-hard-rule)
- [Re-skin smell: "Swift-v2_Text shim + foreign cshtml"](#re-skin-smell-swift-v2_text-shim--foreign-cshtml)
- [Recipe](#recipe)
- [Scoping hooks — one content page vs the whole catalog](#scoping-hooks--one-content-page-vs-the-whole-catalog)
- [A palette swap is a multi-file, multi-notation sweep](#a-palette-swap-is-a-multi-file-multi-notation-sweep)
- [CSS that silently never reaches the browser](#css-that-silently-never-reaches-the-browser)
- [Overriding Swift/Bootstrap-managed layout](#overriding-swiftbootstrap-managed-layout)
- [Floating / overlay header — hero behind the bar](#floating--overlay-header--hero-behind-the-bar)
- [Section-boundary decoration — negative-top pseudo-elements](#section-boundary-decoration--negative-top-pseudo-elements)
- [Utility classes lose to scheme-scoped element rules](#utility-classes-lose-to-scheme-scoped-element-rules)
- [In-page anchors — `<base href>` breaks every bare fragment](#in-page-anchors--base-href-breaks-every-bare-fragment)
- [Conditional-collapse CSS — hide empty bands with sibling `:has()` pairs, not nested `:has()`](#conditional-collapse-css--hide-empty-bands-with-sibling-has-pairs-not-nested-has)
- [What this recipe does NOT do](#what-this-recipe-does-not-do)

## What this file owns vs. what moved to the foundational skill

Vendor-generic Swift re-skin doctrine is now owned by the foundational skills:

- **The "never edit standard templates" never-touch list + allowed override slot, the item-type + variant + CSS "separate the styling from the content" pattern, the Pixel-perfect "what you may / may not create" escalation, and the Pre-escalation "search the source first" check** — owned by the `dw-swift-building` foundational skill, staged in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9 ("Re-skin doctrine").
- **`CustomHeadInclude` + `?<ticks>` static-token wiring** — staged in [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §3.
- **Color schemes architecture + cascade** — staged in [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §4.
- **The three CSS pitfalls (over-broad `[data-dw-button]`, bare `footer { }`, emoji color-font)** — staged in [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §5.

This file keeps the demo-specific spine: the escalation ladder, the `<customer>_custom.css` naming hard rule, the customisations-ledger preflight, and the customer-themed Recipe.

## Pitfall index

The pitfalls (now in the foundational skill) — easy to miss on a partial read:

- `?<ticks>` cache-buster can be STATIC on some builds; put demo-critical CSS in an inline `<style>` block → [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §3.
- Scheme name typos / casing mismatches silently resolve to `data-dw-colorscheme=""` → [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §4.
- Over-broad `[data-dw-button]` selectors paint outline/ghost/icon buttons solid brand colour → [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §5.
- Bare `footer { }` selectors clobber card-internal action-bars → [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §5.
- Emoji codepoints render in color regardless of CSS `color:` (OS color-font fallback) → [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §5.
- Header brand-bar paint loses to colorscheme rules: `.navbar` hits the category sidebar, section colorscheme backgrounds repaint over `header[data-swift-page-header]`, link colours need a stacked `:is()/:not()` override → [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §5.
- A Typography style's `--dw-font-family` renders the browser default serif unless the font is vendored (`@font-face` + woff2 — Swift ships no webfonts) and the stack ends in a generic family → [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §5.
- Custom variant `.cshtml` whose filename sorts before stock variants hijacks empty-`ParagraphTemplate` paragraphs → [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §4. The verification step for any re-skin that adds a custom variant must check this.

## The escalation ladder

**The ladder starts FROM `theme-default`** — the single presentation layer every edition composes (there is no theme choice and no overlay layers in the Distribution). Stage `theme-default`'s `files/` onto the host first ([`styles-assets.md`](styles-assets.md)); it already carries the default Styles JSON+CSS pairs, `default_custom.css` (including the header-nav affordance core — [`header-menu.md`](header-menu.md)), and `DefaultHeadInclude.cshtml`. Every customer re-skin then climbs the tiers below **on top of** that baseline — customer overrides go in `<customer>_custom.css`, never by editing `theme-default`'s own files.

| Tier | Surface | What it touches | Owner |
|------|---------|-----------------|-------|
| 0 | Admin UI Style Tools (Settings → Content → Styles) | Color schemes, button shape, typography — generates the `Styles/*.{json,css}` pairs | [styles-assets.md](styles-assets.md) + [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §7 |
| 1 | `Custom/<customer>_custom.css` | Brand variables, hover states, hacks the schemes don't cover | this file (naming rule below) + [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §3 (wiring) |
| 2 | New layout-only `.cshtml` content layouts | Pixel-perfect reshaping of an item type's render | [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9 |
| 3 | Controller / provider `.cs` (customisations-ledger preflight) | Anything that needs server-side logic | [dynamicweb-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md) |

Before climbing the ladder, run the Pre-escalation "search the source first" check in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9 — most "I need a custom template" reflexes resolve to a canonical surface (permission entity store for role gates, `Page.Loaded` subscriber for redirects, `CustomHeadInclude` for a project stylesheet, `Pageview.User.*` for identity).

## The `<customer>_custom.css` naming hard rule

**Brand CSS goes in `<customer>_custom.css` — never in a file named `custom.css`.** Swift ships `Custom/custom.css` as a placeholder template (`body { background: hotpink !important; }`) and the design-css doc's load-order example shows an `Assets/css/custom.css` — both are Swift sample code, not the demo's override file. Writing brand CSS into a file named exactly `custom.css` breaks the shipped sample and turns the upgrade story into a merge instead of a file-drop.

Create the customer-named sibling — same naming discipline as the `<Prefix>_*` item types:

- The override file: `Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css`
- Wired via a head-include partial: `Custom/<customer>HeadInclude.cshtml` registered on the Master area's `CustomHeadInclude` field (the `AddStylesheet` wiring + the `?<ticks>` static-token caveat live in [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §3).

Verification: `git diff --name-only -- '*custom.css'` must never show a path ending in `custom.css` other than `<customer>_custom.css`. Any file named exactly `custom.css` in the diff is a re-skin bug — revert it and move the rules (this is grep #9 of the discipline audit in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §10).

## Re-skin smell: "Swift-v2_Text shim + foreign cshtml"

Symptom: a paragraph template path like `Templates\Designs\Swift-v2\Paragraph\Swift-v2_Text\<Project>SomeName.cshtml` that has nothing to do with text. The paragraph is created as Swift Text in admin, then the template path is overridden to point at this file. The editor sees only Title/Subtitle/Text fields; the template ignores most of them and bakes the real fields as hardcoded literals.

Fix: define a `<Prefix>_<ConceptName>` custom item type — see [`content-modelling.md`](../../dw-demo-base/references/foundational/content-modelling.md) §2 ("Custom item types — the `<Prefix>_*` discipline") and the separate-the-styling-from-content pattern in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9.

## Recipe

Operates on a deserialized Swift 2.4 composition (framework-only `base` + `surface-swift` content, resolved into a running host via this skill's [`deserialize-flow.md`](deserialize-flow.md)) with `theme-default` staged. All steps are admin UI only. Throughout: `<customer>` is the demo customer's short slug (lowercase, no spaces).

### 1. Logo

- Drop the customer's logo file into `<demo>\Dynamicweb.Host.Suite\wwwroot\Files\Images\<customer>-logo.svg` (or `.png`).
- Admin UI: Pages → `Header _ Footer` → Header paragraph → Logo property → set to `Files/Images/<customer>-logo.svg`.

### 2. Theme tokens (color palette + typography)

- Admin UI: Pages → Theme (page-preset) → edit the theme paragraph's color/typography properties via Visual Editor.
- Pull the customer's primary brand color from their public site or brand guide; pair with a vertical-typical neutral palette (B2B-distributor demos lean toward muted neutrals + a single accent; consumer / fashion demos lean richer).
- Changing a palette **after** content exists is not a token edit — it is the multi-file sweep in [§A palette swap is a multi-file, multi-notation sweep](#a-palette-swap-is-a-multi-file-multi-notation-sweep). Run that checklist or the largest painted areas on the site keep the outgoing colour.

### 3. Header / footer copy

- Admin UI: Pages → `Header _ Footer` → edit each paragraph's text content.
- Replace placeholder copy with the customer's vertical-specific language. Source from the demo's read-only `<demo>\customer-context\` (intro-call notes, project-alignment deck) -- never invent.

### 4. Verification

- Browse to `/` (home) and `/customer-center/` while logged in -- verify logo, palette, and copy are applied.
- Run `git status` in `<demo>\` -- verify NO `.cs` files changed in `Controllers/` or `Providers/` (would have tripped the customisations-ledger preflight in base) and NO `.scss` / `.ts` files changed (recompilation drift).
- `.cshtml` changes are NOT automatically a problem -- new content layouts alongside standard templates are part of the §Pixel-perfect escalation ladder ([`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9). The thing to avoid is **modifications** to existing standard `.cshtml`. Use `git diff` to confirm `.cshtml` changes are net-new files, not modifications to baseline files.
- If a `<customer>_custom.css` was edited: that's the doc-canonical override slot, expected. Verify it lives at `Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css` and is loaded by a `Custom/<customer>HeadInclude.cshtml` wired to the Master area's `CustomHeadInclude` field. Stock `Custom/custom.css` must remain the hotpink placeholder — run `git diff --name-only -- '*custom.css'` and confirm the only hit is `<customer>_custom.css`.
- **Image-band height is a Tier-1 (hard) re-skin item — cap it, do not eyeball it.** The stock `Swift-v2_Image` band and the slider cover-card carry no serialized height field, so a swapped-in photo renders at full column-width height, uncapped, and towers over the fold. Every re-skin that changes photography reproduces this. The durable fix is a Tier-1 (`<customer>_custom.css`) CSS cap on the image wrapper and the slider cover-card — `aspect-ratio` + `max-height: min(60vh, 640px)` + `object-fit: cover`. A full-bleed hero may legitimately fill the fold; a content-band image must not. Definition of done: no image band taller than the configured fraction of the viewport, measured by the `tall` detector in [`visual-qa.md`](../../dw-demo-base/references/visual-qa.md) — that mechanical check is the sign-off, not a screenshot glance.
- **Verify shipped CSS in the CSSOM, not on disk.** A rule can round-trip byte-identical and still not exist in the browser — see [§CSS that silently never reaches the browser](#css-that-silently-never-reaches-the-browser) for the four causes and the two asserts (string-aware comment scan + per-block CSSOM marker) that catch them.
- **Run the mobile pass before "ready".** A re-skin that looks clean at desktop routinely stretches the phone canvas — fixed-width mega-menu, non-wrapping footer/USP rows, `.flex-fill` beating the column bases you just set. The canvas-fit method (measure `document.body.scrollWidth`, not documentElement), the Swift 2.4 trap catalogue, and the Tier-1 fixes (which land in this same `<customer>_custom.css` slot) live in [`mobile-pass.md`](mobile-pass.md). On theme-default ≥1.2.0 most fixes already ship — that pass is a verification, not a re-derivation.

## Scoping hooks — one content page vs the whole catalog

`Swift-v2_Master.cshtml` emits `<body data-dw-page-id="@Model.ID" data-dw-itemtype="@Model.Item?.SystemName?.ToLower()">`. Content pages render itemtype `swift-v2_page`; the shop root, **every** PLP and **every** PDP all render `swift-v2_shop`. That gives every Swift build two collision-free discriminators, and no shipped rule uses either:

- `body[data-dw-page-id="<id>"]` — exactly one content page (give a single page a different voice).
- `body[data-dw-itemtype="swift-v2_shop"]` — the entire catalog in one selector.

Definition of done for a split like this is a computed-style **leak check in both directions** (a catalog-only property must not move on a content page, and vice versa), not a screenshot of each side.

There is a third discriminator for **admin-editor-only** chrome: a `body` hook emitted from the layout master under `Pageview.IsVisualEditorMode`, styled as `body.dw-ve …` here. It is server-side and auth-gated, so it cannot leak to visitors — and admin-only rules must add **offset, never background**, or they flip a design gate's overlay-header classification on the live storefront. Full recipe: [templates.md](templates.md) §"Branching a template on Visual Editor mode".

## A palette swap is a multi-file, multi-notation sweep

Editing the accent tokens in `<customer>_custom.css` recolours eyebrows, links, underlines and icon tiles — and leaves every primary button, every low-alpha tint and every fallback on the outgoing colour. That reads as a half-finished rebrand, and the buttons are the largest single colour area on the site. Chase all five copies:

1. **The generated colour-scheme stylesheet.** Swift buttons paint from `--dw-color-button-primary`, which a hand-authored theme sheet never declares — it is declared in `/Files/System/Styles/ColorSchemes/<design>.css`, and that file hardcodes the colour as **both a hex and an `rgb` triplet, once per scheme** (7 schemes = 14 literals). A custom sheet loaded later cannot override a variable it never mentions. Do **not** work around it by declaring `--dw-color-button-primary` in the custom sheet: that leaves the generated file lying, the admin Styles swatch stale, and the next design save reverts the site.
2. **The `.json` model beside it.** The generated `.css` is emitted from a sibling `<design>.json` (`Schemes[].{Id, BackgroundColor, ForegroundColor, PrimaryButtonColor, SecondaryButtonColor, CustomColors}`) — the editor writes both in one operation (identical `Last-Modified`). Hand-edit the `.json` in the same pass, parse it in pre-flight, and assert every scheme carries the new value. See [`styles-assets.md`](styles-assets.md).
3. **`rgba()` literals.** A custom property cannot express an alpha variant of itself without `color-mix()` or split channel tokens, so authors write `rgba(<r>, <g>, <b>, .08)` inline for hover washes, focus tints and row hovers. Those literals contain neither the token name nor the hex form, and being low-alpha they pass review by eye. **Grep the colour in every notation** — hex, hex+alpha, and `"r, g, b"` with flexible whitespace — for every member of the accent family, and assert an exact expected count per pattern so a changed sheet aborts instead of half-applying.
4. **`var()` fallbacks.** `var(--accent, #OLD)` stores the value twice; updating the token leaves the fallback as a stale second source of truth that paints whenever the property fails to resolve — invisible in normal rendering, a flash of retired brand if the sheet is slow or blocked. Grep the retired value *inside* `var(...)` specifically; prefer no fallback, or one naming a still-current token.
5. **Retired tokens — alias, never delete.** DB-authored content carries inline `style="background-color:var(--brand-blue)"`, and a `HeadInclude.cshtml` `<style>` block commonly re-declares the same token for cache resilience. Deleting the token from the custom sheet leaves the template `<style>` as its only definition and the content falls back to the old colour. Re-point it instead:

```css
:root { --brand-blue: var(--brand-accent) !important; }   /* backward-compat alias */
```

`!important` on a custom property is legal and beats a same-specificity `:root` declared in a template `<style>` block **regardless of source order** — which is what makes the alias work without touching content or templates.

Deploy shape: pre-flight scans **all** payload files for a combined regex over every retired value in both notations and refuses to upload on a hit; the post-upload check re-runs the same regex against the **served** files. Sign-off is a pixel scan of the outgoing hue band across the design's page set × both viewports × anon/signed-in — and a control run that re-serves the pre-deploy CSS through the same renderer, to prove the detector still fires.

## CSS that silently never reaches the browser

Four ways a rule ships, round-trips byte-identical, passes a sentinel census — and does not exist in the browser. A byte-level check cannot see any of them.

- **A comment terminator inside comment PROSE closes the comment early.** Prose like `palette + F1/F2/W*/H1/H2 all untouched` contains a literal `*/`, ending a banner comment ~11 lines before its real terminator. The orphaned prose becomes a selector prelude, and the parser error-recovers by consuming tokens **up to and including the next `{...}` block** — silently discarding the following real rule. The file contains no *unterminated* comment, which is exactly why byte checks and sentinel counts miss it. Scan the candidate before upload and the re-downloaded sheet after, **string-aware** so `content:"*/"` and `url()` do not false-positive — a detector that cries wolf gets switched off. A regex like `[A-Za-z0-9]\*/` is not good enough: it false-negatives on a terminator preceded by punctuation or whitespace.
- **A numeric-leading id selector does not parse.** A CSS ID selector needs a `<hash-token>` of type "id"; a hash starting with a digit is *unrestricted*, so `#12345` is an invalid selector and the parser drops the **whole rule** (`querySelector("#12345")` throws; the same happens inside `:has()`). Every Dynamicweb paragraph / page / row id is numeric, so any rule keyed on one hits this. Use the attribute form `[id="12345"]`. Reject the escape `#\31 2345` — it parses, but the trailing space is load-bearing and any editor or minifier that strips it destroys the rule just as silently.
- **`:has()` with a descendant combinator matches every ancestor.** `section[data-swift-gridrow]:has([data-dw-itemtype="…"])` also matches the hero row *and* the top-level 1Column row that contains the whole page, because `:has()` searches the entire subtree. A `display:none` on that selector blanks the page: document height collapses to exactly the viewport height with header and footer still painting. Anchor the rule to a **direct child** of the owning component and reach the slot through an explicit `> [data-swift-container] >` chain; count the matches in the browser (intended 1, not 3) before shipping.
- **A sentinel block nested inside another is a pending deletion.** Deploy scripts strip their block with a DOTALL `BEGIN`→`END` regex that knows nothing about nesting, so a strictly-contained inner pair is genuinely deleted — and a per-brief verify that names only its own sentinel exits 0 green. Keep every sentinel pair a **sibling**, give each block its own **tracked** source file (plus `*.css text eol=lf` in `.gitattributes`, so a Windows clone cannot CRLF a byte-exact append source), and replace the per-brief verify with a generic one: every sentinel present before the write is present **exactly once** after it, and no span nests inside another — enforced pre-flight (refusing to upload) and again against the served sheet.

Because of all four, **a CSS deploy must assert CSSOM rule presence**: for each shipped block, assert its marker rule is actually in `document.styleSheets`, recursing into `@media`/`@supports` groups and indexing each arm of a grouped selector separately. Asserting a fixed expected rule *count* is not a substitute — it needs a hand-maintained number, rots on every legitimate edit, and never says *which* rule vanished. Pair it with a post-deploy smoke that renders a few real pages and fails on content collapse (`docH >= per-page floor`, `main.innerText >= 400 chars`), horizontal overflow, or a CSSOM rule-count **drop**. Keep the deploy-side scanner and the gate-side detector algorithmically identical so the two can never disagree.

## Overriding Swift/Bootstrap-managed layout

Bootstrap utilities are declared `!important` — `.flex-fill` is `flex: 1 1 auto !important`, and `.d-flex`, `.gap-*`, `.order-*` likewise. Swift puts them on whichever grid column it manages, so **an authored override loses to them no matter how specific the selector**: `!important` beats specificity. There is no parse error and no CSSOM change, so the rule reads as deleted. The signature is that the declaration block *did* apply — sibling declarations read back fine — and only the contested property lost (`display` reads `flex` while `grid-template-columns` reads back your value).

- **Grep the rendered column for utility classes before authoring a flex/display/order override.** Then mark `display`, `order` and `flex` `!important` — and *only* those, never colour, spacing or typography.
- **Mark the counterpart rule in the wider tier `!important` too**, so the later source-order rule still wins. If only one tier is `!important`, the layout tier and the clearance tier disagree across a band of viewport widths: a nav meant to drop onto its own line below a breakpoint instead stays inline until it happens not to fit, while the two-line clearance token already applies — a white gap that appears and disappears over a ~32px band.
- **Assert the computed value, never the presence of the declaration.** `getComputedStyle(el).display === "grid"`; equal left positions across all rows; and sweep viewports across the breakpoint asserting the number of distinct flex **lines** (count of distinct rounded column tops) flips exactly at the media-query edge, with the clearance token matching the measured bar height at every sampled width on both sides.
- **Line-view rows need `min-width: 0` and a bounded title.** In a `nowrap` flex row whose other columns are fixed and non-shrinkable (image + SKU + a `flex: 0 0 280px; flex-shrink: 0` description + stock + price + gaps), the product title is the only `flex-shrink: 1` child, so it absorbs the whole overcommit: it collapses to `width: 0` with `overflow: visible`, stacks one word per line (7–9 line-boxes tall) and paints across the description lane. Give the title a real basis and a floor (`flex: 0 1 320px; min-width: 180px`) plus a hard 2-line `-webkit-line-clamp`, and make the description a shrinkable single-line ellipsis lane (`flex: 1 1 140px; min-width: 0`). Assert per row that the title box does **not** intersect the description box and that the title is ≤2 lines, at 1440 and 390.

## Floating / overlay header — hero behind the bar

**Swift 2.4 exposes no native transparent/overlay-header switch.** The header renders as `header[data-swift-page-header].sticky-top` — `position: sticky`, in flow — with its colour coming from a per-section `data-dw-colorscheme="dark"`; no admin or Visual Editor setting makes it transparent. A floating-bar-over-hero motif is therefore CSS-only, and it is brand-generic enough to belong in `default_custom.css` rather than per-customer:

```css
[data-swift-page-header]        { position: fixed; background: transparent; padding: <top> <inset> 0; }
[data-swift-page-header]::before{ /* the pill: border-radius, brand fill — NO overflow:hidden */ }
[data-swift-page-header] section{ background: transparent; }   /* invisible seam across the header rows */
main                            { padding-top: var(--bar-clearance); }
main:has(> section:first-child [data-swift-poster]) { padding-top: 0; }  /* poster flows behind */
```

`overflow: hidden` on the pill (the reflex for clipping a border-radius) clips the megamenu and dropdowns — never use it here, and keep a standing guard against **any** `overflow` declaration inside header-scoped rules.

- **Key the clearance token on the served DOM, not on a breakpoint.** Dynamicweb serves two different header content pages and picks between them **server-side by user-agent**, not by viewport width: a phone UA receives a 2-row (~84px) header carrying `swift-v2_offcanvasnavigation`, while a desktop UA **at the same 390px width** receives a 3-row (~177px) header carrying `swift-v2_menurelatedcontent`. A media query cannot tell the two documents apart — they arrive at identical widths — so a breakpoint-keyed token is fitted to whichever document happened to be measured and is silently wrong for the other (a ~94px dead band above every page on real phones and tablets, while four consecutive headless passes measured 1px). Select on the DOM instead, outside any media query:

  ```css
  body:has([data-swift-page-header] [data-dw-itemtype="swift-v2_offcanvasnavigation"]) {
    --bar-clearance: calc(var(--bar-top) + var(--bar-h-phone));
  }
  ```

  Specificity (0,2,1) beats `:root` (0,1,0) and `body` sits closer to `main` in the inheritance chain, so it wins regardless of source order. Single non-nested `:has()`; if `:has()` is unsupported the `:root` default applies — over-clearance, not a broken layout. Because it keys on the DOM it self-corrects at every width, which is why it fixes tablets without a tablet rule. Do **not** simply re-fit the breakpoint token: that breaks the narrow desktop browser, which legitimately receives the 3-row header at the same width. Assert clearance (`firstContent.top - header.bottom`, threshold −2..24) at every viewport **with a real device descriptor**, keeping a desktop-UA control at the same width.
- **Budget the gutters against the container's own −32px.** `[data-swift-container]` sets `max-width: calc(-32px + min(<cap>, 100%))` — 32px narrower than its parent — then centres itself with auto margins, which below the cap resolve to **16px per side**. The real left offset is `inset + 16 + container padding`, so any budget computed as `viewport − 2·inset − 2·padding` is 32px optimistic and a gutter tweak visibly under-delivers. Override to `max-width: min(<cap>, 100%)` — preserve the cap itself, it is the composition's max content width — and assert the first column's left edge equals `inset + padding` and computed `marginLeft` is `0px`.
- **Icon-only header controls: `clip` + `clip-path`, not the classic sr-only idiom.** The traditional visually-hidden recipe predates `clip-path` and uses `overflow: hidden`, which the header guard above bans. `clip-path: inset(50%)` crops the 1×1 box identically with no `overflow` declaration, so the constraints never actually conflict: `position:absolute; width:1px; height:1px; clip:rect(0 0 0 0); clip-path:inset(50%); white-space:nowrap`. Never `display:none` or `font-size:0` — both strip the accessible name. Assert (a) no `overflow` declaration in header-scoped rules, (b) the megamenu opens with no ancestor computing `overflow-y != visible`, (c) the control's accessible name is non-empty.
- **A fixed-vh poster behind a fixed bar has viewport-UNSTABLE clearance.** `object-fit: cover` on a wide fixed-height box is **width**-driven, so the subject's vertical position scales with viewport width while the bar height is a fixed px value: the same sheet and image measured ~2px of sky above the subject at 1280/1440 and ~80px at 1920. A focal-point nudge clears the bar at one width and re-breaks at another — it cannot be fixed from the focal point. Pair a **top-anchored crop** (`object-position: 50% 0%`) with a master image that carries deliberate sky headroom (subject in the lower third) and a page-scoped first-row height cap kept under the design gate's band-height guard. Verify measured clearance at four widths, not one.

## Section-boundary decoration — negative-top pseudo-elements

- **A boundary wave at `top: calc(-1 * H)` paints in the PREVIOUS section's space**, so its fill only reads if that band is uniform *and* contrasting: over a same-colour band it disappears into a straight edge; over a two-column image+text band it reads as a muddy vertical seam. Position boundary shapes at `top: 0` so the filled crest paints **inside its own section** over a uniform band and the straight edge butts the neighbour. For a footer wave, keep it above the footer but drop any `scaleY(-1)` flip so the fill is flush and leaves no trough gap. Read the tight wave crops back at both viewports — never self-approve a wave from the full-page shot.
- **A pseudo-element with a negative `top` paints above its owner's border box**, so every clearance check built on element boxes reports healthy headroom while the shape covers real controls: a footer wave at `top:-71px; height:72px` swallowed 51px of a 44px-tall CTA pill while `main.bottom` and `footer.top` agreed on "20px clear", and a 49-assert geometry sweep passed over it. Compute `paintedTop = ownerTop + min(0, parseFloat(::before top))` in the assert and require real clearance to the lowest interactive control. Fix the page rhythm (`main { padding-block-end: clamp(88px, 8vw, 128px) }`), not the motif — a shipped brand shape that is correct on every other page is not the defect.

## Utility classes lose to scheme-scoped element rules

A theme's body-copy softener — `main [data-dw-colorscheme=light|lightgrey1|lightgrey2] p { color: rgba(...) }` at specificity (0,1,2) — out-specifies any bare utility class at (0,1,0). So an eyebrow/kicker utility applied as `<p class="eyebrow">` renders body-copy colour on **every** light band while looking correct on the dark band (where `[data-dw-colorscheme=dark] .eyebrow` is (0,2,0) and no dark softener exists) — a failure that reads as "the class doesn't work sometimes".

Author kickers as a non-`<p>` element (`<span class="eyebrow">`), and in the theme either bump the utility's specificity or exclude it from the softener: `main [data-dw-colorscheme] p:not(.eyebrow)`. The same trap applies to any single-class utility competing with a scheme-scoped element selector.

## In-page anchors — `<base href>` breaks every bare fragment

DW core emits `<base href="https://<host>/">` into the document head via `@Model.MetaTags` — it is **not** a line in `Swift-v2_Master.cshtml`, so it cannot be removed from the master template. A bare fragment URL resolves against the document **base** url rather than the current one, so `href="#specifications"` resolves to `https://<host>/#specifications`: clicking an anchor-strip tab navigates to the homepage instead of scrolling, while the strip looks correct and the target `id`s are genuinely present (the same fragment appended to the page URL scrolls fine).

A static absolute `href` cannot fix it — one paragraph renders for every product URL. Repoint each href at runtime to `location.pathname + location.search + "#id"` and perform the scroll. Assert per bare-fragment link: click it, then `location.pathname` unchanged **and** `scrollY > 0` — and run it over every fragment link in nav, footer and TOCs, not just the strip you built, because `<base>` breaks bare fragments sitewide.

## Conditional-collapse CSS — hide empty bands with sibling `:has()` pairs, not nested `:has()`

When a PDP/PLP band must hide only when it is empty (an empty `productbom` / `productmediatable` shell on a sparse product, while the same band renders on a populated one), write the condition as **sibling `:has()` / `:not(:has())` pairs on one selector** — never one `:has()` nested inside another. A selector that nests `:has()` inside `:has()` (e.g. `section:has(.x:has(a))`) is **invalid per the CSS spec; the browser drops the entire rule silently** — no console error, and adjacent valid rules from the same block (a color tweak, say) still apply, so it reads as a baffling split failure. `Element.matches(<nested-selector>)` throws `SyntaxError` in Chromium — that's the fast confirmation. Use the flat sibling form instead:

```css
/* collapse the band only when it has the wrapper but no populated child */
section[gridrow]:has(.productbom):not(:has(.productbom .bom-row)) { display: none !important; }
```

Anchor the flat form to a direct-child chain as well — a bare descendant argument inside `:has()` matches every ancestor row up to the one wrapping the whole page (see [§CSS that silently never reaches the browser](#css-that-silently-never-reaches-the-browser)), so an over-matching collapse rule blanks the page instead of one band.

The `!important` is load-bearing, not lazy: Swift grid rows carry attribute selectors like `[gridrow][container][gridcolumn]{display:flex}` at specificity `0,3,0`, which beats a plain `display:none` (`0,1,0`). A conditional-collapse `display:none` must be `!important` (or match the attribute specificity) to win. Definition of done: empty bands hidden on sparse products, populated bands still render, and zero overflow at 1440 + 390 (the [`mobile-pass.md`](mobile-pass.md) canvas-fit check). This CSS lands in the Tier-1 `<customer>_custom.css` slot.

## What this recipe does NOT do

- Does not re-derive a customer-specific baseline (that is the demo's data-phase concern, project-specific; see the demo's `.planning/` if it tracks phases).
- Does not seed customer-flavoured products (same -- project-specific data phase, not a Swift skill concern).
- Does not customise the customer-center CSR section -- that's stock per the SKILL.md top-level rule and the [customer-center.md](customer-center.md) playbook (the stock-CSR rule). Even when the §Pixel-perfect escalation authorises new content layouts elsewhere, the CSR section's stock paragraphs are exempt -- see customer-center.md §1.
- Does not touch SCSS source or recompile the Swift asset pipeline. Use `<customer>_custom.css` as the override slot (loaded after `swift.css`).
