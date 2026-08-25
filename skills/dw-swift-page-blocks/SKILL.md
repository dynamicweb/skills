---
name: dw-swift-page-blocks
type: knowledge
group: swift
description: 'Reference for the Swift 2 page-building vocabulary — grid row layouts (DefinitionIds), paragraph component types with their variants and fields, color schemes, and the MCP tools that compose them. Triggers: what row layouts/paragraph types/variants exist in Swift 2, how color schemes work, which tools build or read a Swift 2 page, load before designing or migrating any Swift 2 page. Non-triggers: designing item-type schemas -> dw-content-modelling; writing Razor/cshtml templates -> dw-render-razor; performing the actual page build or migration (this is reference only, no writes) -> dw-swift-page-design, dw-swift-migrate-v1, dw-swift-migrate-content.'
---

# Swift 2 Page Blocks

Reference for the Swift 2 page-building vocabulary — the row layouts, paragraph component
types, color schemes, and the MCP tools that compose them. Load this whenever you are about to
**design** or **migrate** a Swift 2 page; [dw-swift-page-design](../dw-swift-page-design) and
[dw-swift-migrate-v1](../dw-swift-migrate-v1) both build on it. It is reference, not an
action — those flow skills drive the actual writes.

> Everything below is the **shipped Swift v2** default set. Never trust this list blind on a
> live solution — a customer may have added, removed, or renamed components. Snap to reality
> with `get_row_definitions`, `get_item_types`, `get_paragraph_templates`,
> `get_layout_containers` and use the real ids. This catalog tells you what to *expect* and
> what each piece is *for*.

## The MCP tools, by job

**Discover (what exists on THIS solution):**
- `get_layouts` — page/area layout (master) templates; read the real Swift design folder name
  (often `Swift-v2`, not guaranteed).
- `get_row_definitions` — valid grid-row `DefinitionId`s + their column count/widths and which
  per-row toggles are supported.
- `get_paragraph_templates` — for a component, the real variant template paths (e.g.
  `TextMiddleLeft.cshtml`).
- `get_item_types` / `get_item_type_fields` — valid paragraph component names and each one's
  real field system names.
- `get_layout_containers` — the default content container.
- `get_content_apps` — module/app paragraphs (these go through `place_app_paragraph`, NOT
  `save_paragraphs`).

**Read (inspect a page's structure & style):**
- `get_page_by_id`, `get_pages_by_area_id`, `get_pages_by_parent_id` — the tree.
- `get_grid_rows_by_page_id` — the rows. **Returns only `DefinitionId` per row, NOT the
  columns** — join to `get_row_definitions` to learn the column layout.
- `get_paragraphs_by_page_id` — paragraphs with their `GridRowId` + column + `ItemType` +
  `ColorSchemeId`.
- `get_page_item_field_values`, `get_paragraph_item_field_values`, `get_item_type_fields` —
  the field values that hold the copy/media/links.
- `get_color_schemes` — resolve a `ColorSchemeId` to its actual colors (there is no
  "scheme-as-applied" call — read the id off the entity, then resolve here).

**Compose (write):**
- `save_pages` — create/update a page. Item-typed pages overwrite MenuText from the title
  field on every save → set the title field via `set_page_item_fields` FIRST, then
  `save_pages`.
- `save_grid_rows` — create rows. Multi-column comes **solely** from `DefinitionId`; omit it
  and the row is structureless. There is no row template/variant field and no per-column
  setting. **On a from-scratch page set `Container` to the layout's content container or the
  row never renders and the whole page comes up blank** — for Swift v2 that container is
  `Grid` (confirm with `get_layout_containers`, whose `IsDefault` flag marks it). Always pass
  it explicitly when creating rows on a brand-new page.
- `save_paragraphs` — create item-typed paragraphs; set `ItemType` to the exact
  `get_item_types` name, target `GridRowId` + column, and `Template` to the bare template name
  returned by `get_paragraph_templates` **verbatim** (see Field & template contracts). Inline
  grid placement is supported.
- `place_app_paragraph` — for app/module paragraphs only (the ones in `get_content_apps`).
- `set_paragraph_item_fields` / `set_page_item_fields` — fill field values (copy, media,
  links).
- `copy_page` — one-shot clone of a page incl. its grid, paragraphs, and `ColorSchemeId` refs
  (paragraphs included by default). The ONLY one-call clone; there is no style-only clone.
- `add_repeatable_item` — build Slider/Accordion child items. Keyed by **item identity, not
  paragraph**: pass `parentItemType` (e.g. `Swift-v2_Accordion`), `parentItemId` (the
  paragraph's `itemId`, from `get_paragraph_by_id` — NOT the paragraph id), `fieldSystemName`
  (`Accordion_Items`, with the underscore), and `childItemType`
  (`Swift-v2_Accordion_Item`) plus the child `fields` (`Title`, `Text` — wrap as HTML like any
  rich-text field). Slider is the same shape with its own field/child types.

**Style (the design system — file-backed, full-overwrite writes):**
- `get_color_schemes` / `save_color_schemes`, `get_typographies` / `save_typographies`, plus
  button-style and font tools. **Style writes are not patch-safe** — read first. A
  color-scheme save overwrites the submitted scheme's colors (sibling schemes in the group
  survive); typography/button/font saves replace the whole object.

## Grid row layouts (`DefinitionId`)

Fixed Bootstrap grid (`Swift-v2_Row`, widths sum to 12):

| DefinitionId | Cols / widths | Use |
|---|---|---|
| `1Column` | 1 [12] | Hero/Poster, full-width banner, single block, slider |
| `2Columns` | 2 [6,6] | Even split — text + image, two cards |
| `2Columns_8-4` / `2Columns_4-8` | 2 [8,4]/[4,8] | Main content + narrow aside (image+caption); alternate sides down the page |
| `2Columns_3-9` / `2Columns_9-3` | 2 [3,9]/[9,3] | Sidebar + content |
| `3Columns` | 3 [4,4,4] | The workhorse: Feature/Card/Text/Employee rows, 3 USPs |
| `4Columns` | 4 [3×4] | Logo wall, small card grid |
| `6Columns` | 6 [2×6] | Dense logo/icon strip |

Flexible auto-width (`Swift-v2_RowFlex`): `1ColumnFlex`, `2/3/4/6ColumnsFlex`,
`10ColumnsFlex`, `12ColumnsFlex`.

## Paragraph component types (the visual blocks)

Type = `Swift-v2_<Name>`. Buttons use the ButtonEditor (style+link+text); images use the
FileEditor (focal point); Eyebrow/Text are RichText. Variants are real `.cshtml` files —
confirm with `get_paragraph_templates`; field system names — confirm with
`get_item_type_fields` (do NOT assume them).

| Component | Key fields | Variants | Use |
|---|---|---|---|
| `Poster` | Image, Eyebrow, Title, Text, Height, First/Second button, Alt text | TextBottomLeft/Right, TextMiddleCenter/Left/Right | Hero / full-bleed banner with overlaid text + CTAs |
| `VideoPoster` | Video, Eyebrow, Title, Text, Height, 2 buttons | (Poster family) | Video hero |
| `Card` | Title, Text, Image, 2 buttons, Alt text, Image link | CardImageTop/Left/Right, CardOverlayLeft/Right, CardTitleTop | Image + title + REAL body text + CTA |
| `Feature` | Select Icon, Title, Text, Button | — | Icon USP, used in `3Columns` |
| `TextAndImage` | Title, Text, Image, Eyebrow, Subtitle, 2 buttons | — | Editorial text beside image |
| `Text` | Title, Subtitle, Text, 2 buttons | — | Headed rich-text block (most-used) |
| `Button` | First/Second button | — | Standalone CTA(s) |
| `Image` | Image, Alt text, Link | — | Standalone (optionally linked) image |
| `Accordion` | Accordion Items (repeating: Icon, Title, Text) | Flush / Shadow | FAQ / collapsible |
| `Blockquote` | Author image, Quote, Author | LeftLine / Card | Testimonial / pull-quote |
| `Slider` | Items (repeating) | Card / CardCoverFull | Carousel |
| `Employee` | User (backend user link) | ImageTop | Team member (pulls name/photo from the user) |
| `Logo` | logo | — | Brand logo strip |

App/feature paragraphs (`Navigation`, `MiniCart`, `SearchField`, `PostList`, `SignIn`,
`CartApp`, `CheckoutApp`, `ProductCatalogApp`, …) are NOT design blocks — route them through
`place_app_paragraph`.

## Field & template contracts (get these wrong and the paragraph renders broken)

`save_paragraphs` / `set_paragraph_item_fields` store these values **verbatim** — there is NO
auto-correction on this path. A wrong value renders as garbled raw text, overlapping text, or
"the selected option no longer exist".

- **`Template`** — use the `TemplatePath` value `get_paragraph_templates` returns for that
  component, **exactly as given**: a bare template file name, e.g. `CardImageTop.cshtml`. The
  platform resolves it inside the paragraph's item-type folder. Do **NOT** turn it into a path
  or add a `Designs/...` prefix, and don't hand-build it from the variant names in this doc
  (illustrative only; the real set differs per solution). A path value, or a name not in the
  returned set, makes the paragraph fall back to a wrong template that dumps raw field values.
- **Button fields** — EVERY field whose system name ends in `Button` (`FirstButton`,
  `SecondButton`, and the Feature's `Button`) is a ButtonEditor. Its value is ALWAYS a JSON
  object `{"Label":"Shop now","Link":"/shop","Style":"primary"}` (`Link` is a URL string;
  `Style` ∈ `primary` | `outline-primary` | `secondary` | `outline-secondary` | `link`).
  **Never a bare label string** like `"Shop now"` — that is invalid JSON, throws
  `Deserialize<ButtonData>` at render, and the WHOLE paragraph renders an exception dump (the
  overlapping garbled text). For no button, **omit the field** (or empty string) — never a
  plain string, `{}`, or wrong keys (`ButtonText`/`ButtonStyle`).
- **Text fields are rendered RAW — they MUST contain their own HTML.** The Swift paragraph
  templates emit `Eyebrow`, `Title`, `Subtitle`, and `Text` with bare `@field` (no heading tag,
  no wrapper, no separator). A **plain string** in `Title` therefore renders at body size with
  zero margin and butts straight against the next field ("Free delivery" + "Free
  shipping…" → "Free deliveryFree shipping…"). This is the single biggest cause of a page that
  "renders but looks like an unstyled wall of text." So:
  - `Title` → a heading element with a Bootstrap size class: `<h2 class="h1 mb-2">A
    collection worth celebrating</h2>` (use `h1`/`h2`/`h3`/`display-5` for size, `mb-*` for
    spacing). Section headings are NOT optional formatting — without the tag they vanish into
    the body text.
  - `Subtitle` → `<p class="lead text-secondary mb-3">…</p>`; `Eyebrow` → `<p
    class="text-uppercase small mb-2">New in</p>`.
  - `Text` → `<p class="mb-0">…</p>` (multiple `<p>` for multiple paragraphs).
  - Mirror what a well-built existing page on this solution already stores
    (`<h2 class="h3 mb-1">…</h2>`, `<p class="mb-0">…</p>`, or the editor's
    `dw-h*`/`dw-paragraph*` classes). NEVER pass a bare unwrapped string to any of these
    fields.
- **Images are not optional — a blank `Image` is the #1 reason a Swift page looks boring.** A
  `Poster` with no image is a flat color rectangle; a `Card` with no image is a text box; an
  empty `Image` paragraph is dead space. Before building, find the real imagery this solution
  ships (media tools / read an existing paragraph's `Image` value) and assign a fitting file
  to EVERY hero, card, and editorial image slot. Never leave one blank, and never create an
  `Image` paragraph you can't fill.
- **Image fields** (`Image`) — a media-library file path that exists (e.g.
  `/Files/Images/mcp-wine/hero.jpg`), from an existing paragraph or the media tools, not an
  invented URL.
- **`Feature` `Icon` is an SVG/image FILE path, not a CSS icon class.** The template does
  `TryGetImageFile("Icon", …)` and renders nothing if it fails — so `bi bi-truck` (a
  Bootstrap-icons class) shows NO icon. Use a real file from the solution's icon set, e.g.
  `/Files/Images/Icons/truck.svg`. Check what icon files exist before referencing one.
- **Media / video fields** (`Swift-v2_VideoPlayer.VideoSource`) are a MediaEditor: the value
  is a JSON object `{"Path":"https://youtu.be/xyz","ImagePath":""}` (`Path` = the video URL or
  file, `ImagePath` = optional poster). A **bare URL throws `ConverterException: Cannot
  deserialize json string to object of type MediaData`** and the whole paragraph renders an
  exception dump.
- **Option-valued fields (BoxedRadio / dropdown) take the option VALUE, not its label — and
  `get_item_type_fields` does NOT return the legal values.** It gives you `editorType` only.
  So read an existing sibling paragraph's value with `get_item_field_values` before setting
  one; never invent a label-ish string. Known Swift v2 values:
  - `Swift-v2_Poster.Height` → `"2"` = 35vh, `"3"` = 55vh, `"4"` = 85vh. Unset renders a short
    boxy tile.
  - Row `ContainerWidth` → `1` = text width, `2` = 65vw, `3` = default page container,
    **`4` = full-bleed (100% width, zero gutter)**.
  - Row `GapX` / `GapY` → `0` = flush (tiles butt together), `1` = .25rem, `2` = .5rem,
    **`3` = 1rem (default)**, `4` = 2rem, `5` = 3rem, `6` = 6rem.
  - Full-bleed flush image/poster tile grids — the look most brand sites use — are
    `ContainerWidth: 4` + `GapX: 0` + `GapY: 0`. Default (`3`/`3`) gives boxed tiles with white
    gutters.
- **`ColorSchemeId`** (row or paragraph) — only an id `get_color_schemes` returns. To use a
  brand colour, create/update the scheme via `save_color_schemes` FIRST, then reference its
  id. A made-up id (`deep-red`, `offer-highlight`, …) renders an unstyled/broken band.

Rule of thumb: every component name, template path, scheme id, and field system name you
write must be a string a discovery tool actually returned for THIS solution — never one you
composed from this reference.

## Color schemes & the design system

The look is **file-backed JSON** under `Files/System/Styles` (read/write via the style tools,
never by hand):
- `ColorSchemes/swift.json` is a **Group** (`Id:"swift"`) holding a `Schemes[]` array; each
  scheme has `Id`, `Name`, `BackgroundColor`, `ForegroundColor`, `PrimaryButtonColor`,
  `SecondaryButtonColor`. `save_color_schemes` takes scheme rows tagged with their `GroupId`
  (the service saves them into the backing group). Read before write: a submitted scheme's
  colors are fully overwritten (omitted colors nulled, custom colors cleared); other schemes
  in the group are untouched.
- Shipped scheme ids: `light` (#FFF/#242424), `lightgrey1` (#ededed), `lightgrey2` (#f2f2f2),
  `dark` (#242424/#fff), `darksubtle` (#575757), `primary` (#004fff/#fff — brand accent),
  `secondary`. A given solution may rename/add these — `get_color_schemes` is the source of
  truth; reference only ids it returns, and `save_color_schemes` a new one before using it.
- Typography (`Typography/fonts.json`, default font **Inter**, modular scale 1.333) and
  Buttons (`Buttons/buttons.json` — Shape/border/padding; button *colors* come from the
  scheme, not here) are single objects.

## Where the "look" actually lives — the ROW

Pages do not carry a theme (the `Swift-v2_Page` item type is basically just Title). The
**Area** holds the global default styles. **Each row** is the styling unit:
- Per row via `save_grid_rows`: `DefinitionId` (layout) + `ColorSchemeId` (the scheme) +
  optional `BackgroundImage`, plus `Sort` / `Container` / `Active`.
- A paragraph can override the row's scheme with its own `ColorSchemeId` on `save_paragraphs`.
- Mechanism: the row renders `data-dw-colorscheme="<id>"` and `swift.css` maps it to colors.
  **"Applying a scheme" = just setting the id** — no CSS, no class.

So a page's appearance = (area styles as base) + per-row layout + per-row color scheme.
**Alternating schemes between rows** (default → `light` → `lightgrey2` → `lightgrey1`) is what
gives Swift pages their banded, sectioned look.

## The pretty-page grammar (a good default rhythm)

Top → bottom, a rhythm that reads as designed rather than a flat stack:
1. **Hero** — full-width `1Column`: a `Poster` or a `Swift-v2_Slider` with image slides.
2. **Intro** — `1Column` `Text`.
3. **Media / editorial** — `2Columns_8-4` (image + caption) or a `Slider`, alternating image
   side down the page.
4. **Section bands** — switch to a banded scheme (`light`, then `lightgrey2`, then
   `lightgrey1`) to separate sections.
5. **Multi-up content** — `3Columns` of `Feature` (icon USPs), `Text`, `Card`, or `Employee`.
6. **CTA** — a standalone `1Column` `Button` closing a section.
7. **FAQ** — an `Accordion` at the foot.

Vary section types, give a hero/section the `primary` band when it fits the brand, and group
small related blocks into one multi-column row instead of a long single-column stack.

## Gotchas that bite

1. `get_grid_rows_*` returns no columns — always join to `get_row_definitions`.
2. `save_grid_rows` applies no default layout — set `DefinitionId` or the row is
   structureless.
3. Item-typed page rename is two-step: set the title field first, then `save_pages` (it
   rewrites MenuText from the title).
4. Style writes aren't patch-safe: a saved color scheme has its own colors overwritten
   (sibling schemes survive); typography/button/font replace the whole object. Read first.
5. Component routing: item-typed → `save_paragraphs(ItemType=…)`; app/module →
   `place_app_paragraph`. Wrong tool = broken paragraph.
6. Unset text fields can render placeholder copy from the item's default values — blank
   fields you don't use.
7. `Template` for an item-typed paragraph is a **bare file name** (e.g. `CardImageTop.cshtml`)
   from `get_paragraph_templates`, used unchanged. A `Designs/...` path → "selected option no
   longer exist" → the paragraph dumps raw field values.
8. Button fields are `{"Label","Link","Style"}` JSON; any other shape (or a plain string)
   renders as visible raw text. Scheme/template ids must be ones the discovery tools
   returned — invented ids break the render.
9. **A paragraph inside a grid row cannot be hidden.** `Paragraph.ShowParagraph` is
   `get => _showParagraph || GridRowId > 0` ("by design, grid row paragraphs must be
   active"), so `save_paragraphs` with `Active: false` **silently no-ops** — the read-back
   still says active and it still renders. To remove a block from a grid page,
   `delete_paragraphs` it.
10. **Swift v2 sliders have no slides-per-page or aspect-ratio field** (Swift v1 had
    `SlidesPerPage` + `SliderRatio`). `Swift-v2_Slider` has ONE field, `Items`; per-page count
    and crop live in the variant template. So a logo strip built as a slider renders as a few
    enormous cards. For an evenly-sized logo row use a multi-column row (`4Columns`/
    `6Columns`) of `Swift-v2_Image` instead.
11. **Bulk media: copy files on disk, never base64 through `upload_file`.** Each image becomes
    a tool argument, so a few dozen images is millions of tokens. Get the archive root from
    the DW host's file-path setting, copy in with a shell loop, and preserve the source's
    `/Files/...` sub-paths so field values match.
12. **An item-typed paragraph's `Header` is derived from its item title field, so
    `save_paragraphs(Header: …)` does not stick.** `Swift-v2_Text`/`Poster`/etc. declare
    `fieldForTitle` (see `get_item_types`), and the platform rewrites the paragraph header
    from that field on every save — the same behaviour as page `MenuText` (gotcha 3). A
    brand-new item also arrives carrying Swift's shipped default field values, so an
    untouched `Swift-v2_Text` shows up in the CMS tree with placeholder demo copy as its
    title. Fix it by setting the item's title field, not `Header`. It is CMS-tree cosmetics
    only — nothing renders from it — so don't spend calls chasing it mid-build.
13. `get_layout_containers` reports BOTH kinds of container — `@Model.Placeholder(...)` ones
    and the `Model.Grid(...)` ones a Swift v2 page layout uses. Take the `IsDefault` entry
    (`Grid` on `Swift-v2_Page.cshtml`) as the `Container` for rows and paragraphs. A row saved
    with no `Container` never lands in the layout's content area and the whole page renders
    blank, so let the create path default it or pass a discovered name — never a guess.
14. Batching: `set_item_field_values` takes a list spanning DIFFERENT items, so a whole page's
    field values fit in one or two calls — prefer it to one `set_paragraph_item_fields` per
    paragraph. For repeatable children (slider slides, accordion rows) pass an explicit
    `sort` to `add_repeatable_item`, or parallel calls race and scramble the order.
15. **A grid-column CELL renders exactly ONE paragraph.** Stacking a second paragraph into the
    same `GridRowId` + `gridRowColumn` (higher `Sort`) saves fine, reads back fine, and NEVER
    renders — the content is silently invisible, with no error anywhere. One paragraph per
    cell; need two blocks stacked visually → two rows.
16. **A new area MUST get `TypographyId` and `ButtonStyleId` set (standard Swift ids: `fonts`
    / `buttons`) or the whole site renders as unstyled 16px Times New Roman** — Swift's
    heading/body scale is driven by the area's typography CSS variables, so with the setting
    empty, heading classes (`h1`/`h2`/`display-*`) do nothing and every page looks broken. Set
    them in the same `save_areas` call that creates the area.

## Row layout — settable, and what the row look depends on

`save_grid_rows` exposes the row's own layout properties alongside `DefinitionId`/
`ColorSchemeId`: `ContainerWidth`, `GapX`, `GapY`, `TopSpacing`, `BottomSpacing` (values
above). These decide whether a row reads as boxed cards-with-gutters or as a flush full-bleed
band, so they matter as much as the component choice. A row definition only honours them when
its JSON sets the matching `EnableContainerWidth` / `EnableGapSettings` / `EnableTopSpacing` /
`EnableBottomSpacing` — check `get_row_definitions`.

## Ceiling (not settable via MCP)

No per-column settings (offsets, per-column scheme or spacing), no grid-row template/variant,
no row `MobileLayout`/`MobileSortColumns`/`FlexibleColumns`, no per-row device visibility, no
paragraph styling beyond `ColorSchemeId` (no CSS class/anchor), no page-level SEO/redirect/
validity unless surfaced as item fields, and no slider slides-per-page/ratio (see gotcha 10).
Design within this — don't promise what the tools can't set.

**Row vertical alignment matters more than it looks.** `save_grid_rows` takes
`VerticalAlignment` (`None` | `Start` | `Center` | `End`, rendered as
`data-dw-row-vertical-align`). It defaults to `None`, which top-aligns every column — so in an
image-beside-text band the short text column sits at the top and leaves a dead gap beneath
it. Set `Center` on those rows. See "Design discipline" in
[dw-swift-page-design](../dw-swift-page-design).

**Text alignment lives in the field HTML, not in a setting.** The `Swift-v2_Text` variants
centre by default (`text-center` in `TextCenter.cshtml`); the variant name picks the block's
alignment and there is no per-column override. To left-align copy inside a centred variant,
put the class on your own element: `<p class="text-start mb-0">…</p>`. If a layout genuinely
needs something here, say so plainly rather than approximating it and calling it done.
