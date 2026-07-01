# Foundational candidate → dw-swift-building

> **FOUNDATIONAL CANDIDATE.** Vendor-generic Swift 2 / DW10 frontend-building knowledge — the
> component system, paragraph/template/page conventions, the Style-asset format, asset organisation,
> the re-skin doctrine, and the discipline grep-pack — staged here for a future fold-up into
> `dw-swift-building`. No demo/customer content. When folded, move this body into `dw-swift-building`
> and re-target the pointers in the demo skills. Until then, the demo skills reference this file.
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Contents

- [1. Component-first gate](#1-component-first-gate)
- [2. Paragraph categories](#2-paragraph-categories)
- [3. Configuring paragraph item-type fields](#3-configuring-paragraph-item-type-fields)
- [4. Empty `ParagraphTemplate` resolves alphabetically (silent footgun)](#4-empty-paragraphtemplate-resolves-alphabetically-silent-footgun)
- [5. Grid composition cache — restart required](#5-grid-composition-cache--restart-required)
- [6. Template categories, page presets, page-state flags](#6-template-categories-page-presets-page-state-flags)
- [7. Style assets — `Files/System/Styles/`](#7-style-assets--filessystemstyles)
- [8. Asset organisation under `wwwroot/Files/`](#8-asset-organisation-under-wwwrootfiles)
- [9. Re-skin doctrine — never edit standard templates](#9-re-skin-doctrine--never-edit-standard-templates)
- [10. Discipline audit — grep pack](#10-discipline-audit--grep-pack)

## 1. Component-first gate

Swift is a component system. **Before writing or overriding any `.cshtml`, enumerate the standard
components and map the requirement to one.** Most PLP / PDP / navigation needs are already shipped;
reaching for a custom template first is the most common way a Swift build accrues off-baseline,
unmaintainable code that a Serializer re-deploy silently drops.

1. **Enumerate candidates** — `ls Files/Templates/Designs/Swift-v2/Paragraph/Swift-v2_*` and
   `…/eCom/ProductCatalog/*`; grep the dir for keywords from the requirement (`group`, `poster`,
   `image`, `slider`, `facet`, `related`, `bom`).
2. **Classify** the change: **place** a component on a page · **configure** an existing one via its
   item-fields (`get_paragraph_item_field_values` → `set_paragraph_item_fields`) and/or grid
   placement (`save_grid_rows`, `place_paragraph_in_grid`) · **override** its template · **new `.cs`**.
3. **Pick the lowest tier that works.** Author or override a template only when no standard component
   + configuration fits — and log which components you considered and why each was insufficient.
   "Customisation" in Swift is mostly **placement + item-field config**, not new markup.

**Common need → standard component** (always confirm the live item-type fields; names per Swift v2.3):

| Need | Standard component | Key fields / notes |
|---|---|---|
| Category banner (image + title + desc hero) | `Swift-v2_ProductListGroupPoster` | reads the group `LargeImage` asset; `PosterHeight`, `Layout`, `ImageFilter`, `HideGroupTitle/Description` |
| Category image only | `Swift-v2_ProductListGroupImage` | group image asset |
| Group title + description (no image) | `Swift-v2_ProductListInfo` | `HideGroupTitle`, `HideGroupDescription`, `TitleFontSize` |
| Subgroup navigation (tiles / list / carousel) | `Swift-v2_ProductGroupGrid` / `ProductGroupList` / `ProductGroupSlider` | needs child groups; see `SelectedGroups` + aspect-ratio pitfalls below |
| Related / "similar" products | `Swift-v2_ProductComponentSlider` (+ `eCom/ProductCatalog/ProductSlider.cshtml` service) | `RelationType` (variants/most-sold/trending/latest/related-products); lazy-loads from a Catalog-app **service page** — see "Component-slider service page" wiring triad right below the table |
| Spec / attribute groups | `Swift-v2_ProductFieldDisplayGroupsAccordion` | `FieldDisplayGroups`, `Layout` (bullets/list/table), `HideFieldLabels` |
| BOM / assembled-from + configurator | `Swift-v2_ProductBom` | `ListComponentSource` = a Product-card component page; renders fixed lines AND select-one radio groups per configurator slot. The data shape that drives the grouping (`ProductItemBomGroupId` must be a real `EcomGroups` id) is owned by [`pim-modelling.md`](pim-modelling.md) §2.6 |

Picking the type is half the job — how many paragraphs a designed section becomes, and what goes in
fields vs. rich text, is owned by [`content-modelling.md`](content-modelling.md).

### Component-slider service page — the wiring triad and its failure smells

`Swift-v2_ProductComponentSlider` (and the grid variant) POSTs to the page tagged
`ProductSliderService` and injects the response. That service page needs **three** wirings, and each
missing one has a distinct smell — diagnose from the smell, fix only the missing leg:

1. **Layout** = `Swift-v2_ServicePage.cshtml` (renders only classic content). Missing → the POST
   returns a full `<!doctype html>` document; the injector sees non-partial HTML and renders
   **nothing** (the slider container collapses to empty).
2. **An `eCom_ProductCatalog` app paragraph on the page**, placed in a real grid row (`gridRowId=0`
   never renders; copying a working catalog-app paragraph from the shop page is the fast route).
   Missing → the POST returns an empty body; same empty slider.
3. **The app's list template** = `ProductSlider.cshtml` (it dispatches on the `ProductListPartial`
   request param to `ProductGridComponent` / `ProductSliderComponent`). Left at the shop default →
   the slider "works" but leaks the full PLP chrome — facet bar, sort dropdowns, breadcrumb,
   "Load more" — into the injected section.

The slider paragraph itself needs `ListComponentSource` = a Product-card component page and, for the
group-scoped relation types, `RelateTo` group ids. Apply the same triad audit to the other service
pages (`RelatedProductsListService`, search) when their consumers render empty.

## 2. Paragraph categories

Paragraphs are added to grid rows on a page; each grid row holds 1+ paragraph — but **standard
(non-Flex) `Swift-v2_Row` templates render exactly ONE paragraph per grid column**
(`column.Paragraph` is singular): a second paragraph placed in the same `gridRowColumn` is silently
dropped from the render, with no error and no admin warning. Compose multi-element sections inside a
single item's fields instead (e.g. a heading + CTA is one `Swift-v2_Text` with its `FirstButton`
set, not a Text paragraph plus a `Swift-v2_Button` paragraph), or use a `*Flex` row definition,
which renders one flex column per paragraph. Common categories:

| Category | Example types | Where used |
|----------|---------------|------------|
| **Text & content** | Text, Heading, Image, Button | Service pages, page-with-hero layouts |
| **Product** | Product list, Product detail, Product slider, Cross-selling | Shop, Product Components |
| **Customer center** | Order list, Cart list, User profile, Address book, Impersonation control | Customer center/Account, Customer center/CSR |
| **Navigation & layout** | Top nav, Footer nav, Breadcrumbs, Mega-menu | Header _ Footer, Navigation |
| **Forms** | Contact form, Newsletter signup, Login, Register | Service Pages, Sign in |
| **E-commerce flow** | Mini-cart, Cart summary, Checkout step, Payment, Order confirmation | Shopping cart |
| **Search** | Search box, Search results, Facets | Search result page |

The exact paragraph-type list on a running host is enumerable via Admin UI → "Add paragraph" dropdown
when editing any grid row.

## 3. Configuring paragraph item-type fields

When a Swift v2 product paragraph renders with empty headings / empty body, the paragraph row exists
but its **item-type fields** are unset. Every product paragraph is backed by an item type with its own
field schema (read the XML at `wwwroot/Files/System/Items/ItemType_<systemName>.xml`). After creating
a paragraph, fill its fields with `set_item_field_values` keyed by
`(itemType, itemId, fieldSystemName)`. The `paragraph.header` set on `save_paragraphs` is the
**admin-side row label only** and is NOT rendered by stock product paragraphs — the visible heading
comes from the item-type's `Title` field.

| Symptom | Item type | Field to set | Notes |
| --- | --- | --- | --- |
| Empty `<h2></h2>` above the block | any product paragraph | `Title` | Must be non-empty unless `HideTitle=True`. `paragraph.header` is unused. |
| Heading too large/small | any product paragraph | `TitleFontSize` | Static enum: `display-1`..`display-6`, `h1`..`h6`. |
| Specifications accordion renders empty | `Swift-v2_ProductFieldDisplayGroupsAccordion` | `FieldDisplayGroups` | Comma-separated `EcomFieldDisplayGroups.FieldDisplayGroupSystemName` list. **Empty selection = empty render.** |
| Specs include "0"/"No"/blank rows | same | `HideFieldsWithZeroValue` | Set `True` to drop falsy values. |
| Spec layout is bullet/list when you want a table | same | `Layout` | Static enum: `list \| columns \| table \| bullets \| commas`. `table` is cleanest for spec sheets. |
| Documents paragraph shows product images | `Swift-v2_ProductMediaTable` | `ImageAssets` | Comma-separated `EcomDetailsGroup.EcomDetailsGroupSystemName` list. Stock: `Images`, `Manuals`. Default = all. Set to `Manuals` for downloads-only. |
| Downloads list shows giant thumbnails | same | `HideThumbnails` | `True` for a clean filename + filetype + size table. |
| Long description has too-wide lines | `Swift-v2_ProductLongDescription` | `TextReadability` | `max-width-on` (default) constrains to a reading column; `max-width-off` fills the column. |
| Paragraph renders as empty `<div>` after SQL-direct seed | `Swift-v2_ProductGroupGrid` | `SelectedGroups` | See `SelectedGroups` below — SQL CSV/JSON inserts silently return `null`. |

For `IEnumerable<string>` fields (checkbox-list editors — `FieldDisplayGroups`, `ImageAssets`), pass a
**comma-separated string**. Bracketed-array / JSON encodings are NOT recognised by the stock editors.

### `EcomFieldDisplayGroups` cache invalidation

`ProductFieldDisplayGroupsAccordion` resolves `FieldDisplayGroups` against an in-memory cache of
`EcomFieldDisplayGroups` populated at host startup. **Inserts/updates to the four backing tables
(`EcomFieldDisplayGroups`, `EcomFieldDisplayGroupFields`, `EcomFieldDisplayGroupShops`,
`EcomFieldDisplayGroupTranslation`) are NOT picked up live** — even on admin "Cache → Clear all".
Reliable refresh is a host restart. Symptom: the editor's checkbox list shows the new groups (it
re-queries SQL on every load) but the rendered accordion is empty. Seed-flow order: (a) seed the four
tables, (b) `dotnet run` recycle, (c) configure the paragraph's field. See
[`cache-invalidation.md`](cache-invalidation.md).

### `ProductGroupGrid.SelectedGroups` — SQL-direct seeds don't deserialize

DW10's `ProductCatalogGroupEditor` stores `SelectedGroups` in a format only its own editor
understands. SQL-direct seeds with `["GROUP8","GROUP9"]` JSON or `GROUP8,GROUP9` CSV silently return
`null` from `Model.Item.GetValue<IList<ProductGroupViewModel>>("SelectedGroups")` and the stock
template renders an empty `<div>`. **Preferred fix — MCP `set_item_field_values`** on
`(itemType:'Swift-v2_ProductGroupGrid', itemId:<id>)`. **SQL-fallback — variant cshtml with
`GetRawValueString` parse:**

```csharp
@{
    var groupList = Model.Item.GetValue<IList<ProductGroupViewModel>>("SelectedGroups")
                    ?? new List<ProductGroupViewModel>();
    if (groupList.Count == 0)
    {
        string raw = Model.Item.GetRawValueString("SelectedGroups", "").Trim().Trim('[', ']');
        foreach (string token in raw.Split(new[]{',', ';'}, StringSplitOptions.RemoveEmptyEntries))
        {
            var g = Services.ProductGroups.GetGroup(token.Trim().Trim('"'));
            if (g != null)
                groupList.Add(ViewModelFactory.CreateView(new ProductGroupViewModelSettings(), g));
        }
    }
}
```

**Likely fires on other Swift list-fields backed by `ProductCatalog*Editor` item editors** —
`Subgroups`, `SelectedManufacturers`. Before SQL-seeding any item-type field whose admin editor is a
custom picker, check whether the typed lookup returns the data; if null, the same `GetRawValueString`
workaround applies. Pair with §4 (a sort-last variant or `ParagraphTemplate` backfill) so the fallback
variant doesn't hijack stock paragraphs.

### Bootstrap `.ratio` aspect-ratio token vs CSS custom-property

`Swift-v2_ProductGroupGrid`'s admin editor stores aspect-ratio as a Bootstrap token (`1x1`, `4x3`,
`16x9`) and emits `style="--bs-aspect-ratio: 1x1"`. **Bootstrap's `.ratio` class expects a percentage
(`100%`, `75%`, `56.25%`)** — the token form is invalid CSS, the rule no-ops, and the card collapses to
`height: 0` with children spilling out (symptom: ~192px of dead grey space). Fix in project CSS:

```css
.item_swift-v2_productgroupgrid .ratio,
.item_swift-v2_productgroupgrid [class*="ratio"] {
    aspect-ratio: 1 / 1;
    height: auto;
    --bs-aspect-ratio: 100%;
    overflow: hidden;
    position: relative;
}
```

The CSS-side fix beats parsing the token in a variant cshtml (the token is editor-stored, so a Razor
fix would also need `1x1`→`100%`, `4x3`→`75%`, `16x9`→`56.25%`). Composes with `SelectedGroups` above —
SQL/JSON-seeded `ProductGroupGrid` paragraphs hit both bugs.

### Field-system-name format

Display-group field links use the pipe-delimited form `ProductCategory|<CategoryId>|<fieldSystemName>`
(e.g. `ProductCategory|HeadsetsAttributes|audio_driver_size`). Underlying storage in
`EcomProductCategoryFieldValue` splits the parts; the rendering code synthesises the pipe form when
matching, so the stored `FieldDisplayGroupFieldSystemName` MUST be the full pipe form.

### `Swift-v2_Row` has no item-type fields

The row item type ships with zero custom fields — its layout knobs (column definition, container,
color scheme, background image) live on the row entity and are written via `save_grid_rows`, not
`set_item_field_values`. Useful knobs: `definitionId` (1Column/2Columns/3Columns/…), `colorSchemeId`,
`backgroundImage`, `container`. Alternating `colorSchemeId` between adjacent rows on a long PDP gives
visual rhythm without touching templates.

### Where the PDP page is sourced from

`ProductDetailRenderGrid.cshtml` is a one-line shim: `RenderGrid(Model.PrimaryOrDefaultGroup
.PrimaryPageId > 0 ? Model.PrimaryOrDefaultGroup.PrimaryPageId : detailPage)`. DW first checks the
product's primary group's `PrimaryPageId` (`EcomGroups.GroupMetaPrimaryPage`); if empty, falls back to
the page tagged `ProductDetailPage`. **Implication:** to roll one PDP layout across the catalogue,
leave `GroupMetaPrimaryPage` blank on all groups and edit the nav-tag page. To diverge per category,
set each category's `GroupMetaPrimaryPage` to a category-specific page id.

### ProductHeader inline-enrichment escalation

When the stock `Swift-v2_ProductHeader` renders a thin PDP (name + add-to-cart) and the missing
context is **per-product data already on the `ProductViewModel`** (manufacturer, SKU, stock pill,
short description), the cleanest escalation is a **NEW content layout** of the ProductHeader paragraph
— not a new paragraph type and not extra grid rows
(`Paragraph/Swift-v2_ProductHeader/<MyVariant>.cshtml`, doc-sanctioned, no `.cs`). Which fields are on
the view model (and which only look like they should be) is owned by
[`render-viewmodels.md`](render-viewmodels.md).

## 4. Empty `ParagraphTemplate` resolves alphabetically (silent footgun)

When a `Paragraph` row has `ParagraphTemplate IS NULL` or `= ''`, Swift's resolver renders it with the
**first `.cshtml` alphabetically** in the item-type's
`Templates/Designs/Swift-v2/Paragraph/<ItemType>/` folder. This is a runtime resolver fact (it fires
the same whether the row came via MCP `save_paragraphs`, SQL INSERT, or admin UI on an item type with
no default template).

**The trap.** A custom variant `.cshtml` whose filename sorts earlier than the stock variants
(`Acme*.cshtml` beats `TextCenter`/`TextLeft`/`TextRight`) **hijacks every paragraph of that item type
with an empty `ParagraphTemplate`** — including footer/header paragraphs and pages you didn't write.
Symptom: "I added one custom Text variant and now half the site renders with that styling."

- **Mitigation 1 — naming convention.** Prefix custom variants with `Z` (or any letter after the
  stock variants) so the fallback never lands on yours. Do NOT use `_`-prefixed filenames as a
  sort-last strategy without verifying — some resolvers filter `_`-prefixed files as partials.
- **Mitigation 2 — backfill `ParagraphTemplate`.** Preferred surface MCP
  `save_paragraphs(id=<id>, template='TextLeft.cshtml')` (one at a time, auto cache-invalidation);
  SQL-fallback bulk `UPDATE Paragraph SET ParagraphTemplate='TextLeft.cshtml' WHERE
  ParagraphItemType='Swift-v2_Text' AND (ParagraphTemplate IS NULL OR ParagraphTemplate='')` — a
  field UPDATE on an existing row, live with no restart ([`cache-invalidation.md`](cache-invalidation.md)
  edit-vs-insert rule). Run this BEFORE introducing any sort-early custom variant.

## 5. Grid composition cache — restart required

DW10 caches a page's **grid composition** (which paragraphs are in which grid rows) in-memory after
the first request. **Deleting a paragraph or grid row via SQL, MCP, or admin UI does NOT immediately
stop the frontend rendering it.** The composition cache survives admin "Cache → Clear all", DELETE on
`Paragraph`/`GridRow`, MCP `delete_paragraphs`/`delete_grid_rows`, and browser hard-refresh. It does
NOT survive a host process restart. On Windows + `dotnet run`:

```powershell
Get-Process dotnet -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt (Get-Date).AddDays(-2) } | Stop-Process -Force
Start-Process dotnet -ArgumentList "run","--no-build" -WorkingDirectory "<host>\Dynamicweb.Host.Suite" -RedirectStandardOutput "<host>.log" -NoNewWindow
```

After restart, wait for the port to listen then hit the page once to warm JIT. **Practical rule:**
schedule paragraph deletion just BEFORE a restart you were already planning. The general DW10 rule:
**any table whose rows are joined into a render-time composition tree (paragraphs, users, groups,
navigation) is cached in-memory and needs a process restart to repopulate.**

### `ProductListComponentSelector` caches even harder — CSS-hide is the only lever

When a paragraph's cshtml uses `@RenderGrid(componentPage.ID)` to embed another page's grid, the
**inner grid's HTML is cached** and DW10 does NOT observe `ParagraphDeleted = 1` or
`ParagraphShowParagraph = 0` on paragraphs inside that nested grid — **even after a host restart**. The
canonical surface is Swift's PLP dual-page pattern (a wrapper page hosts a
`Swift-v2_ProductListComponentSelector` that `@RenderGrid(<inner-page-id>)`s a component-source page),
and the PDP's component-source pages use the same pattern. Soft-hiding or deleting paragraphs on the
inner page leaves them rendered indefinitely.

This inverts the edit-vs-insert rule: a `ParagraphDeleted`/`ParagraphShowParagraph` flip on a
paragraph rendered through `RenderGrid` is NOT live — the `RenderGrid` HTML cache is keyed by source
page id, not by individual paragraph row state. **The only reliable lever is CSS-hide, and it must be
cache-proof** — prefer an inline `<style>` block in the head-include partial over a project CSS file
(on some builds the file is served under a static version token; see
[`render-razor.md`](render-razor.md) §3). Scope the rule as tightly as possible (item-type class,
data attribute, parent-page wrapper) and document it inline so the next reader removes it once Swift
fixes the invariant.

**Cross-AREA corollary:** the cache is keyed by source page id only — not by area or culture. If a
language layer's component selectors still point at the MASTER's component pages, both areas share one
cache entry and whichever context renders first wins. Repoint the layer's `ComponentSource` at the
layer's own component-page clones (separate ids, separate cache entries) — see
[`content-modelling.md`](content-modelling.md) §3.

## 6. Template categories, page presets, page-state flags

### Template categories (Swift 2.2 baseline, under `_content\Swift 2\`)

| Folder | Role | Touchpoint |
|--------|------|------------|
| `Customer center/` | Logged-in self-service + CSR section | DO NOT re-build the CSR section |
| `Header _ Footer/` | Site-wide header and footer | Logo + nav + copy edits via Visual Editor |
| `Navigation/` | Top nav + footer nav structure | Copy edits via Visual Editor |
| `Page presets/` | Template page-preset definitions (`_theme` + layout primitives) | Theme tokens via Visual Editor |
| `Product Components/` | Product detail page paragraphs | Copy edits only — no custom controllers |
| `Search result page/` | Search results page | Copy edits |
| `Service Pages/` | FAQ, Privacy, About, etc. | Standard CMS pages — copy edits |
| `Shop/` | Catalog browse | Copy edits + product-list paragraph config |
| `Shopping cart/` | Cart + checkout flow | Stock — DO NOT customise (high regression risk) |
| `Sign in/` | Login + register | Stock |
| `Newsletter Emails/` + `System emails/` | Email templates | Subject / body copy edits via admin UI |

### Page presets (the Theme primitive)

Each preset is a paragraph-driven layout. **Theme** = color palette / typography / spacing (the
Visual Editor surface for re-skinning). **Header**/**Footer** presets are referenced by every page (one
edit cascades site-wide). **Page-with-hero**, **Page-narrow**, **Page-full** are content-page layout
variants. Find the live list via Admin UI → Pages → Page presets.

### Page state flags — `active` is "Hidden in Menu", not route availability

The page row carries three orthogonal flags; misreading them causes false-alarm "page is broken"
findings or pollutes the nav menu.

| Flag | DB column | What it controls | Default for utility pages |
|---|---|---|---|
| `published` | (derived) | In the publish graph (live vs draft) | `true` once content is set |
| `hidden` | `Page.PageHidden` | **Excluded from frontend routing** entirely (404) | `false` — keep routable |
| `active` | `Page.PageActive` | **Appears in the navigation menu** ("Hidden in Menu" toggle) | `false` for cart steps, product detail, asset info |

(`Page.PageShowInLegend` is the legacy legend flag — the Swift navigation templates ignore it; don't
reach for it to hide a page from the nav.) The nav additionally hides permission-restricted pages
regardless of flags, which is why a login-gated page can sit at top level without a nav entry.

A page with `published=true, hidden=false, active=false` (DB: `PageActive=0, PageHidden=0`) is
**fully reachable** by direct URL and JS-driven navigation, and correctly hidden from the top nav —
the right state for almost every utility page. **Gotcha — the MCP page tools cannot express that
state:** `publish_pages`, `save_pages(active:…)` and `set_page_menu(showInMenu:…)` all flip **both**
columns together (`active/showInMenu: false` writes `PageActive=0` AND `PageHidden=1` — the page
leaves the nav but also 404s; `true` writes `1/0` — routable but back in the nav). Set the split
state via Management API `PageSave` or a SQL `UPDATE Page SET PageActive=0, PageHidden=0`, then
restart the host — the navigation tree and friendly-URL provider cache the old page set (see
[`cache-invalidation.md`](cache-invalidation.md)). When auditing reachability, check
`published=true` and `hidden=false`; do NOT flag `active=false` on its own. (Full SQL-direct INSERT
required-column list, including the `PageActiveFrom`/`PageActiveTo` silent-404 vector, lives in
[`data-access.md`](data-access.md).)

## 7. Style assets — `Files/System/Styles/`

The higher-leverage re-skin lever (Tier 0): drop a `<brand>.json` + `<brand>.css` pair into each
`wwwroot/Files/System/Styles/{ColorSchemes,Buttons,Typography}/`, point the Area row's
`AreaColorSchemeGroupId` / `AreaButtonStyleId` / `AreaTypographyId` columns at `<brand>`, restart. The
JSON is the source of truth (what admin Style Tools writes on save); the CSS is mechanically generated.
**Hand-authoring works** because the Master template only loads the CSS — keep the JSON in sync anyway
(the next admin save regenerates CSS from JSON).

| Directory | Purpose | Files | Area column |
|-----------|---------|-------|-------------|
| `ColorSchemes/` | Named schemes — background/foreground/button colors as CSS vars under `[data-dw-colorscheme="<id>"]`. Also `ColorScheme.config` (predefined scheme NAMES). | `<brand>.json` (group), `<brand>.css` | `AreaColorSchemeGroupId` (group) + `AreaColorSchemeId` (default scheme) |
| `Buttons/` | Shape, padding, border-radius/width on `[data-dw-button]`. | `<id>.json`, `<id>.css` | `AreaButtonStyleId` |
| `Typography/` | Font families, weights, scale, line-heights on `body`, headings, buttons. | `<id>.json`, `<id>.css` (may `@import` Google Fonts or `@font-face` local) | `AreaTypographyId` |
| `Fonts/` | `@font-face` definitions referenced from a Typography JSON's `*CustomFontId`. | `<font-id>.json`, `<font-id>.css`, `<file>.{ttf,otf,woff2}` | (none — Typography JSON refers by id) |

**How the Master loads them** (`Swift-v2_Master.cshtml`):

```cshtml
AddStylesheet("/Files/Templates/Designs/Swift-v2/Assets/css/swift.css");
@if (Model.TryGetColorSchemeStyle(out string? s)) { AddStylesheet(s); }
@if (Model.TryGetButtonStyle(out string? b)) { AddStylesheet(b); }
@if (Model.TryGetTypographyStyle(out string? t)) { AddStylesheet(t); }
```

`TryGet*Style` returns the URL to `Files/System/Styles/{…}/<area-column-value>.css` **if the file
exists** — and returns `false` (adding nothing to `<head>`) if absent.

**Empty-state pitfall (silent no-op).** A fresh scaffold leaves `Area.AreaColorSchemeGroupId='swift'`
but ships NO `Files/System/Styles/{…}/swift.{json,css}` on disk, so `TryGetColorSchemeStyle` returns
`false`, no scheme stylesheet is added, and every `data-dw-colorscheme="..."` paragraph renders
against default body styles — the page LOOKS styled (swift.css ships baseline rules) but the BRAND
palette never lands. Diagnostic: `curl -ks <host>/ | grep -c 'Styles/ColorSchemes'` returns 0 →
empty-state. Fix: the Area-wiring SQL below + on-disk `<brand>.{json,css}` files.

### JSON schemas (abbreviated)

ColorSchemes `<brand>.json`: root `Id` = what `AreaColorSchemeGroupId` points at; each `Schemes[].Id`
= what a paragraph's `data-dw-colorscheme` resolves against. Ship the same scheme `Id`s as Swift's
defaults (`light`, `lightgrey1`, `lightgrey2`, `dark`, `darksubtle`, `primary`, `secondary`) so
deserialized content's existing attributes map cleanly. The CSS emits one rule per scheme with `*-rgb`
companions (required for `rgba(var(--…-rgb), 0.5)` opacity tricks). Buttons `Shape` enum: **1** =
slight rounded, **2** = pill; `PaddingY`/`PaddingX` in rem. Typography uses `BaseFontSize`,
`BaseFontScale`, `ParagraphFont`/`HeadingFont`/`ButtonFont` (+ weights, line-heights); a local font
uses `ParagraphCustomFontId` resolving against `Fonts/<id>.json`'s `Family`.

### Wiring the Area to a brand

```sql
UPDATE Area SET
  AreaColorSchemeGroupId = '<brand>',   -- root Id from ColorSchemes/<brand>.json
  AreaColorSchemeId      = 'light',     -- which scheme is the area default
  AreaButtonStyleId      = '<brand>',
  AreaTypographyId       = '<brand>'
WHERE AreaId = <area>;
```

Restart so the resolved style URLs reload. Verify:
`curl -ks <host>/ | grep -E 'Styles/(ColorSchemes|Buttons|Typography)/'` → three new `<link>` entries.

**When to use Style assets vs a project CSS file:** use Style assets (Tier 0) for the brand palette +
button shape + typography (applies to every scheme-tagged paragraph, including deserialized baseline
content — highest leverage per line). Use the project CSS file (Tier 1) for everything else (hover
effects, nav polish, footer tweaks, empty-`data-dw-colorscheme` hacks); it loads after the Style
assets so its rules win cascade ties. (Color-scheme architecture/cascade + the CSS pitfalls live in
[`render-razor.md`](render-razor.md) §4-5.)

## 8. Asset organisation under `wwwroot/Files/`

`<host>\Dynamicweb.Host.Suite\wwwroot\Files\` is the live host's asset root.

| Folder | What lives there | Edit policy |
|--------|------------------|-------------|
| `Images/` | Logo, hero imagery, product images | Drop-in safe |
| `Documents/` | PDF/docx attachments referenced by paragraphs | Drop-in safe |
| `Templates/Designs/Swift-v2/` | Swift 2 design root. `Assets/css/swift.css` and `Files/System/Styles/` CSS are NEVER touched. The override slot is `Custom/<name>_custom.css` wired via `Custom/<name>HeadInclude.cshtml`. | Stock `.cshtml`: do not modify — create new content layouts alongside. `Custom/<name>_custom.css`: edit/create freely. |
| `Templates/Paragraph/` | Built-in paragraph Razor templates | DO NOT EDIT — alternative renderings are NEW content layouts alongside. |
| `Templates/Feeds/` | Feed Razor / XSLT templates | See feed/search references. |
| `System/Repositories/` | Index definitions + feed `.query` files | See [`search-indexing.md`](search-indexing.md). |
| `System/SmartSearches/Ecommerce/Shared/` | Dashboard `.query` files | Shared ONLY — see [`search-indexing.md`](search-indexing.md). |

**Asset upload — admin UI vs filesystem drop.** Both put a file into `wwwroot/Files/Images/`: admin
UI (Files → navigate → Upload, visible to property pickers immediately) or filesystem drop (visible on
next directory-listing read, no restart). Both show in `git status` the same way.

**What lives OUTSIDE `wwwroot/Files/`.** Admin UI File management surfaces ONLY `wwwroot/Files/`
content — anything else is shell-only. (Project-specific working folders, read-only context folders,
and ledger files live outside it; those are a deployment/working-folder convention, out of scope for
this skill.)

## 9. Re-skin doctrine — never edit standard templates

### Configuration-only is the default starting point

The configuration-only path covers most copy/asset/layout work with zero code (per
`doc.dynamicweb.dev/swift/design/configuration-only.html`). The 5-step Day-1 workflow: (1) mood board;
(2) translate into admin Style tools (Settings → Content → Styles → Color Schemes / Typography /
Buttons); (3) upload assets via Assets manager; (4) connect styles via Website Settings → Layout +
Favicon; (5) build layout in the Visual Editor. The doc is candid the approach "will consequently not
be able to do everything" — escalate when the style tools can't express the brand, don't fight the
configuration surface.

**Visual Editor surface map + escalation per gap:**

| Change | Visual Editor | Escalation if VE can't |
|--------|---------------|------------------------|
| Theme tokens (colors, typography) | YES (Style tools; bind via Website Settings → Layout) | project CSS overrides consuming `--dw-*` variables |
| Logo / hero image swap | YES (paragraph property → asset path) | n/a |
| Header / footer copy | YES (paragraph text) | n/a |
| Add a content paragraph | YES (page → "Add paragraph" → pick type) | n/a |
| Layout shape no preset matches; new column / alt rendering | NO | New content layout `.cshtml` (pixel-perfect escalation) |
| Site title | YES (Settings → Areas → SHOP1 → Site Settings) | n/a |
| Data-shape transform, conditional rendering, external calls / business logic | NO | Controller / provider `.cs` — triggers the customisations-ledger preflight |

**Executor split:** the admin click-paths are the *map* of what is configurable (for a human, and as
verification targets). When an agent makes a change itself it resolves the click-path to the
equivalent MCP / Management API call (every Style-tools save is an Admin API call underneath), and
drives `/Admin` only to verify, never to author.

### The never-touch list and the allowed override slot

Per `doc.dynamicweb.dev/swift/customization/design-css.html`:

- ❌ `Assets/css/swift.css` — Swift's stylesheet ("never edit Swift.css or DW-generated files"). Cascade
  order loses your changes anyway.
- ❌ `Files/System/Styles/{ColorSchemes,Buttons,Typography}/*.css` — DW-generated from admin config.
  Edit the source (admin Style Tools), not the generated CSS.
- ❌ Modifications to existing standard `.cshtml` under `Files/Templates/Designs/Swift-v2/` or
  `Files/Templates/Paragraph/` — per the pixel-perfect doc: extend or create new templates, never
  modify standard ones.
- ❌ `*Controller.cs`, `Providers/**` — the customisations-ledger preflight.
- ❌ Any `.scss` / `.ts` source — recompilation drift; the host serves compiled output.
- ❌ **Any Swift-shipped file named exactly `custom.css`** (`Custom/custom.css` placeholder ships
  `body { background: hotpink !important; }`; `Assets/css/custom.css` in the doc's load-order example)
  — Swift sample code, not the project's override file. Writing brand CSS into them breaks the sample
  and destroys the upgrade story. **Hard rule: brand CSS goes in a project-named `<name>_custom.css` —
  never a file named `custom.css`.** A `git diff` showing a stock `custom.css` modified is a re-skin
  bug: revert and move the rules. (Project-scoped custom-CSS naming is a deployment convention.)

✅ **Allowed:** a project-scoped `Files/Templates/Designs/Swift-v2/Custom/<name>_custom.css` in the
Swift `Custom/` slot, loaded after `swift.css`, wired via a `Custom/<name>HeadInclude.cshtml`
head-include ([`render-razor.md`](render-razor.md) §3). Layout-only `.cshtml` content layouts (escalation
tier 2) are also allowed — Razor `.cshtml` is **not** in the customisations-ledger preflight glob.

### Separate styling from content (don't paste HTML into RTF fields)

⚠ Inline-styled HTML pasted into a `Swift-v2_Text.Text` (or other RTF) field compiles and renders on
the frontend, but the admin RTE renders the same HTML on its white editor surface — so
`style="color:#ffffff"`, `background:#000`, etc. make content invisible/unusable inside the RTE.
Editor-hostile. The doc-canonical pattern is **item types + custom variants + project CSS +
data-attributes**:

1. Use the standard Swift item type matching the content shape (`Swift-v2_Poster` for heroes,
   `Swift-v2_Feature` for promo cards, `Swift-v2_Card` for content blocks). Editors get the right field
   schema; the admin RTE shows content the way the frontend will.
2. Author a custom variant `.cshtml` under `Paragraph/<ItemType>/`, emitting a
   `data-<brand>-variant="<name>"` attribute on the outer container.
3. Put the styling in the project CSS file, keyed off the data-attribute.
4. Keep them separate — cshtml renders fields with semantic markup; CSS does the visual; admin sees
   clean content.

(The full modeling discipline — decompose by editor concern, field-purity rules, the editor-gate — is
owned by [`content-modelling.md`](content-modelling.md).)

### Pixel-perfect escalation — what you may / may not create

Per `doc.dynamicweb.dev/swift/design/pixel-perfect.html`: "Avoid modifying standard templates
directly; extend or create new ones to remain upgradable." **You MAY** create a new content layout
`.cshtml` for an existing item type, or a new item type + its belonging content layout. **You may
NOT** modify existing standard `.cshtml`, add business logic to a content layout (data-shape
transforms / conditional rendering / external calls are controller/provider territory and trigger the
preflight), or override the customer-center CSR section's stock paragraphs. **Verification:** after the
change, `git status` should show ONLY new `.cshtml` files (not modifications to standard templates) and
no `.cs`. If `.cs` appears, you've crossed into controller/provider territory.

### Pre-escalation check — search the DW10 source first

Before climbing the ladder, search the DW10 source for the canonical surface. Common false-positive
escalations: gating paragraphs by group → Permission table ([`users-permissions.md`](users-permissions.md)),
not cshtml SQL; redirect from master by user identity → `Page.Loaded` subscriber, not `WriteLiteral`;
project-wide stylesheet → `CustomHeadInclude` ([`render-razor.md`](render-razor.md) §3), not inline
`AddStylesheet`; gate routes for anon → page-permission rows + `Page.PermissionType=0`; read user
point-balance / customer-number / groups → `Pageview.User.*` ([`render-viewmodels.md`](render-viewmodels.md)),
not SQL.

## 10. Discipline audit — grep pack

Verify a Swift build's templates against the canonical surfaces before declaring "ready" or before
folding learnings back. Each hit is a candidate finding; a clean run = green light.

```powershell
$Root = "Dynamicweb.Host.Suite\wwwroot"
$Slug = "<area-url-slug>"   # a hardcoded area prefix to scan for

# 1. Raw DB access in Razor (use Services.* per render-razor.md)
gci "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' | Select-String 'Database\.(CreateDataReader|ExecuteScalar|ExecuteReader|ExecuteNonQuery)'
# 2. Substring scans on URL/query (use page-id helpers + Pageview.User)
gci "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' | Select-String 'PathAndQuery\.IndexOf|QueryString\.ToString|Url\.AbsoluteUri\.Contains'
# 3. Hard-coded area prefixes
gci "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' | Select-String "/$Slug/"
# 4. Default.aspx?ID= synthesized links
gci "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' | Select-String 'Default\.aspx\?(ID|GroupID|ProductID)='
# 5. Category-name substring branching (use ProductGroup field)
gci "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' | Select-String '\.PrimaryOrDefaultGroup.*\.(Name|Title).*\.(Contains|StartsWith)'
# 6. Generic-item-type shim smell (project files under generic item folders)
gci "$Root\Templates\Designs\Swift-v2\Paragraph\Swift-v2_*\" -Recurse -Filter '*.cshtml' | ? { $_.Name -notlike 'Swift-v2_*' }
# 7. Inline AddStylesheet / AddScript in master (use Area.Item.CustomHeadInclude)
gci "$Root\Templates\Designs\Swift-v2\Swift-v2_Master.cshtml" | Select-String 'AddStylesheet|AddScript'
# 8. Regex on LongDescription / ProductName (use ProductField list types)
gci "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' | Select-String 'Regex\.(Match|Matches|Replace).*LongDescription|Regex\..*ProductName'
# 9. Stock custom.css written to (brand CSS belongs in <name>_custom.css)
git diff --name-only -- '*custom.css' | Select-String '(^|[\\/])custom\.css$'
git log --name-only --pretty=format: -- '*custom.css' | Select-String '(^|[\\/])custom\.css$' | Select-Object -Unique
```

| Grep | Hit means | Remediation |
|------|-----------|-------------|
| #1 | Raw DB access in a template | [`render-razor.md`](render-razor.md) §1 / [`commerce-catalog.md`](commerce-catalog.md) / [`commerce-orders.md`](commerce-orders.md) / [`render-viewmodels.md`](render-viewmodels.md) |
| #2,#3,#4 | Routing-by-URL-string / project-locked URL / legacy URL synthesis | [`render-razor.md`](render-razor.md) §1 URLs |
| #5 | Marketing-fragile branching | [`render-razor.md`](render-razor.md) per-category + [`content-modelling.md`](content-modelling.md) §2 |
| #6 | Shim instead of custom item type | [`content-modelling.md`](content-modelling.md) §2 |
| #7 | Cache-buster-breaking inline include | [`render-razor.md`](render-razor.md) §3 |
| #8 | Brittle content-extraction regex | [`render-razor.md`](render-razor.md) product field arrays |
| #9 | Brand CSS in Swift's shipped `custom.css` | §9 hard rule — revert, move to `<name>_custom.css` |

## Cross-references

- [`render-razor.md`](render-razor.md) — canonical `Services.*` surfaces, `ViewModelTemplate<>`
  pitfalls, `CustomHeadInclude` wiring, color schemes, CSS pitfalls.
- [`render-viewmodels.md`](render-viewmodels.md) — `ProductViewModel` field inventory + user/group
  accessors.
- [`content-modelling.md`](content-modelling.md) — modelling discipline, custom item-type `<Prefix>_*`
  discipline, language layers (incl. the cross-area component-selector cache).
- [`users-permissions.md`](users-permissions.md) — the Permission entity store (gate page/paragraph
  visibility without template edits).
- [`data-access.md`](data-access.md) — SQL-direct Page/GridRow/Paragraph seeding required columns.
- [`search-indexing.md`](search-indexing.md) — Repositories / queries / index placement.
- [`cache-invalidation.md`](cache-invalidation.md) — the post-mutation cache table.
