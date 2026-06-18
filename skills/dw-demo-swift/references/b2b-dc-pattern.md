# b2b-dc-pattern.md

> The canonical Dynamicweb 10 B2B pattern for any portal where pricing, stock, shipping methods, or shipping fees vary by Distribution Center (DC). Vendor-blessed by the Dynamicweb vendor architect (2026-05-13 architecture call).
>
> **This is the standard B2B mechanic in DW10, not an upgrade path.** Treat it as the default scaffold for any wholesale / B2B-distributor demo that touches DC-aware behavior â€” not as something to design when the customer asks for it explicitly. Customers expect it; framing it as bespoke would invent friction that DW10 doesn't have.

## The mechanic in one sentence

**One AccessUser group per Stock Location.** User membership in those groups (via `AccessUserGroupRelation`) then natively unlocks four stock DW10 features without any custom code:

1. **Assortments** scoped to DC user-group membership â€” DC-specific catalogs (a buyer assigned to `DC-OMA` sees only what that DC stocks).
2. **Shipping methods** filterable by user group â€” e.g. "Fast delivery" shipping method only offered to members of `DC-OMA` (where it's actually feasible).
3. **Shipping fees** with per-user-group price matrices â€” a `ShippingMethodFee` row keyed on `(method, user-group)` gives DC-specific freight.
4. **Cart-time price resolution** scoped by the same user-group â€” already covered by the stock `EcomPrices` resolver when `PriceCustomerGroup` matches a group the user is a member of. (Note: this is base-row resolution; `PriceQuantity > 0` tier rows are still ignored by the stock cart â€” see [`dynamicweb-pim-demo/references/structural-model.md` Â§2.11](../../dw-demo-pim/references/structural-model.md). The vendor-recommended pattern for qty-aware DC pricing is ERP-imported pre-graduated rows, one per (product, user-group, qty-band).)

This is *not* a custom architecture. Each of the four features is a stock DW10 surface that scopes by user-group; "DC = user group" is the convention that makes them compose.

## Naming convention

| Field | Value | Why |
|---|---|---|
| `AccessUserGroupName` (display) | e.g. `DC-OMA`, `DC-GRR`, `DC-PHX` | DC code as the suffix. Short, scannable in admin tree. |
| `AccessUserUserName` (system / login name) | same `DC-OMA` form | Consistent identifier for admin URL lookups and SQL joins. |
| `AccessUserCustomerNumber` | **same `DC-OMA` form** | This is the key bit â€” see below. |
| `AccessUserUserAndGroupType` | leave NULL | A non-NULL type **hides the group from the default admin Users tree** (see "Admin Users tree filters typed groups" below). DC groups want to be visible. |

**Why `AccessUserCustomerNumber` matches the group name.** It lets a single SQL JOIN (or a single Razor `Model.Groups.Where(g => g.CustomerNumber == userDcCode)` lookup) drive a DC-band resolver â€” no `Address.Address2`-prefix lookup, no string-parsing hack. Razor templates and dashboards that need "what DC is this user in?" answer it with one column read. Master injection (`Swift-v2_Master.cshtml`) and PDP info pane (`Swift-v2_ProductPrice.cshtml`) variants both rely on this column convention.

## User assignment

A buyer who's primarily fulfilled out of `DC-OMA` gets `AccessUserGroupRelation` rows linking them to the `DC-OMA` group. If a buyer is multi-DC (e.g. headquarters in Omaha, branch office in Phoenix), they get rows for both â€” DW's user-group resolution returns the union, so Assortments / Shipping methods filtered on either group apply.

**Don't model DC as a user attribute** (e.g. `AccessUserStockLocationID`, custom `AccessUserDCCode` field). The user-attribute path doesn't compose with Assortments / Shipping methods / fees, which all scope by *group*, not by attribute. The attribute approach forces a custom `IPriceProvider` / custom shipping-filter / custom-assortment provider â€” three pieces of code that DW already ships. `AccessUserStockLocationID` (which DW does ship as a bigint column) is fine as supplementary metadata for ERP sync, but **the DC-as-group membership is the load-bearing wiring**.

## Surface guidance for setting this up

This is structural setup, not gotcha-debugging â€” the surface-priority rule from base applies. MCP-first whenever possible.

### MCP (preferred surface for the group + user wiring)

- **`save_user_groups`** â€” create `DC-OMA`, `DC-GRR`, etc. Set `name`, `customerNumber` (same as name), leave `userAndGroupType` empty.
- **`save_users`** â€” create buyer rows with `customerNumber` matching their primary DC.
- **`save_user_group_relations`** (or equivalent â€” confirm the exact tool name at runtime via `ToolSearch`) â€” link users to the groups they belong to.

When MCP is connected and the budget is small (a handful of DCs + a few demo personas), this is the right surface. Cache invalidation is automatic; you don't restart the host.

### SQL fallback (for bulk seeding only)

When seeding tens of users across many DCs â€” typical for "make this demo feel real" data volume â€” bulk SQL is appropriate. Use the surface-priority escalation rule from [`dynamicweb-demo-base/SKILL.md` "Surface priority for CREATES"](../../dw-demo-base/SKILL.md): try MCP, escalate to SQL only for bulk cases where MCP-tool round-trips become prohibitive.

Schema notes for SQL fallback:

- **`AccessUser`** rows for groups: `AccessUserType = 1` (group), `AccessUserUserName` = `AccessUserCustomerNumber` = the DC code (e.g. `'DC-OMA'`), `AccessUserUserAndGroupType` = NULL (so the group remains visible in admin tree), `AccessUserExternalID` = NULL or your ERP key. `AccessUserActive = 1`.
- **`AccessUserGroupRelation`** rows: one per `(AccessUserUserID, AccessUserGroupID)` pair. The user-to-group relations.
- After bulk INSERT, **restart the host** to flush user/group caches â€” per [`dynamicweb-pim-demo/references/cache-invalidation.md`](../../dw-demo-pim/references/cache-invalidation.md) the user-resolution caches don't observe direct SQL writes. **Doesn't apply when** the rows came via MCP / admin UI; those invalidate inline.

**`AccessUser` NOT NULL columns that easily get skipped.** Bulk-INSERTs that pattern-copy from a partial INSERT example abort with a confusing `Cannot insert the value NULL into column '<X>'` on the first row. The columns DW10 requires NOT NULL on `AccessUser` (in addition to the obvious `AccessUserType` / `AccessUserUserName` / `AccessUserActive` you'd write anyway):

| Column | Suggested seed value |
|---|---|
| `AccessUserRead` | `0` |
| `AccessUserInheritAddress` | `0` |
| `AccessUserHideStat` | `0` |
| `AccessUserNewsletterAllowed` | `0` |
| `AccessUserReverseChargeForVat` | `0` |
| `AccessUserUniqueId` | `NEWID()` |
| `AccessUserIsServiceAccount` | `0` |

Also worth knowing: `AccessUserCreatedDate` / `AccessUserUpdatedDate` do **not** exist on the `AccessUser` table despite being common DW10 audit columns on neighbouring tables â€” don't pattern-match those in from another seed script. Run `SELECT name, is_nullable FROM sys.columns WHERE object_id = OBJECT_ID('AccessUser') AND is_nullable = 0` against the target DB if you want the authoritative list for the DW10 version on the host (the set shifts slightly across DW10 minor versions).

### Admin UI (for verification only)

- `/Admin/UI/Users` Groups tree â†’ DC groups should be visible (if hidden, check `AccessUserUserAndGroupType` is NULL â€” see next section).
- Click a group â†’ user list shows the buyers assigned to that DC.

Use this as the post-seed sanity check, not as the seeding surface â€” it's slow at scale.

## Admin Users tree filters typed groups

`AccessUserUserAndGroupType` set to any non-NULL value **hides the group from the default `/Admin/UI/Users` Groups tree**, even when:

- The type is registered in `/Files/System/UserTypes/<Name>.xml`
- The type's `AllowedParents` includes `ROOT-AND-DEFAULT`
- The host is restarted

This is a separate admin-tree filter from the "typed groups are categorised under their own admin section" expectation; both behaviors coexist and the visibility filter is the dominant one.

**For DC groups, leave `AccessUserUserAndGroupType` NULL.** DC groups belong in the default admin tree â€” they're the operator's primary nav to "which buyers are at which DC". Typed groups (e.g. a `SystemAccount` type for service accounts) are appropriate for groups the operator *should not* see in routine browsing.

**If you need a typed group and still want to navigate to it**:
- Either filter at cshtml level (`Model.Groups.Where(g => g.CustomerNumber?.StartsWith("CUST-"))`) instead of using the type column.
- OR navigate directly via `/Admin/UI/Users/UserList?GroupId=<id>` â€” typed groups are reachable by deep-link, just hidden from the default tree.

## Verification flow

After setting up DC groups + Stock Locations + per-DC Assortments + per-DC Shipping methods/fees, verify by logging in as a DC-OMA buyer and confirming:

1. PDP shows the DC-OMA assortment subset (products outside the assortment are filtered out of catalog browsing and search).
2. Cart / checkout offers the shipping methods scoped to DC-OMA, and the fee matrix shows the DC-OMA rate.
3. Order history shows orders from this buyer only.
4. Switch to a DC-GRR buyer â€” repeat the verification, confirm the differences. If both buyers see the same catalog / methods / fees, the user-group wiring isn't taking effect â€” check `AccessUserGroupRelation` rows and host restart.

## When not to use this pattern

- **Single-DC demos** â€” if the customer is single-DC and the storyline doesn't lean on "different buyer sees different stock", don't scaffold DC groups. One Assortment is fine. Adding the DC mechanic to a demo that doesn't need it is wasted complexity (and wasted customisation-budget signal in the closing slide, even though zero customisations were technically added).
- **B2C demos** â€” the DC-as-group pattern presupposes accounts-with-customer-numbers. Anonymous-buyer / B2C demos don't have the user-group hook to scope on.

For everything in between (multi-DC B2B with named buyer accounts), this is the default.

## Cross-references

- [`dynamicweb-pim-demo/references/structural-model.md` Â§2.9](../../dw-demo-pim/references/structural-model.md) â€” Assortments structural model (customer access â‰  Channels).
- [`dynamicweb-pim-demo/references/structural-model.md` Â§2.11](../../dw-demo-pim/references/structural-model.md) â€” Pricing: cart ignores `PriceQuantity > 0`; ERP-pre-graduated rows are the production pattern for qty-aware DC pricing.
- [`customer-center.md`](customer-center.md) â€” Stock Swift CSR section for sales-on-behalf; layered on top of the DC pattern when the CSR persona impersonates DC buyers.
- [`dynamicweb-demo-base/references/vendor-patterns.md`](../../dw-demo-base/references/vendor-patterns.md) â€” vendor-positioning context, including the DW vs ours skill-design differences.


