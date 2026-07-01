# Foundational candidate → dw-pim-modelling

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 PIM structural-modelling knowledge, staged here for a future
> fold-up into `dw-pim-modelling`. No demo/customer content. When folded, move this body into
> `dw-pim-modelling` and re-target the pointers in the demo skills. Until then, the demo skills
> reference this file.

## The structural mental model

Getting any of these wrong causes rework.

### 2.1 Shop types — one enum controls everything

`EcomShops.ShopType` (column) uses `Dynamicweb.Ecommerce.ShopType`:
- `0` None
- `1` **Shop** (commerce storefront / catalog root)
- `2` Warehouse
- `3` **Channel** (feed publishing target — Shopify, HD, EDI partners)
- `4` **DataStructure** (holds data models — NOT customer-facing)

**Rules:**
- **One Shop per brand/market** — don't create duplicates. If `mcp__dynamicweb-commerce-mcp__save_shops` fails to rename the default `SHOP1`, update directly: `UPDATE EcomShops SET ShopName = '...' WHERE ShopId = 'SHOP1'`.
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

**`ProductActive` vs `EcomGroupProductRelation` for visibility gating.** `ProductActive` is a binary all-or-nothing toggle — when the Products index is built with `OnlyIndexActiveProducts=true` (see `Dynamicweb.Ecommerce/Indexing/ProductIndexBuilder.cs:102,277` — `"AND ProductActive = 1"`), `ProductActive=0` rows are excluded from the entire index, killing them in every channel AND every PIM dashboard. For **per-channel** visibility — "online on the webshop, offline on the marketplace" — use `EcomGroupProductRelation` rows scoped per Channel group (i.e. fire the native "Publish to channel" action, see [`commerce-catalog.md`](commerce-catalog.md), or remove a single channel's relation). `ProductActive=0` is for "this product is gone from EVERYWHERE" (discontinuation); `EcomGroupProductRelation` removal is for "this product is gone from THIS channel". Don't conflate them.

### 2.2 Group types — data models vs catalog groups

`EcomGroups.GroupType` (column) uses `Dynamicweb.Ecommerce.Products.GroupType`:
- `0` **Common** (regular catalog group — products attach here)
- `1` **DataModelFolder** (structural container, no products)
- `2` **DataModel** (attaches a Category of fields to products that relate to this group)
- `3` DataSet

**Critical behaviors:**
- Admin distinguishes the product's "Groups/Channels" tab vs "Data Models" tab by filtering on parent shop's `UsageType`: Shop/Channel → Groups tab; DataStructure → Data Models tab. Cite `Dynamicweb.Products.UI/Queries/ProductGroupRelationsByProductIdQuery.cs:38` — `return usageType is ShopType.Shop or ShopType.Channel;` — and the mirror `Dynamicweb.Products.UI/Queries/ProductRelationsByProductIdQuery.cs:40` — `return usageType is ShopType.DataStructure;`. A "PIM-only" product (relations only to ShopType=4 groups) therefore renders an empty Groups/Channels tab — that's the visible signal that nothing is published.
- **Every group needs a `EcomShopGroupRelation` row** linking it to its parent shop. Missing = "channel with no name" appears on every product in that group.
- **Every group needs `GroupType` set explicitly.** NULL defaults to 0 (Common) — data models not set to 2 will appear as catalog groups.
- **Every DataModel group needs `ProductCategoryId`** pointing at a CategoryFields category — that's how field values get plumbed to the product.

### 2.5 Variants — 3 tables, composite IDs

A variant on a hero product is NOT a single row. It needs:

1. **`EcomVariantGroups`** + **`EcomVariantOptions`** (the dimension vocabulary — e.g. a size axis → 9/12/17)
2. **`EcomVariantGroupProductRelation`** — links variant groups to a product. One row per (product, group).
3. **`EcomVariantOptionsProductRelation`** — the combinations. VariantId is the dot-joined option IDs: `VO1.VO4` = first option of group 1 AND first option of group 2 (see `VariantCombinationService.cs:221`).
4. **`EcomProducts`** row per variant — copies master's 60+ columns but overrides `ProductVariantId` (same as step 3), `ProductNumber` (**must be unique per variant** — master `ProductNumber` + dash + short suffix derived from the variant option ids; e.g. master `<CAT>-<SKU>` → `<CAT>-<SKU>-A`, `-B`, `-C`), `ProductActive=1`. Without this row, variants exist but are inactive with no SKU label.

**Hard rule: `ProductNumber` MUST be unique across master + every variant in the family.** Multiple `EcomProducts` rows that share `ProductId` are normal (they're the master + each variant), but their `ProductNumber` values must NOT collide. Downstream consumers that flatten the master/variant tree into separate rows — most notably the PIM-for-Business-Central connector, which exposes each variant as its own BC item via `BCProductIdsByLastModified` and dedupes by SKU — will silently drop variants whose number already matches another row's number. Symptom: BC's "PIM Product List" shows N copies of the same number (one per variant + master), all with the master's name, and the import refuses to create the variant items.

**Regression vector (this WILL happen):** the admin UI's master-product rename flow and some bulk-update paths propagate the master's new `ProductNumber` to every row sharing the same `ProductId` — including the variants — wiping out per-variant suffixes. Re-applying the suffix is idempotent and safe to bake into a verification step / re-run of the seed:
```sql
UPDATE EcomProducts
SET ProductNumber = ProductNumber + '-' + REPLACE(ProductVariantId, 'VO-', '')
WHERE ProductVariantId <> ''
  AND ProductLanguageId = 'LANG1'
  AND CHARINDEX('-' + REPLACE(ProductVariantId, 'VO-', ''), ProductNumber) = 0;
```
Then trigger a Products index rebuild (`POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full"}`) so the BC connector and any other index-backed surface picks up the new SKUs. The BC tenant itself caches its imported PIM Product List — re-run its "Get items from PIM" / sync action after the index rebuild, and if BC dedupes on the same DW `ProductId`, you may need to clear the previously-imported rows on the BC side first. Adjust the `REPLACE(..., 'VO-', '')` term if your variant-option ids don't follow the `VO-<code>` convention; for composite (multi-axis) variants where `ProductVariantId` is dot-joined (e.g. `VO-FIN-WHITE.VO-INT-PINK`), substitute a per-row `NumSuffix` lookup table instead of the `REPLACE`.

Use `INSERT INTO EcomProducts (col1,col2,...) SELECT m.col1, m.col2, ... FROM @combinations v INNER JOIN EcomProducts m ON m.ProductId = v.MasterId AND m.ProductVariantId = ''` — copy master, override 3 fields. Make `ProductNumber` one of the overridden fields, not a copied one.

### 2.5a Single-axis variants — leaner shape + the MCP/SQL surface split (validated DW 10.25.x)

When the product has exactly ONE variant axis (a Color selector, a tier ladder), the shape is leaner than §2.5's general case:

- `EcomProducts.ProductVariantId` is the **bare `VariantOptionId`** (e.g. `VO3`) — **no `EcomVariantOptionsProductRelation` rows needed**. That table only matters for multi-axis dot-joined combinations. The master still keeps one `EcomVariantGroupProductRelation` row.
- Surface split: MCP `save_variant_groups` / `save_variant_options` create the vocabulary, but there is **no MCP surface** for the group→product relation or for the per-variant `EcomProducts` rows. `update_products` against a variant id that has no row yet fails with `Product not found` — it updates, never creates, variant language rows. The §2.5 SQL INSERT (copy master, override per-variant fields) is the proven path for both on local installs. On hosted/API-only installs the Management API chain covers the whole shape — `VariantGroupAdd` then `VariantCombinationSave` (which runs `ExtendAllVariants` to create the per-variant rows); see [`commerce-catalog.md`](commerce-catalog.md) §2.14 "Variants via the Management API (no SQL)" (validated DW 10.25.x).
- Set **`VariantOptionColor`** (hex) on the options and a Swift-style PDP `VariantSelector` renders live **color swatches** with zero template work.
- Per-variant `EcomProducts` gotchas beyond the §2.5 override list:
  - Copy **`ProductDefaultUnitId`** onto every variant row. Variants without it silently drop the per-unit price column from the quantity-break table — the master shows Qty / per-unit / per-piece, the variants show a narrower table, and it reads like a pricing bug even though prices never differed.
  - Seed **per-variant `ProductStock`**, and do it for **every language row** — variants default to 0 even when the master has stock.
  - Quantity-break `EcomPrices` rows with an empty `PriceProductVariantId` apply to **all** variants — no per-variant duplication needed.
- Restart the host before verifying — the PDP selector reads the product cache, so the variants don't show until the bounce. (No restart on a hosted install: bulk-flush the product/stock/price service caches instead — see [`cache-invalidation.md`](cache-invalidation.md).)

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
4. Bundles should get their OWN data model (e.g. a `BundleAttributes` category with bundle-specific fields: UnitsPerCase, RetailerSegment, PlanoReady, etc.). Different products → different data models.

### 2.8 Product Categories + Fields (data model internals)

- **Category** = row in `EcomProductCategory` + translation row in `EcomProductCategoryTranslation`. Categories are SOLUTION-GLOBAL — not scoped to shops.
- **Fields on a category** = rows in `EcomProductCategoryField` + translations in `EcomProductCategoryFieldTranslation`.
- **`reference_category` is load-bearing and easy to miss** — the hidden template category that powers every admin completeness/rule lookup, plus its blank-panel gotcha and seed SQL, lives in [`pim-completeness.md`](pim-completeness.md).
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

### 2.10 Assets

- Files live in `wwwroot/Files/Images/...` (or any `/Files/` subfolder).
- Product asset record = `EcomDetails` row:
  - `DetailProductId`, `DetailVariantId`, `DetailLanguageId`, `DetailType=0` (image), `DetailValue=<file path>`, `DetailIsDefault` (primary), `DetailsGroupId` (asset category numeric id — check `EcomDetailsGroup`)
- Asset categories = `EcomDetailsGroup` table. Default installs ship with at least `Images` (id=1). New categories (e.g. `Manuals` for PDFs) are SQL-only — no MCP tool exists for `EcomDetailsGroup` mutations. Insert into both `EcomDetailsGroup` (set `DetailsGroupExtensions` to filter file types, e.g. `'pdf'`, and `DetailsGroupDefaultUploadFolder` to the target path) AND `EcomDetailsGroupTranslation` (one row per language).
- MCP tools `add_product_image` / `import_product_images_from_urls` / `upload_product_images` handle both download-to-disk + DB row. **Plugin-only — no Management API endpoints back these.** They live entirely in the MCP plugin code path; if the MCP session dies (token expiry, plugin restart, host restart) there is no `POST /admin/api/...` fallback for asset registration. The fallback is direct SQL INSERT on `EcomDetails`.
- **Bulk SQL INSERT must set `DetailLanguageId` to a real language code** (e.g. `'LANG1'`), not empty string and not NULL. The admin asset query and the per-product image listings filter strict-equality on this column, so empty-string language renders the row invisible despite being on disk and registered. Symptom: SQL count says 9 details for the product, admin product page shows 0 assets, file is at the path. Recovery: `UPDATE EcomDetails SET DetailLanguageId = 'LANG1' WHERE DetailLanguageId = '' OR DetailLanguageId IS NULL;` then host restart to flush asset caches. The MCP tools always populate this column correctly — this gotcha only fires when bulk SQL inserts skip the field.
- After bulk SQL inserts, **restart the host** to flush the EcomDetails cache (same protocol as [`cache-invalidation.md`](cache-invalidation.md) covers for product mutations).

### 2.12 Dynamic Workspaces — projections, not storage

Dynamic Workspaces are the modern PIM workbench UI in DW10 — multi-level grouping built from a product query. They are **query-backed projections, not storage**: they don't move product rows, they show different slices of the catalog. The canonical product home is still `EcomGroupProductRelation` rows under a `ShopType=4` DataStructure shop; workspaces just project that home by attribute axes (data-model keys or product fields).

**Storage tables** (separate from `EcomShops` / `EcomGroups`):

| Table | Key | Purpose |
|---|---|---|
| `DynamicStructures` | GUID | One row per workspace — name + backing query GUID. |
| `DynamicStructureLevels` | GUID + ordered | Levels of the workspace tree. Each level has a `SourceField` (the axis) and a `LevelType` enum. |

Cite `Dynamicweb.Core/Indexing/DynamicStructuring/DynamicStructure.cs:24` (`public Guid Id { get; set; }`) and `DynamicStructureLevel.cs` for the level shape.

**Permission entity** — `PermissionName="DynamicStructure"`, key=Guid. Cite `Dynamicweb.Core/Indexing/DynamicStructuring/DynamicStructure.cs:43` (`private const string PermissionName = "DynamicStructure";`) and the `[PermissionEntity(PermissionName)]` attribute at line 12. The class implements `IPermissionEntity, IPermissionEntityLookup` (line 13). Cross-ref [`users-permissions.md`](users-permissions.md) for how this entity slots into the three-layer model.

**Level types** — `DataModelKey` or `ProductField`. Cite `Dynamicweb.Products.UI/Models/ProductCatalogs/DynamicStructureLevelTypes.cs` (2-value enum):

```csharp
public enum DynamicStructureLevelTypes { DataModelKey, ProductField }
```

A workspace level rooted on `DataModelKey` projects products by which DataModel group (GroupType=2) they're related to; a level rooted on `ProductField` projects by distinct values of a product field (e.g. Supplier, `ProductWorkflowStateId`).

**`UseRelationOnProductCreate` — the auto-attach mechanic.** Cite `Dynamicweb.Core/Indexing/DynamicStructuring/DynamicStructureLevel.cs:74` (`public bool UseRelationOnProductCreate { get; set; }`). When `true`, products created from inside the workspace UI are automatically attached to the source `DataModel` group via `EcomGroupProductRelation`. Without this flag, products created in a workspace are **orphans** — they exist in `EcomProducts` but have no group relation, so they appear only in "All products" and are invisible to every channel filter and every other workspace projection. The workspace's `DynamicStructureRepository` persists/reads the flag at lines 152, 170, 173, 201.

**License gate** — `LicenseManager.LicenseHasFeature("PIM")`. Cite `Dynamicweb.Products.UI/Tree/ProductCatalogsSection.cs:13` (class declaration, `Name = "Dynamic workspaces"`, `Sort = 20`) and line 36 (`public override bool ShouldShow() => LicenseManager.LicenseHasFeature("PIM");`). Without the PIM license feature, the entire Dynamic Workspaces section in the Products tree collapses; the navigation falls back to the legacy `ChannelNodeProvider` "All products" surface (see `ChannelNodeProvider.cs:60` — `nodes.Add(QueriesNodeProvider.CreateAllProductsNode());`).

**Mental model:** Dynamic Workspaces are *projections*, not *storage*. They're configurable, multi-level views over the product catalog backed by a query + level definitions. They do not own products — they project the catalog by attribute axes. The single mechanic that makes "creating in a workspace" feel like real storage is `UseRelationOnProductCreate=true` on the workspace's level: when set, the workspace owns the "auto-attach to the source DataModel group" behaviour on create. Without it, "create in workspace" produces orphan rows.

**When workspaces are the right answer:**
- "Show me products by **supplier**" — 1 level, `LevelType=ProductField`, `SourceField=Supplier`.
- "Show me products by **workflow state**" — 1 level, `LevelType=ProductField`, `SourceField=ProductWorkflowStateId`. Replaces a status dashboard for editors who live in the catalog tree.
- "Products by spec attribute" — 2 levels, both `LevelType=DataModelKey`, drilling category → sub-category.

**When workspaces are NOT the right answer:**
- Permission boundary. Workspaces are gated by the `/Products/DynamicWorkspaces` capability key (single on/off across all workspaces of that capability scope), not per workspace. Per-product permissions still come from group-level grants — see [`users-permissions.md`](users-permissions.md) for the full picture.
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

Then flush `ProductFieldService`, `ProductService`, `CompletionRuleService`, `PermissionService` and trigger a Full `BuildIndex` (see [`pim-completeness.md`](pim-completeness.md) "Recovery recipe: Rebuild Products index").

**Completion-rule regex note**: `EcomCompletionRules` uses a comma-separated SystemName list (`EcomCompletionRuleProductFields`), not regex. Rule "completeness" is a field-has-value check, not a pattern match. `EcomValidationRules` is a separate table for input-validation patterns and is independent — touch that only if a custom field carried a regex pattern (`FieldValidationPattern` on `EcomProductCategoryField`) that needs replicating on the standard.
