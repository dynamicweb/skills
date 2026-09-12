---
name: dw-commerce-b2b
type: knowledge
group: commerce
mcp: optional
dynamo: true
description: 'Implement B2B patterns including customer groups, scoped assortments, and sales workflows, and set up or rebuild a customer assortment through the MCP tools. Triggers: B2B commerce, customer groups, DC scoping, CSR sales-on-behalf, create/build a customer assortment, assortment rebuild not taking effect. Non-triggers: standard ecommerce -> dw-commerce-orders; product data -> dw-pim-modelling.'
---

# B2B Commerce Patterns

## Without MCP

The knowledge here stands alone; the Dynamicweb MCP tools it names are the way to apply it, and
in-product they are the only way — the MCP tool set plus read/write under `Files/` is the whole
surface these steps may use. When no tool covers the operation, **stop and tell the user**, naming
the admin screen that performs it, rather than substituting a guessed HTTP call, a file edit
outside `Files/`, or SQL. The Management API, the serializer and direct SQL exist only outside the
product, are never a step in this skill, and are owned by
[`dw-data-access`](../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance".

## Assortments

Assortments scope which products a customer (or user group) can see and buy. They are the primary mechanism for B2B product visibility control.

### Activating Assortments

**Settings > Products > Advanced > Ecommerce & Channels > Assortments > Enable assortments**

Once enabled, logged-in users only see products that belong to their assortment(s). Users with no assortment assigned see nothing (unless an assortment has the **Anonymous** flag set, which applies to non-logged-in users).

### Creating an Assortment

Admin path: **Products > Customer Assortments** (moved from Commerce to Products in v10.22)

1. Click **New Assortment**
2. Set Name, optional Number (for integration/ERP reference), and Active state
3. Configure Availability settings (Include sub groups, Anonymous flag)
4. Use the **Widgets** to add content:

| Widget | Function |
|--------|---------|
| Shops | Restrict assortment to specific shops |
| Product groups | Add entire product groups |
| Products | Add individual products (can be set **Excluded** for "all except" patterns) |
| User groups | Assign assortment to user groups |
| Users | Assign assortment to individual users |

### Assortment Rebuild

Changes go live only **after a rebuild**. Three rebuild triggers:
1. **Scheduled task** — "Build Ecommerce Assortment Items" (recommended; set to run frequently)
2. **Manual** — from the assortment list via Actions menu or context menu
3. **Flag-based** — setting `AssortmentRebuildRequired = true` in code marks the assortment for rebuild on the next scheduled run

### Setting Up an Assortment via MCP Tools

| Intent | Tool |
|---|---|
| List existing assortments | `get_assortments` |
| Create / rename / activate an assortment | `save_assortments` |
| Add products to an assortment | `assign_products_to_assortment` |
| Add whole product groups | `assign_groups_to_assortment` |
| Scope to one or more shops | `assign_shops_to_assortment` |
| Grant a user/group access | `assign_permissions_to_assortment` |
| Inspect what a user can see | `get_assortment_ids_by_user`, `get_assortment_permissions_by_user`, `check_assortment_product_access` |
| Inspect current relations | `get_assortment_relations`, `get_assortment_relations_by_group_id`, `get_assortment_relations_by_product_id`, `get_assortment_relations_by_shop_id` |
| Mark for rebuild without building now | `flag_assortments_for_rebuild` — body is `{"requests":[{"assortmentId":"<id>"}, …]}` |
| Rebuild now | `build_assortments` — same `{"requests":[{"assortmentId":"<id>"}, …]}` shape |
| Find what still needs building | `get_assortments_for_build` |

Removal mirrors each assign tool (`remove_products_from_assortment`,
`remove_groups_from_assortment`, etc.).

**`flag_assortments_for_rebuild` and `build_assortments` take an ARRAY OF REQUEST OBJECTS**, each
carrying one `assortmentId` — not the flat `{"assortmentIds":["…"]}` that reads naturally from the
tool name. The flat shape fails with the bare `An error occurred invoking '<tool>'.`, which names
no argument and does not distinguish a wrong shape from a wrong id.

**Setting `EcomAssortment.AssortmentRebuildRequired` in SQL does not reach the builder.**
`AssortmentService.GetAssortmentsForBuild()` reads an in-process cache, and no public flush exists
for it, so a correct SQL `UPDATE` leaves `get_assortments_for_build` returning `[]` while the rows
on disk are flagged — a scheduled SQL flagger would report success nightly and rebuild nothing.
Flag through `flag_assortments_for_rebuild` (or, in code, `AssortmentService`'s typed
`FlagAssortmentForRebuild(Assortment)`, which needs a small add-in because it takes a typed
`Assortment` and the untyped scheduled-task add-ins cannot construct one). SQL stays a read path
here.

Standard flow: **create** (`save_assortments`, active) → **fill** (`assign_products_to_assortment`
and/or `assign_groups_to_assortment` — group membership is dynamic, so products later added to
an assigned group are included on the next build) → **grant access**
(`assign_permissions_to_assortment` — an assortment with no permissions and `AllowAnonymousUsers`
off is visible to nobody) → **build** (`build_assortments` — until this runs, none of the above is
live; use `get_assortments_for_build` to confirm nothing is left pending) → **wire the storefront**
(on a query-driven site, confirm the catalog page's index query filters on `AssortmentIDs` —
see [dw-search-indexing](../dw-search-indexing); an assortment can be built and still leave the
storefront unfiltered if the query doesn't reference it) → **verify** (read the membership, below).

**A shop relation means the WHOLE shop, so it is not part of a restricted-assortment recipe, and
`check_assortment_product_access` proves nothing.** Both traps are silent, both survive every
prescribed verification, and one of them is unrepairable in place — the detail, the measurements and
the membership read that replaces the access check are in
[references/dc-scoping.md](references/dc-scoping.md) "A shop relation is a union, not a filter".

**The rebuild step is the #1 footgun via MCP too.** `flag_assortments_for_rebuild` only
**marks** assortments dirty; it does not build them. `build_assortments` does the actual work
and may run asynchronously. Never report an assortment as ready right after an assign call —
it is not, until a build completes.

**A membership write does not flag anything.** `assign_products_to_assortment` /
`remove_products_from_assortment` write `EcomAssortmentProductRelations` and leave
`AssortmentRebuildRequired` false and `AssortmentLastBuildDate` unchanged — relation writes and the
rebuild flag are independent operations in the underlying service, and the assign call gives no
signal either way. **Follow every membership batch with an explicit `flag_assortments_for_rebuild`
plus `build_assortments`**, then assert the new membership on `get_assortment` or a storefront
catalogue count. Without it the nightly builder never picks the change up.

**Count the built items before activating a segment assortment.** An assortment bound to a PIM
data-model group (a data-model or data-model-folder group, not a catalogue group) carries no
`EcomGroupProductRelation` rows and builds to ZERO items — and activating a zero-item assortment
does not "add nothing", it takes the whole catalogue away from everyone who holds it, because a
holder's visible set becomes the empty intersection. Run `build_assortments` and check the
assortment's item count is non-zero as the pre-flight for switching `Active` on.

**Enabling assortments prunes live carts, silently.** Once `UseAssortments` is on, the cart is
re-evaluated on every load and order lines whose product is outside the buyer's assortment set are
removed with no message and no log entry, recalculating the total; re-adding the line and loading
the cart again removes it again. Completed orders are untouched — only live carts. So a seeded
demo cart can quietly lose lines the first time a buyer opens it: check every seeded cart line
against the owner's assortment range before enabling the feature, and give the product stock in the
right location or reseed the line with an in-range SKU rather than fighting the pruning.

**Check `EcomAssortmentGroupRelations` before removing or detaching any product group — even while
assortments are disabled.** `UseAssortments = False` means a broken assortment-group relation
produces no error and no symptom until the feature is switched on, so a group that inventory work
has labelled a duplicate legacy tree can be load-bearing for several assortments. Run
`get_assortment_relations_by_group_id` (or the equivalent `SELECT`) for every group being removed
and require zero rows, unconditionally.

**Anonymous access.** If the catalog should be visible to not-signed-in visitors, the
assortment needs anonymous access enabled (`get_allow_anonymous_users_assortment_ids` shows
which currently allow it). Otherwise anonymous storefront visitors see an empty catalog — a
common "all products disappeared" report after enabling assortments.

## Impersonation (CSR Sales-on-Behalf)

Impersonation lets a sales rep (CSR) log in and operate as a customer — seeing their prices, assortments, cart, and account data.

### Setup

On the individual sales rep user: **Edit user > Impersonation tab**

- **Can impersonate:** which users/groups this CSR can impersonate
- **Can be impersonated by:** which users/groups can impersonate this user

### Frontend Flow

1. CSR logs in via Extranet
2. Selects a customer to impersonate
3. The site now shows prices, assortments, and data for that customer
4. The CSR can place orders on behalf of the customer

### Impersonation API

```csharp
using Dynamicweb.Security.UserManagement;

// Get impersonatable users for the current CSR
var impersonatable = UserContext.Current.GetImpersonatableUsers();

// Check if currently impersonating
var impersonating = UserContext.Current.ImpersonatingUser;
bool isImpersonating = impersonating != null;
```

### Impersonation-Required Cart Commands

The `setdiscount` cart command requires the current user to have impersonation rights:

```html
<input name="CartCmd" value="setdiscount" />
<input name="OrderDiscountPercentage" value="10" />
```

The `copy` command's `CartUserId` must be either the current user or an impersonatable user.

## Quote Workflows

Quote flows support B2B quotation processes where customers request pricing before committing to an order.

### Setup

**Settings > Areas > Commerce > Order Management > Quote Flows**

Structure: Quote Flow → Quote States. Each state has:
- Name, Description, Color
- **Default** flag (initial state for new quotes)
- **Allow order** — whether an order can be created from this state
- **Allow edit** — whether the customer can modify the quote from the frontend
- Notification emails
- State rules (which states can transition to/from this state)

### Quote Lifecycle

1. Customer creates a quote cart — Shopping Cart app must have **"Checkout to quote"** enabled
2. Submitted quote appears under **Commerce > Quotes**
3. Staff manages quotes through the quote flow states
4. Customer accepts the quote, converting it to an order. **The accept path is not the
   Customer Center command.** The shipped Swift 2 Accept-quote button and the
   `CustomerCenterCmd=QuoteAccept` command are both measured inert on a quote, so a quote beat
   scripted around either dies silently on stage. The working path, the measurement behind it and
   the one canonical command spelling are in
   [`dw-commerce-orders/references/order-states-and-quotes.md`](../dw-commerce-orders/references/order-states-and-quotes.md)
   "Swift 2's Accept-quote button cannot work on a quote". Read it before demoing this beat.

## Cart Flows (B2B Multi-Step Ordering)

Cart flows support B2B approval workflows (e.g., a buyer builds an order over multiple sessions, a manager approves before submission).

Admin path: **Settings > Commerce > Order Management > Cart Flows**

Same state structure as order flows and quote flows. Front-end state changes:

```html
<form method="post">
    <input name="CustomerCenterCmd" value="cartchangestate" />
    <input name="CartID" value="{CartID}" />
    <input name="StateId" value="{StateId}" />
</form>
```

**API for building cart flow UIs:**

```csharp
using Dynamicweb.Ecommerce.Orders;

var flows = OrderFlowService.GetFlowById(flowId);
var states = OrderStateService.GetStatesByFlow(flowId);
```

## Account Hierarchy (Company-Level Order Visibility)

Users sharing a **Customer Number** can see each other's orders, delivery addresses and favourites
lists in the Customer Experience Center.

User field: **User > Commerce tab > Customer Number**

CEC setting: **`RetrieveListBasedOn = UseCustomerNumber`** ("Own orders and orders from users with
same customer number") — enables company-wide visibility, and the same key drives the favourites
app.

**The customer number identifies the ACCOUNT, not the contact.** Every feature above compares it as
an exact string, so a per-contact suffix (a role suffix, a site suffix, an appended contact id)
turns all of them off while the settings still read back as enabled — see
[references/account-shape.md](references/account-shape.md) for the diagnostic query, the
group-scoped fallback and the recipe for normalising a suffix away.

**Integration tip:** Set the Customer Number from the ERP during user sync to link CRM accounts to Dynamicweb users.

## User Groups for B2B Access Control

User groups are the cross-cutting mechanism for B2B access control. Assign groups to control:

| Area | How groups are used |
|------|-------------------|
| Assortments | "User groups" widget on assortment |
| Payment methods | "Frontend groups" tab on payment method |
| Shipping methods | "Availability" tab on shipping method |
| Page access | Permission on page or page branch |
| Backend area access | Permission on admin area tree node |
| Price rules | Price lists in ecommerce price settings |

### Dynamic Group Membership

User groups support **segment search queries** on the Groups tab — users matching the query are dynamically added as members. Use for "all users with order count > 10" or "all users in country DE" membership rules.

## Deep reference

| Read it for | Reference |
|---|---|
| Distribution-center scoping internals: the DC-as-user-group pattern (one `AccessUserGroup` per DC composing Assortments, group prices and shipping availability), the stock-location join key, the three price scope columns and which one MCP `save_prices` reaches, contract-versus-list pricing per audience with no custom code, the `AccessUser` bulk-seeding schema, the admin Users tree filtering typed groups out of view, the verification flow, and when not to use the pattern | [references/dc-scoping.md](references/dc-scoping.md) |
| The customer number as the account key: what resolves "the same customer" by exact string match, what a per-contact suffix silently disables, the measured recipe for normalising one away, and account-wide favourites lists (impersonation plus `RetrieveListBasedOn = UseCustomerNumber`, and the `FavoriteCmd` vocabulary) | [references/account-shape.md](references/account-shape.md) |

## Pitfalls

**Assortment changes aren't live until rebuilt** — editors often add a product and wonder why customers can't see it. Always check rebuild status.

**Impersonation requires explicit configuration** — a user cannot impersonate by default; both the "can impersonate" and "can be impersonated by" sides must be configured.

**Quote flow vs order flow** — quotes and orders use separate flow configurations. An accepted quote enters the **order flow** at its default state, not the quote flow.

**Anonymous assortments** — if no assortment has the Anonymous flag, anonymous users see no products. For a mixed B2C/B2B store, ensure an anonymous-accessible assortment exists with the appropriate product scope.

## Next Steps

- **Setting up the checkout flow?** See [dw-commerce-orders](../dw-commerce-orders)
- **Product catalog and facets?** See [dw-commerce-catalog](../dw-commerce-catalog)
- **User account management?** See [dw-users-permissions](../dw-users-permissions)
- **ERP integration for customer/price sync?** See [dw-integration-erp](../dw-integration-erp)
