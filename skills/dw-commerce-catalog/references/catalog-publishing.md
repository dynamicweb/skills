# Catalog publishing — channels, feeds, pricing, variants, Management API traps

Field-validated DW10 catalog knowledge: the Catalog-vs-Channel group-tree model, the native
"Publish to channel" action, feeds, assortments-vs-channels, the pricing traps (tier rows, contract
prices), and the Management API chains for variants, relations, images, and shops. Section numbers
(§2.3–§2.14) are stable and referenced from sibling skills.

## Contents

- [2.3 Catalog vs Channel group trees (the published-to story)](#23-catalog-vs-channel-group-trees-the-published-to-story)
- [2.3a Publishing products: native "Publish to channel" action](#23a-publishing-products-native-publish-to-channel-action)
- [2.7 Channels + Feeds](#27-channels--feeds)
- [2.9 Assortments (customer access) ≠ Channels (publishing)](#29-assortments-customer-access--channels-publishing)
- [2.11 Pricing — tier rows are NOT honored by the stock cart](#211-pricing--tier-rows-are-not-honored-by-the-stock-cart)
- [2.12 Pricing — the canonical read surface](#212-pricing--the-canonical-read-surface)
- [2.13 Customer-specific (contract) pricing](#213-customer-specific-contract-pricing)
- [2.14 Variants via the Management API (no SQL)](#214-variants-via-the-management-api-no-sql)
- [Product relations, index refresh, create-vs-update, images, shops](#product-relations-via-the-management-api--relationgroupsave-is-update-only-and-the-maintenance-verbs-take-composite-ids)

## 2.3 Catalog vs Channel group trees (the published-to story)

Each Channel (ShopType=3) has its OWN group tree. Products are published to a channel by creating a `EcomGroupProductRelation` row linking the product to one of the channel's groups. Do NOT:
- Link the same catalog groups to multiple shops via `EcomShopGroupRelation` (shared groups show products under every shop)
- Attach channels directly to the main catalog groups

Do:
- Each channel has its own groups (e.g. `G-CHANNELA-X` under `CH-CHANNELA`, `G-CHANNELB-Y` under `CH-CHANNELB`)
- Use `INSERT...SELECT` to bulk-populate channel groups from catalog groups
- Products live in 1+ catalog group (under the ShopType=1 shop) AND 1+ channel group per channel they're published to

**Primary-shop trap — a group in two shops resolves ONE primary shop, and the wrong one silently
delists it.** A group whose `EcomShopGroupRelation` rows span both the storefront shop and a
PIM/data shop resolves a single primary shop; when that resolves to the data shop, the storefront's
ecom navigation drops the group **and** the friendly-URL provider stops generating its slug — the
symptom is a category sidebar showing only a subset of the shop's groups while the missing groups'
slugs 404 (querystring URLs `?GroupID=…` still work, which is what makes it look like a nav bug
instead of a data bug). Relation sorting does not decide the winner — don't try to out-sort it.
Fix at publish time: re-save the group through `save_groups` with the **storefront** `shopId` — the
save replaces the shop relations, leaving the storefront as the group's home — then restart (the nav
tree and URL provider cache the old homing; see the slug gotcha below). If a seeding flow parks
catalog groups in a data shop first, the publish step owes every storefront group this re-home.

**Group URL slug gotcha — `ShopUrlDataProvider` lazy cache.** When a Swift frontend uses path-based group URLs (e.g. `/swift-2/shop/headsets`), the resolver is `Dynamicweb.Ecommerce.Frontend.UrlHandling.ShopUrlDataProvider`'s static `Lazy<>` indexes (`InitializeProductUrlDataIndex`, `InitializeGroupProductRelationIndex`). Those indexes are populated at first request and only reset when `Notifications.Ecommerce.Group.AfterSave` fires — which fires from MCP `save_groups` and admin-UI saves but NOT from raw `UPDATE EcomGroups SET GroupMetaUrl = ...` SQL. Symptom: SQL-set slugs work in the DB, but `/shop/<slug>` 404s indefinitely until the host restarts OR a group is re-saved through MCP. Index rebuild via `/admin/api/BuildIndex` does NOT flush this — it's separate from Lucene. Recovery after raw-SQL changes to GroupMetaUrl / GroupNumber / any field used by URL resolution: re-save one group through `mcp__dynamicweb-commerce-mcp__save_groups` (idempotent — same payload pattern, same id), or restart the host.

**Same cache-flush rule applies to `EcomGroupProductRelation` mutations** — fired via the native "Publish to channel" action (§2.3a below): `Notifications.Ecommerce.Group.AfterSave` fires, cache flushes, channel URLs resolve immediately. Fired via raw SQL `INSERT INTO EcomGroupProductRelation`: notification doesn't fire, cache stays stale until host restart. See §2.3a.

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

The `PermissionLevel.Edit` gate is a Layer C entity check
([`permission-layers.md`](../../dw-users-permissions/references/permission-layers.md)).

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
- The `.query` files backing feeds must live at the repository ROOT, not a subfolder — see
  [`index-management.md`](../../dw-search-indexing/references/index-management.md) for the placement rule.
- **The public feed endpoint is `GET /dwapi/Feeds/GetFeedOutput?id=<feedId>` — the parameter is the bare
  `id`.** It is undocumented, and the obvious `feedId` returns **404**, which reads as "the feed isn't
  published" rather than "the parameter is named differently". This is the URL to present when showing a
  channel/feed integration; all three provider flavours serve from it (verified live: a CSV feed, a JSON
  feed and an XML feed all `200` on the same shape, differing only in `id`).

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

**Escape hatch for cart-time qty-break math.** Implement a custom `Dynamicweb.Ecommerce.Prices.IPriceProvider` in `Providers/*.cs` (this is custom code — a provider class) that consults `EcomPrices` rows with `PriceQuantity > 0` and returns the best matching row. Worth doing only when the requirement is genuinely "watch the price drop as the buyer adds units" and ERP-pre-graduated rows can't express it.

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

- **Two different scopes live in two different columns, and MCP `save_prices` can only reach one of
  them.** `PriceUserGroupId` (Admin API `userGroupId`) scopes a row to an **`AccessUser` group**;
  `PriceCustomerGroupId` (Admin API `groupCustomerNumber`) matches a customer **NUMBER** string, not a
  group id. MCP `save_prices`'s `customerGroupId` writes `PriceCustomerGroupId`, so passing a user-group
  id there stores a number that matches nothing and the resolver falls through to the list price:
  `save_prices {customerGroupId:"1342"}` answers `succeeded:1`, the row appears in `EcomPrices` with
  `PriceCustomerGroupId=1342` and `PriceUserGroupId=NULL`, and a member of group 1342 still sees the list
  price on the PDP.
- **Write a GROUP-scoped contract price through `/Admin/Api/PriceSave` with `userGroupId` set.** Read the
  full model from `PriceById`, set `userGroupId` to the `AccessUser` group id and leave
  `groupCustomerNumber` empty, and post the whole model. Measured: the same buyer's PDP moved from the
  list 312.00 to the contract 274.56 on that one change. MCP `save_prices` does not expose
  `PriceUserGroupId` at all, so keep it for unscoped rows and for customer-number-scoped rows.
- **A CUSTOMER-scoped contract price is `PriceUserCustomerNumber`**, matching every user whose
  `AccessUserCustomerNumber` equals it, i.e. the whole account. `save_prices` cannot set it either; use
  `PriceSave` with `userCustomerNumber`.
- **Assert the rendered price, not the row.** A row-exists assertion passes while the storefront is still
  on list price. Sign in as a member of the group and read the price block; an anonymous visitor is the
  control.
- **Lowest matching price wins** — not priority. A lower contract amount beats the all-customers list
  price automatically once it matches; no need to set `PricePriority`.

**Where it renders:** *not* on PLP/PDP (those show the index / default price context regardless of who
is signed in). The customer price resolves **live in the cart and checkout** (and on any order whose
customer context carries the customer number). Show it by signing in as the buyer and opening the
cart, not the catalogue. A per-customer price on the PDP requires a content-layout extension that reads
the live price for the current user — not the index field.

**Cache:** prices are cached in process — a SQL price change needs a cache refresh or **host restart**
before it resolves. **Verification trap:** MCP `force_price_recalculation` recomputes *without* a
frontend user price context, so it returns the default price even when customer pricing is correct.
Verify in the storefront cart as the signed-in user, never via recalc.

## 2.14 Variants via the Management API (no SQL)

Building per-variant product rows through the Management API alone, the chain that replaces any
per-variant `EcomProducts` SQL insert. **The chain is version-forked between DW 10.25.x and DW 10.28.x**,
and on 10.28.x the wrong shape answers `status: ok` and writes nothing. Establish the build first
(`/Admin/Api` responses do not carry it; read it from the host's version surface), then run the matching
fork and read every step back.

1. `VariantGroupSave` (post with empty `Id` to create) + `VariantOptionSave` per option. Set `Color`
   (hex) on each option and a Swift PDP renders live swatches.
2. `VariantGroupAdd {ProductId, Ids: [groupId]}` attaches the group to the product.
3. **`VariantCombinationSave {ProductId, Ids: [<variantIds>]}`** persists the combinations AND runs
   `ExtendAllVariants` (creates the per-variant product rows), clears the variant caches, and rebuilds
   the product's index entry. The id shape and the cache key are both version-forked (next section).
4. Per-variant PRICE: `PriceSave` carrying `VariantId`, verified by `PriceById` ("Per-variant price"
   below).
5. Per-variant number / stock / active: writable on 10.25.x, **not writable at all on 10.28.x**
   ("Per-variant row fields" below).

### The combination id shape is INVERTED between 10.25.x and 10.28.x

| Build | Working `Ids` shape | What the other shape does |
|---|---|---|
| DW 10.25.x | `["<VariantGroupId>.<VariantOptionId>"]`, group-qualified | A bare option id answers **500**, naming a group that is not the one you meant |
| DW 10.28.5 | `["<VariantOptionId>"]`, bare option ids | The group-qualified id answers **`{"status":"ok"}`** and creates **zero** combination rows |

```
# DW 10.28.5
POST /Admin/Api/VariantCombinationSave {"ProductId":"<P>","Ids":["<VARGRP>.<VO>"]}
  -> 200 {"status":"ok"}      GET VariantCombinationsByProductId -> totalCount 0     # silent no-op
POST /Admin/Api/VariantCombinationSave {"ProductId":"<P>","Ids":["<VO>"]}
  -> 200 {"status":"ok"}      GET VariantCombinationsByProductId -> totalCount 3     # rows created
```

- **Read the count back after every `VariantCombinationSave`.** `GET VariantCombinationsByProductId?ProductId=<P>`
  must return a `totalCount` equal to the number of combinations posted. On 10.28.x the response body is
  identical whether the call wrote three rows or none, so the read-back is the only signal, and a session
  that trusts the `ok` concludes "combination creation is broken on this build" when only the id shape was
  wrong.
- **One option per group per call.** A combination is a point in the matrix, not a set; two options of the
  same group answer `400 specify options in each variant group` on both builds.
- **`VariantCombinationCreationSetup` exists only on 10.25.x.** There it is called ONCE and its cache key
  threaded through the whole batch (re-calling it RESETS the matrix, so a helper fetching a fresh key per
  combination silently discards the work in progress). On **10.28.5 the verb is gone**:
  `POST /Admin/Api/VariantCombinationCreationSetup` answers `400 {"successful":false,"message":"Unknown
  command: 'VariantCombinationCreationSetup'"}`, and `VariantCombinationSave` needs no cache key there.
  The read model still exposes the field it fed (`VariantCombinationsByProductId` returns
  `variantCombinationSelectionCacheKey: ""`), so the field's presence is not evidence the verb exists.
  `VariantCombinationCreate` is likewise unreachable on 10.28.5.

### Per-variant row fields: writable on 10.25.x, unwritable on 10.28.x

**On DW 10.28.5 a variant `EcomProducts` row cannot be written at ROW level through the sanctioned chain.**
A full-model round-trip `ProductById?Id=<id>&VariantId=<vid>` then `ProductSave` returns `status: ok`,
echoes every requested value back, leaves `autoId` untouched, and **both readers return the MASTER
values**. Measured with a master-row control on the same call shape: 4/4 fields landed on the master and
reverted cleanly, **0 of 19** standard fields landed on the variant, including `number`, `name`, `stock`,
`active`, `ean`, `weight`, `defaultPrice`, and the description and meta fields. Plan no per-variant SKU,
name, stock or active-flag beat on this build, and do not spend a session hunting a payload shape.

- **This is NOT the `AllowChangesAcrossVariants` gate.** A per-field gate cannot discard 19 of 19, and
  `ProductName` and `ProductLongDescription` ship that flag `True` and were discarded with the rest.
  Reading `EcomProductField.AllowChangesAcrossVariants` remains worth doing on **10.25.x**, where a
  `False` flag discards that one field's per-variant value by design while the save still answers ok
  (see [`structural-model.md`](../../dw-pim-modelling/references/structural-model.md) §2.5).
- **On DW 10.25.x the round-trip works** for `stock`, `active` and `number`: set them on the model read
  from `ProductById?Id&VariantId` and `ProductSave` persists them. `DefaultPrice` is the one exception
  there, ignored on every save, so the variant reads back with the MASTER's price (measured across 22
  variants in three families).
- The hosted-publish consequence, including the `VariantCombinationSave` re-derive that resets
  `ProductWeight` and `ProductPrice` on every variant it touches, lives in `dw-demo-hosted`
  (`publish-to-hosted.md`, "Publishing onto an install that already has content").
- **Verify with both readers plus a master control.** `GET /Admin/Api/ProductById?Id&VariantId` AND
  `get_product_by_id(id, variantId)`; master values coming back means the write did not land. Run the
  identical call against the master row in the same pass, so a null result is proof about the variant and
  not about the instrument.

### Per-variant price

Per-variant pricing is an `EcomPrices` row, so the write is **`PriceSave` carrying `VariantId`** on every
build. `DefaultPrice` through `ProductSave` never reaches it.

- **Verify by `PriceById`, not by the product-scoped list.** MCP `get_prices_by_product_id` is served
  through a cache that lags the write: immediately after six successful `PriceSave` calls it returned an
  empty list, and moments later returned all six rows. `GET /Admin/Api/PriceById?Id=<priceId>` is not
  cached, so assert each created id there (or re-read `PricesByProductId` after the cache settles). A
  verification written against the product-scoped list concludes the price write failed when it landed.
- **`defaultPrice` on the product model is a different column** (`EcomProducts.ProductPrice`) and stays
  `0` no matter how many `EcomPrices` rows exist. It is never the price read-back.
- A NULL-price variant row also breaks the product index build; see
  [`index-management.md`](../../dw-search-indexing/references/index-management.md) "A NULL-price variant
  row drops every variant document".

**Run this chain verbatim before concluding a variant row is unwritable.** The verbs *outside* the chain
answer `status: ok` and change nothing, so a session that probes them in sequence reads like proof that
per-variant identity is impossible when the real route was simply never exercised. The catalogue of
success-reporting non-writers, with the working replacement for each:

| Lying/no-op path | What actually writes it |
|---|---|
| `patch_products_safe` / `update_products` against a variant id | Full-model round-trip `ProductById?Id&VariantId` → `ProductSave` on 10.25.x; nothing on 10.28.x |
| MCP `create_variant_combinations` (leaves `ProductActive`/`ProductPrice` NULL) | `VariantCombinationSave` — runs `ExtendAllVariants` (step 3) |
| `ProductSave` with a hand-built **partial** model | The round-trip — `*Save` commands are whole-entity saves |
| `DefaultPrice` via `ProductSave` on a variant | `PriceSave` carrying `VariantId` |
| `VariantCombinationCreate`, `VariantCombinationToggleActive`, `VariantCombinationUpdate` | Not part of the chain — `VariantCombinationSave` covers create + persist |
| `VariantCombinationSave` with group-qualified ids on 10.28.x | The same verb with bare option ids |

On 10.25.x, a read that returns the MASTER's values for a combination means the variant row's own fields
are NULL and the read fell back, so the row exists and is enrichable through this chain. On 10.28.5 the
same read means the row refuses writes: the control above lands 4/4 on the master and 0/19 on the variant
row, whose own `autoId` and `kind: variant` prove it exists. Neither reading is evidence of a missing or
read-only row on its own, so run the master control before you decide which one you are looking at.

### Product relations via the Management API — `RelationGroupSave` is update-only, and the maintenance verbs take composite ids

- **Create a relation group with `GroupId: ""` — `RelationGroupSave` has no explicit-id create path.**
  Posting a chosen id fails; the empty string is the create signal and the server assigns the id. This is
  the same create/update fork as the commerce saves above, expressed through an empty *string* rather than
  an empty `Id`.
- **`SortOrder` is DEAD on both the create and the attach.** It is accepted and ignored by
  `RelationGroupSave` and by `RelatedProductAttach` alike, so `ProductRelatedSortOrder` never lands and the
  read-back always shows the default. **Ordering of related-product callouts must live page-side**, not in
  the relation data — decide that up front rather than after a batch has been written twice.
- **`ProductRelatedMakeTwoWayRelation` and `ProductRelatedDelete` take `Ids[]` of PIPE-DELIMITED COMPOSITE
  KEYS**, not a structured payload. A `{ProductId, RelatedProductId, RelatedGroupId}` object — the obvious
  shape, and the one the create verbs use — fails on both:

  ```
  POST /Admin/Api/ProductRelatedMakeTwoWayRelation
  { "Ids": ["<sourceProductId>|<relationGroupId>|<targetProductId>|<variantId>", …] }
  POST /Admin/Api/ProductRelatedDelete          # same Ids[] shape
  ```

  The trailing variant segment is present even when empty. This is the same "list-command ids are full
  paths, not names" rule the `*Delete` family follows — read one row from the matching list query and
  copy its identifier shape before scripting a batch.

### `ProductSave` without `RunUpdateIndex` leaves the storefront serving the old value

**The PLP renders from the product search index, not from `EcomProducts`** — so a product copy fix that is
correct in the database stays wrong on the category page **indefinitely**, until something else triggers a
full build. `ProductSave` refreshes the product's index entry only when **`RunUpdateIndex`** is set.

- **Make `RunUpdateIndex=true` the default in the documented `ProductSave` shape.** With it, a translated name
  was live on the localized PLP within ~3 seconds of the save returning `ok` — measured across 194 product-copy
  saves and 148 meta saves on one pass.
- **Incremental is also the only practical option.** A full `BuildIndex` takes minutes and outruns the 120s
  API-client timeout, so reaching for a full build per save is both slow and unreadable
  ([`index-management.md`](../../dw-search-indexing/references/index-management.md)).
- Verify on the **rendered** PLP within a few seconds of the save, not on the save response.

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

#### The product-asset verb set — add, remove, and set-default are three different calls

Name-matching picks the wrong verb for two of these three, and one of the wrong picks is catastrophic.
Learn them as a set:

| Intent | Verb | Namespace / scope |
|---|---|---|
| Attach files to products | `AssetAddToMultipleProducts {Model:{ProductIds, AssetCategoryGroupId, FilesToAttach, IsDefault}}` | `Dynamicweb.Products.UI.Commands` — product link |
| **Detach** a file from a product | `ProductAssetDelete {QueryId, ProductId, Ids[]}` | `Dynamicweb.Products.UI.Commands` — product link |
| Make an attached asset the primary | `ProductAssetSetAsDefault {DetailId, ProductId, VariantId, LanguageId}` (inverse: `ProductAssetRemoveDefault`) | `Dynamicweb.Products.UI.Commands` — product link |
| Delete FILES from the archive | `AssetDelete {DirectoryPath, Ids}` | `Dynamicweb.Files.UI.Commands.Files` — **the file archive** |

- **`AssetAddToMultipleProducts.IsDefault` is inert on the raw `/Admin/Api` verb, and MCP
  `add_product_image {setAsPrimary:true}` DOES write the flag.** The inert flag is a property of the
  Management API verb, not of the platform: `AssetAddToMultipleProducts` silently accepts `IsDefault`
  (`status: ok`, row created) and the `EcomDetails` row lands with `isDefault=false`, every time, across
  a whole batch, so on that verb setting a primary is a **second call**, `ProductAssetSetAsDefault` with
  the `DetailId` of the row just created. MCP `add_product_image` is a different code path and honours
  `setAsPrimary` on the first call: measured 335/335 attachments primary on the first read, with no
  `ProductAssetSetAsDefault` call made. **Prefer `add_product_image {setAsPrimary:true}` for bulk
  attach**, two calls per attachment instead of three.
- **The read-back stays mandatory on both paths.** Read the row through `GroupedAssetsByProductId` (or
  MCP `get_product_images`) and assert `isPrimary`; a `status: ok` echo does not prove it. Any bulk
  wiring helper that attaches a primary must do its own follow-up read. Where you find a raw
  `UPDATE EcomDetails SET DetailIsDefault=1` in an existing script, the raw-verb defect is what it was
  covering for. On a host where `get_product_asset_categories` returns `[]`, `groupId: 0` is the correct
  asset-category argument.
- **`AssetDelete` is NOT the inverse of an asset attach.** It lives under
  `Dynamicweb.Files.UI.Commands.Files`, takes `{DirectoryPath, Ids}` and operates on the **file archive**;
  the product-scoped verb is `ProductAssetDelete {QueryId, ProductId, Ids}`. The two differ by one word
  and by their entire blast radius: a generic category tile is routinely the DEFAULT image of *thousands*
  of non-curated products, so deleting three files from the archive to fix twenty-five wrong thumbnails
  breaks every one of them. A reader must be able to say which of the two is product-scoped **without
  calling either**.
- **`ProductAssetDelete` removes the LINK only** — the default row, other asset-category rows (manuals,
  documents) and the file in the archive are all untouched, and the change is visible in rendered HTML
  immediately with no cache flush and no recycle. `QueryId` takes the all-zero GUID. Verify per product:
  row count −1, exactly the intended row gone, default row unchanged, other-category rows unchanged, the
  file still HTTP 200, and 0 occurrences of the removed path in the rendered PDP.
- **Standing rule: a bulk attach must ship with its own bulk detach, in the same file, at the same
  time.** A bulk attach across a whole catalogue takes minutes; the cleanup written later, per-product,
  inside whichever script replaced the *default* image, covers only that handful. Every other product
  keeps the attachment **demoted from default to ADDITIONAL** — a gallery slot nobody audits, invisible to
  every default-image check, and found months later by an owner looking at the site. Grep any bulk-attach
  helper for a matching detach in the same file; a probe that flags any image path attached to more than
  N products AND not default on all of them catches the existing tail.
- **When documenting a write verb, document its inverse in the same edit or mark the capability
  incomplete.** The remove verb above existed all along and was simply never recorded, so every removal in
  one project's history went through raw SQL — and when SQL was banned by standing constraint the
  capability appeared to vanish and blocked a brief.

### Known commerce API gap — `ShopSave` never persists languages

`ShopSave` never persists `Model.Languages` (only `CompletionLanguages`); `EcomShopLanguageRelation`
cannot be written through this API version. A shop created via the API has no language relation until
someone ticks it in the admin UI — a hand-off step, not a bug to debug.

### Read a shop with `GetShopByIdQuery` before any round-trip `ShopSave`

There are two shop-read surfaces and they return different models. **`GetShopById` returns a stub** — `{id, name, permission}` only. The full model (`usageType`, `autoBuildIndex`, and the rest) comes only from the namespaced `Dynamicweb.Products.UI.Queries.Settings.GetShopByIdQuery`. **Read through `GetShopByIdQuery` before a round-trip `ShopSave`**: a save built on the stub write-backs empty values over every field the stub omitted. Verified by readback — a `ShopSave` carrying the full `GetShopByIdQuery` model changes the one target field (e.g. `usageType`) while preserving `name` and `autoBuildIndex`.

### Set `UsageType` explicitly on `ShopSave` — the default `ShopType=0` hides the shop

A `ShopSave` that creates a shop without an explicit `UsageType` leaves `EcomShops.ShopType = 0` (none). The 10.28 admin lists shops by usage-type bucket — the Channels tree filters `UsageType is ShopType.Shop or ShopType.Channel` (`ChannelNodeProvider.GetCatalogShops`), Data models filters `ShopType.DataStructure` — so an untyped shop shows up in **no** typed list, even with a correct area binding and a working storefront (the symptom reads as "the webshop shop is missing from Channels"). **Always set `UsageType` on `ShopSave`:** `shop` for a storefront channel, `channel` for a feed target, `dataStructure` for a data-model shop. Re-typing an existing untyped shop to `shop` makes it reappear in `ShopAll` with storefront checkout/PLP behaviour unchanged. (ShopType enum + admin-nav mapping:
[`structural-model.md`](../../dw-pim-modelling/references/structural-model.md) §2.1.)
