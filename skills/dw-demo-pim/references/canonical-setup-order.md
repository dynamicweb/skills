# canonical-setup-order.md

> The canonical setup order for a Dynamicweb 10 PIM build. Each step depends on earlier ones — skipping or reordering causes rework. Loaded from `~/.claude/skills/dynamicweb-pim-demo/SKILL.md` "Where to find things" table. Cross-references out to `structural-model.md`, `governance.md`, `cache-invalidation.md`, `workflow.md`, `permissions-model.md`.

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
9. **Products** — `create_products` via MCP. Attach to DataModel groups only (no Channel relations yet). `ProductActive=1` from day one; channel visibility is gated by `EcomGroupProductRelation` rows, NOT by `ProductActive`. See `structural-model.md` §2.1 callout on ProductActive-vs-relations.
10. **Relate products to data model groups** — `assign_data_model_to_products` creates `EcomGroupProductRelation` rows to the DataModel group (this is how fields flow to the product). At this point the product is visible in All products, Data models tree, and any Dynamic Workspace whose query matches; invisible to every channel.
11. **Enrich + Assets + Variants + BOM** — `patch_products_safe`, `import_product_images_from_urls`, variant combinations + unique per-variant `ProductNumber`, `EcomProductItems` for bundles. **RESTART HOST AFTER BOM** to refresh ProductItem cache. Same as Variant A steps 12-15; see §1 below for the variant-`ProductNumber` regression rule (`structural-model.md` §2.5).
12. **Workflow definition** — insert `Workflow` row + `WorkflowState` rows (e.g. Draft / Ready / Published) + `WorkflowGoToState` graph + `WorkflowNotification` recipients. Attach to the top-level DataModelFolder via `EcomGroups.GroupWorkflowId` — inheritance cascades to every product under any descendant DataModel. See `workflow.md` for schema, the `ProductWorkflowStateChangedSubscriber`, and the per-state role-gating workarounds (DW10 workflow is permission-blind by default).
13. **Dynamic Workspaces** — insert `DynamicStructures` + `DynamicStructureLevels` rows with `UseRelationOnProductCreate=true` so products created from the workspace auto-attach to the source DataModel group. Levels source = `DataModelKey` or `ProductField` (e.g. `ProductWorkflowStateId` for a state-grouped Inbox). License-gated on `LicenseHasFeature("PIM")`. See `structural-model.md` §2.12.
14. **Channels** — one or more `EcomShops(ShopType=3)`, EACH with its OWN group tree + language relation. **Do NOT share catalog groups across Channels** (existing rule, `structural-model.md` §2.3).
15. **Products.index** — hand-write from `ProductIndexBuilder.DefaultSettings`. `Name="Products.index"` (including extension — Lucene resolver gotcha). **Inline `ProductIndexSchemaExtender`** inside `<Schema><Fields>` — load-bearing; without it BuildIndex returns success on an empty segment and every PLP throws `numHits must be > 0`. Full XML + symptom list: `structural-model.md` §2.4.
16. **BuildIndex Full** — `POST /admin/api/BuildIndex {Repository:Products, IndexName:Products.index, BuildName:Full, BuildType:Full}`. Healthy segment is hundreds of KB; 53 bytes = schema accepted zero documents.
17. **Permissions** — scope per-role via `UnifiedPermission` entries on the Shop / Group / Product / DynamicStructure / Workflow keys. With `CapabilityControlFeature` ON (DW10.21+), Layer B (capability keys like `/Products/DynamicWorkspaces`) gates UI-section visibility; Layer C (entity keys) gates per-row access. With it OFF, the legacy `PermissionSection("Products")` cascade applies. See `permissions-model.md` for the three-layer model and `permissions-recipes.md` for the role-matrix + grant-seeding SQL.
18. **Smoke-test publish** — pick one product, fire the native "Publish to channel" action from the bulk Product List screen (multi-select target Shop + Channel groups, `PermissionLevel.Edit`, additive `EcomGroupProductRelation` rows). Verify rows created + `ShopUrlDataProvider` lazy cache flushed (the native action triggers `Notifications.Ecommerce.Group.AfterSave`; raw SQL does NOT — restart host if you bypass the action). See `structural-model.md` §2.3a.
19. **Dashboard widgets** — `RepositoryCountWidget` per workflow state (e.g. Draft / Ready / Published / Offline), keyed on `ProductWorkflowStateId`. Prefer `RepositoryCountWidget` / `RepositoryGridWidget` over scalar SQL widgets for drill-through. See `governance.md` "Dashboard query location".
20. **FINAL INDEX REBUILD** after all mutations. Same as Variant A step 24.

(Step count varies — the spine merges steps 11's enrich/assets/variants/BOM into one bullet vs Variant A's four; the actual storage mutations are equivalent.)

## 1. Canonical setup order (Variant A — Storefront-first)

1. **Currencies, Countries, Languages** — `save_currencies`, `save_countries`; languages usually pre-seeded (LANG1 = en-US). PriceContext needs a non-null Country entity — seed US if it isn't already.
2. **Keep SHOP1** — rename via `UPDATE EcomShops SET ShopName` if save_shops is perm-blocked.
3. **Language relation for SHOP1** — `INSERT INTO EcomShopLanguageRelation (ShopId, LanguageId, IsDefault) VALUES ('SHOP1','LANG1',1)`.
4. **Units, Manufacturers** — `save_units`, `save_manufacturers`.
5. **DataStructure shop** (ShopType=4) + its language relation — owns data models.
6. **Seed `reference_category`** — insert the parent `EcomProductCategory` row (`CategoryType=2`) and its translation BEFORE any fields get created. See `governance.md` "Completeness rules" section for the exact SQL. Missing this breaks completeness UI silently.
7. **Data Models** via `create_data_model_structure` OR piecewise: create `EcomProductCategory` + translation → fields (in BOTH `reference_category` AND the concrete category, both with translations) → `EcomGroups` row with `GroupType=2` and `ProductCategoryId` set → `EcomShopGroupRelation` linking to SHOP-DATA. See `structural-model.md` §2.8 for the field-plumbing internals.
8. **Catalog groups** (GroupType=0) under SHOP1 — `save_groups` with shopId=SHOP1.
9. **Variant Groups + Options** — `save_variant_groups`, `save_variant_options`.
10. **Products** — `create_products`. Set `ProductType=2` on bundles afterward.
11. **Relate products to data model groups** — `assign_data_model_to_products` (creates `EcomGroupProductRelation` to the DataModel group; that's how fields flow to the product). See `structural-model.md` §2.8 for the four-row reference_category mechanic this depends on.
12. **Enrich** — `patch_products_safe` with customFields.
13. **Assets** — `import_product_images_from_urls` with groupId from `get_product_asset_categories`.
14. **Variants** — attach groups + insert combinations + INSERT variant product rows. Each variant `EcomProducts` row MUST have a unique `ProductNumber` (master + dash + variant-option suffix); collisions silently break the PIM-for-BC connector import. Master renames can re-sync variant numbers — see `structural-model.md` §2.5 for the rule, the regression vector, and the idempotent re-suffix UPDATE.
15. **BOM components** — `EcomProductItems` rows per bundle. **RESTART HOST AFTER** to refresh ProductItem cache.
16. **Repository + Index** — create `Files/System/Repositories/Products/Products.index`: hand-write it from `ProductIndexBuilder.DefaultSettings` with the **inline `ProductIndexSchemaExtender`** and `<Index Name="Products.index">` (extension included), then `POST /admin/api/BuildIndex`. If PLP/PDP throw `numHits must be > 0` after a `state=success` build, the extender is missing (empty Lucene segment). Full XML, the Name-attribute gotcha, the do-NOT-copy-the-Swift-repo-index rule, and the symptom diagnostics: `structural-model.md` §2.4.
17. **Queries** — `create_or_update_product_queries` via MCP. Split by purpose:
    - **Feed queries** (referenced by `EcomFeed.FeedIndexQueryId`) → move to `Files/System/Repositories/Products/` **root** (NOT a subfolder — feeds don't scan subfolders).
    - **Dashboard/widget queries** (referenced by widget `QueryId` param) → move to `Files/System/SmartSearches/Ecommerce/Shared/` only — **never GUID-duplicate to Repositories**. Collision mechanism + recovery: `governance.md` "Dashboard query location — Shared ONLY".
    Use full `ProductCategory|<Cat>|<Field>` format in all FieldExpression attrs. Rebuild recipe: `governance.md` "Recovery recipe: Rebuild Products index".
18. **Channels** (ShopType=3) + their language relations + OWN group trees + products-to-channel-group relations.
19. **Feed templates** — `.cshtml` (TemplateProvider) or `.xslt` (XMLProvider) under `wwwroot/Files/Templates/Feeds/`. Feed `FeedProviderConfiguration` XML MUST include a non-empty `Content Type` parameter (`application/json`, `application/xml`, `text/html` etc.) — empty value causes `FormatException` at `Controller.Content`. Feed URLs need `CountryCode=<code>` as a query parameter or the PriceContext throws.
20. **Feeds** — `EcomFeed` rows with `FeedChannelId`, `FeedIndexQueryId`, `FeedProvider`, `FeedProviderConfiguration`.
21. **Completeness rules + group assignments** — via MCP `create_or_update_completeness_rules` + `assign_completion_rules_to_groups`. NEVER via raw SQL unless you restart the host after (cache). See `cache-invalidation.md` for the post-mutation cache-invalidation table.
22. **Users, User Groups, Assortments** — `create_users`, `save_user_groups`, `save_assortments`, `assign_permissions_to_assortment`.
23. **Dashboards** — `create_dashboards` (area=`Products`), `add_widgets_to_dashboards`. Prefer `RepositoryCountWidget` / `RepositoryGridWidget` over SQL scalar widgets for drill-through.
24. **FINAL INDEX REBUILD** after all mutations.

## Appendix: commerce-side order seeding (used by Swift customer-center demos)

The two sections below are commerce / customer-center seeding, not PIM setup order — they apply when a demo seeds order history for Swift's account-side and CSR views.

### Post-seed: order completion backfill

`mcp__dynamicweb-commerce-mcp__create_orders` seeds rows into `EcomOrders` with `OrderComplete=0`, i.e. **carts**, not completed orders. Swift's account-side Orders paragraph and the CSR Orders impersonation view both filter on `OrderComplete=1` and silently skip the cart rows — the symptom is "I seeded 13 orders via MCP and the My Orders tab is empty," not an error.

For demo seed scripts where the orders are *meant* to be order-history (not in-progress carts), backfill the flag in one SQL after `create_orders` returns:

```powershell
sqlcmd -S "<dwserver>" -d <dwdb> -E -Q `
  "UPDATE EcomOrders SET OrderComplete = 1 WHERE OrderComplete = 0 AND OrderCart = 0 AND OrderID LIKE 'ORDER%'"
```

Use a `WHERE` clause precise enough to skip any rows that are intentionally carts (CART1/CART2/...). The `mcp__dynamicweb-commerce-mcp__complete_order` MCP tool exists and works on individual orders but runs the full price-recalc + workflow chain per call, which is slow for bulk seed and can fail if pricing has any unresolved currency / country gaps. Direct UPDATE is the right tool for seed-script bulk completion; reserve `complete_order` for in-demo flows where the side-effects (workflow, email, inventory) are part of the demo.

**Also seed `OrderCustomerNumber` when seeding for B2B account-side display.** The Account → Orders paragraph uses a `UseCustomerNumber` lookup against the seeded user's `AccessUserCustomerNumber`; MCP `create_orders` populates `OrderCustomerAccessUserId` but not `OrderCustomerNumber`. Backfill:

```sql
UPDATE o
SET OrderCustomerNumber = u.AccessUserCustomerNumber
FROM EcomOrders o
JOIN AccessUser u ON u.AccessUserID = o.OrderCustomerAccessUserId
WHERE o.OrderCustomerNumber IS NULL OR o.OrderCustomerNumber = '';
```

**Currency / country alignment caveat.** Account-side filters orders by the area's *current* currency, not the order's stored currency. If the demo's `Area` row defaults to EUR/DE after a `deserialize` and seeds orders in USD, My Orders renders empty silently. Switch the area to match the seeded `OrderCurrencyCode` (or seed orders in the area's default) BEFORE backfilling completion. See `dynamicweb-swift-demo/references/customer-center.md` for the area-default-vs-seed-currency pitfall.

**Verification:** after the backfill, walk the demo: log in as a seeded buyer, hit `/customer-center/account/orders`, confirm at least N order rows. Then log in as the CSR persona and hit `/customer-center/csr/orders`, confirm rows there too (CSR view depends on `AccessUserSecondaryRelation` grants — see `dynamicweb-swift-demo/references/customer-center.md` §5).

### SQL backfills vs runtime subscribers

The bulk SQL backfills documented above (`OrderCustomerNumber`, `OrderComplete=1`, `AccessUserPassword`) are correct for **seed data** — they're the fastest path to populate a demo from a clean slate.

For **runtime** flows (orders placed by users on the storefront, password resets, etc.), the canonical DW10 path is different:

- `OrderCustomerNumber`: `[Subscribe(Order.BeforeSave)]` subscriber copies `user.CustomerNumber` to `order.CustomerNumber`.
- `OrderComplete=1`: setting `order.Complete = true` + `Services.Orders.Save(order)` auto-stamps `CompletedDate`. Or call `complete_order` MCP. dw10source `Order.cs:250-271`.
- `AccessUserPassword`: `UserManagementServices.Users.ChangePassword(user, pw)` + `Services.Users.Save(user)`. dw10source `UserService.cs:430,439`. DW10's `AuthenticationManager.cs:184` also auto-rehashes plaintext seeds on first successful login.

The subscriber is a `.cs` file but **not in the customisations preflight glob** — a `NotificationSubscriber` ships unprompted. See [`../../dw-demo-base/references/customisations.md`](../../dw-demo-base/references/customisations.md) §"What the rule *actually* forbids vs. doesn't forbid" and [`../../dw-demo-swift/references/dw10-canonical-surfaces.md`](../../dw-demo-swift/references/dw10-canonical-surfaces.md) §"Cross-cutting redirects". Ship the subscriber without a ledger row.


