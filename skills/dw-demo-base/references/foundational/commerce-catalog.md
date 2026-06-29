# Foundational candidate → dw-commerce-catalog

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 catalog-publishing / channels / feeds / pricing knowledge, staged here for a future
> fold-up into `dw-commerce-catalog`. No demo/customer content. When folded, move this body into
> `dw-commerce-catalog` and re-target the pointers in the demo skills. Until then, the demo skills
> reference this file.

## 2.3 Catalog vs Channel group trees (the published-to story)

Each Channel (ShopType=3) has its OWN group tree. Products are published to a channel by creating a `EcomGroupProductRelation` row linking the product to one of the channel's groups. Do NOT:
- Link the same catalog groups to multiple shops via `EcomShopGroupRelation` (shared groups show products under every shop)
- Attach channels directly to the main catalog groups

Do:
- Each channel has its own groups (e.g. `G-SHOP-INDOOR` under `CH-SHOPIFY`, `G-HD-HOUSEPLANTS` under `CH-HOMEDEPOT`)
- Use `INSERT...SELECT` to bulk-populate channel groups from catalog groups
- Products live in 1+ catalog group (under the ShopType=1 shop) AND 1+ channel group per channel they're published to

**Group URL slug gotcha — `ShopUrlDataProvider` lazy cache.** When a Swift frontend uses path-based group URLs (e.g. `/swift-2/shop/headsets`), the resolver is `Dynamicweb.Ecommerce.Frontend.UrlHandling.ShopUrlDataProvider`'s static `Lazy<>` indexes (`InitializeProductUrlDataIndex`, `InitializeGroupProductRelationIndex`). Those indexes are populated at first request and only reset when `Notifications.Ecommerce.Group.AfterSave` fires — which fires from MCP `save_groups` and admin-UI saves but NOT from raw `UPDATE EcomGroups SET GroupMetaUrl = ...` SQL. Symptom: SQL-set slugs work in the DB, but `/shop/<slug>` 404s indefinitely until the host restarts OR a group is re-saved through MCP. Index rebuild via `/admin/api/BuildIndex` does NOT flush this — it's separate from Lucene. Recovery after raw-SQL changes to GroupMetaUrl / GroupNumber / any field used by URL resolution: re-save one group through `mcp__dynamicweb-commerce-mcp__save_groups` (idempotent — same payload pattern, same id), or restart the host.

**Same cache-flush rule applies to `EcomGroupProductRelation` mutations** — fired via the native "Publish to channel" action (§2.3a below): `Notifications.Ecommerce.Group.AfterSave` fires, cache flushes, channel URLs resolve immediately. Fired via raw SQL `INSERT INTO EcomGroupProductRelation`: notification doesn't fire, cache stays stale until host restart. See §2.3a and [`cache-invalidation.md`](cache-invalidation.md).

## 2.3a Publishing products: native "Publish to channel" action

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
| Native "Publish to channel" action | Yes | Flushes immediately → URLs work | The default. Use whenever an editor publishes a product. |
| MCP `save_groups` / admin-UI group save | Yes | Flushes | When seeding groups; relation INSERTs go through the same path. |
| Raw SQL `INSERT INTO EcomGroupProductRelation` | No | Stays stale until host restart | Bulk seeding scripts only — and remember to restart the host or re-fire a `save_groups` notification before verifying URLs. |

Cross-ref [`cache-invalidation.md`](cache-invalidation.md) for the full notification-vs-host-restart matrix and the §2.3 group URL slug gotcha above. The `PermissionLevel.Edit` gate is a Layer C entity check ([`users-permissions.md`](users-permissions.md)).

## 2.7 Channels + Feeds

- **Channel** = `EcomShops` row with `ShopType=3`. Has its own group tree + language relation + (optional) `ShopIndexRepository`+`ShopIndexName` for the feed's index source.
- **Feed** = `EcomFeed` row pointing at a Channel + Query + Provider:
  - `FeedChannelId` = Channel's ShopId
  - `FeedIndexQueryId` = query GUID (from the `.query` file's `<Query ID="...">`)
  - `FeedSource=2` (Index) — for index-based feeds
  - `FeedProvider` = `Dynamicweb.Ecommerce.Feeds.TemplateProvider` (for Razor .cshtml → JSON/CSV/HTML) OR `Dynamicweb.Ecommerce.Feeds.XMLProvider` (for XML/XSLT)
  - `FeedProviderConfiguration` = XML with parameters: `<Parameters><Parameter Name="Template" Value="Feeds/my-template.cshtml" /><Parameter Name="Content Type" Value="application/json" /></Parameters>` for Template, or `<Parameters><Parameter Name="XSLT Stylesheet" Value="Feeds/my.xslt" /></Parameters>` for XML.
- **Template path resolution** — `TemplateProvider` expects paths relative to `wwwroot/Files/Templates/Feeds/`. `XMLProvider` expects XSLT in same folder.
- Feed template example for Razor: `@inherits ViewModelTemplate<Dynamicweb.Ecommerce.ProductCatalog.ProductListViewModel>` + `@Model.Products` iteration. Field values are accessed via `ProductCategories[].Fields[categoryFieldId].Value`.
- The `.query` files backing feeds must live at the repository ROOT, not a subfolder — see [`search-indexing.md`](search-indexing.md) for the placement rule.

## 2.9 Assortments (customer access) ≠ Channels (publishing)

- **Assortments** = `EcomAssortments` + `EcomAssortmentItems` — restrict which products logged-in customers see. Scoped by UserGroup permissions via `EcomAssortmentPermissions` / `EcomAssortmentUserRelation`.
- **Channels/Feeds** = the publishing target (see §2.7).
- Don't model Shopify/marketplace/EDI partners as assortments — they're Channels. Assortments are purely B2B customer visibility.

## 2.11 Pricing — tier rows are NOT honored by the stock cart

`EcomPrices` ships a `PriceQuantity` column that *looks* like quantity-break tier pricing — and the Dynamicweb documentation reinforces that read ("Customers receive the best applicable price for their order volume"). In practice the stock DW10 cart-line-add resolver picks the matching `PriceQuantity = 0` row first and stops. Tested with rows fully unscoped (no user group, no customer number, no shop scoping) — still doesn't honor qty breaks. Confirmed against the cart pricing path; the PDP price-tier *display* table works, the *cart charge* does not.

**Surface-independence — this is the platform, not the surface.** This gotcha fires the same regardless of whether the tier rows were inserted via:
- MCP `save_prices` / `create_or_update_prices`
- Management API
- Direct SQL `INSERT INTO EcomPrices`
- Admin UI

Switching surfaces will not fix it; the resolver is the same downstream code path. If the symptom is "I added a quantity-5 tier row but the cart charges base price for 10 units", **stop debugging the insert — the insert is fine, the resolver doesn't read it**. Same applies in reverse: if you have unrelated cart-pricing weirdness, do NOT assume tier rows are causing it — they're silently ignored, not malfunctioning.

**Production pattern (vendor-recommended).** Per the Dynamicweb vendor architecture guidance: for B2B scenarios that need real qty-break behavior, the canonical DW10 production pattern is ERP integration that imports per-user *pre-graduated* prices — one row per (product, user, qty-band) with the resolved price already baked in. The cart resolver then picks the correct pre-graduated row by user-group scope. This shifts the qty-band logic out of DW into the ERP.

**Escape hatch for cart-time qty-break math.** Implement a custom `Dynamicweb.Ecommerce.Prices.IPriceProvider` in `Providers/*.cs` (the customisations-ledger preflight applies per [`../customisations.md`](../customisations.md)) that consults `EcomPrices` rows with `PriceQuantity > 0` and returns the best matching row. Worth doing only when the requirement is genuinely "watch the price drop as the buyer adds units" and ERP-pre-graduated rows can't express it.

**No-customisation workaround.** Keep the tier rows in `EcomPrices` so the PDP tier table still renders, and treat the limitation as known — the tier prices are illustrative; the cart charges the base row at checkout. A `ProductPrice` template variant can read the tier rows directly via a bypassed SQL path to render the table, while the cart honors the base row.

**This gotcha is misleading precisely because** the docs say it works and the rows look correct in the admin pricing matrix. If you see "tier price not applied at cart", the answer is in this section, not in the data.

## 2.12 Pricing — the canonical read surface

- **Read tier prices**: `Services.Prices.GetByProductId(productId)` — currency / customer-group / shop
  scoped by the configured `IPriceProvider` (dw10source `Prices/Price.cs:179`).
- **Custom price logic**: a `PriceProvider` subclass (dw10source `Prices/PriceProvider.cs:17`).
  Override `FindPrice(PriceContext, PriceProductSelection)` for line price, `FindQuantityPrices` for
  qty-break tier rows, `PreparePrices` for a batched ERP fetch.
- **Read prices through `Services.Prices.GetByProductId`, never a raw `SELECT FROM EcomPrices` in
  Razor.** The raw query returns rows from all customer-group scopes, leaking pricing.

## 2.13 Customer-specific (contract) pricing

Account / contract pricing ("customer-card" prices) is a per-customer `EcomPrices` row. Two gotchas
make a correct setup look broken:

- **Scope by customer number, not the MCP `customerGroupId`.** `save_prices`'s `customerGroupId`
  writes `PriceCustomerGroupId`, which the frontend resolver does **not** match against a logged-in
  user's group membership — the price silently never applies. The reliable scope is the **customer
  number**: `UPDATE EcomPrices SET PriceUserCustomerNumber='<custno>'` (and clear the group columns)
  matches every user whose `AccessUserCustomerNumber` equals it — i.e. the whole account. This is the
  shape that actually resolves.
- **Lowest matching price wins** — not priority. A lower contract amount beats the all-customers list
  price automatically once it matches; no need to set `PricePriority`.

**Where it renders:** *not* on PLP/PDP (those show the index / default price context regardless of who
is signed in). The customer price resolves **live in the cart and checkout** (and on any order whose
customer context carries the customer number). Demo it by signing in as the buyer and showing the
cart, not the catalogue. A per-customer price on the PDP requires a content-layout extension that reads
the live price for the current user — not the index field.

**Cache:** prices are cached in process — a SQL price change needs a cache refresh or **host restart**
before it resolves. **Verification trap:** MCP `force_price_recalculation` recomputes *without* a
frontend user price context, so it returns the default price even when customer pricing is correct.
Verify in the storefront cart as the signed-in user, never via recalc.

## 2.14 Variants via the Management API (no SQL)

Building per-variant product rows through the Management API alone — the full chain that replaces any
per-variant `EcomProducts` SQL insert (validated DW 10.25.x):

1. `VariantGroupSave` (post with empty `Id` to create) + `VariantOptionSave` per option. Set `Color`
   (hex) on each option and a Swift PDP renders live swatches.
2. `VariantGroupAdd {ProductId, Ids: [groupId]}` attaches the group to the product.
3. **`VariantCombinationSave {ProductId, VariantCombinationSelectionCacheKey, Ids: [<variantIds>]}`** —
   for a single axis the variant ids are the bare option ids. This command persists the combinations
   AND runs `ExtendAllVariants` (creates the per-variant product rows), clears the variant caches, and
   rebuilds the product's index entry. **Skip `VariantCombinationCreate`** — it only fills a UI-wizard
   cache and persists nothing.
4. Per-variant stock: round-trip `ProductById?Id=<id>&VariantId=<vid>` → set `stock` /
   `neverOutOfStock` → `ProductSave`. Variants default to 0 stock and render a disabled add-to-cart.

### Create-vs-update fork on commerce saves

Most `*Save` commands (`ShopSave`, `ProductSave`, category-field saves, etc.) **UPDATE when `Id` is set
and CREATE when `Id` is empty** — the server assigns the id (`SHOPxx` / `GROUPxx` / `PRODxx` / field id);
capture it from the response `model.id` or `modelIdentifier`. Category product fields create with
`Id: ""` + `SystemName: "<field id>"` + `CategoryId`. Posting a chosen `Id` to a save command returns
`notFound` ("Shop not found", "Field not found") — that is the create/update fork talking, not a missing
entity.

### Product images via the Management API

- The default "Images" asset category accepts `bmp/jpeg/jpg/png/tiff` — **not webp**; convert before
  upload. Name files `{ProductNumber}.<ext>` in the shop's image folder so the category's
  `{productnumber}` auto-match attaches them, and/or attach explicitly via
  `AssetAddToMultipleProducts {Model: {ProductIds, AssetCategoryGroupId, FilesToAttach, IsDefault}}`.
- The product model's `image` property is **computed** — setting it via `ProductSave` is a no-op.
- `SelectedImage` fields (logos, favicons, posters, product images) have a binder asymmetry: GET
  serialises the value as a plain path string, but the save binder needs
  `{"Id": "/Files/...", "Name": "<file>", "Ratio": "", "FocalX": 0, "FocalY": 0}` — the `Path` property
  is obsolete, **`Id` carries the path**. A string (or `Path`-shaped object) saves silently as empty.

### Known commerce API gap — `ShopSave` never persists languages

`ShopSave` never persists `Model.Languages` (only `CompletionLanguages`); `EcomShopLanguageRelation`
cannot be written through this API version. A shop created via the API has no language relation until
someone ticks it in the admin UI — a hand-off step, not a bug to debug.
