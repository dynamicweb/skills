---
name: dw-demo-pim
description: Dynamicweb 10 PIM modelling -- starts from a blank/fresh DB, building product data from scratch via MCP (no baseline deserialize). Triggers: modelling PIM data structures (shops vs channels, repositories/indexes, variants, BOM, categories, assortments, Dynamic Workspaces), choosing Storefront-first vs PIM-first setup order, fixing "completeness rules don't show", building PIM dashboards, GUID-collision errors in the Products tree, designing the product workflow / approval flow, designing the role/permission matrix for a PIM team, translating products into additional EcomLanguages, recovering from data-load mishaps or stale indexes, post-mutation cache invalidation. Non-triggers: setup/MCP/TLS issues -> dynamicweb-demo-base; storefront/content/re-skin -> dynamicweb-swift-demo; ERP -> dynamicweb-erp-demo. Use AFTER dynamicweb-demo-base (assumes MCP connected with >200 tools, vault resolved).
---

# Dynamicweb PIM Demo Skill

PIM modelling, structural mental model, governance, and recovery for Dynamicweb 10 demo builds. **Use AFTER** `dynamicweb-demo-base` -- this skill assumes MCP is connected with >200 tools and `$env:DW_VAULT` resolves. If MCP isn't connected, fix that there first ([dynamicweb-demo-base/references/mcp-setup.md](../dw-demo-base/references/mcp-setup.md)).

**This skill starts from a blank/fresh DB.** PIM demos do NOT deserialize a content baseline â€” the modelling recipes here build product data from scratch via MCP. The Serializer install + Swift baseline deserialize live in `dynamicweb-demo-base` and `dynamicweb-swift-demo` respectively; see [`../dw-demo-swift/references/deserialize-flow.md`](../dw-demo-swift/references/deserialize-flow.md) only if a hybrid demo needs Swift content alongside the PIM model.

This SKILL.md is an orchestrator only. Each topic links to a `references/<topic>.md` that owns the verbatim recipe and gotchas.

## When to use this skill

Trigger shapes, one per thematic reference (the "Where to find things" table below is the router):

- Choosing the right access surface (MCP / Management API / SQL / filesystem) for a task.
- Modelling PIM data structures (shops vs channels vs data structures, GroupType, repositories+indexes, variants, BOM, channels+feeds, assets, product categories).
- Choosing and executing a setup order â€” Storefront-first vs PIM-first.
- Diagnosing "completeness rule doesn't show", building governance dashboards, recovering from missing seed rows or stale indexes (incl. GUID-collision errors in the Products -> Shared queries tree).
- Looking up the post-mutation cache flush for any surface.
- Designing the product workflow / approval flow (states, transitions, notifications).
- Designing the role/permission matrix for a PIM team.
- Seeding the role/permission grants for demo personas (SQL recipes).
- Translating products / groups / commerce objects into additional `EcomLanguages`.
- PIM-flavoured demo-storytelling tactics.

If the trigger is setup-shaped (host won't start, MCP empty, TLS handshake failing, vault not resolving), it belongs in `dynamicweb-demo-base`, not here. PIM-skill recipes assume the host is up and MCP returns >200 tools â€” but **NOT** that a content baseline has been deserialized. PIM demos start from a blank DB.

## Where to find things

Each reference is an independent file owned end-to-end by a single topic; cross-references between them are explicit.

| If you need to... | Read this reference |
|---|---|
| Pick the right access surface (MCP / API / SQL / FS) for a given task | references/access-surfaces.md |
| Understand the structural model (incl. Â§2.3a native "Publish to channel" action, Â§2.5a single-axis variants, Â§2.11 Pricing / `PriceQuantity>0` cart gotcha, Â§2.12 Dynamic Workspaces) | references/structural-model.md |
| Pick the right setup-order variant â€” Storefront-first or **PIM-first** (no `ShopType=1` shop, Dynamic Workspaces + workflow-driven) | references/canonical-setup-order.md (Â§0 decision matrix at top) |
| Diagnose "rules don't show", build dashboards, recover from missing seed rows or stale indexes | references/governance.md |
| Look up a post-mutation cache flush | references/cache-invalidation.md |
| Design the **DW10 product Workflow** (states, transitions, notifications) + work around the verified per-state-role-gating gap | **references/workflow.md** |
| Understand the **three-layer permission model** (UnifiedPermission + CapabilityControlFeature + entity-level) â€” concept, storage tables, flag decision, admin bypass | **references/permissions-model.md** |
| Seed the role/permission grants for demo personas (SQL recipes: role matrix, functional-view checklist, Readâ†’Edit bumps, field-level differentiation, dashboard pinning) | **references/permissions-recipes.md** |
| Find demo-storytelling tactics (governance flavour) | references/demo-storytelling.md |
| Translate products / groups / commerce objects into additional `EcomLanguages` (PIM side; sister doc is `dynamicweb-swift-demo/references/language-layers.md` for the content/area side) | references/localization.md |

## Demo philosophy â€” go deep, not wide

Inherited principle from [`dynamicweb-demo-base/SKILL.md` "Demo philosophy"](../dw-demo-base/SKILL.md). PIM-specific guardrails:

- **Shops + channels: 1 + 1.** One shop plus one channel. Pick the channel most relevant to the customer's pitch (B2B / retail / wholesale / marketplace â€” whichever the customer leads with). A second channel of equal weight is wasted demo time and dilutes the shop-vs-channel beat. Add it only when the customer's pitch is explicitly multi-channel (e.g. they sell B2B AND retail and want to see both in one platform). The shop-vs-channel concept itself is worth a single moment of pedagogy â€” one channel is enough to land it.
- **Locale: single home market.** Default to the customer's home market only (e.g. US-only with EN/USD/US-country for a US customer; DE/EUR/DE for a DACH customer). `references/canonical-setup-order.md` Steps 1-4 set this up. Add a second language/currency/country only when the customer's case explicitly demands it (e.g. they explicitly sell cross-border).
- **Product catalogue: deep AND wide â€” exception case.** Rich product data is the demo's substance, not its scaffolding. Go deep (variants on every relevant axis, BOM bundles, completeness rules that actually fire, assortments, facets that matter) AND wide (ample SKUs across categories) â€” both are cheap via MCP and make the storefront feel real. The "narrow it down" rule does not apply here. `canonical-setup-order.md` is calibrated for this â€” don't truncate the product-modelling steps to "save time".

When in doubt: every channel, locale, shop, country, currency, and language you add must justify itself against demo minutes. A product family does not need to justify itself.

## Inherited from dynamicweb-demo-base

This skill assumes `dynamicweb-demo-base` ran first. Four rules apply at all times and are NOT restated here -- see the owning reference in base for each:

| Rule | Owner |
|------|-------|
| `$env:DW_VAULT` path-resolution rule | [dynamicweb-demo-base/SKILL.md "Path-resolution rule"](../dw-demo-base/SKILL.md) |
| Customer-context read-only contract | [dynamicweb-demo-base/references/customer-context.md](../dw-demo-base/references/customer-context.md) |
| Customisations-ledger preflight | [dynamicweb-demo-base/references/customisations.md](../dw-demo-base/references/customisations.md) |
| Baseline-drift self-diagnosis rule | [dynamicweb-demo-base/SKILL.md "Self-diagnosis rule"](../dw-demo-base/SKILL.md) |

Runtime enforcement: the per-demo `CLAUDE.md` drop installed by base (`dynamicweb-demo-base/references/customer-context.md` recipe) reminds Claude of these rules regardless of which skill loaded first.

If you find yourself running this skill standalone with no base context, fix that before continuing -- see the description's "Use AFTER" hint. If `~/.claude/skills/dynamicweb-demo-base/` is not installed, install it first -- this skill's inherited rules require it.

## Sister skills

- **`dynamicweb-demo-base`** -- foundation skill (Use FIRST). Owns all setup + path resolution + Serializer install + customisations + customer-context.
- **`dynamicweb-swift-demo`** -- Swift frontend + Swift baseline content deserialize + post-deserialize integrity sweep (Use AFTER, can pair with this skill in either order on the host). PIM-only demos can skip this skill entirely.

A sibling skill that runs without `dynamicweb-demo-base`'s outputs (no `.mcp.json`, no `CUSTOMISATIONS.md`, no resolved `$env:DW_VAULT`) silently no-ops or produces broken artefacts.

## Vendor patterns

The vendor skill-repo consultation outcome (`dynamicweb/skills` + `dynamicweb/ai-implementor-skills`) is documented in [dynamicweb-demo-base/references/vendor-patterns.md](../dw-demo-base/references/vendor-patterns.md).

That file lists patterns we adopt and patterns we deliberately deviate from (PowerShell vs Python; "Use AFTER" composition wording; four-surface vs two-surface decision matrix; explicit recovery recipes inline). Sister skills cross-reference there rather than restating per-skill -- single source of truth for vendor positioning.




