# Dynamicweb Skills

Claude skills for [Dynamicweb 10](https://www.dynamicweb.com) — installable as a Claude plugin.

Skills are organized by task domain on disk (`skills/dw-<domain>-<topic>/`) and bundled by
role in the plugin registry. Skills are shared across bundles: a single skill directory can
appear in more than one role bundle, with no copying or symlinks.

## Structure

```
.claude-plugin/
  marketplace.json          # plugin registry — role bundles, each curating skills by path
skills/
  dw-setup-*/               # install, configure, upgrade a Dynamicweb 10 solution
  dw-render-*/              # Razor, ViewModels, TemplateTags
  dw-content-modelling/     # item types, paragraphs, content models
  dw-content-localization/ # translate a page/site, create a language version
  dw-swift-building/        # customize a Swift 2 site for a business
  dw-swift-page-blocks/     # Swift 2 page-building vocabulary (reference)
  dw-swift-page-design/     # build a Swift 2 page from a reference/mockup
  dw-swift-migrate-v1/      # faithful Swift 1 -> Swift 2 layout port
  dw-swift-migrate-content/ # rebuild any site's content as modern Swift 2
  dw-headless-delivery/     # decoupled frontends over the /dwapi/ delivery API
  dw-pim-*/                 # PIM modelling, completeness, workflow, localization
  dw-pim-migrate-dw9/       # migrate a DW9 product catalog into DW10 PIM
  dw-commerce-*/            # catalog, orders, B2B
  dw-search-indexing/       # search indexes on Lucene
  dw-users-permissions/     # users, groups, permissions
  dw-extend-*/              # C# API, providers, scheduled tasks, MCP tools
  dw-integration-*/         # Integration Framework, ERP connectors, Business Central
  dw-data-access/           # data-access patterns and caching
  dw-data-audit-trail/      # investigate who/when/why something changed
  dw-source-explorer/       # browse Dynamicweb source on GitHub
  dw-source-doc-lookup/     # consult the live Dynamicweb documentation
  dw-demo-*/                # presales demo chain (base, pim, swift, headless, erp)
```

## Plugins

Each bundle is a role-oriented selection of skills. Shared skills (for example
`dw-setup-install`, `dw-extend-mcp-tools`, `dw-integration-bc`) appear in more than one bundle.

| Plugin | Audience | Skills included |
|--------|----------|-----------------|
| `dynamicweb-setup` | Provisioning Dynamicweb 10 | setup-install, setup-config, setup-upgrade |
| `dynamicweb-frontend` | Template & storefront developers | render-razor, render-viewmodels, render-templatetags, content-modelling, content-localization, swift-building, swift-page-blocks, swift-page-design, swift-migrate-v1, swift-migrate-content, headless-delivery |
| `dynamicweb-commerce` | Commerce & PIM implementers | pim-modelling, pim-completeness, pim-workflow, pim-localization, pim-migrate-dw9, commerce-catalog, commerce-orders, commerce-b2b, search-indexing, users-permissions |
| `dynamicweb-backend` | Backend & platform engineers | extend-csharp-api, extend-providers, extend-scheduled-tasks, extend-mcp-tools, integration-framework, integration-erp, integration-bc, data-access, data-audit-trail |
| `dynamicweb-developer` | Developers building on the platform | setup-install, source-explorer, source-doc-lookup, extend-mcp-tools |
| `dynamicweb-presales` | Presales & demo engineers | demo-base, demo-pim, demo-swift, demo-headless, demo-erp, integration-bc; + the foundational skills the demo skills reference (setup-install, setup-config, setup-upgrade, source-explorer, integration-framework, integration-erp, extend-csharp-api, extend-mcp-tools, extend-providers, headless-delivery, search-indexing, users-permissions, the pim/commerce/render/content/data-access skills, swift-building) |

## Skills

### Setup

**[dw-setup-install](skills/dw-setup-install/SKILL.md)**
Installs Dynamicweb Swift 2 from scratch — downloads the latest database, files, and demo data, imports the database, installs the temporary MCP add-ins payload, and writes the first-run bootstrap manifest.

**[dw-setup-config](skills/dw-setup-config/SKILL.md)**
Configure Dynamicweb 10 environment and connection settings.

**[dw-setup-upgrade](skills/dw-setup-upgrade/SKILL.md)**
Manage Dynamicweb 10 version upgrades and migration mechanics.

### Rendering & Content

**[dw-render-razor](skills/dw-render-razor/SKILL.md)**
Build template hierarchies and Razor patterns — the foundation for all rendering.

**[dw-render-viewmodels](skills/dw-render-viewmodels/SKILL.md)**
Fetch and shape content using ViewModels in Dynamicweb 10 templates.

**[dw-render-templatetags](skills/dw-render-templatetags/SKILL.md)**
Build templates using TemplateTags to access content properties directly.

**[dw-content-modelling](skills/dw-content-modelling/SKILL.md)**
Design item types, paragraphs, and content models in Dynamicweb 10, and create/publish a page or paragraph through the MCP tools.

**[dw-content-localization](skills/dw-content-localization/SKILL.md)**
Create a language version of a website and translate its page content, or translate an existing page/site from one language to another.

**[dw-swift-building](skills/dw-swift-building/SKILL.md)**
Customize an existing Swift 2 site for a specific business without rebuilding it — preserves the working page shell and updates area, navigation, category pages, and item values.

**[dw-swift-page-blocks](skills/dw-swift-page-blocks/SKILL.md)**
Reference for the Swift 2 page-building vocabulary — grid row layouts, paragraph component types with their variants and fields, color schemes, and the MCP tools that compose them.

**[dw-swift-page-design](skills/dw-swift-page-design/SKILL.md)**
Build a good-looking Swift 2 page — matching an existing page's style, from a screenshot/mockup, or by recreating a live page from its URL.

**[dw-swift-migrate-v1](skills/dw-swift-migrate-v1/SKILL.md)**
Faithful, layout-preserving migration of pages from a Swift 1 solution into Swift 2.

**[dw-swift-migrate-content](skills/dw-swift-migrate-content/SKILL.md)**
Extract any existing site's content and rebuild it as a standard, modern Swift 2 site.

**[dw-headless-delivery](skills/dw-headless-delivery/SKILL.md)**
Build decoupled frontends using the `/dwapi/` delivery API — authentication, content, ecommerce, users, navigation, forms, and query endpoints.

### PIM & Commerce

**[dw-pim-modelling](skills/dw-pim-modelling/SKILL.md)**
Model Dynamicweb 10 PIM data — Data Models, category fields, variant groups, and global vs category field storage.

**[dw-pim-completeness](skills/dw-pim-completeness/SKILL.md)**
Configure Dynamicweb 10 product completeness — completion rules, completeness scoring, and query-driven automatic workflows.

**[dw-pim-workflow](skills/dw-pim-workflow/SKILL.md)**
Configure Dynamicweb 10 PIM workflows — named states, transitions, and editorial handoffs across the product enrichment lifecycle.

**[dw-pim-localization](skills/dw-pim-localization/SKILL.md)**
Manage product translation and localization across EcomLanguages.

**[dw-pim-migrate-dw9](skills/dw-pim-migrate-dw9/SKILL.md)**
Migrate a Dynamicweb 9 solution's product structure and catalog data into a Dynamicweb 10 PIM — structure, product import, data-model assignment, and verification, in that order.

**[dw-commerce-catalog](skills/dw-commerce-catalog/SKILL.md)**
Render product catalogs and assortments in Dynamicweb 10.

**[dw-commerce-orders](skills/dw-commerce-orders/SKILL.md)**
Handle orders, checkout, and cart functionality.

**[dw-commerce-b2b](skills/dw-commerce-b2b/SKILL.md)**
Implement B2B patterns — customer groups, scoped assortments, and sales workflows.

**[dw-search-indexing](skills/dw-search-indexing/SKILL.md)**
Build and configure Dynamicweb 10 search indexes on Lucene — index types, builders, analyzers, scoring, and product index setup.

**[dw-users-permissions](skills/dw-users-permissions/SKILL.md)**
Manage users, groups, and the Permission entity store.

### Backend & Integration

**[dw-extend-csharp-api](skills/dw-extend-csharp-api/SKILL.md)**
Use the C# API and `Dynamicweb.Services` for custom backend code.

**[dw-extend-providers](skills/dw-extend-providers/SKILL.md)**
Build providers, notification subscribers, and AddIns.

**[dw-extend-scheduled-tasks](skills/dw-extend-scheduled-tasks/SKILL.md)**
Create and manage scheduled tasks, including `RunSqlScheduledTaskAddIn`.

**[dw-extend-mcp-tools](skills/dw-extend-mcp-tools/SKILL.md)**
Step-by-step guide for adding new MCP tools to the Dynamicweb MCP project.

**[dw-integration-framework](skills/dw-integration-framework/SKILL.md)**
Understand Dynamicweb 10 Integration Framework architecture and patterns.

**[dw-integration-erp](skills/dw-integration-erp/SKILL.md)**
Configure ERP connectors and data ownership.

**[dw-integration-bc](skills/dw-integration-bc/SKILL.md)**
Live "PIM for Business Central connector" demos — expose the local DW host publicly via ngrok so a real BC tenant can call the connector's `/admin/api/BC*` surface.

**[dw-data-access](skills/dw-data-access/SKILL.md)**
Choose appropriate data-access patterns and optimize caching.

**[dw-data-audit-trail](skills/dw-data-audit-trail/SKILL.md)**
Investigate why something changed, who changed a record, when a value was set, or inspect version/history for any Dynamicweb 10 entity.

**[dw-source-explorer](skills/dw-source-explorer/SKILL.md)**
Browse Dynamicweb source code on GitHub to understand internal APIs, classes, and extension points.

**[dw-source-doc-lookup](skills/dw-source-doc-lookup/SKILL.md)**
Consult the live Dynamicweb documentation as the source of truth before answering how a feature works, is configured, or fits together.

### Demos (Presales)

**[dw-demo-base](skills/dw-demo-base/SKILL.md)**
Foundation skill for all demos. Scaffolds the dw10-suite host (pinning `Dynamicweb.Suite` to the Distribution's gate-proven platform version when the scaffold validates Distribution content), wires the Backend MCP and two-layer localhost TLS bypass, installs Playwright MCP, and drops the customisations and customer-context guardrails. Use this first. Also owns the **orchestrator abstraction** ([references/orchestrator.md](skills/dw-demo-base/references/orchestrator.md)) — how a build is driven, GSD primary or the native `/demo:*` command set. Owns the **hosted/cloud fork** ([references/online-mode.md](skills/dw-demo-base/references/online-mode.md)) — building on an install reached only by URL + Admin API key — and the **publish path** ([references/publish-to-hosted.md](skills/dw-demo-base/references/publish-to-hosted.md)) — migrating a locally-built demo onto one. Owns the **visual-QA design gate** ([references/visual-qa.md](skills/dw-demo-base/references/visual-qa.md)) — the mechanical definition-of-done (overflow, section-gap, image-band-height, PLP row-content detectors) plus a human taste sign-off, armed from the first gate run. The **product-query verb surface** lives in dw-search-indexing — [query-authoring.md](skills/dw-search-indexing/references/query-authoring.md) (which read verb is authoritative, the restart-free query-cache flush, `QueryMove`/`QueryCopy` order of operations) and [query-expressions.md](skills/dw-search-indexing/references/query-expressions.md) (expression `Path` semantics, operator reality, sorting, result paging, and the three ways a build verb answers 200 and builds nothing).

**[dw-demo-pim](skills/dw-demo-pim/SKILL.md)**
PIM modelling from a blank DB — product data built from scratch via MCP. Use after `dw-demo-base`.

**[dw-demo-swift](skills/dw-demo-swift/SKILL.md)**
Swift frontend — baseline deserialize, the **zero-state pass** ([references/re-skin.md](skills/dw-demo-swift/references/re-skin.md) §"Step 0") that retires the shipped baseline's own copy, `defaultValue` placeholders and skeleton bands before any brand work, **catalogue imagery from a customer print-catalogue PDF** ([references/asset-organisation.md](skills/dw-demo-swift/references/asset-organisation.md)), feature-pack install, templates, paragraph types, Visual Editor, the customer-center playbook (incl. the Swift 2.4 sign-in profiles / switch-user recipe and the checkout order-field recipe), and the **mobile pass** ([references/mobile-pass.md](skills/dw-demo-swift/references/mobile-pass.md)) — canvas-fit debugging (`body.scrollWidth`), the Swift 2.4 trap catalogue, and the theme-default ≥1.2.0 "verify first" caveat. Use after `dw-demo-base`.

**[dw-demo-headless](skills/dw-demo-headless/SKILL.md)**
Headless delivery demo — Frontend API setup, a decoupled frontend against the DW content/commerce APIs. Routes endpoint detail to `dw-headless-delivery`. Use after `dw-demo-base`.

**[dw-demo-erp](skills/dw-demo-erp/SKILL.md)**
ERP integration demo — DB-staged mock or live BC, Integration Framework rules. Use after `dw-demo-base`.

## Skill dependencies

The **presales demo chain** has a hard order. `dw-demo-base` must run **first** — it scaffolds
the host, wires MCP + the TLS bypass, and captures the demo's versions + downloads its artifacts
per-demo. The sister demo skills
(`dw-demo-pim`, `dw-demo-swift`, `dw-demo-headless`, `dw-demo-erp`, and the `dw-integration-bc` connector demo)
are **Use AFTER** and inherit that setup; they no-op or break if run standalone.

The demo skills hold domain knowledge and carry no build sequencing — that is owned by a
swappable **orchestrator**: **GSD** (primary; its pipeline injects the skills into fresh-context
agents via the `agent_skills` block) or the **native `/demo:*` command set** (scaffolded into the
demo project, it detects GSD and defers unless run `--standalone`). With neither present, the floor
is a **lightweight in-skill harness** — each skill guards its own canonical flow (ordering + a gate
per step + a resumable `.demo/<slug>/flow-state.json` artifact) so a fully standalone run is still
not run blind. All three read the same SKILL.md files. The abstraction — running modes,
detection/deference, the `agent_skills` keystone, the strictness gradient, and shared acceptance
criteria — lives in
[dw-demo-base/references/orchestrator.md](skills/dw-demo-base/references/orchestrator.md).

## Manifest

`manifest.json` (repo root) is a generated index of every skill — `name`, `type`
(`knowledge` or `flow`), `group`, a one-sentence `description`, and the `path` to its
`SKILL.md`. The Dynamicweb MCP server ("Dynamo") fetches this single file to auto-discover
skills; Claude Code does not use it (it loads skills via `marketplace.json`).

It is generated from each skill's frontmatter — never edit it by hand:

```
node scripts/build-manifest.mjs          # rewrite manifest.json
node scripts/build-manifest.mjs --check  # CI: fail if it is stale
```

The description shown by Dynamo is the first sentence of each skill's `description`, so keep
that first sentence a tight, intent-bearing summary with no mid-sentence periods. CI
(`.github/workflows/manifest-check.yml`) fails on drift.

## Validation

`scripts/validate-skills.py` (Python 3, no dependencies) lints the repo structure —
marketplace schema and integrity, folder/name/path agreement, relative-link resolution,
absence of UTF-8 BOMs, and the description convention. Run `python3 scripts/validate-skills.py`
before committing. See `CLAUDE.md` for the optional `SessionStart` hook that runs it
automatically.

You can also validate against Claude Code's own schema:

```
claude plugin validate ./
```

## Installation

Add this repo as a plugin marketplace, then install the bundle for your role:

```
claude plugin marketplace add dynamicweb/skills
claude plugin install dynamicweb-presales@dynamicweb-skills
```

Install any of the six bundles by name: `dynamicweb-setup`, `dynamicweb-frontend`,
`dynamicweb-commerce`, `dynamicweb-backend`, `dynamicweb-developer`, `dynamicweb-presales`.

## Requirements

These skills delegate execution to the **Dynamicweb 10 MCP server**. The MCP server must be connected before using any skill.
