# customer-center.md

## Contents

- [1. Why this rule exists](#1-why-this-rule-exists)
- [2. Page-tree map](#2-page-tree-map)
- [3. CSR sales-on-behalf mechanics — foundational](#3-csr-sales-on-behalf-mechanics--foundational)
- [4. What to do when the section "looks empty"](#4-what-to-do-when-the-section-looks-empty)
- [5. Persona presentation: avatar + role badge](#5-persona-presentation-avatar--role-badge)

> The Swift 2.2 customer-center frontend playbook for Dynamicweb 10 demos. Covers the page-tree map (Account vs CSR vs legacy nav vs Overview), the stock-CSR rule rationale (inoculation against the rebuild-the-CSR-section trap in sales-on-behalf demos), and the persona presentation layer. The deeper, vendor-generic mechanics (impersonation, the `AccessUserSecondaryRelation` grant, reorder, seeding filters, permission gating, contract pricing) are owned by foundational skills — see §3.
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## 1. Why this rule exists

Customer 360 / sales-on-behalf -- a typical B2B-distributor differentiator -- is only a differentiator if the CSR can do it without custom code. The stock Swift 2.2 CSR section under `Customer center/CSR/{Orders, Accounts, Carts, Users}` is paragraph-bound to specific Swift 2.2 customer-center web-app paragraph types (e.g. `paragraph-c1-1.yml`). Rebuilding the section from scratch loses these bindings and burns the customisation budget -- the very budget the demo's closing customisation-budget slide celebrates.

The detection signature for the rebuild trap is "demo-builder lands on the CSR Overview page during a fresh re-skin and sees empty grid rows / no test orders / no users in the accounts list, then deletes the page and scaffolds a custom one." The correct move when that symptom appears:

1. Verify the logged-in user has CSR group permissions (`EcomCustomers.GroupId` mapping)
2. Verify orders exist and are tied to a customer the CSR can impersonate
3. Re-theme without touching page structure (see [re-skin.md](re-skin.md))

Rebuilding is never the right answer. The stock section already supports impersonation, mixed-source order viewing (the `OrderSource` discriminator badge needed for sales-on-behalf demos lives in the stock paragraph's templating), cart-pollution prevention, and one-click exit-impersonation. **Even when [re-skin.md](re-skin.md) §Pixel-perfect escalation authorises a new content layout `.cshtml`, the CSR section's stock paragraphs are exempt** -- overriding their layouts loses the wiring that makes sales-on-behalf trivial.

## 2. Page-tree map

Source-of-truth: `<demo-root>\distribution\layers\base\replace\_content\Swift 2\Customer center\` deserialized into a running host. Backtick-quote any path string when copying into other tools -- folder names contain spaces.

```
Customer center/
├── Account/                      ← logged-in customer's own self-service
│   ├── Orders/         (page.yml + grid-row-1/{grid-row.yml, paragraph-c1-1.yml})
│   ├── Carts/, Quotes/, Users/, Addresses/, Favorites/
├── CSR/                          ← THE STOCK SALES-ON-BEHALF SECTION (never rebuild)
│   ├── Orders/, Accounts/, Carts/, Users/
├── Customer center/              ← legacy/alt nav under same top-level
│   └── My profile/, My addresses/, My carts/, My quotes/, My favorites/, My returns/, Change password/, ...
└── Overview/                     ← landing page
```

From base **2.3.2** the Overview landing is a **tile dashboard** (stock `Swift-v2_Feature` cards linking to Orders / Quotes / Carts / Favorites / Addresses / Profile / Returns), not a bare order list, and a stock **My returns** RMA page (`eCom_CustomerExperienceCenterRma`) ships in the buyer `Customer center/` tree. Seed every list those tiles open onto — see [dashboard-seeding.md](dashboard-seeding.md).

From base **2.4.0** the Overview is a **per-role tile dashboard on one shared page**: the buyer tiles (Orders / Quotes / Carts / Favorites / Addresses / Profile / Returns) AND the CSR tiles (Accounts / Orders / Carts / Users) live on the same `Overview` page, each tile (and its grid row) carrying a serialized `permissions:` block so a buyer sees only buyer tiles and a CSR sees only CSR tiles — no code, no split landing. The old separate `CSR/` tile dashboard was retired (its function pages stay); a CSR now lands on the same Overview and sees the CSR tiles. This gating is derived entirely from the base-layer YAML (serializer ≥ 0.8.0-beta) — see §3 and [`users-permissions.md`](../../dw-demo-base/references/foundational/users-permissions.md) §15.

This is the canonical tree any Customer-360 / sales-on-behalf demo references (`Customer center/CSR/{Orders, Accounts, Carts, Users}`). It's pre-built, paragraph-driven, requires no custom Razor.

**The impersonation entrypoint is the `Customer center/CSR/Users/` page, not `CSR/Accounts/`.** Accounts is by design a company directory (no impersonate button); Users lists individual users and carries the "Impersonate" link. Opening Accounts and seeing "no impersonate button" is expected — send the CSR to Users. The full mechanics are foundational (§3).

## 3. CSR sales-on-behalf mechanics — foundational

The vendor-generic mechanics behind this section are owned by foundational skills; this demo file only carries the stock-CSR rule (§1), the page tree (§2), and the persona presentation (§5).

- **Impersonation flow** (the `?NowImpersonating=true&DWExtranetSecondaryUserSelector=…&Redirect=…` command, the Accounts-vs-Users page distinction, the `SystemAccount` `ListGroupType` filter that decides whether an account lists under CSR/Accounts), **the `AccessUserSecondaryRelation` grant** (the impersonator/customer column direction + the required Secondary-user index rebuild + user-cache clear), **the reorder mechanic** (`cartcmd=copyorder` / `CustomerCenterCmd=Reorder` — both append to an existing active cart and no-op without one — plus the `cartcmd=add/remove/delete/empty/update` family), and **seeding the section's demo data** (`OrderComplete=1` so placed orders show in "My orders"; favorites SQL NOT-NULL columns; the profile-address-vs-`UserAddress` checkout gotcha): vendor-generic CSR / order knowledge is owned by the `dw-commerce-orders` foundational skill — staged in [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) ("CSR sales-on-behalf — impersonation mechanics", "Reorder a past order", "Seeding the CSR/account section's demo data").
- **Hiding the CSR section from non-CSR users, gating buyer (Account) sections away from a pure CSR persona, the highest-level-wins frontend resolution rule, and the CC-nav-renders-through-three-templates map**: vendor-generic permission-gating is owned by the `dw-users-permissions` foundational skill — staged in [`users-permissions.md`](../../dw-demo-base/references/foundational/users-permissions.md) §15 ("Render-time half — page/paragraph permissions"). **Canonical gate (base ≥ 2.4.0 on serializer ≥ 0.8.0-beta): the `permissions:` blocks are carried IN THE BASE LAYER YAML** — on pages, grid rows, AND paragraphs — and deserialize straight into `UnifiedPermission` (page/grid-row/paragraph rows). No live admin-panel or SQL step after deserialize: the gate is already in the layer. **Per-role tiles on ONE shared Overview page are the stock pattern** (buyer tiles gated `Customers=all / CSR=none`, CSR tiles `CSR=all / Customers=none`, all `Anonymous=none`); the separate CSR split-landing is retired. The live post-deserialize `UnifiedPermission` seed (admin Permissions panel / SQL INSERT + cache flush) is now a **legacy fallback** for older bases/engines only. Verify the YAML-carried gating applied with the Foundry permissions-parity check (every serialized block ⇔ matching `UnifiedPermission` rows). Never gate via per-template `foreach` filters or raw `SELECT FROM AccessUserGroupRelation`.
- **Customer-specific (contract) pricing** (scope by customer number not `customerGroupId`; lowest matching price wins; resolves live in cart/checkout not PLP/PDP; the `force_price_recalculation` verification trap): vendor-generic catalog/pricing knowledge is owned by the `dw-commerce-catalog` foundational skill — staged in [`commerce-catalog.md`](../../dw-demo-base/references/foundational/commerce-catalog.md) §2.13.

  **Presenter note — the PDP header "from" price is expected behaviour, not a pricing bug.** Stock Swift's PDP header renders the **master product "from" price**; the resolved variant + customer-affiliation/contract price is computed only in **cart/order context**. So the header price legitimately differs from what the cart later shows for a specific variant or a logged-in contract customer — this is not a defect and does not need debugging during polish. Present it by walking the price down the cascade: show the master "from" price on the PDP, then add to cart / sign in as the contract customer and let the **cart** reveal the resolved price. (This is the PDP-header face of the "resolves live in cart/checkout not PLP/PDP" rule above.)

## 4. What to do when the section "looks empty"

Symptom: CSR Overview page has empty grid rows, or `CSR/Orders/` shows no orders, or `CSR/Accounts/` is blank. Cause is almost always one of (demo-side diagnosis):

1. **No orders / users seeded** -- the customer-flavoured baseline (`<demo>-base/`) hasn't been deserialized yet, or only the generic `Swift2.2` baseline has been loaded. Run [`deserialize-flow.md`](deserialize-flow.md) first against the appropriate baseline. The seeding mechanics (`OrderComplete=1`, favorites NOT-NULL, profile-address-for-checkout) are foundational — see [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) "Seeding the CSR/account section's demo data".
2. **Logged-in user is not in a CSR group** -- `EcomCustomers.GroupId` doesn't include a CSR-permission UserGroup row. The customer-flavoured baseline is expected to seed a CSR sample user; the stock `AdminUser` default has admin perms but isn't in a customer-facing CSR group.
3. **CSR ↔ customer grants not wired** -- `AccessUserSecondaryRelation` is empty for this CSR, or the column direction is inverted, or the required index-rebuild + cache-clear follow-up was skipped. See [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) "`AccessUserSecondaryRelation` — the impersonation grant".
4. **Index not built or cache stale after wiring the grant** -- see [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md). For Products-index rebuilds, see [dynamicweb-pim-demo/references/governance.md "Recovery recipe: Rebuild Products index"](../../dw-demo-pim/references/governance.md).

What is NOT the cause: missing paragraphs / broken templates / Swift 2.3 incompatibility. The swift/2.3 baseline is verified working by [`deserialize-flow.md`](deserialize-flow.md); if the page renders at all, the structure is intact and the issue is data-side.

Once the diagnosis is "data-side", drive the fix from [dashboard-seeding.md](dashboard-seeding.md) — the per-tile seed checklist that makes every buyer and CSR list land (the "no empty lists on demo day" bar).

## 5. Persona presentation: avatar + role badge

A demo with multiple personas (customer admin / buyer / browse / CSR) lands harder when the storefront makes the persona switch *visible*. Stock Swift renders every signed-in user the same: blue avatar circle + name. To distinguish:

- Derive a role from `AccessUser.AccessUserCustomerNumber` suffix (a per-demo convention — e.g. `...-ADMIN`, `...-OWNER`, `...-BUYER`, `...-BROWSE`) **plus** CSR group membership via `Pageview.User.GetGroups()` (the suffix-as-role flag and the `GetGroups()` accessor are foundational — see [`users-permissions.md`](../../dw-demo-base/references/foundational/users-permissions.md) §16 and [`render-viewmodels.md`](../../dw-demo-base/references/foundational/render-viewmodels.md)).
- Map each role to a **ring color** + **badge background/foreground**. Suggested palette: blue for admin/owner, teal for buyer, gray for browse, amber for CSR. (Adjust per-demo to fit the brand layer.)
- Render in **both** avatar templates: `Users/UserView/Detail/UserAvatar.cshtml` (header top-right) AND `Users/UserView/Detail/UserInfo.cshtml` (the bigger avatar inside the CC sidebar). Same logic, same palette — keep them visually consistent or the persona signal feels accidental rather than designed.
- Add the user's `Company` field below the role badge — distinguishes one buyer's company name from another's at a glance.

The avatar ring is best done with `box-shadow: 0 0 0 3px <color>` on the wrapper rather than `border` (border affects layout; box-shadow doesn't). The badge is a single `<span class="badge">` with inline `style=` for color tokens; consume from `--<brand>-primary` / `--<brand>-charcoal` style vars per [re-skin.md](re-skin.md) so the brand layer flows through.
