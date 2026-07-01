# Content gaps & skill roadmap

This repo covers the DW10 platform broadly — setup, rendering, content, PIM, commerce,
search, users, extending, integration — plus the presales demo chain. This document records
the functional areas that currently have **no skill**, organized so they can be picked up as
future work. It is a planning document, not part of the shipped plugin.

## Coverage today

| Area | Covered by |
|------|------------|
| Install, configuration, upgrades | `dw-setup-install`, `dw-setup-config`, `dw-setup-upgrade` |
| Rendering (Razor, ViewModels, TemplateTags) | `dw-render-razor`, `dw-render-viewmodels`, `dw-render-templatetags` |
| Content modelling & headless delivery | `dw-content-modelling`, `dw-headless-delivery` |
| PIM (modelling, completeness, workflow, localization) | `dw-pim-modelling`, `dw-pim-completeness`, `dw-pim-workflow`, `dw-pim-localization` |
| Commerce (catalog, orders, B2B) | `dw-commerce-catalog`, `dw-commerce-orders`, `dw-commerce-b2b` |
| Search & indexing | `dw-search-indexing` |
| Users & permissions | `dw-users-permissions` |
| Extending (C# API, providers, scheduled tasks, MCP tools) | `dw-extend-csharp-api`, `dw-extend-providers`, `dw-extend-scheduled-tasks`, `dw-extend-mcp-tools` |
| Integration (framework, ERP, Business Central) | `dw-integration-framework`, `dw-integration-erp`, `dw-integration-bc` |
| Data access & source navigation | `dw-data-access`, `dw-source-explorer` |
| Swift storefront | `dw-swift-building` |
| Presales demos | `dw-demo-base`, `dw-demo-pim`, `dw-demo-swift`, `dw-demo-erp` |

## Gaps with no skill (prioritized)

### High value
1. **Troubleshooting & diagnostics** — a dedicated cross-role skill for query failures, stale
   indexes, MCP connectivity, permission errors, data-sync problems. Recovery recipes exist
   scattered across skill references (and the `dw-demo-base` foundational candidates); nothing
   routes a raw symptom to the right recipe.
2. **Payment & shipping providers** — checkout covers cart/orders, but provider configuration
   (payment gateways, shipping calculators) has no dedicated coverage.
3. **Marketing & personalization** — email marketing, campaigns, personalization rules.

### Medium value
4. **Deployment & DevOps** — environments, release/rollback, config/version management.
5. **Content & SEO** — metadata/canonical URLs, scheduling, redirects beyond the render-surface
   notes in `dw-render-razor`.
6. **API security & audit** — `dw-users-permissions` covers the permission model; API key
   management, audit/compliance surfaces are uncovered.

### Lower value / situational
7. **Reporting & analytics**, **performance tuning**, **non-BC ERP integrations**, **Rapido**
   (if it is ever in scope alongside Swift).

## Structural follow-ups (not new content)
- **Fold up the foundational candidates** — 20+ candidate files under
  `dw-demo-base/references/foundational/` are staged for fold-up into their named foundational
  skills (one skill per PR; see CHANGELOG 3.4.0). This is the standing highest-value
  structural task.
- **Operator / administrator role bundle** — monitoring, backups, user/license management,
  system health. No skills exist for this audience yet.

## Suggested bundling for new skills
- Troubleshooting → all role bundles (or a shared `dynamicweb-troubleshooting`).
- Payment/shipping providers, marketing → `dynamicweb-commerce`.
- Deployment, API security → `dynamicweb-backend` / `dynamicweb-developer`.
