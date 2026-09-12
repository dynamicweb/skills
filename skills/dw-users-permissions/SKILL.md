---
name: dw-users-permissions
type: knowledge
group: users
mcp: optional
dynamo: true
description: 'Manage users, groups, and the Permission entity store in Dynamicweb 10. Triggers: Permission entity, user groups, permission modelling. Non-triggers: product access control -> dw-commerce-b2b; custom backend logic -> dw-extend-csharp-api.'
---

# Users and Permissions

## Without MCP

The knowledge here stands alone; the Dynamicweb MCP tools it names are the way to apply it, and
in-product they are the only way — the MCP tool set plus read/write under `Files/` is the whole
surface these steps may use. When no tool covers the operation, **stop and tell the user**, naming
the admin screen that performs it, rather than substituting a guessed HTTP call, a file edit
outside `Files/`, or SQL. The Management API, the serializer and direct SQL exist only outside the
product, are never a step in this skill, and are owned by
[`dw-data-access`](../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance".

## User Entity Structure

### Key User Fields

**User tab:**
- Username, user type, Active/Inactive checkbox
- Allow backend login (must be checked for editor/admin access)
- Authentication method (password, external provider)
- First name, Last name, Title, Phone, Work
- Default address: Address, Address 2, Zip, City, Region, Country
- Group membership

**Fields tab:** Custom user fields and custom address fields

**Addresses tab:** Multiple addresses per user (one is set as default)

**Advanced tab:** Editor type, Item type, Redirect after login, External ID, Active from/Active to, Latitude/Longitude, Disable live prices

**Commerce tab:** Customer Number, Default shopID, Default currency, Default stock location

### DB Search Columns

When querying users directly, use these column names: `AccessUserName`, `AccessUserUserName`, `AccessUserEmail`, `AccessUserFirstName`, `AccessUserLastName`, `AccessUserCustomerNumber`.

### User Types

| Type | Backend access | Default permissions |
|------|---------------|-------------------|
| Administrator | Full | All permissions |
| Admin | Full | All permissions |
| Editor | Requires "Allow backend login" | None (must be configured) |
| Custom types | Per configuration | Per configuration |

Custom user types can be created at **Settings > Custom user types**.

### Email Template Tags for Users

| Tag | Value |
|-----|-------|
| `DWUsers:User:Username` | Username |
| `DWUsers:User:Password` | Password (new user emails) |
| `DWUsers:User:Name` | Full name |
| `DWUsers:User:Email` | Email address |
| `DWUsers:User:Department` | Department |
| `DWUsers:User:Type` | User type name |
| `DWUsers:User:ValidFrom` / `ValidTo` | Account validity dates |
| `DWUsers:User:PasswordRecoveryUrl` | Password reset link |

## User Groups

User groups are organized in a **nested hierarchy** and appear in the Users area left-side tree.

### Purposes

- **Organizational** — structure users in the admin UI
- **Permission assignment** — grant access to backend areas and frontend pages
- **Customer self-service** — users can opt in/out of groups via the Extranet app
- **B2B scoping** — used in assortments, payment methods, shipping restrictions, price lists

### Group Configuration

**Group tab:**
- Name
- Default permission (inherited by all group members)
- Group image
- Users (segment search query for dynamic membership)
- Default address

**Fields tab:** Custom user field values — act as fallback for group members with no explicit field value set on their user account.

**Advanced tab:** Tree section (determines position in the hierarchy), Redirect after login, Allow backend login, Item type.

### Adding Users to Groups

| Method | How |
|--------|-----|
| Manually | Multi-select users → Action menu → Add to group |
| Self-service | Extranet app — users join/leave via frontend |
| Dynamic | Segment search query on the Group tab |
| Integration | Import via Integration Framework |

### Dynamic Group Membership

Groups support a **segment search query** — users matching the query are dynamically included as members. Examples:
- "All users from country Germany"
- "All users with order count > 10"
- "All users with a specific custom field value"

## Permission Model

### Permission Levels

From lowest to highest:

| Level | Stored value | Includes | Description |
|-------|---|---------|-------------|
| Not set | (no row) | — | No rights (no explicit entry) |
| None | `1` | — | No rights from this group's context |
| Read | `4` | — | Can view content and settings |
| Edit | `20` | Read | Can edit existing items |
| Create | `84` | Read, Edit | Can create new items |
| Delete | `340` | Read, Edit, Create | Can delete items |
| All | `1364` | All lower | Can set permissions on this item |

**The stored values are a sparse bit-flag enum, not a 0-based ladder.** A `UnifiedPermission` row
at level `1` is `None`; level `4` is `Read`. Reading a database of `Anonymous = 1 / <group> = 4` as
"1 is read, 4 is higher" writes the opposite of what was meant — print these numbers beside any
level copied out of a solution.

**Priority rule:** When a user belongs to multiple groups with different permission levels on the same item, **the highest level wins**.

**How to deny, given highest-wins:** `None` on its own does not override a higher permission from
another group — it means "no access from this group's context", not a hard deny. That is precisely
why a gate is written as a **pair**: an explicit `AuthenticatedFrontend → None` deny on the entity
**plus** a `<group id> → Read` grant on the same entity. The deny removes the broad inherited grant
that would otherwise win; the group grant restores it for the intended audience. A bare group grant
with no deny leaves the entity open to every signed-in user. The worked recipe and its enforcement
points are in [`references/page-gating.md`](references/page-gating.md) "Group-scoped gates need the
deny+grant pair".

### System-Wide Default Roles

| Role | Default permission |
|------|--------------------|
| Anonymous users (frontend) | Read |
| Authenticated users (frontend) | Read |
| Authenticated users (backend) | Not set |
| Administrators | All |

### Setting Permissions

Context menu on any area tree item → **Permissions → New permission**:
1. Select **Principal type**: User group or User role
2. Select the **Principal** (specific group or system role)
3. Select the **Permission level**
4. Save

### Granular Commerce Permissions

Permissions can be set at the level of:
- Shops
- Channels
- EcomLanguages

**Effect:** Users only see order data (Orders, Carts, Quotes, Subscriptions, Ledgers, RMAs) from shops they have Read access to.

### Backend areas: the `Section` grant, and the separate UI-visibility dimension

Two different mechanisms are both described as "area permissions", and mixing them up produces a
role that looks configured and cannot save:

- **A `Section` grant is an ordinary entity permission** (`UnifiedPermission`, `PermissionName =
  'Section'`, `PermissionKey` = the admin area name). A backend user who is not an Administrator
  has no grant on any area and sees an admin shell with NO navigation at all until one is written.
  **The level on the `Section` row is the level the screens beneath it operate at** — at `Read` the
  area, its tree and its edit screens render with every write command withheld; at `Edit` the Save
  commands appear. Grant the level the role must operate at.
- **Capability Control (v10.21+)** is the separate visibility dimension, stored in
  `CapabilityLimitation` and set per area / navigation-tree section. It hides UI elements without
  changing what an action is authorised to do, and it does not cascade a level down the tree.

Both are detailed in [references/permission-layers.md](references/permission-layers.md) §3 and §4d.

### Restricting Frontend Page Access

Default: Anonymous users have Read on all pages.

To restrict a page or branch:
1. Set **Anonymous users (frontend) → None** on the page
2. Grant **Read** to **Authenticated users (frontend)** — or, to restrict to specific groups, set
   **Authenticated users (frontend) → None** and grant **Read** to the target groups. The explicit
   broad-role deny is load-bearing: a bare group grant is silently overridden by the inherited
   Authenticated-users grant (highest wins) and does not gate.
3. Write an explicit row for **every** user group as well — `None` for the ones that must not see
   the page. A group with no row inherits its parent's permission, and the parent of a root-level
   page is the permissive area default, so a positive-only grant admits every group it did not
   name. Prove the gate by signing in as a persona from each denied group; "anonymous is
   redirected" is what an incomplete gate looks like.

A denied anonymous visitor is auto-redirected to the first page in the website that carries the
UserAuthentication app — keep that page active and un-restricted.

This pattern is the standard for member-only pages, B2B portals, and customer extranets.

## User API

### Reading Users

```csharp
using Dynamicweb.Security.UserManagement;

// Current user in request context
User? currentUser = UserContext.Current.User;
bool isLoggedIn = UserContext.Current.IsLoggedOn;
int userId = UserContext.Current.UserId;

// Look up users
var service = UserManagementServices.Users;
User? byId = service.GetUserById(userId);
User? byEmail = service.GetUserByEmailAddress("user@example.com");
IEnumerable<User> inGroup = service.GetUsersByGroupId(groupId);
```

### Writing Users

```csharp
// Save user changes
service.Save(user);

// Password management
service.ChangePassword(user, "NewSecurePassword");

// Group membership
var groupService = UserManagementServices.UserGroups;
var group = groupService.GetGroupById(groupId);
service.AddGroupRelations(user, new[] { group });
service.RemoveGroupRelations(user, new[] { group });
```

## Deep reference

The permission internals are split across four references that share one section numbering, so a
§-number is unique across all four:

| Read it for | Reference |
|---|---|
| The storage model — `UnifiedPermission` / `CapabilityLimitation` / `DashboardAccessUserRelation`, the `CapabilityControlFeature` flag, the entity registry, and the backend `Section` entity with its three implicit user roles (§1-§5) | [references/permission-layers.md](references/permission-layers.md) |
| Who bypasses every check, the `PermissionLevel` numbers, the `PermissionSave` write surface, and the recipes that build a non-admin backend role: action buttons, field-level editability, per-role differentiation, UI-section hides, the plaintext-password escape hatch, orphaned addresses (§6-§14) | [references/grant-mechanics.md](references/grant-mechanics.md) |
| Render-time gating of storefront pages, grid rows and paragraphs — the layer-YAML `permissions:` block, the explicit-row-per-group rule, highest-level-wins resolution, impersonation resolving against the effective user, the `/Files` bypass, and the customer-number-suffix presentation flag (§15-§16) | [references/page-gating.md](references/page-gating.md) |
| Writing users, groups and impersonation grants — the MCP-tool versus Management-API-verb table, whole-entity cache saves, the Users-index copy of an impersonation grant, and the Swift `UserGroups` storefront app (§17) | [references/user-group-operations.md](references/user-group-operations.md) |

## Pitfalls

**"Allow backend login" must be checked** — user type alone does not grant backend access. Editors must also have "Allow backend login" checked on their user account.

**A gate is a deny plus a grant, never a grant alone** — highest wins, so a user in two groups where one has None and another has Edit gets Edit. `None` alone is not a hard deny, and that is the reason the working shape pairs an explicit `AuthenticatedFrontend → None` deny with a per-group `Read` grant on the same entity. Shipping the grant without the deny leaves the entity readable by every signed-in user, and the gate passes review because the intended persona does see it. See [`references/page-gating.md`](references/page-gating.md).

**Permissions were rebuilt for DW10** — DW9 permission configurations cannot be migrated. Must be reconfigured from scratch after upgrade. See [dw-setup-upgrade](../dw-setup-upgrade).

**An MCP user/group save writes the WHOLE entity from cache** — `update_users` carrying only an id,
or `save_user_groups` carrying only name and parent, re-saves every other column from the cached
model and blanks what the tool's model does not carry. It is the one call guaranteed to undo a SQL
write made on the same row ([references/user-group-operations.md](references/user-group-operations.md) §17b).

**Dynamic group membership has latency** — segment-query-based group membership is evaluated at query time, not in real time. Changes in the underlying data (e.g., a user's country changes) may not immediately affect group membership.

## Next Steps

- **B2B assortments and CSR impersonation?** See [dw-commerce-b2b](../dw-commerce-b2b)
- **Integrating users from an ERP?** See [dw-integration-erp](../dw-integration-erp)
- **Custom user logic in C#?** See [dw-extend-csharp-api](../dw-extend-csharp-api)
- **Cache invalidation after mutations (what to flush, when a restart is owed)?** See [dw-data-access](../dw-data-access/SKILL.md)
