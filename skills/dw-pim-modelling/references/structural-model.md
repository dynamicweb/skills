# The structural mental model — shops, groups, variants, BOM, fields, assets, workspaces

Deep field-validated knowledge for Dynamicweb 10 PIM structural modelling. Getting any of these wrong causes rework.

## Contents

- [2.1 Shop types — one enum controls everything](#21-shop-types--one-enum-controls-everything)
- [2.2 Group types — data models vs catalog groups](#22-group-types--data-models-vs-catalog-groups)
- [2.5 Variants — 3 tables, composite IDs](#25-variants--3-tables-composite-ids)
- [2.5a Single-axis variants — leaner shape + the MCP/SQL surface split](#25a-single-axis-variants--leaner-shape--the-mcpsql-surface-split-validated-dw-1025x)
- [2.6 Bundles (BOM) — two concerns](#26-bundles-bom--two-concerns)
- [2.8 Product Categories + Fields (data model internals)](#28-product-categories--fields-data-model-internals)
- [Range category fields are half-implemented: do not model a demo attribute as one](#range-category-fields-ecomfieldtype-25-are-half-implemented-do-not-model-a-demo-attribute-as-one)
- [2.10 Assets](#210-assets)
- [2.11 Stock units — a per-location attribute needs a per-location home](#211-stock-units--a-per-location-attribute-needs-a-per-location-home)
- [2.12 Dynamic Workspaces — projections, not storage](#212-dynamic-workspaces--projections-not-storage)
- [Standard ProductField inventory — audit before creating customs](#standard-productfield-inventory--audit-before-creating-customs)
- [Recovery recipe: collapse a custom field back into its standard](#recovery-recipe-collapse-a-custom-field-back-into-its-standard)

### 2.1 Shop types — one enum controls everything

`EcomShops.ShopType` (column) uses `Dynamicweb.Ecommerce.ShopType`:
- `0` None
- `1` **Shop** (commerce storefront / catalog root)
- `2` Warehouse
- `3` **Channel** (feed publishing target — Shopify, HD, EDI partners)
- `4` **DataStructure** (holds data models — NOT customer-facing)

**Rules:**
- **One Shop per brand/market** — don't create duplicates. To rename the default `SHOP1`, send the WHOLE model through `save_shops` (see the full-replace rule below); `UPDATE EcomShops SET ShopName = '...' WHERE ShopId = 'SHOP1'` is the SQL fallback where the tool is permission-blocked.
- **MCP `save_shops` is a FULL-ENTITY REPLACE, not a partial update.** `ShopTools.SaveShops` binds the request item into a fresh `Shop` entity and saves it whole, so a name-only payload resets every column not sent: measured on one host, `{"shops":[{"id":"SHOP1","name":"AgriHub Store"}]}` answered `succeeded:1` and left `ShopAutoBuildIndex` false (was true), `ShopOrderFlowId` NULL (was 1), `ShopImageFolder` / `ShopImagePatternMain` NULL, `ShopAlternativeImagePatterns` empty (was 9 entries), `ShopCompletionRules` NULL, and `ShopCreated` restamped to now. Its sibling `save_areas` documents "on update only the fields you send are changed"; `save_shops` does not, and the response model projects only `id`/`name`/`usageType`/`topLevelProductGroups`, so the damage is invisible in the echo. **Snapshot the row first** (`SELECT * FROM EcomShops WHERE ShopId=... FOR JSON PATH`), send the complete model, then diff the row back. `ShopAutoBuildIndex` silently flipping to false is the leg that costs a later index rebuild.
- **Channels for feeds** — each external system (Shopify, Home Depot, OrderEase, etc.) gets its own ShopType=3 shop with its own group tree. Products get related INTO those groups to control what the feed publishes.
- **DataStructure for data models** — a separate ShopType=4 shop owns the data model tree. Never park data models under the commerce shop.
- **EVERY shop needs a language relation** — insert into `EcomShopLanguageRelation(ShopId, LanguageId, IsDefault)`. Missing this causes "channel with no name" display in admin.

**Where each ShopType appears in admin nav**:

| ShopType | Admin tree section | Source |
|---|---|---|
| 1 (Shop) | Channels (icon: shop) | `Dynamicweb.Products.UI/Tree/ChannelNodeProvider.cs` `GetCatalogShops()` lines 66-74 — filters `UsageType is ShopType.Shop or ShopType.Channel` |
| 3 (Channel) | Channels (icon: code-branch) | same — sibling of Shop in the same filter |
| 4 (DataStructure) | Data models | `Dynamicweb.Products.UI/Tree/StructureNodeProvider.cs` `GetShopsAsDataStructure()` lines 245-262 — filters `UsageType == ShopType.DataStructure` |

So in the admin tree, a `ShopType=1` Shop and a `ShopType=3` Channel sit side-by-side in the **Channels** section (different icon, same tree); only `ShopType=4` shops appear under **Data models**. There is no separate "PIM root" concept — trying to build one fights the UI.

**`ProductActive` vs `EcomGroupProductRelation` for visibility gating.** `ProductActive` is a binary all-or-nothing toggle — when the Products index is built with `OnlyIndexActiveProducts=true` (see `Dynamicweb.Ecommerce/Indexing/ProductIndexBuilder.cs:102,277` — `"AND ProductActive = 1"`), `ProductActive=0` rows are excluded from the entire index, killing them in every channel AND every PIM dashboard. For **per-channel** visibility — "online on the webshop, offline on the marketplace" — use `EcomGroupProductRelation` rows scoped per Channel group (i.e. fire the native "Publish to channel" action, or remove a single channel's relation). `ProductActive=0` is for "this product is gone from EVERYWHERE" (discontinuation); `EcomGroupProductRelation` removal is for "this product is gone from THIS channel". Don't conflate them.

### 2.2 Group types — data models vs catalog groups

`EcomGroups.GroupType` (column) uses `Dynamicweb.Ecommerce.Products.GroupType`:
- `0` **Common** (regular catalog group — products attach here)
- `1` **DataModelFolder** (structural container, no products)
- `2` **DataModel** (attaches a Category of fields to products that relate to this group)
- `3` DataSet

**Critical behaviors:**
- Admin distinguishes the product's "Groups/Channels" tab vs "Data Models" tab by filtering on parent shop's `UsageType`: Shop/Channel → Groups tab; DataStructure → Data Models tab. Cite `Dynamicweb.Products.UI/Queries/ProductGroupRelationsByProductIdQuery.cs:38` — `return usageType is ShopType.Shop or ShopType.Channel;` — and the mirror `Dynamicweb.Products.UI/Queries/ProductRelationsByProductIdQuery.cs:40` — `return usageType is ShopType.DataStructure;`. A "PIM-only" product (relations only to ShopType=4 groups) therefore renders an empty Groups/Channels tab — that's the visible signal that nothing is published.
- **Every group needs an `EcomShopGroupRelation` row, SUBGROUPS INCLUDED. DW resolves a group to its shop through that table and does NOT walk the parent chain.** A subgroup created with MCP `save_groups {name, parentGroupId}` and no `shopId` gets its `EcomGroupRelations` parent row and no shop relation, and the result is a branch that renders but resolves zero products: navigation walks `EcomGroupRelations` so the tree still shows the group, the PLP page returns 200 with the right `h1`, `ProductCatalogGroupById` on it returns `shopId: null`, `ProductsByGroupId` returns `totalCount 0` for a product whose `EcomGroupProductRelation` row demonstrably exists, and the product index writes no `ParentGroupIDs` for it. It is not a cache: measured surviving an `app_offline` recycle plus a Full index rebuild. **Pass `shopId` AND `parentGroupId` in the same `save_groups` call**, then assert the relation: a healthy tree carries one `EcomShopGroupRelation` row for every group (18/18 child groups on a reference install). A missing row on a group whose products all render is the separate "channel with no name" display fault.
- **Every group needs `GroupType` set explicitly.** NULL defaults to 0 (Common) — data models not set to 2 will appear as catalog groups.
- **`GroupType` is the ONLY discriminator, and the MCP group reads do not return it.** A
  `GroupType=2` DataModel group is indistinguishable from a `GroupType=0` catalog group by every
  surface an inventory would use: it is attached to a shop, it comes back from MCP `get_groups` /
  `get_subgroups` exactly like a Common group, it holds `EcomGroupProductRelation` rows exactly like
  a Common group, and it may carry the same display name as a real category (one solution had the
  same category name on both trees). MCP `get_group_by_id` omits `GroupType` entirely, so a
  "duplicate legacy tree" label derived from those tools can point straight at the data-model tree,
  and deleting it un-assigns the data model from every product that carries it. **Read `GroupType`
  before any group-tree audit, cleanup or deletion** — from `EcomGroups` by `SQL` where no higher
  surface reports it (a read, local install only, no cache debt), or by reconstructing the tree from
  the MCP `create_data_models` contract, which states the folder/model/dataset shape. Refuse to
  proceed on any group whose `GroupType` is 1, 2 or 3 without explicit PIM sign-off.
- **Every DataModel group needs `ProductCategoryId`** pointing at a CategoryFields category — that's how field values get plumbed to the product.
- **A data set (`GroupType=3`) stores only its DELTAS from the parent data model's defaults.** The data model above it carries Details-tab default values in `EcomProductCategoryFieldGroupValue`; the data set inherits those, and `DataSetGroupSave` persists only the fields whose value DIFFERS from the inherited default. Measured: 8 values posted to a data set under a data model carrying 5 defaults stored 4 rows, and a second identical save produced the same 4. This is correct behaviour that reads exactly like a failed save, so **an assertion counting stored data-set values must expect (values posted MINUS values equal to the parent default)**. The create is also two-step: `DataSetGroupSave` with `CategoryId` set returns the id, and only a re-read through `DataSetGroupById` exposes the category fields to fill. `DataSetGroupNew` returns an EMPTY `categoryFields` collection because `CategoryId` is not set yet.

### 2.5 Variants — 3 tables, composite IDs

A variant on a hero product is NOT a single row. It needs:

1. **`EcomVariantGroups`** + **`EcomVariantOptions`** (the dimension vocabulary — e.g. a size axis → 9/12/17)
2. **`EcomVariantGroupProductRelation`** — links variant groups to a product. One row per (product, group).
3. **`EcomVariantOptionsProductRelation`** — the combinations. VariantId is the dot-joined option IDs: `VO1.VO4` = first option of group 1 AND first option of group 2 (see `VariantCombinationService.cs:221`). Missing combination rows fail silently at the worst spot: a storefront add-to-cart POST for the variant returns **HTTP 200 and adds nothing**. Existence-guard every direct SQL junction INSERT (`IF NOT EXISTS ... INSERT`) so a re-run converges instead of stacking duplicate relation rows — then restart the host: variant relations are read through a cache resolved at startup.
4. **`EcomProducts`** row per variant — copies master's 60+ columns but overrides `ProductVariantId` (same as step 3), `ProductNumber` (**must be unique per variant** — master `ProductNumber` + dash + short suffix derived from the variant option ids; e.g. master `<CAT>-<SKU>` → `<CAT>-<SKU>-A`, `-B`, `-C`), `ProductActive=1`. Without this row, variants exist but are inactive with no SKU label.

**Hard rule: `ProductNumber` MUST be unique across master + every variant in the family.** Multiple `EcomProducts` rows that share `ProductId` are normal (they're the master + each variant), but their `ProductNumber` values must NOT collide. Downstream consumers that flatten the master/variant tree into separate rows — most notably the PIM-for-Business-Central connector, which exposes each variant as its own BC item via `BCProductIdsByLastModified` and dedupes by SKU — will silently drop variants whose number already matches another row's number. Symptom: BC's "PIM Product List" shows N copies of the same number (one per variant + master), all with the master's name, and the import refuses to create the variant items.

**Regression vector (this WILL happen):** the admin UI's master-product rename flow and some bulk-update paths propagate the master's new `ProductNumber` to every row sharing the same `ProductId` — including the variants — wiping out per-variant suffixes. Re-applying the suffix is idempotent and safe to bake into a verification step / re-run of a seed:
```sql
UPDATE EcomProducts
SET ProductNumber = ProductNumber + '-' + REPLACE(ProductVariantId, 'VO-', '')
WHERE ProductVariantId <> ''
  AND ProductLanguageId = 'LANG1'
  AND CHARINDEX('-' + REPLACE(ProductVariantId, 'VO-', ''), ProductNumber) = 0;
```
Then trigger a Products index rebuild (`POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full"}`) so the BC connector and any other index-backed surface picks up the new SKUs. The BC tenant itself caches its imported PIM Product List — re-run its "Get items from PIM" / sync action after the index rebuild, and if BC dedupes on the same DW `ProductId`, you may need to clear the previously-imported rows on the BC side first. Adjust the `REPLACE(..., 'VO-', '')` term if your variant-option ids don't follow the `VO-<code>` convention; for composite (multi-axis) variants where `ProductVariantId` is dot-joined (e.g. `VO-FIN-WHITE.VO-INT-PINK`), substitute a per-row `NumSuffix` lookup table instead of the `REPLACE`.

Use `INSERT INTO EcomProducts (col1,col2,...) SELECT m.col1, m.col2, ... FROM @combinations v INNER JOIN EcomProducts m ON m.ProductId = v.MasterId AND m.ProductVariantId = ''` — copy master, override 3 fields. Make `ProductNumber` one of the overridden fields, not a copied one.

**MCP `create_variant_combinations` gotcha — it leaves the combo rows NULL where it matters.** The MCP tool creates the per-variant `EcomProducts` rows for you, but it leaves **`ProductActive`** and **`ProductPrice`** **NULL** on the combinations. A NULL-active, NULL-price variant is **invisible storefront-wide** — it does not render in the PDP variant selector and an add-to-cart for it no-ops, exactly like a missing combination row, so it reads as "the tool didn't create them" when the rows are actually there. After `create_variant_combinations`, always set `ProductActive=1` and a real `ProductPrice` (and the §2.5a extras — `ProductDefaultUnitId`, per-variant `ProductStock`) on the new combo rows, then restart/flush. Verify by selecting the combo rows and confirming none have `ProductActive IS NULL` or a NULL price before declaring variants done.

**Enum properties on Management API save models bind by NAME, so a variant write that reuses the DB
ordinal silently zeroes the column.** `VariantGroupTranslationSave` with `DisplayType` read straight out
of `EcomVariantGroups.VariantGroupDisplayType` (int `2` = `VariantColor`) reports successful and stores
`0` = `NothingSelected`, degrading a colour swatch to a plain name list; send `"VariantColor"`. The
general rule, which applies to every `*Save` model carrying an enum, is in the dw-data-access skill,
`references/management-api-and-sql.md`.

### 2.5a Single-axis variants — leaner shape + the MCP/SQL surface split (validated DW 10.25.x)

When the product has exactly ONE variant axis (a Color selector, a tier ladder), the shape is leaner than §2.5's general case:

- `EcomProducts.ProductVariantId` is the **bare `VariantOptionId`** (e.g. `VO3`) — **no `EcomVariantOptionsProductRelation` rows needed**. That table only matters for multi-axis dot-joined combinations. The master still keeps one `EcomVariantGroupProductRelation` row.
- Surface split: MCP `save_variant_groups` / `save_variant_options` create the vocabulary, but there is **no MCP surface** for the group→product relation or for the per-variant `EcomProducts` rows. `update_products` against a variant id that has no row yet fails with `Product not found` — it updates, never creates, variant language rows. The §2.5 SQL INSERT (copy master, override per-variant fields) is the proven path for both on local installs. On hosted/API-only installs the Management API chain covers the whole shape with no SQL — `VariantGroupAdd` then `VariantCombinationSave` (which runs `ExtendAllVariants` to create the per-variant rows) (validated DW 10.25.x).
- Set **`VariantOptionColor`** (hex) on the options and a Swift-style PDP `VariantSelector` renders live **color swatches** with zero template work.
- Per-variant `EcomProducts` gotchas beyond the §2.5 override list:
  - Copy **`ProductDefaultUnitId`** onto every variant row. Variants without it silently drop the per-unit price column from the quantity-break table — the master shows Qty / per-unit / per-piece, the variants show a narrower table, and it reads like a pricing bug even though prices never differed.
  - Seed **per-variant `ProductStock`**, and do it for **every language row** — variants default to 0 even when the master has stock.
  - Quantity-break `EcomPrices` rows with an empty `PriceProductVariantId` apply to **all** variants — no per-variant duplication needed.
- Restart the host before verifying — the PDP selector reads the product cache, so the variants don't show until the bounce. (No restart on a hosted install: bulk-flush the product/stock/price service caches instead.)

### 2.6 Bundles (BOM) — two concerns

1. **Product is BOM** — `UPDATE EcomProducts SET ProductType = 2` (enum: 0=stock, 1=service, 2=bom, 3=giftcard).
2. **Components** — rows in `EcomProductItems`. Two row shapes, split by `ProductItemBomGroupId`:
   - **Fixed component** (predefined bundle line): `ProductItemBomProductId` = the component product
     (append the concatenated variant id for a specific variant, e.g. `PRODx` + `VOn` — and set
     `ProductItemBomVariantId` to the dot-joined variant id), `ProductItemBomGroupId` = `''` empty.
   - **Configurator slot** (customer picks one): `ProductItemBomGroupId` = an **`EcomGroups`
     GroupId** — the slot's options are that group's products, the slot label is the group name, and
     `ProductItemDefaultProductId` picks the pre-selected option. One row per slot, `BomProductId`
     empty. **The GroupId must resolve to a real ecom group**: a synthetic/unknown id (a GUID that
     matches nothing) silently degrades every BOM row into its own single-option pseudo-group named
     after `ProductItemName` — the storefront then shows N one-option "groups" instead of real
     choices, which reads like a template bug but is this data shape.
   - Both shapes: `ProductItemProductId` = parent bundle, plus `ProductItemQuantity`,
     `ProductItemName`, `ProductItemRequired`, `ProductItemSortOrder`. `ProductItemBomProductId` and
     `ProductItemBomVariantId` are NOT NULL — use `''`, never SQL `NULL`.
3. **RESTART THE HOST AFTER INSERTING PRODUCTITEMS** — `ProductItem` uses a `Lazy<Dictionary<...>>` cache (see `ProductItem.cs:145`). Raw SQL inserts bypass it. Until restart, the Bundles tab shows empty.
   **The API alternative — `ProductItemAdd` — accepts exactly one payload shape, `{ProductId, Model}`**, and
   both plausible variations throw rather than degrade. It runs the domain service, so it needs no restart
   and is the correct route on any host where SQL is not sanctioned:
   ```
   { "ProductId": "<parentProductId>", "Model": { … the BOM line … } }   -> ok
   … with ProductOrGroupIds in the payload   -> 500  "Index was outside the bounds of the array"
   … with Model omitted                      -> 400  "Command.Model cannot be null"
   ```
   The 500 is the misleading one: an index-out-of-bounds reads as a platform defect worth reporting, when it
   is the binder rejecting an extra key. Verify BOM lines on the rendered PDP (a kit's lines are visible
   there), not on the add response.
4. Bundles should get their OWN data model (e.g. a `BundleAttributes` category with bundle-specific fields: UnitsPerCase, RetailerSegment, PlanoReady, etc.). Different products → different data models.

### 2.8 Product Categories + Fields (data model internals)

- **`EcomProducts.ProductId` is `NVARCHAR(30)`; `ProductNumber` is `NVARCHAR(255)`.** A
  business-key-as-product-id plan therefore has a hard 30-character ceiling that the product number
  does not share, and **no layer validates it before the write** — the failure surfaces as a
  truncation error inside a bulk import run, not as a validation message. Enforce the length in
  whatever mints the id (the generator, the XSL, the mapping) before the payload reaches the import,
  and keep the long business key on `ProductNumber`.
- **Category** = row in `EcomProductCategory` + translation row in `EcomProductCategoryTranslation`. Categories are SOLUTION-GLOBAL — not scoped to shops.
- **Fields on a category** = rows in `EcomProductCategoryField` + translations in `EcomProductCategoryFieldTranslation`.
- **`reference_category` is load-bearing and easy to miss** — the hidden template category that powers every admin completeness/rule lookup, plus its blank-panel gotcha and seed SQL, lives in [dw-pim-completeness](../../dw-pim-completeness/references/rules-and-dashboards.md).
- **List field options** = `EcomFieldOption` (FieldOptionId, FieldOptionFieldId, FieldOptionName, FieldOptionValue, FieldOptionIsDefault, FieldOptionSort). Scoped to field, not category.
- **Field values on products** = `EcomProductCategoryFieldValue` (FieldValueFieldId, FieldValueFieldCategoryId, FieldValueProductId, FieldValueProductVariantId, FieldValueProductLanguageId, FieldValueValue). One row per (product, field).
- **Dropdown/multi-select values store the option VALUE, never the display name.** For a list-presented
  field, `FieldValueValue` must equal an `EcomFieldOption.FieldOptionValue` (`NaturalOak`), not the
  `FieldOptionName` shown in admin (`Natural Oak`); multi-selects store comma-separated option values.
  A mismatched value renders as a **blank cell with no error** on the storefront spec components even
  though admin shows the raw text — options where value happens to equal name mask the bug for some
  rows, which is why it surfaces as "some attributes randomly missing". When seeding, add any missing
  options first (`create_field_options` takes the reference-field id form
  `ProductCategory|<CategoryId>|<FieldId>`), then write values. Post-seed sweep: select rows on
  list-presented fields whose stored value resolves to no `FieldOptionValue` — every hit is a future
  blank cell.
- **Custom field system names** in MCP use format `ProductCategory|<CategoryId>|<FieldId>` for category fields, plain FieldId for global product fields. Use this SAME format in completeness rule field lists and in product query `FieldExpression` attributes.
- **`ProductFieldOptionSave` writes to an INVISIBLE BUCKET unless the path is
  `ProductCategory|reference_category|<FieldId>`.** Writing options under the *concrete* category
  (`ProductCategory|<CategoryId>|<FieldId>`) is accepted and returns a real option id — and
  `ProductFieldOptionsByFieldId` never serves them back, so the field renders with no choices while the
  write looks perfect. Options belong to the **field**, and a reference field's field-id form is the
  `reference_category` one (same hidden template category that powers the admin completeness/rule lookups —
  [dw-pim-completeness](../../dw-pim-completeness/references/rules-and-dashboards.md)). Write options to the `reference_category` path, then assert
  they come back through `ProductFieldOptionsByFieldId`; a returned id is not evidence.
- **Cloning a reference field's DEFINITION does not clone its OPTIONS — and `EcomFieldOption` primary keys are
  globally unique, so the rows cannot be copied verbatim.** Cloning reference fields into per-type PIM
  categories leaves the options behind in the `ProductCategory|reference_category|<fieldId>` bucket, so the
  editor reads the real category bucket and renders **empty dropdowns** — 11 list fields across six attribute
  categories on one build, every one of them saving and reading back fine. The obvious fix then violates the
  PK: `EcomFieldOption`'s key is **`FieldOptionId` ALONE**, globally unique rather than scoped per field
  (measured: 463/463 distinct), so copying rows verbatim collides. The platform's own precedent settles the
  shape — a stock per-type spec category mirrors its reference field and carries **its OWN copy of every
  option: same values, DIFFERENT option ids**. Mint the new ids
  (`MAX(TRY_CAST(SUBSTRING(FieldOptionId,9,20) AS int)) + ROW_NUMBER()`, the same `TRY_CAST` rule the
  `nvarchar` id columns need elsewhere). **Make option-set copying an explicit step of any reference-field
  clone**, and assert every list-type category field has a non-empty option set *in its own bucket*.
- **`ProductFieldSave` will NOT change `typeId` — it echoes the new type and persists the old.** Worse, the
  *other* edits on the same call **do** persist: rename the field, change its description or display group
  and retype it in one save, and everything except the retype lands. The response carries the new `typeId`,
  so only an independent re-read catches it. **Never retype a category field in place.** The only route the
  platform offers is delete + recreate, which discards every stored value — so the safe motion is
  **create the correctly-typed field alongside, migrate the values, then retire the old field**, and record
  the retirement so a later reader does not treat the leftover as live.

#### Category-field writes that answer `ok` and change nothing, and one that lies the other way

`ProductFieldSave` binds the whole `ProductFieldDataModel` and round-trips it through the read model,
but the repository update covers only a subset of columns. Everything outside that subset is echoed
back with the new value and dropped. Assert every row in this table against raw SQL on
`EcomProductCategoryField`, never against the save response and never against `ProductFieldById`:

| Write | What the API says | What lands | Do this instead |
|---|---|---|---|
| `ProductFieldSave` with `Sort` | `status: ok`, response model carries the new `sort` | `FieldSortOrder` unchanged (71 sort writes, 0 rows moved) | `ProductCategoryFieldSaveSort` (next row) |
| `ProductFieldSave` with `TemplateName` | `status: ok`, response carries the new `templateName` | `FieldTemplateTag` unchanged | Nothing. `FieldTemplateTag` is **create-only** (below) |
| `ProductCategoryFieldSaveSort` with BARE field ids in `OrderedIds` | `{"status":"ok","model":null}` | Zero rows moved. Each `OrderedId` resolves as a fully-qualified product-field id, a bare system name resolves to nothing, and the empty set is written as a no-op | Build every id as `ProductCategory\|<CategoryId>\|<fieldSystemName>`, in the wanted order. A top-level `CategoryId` property on the body does NOT help: the qualification must be inside each id. Qualified ids rewrote all 18 sort orders to a gapless 1..18 |
| `create_category_fields` echo | `fieldOptions: []` and `allowChangesAcrossLanguages: false` even when five options and `true` were sent | **Both persisted correctly.** The echo renders the per-category field copy before the shared `reference_category` option set is attached | Read back with `get_product_category_fields`, which shows all five options with translations on every target category. This echo lies in the safe direction, so do not "fix" a field that is already correct |

**`FieldTemplateTag` is write-once at field CREATE, through every surface.** `ProductFieldSave` drops
it, and so does the admin field-edit screen (`/Admin/UI/Products/ProductAttributeEdit/<guid>?FieldId=…`):
type a tag, click Save, and `SELECT FieldTemplateTag` still returns `''`, but the form REDISPLAYS the
submitted value on the next visit, because the read model serves it from cache. Retried with a unique
value to rule out a uniqueness constraint, same result. A field that needs a template tag must be
recreated (which discards its stored values) or shipped with the tag from the start. Sweep for the gap:
`SELECT FieldTemplateTag FROM EcomProductCategoryField WHERE FieldTemplateTag IS NULL OR FieldTemplateTag = ''`
must be empty on a healthy solution.

### Range category fields (`EcomFieldType` 25) are half-implemented: do not model a demo attribute as one

**Standing rule: use two scalar numeric fields (`…MinC` / `…MaxC`).** They are language-layered,
indexable, facetable, completeness-scorable and cache-stable, which the Range type is not. Reproduced
across two independent catalogues and two host classes on DW 10.26.12, 10.28.3 and 10.28.4. Every leg
fails silently:

| Leg | What actually happens | Consequence |
|---|---|---|
| Storage | The `EcomFieldType` row 25 (`FieldTypeName=Range`, `FLOAT DEFAULT 0.0`) is inserted unconditionally by migration; the `Products.UI.RangeFieldTypeFeature` flag only gates UI/API exposure. Values ride `EcomProductCategoryFieldValue` as **two composite ids**, `<fieldId>\|RangeType\|Minimum` and `<fieldId>\|RangeType\|Maximum` | The type "exists" with the flag off, and there are no dedicated min/max columns to query |
| Write (`ProductSave`) | Persists a Range value **only** as STRING members `{Minimum:"-20",Maximum:"60"}`. `RangeValueConverter` emits strings and numeric members are dropped: `status: ok`, empty message, no row | Twelve payload shapes burned before the right one was found. A control Integer write in the same request body persists fine |
| Write (`patch_products_safe`) | An object `{Minimum,Maximum}` throws "An error occurred invoking patch_products_safe"; the same value as a JSON **string** answers OK and persists nothing | Both readings look like a payload-shape problem |
| Language | Range values are language-invariant: only the default-language row stores. `ProductSave` for a non-default language answers `ok` and persists nothing | Reads in any language resolve the default row, so the value IS correct everywhere. Reads as a 33% write failure |
| Index schema | The schema extender projects a Range field as **two** `System.Double` definitions (`\|RangeType\|Minimum` / `\|Maximum`) the moment the field is created, no rebuild needed. The un-suffixed base name is NOT an index field | `FacetSave` must still point at the **BASE** field id: `RangeHelper.GetRangeFieldWith{Minimum,Maximum}PrefixId` re-applies the postfixes. Pointing a facet at a field the index does not list is correct here and looks certain to fail |
| Index read | The product index answers `IsEmpty=true` for a range field on **every** document (measured 452/452 on a field where sibling scalars answered 449 / 451 / 1) | A query can never witness a range value, so no worklist or dashboard can be built on one |
| Facet render | Swift 2.4 ships **no Range facet renderer**. `FacetRenderOptions.xml` advertises `Range` as selectable; `Paragraph/ProductListFacets/FormFields.cshtml` switches on the raw string render type, `Colors` gets swatches and everything else falls through to checkboxes, and a range facet returns no discrete Options so the group is hidden | Configured, accepted, visible in admin, invisible on the PLP, no error anywhere |
| Cache | Range values are served from the product cache and can be **cross-contaminated between products**: of 17 backfilled products, 8 served null and 4 served ANOTHER product's Minimum/Maximum while still satisfying the probe predicate | A Full build copies the corruption into the index. Deterministic and identical across consecutive rebuilds; no product property separates the poisoned set |
| Rebuild | A Full `Products\|Products.index` rebuild **re-poisons** the values (4 of 5 builds in one day), and the poisoning was present before the build too, so the build triggers rather than causes it | Check and repair after **every** build, not once per pass. The DB stays correct throughout; both the Management and Delivery APIs lie |
| Completeness | Range (and boolean) category fields never satisfy a completeness rule: a product with every rule field populated in the DB scored 91%. A `patch_products_safe` naming three OTHER scalars silently DELETED both range-typed fields from the product | The worklist can never drain, and there is no warning on the delete |

**The read surfaces disagree, and only one of them is honest.** MCP `get_product_by_id` renders every
range as the literal string `"RangeValue { Minimum = , Maximum =  }"` whether or not a value exists,
and the index answers `IsEmpty` for all of them. **`/Admin/Api/ProductById` is the only reader that
returns the typed value the admin editor renders.** Assert there, and report populated/empty counts
explicitly rather than inferring from either of the other two.

**If a catalogue must carry Range values:** treat them as write-once at seed time through the path that
originally worked, re-inject them from SQL BEFORE any `ProductSave` round-trip (the save wipes them
otherwise), and gate on the post-build repair after every index build.

### 2.10 Assets

- Files live in `wwwroot/Files/Images/...` (or any `/Files/` subfolder).
- Product asset record = `EcomDetails` row:
  - `DetailProductId`, `DetailVariantId`, `DetailLanguageId`, `DetailType=0` (image), `DetailValue=<file path>`, `DetailIsDefault` (primary), `DetailsGroupId` (asset category numeric id — check `EcomDetailsGroup`)
- Asset categories = `EcomDetailsGroup` table — **not `EcomAssetCategory`, which does not exist on this
  platform.** A stock solution ships exactly two groups, `Images` and `Documentation`, and **there is
  no per-document-type category**: the difference between a spec sheet, a safety data sheet, a
  warranty and an installation guide lives only in the free-text `EcomDetails.DetailsName` on each row
  inside the single `Documentation` group. So a documents tab that promises a **type** column derives
  it from the asset's own name and says so; a tab built by iterating asset categories renders at most
  two sections whatever the specification asked for. Either mint the extra categories deliberately, or
  design the surface around names — do not assume the categories are there. New categories (e.g.
  `Manuals` for PDFs) are SQL-only — no MCP tool exists for `EcomDetailsGroup` mutations. Insert into both `EcomDetailsGroup` (set `DetailsGroupExtensions` to filter file types, e.g. `'pdf'`, and `DetailsGroupDefaultUploadFolder` to the target path) AND `EcomDetailsGroupTranslation` (one row per language).
- MCP tools `add_product_image` / `import_product_images_from_urls` / `upload_product_images` handle both download-to-disk + DB row. **Plugin-only — no Management API endpoints back these.** They live entirely in the MCP plugin code path; if the MCP session dies (token expiry, plugin restart, host restart) there is no `POST /admin/api/...` fallback for asset registration. The fallback is direct SQL INSERT on `EcomDetails`.
- **`import_product_images_from_urls` does NOT set a default image** — it registers the `EcomDetails` rows with `DetailIsDefault=0` on all of them. A product then has images-but-no-default, and that is a **frontend-breaking** state, not a cosmetic one: the Swift card template **NREs on a product with images but no default**, and because the PLP renders cards in a loop, one such product **degrades the WHOLE product-list page** (the list throws, not just that one card). After any `import_product_images_from_urls` run, set a default: `UPDATE EcomDetails SET DetailIsDefault=1 WHERE DetailProductId=<id> AND DetailLanguageId='LANG1' AND DetailValue=<chosen path>` (exactly one default per product/variant/language), then flush/restart. Make "a DEFAULT image is set" a per-product verification gate for exactly this reason.
- **Bulk SQL INSERT must set `DetailLanguageId` to a real language code** (e.g. `'LANG1'`), not empty string and not NULL. The admin asset query and the per-product image listings filter strict-equality on this column, so empty-string language renders the row invisible despite being on disk and registered. Symptom: SQL count says 9 details for the product, admin product page shows 0 assets, file is at the path. Recovery: `UPDATE EcomDetails SET DetailLanguageId = 'LANG1' WHERE DetailLanguageId = '' OR DetailLanguageId IS NULL;` then host restart to flush asset caches. The MCP tools always populate this column correctly — this gotcha only fires when bulk SQL inserts skip the field.
- After bulk SQL inserts, **restart the host** to flush the `EcomDetails` cache (the same restart-after-SQL protocol that product mutations require).

### 2.11 Stock units — a per-location attribute needs a per-location home

`EcomStockUnit` is the per-(product, stock location) row, and it is the **only** place a per-location
attribute can live. The two homes a specification usually proposes for one are both impossible:

- `EcomStockUnit.StockUnitExpectedDelivery` is a `DATETIME` — it carries the date an inbound
  replenishment arrives and cannot carry its quantity.
- A product custom field is **per product**, so it cannot differ per location; a single value there
  silently means "the same everywhere", which is the opposite of what a per-location figure claims.

So an inbound quantity (or any other per-location number) needs a per-location column on
`EcomStockUnit`, or an equivalent custom table keyed the same way — an `ALTER TABLE` on a local
install, with the host restarted afterwards to flush the stock caches, because no MCP tool or
Management API verb extends that table. Two follow-on facts worth deciding before the column is
added: the delivery API projects the whole `stockUnits[]` collection per product, and the
platform's own stock resolution defaults to the **first** stock unit, so a storefront row that
should show the signed-in user's own location needs its own resolution step rather than the default.

### 2.12 Dynamic Workspaces — projections, not storage

Dynamic Workspaces are the modern PIM workbench UI in DW10 — multi-level grouping built from a product query. They are **query-backed projections, not storage**: they don't move product rows, they show different slices of the catalog. The canonical product home is still `EcomGroupProductRelation` rows under a `ShopType=4` DataStructure shop; workspaces just project that home by attribute axes (data-model keys or product fields).

**Storage tables** (separate from `EcomShops` / `EcomGroups`):

| Table | Key | Purpose |
|---|---|---|
| `DynamicStructures` | GUID | One row per workspace — name + backing query GUID. |
| `DynamicStructureLevels` | GUID + ordered | Levels of the workspace tree. Each level has a `SourceField` (the axis) and a `LevelType` enum. |

Cite `Dynamicweb.Core/Indexing/DynamicStructuring/DynamicStructure.cs:24` (`public Guid Id { get; set; }`) and `DynamicStructureLevel.cs` for the level shape.

**Permission entity** — `PermissionName="DynamicStructure"`, key=Guid. Cite `Dynamicweb.Core/Indexing/DynamicStructuring/DynamicStructure.cs:43` (`private const string PermissionName = "DynamicStructure";`) and the `[PermissionEntity(PermissionName)]` attribute at line 12. The class implements `IPermissionEntity, IPermissionEntityLookup` (line 13). This entity slots into the platform's three-layer permission model as a Layer C entity permission (see the users/permissions foundational knowledge).

**Level types** — `DataModelKey` or `ProductField`. Cite `Dynamicweb.Products.UI/Models/ProductCatalogs/DynamicStructureLevelTypes.cs` (2-value enum):

```csharp
public enum DynamicStructureLevelTypes { DataModelKey, ProductField }
```

A workspace level rooted on `DataModelKey` projects products by which DataModel group (GroupType=2) they're related to; a level rooted on `ProductField` projects by distinct values of a product field. **Which product field is the whole game, and two obvious choices are silent failure modes** (see "Choosing a level source" below).

**`UseRelationOnProductCreate` — the auto-attach mechanic.** Cite `Dynamicweb.Core/Indexing/DynamicStructuring/DynamicStructureLevel.cs:74` (`public bool UseRelationOnProductCreate { get; set; }`). When `true`, products created from inside the workspace UI are automatically attached to the source `DataModel` group via `EcomGroupProductRelation`. Without this flag, products created in a workspace are **orphans** — they exist in `EcomProducts` but have no group relation, so they appear only in "All products" and are invisible to every channel filter and every other workspace projection. The workspace's `DynamicStructureRepository` persists/reads the flag at lines 152, 170, 173, 201.

**License gate** — `LicenseManager.LicenseHasFeature("PIM")`. Cite `Dynamicweb.Products.UI/Tree/ProductCatalogsSection.cs:13` (class declaration, `Name = "Dynamic workspaces"`, `Sort = 20`) and line 36 (`public override bool ShouldShow() => LicenseManager.LicenseHasFeature("PIM");`). Without the PIM license feature, the entire Dynamic Workspaces section in the Products tree collapses; the navigation falls back to the legacy `ChannelNodeProvider` "All products" surface (see `ChannelNodeProvider.cs:60` — `nodes.Add(QueriesNodeProvider.CreateAllProductsNode());`).

**Mental model:** Dynamic Workspaces are *projections*, not *storage*. They're configurable, multi-level views over the product catalog backed by a query + level definitions. They do not own products — they project the catalog by attribute axes. The single mechanic that makes "creating in a workspace" feel like real storage is `UseRelationOnProductCreate=true` on the workspace's level: when set, the workspace owns the "auto-attach to the source DataModel group" behaviour on create. Without it, "create in workspace" produces orphan rows.

**Choosing a level source: it must be a NON-ANALYSED string field.** `DynamicStructureLevel.SourceType`
is `productField` or `dataModelKey` only, and the node value is enumerated from the **index** and matched
as a **string**. That rules out two field classes that both look like the natural choice, and both fail
without erroring:

| Level source | What renders | Why |
|---|---|---|
| **Analysed string field** (free text: a name field such as `ManufacturerName`, a supplier name, a description-shaped field) | Plausible-looking nodes that are **lower-cased word fragments**. One 358-product query produced **129 nodes summing to 419**: `"Hot-Shot"` appeared as both `hot (12)` and `shot (12)`, `"J Lube"` as `j (3)` and `lube (1)`, plus junk nodes `o (1)`, `z (3)`, `plus (3)`. | The level enumerates analysed Lucene **terms**, not stored values. Every node drills to real rows, so nothing errors and no count contradicts itself. |
| **Numeric / id-typed field** (`ProductWorkflowStateId` and similar) | Nodes that open onto **zero rows**. | The value is indexed numerically and the node label is matched as a string, so the label never matches a row. |
| **Non-analysed string field**: an **ID** field (`ManufacturerID`), a `DATAMODEL_*` key, or a category field (`ProductCategory\|<cat>\|<field>`, indexed as keywords) | Correct nodes with exact casing that sum to the query total. | Keyword-indexed, so the enumerated term is the stored value. |

**Use the ID field, not the name field, and let DW resolve the display name.** Swapping the same level
from `ManufacturerName` to `ManufacturerID` took it from 129 nodes summing to 419 to **106 nodes summing
to 358** against a query total of 358, labelled `3M (13) | Allflex (19) | Duflex (27) | Hot-Shot (12) |
…`: DW resolves the id to the manufacturer display name for the node label, so the readable tree costs
nothing.

**Validate by the SUM, not by a drill.** Assert the level's node count and the **sum of node counts**
against the workspace query total. A per-node drill alone does not catch the analysed-field failure,
because every tokenised node drills to real rows.

**A level's node counts follow the BACKING QUERY's predicate, so a sum that overshoots the query is the
query's own document fan-out, not a workspace defect.** A level counts index documents by field value
under the backing query's predicate, which is the same variant × language fan-out the counter widgets
see. Measured: L1 nodes summing `18+1459+833+87+752 = 3149` against a 2 939-row query read as a defect;
adding `LanguageID=ENU` + `VariantID isEmpty` to the four workspace-backing queries brought the same
level to `6+1433+768+29+703 = 2939`, exactly the query, and the sibling workspaces to exactly theirs.
**Narrow the backing query** rather than treating the node counts as independent of it.

**Creating a workspace is TWO commands, and `DynamicStructureSave` silently drops a `Levels` collection.**
Posting `{QueryData:{}, model:{Name, QueryId, Levels:[…]}}` answers `200 {"status":"ok"}`, echoes a real
id, and creates a workspace with **zero levels**. A zero-level workspace still appears in the Products
tree and expands to nothing, so it reads as "the query returned nothing" rather than "the write was
ignored", and nothing in the response mentions the dropped array. Levels are a separate aggregate:

```
1) POST /Admin/Api/DynamicStructureSave  {"QueryData":{}, "model":{"Name":…, "QueryId":…}}
2) per level, POST /Admin/Api/DynamicStructureLevelSave
   {"QueryData":{"StructureId":<guid>,"Type":"DynamicStructureLevelNew"},
    "model":{"StructureId":<guid>,          // REQUIRED inside the model, not only in QueryData
             "SourceType":"DataModelKey"|"ProductField","SourceField":…,
             "SortDirection":"Ascending","Index":<n>,
             "UseRelationOnProductCreate":<bool>,"UseCompleteness":<bool>}}
```

- **`StructureId` is validated out of the MODEL.** With it only in the query envelope the call answers
  `400 {"":["Model validation failed"],"StructureId":["The value is required."]}`.
- **Always pass `Index` explicitly.** It defaults to `0` when the model omits it (the admin form has no
  Index editor), so levels created in sequence all land at index 0 with undefined ordering. Re-saving
  with `model.Index=1|2` fixes the order.
- **`UseCompleteness` and `UseRelationOnProductCreate` are never hydrated on the read, so a
  read-modify-write CLEARS them.** `GET /Admin/Api/DynamicStructureLevelById?Id=<n>&StructureId=<guid>`
  returns `useRelationOnProductCreate:false, useCompleteness:false` regardless of the stored values
  (measured against a DB row holding `UseCompleteness=1`), while `DynamicStructureLevelSave` persists
  both booleans correctly. Posting back the model you just read therefore writes both flags to false,
  and a self-draining completeness workspace quietly stops draining. **Never round-trip a
  `DynamicStructureLevel` model**: read the true state from `DynamicStructureLevels` (or keep an
  intended-state table) and set BOTH booleans explicitly on every save.
- **There is no read query for either aggregate.** `DynamicStructureList`, `DynamicStructures`,
  `DynamicStructureGet`, `DynamicStructureById` and `DynamicStructureFields` all answer
  `400 "Unknown query"`, so the API cannot verify its own write and SQL is the only read-back. Assert
  `COUNT(*) FROM DynamicStructureLevels` for the structure's `DynamicStructureUniqueId` equals the
  number of levels intended, and that `DynamicStructureLevelIndex` is 1..n with no duplicates.
  `status: ok` from `DynamicStructureSave` proves nothing about levels.

**When workspaces are the right answer:**
- "Show me products by **brand**": 1 level, `LevelType=ProductField`, `SourceField=ManufacturerID`.
- "Show me products by **hazard class / spec attribute**": 1 level, `LevelType=ProductField`, `SourceField=ProductCategory|<cat>|<field>` (category fields are keyword-indexed and safe).
- "Products by spec attribute" — 2 levels, both `LevelType=DataModelKey`, drilling category → sub-category.
- A **workflow-state** tree is NOT one of them: `ProductWorkflowStateId` is the numeric failure mode above, and it is not populated as an index field either, so the clause is silently dropped wherever it is used as a filter. Group by state on a string-valued state field, or use the catalog tree with a state column.

**Probing a workspace: `ProductsByDynamicStructureLevel` requires `Path` and returns `0` without it — for
every query, on a healthy workspace.** The command does not error on the missing parameter; it answers
`0`, which is exactly the shape of a broken workspace. Diagnosing from that produces a hunt for missing
relations that were never missing — the same queries returned 756, 31 and 2,929 rows once `Path` was
supplied. **Always pass `Path`**, and any harness leg that probes workspace membership must assert `Path`
is set before it asserts anything about the count, or it asserts on a lie.

**An empty workspace has three candidate causes and they compose — walk the checklist in order rather
than hunting relations.** Two independent faults produced the same "renders no data despite matching
products existing" state on one build, and fixing either alone left it empty:

1. **`Path` missing on the probe** (above) — rule it out first; it is free and it is the one that makes a
   healthy workspace look broken.
2. **The workspace's `queryId` points at a query that does not exist.** The workspace saves and renders
   with a dead reference — nothing validates the pointer — so re-resolve the GUID against the live query
   list before believing anything downstream of it.
3. **The index builder is skipping the terms the workspace projects on.** Both `Products.index` builders
   carried `SkipCompletionRules=True` and `SkipDataModels=True`, so the completeness and data-model terms a
   `DataModelKey` level matches on were never written to the index — the levels had nothing to match and
   returned empty for every product. Read the builder flags, clear them, and **rebuild**; a flag change
   without a rebuild changes nothing. After the repoint + flags + rebuild the three workspaces returned
   756 / 31 / 2,929.

A solution that leans on workspaces should not ship index builders that skip completion rules.

**When workspaces are NOT the right answer:**
- Permission boundary. Workspaces are gated by the `/Products/DynamicWorkspaces` capability key (single on/off across all workspaces of that capability scope), not per workspace. Per-product permissions still come from group-level grants (the users/permissions foundational knowledge covers the full picture).
- Originating products without a catalog group. Without `UseRelationOnProductCreate=true` on at least one level, the workspace's "Create product" UI produces orphans.

Cite source files (all under `dw10source/src/Core/Dynamicweb.Core/Indexing/DynamicStructuring/`):
- `DynamicStructure.cs` — entity (Guid key, `PermissionName="DynamicStructure"`, line 43)
- `DynamicStructureLevel.cs` — level + `UseRelationOnProductCreate` (line 74)
- `DynamicStructureLevelScope.cs` — runtime level recognition (value-based)
- `DynamicStructureRepository.cs` — persistence
- `DynamicStructureService.cs` — service layer

Plus `Dynamicweb.Products.UI/Models/ProductCatalogs/DynamicStructureLevelTypes.cs` (level type enum) and `Dynamicweb.Products.UI/Tree/ProductCatalogsSection.cs` (license gate + admin tree section).

## Standard ProductField inventory — audit before creating customs

DW10 ships ~50 standard `ProductField` system names, hardcoded in `dw10source/src/Features/Ecommerce/Dynamicweb.Ecommerce/Products/ProductField.cs` `FieldSystemName` class. These map to actual columns on `EcomProducts` and are wired through the entire stack (ProductListScreen, completion rules, indexes, feeds, BC connector). Creating a custom field that duplicates a standard creates two distinct failure modes:

1. **Exact-name duplicate.** A custom `EcomProductField` row with `ProductFieldSystemName` matching a standard (e.g. `ProductWeight`, `ProductHeight`, `ProductWidth`, `ProductDepth`, `ProductVolume`, `ProductEAN`) causes two definitions of the same field. Edit screens and field-picker UIs may render twice; some lookups pick the first by autoid (unpredictable across solutions). Always pure duplication, never useful.
2. **Alias duplicate.** A custom field with a *different* SystemName but storing the same semantic value (e.g. `g_ean` next to standard `ProductEAN`; `g_weight_kg` next to `ProductWeight`; `g_height_cm` next to `ProductHeight`). Splits data across two columns. Completion rules, feeds, and integrations have to pick one — usually pick the custom (since that's why it was added) — and the standard column appears empty. BC connector and most off-the-shelf integrations key off the standard, so the data silently never reaches them.

**A standard field is a COLUMN on `EcomProducts`, not an `EcomProductField` row — and the MCP
custom-field path cannot write one.** MCP `get_standard_fields` lists them all, which reads as a list
of writable targets and is not: `patch_products_safe` with `customFields: [{ id: "ProductEAN" }]`
fails every row with `No ProductField or ProductFieldValue based on the given system name`, because
that path resolves through the product-field tables, and `update_products` exposes no property for it
either. Read the current value with `get_product_by_id`, which does carry the scalar; the write is
the product edit screen's own field, and the same holds for every other `EcomProducts` scalar the MCP
model omits. Outside the product: see dw-data-access `recipes-pim.md` §Writing a standard
`EcomProducts` scalar the MCP model omits.

**Preflight rule (do this BEFORE creating any custom field):**

Compare the proposed SystemName against the standard set. The full list is in `ProductField.FieldSystemName` constants — load it once and grep before each `create_product_fields` MCP call or SQL insert. The semantic-overlap set (the ones most often duplicated by alias) covers physical dimensions (Weight, Height, Width, Depth, Volume), identifiers (EAN, Number, ManufacturerID), pricing (Price, Cost, PriceType), stock (Stock, StockGroupID, NeverOutOfStock), content (Name, ShortDescription, LongDescription, MetaTitle/Description/Keywords/Canonical/Url), images (ImageDefault, ImageSmall, ImageMedium, ImageLarge, Images), workflow (WorkflowStateId, Active, Discontinued, ReplacementProductId, DiscontinuedAction), and audit (Created, Updated, Type, DefaultShopID, DefaultUnitID, ExpectedDelivery). If you need one of these, **use the standard**.

Legitimate customs to keep: anything genuinely solution-specific that has no standard equivalent — e.g. ERP-sync hints (`g_bc_reorder`), action-rule routing fields (`g_notify_email` for auto-offline mail recipient), free-text supplier (different from the `ProductManufacturerID` select), lifecycle-state mirrors used by external automation. Use a consistent prefix (`g_` is a common convention) so the legitimate customs are visually distinct from accidental standard-overlap mistakes.

## Recovery recipe: collapse a custom field back into its standard

When a PIM has already accumulated standard-field duplicates (typical after rushed initial modelling), fold each custom back into its standard before continuing. Order matters: backfill data, rewire references, then drop the custom — never delete first.

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
--    (auto-named, vary per install) so the DROP COLUMN doesn't fail with msg 5074.
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

Then flush `ProductFieldService`, `ProductService`, `CompletionRuleService`, `PermissionService` and trigger a Full `BuildIndex` on the Products repository (see [dw-pim-completeness](../../dw-pim-completeness/references/rules-and-dashboards.md) for the rebuild recovery recipe).

**Completion-rule regex note**: `EcomCompletionRules` uses a comma-separated SystemName list (`EcomCompletionRuleProductFields`), not regex. Rule "completeness" is a field-has-value check, not a pattern match. `EcomValidationRules` is a separate table for input-validation patterns and is independent — touch that only if a custom field carried a regex pattern (`FieldValidationPattern` on `EcomProductCategoryField`) that needs replicating on the standard.
