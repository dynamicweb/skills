---
name: dw-pim-workflow
type: knowledge
group: pim
description: 'Configure Dynamicweb 10 PIM workflows — named states, transitions, and editorial handoffs across the product enrichment lifecycle. Triggers: create a PIM workflow, define workflow states and transitions, set up manual editorial handoffs, configure state notifications. Non-triggers: completeness-driven automatic movement -> dw-pim-completeness; the Data Model schema -> dw-pim-modelling.'
---

# PIM Workflow

## What PIM Workflows Are

PIM workflows track the enrichment lifecycle of products through named states. They are used to coordinate editorial handoffs — for example: "Needs content" → "In review" → "Approved" → "Published".

There are two types:
1. **Manual workflows** — editors explicitly move products from one state to the next via an admin action
2. **Automatic workflows (completeness-driven)** — products move between queries automatically when their completeness score crosses a threshold (configured on the query, not on the workflow)

This skill covers manual workflows. See [dw-pim-completeness](../dw-pim-completeness) for the completeness-driven automatic approach.

## Creating a Workflow

Admin path: **Settings > Areas > Products > Productivity > Workflows**

1. Click **New workflow**
2. Provide a **name** (e.g., "Standard enrichment flow")
3. Save

The workflow is now a container for states.

Creating workflows or completion rules via MCP instead? See [references/completeness-and-workflows.md](references/completeness-and-workflows.md) for the `create_or_update_workflows` / `create_or_update_completeness` payload schemas.

## Workflow States

Each state represents a phase in the enrichment process. States are ordered and connected via transitions.

### Adding States

1. Click the workflow to open it
2. Click **+ Workflow state**
3. Provide a **name** (e.g., "Needs translation", "In review", "Approved")
4. Use the **Available states** selector to choose which states can come *after* this one (valid transitions)
5. Optionally configure notifications (see below)
6. Save

Repeat for all states in the workflow.

### State Transitions

The **Available states** field on each state controls where a product can move next. This is the transition graph:

- State "Needs translation" → Available states: "In review"
- State "In review" → Available states: "Approved", "Needs translation" (can send back)
- State "Approved" → Available states: (none, terminal state)

### Notifications per State

Each state has a **Notification tab**. Configure to send emails when a product enters this state:

1. Switch to the **Notification** tab
2. Set **Subject** (email subject line)
3. Select **Users** and/or **Groups** to notify
4. Select an **email template**
5. Set **Sender** and **Sender name**
6. Save

Notifications fire when any product is moved into this state. Useful for alerting translators, reviewers, or approvers.

## Assigning Workflows to Products

Workflows are not assigned to individual products directly. They are assigned at:

### Data model level

Open a Data Model → **Workflow tab** → select the workflow.

All products using this Data Model will have access to the workflow's states.

### Product group (channel) level

Open a product group → **Workflow tab** → select the workflow.

Products in this group will have access to the selected workflow.

When multiple assignments apply, the Data Model's workflow takes precedence.

## Moving Products Between States

### Single product

Open a product → find the **Workflow State** field → select a new state from the available options → Save.

### Bulk state change

In the product list:
1. Multi-select products
2. **Action menu → Change workflow state**
3. Select the target state
4. Confirm

Only states that are valid transitions from the current state appear as options.

### Via integration

Workflow state can be set during product import via the Integration Framework. Map the ERP or source field to the `ProductWorkflowState` destination field.

## Relationship Between Workflow States and Product Visibility

Workflow states in PIM are **editorial tracking only** — they do not directly control the `Active` flag or product visibility on the storefront.

To gate publishing behind a workflow state:
1. Use a product query filtered to "workflow state = Approved"
2. Run a scheduled task that sets products in this query to `Active = true`

Or configure the product index rebuild to fire after the workflow state changes.

## Workflow State Change Notification (Code)

The `Ecommerce.Product.ProductWorkflowStateChanged` notification fires when a product's workflow state changes:

```csharp
using Dynamicweb.Notifications;
using Dynamicweb.Ecommerce.Notifications;

[Subscribe(Ecommerce.Product.ProductWorkflowStateChanged)]
public class WorkflowStateChangedSubscriber : NotificationSubscriber
{
    public override void OnNotify(string notification, NotificationArgs args)
    {
        var typedArgs = (Ecommerce.Product.ProductWorkflowStateChangedArgs)args;
        var product = typedArgs.Product;
        var newState = typedArgs.WorkflowState;
        // React to state change
    }
}
```

## Pitfalls

**Workflow states don't enforce permissions** — any user with product edit access can change the workflow state to any available transition. Permissions are not enforced at the state level; they are enforced at the product or product group level.

**Workflow state ≠ product active** — moving a product to "Approved" does not make it live. You must separately manage the `Active` flag.

**State availability configuration required** — if "Available states" is left empty on a state, users cannot transition to any other state from it, making the product stuck. Always configure at least one outgoing transition (unless it's an intentional terminal state).

**Multiple workflows on one product** — if a product group and a data model both assign different workflows, behavior may be unexpected. Keep workflow assignment consistent — use either data model or group assignment, not both.

## Next Steps

- **Completeness-driven automatic workflows?** See [dw-pim-completeness](../dw-pim-completeness)
- **Product data structure?** See [dw-pim-modelling](../dw-pim-modelling)
- **Translating products with workflow states?** See [dw-pim-localization](../dw-pim-localization)
- **Reacting to state changes in code?** See [dw-extend-providers](../dw-extend-providers)
