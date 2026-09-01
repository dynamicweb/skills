---
name: dw-pim-migrate-dw9
type: flow
group: pim
mcp: required
description: 'Migrate a Dynamicweb 9 (DW9) solution''s product structure and catalog data into a Dynamicweb 10 PIM with the migrate_dw9_export, run_dw9_product_import, and assign_dw9_products_to_data_models tools. Triggers: upgrade or migrate a DW9 warehouse/catalog to DW10, import a DW9 product export, map DW9 groups onto DW10 Data Models, "0 warehouse shops"/"0 memberships" after a DW9 import. Non-triggers: migrating DW9 CMS content/pages (a separate, unrelated effort); single-product creation or Data Model design -> dw-pim-modelling; an in-place DW9->DW10 platform version upgrade -> dw-setup-upgrade.'
---

# Migrate DW9 Products into DW10 PIM

## MCP preflight

This skill drives the Dynamicweb MCP server — its steps are tool calls. Before starting,
verify the Dynamicweb MCP tools are available. If they are not, stop and tell the user the
MCP connection is missing; do not substitute direct SQL, file edits, or guessed HTTP calls
for the tool calls this skill names.

The migration runs in a fixed order — **structure → product data → assignment → verify** — and
each phase depends on the one before it: never start the product import before the structure
phase has run, and never assign before the import has succeeded.

## The two exports (not interchangeable)

Both are DW9 Data Integration exports, and both must sit at a path the **DW10 server** can
read — an XML `<tables>` file or a folder of per-table CSVs, never a browser upload.

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

## Phase 1 — Structure: `migrate_dw9_export`

Run in **plan** mode first — it writes nothing. Pass the structure export as
`DefinitionsPath` and, when known, the product export as `ProductExportPath`: the plan then
preflights the TARGET solution and returns `TargetPreflight` evidence — a same-named shop (a
re-run), existing groups already carrying the incoming DW9 ids as their `Number` (an earlier
migration), and sampled product-id overlap (products the import would overwrite).

Present the counts (warehouse shops, folders, data models, categories, reference fields,
product fields), the **target preflight verbatim**, and every warning — especially custom DW9
field types that fell back to Text. Overlap findings are the headline; a clean preflight means
the migration is purely additive on this solution, fresh or not. Only after the user agrees,
run the same tool in **apply** mode.

- One DW10 shop is created per DW9 warehouse shop; every DW9 group becomes a nested data
  model, with fresh DW10 ids — the structure itself is collision-free.
- Each created group carries its DW9 id as its `Number` — that is how Phase 3 rebuilds the
  DW9→DW10 mapping straight from the database, so nothing has to be carried between phases by
  hand.
- **Not idempotent on shops**: a second apply on the same target duplicates the tree under a
  new same-named shop. The preflight's shop-name finding is the re-run detector — delete the
  earlier shop before applying again.

## Phase 2 — Product data: `run_dw9_product_import`

Call `run_dw9_product_import` with the **product** export. It builds and queues the Data
Integration activity itself — never hand-build the import in the admin. The import is
insert+update only, and structure-owned tables (shops, the group tree, relations,
product↔group memberships, languages) are excluded automatically.

The activity runs in the background: poll `get_dw9_product_import_status` with the activity
name until it reports `succeeded`. If it reports `failed`, stop and point the user at the
Data Integration log — do not guess at the cause, and do not start Phase 3 against a
half-finished import.

## Phase 3 — Assignment: `assign_dw9_products_to_data_models`

The import deliberately does **not** write product↔data-model memberships; this tool does,
from the same **product** export. Run **plan** mode first and review with the user:

- the membership counts,
- `UnmappedGroupIds` — DW9 groups outside the migrated warehouses,
- `FolderTargetGroupIds` — DW9 branch groups; folders cannot hold products, so those products
  attach via their leaf groups instead. Expected, not a fault.

Then **apply** to write the relations ("Assigned products").

## Phase 4 — Verify

- Read the shop tree back with `get_shops` — intact and nested as expected.
- Open one migrated data model in PIM: the imported products sit in "Assigned products", and
  a spot-checked product carries its category field values.
- Rebuild the product index.
- Report any gap against the source counts, including the field types that fell back to Text
  in the plan step.

## Caveats — state these plainly

- Every path must be readable by the **DW10 server**, not just the user's PC.
- Structure before data: the product import and the assignment both depend on the data models
  carrying their DW9 group ids from Phase 1.
- Any target works when the plan's preflight is clean — "fresh solution" is not a requirement,
  it is what a clean preflight proves. When the preflight reports product-id overlap, those
  products get overwritten by the import; surface that to the user and let them decide, never
  decide it for them.
- Images are **not** migrated.

## Out of scope

CMS content/page migration (a separate, unrelated effort), single-product creation or Data
Model design (see [dw-pim-modelling](../dw-pim-modelling)), and an in-place DW9→DW10 platform
version upgrade (a hosting concern, not a data migration — see
[dw-setup-upgrade](../dw-setup-upgrade)).
