# permissions-recipes.md

> **Demo persona → permission-grant mapping for a Dynamicweb 10 PIM demo.** This file owns only the
> *application* of the permission model to demo personas — the abstract role matrix and how each role
> maps to Layer B (capability) + Layer C (entity) grants. The underlying **generic grant mechanics**
> (`PermissionLevel` bit values, the functional-view entity-type checklist, the Read→Edit action-button
> bump, the field-editability dual-gate, the per-role field-level differentiation SQL technique, and the
> plaintext-password escape hatch) are vendor-generic and live in
> [`../../dw-demo-base/references/foundational/users-permissions.md`](../../dw-demo-base/references/foundational/users-permissions.md)
> §7–§13. The three-layer **concept** lives in the same candidate (§1–§6); the demo-routing note is in
> [`permissions-model.md`](permissions-model.md). Loaded from `dw-demo-pim/SKILL.md` "Where to find
> things" table.
>
> All recipes assume direct SQL on the permission tables (the admin UI does not expose them for the
> resources these touch — candidate §4c). After any insert/update, flush caches per the
> [`cache-invalidation.md`](cache-invalidation.md) permission rows. Never verify a persona logged in as
> Angel / BuiltInAdmin / Administrator — those bypass every check (candidate §6); always test as a
> Default-type user in the target group.

## Persona role matrix — the demo's application of the model

A PIM demo's role roster is project-specific. This file does NOT prescribe customer role names — use
customer-specific roles only after the customer-context PDF has been read (per the
[`../../dw-demo-base/references/customer-context.md`](../../dw-demo-base/references/customer-context.md)
read-only contract). For demo-skill purposes, map abstract personas to grants:

| Persona | Layer B (capabilities — UI visibility) | Layer C (entity — actions) | Demo beat |
|---|---|---|---|
| **Editor** | `/Products` Read; `/Products/AllProducts` Edit; `/Products/DynamicWorkspaces` Read | Catalog Groups: Edit. Channel Groups: Read (sees what's published; can't directly attach) | Day-to-day product enrichment. |
| **Reviewer** | Same as Editor + `/Products/DynamicWorkspaces` Edit (sees the review workspace) | Catalog Groups: Edit. Channel Groups: Read. | Approves products in workflow; see [`workflow.md`](workflow.md) for the per-state gating gap. |
| **Publisher** | Same as Reviewer + `/Products/Channels` Edit; `/Products/Feeds` Read | All Groups (catalog + channel): Edit | Fires the "Publish to channel" action (see [`structural-model.md`](structural-model.md) §2.3a). |
| **Admin** | `/Products` All; sibling areas All | All entities All | Override for setup, governance audits, and recovery. |

The matrix assumes the `CapabilityControlFeature` flag is ON (candidate §1). If the flag is OFF,
collapse the Layer B / Layer C distinction: grant Layer C only (entity grants cascade up).

> Concrete role names (e.g. "Product Manager", "Procurement", "Approver", "Merchandiser", "Category
> Manager") are project-specific and belong in the customer's `notes/` or `CLAUDE.md` — not in this
> skill. The customer-context PDF is the source.

## How to seed these personas (mechanics → candidate)

Each persona row above is realised by applying the generic mechanics in the candidate, in this order:

1. **Make every persona group functional** — apply the functional-view entity-type checklist (candidate §8): grants on all five entity types (Section / Shop / ProductGroup / ProductField / File). Skipping the ProductField or File grants leaves visible-but-empty trees and blank product-list columns.
2. **Surface action buttons for the roles that act** — bump the gating entity grants from Read (4) to Edit (20) per the Read→Edit recipe (candidate §9). For the persona matrix that means: Editor/Reviewer/Publisher get their catalog-group grants bumped; Publisher additionally gets channel-group grants bumped.
3. **Unlock field editing** — apply the dual-gate fix (candidate §10): grant `Language` Edit alongside the `ProductField` Edit, or every field renders readonly.
4. **Differentiate the personas visibly** — use the per-role field-level differentiation technique (candidate §11) to downgrade the fields each persona does NOT own back to Read. This is what makes the Editor and the Reviewer see two visually-different Edit screens for the same product — the field-level-security beat.
5. **Hide sections per persona** — insert `CapabilityLimitation` rows for the capability keys a persona should not see (candidate §12). E.g. hide `/Products/Feeds` from the Editor while keeping `/Products/AllProducts`.
6. **Pin each persona's landing dashboard** — one `DashboardAccessUserRelation` `Default=1` row per persona-user pair (candidate §12 / §4b).
7. **Seed the persona logins** — if MCP/admin-UI password seeding isn't available, use the plaintext-password escape hatch (candidate §13) after verifying `EncryptPassword=False`.

`PermissionLevel` bit values used throughout (`None=1, Read=4, Edit=20, Create=84, Delete=340,
All=1364`) are in candidate §7.
