# Foundational candidate → dw-users-permissions

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 permissions knowledge, staged here for a future
> fold-up into `dw-users-permissions`. No demo/customer content. When folded, move this body into
> `dw-users-permissions` and re-target the pointers in the demo skills. Until then, the demo skills
> reference this file.

## Contents

- [1. The `CapabilityControlFeature` flag — DW10.21+, default OFF](#1-the-capabilitycontrolfeature-flag--dw1021-default-off)
- [2. Layer A — `UnifiedPermission` (the storage layer)](#2-layer-a--unifiedpermission-the-storage-layer)
- [3. Layer B — Capability Control (UI-section visibility)](#3-layer-b--capability-control-ui-section-visibility)
- [4. Layer C — Entity-level permissions](#4-layer-c--entity-level-permissions)
- [4b. Dashboard pinning — separate `DashboardAccessUserRelation` table](#4b-dashboard-pinning--separate-dashboardaccessuserrelation-table)
- [4c. Admin-UI exposure gap — must script the tables directly](#4c-admin-ui-exposure-gap--must-script-the-tables-directly)
- [5. The unified picture](#5-the-unified-picture)
- [6. Admin bypass — who escapes every check](#6-admin-bypass--who-escapes-every-check)
- [7. Grant mechanics — `PermissionLevel` bit values](#7-grant-mechanics--permissionlevel-bit-values)
- [8. Functional-view entity-type checklist (flag ON)](#8-functional-view-entity-type-checklist-flag-on)
- [9. Action-button visibility — bump entity grant from Read to Edit](#9-action-button-visibility--bump-entity-grant-from-read-to-edit)
- [10. Field-level editability — the dual-gate trap](#10-field-level-editability--the-dual-gate-trap)
- [11. Per-role field-level differentiation (the SQL technique)](#11-per-role-field-level-differentiation-the-sql-technique)
- [12. Hide a UI section per group (`CapabilityLimitation`)](#12-hide-a-ui-section-per-group-capabilitylimitation)
- [13. Plaintext password storage — `EncryptPassword=False` escape hatch](#13-plaintext-password-storage--encryptpasswordfalse-escape-hatch)
- [15. Render-time half — page/paragraph permissions (the entity store)](#15-render-time-half--pageparagraph-permissions-the-entity-store)
- [16. Customer-number suffix as a role flag (presentation gate)](#16-customer-number-suffix-as-a-role-flag-presentation-gate)
- [17. Cross-references](#17-cross-references)

This is the modelling-time half of DW10 permissions — three SQL tables (`UnifiedPermission` for
entity grants, `CapabilityLimitation` for UI hides, `DashboardAccessUserRelation` for per-user
dashboard pinning), two semantic conventions (permit vs limit — opposite directions), one feature
flag (`CapabilityControlFeature`, DW10.21+) that decides whether the layers cascade or stand
orthogonal. The flag's default and its cascade behavior are the load-bearing facts that prevent the
"I granted Edit on the Products area but the user still can't see anything" detours.

The **render-time** half of permissions — how the storefront's `Page`/`Paragraph` permissions
resolve at request time — lives in §15 below ("Render-time half — page/paragraph permissions").
That section owns the render-time rows — physically `UnifiedPermission` rows keyed
`PermissionName='Page'` on 10.26.x — read on every page/paragraph render. This ref owns
modelling-time concerns (entity hierarchy, capability tree, flag decision, grant seeding); that ref
owns render-time lookup. Roughly: this section's layers control who can EDIT a product in admin; §15
controls who can SEE a CMS page on the storefront. Both live in `UnifiedPermission`, but the
`PermissionName` key shape, role semantics, and enforcement points differ.

> **Admin-UI gap warning (verified DW 10.25.8).** The admin UI does NOT expose per-resource
> Permissions or CapabilityLimitation editing for Dynamic Workspaces, Dashboards, or user-group
> Capability Sets. Direct-SQL on the three tables above is the path. See §4c for the full surface map
> + cache-flush requirement.

## 1. The `CapabilityControlFeature` flag — DW10.21+, default OFF

Source: `dw10source/src/Core/Dynamicweb.Core/CapabilityControl/CapabilityControlFeature.cs:3`:

```csharp
public sealed class CapabilityControlFeature() : FeatureBase("Capability Control", "Capabilities", false);
```

The third positional argument (`false`) is the default-enabled flag. **Capability Control ships OFF.**
Toggle via Settings → Feature management → "Capability Control".

### What the flag changes

The flag is a single switch on a uniform pattern: every entity type in the Products area (Shop /
Group / Product / Feed / Assortment / DynamicStructure) has a `GetPermissionParents()` method whose
tail looks like:

```csharp
if (!Feature.IsActive<Core.CapabilityControl.CapabilityControlFeature>())
    yield return new PermissionSection("Products");
```

Verified:
- `Shop.cs:310-311` (PermissionName at line 314 = `"Shop"`)
- `Group.cs:313-314` (PermissionName at line 278 = `"ProductGroup"`)
- `Product.cs:513-514` (the guard; the `PermissionName` const declaration is at line 498 = `"Product"`)
- `Feed.cs:128-129` (PermissionName at line 118 / 132 = `"Feed"`)
- `Assortment.cs:186-187` (PermissionName at line 180 / 190 = `"Assortment"`)
- `DynamicStructure.cs:60-61` (PermissionName at line 43 = `"DynamicStructure"`)

When the flag is **OFF (legacy, default)**: every entity's parent chain terminates at
`PermissionSection("Products")` — so a grant on the `/Products` capability key cascades down to every
Shop, every Group, every Product, every Feed, every Assortment, every Dynamic Workspace in the system.
This is the inherited DW9-style mental model: "give a user Edit on Products and they get Edit
everywhere."

When the flag is **ON (modern)**: the legacy top link is severed. Entity-level grants stand alone. The
capability tree (Layer B, §3 below) gates *menu visibility*; the entity tree (Layer C, §4) gates
*actions*. They are orthogonal — both must grant for the user to see AND act.

### Decision rubric — ON or OFF for an install

| You want… | Flag |
|---|---|
| The "give Admin user Edit on Products and they can do everything" legacy mental model | OFF |
| Per-section UI hiding (e.g. hide `/Products/Feeds` from product managers; keep `/Products/AllProducts` visible) | ON |
| To showcase the modern permission model to a PIM-selection committee | ON |
| Minimum-effort grants (one capability assignment cascades everywhere) | OFF |
| Per-channel publishing authority where different roles see different channels | ON |
| **You're not sure** | OFF — match the ship default; revisit when the brief calls for orthogonal gating |

**Decide BEFORE granting anything.** Two different role matrices follow from the two settings;
toggling mid-build strands every grant already made.

> **Do not confuse with the Completeness feature flag** (separate flag, also off by default — the
> buggy beta completeness calculation path). `CapabilityControlFeature` is independent of completeness
> behavior.

## 2. Layer A — `UnifiedPermission` (the storage layer)

Source: `dw10source/src/Core/Dynamicweb.Core/Security/Permissions/PermissionRepository.cs`.

```sql
TABLE UnifiedPermission (
  PermissionUserId   nvarchar  -- user OR user-group id
  PermissionKey      nvarchar  -- the resource path (e.g. '/Products/Feeds' or 'SHOP1')
  PermissionName     nvarchar  -- secondary qualifier
  PermissionSubName  nvarchar  -- tertiary qualifier
  PermissionLevel    smallint  -- enum: NotSet / None / Read / Edit / Create / Delete / All
)
```

Verified mechanics:
- `MERGE [UnifiedPermission] WITH (SERIALIZABLE)` insert (line 53) — atomic upsert, no race on concurrent grants.
- `PermissionLevel` is hierarchical: `All` ⊇ `Delete` ⊇ `Create` ⊇ `Edit` ⊇ `Read`.
- Multi-group membership resolves to **highest level wins** across all groups a user belongs to.
- `IncludeSubKeys` query mode (line 111) issues `PermissionKey LIKE '<key>%'` — so granting `/Products` cascades through every sub-section's key when the flag is OFF (§1).

**Layer A stores Layer C (entity) grants.** The layer-A table holds entity-level rows (Shop /
ProductGroup / Product / ProductField / FilePermissionEntity / DynamicStructure / Feed / Assortment /
`Section` for area roots). Each row's *shape* is determined by `PermissionName` (entity type) +
`PermissionKey` (entity id or SystemName). **Layer B does NOT write here.** Capability Control (Layer
B) lives in its own table — see §3.

## 3. Layer B — Capability Control (UI-section visibility)

Source: `dw10source/Dynamicweb.Products.UI/CapabilityControl/ProductsCapabilities.cs` +
`ProductsCapabilityProvider.cs`; storage in
`dw10source/Dynamicweb.CoreUI/CapabilityControl/CapabilityRepository.cs` (verified DW 10.25.8).

Capability Control is the **modern UI-permission layer**, introduced in DW10.21+ to fix the
cascading-inheritance problem the legacy model had with hiding UI elements without affecting feature
access. Each capability key is a slash-delimited path like `/Products/Channels`.

### Storage — separate `CapabilityLimitation` table (NOT `UnifiedPermission`)

```sql
TABLE CapabilityLimitation (
  CapabilityLimitationId          bigint IDENTITY,
  CapabilityLimitationKey         nvarchar,   -- the capability key (starts with '/')
  CapabilityLimitationUserGroupId int         -- user group id (NOT user id)
)
```

Semantics are **inverted from Layer A's "permit" model**: presence of a row = users in this group are
*limited out of* (hidden from) this capability. Absence = no limit = capability visible (subject to
Layer C entity check). The class is called `CapabilityLimitation`, not `CapabilityPermission` — read
it as a hide-list. `DefaultCapabilityService.IsCapabilityLimitedForUser()` returns true when a
matching row exists for any group the user belongs to.

Takes group IDs only — there is no per-user override. To hide a capability for one specific user, put
them in a dedicated group and limit the group.

### Capability key registry — by area

Each backend area has its own `*Capabilities.cs` file under `<Area>.UI/CapabilityControl/`:

| Area | Source file | Top key | Sub-keys |
|---|---|---|---|
| Insights | `Dynamicweb.Insights.UI/.../InsightsCapabilities.cs` | `/Insights` | `/Insights/Dashboard`, `/Insights/Analytics`, `/Insights/Monitoring` |
| Content | `Dynamicweb.Content.UI/.../ContentCapabilities.cs` | `/Content` | `/Content/Navigation`, `/Content/RecycleBin`, `/Content/Settings`, `/Content/Settings/Styles` |
| Assets | `Dynamicweb.Files.UI/.../FilesCapabilities.cs` | `/Assets` | `/Assets/Media`, `/Assets/System`, `/Assets/Design` |
| Users | `Dynamicweb.Users.UI/.../UsersCapabilities.cs` | `/Users` | `/Users/Dashboard`, `/Users/Groups`, `/Users/Queries` |
| Products | `Dynamicweb.Products.UI/.../ProductsCapabilities.cs` | `/Products` | `/Products/Dashboard`, `/Products/Channels`, `/Products/Queries` (+ `/SharedQueries`, `/MyFavorites`, `/MyQueries`), `/Products/DynamicWorkspaces`, `/Products/Feeds`, `/Products/Assortments`, `/Products/DataModels`, `/Products/AllProducts`, `/Products/Warehouses` |
| Commerce | `Dynamicweb.Ecommerce.UI/.../EcommerceCapabilities.cs` | `/Commerce` | `/Commerce/Dashboard`, `/Commerce/OrderManagement`, `/Commerce/Assortments`, `/Commerce/Promotions` |
| Email | `Dynamicweb.Marketing.UI/.../MarketingCapabilities.cs` | `/Email` | `/Email/Dashboard`, `/Email/EmailMarketing` (+ `/AllEmails`), `/Email/DynamicSegments` |
| Integration | `Dynamicweb.Integration.UI/.../IntegrationCapabilities.cs` | `/Integration` | `/Integration/Setup`, `/Integration/Connections` |
| Apps | `Dynamicweb.Apps.UI/.../AppsCapabilities.cs` | `/Apps` | `/Apps/Dashboard`, `/Apps/AppStore` |

**`/Settings` is NOT a capability key.** The Settings tab is gated by the `BuiltInAdmin` /
`SystemAdministrator` user-type check (§6), not by Capability Control. Non-admin users never see
Settings regardless of `CapabilityLimitation` rows.

**Capability keys have parent relationships.** Limit the parent and the children become invisible
regardless of child grants. E.g. add `/Products` to `CapabilityLimitation` for a group and the entire
left-nav section disappears for them — child grants on `/Products/Channels` don't override.

**Capability + entity = both must grant.** This is the orthogonal design (only meaningful with the §1
flag ON):

| User has capability? | User has entity perm? | Outcome |
|---|---|---|
| ✗ | ✗ | Section invisible. (Capability wins on visibility.) |
| ✗ | ✓ | Section invisible. Action would succeed via raw API but UI doesn't expose it. |
| ✓ | ✗ | Section visible; item rows visible (or not — entity ACL governs); action buttons disabled / errors. |
| ✓ | ✓ | Full access. |

If a user reports "capability control doesn't work in conjunction with other permissions": **that's
the design.** Capability *hides* sections; permission *authorises* actions. Trying to make capability
do entity-level gating fails — that's Layer C's job.

Action-level granularity comes from `PermissionLevelRequired` on each `ActionNode`. E.g. `Read` on
`/Products/DynamicWorkspaces` shows the section but hides the "+ Add workspace" button (which is wired
to `PermissionLevel.Create`).

## 4. Layer C — Entity-level permissions

Stored in `UnifiedPermission`; keys come from the entity itself via the `IPermissionEntity` interface.
The mapping (verified DW 10.25.8 against a local clone of the DW10 source):

| Entity | `PermissionName` constant | `PermissionKey` shape | Source citation |
|---|---|---|---|
| Area root (Section grant for the whole area) | `"Section"` | area name without leading slash (e.g. `"Products"`, `"Assets"`) | `PermissionSection.cs:12` |
| Shop | `"Shop"` (`nameof(Shop)`) | `ShopId` (e.g. `"SHOP1"`, `"SHOP2"`) | `Shop.cs:314` |
| Group (catalog, DataModelFolder, DataModel) | `"ProductGroup"` | `GroupId` | `Group.cs:278` |
| Product | `"Product"` | `ProductId` | `Product.cs:498` |
| **ProductField** (standard, custom, AND category fields) | `"ProductField"` | `SystemName` (e.g. `"ProductName"`, `"ProductNumber"`, `"dpp_passport_id"`) | `ProductField.cs:1520` |
| **File / Directory** (Assets tree, Media folders) | `"File"` | relative path (e.g. `"/Files"`, `"/Files/Images"`) | `FilePermissionEntity.cs:13` |
| DynamicStructure (workspace) | `"DynamicStructure"` | `Id` (Guid) | `DynamicStructure.cs:43` |
| Feed | `"Feed"` (via `PermissionNameValue`) | feed id | `Feed.cs:118` (const) / `Feed.cs:132` (property) |
| Assortment | `"Assortment"` (via `PermissionNameValue`) | assortment id | `Assortment.cs:180` (const) / `Assortment.cs:190` (property) |
| FieldDisplayGroup | `"FieldDisplayGroup"` | `FieldDisplayGroupId` | `FieldDisplayGroup.cs:78` |
| **Language** (gates per-field editability on ProductEditScreen) | `"Language"` | `LanguageId` (e.g. `"LANG1"`, `"LANG2"`) | `Language.cs:143` |

### Two entities that demand special attention under flag ON

**ProductField — per-field grants required for columns to render.** The `ProductListScreen` queries
each `ProductField` for permission when building columns. With Cap Control ON,
`ProductField.GetPermissionParents()` terminates (no `PermissionSection("Products")` fall-through) — so
a `Section/Products` grant does NOT cascade to fields. **Symptom of the gap**: list view renders the
rows (Type icon + Completeness bar appear from non-field sources) but Name / Number / Created / Updated
/ custom-field columns are blank. Fix: bulk-grant `('<gid>', '<SystemName>', 'ProductField', '', Read)`
rows for every standard field constant from `ProductField.FieldSystemName`, every
`ProductFieldSystemName` row in `EcomProductField`, and every distinct `FieldId` in
`EcomProductCategoryField`. Category fields use the **same `ProductField` PermissionName**, not a
separate entity — `ProductField.GetPermissionEntityByKey()` falls back to
`GetCategoryFieldBySystemName()` (line 1543).

**FilePermissionEntity — path-chain cascade.** The Assets tree (`MediaFilesNodeProvider`,
`SystemFilesNodeProvider`, `DesignFilesNodeProvider`) gates every folder/file via
`directory.GetPermission().HasPermission(Read)`. `FilePermissionEntity.GetPermissionParents()` yields a
parent with the path's last segment stripped, recursively. Under flag ON the chain terminates at the
root (no fall-through to `PermissionSection("Assets")`). **Symptom of the gap**: Assets tab is visible
but every subtree (Media, System, Design) is empty. Fix: one grant on the root suffices —
`('<gid>', '/Files', 'File', '', Read)`. The path-chain cascade walks every subfolder for free. For
tighter scoping, grant on `/Files/Images` only and Media-other-folders disappear.

Each entity declares its **permission parents** via `GetPermissionParents()`. The parent graph (when
flag is OFF) is:

```
Product ──→ Groups it belongs to ──→ parent Groups (recursive) ──→ Shop ──→ PermissionSection("Products")
                                                                              ▲
                                                                              │
                                                                    This top link only exists
                                                                    when CapabilityControlFeature
                                                                    is OFF. When ON: chain terminates
                                                                    at the Shop (or earlier entity) —
                                                                    no fall-through to Layer B.
```

Verified ancestor chain in `Group.cs:297-307`: a Group yields its parent Group (recursive) OR its
parent Shop, then `Shop.cs:310-311` either yields the area section (flag OFF) or terminates (flag ON).
`Product.cs:502-515` yields its Groups; if no Groups (orphan), yields the area section under the flag.

**The Product hierarchy is dynamic, not static.** A product with relations to three groups inherits
from all three's parent chains. Highest-level wins. A product moved to a new group inherits from the
new chain on next read.

## 4b. Dashboard pinning — separate `DashboardAccessUserRelation` table

Source: `dw10source/src/Core/Dynamicweb.Core/Dashboard/DashboardConfigurationRepository.cs:42`
(verified DW 10.25.8).

```sql
TABLE DashboardAccessUserRelation (
  DashboardRelationDashboardId  int,
  DashboardRelationUserId       int,   -- user id, NOT group id
  DashboardRelationDefault      bit    -- 1 = auto-landing dashboard for this user
)
```

Gates which dashboards a non-admin user sees in the area's dashboard tree. The repository's
`GetDashboardsConfigurations` does a LEFT JOIN with `WHERE DashboardRelationUserId IN (<userIds>)` —
dashboards with no matching relation row are excluded for that user. **Admins bypass via empty
`userIds` context.**

- Empty relation rows + non-admin user = no dashboards visible. The user lands on the area's default `DashboardOverview` and any `?Path=<guid>` URL silently falls back to it.
- One row per (dashboard, user) pair. There is no per-group equivalent; you insert one row per user you want to pin a dashboard for.
- `Default=1` makes that dashboard the user's auto-landing when they navigate to the area root.

## 4c. Admin-UI exposure gap — must script the tables directly

In DW 10.25.8, the admin UI does **NOT** expose per-resource Permissions or CapabilityLimitation
editing for:

- **Dynamic Workspaces** — the workspace edit page Actions menu only offers "Edit" and "Delete".
- **Dashboards** — the dashboard page Actions menu only offers "Edit dashboard" and "Add widget".
- **User group → Capability Sets** (`/Admin/UI/Users/CapabilitySetList?UserGroupId=<gid>`) — shows inherited rows in read mode; no Add path is wired.

Out-of-the-box, a non-admin user with `allowBackend=true` on their group sees **the backend chrome but
no PIM data**: empty Products tree, custom dashboards silently fall back to the default,
`ProductEdit?ProductId=<id>` renders an empty "New product" form. This is more restrictive than typical
PIM expectations and requires direct table seeding (Layer A `UnifiedPermission` + Layer B
`CapabilityLimitation` + 4b `DashboardAccessUserRelation`) to make a non-admin role functional. There
is no admin-UI route around this for the resources above; the Direct-SQL surface
([`data-access.md`](data-access.md)) is the path.

After any direct insert/update on these three tables, flush three caches via Management API before the
change is visible to logged-in users:

```powershell
foreach ($cn in @(
  'Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilityService',
  'Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilitySetService',
  'Dynamicweb.Security.Permissions.PermissionService')) {
  Invoke-RestMethod -SkipCertificateCheck `
    -Uri "https://localhost:<PORT>/admin/api/CacheInformationRefresh" `
    -Headers @{Authorization = "Bearer CLAUDE.xxx"; 'Content-Type' = 'application/json'} `
    -Method POST -Body (@{CacheTypeName = $cn} | ConvertTo-Json) | Out-Null
}
```

`DashboardAccessUserRelation` reads bypass the cache (queried per request) — no flush needed for
dashboard relation changes. New logins always see fresh state regardless. See
[`cache-invalidation.md`](cache-invalidation.md) — the "Direct SQL INSERT/UPDATE/DELETE on
`UnifiedPermission`", "…on `CapabilityLimitation`", "…on `CapabilitySetLimitation`", and "…on
`DashboardAccessUserRelation`" rows — for the full surface.

## 5. The unified picture

```
  Layer B: CapabilityLimitation        Layer A: UnifiedPermission        Side table
  (presence = HIDE)                    (presence = PERMIT)               (per-user pin)

  ┌─────────────────────────┐          ┌─────────────────────────┐        ┌─────────────────────────┐
  │ CapabilityLimitation    │          │  UnifiedPermission      │        │ DashboardAccessUserRel  │
  │                         │          │                         │        │                         │
  │ (groupId, capKey)       │          │ (userOrGroupId, key,    │        │ (dashId, userId,        │
  │                         │          │  name, subname, level)  │        │  default)               │
  │ Capability keys:        │          │                         │        │                         │
  │ /Products, /Assets, ... │          │ Entity keys via         │        │ Per-USER (no group     │
  │ (UI section hides)      │          │ IPermissionEntity:      │        │  equivalent). Default=1 │
  └─────────────────────────┘          │ Shop/ProductGroup/      │        │  = auto-landing.        │
                                       │ Product/ProductField/   │        └─────────────────────────┘
                                       │ FilePermissionEntity/   │
                                       │ DynamicStructure/Feed/  │
                                       │ Assortment/Section/...  │
                                       │ (Layer C — action perm) │
                                       └─────────────────────────┘
        ▼                                          ▼
  "Is this UI section limited                "Does this owner have
   for any group I'm in?"                     PermissionLevel.X on this entity?"
   (returns true → hide)                      (highest level wins across user's groups)

                       CapabilityControlFeature flag (§1)
                       decides whether Layer C entity grants
                       cascade up to PermissionSection(area) keys.
                       Flag OFF = legacy cascade (Section grant covers all entities).
                       Flag ON  = orthogonal (each entity needs its own grant;
                                  Layer B hides are checked independently).
```

Layer B is *what the user can see in the admin nav* (hide-list). Layer A is *what the user can
read/edit/create/delete in the data* (permit-list, written by Layer C). `AccessUserGroup` membership
(separate tables: `AccessUserGroup`, `AccessUserGroupRelation`) provides transitive grants across
users — a user inherits the highest grant from any group they belong to.

The §1 flag controls whether Layer A's entity grants cascade up to Layer B area keys. Flag OFF = legacy
cascade. Flag ON = orthogonal — both layers must permit, and each entity needs its own grant.

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

## 7. Grant mechanics — `PermissionLevel` bit values

`UnifiedPermission` grant rows have the shape `(PermissionUserId, PermissionKey, PermissionName,
PermissionSubName, PermissionLevel)`. The `PermissionLevel` values come from
`dw10source/src/Core/Dynamicweb.Core/Security/Permissions/PermissionLevel.cs`:

```
None=1, Read=4, Edit=20, Create=84, Delete=340, All=1364
```

Bit-flag, higher includes lower (`Edit` = `Read | 1<<4` = `4 | 16` = 20). Most action buttons in PIM
editing screens want `Edit`; the toolbar `Permissions` button on each entity wants `All`.

All recipes below assume direct SQL on the permission tables — the admin UI does not expose them for
the resources these recipes touch (§4c). After any insert/update, flush caches per the "Direct SQL
INSERT/UPDATE/DELETE on `UnifiedPermission`" / "…on `CapabilityLimitation`" / "…on
`CapabilitySetLimitation`" rows in [`cache-invalidation.md`](cache-invalidation.md);
`DashboardAccessUserRelation` reads bypass the cache (no flush needed). Never verify a recipe logged in
as Angel / BuiltInAdmin / Administrator — those user classes bypass every check (§6); always test as a
Default-type user in the target group.

## 8. Functional-view entity-type checklist (flag ON)

To make a non-admin's PIM actually *functional* under flag ON (not just visible), you need grants on
**all five entity types** the Products + Assets areas touch. Granting only the navigation entities
(Shop / ProductGroup) leaves visible-but-empty trees and blank-column product lists. The full set per
group:

| What renders | UnifiedPermission grant |
|---|---|
| Area tree (Products / Assets headers) | `('<gid>', 'Products', 'Section', '', Read)`, `('<gid>', 'Assets', 'Section', '', Read)` |
| Channel section shows shops | `SELECT '<gid>', ShopId, 'Shop', '', Read FROM EcomShops` |
| Channel tree expandable to groups | `SELECT '<gid>', GroupID, 'ProductGroup', '', Read FROM EcomGroups` |
| **Product list columns** (Name / Number / Created / Updated / Type / custom fields) | one row per `ProductField` SystemName: standards from `ProductField.FieldSystemName` constants + customs from `EcomProductField` + category fields from `EcomProductCategoryField.FieldId` (all under `PermissionName='ProductField'`) |
| **Assets tree shows folders** | single row `('<gid>', '/Files', 'File', '', Read)` — the FilePermissionEntity parent chain cascades to every subfolder/file |

Without the ProductField grants, the product list shows rows but most columns are blank. Without the
File grant, the Assets tree is empty even though the tab is visible. Both are easy-to-miss because the
tab + area-section grants alone make the chrome look correct. (Why the cascade stops at these entities
under flag ON: §4 "Two entities that demand special attention".)

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

Fix: bump the entity-grant level on the entities that gate the action. Under flag ON, the Product
entity inherits level from its parent ProductGroups (highest level wins across all parents). So bumping
ProductGroup grants to Edit cascades Edit to every product in those groups — no per-Product row needed.

```sql
UPDATE UnifiedPermission
SET    PermissionLevel = 20    -- Edit (Read | 1<<4 = 4 | 16)
WHERE  PermissionUserId IN ('<gid1>', '<gid2>')
  AND  PermissionName IN ('ProductGroup', 'ProductField', 'File')
  AND  PermissionLevel = 4;    -- only bump rows currently at Read

-- And the area-root section grant (so screen-layout-driven "Edit" tabs work)
UPDATE UnifiedPermission
SET    PermissionLevel = 20
WHERE  PermissionUserId IN ('<gid1>', '<gid2>')
  AND  PermissionName = 'Section'
  AND  PermissionKey = 'Products'
  AND  PermissionLevel = 4;
```

What to leave at Read deliberately: `Shop` entities (editing shop config is platform-admin territory)
and `Section/Assets` (Asset edits flow through the per-product image manager which uses the `File`
grant). Bump these only when a role explicitly needs to edit shop configuration or upload to the Assets
tab directly.

Flush `Dynamicweb.Security.Permissions.PermissionService` after the update (see
[`cache-invalidation.md`](cache-invalidation.md)) — without the flush, logged-in users still see
Read-level UI until re-auth.

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
fall-through), so no upstream grant cascades — you must insert the row explicitly.

```sql
INSERT INTO UnifiedPermission (PermissionUserId, PermissionKey, PermissionName, PermissionSubName, PermissionLevel)
SELECT '<gid>', LanguageID, 'Language', '', 20 FROM EcomLanguages;
```

For multi-language installs, repeat per `LanguageID`. The `PermissionKey` is the language id (e.g.
`"LANG1"`), not the ISO code.

## 11. Per-role field-level differentiation (the SQL technique)

The functional-view bump above ("all standard + custom + category fields to Edit") is the *unlock* — it
makes the screen functional but gives every role the same write surface. To produce **field-level role
security** (writable for some roles, readonly for others), differentiate per role by leaving some
fields at Read for roles that don't own them. The technique:

1. Apply the functional-view checklist to bump everything to `Edit` (level 20) for all groups.
2. Apply the dual-gate fix (Language Edit grants).
3. Per role, identify the fields that role does NOT own and DOWNGRADE those rows to `Read` (level 4).

The downgrade is a single `UPDATE` per role against a list of `ProductField` SystemNames the role
should not write. Illustrative example — a content-owning role keeps content/meta/image/custom-category
fields editable and has commerce/lifecycle/workflow/physical fields downgraded to Read:

```sql
DECLARE @readOnly TABLE (SystemName nvarchar(100));
INSERT INTO @readOnly (SystemName) VALUES
  ('ProductNumber'),('ProductPrice'),('ProductCost'),('ProductStock'),
  ('ProductActive'),('ProductWorkflowStateId'),('ProductDiscontinued'),
  ('ProductDefaultShopID'),('ProductManufacturerID'),('ProductType'),
  ('ProductEAN'),('ProductWeight'),('ProductHeight'),('ProductWidth'),
  ('ProductDepth'),('ProductVolume'),('ProductCreated'),('ProductUpdated');

UPDATE UnifiedPermission
SET    PermissionLevel = 4
WHERE  PermissionUserId = '<role_gid>'
  AND  PermissionName = 'ProductField'
  AND  PermissionKey IN (SELECT SystemName FROM @readOnly);
```

To downgrade all custom category fields for a role (e.g. a workflow-owning role that should not edit
content), target them in bulk:

```sql
UPDATE UnifiedPermission SET PermissionLevel = 4
WHERE PermissionUserId = '<role_gid>' AND PermissionName = 'ProductField'
  AND PermissionLevel = 20
  AND PermissionKey IN (SELECT DISTINCT FieldId FROM EcomProductCategoryField);
```

The result is two visually-different Edit screens for the same product — one role sees content / images
/ category fields as editable inputs and commerce / workflow as readonly with lock icons; another sees
the inverse. The role split becomes visible without any custom code, just data-side grants.

What to keep at `Edit` for every role: `ProductGroup`, `Section/Products`, `File` (`/Files`),
`Language` (per language used). What to keep at `Read` for every role: `Shop` entities,
`Section/Assets` (unless a role explicitly needs shop-config edits or direct Asset-tab uploads).

## 12. Hide a UI section per group (`CapabilityLimitation`)

Layer B semantics: presence of a row = hide; group IDs only; parent keys cascade (§3). The operational
steps:

- Insert one `CapabilityLimitation` row per (group, capability key) to hide — e.g. key `/Products/Feeds` for a group hides the Feeds section while `/Products/AllProducts` stays visible.
- Limiting a parent key (e.g. `/Products`) hides the entire left-nav section; child grants do not override.
- There is no per-user override — to hide a capability for one specific user, put them in a dedicated group and limit the group.
- Flush `Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilityService` afterwards (see [`cache-invalidation.md`](cache-invalidation.md) "Direct SQL INSERT/UPDATE/DELETE on `CapabilityLimitation`" row).

For per-user dashboard pinning via `DashboardAccessUserRelation`: insert one `Default=1` row per
(dashboard, user) pair to give a user an auto-landing dashboard, plus `Default=0` rows for any users
who should also see it. No cache flush needed — the table is queried per request (§4b).

## 13. Plaintext password storage — `EncryptPassword=False` escape hatch

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
`AccessUser.AccessUserPassword` column stores plaintext. **This unlocks the SQL escape hatch for
seeding logins** when no MCP / admin-UI / API path is available:

```sql
UPDATE AccessUser SET AccessUserPassword = 'Password123!'
WHERE AccessUserUserName IN ('user1', 'user2');
```

The MCP `create_users` tool has no password parameter (verified DW 10.25.8); the Management API
`UserSave` command likewise **cannot set a password** — a backend user created through the API has no
usable password until one is set in the admin UI (or via the SQL path below). The admin UI's Users →
user → password field works but is manual. For automated seeding the SQL update is the fast path.
Verify the setting before relying on it — production solutions often flip these to `True`, and any
plaintext seeded under `False` becomes a stale invalid hash after the flip. (DW10's
`AuthenticationManager.cs:184` auto-rehashes a plaintext seed on first successful login.)

## 15. Render-time half — page/paragraph permissions (the entity store)

This is the **render-time** half: how the storefront's `Page` / `Paragraph` permissions resolve at
request time. The load-bearing fact that prevents the entire "SQL-write to
`EcomParagraph.ParagraphPermission`, then template-shim because nothing gates" detour: DW10's `Page`
and `Paragraph` render-time permissions live in the permission **entity store**, not in the legacy
`Page.PagePermission` / `EcomParagraph.ParagraphPermission` columns. The legacy columns exist for
back-compat but the runtime renderer ignores them.

### Physical storage — `UnifiedPermission` rows keyed `PermissionName='Page'` (verified DW 10.26.x)

The entity store's physical rows land in the **same `UnifiedPermission` table** as the Layer-A
entity grants (§2), disambiguated by `PermissionName`:

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
(Assortments, DC groups — [`commerce-b2b.md`](commerce-b2b.md)).

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

1. On the subtree root, set role → level via the admin Permissions panel (children inherit;
   `Page.PermissionType = 0` keeps a page inheriting rather than carrying its own rows).
2. No template edits needed. Nav, redirect, and child-render all self-filter.

### How to hide a single paragraph from a persona

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
others keep it; children inherit the root. (When a CSR-type user **impersonates** a customer the
session becomes that customer, so the customer-only dashboards correctly reappear under impersonation.)

### Common misdiagnosis

If a `Page.PagePermission` / `EcomParagraph.ParagraphPermission` UPDATE didn't gate the entity from
frontend users, you wrote to the **wrong place** — the legacy column is admin-side only; the runtime
check reads the entity store (`UnifiedPermission`, `PermissionName='Page'`). Symptoms: paragraph
still renders for anon despite `ParagraphPermission='9'`; page still navigable despite
`PagePermission='<groupId>'`; admin Permissions panel shows the legacy value but the storefront
ignores it. Fix: revert the legacy-column write, add the equivalent entity-store grant through the
Permissions panel, remove any template shims added to compensate.

### Cache caveat when writing permission rows via SQL

The admin UI invalidates the permission model for you; a direct SQL INSERT does not (DW caches the
model in process). A SQL-only grant won't take effect — the nav still shows the pages, the gate still
lets the page render — until the cache drops: **refresh the security cache or restart the host**.
Verify only after the drop, or you'll misread a working gate as broken.

### Where the CC nav renders (theming map, not a gating surface)

If re-theming the customer-center nav (not gating it), note it renders through **three** templates by
viewport / entry point: `Navigation/Navigation.cshtml` (site-wide nav paragraphs);
`Paragraph/Swift-v2_MyAccount/UserAvatar.cshtml` (avatar dropdown / mobile drawer); and
`Swift-v2_CustomerCenter.cshtml` (desktop CC sidebar `<aside>`). A styling change applied to only one
looks fixed on desktop and broken in the mobile drawer (or vice versa). Test both widths. The
**permission gate covers all three** without per-template edits — prefer it over template `foreach`
filters on `PageNavigationTag` (which fail the discipline grep-pack).

### Write surface — the admin Permissions panel (no MCP tool, no Management API endpoint)

`assign_permissions_to_assortment` writes assortment permissions; there is no page/paragraph
equivalent in MCP, and the Management API catalog (`/admin/api/openapi.json`) exposes no
page-permission endpoint either (checked on 10.26.x). The working path: drive the admin UI
**Permissions** panel — `/Admin/UI/Content/PermissionList?Key=<pageId>&Name=Page` — headless
(browser automation), once per page, and verify each write with a read-only SELECT on
`UnifiedPermission`. Direct SQL INSERT stays the last resort; if used, flush the security cache or
restart before verifying (cache caveat above).

## 16. Customer-number suffix as a role flag (presentation gate)

For lightweight storefront visibility flags ("hide prices for browse-only", "installer mode"), the
lowest-overhead role gate bakes the role into the user's `AccessUserCustomerNumber` suffix (e.g.
`CUST-002-BROWSE`) and reads it off `Pageview.User?.CustomerNumber` in any paragraph that gates
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
user groups** ([`commerce-b2b.md`](commerce-b2b.md)) instead. The two compose: a buyer is both a member
of a DC group (group → unlocks Assortments + Shipping) and carries a `-BROWSE` customer-number suffix
(suffix → suppresses price display).

A presentation role can also combine the suffix with CSR/staff group membership read via
`Pageview.User.GetGroups()` ([`render-viewmodels.md`](render-viewmodels.md)) to drive avatar-ring /
badge presentation — that is presentation, not gating; use `GetGroups()` for it, never raw
`SELECT FROM AccessUserGroupRelation`.

## 17. Cross-references

- **Render-time half of permissions** — §15 above ("Render-time half — page/paragraph
  permissions"). Owns the render-time entity-store rows (`UnifiedPermission`,
  `PermissionName='Page'`) which gate `Page` / `Paragraph` render at request time.
- **Workflow transitions** — [`pim-workflow.md`](pim-workflow.md). DW10's workflow engine has NO native per-state role gating (verified gap). The workarounds (subscriber-reject; custom capability key; soft gating via permission-aware surfaces) all build on Layer C entity permissions from this ref.
- **Publish-to-channel native action** — [`commerce-catalog.md`](commerce-catalog.md). The action's `PermissionLevelRequired = PermissionLevel.Edit` is a Layer C check on the source products + a write-permission check on the target Channel groups.
- **Dynamic Workspaces entity** (`PermissionName="DynamicStructure"`) — [`pim-modelling.md`](pim-modelling.md). How the workspace entity slots into the three-layer model.
- **Access surfaces** (Direct-SQL / Management API) — [`data-access.md`](data-access.md). Per §4c, all three permission tables are Direct-SQL territory in DW 10.25.8 — the admin UI does not expose them for the Dynamic-Workspace / Dashboard / Capability-Set resources.
- **Cache invalidation after direct-SQL permission seeding** — [`cache-invalidation.md`](cache-invalidation.md), the "Direct SQL INSERT/UPDATE/DELETE on `UnifiedPermission` / `CapabilityLimitation` / `CapabilitySetLimitation` / `DashboardAccessUserRelation`" rows. The three caches that need flushing (`DefaultCapabilityService`, `DefaultCapabilitySetService`, `PermissionService`) are listed there with the exact `CacheInformationRefresh` payload.
- **`AccessUserGroup` membership** — DW10 admin Users → Groups. Group membership is what makes Layer A's "highest level wins" resolution work across users.

Source citations re-verified against a local clone of the DW10 source on DW 10.25.8.
