# Permission layers — the storage model behind every DW10 grant

Field-validated DW10 permissions knowledge: the three storage tables, the
`CapabilityControlFeature` flag, the entity registry, and the backend `Section` entity with its
three implicit user roles.

## Contents

- [1. The `CapabilityControlFeature` flag — DW10.21+, default OFF](#1-the-capabilitycontrolfeature-flag--dw1021-default-off)
- [2. Layer A — `UnifiedPermission` (the storage layer)](#2-layer-a--unifiedpermission-the-storage-layer)
- [3. Layer B — Capability Control (UI-section visibility)](#3-layer-b--capability-control-ui-section-visibility)
- [4. Layer C — Entity-level permissions](#4-layer-c--entity-level-permissions)
- [4b. Dashboard pinning — separate `DashboardAccessUserRelation` table](#4b-dashboard-pinning--separate-dashboardaccessuserrelation-table)
- [4c. Admin-UI exposure gap — must script the tables directly](#4c-admin-ui-exposure-gap--must-script-the-tables-directly)
- [4d. Backend areas are the `Section` entity, and its level cascades](#4d-backend-areas-are-the-section-entity-and-its-level-cascades)
- [5. The unified picture](#5-the-unified-picture)
- [Cross-references](#cross-references)

This reference is the **modelling-time** half of DW10 permissions. Three siblings carry the rest,
and they continue this file's section numbering, so a §-number is unique across all four:

| Sections | File | Owns |
|---|---|---|
| §1-§5 | this file | The storage tables, the feature flag, the entity registry, the backend `Section` entity |
| §6-§14 | [`grant-mechanics.md`](grant-mechanics.md) | Admin bypass, `PermissionLevel` values, the `PermissionSave` write surface, and the recipes that build a non-admin backend role |
| §15-§16 | [`page-gating.md`](page-gating.md) | Render-time page/paragraph gating on the storefront, and the customer-number-suffix presentation flag |
| §17 | [`user-group-operations.md`](user-group-operations.md) | Writing users, groups and impersonation grants, and the Swift UserGroups storefront app |

Three SQL tables carry the model — `UnifiedPermission` for entity grants, `CapabilityLimitation`
for UI hides, `DashboardAccessUserRelation` for per-user dashboard pinning — with two semantic
conventions (permit vs limit, opposite directions) and one feature flag (`CapabilityControlFeature`,
DW10.21+) that decides whether the layers cascade or stand orthogonal. The flag's default and its
cascade behavior are the load-bearing facts that prevent the "I granted Edit on the Products area
but the user still can't see anything" detours.

The **render-time** half of permissions — how the storefront's `Page`/`Paragraph` permissions
resolve at request time — lives in [`page-gating.md`](page-gating.md) §15. That section owns the
render-time rows — physically `UnifiedPermission` rows keyed `PermissionName='Page'` on 10.26.x —
read on every page/paragraph render. This ref owns modelling-time concerns (entity hierarchy,
capability tree, flag decision); [`grant-mechanics.md`](grant-mechanics.md) owns the write surface
and the levels. Roughly: this file's layers describe who can EDIT a product in admin; §15 describes
who can SEE a CMS page on the storefront. Both live in `UnifiedPermission`, but the
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

## 4d. Backend areas are the `Section` entity, and its level cascades

Backend authorisation runs on the same `UnifiedPermission` store as the storefront. The entity is
`Section` and its `PermissionKey` is the admin area name (§4's first table row). Measured on
10.28.x.

**Three implicit user ROLES sit under every permission entity.** `GET
/Admin/Api/PermissionsByIdentifier?Name=Section&Key=<Area>` returns them on any key, with
`isUserRolePermission: true` and `isExplicitPermission: false`:

| Implicit role | Default level on every entity |
|---|---|
| `Anonymous` | `read` |
| `AuthenticatedFrontend` | `read` |
| `Administrator` | `all` |

A backend user who is not an Administrator (`UserType` `Default = 5`) resolves as
`AuthenticatedFrontend`, which grants nothing on any admin `Section`. So **a new backend user with
`AllowBackend` set and no `Section` grant signs in successfully and gets an admin shell with no
area navigation at all** — one collapse toggle and a licence link, and direct navigation to
`/Admin/UI/<Area>` serves the same bare shell. That is the model working: every restriction here
is the ABSENCE of a grant, and the model has no deny row. Grant one `Section` row per area the
role needs, on the role's user group.

**The level on the `Section` row is the level the screens beneath it operate at.** Isolated on one
`Section:Content` row with the level as the only variable: at `Read` (4) the area label, the page
tree and the page-edit screen all render and the `PageSave` command and its Save button are simply
not emitted; at `Edit` (20) both are present. So grant the level the role must *operate* at, and
read a `Section` grant as "what this role can do everywhere under that area" — a `Read` grant is a
browsable, unsaveable area, with nothing on screen to say why. (Capability Control in §3 is the
separate mechanism that hides UI sections without changing what an action may do; the two are
often confused because both are described as "area permissions".)

Grant shape, on the user group that carries the role:

```
POST /Admin/Api/PermissionSave
{"Model":{"Key":"Content","Name":"Section","SubName":"","OwnerId":"<groupId>","Level":20,
          "IsUserRolePermission":false,"IsExplicitPermission":true}}
```

**The area keys are the `AreaBase` subclass names in the shipped assemblies** — `SettingsArea`,
`AppsArea`, `ContentArea`, `EcommerceArea`, `FilesArea`, `InsightsArea`, `IntegrationArea`,
`MarketingArea`, `ProductsArea`, `UsersArea` — keyed without the `Area` suffix (`Content`,
`Ecommerce`, `Products`, `Users`, `Settings`, …). They cannot be enumerated through the API:
`PermissionsByIdentifier` answers with the same three implicit rows for any string, valid or not,
so a typo is indistinguishable from a correct key. **Prove a key by signing in as a member of the
granted group and checking the area renders**, never by reading the permission query back.

Backend access itself is a separate bit, `AccessUser.AccessUserAllowBackend`, and it can be set on
a GROUP row (`AccessUserType = 2`) and inherited — MCP `save_user_groups` exposes it as
`allowBackend`. A user needs both: the bit to reach the shell, and a `Section` grant to see
anything in it.

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

## Cross-references

- **Grant levels and the `PermissionSave` write surface** —
  [`grant-mechanics.md`](grant-mechanics.md) §7.
- **Render-time half of permissions** — [`page-gating.md`](page-gating.md) §15. Owns the
  render-time entity-store rows (`UnifiedPermission`, `PermissionName='Page'`) which gate `Page` /
  `Paragraph` render at request time.
- **Writing users, groups and impersonation grants** —
  [`user-group-operations.md`](user-group-operations.md) §17.
- **Workflow transitions** — [`workflow-engine.md`](../../dw-pim-workflow/references/workflow-engine.md). DW10's workflow engine has NO native per-state role gating (verified gap). The workarounds (subscriber-reject; custom capability key; soft gating via permission-aware surfaces) all build on Layer C entity permissions from this ref.
- **Publish-to-channel native action** — [`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md). The action's `PermissionLevelRequired = PermissionLevel.Edit` is a Layer C check on the source products + a write-permission check on the target Channel groups.
- **Dynamic Workspaces entity** (`PermissionName="DynamicStructure"`) — [`structural-model.md`](../../dw-pim-modelling/references/structural-model.md). How the workspace entity slots into the three-layer model.
- **Access surfaces** (Direct-SQL / Management API) — [dw-data-access](../../dw-data-access/SKILL.md). Per §4c, all three permission tables are Direct-SQL territory in DW 10.25.8 — the admin UI does not expose them for the Dynamic-Workspace / Dashboard / Capability-Set resources.
- **Cache invalidation after direct-SQL permission seeding** — the three caches that need flushing
  (`DefaultCapabilityService`, `DefaultCapabilitySetService`, `PermissionService`) are listed in §4c
  with the exact `CacheInformationRefresh` payload; `DashboardAccessUserRelation` reads bypass the
  cache.
- **`AccessUserGroup` membership** — DW10 admin Users → Groups. Group membership is what makes Layer A's "highest level wins" resolution work across users.

Source citations re-verified against a local clone of the DW10 source on DW 10.25.8.
