---
name: dw-swift-building
type: flow
group: swift
mcp: required
dynamo: true
description: 'Customize an existing Swift 2 Dynamicweb site for a specific business without rebuilding it — preserve the working page shell and update area, navigation, category pages, and item values. Triggers: rebrand or repurpose an existing Swift 2 site, update area/page settings and navigation for a new business, adjust category pages and item values. Non-triggers: installing Swift 2 from scratch -> dw-setup-install; modelling PIM data -> dw-pim-modelling; configuring commerce/catalog data -> dw-commerce-catalog.'
---

# Dynamicweb Swift 2 Site Builder

## MCP preflight

This skill drives the Dynamicweb MCP server — its steps are tool calls, and the MCP tool set plus
read/write under `Files/` is the whole surface they may use. Verify the tools are available before
starting. If a step's tool is missing, **stop at that step** and tell the user what is missing and
which admin screen performs it; do not substitute a guessed HTTP call, a file edit outside
`Files/`, or SQL. The Management API, the serializer and direct SQL are out-of-product surfaces,
owned by [`dw-data-access`](../dw-data-access/SKILL.md), and are never a step here.

## Objective
Take an existing Swift 2 site and make it fit a new business while keeping the working site shell intact.

Read the current site first so you understand:
- which pages already exist
- which navigation tags are already correct
- which page and area item values are populated
- which pages are reusable shell versus demo-only business content

## References
- [references/swift2-page-structure.md](references/swift2-page-structure.md)
- [references/branding-presets.md](references/branding-presets.md) when deeper branding is needed
- [references/component-system-and-reskin.md](references/component-system-and-reskin.md) — the deep reference: the component-first gate (map a requirement to a standard `Swift-v2_*` component before customising), paragraph item-field configuration and its symptom table, the empty-`ParagraphTemplate` alphabetical-fallback hijack, the grid-composition and `RenderGrid` caches, template categories and page-state flags (`PageActive` vs `PageHidden`), Style assets under `Files/System/Styles/`, asset organisation, the re-skin doctrine (never edit standard templates; the `custom.css` naming hard rule), and the discipline grep-pack
- [references/grid-rows-and-binding.md](references/grid-rows-and-binding.md) — grid rows: the surfaces that write one, the five donor attributes `GridRowCopy` carries and how to normalise them, the column-binding law (a cell renders exactly one paragraph), the spacing an inert row still pays, a constraint that sits on the grid COLUMN rather than the paragraph, scheme-driven anchor colour, and idempotent row minting
- [references/layout-verification.md](references/layout-verification.md) — the browser-side checks a markup assert cannot make: horizontal-overflow diagnosis (three numbers, offender by right edge, both auth states), the visually-hidden containment rule, hit testing a stretched-link card, and contrast. Load when a page passes every content assert and still looks or behaves wrong
- [references/shipped-template-defects.md](references/shipped-template-defects.md) — measured behaviour of the shipped Swift 2 templates: the ones that do not compile on DW 10.29/.NET 10, the search dropdown that crashes without product images, the order surfaces that never render the payment method, the price a "price-hidden" page still delivers in markup, and the Express Buy feed's row contract

## Core Rules
- Never create a new area in this flow.
- Always inspect the area and page tree before patching.
- Always read page and area item values before writing them, when those tools are available.
- Only create a page when a required business page is genuinely missing.
- Only deactivate a demo category page after confirming it is demo-only.
- Never hardcode environment-specific URL prefixes in custom HTML (for example `/en-us/...`).
- Always derive the canonical shop-root path at runtime and build all custom links from that path.
- **Measure the storefront prefix once per host; never derive it from a field.** The area's url name
  is not the addressable segment — on a single-area host it is commonly decorative, and the live
  prefix is the **area culture** rendered as a path segment (`en-US` → `/en-us/`). A URL composed
  from the url name 404s, which reads like a failed publish and sends the agent debugging the write
  path instead of the address. So fetch one page that certainly exists under each candidate prefix,
  keep the one that answers 200, and let every later verify step and every documented URL take the
  prefix from that measurement. (Area resolution on a shared host is by domain, which is why the url
  name mints no prefix there — `dw-content-modelling`, `language-layers.md`.)

## Key Tools
- Site structure: `get_areas`, `get_pages_by_area_id`, `get_pages_by_parent_id`, `get_navigation_structure`
- Updates: `save_areas`, `save_pages`, `reorder_pages`
- Item values: `get_page_item_field_values`, `set_page_item_fields`, `get_item_field_values`, `set_item_field_values`
- Supporting tools: `import_product_images_from_urls`, `fetch_frontend_page_html`

## Workflow

### 1. Map the Existing Site
Inspect:
- the active Swift 2 area
- the full page tree
- the public navigation tree when available
- the homepage and shop root item values when available

Create a concise baseline note covering:
- area name and domain
- key page IDs and navigation tags
- populated item values
- demo placeholder pages
- current SEO patterns

Also capture URL portability context:
- resolve the shop page ID by finding the page with navigation tag `shop` in the `get_navigation_structure` / `get_pages_by_area_id` output
- call `fetch_frontend_page_html` on `/Default.aspx?ID={ShopPageId}`
- parse the redirect target as the canonical shop root path (for example `/vinshop` or `/vinhuset/vinshop`)
- use that canonical root for every custom CTA/category link in this flow

### 2. Fix Navigation Tags
Ensure the core pages keep the expected tags:
- `homepage`
- `shop`
- `cart`
- `checkout`
- `orderconfirmation`
- `myaccount`
- `login`
- `register`

Patch missing or incorrect tags before deeper changes.

### 3. Update the Area
Patch the existing area with:
- business name
- domain if supplied
- linked shop
- language
- currency
- country

**Bind only what `save_areas` exposes.** The tool has no frontpage member of any name, so an instruction
to bind the site-root page id cannot be followed from this surface and does not need to be: the frontpage
resolves from page sort order while the area's redirect-first-page flag is set, which is the shipped
state. Read the area back with `get_area_by_id` after the patch and confirm each bound value echoes;
a value that does not appear in that echo was not accepted. The per-environment `Area` binding columns
that no tool writes are named, with their restart debt, in
[`dw-data-access/references/cache-invalidation.md`](../dw-data-access/references/cache-invalidation.md).

### 4. Update Core Page Metadata
Patch the main pages so the site is clearly branded for the new business:
- homepage
- shop root
- cart
- checkout
- my account
- login and register when present

### 5. Reuse or Create Category Pages
For each product type:
1. check whether a suitable category page already exists under the shop page
2. reuse and patch it if it is structurally useful
3. create it only if nothing suitable exists

For demo category pages that do not fit the new business:
- inspect their name, SEO, and item values first
- decide whether to repurpose or deactivate them

### 6. Apply Deeper Branding
When item-value tools are available:
1. read current homepage item values
2. read current area item values
3. replace demo hero text, logos, imagery, and theme fields where appropriate
4. patch category-page item values if those pages support them

If item values are not available, fall back to metadata updates and report the limitation.

### 7. Verify the Site Structure
Verify that:
- the homepage renders
- the shop root renders
- the nav structure still makes sense
- shell pages remain active
- demo-only pages intended for removal are deactivated
- every custom link patched in this run resolves with `200` via `fetch_frontend_page_html`

## Output Summary
Report:
- what demo structure was found
- which pages were reused
- which pages were created
- which demo-only pages were deactivated
- which item values were preserved or replaced
- any branding limits caused by missing item types

## Error Handling
- If no Swift 2 area exists, stop and hand back to the installer flow.
- If a key shell page is missing, create it only when necessary and keep the standard navigation tag.
- If item values cannot be read, do not overwrite blindly.

