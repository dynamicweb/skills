# Users, groups and impersonation — write surfaces and the storefront app

Section §17 of the DW10 permission model and its neighbours: the Swift `UserGroups` storefront
app, the verbs that write users, groups and impersonation grants, and the search-index copy of the
impersonation relation. The permission store these grants are read against is
[`permission-layers.md`](permission-layers.md); the `PermissionSave` verb is
[`grant-mechanics.md`](grant-mechanics.md) §7.

## Contents

- [17. Frontend user management — the Swift 2.4 UserGroups app](#17-frontend-user-management--the-swift-24-usergroups-app)
- [17b. Write surfaces for users, groups and impersonation grants](#17b-write-surfaces-for-users-groups-and-impersonation-grants)
- [17c. An impersonation grant is denormalised into the Users index](#17c-an-impersonation-grant-is-denormalised-into-the-users-index)
- [Cross-references](#cross-references)

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
  {"Model":{"Key":"<accountGroupId>","Name":"UserGroup","SubName":"User",
            "OwnerId":"<adminGroupId>","Level":340,
            "IsUserRolePermission":false,"IsExplicitPermission":true}}
```

(The body is nested under `Model`, `Key` is a string, and `340` is `Delete` — the level numbers are
sparse, see [`grant-mechanics.md`](grant-mechanics.md) §7.)

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

### The app pages over EVERY group and the list template filters the CURRENT PAGE

**An accounts directory that lists two of fifteen accounts is a PAGING symptom, not a permissions
or a settings symptom.** `UserGroups` does not restrict the group list: it pages over every
`AccessUser` row with `AccessUserType = 2` (system groups, role groups and DC groups included), and
Swift's `Users/UserGroups/List/UserGroup_List.cshtml` then filters `Model.Groups` — the CURRENT
PAGE — down to the customer accounts. The filter runs after paging, so any account that does not
fall on page one is invisible, and the pager counts the unfiltered total. **The tell is a page
count that divides the TOTAL group count rather than the filtered one** (44 groups at `PageSize`
10 reads "page 1 of 5" while showing two accounts).

Widening the app's `UserGroups` setting changes nothing — it is an invite-time setting, not a list
filter (above). The reachable fix is a `PageSize` larger than the whole group tree (10 → 60 on one
install listed all fifteen accounts, with the template's own filter still keeping every staff group
out). Say out loud that this fix is fragile: it holds only while the tree stays smaller than the
page size. The durable fix is to filter BEFORE paging, which means `AccessUserUserAndGroupType`
plus the app's `ListGroupType` — and that column is writable by no verb on 10.28.x (not on MCP
`save_user_groups`, and there is no `UserGroupSave` / `UserGroupById` command at all), so the
template filter plus a generous page size is what is reachable without SQL.

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

**For a picker that must scale, scope it in the index rather than after the read.** The shipped
`UserIndexSchemaExtender` publishes the impersonation graph in both directions — `CanImpersonate` on
the impersonator's document, `CanBeImpersonatedBy` on the target's — already expanded through group
inheritance, so the whole scope is one arm of a repository query instead of hydrating every hit and
discarding most of them. Two rules govern building on it, both owned by
[`dw-search-indexing`](../../dw-search-indexing/references/index-management.md#the-user-index-publishes-a-password-hash-and-the-whole-impersonation-graph):
those fields are **numeric**, so the arm's right-hand side must declare `System.Int32` /
`System.Int32[]` or it matches nothing and fails closed
([`query-expressions.md`](../../dw-search-indexing/references/query-expressions.md#a-numeric-predicate-needs-a-typed-constant));
and every user document also carries the account's password hash, so a template over the results names
the fields it renders rather than looping the document.

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


## 17b. Write surfaces for users, groups and impersonation grants

Per operation, the two surfaces and what each one actually writes. MCP tools are `snake_case`;
Management API verbs are `PascalCase` at `/Admin/Api/<Verb>`. Measured on 10.28.x.

| Operation | MCP tool | Management API verb | Notes |
|---|---|---|---|
| Create / edit a user | `create_users`, `update_users` | `UserSave` (`{Model:{…}}`) | The MCP tools are whole-entity saves against the cache — see below. Neither surface sets a password ([`grant-mechanics.md`](grant-mechanics.md) §13 is the escape hatch). |
| Create / edit a user group | `save_user_groups` | none — `UserGroupSave` does not exist, and `UserGroupById` / `UserGroups` answer `Unknown query` | MCP is the only verb-shaped surface, so a group column outside its model has no write path at all. |
| Add users to groups | `assign_users_to_group`, `assign_groups_to_user` | `UsersAddToGroups` `{"GroupIds":[<int>],"Ids":["<string>"]}` | `UserGroupRelationSave` is a LIST command: the single-relation `{"GroupId":…,"UserId":…}` shape answers `HTTP 200 {"status":"invalid","message":"No items selected"}`. |
| Grant impersonation | none | `UserImpersonateAdd` `{"UserOrGroupId":<int>,"ICanImpersonateUsersOrGroups":true,"UserOrGroupIdsToAdd":[<int>]}` | Ids are **ints** here. |
| Revoke impersonation | none | `UserImpersonateDelete` `{"UserOrGroupId":<int>,"ICanImpersonateUsersOrGroups":true,"Ids":["<string>"]}` | `Ids` is **inherited from `ListItemsCommandBase`, and its elements are STRINGS**. No `…ToRemove` / `…ToDelete` property exists anywhere in the assembly, so hunting for a symmetric counterpart to `UserOrGroupIdsToAdd` finds nothing; the read twin `GroupsICanImpersonateByGroupId` returns exactly the values `Ids` wants, as `modelIdentifier` strings. |
| Write an entity permission grant | `assign_permissions_to_assortment` (assortments only) | `PermissionSave` | [`grant-mechanics.md`](grant-mechanics.md) §7. |

Three rules come out of that table.

**A refusal arrives as HTTP 200.** The wrong-shape refusal above and a permission refusal on the
storefront app both return 200 with a normal-looking body, so a helper reading the status field
reports success. **Assert the relation table afterwards** — `AccessUserGroupRelation` row counts for
membership, `AccessUserSecondaryRelation` for impersonation — or assert the state the write was for.
One `UserImpersonateDelete` over fifteen group rows took `AccessUserSecondaryRelation` 61 → 46 with
a row-by-row diff showing exactly those fifteen gone and membership untouched; that diff is the
evidence, not the `ok`. Both relation tables carry IDENTITY columns, so a revert has to be generated
as literal re-INSERTs with `SET IDENTITY_INSERT` before the write, never derived from the rows
afterwards.

**MCP `save_user_groups` and `update_users` are WHOLE-ENTITY saves against the CACHE.** They are
partial in what you may SEND, not in what they WRITE: each loads the entity from the Dynamicweb
cache, applies the properties present in the request, and saves the whole entity back. So any column
outside the tool's model is written back as that model's default — `save_user_groups` carrying only
`id` / `name` / `parentGroupId` / `customerNumber` blanked those groups' `AccessUserRedirectOnLogin`
— and any column the tool does model is written back from the CACHED value. `update_users
{"users":[{"id":89}]}` is therefore not a no-op: it is precisely the call that reverts a SQL write
made on that row a second earlier (a password hash restored by SQL came back as the pre-restore
value, and re-running the same UPDATE without the MCP call held). **Never use an MCP write on row X
to invalidate the cache for a SQL write on row X.** Make the cache-invalidating write FIRST and the
SQL write second, accepting that the value is not live until something else evicts the entry; or
touch a different entity; or spend a host restart. This is the standing exception to the "SQL write
plus an API touch to invalidate" pattern in
[`cache-invalidation.md`](../../dw-data-access/references/cache-invalidation.md).

**`AccessUserAdministratorInGroups` is not usable as an identity signal.** For a value written to
the column by SQL, `User.AdministratorInGroups` and `User.GroupsIdsUserIsAdmin` both read back as
EMPTY collections in a live Razor render, and the static `GetAdministratorsByGroupID(<groupId>)`
returns empty too — measured on every row carrying it, after a host restart, with the value written
both bare and delimited. Model an account-admin role as GROUP MEMBERSHIP instead: it is
cache-coherent, it reads correctly from Razor, the C# API and the MCP tools, and it survives a
customer-number change. One role group holding exactly one member per customer account answers "who
is the account admin here" with a membership query and no string convention at all. Where the column
genuinely has to be written, the write path is the method pair `AddToGroupAdministrators(groupId)` /
`RemoveFromGroupAdministrators(groupId)` on `Dynamicweb.Security.UserManagement.User` plus a user
save — the property has no setter but the type does have the methods, so a SQL write is not
equivalent to the platform's own write path.

## 17c. An impersonation grant is denormalised into the Users index

The shipped user-index extender writes the impersonation relation onto the user documents as
`CanImpersonate` and `CanBeImpersonatedBy`, **already expanded through group inheritance**. Any
surface built on those fields — a CSR account picker, a scoped user list — therefore reads the
INDEX as the effective permission model, not the table. Nothing marks the affected documents dirty
when the relation is written: not the impersonation verbs, not a `CacheInformationRefresh` of
`UserService`, and not an incremental index build. **After any write to
`AccessUserSecondaryRelation`, flush `UserService` AND run a Full build, then re-read the index
document:**

```
POST /Admin/Api/BuildIndex {"repository":"Users","indexName":"Users.index","buildName":"Full"}
```

Measured: fifteen group-level grants deleted through `UserImpersonateDelete` and verified row by row
in SQL, `UserService` flushed by verb, and the affected document still carried all fifteen grants
minutes later; one Full build reduced it to the single surviving grant, with no restart.

**Assert on the index document of the identity whose grant was REMOVED**, not only on the rendered
surface of the identity whose grant was kept. A set-equality sweep over what a picker renders for
the CSR is structurally blind to a stale grant on someone else's document — the CSR's own rows never
moved, so the proof written to catch scoping errors passes while the over-grant is still live.


## Cross-references

- [`permission-layers.md`](permission-layers.md) — §1-§5, the permission storage model.
- [`grant-mechanics.md`](grant-mechanics.md) — §7 the `PermissionSave` write surface, §13 the
  password escape hatch.
- [`page-gating.md`](page-gating.md) — §15, how a page gate resolves against the effective
  (impersonated) user.
- [`dc-scoping.md`](../../dw-commerce-b2b/references/dc-scoping.md) — DC user groups and the
  single-account-person shape.
- [`index-management.md`](../../dw-search-indexing/references/index-management.md) — `BuildIndex`
  and the repository / index naming the §17c rebuild uses.
