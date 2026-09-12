# customer-center.md

## Contents

- [1. Why this rule exists](#1-why-this-rule-exists)
- [2. Page-tree map](#2-page-tree-map)
- [3. CSR sales-on-behalf mechanics — foundational](#3-csr-sales-on-behalf-mechanics--foundational)
- [4. What to do when the section "looks empty"](#4-what-to-do-when-the-section-looks-empty)
- [5. Persona presentation: avatar + role badge](#5-persona-presentation-avatar--role-badge)
- [6. Sign-in profiles / switch user (Swift 2.4) — not impersonation](#6-sign-in-profiles--switch-user-swift-24--not-impersonation)
- [7. Signing in AS a persona — the field names, and the right assertion target](#7-signing-in-as-a-persona--the-field-names-and-the-right-assertion-target)
- [8. Renaming a persona is a sweep, not a user edit](#8-renaming-a-persona-is-a-sweep-not-a-user-edit)
- [9. Checkout — paths, method names, delivery date and custom order fields](#9-checkout--paths-method-names-delivery-date-and-custom-order-fields)
- [10. The storefront account-admin page (Swift 2.4 UserGroups app)](#10-the-storefront-account-admin-page-swift-24-usergroups-app)
- [11. The B2B DC pattern (one AccessUser group per Stock Location)](#11-the-b2b-dc-pattern-one-accessuser-group-per-stock-location)

> The Swift customer-center frontend playbook for Dynamicweb 10 demos. Covers the page-tree map (Account vs CSR vs legacy nav vs Overview), the stock-CSR rule rationale (inoculation against the rebuild-the-CSR-section trap in sales-on-behalf demos), the persona presentation layer, the Swift 2.4 sign-in profiles / switch-user recipe (§6), the checkout order-field recipe (§9), the storefront account-admin page (§10), and the B2B DC pattern (§11). The deeper, vendor-generic mechanics (impersonation, the `AccessUserSecondaryRelation` grant, reorder, seeding filters, permission gating, contract pricing) are owned by foundational skills — see §3.
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

Source-of-truth: `<demo-root>\distribution\layers\surface-swift\replace\_content\Swift 2\Customer center\` deserialized into a running host. Backtick-quote any path string when copying into other tools -- folder names contain spaces.

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

From base **2.4.0** the Overview is a **per-role tile dashboard on one shared page**: the buyer tiles (Orders / Quotes / Carts / Favorites / Addresses / Profile / Returns) AND the CSR tiles (Accounts / Orders / Carts / Users) live on the same `Overview` page, each tile (and its grid row) carrying a serialized `permissions:` block so a buyer sees only buyer tiles and a CSR sees only CSR tiles — no code, no split landing. The old separate `CSR/` tile dashboard was retired (its function pages stay); a CSR now lands on the same Overview and sees the CSR tiles. This gating is derived entirely from the base-layer YAML (serializer ≥ 0.8.0-beta) — see §3 and [`page-gating.md`](../../dw-users-permissions/references/page-gating.md) §15.

This is the canonical tree any Customer-360 / sales-on-behalf demo references (`Customer center/CSR/{Orders, Accounts, Carts, Users}`). It's pre-built, paragraph-driven, requires no custom Razor.

**Prove a CSR gate as a PAIR, by page id, on the body length.** The natural negative check — sign in as a
buyer-only persona, fetch the CSR accounts path, expect something other than a 200 with content — fails
twice over on this tree. First, the CSR subtree commonly has **no resolvable friendly URL**: the composed
path 404s for every persona, the authorised CSR included, so the check passes without ever reaching the
gate and would pass identically on a solution with the exposure it exists to catch. Second, a denied Swift
page answers **HTTP 200 with a near-empty body** (a low-hundreds-of-bytes shell), so no status-code
comparison can see the deny either. The runnable form:

1. Read the CSR page ids from the page tree (`get_pages_by_parent_id` down the `Customer center/CSR/`
   branch) rather than composing a path from memory.
2. Fetch the SAME page id as the denied persona **and** as the authorised CSR persona, in one pass:
   `/Default.aspx?ID=<pageId>` addresses a page by id whatever its url resolution does.
3. PASS requires **both** halves: the CSR persona receives a full page, and the denied persona receives a
   body an order of magnitude smaller. A run where both personas receive the same response is a broken
   assert, not a pass — including the run where both receive 404.

An assert that never succeeds for the authorised persona is not a gate. The vendor-generic half of this
rule lives in [`page-gating.md`](../../dw-users-permissions/references/page-gating.md) §15.

**The impersonation entrypoint is the `Customer center/CSR/Users/` page, not `CSR/Accounts/`.** Accounts is by design a company directory (no impersonate button); Users lists individual users and carries the "Impersonate" link. Opening Accounts and seeing "no impersonate button" is expected — send the CSR to Users. The full mechanics are foundational (§3).

## 3. CSR sales-on-behalf mechanics — foundational

The vendor-generic mechanics behind this section are owned by foundational skills; this demo file only carries the stock-CSR rule (§1), the page tree (§2), and the persona presentation (§5).

- **Impersonation flow** (the `?NowImpersonating=true&DWExtranetSecondaryUserSelector=…&Redirect=…` command, the Accounts-vs-Users page distinction, the `SystemAccount` `ListGroupType` filter that decides whether an account lists under CSR/Accounts), **the `AccessUserSecondaryRelation` grant** (the impersonator/customer column direction + the required Secondary-user index rebuild + user-cache clear), **the reorder mechanic** (`cartcmd=copyorder` / `CustomerCenterCmd=Reorder` — both append to an existing active cart and no-op without one — plus the `cartcmd=add/remove/delete/empty/update` family), and **seeding the section's demo data** (`OrderComplete=1` so placed orders show in "My orders"; favorites SQL NOT-NULL columns; the profile-address-vs-`UserAddress` checkout gotcha): vendor-generic CSR / order knowledge is owned by the `dw-commerce-orders` foundational skill — staged in [`order-lifecycle.md`](../../dw-commerce-orders/references/order-lifecycle.md) ("CSR sales-on-behalf — impersonation mechanics", "Reorder a past order", "Seeding the CSR/account section's demo data").
- **Hiding the CSR section from non-CSR users, gating buyer (Account) sections away from a pure CSR persona, the highest-level-wins frontend resolution rule, and the CC-nav-renders-through-three-templates map**: vendor-generic permission-gating is owned by the `dw-users-permissions` foundational skill — staged in [`page-gating.md`](../../dw-users-permissions/references/page-gating.md) §15 ("Render-time half — page/paragraph permissions"). **Canonical gate (base ≥ 2.4.0 on serializer ≥ 0.8.0-beta): the `permissions:` blocks are carried IN THE BASE LAYER YAML** — on pages, grid rows, AND paragraphs — and deserialize straight into `UnifiedPermission` (page/grid-row/paragraph rows). No live admin-panel or SQL step after deserialize: the gate is already in the layer. **Per-role tiles on ONE shared Overview page are the stock pattern** (buyer tiles gated `Customers=all / CSR=none`, CSR tiles `CSR=all / Customers=none`, all `Anonymous=none`); the separate CSR split-landing is retired. The live post-deserialize `UnifiedPermission` seed (admin Permissions panel / SQL INSERT + cache flush) is now a **legacy fallback** for older bases/engines only. Verify the YAML-carried gating applied with the Foundry permissions-parity check (every serialized block ⇔ matching `UnifiedPermission` rows). Never gate via per-template `foreach` filters or raw `SELECT FROM AccessUserGroupRelation`.
- **Customer-specific (contract) pricing** (scope by customer number not `customerGroupId`; lowest matching price wins; resolves live in cart/checkout not PLP/PDP; the `force_price_recalculation` verification trap): vendor-generic catalog/pricing knowledge is owned by the `dw-commerce-catalog` foundational skill — staged in [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.13.

  **DW 10.28 behaviour — bind the area currency explicitly before debugging any price.** On DW 10.28+ an area with no bound `AreaEcomCurrencyId` derives its currency from the area **CULTURE** (an `en-US` area silently prices in USD via currency conversion), not from `CurrencyIsDefault`. Wrong-currency cart/checkout totals on a demo are almost always this, not a pricing-rule bug — bind `AreaEcomShopId`/`AreaEcomCurrencyId`/`AreaEcomLanguageId` per area + restart, per [`deserialize-flow.md`](deserialize-flow.md) §7 ("Mandatory consumer obligation").

  **Presenter note — the PDP header "from" price is expected behaviour, not a pricing bug.** Stock Swift's PDP header renders the **master product "from" price**; the resolved variant + customer-affiliation/contract price is computed only in **cart/order context**. So the header price legitimately differs from what the cart later shows for a specific variant or a logged-in contract customer — this is not a defect and does not need debugging during polish. Present it by walking the price down the cascade: show the master "from" price on the PDP, then add to cart / sign in as the contract customer and let the **cart** reveal the resolved price. (This is the PDP-header face of the "resolves live in cart/checkout not PLP/PDP" rule above.)

## 4. What to do when the section "looks empty"

Symptom: CSR Overview page has empty grid rows, or `CSR/Orders/` shows no orders, or `CSR/Accounts/` is blank. Cause is almost always one of (demo-side diagnosis):

1. **No orders / users seeded** -- the customer-flavoured baseline (`<demo>-base/`) hasn't been deserialized yet, or only the generic `Swift2.2` baseline has been loaded. Run [`deserialize-flow.md`](deserialize-flow.md) first against the appropriate baseline. The seeding mechanics (`OrderComplete=1`, favorites NOT-NULL, profile-address-for-checkout) are foundational — see [`order-lifecycle.md`](../../dw-commerce-orders/references/order-lifecycle.md) "Seeding the CSR/account section's demo data".
2. **Logged-in user is not in a CSR group** -- `EcomCustomers.GroupId` doesn't include a CSR-permission UserGroup row. The customer-flavoured baseline is expected to seed a CSR sample user; the stock `AdminUser` default has admin perms but isn't in a customer-facing CSR group.
3. **CSR ↔ customer grants not wired** -- `AccessUserSecondaryRelation` is empty for this CSR, or the column direction is inverted, or the required index-rebuild + cache-clear follow-up was skipped. See [`order-lifecycle.md`](../../dw-commerce-orders/references/order-lifecycle.md) "`AccessUserSecondaryRelation` — the impersonation grant".
4. **Index not built or cache stale after wiring the grant** -- see [`order-lifecycle.md`](../../dw-commerce-orders/references/order-lifecycle.md). For Products-index rebuilds, see [dw-demo-pim/references/governance.md "Recovery recipe: Rebuild Products index"](../../dw-demo-pim/references/governance.md).

What is NOT the cause: missing paragraphs / broken templates / Swift 2.3 incompatibility. The swift/2.3 baseline is verified working by [`deserialize-flow.md`](deserialize-flow.md); if the page renders at all, the structure is intact and the issue is data-side.

Once the diagnosis is "data-side", drive the fix from [dashboard-seeding.md](dashboard-seeding.md) — the per-tile seed checklist that makes every buyer and CSR list land (the "no empty lists on demo day" bar).

## 5. Persona presentation: avatar + role badge

A demo with multiple personas (customer admin / buyer / browse / CSR) lands harder when the storefront makes the persona switch *visible*. Stock Swift renders every signed-in user the same: blue avatar circle + name. To distinguish:

- Derive a role from `AccessUser.AccessUserCustomerNumber` suffix (a per-demo convention — e.g. `...-ADMIN`, `...-OWNER`, `...-BUYER`, `...-BROWSE`) **plus** CSR group membership via `Pageview.User.GetGroups()` (the suffix-as-role flag and the `GetGroups()` accessor are foundational — see [`page-gating.md`](../../dw-users-permissions/references/page-gating.md) §16 and [`dw-render-viewmodels`](../../dw-render-viewmodels/SKILL.md)).
- Map each role to a **ring color** + **badge background/foreground**. Suggested palette: blue for admin/owner, teal for buyer, gray for browse, amber for CSR. (Adjust per-demo to fit the brand layer.)
- Render in **both** avatar templates: `Users/UserView/Detail/UserAvatar.cshtml` (header top-right) AND `Users/UserView/Detail/UserInfo.cshtml` (the bigger avatar inside the CC sidebar). Same logic, same palette — keep them visually consistent or the persona signal feels accidental rather than designed.
- Add the user's `Company` field below the role badge — distinguishes one buyer's company name from another's at a glance.

The avatar ring is best done with `box-shadow: 0 0 0 3px <color>` on the wrapper rather than `border` (border affects layout; box-shadow doesn't). The badge is a single `<span class="badge">` with inline `style=` for color tokens; consume from `--<brand>-primary` / `--<brand>-charcoal` style vars per [re-skin.md](re-skin.md) so the brand layer flows through.

## 6. Sign-in profiles / switch user (Swift 2.4) — not impersonation

Swift 2.4's "Sign in with multiple Profiles" is a **second user-on-user mechanism, separate from
impersonation** — the two are easy to conflate and are wired through entirely different tables:

1. **Profiles / switch user** (Swift 2.4 UI): multiple `AccessUser` rows sharing one
   `AccessUserUserName`, disambiguated by the `AccessUserIsLogin` flag. Templates
   `Users/UserAuthentication/Login/SelectableUsers.cshtml` and `SelectableUsersDirectLogin.cshtml`;
   app settings on the *Users - Authentication* paragraph: `ListUserProfiles` (bool) +
   `UserProfilesTemplate`. Switching posts `DwSwitchUserUniqueId` →
   `AuthenticationManager.StartSwitchUser`, which hard-requires the target user's `UserName` to
   equal the current user's (case-insensitive) — no password re-entry, no banner, no
   `CanImpersonate` check. **The same-username rule IS the authorization**, and the switch is a
   full session identity change.
2. **Impersonation** (existing): `AccessUserSecondaryRelation` + `CanImpersonate`,
   `DWExtranetSecondaryUserSelector` / `DwExtranetRemoveSecondaryUser`, ImpersonationBar templates
   — owned by [`order-lifecycle.md`](../../dw-commerce-orders/references/order-lifecycle.md)
   "CSR sales-on-behalf — impersonation mechanics". A CSR demo uses impersonation; a
   one-buyer-many-accounts demo (one login serving several customer accounts) uses profiles.

A third, legacy branch exists in `GetProfilesListOutput`: same-username users with *different
ShopID* and no `IsLogin` row anywhere, reachable only with `?ShowProfiles=1` (shop-scoped
profiles). Don't mistake it for the 2.4 mechanism.

### Platform gate — state the platform honestly

The release notes gate same-username profiles on **DW 10.29+**. **The 10.29 requirement is
ADMINISTRATIVE ONLY — the runtime resolver already works on 10.28.x stable.** What 10.29 actually
unblocks is `UserSave`: pre-10.29 it rejects a duplicate username, so you cannot *create* the profile
rows from the admin side. Everything downstream of that is present and working on 10.28.3 — the
`AccessUserIsLogin` column, `GetProfilesListOutput` → `GetUsersByUserName` + `IsLogin`, and the login
resolution that prefers the `IsLogin=1` row. A 10.28.3 demo host showed **four profiles** at
`/<lang>/sign-in/sign-in?ShowProfiles=True` and switched between them successfully.

So the demo is not blocked on 10.28.x; only the creation surface is. Seed the rows with
`AccessUserIsLogin` set via SQL (the recipe below) and the feature runs. The duplicate-username
validation in `UserService.IsValidUserName` still holds as a data rule — at most one `IsLogin=1` row per
shop, distinct non-empty customer numbers — so honour it in the seed rather than working around it.
When a demo host is pinned to a PreRelease or to 10.29+, say so when presenting the feature: the
*administration* of profiles is what the customer's GA version may lack, and that is a fair thing to
name on screen.

### Every member of a multi-profile login is permanently UNEDITABLE through `UserSave`

The duplicate-username validation has a second consequence beyond blocking creation: **`UserSave` rejects any
`userName` already held by another row, and the check does not exclude the row being saved from its own
duplicate group.** A profile set *is* a group of rows sharing one username — that is what produces the picker —
so every member of an existing set is unsaveable, even round-tripping its own unmodified model, and even to
change something unrelated like a surname:

```
POST UserSave  (own unmodified model, row belongs to a profile set)
  -> 400 {"status":"invalid","message":"Username already taken by another user."}
```

Reproduced on both profile sets on one install. **The escape hatch is to make the username momentarily
unique:** SQL-park the OTHER rows of the set on throwaway usernames so the validator sees the real username as
free → `UserSave` the target row (which updates the database **and** the cache, which is why this is worth
doing rather than SQL-editing the row) → SQL-restore the whole set. Repeat per row. Verify afterwards that
`/dwapi/users/info/profiles/switch` still returns `200` for every profile — the parking step is exactly the
kind of edit that leaves a set half-restored.

### Zero-custom-code picker recipe (SQL + one restart)

1. **Clone the buyer's `AccessUser` row per profile:** same `AccessUserUserName`, new
   `AccessUserUniqueId = NEWID()`, `AccessUserIsLogin = 0`, a **distinct non-empty
   `AccessUserCustomerNumber`**, and distinct company/address values (the picker renders name,
   address, company, and customer number). Copy the group relations — the B2B price gate and
   customer-center access follow the group.
2. **Set `AccessUserIsLogin = 1` on the master row** — password login resolves to it; the clone
   rows' passwords are never used.
3. **Paragraph settings** on the UserAuthentication paragraph:
   `<ListUserProfiles>True</ListUserProfiles>` +
   `<UserProfilesTemplate>SelectableUsers.cshtml</UserProfilesTemplate>`.
4. **Restart once** (user + paragraph caches).

Per-profile data isolation comes free: contract prices key on `PriceUserCustomerNumber` and the
My-orders list filters on `RetrieveListBasedOn=UseUserID` — both differ per profile row.
**Verify end-to-end:** log in → the picker lists every profile → per-profile contract price on
the cart and per-profile order lists with no cross-visibility, in both switch directions.

### Picker-trigger UX quirk

With `ListUserProfiles=True` the login form rewrites its redirect to
`?ShowProfiles=1&RedirectAfterSwitchUser=...` **back to the sign-in page** — after login the user
lands on the picker on the sign-in page, then is redirected onward. Re-visiting the sign-in page
while signed in shows the picker again; that IS the in-session account switcher. Stock Swift has
no header/avatar entry point for switching, so link the sign-in page from the account menu when
the demo storyline needs a visible switch affordance.

## 7. Signing in AS a persona — the field names, and the right assertion target

**A login that returns HTTP 200 and is not signed in reads as a broken login or a bad password. It is almost
always the field names.** The Swift 2.4 sign-in form takes **lowercase** `username`, `password` and
`redirect`. Posting the classic Dynamicweb names (`Username` / `Password` / `LoginAction`) is **accepted and
ignored** — 200, no session, no error. That shape produced a false FAIL in one authentication proof.

**The assertion target matters as much as the field names: assert against the customer-centre page fetched
WITH the session cookie, never against the POST response**, which is 200 either way.

The API side is a separate shape, measured separately:

```
storefront form :  POST <sign-in page>        username / password / redirect        (lowercase)
storefront API  :  POST /dwapi/users/authenticate   { userName, password }          (capital N)
                   /dwapi/users/token -> 401 — it is not the storefront route
```

**The dwapi session is carried by a COOKIE, not a bearer**, so every subsequent cart / customer-centre call
must reuse the same web session. A persona-login gate should assert a **signed-in marker on the
customer-centre page**, not a POST status code.

**Sign out between personas — always, in a demo script and in a probe.** Authenticating a second user
over a live extranet session does **not** clear the context cart: the platform keeps the previous
persona's cart, mints a `DynamicwebEcomCart<newUserId>` cookie for the same encrypted order id, and
**persists that cart id onto the new user's `AccessUser` row**. So the leak is not a session artefact
that a fresh browser clears — it is written to the user, and it reappears in every later session,
including from a brand-new profile. The anonymous-to-authenticated transition clears correctly; the
authenticated-to-authenticated one is the gap.

The explicit log-off path (`/Admin/Public/ExtranetLogoff.aspx`) drops the cookie and the session cart
correctly, which is what makes the workaround reliable: **navigate through the log-off between logins,
or use a separate browser profile per persona.** Prove it both ways once — run the two-login script
with and without the log-off step and assert that in the log-off run the new user's
`DynamicwebEcomCart<id>` cookie is absent and their `AccessUserCartId` is unchanged.

## 8. Renaming a persona is a sweep, not a user edit

**A persona is not a user-table row.** It is referenced by hardcoded credentials in shared harnesses, by
generator scripts that write live pages and dashboards, by data seeders, by build specs consumed by *other*
agents, and by gate persona secrets — none of which a user rename touches.

Measured blast radius of one rename: a standing regression harness went **14/14 → 1/14 within seconds** (every
scenario failing with `400` downstream of an authentication that returned an empty token), and a workstream
running in parallel read that RED as evidence of *its own* damage. Dozens of files under the demo home still
referenced the old username — shared verification scripts, an inventory JSON, and around twenty probe scripts.

**The latent half was worse than the visible half:**

- **Generators re-publish the retired identity.** Re-running the cheat-sheet, inventory, about-page and
  quote/order/address seeders would have put the old name back onto live pages, onto an external dashboard,
  and onto orders and addresses. One inventory generator both rewrites its JSON *and* POSTs the row to a live
  external endpoint — so fixing only the JSON is undone on the next run.
- **A build spec consumed by a separate frontend agent** instructed hardcoding the old credentials into a
  shipped login screen.
- **The gate config showed ZERO matches** and was still broken: gate personas resolve by *secret key*, so the
  credential lives in the secret store, which had to be updated or the closeout personas leg would fail on a
  login that no longer exists.

**Treat a rename as a sweep of every surface that can put the name back**, in this order: shared harnesses →
generators (the dangerous class) → seeders → build specs consumed by other agents → the gate secret store.
Then **parameterise the persona** in shared harnesses instead of hardcoding it, so the next rename is a config
edit. Gate: the personas leg authenticates **using the secret store**, and a repo-wide grep for the retired
identity returns only documented evidence-file exemptions.

When the rename is being done for **privacy** reasons rather than storyline reasons, the user-table edit is
also only one of five database layers — see
[`../../dw-demo-base/references/pii-sweep.md`](../../dw-demo-base/references/pii-sweep.md). And never repair
a user row by raw SQL: the in-process user cache is unflushable and the failure surfaces three endpoints away
([`cache-invalidation.md`](../../dw-data-access/references/cache-invalidation.md)
"Raw-SQL `AccessUser` writes create a split brain").

## 9. Checkout — paths, method names, delivery date and custom order fields

### Resolve the checkout URLs by walking the cart subtree

**Resolve the checkout URLs by walking the cart subtree, never by composing a remembered path.** The
shopping-cart branch (`Cart` with children for the empty cart, the anonymous checkout, the user checkout
and the quote checkout) resolves its friendly urls **outside the culture prefix** that every content page
carries — the checkout screens answer at bare `/checkout` and `/user/checkout` while `/` content sits under
`/<culture>/`. A path composed as `<culture>/cart/checkout-user` 404s, which reads as a failed publish and
sends the pass debugging the content tree. Read the page ids from the tree, fetch each by
`/Default.aspx?ID=<pageId>` following redirects, and record the `url` each one lands on: that measured url
is the one every later assert and every demo link uses. This is the same measured-prefix discipline the
language layer needs ([`language-layers.md`](language-layers.md)).

**Read the shipped method names before asserting on them.** The stock payment and shipping rows on the
current baseline carry **English** names, while several still describe themselves in the platform vendor's
home locale in the `description` field — so an assert that sweeps for that locale's method names passes
vacuously before any work is done, and the debrand that actually matters is the descriptions. Start the
step with `get_payment_methods` and `get_shipping_methods`, debrand the names **and** the descriptions,
deactivate the carriers the demo does not use, and write the asserts against the rows just read rather than
against a remembered name list.

**The first checkout screen carries no method radios.** It collects customer details; the payment and
shipping options render on a later step that only a cart past that step reaches. So "the checkout renders at
least one payment and one shipping option" is a **persona-dependent leg** driven through the flow, not a
GET — a cart driven straight to the checkout url renders neither, correctly. Assert the method rows
themselves with the read tools, and keep the rendered-radio assert on the driven leg.


### Populate the billing block on every buying contact, or their ship-tos vanish at checkout

**Swift's checkout hides ALL delivery addresses when the user's own billing-address fields are
empty.** `eCom7/CartV2/Step/Helpers/AddressUser.cshtml` builds a comma-joined string from the
`AccessUser` row's OWN address fields and, when that string is blank, renders "You do not have any
address yet" **instead of** the delivery-address list — even when the user has `AccessUserAddress`
ship-to rows that the Admin API happily returns.

So a user import that lands ship-tos but not a billing address produces a persona who cannot check
out, **with no error anywhere**, and an app-pool recycle does not help: it is a data gap, not a cache
one. **Fix it in the data — populate the billing block for every buying contact** rather than
patching the template. Assert it per persona by reaching the delivery-address step in the real
checkout flow and counting the ship-tos rendered, not by reading the addresses back through the API.

### The delivery-date beat needs NO custom order field

Stock Swift already carries it: enable **`EnableDeliveryDate`** on the `Swift-v2_CheckoutApp`
paragraph — checkout then renders a delivery-date picker and posts `EcomOrderShippingDate` into
the **native `OrderShippingDate` column** on the order row. Recent base layers ship the checkout
paragraph with it enabled; verify on the deserialized checkout page before authoring anything.
Reach for a custom order field only when the beat genuinely needs a field the order schema does
not already carry.

**Verify:** enable delivery date on checkout, place an order with a specific date, assert
`OrderShippingDate` is set on the order row and both the storefront My-orders list and the admin
order list render without exceptions.

### Custom order fields: the `EcomOrders` column contract

Order-field **values live in per-system-name columns on `EcomOrders`**, not in `OrderFieldsXML`.
An `EcomOrderField` definition row without a matching `EcomOrders.<SystemName>` column breaks
**every order read** — `OrderRepository.ExtractOrderFieldValues` throws
`System.IndexOutOfRangeException: <SystemName>`, taking down storefront My-orders AND the admin
order lists in one stroke.

When a custom order field is genuinely needed via SQL, create both halves in the same batch, then
flush:

```sql
INSERT INTO EcomOrderField (OrderFieldName, OrderFieldSystemName, OrderFieldTypeId, ...)
    VALUES (...);  -- OrderFieldTypeId MUST exist in EcomFieldType
ALTER TABLE EcomOrders ADD [<SystemName>] <type> NULL;
```

Flush the `OrderFieldService`/`OrderService` caches (or restart the host) before reading any
order.

### MCP `create_order_field` fails on a foreign-key violation (version-pinned)

`create_order_field` errors on every call: its MERGE into `EcomOrderField` passes an
`OrderFieldTypeID` not present in `EcomFieldType`, violating the
`DW_FK_EcomOrderField_EcomFieldType` constraint (verified DW 10.27.x — an upstream tool bug).
Until it is fixed, create the definition via the SQL contract above — and first ask whether the
beat needs a custom field at all (see the delivery-date rule).

## 10. The storefront account-admin page (Swift 2.4 UserGroups app)

The "Manage users" page an account admin uses to invite, activate, impersonate and remove their own
people. The permission gate that decides whether ANY of it works, the module's real property set, the
`AccountListScope` directory filter and the single-account-person modelling trade-off are foundational —
[`user-group-operations.md`](../../dw-users-permissions/references/user-group-operations.md) §17. **Read that
first: out of the box every command on this page is refused with a 200 and a toast, and the buttons still
render.** What follows is the demo-facing behaviour of the same page.

### Impersonating from this page answers a 128-byte permission-denied page, and that IS the switch succeeding

The impersonate anchor in `UserGroupUser_List.cshtml` posts back to the **same URL it is rendered on**:
`{baseUrl}?NowImpersonating=true&DWExtranetSecondaryUserSelector={id}&Redirect={RedirectAfterImpersonation}`.
The secondary-user switch is applied **before** the page renders, so the acting user is already the
impersonated buyer, who by design has no permission on the account-admin Users page. The response is
therefore the denied page **for the new identity**, and the paragraph's `RedirectAfterImpersonation`
setting is not honoured on this request:

```
GET /<lang>/account/users?NowImpersonating=true&DWExtranetSecondaryUserSelector=<buyerId>&Redirect=…
    -> 200, length 128 (the DW "You do not have permission to view the page" body)
GET <the buyer's overview page>
    -> 200, 146 KB, the buyer's name plus a DwExtranetRemoveSecondaryUser switch-back link
GET <the buyer's orders page>            -> the buyer's order codes
GET /<lang>/account/users?DwExtranetRemoveSecondaryUser=1   -> back to the admin identity
```

Every naive assertion (banner present, list re-rendered, length > N) reads that 128-byte body as a failed
impersonation, and the obvious next move is to go re-check `AccessUserSecondaryRelation` rows that are
already correct. **Assert the impersonation on the FOLLOWING request to a buyer-visible page, never on the
response to the impersonate link itself.** A 128-byte denied page there is the expected success signature
when the host page is admin-only.

### The invitation mail cannot greet the invitee by name

`Users/UserCreate/ConfirmationEmail/UserInviteEmailConfirmation.cshtml` does `Model.Name ?? Model.UserName`,
but `Dynamicweb.Users.Frontend.UserCreate.UserCreateViewModelFactory.CreateNewUserViewModel(user,
settings)` populates only `Result`, `Email` and `UserName` from the user — **`Name` is never assigned**.
The UserGroups invite form defaults `UserName` to the email address, so the fallback always renders the
address and every invitation opens "Dear <email address>," while the account Users list shows the person's
real name on the row. The same factory feeds the on-screen invite form, where the gap is invisible.

`UserCreationHelper.SendEmail` runs `SendInvitationEmail` **after**
`UserManagementServices.Users.Save(user)`, so the row exists by then and the template can fall back
through it:

```csharp
if (string.IsNullOrEmpty(userName) && !string.IsNullOrEmpty(Model.Email)) {
    var invitee = UserManagementServices.Users.GetUserByEmailAddress(Model.Email);
    if (invitee != null && !string.IsNullOrEmpty(invitee.Name)) userName = invitee.Name;
}
```

Verify by inviting a throwaway whose Name differs from the email, capturing the outgoing `.eml`
(`saveAllMailsToDisk`) and asserting the greeting carries the Name and not the address. The upstream fix
is `Name = user?.Name` in `CreateNewUserViewModel`.

### A failed invitation mail is INVISIBLE in the EventViewer, and the badge is the delivery signal

`UserCreationHelper.SendEmail` calls `SendInvitationEmail` FIRST and only then sets `user.InvitationSent`
and saves. If the SMTP send throws, `InvitationSent` is never written, so `User.GetStatus()` returns
**Inactive** instead of **Pending**. The invite POST returns 200, there is no error toast, and **nothing
lands in `Files/System/Log/EventViewer`** — reading that log had previously been used to conclude the mail
"ran without throwing".

Mail exceptions go to a different log, `Files/System/Log/EmailHandler/<yyyy_MM>.log`, and DW drops a
second copy of the message as `<timestamp>_<guid>.eml` in that folder on the failure path (so a broken
send leaves TWO `.eml` files milliseconds apart where a healthy one leaves one).

**Assert on the EmailHandler log, not the EventViewer, and treat the badge as the cheap in-band delivery
check.** PASS requires both: zero lines matching `Error:` appended to
`Files/System/Log/EmailHandler/<yyyy_MM>.log` after t0, **and** status `Pending` on the row. Then delete
the throwaway.

## 11. The B2B DC pattern (one AccessUser group per Stock Location)

The canonical Dynamicweb 10 B2B pattern for any portal where pricing, stock, shipping methods, or
shipping fees vary by Distribution Center (DC) — vendor-blessed (Dynamicweb architecture guidance).
**This is the standard B2B mechanic in DW10, not an upgrade path:** treat it as the default scaffold
for any wholesale / B2B-distributor demo that touches DC-aware behavior. Customers expect it; framing
it as bespoke would invent friction DW10 doesn't have.

The mechanic — **one AccessUser group per Stock Location**, which natively unlocks DC-scoped
Assortments + Shipping methods + Shipping fees + cart-time pricing without custom code — plus the
naming convention, user assignment, surface guidance (MCP-first; the `AccessUser` NOT-NULL column
list for SQL fallback), the admin-tree typed-group filter, and the verification flow are owned by the
`dw-commerce-b2b` foundational skill — staged in
[`dc-scoping.md`](../../dw-commerce-b2b/references/dc-scoping.md) ("The DC-as-user-group
pattern"). Read that before scaffolding DC groups. Related:
[`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §2.9
(Assortments structural model — customer access ≠ Channels) and §2.11 (the stock cart ignores
`PriceQuantity > 0` tier rows; ERP-pre-graduated rows are the production pattern for qty-aware DC
pricing). The stock Swift CSR section (§1–§3 above) layers on top of the DC pattern when a CSR
persona impersonates DC buyers.

### Stock Swift renders NOTHING where the price goes when the area hides prices

**On an area configured `AnonymousUsers="cart-price"`, the PLP and PDP render an EMPTY
`<div data-dw-itemtype="swift-v2_productprice">` to anonymous visitors**: no price, no explanation, no
sign-in call to action, so a prospect sees products with no commercial surface at all. This is not a
misconfiguration to chase. `Swift-v2_ProductPrice.cshtml` computes
`hidePrice = anonymousUsersLimitations.Contains("price") && anonymousUser`, wraps its ENTIRE body in
`@if (product is object && !hidePrice && …)`, and the only `else` branch is
`else if (Pageview.IsVisualEditorMode)`. **There is nothing to configure — the call to action has to be
added to the component**, as an `else if (hidePrice)` branch rendering a note plus a real anchor to the
sign-in page, carrying a marker class so the gate can assert it.

**The anchor string `else if (Pageview.IsVisualEditorMode)` occurs TWICE in that file**, and the first
occurrence is inside the leading `@{ }` block. A `String.replace` on the first match injects the new
branch **above** the `hidePrice` declaration, Razor fails to compile, and every PLP and PDP serves a
compiler stack trace **while still answering HTTP 200**. Anchor on the second occurrence, or on a longer
unique span, and prove the edit by fetching a PLP and asserting the marker class is present rather than
asserting a status code. Gate shape that works: at least one element matching the marker class per product
row on the PLP, each at least 34px tall and 120px wide with a background or a border, plus a
"every row carries a price surface" assert.

### Hiding prices from anonymous visitors is a **template-level** gate only

The area's `AnonymousUsers` setting (a value containing `price`) is enforced in the **rendering** templates —
`Swift-v2_ProductPrice.cshtml` checks `anonymousUsersLimitations.Contains("price")` — **not** in the product
data handed to the page. The analytics / ecommerce tracking payload is built from the *unfiltered* product
object, so the anonymous HTML still ships the list price: a `clickProductLink('<productid>', …, '<currency>',
'<list price>', '0.00')` call sits in the same page whose visible price cell renders only a locked
"Dealer price" label. Anyone with devtools reads the withheld number. GA4 `dataLayer` pushes leak the same way.

- **Any demo that sells "prices hidden from anonymous" as its commercial contract must assert the payload, not
  the pixels.** Gate assert: fetch every PLP and PDP anonymously and assert (a) the signed-in price string
  appears nowhere in the body, and (b) every `clickProductLink` / `dataLayer` price argument is `0` or absent.
  A visual check of the price cell proves nothing here.
- **The fix belongs where the payload is built**, not in the template: the analytics product mapping must
  consult the same hide-price predicate the price template uses and emit `0` — or omit the price node — when
  prices are gated. Until that lands, treat it as a known leak and say so in the run notes.

### The anonymous sign-in nudge — one CTA, not one per price cell

In the open-catalog B2B pattern (anonymous browsing, prices hidden) the stock sign-in nudge is authored as a
**control** and emitted per price cell, so a ~200px outlined button repeats once per product row (10–12 per
PLP): it drowns out the single signup CTA the page wants to convert on, and its Bootstrap margin makes
anonymous rows taller than the same rows for a signed-in dealer. A price cell is a *column*, and a column
repeats by definition — the defect is the affordance, not the repetition.

**Fix: branch the shared price template on list-vs-detail context.** In LIST emit a muted, non-interactive
locked glyph + label with no anchor; in DETAIL emit the same glyph and the same copy string at buy-panel scale
**plus** the page's single sign-in anchor. The branch selects scale and affordance, never *whether* the price
is locked — so no context is left with empty space where a price belongs.

**Assert it:** per-row sign-in anchors inside price cells == 0; signup links inside `main` == exactly 1;
locked labels == product row count; anonymous row height within a few px of dealer row height; and on the
detail page the sign-in anchor must be **inside** the locked component (assert containment, not presence)
with both the locked component and its price slot rendering height > 0.

**Rejected alternatives:** a CSS-only restyle of the anchor into a text link (leaves every sign-in link live,
and re-labelling needs a `font-size:0` + `::after` hack that lies to screen readers); hiding the price cell
for anonymous visitors (empty cells read as a broken catalogue and break the required-price assert); showing
list/MSRP anonymously (contradicts the stated commercial contract, and leaks).

### Driving the cart in an automated probe

Two Swift shapes break naive cart automation, and both make a perfectly healthy cart look broken:

- **The visible add-to-cart control is `<button type="button">`; the form's `input[type=submit]` renders at
  0×0.** The obvious selector (`form button[type=submit]`, `[name=cartcmd]`) matches the hidden 0-height element
  and the click is a no-op — the page does nothing and the run reports a broken checkout path. Select **by
  rendered height (> 10px) inside `[data-dw-itemtype="swift-v2_productaddtocart"]`**, never by `type=submit` or
  `name=cartcmd`. (The hidden inputs alongside it carry `cartcmd=add`, `ProductId`, `Quantity`.)
- **The cart page has no per-line delete control** — lines are `div`s, not table rows, so "find the row, click
  its delete button" finds nothing. Removal goes through the page's single `cartcmd=updateorderlines` form:
  set `QuantityOrderLine<OrderLineId>` to `0` and submit.
- **A probe that adds to a live demo cart must restore it.** A working smoke test otherwise pollutes a cart a
  prospect may be shown minutes later. Assert the cart count increments by exactly 1 after clicking the visible
  button, then zero the affected order line and assert the count returns to its starting value; exit non-zero if
  either leg fails. Retry the cart navigation — it can `ERR_ABORT` while a mini-cart POST redirect is in flight.

### Driving the cart from curl: the User-Agent gate and the cache-safe reset

**DW10 silently skips the cart command for curl's default User-Agent.** The POST returns **HTTP 200**,
CREATES the cart row in `EcomOrders`, and adds **no `EcomOrderLines` row at all**, with nothing in the
log. Session, cart creation and the 200 all happen, so every observable except the order lines says
success. That signature (200 + cart row + zero lines + no log) cost half an hour of CSRF and
order-context theories and very nearly shipped a false "the cart is broken" finding. The identical
request with `-A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)
Chrome/126.0.0.0 Safari/537.36"` works. Bake a browser UA into the harness's curl wrapper so a cart
gate cannot be written without one. Two curl gotchas ride along:

- `/Default.aspx?ID=...` **301-redirects** to the friendly URL, so a probe needs `-L` (0 bytes without
  it) and a POST needs `--post301`, or post straight to the friendly URL.
- Swift posts **cart** forms as multipart (FormData), so use `-F` there — and only there. This is not
  a general form rule: an ordinary Razor form declares no `enctype`, a browser posts it
  urlencoded, and a `-F` probe against one is truncated after the sixth field with the later required
  fields reported missing. Read the rendered form's `enctype` and match it
  ([`../../dw-demo-base/references/browser-automation.md`](../../dw-demo-base/references/browser-automation.md)
  "Post a form the way the rendered form posts it").

**Never clear a cart with a lines-only SQL delete.** DW holds the `Order` object in memory, and a
`DELETE FROM EcomOrderLines` does not invalidate it: on the next cart command the cached Order
re-persists its stale lines and merges the new add on top, so quantities come back **doubled**. The
database looks clean between the two steps, which is exactly what makes the doubled numbers read as an
add-to-cart bug rather than a cache artefact. The working three-step reset before any cart gate:

```sql
DELETE FROM EcomOrderLines WHERE OrderId = <cart>;
DELETE FROM EcomOrders     WHERE OrderCart = 1;     -- the cart ROW too
-- then restart the app pool, which drops the cached Order
```

Regression test for the trap: run the identical cart sequence twice with the full reset between runs
and assert identical line counts and quantities both times. Without the reset, run two doubles.

### When not to use this pattern

- **Single-DC demos** — if the customer is single-DC and the storyline doesn't lean on "different
  buyer sees different stock", don't scaffold DC groups. One Assortment is fine. Adding the DC mechanic
  to a demo that doesn't need it is wasted complexity (and wasted customisation-budget signal in the
  closing slide, even though zero customisations were technically added).
- **B2C demos** — the DC-as-group pattern presupposes accounts-with-customer-numbers. Anonymous-buyer
  / B2C demos don't have the user-group hook to scope on.

For everything in between (multi-DC B2B with named buyer accounts), this is the default.
