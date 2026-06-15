# permissions-model.md

> Three-layer permission model for Dynamicweb 10 — three SQL tables (`UnifiedPermission` for entity grants, `CapabilityLimitation` for UI hides, `DashboardAccessUserRelation` for per-user dashboard pinning), two semantic conventions (permit vs limit — opposite directions), one feature flag (`CapabilityControlFeature`, DW10.21+) that decides whether the layers cascade or stand orthogonal. Read this BEFORE designing any role matrix; the flag's default and its cascade behavior are the load-bearing facts that prevent a half-day of "I granted Edit on the Products area but the user still can't see anything" detours. Loaded from `~/.claude/skills/truvio-pim-demo/SKILL.md` "Where to find things" table. Cross-cuts with the **render-time** half of permissions — see [`truvio-swift-demo/references/dw10-canonical-surfaces.md`](../../truvio-swift-demo/references/dw10-canonical-surfaces.md) §"Permissions — the entity store" for how the storefront's `Page`/`Paragraph` permissions resolve at request time. This ref owns **modelling-time** concerns (entity hierarchy, capability tree, flag decision); the Swift ref owns **render-time** lookup (the `Permission` table read on every paragraph render). **Concept lives here; seeding grants for demo personas → [permissions-recipes.md](permissions-recipes.md).**
>
> **Cross-cutting placement note.** This ref sits at PIM-skill level. Permissions touch PIM, Swift frontend, ERP integration, and Business Central potentially — all of them. If cross-cutting use materialises across more than two sibling skills, consider promoting to a future `truvio-platform-demo` sibling alongside `truvio-demo-base`. Until then, this is the home and Swift's `dw10-canonical-surfaces.md` §"Permissions — the entity store" cross-references back.
>
> **Admin-UI gap warning (verified DW 10.25.8).** The admin UI does NOT expose per-resource Permissions or CapabilityLimitation editing for Dynamic Workspaces, Dashboards, or user-group Capability Sets. Direct-SQL on the three tables above is the path. See §4c for the full surface map + cache-flush requirement.

## 1. The `CapabilityControlFeature` flag — DW10.21+, default OFF

Source: `dw10source/src/Core/Dynamicweb.Core/CapabilityControl/CapabilityControlFeature.cs:3` (verified 2026-05-21):

```csharp
public sealed class CapabilityControlFeature() : FeatureBase("Capability Control", "Capabilities", false);
```

The third positional argument (`false`) is the default-enabled flag. **Capability Control ships OFF.** Toggle via Settings → Feature management → "Capability Control".

### What the flag changes

The flag is a single switch on a uniform pattern: every entity type in the Products area (Shop / Group / Product / Feed / Assortment / DynamicStructure) has a `GetPermissionParents()` method whose tail looks like:

```csharp
if (!Feature.IsActive<Core.CapabilityControl.CapabilityControlFeature>())
    yield return new PermissionSection("Products");
```

Verified at (2026-05-21):
- `Shop.cs:310-311` (PermissionName at line 314 = `"Shop"`)
- `Group.cs:313-314` (PermissionName at line 278 = `"ProductGroup"`)
- `Product.cs:513-514` (the guard; the `PermissionName` const declaration is at line 498 = `"Product"`)
- `Feed.cs:128-129` (PermissionName at line 118 / 132 = `"Feed"`)
- `Assortment.cs:186-187` (PermissionName at line 180 / 190 = `"Assortment"`)
- `DynamicStructure.cs:60-61` (PermissionName at line 43 = `"DynamicStructure"`)

When the flag is **OFF (legacy, default)**: every entity's parent chain terminates at `PermissionSection("Products")` — so a grant on the `/Products` capability key cascades down to every Shop, every Group, every Product, every Feed, every Assortment, every Dynamic Workspace in the system. This is the inherited DW9-style mental model: "give a user Edit on Products and they get Edit everywhere."

When the flag is **ON (modern)**: the legacy top link is severed. Entity-level grants stand alone. The capability tree (Layer B, §3 below) gates *menu visibility*; the entity tree (Layer C, §4) gates *actions*. They are orthogonal — both must grant for the user to see AND act.

### Decision rubric — ON or OFF for a Truvio demo

| You want… | Flag |
|---|---|
| The "give Admin user Edit on Products and they can do everything" legacy mental model | OFF |
| Per-section UI hiding (e.g. hide `/Products/Feeds` from product managers; keep `/Products/AllProducts` visible) | ON |
| To demo the modern permission model to a PIM-selection committee | ON |
| Minimum-effort grants (one capability assignment cascades everywhere) | OFF |
| Per-channel publishing authority where different roles see different channels | ON |
| **You're not sure** | OFF — match the ship default; revisit when the demo brief calls for orthogonal gating |

**Decide BEFORE granting anything.** Two different role matrices follow from the two settings; toggling mid-demo strands every grant you already made.

> **Do not confuse with the Completeness feature flag** (separate flag, also off by default; that one is the buggy beta covered in [`governance.md` "Completeness rules" §7](governance.md)). `CapabilityControlFeature` is independent of completeness behavior.

## 2. Layer A — `UnifiedPermission` (the storage layer)

Source: `dw10source/src/Core/Dynamicweb.Core/Security/Permissions/PermissionRepository.cs` (verified 2026-05-21).

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

**Layer A stores Layer C (entity) grants.** The layer-A table holds entity-level rows (Shop / ProductGroup / Product / ProductField / FilePermissionEntity / DynamicStructure / Feed / Assortment / `Section` for area roots). Each row's *shape* is determined by `PermissionName` (entity type) + `PermissionKey` (entity id or SystemName). **Layer B does NOT write here.** Capability Control (Layer B) lives in its own table — see §3.

## 3. Layer B — Capability Control (UI-section visibility)

Source: `dw10source/Dynamicweb.Products.UI/CapabilityControl/ProductsCapabilities.cs` + `ProductsCapabilityProvider.cs`; storage in `dw10source/Dynamicweb.CoreUI/CapabilityControl/CapabilityRepository.cs` (verified DW 10.25.8).

Capability Control is the **modern UI-permission layer**, introduced in DW10.21+ to fix the cascading-inheritance problem the legacy model had with hiding UI elements without affecting feature access. Each capability key is a slash-delimited path like `/Products/Channels`.

### Storage — separate `CapabilityLimitation` table (NOT `UnifiedPermission`)

```sql
TABLE CapabilityLimitation (
  CapabilityLimitationId          bigint IDENTITY,
  CapabilityLimitationKey         nvarchar,   -- the capability key (starts with '/')
  CapabilityLimitationUserGroupId int         -- user group id (NOT user id)
)
```

Semantics are **inverted from Layer A's "permit" model**: presence of a row = users in this group are *limited out of* (hidden from) this capability. Absence = no limit = capability visible (subject to Layer C entity check). The class is called `CapabilityLimitation`, not `CapabilityPermission` — read it as a hide-list. `DefaultCapabilityService.IsCapabilityLimitedForUser()` returns true when a matching row exists for any group the user belongs to.

Takes group IDs only — there is no per-user override. Per-role hide recipe → [permissions-recipes.md](permissions-recipes.md) §"Hide a UI section per role".

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

**`/Settings` is NOT a capability key.** The Settings tab is gated by the `BuiltInAdmin` / `SystemAdministrator` user-type check (§7), not by Capability Control. Non-admin users never see Settings regardless of `CapabilityLimitation` rows.

**Capability keys have parent relationships.** Limit the parent and the children become invisible regardless of child grants. E.g. add `/Products` to `CapabilityLimitation` for a group and the entire left-nav section disappears for them — child grants on `/Products/Channels` don't override.

**Capability + entity = both must grant.** This is the orthogonal design (only meaningful with the §1 flag ON):

| User has capability? | User has entity perm? | Outcome |
|---|---|---|
| ✗ | ✗ | Section invisible. (Capability wins on visibility.) |
| ✗ | ✓ | Section invisible. Action would succeed via raw API but UI doesn't expose it. |
| ✓ | ✗ | Section visible; item rows visible (or not — entity ACL governs); action buttons disabled / errors. |
| ✓ | ✓ | Full access. |

If a user reports "capability control doesn't work in conjunction with other permissions": **that's the design.** Capability *hides* sections; permission *authorises* actions. Trying to make capability do entity-level gating fails — that's Layer C's job.

Action-level granularity comes from `PermissionLevelRequired` on each `ActionNode`. E.g. `Read` on `/Products/DynamicWorkspaces` shows the section but hides the "+ Add workspace" button (which is wired to `PermissionLevel.Create`).

## 4. Layer C — Entity-level permissions

Stored in `UnifiedPermission`; keys come from the entity itself via the `IPermissionEntity` interface. The mapping (verified DW 10.25.8 against `$env:DW_VAULT/dw10source/`):

| Entity | `PermissionName` constant | `PermissionKey` shape | Source citation |
|---|---|---|---|
| Area root (Section grant for the whole area) | `"Section"` | area name without leading slash (e.g. `"Products"`, `"Assets"`) | `PermissionSection.cs:12` |
| Shop | `"Shop"` (`nameof(Shop)`) | `ShopId` (e.g. `"SHOP1"`, `"SHOP-DATA"`, `"CH-WEBSHOP"`) | `Shop.cs:314` |
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

**ProductField — per-field grants required for columns to render.** The `ProductListScreen` queries each `ProductField` for permission when building columns. With Cap Control ON, `ProductField.GetPermissionParents()` terminates (no `PermissionSection("Products")` fall-through) — so a `Section/Products` grant does NOT cascade to fields. **Symptom of the gap**: list view renders the rows (Type icon + Completeness bar appear from non-field sources) but Name / Number / Created / Updated / custom-field columns are blank. Fix: bulk-grant `('Group11', '<SystemName>', 'ProductField', '', Read)` rows for every standard field constant from `ProductField.FieldSystemName`, every `ProductFieldSystemName` row in `EcomProductField`, and every distinct `FieldId` in `EcomProductCategoryField`. Category fields use the **same `ProductField` PermissionName**, not a separate entity — `ProductField.GetPermissionEntityByKey()` falls back to `GetCategoryFieldBySystemName()` (line 1543).

**FilePermissionEntity — path-chain cascade.** The Assets tree (`MediaFilesNodeProvider`, `SystemFilesNodeProvider`, `DesignFilesNodeProvider`) gates every folder/file via `directory.GetPermission().HasPermission(Read)`. `FilePermissionEntity.GetPermissionParents()` yields a parent with the path's last segment stripped, recursively. Under flag ON the chain terminates at the root (no fall-through to `PermissionSection("Assets")`). **Symptom of the gap**: Assets tab is visible but every subtree (Media, System, Design) is empty. Fix: one grant on the root suffices — `('Group11', '/Files', 'File', '', Read)`. The path-chain cascade walks every subfolder for free. For tighter scoping, grant on `/Files/Images` only and Media-other-folders disappear.

Each entity declares its **permission parents** via `GetPermissionParents()`. The parent graph (when flag is OFF) is:

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

Verified ancestor chain in `Group.cs:297-307`: a Group yields its parent Group (recursive) OR its parent Shop, then `Shop.cs:310-311` either yields the area section (flag OFF) or terminates (flag ON). `Product.cs:502-515` yields its Groups; if no Groups (orphan), yields the area section under the flag.

**The Product hierarchy is dynamic, not static.** A product with relations to three groups inherits from all three's parent chains. Highest-level wins. A product moved to a new group inherits from the new chain on next read.

## 4b. Dashboard pinning — separate `DashboardAccessUserRelation` table

Source: `dw10source/src/Core/Dynamicweb.Core/Dashboard/DashboardConfigurationRepository.cs:42` (verified DW 10.25.8).

```sql
TABLE DashboardAccessUserRelation (
  DashboardRelationDashboardId  int,
  DashboardRelationUserId       int,   -- user id, NOT group id
  DashboardRelationDefault      bit    -- 1 = auto-landing dashboard for this user
)
```

Gates which dashboards a non-admin user sees in the area's dashboard tree. The repository's `GetDashboardsConfigurations` does a LEFT JOIN with `WHERE DashboardRelationUserId IN (<userIds>)` — dashboards with no matching relation row are excluded for that user. **Admins bypass via empty `userIds` context.**

- Empty relation rows + non-admin user = no dashboards visible. The user lands on the area's default `DashboardOverview` and any `?Path=<guid>` URL silently falls back to it.
- One row per (dashboard, user) pair. There is no per-group equivalent; you insert one row per user you want to pin a dashboard for.
- `Default=1` makes that dashboard the user's auto-landing when they navigate to the area root.

Persona-scoped landing recipe → [permissions-recipes.md](permissions-recipes.md) §"Dashboard pinning per persona".

## 4c. Admin-UI exposure gap — must script the tables directly

In DW 10.25.8, the admin UI does **NOT** expose per-resource Permissions or CapabilityLimitation editing for:

- **Dynamic Workspaces** — the workspace edit page Actions menu only offers "Edit" and "Delete".
- **Dashboards** — the dashboard page Actions menu only offers "Edit dashboard" and "Add widget".
- **User group → Capability Sets** (`/Admin/UI/Users/CapabilitySetList?UserGroupId=<gid>`) — shows inherited rows in read mode; no Add path is wired.

Out-of-the-box, a non-admin user with `allowBackend=true` on their group sees **the backend chrome but no PIM data**: empty Products tree, custom dashboards silently fall back to the default, `ProductEdit?ProductId=<id>` renders an empty "New product" form. This is more restrictive than typical PIM expectations and requires direct table seeding (Layer A `UnifiedPermission` + Layer B `CapabilityLimitation` + 4b `DashboardAccessUserRelation`) to make the persona functional. There is no admin-UI route around this for the resources above; the [access-surfaces.md](access-surfaces.md) Direct-SQL surface is the path. The persona-seeding recipes themselves live in [permissions-recipes.md](permissions-recipes.md).

After any direct insert/update on these three tables, flush three caches via Management API before the change is visible to logged-in users:

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

`DashboardAccessUserRelation` reads bypass the cache (queried per request) — no flush needed for dashboard relation changes. New logins always see fresh state regardless.

See [cache-invalidation.md](cache-invalidation.md) — the "Direct SQL INSERT/UPDATE/DELETE on `UnifiedPermission`", "…on `CapabilityLimitation`", "…on `CapabilitySetLimitation`", and "…on `DashboardAccessUserRelation`" rows — for the full surface.

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

Layer B is *what the user can see in the admin nav* (hide-list). Layer A is *what the user can read/edit/create/delete in the data* (permit-list, written by Layer C). `AccessUserGroup` membership (separate tables: `AccessUserGroup`, `AccessUserGroupRelation`) provides transitive grants across users.

The §1 flag controls whether Layer A's entity grants cascade up to Layer B area keys. Flag OFF = legacy cascade. Flag ON = orthogonal — both layers must permit, and each entity needs its own grant.

## 6. Role matrix + grant seeding — moved

The abstract role matrix (Editor / Reviewer / Publisher / Admin), the functional-view checklist, the action-button Read→Edit bump, the field-editability dual-gate, and the per-role field-level differentiation recipes all live in [permissions-recipes.md](permissions-recipes.md).

## 7. Admin bypass — who escapes every check

Source: `dw10source/Dynamicweb.CoreUI/CapabilityControl/CapabilityHelper.cs:87` (verified DW 10.25.8):

```csharp
internal static bool IsRelevantUser(int userId)
    => UserManagementServices.Users.GetUserById(userId) is User user
       && !(user.IsAngel || user.IsBuiltInAdmin);
```

Three classes of user bypass all `CapabilityLimitation` checks AND the per-resource Layer C checks (Dashboard listings, area trees, ProductField columns, File trees — everything):

- **Angel** (`AccessUserID = 1`) — the system-bootstrap account; always sees everything.
- **BuiltInAdmin** (`AccessUserType = 1`, "SystemAdministrator") — installation-owner account.
- **Administrator** (`AccessUserType = 3`) — full backend admin in practice; bypasses Capability + dashboard relation filters via empty-userIds context.

Effect: when designing the role matrix, never test a recipe by logging in as one of the above. Always create a Default-type user in the target group and log in as them. A persona scoping that "works" only because you're testing as Admin is not a scoping.

## 8. Plaintext password storage — moved

The `EncryptPassword=False` SQL escape hatch for seeding persona logins lives in [permissions-recipes.md](permissions-recipes.md) §"Plaintext-password escape hatch".

## 9. Cross-references

- **Grant-seeding recipes for demo personas** — [permissions-recipes.md](permissions-recipes.md). Everything operational (role matrix, functional-view checklist, level bumps, dual-gate, per-role differentiation, hides, pinning, passwords) lives there.
- **Render-time half of permissions** — see [`truvio-swift-demo/references/dw10-canonical-surfaces.md`](../../truvio-swift-demo/references/dw10-canonical-surfaces.md) §"Permissions — the entity store". That section owns the `Permission` table (different from `UnifiedPermission`) which gates `Page` / `Paragraph` render at request time. Roughly: this ref controls who can EDIT a product in admin; that one controls who can SEE a CMS page on the storefront. Both ultimately read from a permission table, but the tables, the enforcement points, and the key shapes differ.
- **Workflow transitions** — see [`workflow.md`](workflow.md). DW10's workflow engine has NO native per-state role gating (verified gap). The workarounds (subscriber-reject; custom capability key; soft gating via permission-aware surfaces) all build on Layer C entity permissions from this ref.
- **Publish-to-channel native action** — see `structural-model.md` §2.3 / §2.3a. The action's `PermissionLevelRequired = PermissionLevel.Edit` is a Layer C check on the source products + a write-permission check on the target Channel groups.
- **`AccessUserGroup` membership** — see DW10 admin Users → Groups. Group membership is what makes Layer A's "highest level wins" resolution work across users. A user inherits the highest grant from any group they belong to.
- **Capability Control vs Completeness feature flag** — different flags; do not confuse. `CapabilityControlFeature` is the permission-model toggle (this ref). The completeness flag is a separate buggy-beta toggle covered in [`governance.md`](governance.md) "Completeness rules" §7.
- **Cache invalidation after direct-SQL permission seeding** — see [cache-invalidation.md](cache-invalidation.md), the "Direct SQL INSERT/UPDATE/DELETE on `UnifiedPermission` / `CapabilityLimitation` / `CapabilitySetLimitation` / `DashboardAccessUserRelation`" rows. The three caches that need flushing (`DefaultCapabilityService`, `DefaultCapabilitySetService`, `PermissionService`) are listed there with the exact `CacheInformationRefresh` payload.
- **Access surfaces** — see [access-surfaces.md](access-surfaces.md). Per §4c, all three permission tables (`UnifiedPermission`, `CapabilityLimitation`, `DashboardAccessUserRelation`) are Direct-SQL territory in DW 10.25.8 — the admin UI does not expose them for the Dynamic-Workspace / Dashboard / Capability-Set resources we care about.

Source citations re-verified against `$env:DW_VAULT/dw10source/` on DW 10.25.8.
