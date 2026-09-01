---
name: dw-swift-building
type: flow
group: swift
mcp: required
description: 'Customize an existing Swift 2 Dynamicweb site for a specific business without rebuilding it — preserve the working page shell and update area, navigation, category pages, and item values. Triggers: rebrand or repurpose an existing Swift 2 site, update area/page settings and navigation for a new business, adjust category pages and item values. Non-triggers: installing Swift 2 from scratch -> dw-setup-install; modelling PIM data -> dw-pim-modelling; configuring commerce/catalog data -> dw-commerce-catalog.'
---

# Dynamicweb Swift 2 Site Builder

## MCP preflight

This skill drives the Dynamicweb MCP server — its steps are tool calls. Before starting,
verify the Dynamicweb MCP tools are available. If they are not, stop and tell the user the
MCP connection is missing; do not substitute direct SQL, file edits, or guessed HTTP calls
for the tool calls this skill names.

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

## Core Rules
- Never create a new area in this flow.
- Always inspect the area and page tree before patching.
- Always read page and area item values before writing them, when those tools are available.
- Only create a page when a required business page is genuinely missing.
- Only deactivate a demo category page after confirming it is demo-only.
- Never hardcode environment-specific URL prefixes in custom HTML (for example `/en-us/...` or `/vinhuset/...`).
- Always derive the canonical shop-root path at runtime and build all custom links from that path.

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

