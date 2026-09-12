# Out-of-product recipes — PIM

This reference holds the out-of-product recipes for pim (products, product groups, variants, data models, completeness rules, product translation): Management API
commands at `/admin/api/...`, serializer layers, and direct SQL. The in-product skills for this
area are `dynamo: true` and carry no instruction on those surfaces, so they keep a one-line pointer
here instead of the recipe.

Every recipe names its surface in the repo convention: MCP tools `snake_case` in backticks,
Management API commands `PascalCase` in backticks with the route on first use in this file,
serializer operations by command or by layer and mode, and `SQL` labelled as such in a fenced `sql`
block. Every SQL recipe states three things inline — why the higher surfaces do not cover it, that
it is **local installs only**, and the cache flush or host restart it owes.

## Contents

- [Writing a standard `EcomProducts` scalar the MCP model omits](#writing-a-standard-ecomproducts-scalar-the-mcp-model-omits)
- [Asset-category names — `EcomDetailsGroupTranslation` has no verb](#asset-category-names--ecomdetailsgrouptranslation-has-no-verb)
- [Reading translations back off the delivery API](#reading-translations-back-off-the-delivery-api)
- [Verifying a data model's per-category fields and option sets](#verifying-a-data-models-per-category-fields-and-option-sets)
- [Writing the per-variant `EcomProducts` row on 10.28.x](#writing-the-per-variant-ecomproducts-row-on-1028x)

## Writing a standard `EcomProducts` scalar the MCP model omits

A standard product field is a **column on `EcomProducts`**, not an `EcomProductField` row, so the MCP
custom-field path cannot write one: `patch_products_safe` with
`customFields: [{ id: "ProductEAN" }]` fails every row with
`No ProductField or ProductFieldValue based on the given system name`, because that path resolves
through the product-field tables, and `update_products` exposes no property for it either. MCP
`get_standard_fields` lists all ~50 of them, which reads as a list of writable targets and is not.

**Surface: Management API, read-modify-write.**

```
GET  /Admin/Api/ProductById?id=<id>&languageId=<lang>     -> a model that carries the scalar (`ean`)
POST /Admin/Api/ProductSave                               -> the same model, with the scalar set
```

`ProductSave` is a **whole-entity save**, so send back the model you read rather than a fragment, and
verify on the row afterwards: a correct run diffs only `ProductUpdated`. The same shape covers every
other `EcomProducts` scalar the MCP model omits.

Inside the product these scalars are the product edit screen's own fields; there is no tool path.

## Asset-category names — `EcomDetailsGroupTranslation` has no verb

Author or migrate translation rows under the site's **live default language** (the layer with
`LanguageIsDefault = 1`, which MCP `get_languages` reports), because the fallback reads that one
layer and no other. Every chrome object with a verb takes it — `save_unit_translation`,
`save_group_translations`, `set_option_translations`, `save_country_translation` and the rest.

`EcomDetailsGroupTranslation` is the exception: no Management API verb and no MCP tool writes it on
10.28.x.

**Surface: `SQL`.**

```sql
INSERT INTO EcomDetailsGroupTranslation
  (DetailsGroupTranslationDetailsGroupId, DetailsGroupTranslationLanguageId, DetailsGroupTranslationName)
VALUES ('<detailsGroupId>', '<defaultLanguageId>', '<name>');
```

- **Why the higher surfaces do not cover it** — the table has no verb and no tool on 10.28.x.
- **Local installs only** — a hosted install has no SQL surface.
- **The debt it owes** — a **host restart**, to flush the ecommerce caches before the name renders.

Afterwards re-run the empty-string probe on the rendered surface: the row is not proof, the render
is. Inside the product, asset-category names are an admin-screen edit under the product's asset
categories.

## Verifying a data model's per-category fields and option sets

`get_product_category_fields` cannot verify a data model it has just created: it returns every category
field on the solution whatever `categoryId` is passed, carries no id member, renders the field type as a
number in `typeName`, and reports `options: []` on every list field. Twenty-four rows on a six-field
category is the tool, not a collapsed model. The write is correct in both tables — only the read is
wrong — so the proof has to come from the storage.

**Surface: `SQL`.**

```sql
SELECT FieldId, FieldCategoryId, FieldType FROM EcomProductCategoryField ORDER BY FieldCategoryId;
SELECT FieldOptionFieldId, COUNT(*) FROM EcomFieldOption GROUP BY FieldOptionFieldId;
```

The first query answers the per-category assignment; the second answers the option sets, which hang off
the shared `reference_category` field id (`ProductCategory|reference_category|<field>`) rather than off the
concrete category, which is why the tool's `options` array is empty and why a concrete-category lookup
finds nothing.

- **Why the higher surfaces do not cover it** — the only read tool for these rows ignores its
  `categoryId` argument and does not resolve the option set.
- **Local installs only** — a hosted install has no SQL surface; there the create call's own
  `succeeded`/`failed` counts are the write proof and the admin data-model screen is the read.
- **The debt it owes** — none; these are reads.

Never re-send an option set because the tool reported it empty: the options are already there and a
re-send stacks duplicates.

## Writing the per-variant `EcomProducts` row on 10.28.x

On DW 10.28.x no API writes a variant product row. `create_variant_combinations` creates the rows and
inherits nothing from the master; `combine_products_as_variants` produces active rows but copies no scalar
column, substituting the master price and leaving the number empty while deleting the standalone rows that
held the real values; and `patch_products_safe`, `update_products` and `ProductSave` (with `Id` and
`VariantId`) each answer success and leave the row untouched. Per-variant **price** has a working
in-product surface (`save_prices` with `productId` and `variantId`); per-variant number, name, unit,
active and stock do not.

**Surface: `SQL`,** on the rows a combination create has already made:

```sql
UPDATE EcomProducts
SET ProductNumber  = '<master number>-<suffix>',
    ProductActive  = 1,
    ProductDefaultUnitId = '<unitId>',
    ProductStock   = <qty>
WHERE ProductId = '<masterId>' AND ProductVariantId = '<dot-joined option ids>';
```

- **Why the higher surfaces do not cover it** — every documented write surface reports success and writes
  nothing to the variant row on this build; the echo is the request model, not a post-write read.
- **Local installs only** — on a hosted install plan no per-variant SKU or stock beat at all.
- **The debt it owes** — a product-service cache flush (see [`cache-invalidation.md`](cache-invalidation.md))
  and an index rebuild before the storefront reflects it.

`ProductNumber` must be unique across the master and every variant in the family; a collision is silently
dropped by downstream consumers that flatten the family.

## Reading translations back off the delivery API

The delivery API's fallbacks differ **within one response**, so a name that looks right can mean the
row is absent.

| Field on `/dwapi/ecommerce/products/{id}` | What a missing row returns | Consequence |
|---|---|---|
| `assetCategories[].name` | the **SystemName** — the view model is SystemName-derived on this build and never consults `EcomDetailsGroupTranslation` | asking for a language with zero translation rows in any layer still returns a plausible English name, so this endpoint **cannot verify an asset-category translation** |
| `relatedGroups[].name` | the **raw id** (`{"id":"<RELGROUPID>","name":"<RELGROUPID>"}`) | a name equal to the id is a missing-row signal, not a label |

Verify an asset-category translation by reading `EcomDetailsGroupTranslation` directly
(`SQL`, local installs only, no cache debt for a read), or by rendering a template that calls
`DetailsGroup.GetName()`.
