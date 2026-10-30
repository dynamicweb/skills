# Catalog: survey, scrape, data model, import

Steps 1 to 4 of [dw-swift-migrate-site](../SKILL.md) when the scope includes products. The
pattern: the source is copied into files once, bulk data moves from those files through the dw
CLI and Data Integration, and every write is proven on the frontend.

## Contents

- [Survey](#survey)
- [Scrape into files](#scrape-into-files)
- [Data model](#data-model)
- [Import order](#import-order)
- [Product ids and numbers](#product-ids-and-numbers)
- [Uploading files](#uploading-files)
- [Data Integration activities](#data-integration-activities)
- [Proving an import](#proving-an-import)

## Survey

Read `robots.txt` and the sitemaps before anything else, and keep the crawl delay it states (one
request per second when it states none). When it disallows paths the migration needs, stop and
ask the user.

Find how listings and product pages load their data. Most shops call a JSON endpoint from the
listing page or embed structured data (`application/ld+json`, a hydration blob) in the product
page; reading those is faster and more accurate than parsing HTML. Note the source platform, its
languages, and whether listed prices include VAT.

When the intake scope is a subset, propose categories that together cover every product shape
the full catalog has: simple products, products with one variant dimension (sizes), products
with several, and products with rich specifications. Report product, variant, and image counts
per proposed category at the checkpoint.

## Scrape into files

Write small, resumable scripts in the working folder (any runtime the agent can run):

- Save raw responses as JSON Lines, one record per line, so a stopped crawl continues and parsing
  can be rerun without crawling again
- Keep a crawl log of the source URL behind every record, so any value traces back to its page
- Download images once and resize them for the web before upload (long edge around 1200px, JPEG)
- Keep names, descriptions, and specifications exactly as the source has them

At the checkpoint, report record counts per file, five sample products, and every field that is
empty in more than 10% of records. Those gaps decide what the data model can promise.

## Data model

Read the solution's existing shops, data models, field types, and standard product fields before
proposing anything, and reuse what fits. Then propose:

- One data model per source product category
- A category field for every source specification, with a field type that matches its values
  (text, number, list), marking the ones that matter for filtering
- Standard product fields (name, number, descriptions, price) for what they are meant for; a
  category field never duplicates one
- Variant groups for the specifications the source uses to pick a variant (size, length, color),
  with one option per distinct value; a specification that varies per variant but never picks
  one stays a category field
- One clean product group tree: merge parallel source categories (the same category listed under
  two audiences, a child named like its parent) and remap products to the merged groups

At the checkpoint, show the proposal and a table mapping every source specification to its field
or variant group, before anything is created. After approval, create the whole structure in one
call where the server offers a data-model-structure tool, and read it back.

## Import order

Create the data models and category fields, then the product groups. Record the group ids the save
returns: they can differ from the ids you asked for, and every later file must use the returned
ones. Then write one CSV per table and import each with its own Data Integration activity:

1. Manufacturers, variant groups, and variant options
2. Products and variants
3. Product-group relations
4. Variant relations and category field values
5. Prices
6. Product images (detail rows pointing at the uploaded files)

Create products and groups in the solution's **default ecommerce language**, even when the
website language differs. Rows in another language are invisible to the index and the
navigation.

## Product ids and numbers

Use the source's item numbers as product numbers, and make sure every product has one. Leave the
product id out of the product import: the Ecom provider then matches an existing product by
number (or by name when there is no number) and otherwise generates a new, unused id. So an import
never overwrites an unrelated product, also on a solution shared with other data.

After the product import, look up the id each product number got and write those ids into the
later files: variant relations, category field values, prices, and images all address products by
id.

## Uploading files

Upload CSV files and images in bulk with the dw CLI (`npm install -g @dynamicweb/cli`):

- **Authenticate with an API key per command**, never with `dw login`: pass `--host <solution>`
  and `--apiKey "$(cat <key file>)"`, reading the key from the file the user named at intake so
  its value never appears in the conversation or a command line. Add `--protocol http` only for a
  local HTTP host. The user creates the key in **Settings > System > Developer > Api Keys**.
- **Always pass `-o` on an upload**: `dw files <local folder> <archive folder> -i -o`. Without it,
  existing files are skipped silently and the command still exits cleanly.
- **Verify by listing the folder** (`dw files <archive folder> -l -f`); the upload's own output is
  not proof.
- Put CSV files for Data Integration under `/Files/Files/Integration`, the folder the file
  providers read from, and images under `/Files/Images/<source site>/`.

## Data Integration activities

One activity per CSV file: the CSV provider as source and the **Ecom provider** as destination
(it creates missing ids, language rows, groups, and manufacturers). For each activity, read both
providers' schemas, map every column, and mark the natural key (`ProductNumber` for products) as
the key column. Without a key column, every run inserts duplicates.

- **An activity stores the source file's columns when it is created.** When a CSV gains a column,
  create a new activity; the old one silently ignores the new column.
- **A run is queued, not finished.** Wait for the activity's status to complete, then read its log.
- **Duplicate keys fail the whole job.** A variant family that lists the same option twice, or a
  product listed twice, rejects every row. Deduplicate on the mapped key columns before upload.
- **Give every variant its own price row.** A variant without one can break price rendering on
  the product list and detail pages.
- **Attach variant groups to master products explicitly** when an import column does not attach
  them, then re-run the variant relations: attaching them rebuilds the combinations.
- **Imports write straight to the database.** Products, groups, variant groups, and prices the
  running solution has already cached can keep showing old values until the application restarts.
  Restarting affects everyone on the solution, so ask the user; do not work around a stale cache
  with extra writes.

## Proving an import

A success response or a Data Integration row count is not proof. For each import:

1. Read the activity log and compare rows affected with the file's row count
2. Rebuild the storefront product index, wait for the build to finish, and confirm the document
   count moved
3. Open the frontend page of a product nobody has viewed yet and check name, number, price,
   variants, specifications, and images. A product already viewed may be served from cache and
   hide a failed import

At the checkpoint, report product, variant, price, and image counts in the solution against the
scraped counts, with links to the checked product pages.
