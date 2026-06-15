# Content gaps & skill roadmap

This repo covers PIM and presales demos in depth, with solid implementer and developer
coverage for the install → configure → build flow. This document records the functional
areas that currently have **no skill**, organized so they can be picked up as future work.
It is a planning document, not part of the shipped plugin.

## Coverage today

| Area | Covered by |
|------|------------|
| PIM queries, dashboards, enrichment, data-model design | `pim-query`, `pim-dashboard`, `pim-enrichment`, `pim-solution-assistant`, `pim-demo` |
| Swift 2 frontend (content, branding, customer center) | `swift2-site-builder`, `swift-demo` |
| Business solution build & configuration | `business-solution-agent`, `business-setup-agent` |
| Install & bootstrap | `solution-installer`, `demo-base` |
| ERP / Business Central integration (demo) | `erp-demo`, `pim-for-bc` |
| Developer platform (source, MCP tools) | `source-explorer`, `mcp-tool-creator` |

## Gaps with no skill (prioritized)

### High value
1. **Troubleshooting & diagnostics** — query failures, stale indexes, MCP connectivity,
   permission errors, data-sync problems. Cross-role; every role needs it.
2. **Search & indexing** — Lucene/repository configuration, facets/filters, relevance
   tuning. Core to ecommerce and currently only touched tangentially.
3. **Commerce operations** — orders, checkout, pricing/discount rules, payment and shipping
   providers, stock/inventory. No coverage today.
4. **Advanced PIM** — variants (single/multi-axis), BOM/bundles, assortments, channels vs
   shops, workflow/approval states. Exists only scattered inside `pim-demo` references, not
   as an implementer-facing skill.

### Medium value
5. **Upgrades & migration** — DW9→10, Swift version upgrades, legacy data migration.
6. **Security & permissions** — role/permission model, API security, audit/compliance.
7. **Content & SEO** — page hierarchy, metadata/canonical URLs, scheduling, asset
   management (beyond the Swift demo baseline).
8. **Deployment & DevOps** — environments, release/rollback, config/version management.

### Lower value / situational
9. **Reporting & analytics**, **marketing/personalization**, **performance tuning**,
   **non-BC ERP integrations**, **Rapido** (if it is ever in scope alongside Swift).

## Structural follow-ups (not new content)
- **`dynamicweb-foundations` shared skill** — extract the cross-cutting knowledge currently
  living in `demo-base/references/` (MCP setup, TLS bypass, vendor patterns) so non-demo
  skills can reuse it without depending on the demo bundle.
- **Implementer-facing integration coverage** — today ERP/BC knowledge is presales-only;
  implementers have no production integration skill.
- **Operator / administrator role bundle** — monitoring, backups, user/license management,
  system health. No skills exist for this audience yet.

## Suggested bundling for new skills
- Troubleshooting → all role bundles (or a shared `dynamicweb-troubleshooting`).
- Search/indexing, advanced PIM, commerce ops, security → `dynamicweb-implementer`.
- Upgrades, deployment → `dynamicweb-developer`.
