---
name: dw-swift-upgrade
type: flow
group: swift
mcp: required
dynamo: true
description: 'Upgrade a Swift 1 site to Swift 2 as it is: a faithful port of its pages with layout and structure preserved. Triggers: upgrade Swift 1 to Swift 2, Swift v1 migration, 1:1 layout port, faithful Swift conversion. Non-triggers: redesign, non-Swift source or catalog -> dw-swift-migrate-site; new page -> dw-swift-page-design.'
---

# Swift 1 → Swift 2 upgrade

## MCP preflight

This skill drives the Dynamicweb MCP server. Its steps are tool calls, and the MCP tool set plus
read/write under `Files/` is the whole surface they may use. Call `tools/list` before planning and
check the tools each step names below. If a step's tool is missing, **stop at that step** and tell
the user what is missing and which admin screen performs it; do not substitute a guessed HTTP
call, a file edit outside `Files/`, or SQL. The Management API, the serializer and direct SQL are
out-of-product surfaces, owned by [`dw-data-access`](../dw-data-access/SKILL.md), and are never a
step here.

**Reading the source is a precondition.** The MCP server works on one solution, the target.

- **Source in the same solution** (a Swift 1 website next to the new Swift 2 one): read it with
  the content tools. Nothing else is needed.
- **Source on another solution**: the rendered pages have to be read some other way. Check
  `tools/list` (and the client's own tools) for one that fetches a public URL or drives a
  browser. `fetch_frontend_page_html` reads pages of this solution only. When nothing reads the
  source, ask the user for the content (page list, copy, image URLs) or to load the source into
  this solution, then run the skill on what they give.

## When to use it

Use this skill when the user wants to move pages from a **Swift 1** (Swift v1) website to
**Swift 2** and **keep the layout**: a faithful, structure-preserving port, not a re-design.
What makes it worth its own skill: **Swift 1 and Swift 2 use the same grid model** (paragraphs
placed by row and column, and the row `DefinitionId` sets overlap almost 1:1), so the original
layout can carry over.

This is the faithful sibling of [dw-swift-migrate-site](../dw-swift-migrate-site). That skill
moves ANY source into *standard, modern* Swift 2 and **re-flows content into new compositions on
purpose**. Choose by intent:

- "migrate all the pages from this site, make it modern" → [dw-swift-migrate-site](../dw-swift-migrate-site).
- "it's a Swift 1 site, port it and **keep the layout / don't redesign / 1:1**" → THIS skill.
- one new page with design intent, no source → [dw-swift-page-design](../dw-swift-page-design).

**Load [dw-swift-page-blocks](../dw-swift-page-blocks) first** for the target vocabulary. Its
"Field & template contracts" section and its "Gotchas that bite" list hold the field rules this
skill relies on: button values as `{"Label","Link","Style"}` JSON, `Template` as the bare file
name from `get_paragraph_templates`, the `Swift-v2_Poster` `Height` values, the row
`ContainerWidth` and gap values, and text fields that carry their own HTML. Follow them there;
they are not repeated here.

## What you decide

You build every page with the standard tools, so every choice is yours: the row `DefinitionId`,
the row color band, the component and its template, and the value of every field. Nothing picks
a component by content shape for you, and nothing fills a field you leave out. That is why the
result can match the source closely, and also why each page must be read back.

## The block list

A **block** is a piece of content as a visitor reads it: a hero with its heading and button, a
quote, a row of three cards. It is not a page-builder element; one block can span several
paragraphs, and one paragraph can hold several blocks.

- **Survey:** for each source page, list every block in reading order, with its row and column,
  its text, images and links.
- **Build:** record where each block ended up: the component that holds it, `merged` into
  another block (name it), or `dropped` with a reason the user approved at the proposal.
- **Read back:** after building a page, read it with `get_paragraphs_by_page_id` and check it
  against the list. Every block marked used is there, with its text, images and links, and no
  field is empty that the source filled.

The block list is the proof that nothing was lost. Keep it per page until the final summary.

## Mapping Swift 1 item types to Swift 2

Do not assume a mapping. Work it out from this solution and propose it.

1. **Read the source types.** `get_item_types`, then `get_item_type_fields` for each Swift 1 item
   type the source pages use. Read real values with `get_paragraph_item_field_values` on a few
   paragraphs of each type.
2. **Read the target types the same way**, and `get_paragraph_templates` for each Swift 2
   component you consider.
3. **Compare how each renders.** Look at the source block on the rendered page and at how the
   Swift 2 component lays out the same fields. Map by what the visitor sees, not by name.
4. **Propose the mapping** at the proposal checkpoint: one line per Swift 1 type with its Swift 2
   component, template and field mapping, plus any field that has no home.

What one test found, as a starting point only:

- Same-named pairs mostly carry over (`Swift_Text` → `Swift-v2_Text`, `Swift_Poster` →
  `Swift-v2_Poster`, `Swift_Image`, `Swift_Slider`, `Swift_Accordion`). Still check the fields.
- `Swift_TextAdvanced`, `Swift_SectionHeader`, `Swift_ArticleHeader`, `Swift_MegaMenu` and
  `Swift_Article` have no Swift 2 type of the same name. Choose a target by how the block
  renders, and say what is lost.
- Swift 1 option values (poster height, layout, button style, row width, row spacing, image
  ratio) have no stated Swift 2 equivalent. Map each one by its rendered effect, against the
  Swift 2 values in dw-swift-page-blocks, and list your choice in the proposal. Do not present it
  as a known table.

Row `DefinitionId`s map near 1:1 (`1Column`, `2Columns`, the `2Columns_*` splits, `3/4/6Columns`,
the `*Flex` rows). `5ColumnsFlex` has no Swift 2 twin: take the nearest (`6ColumnsFlex`) or split
the row, and flag it. Check the real set with `get_row_definitions`.

## Flow

1. **Target precondition.** Build into a real Swift 2 website (`save_areas` with the Swift 2
   master `LayoutTemplate`, `Active` and `Published`); confirm the design folder name from
   `get_layouts`. Discover the target vocabulary once: `get_row_definitions`, `get_item_types`,
   `get_paragraph_templates`, `get_layout_containers`.
2. **Survey the source (read only).**
   - Same solution: `get_pages_by_area_id` for the tree, then per page
     `get_grid_rows_by_page_id`, `get_paragraphs_by_page_id` and
     `get_paragraph_item_field_values`. Inactive rows are listed with `active=false`; leave them
     out. A paragraph past its `validTo` still reads `active=true` but is not shown, so compare
     the dates and leave expired ones out too.
   - Another solution: read the rendered pages with the fetch or browser tool from the preflight.
   - Note the brand (colors, fonts, button shapes), the header and footer, the media, and every
     internal link and product-group reference. Write the block list.
3. **Proposal checkpoint: confirm once.** State the source and target, that this is a
   **faithful, layout-preserving** port, the item-type mapping, the option-value choices, every
   block you plan to merge or drop and why, and what goes to a human. Once the user agrees, run
   to completion: one final summary, no stop per batch.
4. **Brand first.** Read the target's current styles, then `save_color_schemes`,
   `save_typographies` and `save_button_styles` (style writes replace the whole object; see
   dw-swift-page-blocks). Assign the scheme to the website with `save_areas`
   (`colorSchemeGroupId`, `colorSchemeId`).
5. **Media.** `upload_file_from_url` for each image, fetching the original file, not a resized
   rendition. Keep a map from source URL to the new `/Files/...` path.
6. **Header and footer.** Build a header page and a footer page with `save_pages` and
   `save_paragraphs` (or `copy_page` from a working Swift 2 header and footer), placed under a
   parent page, not at the website root. Link them in the website's `Swift-v2_Master` fields
   `HeaderDesktop`, `HeaderMobile`, `FooterDesktop` and `FooterMobile` with
   `set_item_field_values`. Carry other master settings by meaning (`get_item_type_fields` on
   the website's item type).
7. **Shop pages (when the source is a shop).** Build or `copy_page` the catalog pages: the shop
   page, product list and detail, the `ProductSliderService` and `VariantSelectorService` pages,
   cart and checkout. Then check every setting on the copies for page ids or shop ids that still
   point at the source website, and replace them.
8. **Port pages in batches.** Per page: `save_pages`, then `save_grid_rows` with each row's
   `DefinitionId` and `ColorSchemeId`, then `save_paragraphs` and `set_paragraph_item_fields`
   following the mapping. Keep each real block as its own paragraph in its own column. Write
   internal links as `Default.aspx?ID=<new page id>` and product-group references as the new
   group ids, using your source-to-new id maps. Record each block's outcome in the block list.
9. **Read back every page.** `get_paragraphs_by_page_id` against the block list,
   `inspect_page_render` for what renders, and `validate_page_content` for broken fields. Fix and
   read again until the page matches.
10. **One final summary.** Pages built, each block's outcome, the item-type and option-value
    mappings used, the `5ColumnsFlex` picks, links or ids that could not be resolved, and
    everything left for a human.

## Honesty floor

- "Faithful" is not "identical". Say what was preserved, what was mapped to a different
  component, and what was approximated (option values, types with no same-named twin).
- Account for EVERY block in the block list. Drop only for a reason the user approved. Never
  silently re-flow or drop content.
- A Swift 2 page that reads back with a missing block or an empty field is not done.
- Raw HTML, custom `.cshtml` and modules or apps outside the shop pages go on a side list for a
  human. Never guess or fake them.

## Out of scope

Custom HTML and `.cshtml`, modules and apps beyond the standard shop pages, product and catalog
data (see [dw-swift-migrate-site](../dw-swift-migrate-site) for a catalog import), and in-place
platform upgrades (see [dw-setup-upgrade](../dw-setup-upgrade)). Pixel-identical reproduction is
not the goal; faithful structure, banding and content are.
