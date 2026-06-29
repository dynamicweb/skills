# Foundational candidate → split across dw-search-indexing / dw-content-modelling / dw-commerce-catalog / dw-users-permissions

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 post-mutation cache-invalidation knowledge, staged here for a
> future fold-up — split across `dw-search-indexing` / `dw-content-modelling` / `dw-commerce-catalog` /
> `dw-users-permissions` (it is cross-cutting). No demo/customer content. When folded, distribute this body into
> those skills and re-target the pointers in the demo skills. Until then, the demo skills reference this file.

Post-mutation cache invalidation for Dynamicweb 10. Use this to look up "I just mutated X — what cache do I need to flush, and do I need to restart the host?".

## Surface scope — when this table matters

This table is the rulebook for **Direct SQL fallback** mutations and a handful of MCP/API edge cases. It is **NOT** something you read before using MCP or admin UI for the same operation:

- **MCP `save_*` / `create_or_update_*` / admin-UI Visual Editor / admin-UI form save** → these go through DW's domain services, which invalidate caches inline. You do not consult this table; you do not restart the host. Domain-service surfaces — MCP `save_*` / `create_or_update_*` and the admin UI — invalidate caches inline, so prefer them for structural CREATEs for exactly this reason.
- **Management API** (`POST /admin/api/...`) → same domain services as MCP; same cache invalidation behavior. The dedicated `CacheInformationRefresh` / `BuildIndex` / `GetServiceCaches` endpoints listed below are themselves Management API calls — use them when you need to flush something explicitly without restarting. On a **hosted install** there is no restart at all: every "YES restart" row below resolves to a bulk flush instead — `GetServiceCaches` → `CacheInformationsRefresh {"Ids": [...]}` (plural, takes the service ids); the Management API surface for both is in [`data-access.md`](data-access.md).
- **Direct SQL `INSERT` / `UPDATE`** → bypasses every domain service. Almost everything below applies to this surface. **The "Restart required" column tells you what SQL-direct seeding owes you afterward.**
- **Filesystem mutations** (`.query`, `.index`, `.cshtml` drops/edits) → mostly cache-bypassing. The `.query` row below covers the worst case.

If you used MCP for a row whose mutation type appears in the table below, you should already be done — do not "double-fix" by also restarting; the cost is a 30-second host bounce + lost in-memory state that wasn't broken in the first place.

## Post-mutation cache table

| Mutation | Cache touched | Invalidation surface | Restart required? |
|----------|---------------|----------------------|-------------------|
| MCP `create_or_update_completeness_rules` | `CompletionRuleService` ServiceCache | (auto via MCP) | No |
| Direct SQL INSERT into `EcomCompletionRules` | Same | (none — SQL bypasses cache) | YES (or save once via admin UI) — see [pim-completeness.md "Completeness rules"](pim-completeness.md) |
| MCP `create_or_update_product_queries` | `Searching:Queries` cache | (cache populated at startup; no API to invalidate) | YES on overwrite/conflict — see [search-indexing.md "Dashboard query location"](search-indexing.md) |
| Disk delete of `.query` file | Same | (none) | YES — see [search-indexing.md "Dashboard query location"](search-indexing.md) |
| MCP product mutation | Lucene index | `POST /admin/api/BuildIndex {Repository:Products,IndexName:Products.index,BuildName:Full}` | No — see [search-indexing.md "Recovery recipe: Rebuild Products index"](search-indexing.md) |
| **Direct SQL UPDATE on `EcomProducts` translatable fields** (e.g. `ProductName`, `ProductShortDescription` on a per-language layer row) | live `ProductService` product cache **and the Lucene index builder reads *through* that cache** | `POST /admin/api/CacheInformationRefresh` (or restart) **then** BuildIndex | YES (flush/restart) — and see the ordering trap below: a `BuildIndex` run while the product cache is stale bakes the OLD values into the index, so reindex is NOT sufficient on its own |
| Direct SQL INSERT into `EcomProductItems` | `ProductItem` Lazy<Dictionary> cache | (none) | YES — bundle Components tab will show empty until restart |
| **Direct SQL INSERT new `Page` row** | Page-resolution cache | (none) | YES — page 404s on the storefront until restart, even with correct slug/area wiring |
| **Direct SQL INSERT new `Paragraph` row** | Page-composition cache | (none) | YES — paragraph does not render until restart |
| **Direct SQL INSERT new `GridRow` row** | Page-composition cache | (none) | YES — grid row + its paragraphs do not render until restart |
| **Direct SQL INSERT new `EcomPrices` row** | Resolved-price cache | (none) | YES — new price is not picked up by PDP / cart resolution until restart |
| **Direct SQL UPDATE on an existing `Page` / `Paragraph` / `GridRow` field** (e.g. `ParagraphTemplate`, `PageMetaTitle`, content fields) | (cache holds the row by id; updated fields are read live from DB on next render) | (none needed) | **No** — live, refresh the page. This is the one safe SQL pattern for these tables. |
| **Direct SQL UPDATE on `GridRow.GridRowSort` (re-ordering existing rows)** | Page-composition cache holds the ordered list | (none) | YES — the cached ordering wins until restart, even though field updates on individual rows go live |
| **Direct SQL UPDATE on `EcomPrices.PriceAmount` / `PriceCurrency` / scope columns** | Resolved-price cache | (none) | YES — old price wins until restart |
| **Direct SQL UPDATE on `EcomOrderStates.OrderStateColor` (or other state-row columns read at render time)** | `OrderStates.GetStateById()` in-memory cache | (none) | YES — the badge's inline-style attribute holds the stale color even after a full page reload; storefront-rendered order-state badges and CSS variables fed by `Services.Orders.GetStateById(...).Color` keep the old hex until restart |
| MCP `save_paragraphs` / `save_pages` / `save_grid_rows` | Page-composition cache | (auto via MCP) | No — these are the preferred surface for content seeding; the four "Direct SQL INSERT" rows above are the SQL-fallback equivalents |
| **Paragraph-soft-hide / delete inside a `@RenderGrid(otherPageId)` nested grid** (e.g. Swift's `Swift-v2_ProductListComponentSelector` PLP wrapper) | RenderGrid HTML cache (keyed by source page id) | (none — survives host restart) | **No surface fix** — `ParagraphDeleted=1` / `ParagraphShowParagraph=0` are not observed even after restart. CSS-hide is the only reliable lever; see [`swift-building.md` §5 "ProductListComponentSelector caches even harder"](swift-building.md) for the worked recipe. |
| Service-cache enumerate | All services | `GET /admin/api/GetServiceCaches` | n/a (read-only) |
| Specific service cache flush | Single service | `POST /admin/api/CacheInformationRefresh {CacheTypeName:...}` | No |
| Feature flag toggle | (varies; flag-specific) | `POST /admin/api/FeatureManagementToggle {FeatureTypeName:...}` — **DO NOT use for Completeness flag, see [pim-completeness.md "Completeness rules" step 7](pim-completeness.md)** | Varies |
| Rule-usage inspection | (read-only) | `GET /admin/api/CompletionSettingsSourceById?Id=<ruleId>` | n/a |
| **Direct SQL INSERT/UPDATE/DELETE on `UnifiedPermission`** (entity grants, Layer A / C) | `Dynamicweb.Security.Permissions.PermissionService` ServiceCache | `POST /admin/api/CacheInformationRefresh {CacheTypeName:"Dynamicweb.Security.Permissions.PermissionService"}` | No — but logged-in users do not see the change until flush + re-auth; new logins always see fresh state. See [users-permissions.md §4c](users-permissions.md) for the admin-UI gap that forces this SQL surface. |
| **Direct SQL INSERT/UPDATE/DELETE on `CapabilityLimitation`** (UI hides, Layer B) | `Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilityService` ServiceCache | `POST /admin/api/CacheInformationRefresh {CacheTypeName:"Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilityService"}` | No — flush picks up immediately for current users. |
| **Direct SQL INSERT/UPDATE/DELETE on `CapabilitySetLimitation`** (capability-set hides) | `Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilitySetService` ServiceCache | `POST /admin/api/CacheInformationRefresh {CacheTypeName:"Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilitySetService"}` | No |
| **Direct SQL INSERT/UPDATE/DELETE on `DashboardAccessUserRelation`** (per-user dashboard pinning) | (none — `DashboardConfigurationRepository` queries the DB per request, bypassing cache) | n/a | **No** — changes are live on next dashboard tree fetch. |

## The edit-vs-insert rule for content tables (SQL-fallback surface only)

For `Page` / `Paragraph` / `GridRow` / `EcomPrices`, the cache-vs-live behavior splits cleanly along edit-vs-insert lines when mutating via SQL:

- **Editing an existing row's non-ordering fields** — live. The page-composition cache holds the row by id; on next render, DW reads the current field values back from the DB. So a SQL `UPDATE Paragraph SET ParagraphTemplate = '...' WHERE ParagraphId = N` shows up immediately on refresh, no restart.
- **Inserting a new row** — requires restart. The cache resolved the parent (Page / GridRow / shop-currency-language combination for prices) at startup or at last invalidation; it doesn't know about the new child row. Restart flushes the cache and rebuilds it from the current DB state.
- **Re-ordering existing rows** (`GridRow.GridRowSort` re-sort) — requires restart. Even though each individual row's other fields read live, the cache holds the *ordered list* and won't re-sort until reload. Same applies to `ParagraphSort` if you re-sort paragraphs within a GridRow.
- **Changing price amount or scope** — requires restart. The resolved-price cache keys by (product, currency, customer-group, shop, qty-band, validity-window) and doesn't reactively reload on column changes.

This is **the SQL-fallback rulebook only.** MCP `save_paragraphs` / `save_pages` / `save_grid_rows` / `save_prices` and the admin-UI Visual Editor invalidate the relevant caches for you — none of these rules apply to those surfaces. Choosing SQL-direct over a domain-service surface is a separate decision; when a service surface is available, prefer it and skip this section.

## The index-build-reads-through-cache ordering trap

When you write product data via **Direct SQL** (e.g. translating `ProductName` /
`ProductShortDescription` into a per-language layer, or any `EcomProducts` field edit) and then
need it visible on the storefront/Delivery API PLP, two caches are in play and **order matters**:

1. The live `ProductService` holds products in an in-memory cache. A SQL write does not touch it,
   so reads (single-product Delivery API, PDP) return the **stale** value until the cache is
   flushed (`CacheInformationRefresh`) or the host restarts. A `BuildIndex` does **not** flush it.
2. **The Lucene index builder reads product data *through* that same `ProductService` cache.** So
   if you `BuildIndex` while the cache is stale, the builder indexes the OLD values — the PLP/
   facets then show stale data even though the DB is correct and you "reindexed".

**Correct order for a SQL product-data write:** write → **flush/restart** (clear the
`ProductService` cache) → **then** `BuildIndex`. Reindex-then-restart is the wrong order: the index keeps the stale values until the *next* rebuild after a flush.

Related write-path note: MCP `patch_products_safe` with a non-default `languageId` was observed to
echo the translated `name` in its response but not persist it to the `EcomProducts` language-layer
row (DB stayed default-language) on a 10.26.x build — verify the DB row after a
per-language product-text write; direct SQL was the reliable surface.

## When a mutation doesn't show up

If a mutation looks like it should have applied but the symptom persists (a stale dashboard count, an empty completeness panel, a missing variant SKU), it's a cache the mutation surface didn't invalidate. Resolve it in order:

1. **Find the row above and run its named invalidation surface** — usually a targeted `CacheInformationRefresh` (enumerate cache ids with `GET /admin/api/GetServiceCaches`). This is the specific fix and the one to reach for first.
2. **Restart the host (`dotnet run`)** only when the row says "YES restart", or when you can't identify which cache holds the stale value. Restarting drops all in-memory state, so don't use it as the default when the table names a flush.
3. **Re-verify after the fix:** re-run your post-change verification probes — the targeted MCP/SQL checks whose result was stale.
