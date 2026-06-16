# permissions-recipes.md

> Operational SQL recipes for seeding the role/permission grants behind demo personas in Dynamicweb 10 â€” abstract role matrix, functional-view grant checklist, action-button level bump, field-editability dual-gate, per-role field-level differentiation, UI-section hides, dashboard pinning, and the plaintext-password escape hatch. **Concept â†’ [permissions-model.md](permissions-model.md)** (three-layer model, storage tables, `CapabilityControlFeature` flag, entity registry, admin bypass, cache/enforcement); **seeding grants for personas â†’ this file.** Loaded from `~/.claude/skills/dynamicweb-pim-demo/SKILL.md` "Where to find things" table.
>
> All recipes assume direct SQL on the permission tables â€” the admin UI does not expose them for the resources these recipes touch ([permissions-model.md](permissions-model.md) Â§4c). After any insert/update, flush caches per the "Direct SQL INSERT/UPDATE/DELETE on `UnifiedPermission`" / "â€¦on `CapabilityLimitation`" / "â€¦on `CapabilitySetLimitation`" rows in [cache-invalidation.md](cache-invalidation.md); `DashboardAccessUserRelation` reads bypass the cache (no flush needed). Never verify a recipe logged in as Angel / BuiltInAdmin / Administrator â€” those user classes bypass every check ([permissions-model.md](permissions-model.md) Â§7); always test as a Default-type user in the target group.

## 1. Role matrix â€” abstract roles only

A PIM demo's role roster is project-specific. This ref does NOT prescribe role names â€” use customer-specific roles only after the customer-context PDF has been read (per the [`dynamicweb-demo-base/references/customer-context.md`](../../dw-tbd-demo-base/references/customer-context.md) read-only contract). For demo-skill purposes use abstract roles:

| Role | Layer B (capabilities â€” UI visibility) | Layer C (entity â€” actions) | Notes |
|---|---|---|---|
| **Editor** | `/Products` Read; `/Products/AllProducts` Edit; `/Products/DynamicWorkspaces` Read | Catalog Groups: Edit. Channel Groups: Read (sees what's published; can't directly attach) | Day-to-day product enrichment. |
| **Reviewer** | Same as Editor + `/Products/DynamicWorkspaces` Edit (sees the review workspace) | Catalog Groups: Edit. Channel Groups: Read. | Approves products in workflow; see `workflow.md` for the per-state gating gap. |
| **Publisher** | Same as Reviewer + `/Products/Channels` Edit; `/Products/Feeds` Read | All Groups (catalog + channel): Edit | Fires the "Publish to channel" action (`structural-model.md` Â§2.3a). |
| **Admin** | `/Products` All; sibling areas All | All entities All | Override for setup, governance audits, and recovery. |

The matrix assumes the `CapabilityControlFeature` flag is ON ([permissions-model.md](permissions-model.md) Â§1). If flag is OFF, collapse Layer B / Layer C distinctions: grant Layer C only (entity grants cascade up).

> Concrete role names (e.g. "Product Manager", "Procurement", "Approver", "Merchandiser", "Category Manager") are project-specific and belong in the customer's `notes/` or `CLAUDE.md` â€” not in this skill. Customer-context PDF is the source.

## 2. Functional-view checklist (flag ON)

The role matrix above lists the *concept* grants per role. To make a non-admin's PIM actually *functional* under flag ON (not just visible), you need grants on **all five entity types** the Products + Assets areas touch. Granting only the navigation entities (Shop / ProductGroup) leaves visible-but-empty trees and blank-column product lists. The full set per persona group:

| What renders | UnifiedPermission grant |
|---|---|
| Area tree (Products / Assets headers) | `('<gid>', 'Products', 'Section', '', Read)`, `('<gid>', 'Assets', 'Section', '', Read)` |
| Channel section shows shops | `SELECT '<gid>', ShopId, 'Shop', '', Read FROM EcomShops` |
| Channel tree expandable to groups | `SELECT '<gid>', GroupID, 'ProductGroup', '', Read FROM EcomGroups` |
| **Product list columns** (Name / Number / Created / Updated / Type / custom fields) | one row per `ProductField` SystemName: standards from `ProductField.FieldSystemName` constants + customs from `EcomProductField` + category fields from `EcomProductCategoryField.FieldId` (all under `PermissionName='ProductField'`) |
| **Assets tree shows folders** | single row `('<gid>', '/Files', 'File', '', Read)` â€” the FilePermissionEntity parent chain cascades to every subfolder/file |

Without the ProductField grants, the product list shows rows but most columns are blank. Without the File grant, the Assets tree is empty even though the tab is visible. Both are easy-to-miss because the tab + area-section grants alone make the chrome look correct. (Why the cascade stops at these entities under flag ON: [permissions-model.md](permissions-model.md) Â§4 "Two entities that demand special attention".)

## 3. Action-button visibility â€” bump entity grant from Read to Edit

The functional-view grants above are at `PermissionLevel.Read` (`4`). That makes the data *visible* but leaves action buttons hidden because every write action node carries `PermissionLevelRequired = PermissionLevel.Edit` (or `Create` / `Delete` for those operations). Symptom: a non-admin persona can browse products with full columns, but the **"Edit" link in the top-right of each attributes panel on a product detail page is missing**. Same for inline "Edit" / "Delete" actions on group nodes, dynamic-relation editors, AI-text generation, "Edit all" grid-edit, language add/remove, etc.

The gate sits inside the action-node factory used across product screens. The pattern (seen e.g. in `dw10source/Dynamicweb.Application.UI/Helpers/ActionBuilder.cs:81` `GetEditNode<TScreen>()`):

```csharp
PermissionLevelRequired = PermissionLevel.Edit,
```

and the attributes-panel-specific construction in `dw10source/Dynamicweb.Products.UI/Screens/ProductOverviewScreen.cs:996` (`ActionBuilder.Edit<ProductEditScreen>`) and `:1076` (screen-layout-driven "Edit" node).

Fix: bump the entity-grant level on the entities that gate the action. Under flag ON, the Product entity inherits level from its parent ProductGroups (highest level wins across all parents). So bumping ProductGroup grants to Edit cascades Edit to every product in those groups â€” no per-Product row needed.

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

The values come from `dw10source/src/Core/Dynamicweb.Core/Security/Permissions/PermissionLevel.cs`: `None=1, Read=4, Edit=20, Create=84, Delete=340, All=1364` (bit-flag, higher includes lower). Most action buttons in PIM editing screens want `Edit`. The toolbar `Permissions` button on each entity itself wants `All`.

What to leave at Read deliberately: `Shop` entities (editing shop config is platform-admin territory) and `Section/Assets` (Asset edits flow through the per-product image manager which uses the `File` grant). Bump these only when a role explicitly needs to edit shop configuration or upload to the Assets tab directly.

Flush `Dynamicweb.Security.Permissions.PermissionService` after the update (see [cache-invalidation.md](cache-invalidation.md)) â€” without the flush, logged-in users still see Read-level UI until re-auth.

## 4. Field-level editability â€” the dual-gate trap

Bumping ProductField grants to Edit makes write-action *buttons* appear, but a user who clicks "Edit" on a product can still land on a screen where **every field renders with a readonly lock icon** â€” including standard text fields like Name and custom category fields like DPP attributes. The reason is the dual-gate inside `dw10source/Dynamicweb.Products.UI/Screens/ProductEditScreen.cs:491`:

```csharp
if (!productLanguage.HasPermission(PermissionLevel.Edit) || !field.HasPermission(PermissionLevel.Edit))
    return true; // readonly
```

Both conditions must pass:

1. The `Language` entity for the product's language has `Edit` for the current user.
2. The `ProductField` entity has `Edit` for the current user.

If only one is granted, every input is readonly. **The Language entity is the easy one to forget** because the entity isn't visually represented on the screen â€” there's no "Language" panel to click. With Cap Control ON, `Language.GetPermissionParents()` terminates (no `PermissionSection("Products")` fall-through), so no upstream grant cascades â€” you must insert the row explicitly.

```sql
INSERT INTO UnifiedPermission (PermissionUserId, PermissionKey, PermissionName, PermissionSubName, PermissionLevel)
SELECT '<gid>', LanguageID, 'Language', '', 20 FROM EcomLanguages;
```

For multi-language demos, repeat per `LanguageID`. The `PermissionKey` is the language id (e.g. `"LANG1"`), not the ISO code.

## 5. Per-role field-level differentiation (writable for some roles, readonly for others)

The functional-view bump above ("all standard + custom + category fields to Edit") is the *unlock* â€” it makes the screen functional but gives every role the same write surface. To showcase **field-level role security** (a typical PIM-selection demo beat), differentiate per role by leaving some fields at Read for roles that don't own them. The pattern:

1. Apply the functional-view checklist to bump everything to `Edit` (level 20) for all persona groups.
2. Apply the dual-gate fix (Language Edit grants).
3. Per role, identify the fields that role does NOT own and DOWNGRADE those rows to `Read` (level 4).

```sql
-- Editor role: owns content + meta + images + all custom category fields.
-- Downgrade the commerce / lifecycle / workflow / physical fields.
DECLARE @editorReadOnly TABLE (SystemName nvarchar(100));
INSERT INTO @editorReadOnly (SystemName) VALUES
  ('ProductNumber'),('ProductPrice'),('ProductCost'),('ProductStock'),
  ('ProductActive'),('ProductWorkflowStateId'),('ProductDiscontinued'),
  ('ProductDefaultShopID'),('ProductManufacturerID'),('ProductType'),
  ('ProductEAN'),('ProductWeight'),('ProductHeight'),('ProductWidth'),
  ('ProductDepth'),('ProductVolume'),('ProductCreated'),('ProductUpdated');

UPDATE UnifiedPermission
SET    PermissionLevel = 4
WHERE  PermissionUserId = '<editor_gid>'
  AND  PermissionName = 'ProductField'
  AND  PermissionKey IN (SELECT SystemName FROM @editorReadOnly);

-- Reviewer/Publisher role: owns workflow + lifecycle + channel scope.
-- Downgrade content, meta, images, all DPP/category fields, commerce, physical.
DECLARE @reviewerReadOnly TABLE (SystemName nvarchar(100));
INSERT INTO @reviewerReadOnly (SystemName) VALUES
  ('ProductName'),('ProductShortDescription'),('ProductLongDescription'),
  ('ProductMetaTitle'),('ProductMetaDescription'),('ProductMetaKeywords'),
  ('ProductImageDefault'),('ProductImageSmall'),('ProductImageMedium'),
  ('ProductImageLarge'),('ProductImages'),
  ('ProductNumber'),('ProductPrice'),('ProductCost'),('ProductStock'),
  ('ProductEAN'),('ProductWeight'),('ProductHeight'),('ProductWidth'),
  ('ProductDepth'),('ProductVolume'),
  ('ProductManufacturerID'),('ProductType'),('ProductCreated'),('ProductUpdated');

UPDATE UnifiedPermission SET PermissionLevel = 4
WHERE PermissionUserId = '<reviewer_gid>' AND PermissionName = 'ProductField'
  AND PermissionKey IN (SELECT SystemName FROM @reviewerReadOnly);

-- Reviewer also gets all custom category fields downgraded (content domain).
UPDATE UnifiedPermission SET PermissionLevel = 4
WHERE PermissionUserId = '<reviewer_gid>' AND PermissionName = 'ProductField'
  AND PermissionLevel = 20
  AND PermissionKey IN (SELECT DISTINCT FieldId FROM EcomProductCategoryField);
```

The result is two visually-different Edit screens for the same product: the Editor sees content / images / category fields as editable inputs and commerce / workflow as readonly with lock icons; the Reviewer sees the inverse â€” workflow / lifecycle / channel scope editable, content locked. This makes the role split visible to the audience without any custom code, just data-side grants.

What to keep at `Edit` for every role: `ProductGroup`, `Section/Products`, `File` (`/Files`), `Language` (per language used). What to keep at `Read` for every role: `Shop` entities, `Section/Assets` (unless a role explicitly needs shop-config edits or direct Asset-tab uploads).

## 6. Hide a UI section per role (`CapabilityLimitation`)

Layer B semantics live in [permissions-model.md](permissions-model.md) Â§3 (presence of a row = hide; group IDs only; parent keys cascade). The operational steps:

- Insert one `CapabilityLimitation` row per (group, capability key) to hide â€” e.g. key `/Products/Feeds` for the Editor group hides the Feeds section while `/Products/AllProducts` stays visible.
- Limiting a parent key (e.g. `/Products`) hides the entire left-nav section; child grants do not override.
- There is no per-user override â€” to hide a capability for one specific user, put them in a dedicated group and limit the group.
- Flush `Dynamicweb.CoreUI.CapabilityControl.DefaultCapabilityService` afterwards (see [cache-invalidation.md](cache-invalidation.md) "Direct SQL INSERT/UPDATE/DELETE on `CapabilityLimitation`" row).

## 7. Dashboard pinning per persona (`DashboardAccessUserRelation`)

Table mechanics in [permissions-model.md](permissions-model.md) Â§4b (per-USER rows, no group equivalent, `Default=1` = auto-landing). Pattern: persona-scoped landing. To give each persona their own default dashboard, insert one `Default=1` row per persona-user pair, plus `Default=0` rows for any admin users who should also see the dashboard. No cache flush needed â€” `DashboardAccessUserRelation` is queried per request.

## 8. Plaintext-password escape hatch (seeding persona logins)

`GlobalSettings.config` (path: `Dynamicweb.Host.Suite/wwwroot/Files/GlobalSettings.config` on a standard install) controls password storage mode for both backend admins and extranet users:

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

When `EncryptPassword=False` (typical for development / on-prem demo solutions), the `AccessUser.AccessUserPassword` column stores plaintext. **This unlocks the SQL escape hatch for seeding persona logins** when no MCP / admin-UI / API path is available:

```sql
UPDATE AccessUser SET AccessUserPassword = 'DemoPassword123!'
WHERE AccessUserUserName IN ('persona1', 'persona2');
```

The MCP `create_users` tool has no password parameter (verified DW 10.25.8); the admin UI's Users â†’ user â†’ password field works but is manual. For automated demo seeding the SQL update is the fast path. Verify the setting before relying on it â€” production solutions often flip these to `True` and any plaintext seeded under `False` becomes a stale invalid hash after the flip.

