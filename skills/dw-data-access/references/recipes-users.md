# Out-of-product recipes — Users

This reference holds the out-of-product recipes for users (users, user groups, permissions, page and paragraph gating): Management API
commands at `/admin/api/...`, serializer layers, and direct SQL. The in-product skills for this
area are `dynamo: true` and carry no instruction on those surfaces, so they keep a one-line pointer
here instead of the recipe.

Every recipe names its surface in the repo convention: MCP tools `snake_case` in backticks,
Management API commands `PascalCase` in backticks with the route on first use in this file,
serializer operations by command or by layer and mode, and `SQL` labelled as such in a fenced `sql`
block. Every SQL recipe states three things inline — why the higher surfaces do not cover it, that
it is **local installs only**, and the cache flush or host restart it owes.

## Contents

- [`PermissionSave` — the write verb for every entity grant](#permissionsave--the-write-verb-for-every-entity-grant)
- [`PermissionsByIdentifier` — the read verb and its empty-SubName trap](#permissionsbyidentifier--the-read-verb-and-its-empty-subname-trap)
- [Deny backend access to an admin row — `UserSave` plus the column read-back](#deny-backend-access-to-an-admin-row--usersave-plus-the-column-read-back)
- [Seed the functional-view grants for a backend role](#seed-the-functional-view-grants-for-a-backend-role)
- [Bump entity grants from Read to Edit](#bump-entity-grants-from-read-to-edit)
- [Grant the Language entity — the dual-gate half nothing cascades](#grant-the-language-entity--the-dual-gate-half-nothing-cascades)
- [Per-role field-level differentiation](#per-role-field-level-differentiation)
- [Grant the storefront user-management commands](#grant-the-storefront-user-management-commands)
- [Seed a password for a freshly created login](#seed-a-password-for-a-freshly-created-login)
- [Assert a user delete on the row count, not the status](#assert-a-user-delete-on-the-row-count-not-the-status)
- [Delete orphaned user addresses](#delete-orphaned-user-addresses)
- [Rebuild the Users index after an impersonation write](#rebuild-the-users-index-after-an-impersonation-write)

Every grant recipe below carries the same two standing rules. **Flush after every write**: the three
permission caches are `DefaultCapabilityService`, `DefaultCapabilitySetService` and
`PermissionService`, refreshed with `CacheInformationRefresh` (the per-surface rulebook is
[`cache-invalidation.md`](cache-invalidation.md)); `DashboardAccessUserRelation` reads bypass the
cache and need no flush. **Never verify as Angel, BuiltInAdmin or Administrator** — those three user
classes bypass every check, so a scoping that passes as one of them is not a scoping; always test as
a Default-type user in the target group.

## `PermissionSave` — the write verb for every entity grant

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`grant-mechanics.md` §7). Inside the product, grants are an admin-screen operation: the
**Permissions** panel on the entity (`/Admin/UI/Content/PermissionList?Key=<key>&Name=<name>`, or
the toolbar **Permissions** button on the entity's own screen). MCP reaches exactly one corner of
this surface — `assign_permissions_to_assortment` writes assortment permissions and there is no
page, paragraph, section or user-group equivalent.

**`PermissionSave` at `/Admin/Api/PermissionSave` is the write verb for every entity grant** —
`Section`, `Page`, `GridRow`, `Paragraph`, `UserGroup` and the rest of the `[PermissionEntity]`
registry. It is proven on 10.28.x, it is an upsert, and it is safe to re-run. It self-invalidates
the permission cache, which a raw SQL INSERT does not, so prefer it wherever it reaches.

**The body is nested under `Model`.** `PermissionSaveCommand` is a `CommandBase<PermissionDataModel>`,
so a flat body of the inner properties is rejected before it executes — `HTTP 400
{"Command.Model":["Command.Model cannot be null"]}` — leaving the table untouched and saying nothing
about what the model is:

```
POST /Admin/Api/PermissionSave
{"Model":{"Key":"97","Name":"Page","SubName":"","OwnerId":"9","Level":4,
          "IsUserRolePermission":false,"IsExplicitPermission":true}}
-> HTTP 200, level echoed as the string "read", modelIdentifier "97|$|Page|$||$|9"
```

`PermissionDataModel` is `{PermissionLevel Level; String Key; String Name; String SubName; String
OwnerId; Boolean IsUserRolePermission; Boolean IsExplicitPermission}`. **`Key` is a STRING on every
entity type**, so a numeric page id is quoted. The response `modelIdentifier` is a composite joined
with the literal separator `|$|` (`<Key>|$|<Name>|$|<SubName>|$|<OwnerId>`), which is also the shape
`PermissionDelete`'s `PermissionIdentifier` takes.

`Level` takes the sparse `PermissionLevel` numbers (`None=1, Read=4, Edit=20, Create=84, Delete=340,
All=1364`), and `1` is a denial, not the bottom of a ladder.

Siblings in the same assembly: `PermissionDeleteCommand {String PermissionIdentifier}`,
`PermissionSetPermissionCommand : ListItemsCommandBase {PermissionLevel PermissionLevel;
IEnumerable<String> Ids}`, and the read query `PermissionsByIdentifierQuery {String Key; String Name;
String SubName; …}`.

Verify a write on the rendered surface (sign in as a member of the owner group) or with a read-only
`SELECT` on `UnifiedPermission`; the Permissions panel is a verification surface, not the authoring
path for the resources these recipes touch.

## `PermissionsByIdentifier` — the read verb and its empty-SubName trap

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`page-gating.md` §15, `permission-layers.md` §4d).

**The read returns an EMPTY `data` array when `SubName` is passed as `""`.** An empty-string sub-name
is not treated as "no sub-name" — it filters to nothing. Auditing page permissions before a change is
exactly when this fires, and the empty result reads as "no permissions configured, safe to add mine"
while the rows sat there the whole time:

```
GET /Admin/Api/PermissionsByIdentifier?Key=8460&Name=Page&SubName=   -> {"data":[]}
GET /Admin/Api/PermissionsByIdentifier?Key=8460&Name=Page            -> {"totalCount":7, …}
```

**Omit `SubName` entirely when reading.** The write side still takes `SubName:""` normally. The same
query on any key also returns the three implicit user ROLES (`Anonymous`, `AuthenticatedFrontend`,
`Administrator`) with `isUserRolePermission: true` and `isExplicitPermission: false`.

Cross-check the API read against `UnifiedPermission` before treating any empty result as "no
permissions set". Read-only, **local installs only**, no flush owed. Mind the `nvarchar`
`PermissionUserId`: a bare `int = PermissionUserId` comparison aborts the whole statement on the
literal `'Anonymous'`, so use `TRY_CAST`.

```sql
SELECT PermissionUserId, PermissionLevel FROM UnifiedPermission
WHERE PermissionName = 'Page' AND PermissionKey = '8460';
-- e.g. 1270|1   1292|1364   1325|1   Anonymous|1
```

## Deny backend access to an admin row — `UserSave` plus the column read-back

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`grant-mechanics.md` §6).

`allowBackend=false` is a no-op on an admin row: `User.AllowBackend` is computed
(`get { if (!allowBackend && !IsAdmin) return IsAngel; return true; }`), so for `AccessUserType`
SystemAdministrator (1) or Administrator (3) the getter always returns true and
`AccessUserAllowBackend` persists as `1` with no validation error and no warning. Measured on
10.28.1:

```
POST /Admin/Api/UserSave {"Model":{… "allowBackend":false, "active":false …}}
-> ok; the columns read back False, True
the identical call with "userType":"default" added
-> ok; the columns read back False, False
```

The only levers that deny backend access are `userType` (demote to `Default=5`) and `active=false`,
so a teardown must set `userType` in the same save. The API echo is not evidence — assert from the
columns, read-only, no flush owed:

```sql
SELECT AccessUserActive, AccessUserAllowBackend FROM AccessUser WHERE AccessUserID = <id>;
-- and, so the cleanup cannot lock everyone out:
SELECT COUNT(*) FROM AccessUser
WHERE AccessUserType IN (1,3) AND AccessUserActive = 1 AND AccessUserAllowBackend = 1;
```

## Seed the functional-view grants for a backend role

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`grant-mechanics.md` §8), which carries the checklist of what renders from which entity type.

The area-tree and Assets rows are single grants and belong on `PermissionSave`. The Shop,
ProductGroup and ProductField rows are one grant per row of an existing table — hundreds of them on a
real catalog — and the verb has no set-based form, so a set-based `SQL INSERT` is the sanctioned
shape. **Local installs only**, and it owes the three-cache flush above, because a raw INSERT does
not self-invalidate.

```sql
INSERT INTO UnifiedPermission (PermissionUserId, PermissionKey, PermissionName, PermissionSubName, PermissionLevel)
SELECT '<gid>', ShopId,  'Shop',         '', 4 FROM EcomShops;
INSERT INTO UnifiedPermission (PermissionUserId, PermissionKey, PermissionName, PermissionSubName, PermissionLevel)
SELECT '<gid>', GroupID, 'ProductGroup', '', 4 FROM EcomGroups;
```

Product-list COLUMNS need one `PermissionName='ProductField'` row per field system name: the
standards from the `ProductField.FieldSystemName` constants, the customs from `EcomProductField`, and
the category fields from `EcomProductCategoryField.FieldId`. Without them the list shows rows with
most columns blank.

## Bump entity grants from Read to Edit

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`grant-mechanics.md` §9), which carries why the buttons are hidden and what to leave at Read.

A bulk level change across an existing grant set has no verb-shaped form — `PermissionSave` is
per-row — so this is `SQL`, **local installs only**, and it owes a `PermissionService` flush;
without the flush, logged-in users keep seeing Read-level UI until re-auth.

```sql
UPDATE UnifiedPermission
SET    PermissionLevel = 20    -- Edit (Read | 1<<4 = 4 | 16)
WHERE  PermissionUserId IN ('<gid1>', '<gid2>')
  AND  PermissionName IN ('ProductGroup', 'ProductField', 'File')
  AND  PermissionLevel = 4;    -- only bump rows currently at Read

-- and the area-root section grant, so screen-layout-driven "Edit" tabs work
UPDATE UnifiedPermission
SET    PermissionLevel = 20
WHERE  PermissionUserId IN ('<gid1>', '<gid2>')
  AND  PermissionName = 'Section'
  AND  PermissionKey = 'Products'
  AND  PermissionLevel = 4;
```

## Grant the Language entity — the dual-gate half nothing cascades

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`grant-mechanics.md` §10), which carries the dual-gate itself.

`Language.GetPermissionParents()` terminates under Cap Control ON, so no upstream grant cascades and
the row has to be inserted explicitly, one per language. Set-based over `EcomLanguages`, so `SQL`,
**local installs only**, owing the three-cache flush. The `PermissionKey` is the language id (e.g.
`LANG1`), not the ISO code.

```sql
INSERT INTO UnifiedPermission (PermissionUserId, PermissionKey, PermissionName, PermissionSubName, PermissionLevel)
SELECT '<gid>', LanguageID, 'Language', '', 20 FROM EcomLanguages;
```

## Per-role field-level differentiation

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`grant-mechanics.md` §11), which carries the three-step method and what every role keeps.

Step 3 — downgrading the fields a role does not own — is one `UPDATE` per role against a list of
`ProductField` system names. Same surface argument as the bump above: `SQL`, **local installs only**,
owing the `PermissionService` flush.

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

To downgrade every custom category field for a role in bulk:

```sql
UPDATE UnifiedPermission SET PermissionLevel = 4
WHERE PermissionUserId = '<role_gid>' AND PermissionName = 'ProductField'
  AND PermissionLevel = 20
  AND PermissionKey IN (SELECT DISTINCT FieldId FROM EcomProductCategoryField);
```

## Grant the storefront user-management commands

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`user-group-operations.md` §17), which carries why every `UserGroupCmd` is refused out of the box.

The grant is one `PermissionSave` row on the `UserGroup` entity with `SubName: User`, owned by the
account-admin group, at `Delete` (340) so it satisfies the `Read` / `Edit` / `Create` / `Delete`
requirements of the whole command set:

```
POST /Admin/Api/PermissionSave
{"Model":{"Key":"<accountGroupId>","Name":"UserGroup","SubName":"User",
          "OwnerId":"<adminGroupId>","Level":340,
          "IsUserRolePermission":false,"IsExplicitPermission":true}}
```

Before the grant, the read on the same identifier shows only inherited owners; after it the identical
storefront requests pass and the state actually changes.

## Seed a password for a freshly created login

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`grant-mechanics.md` §13), which carries the `EncryptPassword` settings and the passwordless-user
trap.

There is no MCP password tool and `UserSave` cannot set a password either, so a freshly seeded
persona cannot sign in until a password is set out of band. The admin UI's Users → user → password
field works and is manual; for automated seeding the `SQL` escape hatch is the fast path, and it is
only valid while `EncryptPassword` is `False` — plaintext seeded under `False` becomes a stale
invalid hash after the flip. **Local installs only**, no flush owed (authentication reads the column
per attempt), and Dynamicweb auto-rehashes a plaintext seed on the first successful login.

```sql
UPDATE AccessUser SET AccessUserPassword = 'Password123!'
WHERE AccessUserUserName IN ('user1', 'user2');
```

Validate by signing in as the persona, not as an admin, and reaching the account landing page.

## Assert a user delete on the row count, not the status

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`user-group-operations.md` §17b), which carries the `Ids`-as-strings shape and the 200-means-nothing
rule.

Measure the `AccessUser` delta immediately after every batch and have the helper return
`deleted: (countAfter === 0)` rather than `deleted: true`. Read-only, **local installs only**, no
flush owed:

```sql
SELECT COUNT(*) FROM AccessUser WHERE AccessUserUserName = '<probe>';   -- must be 0
SELECT COUNT(*) FROM AccessUser WHERE AccessUserType = 2;               -- clone-hygiene census
```

## Delete orphaned user addresses

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`grant-mechanics.md` §14), which carries why the verb answers 404 for exactly these rows.

`UserAddressDelete` resolves an address through its owning user, and an orphan carries
`AccessUserAddressUserId = 0`, so the only address-delete verb cannot reach the rows the Ecommerce
health check flags. `SQL` is the only route and is sanctioned here; no runtime cache is keyed on
`AccessUserAddress`, so it owes no flush and no restart, and it stays **local installs only**. Scope
on the null owner **plus** blank address fields — orphans interleave with real address ids, so an
id-range delete takes live personas' addresses with it.

```sql
SELECT * FROM AccessUserAddress WHERE AccessUserAddressUserId = 0;   -- inspect before deleting
DELETE FROM AccessUserAddress
WHERE AccessUserAddressUserId = 0
  AND ISNULL(AccessUserAddressName, '') = '' AND ISNULL(AccessUserAddressAddress, '') = '';
```

Verify afterwards that the health provider's orphaned-address check returns 0 **and** that live
personas still have their addresses.

## Rebuild the Users index after an impersonation write

In-product home: [dw-users-permissions](../../dw-users-permissions/SKILL.md)
(`user-group-operations.md` §17c), which carries why the index is the effective permission model.

Nothing marks the affected documents dirty when the impersonation relation is written, so a Full
build is owed after any write to `AccessUserSecondaryRelation`. In-product that is `build_product_index`
against the Users repository followed by `wait_for_product_index`; the Management API form is:

```
POST /Admin/Api/BuildIndex {"repository":"Users","indexName":"Users.index","buildName":"Full"}
```

Flush `UserService` as well, and re-read the index document of the identity whose grant was REMOVED.
