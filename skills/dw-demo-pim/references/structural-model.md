# structural-model.md

> The structural mental model for Dynamicweb 10 PIM. Read before modelling — getting any of these wrong causes rework. Loaded from `~/.claude/skills/dynamicweb-pim-demo/SKILL.md` "Where to find things" table. Each `### 2.x` sub-section cross-references siblings; do NOT split this file.

## The structural mental model

Getting any of these wrong causes rework. Each has burned me.

### 2.1 Shop types — one enum controls everything

`EcomShops.ShopType` (column) uses `Dynamicweb.Ecommerce.ShopType`:
- `0` None
- `1` **Shop** (commerce storefront / catalog root)
- `2` Warehouse
- `3` **Channel** (feed publishing target — Shopify, HD, EDI partners)
- `4` **DataStructure** (holds data models — NOT customer-facing)

**Rules:**
- **One Shop per brand/market** — don't create duplicates. If `mcp__dynamicweb-commerce-mcp__save_shops` fails to rename SHOP1, update directly: `UPDATE EcomShops SET ShopName = '...' WHERE ShopId = 'SHOP1'`.
- **Channels for feeds** — each external system (Shopify, HD, OrderEase, PackGenie) gets its own ShopType=3 shop with its own group tree. Products get related INTO those groups to control what the feed publishes.
- **DataStructure for data models** — a separate ShopType=4 shop owns the data model tree. Never park data models under the commerce shop.
- **EVERY shop needs a language relation** — insert into `EcomShopLanguageRelation(ShopId, LanguageId, IsDefault)`. Missing this causes "channel with no name" display in admin.

**Where each ShopType appears in admin nav**:

| ShopType | Admin tree section | Source |
|---|---|---|
| 1 (Shop) | Channels (icon: shop) | `Dynamicweb.Products.UI/Tree/ChannelNodeProvider.cs` `GetCatalogShops()` lines 66-74 — filters `UsageType is ShopType.Shop or ShopType.Channel` |
| 3 (Channel) | Channels (icon: code-branch) | same — sibling of Shop in the same filter |
| 4 (DataStructure) | Data models | `Dynamicweb.Products.UI/Tree/StructureNodeProvider.cs` `GetShopsAsDataStructure()` lines 245-262 — filters `UsageType == ShopType.DataStructure` |

So in the admin tree, a `ShopType=1` Shop and a `ShopType=3` Channel sit side-by-side in the **Channels** section (different icon, same tree); only `ShopType=4` shops appear under **Data models**. There is no separate "PIM root" concept — trying to build one fights the UI.

**`ProductActive` vs `EcomGroupProductRelation` for visibility gating.** `ProductActive` is a binary all-or-nothing toggle — when the Products index is built with `OnlyIndexActiveProducts=true` (see `Dynamicweb.Ecommerce/Indexing/ProductIndexBuilder.cs:102,277` — `"AND ProductActive = 1"`), `ProductActive=0` rows are excluded from the entire index, killing them in every channel AND every PIM dashboard. For **per-channel** visibility — "online on the webshop, offline on the marketplace" — use `EcomGroupProductRelation` rows scoped per Channel group (i.e. fire the native "Publish to channel" action, §2.3a, or remove a single channel's relation). `ProductActive=0` is for "this product is gone from EVERYWHERE" (discontinuation); `EcomGroupProductRelation` removal is for "this product is gone from THIS channel". Don't conflate them.

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
- **Every DataModel group needs `ProductCategoryId`** pointing at a CategoryFields category (e.g. `PlantAttributes`) — that's how field values get plumbed to the product.

### 2.3 Catalog vs Channel group trees (the published-to story)

Each Channel (ShopType=3) has its OWN group tree. Products are published to a channel by creating a `EcomGroupProductRelation` row linking the product to one of the channel's groups. Do NOT:
- Link the same catalog groups to multiple shops via `EcomShopGroupRelation` (this broke my demo — shared groups show products under every shop)
- Attach channels directly to the main catalog groups

Do:
- Each channel has its own groups (e.g. `G-SHOP-INDOOR` under `CH-SHOPIFY`, `G-HD-HOUSEPLANTS` under `CH-HOMEDEPOT`)
- Use `INSERT...SELECT` to bulk-populate channel groups from catalog groups
- Products live in 1+ catalog group (under SHOP1) AND 1+ channel group per channel they're published to

**Group URL slug gotcha — `ShopUrlDataProvider` lazy cache.** When a Swift frontend uses path-based group URLs (e.g. `/swift-2/shop/headsets`), the resolver is `Dynamicweb.Ecommerce.Frontend.UrlHandling.ShopUrlDataProvider`'s static `Lazy<>` indexes (`InitializeProductUrlDataIndex`, `InitializeGroupProductRelationIndex`). Those indexes are populated at first request and only reset when `Notifications.Ecommerce.Group.AfterSave` fires — which fires from MCP `save_groups` and admin-UI saves but NOT from raw `UPDATE EcomGroups SET GroupMetaUrl = ...` SQL. Symptom: SQL-set slugs work in the DB, but `/shop/<slug>` 404s indefinitely until the host restarts OR a group is re-saved through MCP. Index rebuild via `/admin/api/BuildIndex` does NOT flush this — it's separate from Lucene. Recovery after raw-SQL changes to GroupMetaUrl / GroupNumber / any field used by URL resolution: re-save one group through `mcp__dynamicweb-commerce-mcp__save_groups` (idempotent — same payload pattern, same id), or restart the host.

**Same cache-flush rule applies to `EcomGroupProductRelation` mutations** — fired via the native "Publish to channel" action (§2.3a below): `Notifications.Ecommerce.Group.AfterSave` fires, cache flushes, channel URLs resolve immediately. Fired via raw SQL `INSERT INTO EcomGroupProductRelation`: notification doesn't fire, cache stays stale until host restart. See §2.3a and `cache-invalidation.md`.

### 2.3a Publishing products: native "Publish to channel" action

The DW10 admin ships a built-in action that is the **only supported way** to move a product from "in PIM" to "in a channel". Until this action fires (or its single-product equivalent), a product is invisible to every publish target — feeds, storefront templates, channel-group filters all return zero rows for it.

**Bulk variant** — cite `Dynamicweb.Products.UI/Screens/ProductListScreen.cs` `GetPublishToChannelDataNode()` at lines 726-743. Wired into the bulk Product List screen at lines 415-421 alongside `GetAddToDataModelActionNode()` and `GetAddToDataSetActionNode()`, gated on `LicenseManager.LicenseHasFeature("PIM")`:

```csharp
NodeAction = ProductListHelper.GetGroupSlideOverSelectorAction(
    showShops: true,
    showChannels: true,
    showWarehouses: false,
    confirmLabel: "Publish product?",
    confirmMessage: "Do you want to publish products to selected groups?",
    multiSelect: true,
    query: Query
),
PermissionLevelRequired = PermissionLevel.Edit
```

**Single-product variant** — same file, second `yield return new()` at line 370 (`Name = "Publish to channel"`, `Icon = Icon.CodeBranch`), surfaced from the per-product action row. Same flags (`showShops: true, showChannels: true, showWarehouses: false`), same permission level, scoped to the one product via `productIds: [model.GetId()]`.

**Behaviour:**
- Slide-over selector shows Shop (ShopType=1) AND Channel (ShopType=3) groups together — user picks any combination.
- Multi-select target groups → one `EcomGroupProductRelation` row created per selected group.
- **Purely additive** — does NOT remove existing relations. To un-publish from a channel, delete the relation row directly.
- Requires `PermissionLevel.Edit` on the products being published.

**When to use this vs raw SQL `INSERT INTO EcomGroupProductRelation`:**

| Path | `Notifications.Ecommerce.Group.AfterSave` fires? | `ShopUrlDataProvider` lazy cache | When to use |
|---|---|---|---|
| Native "Publish to channel" action | Yes | Flushes immediately → URLs work | The default. Use whenever the demo storyline shows an editor publishing a product. |
| MCP `save_groups` / admin-UI group save | Yes | Flushes | When seeding groups; relation INSERTs go through the same path. |
| Raw SQL `INSERT INTO EcomGroupProductRelation` | No | Stays stale until host restart | Bulk seeding scripts only — and remember to restart the host or re-fire a `save_groups` notification before verifying URLs. |

Cross-ref `cache-invalidation.md` for the full notification-vs-host-restart matrix and the §2.3 group URL slug gotcha above.

### 2.4 Repositories, Indexes, and Queries — file-based

- **Repository** = folder under `wwwroot/Files/System/Repositories/<RepoName>/`
- **Index** = `.index` XML file inside the repo folder (build via management API `POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full"}`)
- **Queries** = `.query` XML files with `<Query ID="guid">` and `<Source Repository="..." Item="..." />`. Query placement rules are SUBTLE:
  - Queries used by **feeds** (`EcomFeed.FeedIndexQueryId`) must live DIRECTLY in the repository root folder: `wwwroot/Files/System/Repositories/<RepoName>/*.query`. **Subfolders are NOT scanned for feed resolution** — admin will show "query does not exist" on the feed if the .query file is in a subfolder.
  - Queries used by **dashboards/widgets** (referenced by GUID) must live in `wwwroot/Files/System/SmartSearches/Ecommerce/Shared/` (or a subfolder of it) — **never GUID-duplicated to `Repositories/<RepoName>/<subfolder>/`**. GUID-collision mechanism + recovery: [governance.md](governance.md) "Dashboard query location — Shared ONLY".
  - Admin "Queries" UI under Products → Queries → Shared queries shows all queries in the SmartSearches/Shared tree. Feed queries are visible in a separate Repository-based surface (Settings → Integration → Repositories → Products).
  - Rule of thumb: **feed-backing queries → `Files/System/Repositories/<RepoName>/` root. Dashboard-backing queries → `Files/System/SmartSearches/Ecommerce/Shared/` only. Never both.**
- Product index builder: `Dynamicweb.Ecommerce.Indexing.ProductIndexBuilder, Dynamicweb.Ecommerce`. Instances use `Dynamicweb.Indexing.Lucene.LuceneIndexProvider`.
- **Hand-author the index — do NOT copy `ProductsBackend/Products.index` or `ProductsFrontend/Products.index` from the github Swift repo.** Those reference Swift's bike-demo custom fields (`PlantHardiness`, `BikeFrameSize`, plant/bike facets, etc.) that fail to build against any other product catalogue with `field not found in products` (the index builder validates every field reference against `EcomProductCategoryField`). The Swift content baseline at `$env:DW_VAULT\serialized-data\Swift2.2\` is content-only and ships no Repositories tree — there's nothing to copy from there either. For a hybrid PIM-data + Swift-frontend demo: hand-write the `.index` listing only standard product fields plus 5-10 demo-relevant `ProductCategory|<Cat>|<FieldId>` per category — not the full custom-field set. Use `ProductIndexBuilder.DefaultSettings` in the dw10 source as the structural template.
- **Name-attribute gotcha:** the `<Index Name="..."/>` attribute inside `Products.index` MUST equal the file name **including the `.index` extension** — i.e. `Name="Products.index"`, not `Name="Products"`. The error on mismatch is the misleading `"Index file not found: ...\Products"` even though the file IS at `...\Products.index`; the Lucene resolver uses the `Name` attribute as the lookup key.
- **`ProductIndexSchemaExtender` is load-bearing — a hand-written index without it builds successfully and serves zero hits.** The default DW catalog frontend resolves products via `ProductQueryHelper.GetProductsAutoIdsFromIndexQuery`, which expects a battery of stock fields (`AutoID`, `LanguageID`, `ParentGroupIDs`, `ShopIDs`, `Active`, `freetext`, `ProductName_Search`, `Manufacturer_Facet`, `PriceRange`, etc.). If your `<Fields>` block lists only your demo-specific custom fields, **every PLP / PDP throws `System.ArgumentOutOfRangeException: numHits must be > 0` from `Lucene.Net.Search.TopScoreDocCollector.Create`** — `BuildIndex` returns `state=success` and the Lucene segment files on disk are 53 bytes (empty). With the extender wired, the segment grows to hundreds of KB for the same product count. Inline the extender inside `<Schema><Fields>` so the builder auto-injects the stock catalog fields alongside your custom ones:

  ```xml
  <Schema>
    <Fields>
      <Extension Type="Dynamicweb.Ecommerce.Indexing.ProductIndexSchemaExtender, Dynamicweb.Ecommerce" />
      <!-- your 5-10 demo-specific ProductCategory|<Cat>|<FieldId> fields here -->
    </Fields>
  </Schema>
  ```

  Then rebuild: `POST /admin/api/BuildIndex {Repository:Products, IndexName:Products.index, BuildName:Full, BuildType:Full}`. **Symptom check:** if PLP/PDP render `numHits must be > 0` and the index built `state=success`, this is the cause — not a missing query file, not a missing `Products.query`, not a paragraph misconfiguration. The data on disk is the diagnostic: a healthy Products index segment is ~270 KB at 30 docs; 53 bytes means the schema accepted zero documents.
- MCP `create_or_update_product_queries` saves `.query` XML but leaves `<Source Repository="" Item="" />` empty — fix via `sed` or patch the file before index build.
- Rebuild the index after ANY product/group/channel mutation.

### 2.5 Variants — 3 tables, composite IDs

A variant on a hero product is NOT a single row. It needs:

1. **`EcomVariantGroups`** + **`EcomVariantOptions`** (the dimension vocabulary — e.g. Pot Size → 9/12/17 cm)
2. **`EcomVariantGroupProductRelation`** — links variant groups to a product. One row per (product, group).
3. **`EcomVariantOptionsProductRelation`** — the combinations. VariantId is the dot-joined option IDs: `VO1.VO4` = first option of group 1 AND first option of group 2 (see `VariantCombinationService.cs:221`).
4. **`EcomProducts`** row per variant — copies master's 60+ columns but overrides `ProductVariantId` (same as step 3), `ProductNumber` (**must be unique per variant** — master `ProductNumber` + dash + short suffix derived from the variant option ids; e.g. master `CKT-OAK-HERIT` → `CKT-OAK-HERIT-CHAMP`, `-IVORY`, `-BLUE`), `ProductActive=1`. Without this row, variants exist but are inactive with no SKU label.

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
- Surface split: MCP `save_variant_groups` / `save_variant_options` create the vocabulary, but there is **no MCP surface** for the group→product relation or for the per-variant `EcomProducts` rows. `update_products` against a variant id that has no row yet fails with `Product not found` — it updates, never creates, variant language rows. The §2.5 SQL INSERT (copy master, override per-variant fields) is the proven path for both on local installs. On hosted/API-only installs the Management API chain covers the whole shape — `VariantGroupAdd` then `VariantCombinationSave` (which runs `ExtendAllVariants` to create the per-variant rows); see [`dynamicweb-demo-base/references/online-mode.md`](../../dw-demo-base/references/online-mode.md) §"Variants without SQL" (validated DW 10.25.x).
- Set **`VariantOptionColor`** (hex) on the options and Swift's PDP `VariantSelector` renders live **color swatches** with zero template work.
- Per-variant `EcomProducts` gotchas beyond the §2.5 override list:
  - Copy **`ProductDefaultUnitId`** onto every variant row. Variants without it silently drop the per-unit price column from Swift's quantity-break table — the master shows Qty / per-unit / per-piece, the variants show a narrower table, and it reads like a pricing bug even though prices never differed.
  - Seed **per-variant `ProductStock`**, and do it for **every language row** — variants default to 0 even when the master has stock.
  - Quantity-break `EcomPrices` rows with an empty `PriceProductVariantId` apply to **all** variants — no per-variant duplication needed.
- Restart the host before verifying — the PDP selector reads the product cache, so the variants don't show until the bounce. (No restart on a hosted install: bulk-flush the product/stock/price service caches instead — `dynamicweb-demo-base/references/online-mode.md` §"Cache refresh = the online host restart".)

### 2.6 Bundles (BOM) — two concerns

1. **Product is BOM** — `UPDATE EcomProducts SET ProductType = 2` (enum: 0=stock, 1=service, 2=bom, 3=giftcard).
2. **Components** — rows in `EcomProductItems`:
   - `ProductItemProductId` = parent bundle
   - `ProductItemBomProductId` = component product
   - `ProductItemQuantity`, `ProductItemName`, `ProductItemRequired`, `ProductItemSortOrder`
   - `ProductItemBomGroupId` = optional (for configurable groups where customer picks)
3. **RESTART THE HOST AFTER INSERTING PRODUCTITEMS** — `ProductItem` uses a `Lazy<Dictionary<...>>` cache (see `ProductItem.cs:145`). Raw SQL inserts bypass it. Until restart, the Bundles tab shows empty.
4. Bundles should get their OWN data model (e.g. `BundleAttributes` category with bundle-specific fields: UnitsPerCase, RetailerSegment, PlanoReady, etc.). Different products → different data models.

### 2.7 Channels + Feeds

- **Channel** = `EcomShops` row with `ShopType=3`. Has its own group tree + language relation + (optional) `ShopIndexRepository`+`ShopIndexName` for the feed's index source.
- **Feed** = `EcomFeed` row pointing at a Channel + Query + Provider:
  - `FeedChannelId` = Channel's ShopId
  - `FeedIndexQueryId` = query GUID (from the `.query` file's `<Query ID="...">`)
  - `FeedSource=2` (Index) — for index-based feeds
  - `FeedProvider` = `Dynamicweb.Ecommerce.Feeds.TemplateProvider` (for Razor .cshtml → JSON/CSV/HTML) OR `Dynamicweb.Ecommerce.Feeds.XMLProvider` (for XML/XSLT)
  - `FeedProviderConfiguration` = XML with parameters: `<Parameters><Parameter Name="Template" Value="Feeds/my-template.cshtml" /><Parameter Name="Content Type" Value="application/json" /></Parameters>` for Template, or `<Parameters><Parameter Name="XSLT Stylesheet" Value="Feeds/my.xslt" /></Parameters>` for XML.
- **Template path resolution** — `TemplateProvider` expects paths relative to `wwwroot/Files/Templates/Feeds/`. `XMLProvider` expects XSLT in same folder.
- Feed template example for Razor: `@inherits ViewModelTemplate<Dynamicweb.Ecommerce.ProductCatalog.ProductListViewModel>` + `@Model.Products` iteration. Field values are accessed via `ProductCategories[].Fields[categoryFieldId].Value`.

### 2.8 Product Categories + Fields (data model internals)

- **Category** = row in `EcomProductCategory` + translation row in `EcomProductCategoryTranslation`. Categories are SOLUTION-GLOBAL — not scoped to shops.
- **Fields on a category** = rows in `EcomProductCategoryField` + translations in `EcomProductCategoryFieldTranslation`.
- **`reference_category` is load-bearing and easy to miss**: Dynamicweb uses a hidden "template" category `reference_category` (`CategoryType=2`) to power every admin UI rule/completeness lookup. You need two one-time rows per DATABASE (steps 1-2) plus four rows per FIELD (steps 3-5; step 5 is two translation rows) to be complete:
  1. The parent `EcomProductCategory` row for `reference_category` with `CategoryType=2` (seed ONCE per database)
  2. The parent `EcomProductCategoryTranslation` row for `reference_category` (also once per database, per language)
  3. One `EcomProductCategoryField` row with `FieldCategoryId='reference_category'` (mirror of the concrete field)
  4. One `EcomProductCategoryField` row in the concrete category (e.g. `<CategoryName>Attributes`)
  5. Both translations in `EcomProductCategoryFieldTranslation` (one for the mirror, one for the concrete field)
  Missing step 1 causes the most-misleading failure in DW: rules validate, assignments persist, API returns correct data, but the product/group completeness panels in admin render empty. See `governance.md` "Completeness rules" section for the SQL.
- **List field options** = `EcomFieldOption` (FieldOptionId, FieldOptionFieldId, FieldOptionName, FieldOptionValue, FieldOptionIsDefault, FieldOptionSort). Scoped to field, not category.
- **Field values on products** = `EcomProductCategoryFieldValue` (FieldValueFieldId, FieldValueFieldCategoryId, FieldValueProductId, FieldValueProductVariantId, FieldValueProductLanguageId, FieldValueValue). One row per (product, field).
- **Custom field system names** in MCP use format `ProductCategory|<CategoryId>|<FieldId>` for category fields, plain FieldId for global product fields. Use this SAME format in completeness rule field lists and in product query `FieldExpression` attributes.

### 2.9 Assortments (customer access) ≠ Channels (publishing)

- **Assortments** = `EcomAssortments` + `EcomAssortmentItems` — restrict which products logged-in customers see. Scoped by UserGroup permissions via `EcomAssortmentPermissions` / `EcomAssortmentUserRelation`.
- **Channels/Feeds** = the publishing target (see §2.7).
- Don't model Shopify/HomeDepot/EDI as assortments — they're Channels. Assortments are purely B2B customer visibility.

### 2.10 Assets

- Files live in `wwwroot/Files/Images/...` (or any `/Files/` subfolder).
- Product asset record = `EcomDetails` row:
  - `DetailProductId`, `DetailVariantId`, `DetailLanguageId`, `DetailType=0` (image), `DetailValue=<file path>`, `DetailIsDefault` (primary), `DetailsGroupId` (asset category numeric id — check `EcomDetailsGroup`)
- Asset categories = `EcomDetailsGroup` table. Default installs ship with at least `Images` (id=1). New categories (e.g. `Manuals` for PDFs) are SQL-only — no MCP tool exists for `EcomDetailsGroup` mutations. Insert into both `EcomDetailsGroup` (set `DetailsGroupExtensions` to filter file types, e.g. `'pdf'`, and `DetailsGroupDefaultUploadFolder` to the target path) AND `EcomDetailsGroupTranslation` (one row per language).
- MCP tools `add_product_image` / `import_product_images_from_urls` / `upload_product_images` handle both download-to-disk + DB row. **Plugin-only — no Management API endpoints back these.** They live entirely in the MCP plugin code path; if the MCP session dies (token expiry, plugin restart, host restart) there is no `POST /admin/api/...` fallback for asset registration. The fallback is direct SQL INSERT on `EcomDetails`.
- **Bulk SQL INSERT must set `DetailLanguageId` to a real language code** (e.g. `'LANG1'`), not empty string and not NULL. The admin asset query and the per-product image listings filter strict-equality on this column, so empty-string language renders the row invisible despite being on disk and registered. Symptom: SQL count says 9 details for the product, admin product page shows 0 assets, file is at the path. Recovery: `UPDATE EcomDetails SET DetailLanguageId = 'LANG1' WHERE DetailLanguageId = '' OR DetailLanguageId IS NULL;` then host restart to flush asset caches. The MCP tools always populate this column correctly — this gotcha only fires when bulk SQL inserts skip the field.
- After bulk SQL inserts, **restart the host** to flush the EcomDetails cache (same protocol as `cache-invalidation.md` covers for product mutations).

### 2.11 Pricing — tier rows are NOT honored by the stock cart

`EcomPrices` ships a `PriceQuantity` column that *looks* like quantity-break tier pricing — and the Dynamicweb documentation reinforces that read ("Customers receive the best applicable price for their order volume"). In practice the stock DW10 cart-line-add resolver picks the matching `PriceQuantity = 0` row first and stops. Tested with rows fully unscoped (no user group, no customer number, no shop scoping) — still doesn't honor qty breaks. Confirmed against the cart pricing path; the PDP price-tier *display* table works, the *cart charge* does not.

**Surface-independence — this is the platform, not the surface.** This gotcha fires the same regardless of whether the tier rows were inserted via:
- MCP `save_prices` / `create_or_update_prices`
- Management API
- Direct SQL `INSERT INTO EcomPrices`
- Admin UI

Switching surfaces will not fix it; the resolver is the same downstream code path. If the symptom is "I added a quantity-5 tier row but the cart charges base price for 10 units", **stop debugging the insert — the insert is fine, the resolver doesn't read it**. Same applies in reverse: if you have unrelated cart-pricing weirdness, do NOT assume tier rows are causing it — they're silently ignored, not malfunctioning.

**Production pattern (vendor-recommended).** Per the Dynamicweb vendor architect (architecture call): for B2B demos that need real qty-break behavior, the canonical DW10 production pattern is ERP integration that imports per-user *pre-graduated* prices — one row per (product, user, qty-band) with the resolved price already baked in. The cart resolver then picks the correct pre-graduated row by user-group scope. This shifts the qty-band logic out of DW into the ERP. For demos that explicitly want to show the DC-aware / customer-group-aware pricing beat, this is the pattern to scaffold (see `dynamicweb-swift-demo` DC pattern for the user-group side).

**Escape hatch for demos that need cart-time qty-break math.** Implement a custom `Dynamicweb.Ecommerce.Prices.IPriceProvider` in `Providers/*.cs` (the customisations-ledger preflight applies per [`dynamicweb-demo-base/references/customisations.md`](../../dw-demo-base/references/customisations.md)) that consults `EcomPrices` rows with `PriceQuantity > 0` and returns the best matching row. Worth doing only when the demo's storyline lands on a "watch the price drop as the buyer adds units" beat that ERP-pre-graduated rows can't tell.

**Demo workaround (no-customisation).** Keep the tier rows in `EcomPrices` so the PDP tier table still renders, and surface the limitation in the demo cheat-sheet — "tier prices are illustrative; cart shows base price". The pattern: a per-demo `Swift-v2_ProductPrice.cshtml` variant reads the tier rows directly via a bypassed SQL path to render the table, while the cart honors the base row at checkout. Acceptable for demos that don't make qty-break-at-cart-time the closing beat.

**This gotcha is misleading precisely because** the docs say it works and the rows look correct in the admin pricing matrix. If you see "tier price not applied at cart", the answer is in this section, not in the data.

### 2.12 Dynamic Workspaces — projections, not storage

Dynamic Workspaces are the modern PIM workbench UI in DW10 — multi-level grouping built from a product query. They are **query-backed projections, not storage**: they don't move product rows, they show different slices of the catalog. The canonical product home is still `EcomGroupProductRelation` rows under a `ShopType=4` DataStructure shop; workspaces just project that home by attribute axes (data-model keys or product fields).

**Storage tables** (separate from `EcomShops` / `EcomGroups`):

| Table | Key | Purpose |
|---|---|---|
| `DynamicStructures` | GUID | One row per workspace — name + backing query GUID. |
| `DynamicStructureLevels` | GUID + ordered | Levels of the workspace tree. Each level has a `SourceField` (the axis) and a `LevelType` enum. |

Cite `Dynamicweb.Core/Indexing/DynamicStructuring/DynamicStructure.cs:24` (`public Guid Id { get; set; }`) and `DynamicStructureLevel.cs` for the level shape.

**Permission entity** — `PermissionName="DynamicStructure"`, key=Guid. Cite `Dynamicweb.Core/Indexing/DynamicStructuring/DynamicStructure.cs:43` (`private const string PermissionName = "DynamicStructure";`) and the `[PermissionEntity(PermissionName)]` attribute at line 12. The class implements `IPermissionEntity, IPermissionEntityLookup` (line 13). Cross-ref `permissions-model.md` for how this entity slots into the three-layer model.

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
- "Mobility products by spec attribute" — 2 levels, both `LevelType=DataModelKey`, drilling category → sub-category.

**When workspaces are NOT the right answer:**
- Permission boundary. Workspaces are gated by the `/Products/DynamicWorkspaces` capability key (single on/off across all workspaces of that capability scope), not per workspace. Per-product permissions still come from group-level grants — see the parallel `permissions-model.md` for the full picture.
- Originating products without a catalog group. Without `UseRelationOnProductCreate=true` on at least one level, the workspace's "Create product" UI produces orphans.

Cite source files (all under `dw10source/src/Core/Dynamicweb.Core/Indexing/DynamicStructuring/`):
- `DynamicStructure.cs` — entity (Guid key, `PermissionName="DynamicStructure"`, line 43)
- `DynamicStructureLevel.cs` — level + `UseRelationOnProductCreate` (line 74)
- `DynamicStructureLevelScope.cs` — runtime level recognition (value-based)
- `DynamicStructureRepository.cs` — persistence
- `DynamicStructureService.cs` — service layer

Plus `Dynamicweb.Products.UI/Models/ProductCatalogs/DynamicStructureLevelTypes.cs` (level type enum) and `Dynamicweb.Products.UI/Tree/ProductCatalogsSection.cs` (license gate + admin tree section).


