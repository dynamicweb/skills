# Render-time page and paragraph gating

Sections §15-§16 of the DW10 permission model: how the storefront resolves `Page` / `GridRow` /
`Paragraph` permissions at request time, and the customer-number-suffix presentation flag that is
the lighter alternative when the requirement is display-only. The storage model is
[`permission-layers.md`](permission-layers.md) §1-§5; the write verb and the level values are
[`grant-mechanics.md`](grant-mechanics.md) §7.

## Contents

- [15. Render-time half — page/paragraph permissions (the entity store)](#15-render-time-half--pageparagraph-permissions-the-entity-store)
- [16. Customer-number suffix as a role flag (presentation gate)](#16-customer-number-suffix-as-a-role-flag-presentation-gate)
- [Cross-references](#cross-references)

## 15. Render-time half — page/paragraph permissions (the entity store)

This is the **render-time** half: how the storefront's `Page` / `Paragraph` permissions resolve at
request time. The load-bearing fact that prevents the entire "SQL-write to
`EcomParagraph.ParagraphPermission`, then template-shim because nothing gates" detour: DW10's `Page`
and `Paragraph` render-time permissions live in the permission **entity store**, not in the legacy
`Page.PagePermission` / `EcomParagraph.ParagraphPermission` columns. The legacy columns exist for
back-compat but the runtime renderer ignores them.

### Canonical gate — YAML-carried permissions in the base layer (base ≥ 2.4.0 / serializer ≥ 0.8.0-beta)

**The canonical way to ship a page/grid-row/paragraph gate is IN THE LAYER YAML, not a live post-deserialize step.** From base **2.4.0** on serializer **≥ 0.8.0-beta**, `page.yml`, `grid-row.yml`, and `paragraph-*.yml` each carry an optional `permissions:` block that deserializes straight into the `UnifiedPermission` rows described below — no admin-panel click, no SQL INSERT, no cache flush at build time. The block shape is identical across all three entities:

```yaml
"permissions":
- "owner": "Customers"          # group name (informational)
  "ownerType": "group"          # group | role
  "ownerId": "1325"             # group id (omitted for roles; role name IS the owner)
  "level": "all"                # all | read | none
  "levelValue": 1364            # PermissionLevel bit value (all=1364, read=4, none=1)
# roles carry no ownerId:
- "owner": "Anonymous"
  "ownerType": "role"
  "level": "none"
  "levelValue": 1
```

This makes per-role dashboards **fully derivable from the layer**: base 2.4.0's Customer Center puts buyer tiles and CSR tiles on ONE shared `Overview` page, each tile paragraph (and its grid row) gated `Customers=all / CSR=none` or `CSR=all / Customers=none`, all `Anonymous=none` — a buyer and a CSR open the same URL and see different tiles, zero custom code. (Per-role tiles on one shared page were previously believed impossible via YAML; that was the pre-0.8.0 engine, which serialized permissions page-level only.)

**Engine floor is load-bearing.** An engine **≤ 0.7.1-beta silently drops** the row/paragraph `permissions:` blocks on deserialize (`IgnoreUnmatchedProperties`) → the tiles render **ungated** (a security regression). A base that carries these blocks declares the engine floor in `layers/base/base.contract.json` `minSerializerVersion`; read that floor from the layer and consume the base only on an engine at or above it.

**Ordering trap (handled in-engine, ≥ 0.8.0-beta).** AccessUser groups deserialize AFTER the content that references them; the engine defers unresolvable-group permission sets to an end-of-run re-apply pass (with a user-group cache refresh) so group grants land instead of collapsing to the `Anonymous=None` safety fallback. Verify with a permissions-parity check: every serialized `permissions:` block ⇔ matching `UnifiedPermission` rows (count + owner + level + SubName).

**The live post-deserialize seed below (admin Permissions panel / SQL INSERT + cache flush) is now a LEGACY FALLBACK** — use it only for older bases/engines that cannot carry the blocks, or for ad-hoc gating outside a layer. For a base ≥ 2.4.0 the correct action after deserialize is to **verify** the YAML-carried gating applied (parity check), not to re-seed it.

### Physical storage — `UnifiedPermission` rows keyed `PermissionName='Page'`/`'GridRow'`/`'Paragraph'` (verified DW 10.26.x)

The entity store's physical rows land in the **same `UnifiedPermission` table** as the Layer-A
entity grants ([`permission-layers.md`](permission-layers.md) §2), disambiguated by `PermissionName`:

```
UnifiedPermission
  PermissionName     'Page'  (render-time page gate; Layer-A grants use entity names instead)
  PermissionKey      page id as string (e.g. '69')
  PermissionUserId   role string: 'Anonymous' | 'AuthenticatedFrontend'
  PermissionLevel    bit values per PermissionLevel.cs — None=1, Read=4, Edit=20, …
```

Verified live on 10.26.x by writing gates through the admin Permissions panel and SELECTing the rows
back: every grant lands in `UnifiedPermission`. A separate `Permission` table with
`PermissionOwnerName` / `PermissionOwnerKey` / `PermissionExplicitDeny` columns does not hold these
rows on that build, and `AccessElementPermission` (which also exists) stays empty throughout. The
modelling-time / render-time split this ref opens with is **semantic, not physical** — same table,
different `PermissionName`, key shape, and enforcement points.

**Group-scoped gates need the deny+grant pair.** Rows scoped to the frontend role strings
`Anonymous` / `AuthenticatedFrontend` gate correctly on their own. A **bare** group-id grant does
NOT gate — highest-wins resolution lets the inherited broad `AuthenticatedFrontend` grant override
it, which reads as "group gating is non-functional" if that's the only shape tested. The working
shape (verified live on 10.26.x, page AND paragraph level): an explicit
`AuthenticatedFrontend → None` deny **plus** a `<group id> → Read` grant **on the same entity** —
i.e. exactly the two-step recipe under "Frontend resolution" below. For visibility that should
follow commerce data rather than CMS permissions, prefer the surfaces that natively scope by group
(Assortments, DC groups — [`dc-scoping.md`](../../dw-commerce-b2b/references/dc-scoping.md)).

### Enforcement points

- Page navigation tree filter: `PageNavigationTreeNodeProvider.cs:161` —
  `page.HasPermission(PermissionLevel.Read)`.
- Page-level redirect for anon: `PageView.cs:399-427` `CheckPermissionsAndRedirect()` auto-302s anon
  hits to the login page (target resolution below).
- Paragraph render: `Frontend/Content.cs:398` — returns `ContentOutputResult.Empty` when
  `paragraph.HasPermission(PermissionLevel.Read)` fails.

### Anonymous deny → automatic redirect to the UserAuthentication page

When a page-level gate denies an anonymous visitor, the 302 target is **the first page in the
website that carries the UserAuthentication app** — DW auto-discovers it; there is no area-level
"login page" setting to point at (the area settings surface exposes none). Keep that page active and
un-gated, and keep it unique per website.

This enables the signed-in-first storefront (the B2B-portal default): grant
`AuthenticatedFrontend → Read` and `Anonymous → None` on the storefront entry pages (shop root, cart,
customer center); leave the sign-in page, its children (forgot password, create profile), and the
header/footer utility folder un-gated so the login page renders with chrome. An anonymous hit on `/`
then 302s to sign-in. Page-level gating is the ONLY layer that redirects — assortment scoping and
paragraph gating just render an empty page (empty catalog / `ContentOutputResult.Empty`), which reads
as "blank homepage", not "please sign in".

### How to gate a page subtree (e.g. a role-restricted section)

1. **Write an explicit row for every identity, not only for the ones being granted.** A group with
   no row on the page inherits its PARENT's permission, and the parent of a root-level page is the
   area default, which is permissive — so a positive-only grant ("all" to the two entitled groups,
   "none" to Anonymous) admits every other signed-in persona. Enumerate the install's user groups
   and write `all` for those that may see the page and `none` for the rest; copy the row shape from
   a baseline page that already ships one row per group. Eight `none` rows per page is the normal
   size of a correct gate, not a sign of overkill.
2. Put the rows on the subtree root; children inherit (`Page.PermissionType = 0` keeps a page
   inheriting rather than carrying its own rows). No template edits: nav, redirect and
   child-render all self-filter.
3. **Verify by SIGNING IN as one persona from each DENIED group, AND as one from a granted group, in
   the same pass.** "Anonymous is redirected" proves nothing: Anonymous is the one identity a
   positive-only grant does deny, which is exactly why the broken shape reads as working. A denied
   signed-in user does not get a redirect or a 403 either — the page answers **HTTP 200 with a
   near-empty body** (a shell of a few hundred bytes), so the observation is the **rendered body size**,
   not the status code. And address the page **by id** (`/Default.aspx?ID=<pageId>`) rather than by a
   composed friendly path: a subtree whose friendly url does not resolve answers 404 for every identity,
   granted and denied alike, so the check passes without ever reaching the gate. PASS needs both halves —
   a full page for the granted persona and a near-empty one for the denied — and a run where both
   personas receive the same response is a broken check, not a pass. A row read-back is not proof either — `PermissionsByIdentifier`
   has the empty-`SubName` trap below and answers for keys that carry nothing. Most-permissive wins
   across a user's groups, so a user holding one granted group and three denied ones is admitted by
   design; design the group map for that rather than fighting it.

### How to hide a single paragraph from a persona

**Canonical path (base ≥ 2.4.0 / serializer ≥ 0.8.0-beta): author the `permissions:` block on the `paragraph-*.yml` in the layer** (see "Canonical gate" above) — it deserializes into the row described here with no live step. The live/SQL recipe below is the legacy fallback for older bases/engines.

Same entity-store mechanics with `PermissionName='Paragraph'` and the paragraph id as
`PermissionKey` (live-verified on 10.26.x): write the deny+grant pair —
`('AuthenticatedFrontend', '<paragraphId>', 'Paragraph', <None>)` plus
`('<groupId>', '<paragraphId>', 'Paragraph', <Read>)` — via the paragraph's Permissions panel or
direct SQL + security-cache flush. The frontend renderer's `Content.cs:398` returns empty content
for users without a read grant.

### Frontend resolution takes the HIGHEST level across a user's identities

Frontend permissions resolve by **role**, not by individual `AccessUser` id — a specific-user grant
is ignored. Resolution takes the **highest** level across all of a user's identities, so you
**cannot hide a page from a sub-audience by giving it `None`** if a broader role the user also holds
grants `Read`. To hide a subtree from one persona while keeping it for others:

1. Deny the broad role on the subtree root (e.g. `AuthenticatedFrontend → None`).
2. Grant the personas that *should* keep it → `Read` (group-id grants work here — the explicit
   deny in step 1 is what makes them effective; a group grant without it is silently overridden).

The excluded persona then resolves to `None` (section drops from all nav templates, direct URLs 302);
others keep it; children inherit the root.

**Impersonation switches the identity the gate resolves against.** While a session impersonates,
page permissions are evaluated against the EFFECTIVE (impersonated) user, not the signed-in staff
identity. That is what makes the customer-only dashboards correctly reappear under impersonation —
and it also means **a page gated to a staff group is unreachable for the whole impersonation
session**: measured on 10.28.x, a CSR's own staff section and every page under it answered a
~130-byte "You do not have permission to view the page" from the moment impersonation started, and
was byte-identical to its pre-impersonation render the moment the grant was released. So **land the
impersonation Redirect on a page the CUSTOMER can see** (the shipped ship-to selector, the customer
centre) and put the staff affordances in the impersonation bar, which renders everywhere. A staff
tool that has to stay on screen DURING impersonation is the one shape this model cannot carry.

### Common misdiagnosis

If a `Page.PagePermission` / `EcomParagraph.ParagraphPermission` UPDATE didn't gate the entity from
frontend users, you wrote to the **wrong place** — the legacy column is admin-side only; the runtime
check reads the entity store (`UnifiedPermission`, `PermissionName='Page'`). Symptoms: paragraph
still renders for anon despite `ParagraphPermission='9'`; page still navigable despite
`PagePermission='<groupId>'`; admin Permissions panel shows the legacy value but the storefront
ignores it. Fix: revert the legacy-column write, add the equivalent entity-store grant through the
Permissions panel, remove any template shims added to compensate.

### A grant written under the admin UI takes effect; one written under it does not

The admin UI invalidates the permission model as part of the write. A grant that reached the table by
any other route does not invalidate anything — DW caches the model in process — so the nav still
shows the pages and the gate still lets the page render until the cache drops. **A gate that reads as
broken immediately after an out-of-product grant is usually a stale cache, not a wrong row**: check
when the model was last invalidated before re-writing the grant. The flush itself and what owes it
are in [dw-data-access](../../dw-data-access/SKILL.md) `references/recipes-users.md`.

### Where the customer-center nav renders (theming map, not a gating surface)

If re-theming the customer-center nav (not gating it), note it renders through **three** templates by
viewport / entry point: `Navigation/Navigation.cshtml` (site-wide nav paragraphs);
`Paragraph/Swift-v2_MyAccount/UserAvatar.cshtml` (avatar dropdown / mobile drawer); and
`Swift-v2_CustomerCenter.cshtml` (desktop CC sidebar `<aside>`). A styling change applied to only one
looks fixed on desktop and broken in the mobile drawer (or vice versa). Test both widths. The
**permission gate covers all three** without per-template edits — prefer it over template `foreach`
filters on `PageNavigationTag`.


### Write surface — the Permissions panel

Page, grid-row and paragraph grants go through the same surface as every other entity grant, and
that surface is an admin screen, not an MCP tool: [`grant-mechanics.md`](grant-mechanics.md) §7
carries the panel, the `PermissionLevel` numbers (`1` is `None`, `4` is `Read`) and the pointer to
the scripted form.

**The READ side has a trap that inverts its answer: the permissions-by-identifier read returns an
EMPTY result when the sub-name is passed as an empty string.** An empty-string sub-name is not
treated as "no sub-name" — it filters to nothing. Auditing page permissions before a change is
exactly when this fires, and the empty result reads as "no permissions configured, safe to add mine"
while the rows sat there the whole time. **Omit the sub-name entirely when reading**; the write side
still takes an empty sub-name normally. The literal request pair and the cross-check that proves the
rows exist are in [dw-data-access](../../dw-data-access/SKILL.md) `references/recipes-users.md`
§"`PermissionsByIdentifier` — the read verb and its empty-SubName trap".

From inside the product the reliable audit is the rendered one: fetch the protected URL
anonymously with `fetch_frontend_page_html` and treat a redirect to sign-in as the gated state and a
200 as ungated. Never treat an empty permission read as "no permissions set".

### Static files under `/Files` bypass page permissions entirely

**`UnifiedPermission` gates the PAGE request pipeline. A request for `/Files/...` is served by the static
file handler and never enters it**, so every image, PDF and screenshot embedded in a role-gated page stays
anonymously readable:

```
GET /Files/Images/<folder>/<asset>.png   with no cookies  -> 200, image/png, valid PNG
   (the same asset's host page denies anonymous, the dealer buyer AND the account admin)
```

**Treat anything under `/Files` as public.** Never put a screenshot carrying a credential, a token or a
customer's data behind a page gate and call it protected, and state the exposure in the run notes rather
than implying the gate covers it. Page-level gating protects the narrative, not the assets.

## 16. Customer-number suffix as a role flag (presentation gate)

For lightweight storefront visibility flags ("hide prices for browse-only", "installer mode"), the
lowest-overhead role gate bakes the role into the user's `AccessUserCustomerNumber` suffix (e.g.
`<customer-number>-BROWSE`) and reads it off `Pageview.User?.CustomerNumber` in any paragraph that gates
behavior:

```csharp
bool isBrowseOnly = Pageview.User?.CustomerNumber?.EndsWith("-BROWSE",
    StringComparison.OrdinalIgnoreCase) ?? false;
bool hidePrice = (anonLimitations.Contains("price") && anonymousUser) || isBrowseOnly;
```

No new user group, no permission plumbing, no admin wiring beyond seeding the `AccessUserCustomerNumber`
field. Extends the existing `Pageview.AreaSettings.AnonymousUsers` machinery rather than introducing a
parallel role system.

**When to escalate.** The suffix-as-role pattern is right when the role is a *visibility flag* on the
storefront templates (hide price, hide add-to-cart) — you're already touching the relevant layout.
When the role must drive Assortments / Shipping methods / fees / cart-time pricing, escalate to **DC
user groups** ([`dc-scoping.md`](../../dw-commerce-b2b/references/dc-scoping.md)) instead. The two
compose: a buyer is both a member of a DC group (group → unlocks Assortments + Shipping) and carries a
`-BROWSE` customer-number suffix (suffix → suppresses price display).

A presentation role can also combine the suffix with CSR/staff group membership read via
`Pageview.User.GetGroups()` ([dw-render-viewmodels](../../dw-render-viewmodels/SKILL.md)) to drive
avatar-ring / badge presentation — that is presentation, not gating; use `GetGroups()` for it, never
raw `SELECT FROM AccessUserGroupRelation`.


## Cross-references

- [`permission-layers.md`](permission-layers.md) — §1-§5, the storage model these rows live in.
- [`grant-mechanics.md`](grant-mechanics.md) — §7, the `PermissionSave` body and the
  `PermissionLevel` numbers; §6, the user classes that bypass every check when you try to verify a
  gate.
- [`user-group-operations.md`](user-group-operations.md) — §17, impersonation grants and the
  storefront user-management app whose commands these permissions gate.
- [`dc-scoping.md`](../../dw-commerce-b2b/references/dc-scoping.md) — DC user groups, the group
  layer a page gate composes with.
