---
name: dw-data-audit-trail
type: flow
group: data
description: 'Investigate why something changed, who changed a record, when a value was set, or inspect version/history for any Dynamicweb 10 entity, using the Dynamicweb.Auditing subsystem and its AuditQuery filter. Triggers: "why did this change", "who changed this product/order/page", "when was this field set", inspect audit log or version history. Non-triggers: reverting or fixing the change itself (a separate write, not this skill); data-access/caching patterns -> dw-data-access.'
---

# Audit Trail Investigation

Use this when the question is about history — why something changed, who changed it, when a
value was set — for any Dynamicweb entity. This skill is **read-only**: if the investigation
concludes a write is needed (a revert, a fix), stop and propose that write as its own step —
never chain it onto an investigation.

## Domain anchor

The audit subsystem lives in `Dynamicweb.Auditing`. Each `Audit` event is keyed on:

- **`Type`** — the object type (e.g. `Product`, `Order`, `Page`).
- **`Id`** — the object ID (string).
- **`SubId`** — sub-entity within the object (e.g. a specific product field). Use this to
  scope to a single field's history.
- **`LanguageId`** — language layer the change applies to. A translation edit and a master
  edit are separate audit rows.
- **`UserId`**, **`Timestamp`** — who and when.
- **`Parent`** — parent object reference for nested entities.

Filter via `AuditQuery`: `Id`, `SubId`, `LanguageId`, `Parent`, `FreeText`, `StartTime`,
`EndTime`, plus `Ordering` and `TopNResults`. Many entities carry a denormalized
last-modified summary — cheaper to read first.

## MCP tools

- `get_audit_by_id` / `get_audits_by_ids` — read specific audit rows.
- `get_audits_by_query` / `count_audits_by_query` — filter with an `AuditQuery` shape (above).
- `get_audit_details` — the full detail of one audit event (old/new value where captured).
- `get_unique_audit_types` / `get_unique_audit_actions` — discover what `Type`/action values
  this solution's audit log actually contains, rather than guessing.
- `has_any_audits` — cheap existence check before paging a query that might return nothing.

## Establish the entity first

A "what changed" question without a concrete entity drifts. Resolve before reading history:

1. The entity type (`Type`).
2. Its `Id`.
3. The field or behavior the user thinks changed (this maps to `SubId`).
4. Roughly when (`StartTime` / `EndTime` window).

If the visible context already identifies the entity, use that. Otherwise ask one targeted
question rather than guessing.

## History sources, in order

1. **Last-modified on the entity** — many entities expose a denormalized last-modified
   summary. Cheapest signal; often answers "when" and "who" in one read.
2. **`AuditQuery` against the audit subsystem** — filter by `Type` + `Id` + time window. Add
   `SubId` to narrow to a specific field. Add `LanguageId` to separate translation edits from
   master edits.
3. **Version history** — pages and some commerce entities keep version snapshots. Compare
   adjacent versions for field-level diffs.
4. **Order / payment / shipment state history** — for orders, the order state ladder (see
   [dw-commerce-orders](../dw-commerce-orders)) is the history. Walk it before reading audit.
5. **Scheduled tasks / integration activities** — if a scheduled task or integration activity
   can write to the entity, check recent runs that touched it before blaming a user.
   System-driven writes can show up as a system/service account rather than a real person.

## Reporting

Lead with the answer, then evidence. "User Anna changed VAT on this product yesterday at
14:32 — audit row #4711." Do not present the audit log raw and ask the user to interpret it.

## Recovery is a separate step

If the user wants to revert a change, stop the diagnostic and propose the revert as its own
step. This skill is read-only — do not chain a revert onto an investigation request.

## Limits

- If audit logging is disabled in this installation, say so directly. The honest answer
  ("audit log is off, only signal is the entity's own last-modified field") beats a long
  fruitless search.
- A change attributed to a system/service account usually means an automated process ran —
  trace the scheduled task or integration activity rather than presenting that as the final
  answer.
