# customer-center.md

> The Swift 2.2 customer-center frontend playbook for Dynamicweb 10 demos. Covers the page-tree map (Account vs CSR vs legacy nav vs Overview), the stock-CSR rule rationale (inoculation against the rebuild-the-CSR-section trap in sales-on-behalf demos), and where impersonation, mixed-source order rendering, and exit-impersonation live in the stock paragraph wiring. The top-level rule lifts a one-paragraph summary into SKILL.md body; this file is the deeper playbook.
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

Source-of-truth: `$env:DW_VAULT\serialized-data\Swift2.2\_content\Swift 2\Customer center\` deserialized into a running host. Backtick-quote any path string when copying into other tools -- folder names contain spaces.

```
Customer center/
├── Account/                      ← logged-in customer's own self-service
│   ├── Orders/         (page.yml + grid-row-1/{grid-row.yml, paragraph-c1-1.yml})
│   ├── Carts/, Quotes/, Users/, Addresses/, Favorites/
├── CSR/                          ← THE STOCK SALES-ON-BEHALF SECTION (never rebuild)
│   ├── Orders/, Accounts/, Carts/, Users/
├── Customer center/              ← legacy/alt nav under same top-level
│   └── My profile/, My addresses/, Change password/, ...
└── Overview/                     ← landing page (4 grid rows)
```

This is the canonical tree any Customer-360 / sales-on-behalf demo references (`Customer center/CSR/{Orders, Accounts, Carts, Users}`). It's pre-built, paragraph-driven, requires no custom Razor.

## 3. Where the impersonation flow lives

The CSR-driven impersonation entrypoint is the **`Customer center/CSR/Users/`** page, *not* `Customer center/CSR/Accounts/`. Both pages share the `UserGroups` web-app module but render different views:

| Page | Stock template | Function |
| --- | --- | --- |
| `Customer center/CSR/Accounts/` | `Templates/Designs/Swift-v2/Users/UserGroups/List/UserGroup_List.cshtml` | Lists **customer groups** (companies). Per-row actions are "View account users" and "Edit account" only -- no impersonate button. Acts as a company directory and a drill-in to the user list. |
| `Customer center/CSR/Users/` | `Templates/Designs/Swift-v2/Users/UserView/List/UserGroupUser_List.cshtml` | Lists individual **users** across customer accounts. Each row's actions menu has the "Impersonate" link, which fires the impersonation start request. |

The Impersonate link uses the stock UserGroups module command:

```
?NowImpersonating=true
&DWExtranetSecondaryUserSelector=<targetUserId>
&Redirect=<post-impersonation-target-url>
```

Hitting that URL sets the `Dynamicweb.Ecommerce.Customers.User.ImpersonatedUser` session value. The corresponding switch-back link emitted on the same row when the CSR is already impersonating is `?DwExtranetRemoveSecondaryUser=1`.

While impersonation is active:

- The customer's order list is rendered by the same `Account/Orders/` paragraph the customer sees themselves -- same template, same fields, same `OrderSource` discriminator.
- A header banner ("Viewing as <Customer Name>") appears on every page; clicking it ends impersonation and returns the CSR to their own session.
- Cart pollution prevention: the cart shown while impersonating is the impersonated customer's cart, not the CSR's.

A typical mixed-source-orders demo requirement (orders with discriminator badge by source channel) maps onto this view 1:1 -- the badge text is whatever the order's `OrderSource` column holds (`WEBSHOP`, `EDI`, `PUNCH-OUT`, `MANUAL`); rendering is paragraph-driven, no controller changes needed.

**Demo-builder pitfall:** opening `Customer center/CSR/Accounts/` and seeing "no impersonate button" is *expected* -- that page is by design a company directory, not the sales-on-behalf launcher. Send the CSR to `Customer center/CSR/Users/`. If `Users/` *also* shows no Impersonate link on a row, the wiring described in §5 is missing or has the column direction inverted.

## 4. What to do when the section "looks empty"

Symptom: CSR Overview page has empty grid rows, or `CSR/Orders/` shows no orders, or `CSR/Accounts/` is blank.

Cause is almost always one of:

1. **No orders / users seeded** -- the customer-flavoured baseline (`<demo>-base/`) hasn't been deserialized yet, or only the generic `Swift2.2` baseline has been loaded. Run [`deserialize-flow.md`](deserialize-flow.md) first against the appropriate baseline.
2. **Logged-in user is not in a CSR group** -- `EcomCustomers.GroupId` doesn't include a CSR-permission UserGroup row. The customer-flavoured baseline is expected to seed a CSR sample user; the stock `AdminUser` default has admin perms but isn't in a customer-facing CSR group.
3. **CSR ↔ customer grants not wired** -- `AccessUserSecondaryRelation` is empty for this CSR. See §5 below.
4. **Index not built or cache stale after wiring §5** -- see §5 for the rebuild + cache-clear step that *must* follow any change to `AccessUserSecondaryRelation`. For Products-index rebuilds, see [dynamicweb-pim-demo/references/governance.md "Recovery recipe: Rebuild Products index"](../../dynamicweb-pim-demo/references/governance.md).

What is NOT the cause: missing paragraphs / broken templates / Swift 2.3 incompatibility. The Swift2.2 baseline is verified working by [`deserialize-flow.md`](deserialize-flow.md); if the page renders at all, the structure is intact and the issue is data-side.

## 5. Wiring CSR ↔ customer impersonation grants (`AccessUserSecondaryRelation`)

The session-level impersonation flow in §3 only fires if the database knows that *this CSR* is allowed to impersonate *this customer*. That permission lives in a single table:

| Column | Meaning |
| --- | --- |
| `AccessUserSecondaryRelationUserId` | The **impersonator** (i.e. the CSR -- the user who acts on behalf of someone else) |
| `AccessUserSecondaryRelationSecondaryUserId` | The **customer** being impersonated |
| `AccessUserSecondaryRelationAutoId` | Surrogate key |

The naming is counter-intuitive -- "Secondary user" reads as "the sub-user under a primary," which is the opposite of how DW interprets it. Verified direction (DW10 admin user-overview screen labels):

- Viewing the **CSR's** profile, "Users this user can impersonate" lists the rows where the CSR's id is in the `UserId` column.
- Viewing the **customer's** profile, "Users that can impersonate this user" lists the rows where the customer's id is in the `SecondaryUserId` column.

So a single grant looks like:

```sql
INSERT INTO AccessUserSecondaryRelation
    (AccessUserSecondaryRelationUserId,            -- CSR id
     AccessUserSecondaryRelationSecondaryUserId)   -- customer id
VALUES (<csr_user_id>, <customer_user_id>);
```

**Symptom of wrong direction:** the CSR signs in, the storefront impersonation bar / `CSR/Accounts/` page is empty, and (the giveaway) the customer's admin profile shows the CSR under "Users that can impersonate this user" -- meaning DW is reading the row as "customer can impersonate CSR" instead of the other way round. If you see this, swap the two ids and try again. Don't trust the column name; trust the screen label.

### Required follow-up: rebuild the Secondary user index + clear cache

Inserts/updates to `AccessUserSecondaryRelation` are **not** picked up live. Two things must happen after the SQL change before the impersonation bar appears for the CSR:

1. **Rebuild the Secondary user index** -- the impersonation lookup is index-backed.
2. **Clear the user / system cache** -- DW caches `AccessUser` objects in process memory; the new grant will not be visible until the cached row is dropped.

Both can be triggered from the DW admin UI **and** via the admin API (the admin UI buttons are thin wrappers over the same admin-API endpoints). Use whichever is convenient -- API for scripted seed flows, UI for one-off fixes:

- Settings → Indexing surfaces the index-rebuild endpoint for the Secondary user index.
- Settings → System info → Cache surfaces the cache-clear endpoint.

If you can sign in as the CSR and the impersonation bar still does not list the customer after both steps, re-check §5 column direction first; if direction is correct, re-check that the CSR's `AccessUserType` does not have the bit-16 *Service* flag set (Service-flagged users are filtered out of MCP listings and standard form-login flows).

## 6. Hiding the CSR section from non-CSR users (per-demo gating)

**Default Swift behaviour:** every signed-in user — customer admin, buyer, browse-only, AND the CSR — sees the same Customer center side nav, including the CSR section under `Customer center/CSR/{Orders, Accounts, Carts, Users}`. For demos that show a customer-admin journey alongside a separate CSR sales-on-behalf journey, this leaks the wrong persona's UI to the wrong audience.

**The canonical gate is the `Permission` entity store — zero template edits.** Per [dw10-canonical-surfaces.md](dw10-canonical-surfaces.md) §"Permissions — the entity store" → "How to gate a page subtree":

1. Set `Page.PermissionType = 0` on the CSR root + descendants.
2. INSERT one `Permission` row per (page, CSR group) binding Read access.
3. Done. All three enforcement points self-filter: the nav tree drops the pages (`PageNavigationTreeNodeProvider`), a direct URL hit (`/customer-center/csr/orders` typed in the bar) 302s via `CheckPermissionsAndRedirect()`, and paragraph render returns empty. Verify as the CSR, as a signed-in non-CSR, and anonymous — at desktop and mobile widths (the CC nav renders through three different templates; the permission gate covers all of them).

**The wrong-looking-right path:** the legacy `Paragraph.ParagraphPermission` / `Page.PagePermission` columns can be SQL-set but do NOT enforce frontend visibility — they're admin-side back-compat only. Setting `ParagraphPermission='9'` and reloading changes nothing. Write the equivalent `Permission` row instead ([dw10-canonical-surfaces.md](dw10-canonical-surfaces.md) §"Permissions — the entity store" → "Common misdiagnosis").

**If template logic genuinely needs group membership** (e.g. the §7 role badge — presentation, not gating): use `Pageview.User.GetGroups()`, non-obsolete on 10.25+ — see [dw10-canonical-surfaces.md](dw10-canonical-surfaces.md) §"User identity / groups". Never raw `SELECT FROM AccessUserGroupRelation` in Razor; it fails the grep pack at [dw10-canonical-surfaces.md](dw10-canonical-surfaces.md) §"Discipline audit — grep pack".

> Superseded 2026-06-10: this section previously gated via per-template `foreach` filters on `PageNavigationTag`, raw `Database.ExecuteScalar` lookups on `AccessUserGroupRelation`, and a redirect guard inside `Swift-v2_CustomerCenter.cshtml`, on the claim that `Pageview.User` group APIs fail at compile time. Retracted — `GetGroups()` compiles on 10.25+, template SQL fails the skill's own audit, and the Permission store gates nav + URL + render without touching templates.

### Where the CC nav renders (theming map, not a gating surface)

If you're re-theming the Customer center nav (not gating it), know that it renders through **three** templates depending on viewport and entry point:

| Template | When it renders |
| --- | --- |
| `Designs/Swift-v2/Navigation/Navigation.cshtml` | Every Swift navigation paragraph site-wide (top nav, footer, vertical side-bars outside the CC master). |
| `Designs/Swift-v2/Paragraph/Swift-v2_MyAccount/UserAvatar.cshtml` | Avatar dropdown / off-canvas mobile drawer (own recursive `RenderNavItem`). |
| `Designs/Swift-v2/Swift-v2_CustomerCenter.cshtml` | Desktop CC sidebar `<aside>` inside the CC master (another `RenderNavItem`). |

A styling change applied to only one of the three will look fixed on desktop and broken in the mobile drawer (or vice versa). Test both widths.

## 7. Persona presentation: avatar + role badge

A demo with multiple personas (customer admin / buyer / browse / CSR) lands harder when the storefront makes the persona switch *visible*. Stock Swift renders every signed-in user the same: blue avatar circle + name. To distinguish:

- Derive a role from `AccessUser.AccessUserCustomerNumber` suffix (a per-demo convention — e.g. `...-ADMIN`, `...-OWNER`, `...-BUYER`, `...-BROWSE`) **plus** CSR group membership via `Pageview.User.GetGroups()` (§6).
- Map each role to a **ring color** + **badge background/foreground**. Suggested palette: blue for admin/owner, teal for buyer, gray for browse, amber for CSR. (Adjust per-demo to fit the brand layer.)
- Render in **both** avatar templates: `Users/UserView/Detail/UserAvatar.cshtml` (header top-right) AND `Users/UserView/Detail/UserInfo.cshtml` (the bigger avatar inside the CC sidebar). Same logic, same palette — keep them visually consistent or the persona signal feels accidental rather than designed.
- Add the user's `Company` field below the role badge — distinguishes one buyer's company name from another's at a glance.

The avatar ring is best done with `box-shadow: 0 0 0 3px <color>` on the wrapper rather than `border` (border affects layout; box-shadow doesn't). The badge is a single `<span class="badge">` with inline `style=` for color tokens; consume from `--<brand>-primary` / `--<brand>-charcoal` style vars per [re-skin.md](re-skin.md) so the brand layer flows through.

## 8. Reorder a past order — `cartcmd=copyorder` is built in

DW10 ships a cart command that copies every line of a previous order into the user's active cart, repricing at today's prices. **No backend code needed, no custom controller, no MCP tool** — it's the same surface the cart uses for add-to-cart / remove / update-quantity.

The shape:

```
/Default.aspx?ID=<cart-service-page-id>&cartcmd=copyorder&orderid=<order-id>&redirect=true
```

- `ID` = the page id of the cart service / cart-handling page (the page that hosts the cart paragraph; same id used by stock add-to-cart links elsewhere).
- `orderid` = the order to copy from. Stock Swift Order paragraphs expose this as `Model.Order.Id` inside the order-list / order-detail templates.
- `redirect=true` = redirect to the cart page after the copy. Omit if you'd rather handle the response yourself.

Practical use in a Swift Order detail layout — a one-line Razor expression renders the Reorder button without any C# behind it:

```cshtml
<a class="btn btn-primary"
   href="/Default.aspx?ID=@cartServicePageId&cartcmd=copyorder&orderid=@Model.Order.Id&redirect=true">
    Reorder
</a>
```

**Where the button belongs:** `Customer center/Account/Orders/` order-detail (the buyer's own order history). The CSR section under `Customer center/CSR/Orders/` also benefits — copying a previous order while impersonating a customer is a high-impact sales-on-behalf beat ("repeat last month's pallet order in one click").

**This is a stock DW10 mechanic, not a dynamicweb-specific add-on.** Works in DW10 1.26.0 and reachable on every Swift baseline this skill loads. Adding a Reorder button is one-line of Razor in a custom content-layout for an Order-detail paragraph — it does NOT trigger base's customisations-ledger preflight because no `.cs` or controller is involved (see [`re-skin.md`](re-skin.md) §Pixel-perfect escalation for what a new content-layout `.cshtml` is and is not allowed to do).

**Related cart commands (the family `cartcmd=` belongs to).** `cartcmd=add` / `cartcmd=remove` / `cartcmd=delete` / `cartcmd=empty` / `cartcmd=update` all flow through the same handler. The Swift product-detail and cart paragraphs use these directly — meaning any `cartcmd=` URL you'd construct for a custom button is structurally identical to what Swift already emits, just with different parameters. Don't reinvent.

This pattern stays inside the [re-skin.md](re-skin.md) §Pixel-perfect escalation envelope: it's a content-layout extension to existing item-type templates (the user view models), not a controller change.
