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
