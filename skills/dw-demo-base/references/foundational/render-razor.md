# Foundational candidate → dw-render-razor

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 Razor-rendering knowledge — canonical `Services.*`
> surfaces to call from templates, `ViewModelTemplate<>` execution pitfalls, head-include / stylesheet
> wiring, and the CSS pitfalls that bite re-skins — staged here for a future fold-up into
> `dw-render-razor`. No demo/customer content. When folded, move this body into `dw-render-razor` and
> re-target the pointers in the demo skills. Until then, the demo skills reference this file.

## Contents

- [1. Canonical surfaces — use these, don't re-implement](#1-canonical-surfaces--use-these-dont-re-implement)
- [2. `ViewModelTemplate<>` Razor pitfalls](#2-viewmodeltemplate-razor-pitfalls)
- [3. Project-scoped stylesheet wiring (`CustomHeadInclude`)](#3-project-scoped-stylesheet-wiring-customheadinclude)
- [4. Color schemes architecture + cascade](#4-color-schemes-architecture--cascade)
- [5. CSS pitfalls that bite re-skins](#5-css-pitfalls-that-bite-re-skins)

## 1. Canonical surfaces — use these, don't re-implement

Every "fake pattern" in a Swift template (raw SQL probes, hard-coded area prefixes, master-template
`WriteLiteral` redirects, `EcomOrders` SQL chains in Razor) is a workaround for a surface the author
didn't know was there. When in doubt, search the DW10 source for the canonical surface before writing
SQL or parsing URLs.

### Products

- **Get product**: `Services.Products.GetProductById(productId, variantId, true)` (the `true` =
  include all fields, materialise `ProductFieldValues`).
- **Get product URL**: `Services.Products.GetProductUrl(...)` or
  `SearchEngineFriendlyURLs.GetFriendlyUrl(...)`.
- **Get product groups**: `Services.ProductGroups.GetGroup(id).Subgroups`.
- **Identify a product via `Services.Products.GetProductById(...)`, never by parsing a URL or
  `Request.RawUrl`.**

(Pricing read surfaces live in [`commerce-catalog.md`](commerce-catalog.md); customer-order read
surfaces in [`commerce-orders.md`](commerce-orders.md).)

### URLs

- **Friendly URL for a page**: `SearchEngineFriendlyURLs.GetFriendlyUrl(pageId)`.
- **Page ID by tag**: `GetPageIdByNavigationTag("tag")` (helper available in Swift templates).
- **Canonical share URL**: `Pageview.Meta.Canonical?.ToString()` (NOT `Request.Url.AbsoluteUri` —
  that captures tracking params + proxy hostnames).
- **Build links via `SearchEngineFriendlyURLs.GetFriendlyUrl(...)` / `GetPageIdByNavigationTag(...)`,
  never hard-coded area prefixes (`/<slug>/...`) or synthesized `/Default.aspx?ID=...` strings.**

### Stylesheets / scripts

- **Page-scoped css/js**: `AddStylesheet(...)` / `AddScript(...)` in the same `@{}` block as the
  paragraph setup code. The Swift master hoists, dedups, and orders them into `<head>`.
- **Project-scoped includes**: `Area.Item.CustomHeadInclude` field pointing at a
  `Custom\<Name>HeadInclude.cshtml` partial. The stock master already renders this partial if set
  (stock example: `Custom\CustomHeadIncludeExample.cshtml`). See §3 below.
- **Add scripts via `AddScript(...)` in the paragraph's `@{}` block, never an inline
  `<script src="...">` in a paragraph template** (it re-emits per paragraph appearance and breaks
  cache-busting). **Add project-scoped includes via `Area.Item.CustomHeadInclude`, never an inline
  `AddStylesheet(...)` in the master template.**

### Cross-cutting redirects (anon gate, role gate, etc.)

- **Canonical hook**: a `NotificationSubscriber` on `Notifications.Standard.Page.Loaded` that sets
  `loadedArgs.OutputResult = new RedirectOutputResult { RedirectUrl = ... }`. Fires before any Razor
  streams (`PageView.cs:388-392`). A subscriber is **NOT** a hit on the customisations-ledger
  preflight — see the customisations-rule scope note in the demo base, and the subscriber lifecycle
  in [`extend-providers.md`](extend-providers.md).
- **For "anon hits a permission-required page"**: don't write anything. Configure
  `Page.PermissionType = 0` + a `Permission` row, and `CheckPermissionsAndRedirect()` handles it —
  see [`users-permissions.md`](users-permissions.md).
- **Use a `NotificationSubscriber` on `Notifications.Standard.Page.Loaded` for cross-cutting
  redirects, never `WriteLiteral` + `return;` from inside the master template.**

### Per-category behavior

- **Storage**: `ProductGroup.ProductGroupFieldValues` (group-level custom fields).
- **Read**: `product.PrimaryOrDefaultGroup.ProductGroupFieldValues["FieldName"]`.
- **Read per-category behavior from `product.PrimaryOrDefaultGroup.ProductGroupFieldValues["..."]`,
  never `product.PrimaryOrDefaultGroup.Name.Contains("...")` in Razor.** Marketing renames the group
  → silent breakage.

### Product field arrays / lists

- **Define** a `ProductField` of type `ListBox` / `EditableList` / repeater.
- **Read list data from the `ProductField`, never regex on `LongDescription` to lift `<li>` items.**

## 2. `ViewModelTemplate<>` Razor pitfalls

Three pitfalls land repeatedly when authoring custom variants under `Paragraph/<ItemType>/` or
editing `Designs/Swift-v2/` layouts. All three fail in subtle ways — the error often surfaces under
the *wrong* file.

### `@Html.Raw()` does NOT exist in `ViewModelTemplate<>`

Layouts inheriting `Dynamicweb.Rendering.ViewModelTemplate<>` (e.g. `Swift-v2_Master.cshtml`, every
`Paragraph/*` layout) do not expose the MVC `Html` helper. `@Html.Raw(value)` fails with `'Html' does
not exist in the current context`. **The error surfaces misleadingly** — reported against
`Swift-v2_Page.cshtml` as a flood of duplicate-using / nullable warnings; scroll to the bottom for the
real `'Html' does not exist` line.

**Fix.** Default to plain `@var`. Razor encodes, but for content without HTML-special characters
(`<`, `>`, `&`, `"`, `'`) — CSS custom-property values, brand strings, numeric tokens — the encoding
is a no-op. `ShortDescription` / `LongDescription` are already HTML strings; emit them directly
(`@product.ShortDescription`) and DW renders them un-escaped. If a value can legitimately contain
HTML-special characters, pre-escape in C# before emitting.

### `product.ProductFieldValues` is NOT on `ProductViewModel`

`product.ProductFieldValues` lives on the underlying `Dynamicweb.Ecommerce.Products.Product` entity,
NOT on `Dynamicweb.Ecommerce.ProductCatalog.ProductViewModel`. Calling it against `Model.Product` (a
view model) compiles to a runtime error that **surfaces as raw Razor source rendered as page text**
on the PDP (a demo-blocker). Fix — resolve the underlying entity:

```cshtml
@{
    var entity = Dynamicweb.Ecommerce.Services.Products.GetProductById(
        product.Id, product.VariantId ?? "", true);
    var fields = entity?.ProductFieldValues;
}
```

The third argument (`true`) materialises `ProductFieldValues`; without it the property returns `null`
even on a valid entity. (Which fields surface where on the view model: see
[`render-viewmodels.md`](render-viewmodels.md).)

### `ToggleFavorite.cshtml` silently no-ops when `FavoriteListId=0`

The Swift "Add to favorites" icon inside `Swift-v2_ProductAddToCart` calls
`RenderPartial("Components/ToggleFavorite.cshtml", product)` **without** the `ListId` view parameter,
so its resolver computes `favoriteListId = 0` regardless of how many lists the user has. The button
ships `FavoriteListId=0` and the AJAX call either silently fails, adds to "list 0" (no-op), or opens
an empty offcanvas — depending on single-list vs multi-list mode. Fix in a project override of
`Components/ToggleFavorite.cshtml` (a content-layout override of an existing item type — no `.cs`):
auto-resolve `favoriteListId` to the user's first list when exactly one exists, and route zero-list
users to the favorites overview page.

## 3. Project-scoped stylesheet wiring (`CustomHeadInclude`)

Swift v2 doesn't auto-load arbitrary CSS from `Custom/`. To get a project-scoped override file served
on every page, register it via the Master area's `CustomHeadInclude` field, which points at a Razor
partial that calls `AddStylesheet`. Convention: `Custom/<name>HeadInclude.cshtml`:

```cshtml
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Frontend.PageViewModel>
@using Dynamicweb.Frontend
@{
    AddStylesheet("/Files/Templates/Designs/Swift-v2/Custom/<name>_custom.css", "all");
}
```

Wire it once in admin (Settings → Areas → SHOP1 → Site Settings → Master → "Custom <head> include
file"). After that every page's `<head>` carries
`<link rel="stylesheet" href="/.../Custom/<name>_custom.css?<ticks>" media="all">`.

**⚠ The `?<ticks>` cache-buster token can be STATIC on some builds (observed DW 10.25.x).** On at
least one 10.25.x host the emitted token never changed across CSS edits AND host restarts — the
server served the new file content, but browsers with the URL cached kept the stale copy, so CSS
edits silently never reached the page. Two consequences:

1. **Verify the token, not just the server.** After the first CSS edit on a new host, save, reload the
   page source, and confirm the `?<ticks>` value moved. If it did, the head-include + CSS-file flow
   works as documented.
2. **If the token is static on your build, put render-critical CSS in an inline `<style>` block inside
   the head-include partial** — visibility hides, brand chrome, layout fixes. Razor recompiles live
   and an inline block has no cache key to go stale. Keep the CSS file for nice-to-have polish only.
   (This also matters for the `ProductListComponentSelector` CSS-hide lever in
   [`swift-building.md`](swift-building.md) — a hide that lives only in a stale-cached CSS file is no
   hide at all.)

**Why `Custom/` not `Assets/css/`?** `Assets/css/` is Swift-shipped output; a file there is
indistinguishable from Swift's own. Keeping the project file in `Custom/` (the tenant-extension
folder) makes upgrade-time diffing and cleanup trivial. (The "never write a file named exactly
`custom.css`" hard rule lives in [`swift-building.md`](swift-building.md).)

## 4. Color schemes architecture + cascade

Swift v2 color schemes live in `/Files/System/Styles/ColorSchemes/`. Three pieces:

| File | Role | Edited by |
| --- | --- | --- |
| `ColorScheme.config` | JSON list of scheme NAMES available for selection (`"Light"`, `"Dark 1"`, `"Primary"`, …) | Hand-edit / ships with Swift |
| `colorscheme.json` | Per-scheme color values (background, foreground, button) — source of truth | Admin Style Tools (Settings → Content → Styles → Color Schemes) writes this on save |
| `colorscheme.css` | Generated from the JSON — `[data-dw-colorscheme="<name>"] { ... }` CSS-variable rules | Auto-generated; do not edit directly |

A scheme attaches at any level of the content hierarchy: **area** (master) → **page** → **row** →
**paragraph**, where **lower scope overrides higher**. The rendered HTML carries the resolved scheme
as `data-dw-colorscheme="<name>"` on the wrapper element. Swift emits a non-empty value only if the
scheme is registered AND has a value-config (the JSON entry). Without admin-UI configuration — common
on a fresh deserialize — `ColorScheme.config` still lists the names but `colorscheme.json` is missing,
so every level renders `data-dw-colorscheme=""` regardless of what's stored, and the project CSS rule
for the empty scheme decides the look.

**Pitfall: scheme name typos / casing mismatches.** The `colorSchemeId` stored on a row must EXACTLY
match a name in `ColorScheme.config` (case-sensitive, including spaces). `"dark"` / `"lightgrey1"`
won't resolve against `"Dark 1"` / `"Light gray 1"` — Swift falls back to empty.

**Diagnostic playbook when a scheme isn't applying:**

1. Check the row's stored `colorSchemeId` (`GridRow.GridRowColorSchemeId`); confirm it matches a name
   in `ColorScheme.config` exactly.
2. Inspect the rendered wrapper in DevTools — `data-dw-colorscheme=""` with a value set means the JSON
   config is missing or the name mismatched. Open Settings → Content → Styles → Color Schemes and
   Save the scheme to materialise `colorscheme.json`.
3. If `data-dw-colorscheme="<name>"` is correct but the visual is off, it's a project-CSS cascade /
   specificity issue.

**CSS bridge when admin-UI scheme config isn't an option (headless seed flows):** add a
higher-specificity rule keyed off `data-dw-colorscheme=""` for the specific surface that needs to look
branded, and document the workaround inline so the next reader removes it once schemes are
admin-configured.

## 5. CSS pitfalls that bite re-skins

### Over-broad `[data-dw-button]` selectors

Swift tags every button-flavoured anchor and `<button>` with `data-dw-button` — not just the primary
CTAs. A naked `[data-dw-button] { background-color: var(--brand) !important; color: #fff; }` paints
**outline buttons, ghost buttons, table-action ellipsis menus, dropdown chevrons, and pagination
chevrons** the same solid brand colour. Symptom: customer-center grids show ACTIONS columns where
every icon button is a solid tile with no icon contrast, and `…` / `<` / `>` controls vanish into a
blob. Easy to miss because the home page and PDP look right (they only use primary CTAs); the breakage
is one click deeper. Fix — narrow the selector and add an explicit outline reset:

```css
[data-dw-button]:not(.btn-link):not(.btn-outline-primary):not(.btn-outline-secondary):not(.btn-outline-success):not(.btn-outline-info):not(.btn-outline-warning):not(.btn-outline-danger):not(.btn-outline-light):not(.btn-outline-dark):not(.btn-ghost) {
    background-color: var(--brand);
    color: #fff;
}
.btn-outline-secondary[data-dw-button] { background-color: transparent; color: inherit; border-color: transparent; }
.btn-outline-secondary[data-dw-button]:hover { background-color: rgba(var(--bs-body-color-rgb), .0675); }
```

**Rule of thumb:** any `[data-dw-button]` rule that sets `background-color` without a `:not()` chain
is a bug-in-waiting.

### Bare `footer { ... }` selectors clobber card action-bars

Swift uses `<footer>` as a semantic landmark **inside card components** (notably
`Components/Lists/FavoriteLists.cshtml`, which renders each card's Rename/Delete action-bar as
`<footer class="d-flex …">`). A generic `footer { background: var(--brand); … }` repaints every
`<footer>` on the page, not just the page footer. Fix — scope the page-footer paint to the landmark:

```css
body > footer,
[data-swift-page-footer] {
    background: var(--brand);
    border-top: 4px solid var(--accent);
}
```

**Rule of thumb:** any rule using a bare element selector (`footer`, `header`, `nav`, `aside`,
`main`, `section`) for paint is a bug-in-waiting — Swift uses HTML5 landmarks semantically throughout.
Scope by class, ID, parent selector, or data-attribute instead.

### Emoji codepoints render in color regardless of CSS `color:`

Unicode emoji codepoints (`📞`, `✉`, `🚛`, `▲`) drop into Razor and inline-HTML fields freely as
"icon-ish" affordances. **On Windows the system falls back to the Segoe UI Emoji color-font, which
renders glyphs in their fixed multi-color palette regardless of any CSS `color:`** — so a navy/cream
brand reads as pink/yellow/green in a contact strip or value-props band. This is OS-level font
fallback, not CSS specificity. Workarounds:

1. **Drop the emoji and use a text label** — usually preferable for B2B chrome anyway.
2. **Inline SVG** (Unicons / Lucide / Heroicons path data) filled via `currentColor` / `fill:
   var(--brand)` — survives the color-font fallback.
3. **`<i class="bi bi-...">` Bootstrap Icons** — already loaded by Swift's vendor pipeline, monochrome,
   honors `color:`.

Verification — search the rendered HTML for emoji in branded chrome:

```powershell
$page = (Invoke-WebRequest -SkipCertificateCheck https://localhost:<port>/).Content
[regex]::Matches($page, '[\u{1F300}-\u{1F9FF}\u{2600}-\u{27BF}]') | Select-Object -ExpandProperty Value -Unique
```

Any hits in `<header>`/`<footer>`/`<nav>`/value-props bands render in color on the demo machine even
if they look fine on a Mac (which renders some codepoints monochrome by default).

## Cross-references

- [`render-viewmodels.md`](render-viewmodels.md) — the data side: which fields surface on
  `ProductViewModel` vs the underlying entity, and the user/group accessors.
- [`swift-building.md`](swift-building.md) — the Swift component system, the re-skin escalation ladder,
  Style assets, the `custom.css` naming hard rule, and the discipline grep-pack.
- [`users-permissions.md`](users-permissions.md) — the Permission entity store for gating
  page/paragraph visibility (the canonical alternative to template-side SQL gates).
- [`commerce-catalog.md`](commerce-catalog.md) / [`commerce-orders.md`](commerce-orders.md) — pricing
  and customer-order read surfaces.
- [`extend-providers.md`](extend-providers.md) — `NotificationSubscriber` lifecycle.
