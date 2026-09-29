# Product listing and stock — ordering, hidden products, assets, stock columns

What decides the order of a product list, what silently removes rows from one, and the two stock and
price columns whose "empty" conventions differ between writers. Measured on DW 10.27.x / 10.28.x with
Swift 2.

## Contents

- [Any default sort replaces search relevance](#any-default-sort-replaces-search-relevance)
- [`ProductHidden` is enforced in SQL, absent from the index, unwritable by every API](#producthidden-is-enforced-in-sql-absent-from-the-index-unwritable-by-every-api)
- [`AssetCategories` lists every asset twice](#assetcategories-lists-every-asset-twice)
- [Order completion and the two stock tables](#order-completion-and-the-two-stock-tables)
- [An unscoped price row carries stock location `0`, not `NULL`](#an-unscoped-price-row-carries-stock-location-0-not-null)
- [Scoping a listing to one group, and the `Shop` tag every product link needs](#scoping-a-listing-to-one-group-and-the-shop-tag-every-product-link-needs)

## Any default sort replaces search relevance

The Lucene provider treats an explicit `Sort` as **the whole ordering**: a `_score` entry in a sort
list does not restore the relevance ranking that a sort-less query has. So **a default sort is a
search-relevance kill switch**, whether it is set as the catalog paragraph's `QuerySortByParams` or
as a `Sort` element on the query itself.

That matters more than it looks, because in a stock Swift 2 site **the header search and the shop
root share one Product Catalog paragraph** — the search field posts to the page carried by the Shop
navigation tag. A default sort added to make the root listing look right therefore reorders every
search result on the site, and a search for a part returns whatever the sort ranks first.

**Order group listings with the data the catalog already carries, not with a sort:**

| Want | Do | Surface |
|---|---|---|
| A deliberate order on a group listing | set `UseGroupSortInGroupContext = 1` on the catalog paragraph and give the groups their `EcomGroupProductRelation.Sorting` values | paragraph setting + the group-product relation the group editor writes |
| Keep scaffolding products out of a listing | set `ProductExcludeFromIndex = 1` on them and rebuild — the index builder filters on it (`ProductExcludeFromIndex <> 1`) | MCP `patch_products_safe` / Admin API `ProductSave`, then Admin API `BuildIndex` |
| Search to rank by relevance | keep the shared paragraph **free of any default sort** | paragraph setting |

**Keep the shop root free of a default `GroupID` too.** `UseGroupSortInGroupContext` sorts by
`EcomGroupProductRelation.Sorting` whenever the request carries a `GroupID` — **including a default
`GroupID` list put on the root to hide scaffolding** — so with the flag on, the root's search results
come back in group-sorting order rather than relevance order. Hiding scaffolding is the index flag's
job, not the group filter's.

Residual to accept and state: a root listing with no group context and no sort is in
index-document order, which a rebuild may reshuffle. That is the correct trade when the same
paragraph serves search.

## `ProductHidden` is enforced in SQL, absent from the index, unwritable by every API

A product list built over the product index reports a **count higher than the number of rows it
renders**, with no error and nothing logged — a constant shortfall on every listing, for every user.

Three facts compose:

- `ProductRepository.GetProductsByAutoIDs` appends
  `AND (ISNULL(EcomProducts.ProductHidden, 0) <> 1)` to its `SELECT`, so the entity fetch behind the
  product-list view model silently drops hidden products.
- **The product index does not carry `ProductHidden` in any form** — not in the `.index` schema, not
  written by the product index builder, and no build setting excludes hidden products — so the
  header's total still counts them.
- **`Dynamicweb.Ecommerce.Products.Product` has no `Hidden` property at all** (only
  `ShowInProductList`, a different column), so MCP `patch_products_safe`, MCP `update_products` and
  every save verb cannot reach the flag, and the DW10 backend product editor has no control for it.
  It is a DW9 leftover that is still read and no longer writable.

**So in-product the flag can be diagnosed but not cleared.** MCP `verify_product_visibility` on a
product the listing counts and does not render is the in-surface diagnosis; say plainly that
nothing in the product editor clears the flag. Clearing it is out of product: see
[`recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md) "`ProductHidden` is
enforced in SQL and unwritable by every API".

**The durable guard is an assertion that rendered product rows equal the header count** on every
listing probe. It is the only check that catches this class, and it catches the neighbouring
classes (a mis-scoped shop, a stale index) for free.

## `AssetCategories` lists every asset twice

`ProductViewModel.AssetCategories` surfaces each asset **under a pseudo-category named after the
asset AND under its real detail group**, so the natural nested loop — iterate categories, then each
category's assets — renders every document twice. Four files come out as eight rows.

**De-duplicate by asset path** when building a documents or downloads tab from `AssetCategories`.
(A separate trap on the same property: it can be `null` on a stub view model even where the model
itself is non-null, so a bare `is object` check does not protect the loop.)

## Order completion and the two stock tables

DW10 keeps an aggregate stock figure on the product (`EcomProducts.ProductStock`) and a per-location
figure in `EcomStockUnit` rows, and a storefront can render both on the same page. **What order
completion decrements follows the stock location on the order line:**

- **A line with no stock location attached** decrements only the aggregate `ProductStock`. The
  per-location rows do not move, and the two numbers drift apart by exactly the quantity sold, once
  per order, with nothing logged.
- **A line carrying `OrderLineStockLocationId`** — which is what a per-warehouse storefront requires
  anyway — decrements **both**: the aggregate and the matching `EcomStockUnit` row.

So the safe assumption is **both tables move**, and the invariant worth holding is that for every
product `SUM(StockUnitQuantity)` equals `ProductStock` — which is what makes whichever number the
storefront renders the one the catalog published. In-product, check it per product: MCP
`get_products_by_ids` carries the aggregate and MCP `get_stock_locations` the per-location rows, and
snapshot both **before** any check that places its own order, or the check fails on its own side
effect. The corpus-wide version of the same assertion is in
[`recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md) "The two stock tables".

The practical consequence runs the other way from the drift: **an inbound integration that re-asserts
only the product total leaves the per-warehouse breakdown behind**, and the storefront then shows an
aggregate larger than its own stock-location panel. Give the integration a **per-location on-hand
source** (one row per `EcomStockUnit`) and map it in the **same activity** as the product total, so
one inbound run repairs both numbers in one pass. Any reset that restores stock restores both tables
in one transaction for the same reason.

## An unscoped price row carries stock location `0`, not `NULL`

MCP price writes put **`0`** into `EcomPrices.PriceStockLocationID` when no stock location is
supplied — not a SQL `NULL`. Any other pipeline writing the same column must match that convention:
an integration job emitting `NULL` for its unscoped rows produces rows that do not behave like the
unscoped rows already on the table. Emit `0`.

## Scoping a listing to one group, and the `Shop` tag every product link needs

Two Swift catalog wiring faults render a page that looks right and is wrong, with no error.

**`IndexQueryConditions` is not a setting of the catalog paragraph.** Written as
`IndexQueryConditions = GroupID=<groupId>`, it was accepted without error and the listing still
rendered every product the query returned, while the same `?GroupID=<groupId>` on the URL filtered
correctly [dw 10.28.11 · mcp 0.6.0-beta]. The stored settings of an `eCom_ProductCatalog` paragraph
carry `IndexQuery` (the `.query` path) and `QueryConditions`, a JSON array of
`{Name, TypeName, DefaultValue}` parameter defaults; `QueryConditions` is the per-paragraph lever
(dw-content-modelling `references/render-after-write.md`). Read the
paragraph with `get_module_settings` first and write only a key it returns. To scope a page to one
group, use one of:

| Want | Do |
|---|---|
| A group listing reached from navigation | link to the `Shop` page with `GroupID=<groupId>`, the shape Swift's own group navigation emits |
| A fixed page that always shows one group | a `QueryConditions` default for the query's group parameter, or a per-page `.query` whose group arm is a constant, named in that page's `IndexQuery` |

Assert the scope with a count on the rendered page, never with the setting's read-back.

**Every Swift product link resolves through the page tagged `Shop`.** The stock templates build
product and group URLs with `GetPageIdByNavigationTag("Shop")`: the product card, sliders, search
dropdown, cart lines, order details and favourites among them. With no page carrying the tag the
helper returns `0`, every card links to `Default.aspx?ID=0&ProductID=<id>`, and page `0` answers
**200 with the homepage**, not a 404, so the listing looks finished and every click lands on home
[dw 10.28.11 · swift 2.4.0]. Treat "a page tagged `Shop` hosts a live catalog paragraph" as a
precondition of every product link; one such page serves detail mode for products of every group.
Detect it from the frontend: grep the rendered listing's card links for `ID=0`. `save_pages` may not
persist `navigationTag`, so assert the rendered link after tagging
(dw-content-modelling `references/page-paragraph-writes.md`).
