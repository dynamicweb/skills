---
name: dw-users-permissions
type: knowledge
group: users
description: 'Manage users, groups, and the Permission entity store in Dynamicweb 10. Triggers: Permission entity, user groups, permission modelling. Non-triggers: product access control -> dw-commerce-b2b; custom backend logic -> dw-extend-csharp-api.'
---

# Users and Permissions

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

| Level | Includes | Description |
|-------|---------|-------------|
| Not set | — | No rights (no explicit entry) |
| None | — | No rights (explicit deny) |
| Read | — | Can view content and settings |
| Edit | Read | Can edit existing items |
| Create | Read, Edit | Can create new items |
| Delete | Read, Edit, Create | Can delete items |
| All | All lower | Can set permissions on this item |

**Priority rule:** When a user belongs to multiple groups with different permission levels on the same item, **the highest level wins**.

**Important note on None:** In the new permission model, `None` does NOT override a higher permission from another group. `None` means "no access from this group's context" but doesn't actively deny access granted by another group.

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

### UI Permissions (v10.21+)

A second permission dimension — set on **Areas** and **Navigation tree sections** only. Hides UI elements **without affecting functional access** (a user still has the functional permission but doesn't see the menu item).

- Does **not** cascade down the tree
- Applied per area/navigation node independently

### Restricting Frontend Page Access

Default: Anonymous users have Read on all pages.

To restrict a page or branch:
1. Set **Anonymous users (frontend) → None** on the page
2. Grant **Read** to **Authenticated users (frontend)** — or, to restrict to specific groups, set
   **Authenticated users (frontend) → None** and grant **Read** to the target groups. The explicit
   broad-role deny is load-bearing: a bare group grant is silently overridden by the inherited
   Authenticated-users grant (highest wins) and does not gate.

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

## Pitfalls

**"Allow backend login" must be checked** — user type alone does not grant backend access. Editors must also have "Allow backend login" checked on their user account.

**Permission "None" is not a hard deny** — in the new model, a user in two groups where one has None and another has Edit on the same item gets Edit access (highest wins). Use explicit permission management rather than relying on None as a deny mechanism.

**Permissions were rebuilt for DW10** — DW9 permission configurations cannot be migrated. Must be reconfigured from scratch after upgrade. See [dw-setup-upgrade](../dw-setup-upgrade).

**Dynamic group membership has latency** — segment-query-based group membership is evaluated at query time, not in real time. Changes in the underlying data (e.g., a user's country changes) may not immediately affect group membership.

## Next Steps

- **B2B assortments and CSR impersonation?** See [dw-commerce-b2b](../dw-commerce-b2b)
- **Integrating users from an ERP?** See [dw-integration-erp](../dw-integration-erp)
- **Custom user logic in C#?** See [dw-extend-csharp-api](../dw-extend-csharp-api)
