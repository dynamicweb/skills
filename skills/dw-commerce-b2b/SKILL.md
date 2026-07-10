---
name: dw-commerce-b2b
type: knowledge
group: commerce
description: 'Implement B2B patterns including customer groups, scoped assortments, and sales workflows. Triggers: B2B commerce, customer groups, DC scoping, CSR sales-on-behalf. Non-triggers: standard ecommerce -> dw-commerce-orders; product data -> dw-pim-modelling.'
---

# B2B Commerce Patterns

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
4. Customer uses the Customer Experience Center with `AcceptQuote` to convert to an order:

```
?CustomerCenterCmd=AcceptQuote&QuoteId={QuoteId}
```

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

Users sharing a **Customer Number** can see each other's orders in the Customer Experience Center.

User field: **User > Commerce tab > Customer Number**

CEC setting: **"Retrieve list based on: Own orders and orders from users with same customer number"** — enables company-wide order visibility.

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

## Pitfalls

**Assortment changes aren't live until rebuilt** — editors often add a product and wonder why customers can't see it. Always check rebuild status.

**Impersonation requires explicit configuration** — a user cannot impersonate by default; both the "can impersonate" and "can be impersonated by" sides must be configured.

**Quote flow vs order flow** — quotes and orders use separate flow configurations. A quote accepted via `AcceptQuote` enters the **order flow** at its default state, not the quote flow.

**Anonymous assortments** — if no assortment has the Anonymous flag, anonymous users see no products. For a mixed B2C/B2B store, ensure an anonymous-accessible assortment exists with the appropriate product scope.

## Next Steps

- **Setting up the checkout flow?** See [dw-commerce-orders](../dw-commerce-orders)
- **Product catalog and facets?** See [dw-commerce-catalog](../dw-commerce-catalog)
- **User account management?** See [dw-users-permissions](../dw-users-permissions)
- **ERP integration for customer/price sync?** See [dw-integration-erp](../dw-integration-erp)
