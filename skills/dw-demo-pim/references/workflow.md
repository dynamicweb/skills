# workflow.md

> Demo routing for the Dynamicweb 10 product workflow. The platform knowledge — the five-table
> schema, the two attachment paths, the email-firing state-change subscriber, the verified
> per-state-role-gating gap, and the three workaround patterns — is vendor-generic and lives in
> [`../../dw-demo-base/references/foundational/pim-workflow.md`](../../dw-demo-base/references/foundational/pim-workflow.md).
> Read that first. This file holds only the demo-build delta. Loaded from `~/.claude/skills/dynamicweb-pim-demo/SKILL.md` "Where to find things" table.

## Platform knowledge → foundational candidate

Everything about *how DW10 workflow works* moved to
[`../../dw-demo-base/references/foundational/pim-workflow.md`](../../dw-demo-base/references/foundational/pim-workflow.md):

- §1 Schema — five tables (`Workflow`, `WorkflowState`, `WorkflowGoToState`, `WorkflowNotification`, `WorkflowStateNotificationRelation`) + the `ProductWorkflowStateId` / `GroupWorkflowId` FK columns.
- §2 Two attachment paths — group (`EcomGroups.GroupWorkflowId`, any GroupType) vs product (`EcomProducts.ProductWorkflowStateId`).
- §3 The state-change subscriber — emails fire from `ProductWorkflowStateChanged` with no custom C#.
- §4 Notification template path — `Files/Templates/PIM/Workflow Notifications/`.
- §5 The VERIFIED GAP — DW10 has no native per-state role gating.
- §6 Three workaround patterns (subscriber-reject / custom capability key / soft permission-aware gating) + the audit-log subscriber.

## Demo delta — wire one workflow for the PIM-first story

**Recommendation for PIM-first demos**: attach **one** workflow to the top-level DataModelFolder
(GroupType=1) under a `ShopType=4` DataStructure shop and let inheritance do the rest. That single
attachment is the key beat behind the PIM-first story — one workflow on the data-structure origin
drives state for every product under any descendant DataModel (GroupType=2), so the audience sees
governance flow from the single source of truth rather than from the publish side. The Channel
shops (`ShopType=3`) carry no workflow; they only hold publish-target relations. Per-product
override (direct `ProductWorkflowStateId`) is the per-record fallback you mention but don't lead
with.

For the demo's "approve / publish" beat, §6.3 (soft gating via permission-aware Dynamic Workspaces
+ dashboards) usually carries on its own — it relies entirely on the permission-entity grants the
persona matrix already needs ([permissions-recipes.md](permissions-recipes.md)). Augment with §6.1
(subscriber-reject) only when the demo specifically calls out "what stops a malicious user from
bypassing?".

## Cross-references

- **Platform workflow knowledge** — [`../../dw-demo-base/references/foundational/pim-workflow.md`](../../dw-demo-base/references/foundational/pim-workflow.md).
- **Permissions (persona grants)** — [permissions-recipes.md](permissions-recipes.md); model concept in [permissions-model.md](permissions-model.md).
- **Setup order** — the workflow step sits in [canonical-setup-order.md](canonical-setup-order.md) (PIM-first §0.B step 12; the DataModelFolder attachment is the recommended shape there).
- **Cache invalidation** — [cache-invalidation.md](cache-invalidation.md): use `WorkflowStateService.Save` (fires the notification), not raw `UPDATE EcomProducts SET ProductWorkflowStateId`.
