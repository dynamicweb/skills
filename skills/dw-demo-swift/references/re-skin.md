# re-skin.md

> Customer-themed re-skin recipe for a Swift 2 baseline. Defaults to the configuration-only path (admin UI Visual Editor + theme tokens -- see [admin-ui-authoring.md](admin-ui-authoring.md)). Escalation ladder when configuration falls short: (1) project-scoped CSS overrides at `Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css` consuming the `--dw-*` variables Dynamicweb generates from admin; (2) layout-only `.cshtml` content-layouts for tailored screens; (3) controller/provider `.cs` triggers base's customisations-ledger preflight ([dw-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md)).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Contents

- [What this file owns vs. what moved to the foundational skill](#what-this-file-owns-vs-what-moved-to-the-foundational-skill)
- [The escalation ladder](#the-escalation-ladder)
- [The `<customer>_custom.css` naming hard rule](#the-customer_customcss-naming-hard-rule)
- [Re-skin smell: "Swift-v2_Text shim + foreign cshtml"](#re-skin-smell-swift-v2_text-shim--foreign-cshtml)
- [Step 0 — the zero-state pass](#step-0--the-zero-state-pass)
- [Recipe](#recipe)
- [Scoping hooks — one content page vs the whole catalog](#scoping-hooks--one-content-page-vs-the-whole-catalog)
- [A palette swap is a multi-file, multi-notation sweep](#a-palette-swap-is-a-multi-file-multi-notation-sweep)
- [CSS that silently never reaches the browser](#css-that-silently-never-reaches-the-browser)
- [Overriding Swift/Bootstrap-managed layout](#overriding-swiftbootstrap-managed-layout)
- [Grid galleries and thumbnail strips](#grid-galleries-and-thumbnail-strips)
- [Floating / overlay header — hero behind the bar](#floating--overlay-header--hero-behind-the-bar)
- [Section-boundary decoration — negative-top pseudo-elements](#section-boundary-decoration--negative-top-pseudo-elements)
- [Utility classes lose to scheme-scoped element rules](#utility-classes-lose-to-scheme-scoped-element-rules)
- [In-page anchors — `<base href>` breaks every bare fragment](#in-page-anchors--base-href-breaks-every-bare-fragment)
- [Conditional-collapse CSS — hide empty bands with sibling `:has()` pairs](#conditional-collapse-css--hide-empty-bands-with-sibling-has-pairs)
- [Selector reach — scope what hides content, comment what counts children](#selector-reach--scope-what-hides-content-comment-what-counts-children)
- [Row colour schemes paint the SECTION, not the paragraph](#row-colour-schemes-paint-the-section-not-the-paragraph)
- [Colour contrast — resolve the EFFECTIVE alpha before darkening anything](#colour-contrast--resolve-the-effective-alpha-before-darkening-anything)
- [A workaround block must name the condition that retires it](#a-workaround-block-must-name-the-condition-that-retires-it)
- [What this recipe does NOT do](#what-this-recipe-does-not-do)

## What this file owns vs. what moved to the foundational skill

Vendor-generic Swift re-skin doctrine is now owned by the foundational skills:

- **The "never edit standard templates" never-touch list + allowed override slot, the item-type + variant + CSS "separate the styling from the content" pattern, the Pixel-perfect "what you may / may not create" escalation, and the Pre-escalation "search the source first" check** — owned by the `dw-swift-building` foundational skill, owned by [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §9 ("Re-skin doctrine").
- **`CustomHeadInclude` + `?<ticks>` static-token wiring** — owned by [`razor-surfaces-and-pitfalls.md`](../../dw-render-razor/references/razor-surfaces-and-pitfalls.md) §3.
- **Color schemes architecture + cascade** (including silent scheme-name typo resolution to `data-dw-colorscheme=""`) — owned by [`razor-surfaces-and-pitfalls.md`](../../dw-render-razor/references/razor-surfaces-and-pitfalls.md) §4.
- **CSS pitfalls** (over-broad `[data-dw-button]`, bare `footer { }`, emoji color-font, header brand-bar vs colorscheme rules, webfont vendoring for `--dw-font-family`) — owned by [`razor-surfaces-and-pitfalls.md`](../../dw-render-razor/references/razor-surfaces-and-pitfalls.md) §5.
- **Custom variant filename-sort hijack of empty-`ParagraphTemplate` paragraphs** — [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §4; the verification step for any re-skin that adds a custom variant must check this.

This file keeps the demo-specific spine: the zero-state pass, the escalation ladder, the `<customer>_custom.css` naming hard rule, the customisations-ledger preflight, and the customer-themed Recipe.

## The escalation ladder

**The ladder starts FROM `theme-default`** — the single presentation layer every edition composes (no theme choice, no overlay layers in the Distribution). Stage its `files/` onto the host first ([`styles-assets.md`](styles-assets.md)): it carries the default Styles JSON+CSS pairs, `default_custom.css` (including the header-nav affordance core — [`header-menu.md`](header-menu.md)), and `DefaultHeadInclude.cshtml`. Customer overrides go in `<customer>_custom.css`, never by editing `theme-default`'s own files.

| Tier | Surface | What it touches | Owner |
|------|---------|-----------------|-------|
| 0 | Admin UI Style Tools (Settings → Content → Styles) | Color schemes, button shape, typography — generates the `Styles/*.{json,css}` pairs | [styles-assets.md](styles-assets.md) + [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §7 |
| 1 | `Custom/<customer>_custom.css` | Brand variables, hover states, hacks the schemes don't cover | this file (naming rule below) + [`razor-surfaces-and-pitfalls.md`](../../dw-render-razor/references/razor-surfaces-and-pitfalls.md) §3 (wiring) |
| 2 | New layout-only `.cshtml` content layouts | Pixel-perfect reshaping of an item type's render | [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §9 |
| 3 | Controller / provider `.cs` (customisations-ledger preflight) | Anything that needs server-side logic | [dw-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md) |

Before climbing the ladder, run the Pre-escalation "search the source first" check in [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §9 — most "I need a custom template" reflexes resolve to a canonical surface (permission entity store for role gates, `Page.Loaded` subscriber for redirects, `CustomHeadInclude` for a project stylesheet, `Pageview.User.*` for identity).

## The `<customer>_custom.css` naming hard rule

**Brand CSS goes in `<customer>_custom.css` — never in a file named `custom.css`.** Swift ships `Custom/custom.css` as a placeholder template (`body { background: hotpink !important; }`) and the design-css doc's load-order example shows an `Assets/css/custom.css` — both are Swift sample code. Writing brand CSS into a file named exactly `custom.css` breaks the shipped sample and turns the upgrade story into a merge instead of a file-drop. Create the customer-named sibling — same naming discipline as the `<Prefix>_*` item types:

- The override file: `Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css`
- Wired via a head-include partial: `Custom/<customer>HeadInclude.cshtml` registered on the Master area's `CustomHeadInclude` field (the `AddStylesheet` wiring + the `?<ticks>` static-token caveat live in [`razor-surfaces-and-pitfalls.md`](../../dw-render-razor/references/razor-surfaces-and-pitfalls.md) §3 — put demo-critical CSS in an inline `<style>` block where the cache-buster is static).

Verification: `git diff --name-only -- '*custom.css'` must never show a path ending in `custom.css` other than `<customer>_custom.css`. Any file named exactly `custom.css` in the diff is a re-skin bug — revert it and move the rules (this is grep #9 of the discipline audit in [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §10).

## Re-skin smell: "Swift-v2_Text shim + foreign cshtml"

Symptom: a paragraph template path like `Templates\Designs\Swift-v2\Paragraph\Swift-v2_Text\<Project>SomeName.cshtml` that has nothing to do with text. The paragraph is created as Swift Text in admin, then the template path is overridden to point at this file. The editor sees only Title/Subtitle/Text fields; the template ignores most of them and bakes the real fields as hardcoded literals.

Fix: define a `<Prefix>_<ConceptName>` custom item type — see [`modelling-discipline.md`](../../dw-content-modelling/references/modelling-discipline.md) §2 ("Custom item types — the `<Prefix>_*` discipline") and the separate-the-styling-from-content pattern in [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §9.

## Step 0 — the zero-state pass

**Run this pass immediately after [`deserialize-flow.md`](deserialize-flow.md) and before any brand work.** A freshly deserialized baseline is a complete, plausible site whose every surface belongs to the *shipped* demo: every band renders, every page answers `200` — but the title, hero, features cards, editorial band and header/footer wordmark are all the shipped vertical's. A structural gate passes over all of it, and brand work on top of an un-zeroed baseline just re-paints the shipped demo. The fix is mechanical: stock copy is a **fixed, greppable string set**, an unwritten item field renders its declared `defaultValue`, and an empty band is detectable from the served markup.

### Step 0.1 — Inventory the stock surfaces (tripwire grep)

Fetch the served HTML of the storyline page set and grep it for the shipped baseline's own copy — a hit means that surface has never been authored for this prospect:

| Tripwire | Surface it exposes |
|---|---|
| `Swift Frontpage` | the frontpage `<title>` / meta title, never re-titled |
| `Latest travel guides` | the editorial/blog band, still pointed at the shipped article set |
| `One Pedal at a Time` | shipped article titles behind that band |
| `Whether it's in our homes` | the USP / features band rendering an unwritten field's `defaultValue` |
| `High Quality Products and Parts` | the shipped hero headline |
| `Swift` inside `header`/`footer` brand slots | the platform wordmark still standing in for the customer mark |

```powershell
$pages   = @('/', '/shop', '/customer-center')      # plus every storyline page and language prefix
$tripwire = 'Swift Frontpage|Latest travel guides|One Pedal at a Time|Whether it''s in our homes|High Quality Products and Parts'
$hits = foreach ($p in $pages) {
  $html = (Invoke-WebRequest -Uri "$baseUrl$p" -SkipCertificateCheck).Content
  [regex]::Matches($html, $tripwire) | ForEach-Object { [pscustomobject]@{ page = $p; hit = $_.Value } }
}
$hits    # definition of done: empty
```

Extend the list with any string the composed edition adds — the check is the *shape*, not these six rows. Grep the served HTML rather than the database: a string can reach the page from an item field, a template default, or a shipped article the band still points at, and only the render sees all three.

### Step 0.2 — Retire the identity strings

Three first-class steps, each visible in the first five seconds of a demo — never left "for polish":

1. **Frontpage title and meta title** — `save_pages` with the customer's own `metaTitle`; assert the served `<title>` no longer matches the tripwire list.
2. **Area name** — surfaces in admin, the page tree, and generated meta; set it to the customer slug.
3. **Header and footer brand** — the logo asset *and* the wordmark text. The footer brand is a separate paragraph from the header one and is the one that survives a logo swap. Assert both from the served `header` and `footer` fragments, not the logo field.

### Step 0.3 — Resolve every `defaultValue` field

**An item-type field that was never written renders its declared `defaultValue`, and shipped `defaultValue`s read as plausible marketing copy — an unauthored field is indistinguishable from an authored one on screen.** That is what produces a features band whose three cards carry the same sentence: one field, three paragraphs, none written. Resolve per item type, not per page: read the type's field definitions (`get_item_type` / the Management API item-type surface) and list every field with a non-empty `defaultValue`; for each paragraph of that type on the storyline pages, an **empty stored value with a non-empty rendered string** is an unwritten field — write the customer's value or clear the `defaultValue` on the definition. Check the feature/USP card, slider item and accordion/FAQ item first (the usual copy-shaped defaults), then sweep the rest. Assert: no two siblings of the same item type render byte-identical body copy — identical siblings are the signature of an unwritten field.

### Step 0.4 — Rewire or delete every empty band

**A band whose data source is empty gets rewired or deleted — never left standing as a skeleton.** Once shipped fixture content is removed, the bands that pointed at it keep rendering (four empty editorial cards, an FAQ heading over nothing) and read as a broken site. Detect from the served markup, per band:

```js
// run against each storyline page; a band with a heading and no content children is a skeleton
[...document.querySelectorAll('section[data-swift-gridrow]')]
  .map(s => ({
    heading: s.querySelector('h1,h2,h3')?.innerText?.trim() ?? '',
    cards:   s.querySelectorAll('article, .card, [data-dw-itemtype]').length,
    text:    s.innerText.replace(/\s+/g, ' ').trim().length
  }))
  .filter(b => b.text < 40 || (b.heading && b.cards === 0));   // definition of done: empty
```

Three dispositions, in preference order: **rewire** at the customer's own data (real articles, real FAQ entries, a real product query); **delete** the row when no equivalent content exists; **hide** only when the band returns in a later brief, recording the condition that retires the hide ([§A workaround block must name the condition that retires it](#a-workaround-block-must-name-the-condition-that-retires-it)).

### Step 0.5 — Prove the catalogue has pixels

`document.images.length` on the frontpage and shop landing catches the whole class: a seeded catalogue with no attached assets renders as grey placeholder tiles, and every structural PLP assert passes over it. Assert a floor per surface (`> 0` on the frontpage, a per-category coverage target on the PLP) in this pass, not at polish. Sourcing the imagery is its own brief — [`asset-organisation.md`](asset-organisation.md) "Catalogue imagery is its own brief"; what belongs here is only the measurement.

### Step 0.6 — Arm the asserts on gate run one

**Design verification is a property of every gate run, not of the design brief** — an unconfigured design leg stamps `SKIP` and reports `PASS` over overflow, skeleton bands and shipped copy. Three legs arm from the first run against a raw deserialize, with no custom design configuration:

1. **Overflow** — `document.body.scrollWidth === window.innerWidth` at desktop and mobile widths.
2. **Skeleton / empty-band scan** — the Step 0.4 detector, over the storyline page set.
3. **Stock-copy tripwire** — the Step 0.1 regex, over the served HTML.

Cover **every language prefix the build serves**: chrome copy is longer in some languages, so a translated header can carry a constant horizontal overflow on every page of that language while default-language pages measure clean — an overflow value *constant per language and independent of page content* is the tell that it lives in chrome. Expected first result on a raw baseline is **FAIL on all three** — the pass is earned by fixing them, never by leaving a leg unconfigured ([`../../dw-demo-base/references/orchestrator.md`](../../dw-demo-base/references/orchestrator.md) "Acceptance criteria").

## Recipe

Operates on a deserialized Swift 2.4 composition (framework-only `base` + `surface-swift` content, resolved into a running host via this skill's [`deserialize-flow.md`](deserialize-flow.md)) with `theme-default` staged and the zero-state pass (Step 0 above) done. All steps are admin UI only. Throughout: `<customer>` is the demo customer's short slug (lowercase, no spaces).

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
- Run `git status` in `<demo>\` -- NO `.cs` changes in `Controllers/` or `Providers/` (would trip the customisations-ledger preflight) and NO `.scss` / `.ts` changes (recompilation drift). `.cshtml` changes must be net-new content layouts (the §Pixel-perfect escalation, [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §9), never modifications to existing standard `.cshtml` — confirm with `git diff`.
- If a `<customer>_custom.css` was edited: expected — verify its path and its `Custom/<customer>HeadInclude.cshtml` wiring per the naming rule above, and that stock `Custom/custom.css` remains the hotpink placeholder (`git diff --name-only -- '*custom.css'` hits only `<customer>_custom.css`).
- **Image-band height is a Tier-1 (hard) re-skin item — cap it, do not eyeball it.** The stock `Swift-v2_Image` band and the slider cover-card carry no serialized height field, so a swapped-in photo renders at full column-width height and towers over the fold; every re-skin that changes photography reproduces this. Fix: a Tier-1 CSS cap on the image wrapper and the slider cover-card — `aspect-ratio` + `max-height: min(60vh, 640px)` + `object-fit: cover`. A full-bleed hero may fill the fold; a content-band image must not. Definition of done: no image band taller than the configured viewport fraction, measured by the `tall` detector in [`visual-qa.md`](../../dw-demo-base/references/visual-qa.md).
- **Verify shipped CSS in the CSSOM, not on disk** — see [§CSS that silently never reaches the browser](#css-that-silently-never-reaches-the-browser).
- **Run the mobile pass before "ready".** A desktop-clean re-skin routinely stretches the phone canvas — fixed-width mega-menu, non-wrapping footer/USP rows, `.flex-fill` beating the column bases you just set. Method, trap catalogue and Tier-1 fixes: [`mobile-pass.md`](mobile-pass.md). On theme-default ≥1.2.0 most fixes already ship — that pass is a verification, not a re-derivation.

## Scoping hooks — one content page vs the whole catalog

`Swift-v2_Master.cshtml` emits `<body data-dw-page-id="@Model.ID" data-dw-itemtype="@Model.Item?.SystemName?.ToLower()">`. Content pages render itemtype `swift-v2_page`; the shop root, **every** PLP and **every** PDP all render `swift-v2_shop`. That gives every Swift build two collision-free discriminators, and no shipped rule uses either:

- `body[data-dw-page-id="<id>"]` — exactly one content page (give a single page a different voice).
- `body[data-dw-itemtype="swift-v2_shop"]` — the entire catalog in one selector.

Definition of done for a split like this is a computed-style **leak check in both directions** (a catalog-only property must not move on a content page, and vice versa), not a screenshot of each side.

**A component scoped by one of these hooks is scoped, not portable — record the SCOPE SELECTOR next to the class names.** Rules written `body[data-dw-itemtype="swift-v2_shop"] main .<component>` match nothing on a content page (`swift-v2_page`): the DOM is present, count-based asserts pass, the visitor sees unstyled text. Before reusing on a new surface, read the target page's `<body>` tag; extend scope with a **sentinel block at lower specificity** (declarations copied verbatim, scoped to the new component's own class) so the original scope still wins, and verify with computed style, anonymous and signed-in.

Third discriminator for **admin-editor-only** chrome: a `body` hook emitted under `Pageview.IsVisualEditorMode` (`body.dw-ve …`) — server-side and auth-gated, cannot leak to visitors. Admin-only rules must add **offset, never background**, or they flip a design gate's overlay-header classification on the live storefront. Full recipe: [templates.md](templates.md) §"Branching a template on Visual Editor mode".

**Never key a rule on `:first-child` (or any structural pseudo-class) among `main`'s children — Visual Editor mode injects a `<dw-placeholder>` as `main`'s first element child**, shifting every structural match by one inside the editor only ("the Visual Editor doesn't load my CSS"). Widen the selector (`main > :is(dw-placeholder + section, section:first-child)`) or key on the component (`main > section:has(> [data-swift-container] > [data-dw-itemtype="…"])`). Confirm by appending `visualedit=true` and reading `main.firstElementChild.tagName` (`DW-PLACEHOLDER` in VE); any VE-mode probe that walks children by index must skip the placeholder.

## A palette swap is a multi-file, multi-notation sweep

Editing the accent tokens in `<customer>_custom.css` recolours eyebrows, links and icon tiles — and leaves every primary button (the largest single colour area on the site), every low-alpha tint and every fallback on the outgoing colour. Chase all five copies:

1. **The generated colour-scheme stylesheet.** Swift buttons paint from `--dw-color-button-primary`, declared only in `/Files/System/Styles/ColorSchemes/<design>.css` — hardcoded as **both a hex and an `rgb` triplet, once per scheme** (7 schemes = 14 literals). A custom sheet loaded later cannot override a variable it never mentions — and do **not** declare `--dw-color-button-primary` in the custom sheet as a workaround: the generated file then lies, the admin Styles swatch is stale, and the next design save reverts the site.
2. **The `.json` model beside it.** The generated `.css` is emitted from a sibling `<design>.json` (`Schemes[].{Id, BackgroundColor, ForegroundColor, PrimaryButtonColor, SecondaryButtonColor, CustomColors}`) — the editor writes both in one operation. Hand-edit the `.json` in the same pass and assert every scheme carries the new value. See [`styles-assets.md`](styles-assets.md).
3. **`rgba()` literals** — inline `rgba(<r>, <g>, <b>, .08)` hover washes and focus tints contain neither the token name nor the hex form, and being low-alpha they pass review by eye. **Grep the colour in every notation** — hex, hex+alpha, and `"r, g, b"` with flexible whitespace — for every member of the accent family, asserting an exact expected count per pattern.
4. **`var()` fallbacks.** `var(--accent, #OLD)` stores the value twice; the stale fallback paints whenever the property fails to resolve. Grep the retired value *inside* `var(...)`; prefer no fallback, or one naming a still-current token.
5. **Retired tokens — alias, never delete.** DB-authored content carries inline `style="background-color:var(--brand-blue)"`, and a `HeadInclude.cshtml` `<style>` block commonly re-declares the token; deleting it from the custom sheet leaves the template `<style>` as its only definition. Re-point instead:

```css
:root { --brand-blue: var(--brand-accent) !important; }   /* backward-compat alias */
```

`!important` on a custom property is legal and beats a same-specificity `:root` in a template `<style>` block **regardless of source order** — which is what makes the alias work without touching content or templates.

Deploy shape: pre-flight refuses to upload on any hit of a combined regex over every retired value in both notations across **all** payload files; the post-upload check re-runs it against the **served** files. Sign-off: pixel scan of the outgoing hue across the page set × both viewports × anon/signed-in, plus a control run against the pre-deploy CSS to prove the detector still fires.

## CSS that silently never reaches the browser

Four ways a rule ships, round-trips byte-identical — and does not exist in the browser. A byte-level check cannot see any of them.

- **A `*/` inside comment PROSE closes the comment early** (e.g. `F1/F2/W*/H1`); the orphaned remainder becomes a selector prelude and the parser error-recovers by consuming tokens up to and including the next `{...}` block — silently discarding the following real rule. No comment is *unterminated*, which is why byte checks miss it. Scan pre-upload and the re-downloaded sheet, **string-aware** (so `content:"*/"` and `url()` do not false-positive).
- **A numeric-leading id selector does not parse.** Every Dynamicweb paragraph / page / row id is numeric, and `#12345` is invalid CSS (the hash-token is *unrestricted*, not type "id") — the parser drops the **whole rule**, and `querySelector("#12345")` throws, including inside `:has()`. Use the attribute form `[id="12345"]`. Reject the escape `#\31 2345` — it parses, but the load-bearing trailing space is destroyed by any minifier.
- **`:has()` with a descendant combinator matches every ancestor.** `section[data-swift-gridrow]:has([data-dw-itemtype="…"])` also matches the hero row *and* the top-level 1Column row wrapping the whole page — a `display:none` there blanks the page (document height collapses to the viewport, header and footer still painting). Anchor to a **direct child** through an explicit `> [data-swift-container] >` chain; count the matches in the browser (intended 1, not 3) before shipping.
- **A sentinel block nested inside another is a pending deletion** — deploy scripts strip blocks with a DOTALL `BEGIN`→`END` regex that knows nothing about nesting, so a strictly-contained inner pair is genuinely deleted while its own verify exits green. Keep every sentinel pair a **sibling**, give each block its own tracked source file (plus `*.css text eol=lf` in `.gitattributes`), and verify generically: every sentinel present before the write is present **exactly once** after it, no span nested inside another — pre-flight and against the served sheet.

**A rewriter cannot prove its own rule identity — verify with a parser that shares no code with it.** A stripper that proves "no rule was removed" by normalising both files with its own tokeniser is self-referential: a tokeniser bug deletes the rule from both sides and `before == after` still holds. Diff the **flattened CSSOM** in a headless browser instead — `document.styleSheets[0].cssRules` flattened to `selectorText` plus every declaration name/value/priority, compared position-by-position.

Because of all four, **a CSS deploy must assert CSSOM rule presence**: for each shipped block, assert its marker rule is in `document.styleSheets`, recursing into `@media`/`@supports` groups and indexing each arm of a grouped selector separately (a fixed expected rule *count* rots on every legitimate edit and never says which rule vanished). Pair with a post-deploy smoke that renders real pages and fails on content collapse (`docH >= per-page floor`, `main.innerText >= 400 chars`), horizontal overflow, or a CSSOM rule-count **drop**. Keep the deploy-side scanner and the gate-side detector algorithmically identical.

## Overriding Swift/Bootstrap-managed layout

Bootstrap utilities are declared `!important` — `.flex-fill` is `flex: 1 1 auto !important`, likewise `.d-flex`, `.gap-*`, `.order-*` — and Swift puts them on whichever grid column it manages, so **an authored override loses to them no matter how specific the selector** — no parse error, no CSSOM change. Signature: sibling declarations apply, only the contested property lost.

- **Grep the rendered column for utility classes before authoring a flex/display/order override**, then mark `display`, `order` and `flex` `!important` — *only* those, never colour, spacing or typography.
- **When a later rule needs `!important` to win, every earlier non-`!important` rule for that property is already dead — and usually looks correct**, because the utility and the intended value are drawn from the same spacing scale. **Deleting the `!important` is not a cleanup — it is a silent handover to the framework.** When the live value is deliberately set *to* the framework's, only a CSSOM marker pinned to that selector holds the line.
- **Read the COMPUTED value to name the dead rule** (`getComputedStyle(nav).columnGap` vs declared), and mechanically audit every (selector-target, property) pair declared more than once, reporting which declaration wins in the CSSOM.
- **Mark the counterpart rule in the wider tier `!important` too**, so the later source-order rule still wins — otherwise the layout tier and the clearance tier disagree across a band of widths (a nav meant to wrap stays inline while the two-line clearance token already applies).
- **Assert the computed value, never the presence of the declaration** — `getComputedStyle(el).display === "grid"`; sweep viewports asserting the flex line count flips exactly at the media-query edge.
- **A grid dropped into a text paragraph inherits Swift's reading measure — measure the rendered TILE, never the column count.** Swift wraps a paragraph body in a div carrying a prose `max-width` (~757px) inside a full-content-width container — right for running text, wrong for a card rack: the grid keeps its column count while each card collapses to half the intended width, and **a column count is not a size**, so structural assertions pass. Lift the cap for exactly the element that *directly* contains the grid (`[data-dw-itemtype="swift-v2_text"] :has(> .<grid-class>) { max-width: none }`), leave headings at their reading measure, and assert the **rendered card width in px** per breakpoint.
- **Line-view rows need `min-width: 0` and a bounded title.** In a `nowrap` flex row with fixed non-shrinkable siblings, the product title is the only `flex-shrink: 1` child and absorbs the whole overcommit — collapsing to `width: 0` with `overflow: visible` and painting across the description lane. Give the title a basis and a floor (`flex: 0 1 320px; min-width: 180px`) plus a 2-line `-webkit-line-clamp`; make the description a shrinkable single-line ellipsis lane (`flex: 1 1 140px; min-width: 0`). Assert per row: title box does not intersect description box, title ≤2 lines, at 1440 and 390.

## Grid galleries and thumbnail strips

On the Swift PDP thumbnail strip, `grid-template-columns: repeat(auto-fit, minmax(96px, 1fr))` behaves as a **ratio**, not a size: tile size becomes a function of the product's image **count**, and lowering the `minmax` minimum changes nothing below the fit ("the CSS didn't apply"). Swift's inline `width: clamp(4.5rem, 18vw, 8rem)` on the children is usually already neutralised by the `width: auto !important` needed to beat Bootstrap, so the track spec is the only lever left. A **fixed track** (`repeat(auto-fit, 104px)`) is the only count-stable choice; pick `justify-content: start` (`space-between` blows the inter-tile gap apart at low counts, and a container `max-width` alone stays count-dependent). With a fixed track, "flush at both edges" and "constant tile size" are mutually exclusive below the fit — state the trade. Verify by measuring the rendered tile at **two different image counts** per viewport; a single-count measurement cannot see this defect.

## Floating / overlay header — hero behind the bar

**Swift 2.4 exposes no native transparent/overlay-header switch.** The header renders as `header[data-swift-page-header].sticky-top` — `position: sticky`, in flow — coloured by a per-section `data-dw-colorscheme="dark"`. A floating-bar-over-hero motif is therefore CSS-only, brand-generic enough for `default_custom.css`:

```css
[data-swift-page-header]        { position: fixed; background: transparent; padding: <top> <inset> 0; }
[data-swift-page-header]::before{ /* the pill: border-radius, brand fill — NO overflow:hidden */ }
[data-swift-page-header] section{ background: transparent; }   /* invisible seam across the header rows */
main                            { padding-top: var(--bar-clearance); }
main:has(> section:first-child [data-swift-poster]) { padding-top: 0; }  /* poster flows behind — :first-child shifts in VE, see §Scoping hooks */
```

`overflow: hidden` on the pill (the reflex for clipping a border-radius) clips the megamenu and dropdowns — never use it here; keep a standing guard against **any** `overflow` declaration inside header-scoped rules.

- **Key the clearance token on the served DOM, not on a breakpoint.** Dynamicweb picks between two different header content pages **server-side by user-agent**, not viewport width: a phone UA gets a 2-row (~84px) header carrying `swift-v2_offcanvasnavigation`; a desktop UA **at the same 390px width** gets a 3-row (~177px) header carrying `swift-v2_menurelatedcontent`. A media query cannot tell the two documents apart, so a breakpoint-keyed token is silently wrong for whichever document was not measured. Select on the DOM, outside any media query:

  ```css
  body:has([data-swift-page-header] [data-dw-itemtype="swift-v2_offcanvasnavigation"]) {
    --bar-clearance: calc(var(--bar-top) + var(--bar-h-phone));
  }
  ```

  Specificity (0,2,1) beats `:root` (0,1,0) regardless of source order; without `:has()` support the `:root` default applies — over-clearance, not breakage — and it self-corrects at every width. Do **not** re-fit the breakpoint token: the narrow desktop browser legitimately receives the 3-row header at the same width. Assert clearance (`firstContent.top - header.bottom`, threshold −2..24) per viewport **with a real device descriptor**, keeping a desktop-UA control at the same width.
- **Budget the gutters against the container's own −32px.** `[data-swift-container]` sets `max-width: calc(-32px + min(<cap>, 100%))` — 32px narrower than its parent — and centres with auto margins that resolve to **16px per side** below the cap, so any budget computed as `viewport − 2·inset − 2·padding` is 32px optimistic. Override to `max-width: min(<cap>, 100%)` (preserve the cap — it is the composition's max content width) and assert the first column's left edge equals `inset + padding` with computed `marginLeft` `0px`.
- **Icon-only header controls: `clip` + `clip-path`, not the classic sr-only idiom** — the traditional visually-hidden recipe uses `overflow: hidden`, which the header guard bans. Use `position:absolute; width:1px; height:1px; clip:rect(0 0 0 0); clip-path:inset(50%); white-space:nowrap`; never `display:none` or `font-size:0` (both strip the accessible name). Assert: no `overflow` declaration in header-scoped rules, the megamenu opens with no ancestor computing `overflow-y != visible`, and the control's accessible name is non-empty.
- **A fixed-vh poster behind a fixed bar has viewport-UNSTABLE clearance.** `object-fit: cover` on a wide fixed-height box is **width**-driven, so the subject's vertical position scales with viewport width while the bar height is fixed px — a focal-point nudge clears one width and re-breaks another. Pair a **top-anchored crop** (`object-position: 50% 0%`) with a master image carrying deliberate sky headroom (subject in the lower third) and a page-scoped first-row height cap under the design gate's band-height guard. Verify measured clearance at four widths.

## Section-boundary decoration — negative-top pseudo-elements

- **A boundary wave at `top: calc(-1 * H)` paints in the PREVIOUS section's space**, so its fill only reads over a uniform, contrasting band — elsewhere it vanishes or reads as a muddy seam. Position boundary shapes at `top: 0` so the crest paints inside its own section; for a footer wave, drop any `scaleY(-1)` flip so the fill is flush. Review tight wave crops at both viewports, never the full-page shot.
- **A pseudo-element with a negative `top` paints above its owner's border box**, so clearance checks built on element boxes report healthy headroom while the shape covers real controls. Compute `paintedTop = ownerTop + min(0, parseFloat(::before top))` in the assert and require real clearance to the lowest interactive control. Fix the page rhythm (`main { padding-block-end: clamp(88px, 8vw, 128px) }`), not the motif.

## Utility classes lose to scheme-scoped element rules

A theme's body-copy softener — `main [data-dw-colorscheme=light|lightgrey1|lightgrey2] p { color: rgba(...) }` at specificity (0,1,2) — out-specifies any bare utility class at (0,1,0), so an eyebrow/kicker applied as `<p class="eyebrow">` renders body-copy colour on **every** light band while looking correct on the dark band ("the class doesn't work sometimes"). Author kickers as a non-`<p>` element (`<span class="eyebrow">`), and in the theme either bump the utility's specificity or exclude it from the softener: `main [data-dw-colorscheme] p:not(.eyebrow)`. Applies to any single-class utility competing with a scheme-scoped element selector.

## In-page anchors — `<base href>` breaks every bare fragment

DW core emits `<base href="https://<host>/">` via `@Model.MetaTags` — not a line in `Swift-v2_Master.cshtml`, so it cannot be removed from the master template — and it breaks bare fragments sitewide: `href="#specifications"` navigates to the homepage instead of scrolling. A static absolute `href` cannot fix it (one paragraph renders for every product URL): repoint each href at runtime to `location.pathname + location.search + "#id"` and perform the scroll. Assert per bare-fragment link — click, then `location.pathname` unchanged **and** `scrollY > 0` — over every fragment link in nav, footer and TOCs.

## Conditional-collapse CSS — hide empty bands with sibling `:has()` pairs

When a PDP/PLP band must hide only when empty (an empty `productbom` / `productmediatable` shell on a sparse product), write the condition as **sibling `:has()` / `:not(:has())` pairs on one selector** — nested `:has()` is invalid per spec and the browser drops the entire rule silently (`Element.matches(<nested-selector>)` throwing `SyntaxError` in Chromium is the fast confirmation):

```css
/* collapse the band only when it has the wrapper but no populated child */
section[gridrow]:has(.productbom):not(:has(.productbom .bom-row)) { display: none !important; }
```

Anchor the flat form to a direct-child chain (a bare descendant argument inside `:has()` matches every ancestor row — see [§CSS that silently never reaches the browser](#css-that-silently-never-reaches-the-browser)). The `!important` is load-bearing: Swift grid rows carry `[gridrow][container][gridcolumn]{display:flex}` at specificity `0,3,0`, beating a plain `display:none` at `0,1,0`. Definition of done: empty bands hidden on sparse products, populated bands still render, zero overflow at 1440 + 390 ([`mobile-pass.md`](mobile-pass.md)). Lands in the Tier-1 `<customer>_custom.css` slot.

## Selector reach — scope what hides content, comment what counts children

The collapse rules above hide content on purpose. Both failure modes are silent: the rule reaches a page that did not exist when it was written, or the right position and the wrong element.

- **A hide/collapse rule must be scoped to the surface it was written for — a page-id or component ancestor, never a bare `.grid` descendant chain.** Every Swift `4Columns` row renders its columns as `.grid > .g-col-lg-3` with the first always `.order-1`, so a rule like `.grid > [class*="g-col-lg-3"].order-1:not(:has(button, a, input, select, label)) { display: none }` (written to collapse an empty facet rail) hides the first column of **every** four-column row sitewide whose content carries no interactive element. The element stays present in the served HTML, so content asserts pass while it computes `display: none`.
- **A CSS audit run from page script cannot see the rule that did it** — `el.matches(":not(:has(…))")` **throws** in Chromium and the exception is typically swallowed, so enumerating `document.styleSheets` reports "no rule matches" on a demonstrably hidden element. Use CDP `CSS.getMatchedStylesForNode`, paired with the gate-side assert that every paragraph present in the served HTML also has a non-zero box ([`visual-qa.md`](../../dw-demo-base/references/visual-qa.md) "Assert design rules").
- **The row DEFINITION decides which CSS can reach the content.** `Swift-v2_Row.cshtml` renders `<div data-swift-container class="grid">` with `g-col-12 g-col-lg-N order-N` column classes; `Swift-v2_RowFlex.cshtml` renders `<div data-swift-container class="d-flex">` with only `flex-fill` per column — no `.grid` ancestor, no `g-col-*`, no `.order-*`, computed `order: 0`. They read as interchangeable in the admin UI and are not: converting a row between the families changes which custom rules apply with no content change — also the cheapest escape from an over-reaching rule you are not authorised to edit. Assert a conversion by the emitted column class list, not by eye.
- **A positional selector over a data-driven list has no error mode — it re-targets, silently, forever.** Where a block bans `:has()`, the fallback `:nth-child(N)` encodes list CONTENT as a POSITION; over a nav tree assembled at render time from CMS pages plus commerce groups, one routine content edit shifts the target with every check green. Prefer, in order: a data-level fix; an attribute/`href`-keyed selector (`:has(> a[href$="/about"])` cannot re-target); a single-level `:has()` where permitted; a positional selector only as a documented last resort — with a **mandatory guard comment** naming that it is positional, the exact list state that makes it correct, and the edit that invalidates it.
- **Pin the assertion to the intent, not to the rule** — assert the rendered label sequence and that no sibling's computed `order` changed. Note the cost of `order:` itself: visual order diverges from DOM order (WCAG 1.3.2 / 2.4.3), so tab order still visits the item in its old position.

## Row colour schemes paint the SECTION, not the paragraph

**Before adding a radius, a border or a shadow to a banded row, find which element carries the BACKGROUND and put the treatment there.** In Swift the row colour scheme (`data-dw-colorscheme` on `section[data-swift-gridrow]`) paints the fill; the paragraph column inside it is transparent, and a `border-radius` on a transparent child can never round a filled ancestor — the fill's corners poke out at all four, and no radius value fixes it. Put the treatment on the **painting section**, collapsing the row/container `padding-block` to `0` when the fill box and content box must coincide; verify box height equals row height and the expected count of treated rows per page type. Cheap general probe: flag every element with `border-radius > 0` and a transparent background whose nearest painted ancestor is square and overlaps it on any edge — confirm it fires on the pre-fix sheet before trusting it silent.

## Colour contrast — resolve the EFFECTIVE alpha before darkening anything

**A reported contrast failure whose foreground colour appears nowhere in any sheet is an ancestor-opacity composite, not a scheme token.** Swift renders the accordion body as `<div class="accordion-body mb-0-last-child opacity-75">` and Bootstrap ships `.opacity-75 { opacity: .75 !important }`, multiplying the already-muted paragraph alpha — the reported colour is **emergent**, never declared, so grepping the hex finds nothing. Resolve the effective alpha (declared alpha × every ancestor `opacity`, walked via `getComputedStyle`) before choosing a fix, and **prefer removing the redundant dim over darkening the colour** — the same ancestor opacity multiplies a darker value back below the threshold it was meant to clear; verify arithmetically. The right-fix shape: `main .accordion .accordion-body.opacity-75 { opacity: 1 !important }`. The class is a family, not an incident — it recurs wherever opacity-dimmed muted text sits on a near-white band (`breadcrumb-item.active`, product short description, `.text-success` stock label, `.fs-7.opacity-85` product number): fix the family in **one** pass against the sheet you own, and route Swift/Bootstrap defaults on a signed-off design to the owner as a decision.

## A workaround block must name the condition that retires it

**A workaround that works is invisible: no assert fails, and the constraint that justified it can be retired without anything noticing.** Canonical shape: a CSS block painting the correct photo as a `background-image` while holding the real `<img>` at `opacity: 0` — the card looks right while the database still references a different image and any future edit to the slide is silently painted over. **State the deletion condition inside the block's own comment** (what must become true for removal, and what breaks while it stays), and **never remove a workaround in a run that cannot land the real fix** — deleting it alone puts the wrong content back on a live page. Probe: flag any rule painting a `background-image` onto an element whose child `<img>` is held at `opacity: 0` (almost always a data defect wearing a costume) and fail the design leg with the selector named.

## What this recipe does NOT do

- Does not re-derive a customer-specific baseline (that is the demo's data-phase concern, project-specific; see the demo's `.planning/` if it tracks phases).
- Does not seed customer-flavoured products (same -- project-specific data phase, not a Swift skill concern).
- Does not customise the customer-center CSR section -- that's stock per the SKILL.md top-level rule and the [customer-center.md](customer-center.md) playbook (the stock-CSR rule). Even when the §Pixel-perfect escalation authorises new content layouts elsewhere, the CSR section's stock paragraphs are exempt -- see customer-center.md §1.
- Does not touch SCSS source or recompile the Swift asset pipeline. Use `<customer>_custom.css` as the override slot (loaded after `swift.css`).
