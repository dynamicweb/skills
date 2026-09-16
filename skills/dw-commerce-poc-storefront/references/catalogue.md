# Data model, import, and the index

Model from the crawl file, not from an idea of the industry. Every field in the model must be
answerable from `crawl/products.json` for a usable share of the catalogue; a field nothing fills
renders as an empty row on every product page.

## Contents

- [Derive the model from the distribution](#derive-the-model-from-the-distribution)
- [Field type decides whether a facet works](#field-type-decides-whether-a-facet-works)
- [Two facets can collide on one label](#two-facets-can-collide-on-one-label)
- [Groups and the category tree](#groups-and-the-category-tree)
- [Importing products](#importing-products)
- [Reading products back](#reading-products-back)
- [Prices, images and relations](#prices-images-and-relations)
- [Display groups — what the product page shows](#display-groups--what-the-product-page-shows)
- [Teasers and descriptions](#teasers-and-descriptions)
- [The index](#the-index)

## Derive the model from the distribution

Before designing anything, count. For every attribute the crawl found, compute how many
products carry it and how many distinct values it takes. That table decides the model:

- **High fill, few distinct values** → a list field, and almost certainly a facet.
- **High fill, many distinct values** → a numeric or text field for the spec panel; a facet only
  after banding it.
- **Low fill** → keep it as a spec row, keep it off the filter bar, and keep it out of any
  sentence that claims every product has it.
- **One distinct value across the catalogue** → drop it, or fold it into copy.

Group the surviving fields into categories by the panel they will render as — classification,
dimensions, comfort or construction, materials, commercial and logistics, media. Those
categories become the product page's accordions, so name them the way a shopper reads them.

`create_data_model_structure` builds folders, data models, categories and fields in one payload;
[dw-pim-modelling](../../dw-pim-modelling) owns the payload shape and the global-versus-category
storage decision.

## Field type decides whether a facet works

This is the single most expensive mistake in the flow, and it is invisible until a facet is
opened in a demo.

**A text-typed category field is analysed by the search index.** The stored value is lowercased,
split on whitespace and stripped of stopwords before it is indexed, so a field holding
`Made to order` produces the facet options `made` and `order`, and `BLACK Label` produces
`black` and `label`. **A list-typed field is indexed as the stored value, verbatim.**

So: every field that drives a facet is a list field. Text fields are for prose that is read, not
filtered.

Two corollaries:

- **A list value containing a comma splits into several facet terms.** A composition written
  `80 % Polyester / 17,5 % Leather / 2,5 % Polyurethane` becomes three nonsense options. Use
  decimal points in any value that will be faceted, and normalise the source's decimal commas
  during the import, not afterwards.
- **A field's label cannot be renamed in place.** `update_category_fields` writes visibility and
  decimal-presentation settings only. Correcting a label means creating a replacement field,
  migrating the values, repointing the display groups, and deleting the original — so choose
  labels once, at modelling time, with the filter bar in mind.

Mark a field as a facet with `useAsFacet`, then rebuild the index; facet order follows category
order and then field order within the category.

## Two facets can collide on one label

Facet headings come from field labels, so two fields in different categories with the same label
render two identically named dropdowns side by side. It looks like a bug because it reads like
one. Scan the labels of every `useAsFacet` field across all categories for duplicates before the
first index build, and disambiguate by naming the domain in the label rather than the entity —
a textile's tier and a product's tier are both "tier" only until one of them says which.

## Groups and the category tree

Mirror the source's own category names: they become the navigation, the breadcrumb and the page
titles a demo audience reads. Create a group per source category, nested as the source nests
them, and write a real introduction on each — two or three sentences that say what the category
is and which filters are worth using. A category page that opens with a sentence beats one that
opens with a grid.

Assign every product to its category group, and give collection- or programme-style groupings
their own groups too — they make good navigation entries and good facets at once.

## Importing products

Import in batches and verify from a read, not from the echo.

- `create_products` for the initial load; `patch_products_safe` for enrichment, since it writes
  only the fields present in the request and leaves everything else untouched.
- **Batch at most eight products per `patch_products_safe` call.** Larger batches are where
  partial writes hide.
- **Send only the fields you are changing.** A patch that carries a field it did not intend to
  change is how an enrichment pass silently reverts an earlier one.
- **The patch echo is not proof.** It can report a value the write did not persist. Confirm with
  a fresh read of the affected records before reporting a phase complete.

**Several tools return a response that fails output-schema validation on `validFrom` /
`validTo` date-times.** The write applied; only the response failed to serialize. Do not retry
the write on that error — read the record back and continue. Retrying is how a catalogue ends up
with duplicates.

When running enrichment passes in parallel across slices of the catalogue, give each slice a
**disjoint field set**. Two passes writing the same field to the same product will clobber each
other in whichever order they land.

## Reading products back

`get_products_by_sku` resolves numbers to ids but **returns `customFields: []`** on this
surface. Read field values with `get_products_by_ids`, in chunks of roughly twenty.

A large read exceeds the response cap and is written to a file instead; query that file with
`jq` rather than re-issuing a smaller read, and keep the audit files — a before-and-after pair
per pass is what lets you prove an enrichment changed only what it meant to.

## Prices, images and relations

- **Prices** — `save_prices`, in the agreed currency. Set the area's `pricesWithVat` to match
  the decision from the gate.
- **Images** — `import_product_images_from_urls` fetches server-side from the crawl's URL list.
  Then check the primary image of every product as a contact sheet and repoint the ones showing
  a detail crop with `set_product_primary_image`.
- **Relations** — a real relation group plus `save_product_relations` gives a cross-sell block
  that is per-product and excludes the product itself. Derive the edges from the data: same
  family, same material, complementary category. A slider configured on a generic relation type
  will happily recommend the product you are already looking at.

## Display groups — what the product page shows

Field display groups bundle fields into the panels a product page renders. Create one per
category, in reading order, and use a separate short group for the four or five facts that
belong beside the price rather than inside an accordion.

Two behaviours to design around:

- A **file-typed field renders as its raw path**, not as a link. Display groups are therefore the
  wrong way to surface PDFs, drawings or videos; that needs a template change, so record it as a
  limitation rather than shipping a panel of `/Files/...` strings.
- A group whose fields are all empty for a product still renders its heading. Keep
  product-type-specific fields in their own group so a table does not open an empty panel labelled
  for a sofa.

Clear values that read as noise — a spec row saying "Not relevant" is worse than an absent row —
and add an overall-size field for product types whose individual dimensions do not apply.

## The index

Build the index the storefront actually queries, using the repository and index names recorded
at the gate rather than the tools' defaults. Rebuild after: creating or retyping fields, changing
`useAsFacet`, and any bulk value change that a facet or a card reads.

Poll `get_product_index_status` or `wait_for_product_index`, then verify against the rendered
page rather than the tool's own report: fetch the listing page and read the facet headings and
their option values out of the HTML. That check catches the analysed-text problem, the duplicate
label and the comma split in one pass, and it is the only check that proves what a visitor sees.
