# Content rebuild: pages, brand, and chrome as standard Swift 2

The content phase of [dw-swift-migrate-site](../SKILL.md) (step 5). It reads the source site's
pages and rebuilds them here in Swift 2's own components: a modern rebuild, never a 1:1 copy of
the old design. The source can be any website: a Dynamicweb solution (Swift v1, Rapido, Espresso,
custom, read over `/dwapi`) or any other site.

## Contents

- [Check the migration tools first](#check-the-migration-tools-first)
- [Building without the migration tools](#building-without-the-migration-tools)
- [The dividing line](#the-dividing-line)
- [Scope of this phase](#scope-of-this-phase)
- [The per-page contract: a content-free layout plan](#the-per-page-contract-a-content-free-layout-plan)
- [Flow](#flow)
- [Design guide: choosing components and variants](#design-guide-choosing-components-and-variants)
- [How a well-built Swift 2 page reads](#how-a-well-built-swift-2-page-reads)
- [The product catalog shell](#the-product-catalog-shell)
- [Honesty floor](#honesty-floor)

## Check the migration tools first

The MCP server has a family of migration tools that read a source site and build pages from it:
`extract_site_content`, `get_extracted_site`, `get_extracted_page`, `build_pages`,
`import_site_media`, `apply_brand_color_scheme` and `setup_website_chrome`. The family is
restricted: it reaches an MCP configuration only once an administrator grants it. Without the
grant the names are absent from the tool list and a call answers `Access denied ... Required
permission: Read. Allowed permission: none` [mcp 0.6.0-beta].

So **list the tools first**:

- The seven are present: run this phase as written.
- They are absent: name the missing tools, tell the user the fix is to grant the migration tools
  to the MCP configuration this session connects with, and list the tools again after they have.
  The family ships inside the MCP add-in itself, so an AppStore search for a separate "migration"
  app finds nothing and proves nothing.

**Content inherits the limits of the reader that produced it.** A reader that executes no
JavaScript sees only a page's server-rendered shell: a client-rendered product grid is absent,
and a sign-in fragment for a price panel reads as a login gate over the whole catalog. So a source
page that reads as login-gated, empty or product-less is **unconfirmed** until a reader that
executes JavaScript has rendered it and counted the product tiles or main content nodes. Record
next to each such finding which reader produced it, and never let an unconfirmed finding set
scope.

## Building without the migration tools

Use this path while the grant is missing, and when the flow below says not to run the
extraction. The content scraped in step 2 is the source, and the construction runs on the ordinary
page tools, one page at a time. It replaces the construction only, never a design decision, and
none of the page builder's checks run, so read every page back.

**Create order for every component**, each call carrying its item type:

1. Create the page with `save_pages`: id 0, the area, the parent page, menu text, URL name, and
   `itemType: 'Swift-v2_Page'`. **The item type must be on the create call.** Adding it to an
   existing page creates no item, and every later field write fails with `Page N has no item type
   attached` [dw 10.28.11 · mcp 0.6.0-beta]. Recreate such a page.
2. Create a grid row with `save_grid_rows`: id 0, the page, the row definition, a sort order,
   `itemType: 'Swift-v2_Row'`, and **the layout's content container**. Read the container name
   once from the layout's containers (the one marked default, `Grid` on Swift 2) and pass it
   verbatim. A row with an empty or unknown container saves and reads back, but its paragraphs
   never render and the page answers 200 with an empty `<main>`. Header and footer pages render
   through the same grid, so each needs its own row too.
3. Create the paragraph with `save_paragraphs`: id 0, the page, the component's item type, the
   variant as its template, the grid row from step 2, and the column. **One paragraph per grid
   column:** a second paragraph in the same column saves, reads back, and never renders; two
   stacked blocks are two rows.
4. Write the content with `set_paragraph_item_fields`, and **blank every button field in the same
   call** (`FirstButton: ""` and `SecondButton: ""` on a Text paragraph). A new paragraph gets
   text defaults in its button fields, the button editor fails on them, and the page renders an
   error block where the copy should be while still answering 200. Give a button a value only as
   a `{"Label":…,"Link":…,"Style":…}` object.

**Prove each page on the rendered frontend:** a distinctive string from the copy you wrote is
present, and no error markup is.

The other migration tools fall back the same way:

- **Media:** upload the images to `/Files/Images/<source site>/` (the dw CLI for many files).
- **Color scheme:** create the scheme group and its schemes from the brand colors, then assign
  the group and scheme to the website.
- **Header and footer:** with the migration tools granted, the chrome tool needs no extraction
  (give it the logo file and the menu links). Without them, use what the website already has, and
  build a missing header or footer as a page with one row and one paragraph per column, wired to
  the website's settings.

## The dividing line

- **The build owns content and structure.** It fills every word of copy, every image and every
  link from the source; validates the plan exactly (every block accounted for, drops only for
  approved reasons); snaps every component, variant and row definition to what is installed;
  checks the preconditions (Swift 2 installed, v2 design, published website); imports media,
  remaps links, scaffolds the chrome, and sorts the front page. Content cannot be lost or invented.
- **You own arrangement.** Which block goes in which row and column, as which component and
  variant, with which color band, what merges into fewer and richer rows, and what is honestly
  dropped (chrome, breadcrumbs, empties). That design judgment is where the quality lives.

## Scope of this phase

- **In:** content pages (text, media, structure, internal links) and the brand (logo, favicon,
  colors as one color scheme).
- **Product list and product detail pages:** never rebuilt as content. Identify them from the
  extracted page's source item type (a `*ProductList*` or `*ProductDetails*` type) or, on another
  platform, from what the page shows, and side-list them. Swift 2's standard catalog shell
  replaces them (see [The product catalog shell](#the-product-catalog-shell)).
- **Out:** unpublished pages (the source cannot return them; see the extraction warnings).

## The per-page contract: a content-free layout plan

With the migration tools, each extracted page comes back as `Rows` → `Columns` → `Blocks`, each
block with a stable `Id`. Read each block's `Title`/`Texts`/`Images`/`Links`/`Children`/`Options`
to understand what it is, but the page build spec carries **no text**: only `SourcePageId` (a real
id from the extraction, never an invented page) and a `Plan`:

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

- `used` blocks appear exactly once in `Rows`; `merged-into:<id>` blocks render as their own
  paragraph next to the target (grouping into fewer, richer rows, never concatenation). Drops
  only from: `chrome | breadcrumb | empty | duplicate-nav | product-list | product-detail |
  ecommerce | out-of-scope`.
- Omit `Component` to let the deterministic mapper choose for that block (do this for
  product-group showcases and raw-HTML blocks). Unknown components fall back to the mapper.
- A failed plan rebuilds that page faithfully and flags it, per page, never aborting the batch.
- Tree facts (parent, menu visibility, name, order, front page) come from the extraction
  automatically; never set them by hand.

Without the migration tools, make the same decisions per block and record them in `RUN-STATE.md`
the same way, so every source block is accounted for.

## Flow

1. **Extract.** Run the site extraction with the source URL (and credentials when the source
   needs them). It returns the page tree, brand, media count, and warnings. Dynamicweb sources are
   read over `/dwapi`; anything else falls back to generic HTML extraction, and the warnings say
   which mode ran (treat HTML-mode trees with extra scepticism). Note the source host and report
   the warnings: an unauthenticated read misses unpublished pages, so every count is a floor. A
   prior extraction can be re-read without crawling again.
   **Run the extraction only when the user confirms the source's owner accepts its load.** Both
   modes read the source 6 requests at a time without reading `robots.txt`, and HTML mode crawls
   up to 120 pages [mcp 0.6.1-beta], so it cannot keep the crawl delay, the
   one-request-per-second default, or a scope of a few pages. That fits a solution the customer
   owns and has agreed to; for any other source, build from the files of step 2 as described in
   [Building without the migration tools](#building-without-the-migration-tools).
2. **Target website.** Build into the website agreed at intake. A new website uses the Swift 2
   master layout (read the real design folder name from the solution's layouts if it isn't
   `Swift-v2`), and is active and published. Decide deliberately whether child URLs ignore the
   website's URL name: off puts every page at `/<website url name>/<page>`, on puts it at
   `/<page>`, the usual shape for a single storefront. Derive every internal link and nav target
   from that choice.
3. **Brand and website settings, before pages.** The website settings live on the website's
   settings item. List that item type's real fields and fill them from the extracted brand and
   settings by meaning: site name, OG image, privacy and cookie links (remap
   `Default.aspx?ID=<sourceId>` first), cookie-banner layout. Skip and side-list analytics ids,
   verification tokens, social handles, ERP settings, and custom head includes. Then:
   - Create and apply the branded color scheme from the captured palette with the migration tool
     built for it. Do not hand-build schemes while that tool is available.
   - Scaffold the header and footer (logo and navigation, desktop and mobile) with the chrome
     tool, and the product catalog shell when the catalog is in scope. It works without an
     extraction when given the logo file and the menu links. It creates no search, sign-in, cart
     or checkout pages. Check its status, wired fields and errors. Do not hand-build the chrome
     while that tool is available.
4. **Media.** Import the source media (path-preserving and safe to repeat). Side-list its
   failures. The media import reads the source 6 files at a time like the extraction, so the
   same consent applies; without it, upload the images downloaded in step 2.
5. **Build pages in batches.** For each page, read the extracted page, decide what each block
   wants to be, and write the plan. Build a batch of pages in one call; the result has per-page
   results and says whether more pages remain (folders, system and product pages are excluded).
   While more remain, design and build the next batch, re-sending only failures. Run the batches
   to completion without stopping between them; the checkpoint is at the end of the phase.
6. **Verify.** Look for pages whose item cannot be resolved, then check the frontend health of
   every built page. Report pages built, components used, website settings filled versus skipped,
   plans that fell back to the faithful mapping, and the side-list.

## Design guide: choosing components and variants

Decide from the content, never from the source item type, and restructure when a richer
composition serves the content better.

| The block looks like… | Component | Typical variant |
|---|---|---|
| Heading / body text | `Swift-v2_Text` | `TextLeft` (or Center/Right per the block's options) |
| Big image + overlaid headline/CTA (hero) | `Swift-v2_Poster` | `TextMiddleLeft` / `TextBottomLeft` |
| Image beside text | image col `Swift-v2_Image` + text col `Swift-v2_Text` in `2Columns_8-4`/`4-8` | `Plain` + `TextLeft` |
| A card (image + title + real body text) | `Swift-v2_Card` | `CardImageTop` |
| A grid of image + label tiles (no body text) | N× `Swift-v2_Poster` in an N-column row | `TextBottomLeft` |
| A tile with no label (brand-logo tiles) | clickable `Swift-v2_Image` | `Plain` |
| Carousel/slider (`Children[]`) | `Swift-v2_Slider` | hero: `CardCoverFull`; in-page: `Card` |
| Product-group showcase (`Options["ProductGroupIds"]`) | omit `Component` | — |
| Icon + short feature | `Swift-v2_Feature` | `IconLeft` |
| Expandable sections (`Children[]`) | `Swift-v2_Accordion` | `Flush` |
| Standalone CTA link | `Swift-v2_Button` | `ButtonLeft` |
| Pull-quote | `Swift-v2_Blockquote` | `LeftLine` |
| Video | `Swift-v2_VideoPlayer` | `Plain` |
| Plain image | `Swift-v2_Image` | `Plain` |
| Unknown / only `RawHtml` | omit `Component`, and side-list it | — |

Row layout: pass the source row's `LayoutHint` through when it matches a real `DefinitionId`
(`1Column`, `2Columns_4-8`, `3Columns`…); otherwise pick by column count. `1Column` always
renders. When a block fits none of these, read the solution's installed paragraph types and row
definitions before choosing.

## How a well-built Swift 2 page reads

1. **Hero:** full-width `1Column` with a `Poster` or a `Swift-v2_Slider` of image slides
2. **Intro:** `1Column` `Text`
3. **Image-beside-text sections:** `2Columns_8-4` / `2Columns_4-8`, alternating sides
4. **Showcase:** `3Columns`/`4Columns` of `Poster` tiles or `Feature`s; `Card`s only with real
   body text
5. **CTA:** a standalone `Button` row
6. **FAQ/details:** an `Accordion`

Vary section types, group related small blocks into shared rows (`merged-into`) instead of a
long single-column stack, and give a hero or section row the `primary` color band when it fits the
brand.

## The product catalog shell

A stock Swift 2 catalog is one fixed shape; do not invent another:

- **Shop** page in the menu (`Swift-v2_Shop`), with the shop's group navigation under it
- Hidden **Product list** child (`Swift-v2_ProductList`): one `2Columns_3-9` row with group
  navigation and facets in the narrow column and a list-component selector in the wide one,
  pointing at a **Product list area** component page whose item repeater stamps a **Product
  card** component page per product
- Hidden **Product detail** child (`Swift-v2_ProductDetails`): one `2Columns_8-4` row with
  product media wide and a component selector narrow, pointing at a **Product info** component
  page (name, number, price, description, variant selector, add-to-cart)
- All component pages in a **Product Components** folder

The chrome tool builds exactly this shape when asked to include the product catalog. Ask for it
whenever the migration scope includes the catalog, and never for a content-only migration of a
site without commerce, so a brochure site never gets a shop. The catalog renders empty until the
import step has supplied products, the website is bound to the shop, and the product index is
built; the catalog tuning in [catalog-tuning.md](catalog-tuning.md) builds on this shell.

## Honesty floor

- Account for every block id in `Dispositions`, drops only for the approved reasons, and explain
  notable drops in the summary.
- Product list and detail pages and unpublished pages appear in the side-list, never rebuilt as
  content or guessed.
- End the phase with a side-list: drops and why, plans that fell back, and what a human should
  review.
