# workflow.md

> Dynamicweb 10 has a real product-workflow engine. Tables, state graph, the email-firing subscriber, the verified gap (no native per-state role gating), and three workaround patterns for role-based transitions. Read this BEFORE building any "approve / publish" demo story â€” most of the moving parts are already wired and you only need data, not C#. Loaded from `~/.claude/skills/dynamicweb-pim-demo/SKILL.md` "Where to find things" table.
>
> **Cross-cutting placement note.** Same placement note as [`permissions-model.md`](permissions-model.md): this ref sits at PIM-skill level. Workflow concerns touch PIM and the Swift frontend (the approver UI is a CMS surface; the audit log can drive content) and integrations (ERP push fires off state changes). If cross-cutting use materialises across more than two sibling skills, consider promoting to a future `dynamicweb-platform-demo` sibling. For now: here.

## 1. Schema â€” five tables, two foreign-key columns

Source: `dw10source/src/Core/Dynamicweb.Core/Security/Workflows/` (verified 2026-05-21). Class files present: `Workflow.cs`, `WorkflowState.cs`, `WorkflowStateRepository.cs`, `WorkflowNotification.cs`, `WorkflowNotificationRepository.cs`, `WorkflowRepository.cs`, `WorkflowService.cs`, `WorkflowNotificationService.cs`, `WorkflowStateService.cs`, `WorkflowUsage.cs`. No `WorkflowGoToState.cs` file â€” the table is read/written directly from `WorkflowStateRepository.cs` (lines 41-77 via `GetGoToStates` / `SetGoToStates`) and the schema can only be cited by symbol + the SQL strings in that repository.

| Table | Columns | Purpose |
|---|---|---|
| `Workflow` | `WorkflowId`, `WorkflowName`, `WorkflowCreated` | A named workflow (e.g. "Product Lifecycle"). |
| `WorkflowState` | `WorkflowStateId`, `WorkflowStateWorkflowId`, `WorkflowStateName` | The states (Draft / Pending approval / Approved / Active / Offline / etc.). **Three columns only** â€” verified by reading `WorkflowState.cs` (3 properties: `Id`, `WorkflowId`, `Name`) and `WorkflowStateRepository.ExtractWorkflowState` extracts only those three. See Â§5 for why this matters. |
| `WorkflowGoToState` | `WorkflowGoToStateStateId`, `WorkflowGoToStateGoToStateId` | Allowed transitions (directed graph). Each row says "from state A you may move to state B". **Two columns only.** Schema cited by SQL strings in `WorkflowStateRepository.cs:48-50, 65, 71, 97-98` â€” there is no model class for this table. |
| `WorkflowNotification` | `Id`, `WorkflowId`, `Subject`, `Sender`, `SenderName`, `Template`, `Users` | Email-notification config. `Users` is a comma-separated list of recipient user / user-group ids â€” **recipients, not transitioners** (Â§5). Verified in `WorkflowNotification.cs:41`. |
| `WorkflowStateNotificationRelation` | `WorkflowStateNotificationRelationStateId`, `WorkflowStateNotificationRelationNotificationId` | Which notifications fire on entering which state. Schema cited by SQL strings in `WorkflowNotificationRepository.cs:28-29, 43, 53, 82` â€” no model class. |
| `EcomProducts.ProductWorkflowStateId` | int | **Current state per product** (per language row). Zero = no workflow active. |
| `EcomGroups.GroupWorkflowId` | int | Workflow assigned to a group â†’ products under that group inherit. |

State transitions are **graph-defined, not linear**: `WorkflowGoToState` rows say "from state A you may move to states {B, C, F}". So "Pending Approval â†’ Approved" and "Pending Approval â†’ Returned to Draft" are two separate `WorkflowGoToState` rows.

## 2. Two attachment paths â€” group OR product

A workflow can be attached two ways:

1. **Via a group** â€” `EcomGroups.GroupWorkflowId`. The column is on `EcomGroups` and applies **regardless of `GroupType`**. So it works on catalog groups (GroupType=0), DataModelFolder (GroupType=1), AND DataModel (GroupType=2) groups equally. Products inherit via their group relations. The enumerator query is in `WorkflowServiceExtensions.cs` line 24 (in method `GetWorkflowsInUseByGroups`, body lines 15-34):
   ```sql
   SELECT g.GroupWorkflowId AS id FROM EcomGroups g WHERE g.GroupWorkflowId > 0
   ```
   **No GroupType filter in the query** â€” every group type is eligible. Cite by symbol: `WorkflowServiceExtensions.GetWorkflowsInUseByGroups`.
2. **Direct on a product** â€” `EcomProducts.ProductWorkflowStateId` set to a `WorkflowStateId` whose parent workflow you want active. Enumerator: `WorkflowServiceExtensions.GetWorkflowsInUseByProducts` (line 40, body 40-59).

**Recommendation for PIM-first demos**: attach **one** workflow to the top-level DataModelFolder under a `ShopType=4` DataStructure shop and let inheritance do the rest. Per-product override (direct attachment) is the per-record fallback. The Channel shops (`ShopType=3`) carry no workflow â€” they only hold publish-target relations.

This is the key fact behind the PIM-first story: a DataModelFolder (GroupType=1) can drive workflow state for every product under any descendant DataModel (GroupType=2). The workflow lives on the *origin* side (data structure), not on the publish side (channels).

## 3. The state-change subscriber â€” emails fire from state changes

Source: `dw10source/src/Features/Ecommerce/Dynamicweb.Ecommerce/Products/ProductWorkflowStateChangedSubscriber.cs` (verified 2026-05-21).

The subscriber wires `Notifications.Ecommerce.Product.ProductWorkflowStateChanged` to email sending:

1. On `OnNotify` (line 40), looks up the new `WorkflowState` (line 47).
2. Looks up all `WorkflowNotification`s related to that state via `WorkflowNotificationService.GetByState(state)` (line 51) â€” this resolves the `WorkflowStateNotificationRelation` rows.
3. For each notification, calls `SendEmailNotification` (line 58) which:
   - Loads the recipients from `notification.Users` via `notificationService.GetRecipients(notification)` (line 66).
   - Loads the template via `GetTemplate(notification)` (line 88).
   - Sends the mail to each recipient with a valid email address.

**Template path**: `Files/Templates/PIM/Workflow Notifications/<filename>.cshtml` â€” confirmed at `ProductWorkflowStateChangedSubscriber.cs:92` (`TemplateHelper.GetTemplatePath(notification.Template, "PIM/Workflow Notifications")`).

Default template ships at `DefaultTemplates/WorkflowNotificationTemplate.cshtml` â€” used when `notification.Template` is blank (line 90-97 fallback to `DefaultTemplate.WorkflowNotification.Value`).

Tags available in the template (per the notification args + standard product rendering):
- `ProductWorkflowStateChanged:Product.Link` â€” deep-links into the admin product overview
- `ProductWorkflowStateChanged:Workflow.Name`
- `ProductWorkflowStateChanged:PreviousState.Name`, `:CurrentState.Name`
- `ProductWorkflowStateChanged:Date`
- All standard product tags via `RenderProduct`
- User tags: `UserName`, `UserFirstName`, `UserLastName`, `UserFullName`

This **directly delivers "PIM sends notification email on state change"** with no custom C#. You need only data: a workflow row, state rows, a notification row, a relation row. No `NotificationSubscriber.cs` to write.

## 4. Notification template path

Same as Â§3: `wwwroot/Files/Templates/PIM/Workflow Notifications/<filename>.cshtml`. To customise per state, ship one Razor file per notification entry and set `WorkflowNotification.Template` to its filename (relative to the `PIM/Workflow Notifications/` root). Templates are plain Razor with the `ProductWorkflowStateChanged:*` tag set above.

> If you blank out `WorkflowNotification.Template`, the default ships from `DefaultTemplates/WorkflowNotificationTemplate.cshtml` baked into `Dynamicweb.Ecommerce.dll`. For a "no-custom-files" demo, use the default and seed only the data rows.

## 5. VERIFIED GAP â€” DW10 workflow has NO per-state role gating

This is the one place DW10's workflow engine falls short of "out of the box for enterprise approval flows", and the gap is the same shape in every release as of 2026-05-21:

**Confirmed in source** (`$env:DW_VAULT/dw10source/src/Core/Dynamicweb.Core/Security/Workflows/`):

| Table | Columns | Role-aware? | Verification |
|---|---|---|---|
| `Workflow` | Id, Name, Created | No | `Workflow.cs` â€” 3 properties. |
| `WorkflowState` | Id, WorkflowId, Name | **No** | `WorkflowState.cs` â€” exactly three properties (`Id`, `WorkflowId`, `Name`); no Users / Roles / Permission column. `WorkflowStateRepository.ExtractWorkflowState` (lines 183-191) reads only these three columns from `SELECT * FROM WorkflowState`. |
| `WorkflowGoToState` | StateId, GoToStateId | **No** | Schema visible only in SQL strings (`WorkflowStateRepository.cs:71-72`); the INSERT writes exactly two columns. Only defines which transitions are *valid*, not who can fire them. |
| `WorkflowNotification` | Id, WorkflowId, Subject, Sender, SenderName, Template, **Users** | The `Users` field is **recipients of notification emails, not who-can-transition** | `WorkflowNotification.cs:41` declares `public string Users`; `ProductWorkflowStateChangedSubscriber.cs:66` uses it as `GetRecipients(notification)`. The field name is misleading; it does not gate transitions. |
| `WorkflowStateNotificationRelation` | StateId, NotificationId | No | Pairs notifications to states for emailing only. |

**Practical consequence**: in DW10, **any user with `PermissionLevel.Edit` on a product can pick any next state listed in `WorkflowGoToState`**. The valid-transitions graph is structural; *who can fire each arrow* is open. There is no native column, no native API, and no native UI for restricting transitions by role / user group.

If a demo (or production setup) needs "only Reviewers may move Pending Approval â†’ Approved", the gate **must live outside the workflow tables**. See Â§6 for the three workaround patterns.

## 6. Three workaround patterns for per-state role gating

In increasing fidelity. Pick one or compose â€” they layer.

### 6.1 Subscriber-reject (`Notifications.Ecommerce.Product.BeforeSave`)

A custom `NotificationSubscriber` on `Product.BeforeSave` (or on `ProductWorkflowStateChanged` if you want to reject post-decision rather than at-save). The subscriber:

1. Reads the proposed new `ProductWorkflowStateId` from the save args.
2. Looks up which AccessUserGroup is allowed to move INTO that state (config lives in a small custom table OR a JSON config file under `Files/System/` â€” no schema change needed).
3. If the current user (from `args.User` or `Pageview.User`) is not a member of the allowed group, throws â€” which cancels the save.

Single `.cs` file. Ships under the "NotificationSubscriber" customisation budget (per [`dynamicweb-demo-base/references/customisations.md`](../../dw-demo-base/references/customisations.md)) â€” not a preflight-blocked surface. Compose with Â§6.2 / Â§6.3 for UI gating.

**Strength**: backend-enforced â€” even MCP / raw API can't bypass.
**Weakness**: error surfacing is generic (admin sees "save failed"); UI still shows the dropdown options. Use with Â§6.2 if dropdown noise matters.

### 6.2 Custom capability key + permission-gated action

Wire a custom "Approve" / "Publish" button to a dedicated capability key (e.g. `/Products/Workflow/Approve`) with `PermissionLevelRequired = PermissionLevel.Create`. This is the same pattern the native "Publish to channel" action uses (`ProductListScreen.cs:726-743`, verified 2026-05-21; there is also a duplicate inline-form "Publish to channel" at line 372, and the bulk-action wiring is at line 420).

Layer B (capability) hides the button entirely from non-approvers (see [`permissions-model.md`](permissions-model.md) Â§3 for the capability tree). When the button isn't rendered, the user can't even attempt the transition.

**Strength**: clean UI â€” non-approvers literally don't see Approve. Aligns with the modern DW10 permission model (flag ON).
**Weakness**: more code (a custom `ActionNode` and screen wiring); doesn't prevent raw API / MCP transitions on its own â€” compose with Â§6.1 for hard enforcement.

### 6.3 Soft gating via permission-aware surfaces

The lowest-fidelity option but cheapest to set up. Lean on Layer C entity permissions ([`permissions-model.md`](permissions-model.md) Â§4) on **Dynamic Workspaces** and **dashboards**:

- The "Pending approval" workspace is a `DynamicStructure` entity with `PermissionName="DynamicStructure"`, key = its Guid (`DynamicStructure.cs:43`). Grant Read on it only to the Reviewer/Approver group. Non-approvers don't see the surface at all.
- The Reviewer dashboard (showing the pending-approval queue widget) is its own `Dashboard` row â€” same Layer C grants gate it.
- The "Approve" button only renders inside those surfaces. A user without dashboard-read can't reach the button.

State-aware action visibility: the custom button checks (a) is the current state Pending approval, AND (b) does the user have permission to see this surface. If either fails, the button doesn't render. So even if an editor navigates to a Draft product through `/Products/AllProducts`, they don't see Approve (no-op transition).

**Strength**: zero custom subscribers; relies entirely on permission-entity grants you'd write anyway.
**Weakness**: pure UI gating â€” a determined user with raw MCP access could still fire any transition. Acceptable for demos where the audience cares about UI gating, not API-level enforcement; pair with an audit log subscriber to catch out-of-band transitions.

### 6.4 Composition rule

For a production-grade flow: 6.1 (backend enforcement) + 6.2 (clean UI) + 6.3 (permission-scoped surfaces) all stacked. For a demo: 6.3 alone usually carries â€” augment with 6.1 if the demo specifically calls out "what stops a malicious user from bypassing?".

In all three workarounds, **add the audit-log subscriber** anyway: a `NotificationSubscriber` on `ProductWorkflowStateChanged` that writes every transition (user, from-state, to-state, timestamp, optional comment) to a custom `ProductWorkflowAudit` table. Accountability is independent of prevention; one `.cs` file delivers it.

## 7. Cross-references

- **Permissions** â€” [`permissions-model.md`](permissions-model.md). All three Â§6 workarounds build on Layer B and Layer C grants from that ref.
- **Render-time permissions** (Page / Paragraph gating in storefront) â€” [`dynamicweb-swift-demo/references/dw10-canonical-surfaces.md`](../../dw-demo-swift/references/dw10-canonical-surfaces.md) Â§"Permissions â€” the entity store". Different table (`Permission`, not `UnifiedPermission`), different lookup. Don't confuse â€” `UnifiedPermission` gates ADMIN actions (the focus of this ref); `Permission` gates STOREFRONT renders.
- **Customisations budget** â€” [`dynamicweb-demo-base/references/customisations.md`](../../dw-demo-base/references/customisations.md). `NotificationSubscriber` and scheduled-task surfaces are NOT in the preflight glob â€” Â§6.1 and the audit-log subscriber ship unprompted.
- **Cache invalidation** â€” [`cache-invalidation.md`](cache-invalidation.md). State transitions via `WorkflowStateService.Save` go through the domain service and invalidate caches inline; raw `UPDATE EcomProducts SET ProductWorkflowStateId = â€¦` does NOT fire the `ProductWorkflowStateChanged` notification at all (so emails won't fire either) â€” use the service, not raw SQL.

Source-citation line numbers re-verified against `$env:DW_VAULT/dw10source/` on 2026-05-21.


