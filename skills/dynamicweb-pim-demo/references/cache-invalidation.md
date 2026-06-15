# cache-invalidation.md

> Post-mutation cache invalidation table for Dynamicweb 10 PIM. Use this to look up "I just mutated X — what cache do I need to flush, and do I need to restart the host?". Loaded from `~/.claude/skills/dynamicweb-pim-demo/SKILL.md` "Where to find things" table. Cross-references `governance.md` for the causal explanations behind each "YES restart" row.

## Surface scope — when this table matters

This table is the rulebook for **Direct SQL fallback** mutations and a handful of MCP/API edge cases. It is **NOT** something you read before using MCP or admin UI for the same operation:

- **MCP `save_*` / `create_or_update_*` / admin-UI Visual Editor / admin-UI form save** → these go through DW's domain services, which invalidate caches inline. You do not consult this table; you do not restart the host. The surface-priority table in [`dynamicweb-demo-base/SKILL.md` "Surface priority for CREATES"](../../dynamicweb-demo-base/SKILL.md) names these as the default for any structural CREATE for exactly this reason.
- **Management API** (`POST /admin/api/...`) → same domain services as MCP; same cache invalidation behavior. The dedicated `CacheInformationRefresh` / `BuildIndex` / `GetServiceCaches` endpoints listed below are themselves Management API calls — use them when you need to flush something explicitly without restarting. On a **hosted install** there is no restart at all: every "YES restart" row below resolves to a bulk flush instead — `GetServiceCaches` → `CacheInformationsRefresh {"Ids": [...]}` (plural, takes the service ids); recipe in [`dynamicweb-demo-base/references/online-mode.md`](../../dynamicweb-demo-base/references/online-mode.md) §"Cache refresh = the online host restart".
- **Direct SQL `INSERT` / `UPDATE`** → bypasses every domain service. Almost everything below applies to this surface. **The "Restart required" column tells you what SQL-direct seeding owes you afterward.**
- **Filesystem mutations** (`.query`, `.index`, `.cshtml` drops/edits) → mostly cache-bypassing. The `.query` row below covers the worst case.

If you used MCP for a row whose mutation type appears in the table below, you should already be done — do not "double-fix" by also restarting; the cost is a 30-second host bounce + lost in-memory state that wasn't broken in the first place.

## Post-mutation cache table

| Mutation | Cache touched | Invalidation surface | Restart required? |
|----------|---------------|----------------------|-------------------|
| MCP `create_or_update_completeness_rules` | `CompletionRuleService` ServiceCache | (auto via MCP) | No |
| Direct SQL INSERT into `EcomCompletionRules` | Same | (none — SQL bypasses cache) | YES (or save once via admin UI) — see [governance.md "Completeness rules"](governance.md) |
| MCP `create_or_update_product_queries` | `Searching:Queries` cache | (cache populated at startup; no API to invalidate) | YES on overwrite/conflict — see [governance.md "Dashboard query location"](governance.md) |
| Disk delete of `.query` file | Same | (none) | YES — see [governance.md "Dashboard query location"](governance.md) |
| MCP product mutation | Lucene index | `POST /admin/api/BuildIndex {Repository:Products,IndexName:Products.index,BuildName:Full}` | No — see [governance.md "Recovery recipe: Rebuild Products index"](governance.md) |
| Direct SQL INSERT into `EcomProductItems` | `ProductItem` Lazy<Dictionary> cache | (none) | YES — bundle Components tab will show empty until restart |
| **Direct SQL INSERT new `Page` row** | Page-resolution cache | (none) | YES — page 404s on the storefront until restart, even with correct slug/area wiring |
| **Direct SQL INSERT new `Paragraph` row** | Page-composition cache | (none) | YES — paragraph does not render until restart |
| **Direct SQL INSERT new `GridRow` row** | Page-composition cache | (none) | YES — grid row + its paragraphs do not render until restart |
| **Direct SQL INSERT new `EcomPrices` row** | Resolved-price cache | (none) | YES — new price is not picked up by PDP / cart resolution until restart |
| **Direct SQL UPDATE on an existing `Page` / `Paragraph` / `GridRow` field** (e.g. `ParagraphTemplate`, `PageMetaTitle`, content fields) | (cache holds the row by id; updated fields are read live from DB on next render) | (none needed) | **No** — live, refresh the page. This is the one safe SQL pattern for these tables. |
| **Direct SQL UPDATE on `GridRow.GridRowSort` (re-ordering existing rows)** | Page-composition cache holds the ordered list | (none) | YES — the cached ordering wins until restart, even though field updates on individual rows go live |
| **Direct SQL UPDATE on `EcomPrices.PriceAmount` / `PriceCurrency` / scope columns** | Resolved-price cache | (none) | YES — old price wins until restart |
| **Direct SQL UPDATE on `EcomOrderStates.OrderStateColor` (or other state-row columns read at render time)** | `OrderStates.GetStateById()` in-memory cache | (none) | YES — the badge's inline-style attribute holds the stale color even after a full page reload; storefront-rendered order-state badges and CSS variables fed by `Services.Orders.GetStateById(...).Color` keep the old hex until restart (2026-05-13) |
| MCP `save_paragraphs` / `save_pages` / `save_grid_rows` | Page-composition cache | (auto via MCP) | No — these are the preferred surface for content seeding; the four "Direct SQL INSERT" rows above are the SQL-fallback equivalents |
| **Paragraph-soft-hide / delete inside a `@RenderGrid(otherPageId)` nested grid** (e.g. Swift's `Swift-v2_ProductListComponentSelector` PLP wrapper) | RenderGrid HTML cache (keyed by source page id) | (none — survives host restart) | **No surface fix** — `ParagraphDeleted=1` / `ParagraphShowParagraph=0` are not observed even after restart. CSS-hide is the only reliable lever; see [`dynamicweb-swift-demo/references/paragraphs.md` "ProductListComponentSelector caches even harder"](../../dynamicweb-swift-demo/references/paragraphs.md) for the worked recipe (2026-05-13). |
| Service-cache enumerate | All services | `GET /admin/api/GetServiceCaches` | n/a (read-only) |
| Specific service cache flush | Single service | `POST /admin/api/CacheInformationRefresh {CacheTypeName:...}` | No |
| Feature flag toggle | (varies; flag-specific) | `POST /admin/api/FeatureManagementToggle {FeatureTypeName:...}` — **DO NOT use for Completeness flag, see [governance.md "Completeness rules" step 7](governance.md)** | Varies |
| Rule-usage inspection | (read-only) | `GET /admin/api/CompletionSettingsSourceById?Id=<ruleId>` | n/a |
| **Direct SQL INSERT/UPDATE/DELETE on `UnifiedPermission`** (entity grants, Layer A / C) | `Dynamicweb.Security.Permissions.PermissionService` ServiceCache | `POST /admin/api/CacheInformationRefresh {CacheTypeName:"Dynamicweb.Security.Permissions.PermissionService"}` | No — but logged-in users do not see the change until flush + re-auth; new logins always see fresh state. See [permissions-model.md §4c](permissions-model.md) for the admin-UI gap that forces this SQL surface. |
| **Direct SQL INSERT/UPDATE/DELETE on `CapabilityLimitation`** (UI hides, Layer B) | `Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilityService` ServiceCache | `POST /admin/api/CacheInformationRefresh {CacheTypeName:"Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilityService"}` | No — flush picks up immediately for current users. |
| **Direct SQL INSERT/UPDATE/DELETE on `CapabilitySetLimitation`** (capability-set hides) | `Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilitySetService` ServiceCache | `POST /admin/api/CacheInformationRefresh {CacheTypeName:"Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilitySetService"}` | No |
| **Direct SQL INSERT/UPDATE/DELETE on `DashboardAccessUserRelation`** (per-user dashboard pinning) | (none — `DashboardConfigurationRepository` queries the DB per request, bypassing cache) | n/a | **No** — changes are live on next dashboard tree fetch. |

## The edit-vs-insert rule for content tables (SQL-fallback surface only)

For `Page` / `Paragraph` / `GridRow` / `EcomPrices`, the cache-vs-live behavior splits cleanly along edit-vs-insert lines when mutating via SQL:

- **Editing an existing row's non-ordering fields** — live. The page-composition cache holds the row by id; on next render, DW reads the current field values back from the DB. So a SQL `UPDATE Paragraph SET ParagraphTemplate = '...' WHERE ParagraphId = N` shows up immediately on refresh, no restart.
- **Inserting a new row** — requires restart. The cache resolved the parent (Page / GridRow / shop-currency-language combination for prices) at startup or at last invalidation; it doesn't know about the new child row. Restart flushes the cache and rebuilds it from the current DB state.
- **Re-ordering existing rows** (`GridRow.GridRowSort` re-sort) — requires restart. Even though each individual row's other fields read live, the cache holds the *ordered list* and won't re-sort until reload. Same applies to `ParagraphSort` if you re-sort paragraphs within a GridRow.
- **Changing price amount or scope** — requires restart. The resolved-price cache keys by (product, currency, customer-group, shop, qty-band, validity-window) and doesn't reactively reload on column changes.

This is **the SQL-fallback rulebook only.** MCP `save_paragraphs` / `save_pages` / `save_grid_rows` / `save_prices` and the admin-UI Visual Editor invalidate the relevant caches for you — none of these rules apply to those surfaces. The decision to use SQL-direct over MCP is a separate question, governed by [`dynamicweb-demo-base/SKILL.md` "Surface priority for CREATES"](../../dynamicweb-demo-base/SKILL.md); when MCP is available, use it and skip this section.

## When in doubt: restart

If a mutation looks like it should have applied but the symptom (a stale dashboard count, an empty completeness panel, a missing variant SKU) persists, the safest single step is `dotnet run` restart. The host start time is bounded (~30 seconds on a warm SQL Express); a half-day of "is it cached or is it broken" is not. After restart, if a Swift baseline was previously deserialized you can re-run the integrity-sweep checks owned by Swift ([dynamicweb-swift-demo/references/integrity-sweep.md](../../dynamicweb-swift-demo/references/integrity-sweep.md)) to confirm; on a blank PIM-only DB, just re-run the targeted MCP/SQL probe whose result was stale.
