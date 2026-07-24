# canonical-setup-order.md

## Contents

- [0. Setup-order variants](#0-setup-order-variants)
- [1. Canonical setup order (Variant A — Storefront-first)](#1-canonical-setup-order-variant-a--storefront-first)
- [Product-completeness checklist — verify before declaring catalog done](#product-completeness-checklist--verify-before-declaring-catalog-done)
- [Appendix: commerce-side order seeding (used by Swift customer-center demos)](#appendix-commerce-side-order-seeding-used-by-swift-customer-center-demos)

> The canonical setup order for a Dynamicweb 10 PIM build. Each step depends on earlier ones — skipping or reordering causes rework. Loaded from `~/.claude/skills/dynamicweb-pim-demo/SKILL.md` "Where to find things" table. Cross-references out to `structural-model.md`, `governance.md`, `cache-invalidation.md`, `workflow.md`, `permissions-model.md`.

**ID discipline for every MCP `create_*` / `save_*` step below:** the PIM catalogue tools **auto-assign entity IDs and ignore IDs you pass in** — a requested variant-group id comes back as an auto-generated one, and a partial create can surface as a `JsonException` from the tool. Capture `items[].id` from every create/save response and key all subsequent steps off the captured ids, never the requested ones. On a failed or repeated run, clean up (or rebuild from) the auto-IDed leftovers before re-running — a blind re-run stacks duplicate, mis-IDed entities.

## 0. Setup-order variants

Two shapes — pick before you start. Storefront-first is the legacy full order (§1 below). PIM-first is a leaner order; it drops the `ShopType=1` SHOP1 + catalog-group tree and routes everything through `SHOP-DATA` (ShopType=4) + Dynamic Workspaces + Channels (ShopType=3).

### Decision matrix

| Signal | Variant A (Storefront-first) | Variant B (PIM-first) |
|---|---|---|
| Demo has a storefront (Swift baseline) | YES | NO |
| Products need to render publicly | YES | NO (publish later, if at all) |
| Customer pitch is "PIM as the single source" | NO | YES |
| Workflow + Dynamic Workspaces are central beats | sometimes | YES |
| `ShopType=1` shop needed | YES | NO (skip) |

The two variants share their spine: currencies/countries/languages, reference_category seed, EcomProductCategory + completeness rules, products, Products.index + `ProductIndexSchemaExtender`, BuildIndex Full, FINAL INDEX REBUILD. The deltas are at the start (whether SHOP1 exists) and at the channel/workflow/workspace/permission steps.

### 0.A Storefront-first

Use the order in §1 below as-is. SHOP1 (ShopType=1) is the anchor; SHOP-DATA owns the taxonomy; Channels (ShopType=3) publish from SHOP1's catalog groups. Most Swift-baseline demos land here.

### 0.B PIM-first

No `ShopType=1` shop. Products live on `EcomGroupProductRelation` rows under `SHOP-DATA` (ShopType=4) only until step 17 fires the native "Publish to channel" action. Empty Groups/Channels tab on the product page = visible signal "in PIM, in no channel" (see `structural-model.md` §2.2).

1. **Currencies, Countries, Languages** — `save_currencies`, `save_countries`; LANG1 = en-US. PriceContext needs a non-null Country entity — seed US if absent. Same as Variant A step 1.
2. **(skipped — no SHOP1)** — Variant A's SHOP1 rename + language relation does not apply. The Channels admin tree shows ShopType=1 OR 3 (`ChannelNodeProvider.GetCatalogShops`); without SHOP1, Channels lists only the ShopType=3 rows from step 13.
3. **Units, Manufacturers** — `save_units`, `save_manufacturers`. Same as Variant A step 4.
4. **DataStructure shop SHOP-DATA** (ShopType=4) + `EcomShopLanguageRelation(SHOP-DATA, LANG1, IsDefault=1)`. This is the canonical taxonomy + product home — no PIM Shop is needed beyond it. See `structural-model.md` §2.1 for the ShopType enum.
5. **Nested DataModelFolder (GroupType=1) + DataModel (GroupType=2) taxonomy** under SHOP-DATA. Folders are structural-only; DataModel leaves carry `ProductCategoryId` pointing at the attribute bundle. See `structural-model.md` §2.2.
6. **Seed `reference_category`** — parent `EcomProductCategory` row (`CategoryType=2`) + translation BEFORE any fields. Same load-bearing seed as Variant A step 6. See `governance.md` "Completeness rules" for the SQL.
7. **EcomProductCategory rows + fields** — the actual attribute bundles per DataModel leaf, with fields plumbed into BOTH `reference_category` and the concrete category (both with translations). See `structural-model.md` §2.8 for the four-row mechanic.
8. **Completeness rules + group assignments** — `create_or_update_completeness_rules` + `assign_completion_rules_to_groups`. NEVER via raw SQL unless restarting host (cache). See `cache-invalidation.md`.
9. **Products** — `create_products` via MCP. Attach to DataModel groups only (no Channel relations yet). `ProductActive=1` from day one; channel visibility is gated by `EcomGroupProductRelation` rows, NOT by `ProductActive`. See `structural-model.md` §2.1 callout on ProductActive-vs-relations. **`create_products` ignores `languageId`** — products land on the default (master) language; if this demo publishes to a non-default-language storefront, translate/repoint them or they render invisible (see [`localization.md`](localization.md) "create_products ignores languageId").
10. **Relate products to data model groups** — `assign_data_model_to_products` creates `EcomGroupProductRelation` rows to the DataModel group (this is how fields flow to the product). At this point the product is visible in All products, Data models tree, and any Dynamic Workspace whose query matches; invisible to every channel.
11. **Enrich + Assets + Variants + BOM** — `patch_products_safe`, `import_product_images_from_urls`, variant combinations + unique per-variant `ProductNumber`, `EcomProductItems` for bundles. **RESTART HOST AFTER BOM** to refresh ProductItem cache. Same as Variant A steps 12-15; see §1 below for the variant-`ProductNumber` regression rule (`structural-model.md` §2.5).
12. **Workflow definition** — insert `Workflow` row + `WorkflowState` rows (e.g. Draft / Ready / Published) + `WorkflowGoToState` graph + `WorkflowNotification` recipients. Attach to the top-level DataModelFolder via `EcomGroups.GroupWorkflowId` — inheritance cascades to every product under any descendant DataModel. See `workflow.md` for schema, the `ProductWorkflowStateChangedSubscriber`, and the per-state role-gating workarounds (DW10 workflow is permission-blind by default).
13. **Dynamic Workspaces** — insert `DynamicStructures` + `DynamicStructureLevels` rows with `UseRelationOnProductCreate=true` so products created from the workspace auto-attach to the source DataModel group. Levels source = `DataModelKey` or `ProductField` (e.g. `ProductWorkflowStateId` for a state-grouped Inbox). License-gated on `LicenseHasFeature("PIM")`. See `structural-model.md` §2.12.
14. **Channels** — one or more `EcomShops(ShopType=3)`, EACH with its OWN group tree + language relation. **Do NOT share catalog groups across Channels** (existing rule, `structural-model.md` §2.3).
15. **Products.index** — hand-write from `ProductIndexBuilder.DefaultSettings`. `Name="Products.index"` (including extension — Lucene resolver gotcha). **Inline `ProductIndexSchemaExtender`** inside `<Schema><Fields>` — load-bearing; without it BuildIndex returns success on an empty segment and every PLP throws `numHits must be > 0`. Full XML + symptom list: `structural-model.md` §2.4.
16. **BuildIndex Full** — `POST /admin/api/BuildIndex {Repository:Products, IndexName:Products.index, BuildName:Full, BuildType:Full}`. Healthy segment is hundreds of KB; 53 bytes = schema accepted zero documents. **An index-level `State=Warning` caused solely by an unbuilt secondary balancer instance is a false alarm** — the index reports Warning while a second (balancer/replica) instance sits `NeverBuilt`, even though the primary instance built cleanly. Judge success by the **primary instance's build result + doc count** (a fresh `LifecycleState=Completed` with the expected document count), not by the index-level Warning. Don't chase it as a failure; see [`../../dw-demo-base/references/foundational/search-indexing.md`](../../dw-demo-base/references/foundational/search-indexing.md) for the build-status contract.
17. **Permissions** — scope per-role via `UnifiedPermission` entries on the Shop / Group / Product / DynamicStructure / Workflow keys. With `CapabilityControlFeature` ON (DW10.21+), Layer B (capability keys like `/Products/DynamicWorkspaces`) gates UI-section visibility; Layer C (entity keys) gates per-row access. With it OFF, the legacy `PermissionSection("Products")` cascade applies. See `permissions-model.md` for the three-layer model and `permissions-recipes.md` for the role-matrix + grant-seeding SQL.
18. **Smoke-test publish** — pick one product, fire the native "Publish to channel" action from the bulk Product List screen (multi-select target Shop + Channel groups, `PermissionLevel.Edit`, additive `EcomGroupProductRelation` rows). Verify rows created + `ShopUrlDataProvider` lazy cache flushed (the native action triggers `Notifications.Ecommerce.Group.AfterSave`; raw SQL does NOT — restart host if you bypass the action). See `structural-model.md` §2.3a.
19. **Dashboard widgets** — `RepositoryCountWidget` per workflow state (e.g. Draft / Ready / Published / Offline), keyed on `ProductWorkflowStateId`. Prefer `RepositoryCountWidget` / `RepositoryGridWidget` over scalar SQL widgets for drill-through. See `governance.md` "Dashboard query location".
20. **FINAL INDEX REBUILD** after all mutations. Same as Variant A step 24.

(Step count varies — the spine merges steps 11's enrich/assets/variants/BOM into one bullet vs Variant A's four; the actual storage mutations are equivalent.)

## 1. Canonical setup order (Variant A — Storefront-first)

1. **Currencies, Countries, Languages** — `save_currencies`, `save_countries`; languages usually pre-seeded (LANG1 = en-US). PriceContext needs a non-null Country entity — seed US if it isn't already.
2. **Keep SHOP1** — rename via `UPDATE EcomShops SET ShopName` if save_shops is perm-blocked. If you instead create a storefront shop through `ShopSave`, set `UsageType=shop` explicitly — the API default `ShopType=0` (none) hides the shop from every typed admin list (see [`../../dw-demo-base/references/foundational/commerce-catalog.md`](../../dw-demo-base/references/foundational/commerce-catalog.md) "Set `UsageType` explicitly on `ShopSave`").
3. **Language relation for SHOP1** — `INSERT INTO EcomShopLanguageRelation (ShopId, LanguageId, IsDefault) VALUES ('SHOP1','LANG1',1)`.
4. **Units, Manufacturers** — `save_units`, `save_manufacturers`.
5. **DataStructure shop** (ShopType=4) + its language relation — owns data models.
6. **Seed `reference_category`** — insert the parent `EcomProductCategory` row (`CategoryType=2`) and its translation BEFORE any fields get created. See `governance.md` "Completeness rules" section for the exact SQL. Missing this breaks completeness UI silently.
7. **Data Models** via `create_data_model_structure` OR piecewise: create `EcomProductCategory` + translation → fields (in BOTH `reference_category` AND the concrete category, both with translations) → `EcomGroups` row with `GroupType=2` and `ProductCategoryId` set → `EcomShopGroupRelation` linking to SHOP-DATA. See `structural-model.md` §2.8 for the field-plumbing internals.
8. **Catalog groups** (GroupType=0) under SHOP1 — `save_groups` with shopId=SHOP1.
9. **Variant Groups + Options** — `save_variant_groups`, `save_variant_options`.
10. **Products** — `create_products`. Set `ProductType=2` on bundles afterward. **`create_products` ignores `languageId`** — products land on the default (master) language; on a non-default-language storefront translate/repoint them or the PLP renders empty (see [`localization.md`](localization.md) "create_products ignores languageId").
11. **Relate products to data model groups** — `assign_data_model_to_products` (creates `EcomGroupProductRelation` to the DataModel group; that's how fields flow to the product). See `structural-model.md` §2.8 for the four-row reference_category mechanic this depends on.
12. **Enrich** — `patch_products_safe` with customFields.
13. **Assets** — `import_product_images_from_urls` with groupId from `get_product_asset_categories`.
14. **Variants** — attach groups + insert combinations + INSERT variant product rows. **The SQL sweep is the canonical variant-enrichment step:** `patch_products_safe` against a variant row (`id` + `variantId`) reports success and echoes the requested values while the variant `EcomProducts` row stays untouched — the echo is the input model, not a post-write read (silent no-op catalogue, [`extend-mcp-tools.md`](../../dw-demo-base/references/foundational/extend-mcp-tools.md) §5). Never trust a tool echo for variants; `SELECT` the variant row immediately after any tool-based variant write. Each variant `EcomProducts` row MUST have a unique `ProductNumber` (master + dash + variant-option suffix); collisions silently break the PIM-for-BC connector import. Master renames can re-sync variant numbers — see `structural-model.md` §2.5 for the rule, the regression vector, and the idempotent re-suffix UPDATE.
15. **BOM components** — `EcomProductItems` rows per bundle. **RESTART HOST AFTER** to refresh ProductItem cache.
16. **Repository + Index** — create `Files/System/Repositories/Products/Products.index`: hand-write it from `ProductIndexBuilder.DefaultSettings` with the **inline `ProductIndexSchemaExtender`** and `<Index Name="Products.index">` (extension included), then `POST /admin/api/BuildIndex`. If PLP/PDP throw `numHits must be > 0` after a `state=success` build, the extender is missing (empty Lucene segment). Full XML, the Name-attribute gotcha, the do-NOT-copy-the-Swift-repo-index rule, and the symptom diagnostics: `structural-model.md` §2.4. Note: an index-level `State=Warning` whose only cause is an unbuilt secondary balancer instance is benign — judge by the **primary instance's** build result + doc count, not the index-level Warning (see [`../../dw-demo-base/references/foundational/search-indexing.md`](../../dw-demo-base/references/foundational/search-indexing.md)).
17. **Queries** — `create_or_update_product_queries` via MCP. Split by purpose:
    - **Feed queries** (referenced by `EcomFeed.FeedIndexQueryId`) → move to `Files/System/Repositories/Products/` **root** (NOT a subfolder — feeds don't scan subfolders).
    - **Dashboard/widget queries** (referenced by widget `QueryId` param) → move to `Files/System/SmartSearches/Ecommerce/Shared/` only — **never GUID-duplicate to Repositories**. Collision mechanism + recovery: `governance.md` "Dashboard query location — Shared ONLY".
    - **Storefront catalog query (`ProductsFrontend`) — required for a Swift-baseline demo.** The Swift catalog app resolves its PLP/PDP index query against a **`ProductsFrontend` repository** (`Files/System/Repositories/ProductsFrontend/Products.query` + `Products.facets`) — a repository the **scaffolding-only `base` layer does NOT ship** (its Swift copy skips `ProductsFrontend/` because that indexes Swift's bike-demo custom fields; see [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) "Repositories skip rule"). Result: **an authored catalog with a working `Products.index` still renders an empty PLP** until this query exists. Author it as a required step — either (a) hand-write `Files/System/Repositories/ProductsFrontend/Products.query` (+ `Products.facets`) sourced from `Repository="Products"` with parameters matching your data-model facet fields, or (b) point the Swift catalog paragraphs at your own `Products/` repo via the bulk `ParagraphModuleSettings` path-rewrite in [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) ("Catalog-paragraph path rewrite"). (If a future `base` layer ships a neutral `ProductsFrontend/Products.query` stub over the demo's own data model, this step becomes a no-op — check the base layer's `README` before authoring.)
    Use full `ProductCategory|<Cat>|<Field>` format in all FieldExpression attrs. Rebuild recipe: `governance.md` "Recovery recipe: Rebuild Products index".
18. **Channels** (ShopType=3) + their language relations + OWN group trees + products-to-channel-group relations.
19. **Feed templates** — `.cshtml` (TemplateProvider) or `.xslt` (XMLProvider) under `wwwroot/Files/Templates/Feeds/`. Feed `FeedProviderConfiguration` XML MUST include a non-empty `Content Type` parameter (`application/json`, `application/xml`, `text/html` etc.) — empty value causes `FormatException` at `Controller.Content`. Feed URLs need `CountryCode=<code>` as a query parameter or the PriceContext throws.
20. **Feeds** — `EcomFeed` rows with `FeedChannelId`, `FeedIndexQueryId`, `FeedProvider`, `FeedProviderConfiguration`.
21. **Completeness rules + group assignments** — via MCP `create_or_update_completeness_rules` + `assign_completion_rules_to_groups`. NEVER via raw SQL unless you restart the host after (cache). See `cache-invalidation.md` for the post-mutation cache-invalidation table.
22. **Users, User Groups, Assortments** — `create_users`, `save_user_groups`, `save_assortments`, `assign_permissions_to_assortment`.
23. **Dashboards** — `create_dashboards` (area=`Products`), `add_widgets_to_dashboards`. Prefer `RepositoryCountWidget` / `RepositoryGridWidget` over SQL scalar widgets for drill-through.
24. **FINAL INDEX REBUILD** after all mutations.

## Product-completeness checklist — verify before declaring catalog done

Before calling catalog authoring finished, verify **every product** (and every variant combination — variants are their own `EcomProducts` rows and fail these independently of the master) against this list. Each gap has a distinct, misleading frontend symptom, so a product that "looks authored" in admin can still be broken on the storefront:

| Must hold, per product (and per variant combo) | Storefront symptom when it doesn't |
|---|---|
| **`ProductActive=true`** — including variant combos (MCP `create_variant_combinations` leaves them NULL, see [`../../dw-demo-base/references/foundational/pim-modelling.md`](../../dw-demo-base/references/foundational/pim-modelling.md) §2.5) | Product/variant is **invisible** — absent from PLP and the PDP variant selector; add-to-cart no-ops. |
| **A price** — a real `ProductPrice` / `EcomPrices` row, incl. combos | Renders at **€0** (or the variant drops out of the price/qty table). |
| **Stock > 0 OR `NeverOutOfStock=true`** — seed per-variant `ProductStock` for **every** language row (variants default to 0) | Shows **"Out Of Stock"** / not orderable even though the master has stock. |
| **A DEFAULT image is set** — exactly one `EcomDetails.DetailIsDefault=1` per product/variant/language (`import_product_images_from_urls` sets none) | Swift card **NREs on images-but-no-default**, taking down the **whole PLP**, not just that card. |
| **Texts present in all shipped language layers** — name/description on each `ProductLanguageId` row | Blank name/description (or default-language fallback leaking) on the localized storefront. |

Run this as a SQL sweep, not an eyeball pass: select products/variants where any of `ProductActive IS NULL`, no price row, `ProductStock=0 AND NeverOutOfStock=0`, no `DetailIsDefault=1`, or a missing language-layer text row — every hit is a future storefront defect. Fix, then flush/restart and rebuild the index before the final verification walk. The per-tool root causes live in [`../../dw-demo-base/references/foundational/pim-modelling.md`](../../dw-demo-base/references/foundational/pim-modelling.md) (§2.5 variants, §2.5a per-variant unit/stock, §2.10 assets).

## Appendix: commerce-side order seeding (used by Swift customer-center demos)

The two sections below are commerce / customer-center seeding, not PIM setup order — they apply when a demo seeds order history for Swift's account-side and CSR views.

The vendor-generic order-completion backfill facts — `create_orders` seeds `OrderComplete=0` carts (not completed orders), `OrderCustomerNumber` is not populated by `create_orders` (the `UseCustomerNumber` lookup), the area-currency-filters-order-history caveat, the order-line price-seeding rules (change the default currency → restart → THEN seed; `add_products` writes only unit-price columns so line/order totals need a backfill; qty-tier `EcomPrices` rows silently reprice explicit unit prices), and the SQL-backfills-vs-runtime-subscribers distinction — live in [`../../dw-demo-base/references/foundational/commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md). The `Order.BeforeSave` / `complete_order` / password-rehash runtime paths and the "subscriber ships without a ledger row" rule are covered there too.

**Demo-sequence context:** in a Swift customer-center demo this seeding fires *after* the order rows are created, before the account-side / CSR verification walk. The area-default-vs-seed-currency pitfall is the one that most often produces a silently-empty My Orders tab on a deserialized Swift baseline — align the area currency to the seeded `OrderCurrencyCode` before backfilling completion. See [`../../dw-demo-swift/references/customer-center.md`](../../dw-demo-swift/references/customer-center.md) for the area-default pitfall and the CSR `AccessUserSecondaryRelation` grants.

**Verification (demo walk):** after the backfill, log in as a seeded buyer and hit `/customer-center/account/orders`, confirm at least N order rows; then log in as the CSR persona and hit `/customer-center/csr/orders`, confirm rows there too (CSR view depends on `AccessUserSecondaryRelation` grants — see [`../../dw-demo-swift/references/customer-center.md`](../../dw-demo-swift/references/customer-center.md) §5).


