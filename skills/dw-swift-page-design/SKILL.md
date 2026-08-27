---
name: dw-swift-page-design
type: flow
group: swift
mcp: required
description: 'Build a good-looking Swift 2 page — matching the style of an existing page, from a supplied image/screenshot/mockup, from a plain-language description, or by recreating a single live page from its URL. Composes the page with the low-level content tools (save_grid_rows, save_paragraphs, set_paragraph_item_fields, color schemes) and the Swift 2 design grammar. Triggers: build a page that looks like another page, build a page from a screenshot or mockup, design a pretty campaign/landing page, recreate a live page''s look here. Non-triggers: importing/rebuilding a whole existing site -> dw-swift-migrate-content; a faithful Swift 1 port -> dw-swift-migrate-v1; a plain page with no design concern (build directly with the page/paragraph tools, no skill needed).'
---

# Swift 2 Page Design

## MCP preflight

This skill drives the Dynamicweb MCP server — its steps are tool calls. Before starting,
verify the Dynamicweb MCP tools are available. If they are not, stop and tell the user the
MCP connection is missing; do not substitute direct SQL, file edits, or guessed HTTP calls
for the tool calls this skill names.

Use this skill when the user wants to **build a good-looking Swift 2 page from a
reference** — either "make a page that looks like this other page" (clone/match an existing
page's style) or "build a page from this image/screenshot/mockup". You compose the page
directly with the low-level content tools and the Swift 2 design vocabulary.

**Load [dw-swift-page-blocks](../dw-swift-page-blocks) first** — it is the vocabulary (row
`DefinitionId`s, paragraph components + variants + fields, color schemes, the pretty-page
grammar) and the tool reference this flow assumes. Everything below is the *procedure*; that
skill is the *catalog*.

This is for authoring ONE page (or a small handful) with design intent — modeled on a
reference page or an image. It is NOT a site import: migrating *all* the pages/content from a
URL is [dw-swift-migrate-content](../dw-swift-migrate-content) (modern re-design) or
[dw-swift-migrate-v1](../dw-swift-migrate-v1) (faithful Swift 1 port); a plain page with no
design concern needs nothing beyond the ordinary page/paragraph tools.

## Before you write — snap to THIS solution (skipping this is what produces broken pages)

Template paths, component names, color schemes, and field names differ per solution and are
stored **verbatim** by `save_paragraphs`/`set_paragraph_item_fields` (no auto-correction). So,
once up front:
1. Call `get_item_types`, `get_row_definitions`, `get_paragraph_templates`,
   `get_color_schemes`. From here on use **only the exact strings they return.** Names quoted
   in `dw-swift-page-blocks` are illustrative — never copy them as literal values.
2. Honour the **Field & template contracts** (in `dw-swift-page-blocks`): pass each
   `get_paragraph_templates` value unchanged — a bare file name like `CardImageTop.cshtml`,
   never a `Designs/...` path; build button fields as `{"Label":"…","Link":"…",
   "Style":"primary"}` (not `ButtonText`/`ButtonStyle`); reference only color-scheme ids that
   exist — `save_color_schemes` a brand colour FIRST if you need a new one (a made-up id
   renders a broken band).
3. Create the page **once**. Check it doesn't already exist (`get_pages_by_parent_id`) before
   creating; on a multilingual site build on the master layer. Re-running blindly creates
   duplicate pages.
4. **Read ONE existing well-built page as your format reference** — a front page or a similar
   page in this solution. `get_paragraphs_by_page_id` then `get_item_field_values` on one
   instance of each component type you plan to use, and `get_grid_rows_by_page_id` for the
   row settings a real designer used here. Copy those value shapes verbatim. This is the
   cheapest single step in the whole flow: it hands you the heading markup convention, the
   button JSON, the option values and the row layout numbers at once, instead of discovering
   each one as a render error later.
5. **Spike one row before batching.** Build a single row containing one instance of each
   distinct component, render it (`fetch_frontend_page_html`, or fetch the page and grep for
   `Error executing template`), and only then create the remaining rows. Authoring thirty
   paragraphs before rendering one means every format mistake is paid for thirty times.

## Two modes

### Mode A — Match an existing page's style ("like the About page")

You are reproducing a *look*, not necessarily the content.

1. **Read the reference.** `get_grid_rows_by_page_id` on the source → join each row to
   `get_row_definitions` for its real column layout. `get_paragraphs_by_page_id` → the
   component type, variant `Template`, column, and `ColorSchemeId` of each paragraph. Note the
   **rhythm**: the sequence of (layout → scheme → component) down the page. That rhythm IS the
   style.
2. **Decide clone vs. reconstruct.**
   - Same content, new copy of the page → `copy_page` (clones grid + paragraphs + scheme refs
     in one call), then edit field values. Fastest; use when "duplicate this page and change
     the text".
   - New content in the same *style* → reconstruct: build fresh rows/paragraphs that mirror
     the reference's layout+scheme rhythm but carry the new copy. Use when the content
     differs.
3. **Build** (reconstruct path): `save_pages` → `save_grid_rows` (mirror the reference's
   `DefinitionId` per row, and set `ColorSchemeId` to match its banding) → `save_paragraphs`
   (same component + variant, into the right row/column) → `set_paragraph_item_fields` (the
   new copy/media/links).
4. **Carry the palette, not the copy.** Match `ColorSchemeId` per row so the banding reads the
   same; do not copy the source's text into an unrelated page.

### Mode B — Build from an image / screenshot / mockup

Be honest up front: the result is a **faithful Swift 2 interpretation of the design, not a
pixel-perfect clone.** You map what the image shows onto Swift 2's real components and grid —
you cannot invent CSS or custom layout the tools don't expose (see the ceiling in
`dw-swift-page-blocks`).

1. **Read the image as sections, top to bottom.** For each band identify: is it a hero (big
   image + headline + CTA → `Poster`)? an intro (`Text`)? a row of repeated cards/USPs
   (→ `3Columns`/`4Columns` of `Card`/`Feature`)? image-beside-text (→ `2Columns_8-4`)? a
   quote (`Blockquote`)? an FAQ (`Accordion`)? a CTA bar (`Button`)? Map each band to a
   (layout `DefinitionId` + component + variant) from the vocabulary.
2. **Read the palette.** Pick the per-row `ColorSchemeId` that matches each band's background
   (light bands → `light`/`lightgrey1`/`lightgrey2`; dark/accent bands → `dark`/`primary`).
   If the brand colors differ from the shipped schemes, propose a `save_color_schemes` update
   to the `swift` group (read it first — saves are full overwrites) rather than forcing an
   approximate scheme.
3. **Plan, then confirm** — show the section→component map so the user can correct a mis-read
   before you write (see Confirm before writing, below).
4. **Build** in vocabulary order: `save_pages` → `save_grid_rows` → `save_paragraphs` (real
   variant from `get_paragraph_templates`) → `set_paragraph_item_fields`. Use the user's
   supplied copy/images; where the image only shows lorem/placeholder, ask for the real text
   rather than baking in filler.

### Mode C — Recreate a live page from its URL

The user points at a real page ("recreate go-pakgroup.com's front page here").

1. **Get the reference screenshot FIRST, and judge on the image.** Page text proves content
   exists; it says nothing about whether the result *looks* alike, which is the actual
   requirement. Swift and most modern sites animate content in on scroll (AOS) and lazy-load
   images, so a naive full-page capture is mostly blank — force everything visible before
   shooting: add a style setting `[data-aos],.aos-init{opacity:1 !important;transform:none
   !important}`, add the `aos-animate` class to `.aos-init` elements, set every
   `img.loading='eager'`, then scroll the full height in steps. On a cookie banner, decline
   non-essential.
2. **Get exact content, don't scrape.** If the source is a Dynamicweb solution, `/dwapi` is
   open and authoritative: `/dwapi/content/areas`, `/dwapi/content/pages?AreaId=<id>`, and
   **`/dwapi/content/rows/<pageId>/Desktop`** for a page's full rows → columns → paragraphs →
   item fields. Shape: `row.Columns[].Paragraph` (singular), `row.Definition.Name`,
   `paragraph.Item.Fields[]`; array order IS render order. Dump it to a file and summarise
   rather than paging it all through context. For non-Dynamicweb sources, or a whole site
   rather than one page, use [dw-swift-migrate-content](../dw-swift-migrate-content) and its
   extraction tools instead.
3. **Write the mapping before building.** Source component → target component + variant + row
   `DefinitionId` + row layout (`ContainerWidth`/`GapX`). Verify every target type exists via
   `get_item_types`. Swift v1 → v2 has no `TextAdvanced` and no `SectionHeader`; both collapse
   to `Swift-v2_Text`. Full-bleed flush tile grids need `ContainerWidth: 4` + `GapX: 0`.
4. **Media on disk**, per the bulk-media gotcha in `dw-swift-page-blocks` — never base64 dozens
   of images through `upload_file`.
5. **Links to pages that don't exist in the target** resolve to nothing. Either point them at
   the source site's absolute URLs or leave them off — say which you did.
6. Then follow the shared discipline below, and verify by re-shooting and diffing against
   step 1.

### Header, footer and un-reproducible modules

- **Header/footer:** don't hand-build them. `setup_website_chrome(targetAreaId)` creates the
  hidden `Header / Footer` folder, a `Swift-v2_Header` page (Logo + horizontal Navigation) and
  a `Swift-v2_Footer` page (Logo + vertical Navigation + copyright), and wires the website's
  `HeaderDesktop`/`HeaderMobile`/`FooterDesktop`/`FooterMobile` Master link fields. It is
  idempotent and `sourceHost` is **optional**, so it works for an original site with no
  migration involved. It requires the area's Swift v2 master `ItemType` (provisioned by
  `save_areas`). If the tool isn't available it is permission-gated — say so and ask for the
  grant rather than reconstructing the chrome by hand.
- **Third-party embeds are not content.** Source pages carry blocks that are really external
  services: an unknown custom element (`<f24-form>`, `<x-*>`), a field whose entire value is a
  `<script>`, an iframe to a non-media host, a loader placeholder. Spot these at the
  **mapping** stage, not at the end.
  Then: build the **native equivalent** where one exists (a newsletter signup should become a
  real Swift form, not a picture of one); offer a native look-alike for purely **decorative**
  blocks (a `Poster` with the real copy and image); otherwise side-list it as "external
  service, not reproduced" and leave the slot empty.
  **Ask before simulating — never silently ship a look-alike.** And never let a simulation
  appear to collect data it cannot deliver: a fake newsletter or contact form that looks live
  but discards what people type costs the site real submissions and real trust. Either wire a
  genuine native form, or make it visibly a non-submitting placeholder. Same rule for anything
  implying a live integration — stock, prices, account state.

## Design discipline (both modes)

- Follow the pretty-page grammar from `dw-swift-page-blocks`: full-width `Poster` hero →
  alternating banded sections → `3Columns` for repeated blocks → standalone `Button` CTA →
  `Accordion` at the foot.
- **Alternate color schemes** between adjacent sections — that banding is what makes a Swift
  page read as designed rather than a flat stack.
- Use `3Columns` for any "three of a thing" (features, team, cards); don't stack them in a
  single column.
- Snap every component/variant/`DefinitionId` to what `get_item_types` /
  `get_paragraph_templates` / `get_row_definitions` actually return — never write a guessed
  name.
- Blank text fields you aren't using so no placeholder demo copy leaks through.
- **Assign a real image to every hero, card, and editorial slot.** A Swift page with empty
  `Image` fields renders as flat color blocks and text walls no matter how good the copy is —
  imagery is what makes it look designed. Discover the solution's media first (read an
  existing paragraph's `Image`, or the media tools) and fill every slot; never leave one blank
  or create an `Image` paragraph you can't fill. (See the image + rich-text contracts in
  `dw-swift-page-blocks`.)
- **Write Title/Subtitle/Eyebrow/Text as HTML, never bare strings.** These fields render raw,
  so a plain `Title` becomes tiny unstyled text glued to the next field. Wrap headings as
  `<h2 class="h1 mb-2">…</h2>`, eyebrows as `<p class="text-uppercase small mb-2">…</p>`, body
  as `<p class="mb-0">…</p>`. This is what gives the page its type hierarchy and vertical
  rhythm. `Feature` icons are SVG file paths (`/Files/Images/Icons/…svg`), not `bi …` classes.

## The visual quality bar — what separates a 6/10 page from a 9–10/10 page

A page can clear every contract above and still look amateur. Apply all of these:

- **One type scale, used consistently.** Pick exactly three levels and reuse them: hero =
  `display-4`/`display-5`; every section heading = the SAME class (e.g. `h1`); every
  card/feature title = the SAME smaller class (e.g. `h5`). Mixing `h1` on one section and `h2`
  on the next reads as a mistake.
- **Legible eyebrows — never washed-out grey.** An eyebrow/kicker is a small uppercase accent
  line: `<p class="text-uppercase fw-semibold mb-2"
  style="letter-spacing:.14em;font-size:.8rem;color:#<brand-accent>;">`. On a dark/`primary`
  band use white. `text-secondary` grey on a light band is near-invisible — don't use it for
  eyebrows or sub-headings.
- **Distinct, on-theme imagery in every slot.** Never reuse the same photo twice on a page,
  and make each image *mean* its section (a vineyard for "among the vines", a gift box for a
  gifting band). Verify what a file actually depicts before using it — generic
  "environment/stock" folders may contain off-theme shots that wreck the narrative. When
  unsure, prefer the on-brand product/lifestyle set.
- **Force a consistent aspect ratio on every image in a grid.** Cards in a row use `.card
  h-100` so the *container* equalises, but raw images of different native ratios still make
  the grid ragged. Append a crop ratio to the image path — `…/red.jpg?r=3/2` — and use the
  SAME ratio for all cards in the row. (`?r=W/H` also works to make a wide editorial band,
  e.g. `?r=21/9`.)
- **No dead CTA bands.** A full-width banded row holding a lone button reads as an empty
  colour block. Give every CTA section a heading + one line of copy + the button — the `Text`
  component carries `FirstButton`, so a single `Text` paragraph (`Title` + short `Text` +
  `FirstButton`) is a complete CTA section. Differentiate repeated CTA labels by what they do
  ("Shop the trio", "Book the tour") rather than three identical "Learn more"/"Shop now".
- **Blank unused `Subtitle` explicitly.** A newly created `Text`/`Poster` paragraph can
  materialise a shipped `Subtitle` placeholder that leaks between the heading and body. Set
  `Subtitle` to `""` on every paragraph where you don't use it.
- **Prefer a `3Columns` row of `Card`s over a `Slider` for a small fixed set.** Repeatable
  child-item updates (Slider/Accordion children) do not reliably re-render after edit on a
  live host — get the children right at create time, or use `Card`s (full per-item control,
  differentiated CTAs, no placeholder leak) when you have ≤4 items.
- **In an image-beside-text band, make the TEXT set the row height — not the image.** A
  `2Columns` (6/6) row with a square-ish photo lets the image dictate the height, so the copy
  top-aligns and leaves a big dead gap beneath it. Three levers, apply all three: set the
  row's `VerticalAlignment: "Center"` so the text centres against the image instead of hugging
  the top; give the text the wider column (`2Columns_8-4`, or `4-8` with the image first,
  alternating sides down the page); and crop the image to a landscape ratio with `?r=4/3` (or
  `3/2`). Verify by measuring row and column heights in the browser, not by eye.
- **Match testimonial author to the portrait.** If a `Blockquote` uses an `AuthorImage`, the
  name must fit the person shown, and force a legible author colour on dark bands
  (`style="color:#<light>;"`).

A quick self-check before declaring done: open the page in a browser and read each band — is
every heading clearly larger than its body? does every image fit its section's meaning and is
it unique? does every coloured band carry content, not just a button? is any eyebrow/sub-line
hard to read? Fix what fails; those are exactly the points a visual audit marks down.

## Confirm before writing

Before the first write, state the page + where it goes, the source of the design (which
reference page, or "from the supplied image"), the section→component plan (rows with their
layout + component + scheme), and whether it will be published. For Mode B, the
section→component map IS the thing to confirm — get it right before writing.

## Verify + summary

**Fetch the rendered page** with `fetch_frontend_page_html` and read it — confirm it shows
real content, NOT raw `{"Label":…}` JSON, overlapping/garbled text, or "the selected option no
longer exist". Reading back the stored structure is **not enough**: a page with perfectly
valid rows and paragraphs still renders broken if one `Template` path, button value, or scheme
id is wrong (that exact failure looks fine in `get_paragraphs_by_page_id`). If the render is
broken, find the offending field (almost always a bad `Template` path or button shape), fix
it, and re-fetch.

Also check the page is not merely *valid* but *designed* — these render fine structurally yet
look broken/boring, and each maps to a contract in `dw-swift-page-blocks`:
- **Headings the same size as body, or a title run into the next text** ("Free
  deliveryFree shipping…") → that field holds a bare string; rewrite it as `<h_ class="h1|h2|
  h3 mb-2">…</h_>`.
- **A flat color block where a hero should be, or text-only cards** → the `Image` field is
  blank; assign a real media file.
- **A USP/feature with no icon** → `Icon` is a CSS class string, not an SVG file path.
The published page is best inspected by rendering it in a browser (e.g. open its URL) — the
title-size and missing-image problems are obvious visually but invisible in the stored JSON.

Then read the structure back (`get_grid_rows_by_page_id` + `get_paragraphs_by_page_id`) and
confirm rows/components/schemes match the plan. If publishing, that is a separate write —
propose it as its own step. Report: rows + components created, color schemes used per band,
the render-check result, anything the image asked for that Swift 2 can't express (and what you
did instead), and any copy/media still needed. Nothing silent.

## Recovery

- Write fails on item-type/schema validation → re-read `get_item_type_fields` for that
  component and fix the field name; never invent placeholder values to satisfy a required
  field.
- A row renders structureless → its `DefinitionId` was omitted or wrong; re-set it via
  `save_grid_rows`.
- The look is off after build → check each row's `ColorSchemeId` (the look lives on the row,
  not the page).

## Out of scope

Custom CSS/JS, bespoke layouts the grid can't express, per-column spacing/offsets (not
settable — see the ceiling in `dw-swift-page-blocks`), product-list/detail design (PIM-driven),
and whole-site import ([dw-swift-migrate-content](../dw-swift-migrate-content) /
[dw-swift-migrate-v1](../dw-swift-migrate-v1)). When the design needs something past the
ceiling, say so and offer the closest Swift 2 composition instead of pretending.
