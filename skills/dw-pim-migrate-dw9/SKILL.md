---
name: dw-pim-migrate-dw9
type: flow
group: pim
mcp: required
dynamo: true
description: 'Migrate DW9 product structure and catalog data into DW10 PIM. Triggers: DW9 product export, map groups to Data Models, 0 warehouse shops or memberships. Non-triggers: Data Model design -> dw-pim-modelling; platform upgrade -> dw-setup-upgrade.'
---

# Migrate DW9 Products into DW10 PIM

## Tool availability: call `tools/list` before planning

The DW9 migration tools are `migrate_dw9_export`, `run_dw9_product_import`,
`get_dw9_product_import_status` and `assign_dw9_products_to_data_models`. They are restricted: an MCP configuration gets them only once
it has been granted them, and they are off by default. Without the grant the names are absent
from `tools/list` and a call answers `Access denied ... Required permission: Read. Allowed
permission: none` [mcp 0.6.0-beta]. That is a grant on the solution, not a property of the
client: any client gets the family when the configuration it connects with carries it.

So **call `tools/list` first and read the answer**:

- The DW9 tools are present: each phase may use them as described under **With the DW9 tools**.
- They are absent: run every phase on the **standard-tools route** described under each phase.
  Tell the user which route is in use. If they would rather use the DW9 tools, the fix is to
  grant them to the MCP configuration this session connects with, then call `tools/list` again.

**The standard-tools route is untested against a real DW9 export.** It was run by importing
from a DW10 site. So on the first real export, check each phase against counts taken from the
export before starting the next phase, and report every gap.

## MCP preflight

This skill drives the Dynamicweb MCP server — its steps are tool calls, and the MCP tool set plus
read/write under `Files/` is the whole surface they may use. Verify the tools are available before
starting. The DW9 family has a standard-tools route, above. For any other missing tool, **stop at
that step** and tell the user what is missing and which admin screen performs it; do not
substitute a guessed HTTP call, a file edit outside `Files/`, or SQL. The Management API, the
serializer and direct SQL are out-of-product surfaces, owned by
[`dw-data-access`](../dw-data-access/SKILL.md), and are never a step here.

The migration runs in a fixed order — **structure → product data → assignment → content
references → verify** — and each phase depends on the one before it: never start the product
import before the structure phase has run, and never assign before the import has succeeded.

## The two exports (not interchangeable)

Both are DW9 Data Integration exports, and both must sit at a path the **DW10 server** can
read — an XML `<tables>` file or a folder of per-table CSVs. On the standard-tools route, put
them under `Files/` with `upload_file`.

- **Structure export** — made in DW9 admin: Settings → Integration → Data integration → New
  activity, **Source = "Dynamicweb Provider"** (reads the DW9 DB directly), **Destination =
  "XML Provider"**. Map: `EcomShops`, `EcomGroups`, `EcomGroupRelations` +
  `EcomShopGroupRelation` (required — the raw `EcomGroups` table carries no tree),
  `EcomLanguages`, `EcomFieldType`, `EcomProductField` + `EcomProductFieldTranslation`,
  `EcomProductCategory`, `EcomProductCategoryField` + `EcomProductCategoryFieldTranslation`,
  `EcomFieldOption` + `EcomFieldOptionTranslation`, plus `EcomCompletionRules` if the solution
  uses them. It contains **no products**.
- **Product export** — the DW9 **Ecom Provider** catalog export, usually the much larger
  file: `EcomProducts`, `EcomGroupProductRelation`, `EcomProductCategoryFieldValue`,
  `EcomVariantGroups`, `EcomVariantsOptions`, `EcomVariantOptionsProductRelation` (+
  `EcomPrices`, `EcomManufacturers` if wanted). It contains **no shops**.

**A tool fed the wrong shape reports an honest zero, not an error.** "0 warehouse shops" or "0
memberships" means the wrong file was used, not missing data — never tell the user their data
is absent until the right export has actually been tried.

Before Phase 1 on either route, count from the exports: shops, groups per shop, product fields,
categories and category fields, products, variants, prices, group memberships. These counts are
what every phase is checked against.

## Run state

Keep a run state the user can see: the route in use, the source counts, each phase's result,
and the **old→new group id map** (DW9 group id → DW10 group id). On the DW9-tools route the map
lives in the database. On the standard-tools route you build it yourself in Phase 1 and record
it here, because Phases 3 and 4 read from it.

## Phase 1 — Structure

**With the DW9 tools: `migrate_dw9_export`.** Run in **plan** mode first — it writes nothing.
Pass the structure export as `DefinitionsPath` and, when known, the product export as
`ProductExportPath`: the plan then preflights the TARGET solution and returns `TargetPreflight`
evidence — a same-named shop (a re-run), existing groups already carrying the incoming DW9 ids
as their `Number` (an earlier migration), and sampled product-id overlap (products the import
would overwrite).

Present the counts (warehouse shops, folders, data models, categories, reference fields,
product fields), the **target preflight verbatim**, and every warning — especially custom DW9
field types that fell back to Text. Overlap findings are the headline; a clean preflight means
the migration is purely additive on this solution, fresh or not. Only after the user agrees,
run the same tool in **apply** mode.

- One DW10 shop is created per DW9 warehouse shop; every DW9 group becomes a nested data
  model, with fresh DW10 ids — the structure itself is collision-free.
- Each created group carries its DW9 id as its `Number` — that is how Phase 3 rebuilds the
  DW9→DW10 mapping straight from the database.
- **Not idempotent on shops**: a second apply on the same target duplicates the tree under a
  new same-named shop. The preflight's shop-name finding is the re-run detector — delete the
  earlier shop before applying again.

**Standard-tools route.** Do the plan step yourself. Read the target with `get_shops` and look
for a same-named shop and for groups whose `Number` already holds an incoming DW9 group id. Read
a sample of export product ids with `get_products_by_ids` to find overlap. Present the plan and
these findings, and build only after the user agrees.

- Build the tree with `create_data_model_structure`, or step by step with `create_shops`,
  `create_data_models`, `create_categories`, `create_category_fields`, `create_product_fields`
  and `create_or_update_completeness_rules`. Read `get_field_types` and `get_standard_fields`
  first, and map each DW9 field type to a DW10 one; report every type that falls back to Text.
- `create_data_model_structure` creates a PIM data-structure shop, not a storefront shop. A
  storefront shop is a separate `save_shops`.
- Give each new group its DW9 group id as its `Number`. Record each DW9 id → new DW10 id pair
  in the run state as you go.
- Read the tree back with `get_shops` and compare shop, group and field counts with the export.

## Phase 2 — Product data

**With the DW9 tools: `run_dw9_product_import`.** Call it with the **product** export. It
builds and queues the Data Integration activity itself — never hand-build the import in the
admin. The import is insert+update only, and structure-owned tables (shops, the group tree,
relations, product↔group memberships, languages) are excluded automatically. The activity runs
in the background: poll `get_dw9_product_import_status` with the activity name until it reports
`succeeded`.

**Standard-tools route.** Upload the export's CSV files with `upload_file`, or use the export's
XML with the XML Provider as source. Create a Data Integration activity with
`create_integration_activity` that writes products, variants and prices; leave out shops, the
group tree and languages, which Phase 1 owns. Run it with `run_integration_activity`, follow it
with `get_integration_activity_status`, and read `get_integration_activity_logs` when it ends.

- **Decimals.** Set either the source's decimal separator or the activity culture to match the
  file, never both. After the first run, read one decimal value back (a price) before importing
  the rest.
- Reading the status after a finished Ecom run clears the product caches, so prices, variants
  and group memberships read back straight away.
- Compare product, variant and price counts with the export.

On either route: if the run fails, stop and show the user the Data Integration log. Do not
guess at the cause, and do not start Phase 3 against a half-finished import. When the import is
done, run one full `build_product_index`.

## Phase 3 — Assignment: products to data models

The import deliberately does **not** write product↔data-model memberships; this phase does,
from the same **product** export.

**With the DW9 tools: `assign_dw9_products_to_data_models`.** Run **plan** mode first and
review with the user:

- the membership counts,
- `UnmappedGroupIds` — DW9 groups outside the migrated warehouses,
- `FolderTargetGroupIds` — DW9 branch groups; folders cannot hold products, so those products
  attach via their leaf groups instead. Expected, not a fault.

Then **apply** to write the relations ("Assigned products").

**Standard-tools route.** Read `EcomGroupProductRelation` from the export and translate each
DW9 group id through the group-id map. Report the same three findings: membership counts, DW9
groups not in the map, and branch groups whose products go to a leaf group. After the user
agrees, write with `assign_data_model_to_products` in batches scoped to one data model each.
Read a few products back with `get_groups_for_product` and compare the membership count with
the export.

## Phase 4 — Content references to groups

Pages and paragraphs can hold DW9 group ids in item fields (a product list, a group link).
Those ids now point at nothing.

Find the item fields that hold group ids, read their values with
`get_item_field_values`, and rewrite each DW9 group id through the map with
`set_item_field_values` or `set_paragraph_item_fields`. Show the user the list of changes
before writing, and read a sample back after.

## Phase 5 — Verify

- Read the shop tree back with `get_shops` — intact and nested as expected.
- Open one migrated data model in PIM: the imported products sit in "Assigned products", and
  a spot-checked product carries its category field values.
- Make sure the full product index build from Phase 2 ran after the last write; run it again if
  later phases changed products.
- Report any gap against the source counts, including the field types that fell back to Text
  in the structure phase.

## Caveats — state these plainly

- Every path must be readable by the **DW10 server**, not just the user's PC.
- Structure before data: the product import and the assignment both depend on the data models
  carrying their DW9 group ids from Phase 1.
- Any target works when the preflight is clean — "fresh solution" is not a requirement, it is
  what a clean preflight proves. When the preflight reports product-id overlap, those products
  get overwritten by the import; surface that to the user and let them decide, never decide it
  for them.
- The standard-tools route has not yet run on a real DW9 export. Check every phase against the
  export counts on the first run.
- Images are **not** migrated.

## Out of scope

CMS content/page migration (a separate, unrelated effort; Phase 4 only rewrites group ids in
existing content), single-product creation or Data Model design (see
[dw-pim-modelling](../dw-pim-modelling)), and an in-place DW9→DW10 platform version upgrade (a
hosting concern, not a data migration — see [dw-setup-upgrade](../dw-setup-upgrade)).
