# B2B distribution-center scoping — DC-as-user-group, contract prices, seeding

Field-validated DW10 B2B distribution-center (DC) scoping knowledge: the DC-as-user-group pattern, customer-scoped contract prices, the `AccessUser` seeding schema, and the admin-tree visibility trap.

## Contents

- [The DC-as-user-group pattern](#the-dc-as-user-group-pattern)
- [A shop relation is a union, not a filter](#a-shop-relation-is-a-union-not-a-filter)
- [Contract prices: three scope columns, and which argument matches which](#contract-prices-three-scope-columns-and-which-argument-matches-which)
- [Contract-versus-list pricing per audience, with no custom code](#contract-versus-list-pricing-per-audience-with-no-custom-code)
- [Naming convention](#naming-convention)
- [User assignment](#user-assignment)
- [Surface guidance for setting this up](#surface-guidance-for-setting-this-up)
- [Admin Users tree filters typed groups](#admin-users-tree-filters-typed-groups)
- [Verification flow](#verification-flow)
- [When not to use this pattern](#when-not-to-use-this-pattern)
- [Cross-references](#cross-references)

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
4. **Cart-time price resolution** scoped by the same user-group, covered by the stock `EcomPrices`
   resolver when **`PriceUserGroupId`** names a group the user is a member of (the scope column, see
   "Contract prices" below). (Note: this is
   base-row resolution; `PriceQuantity > 0` tier rows are still ignored by the stock cart — see
   [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.11. The
   vendor-recommended pattern for qty-aware DC pricing is ERP-imported pre-graduated rows, one per
   (product, user-group, qty-band).)

This is *not* a custom architecture. Each of the four features is a stock DW10 surface that scopes
by user-group; "DC = user group" is the convention that makes them compose.

**Join a DC to its stock location on `EcomStockLocation.StockLocationExternalId`.** There is no
`Code` column on `EcomStockLocation` — the external id IS the warehouse/ERP code, and it is the
only safe join key; the full column set is `StockLocationId`, `StockLocationName`,
`StockLocationDescription`, `StockLocationLanguageId`, `StockSortOrder`, `StockLocationGroupId`,
`StockLocationCategoryId`, `StockLocationUserId`, `StockLocationExternalId`. Templates that reach
the stock location by matching its display NAME against another table's name column resolve
correctly and break the moment anyone renames a display string. With the naming convention below,
the whole chain is one key: user → group `DC-<CODE>` → `StockLocationExternalId = <CODE>`.

## A shop relation is a union, not a filter

**`assign_shops_to_assortment` widens a restricted assortment to the whole shop.** A shop relation
*means* the whole shop, and the build treats the relation set as a **union**, so adding it after the
narrow group and product relations replaces the intended scope with the entire catalogue. Measured on
two builds of the same assortment differing only in that call: with the shop relation the built item
set equalled every product in the shop; without it, exactly the intended scope. Every tool answers
success, the relation counts read back correctly and `get_assortments_for_build` comes back empty as it
should — nothing in the usual verification sees it. Add a shop relation only when the intent genuinely
is "every product in this shop".

**And it cannot be undone in place.** `remove_shops_from_assortment` answers `succeeded: 1, failed: 0`
and removes nothing: the relation survives the call, survives a re-flag and rebuild, and is still
returned by `get_assortment_relations_by_shop_id`. An assortment built wide by a shop relation is
**deleted and rebuilt**, not repaired.

**`check_assortment_product_access` answers `true` unconditionally, so it is not the gate.** Measured
against a correctly built, active, permissioned assortment: `true` for an in-scope product, `true` for
an out-of-scope product, `true` for a user holding no assortment at all, and `true` for anonymous —
surviving a targeted assortment-service flush and a full host restart. It does not consult the built
item set, so it can neither fail nor prove anything.

Verify by **reading the membership** instead: `get_assortments_by_product` must return the assortment
for an in-scope product and must not for an out-of-scope one, and the storefront catalogue must differ
between a holder and a non-holder. The built item count itself is read outside the product
([`dw-data-access/references/recipes-commerce.md`](../../dw-data-access/references/recipes-commerce.md)
"Counting an assortment's built item set").

## Contract prices: three scope columns, and which argument matches which

Contract pricing is native default-provider behavior, zero custom code (no `IPriceProvider`). The whole
question is which `EcomPrices` column carries the scope, and the two group-shaped names are not
interchangeable:

| Scope | Column | Admin API property | Matches |
|---|---|---|---|
| A DC (an `AccessUser` group) | `PriceUserGroupId` | `userGroupId` | Every member of that user group |
| One customer account | `PriceUserCustomerNumber` | `userCustomerNumber` | Every user whose `AccessUserCustomerNumber` equals it |
| A customer NUMBER, not a group | `PriceCustomerGroupId` | `groupCustomerNumber` | A customer number string, despite the column name |

**A DC-scoped contract price is `PriceUserGroupId`, and MCP `save_prices` writes it.** On MCP 0.4.4 the
price item carries `userGroupId` alongside `userId`, `userCustomerNumber` and `customerGroupId`, and the
value reaches the column: a row written with `userGroupId` set reads back from `EcomPrices` with
`PriceUserGroupId` carrying it. An earlier, narrower server exposed no such member, which is why a
group-scoped price used to be described as unreachable from the tool set and modelled as a discount
instead; that reason no longer holds, and **a group-scoped price row is a real alternative to a
discount** — one row per group per product, resolved by the stock price provider with no engine
activation, against a discount's single rule covering the whole catalogue.

Keep the column-to-argument mapping in the table above straight: `customerGroupId` writes
`PriceCustomerGroupId`, which matches a **customer number** despite the name, so passing a user-group id
there stores a number that matches nothing — the call answers `succeeded:1`, the row is visibly in
`EcomPrices`, and the group's buyers still see the list price, which reads as a price-resolution or cache
problem. `userGroupId` is the member that matches a user group.

**No catalogue-level price recalculation exists in the tool set.** `force_price_recalculation` takes an
order id and recomputes that order; called after a catalogue price write it answers the bare invocation
error. Where a price write has to become visible, the follow-up is the product-index rebuild
([`dw-data-write-effects`](../../dw-data-write-effects/SKILL.md)).

**Validate on the rendered storefront, never on the row.** Sign in as a member of the group: the PDP and
cart must show the contract price. Sign in as a non-member or stay anonymous: they see the list price. A
row-exists assertion passes while the storefront is still on list price, which is exactly the failure
this section describes. (Quantity-tier enforcement, `PriceQuantity > 0` rows, is a separate matter the
**stock cart ignores**; see
[`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.11, and the
same three-column table lives at §2.13 there.)

## Contract-versus-list pricing per audience, with no custom code

"Same catalogue, same portal: dealers see their NET with the MSRP struck through, service centres
see the MSRP only, anonymous visitors see no price" is the standard B2B ask, and the three obvious
builds — a custom `IPriceProvider`, a second shop per audience, an if-group-else in the price
template — are all unnecessary. Four stock mechanisms compose:

1. `EcomPrices` rows are scoped by `PriceUserGroupId` (the table above).
2. **`PriceIsInformative` rows honour `PriceUserGroupId` exactly like ordinary rows.** This is the
   undocumented fact the whole pattern rests on: an informative row lands on
   `ProductViewModel.PriceInformative` for members of the named group and resolves to `0` for
   everyone else.
3. Swift's shipped `Swift-v2_ProductPrice` paragraph carries a `ShowInformativePrice` item field
   that renders `PriceInformative` struck through above the price, and already guards on
   `PriceInformative.Price == 0` — so an audience with no rows falls back to
   `EcomProducts.ProductPrice` with no second number and no template branch.
4. The area's `AnonymousUsers` price setting hides both from anonymous visitors.

The recipe:

1. One user group per commercial model. **Membership in the group is the only switch** — that is
   what makes the pattern demonstrable as configuration rather than code.
2. Per product, a PAIR of rows on that `PriceUserGroupId`, written through Admin API `PriceSave`
   (MCP `save_prices` cannot reach `PriceUserGroupId`, above): `PriceIsInformative = 0` carrying
   the contract/NET amount, and `PriceIsInformative = 1` carrying the list/MSRP amount.
3. **The audience that sees list pricing is configured by having NO price rows**, not by a rule.
4. Switch `ShowInformativePrice` on for the PDP and PLP price paragraphs — a shipped item field
   that the baseline leaves off.
5. Wording only ("Your dealer NET" rather than "RRP") rides an alternate paragraph template
   selected per paragraph through `Paragraph.ParagraphTemplate`, so the stock template stays
   byte-untouched.

**Probe the pair on ONE product before generating hundreds.** Write the two rows, fetch the PDP as
a member and as a non-member, and confirm the member sees both numbers and the non-member sees the
single list number with the contract amount absent from the response. One install generated 414
rows over 160 products only after that two-row probe.

Two follow-ons a storefront hits immediately: the `schema.org` offer price legitimately becomes the
contract price for a signed-in member, so any assertion on `itemprop="price"` has to become
per-audience assertions rather than one; and quantity-break rows need the price-table paragraph to
sit in its own grid row.

## Naming convention

| Field | Value | Why |
|---|---|---|
| `AccessUserGroupName` (display) | the DC code (e.g. `DC-<CODE>`) | Short, scannable in admin tree. |
| `AccessUserUserName` (system / login name) | same `DC-<CODE>` form | Consistent identifier for admin URL lookups and SQL joins. |
| `AccessUserCustomerNumber` | **same `DC-<CODE>` form** | This is the key bit — see below. |
| `AccessUserUserAndGroupType` | leave NULL **for a DC scoping group** | A non-NULL type **hides the group from the default admin Users tree** (see "Admin Users tree filters typed groups" below). DC groups want to be visible. A **B2B account group** is the other role and needs `SystemAccount`; see below. |

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

When the people in those groups are single-identity buyers (one person, one account, one login), the
DC-group wiring above still holds but the user SHAPE has no clean answer in Swift 2.4: section 17 of
[`user-group-operations.md`](../../dw-users-permissions/references/user-group-operations.md) carries the
`Login.xml` `AllowedParents` trade-off and the recommended default.

## Surface guidance for setting this up

Structural setup, not gotcha-debugging — prefer MCP whenever possible; escalate to SQL only for bulk.

### MCP (preferred surface for the group + user wiring)

- **`save_user_groups`** — create the DC groups. Set `name`, `customerNumber` (same as name), leave
  `userAndGroupType` empty.
- **`create_users`** (`update_users` for an existing row) — create buyer rows with
  `customerNumber` matching their primary DC. No save_users tool is registered.
- **`assign_users_to_group`**, or **`assign_groups_to_user`** from the other side — link users to
  the groups they belong to. There is no relation-row tool; both take the pair directly.

When MCP is connected and the volume is small (a handful of DCs + a few personas), this is the right
surface. Cache invalidation is automatic; no host restart.

### SQL fallback (for bulk seeding only)

When seeding tens of users across many DCs, bulk SQL is appropriate. Try MCP first, escalate to SQL
only for bulk cases where MCP-tool round-trips become prohibitive.

Schema notes for SQL fallback:

- **`AccessUser`** rows for groups: `AccessUserType = 1` (group), `AccessUserUserName` =
  `AccessUserCustomerNumber` = the DC code, `AccessUserUserAndGroupType` = NULL (so the group
  remains visible in admin tree), `AccessUserExternalID` = NULL or your ERP key. `AccessUserActive = 1`.
- **`AccessUserGroupRelation`** rows: one per `(AccessUserUserID, AccessUserGroupID)` pair.
- After bulk INSERT, **restart the host** to flush user/group caches — the user-resolution caches
  don't observe direct SQL writes. **Doesn't apply when** the rows came via MCP / admin UI; those
  invalidate inline.

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

**For a DC scoping group, leave `AccessUserUserAndGroupType` NULL.** DC groups belong in the
default admin Users tree, and a non-NULL type hides them from it.

**The opposite rule applies to a B2B account group**, which must carry
`AccessUserUserAndGroupType = 'SystemAccount'` or it never lists under Accounts — the Accounts
page filters on exactly that value. The two rules are not in conflict: they are two different group
roles reading the same column. State which role a group plays before setting the column. The
account-group side is in
[`dw-commerce-orders/references/order-lifecycle.md`](../../dw-commerce-orders/references/order-lifecycle.md)
"Why the Accounts page can be empty while Users is populated".

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

- [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.9 —
  Assortments structural model (customer access ≠ Channels); §2.11 — cart ignores
  `PriceQuantity > 0`; ERP-pre-graduated rows are the production pattern for qty-aware DC pricing.
- [`order-lifecycle.md`](../../dw-commerce-orders/references/order-lifecycle.md) — CSR
  sales-on-behalf / impersonation, layered on top of the DC pattern when a CSR persona impersonates
  DC buyers.
- [`permission-layers.md`](../../dw-users-permissions/references/permission-layers.md) —
  `AccessUserGroup` membership resolution ("highest level wins" across a user's groups), which is
  what makes union-of-DCs work.
