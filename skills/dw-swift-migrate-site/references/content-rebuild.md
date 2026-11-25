# Content rebuild: pages, brand, and chrome as standard Swift 2

The content phase of [dw-swift-migrate-site](../SKILL.md) (step 5). It reads the source site's
pages and rebuilds them here in Swift 2's own components: a modern rebuild, never a 1:1 copy of
the old design. The source can be any website: a Dynamicweb solution (Swift v1, Rapido, Espresso,
custom) or any other site.

## Contents

- [Reading the source](#reading-the-source)
- [The block list](#the-block-list)
- [Building a page with the standard tools](#building-a-page-with-the-standard-tools)
- [The dividing line](#the-dividing-line)
- [Scope of this phase](#scope-of-this-phase)
- [Flow](#flow)
- [Design guide: choosing components and variants](#design-guide-choosing-components-and-variants)
- [Recipes](#recipes)
- [How a well-built Swift 2 page reads](#how-a-well-built-swift-2-page-reads)
- [The product catalog shell](#the-product-catalog-shell)
- [Honesty floor](#honesty-floor)

The build runs on the standard MCP tools, one page at a time. The tools read, check and set up;
every layout decision is yours, made from this file and the field rules in
[dw-swift-page-blocks](../../dw-swift-page-blocks/SKILL.md) ("Field & template contracts").

Read the content of a Dynamicweb source on another solution from its rendered pages, like any
other site: its `/dwapi` content routes leave out blocks and return ones that aren't shown.
Rebuild blocks whose fields hold hand-written HTML as components; never paste the HTML into the
new website. Map the source's item types to Swift 2 components, and propose the mapping at the
website-proposal checkpoint.

## Reading the source

Read each page with your own web fetch or browser, one URL at a time, keeping the crawl delay.
Where the source is a website in the **same** solution, read it with the content tools instead
(`get_pages_by_area_id`, `get_grid_rows_by_page_id`, `get_paragraphs_by_page_id`,
`get_paragraph_item_field_values`); products, prices and files are already there. Two traps on
that route: a paragraph past its `validTo` still reads `active: true` but is not shown, so compare
the dates; and a row with `active: false` is not shown, nor are its paragraphs.

**Content inherits the limits of the reader that produced it.** A reader that executes no
JavaScript sees only a page's server-rendered shell: a client-rendered product grid is absent,
and a sign-in fragment for a price panel reads as a login gate over the whole catalog. So a source
page that reads as login-gated, empty or product-less is **unconfirmed** until a reader that
executes JavaScript has rendered it and counted the product tiles or main content nodes. Record
next to each such finding which reader produced it, and never let an unconfirmed finding set
scope.

When reading a page by hand, check for:

- images loaded late: the real source sits in `data-src` or `srcset`, and size suffixes in file
  names point at a smaller copy than the original
- photos set as CSS backgrounds, which no `<img>` shows
- content in tabs, accordions and sliders that is hidden until clicked
- counters that show `0` until animated; the value is in a data attribute
- text in plain `div` elements instead of headings and paragraphs, and page-builder wrappers
  around the real content
- scroll animations that keep content invisible in screenshots until scrolled into view
- fields holding hand-written HTML (`<style>`, `<script>`, `<iframe>`, images as data URIs)

## The block list

In the survey, list every block on each source page by what it is and what it contains. A block is
a piece of content as a visitor reads it, not an element of the source's page builder: when the
builder splits one sentence, list or heading with its text across several elements, list them as
one block. When building, record where each block ended up: which component or components,
merged into another block, or dropped for one of the approved reasons (`chrome`, `breadcrumb`,
`empty`, `duplicate-nav`, `product-list`, `product-detail`, `ecommerce`, `out-of-scope`). After
building a page, read it back with `get_paragraphs_by_page_id` and check it against the list:
every block that was used is there with its text, images and links, and no field is empty.

Keep the list in `RUN-STATE.md`, so a stopped run knows which blocks are done.

## Building a page with the standard tools

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
   through the same grid, so each needs its own row too. Check the row's phone layout
   (`MobileLayout`): columns that should stack on a phone are `12` each. Keep the column gap
   (`GapX`) at 3 or less on rows that stack: at 5, whole pages rendered wider than a 390 px phone
   and scrolled sideways.
3. Create the paragraph with `save_paragraphs`: id 0, the page, the component's item type, the
   variant as its template, the grid row from step 2, and the column. **One paragraph per grid
   column:** a second paragraph in the same column saves, reads back, and never renders; two
   stacked blocks are two rows.
4. Write the content with `set_paragraph_item_fields`, and **blank every button field in the same
   call** (`FirstButton: ""` and `SecondButton: ""` on a Text paragraph). A new paragraph gets
   text defaults in its button fields, the button editor fails on them, and the page renders an
   error block where the copy should be while still answering 200. Give a button a value only as
   a `{"Label":…,"Link":…,"LinkType":…,"Style":…}` object. The values each field takes (buttons,
   `Template` as a bare file name, the `Poster` heights, the row's `ContainerWidth`) are in
   [dw-swift-page-blocks](../../dw-swift-page-blocks/SKILL.md); read them before the first page.

**Prove each page on the rendered frontend:** a distinctive string from the copy you wrote is
present, and no error markup is. Then run `inspect_page_render` and `validate_page_content`, and
check it against the block list.

## The dividing line

- **The tools own the mechanics.** They create, read back, check and render; they never decide a
  layout.
- **You own content and arrangement.** Every word, image and link comes from the source; which
  block goes in which row and column, as which component and variant, with which color band,
  what merges into fewer and richer rows, and what is honestly dropped (chrome, breadcrumbs,
  empties). That design judgment is where the quality lives.

## Scope of this phase

- **In:** content pages (text, media, structure, internal links) and the brand (logo, favicon,
  colors as one color scheme, typography).
- **Product list and product detail pages:** never rebuilt as content. Identify them from what the
  page shows (or, on a Dynamicweb source, a `*ProductList*` or `*ProductDetails*` item type) and
  side-list them. Swift 2's standard catalog shell replaces them (see
  [The product catalog shell](#the-product-catalog-shell)).
- **Out:** unpublished pages, which the source does not return.

## Flow

1. **Read.** Read every page in scope as described in [Reading the source](#reading-the-source),
   and write the block list. Before building, compare 3–5 pages as read with the same pages
   rendered in a browser, late-loading blocks included, and fix the gaps.
2. **Target website.** Build into the website agreed at intake. A new website uses the Swift 2
   master layout (read the real design folder name from the solution's layouts if it isn't
   `Swift-v2`), and is active and published. Don't derive the website's URL prefix from its URL
   name. Measure it once on a page that certainly exists, and take every documented URL and verify
   step from that measurement (`dw-swift-building`, "Measure the storefront prefix once per
   host"). Internal links and navigation use page ids (`Default.aspx?ID=<id>`), so they don't
   depend on the prefix.
3. **Brand and website settings, before pages.** The website settings live on the website's
   settings item. List that item type's real fields and fill them from the source by meaning: site
   name, OG image, privacy and cookie links, cookie-banner layout. Skip and side-list analytics
   ids, verification tokens, social handles, ERP settings, and custom head includes. Then:
   - Create a color scheme group named after the site with `save_color_schemes`, and a button
     style with `save_button_styles`. Take the brand's colours from its brand guide if there is
     one, and from the logo. Check that every text and button colour pair reaches at least 4.5:1
     contrast. When the brand uses a colour the scheme's standard colours don't cover (a heading,
     link or accent colour that differs from the text and button colours), first judge whether it
     matters. If it is a deliberate brand choice (used consistently across the source, or part of
     the brand's identity), or the user asked for a close copy, give the user two options at the
     website-proposal checkpoint: align with the scheme's standard colours, or add it as a custom
     colour (`save_color_scheme_custom_colors`). If it is incidental, align, and say so in the
     proposal. A custom colour is a CSS variable in each scheme (`--dw-color-<id>`) and does
     nothing until CSS uses it: write that CSS with the variable and a fallback to the text colour
     (`var(--dw-color-<id>, var(--dw-color-foreground))`), in a stylesheet of the website's own
     linked through its "Custom `<head>` include file", or for some paragraphs as a class in a new
     layout template. Never edit Swift's own templates or stylesheet. Writing that file needs a
     Files folder the MCP configuration may write to; ask the user to grant one or add the file.
   - Set the typography from the brand: font, base size, scale and heading case, measured against
     the original. Name the original's font in the website proposal; when it's a font the solution
     doesn't have, ask the user to provide it for web use (font files or their web-font service) or
     to accept the close free font you propose. A typography's font is set by its Google Fonts
     family name: choose one of the same kind as the original (for example a geometric sans for a
     geometric sans), with the weights the brand uses. Copy font files from the source only when
     the user confirms the licence covers the new website; a free font needs no confirmation. The
     default typography is a starting point, not a decision. Use a new typography named after the
     site.
   - Assign the color scheme group, scheme, typography and button style to the website with
     `save_areas`, and check the served page head for their three stylesheet links.
   - Build the header and footer (desktop and phone) as pages under a parent page (not at the
     website's root), each with its rows and one paragraph per column: logo, menu, search, account
     and cart as the Swift 2 components. Link them in the website's `Swift-v2_Master` fields
     `HeaderDesktop`, `HeaderMobile`, `FooterDesktop` and `FooterMobile` with
     `set_item_field_values`. Swift 2 has no mega menu, so one becomes the menu's dropdown. When
     the solution has another Swift 2 website, `copy_page` its header and footer and adapt them.
4. **Media.** Upload images with `upload_file_from_url`, fetching the original file, into
   `/Files/Images/<source site>/`. Before building, check that the image handler serves each
   format: an AVIF original uploads fine but renders broken, so convert it first or use another
   format the source offers. Side-list images whose best original is smaller than the width they
   are shown at, so the owner can supply larger ones. On an installation with more than one
   website, check that each file is this site's own.
5. **Build pages.** For each page, decide what each block wants to be, build it as in
   [Building a page with the standard tools](#building-a-page-with-the-standard-tools), and
   record each block's place in the block list. Run the pages to completion without stopping
   between them; the checkpoint is at the end of the phase.
6. **Verify.** Check the frontend health of every built page, read each one back against the
   block list, and report pages built, components used, website settings filled versus skipped,
   and the side-list.

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
| Carousel/slider | `Swift-v2_Slider` | hero: `CardCoverFull`; in-page: `Card` |
| Icon + feature: an image the source shows small, as a badge or pictogram (for example under about 100 px), whatever its file type; the text may be long. Choose by how the source shows the image, not by its file | `Swift-v2_Feature` | `IconLeft` |
| Expandable sections | `Swift-v2_Accordion` | `Flush` |
| Standalone CTA link | `Swift-v2_Button` | `ButtonLeft` |
| Pull-quote | `Swift-v2_Blockquote` | `LeftLine` |
| Video (a Vimeo or YouTube URL). Keep a text link to the video next to it: like every external embed (a map, a social post), the player shows an empty box until the visitor accepts cookies, and in screenshots | `Swift-v2_VideoPlayer` | `Plain` |
| Plain image | `Swift-v2_Image` | `Plain` |
| Hand-written HTML | rebuild as the components above, and side-list what has no component | — |

Row layout: pick the row definition by column count and proportion (`1Column`, `2Columns_4-8`,
`3Columns`…); `1Column` always renders. When a block fits none of these, read the solution's
installed paragraph types and row definitions before choosing. Changing a paragraph's item type
afterwards wipes its fields, so choose before writing content.

## Recipes

- **A form.** Create the form and its fields with the form tools, set the form's template to the
  design's form template (`Forms/Form/Default.cshtml` on Swift 2; the automatic one renders a
  broken image per field), place the form app with `place_app_paragraph`, and set only its
  `FormId` setting.
- **A table.** A plain `<table>` with `<thead>` and `<tbody>` in a Text paragraph, no styles. Keep
  it to the columns a phone shows: a wide table pushed a phone page wider than the screen, so
  split a wide one into rows or cards.
- **A block the source repeats on several pages.** Build it once, then `copy_grid_row` it to each
  page and place it with `sort_grid_rows`.
- **A section's heading row and content row.** Tighten the spacing between them so they read as
  one section.
- **A collection (case list, news).** Child pages with a post list that fills itself and an index
  rebuild; fixed cards only when the index can't be touched, and side-list that choice.
- **Customer logos.** An image grid in a narrow container, not a slider.
- **An external call-to-action.** Button fields take a full external URL
  (`"LinkType":"external"`).
- **Transparent images and icons.** Check each against its band colour: a white line drawing
  vanishes on a light band.

## How a well-built Swift 2 page reads

Choose each page's sections for its content and visitors; a page has a hero, a showcase or an FAQ
only when its content calls for one. Vary section types, and group related small blocks into
shared rows instead of a long single-column stack.

## The product catalog shell

A Swift 2 catalog has a fixed page structure; keep it as it is:

- **Shop** page in the menu (`Swift-v2_Shop`), with the shop's group navigation under it
- Hidden **Product list** child (`Swift-v2_ProductList`), with a list-component selector
  pointing at a **Product list area** component page, whose item repeater stamps a **Product
  card** component page per product
- Hidden **Product detail** child (`Swift-v2_ProductDetails`), with a component selector
  pointing at a **Product info** component page
- All component pages in a **Product Components** folder
- The service pages tagged `ProductSliderService` and `VariantSelectorService`, and for a shop
  the cart and checkout pages
- Optionally, a product group can have its own product detail page, for products that need a
  different page (for example specifications first instead of images): a copy of the detail page
  without the navigation tag, set as the group's Primary page. Products use it only when that
  group is their primary group.

Copy these pages from another Swift 2 website in the solution with `copy_page` (or create them
with `save_pages` when a copy is refused), then point them at this website: the shop page's shop
and product page, every component selector and navigation setting, the product slider's
component page and the specification groups. A copy keeps the source website's page and shop ids
and its components' content (a stock-locations block, another shop's specification block), and
still renders, so check every setting on the copies. Check the variant service page carries its
`VariantSelectorService` tag.

Build this structure whenever the migration scope includes the catalog, and never for a
content-only migration of a site without commerce, so a brochure site never gets a shop. The
catalog renders empty until the import step has supplied products, the website is bound to the
shop, and the product index is built; the catalog tuning in [catalog-tuning.md](catalog-tuning.md)
builds on this shell. Payment and shipping methods are not set up here, so the checkout cannot
complete an order until they are.

The layout of these pages is decided for each site. Read what is on them, and the settings of the
product list and facet components, before changing it, and check the result rendered at desktop
and phone width.

## Honesty floor

- Account for every block in the block list, drops only for the approved reasons, and explain
  notable drops in the summary.
- Product list and detail pages and unpublished pages appear in the side-list, never rebuilt as
  content or guessed.
- End the phase with a side-list: drops and why, and what a human should review.
