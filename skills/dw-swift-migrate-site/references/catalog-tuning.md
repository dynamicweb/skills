# Catalog tuning: facets, sorting, variants, product pages

Step 6 of [dw-swift-migrate-site](../SKILL.md). A first import usually works but does not yet
feel like a good shop; these are the changes that matter most. The product index, its queries and
facet groups can be used by several websites on the solution. Reuse what fits the new website as
it is. When it needs something different, never change what another website uses without asking
(see step 3); make its own instead: a facet group of its own on the shared query (with query
parameters named so they can't clash with other websites'), or a query of its own when the
products, conditions or sorting differ. Propose which at the website-proposal checkpoint. Rebuild
the product index after each change, and check the result on the frontend. A facetable index
field becomes an automatic filter on every product list that uses the index, next to the facet
group's own, so leave `facetable` off for a field that is in a facet group.

## Facets

- **Facet on non-analyzed fields.** Category fields are often indexed as analyzed text, so a
  facet on them splits and lower-cases values (`Li-Ion` becomes `li` and `ion`). Add an index
  field per faceted value that is indexed and not analyzed, and point both the facet and
  the query condition that filters by it at the new field. Use the same analyzer setting for
  indexing and querying, or the filter returns nothing.
- **Show a facet only where it applies.** Make category-specific facets conditional on the group
  parameter, so the top of the shop shows only facets that make sense across the whole catalog.
- **Clean values belong in the facet field, not the displayed value.** Normalize spelling, units,
  and decimal separators in the facet field; the value shown on the product page stays as scraped.
- **Order numeric facets by value.** Sizes, voltages, and diameters read as strings by default.

## Sorting

Give the product catalog app a default sort that puts core products before accessories, for
example a numeric rank field (core, then consumables, then accessories) followed by name. A sort
the shopper picks still overrides it.

## Variants and product cards

- Show the variant selector on the product page, with add-to-cart disabled until a variant is
  chosen and a clear hint on the button
- Tell shoppers on the product card that more variants exist (for example the number of sizes),
  and keep the card's title, price, and button aligned across a row
- A product the source sells as a single variant of a sized family is genuinely one product;
  make that visible in its name or card rather than inventing variants

## Product pages and descriptions

- Show the specifications on the product page through a field display group
- When the short and long descriptions repeat each other, choose which one each template shows;
  never edit the scraped text to fix it
- Decide whether the product page shows other products, for example related or similar products,
  accessories or spare parts, from what the original site has and what the product data supports.

## Search

Search the frontend for a few product names and numbers and confirm the products are found. A
search that finds nothing usually means the index is stale or the products are in another
language than the index reads.

## Checkpoint

Report the facets per category with sample values, and links to three filtered listings.
