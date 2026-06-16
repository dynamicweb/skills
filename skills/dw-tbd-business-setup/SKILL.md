---
name: dw-tbd-business-setup
description: Full-stack Dynamicweb 10 plus Swift 2 business configurator that turns an already-installed Swift 2 site into a specific business -- inspects the demo install, preserves the Swift 2 shell, removes demo business data as needed, and configures content, catalog, PIM, and commerce. Triggers: MCP bootstrap is already complete and the user wants the install configured for a named business, replace demo data with real business data, set up catalog/PIM/commerce on an existing site. Non-triggers: no install yet or starting from a plain-language brief -> dynamicweb-business-solution-agent; installing Swift 2 -> dynamicweb-solution-installer; only site shell or branding changes -> dynamicweb-swift2-site-builder.
---

# Dynamicweb Business Setup Agent

## Objective
Turn a plain-language business description into a configured Dynamicweb solution built on top of the
existing Swift 2 installation.

Use the Swift 2 demo in two ways:
- as a baseline example of how the site is wired together
- as sample business data that should be replaced when the user wants a brand-new business

Inspect first. Delete second. Rebuild third.

## Delegates
- `dynamicweb-swift2-site-builder` for area, page, and branding work
- `dynamicweb-pim-solution-assistant` for data-model structure
- `dynamicweb-product-query-creator` for saved editorial queries

## Core Rules
- Never create a new area for this flow.
- Never create a new shop for this flow.
- Never delete demo business data before capturing the baseline.
- Preserve the Swift 2 shell: area, shop, key pages, navigation tags, checkout flow, and account flow.
- Use `PatchProductsSafe` for enrichment work.
- Save IDs as you go.
- Do not hardcode environment-specific URL prefixes in custom HTML content.
- Require canonical shop-root path detection before patching any custom links.

## Key Tools
- Discovery: `GetAreas`, `GetShops`, `GetPagesByArea`, `GetGroups`, `GetProducts`
- Site branding: `PatchArea`, `PatchPage`, `GetPageItemValues`, `PatchPageItemValues`, `GetAreaItemValues`, `PatchAreaItemValues`
- Catalog page wiring: `GetPageItemValues`, `PatchPageItemValues` â€” use to update the `IndexQuery` field on `eCom_ProductCatalog` pages after creating the new saved query
- Catalog: `SaveGroups`, `CreateProducts`, `AssignProductsToGroup`
- Commerce: `GetPayments`, `GetShippings`, `GetOrderFlows`, `SaveUnits`, `SaveManufacturers`, `SavePrices`
- Verification: `GetFrontendHealth`, `FetchFrontendPageHtml`, `VerifyProductVisibility`
- Link portability discovery: `GetPageByNavigationTag` and `FetchFrontendPageHtml` (`/Default.aspx?ID={shopPageId}`)

## Workflow

### 0. Verify Swift 2
Call `GetAreas`.

If a Swift 2 area exists, continue.
If not, delegate to `dynamicweb-solution-installer`.

### 1. Parse the Business Request
Extract:
- business name
- business type
- industry
- product types
- primary language
- primary currency
- primary market
- optional domain
- optional tagline

If the request is missing key setup details, ask one concise follow-up.

### 2. Capture the Demo Baseline
Inspect the current solution before changing anything.

Call in parallel where possible:
- `GetAreas`
- `GetShops`
- `GetLanguages`
- `GetCurrencies`
- `GetCountries`
- `GetPagesByArea`
- `GetGroups`
- `GetProducts`
- `GetPayments`
- `GetShippings`
- `GetOrderFlows`
- `GetDashboards`

Also inspect when available:
- `GetAreaItemValues`
- `GetPageItemValues` for the homepage and shop root
- `GetNavigationStructure`

Create a short baseline note that captures:
- area and shop IDs
- key page IDs and navigation tags
- category tree shape
- sample item values or theme settings
- payment, shipping, and order-flow setup
- dashboard presence

### 3. Remove Demo Business Data When Needed
Only do this after the baseline note exists.

When replacing the demo business:
1. remove demo products
2. remove demo prices tied to them
3. remove demo manufacturers if they are no longer useful
4. remove demo assortments if they belong only to the old catalog
5. remove or deactivate demo groups that will not be reused
6. deactivate demo-only category pages that should not remain in the new business

Do not delete the area, shop, or core Swift 2 page shell.

### 4. Create the Foundation
Reuse what already exists where sensible, then add what is missing:
- languages via `SaveLanguages`
- currencies via `SaveCurrencies`
- countries via `SaveCountries`

### 5. Update the Existing Shop
Call `SaveShops` with the existing shop ID and update:
- name
- image folder
- image pattern fields
- image search settings

### 6. Update the Existing Website
Delegate to `dynamicweb-swift2-site-builder`.

Pass the business context plus:
- the requirement to inspect the current structure before patching
- the requirement to preserve the shell and only deactivate demo-only pages
- the requirement to detect canonical shop-root path and avoid hardcoded URL prefixes

### 7. Build the Product Group Structure
Inspect `GetGroups` again after cleanup.

If a demo group is structurally useful, rename and reuse it.
If it is business-specific noise, remove it first.

Then create or repurpose top-level groups and child groups for each product type.

### 8. Create the PIM Structure
Delegate to `dynamicweb-pim-solution-assistant` with:
- business description
- product types
- language ID
- any baseline insights that affect the structure

### 9. Create Sample Products
Before creating anything, confirm demo products are gone if the site is meant to be brand-new.

Create representative sample products and assign them to the correct groups.

### 10. Add Images
Prefer free-to-use product imagery.

Use `DownloadRemoteImages` and `ImportProductImagesFromUrls` when available, or place files by the
shop image pattern convention.

### 11. Configure Commerce
Configure or adapt:
- units
- manufacturers
- prices
- payment methods
- shipping methods
- order flow

### 12. Index and Verify
Build the product index, then verify:
- the site responds
- the homepage reflects the new business
- products are indexed
- shop and category pages render
- custom CTA/category links in patched paragraphs resolve to `200` in the current environment

If products are not visible on a shop/catalog page despite being indexed, check whether the page is
still running the old demo IndexQuery before reindexing. The ViewModel `eCom_ProductCatalog` module
is query-driven: it reads the saved IndexQuery from page/module settings and ignores the current
group/shop structure until that query is updated.

### 13. Create Queries and Dashboard
Use `dynamicweb-product-query-creator` to create a saved product query scoped to the new catalog.

Then create the business dashboard and attach widgets.

### 14. Wire Catalog Pages to the New Query
**Critical.** After creating the editorial query, update the storefront catalog pages to use it.

The `eCom_ProductCatalog` module reads a saved `IndexQuery` from page/module settings. It does **not**
automatically derive scope from the shop or group tree. Until this is patched, the storefront will
continue to run the old demo query with old facets and old product scope.

Steps:
1. Identify the shop catalog pages (the "our products" or equivalent root shop page).
2. Call `GetPageItemValues` to read the current module settings for each catalog page.
3. Find the `IndexQuery` field (or equivalent saved-query reference field).
4. Call `PatchPageItemValues` to set it to the ID of the newly created query.
5. Verify with `FetchFrontendPageHtml` or `VerifyProductVisibility` that the new products appear.

## Output Summary
Report:
- what was learned from the demo baseline
- whether demo data was removed
- what shell pieces were preserved
- what content, catalog, PIM, and commerce setup was created
- any residual gaps or manual follow-up

## Error Handling
- If baseline capture fails, do not perform destructive cleanup.
- If cleanup partially fails, report exactly what remains.
- Never silently skip preservation or cleanup steps.

