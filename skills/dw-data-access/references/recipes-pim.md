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
- [Asset categories and BOM lines: `AssetCategorySave` and `ProductItemAdd`](#asset-categories-and-bom-lines-assetcategorysave-and-productitemadd)
- [Seeding the `reference_category` parent row](#seeding-the-reference_category-parent-row)
- [Probing completion-rule verbs on the Management API](#probing-completion-rule-verbs-on-the-management-api)
- [Detaching a deleted completion rule from its groups](#detaching-a-deleted-completion-rule-from-its-groups)
- [Seeding standard-field `EcomProductField` rows for per-language editing](#seeding-standard-field-ecomproductfield-rows-for-per-language-editing)
- [Minting a catalogue-group language row: the `EcomGroups` clone](#minting-a-catalogue-group-language-row-the-ecomgroups-clone)
- [Category-field label translations: `ProductCategoryFieldTranslationSave`](#category-field-label-translations-productcategoryfieldtranslationsave)
- [Re-applying per-variant `ProductNumber` suffixes](#re-applying-per-variant-productnumber-suffixes)
- [Reading a Range field value back: `ProductById`](#reading-a-range-field-value-back-productbyid)
- [Creating a Dynamic Workspace: `DynamicStructureSave` then `DynamicStructureLevelSave`](#creating-a-dynamic-workspace-dynamicstructuresave-then-dynamicstructurelevelsave)
- [Collapsing a custom field back into its standard](#collapsing-a-custom-field-back-into-its-standard)
- [Product verb and tool traps measured on a live host](#product-verb-and-tool-traps-measured-on-a-live-host)

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
  No verb or tool writes the table either, so an online build asks the user (the admin-screen edit below).
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

The measured cause is the master-only default on six product fields, and the unlock that makes a
variant write persist is the first row of "Product verb and tool traps measured on a live host" below.

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

## Asset categories and BOM lines: `AssetCategorySave` and `ProductItemAdd`

No MCP tool creates an asset category (`get_product_asset_categories` only reads them) or a BOM line. A
Swift 2 product page whose media paragraphs bind named categories (`Images`, `Manuals`) and whose BOM
paragraph reads the product's items renders those rows empty until both exist, and nothing but the
paragraph settings names the dependency.

**Surface: Management API.**

- **`AssetCategorySave`** (at `/admin/api/AssetCategorySave`) creates an `EcomDetailsGroup` row. Only
  `Name` is required, so a minimal body creates a live category: never send one to learn the shape. Read
  an existing category's model through `AssetCategoryAll`, send the full model with the name, the file-type
  filter and the default upload folder set, and assert that `AssetCategoryAll` `totalCount` rose by exactly
  one. `AssetCategoryDelete` with `{"GroupId":<id>}` removes a category. Names in further languages are the
  `EcomDetailsGroupTranslation` recipe above.
- **`ProductItemAdd`** (at `/admin/api/ProductItemAdd`) adds one BOM line through the domain service and
  needs no restart. It accepts exactly one payload shape, and both plausible variations throw rather than
  degrade:

```
{ "ProductId": "<parentProductId>", "Model": { … the BOM line … } }   -> ok
… with ProductOrGroupIds in the payload   -> 500  "Index was outside the bounds of the array"
… with Model omitted                      -> 400  "Command.Model cannot be null"
```

The 500 is the misleading one: an index-out-of-bounds reads as a platform defect, when it is the binder
rejecting an extra key. Set the parent's product type to BOM in the same pass, and verify the lines on the
rendered product page, where a kit's lines are visible, not on the add response.

**Surface: `SQL`, where the Management API is not in play.**

```sql
UPDATE EcomProducts SET ProductType = 2 WHERE ProductId = '<parentProductId>';   -- 2 = bom
-- then one EcomProductItems row per line, in the fixed-component or configurator-slot shape
-- (dw-pim-modelling, structural-model.md section 2.6); ProductItemBomProductId and
-- ProductItemBomVariantId take '' and never NULL.
-- An asset category is one EcomDetailsGroup row (DetailsGroupExtensions, DetailsGroupDefaultUploadFolder)
-- plus one EcomDetailsGroupTranslation row per language.
```

- **Why the higher surfaces do not cover it**: no MCP tool writes either table; use SQL only where the
  Management API verbs above cannot be called.
- **Local installs only**: a hosted install has no SQL surface, and the verbs above are its route.
- **The debt it owes**: a **host restart**. `ProductItem` holds its rows in a lazy in-process dictionary,
  so the BOM tab and the product page show no lines until the bounce, and a new asset category sits
  behind the ecommerce caches the same way.

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

## Seeding the `reference_category` parent row

A completeness rule that is defined and assigned but renders no panel on the product almost always
means the `reference_category` parent row is missing from `EcomProductCategory` (`CategoryType=2`).
`create_category_fields` creates or reuses the reference field inside `reference_category` before it
copies the field into the target category, so fields created through it carry their mirror; no MCP
tool seeds a missing parent row or its translation.

**Surface: `SQL`,** idempotent, run with `sqlcmd` or any SQL client against `<sqlserver>` / `<dwdb>`
(the database named in `GlobalSettings.Database.config`). Pass it as a file (`sqlcmd -i`) rather than
inline through a shell, so no interpolation touches it.

```sql
IF NOT EXISTS (SELECT 1 FROM EcomProductCategory WHERE CategoryId = 'reference_category' AND CategoryType = 2)
  INSERT INTO EcomProductCategory (CategoryId, CategoryProductProperties, CategoryType)
  VALUES ('reference_category', 0, 2);

IF NOT EXISTS (SELECT 1 FROM EcomProductCategoryTranslation
               WHERE CategoryTranslationCategoryId = 'reference_category'
                 AND CategoryTranslationLanguageId = '<defaultLanguageId>')
  INSERT INTO EcomProductCategoryTranslation
    (CategoryTranslationCategoryId, CategoryTranslationLanguageId, CategoryTranslationCategoryName)
  VALUES ('reference_category', '<defaultLanguageId>', 'Reference category');
```

After the parent exists, mirror every concrete-category field row that was not created through
`create_category_fields` into `reference_category` (`FieldCategoryId='reference_category'`), plus its
translation rows.

- **Why the higher surfaces do not cover it**: no MCP tool and no known Management API command writes
  the parent row.
- **Local installs only**: a hosted install has no SQL surface, so an online build asks the user.
- **The debt it owes**: a **host restart** (`CompletionRuleService` and `ProductCategoryService` hold
  their `ServiceCache` rows through raw SQL), then a Full Products index build: MCP
  `wait_for_product_index` with `indexName: "Products.index"`, or the Management API form in
  [`recipes-search.md`](recipes-search.md) "Re-running an index build on the Management API".

## Probing completion-rule verbs on the Management API

In product the rule read is `get_completion_rules`, which has none of the traps below. On the Management
API, a missing required parameter on `ProductCompletenessRulesByProductId` answers **500, not 400**: the
binder leaves `languageId` an empty string and the handler dereferences it, so the `ArgumentException`
escapes unhandled instead of reaching model validation.

**Surface: Management API.**

```
GET /Admin/Api/ProductCompletenessRulesByProductId?ProductId=<id>
  -> 500 {"title":"The value cannot be an empty string. (Parameter 'languageId')","status":500}
Same 500 for &LanguageId=<lang>, &languageId=<lang>, &ProductLanguage=<lang>, &LangId=<lang>.
Only &ProductLanguageId=<lang> works -> 200.
```

Parameter spelling is not shared across the family: `ProductById` binds `Id`,
`ProductCompletenessRulesByProductId` binds `ProductId` + `ProductLanguageId`, and neither accepts the
other's spelling. Triage any verb probe by its failure mode:

| Response | Meaning |
|---|---|
| `"Unknown query: 'X'"` | The verb does not exist |
| `"Unable to load query parameters for query type"` | The verb EXISTS, the parameter names are wrong |
| HTTP 500 `ArgumentException` naming a parameter | The verb exists and that named parameter bound empty: supply it |

Re-probe with the named parameter before reporting a host problem. The dispatcher strips a trailing
`Query`/`Command` from the class name but not a leading `Get`, so `GetLanguagesQuery` is the verb
`GetLanguages`. No cache debt: these are reads.

## Detaching a deleted completion rule from its groups

`CompletionRuleDelete` never clears `EcomGroups.GroupCompletionRules`, so a rule deleted while assigned
leaves its id dangling. The detach verb normally hides that, but every group-scoped verb resolves a group
through its **default-language row**, so a catalogue group with only non-default language rows cannot be
reached. Online, detach first with `assign_completion_rules_to_groups` (it replaces a group's whole
assignment set), then `delete_completion_rules`; no MCP tool is known to reach a language-only group row.

**Surface: Management API** for the detach:

```
POST /Admin/Api/CompletionRuleRemoveFromGroup {"GroupId":"<G>","Id":<ruleId>}
  -> 404 {"status":"notFound","message":"The group with the id <G> does not exist"}
     ... while SELECT GroupId, GroupLanguageId FROM EcomGroups WHERE GroupId='<G>' returns four rows
```

**Surface: `SQL`** for the verification, which must return 0 after any completeness-rule deletion:

```sql
SELECT COUNT(*) FROM EcomGroups
 WHERE ISNULL(GroupCompletionRules,'') <> ''
   AND GroupCompletionRules NOT IN (SELECT CAST(EcomCompletionRuleId AS varchar) FROM EcomCompletionRules);
```

For language-only orphan rows, clear the remaining ids through the sanctioned scheduled-task SQL runner:

```sql
UPDATE EcomGroups SET GroupCompletionRules = '' WHERE GroupCompletionRules = '<deletedRuleId>';
```

- **Why the higher surfaces do not cover it**: the verb answers 404 for a group without a default-language
  row, and the verb's own answer is never proof of the detach.
- **Local installs only** for the census and the runner: on a hosted install ask the user.
- **The debt it owes**: a host restart, or one rule save from the admin UI, to reload `CompletionRuleService`.

## Seeding standard-field `EcomProductField` rows for per-language editing

About 40 standard product fields are hardcoded in the admin editor, and with no `EcomProductField` row
`AllowChangesAcrossLanguages` defaults to `False`, so the side-by-side translation editor renders every
field read-only. The fix is one row per standard field that needs translation (name, descriptions, meta),
never for prices, stock, identifiers, dimensions, timestamps or the manufacturer FK. Do not edit the legacy
`/Globalsettings/Ecom/ProductLanguageControl` XML: it is vestigial once `MigrationToDatabaseDone` is set.

**Surface: `SQL`.**

```sql
-- ProductFieldAutoId is IDENTITY: leave it out of the column list.
-- ProductFieldId continues the existing FIELD<n> sequence (FIELD1-FIELD7 hold the scaffold's dimensions).
INSERT INTO EcomProductField (
  ProductFieldId, ProductFieldName, ProductFieldSystemName, ProductFieldTypeId, ProductFieldTypeName,
  ProductFieldLocked, ProductFieldSort, ProductFieldDoNotRender, ProductFieldIsStandard,
  ProductFieldAllowChangesAcrossLanguages, ProductFieldAllowChangesAcrossVariants,
  ProductFieldRequired, ProductFieldReadOnly,
  ProductFieldShowFieldOnBothMasterAndVariant, ProductFieldUseAsFacet
)
VALUES
  (N'FIELD8',  N'Name',              N'ProductName',             1, N'Text',       1, 0, 0, 1, 1, 1, 0, 0, 0, 0),  -- variants can differ
  (N'FIELD9',  N'Short description', N'ProductShortDescription', 14, N'EditorText', 1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD10', N'Long description',  N'ProductLongDescription',  14, N'EditorText', 1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD11', N'Meta title',        N'ProductMetaTitle',        1, N'Text',       1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD12', N'Meta description',  N'ProductMetaDescription',  2, N'LargeText',  1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD13', N'Meta keywords',     N'ProductMetaKeywords',     2, N'LargeText',  1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD14', N'Meta canonical',    N'ProductMetaCanonical',    1, N'Text',       1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD15', N'Meta URL',          N'ProductMetaUrl',          1, N'Text',       1, 0, 0, 1, 1, 0, 0, 0, 0, 0);
```

- **Why the higher surfaces do not cover it**: no MCP tool is known to create a standard-field row.
  `update_product_fields` sets `allowChangesAcrossLanguages` on a field it resolves by id or system name;
  whether it creates a missing standard-field row has not been measured.
- **Local installs only**: on a hosted install ask the user.
- **The debt it owes**: a **host restart**; the field list is loaded at startup.

## Minting a catalogue-group language row: the `EcomGroups` clone

`ProductCatalogGroupSave` only updates: when no `EcomGroups` row exists for the language it answers
`{"status":"ok"}` and inserts nothing, and `ProductCatalogGroupNew` mints a new group, not a language row.
Online, `save_group_translations` writes the language row. Outside the tools the row is a clone of the
default-language row with `GroupLanguageId` and `GroupName` substituted.

**Surface: `SQL`,** through the sanctioned scheduled-task SQL runner. Build the column list dynamically so
the identity column `GroupAutoId` stays out:

```sql
INSERT INTO EcomGroups (<every column except GroupAutoId>)
SELECT <same columns, GroupLanguageId and GroupName substituted>
  FROM EcomGroups
 WHERE GroupId = @g AND GroupLanguageId = '<defaultLanguageId>';
```

Then flush the group cache on the Management API, or every subsequent read is stale:

```
POST /Admin/Api/CacheInformationRefresh {"CacheTypeName":"Dynamicweb.Ecommerce.Products.GroupService"}
```

- **Why the higher surfaces do not cover it**: the Management API cannot create the row; the MCP tool can,
  so use this only for a bulk clone outside the product.
- **Local installs only**: on a hosted install use `save_group_translations`.
- **The debt it owes**: the `GroupService` flush above; after it `ProductCatalogGroupSave` works on the new row.

## Category-field label translations: `ProductCategoryFieldTranslationSave`

No MCP tool writes `EcomProductCategoryFieldTranslation`: `save_group_translations` and
`set_option_translations` write other tables, and `apply_translation` writes page content only. Inside
the product the label is an admin edit on the category field.

**Surface: Management API.**

```
POST /Admin/Api/ProductCategoryFieldTranslationSave
{ "Model": { "CategoryId": "<cat>", "FieldId": "<field>", "LanguageId": "<lang>", "Name": "<label>" } }
```

`Name` carries the label. Measured 160/160 rows with 0 failures. Shapes rejected on the way: `{Label:…}`,
`{SystemName:…}` and `{Id:…}` all answer `400 "FieldId: The value is required"`, and sending both `Model`
and `model` keys answers 500 "An item with the same key has already been added. Key: model". No cache
debt was observed; verify on the row count.

## Re-applying per-variant `ProductNumber` suffixes

The admin master-product rename and some bulk-update paths push the master's new `ProductNumber` onto
every row sharing the `ProductId`, variants included. No write surface reaches a variant `EcomProducts`
row (see "Writing the per-variant `EcomProducts` row on 10.28.x" above), so the repair is SQL.

**Surface: `SQL`.** Re-applying the suffix is idempotent:

```sql
UPDATE EcomProducts
SET ProductNumber = ProductNumber + '-' + REPLACE(ProductVariantId, 'VO-', '')
WHERE ProductVariantId <> ''
  AND ProductLanguageId = '<defaultLanguageId>'
  AND CHARINDEX('-' + REPLACE(ProductVariantId, 'VO-', ''), ProductNumber) = 0;
```

Adjust the `REPLACE(..., 'VO-', '')` term when option ids do not follow `VO-<code>`; for composite
(dot-joined) variant ids substitute a per-row suffix lookup table. Creating the variant rows themselves is
a copy of the master with `ProductNumber` among the overridden columns, never a copied one:

```sql
INSERT INTO EcomProducts (col1, col2, ...)
SELECT m.col1, m.col2, ...
  FROM @combinations v
 INNER JOIN EcomProducts m ON m.ProductId = v.MasterId AND m.ProductVariantId = '';
```

- **Why the higher surfaces do not cover it**: every documented write surface leaves the variant row untouched.
- **Local installs only**: on a hosted install plan no per-variant SKU beat.
- **The debt it owes**: a product-service cache flush (see [`cache-invalidation.md`](cache-invalidation.md)),
  then a Full Products index build; a downstream connector that caches its imported product list needs its
  own re-sync after the build.

## Reading a Range field value back: `ProductById`

MCP `get_products_by_ids` renders every Range value as the literal string
`"RangeValue { Minimum = , Maximum =  }"` and the product index answers `IsEmpty` for all of them. The
Management API product read is the only reader that returns the typed value the admin editor renders.

**Surface: Management API.**

```
GET /Admin/Api/ProductById?id=<id>&languageId=<defaultLanguageId>
```

Assert there and report populated and empty counts explicitly. Values live in
`EcomProductCategoryFieldValue` under `<fieldId>|RangeType|Minimum` and `<fieldId>|RangeType|Maximum`; a
`ProductSave` round-trip wipes them, so re-inject them before one (SQL, local installs only). Inside the
product there is no read that proves a Range value; the user checks the product edit screen.

## Creating a Dynamic Workspace: `DynamicStructureSave` then `DynamicStructureLevelSave`

No MCP tool creates or reads a Dynamic Workspace; inside the product the user builds it on the Dynamic
Workspaces screen. `DynamicStructureSave` silently drops a `Levels` collection, so the build is two commands.

**Surface: Management API.**

```
1) POST /Admin/Api/DynamicStructureSave  {"QueryData":{}, "model":{"Name":…, "QueryId":…}}
2) per level, POST /Admin/Api/DynamicStructureLevelSave
   {"QueryData":{"StructureId":<guid>,"Type":"DynamicStructureLevelNew"},
    "model":{"StructureId":<guid>,          // REQUIRED inside the model, not only in QueryData
             "SourceType":"DataModelKey"|"ProductField","SourceField":…,
             "SortDirection":"Ascending","Index":<n>,
             "UseRelationOnProductCreate":<bool>,"UseCompleteness":<bool>}}
```

- **`StructureId` only in the query envelope** answers
  `400 {"":["Model validation failed"],"StructureId":["The value is required."]}`.
- **Pass `Index` on every level.** Re-saving with `model.Index=1|2` fixes an order that landed at 0.
- **Never round-trip a level model.** `GET /Admin/Api/DynamicStructureLevelById?Id=<n>&StructureId=<guid>`
  returns `useRelationOnProductCreate:false, useCompleteness:false` whatever is stored, so posting back the
  model you read writes both flags false. Set both booleans explicitly on every save.
- **Read back from the table.** No read query exists for either aggregate, so assert in `SQL` that
  `COUNT(*)` of `DynamicStructureLevels` rows for the structure's `DynamicStructureUniqueId` equals the
  number of levels intended and that `DynamicStructureLevelIndex` runs 1..n with no duplicates.

- **Why the higher surfaces do not cover it**: MCP has no workspace tools, and the Management API has no read.
- **Local installs only** for the SQL read-back: on a hosted install ask the user to confirm the levels in admin.
- **The debt it owes**: none observed for the saves; the SQL is a read.

## Collapsing a custom field back into its standard

Fold each custom duplicate of a standard field back into its standard in this order: backfill, rewire,
delete, drop, clean grants. Never delete first.

**Surface: `SQL`.**

```sql
-- 1) Backfill the standard column from the custom where the standard is empty.
UPDATE EcomProducts SET ProductEAN    = g_ean        WHERE g_ean        IS NOT NULL AND g_ean        <> '' AND (ProductEAN    IS NULL OR ProductEAN    = '');
UPDATE EcomProducts SET ProductWeight = g_weight_kg  WHERE g_weight_kg  > 0 AND (ProductWeight IS NULL OR ProductWeight = 0);
-- ...repeat per duplicated dimension/identifier...

-- 2) Rewire completion-rule references from custom SystemName to standard.
UPDATE EcomCompletionRules
SET EcomCompletionRuleProductFields =
      REPLACE(REPLACE(EcomCompletionRuleProductFields, 'g_weight_kg', 'ProductWeight'), 'g_ean', 'ProductEAN')
WHERE EcomCompletionRuleProductFields LIKE '%g_ean%'
   OR EcomCompletionRuleProductFields LIKE '%g_weight_kg%';

-- 3) Delete the duplicate EcomProductField rows (BOTH exact-name + alias).
DELETE FROM EcomProductField
 WHERE ProductFieldSystemName IN
   ('ProductWeight','ProductHeight','ProductWidth','ProductDepth','ProductVolume',
    'g_ean','g_weight_kg','g_height_cm','g_width_cm','g_length_cm');

-- 4) Drop the custom columns from EcomProducts. Drop their default constraints first
--    (auto-named, vary per install) so the DROP COLUMN does not fail with msg 5074.
DECLARE @def nvarchar(200), @sql nvarchar(500);
DECLARE colcur CURSOR FOR
  SELECT dc.name FROM sys.default_constraints dc
   JOIN sys.columns c ON c.default_object_id = dc.object_id
  WHERE c.object_id = OBJECT_ID('EcomProducts')
    AND c.name IN ('g_ean','g_weight_kg','g_height_cm','g_width_cm','g_length_cm');
OPEN colcur; FETCH NEXT FROM colcur INTO @def;
WHILE @@FETCH_STATUS = 0 BEGIN
  SET @sql = 'ALTER TABLE EcomProducts DROP CONSTRAINT [' + @def + ']';
  EXEC sp_executesql @sql;
  FETCH NEXT FROM colcur INTO @def;
END
CLOSE colcur; DEALLOCATE colcur;

ALTER TABLE EcomProducts DROP COLUMN g_ean;
ALTER TABLE EcomProducts DROP COLUMN g_weight_kg;
-- ...one per dropped column...

-- 5) Clean any UnifiedPermission grants that referenced the now-deleted SystemNames.
DELETE FROM UnifiedPermission
 WHERE PermissionName = 'ProductField'
   AND PermissionKey IN ('g_ean','g_weight_kg','g_height_cm','g_width_cm','g_length_cm');
```

- **Why the higher surfaces do not cover it**: no MCP tool or Management API verb backfills a standard
  `EcomProducts` scalar in bulk or drops a column.
- **Local installs only**: online, rewire the rules with `create_or_update_completeness_rules` and remove
  the duplicate fields with `delete_product_fields`; the backfill and the column drop go to the user.
- **The debt it owes**: flush `ProductFieldService`, `ProductService`, `CompletionRuleService` and
  `PermissionService` (or restart the host), then a Full Products index build.

## Product verb and tool traps measured on a live host

Each row is a call that answers as if it had done what was asked [dw 10.28.10 · mcp 0.6.0-beta]. The rows mix surfaces, so
each names its own, and every "do instead" ends with a read that is not the call's own echo.

| Surface | Call | What it answers | What is true | Do instead |
|---|---|---|---|---|
| Management API, MCP | `ProductSave` with `VariantId`; `patch_products_safe` or `update_products` with `variantId` | success, echoing the requested values | Six product fields are master-only by default (`ProductNumber`, `ProductPrice`, `ProductStock`, `ProductShortDescription`, `ProductMetaTitle`, `ProductMetaDescription`: per-field variant editing off, stored as `EcomProductField.ProductFieldAllowChangesAcrossVariants`, an empty table on a stock host). A master save through any route copies the master value onto every variant row, and a later variant save is put back to the master value. | Unlock first: `POST /Admin/Api/ProductAttributeSettingsSave {"FieldIds":[<the six>],"VariantEditing":true}` (`ProductFieldById` then reads `variantEditing: true`); the variant writes persist after it. Verify on the variant row, MCP `get_products_by_sku` with the new variant number or `ProductById` with `VariantId`, never on the response echo. |
| Management API | `ProductAssetByProductKey` with `ProductVariantId` | the master's asset rows [dw 10.28.10] | Seen on one build only: the parameter was ignored and the variant's own asset rows were not listed [dw 10.28.10]. A later build honours it and lists the variant's own rows (`onMaster: false`) beside the inherited master rows (`onMaster: true`) [dw 10.28.11]. | Read the `onMaster` flag of each row. When only master rows come back for a variant known to carry its own, list them through `ProductAssetByAssetValueAndProductId`; `ProductAssetMetadataSave` with `VariantId` in the model writes them. |
| MCP, Management API | `get_product_category_fields` with no arguments; `ProductCategoriesAll` with the default `categoryType` | `count: 0` / `totalCount: 0` | The zero is correct for the default filter. Product category fields are stored as `PropertyFields` categories (`EcomProductCategory.CategoryType = 1`; the enum is `CategoryFields` 0, `PropertyFields` 1, `SystemFields` 2), and both lists default to `CategoryFields`. | List them with `GET /Admin/Api/ProductCategoriesAll?CategoryType=PropertyFields` [dw 10.28.11]. Check the `get_product_category_fields` schema for a type member before trusting its count. `patch_products_safe` writes `ProductCategory\|<category>\|<field>` values and echoes only global fields: confirm by re-reading the product. |
| Management API | `GET ProductCatalogGroupsSortList` | 500 `Serialization of System.Type is not supported` (`$.Model.SaveCommandType`) | The read verb is broken; `ProductCatalogGroupsSaveSort` works. | Write the order with `ProductCatalogGroupsSaveSort` and read it back on the rendered menu, which is the only reader of the order. |
