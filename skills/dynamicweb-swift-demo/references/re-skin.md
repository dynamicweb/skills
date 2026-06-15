# re-skin.md

> Customer-themed re-skin recipe for a Swift 2 baseline. Defaults to the configuration-only path (admin UI Visual Editor + theme tokens -- see [admin-ui-authoring.md](admin-ui-authoring.md)). Escalation ladder when configuration falls short: (1) project-scoped CSS overrides at `Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css` consuming the `--dw-*` variables Dynamicweb generates from admin (per [doc.dynamicweb.dev/swift/customization/design-css.html](https://doc.dynamicweb.dev/swift/customization/design-css.html)); (2) layout-only `.cshtml` content-layouts for tailored screens (per [doc.dynamicweb.dev/swift/design/pixel-perfect.html](https://doc.dynamicweb.dev/swift/design/pixel-perfect.html) -- see §Pixel-perfect escalation below); (3) controller/provider `.cs` triggers base's customisations-ledger preflight ([truvio-demo-base/references/customisations.md](../truvio-demo-base/references/customisations.md)).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Pitfall index

The pitfalls appended further down — easy to miss on a partial read:

- §"Wiring up project-scoped custom.css" — the `?<ticks>` cache-buster token can be STATIC on some builds; verify the token moves, and put demo-critical CSS in an inline `<style>` block.
- §"Color schemes architecture" — scheme name typos / casing mismatches silently resolve to `data-dw-colorscheme=""`.
- §"Pitfall: over-broad `[data-dw-button]` selectors" — a naked attribute selector paints outline/ghost/icon buttons solid brand colour.
- §"Pitfall: bare `footer { ... }` selectors" — clobbers card-internal action-bars, not just the page footer.
- §"Pitfall: emoji codepoints render in color" — OS color-font fallback ignores CSS `color:`.

## Surface inventory

| Surface | Where it lives (in a deserialized Swift2.2 host) | What re-skin touches |
|---------|--------------------------------------------------|----------------------|
| Theme tokens (colors, typography, spacing) | Admin Style tools (Settings → Content → Styles → Color Schemes / Typography / Buttons); DW-generated CSS at `wwwroot/Files/System/Styles/{ColorSchemes,Buttons,Typography}/`; Area row's `AreaColorSchemeGroupId` / `AreaButtonStyleId` / `AreaTypographyId` columns point at the active `<id>` | Edit via admin Style tools (preferred when human at keyboard) — see [admin-ui-authoring.md](admin-ui-authoring.md) for the 5-step Day-1 workflow. **For headless / autonomous-agent setups,** drop the JSON+CSS pairs by hand and SQL-update the Area columns — see [styles-assets.md](styles-assets.md). Reference vault: `$env:DW_VAULT\dw-swift-styles\`. |
| Logo asset | `wwwroot/Files/Images/` (drop-in) + `Header _ Footer` page-preset paragraph property | Upload the customer's logo PNG/SVG to `Files/Images/`; set the Header paragraph's logo property to the new file |
| Header / footer copy | `_content\Swift 2\Header _ Footer\…` page tree + the corresponding paragraphs in the live host | Edit paragraph text in admin UI Visual Editor |
| Site title | Site Settings (Settings → Areas → SHOP1 → Site Settings) | Admin UI only |
| Color palette | Settings → Content → Styles → Color Schemes (admin Style tool) | Admin UI only |
| Custom CSS overrides | `wwwroot/Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css` (project-scoped naming; the stock `Custom/custom.css` placeholder ships with `body { background: hotpink !important; }` and stays untouched as a Swift slot template) | Create a project-named file alongside the stock `custom.css`. Wire it up via `Custom/<customer>HeadInclude.cshtml` (see §Wiring up custom CSS). Loads after `swift.css`; consumes `--dw-*` variables. |

## What NOT to touch (and what IS allowed)

The Swift docs ([doc.dynamicweb.dev/swift/customization/design-css.html](https://doc.dynamicweb.dev/swift/customization/design-css.html)) name a precise never-touch list and an explicit allowed-override slot:

- ❌ `Files/Templates/Designs/Swift-v2/Assets/css/swift.css` -- Swift's stylesheet. The doc says: _"never edit Swift.css or DW-generated files."_ Cascade-order would lose your changes anyway because `custom.css` loads after.
- ❌ `Files/System/Styles/ColorSchemes/swift.css`, `Files/System/Styles/Buttons/buttons.css`, `Files/System/Styles/Typography/fonts.css` -- DW-generated from admin config. Edit the source (admin UI Color Schemes / Buttons / Typography), not the generated CSS.
- ❌ Modifications to existing standard `.cshtml` templates under `Files/Templates/Designs/Swift-v2/` or `Files/Templates/Paragraph/` -- per the pixel-perfect doc (quoted in §Pixel-perfect escalation below): extend or create new templates, never modify standard ones.
- ❌ `Dynamicweb.Host.Suite/Controllers/**/*.cs`, `Providers/**`, `*Controller.cs` -- the customisations-ledger preflight (three-branch: Approve+log / Refactor / Cancel). See [truvio-demo-base/references/customisations.md](../truvio-demo-base/references/customisations.md).
- ❌ Any `.scss` / `.ts` source file under the Swift project -- recompilation drift; the live host serves compiled output.
- ❌ **Any Swift-shipped file named exactly `custom.css`** (`Custom/custom.css` placeholder; `Assets/css/custom.css` in the design-css doc's load-order example) -- these are Swift sample code, not the demo's override file. Writing brand CSS into them breaks the shipped sample, and every later reader can no longer tell what is Swift's and what is the demo's. **Hard rule: brand CSS goes in `<customer>_custom.css` — never in a file named `custom.css`.** A `git diff` showing a stock `custom.css` modified is a re-skin bug: revert it and move the rules.

✅ **Allowed (the doc-canonical override slot):** `Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css` -- your own project-scoped CSS file in the Swift `Custom/` slot folder, loaded after `swift.css`. Use it to consume `--dw-*` variables or add new rules. Scope carefully using `data-dw-colorscheme` and `data-dw-itemtype` attributes per the doc. Verbatim from the doc: _"Your own `custom.css`, loaded after Swift.css and DW files. This is where you consume or override variables, or add entirely new rules."_ The doc's "your own `custom.css`" means a file YOU create — and on a demo it must be customer-named: Swift 2.2 / 2.3 already ships `Custom/custom.css` as a placeholder template (`body { background: hotpink !important; }`), so writing into the literal `custom.css` destroys the sample (the hard rule in the ❌ list above). Create the sibling `<customer>_custom.css` — same naming discipline as the `<Prefix>_*` item types. See §Wiring up project-scoped custom.css below for the head-include.

✅ **Allowed with care (escalation tier 2):** Layout-only `.cshtml` content-layouts for new item types or new content layouts to existing item types. See §Pixel-perfect escalation below. Razor `.cshtml` is **not** in the customisations-ledger preflight glob (per [truvio-demo-base/references/customisations.md](../truvio-demo-base/references/customisations.md) §5: _"Razor files (`*.cshtml`) are NOT in the preflight glob. DW10 templates are conventional, not 'customisations' in the pitch sense -- a Swift template override is part of normal demo-build flow."_).

⚠️ **Don't paste inline-styled HTML into `Swift-v2_Text.Text` (or other RTF fields).** It compiles and renders correctly on the frontend, but the admin RTE renders the same HTML on its white-themed editor surface — so `style="color:#ffffff"`, `background:#000`, custom font-sizes, absolute positioning, etc. make the content invisible or unusable inside the RTE. Editors can't see what they're meant to edit; rewording becomes "highlight blindly and hope for the best". This is editor-hostile, not just stylistically inelegant.

The doc-canonical pattern is: **separate the styling from the content via item types + custom variants + custom.css + data-attributes**.

1. Use the standard Swift item types that match the content shape — `Swift-v2_Poster` for heroes, `Swift-v2_Feature` for promo cards, `Swift-v2_Card` for content blocks, etc. Editors get the right field schema: RTE Light for short copy + ButtonEditor + FileEditor for image/CTA + plain-text fields for headings. The content stays clean and the admin RTE shows it the way the frontend will.
2. Author a custom variant `.cshtml` under `Files/Templates/Designs/Swift-v2/Paragraph/<ItemType>/`. The cshtml emits a `data-<brand>-variant="<name>"` attribute on the outer container (or `data-dw-itemtype` if you can scope by item type alone).
3. Put all the styling in `<customer>_custom.css`, keyed off the data-attribute. Cascade order: `swift.css` first, your `<customer>_custom.css` last (per §Wiring up custom CSS).
4. Don't mix — the cshtml renders the item-type fields with semantic markup; CSS does the visual; admin sees clean content. Worked examples (substitute your own `<Brand>` prefix): a brand hero (`Swift-v2_Poster` + `Paragraph/Swift-v2_Poster/<Brand>Hero.cshtml` + `[data-<brand>-variant="hero"]` rules in `<brand>_custom.css`); a NEW FEATURE card (`Swift-v2_Feature` + `Paragraph/Swift-v2_Feature/<Brand>NewFeature.cshtml`).

When the temptation is "I'll just paste this HTML mockup the designer sent into the Text field, it's faster" — it is faster the first time, slower the second time when the editor (the demo presenter or the customer's content team) needs to change a word and can't read what they're editing. Pay the 15 minutes to wire the item-type + variant + CSS up front. Also cross-references the alphabetical-fallback rule below — `<Brand>`-prefixed variant filenames need the sort-last mitigation. The full modeling discipline (decompose by editor concern, field-purity rules, the editor-gate before calling a page done) is owned by [content-modeling.md](content-modeling.md).

⚠️ **Empty `ParagraphTemplate` alphabetical-fallback hazard.** A custom variant `.cshtml` whose filename sorts before the stock variants silently hijacks every paragraph of that item type with an empty `ParagraphTemplate` — the rule, symptom, and both mitigations (sort-last `Z<Brand>*` naming, `ParagraphTemplate` backfill) live in [`paragraphs.md` "Empty `ParagraphTemplate` resolves to the first cshtml alphabetically"](paragraphs.md). The verification step for any re-skin that adds a custom variant must check this.

## Pre-escalation check — search `dw10source` first

Before climbing the ladder, search `$env:DW_VAULT/dw10source` for the DW10-canonical surface that solves your problem. The most common false-positive escalations are:

1. **"I need to gate paragraphs by group"** → Tier 0 Permission table ([`dw10-canonical-surfaces.md`](dw10-canonical-surfaces.md) §"Permissions — the entity store"), not Tier 3 cshtml SQL.
2. **"I need to redirect from master based on user identity"** → Tier 4 Notification subscriber (NOT a customisations-rule violation; see [`../../truvio-demo-base/references/customisations.md`](../../truvio-demo-base/references/customisations.md) §"What the rule *actually* forbids vs. doesn't forbid"), not Tier 3 `WriteLiteral`.
3. **"I need to add a project-wide stylesheet"** → Tier 1 `Custom\<Customer>HeadInclude.cshtml` + set `Area.Item.CustomHeadInclude` field via MCP (see §"Wiring up project-scoped custom.css" below), not Tier 3 inline `AddStylesheet` in the master.
4. **"I need to gate routes for anonymous users"** → Tier 0 page-permission rows + `Page.PermissionType=0`, not Tier 3 substring match on `Request.Url.PathAndQuery`.
5. **"I need to read user point balance / customer number / group membership"** → `Pageview.User.PointBalance` / `Pageview.User.CustomerNumber` / `Pageview.User.GetGroups()`, not Tier 3 SQL.

See [`dw10-canonical-surfaces.md`](dw10-canonical-surfaces.md) for the full surface inventory, and its §"Discipline audit — grep pack" for the retrospective grep pack.

## Re-skin smell: "Swift-v2_Text shim + foreign cshtml"

Symptom: a paragraph template path like `Templates\Designs\Swift-v2\Paragraph\Swift-v2_Text\<Project>SomeName.cshtml` that has nothing to do with text. The paragraph is created as Swift Text in admin, then the template path is overridden to point at this file. The editor sees only Title/Subtitle/Text fields; the template ignores most of them and bakes the real fields as hardcoded literals.

Fix: define a `<Prefix>_<ConceptName>` custom item type. See [`dw10-canonical-surfaces.md`](dw10-canonical-surfaces.md) §"Custom item types — the `<Prefix>_*` discipline".

## Pixel-perfect escalation: layout-only `.cshtml` content layouts

When the configuration-only path + `custom.css` overrides don't reach a tailored screen's visual, escalation to a NEW content layout `.cshtml` is the doc-sanctioned path. Per [doc.dynamicweb.dev/swift/design/pixel-perfect.html](https://doc.dynamicweb.dev/swift/design/pixel-perfect.html):

> "Avoid modifying standard templates directly; extend or create new ones to remain upgradable."
>
> "Customize existing item types by adding fields - use DynamicWeb's 'Customize' feature for items for better upgradability."
>
> "Create new item types where necessary for extending the content model. Create belonging content layout templates to the new item types."
>
> "Use Swift's simplified templates and add e.g. content layouts to change appearance of content."

### What you may create

- A NEW content layout `.cshtml` for an existing item type (alternative rendering, alongside the standard layout).
- A NEW item type + its belonging content layout `.cshtml` (when the content model legitimately needs to extend).

### What you may NOT do

- Modify the existing standard `.cshtml` templates under `Files/Templates/Designs/Swift-v2/` or `Files/Templates/Paragraph/` (per the doc quote above).
- Add business logic to a content layout `.cshtml`. Layouts render item-type fields with alternative markup/styling; data-shape transformation, conditional rendering, and external calls are controller/provider territory and trigger the customisations-ledger preflight in base.
- Touch the customer-center CSR section's stock paragraphs -- see [customer-center.md](customer-center.md) §1 (the stock-CSR rule); even a "layout-only" override of CSR paragraphs loses the wiring that makes sales-on-behalf trivial.

### How to know you're escalating correctly

After the change, `git status` should show ONLY new `.cshtml` files (not modifications to existing standard templates) and ONLY under the customer-extension paths your demo's content model uses. No `.cs` should appear; if `.cs` appears, you've crossed into controller/provider territory and base's customisations-ledger preflight should have triggered.

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
- `.cshtml` changes are NOT automatically a problem -- new content layouts alongside standard templates are part of the §Pixel-perfect escalation ladder. The thing to avoid is **modifications** to existing standard `.cshtml` under `Files/Templates/Designs/Swift-v2/` or `Files/Templates/Paragraph/` (per the doc quote in §Pixel-perfect escalation). Use `git diff` to confirm `.cshtml` changes are net-new files, not modifications to baseline files.
- If a `<customer>_custom.css` was edited: that's the doc-canonical override slot, expected. Verify it lives at `Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css` and is loaded by a `Custom/<customer>HeadInclude.cshtml` wired to the Master area's `CustomHeadInclude` field (see §Wiring up project-scoped custom.css). Stock `Custom/custom.css` must remain the hotpink placeholder — run `git diff --name-only -- '*custom.css'` and confirm the only hit is `<customer>_custom.css`; any file named exactly `custom.css` in the diff is a finding (dw10-canonical-surfaces.md grep #9).

## What this recipe does NOT do

- Does not re-derive a customer-specific baseline (that is the demo's data-phase concern, project-specific; see the demo's `.planning/` if it tracks phases).
- Does not seed customer-flavoured products (same -- project-specific data phase, not a Swift skill concern).
- Does not customise the customer-center CSR section -- that's stock per the SKILL.md top-level rule and the [customer-center.md](customer-center.md) playbook (the stock-CSR rule). Even when this file's §Pixel-perfect escalation authorises new content layouts elsewhere, the CSR section's stock paragraphs are exempt -- see customer-center.md §1.
- Does not touch SCSS source or recompile the Swift asset pipeline. Use `<customer>_custom.css` as the override slot (loaded after `swift.css`).

## Wiring up project-scoped custom.css

Swift v2 doesn't auto-load arbitrary CSS from `Custom/`. To get a project-scoped override file served on every page, register it via the Master area's `CustomHeadInclude` field, which points at a Razor partial that calls `AddStylesheet`. The convention is `Custom/<customer>HeadInclude.cshtml`:

```cshtml
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Frontend.PageViewModel>
@using Dynamicweb.Frontend
@{
    AddStylesheet("/Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css", "all");
}
```

Wire it once in admin (Settings → Areas → SHOP1 → Site Settings → Master → "Custom <head> include file" → pick the `Custom/<customer>HeadInclude.cshtml` you just created). After that, every page's `<head>` carries:

```html
<link rel="stylesheet" type="text/css" href="/Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css?<ticks>" media="all">
```

The `?<ticks>` cache-buster is *supposed to* update automatically on file save (DW writes the file mtime as the query string), so a save → refresh in the browser is enough; no host restart required for CSS-only edits. **Do not trust this until verified on your build — see the static-token warning below.** Verify with `curl -ks https://<host>/Files/Templates/Designs/Swift-v2/Custom/<customer>_custom.css | head` to confirm the host is serving the new content.

**⚠ The `?<ticks>` token can be STATIC on some builds (observed DW 10.25.x, 2026-06-09).** On at least one 10.25.x host the emitted token never changed across CSS edits AND host restarts — the server served the new file content, but browsers that had the URL cached kept the stale copy, so CSS edits silently never reached the page. A hard-refresh fixes it, which is exactly what a demo audience won't do. Two consequences:

1. **Verify the token, not just the server.** After the first CSS edit on a new host, save, reload the page source, and confirm the `?<ticks>` value moved. If it did, the head-include + `<customer>_custom.css` flow works as documented above.
2. **If the token is static on your build, put demo-critical CSS in an inline `<style>` block inside `Custom/<customer>HeadInclude.cshtml`** — visibility hides, brand chrome, layout fixes, anything the walkthrough depends on. Razor recompiles live and an inline block has no cache key to go stale. Keep `<customer>_custom.css` for nice-to-have polish only. This also matters for the `ProductListComponentSelector` CSS-hide lever in [`paragraphs.md`](paragraphs.md) — a hide that only exists in a stale-cached `custom.css` is no hide at all.

**Why not put it in `Assets/css/`?** The design-css doc's load-order example shows `custom.css` served from `Assets/css/` — but that folder is Swift-shipped output, and a file there is indistinguishable from Swift's own. Keeping the project file in `Custom/` (the tenant-extension folder, next to the stock `CustomHeadIncludeExample.cshtml`) makes upgrade-time diffing and cleanup trivial: everything customer-specific in one folder, nothing Swift-shipped modified.

**Never write to a stock `custom.css` (hard rule — restated from §What NOT to touch).** Swift ships `custom.css` as sample code; `Custom/custom.css` is the hotpink placeholder slot template. Adding brand CSS to it breaks the shipped sample and turns the upgrade story into a merge instead of a file-drop. Always create the customer-named sibling `<customer>_custom.css` — one file, one brand, one diff. Verification: `git diff --name-only` over the design folder must never show a path ending in `custom.css` other than `<customer>_custom.css`.

## Color schemes architecture

Swift v2 color schemes live in `/Files/System/Styles/ColorSchemes/`. Three pieces:

| File | Role | Edited by |
| --- | --- | --- |
| `ColorScheme.config` | JSON list of scheme NAMES available for selection (e.g. `"Light"`, `"Dark 1"`, `"Dark 2"`, `"Light gray 1"`, `"Light gray 2"`, `"Primary"`, `"Secondary"`) | Hand-edit / ships with Swift |
| `colorscheme.json` | Per-scheme color values (background, foreground, button) -- the source of truth for how each named scheme actually looks | Admin UI Style Tools (Settings → Content → Styles → Color Schemes) writes this on save |
| `colorscheme.css` | Generated from `colorscheme.json` -- `[data-dw-colorscheme="<name>"] { ... }` rules emitting CSS variables | Auto-generated; do not edit directly |

A scheme can be attached at any level of the content hierarchy: **area** (master) → **page** → **row** → **paragraph**, where **lower scope overrides higher**. So a paragraph-level scheme wins against the row-level scheme on its parent, which in turn beats the page-level scheme, which beats the area-level scheme.

The frontend rendered HTML carries the resolved scheme as `data-dw-colorscheme="<name>"` on the corresponding wrapper element (the `<footer>`, the `<section>` for a row, the per-paragraph wrapper). Swift only emits a non-empty value if the scheme is registered AND has a value-config (the JSON entry). Without admin-UI configuration -- common on a fresh deserialize -- ColorScheme.config still lists the names but `colorscheme.json` is missing, so every level renders `data-dw-colorscheme=""` regardless of what's stored on the row, and the `<customer>_custom.css` rule for empty scheme decides the look.

**Pitfall: scheme name typos / casing mismatches.** The `colorSchemeId` stored on a row must EXACTLY match a name in `ColorScheme.config` (case-sensitive, including spaces). Values like `"dark"`, `"Dark"`, `"lightgrey1"` won't resolve against the `"Dark 1"` / `"Light gray 1"` predefined names -- Swift falls back to empty. Verify with `SELECT GridRowColorSchemeId FROM GridRow WHERE GridRowPageId = <id>` and reconcile against the names in `ColorScheme.config`.

**Diagnostic playbook when a scheme isn't applying:**

1. Check the row's stored `colorSchemeId` (admin Visual Editor or `GridRow.GridRowColorSchemeId` in SQL). Confirm the value matches a name in `ColorScheme.config` exactly.
2. Open the rendered page in DevTools and inspect the wrapper -- if `data-dw-colorscheme=""` and the row has a value set, the JSON config is missing or the name mismatch above. Browse Settings → Content → Styles → Color Schemes in admin and click Save on the relevant scheme to materialise `colorscheme.json`.
3. If `data-dw-colorscheme="<name>"` is correct but the visual is still off, the issue is in `<customer>_custom.css` cascade -- check the `[data-dw-colorscheme="<name>"]` rule's specificity vs whatever was rendering before.

**Pragmatic CSS bridge when admin-UI scheme config isn't an option (e.g. headless seed flows):** add a higher-specificity rule in `<customer>_custom.css` keyed off `data-dw-colorscheme=""` for the specific surface that needs to look "dark" / "branded". Document the workaround in the same block so the next reader knows to delete it once schemes are admin-configured. Example pattern: target `<footer>` with `footer[data-dw-colorscheme]` (specificity 0,0,1,1) to outrank the empty-scheme rule from §3 (specificity 0,0,1,0), and force inner rows transparent so the parent's bg shows through.

## Pitfall: over-broad `[data-dw-button]` selectors in `<customer>_custom.css`

Swift tags every button-flavoured anchor and `<button>` with `data-dw-button` -- not just the primary CTAs you actually want to brand. A naked `[data-dw-button] { background-color: var(--brand) !important; color: #fff; }` in `<customer>_custom.css` will paint **outline buttons, ghost buttons, table-action ellipsis menus, dropdown chevrons, and pagination chevrons** the same solid brand colour. Symptom: a customer-center grid (orders, favorites, accounts) shows ACTIONS columns where every icon button is a solid blue tile with no visible icon contrast, and `…` / `<` / `>` controls vanish into a blue blob.

**Why this is easy to miss:** the home page and PDP look right because they only use primary CTAs. The breakage is one click deeper, inside the customer-center grids that ship buttons like `<button class="btn btn-outline-secondary ..." data-dw-button>`. Reskin verification often stops at the home page.

**The fix is to narrow the selector and add an explicit outline reset:**

```css
/* Re-skin primary buttons only — exclude every variant that needs its own look */
[data-dw-button]:not(.btn-link):not(.btn-outline-primary):not(.btn-outline-secondary):not(.btn-outline-success):not(.btn-outline-info):not(.btn-outline-warning):not(.btn-outline-danger):not(.btn-outline-light):not(.btn-outline-dark):not(.btn-ghost) {
    background-color: var(--brand);
    color: #fff;
}

/* Explicit reset so outline buttons stay outline-shaped after brand overrides on .btn / .btn-primary */
.btn-outline-secondary[data-dw-button] {
    background-color: transparent;
    color: inherit;
    border-color: transparent;
}
.btn-outline-secondary[data-dw-button]:hover {
    background-color: rgba(var(--bs-body-color-rgb), .0675);
}
```

**Verification:** after the override, the customer-center grid ACTIONS columns must still render the `…` ellipsis icon and pagination chevrons against a transparent background. Walk `/customer-center/my-favorites`, `/customer-center/account/orders`, and (if the demo wires CSR) `/customer-center/csr/accounts` and confirm icon buttons are not solid brand-coloured tiles. Pair with [integrity-sweep.md](integrity-sweep.md) Check 6 (icon set populated) -- a missing icon set AND an over-broad button selector both manifest as "blue blob in ACTIONS column" and the icon-set fix has to come first or the symptoms overlap.

**Rule of thumb:** any `[data-dw-button]` rule in `<customer>_custom.css` that sets `background-color` without a `:not()` chain is a bug-in-waiting. Treat the attribute selector as "every Swift button" -- because that's what it is -- and brand only the variants you explicitly mean to.

## Pitfall: bare `footer { ... }` selectors clobber card action-bars

Same shape of bug as the `[data-dw-button]` pitfall above, different surface. A re-skin that paints the page footer with a generic selector — `footer { background: var(--brand); border-top: 4px solid var(--accent); }` — silently repaints **every other `<footer>` element on the page**, because Swift templates use `<footer>` as a semantic landmark inside card components.

The worst offender is **`Components/Lists/FavoriteLists.cshtml`**, which renders the Rename/Delete action-bar inside each favorites-list card as `<footer class="d-flex flex-row gap-3 ...">`. Symptom: a brand-coloured bar with a contrast stripe under every favorites card on `/customer-center/my-favorites`. Same pattern likely exists in cart/checkout card templates (`Components/Cart/...`) and product-card variants — audit before committing any global `footer` rule.

**The fix is to scope the page-footer paint to the landmark only:**

```css
/* Page footer only — not every <footer> on the page */
body > footer,
[data-swift-page-footer] {
    background: var(--brand);
    border-top: 4px solid var(--accent);
}
```

`body > footer` matches the top-level page footer that lives as a direct child of `<body>` (Swift's stock master-page footer renders there); card-internal footers nest inside `<main>` / `<section>` and don't match. The `[data-swift-page-footer]` selector is a belt-and-braces fallback in case a future Swift release moves the page footer deeper — add the attribute to your page-footer template if you author a custom variant.

**Verification:** after the override, walk `/customer-center/my-favorites` (favorites cards), `/cart` (cart summary card affordances), and any PLP with product-card hover affordances. None of the card footers should carry the brand colour. Pair with the `[data-dw-button]` pitfall above — both manifest as "unexpected brand-coloured rectangle inside a card" and are easy to confuse on first inspection.

**Rule of thumb:** any rule in `<customer>_custom.css` that uses a bare element selector (`footer`, `header`, `nav`, `aside`, `main`, `section`) for paint is a bug-in-waiting. Swift uses HTML5 landmarks semantically throughout its component templates — scope by class, ID, parent selector, or data-attribute instead.

## Pitfall: emoji codepoints render in color regardless of CSS `color:`

Unicode emoji codepoints (`📞`, `✉`, `🚛`, `📊`, `🤝`, `▲`) drop into Razor templates and inline-HTML editor fields freely — they're a tempting shortcut for "icon-ish" affordances in a DC contact strip, header utility bar, footer chips, or value-props band. **On Windows the system falls back to the Segoe UI Emoji color-font which renders glyphs in their fixed multi-color palette regardless of any CSS `color:` directive** (2026-05-13). Symptom: the demo's brand is navy + cream + a single teal accent, but the DC band and value-props strip read as pink / magenta / yellow / green from the emoji colour palette. `color: var(--brand) !important` does nothing; Segoe UI Emoji wins the cascade because it's a color font, not a glyph font.

This is **OS-level font fallback, not a CSS specificity problem**. Workarounds:

1. **Drop the emoji and use a text label.** `<DC code> DC · <DCM name>, DCM · 7am–5pm <TZ> · <phone>` reads cleanly without the `📞`. Most B2B-distributor demos prefer text-only chrome anyway.
2. **Inline SVG** — copy the path data from Unicons / Lucide / Heroicons into a `<svg>` element that the brand layer can fill via `currentColor` or `fill: var(--brand)`. Survives the color-font fallback because it's not a font.
3. **`<i class="bi bi-...">` Bootstrap Icons font** — already loaded by Swift's vendor pipeline (`Assets/lib/`), monochrome by design, honors `color:`.

**Verification.** After any re-skin pass, search the rendered HTML for emoji codepoints inside `<header>` / `<footer>` / `<nav>` / value-props bands:

```powershell
$page = (Invoke-WebRequest -SkipCertificateCheck https://localhost:55620/).Content
[regex]::Matches($page, '[\u{1F300}-\u{1F9FF}\u{2600}-\u{27BF}]') | Select-Object -ExpandProperty Value -Unique
```

Any hits in branded chrome are a regression vector — they'll render in color on the demo machine even if they look fine on the developer's Mac (which renders some codepoints monochrome by default in some browsers). Pair with the `[data-dw-button]` and `footer { ... }` pitfalls above — all three are "the visual reads wrong but the CSS looks fine" symptoms and easily confused on first inspection.
