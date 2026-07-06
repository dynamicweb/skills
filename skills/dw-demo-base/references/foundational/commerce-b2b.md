# Foundational candidate → dw-commerce-b2b

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 B2B distribution-center (DC) scoping knowledge, staged here for a future
> fold-up into `dw-commerce-b2b`. No demo/customer content. When folded, move this body into
> `dw-commerce-b2b` and re-target the pointers in the demo skills. Until then, the demo skills
> reference this file.

## The DC-as-user-group pattern

The canonical Dynamicweb 10 B2B pattern for any portal where pricing, stock, shipping methods, or
shipping fees vary by Distribution Center (DC). Vendor-blessed (Dynamicweb architecture guidance).
**This is the standard B2B mechanic in DW10, not an upgrade path** — the default scaffold for any
wholesale / B2B-distributor scenario that touches DC-aware behavior.

### The mechanic in one sentence

**One AccessUser group per Stock Location.** User membership in those groups (via
`AccessUserGroupRelation`) then natively unlocks four stock DW10 features without any custom code:

1. **Assortments** scoped to DC user-group membership — DC-specific catalogs (a buyer assigned to a
   given DC group sees only what that DC stocks).
2. **Shipping methods** filterable by user group — e.g. a "Fast delivery" method offered only to
   members of a DC where it's feasible.
3. **Shipping fees** with per-user-group price matrices — a `ShippingMethodFee` row keyed on
   `(method, user-group)` gives DC-specific freight.
4. **Cart-time price resolution** scoped by the same user-group — covered by the stock `EcomPrices`
   resolver when `PriceCustomerGroup` matches a group the user is a member of. (Note: this is
   base-row resolution; `PriceQuantity > 0` tier rows are still ignored by the stock cart — see
   [`commerce-catalog.md`](commerce-catalog.md) §2.11. The vendor-recommended pattern for qty-aware
   DC pricing is ERP-imported pre-graduated rows, one per (product, user-group, qty-band).)

This is *not* a custom architecture. Each of the four features is a stock DW10 surface that scopes
by user-group; "DC = user group" is the convention that makes them compose.

## Customer-scoped contract prices — `save_prices` can't set the customer number

A **contract price** scoped to one customer account (not a whole user-group) lives in an `EcomPrices`
row whose **`PriceUserCustomerNumber`** equals the buyer's `AccessUserCustomerNumber`. The stock price
resolver applies that row when the signed-in buyer's customer number matches — **contract pricing is
native default-provider behavior, zero custom code** (no `IPriceProvider`). The gap is authoring: the
MCP **`save_prices` tool has no `PriceUserCustomerNumber` parameter** — it can set list / currency /
`PriceCustomerGroup`-scoped rows, but **cannot scope a row to a customer number**. Author the contract
row via SQL:

```sql
-- Confirm the row's NOT-NULL columns first:
--   SELECT name, is_nullable FROM sys.columns WHERE object_id = OBJECT_ID('EcomPrices') AND is_nullable = 0;
INSERT INTO EcomPrices (PriceProductId, PriceCurrencyCode, PriceAmount, PriceUserCustomerNumber /*, …*/)
VALUES (N'<productId>', N'<CUR>', <amount>, N'<buyer AccessUserCustomerNumber>' /*, … */);
```

Restart or flush the price cache after a direct SQL write (see [`cache-invalidation.md`](cache-invalidation.md)).
**Validate:** sign in as that buyer → the PDP / cart shows the contract price; sign in as a different
buyer → they see the list price. (Contract price = per-customer; the group-scoped `PriceCustomerGroup`
resolver of §"Cart-time price resolution" is the per-DC-group counterpart. Quantity-tier
enforcement — `PriceQuantity > 0` rows — is a separate matter the **stock cart ignores**; see
[`commerce-catalog.md`](commerce-catalog.md) §2.11.)

## Naming convention

| Field | Value | Why |
|---|---|---|
| `AccessUserGroupName` (display) | the DC code (e.g. `DC-<CODE>`) | Short, scannable in admin tree. |
| `AccessUserUserName` (system / login name) | same `DC-<CODE>` form | Consistent identifier for admin URL lookups and SQL joins. |
| `AccessUserCustomerNumber` | **same `DC-<CODE>` form** | This is the key bit — see below. |
| `AccessUserUserAndGroupType` | leave NULL | A non-NULL type **hides the group from the default admin Users tree** (see "Admin Users tree filters typed groups" below). DC groups want to be visible. |

**Why `AccessUserCustomerNumber` matches the group name.** It lets a single SQL JOIN (or a single
Razor `Model.Groups.Where(g => g.CustomerNumber == userDcCode)` lookup) drive a DC-band resolver —
no address-field-prefix lookup, no string-parsing hack. Razor templates and dashboards that need
"what DC is this user in?" answer it with one column read. Master-template injection and PDP
price-pane variants both rely on this column convention.

## User assignment

A buyer primarily fulfilled out of one DC gets `AccessUserGroupRelation` rows linking them to that
DC group. A multi-DC buyer (e.g. headquarters in one city, branch office in another) gets rows for
both — DW's user-group resolution returns the union, so Assortments / Shipping methods filtered on
either group apply.

**Model DC as group membership, not as a user attribute** (e.g. `AccessUserStockLocationID`, a
custom `AccessUserDCCode` field). The user-attribute path doesn't compose with Assortments /
Shipping methods / fees, which all scope by *group*, not by attribute. The attribute approach forces
a custom `IPriceProvider` / custom shipping-filter / custom-assortment provider — three pieces of
code that DW already ships. `AccessUserStockLocationID` (which DW does ship as a bigint column) is
fine as supplementary metadata for ERP sync, but **the DC-as-group membership is the load-bearing
wiring**.

## Surface guidance for setting this up

Structural setup, not gotcha-debugging — the surface-priority rule applies. MCP-first whenever
possible.

### MCP (preferred surface for the group + user wiring)

- **`save_user_groups`** — create the DC groups. Set `name`, `customerNumber` (same as name), leave
  `userAndGroupType` empty.
- **`save_users`** — create buyer rows with `customerNumber` matching their primary DC.
- **`save_user_group_relations`** (or equivalent — confirm the exact tool name at runtime via
  `ToolSearch`) — link users to the groups they belong to.

When MCP is connected and the volume is small (a handful of DCs + a few personas), this is the right
surface. Cache invalidation is automatic; no host restart.

### SQL fallback (for bulk seeding only)

When seeding tens of users across many DCs, bulk SQL is appropriate. Use the surface-priority
escalation rule — try MCP, escalate to SQL only for bulk cases where MCP-tool round-trips become
prohibitive.

Schema notes for SQL fallback:

- **`AccessUser`** rows for groups: `AccessUserType = 1` (group), `AccessUserUserName` =
  `AccessUserCustomerNumber` = the DC code, `AccessUserUserAndGroupType` = NULL (so the group
  remains visible in admin tree), `AccessUserExternalID` = NULL or your ERP key. `AccessUserActive = 1`.
- **`AccessUserGroupRelation`** rows: one per `(AccessUserUserID, AccessUserGroupID)` pair.
- After bulk INSERT, **restart the host** to flush user/group caches — per
  [`cache-invalidation.md`](cache-invalidation.md) the user-resolution caches don't observe direct
  SQL writes. **Doesn't apply when** the rows came via MCP / admin UI; those invalidate inline.

**`AccessUser` NOT NULL columns that easily get skipped.** Bulk-INSERTs that pattern-copy from a
partial INSERT example abort with a confusing `Cannot insert the value NULL into column '<X>'` on
the first row. The columns DW10 requires NOT NULL on `AccessUser` (beyond the obvious
`AccessUserType` / `AccessUserUserName` / `AccessUserActive`):

| Column | Suggested seed value |
|---|---|
| `AccessUserRead` | `0` |
| `AccessUserInheritAddress` | `0` |
| `AccessUserHideStat` | `0` |
| `AccessUserNewsletterAllowed` | `0` |
| `AccessUserReverseChargeForVat` | `0` |
| `AccessUserUniqueId` | `NEWID()` |
| `AccessUserIsServiceAccount` | `0` |

Also: `AccessUserCreatedDate` / `AccessUserUpdatedDate` do **not** exist on the `AccessUser` table
despite being common DW10 audit columns on neighbouring tables — don't pattern-match those in from
another seed script. Run `SELECT name, is_nullable FROM sys.columns WHERE object_id =
OBJECT_ID('AccessUser') AND is_nullable = 0` against the target DB for the authoritative list on the
host's DW10 version (the set shifts slightly across DW10 minor versions).

### Admin UI (for verification only)

- `/Admin/UI/Users` Groups tree → DC groups should be visible (if hidden, check
  `AccessUserUserAndGroupType` is NULL — see next section).
- Click a group → user list shows the buyers assigned to that DC.

Use this as the post-seed sanity check, not as the seeding surface — it's slow at scale.

## Admin Users tree filters typed groups

`AccessUserUserAndGroupType` set to any non-NULL value **hides the group from the default
`/Admin/UI/Users` Groups tree**, even when:

- The type is registered in `/Files/System/UserTypes/<Name>.xml`
- The type's `AllowedParents` includes `ROOT-AND-DEFAULT`
- The host is restarted

This is a separate admin-tree filter from the "typed groups are categorised under their own admin
section" expectation; both behaviors coexist and the visibility filter is the dominant one.

**For DC groups, leave `AccessUserUserAndGroupType` NULL.** DC groups belong in the default admin
tree. Typed groups (e.g. a `SystemAccount` type for service accounts) are appropriate for groups the
operator *should not* see in routine browsing.

**If you need a typed group and still want to navigate to it**:
- Either filter at cshtml level (`Model.Groups.Where(g => g.CustomerNumber?.StartsWith("..."))`)
  instead of using the type column.
- OR navigate directly via `/Admin/UI/Users/UserList?GroupId=<id>` — typed groups are reachable by
  deep-link, just hidden from the default tree.

## Verification flow

**Prove the cart in a browser, not with curl.** Swift's add-to-cart / cart-update is **client-side JS
(htmx / AJAX)** — a `curl` / `Invoke-RestMethod` GET or POST does not exercise it and returns the empty
pre-cart page, which reads as a false "cart is broken". Drive the add-to-cart → cart → price-check flow
through browser automation (Playwright) signed in as the buyer; the raw-HTTP surfaces only prove
server-rendered state (PLP, PDP price pane), not the cart round-trip.

After setting up DC groups + Stock Locations + per-DC Assortments + per-DC Shipping methods/fees,
verify by logging in as a buyer in one DC group and confirming:

1. PDP shows that DC's assortment subset (products outside the assortment are filtered out of
   catalog browsing and search).
2. Cart / checkout offers the shipping methods scoped to that DC, and the fee matrix shows the DC's
   rate.
3. Order history shows orders from this buyer only.
4. Switch to a buyer in a different DC group — repeat, confirm the differences. If both buyers see
   the same catalog / methods / fees, the user-group wiring isn't taking effect — check
   `AccessUserGroupRelation` rows and host restart.

## When not to use this pattern

- **Single-DC scenarios** — if the use case doesn't involve "different buyer sees different stock",
  don't scaffold DC groups. One Assortment is fine. Adding the DC mechanic where it isn't needed is
  wasted complexity.
- **B2C scenarios** — the DC-as-group pattern presupposes accounts-with-customer-numbers.
  Anonymous-buyer / B2C flows don't have the user-group hook to scope on.

For everything in between (multi-DC B2B with named buyer accounts), this is the default.

## Cross-references

- [`commerce-catalog.md`](commerce-catalog.md) §2.9 — Assortments structural model (customer access
  ≠ Channels); §2.11 — cart ignores `PriceQuantity > 0`; ERP-pre-graduated rows are the production
  pattern for qty-aware DC pricing.
- [`commerce-orders.md`](commerce-orders.md) — CSR sales-on-behalf / impersonation, layered on top
  of the DC pattern when a CSR persona impersonates DC buyers.
- [`data-access.md`](data-access.md) — the SQL-fallback surface for bulk `AccessUser` /
  `AccessUserGroupRelation` seeding.
- [`users-permissions.md`](users-permissions.md) — `AccessUserGroup` membership resolution
  ("highest level wins" across a user's groups), which is what makes union-of-DCs work.
