# Catalog tuning: facets, sorting, variants, product pages

Step 6 of [dw-swift-migrate-site](../SKILL.md). A first import usually works but does not yet
feel like a good shop; these are the changes that matter most. The product index and its facets
are shared by every website on the solution, so ask before changing them, rebuild the product
index after each change, and check the result on the frontend.

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
- Add a "more in this category" product row so a page never ends empty

## Search

Search the frontend for a few product names and numbers and confirm the products are found. A
search that finds nothing usually means the index is stale or the products are in another
language than the index reads.

## Checkpoint

Report the facets per category with sample values, and links to three filtered listings.
