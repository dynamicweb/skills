# Grant mechanics and backend-role recipes

Sections §6-§14 of the DW10 permission model: who bypasses every check, what the
`PermissionLevel` numbers mean, the `PermissionSave` write surface every entity grant goes
through, and the recipes that turn those grants into a working non-admin backend role. The
storage model the grants land in is [`permission-layers.md`](permission-layers.md) §1-§5.

## Contents

- [6. Admin bypass — who escapes every check](#6-admin-bypass--who-escapes-every-check)
- [7. Grant mechanics — `PermissionLevel` bit values and the `PermissionSave` write surface](#7-grant-mechanics--permissionlevel-bit-values-and-the-permissionsave-write-surface)
- [8. Functional-view entity-type checklist (flag ON)](#8-functional-view-entity-type-checklist-flag-on)
- [9. Action-button visibility — bump entity grant from Read to Edit](#9-action-button-visibility--bump-entity-grant-from-read-to-edit)
- [10. Field-level editability — the dual-gate trap](#10-field-level-editability--the-dual-gate-trap)
- [11. Per-role field-level differentiation](#11-per-role-field-level-differentiation)
- [12. Hide a UI section per group (`CapabilityLimitation`)](#12-hide-a-ui-section-per-group-capabilitylimitation)
- [13. Plaintext password storage — `EncryptPassword=False` escape hatch](#13-plaintext-password-storage--encryptpasswordfalse-escape-hatch)
- [14. `UserAddressDelete` resolves through the owning user — orphaned addresses are API-unreachable](#14-useraddressdelete-resolves-through-the-owning-user--orphaned-addresses-are-api-unreachable)

## 6. Admin bypass — who escapes every check

Source: `dw10source/Dynamicweb.CoreUI/CapabilityControl/CapabilityHelper.cs:87` (verified DW 10.25.8):

```csharp
internal static bool IsRelevantUser(int userId)
    => UserManagementServices.Users.GetUserById(userId) is User user
       && !(user.IsAngel || user.IsBuiltInAdmin);
```

Three classes of user bypass all `CapabilityLimitation` checks AND the per-resource Layer C checks
(Dashboard listings, area trees, ProductField columns, File trees — everything):

- **Angel** (`AccessUserID = 1`) — the system-bootstrap account; always sees everything.
- **BuiltInAdmin** (`AccessUserType = 1`, "SystemAdministrator") — installation-owner account.
- **Administrator** (`AccessUserType = 3`) — full backend admin in practice; bypasses Capability + dashboard relation filters via empty-userIds context.

Effect: when designing or testing a role matrix, never verify a scoping by logging in as one of the
above. Always create a Default-type user in the target group and log in as them. A scoping that "works"
only because you're testing as Admin is not a scoping.

**`allowBackend=false` is a no-op on an admin row: clear the `userType` instead, then read the value
back.** The save does assign `user.AllowBackend = model.AllowBackend`, but
`Dynamicweb.Security.UserManagement.User.AllowBackend` is computed:
`get { if (!allowBackend && !IsAdmin) return IsAngel; return true; }`. For `AccessUserType`
SystemAdministrator (1) or Administrator (3) the getter always returns true, so the stored value
persists as `1` no matter what the model carried, with no validation error and no warning. Measured
on 10.28.1: an `update_users` call carrying `allowBackend: false, active: false` answered ok and the
row still read back as backend-allowed; the identical call with `userType: "default"` added read back
denied. The only levers that actually deny backend access are `userType` (demote to `Default=5`) and
`active: false`. So a teardown or "deactivate and deny backend" cleanup must set `userType` in the
same `update_users` call and then re-read the user with `get_user_by_id`, since the save's own echo is
not evidence. Assert separately, with `search_users`, that other backend admins survive (count the
active, backend-allowed users of type 1 and 3) so the cleanup cannot lock everyone out. The
column-level read-back and the Management API measurement are in
[dw-data-access](../../dw-data-access/SKILL.md) `references/recipes-users.md` §"Deny backend access
to an admin row".

## 7. Grant mechanics — `PermissionLevel` bit values and the `PermissionSave` write surface

`UnifiedPermission` grant rows have the shape `(PermissionUserId, PermissionKey, PermissionName,
PermissionSubName, PermissionLevel)`. The `PermissionLevel` values come from
`dw10source/src/Core/Dynamicweb.Core/Security/Permissions/PermissionLevel.cs`:

```
None=1, Read=4, Edit=20, Create=84, Delete=340, All=1364
```

Bit-flag, higher includes lower (`Edit` = `Read | 1<<4` = `4 | 16` = 20). Most action buttons in PIM
editing screens want `Edit`; the toolbar `Permissions` button on each entity wants `All`.

Two rules hold over every grant below. The permission model is cached, so a write that has not been
followed by a flush of `DefaultCapabilityService`, `DefaultCapabilitySetService` and
`PermissionService` reads as though it never landed ([`permission-layers.md`](permission-layers.md)
§4c); `DashboardAccessUserRelation` reads bypass the cache and need none. And never verify a grant
signed in as Angel / BuiltInAdmin / Administrator — those user classes bypass every check (§6);
always test as a Default-type user in the target group.

### Write surface — an admin-screen operation from inside the product

**Writing a grant is an admin-screen operation.** MCP reaches exactly one corner of the permission
store: `assign_permissions_to_assortment` writes assortment permissions, and there is no page,
paragraph, section or user-group equivalent. Everything else is authored on the entity's own
**Permissions** panel in the administration (the toolbar **Permissions** button on the entity's
screen, reached in the admin at `/Admin/UI/Content/PermissionList?Key=<key>&Name=<name>`). From
inside the product, ask for the grant to be made there and then verify it on the rendered surface:
sign in as a member of the owner group and assert the state actually changed.

The scripted write verb, its body shape and its upsert semantics are out of product —
[dw-data-access](../../dw-data-access/SKILL.md) `references/recipes-users.md` §"`PermissionSave` —
the write verb for every entity grant", which also carries the `PermissionDelete` /
`PermissionSetPermission` siblings and the read query whose empty-`SubName` trap is in
[`page-gating.md`](page-gating.md) §15.

Two facts about the stored row travel with every grant regardless of surface. **`Key` is a STRING on
every entity type**, so a numeric page id is a quoted string wherever it appears. And **the level `1`
is `None`, not the bottom of a ladder** — this is the trap that inverts a gate: a solution whose
gated pages read `Anonymous = 1` and the entitled group `= 4` is showing a denial beside a read
grant, and reading it as a 0-based ladder writes the opposite of what was meant. Print the values
beside any level read out of a solution — `None=1, Read=4, Edit=20, Create=84, Delete=340, All=1364`.

## 8. Functional-view entity-type checklist (flag ON)

To make a non-admin's PIM actually *functional* under flag ON (not just visible), you need grants on
**all five entity types** the Products + Assets areas touch. Granting only the navigation entities
(Shop / ProductGroup) leaves visible-but-empty trees and blank-column product lists. The full set per
group:

| What renders | Grant the group needs (entity, key, level) |
|---|---|
| Area tree (Products / Assets headers) | `Section` / `Products` / Read, and `Section` / `Assets` / Read |
| Channel section shows shops | `Shop` / every shop id / Read |
| Channel tree expandable to groups | `ProductGroup` / every product-group id / Read |
| **Product list columns** (Name / Number / Created / Updated / Type / custom fields) | `ProductField` / one row per field system name / Read — the standards, every custom product field, and every category field |
| **Assets tree shows folders** | `File` / `/Files` / Read — a single row; the FilePermissionEntity parent chain cascades to every subfolder and file |

Without the ProductField grants, the product list shows rows but most columns are blank. Without the
File grant, the Assets tree is empty even though the tab is visible. Both are easy-to-miss because the
tab + area-section grants alone make the chrome look correct. (Why the cascade stops at these entities
under flag ON: [`permission-layers.md`](permission-layers.md) §4 "Two entities that demand special attention".)

The Shop, ProductGroup and ProductField rows are one grant per existing row — hundreds of them on a
real catalog — and the Permissions panel writes one at a time, so seeding a role is a scripted
out-of-product job: [dw-data-access](../../dw-data-access/SKILL.md) `references/recipes-users.md`
§"Seed the functional-view grants for a backend role". Enumerate what needs granting from inside the
product first (`get_shops`, `get_groups`, `get_standard_fields`, `get_product_category_fields`) so the
list handed over is the solution's own.

## 9. Action-button visibility — bump entity grant from Read to Edit

The functional-view grants above are at `PermissionLevel.Read` (`4`). That makes the data *visible* but
leaves action buttons hidden because every write action node carries `PermissionLevelRequired =
PermissionLevel.Edit` (or `Create` / `Delete` for those operations). Symptom: a non-admin user can
browse products with full columns, but the **"Edit" link in the top-right of each attributes panel on a
product detail page is missing**. Same for inline "Edit" / "Delete" actions on group nodes,
dynamic-relation editors, AI-text generation, "Edit all" grid-edit, language add/remove, etc.

The gate sits inside the action-node factory used across product screens. The pattern (seen e.g. in
`dw10source/Dynamicweb.Application.UI/Helpers/ActionBuilder.cs:81` `GetEditNode<TScreen>()`):

```csharp
PermissionLevelRequired = PermissionLevel.Edit,
```

and the attributes-panel-specific construction in
`dw10source/Dynamicweb.Products.UI/Screens/ProductOverviewScreen.cs:996`
(`ActionBuilder.Edit<ProductEditScreen>`) and `:1076` (screen-layout-driven "Edit" node).

Fix: bump the entity-grant level from Read (4) to Edit (20) on the entities that gate the action —
`ProductGroup`, `ProductField`, `File`, and the area-root `Section` / `Products` grant so that
screen-layout-driven "Edit" tabs work. Under flag ON, the Product entity inherits level from its
parent ProductGroups (highest level wins across all parents), so bumping ProductGroup grants to Edit
cascades Edit to every product in those groups — no per-Product row needed.

What to leave at Read deliberately: `Shop` entities (editing shop config is platform-admin territory)
and `Section/Assets` (Asset edits flow through the per-product image manager which uses the `File`
grant). Bump these only when a role explicitly needs to edit shop configuration or upload to the Assets
tab directly.

A level change across an existing grant set is the same many-rows-at-once shape as §8, so it is a
scripted out-of-product job — [dw-data-access](../../dw-data-access/SKILL.md)
`references/recipes-users.md` §"Bump entity grants from Read to Edit". Until the permission cache
drops, logged-in users keep seeing Read-level UI, so the verification is a fresh sign-in as a
Default-type member of the group, checking that the attributes-panel "Edit" link is there.

## 10. Field-level editability — the dual-gate trap

Bumping ProductField grants to Edit makes write-action *buttons* appear, but a user who clicks "Edit"
on a product can still land on a screen where **every field renders with a readonly lock icon** —
including standard text fields like Name and custom category fields. The reason is the dual-gate inside
`dw10source/Dynamicweb.Products.UI/Screens/ProductEditScreen.cs:491`:

```csharp
if (!productLanguage.HasPermission(PermissionLevel.Edit) || !field.HasPermission(PermissionLevel.Edit))
    return true; // readonly
```

Both conditions must pass:

1. The `Language` entity for the product's language has `Edit` for the current user.
2. The `ProductField` entity has `Edit` for the current user.

If only one is granted, every input is readonly. **The Language entity is the easy one to forget**
because the entity isn't visually represented on the screen — there's no "Language" panel to click.
With Cap Control ON, `Language.GetPermissionParents()` terminates (no `PermissionSection("Products")`
fall-through), so no upstream grant cascades and the row has to exist explicitly, one per language.

The `PermissionKey` is the language id (e.g. `"LANG1"`, from `get_languages`), not the ISO code. The
grant itself is one `Language` / `<language id>` / Edit row per language — written on the Permissions
panel, or scripted for a multi-language install per
[dw-data-access](../../dw-data-access/SKILL.md) `references/recipes-users.md` §"Grant the Language
entity". The symptom that tells you which half is missing: buttons visible and every input locked
means the ProductField half landed and the Language half did not.

## 11. Per-role field-level differentiation

The functional-view bump above ("all standard + custom + category fields to Edit") is the *unlock* — it
makes the screen functional but gives every role the same write surface. To produce **field-level role
security** (writable for some roles, readonly for others), differentiate per role by leaving some
fields at Read for roles that don't own them. The technique:

1. Apply the functional-view checklist to bump everything to `Edit` (level 20) for all groups.
2. Apply the dual-gate fix (Language Edit grants).
3. Per role, identify the fields that role does NOT own and DOWNGRADE those rows to `Read` (level 4).

The downgrade is one level change per role against a list of `ProductField` system names the role
should not write. A content-owning role, for instance, keeps content / meta / image / custom-category
fields editable and has the commerce, lifecycle, workflow and physical fields downgraded to Read:
`ProductNumber`, `ProductPrice`, `ProductCost`, `ProductStock`, `ProductActive`,
`ProductWorkflowStateId`, `ProductDiscontinued`, `ProductDefaultShopID`, `ProductManufacturerID`,
`ProductType`, `ProductEAN`, `ProductWeight`, `ProductHeight`, `ProductWidth`, `ProductDepth`,
`ProductVolume`, `ProductCreated`, `ProductUpdated`. The mirror-image role (workflow-owning, no
content edits) downgrades the custom category fields instead — read the list for the solution in hand
with `get_product_category_fields`.

The step is one bulk level change per role, so it runs with §9's script rather than on the panel:
[dw-data-access](../../dw-data-access/SKILL.md) `references/recipes-users.md` §"Per-role field-level
differentiation".

The result is two visually-different Edit screens for the same product — one role sees content / images
/ category fields as editable inputs and commerce / workflow as readonly with lock icons; another sees
the inverse. The role split becomes visible without any custom code, just data-side grants.

What to keep at `Edit` for every role: `ProductGroup`, `Section/Products`, `File` (`/Files`),
`Language` (per language used). What to keep at `Read` for every role: `Shop` entities,
`Section/Assets` (unless a role explicitly needs shop-config edits or direct Asset-tab uploads).

## 12. Hide a UI section per group (`CapabilityLimitation`)

Layer B semantics: presence of a row = hide; group IDs only; parent keys cascade ([`permission-layers.md`](permission-layers.md) §3). The operational
steps:

- Insert one `CapabilityLimitation` row per (group, capability key) to hide — e.g. key `/Products/Feeds` for a group hides the Feeds section while `/Products/AllProducts` stays visible.
- Limiting a parent key (e.g. `/Products`) hides the entire left-nav section; child grants do not override.
- There is no per-user override — to hide a capability for one specific user, put them in a dedicated group and limit the group.
- Flush `Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilityService` afterwards (via `CacheInformationRefresh`, [`permission-layers.md`](permission-layers.md) §4c).

For per-user dashboard pinning via `DashboardAccessUserRelation`: insert one `Default=1` row per
(dashboard, user) pair to give a user an auto-landing dashboard, plus `Default=0` rows for any users
who should also see it. No cache flush needed — the table is queried per request ([`permission-layers.md`](permission-layers.md) §4b).

**A `Section`-level `UnifiedPermission` deny hides only the Settings area on 10.28 — promise nothing
else.** `ShellScreen.GetAreas()` drops an area when its `GetPermissionSection().HasPermission(Read)` is
false, but only Settings is evidently gated on its Section in the shipped shell. Measured with explicit
level-`None` (1) rows in the database for a persona's single group:

```
UnifiedPermission for the persona's group: Section|Settings=1, Users=1, Integration=1,
                                           Commerce=1, Marketing=1, Content=1, <add-in area>=1
signed in as that persona -> areas = [Apps, Content, <add-in area>, Ecommerce, Files, Insights,
                                      Integration, Marketing, Products, Users]     (Settings gone)
same run, a persona with Section|Settings=4 (Read) -> the same list PLUS Settings
```

The area keys are correct (confirmed by reflection over every `AreaBase` subclass: Apps, Commerce,
Insights, Integration, Marketing, Products, Settings, Users, plus Content and Files), so this is not a
key-naming mistake. **Do not sell a Section-level nav fence for Commerce / Content / Marketing /
Integration / Users on 10.28.** Where a tight persona navigation is genuinely required, hide the sections
with `CapabilityLimitation` rows (above) rather than Section denies, and verify by logging in as a
Default-type persona and recording the permission-filtered area list.

## 13. Plaintext password storage — `EncryptPassword=False` escape hatch

**The passwordless-user trap.** There is **no MCP password tool** — `create_users` (and the Management
API `UserSave`) create a login with **no usable password**, so a freshly-seeded buyer / CSR / admin
persona **cannot sign in** until a password is set out-of-band. Naively adding personas via MCP and
then trying to sign in as them fails at the sign-in screen with no obvious cause. Setting the password
is an admin-screen operation from inside the product — Users → the user → the password field — and the
scripted escape hatch for a whole persona set is
[dw-data-access](../../dw-data-access/SKILL.md) `references/recipes-users.md` §"Seed a password for a
freshly created login". **Validate:** after the password is set, actually sign in as the persona (not
as an admin) and confirm you reach the account/customer-center landing.

**A user index is a second copy of the password column.** Every document a user repository builds
carries `UserPassword` — the stored hash — because the platform's own schema extender declares it, and
no `.index` setting removes it. Standing up a user repository therefore writes one offline-crackable
hash per account into a Lucene file under the web root's file area. Treat that folder as sensitive and
keep it out of copies that travel; the full statement is in
[`dw-search-indexing`](../../dw-search-indexing/references/index-management.md#the-user-index-publishes-a-password-hash-and-the-whole-impersonation-graph).

`GlobalSettings.config` (path: `Dynamicweb.Host.Suite/wwwroot/Files/GlobalSettings.config` on a
standard install) controls password storage mode for both backend admins and extranet users:

```xml
<Users>
  <EncryptPassword>False</EncryptPassword>
  ...
</Users>
<Extranet>
  <EncryptPassword>False</EncryptPassword>
</Extranet>
<UserManagement>
  <EncryptNewPasswords>False</EncryptNewPasswords>
</UserManagement>
```

When `EncryptPassword=False` (typical for development / on-prem solutions), the
`AccessUser.AccessUserPassword` column stores plaintext, which is what makes the scripted escape
hatch possible at all.

The MCP `create_users` tool has no password parameter (verified DW 10.25.8); the Management API
`UserSave` command likewise **cannot set a password** — a backend user created through either has no
usable password until one is set. The admin UI's Users → user → password field works and is manual;
automated seeding is the out-of-product recipe. Check the setting before anyone relies on it —
production solutions often flip these to `True`, and any plaintext seeded under `False` becomes a
stale invalid hash after the flip. (DW10's `AuthenticationManager.cs:184` auto-rehashes a plaintext
seed on first successful login.)

## 14. `UserAddressDelete` resolves through the owning user — orphaned addresses are API-unreachable

**The Ecommerce health check flags orphaned `AccessUserAddress` rows, and the only address-delete verb answers
`404` for exactly those rows.** `UserAddressDelete` takes a scalar `AddressId` but looks the address up
**through its owning user**; an orphan carries `AccessUserAddressUserId = 0`, so there is no user to resolve
through and the lookup fails:

```
POST UserAddressDelete {AddressId: <orphanId>}  -> 404 {"status":"notFound","message":"Address not found: <orphanId>"}
```

So no verb — and no MCP tool — can fix what the health check reports; the delete is an out-of-product
one ([dw-data-access](../../dw-data-access/SKILL.md) `references/recipes-users.md` §"Delete orphaned
user addresses"). Scope it precisely (`AccessUserAddressUserId = 0` **plus** blank address fields):
orphans interleave with real address ids, so an id-range delete takes live personas' addresses with
it.

Two generalisations worth carrying:

- **Health-provider orphan rows are usually API-unreachable by construction** — the verbs resolve through the
  parent entity that the orphan, by definition, has lost. Expect a sanctioned SQL exception rather than
  hunting for a verb that does not exist.
- **Check the provenance before deciding it is fallout.** All 19 rows on one install were completely blank with
  `UserId 0` — residue of address-save probes that ran with no user id, not deleted-user fallout. Verify
  afterwards that the health provider's orphaned-address check returns 0 **and** that live personas still have
  their addresses.

## Cross-references

- [`permission-layers.md`](permission-layers.md) — §1-§5, the storage tables, the entity registry
  and the backend `Section` entity these grants are written against.
- [`page-gating.md`](page-gating.md) — §15-§16, the render-time half: gating storefront pages and
  paragraphs with the same `PermissionSave` verb.
- [`user-group-operations.md`](user-group-operations.md) — §17, the user/group/impersonation write
  verbs and the storefront user-management app.
- [dw-data-access](../../dw-data-access/SKILL.md) (`cache-invalidation.md`) — the per-surface cache
  rulebook these recipes' flush steps come from.
