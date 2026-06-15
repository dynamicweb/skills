# Dynamicweb Skills

Claude skills for [Dynamicweb 10](https://www.dynamicweb.com) — installable as a Claude plugin.

Skills are organized by task domain on disk and bundled by role in the plugin registry.

## Structure

```
.claude-plugin/
  marketplace.json                       # plugin registry — role bundles referencing skills by path
skills/
  dynamicweb-pim-query/                  # design, validate, and generate product queries
  dynamicweb-pim-dashboard/              # create dashboards and attach widgets
  dynamicweb-pim-enrichment/             # fill missing completeness fields on products
  dynamicweb-pim-solution-assistant/     # design full PIM data model structures
  dynamicweb-business-setup-agent/       # configure an existing Swift 2 installation as a business
  dynamicweb-business-solution-agent/    # end-to-end business solution from a plain-language request
  dynamicweb-swift2-site-builder/        # customize a Swift 2 site for a specific business
  dynamicweb-solution-installer/         # install Swift 2 from scratch
  dynamicweb-source-explorer/            # browse Dynamicweb source code on GitHub
  dynamicweb-mcp-tool-creator/           # add new MCP tools to the Dynamicweb.MCP project
  dynamicweb-demo-base/                  # foundation skill for all demos — MCP wiring, TLS, customisations
  dynamicweb-pim-demo/                   # PIM modelling from a blank DB — structures, completeness, workflows
  dynamicweb-swift-demo/                 # Swift 2 frontend — baseline deserialize, re-skin, content, paragraphs
  dynamicweb-erp-demo/                   # ERP integration demo — mock or live BC, Integration Framework rules
  dynamicweb-pim-for-bc/                 # live BC connector demo — ngrok tunnel, AppStore connector setup
```

## Plugins

| Plugin | Audience | Skills included |
|--------|----------|-----------------|
| `dynamicweb-developer` | Developers building on Dynamicweb 10 | solution-installer, source-explorer, mcp-tool-creator |
| `dynamicweb-implementer` | Implementers configuring PIM, content, and business solutions | pim-query, pim-dashboard, pim-enrichment, pim-solution-assistant, business-setup-agent, swift2-site-builder |
| `dynamicweb-user` | End-users and business users | pim-enrichment, pim-query, business-solution-agent |
| `dynamicweb-presales` | Presales and demo engineers | demo-base, pim-demo, swift-demo, erp-demo, pim-for-bc |

## Skills

### PIM & Data

**[dynamicweb-pim-query](skills/dynamicweb-pim-query/SKILL.md)**
Design, validate, and generate Dynamicweb 10 product queries. Covers the MCP payload model, field discovery, completion rules, and source index format.

**[dynamicweb-pim-dashboard](skills/dynamicweb-pim-dashboard/SKILL.md)**
Create dashboards and add widgets using MCP tools. Handles dashboard areas, widget discovery, parameter lookup, and query-backed count widgets.

**[dynamicweb-pim-enrichment](skills/dynamicweb-pim-enrichment/SKILL.md)**
Interactive agent that fills missing completeness fields on products returned by a saved query — page by page, with confirmation before writing.

**[dynamicweb-pim-solution-assistant](skills/dynamicweb-pim-solution-assistant/SKILL.md)**
Design full PIM data model structures from real source data. Proposes folders, DataModels, category fields, completeness rules, workflows, product queries, and dashboards.

### Business Solutions

**[dynamicweb-business-solution-agent](skills/dynamicweb-business-solution-agent/SKILL.md)**
End-to-end business solution orchestrator. Builds a full Dynamicweb 10 + Swift 2 solution from a plain-language request such as "I want a wine solution."

**[dynamicweb-business-setup-agent](skills/dynamicweb-business-setup-agent/SKILL.md)**
Full-stack business configurator. Use after MCP bootstrap is complete to turn an existing Swift 2 installation into a specific business.

**[dynamicweb-swift2-site-builder](skills/dynamicweb-swift2-site-builder/SKILL.md)**
Customize an existing Swift 2 site for a specific business — inspects the current installation, preserves the page shell, and applies branding and content changes.

### Developer & Platform

**[dynamicweb-solution-installer](skills/dynamicweb-solution-installer/SKILL.md)**
Installs Dynamicweb Swift 2 from scratch — downloads the latest database, files, and demo data, imports the database, and bootstraps the MCP connection.

**[dynamicweb-source-explorer](skills/dynamicweb-source-explorer/SKILL.md)**
Browse Dynamicweb source code on GitHub to understand internal APIs, classes, extension points, and patterns before building MCP tools or add-ins.

**[dynamicweb-mcp-tool-creator](skills/dynamicweb-mcp-tool-creator/SKILL.md)**
Step-by-step guide for adding new MCP tools to the Dynamicweb.MCP project — tool classes, services, models, and route handlers.

### Demos (Presales)

**[dynamicweb-demo-base](skills/dynamicweb-demo-base/SKILL.md)**
Foundation skill for all demos. Scaffolds the dw10-suite host, wires the Backend MCP and two-layer localhost TLS bypass, installs Playwright MCP, and drops the customisations and customer-context guardrails. Use this first.

**[dynamicweb-pim-demo](skills/dynamicweb-pim-demo/SKILL.md)**
PIM modelling from a blank DB — product data structures, shops vs channels, variants, BOM, completeness rules, workflows, role/permission matrix, and localization. Use after `dynamicweb-demo-base`.

**[dynamicweb-swift-demo](skills/dynamicweb-swift-demo/SKILL.md)**
Swift 2 frontend — baseline content deserialize, re-skinning to a customer brand, paragraph types, Visual Editor, language layers, and customer-center flows. Use after `dynamicweb-demo-base`.

**[dynamicweb-erp-demo](skills/dynamicweb-erp-demo/SKILL.md)**
ERP integration demo — DB-staged mock or live BC, Integration Framework rules, field ownership (ERP vs PIM), and demo reset between runs. Use after `dynamicweb-demo-base`.

**[dynamicweb-pim-for-bc](skills/dynamicweb-pim-for-bc/SKILL.md)**
Live BC connector demo — exposes the local DW host publicly via ngrok so a real BC tenant can call the connector's `/admin/api/BC*` surface. Use after `dynamicweb-demo-base`.

## Installation

Register this repo as a plugin marketplace in your Claude Code settings, then install the plugin for your role.

```jsonc
// .claude/settings.json
{
  "pluginMarketplaces": [
    "https://github.com/your-org/skills"
  ]
}
```

Then install a plugin bundle:

```
/plugins install dynamicweb-implementer
```

## Requirements

These skills delegate execution to the **Dynamicweb 10 MCP server**. The MCP server must be connected before using any skill.
