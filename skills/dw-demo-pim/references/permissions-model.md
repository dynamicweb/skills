# permissions-model.md

> **The three-layer DW10 permission model is vendor-generic platform knowledge — it now lives in the
> foundational candidate [`../../dw-demo-base/references/foundational/users-permissions.md`](../../dw-demo-base/references/foundational/users-permissions.md).**
> Read that for the `CapabilityControlFeature` flag (DW10.21+, default OFF) and its decision rubric,
> Layer A `UnifiedPermission`, Layer B `CapabilityLimitation` + capability-key registry, Layer C
> entity-level permissions + entity registry, `DashboardAccessUserRelation` pinning, the admin-UI
> exposure gap + cache-flush, the admin bypass, and the unified picture. Loaded from
> `dw-demo-pim/SKILL.md` "Where to find things" table.
>
> **This demo file owns only the routing + cross-cutting placement.** The grant-seeding recipes
> *as applied to demo personas* live in [`permissions-recipes.md`](permissions-recipes.md); the
> generic grant mechanics they build on live in the candidate.

## What lives where

| You need… | Read |
|---|---|
| The three-layer model — flag, tables, entity registry, admin bypass, cache flush | [`../../dw-demo-base/references/foundational/users-permissions.md`](../../dw-demo-base/references/foundational/users-permissions.md) |
| Generic grant mechanics — `PermissionLevel` bits, functional-view checklist, Read→Edit bump, dual-gate, field-level differentiation technique, plaintext-password hatch | same candidate, §7–§13 |
| Demo persona → grant mapping (Editor / Reviewer / Publisher / Admin) | [`permissions-recipes.md`](permissions-recipes.md) |
| Render-time permissions (storefront `Page` / `Paragraph`) | [`../../dw-demo-base/references/foundational/users-permissions.md`](../../dw-demo-base/references/foundational/users-permissions.md) §15 |

## Cross-cutting placement note (demo-routing)

Permissions touch every demo surface — PIM, the Swift frontend, ERP integration, and Business Central
potentially. The vendor-generic model is therefore staged in `dw-demo-base`'s foundational area so all
sister demo skills point at one copy. The candidate's §15 owns the **render-time** half (the
entity-store rows — `UnifiedPermission`, `PermissionName='Page'` — read on every page/paragraph
render), routed to from the Swift demo's `dw10-canonical-surfaces.md`. This demo skill's permission story (the persona matrix) lives
in [`permissions-recipes.md`](permissions-recipes.md).

For a PIM demo: decide the `CapabilityControlFeature` flag (candidate §1) BEFORE granting anything —
two different role matrices follow from the two settings, and toggling mid-build strands every grant
already made. Showcasing the modern orthogonal model to a PIM-selection committee means flag ON; the
legacy "Edit on Products = Edit everywhere" mental model means flag OFF.
