---
name: dw-swift-migrate-content
type: flow
group: swift
description: 'Bring the CONTENT of an existing/old website into a Dynamicweb 10 solution as a standard, modern Swift 2 site — extract a source site''s pages/media and rebuild them here. Source-agnostic: a Dynamicweb solution (Swift v1/Rapido/Espresso/custom, read via /dwapi) or any other site (generic HTML crawl). Triggers: import/rebuild a whole existing site''s content in Swift 2, migrate this site''s content into the solution, rebuild an old site as Swift 2. Non-triggers: a faithful Swift 1 1:1 layout port -> dw-swift-migrate-v1; migrating PIM product structure/data -> dw-pim-migrate-dw9; a single new page with design intent -> dw-swift-page-design.'
---

# Swift 2 Content Migration

Use this skill when the user wants the CONTENT of an existing/old website brought into this
solution as a standard, modern **Swift 2** site — extract a source site and rebuild its pages
here. It is content-first and source-agnostic: the source can be ANY website — a Dynamicweb
solution (Swift v1 / Rapido / Espresso / custom, read via `/dwapi`) **or any other site** (read
via the generic HTML crawler). You arrange the extracted content in Swift 2's own components,
NOT a 1:1 copy of the old design.

**The dividing line — this is the whole architecture:**

- **The build owns content and structure.** It fills every word of copy, every image and
  every link FROM THE EXTRACTION; validates your plan exactly (every block accounted for,
  drops only for approved reasons); snaps every component/variant/row definition to what is
  installed; enforces the preconditions (Swift 2 installed, v2 design, published area — it
  fail-fasts or self-heals); imports media, remaps links, scaffolds the chrome, sorts the
  front page; and rebuilds any page faithfully when its plan fails validation. **You cannot
  lose or invent content — the contract makes it impossible.**
- **You own arrangement.** Which block goes in which row/column, as which component and
  variant, with which color band, what merges into fewer/richer rows, and what is honestly
  dropped (chrome, breadcrumbs, empties). That is the design judgment — it is the only thing
  you decide, and it is where the quality lives.

This is the modern-rebuild sibling of [dw-swift-migrate-v1](../dw-swift-migrate-v1): that
skill exists specifically for a **Swift 1** source where the user wants the layout kept 1:1.
For any other source, or when the user wants a modern re-design rather than a faithful port,
use this skill.

## Scope (hard)

- **In:** content pages — text, media, structure, internal links; brand logo/favicon/colors
  → one color scheme.
- **Leave alone:** product list & product detail pages (identify from a page's
  `SourceItemType` — a `*ProductList*` / `*ProductDetails*` type) and side-list them as "left
  intact". When the source has such pages, `setup_website_chrome` scaffolds their standard
  Swift 2 replacement (a Shop page with hidden Product list/Product detail pages wired to
  Product Components) — products, the shop binding and the product index remain the product
  migration's job (see [dw-pim-migrate-dw9](../dw-pim-migrate-dw9) when the source is DW9).
- **Out:** e-commerce data, PIM, integrations, and unpublished pages (the source API cannot
  return unpublished pages — see the extraction `Warnings`). Never guess e-com.

## The per-page contract — a CONTENT-FREE layout plan

`get_extracted_page(sourceHost, pageId)` returns the page's `Rows` → `Columns` → `Blocks`;
**each block carries a stable `Id`**. You read each block's `Title`/`Texts`/`Images`/`Links`/
`Children`/`Options` to understand WHAT it is — but your `PageBuildSpec` carries **no text**:
only `SourcePageId` (a REAL id from the extraction — never invent pages) and a `Plan`:

```jsonc
{
  "Rows": [
    { "DefinitionId": "2Columns_8-4",
      "Columns": [
        { "Blocks": [ { "BlockId": "4711", "Component": "Swift-v2_Text" } ] },
        { "Blocks": [ { "BlockId": "4712", "Component": "Swift-v2_Image", "Variant": "Plain" } ] }
      ] }
  ],
  "Dispositions": {           // EVERY extracted block id must appear
    "4710": "dropped:breadcrumb",
    "4711": "used",
    "4712": "used",
    "4713": "merged-into:4711"
  }
}
```

- `used` blocks appear exactly once in `Rows`; `merged-into:<id>` blocks render as their OWN
  paragraph next to the target (grouping into fewer/richer rows — never concatenation). Drops
  only from: `chrome | breadcrumb | empty | duplicate-nav | product-list | product-detail |
  ecommerce | out-of-scope`.
- Omit `Component` to let the deterministic mapper choose for that block (do this for
  product-group showcases and raw-HTML blocks). Unknown components fall back to the mapper's
  faithful choice.
- A failed plan rebuilds that page faithfully and flags it — per page, never aborting the
  batch.
- Tree facts (parent, menu visibility, name, order, front page) come from the extraction
  automatically — never guess or set them.

## Flow

1. **Confirm once.** State the source + target ("Rebuild gopak.cloud content into <site> as
   Swift 2"). Once the user agrees, the whole run is authorized — do NOT raise a new
   confirmation or stop to check in per batch.

2. **Extract.** `extract_site_content(sourceUrl, [username/password|bearerToken|apiKey])` →
   page tree, brand, media count, warnings. **Works on ANY website**: Dynamicweb sources via
   `/dwapi`; anything else falls back to generic HTML extraction — the `Warnings` say which
   mode ran (treat HTML-mode trees with extra scepticism in the final summary). Note the
   `SourceHost`, and present the `Warnings` up front: an unauthenticated read misses
   unpublished pages, so every count is a floor. (`get_extracted_site(sourceHost)` re-reads a
   prior extraction.)

3. **Target area.** Build into a FRESH area set up as a real Swift 2 site: `save_areas` with
   the Swift-v2 master `LayoutTemplate`, `Active: true`, `Published: true`. (`build_pages`
   fail-fasts when Swift 2 isn't installed or the area's design isn't v2, and self-heals the
   publish state — but set it up right from the start.) Read the real design folder name from
   `get_layouts` if it isn't `Swift-v2`.

4. **Brand & the Master settings item — BEFORE pages.** The website settings live on the item
   identified by the area's `ItemType` + `ItemId` (from `get_areas`; set `ItemType` via
   `save_areas` if missing, then re-read for the `ItemId`). **Enumerate real fields with
   `get_item_type_fields(area.ItemType)` and match the extracted `Brand`/`AreaSettings` by
   meaning:** carry site/brand name, OG/meta image, privacy & cookie policy links (remap
   `Default.aspx?ID=<sourceId>` first), cookie-banner layout and behavioral toggles. **Skip
   and side-list** analytics/tag-manager ids, verification tokens, social handles, ERP/
   commerce settings, custom head includes — anything tied to the old domain/account. Then:
   - `apply_brand_color_scheme(targetAreaId, sourceHost)` — creates + applies the branded
     scheme from the captured palette (its `primary` scheme is the accent band for hero/
     section rows). Don't hand-build schemes.
   - `setup_website_chrome(targetAreaId, sourceHost, includeProductCatalog)` — scaffolds the
     standard header/footer/mobile chrome, the working search page + app, the sign-in
     foundation, the cart/checkout flow when the target is commerce-capable, and (when YOU
     decide the site needs one — see "The product catalog") the standard product catalog.
     Wires all the Master link fields. Check `Status`/`WiredFields`/`Errors`. Never hand-build
     the chrome.

5. **Media.** `import_site_media(sourceHost)` — path-preserving, idempotent. Side-list its
   `Failures`.

6. **Build pages in batches — design each page, then build (run to completion silently).**
   For each page: `get_extracted_page` → **think like a designer** (what is this page? what
   does each block want to be? which blocks group into a shared row, which are chrome/empty
   drops?) → emit the `Plan`. Build the batch in ONE call: `build_pages(targetAreaId,
   [PageBuildSpec…], sourceHost)` → per-page results + `HasMore`/`NextSourcePageIds` (folders,
   system and product pages are excluded for you). **While `HasMore` is true**: take
   `NextSourcePageIds`, design, build, repeat — re-send only failures. **Auto-continue, no
   narration**: no "shall I continue?" between batches; if the runtime ends your turn, resume
   immediately; post exactly ONE final summary at the very end. Internal-link remapping, the
   content index build and front-page sorting run automatically (per batch + a final pass).

7. **Verify + final summary (one message).** `find_unresolvable_item_pages(targetAreaId)`;
   spot-check a built page renders with header/footer. Report: pages built, components used,
   Master settings filled vs skipped, plans that fell back to the faithful mapping, and the
   side-list — drops and why, low-confidence blocks, product/e-com pages left intact, missing
   media, settings not carried. Nothing silent.

## Design guide — choosing components and variants (a STARTING POINT, not a lookup table)

Reason about each block and restructure when a richer composition serves the content better —
a banner wants to be a `Poster`, a set of items wants `Card`s or a `Slider`, Q&A wants an
`Accordion`. Decide from the content, never from the source item type.

| The block looks like… | Component | Typical variant |
|---|---|---|
| Heading / body text | `Swift-v2_Text` | `TextLeft` (or Center/Right per the block's options) |
| Big image + overlaid headline/CTA (hero) | `Swift-v2_Poster` | `TextMiddleLeft` / `TextBottomLeft` |
| Image beside text | image col `Swift-v2_Image` + text col `Swift-v2_Text` in `2Columns_8-4`/`4-8` | `Plain` + `TextLeft` |
| A card (image + title + REAL body text) | `Swift-v2_Card` | `CardImageTop` |
| A grid of image+label TILES (category tiles, no body text) | N× `Swift-v2_Poster` in an N-column row (fixed-ratio crop keeps the row aligned; label/button bottom-anchored) | `TextBottomLeft` |
| A tile with NO label at all (brand-logo tiles) | clickable `Swift-v2_Image` | `Plain` |
| Carousel/slider (`Children[]`, was a slider) | `Swift-v2_Slider` (slides come from the block's children) | hero: `CardCoverFull`; in-page: `Card` |
| Product-group showcase (`Options["ProductGroupIds"]`) | omit `Component` — the build picks the native group slider when the target has the groups + a Shop page, else aligned tiles | — |
| Icon + short feature | `Swift-v2_Feature` | `IconLeft` |
| Expandable sections (`Children[]`) | `Swift-v2_Accordion` | `Flush` |
| Standalone CTA link | `Swift-v2_Button` | `ButtonLeft` |
| Pull-quote | `Swift-v2_Blockquote` | `LeftLine` |
| Video | `Swift-v2_VideoPlayer` | `Plain` |
| Plain image | `Swift-v2_Image` | `Plain` |
| Unknown / only `RawHtml` | omit `Component` (the mapper renders it faithfully) — and side-list it | — |

Row layout: pass the source row's `LayoutHint` through when it matches a real `DefinitionId`
(`1Column`, `2Columns_4-8`, `3Columns`…); otherwise pick by column count. `1Column` always
renders.

## How a WELL-BUILT Swift 2 page reads (the grammar shared with dw-swift-page-blocks)

1. **Hero** — full-width `1Column`: a `Poster` or a `Swift-v2_Slider` with image slides.
2. **Intro** — `1Column` `Text`.
3. **Image-beside-text sections** — `2Columns_8-4` / `2Columns_4-8`, **alternating sides**
   down the page.
4. **Showcase** — `3Columns`/`4Columns` of `Poster` tiles or `Feature`s; `Card`s only with
   real body text.
5. **CTA** — a standalone `Button` row.
6. **FAQ/details** — an `Accordion`.

The rhythm is your design freedom — the content is fixed by the extraction. Vary section
types, group related small blocks into shared rows (`merged-into`) instead of a long
single-column stack, and give a hero/section row the `primary` color band when it fits the
brand. See [dw-swift-page-blocks](../dw-swift-page-blocks) for the full vocabulary this design
guide draws on.

## The product catalog — know it, judge it, then let the tool build it

A GOOD Swift 2 catalog is one fixed shape (this is what a stock Swift 2 install ships — don't
invent another):

- **Shop** page in the menu (`Swift-v2_Shop`) — the shop's group navigation hangs under it.
- Hidden **Product list** child (`Swift-v2_ProductList`): one `2Columns_3-9` row — group
  navigation + facets in the narrow column, a list-component selector in the wide one pointing
  (by page id) at a **Product list area** component page (selected-facet chips + the item
  repeater, which stamps a **Product card** component page per product: image, name, price,
  add-to-cart).
- Hidden **Product detail** child (`Swift-v2_ProductDetails`): one `2Columns_8-4` row —
  product media wide, a component selector narrow pointing at a **Product info** component
  page (name, number, price, description, variant selector, add-to-cart).
- All component pages live in a **Product Components** folder. Group/product links route to
  the hidden pages automatically — nothing else to wire.

**The decision is yours; the construction is not.** `setup_website_chrome` builds exactly the
shape above, idempotently. Decide `includeProductCatalog` from the SOURCE:

- Source has `*ProductList*`/`*ProductDetails*`-typed pages → the tool auto-scaffolds; omit
  the parameter.
- Source's catalog is module/app-driven and untyped (the extraction shows pages whose blocks
  are content-free module placeholders clearly belonging to the old product catalog — e.g.
  blocks named after a product-catalog app) and products are being migrated for this site →
  pass `true`.
- Source has no commerce at all → omit (nothing triggers) — never scaffold a shop onto a
  brochure site.
- Genuinely unclear → fold ONE question into the up-front confirmation; never a mid-run stop.

**After the scaffold, tune it like a designer** with the normal page/paragraph tools — the
scaffold is the standard starting point, not a straitjacket: a B2B trade site may want the
product NUMBER on the card; a site without variants doesn't need the variant selector; a
download/asset portal wants `Swift-v2_ProductAddToDownloadCart` instead of add-to-cart. Read
the result's Notes: the catalog renders EMPTY until the product migration supplies products,
the area's shop binding (`save_areas`: `EcomShopId`) and a product index — repeat those
prerequisites in your final summary rather than presenting the catalog as live. When the
source is a DW9 solution, [dw-pim-migrate-dw9](../dw-pim-migrate-dw9) is the product-side
counterpart to this content migration.

## Honesty floor

- Account for EVERY block id in `Dispositions` — drops only for the approved reasons. The
  validator enforces it; plan accordingly, and explain notable drops in the final summary.
- Product list/detail, e-com, unpublished: "left intact / out of scope" in the side-list,
  never rebuilt as content or guessed — the catalog scaffold (when you chose it) is reported
  as scaffolded-empty, with its prerequisites.
- End with a clear side-list: drops and why, plans that fell back, what a human should review.

## Confirm before writing

State the source + target site and that it's a Swift 2 rebuild. Confirm the page count and
that it's a rebuild (not a 1:1 copy), and into which website. Confirm once; then the whole run
is authorized — one final summary at the end, never a stop-and-wait after each batch.

## Out of scope

- A perfect 1:1 reproduction of the old design (explicitly a non-goal — produce standard,
  modern Swift 2; for that, see [dw-swift-migrate-v1](../dw-swift-migrate-v1)).
- Rebuilding the OLD product list/detail pages' look, e-commerce data, PIM, integrations,
  unpublished pages. (The standard catalog scaffold replaces the old catalog pages
  structurally — their old design is not carried.)
