# Permission layers — capability control, entity grants, render-time gates

Field-validated DW10 permissions knowledge: the three storage tables, the `CapabilityControlFeature`
flag, entity-grant mechanics, per-role field-level differentiation, and the render-time
page/paragraph entity store.

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
- [14. `UserAddressDelete` resolves through the owning user — orphaned addresses are API-unreachable](#14-useraddressdelete-resolves-through-the-owning-user--orphaned-addresses-are-api-unreachable)
- [15. Render-time half — page/paragraph permissions (the entity store)](#15-render-time-half--pageparagraph-permissions-the-entity-store)
- [16. Customer-number suffix as a role flag (presentation gate)](#16-customer-number-suffix-as-a-role-flag-presentation-gate)
- [17. Frontend user management — the Swift 2.4 UserGroups app](#17-frontend-user-management--the-swift-24-usergroups-app)
- [18. Cross-references](#18-cross-references)

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
no PIM data**: empty Products tree, custom dashboards silently fall back to the default. This is more
restrictive than typical PIM expectations and requires direct table seeding (Layer A
`UnifiedPermission` + Layer B `CapabilityLimitation` + 4b `DashboardAccessUserRelation`) to make a
non-admin role functional. There is no admin-UI route around this for the resources above; direct SQL
([dw-data-access](../../dw-data-access/SKILL.md)) is the path.

**Rule out the query string before attributing an empty product editor to permission starvation.**
`ProductEdit` resolves its model from the `Type=` parameter, not from `Id=`. With no `Type`, the model
binder produces an empty `ProductDataModel` and the screen renders in **create** mode: breadcrumb
"New product", every field empty, a live green "Save and close", `Id=` simply ignored. That is
identical to what a starved permission set looks like, and it happens to a full administrator.

```
/Admin/UI/Products/ProductEdit?Id=PROD12384                          -> "New product", fields empty
/Admin/UI/Products/ProductEdit?Id=PROD12384&Type=ProductById&LanguageId=ENU
                                                                     -> the product, all layout tabs
```

Every product deep link needs
`?Id=<PRODID>&Type=ProductById&LanguageId=<LANG>&QueryContext=Dynamicweb.CoreUI.Data.DataQueryContext`,
and the assertion is that the breadcrumb is the product name, not "New product". The neighbouring
symptom on the same screens: `DynamicStructureLevelResultsList` and `QueryListScreen?Type=FavoriteQueries`
entered **cold** produce empty grids and "An unhandled error occurred", because they resolve their
navigation node path from tree state and a cold URL has no `DynamicStructureNavigationNodePath` and no
`screenTypeName`. The same screens reached by clicking the left nav work, and the URL the UI itself
builds carries a per-screen GUID segment plus a five-segment node path. Screenshot and assertion
harnesses for the Products area must click the left nav, not construct routes.

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
dashboard relation changes. New logins always see fresh state regardless.

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

**`allowBackend=false` is a no-op on an admin row: clear the `userType` instead, then read the column
back.** `UserSaveCommand` does assign `user.AllowBackend = model.AllowBackend`, but
`Dynamicweb.Security.UserManagement.User.AllowBackend` is computed:
`get { if (!allowBackend && !IsAdmin) return IsAngel; return true; }`. For `AccessUserType`
SystemAdministrator (1) or Administrator (3) the getter always returns true, so `AccessUserAllowBackend`
persists as `1` no matter what the model carried, with no validation error and no warning. Measured on
10.28.1: `POST /Admin/Api/UserSave {Model:{... allowBackend:false, active:false ...}}` answered ok and
`SELECT AccessUserActive, AccessUserAllowBackend FROM AccessUser WHERE AccessUserID=3081` returned
`False, True`; the identical call with `model.userType = "default"` added returned `False, False`. The
only levers that actually deny backend access are `userType` (demote to `Default=5`) and `Active=false`.
So a teardown or "deactivate and deny backend" cleanup must set `userType` in the same `UserSave` and
then assert `AccessUserAllowBackend = 0` from the column, since the API echo is not evidence. Assert
separately that other backend admins survive (`COUNT` of `AccessUserType IN (1,3) AND Active=1 AND
AllowBackend=1`) so the cleanup cannot lock everyone out.

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
the resources these recipes touch (§4c). After any insert/update, flush the three caches listed in §4c
(`DefaultCapabilityService`, `DefaultCapabilitySetService`, `PermissionService`);
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

Flush `Dynamicweb.Security.Permissions.PermissionService` after the update (via
`CacheInformationRefresh`, §4c) — without the flush, logged-in users still see Read-level UI until
re-auth.

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
- Flush `Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilityService` afterwards (via `CacheInformationRefresh`, §4c).

For per-user dashboard pinning via `DashboardAccessUserRelation`: insert one `Default=1` row per
(dashboard, user) pair to give a user an auto-landing dashboard, plus `Default=0` rows for any users
who should also see it. No cache flush needed — the table is queried per request (§4b).

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
then trying to sign in as them fails at the sign-in screen with no obvious cause. The canonical recovery
is the SQL escape hatch below (plaintext under `EncryptPassword=False`, which DW auto-rehashes on first
login). **Validate:** after setting the password, actually sign in as the persona (not as an admin) and
confirm you reach the account/customer-center landing.

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

## 14. `UserAddressDelete` resolves through the owning user — orphaned addresses are API-unreachable

**The Ecommerce health check flags orphaned `AccessUserAddress` rows, and the only address-delete verb answers
`404` for exactly those rows.** `UserAddressDelete` takes a scalar `AddressId` but looks the address up
**through its owning user**; an orphan carries `AccessUserAddressUserId = 0`, so there is no user to resolve
through and the lookup fails:

```
POST UserAddressDelete {AddressId: <orphanId>}  -> 404 {"status":"notFound","message":"Address not found: <orphanId>"}
```

So the API cannot fix what the health check reports. **Raw SQL `DELETE` is the only route and is sanctioned
here** — no runtime cache is keyed on `AccessUserAddress`, so the delete needs no flush and no restart. Scope
it precisely (`AccessUserAddressUserId = 0` **plus** blank address fields): orphans interleave with real
address ids, so an id-range delete takes live personas' addresses with it.

Two generalisations worth carrying:

- **Health-provider orphan rows are usually API-unreachable by construction** — the verbs resolve through the
  parent entity that the orphan, by definition, has lost. Expect a sanctioned SQL exception rather than
  hunting for a verb that does not exist.
- **Check the provenance before deciding it is fallout.** All 19 rows on one install were completely blank with
  `UserId 0` — residue of address-save probes that ran with no user id, not deleted-user fallout. Verify
  afterwards that the health provider's orphaned-address check returns 0 **and** that live personas still have
  their addresses.

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

**Engine floor is load-bearing.** An engine **≤ 0.7.1-beta silently drops** the row/paragraph `permissions:` blocks on deserialize (`IgnoreUnmatchedProperties`) → the tiles render **ungated** (a security regression). A base that carries these blocks declares `minSerializerVersion` in its contract; consume it only on ≥ 0.8.0-beta.

**Ordering trap (handled in-engine, ≥ 0.8.0-beta).** AccessUser groups deserialize AFTER the content that references them; the engine defers unresolvable-group permission sets to an end-of-run re-apply pass (with a user-group cache refresh) so group grants land instead of collapsing to the `Anonymous=None` safety fallback. Verify with a permissions-parity check: every serialized `permissions:` block ⇔ matching `UnifiedPermission` rows (count + owner + level + SubName).

**The live post-deserialize seed below (admin Permissions panel / SQL INSERT + cache flush) is now a LEGACY FALLBACK** — use it only for older bases/engines that cannot carry the blocks, or for ad-hoc gating outside a layer. For a base ≥ 2.4.0 the correct action after deserialize is to **verify** the YAML-carried gating applied (parity check), not to re-seed it.

### Physical storage — `UnifiedPermission` rows keyed `PermissionName='Page'`/`'GridRow'`/`'Paragraph'` (verified DW 10.26.x)

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

1. On the subtree root, set role → level via the admin Permissions panel (children inherit;
   `Page.PermissionType = 0` keeps a page inheriting rather than carrying its own rows).
2. No template edits needed. Nav, redirect, and child-render all self-filter.

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

### Where the customer-center nav renders (theming map, not a gating surface)

If re-theming the customer-center nav (not gating it), note it renders through **three** templates by
viewport / entry point: `Navigation/Navigation.cshtml` (site-wide nav paragraphs);
`Paragraph/Swift-v2_MyAccount/UserAvatar.cshtml` (avatar dropdown / mobile drawer); and
`Swift-v2_CustomerCenter.cshtml` (desktop CC sidebar `<aside>`). A styling change applied to only one
looks fixed on desktop and broken in the mobile drawer (or vice versa). Test both widths. The
**permission gate covers all three** without per-template edits — prefer it over template `foreach`
filters on `PageNavigationTag`.

### Write surface — `PermissionSave` on the Management API (DW 10.28.x)

**`POST /Admin/Api/PermissionSave` is the write verb, and it is proven on 10.28.x for page, grid-row,
paragraph and user-entity grants.** The shape is
`{Key:<entityId>, Name:"<PermissionName>", SubName:"<subName or empty>", OwnerId:<userOrGroupId>,
Level:"<read|edit|create|delete|all|none>"}`. It is the surface a language-layer permission mirror drives
row by row, and the surface the frontend user-management grant below depends on. `assign_permissions_to_assortment`
writes assortment permissions; there is still no page/paragraph equivalent in MCP. Verify every write with a
read-only `SELECT` on `UnifiedPermission`, and flush the security cache or restart before believing a read
(cache caveat above). Direct SQL INSERT stays the last resort (local install only). The admin **Permissions** panel
(`/Admin/UI/Content/PermissionList?Key=<pageId>&Name=Page`) is a verification surface, not the authoring
path.

**The READ side has a trap that inverts its answer: `PermissionsByIdentifier` returns an EMPTY `data`
array when `SubName` is passed as `""`.** An empty-string sub-name is not treated as "no sub-name" — it
filters to nothing. Auditing page permissions before a change is exactly when this fires, and the empty
result reads as "no permissions configured, safe to add mine" while the rows sat there the whole time:

```
GET /Admin/Api/PermissionsByIdentifier?Key=8460&Name=Page&SubName=   -> {"data":[]}
GET /Admin/Api/PermissionsByIdentifier?Key=8460&Name=Page            -> {"totalCount":7, …}
SQL SELECT PermissionUserId, PermissionLevel FROM UnifiedPermission
      WHERE PermissionName='Page' AND PermissionKey='8460'
  -> 1270|1   1292|1364   1325|1   Anonymous|1
```

**Omit `SubName` entirely when reading.** The write side still takes `SubName:""` normally. Cross-check
the API read against the `UnifiedPermission` SELECT before treating any empty result as "no permissions
set" (and mind the nvarchar `PermissionUserId` join trap when writing that SELECT: a bare
`int = PermissionUserId` comparison aborts the whole statement on the literal `'Anonymous'`, so use
`TRY_CAST`).

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
user groups** ([`dc-scoping.md`](../../dw-commerce-b2b/references/dc-scoping.md)) instead. The two
compose: a buyer is both a member of a DC group (group → unlocks Assortments + Shipping) and carries a
`-BROWSE` customer-number suffix (suffix → suppresses price display).

A presentation role can also combine the suffix with CSR/staff group membership read via
`Pageview.User.GetGroups()` ([dw-render-viewmodels](../../dw-render-viewmodels/SKILL.md)) to drive
avatar-ring / badge presentation — that is presentation, not gating; use `GetGroups()` for it, never
raw `SELECT FROM AccessUserGroupRelation`.

## 17. Frontend user management — the Swift 2.4 UserGroups app

The storefront "Manage users" surface is the `UserGroups` content module
(`Dynamicweb.Users.UI.ContentModules.UserGroupContentModuleAddIn`). Everything below is measured on
DW 10.28.1-PreRelease with Swift 2.4.

### Every management command is gated by the ACTING user's permission on their OWN User entity

**Out of the box every `UserGroupCmd` is refused, the buttons still render, and the demo silently does
nothing.** `?UserGroupCmd=inviteuser` falls back to the account list; `ChangeActiveStatus` /
`ResendInvitation` / `DeleteUser` return **HTTP 200** with the group list plus the toast "You do not have
permission to edit this account". No data changes and nothing is logged.

`UserGroupFrontend.GetModuleContent` computes `GetRequiredPermission(cmd)` — `Read` for the plain list,
`Edit` for `ChangeActiveStatus` / `EditGroup` / `SaveGroup`, `Create` for `InviteUser` /
`ResendInvitation`, `Delete` for `DeleteUser` — and evaluates it as `user.HasPermission(required)` where
`user` is `UserContext.Current.User` **as a permission entity** (`[PermissionEntity("User")]`). It is the
acting user's permission over their **own** `User` row, not over the target user and not over the account.
Resolution order is explicit (`User/<uid>`), then inherited parents — `User.GetPermissionParents()` yields
`PermissionSubset("User", group)`, i.e. `Name=UserGroup`, `Key=<groupId>`, `SubName=User` — then owner
defaults. The only match a storefront user has out of the box is the `AuthenticatedFrontend` role at level
`read`, which satisfies `Read` and refuses `Edit` / `Create` / `Delete`.

**Neither the "Enable user account functionality" feature flag, nor group membership, nor
`AccessUserAdministratorInGroups` has any effect.** The grant is the fix:

```
POST /Admin/Api/PermissionSave
  {Name:"UserGroup", Key:<accountGroupId>, SubName:"User", OwnerId:<adminGroupId>, Level:"delete"}
```

Before the grant, `PermissionsByIdentifier?Key=<accountGroupId>&Name=UserGroup&SubName=User` shows only
inherited owners (`Anonymous=read`, `AuthenticatedFrontend=read`, `Administrator=all`) and an invite loop
runs 3 passed / 5 failed. After it the identical requests pass 13/13 and the badge actually flips. **A
gate leg on this surface must POST one `UserGroupCmd` and assert the STATE CHANGED**, because the refusal
is a 200 with the full action set rendered.

### The module's real property set, and what is not on it

Decompiling `UserGroupContentModuleAddIn` gives exactly 20 `AddInParameter` properties: `ListGroupType`,
`AccountListScope`, `PageSize`, `SortOrder`, `SortBy`, `GroupListTemplate`, `UserListTemplate`,
`EditGroupTemplate`, `CreateUserTemplate`, `UserGroups`, `UserSelectableGroups`, `EmailTemplate`,
`SenderName`, `SenderEmail`, `EmailSubject`, `RedirectAfterSubmission`, `RedirectAfterApproval`,
`RedirectAfterImpersonation`, `LoginPageId`, `CreatePasswordPageId`.

- **There is no `ShowInactiveUsers`** — it is a `UserView` property. It is also not needed: the user list
  is built from `UserManagementServices.Users.GetUsersByGroupId(groupId)` with no active filter, so
  inactive users are ALWAYS listed.
- **There is no account pre-select.** `UserGroupSettings.SelectedGroupId` exists on the settings class but
  carries no `AddInParameter`; `UserGroupFrontend` populates it from the `?UserGroupId=` querystring only.
  So a single-account admin always lands on an account DIRECTORY and must click their own account first.
  The fix is a thin `GroupListTemplate` wrapper that `Response.Redirect`s to `?UserGroupId=<id>` when the
  scope yields exactly one group and no `UserGroupId` was requested, falling back to the stock list
  otherwise.
- **`UserGroups` and `UserSelectableGroups` are NOT an account whitelist.** Their `AddInLabel`s are "Groups
  for new users" and "Groups the new user can be added to" — both are invite-time settings and neither
  filters the directory. `UserGroupFrontend.RenderUserGroupList` calls
  `GetFilteredGroups(SelectedGroupTypeSystemName, filterText, AccountListScope)`: the listed set is
  filtered by group TYPE and by ACCOUNT SCOPE only, and **there is no id whitelist anywhere**.

### Scope an account directory with `AccountListScope`, which matches on CUSTOMER NUMBER

`AccountListScope` is `AllAccounts | OwnAccounts | OwnAndImpersonatableAccounts`.
`ApplyAccountScopeFilter` builds a set of **customer numbers** from every valid user sharing the acting
user's username (all their profiles) plus, under `OwnAndImpersonatableAccounts`, every impersonatable
user, then keeps the groups reachable through `GetGroupsByCustomerNumber`. On one host that took a CSR
directory from 1,581 listed groups to exactly the three real accounts, and the system groups dropped out
for free because they carry no customer number.

**Prerequisites, and they are the whole trick:** the account groups must carry
`AccessUserCustomerNumber`, and the acting user's profiles must carry the matching numbers.
`OwnAndImpersonatableAccounts` additionally needs the Secondary-users index to be current. `OwnAccounts`
narrows the directory but still renders it as a directory.

### `UserChangeType` does NOT change the user-and-group type

Two different concepts share the word "type", and the verb named after it targets the other one.

- `Dynamicweb.Security.UserManagement.UserType` (in `Dynamicweb.Core`) is the **admin-rights** enum
  `{SystemAdministrator=1, Administrator=3, Default=5}` backing `AccessUserType`. That is what
  `UserChangeType` writes. Its OpenAPI schema shows `{UserId:int, UserType:<no type>}` with no value
  domain, and every user-and-group type name answers **HTTP 500** "The JSON value could not be converted
  to `Dynamicweb.Security.UserManagement.UserType`".
- The **user-and-group type** (`Login` / `Profile` / `Dealership` / `Role` / `Account`, declared in
  `Files/System/UserTypes/*.xml`) is a separate string column, `AccessUserUserAndGroupType`.

**The only write path for the user-and-group type is `UserSaveCommand`**, which does
`user.UserAndGroupTypeSystemName = model.UserAndGroupTypeSystemName`. So: `GET UserById` → set
`userAndGroupTypeSystemName` → `POST UserSave {Model}`. Measured on a `Profile` to `Login` conversion, the
full `AccessUser` row diff was exactly two columns (the type and `AccessUserUpdatedOn`), the
`AccessUserId` was unchanged, and the orders, addresses and favourite lists hanging off it stayed
attached.

`UserSaveCommand.ValidateModel` rejects `IsLogin=true` only when **another** row with the same username
already has `IsLogin=true`, so a standalone row converts fine and a member of a multi-profile set does not
(the escape hatch for editing a member of an existing multi-profile set is to SQL-park the other rows
of the set on throwaway usernames, `UserSave` the target row, then restore the set).

### Every `UserSave` mints a blank `AccessUserAddress` carrier row

`UserSaveCommand` unconditionally calls `HandleDynamicFields(user.AddressCustomFieldValues, m =>
m.DefaultAddressCustomFields)`. `GET UserById` always returns a `defaultAddressCustomFields` block (with
`groups[0].fields = []` when no address custom fields are defined), and persisting it materialises an
`AccessUserAddress` row with every column blank, `AccessUserAddressIsDefault=0` and
`AccessUserAddressDefaultAddressCustomFields=1`. **There is no way to suppress it from the payload —
omitting the property still produces the row.** Measured: one round-trip `UserSave` per user changing ONE
field took the address counts 3 to 4, 3 to 4, 3 to 4 and 0 to 1.

The frontend impact is nil (the carrier does not render, and a user whose only address row is a carrier
still gets the empty state), so this is invisible residue that grows per call. **Make scripted user
backfills one-shot, and exclude `AccessUserAddressDefaultAddressCustomFields = 1` from any address-count
assertion.**

### Deleting a user versus deleting a group — two verbs, and each is a silent no-op on the other's target

A DW10 user GROUP is an `AccessUser` row (`AccessUserType` 2 or 3), not a separate entity, which is what
makes the two verbs look interchangeable. They are not, and each answers `{"status":"ok"}` when pointed at
the wrong one.

- **`GroupDelete {Ids:["<id>"]}` deletes a group in every shape** measured at 10.28.1: a parented child, a
  top-level group, a parent (which cascades to its child group) and a group carrying members. Member
  `AccessUser` **user** rows survive the group's deletion. The `GroupId` parameter is irrelevant to the
  outcome. It is the batch verb, and the only path that keeps the user cache and tree indexes consistent —
  never raw SQL, which leaves the cache and the secondary-user index stale with no flush verb.
- **`UserDelete` on a GROUP id answers `{"status":"ok"}` and deletes NOTHING.** `UserDelete` on a real
  user row works. This inverse is the trap: a cleanup step that reaches for `UserDelete` on a group
  reports success while the group is still there.
- **`UserDelete` wants `Ids` as an array of STRINGS.** `{"Id":1332}` answers **400** `{"status":"invalid",
  "message":"No items selected"}` — a 4xx that a wrapper checking only "did the call return" happily
  swallows, which is how a backend `systemAdministrator` account survived a throwaway-admin cleanup on a
  demo about to be handed to a prospect. `{"Ids":[1332]}` answers **500** "The JSON value could not be
  converted to System.String". `{"Ids":["1332"]}` works.

```
POST UserDelete {"Id":1332}       -> 400 "No items selected"   alive
POST UserDelete {"Ids":[1332]}    -> 500 JSON conversion        alive
POST UserDelete {"Ids":["1332"]}  -> 200 {"status":"ok"}        gone
```

**Assert the row count, never the HTTP status.** Measure the `AccessUser` delta immediately after every
batch (`SELECT COUNT(*) FROM AccessUser WHERE AccessUserUserName='<probe>'` must be 0), and have the
helper return `deleted: (countAfter === 0)` rather than `deleted: true`. A clone-hygiene check belongs in
every build that inherits a host: count `AccessUserType=2` rows and assert every group is reachable from a
reference, not merely present in the tree. On one inherited host 1,576 of 1,602 groups had a reference
count of exactly zero, invisible to every storefront probe and every gate assert, and `GroupDelete` in
batches of 25 removed them with zero collateral (`AccessUserGroupRelation`, `UnifiedPermission`,
`AccessUserSecondaryRelation`, `AccessUserAddress` and `EcomOrders` deltas all 0).

A DW 10.28.4 capture recorded `GroupDelete` behaving as a detach-from-parent no-op on that build. Treat
that as a version fork and measure the delta on the host in front of you before scripting a batch.

### There is no shape for a single-account person, so pick the deviation deliberately

The type model assumes every account member is a `Login` row in a `Logins` group PLUS one `Profile` row
per account in the account group, with orders and addresses hanging off the Profile. That is right for a
multi-account person (a vendor CSR, a buying group) and wrong for the common B2B case of one person, one
account, one identity:

- `Files/System/UserTypes/Login.xml` declares `<AllowedParents><Parent>Logins</Parent></AllowedParents>`,
  so a Login may not sit in an account (`Dealership`) group.
- The Swift account Users page lists `AccessUserGroupRelation` members **of the account group**, so anyone
  who must appear there has to be a direct member of it.
- `Profile.xml` allows `Dealership` and `Role` parents, so a Profile lists — but can never be a login
  identity in its own right and can never gain sibling profiles.

**`AllowedParents` is advisory: it is honoured by the admin UI tree and is NOT enforced by `UserSave`.**
Recommended default for a person who belongs to exactly one account: **a `Login` row in All Logins that is
ALSO a direct member of the account group**, accepting the `AllowedParents` deviation, because it is the
only shape that authenticates, lists on the account Users page, and can later gain sibling profiles.
Measured end to end on four personas: logins authenticate, the account Users page lists them, the
account admin impersonates each of them, and order and quote lists are byte-identical before and after
the conversion. Building the person as a `Profile` with `AccessUserIsLogin=1` authenticates but is
structurally dead. (Modelling an account group as a DC group for pricing and shipping is a separate
concern owned by `dw-commerce-b2b`.)

## 18. Cross-references

- **Render-time half of permissions** — §15 above ("Render-time half — page/paragraph
  permissions"). Owns the render-time entity-store rows (`UnifiedPermission`,
  `PermissionName='Page'`) which gate `Page` / `Paragraph` render at request time.
- **Workflow transitions** — [`workflow-engine.md`](../../dw-pim-workflow/references/workflow-engine.md). DW10's workflow engine has NO native per-state role gating (verified gap). The workarounds (subscriber-reject; custom capability key; soft gating via permission-aware surfaces) all build on Layer C entity permissions from this ref.
- **Publish-to-channel native action** — [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md). The action's `PermissionLevelRequired = PermissionLevel.Edit` is a Layer C check on the source products + a write-permission check on the target Channel groups.
- **Dynamic Workspaces entity** (`PermissionName="DynamicStructure"`) — [`structural-model.md`](../../dw-pim-modelling/references/structural-model.md). How the workspace entity slots into the three-layer model.
- **Access surfaces** (Direct-SQL / Management API) — [dw-data-access](../../dw-data-access/SKILL.md). Per §4c, all three permission tables are Direct-SQL territory in DW 10.25.8 — the admin UI does not expose them for the Dynamic-Workspace / Dashboard / Capability-Set resources.
- **Cache invalidation after direct-SQL permission seeding** — the three caches that need flushing
  (`DefaultCapabilityService`, `DefaultCapabilitySetService`, `PermissionService`) are listed in §4c
  with the exact `CacheInformationRefresh` payload; `DashboardAccessUserRelation` reads bypass the
  cache.
- **Never rename or edit an `AccessUser` row by raw SQL.** The in-process user cache is reachable by
  **no** invalidation verb, so `SELECT` and `UserById` disagree indefinitely and the failure surfaces
  three endpoints away as a `403` on profile switch. Every such write owes a per-row DB-vs-API diff,
  and any repair that re-saves through `UserById` must supply the DB values explicitly or it writes
  the stale value back.
- **`AccessUserGroup` membership** — DW10 admin Users → Groups. Group membership is what makes Layer A's "highest level wins" resolution work across users.

Source citations re-verified against a local clone of the DW10 source on DW 10.25.8.
