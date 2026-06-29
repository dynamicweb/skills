# re-skin.md

> Customer-themed re-skin recipe for a Swift 2 baseline. Defaults to the configuration-only path (admin UI Visual Editor + theme tokens -- see [admin-ui-authoring.md](admin-ui-authoring.md)). Escalation ladder when configuration falls short: (1) project-scoped CSS overrides at `Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css` consuming the `--dw-*` variables Dynamicweb generates from admin; (2) layout-only `.cshtml` content-layouts for tailored screens; (3) controller/provider `.cs` triggers base's customisations-ledger preflight ([dynamicweb-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md)).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

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
- Custom variant `.cshtml` whose filename sorts before stock variants hijacks empty-`ParagraphTemplate` paragraphs → [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §4. The verification step for any re-skin that adds a custom variant must check this.

## The escalation ladder

| Tier | Surface | What it touches | Owner |
|------|---------|-----------------|-------|
| 0 | Admin UI Style Tools (Settings → Content → Styles) | Color schemes, button shape, typography — generates the `Styles/*.{json,css}` pairs | [styles-assets.md](styles-assets.md) + [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §7 |
| 1 | `Custom/<customer>_custom.css` | Brand variables, hover states, hacks the schemes don't cover | this file (naming rule below) + [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §3 (wiring) |
| 2 | New layout-only `.cshtml` content layouts | Pixel-perfect reshaping of an item type's render | [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9 |
| 3 | Controller / provider `.cs` (customisations-ledger preflight) | Anything that needs server-side logic | [dynamicweb-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md) |

Before climbing the ladder, run the Pre-escalation "search the source first" check in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9 — most "I need a custom template" reflexes resolve to a canonical surface (Permission table for group gates, `Page.Loaded` subscriber for redirects, `CustomHeadInclude` for a project stylesheet, `Pageview.User.*` for identity).

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

Operates on a deserialized Swift2.2 baseline at `$env:DW_VAULT\serialized-data\Swift2.2\` (resolved into a running host via this skill's [`deserialize-flow.md`](deserialize-flow.md)). All steps are admin UI only. Throughout: `<customer>` is the demo customer's short slug (lowercase, no spaces).

### 1. Logo

- Drop the customer's logo file into `<demo>\Dynamicweb.Host.Suite\wwwroot\Files\Images\<customer>-logo.svg` (or `.png`).
- Admin UI: Pages → `Header _ Footer` → Header paragraph → Logo property → set to `Files/Images/<customer>-logo.svg`.

### 2. Theme tokens (color palette + typography)

- Admin UI: Pages → Theme (page-preset) → edit the theme paragraph's color/typography properties via Visual Editor.
- Pull the customer's primary brand color from their public site or brand guide; pair with a vertical-typical neutral palette (B2B-distributor demos lean toward muted neutrals + a single accent; consumer / fashion demos lean richer).

### 3. Header / footer copy

- Admin UI: Pages → `Header _ Footer` → edit each paragraph's text content.
- Replace placeholder copy with the customer's vertical-specific language. Source from the demo's read-only `<demo>\customer-context\` (intro-call notes, project-alignment deck) -- never invent.

### 4. Verification

- Browse to `/` (home) and `/customer-center/` while logged in -- verify logo, palette, and copy are applied.
- Run `git status` in `<demo>\` -- verify NO `.cs` files changed in `Controllers/` or `Providers/` (would have tripped the customisations-ledger preflight in base) and NO `.scss` / `.ts` files changed (recompilation drift).
- `.cshtml` changes are NOT automatically a problem -- new content layouts alongside standard templates are part of the §Pixel-perfect escalation ladder ([`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9). The thing to avoid is **modifications** to existing standard `.cshtml`. Use `git diff` to confirm `.cshtml` changes are net-new files, not modifications to baseline files.
- If a `<customer>_custom.css` was edited: that's the doc-canonical override slot, expected. Verify it lives at `Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css` and is loaded by a `Custom/<customer>HeadInclude.cshtml` wired to the Master area's `CustomHeadInclude` field. Stock `Custom/custom.css` must remain the hotpink placeholder — run `git diff --name-only -- '*custom.css'` and confirm the only hit is `<customer>_custom.css`.

## What this recipe does NOT do

- Does not re-derive a customer-specific baseline (that is the demo's data-phase concern, project-specific; see the demo's `.planning/` if it tracks phases).
- Does not seed customer-flavoured products (same -- project-specific data phase, not a Swift skill concern).
- Does not customise the customer-center CSR section -- that's stock per the SKILL.md top-level rule and the [customer-center.md](customer-center.md) playbook (the stock-CSR rule). Even when the §Pixel-perfect escalation authorises new content layouts elsewhere, the CSR section's stock paragraphs are exempt -- see customer-center.md §1.
- Does not touch SCSS source or recompile the Swift asset pipeline. Use `<customer>_custom.css` as the override slot (loaded after `swift.css`).
