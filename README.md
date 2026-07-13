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
  dw-swift-building/        # customize a Swift 2 site for a business
  dw-headless-delivery/     # decoupled frontends over the /dwapi/ delivery API
  dw-pim-*/                 # PIM modelling, completeness, workflow, localization
  dw-commerce-*/            # catalog, orders, B2B
  dw-search-indexing/       # search indexes on Lucene
  dw-users-permissions/     # users, groups, permissions
  dw-extend-*/              # C# API, providers, scheduled tasks, MCP tools
  dw-integration-*/         # Integration Framework, ERP connectors, Business Central
  dw-data-access/           # data-access patterns and caching
  dw-source-explorer/       # browse Dynamicweb source on GitHub
  dw-demo-*/                # presales demo chain (base, pim, swift, erp)
```

## Plugins

Each bundle is a role-oriented selection of skills. Shared skills (for example
`dw-setup-install`, `dw-extend-mcp-tools`, `dw-integration-bc`) appear in more than one bundle.

| Plugin | Audience | Skills included |
|--------|----------|-----------------|
| `dynamicweb-setup` | Provisioning Dynamicweb 10 | setup-install, setup-config, setup-upgrade |
| `dynamicweb-frontend` | Template & storefront developers | render-razor, render-viewmodels, render-templatetags, content-modelling, swift-building, headless-delivery |
| `dynamicweb-commerce` | Commerce & PIM implementers | pim-modelling, pim-completeness, pim-workflow, pim-localization, commerce-catalog, commerce-orders, commerce-b2b, search-indexing, users-permissions |
| `dynamicweb-backend` | Backend & platform engineers | extend-csharp-api, extend-providers, extend-scheduled-tasks, extend-mcp-tools, integration-framework, integration-erp, integration-bc, data-access |
| `dynamicweb-developer` | Developers building on the platform | setup-install, source-explorer, extend-mcp-tools |
| `dynamicweb-presales` | Presales & demo engineers | demo-base, demo-pim, demo-swift, demo-erp, integration-bc; + foundational skills the demo skills reference (integration-framework, extend-csharp-api) |

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
Design item types, paragraphs, and content models in Dynamicweb 10.

**[dw-swift-building](skills/dw-swift-building/SKILL.md)**
Customize an existing Swift 2 site for a specific business without rebuilding it — preserves the working page shell and updates area, navigation, category pages, and item values.

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

**[dw-source-explorer](skills/dw-source-explorer/SKILL.md)**
Browse Dynamicweb source code on GitHub to understand internal APIs, classes, and extension points.

### Demos (Presales)

**[dw-demo-base](skills/dw-demo-base/SKILL.md)**
Foundation skill for all demos. Scaffolds the dw10-suite host, wires the Backend MCP and two-layer localhost TLS bypass, installs Playwright MCP, and drops the customisations and customer-context guardrails. Use this first. Also owns the **orchestrator abstraction** ([references/orchestrator.md](skills/dw-demo-base/references/orchestrator.md)) — how a build is driven, GSD primary or the native `/demo:*` command set. Owns the **hosted/cloud fork** ([references/online-mode.md](skills/dw-demo-base/references/online-mode.md)) — building on an install reached only by URL + Admin API key, and publishing a locally-built demo onto one.

**[dw-demo-pim](skills/dw-demo-pim/SKILL.md)**
PIM modelling from a blank DB — product data built from scratch via MCP. Use after `dw-demo-base`.

**[dw-demo-swift](skills/dw-demo-swift/SKILL.md)**
Swift frontend — baseline deserialize, feature-pack install, templates, paragraph types, Visual Editor, and the customer-center playbook (incl. the Swift 2.4 sign-in profiles / switch-user recipe and the checkout order-field recipe). Use after `dw-demo-base`.

**[dw-demo-erp](skills/dw-demo-erp/SKILL.md)**
ERP integration demo — DB-staged mock or live BC, Integration Framework rules. Use after `dw-demo-base`.

## Skill dependencies

The **presales demo chain** has a hard order. `dw-demo-base` must run **first** — it scaffolds
the host, wires MCP + the TLS bypass, and captures the demo's versions + downloads its artifacts
per-demo. The sister demo skills
(`dw-demo-pim`, `dw-demo-swift`, `dw-demo-erp`, and the `dw-integration-bc` connector demo)
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
