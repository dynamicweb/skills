# Dynamicweb Skills — Naming & Structure

Naming convention and skill catalog for the official `dynamicweb/skills` repository, anchored on the Dynamicweb 10 developer documentation ([doc.dynamicweb.dev](https://doc.dynamicweb.dev/)) and the developer workflow.

---

## Anchor

The structure mirrors how DW10 already organizes itself, so a skill's name predicts where its knowledge lives in the docs.

**Three documentation pillars (the developer journey):** **Setup** (install, CLI, config, upgrade) → **Implementation** (build Content, Products/PIM, Commerce on the rendering engine — template hierarchy, Razor, ViewModels, TemplateTags) → **Extending** (C# API, providers, notification subscribers, AddIns, scheduled tasks).

**Four implementation directions:** Swift (storefront accelerator), Core, From Scratch, Headless (`/dwapi/` delivery API).

---

## Naming convention

**`dw-<area>[-<capability>]`** — kebab-case, with folder name ≡ frontmatter `name:` ≡ `marketplace.json` path basename.

- **Prefix `dw-`** — recognized Dynamicweb abbreviation; namespaces against other installed plugins without repeating the org name inside the org's own repo. (Fallback: `dynamicweb-`; scheme is identical.)
- **`<area>`** — one canonical area (table below).
- **`<capability>`** — optional specific noun/verb when an area needs more than one skill.

### Area taxonomy

| Area | Pillar | Docs / product anchor | Scope |
|---|---|---|---|
| `setup` | Setup | install, CLI, config, upgrade | Bootstrap a solution, dev environment, configuration, upgrades |
| `render` | Implementation | template hierarchy, Razor, ViewModels, TemplateTags | Template structure, Razor patterns, canonical render surfaces, fetching/shaping content for templates |
| `swift` | Implementation | Swift accelerator | Building on the Swift storefront |
| `headless` | Implementation | `/dwapi/` delivery API | Decoupled frontends, REST ViewModels |
| `content` | Implementation | Content / Items / Files | Pages, paragraphs, item types, content modelling, assets |
| `pim` | Implementation | PIM / Products | Modelling, variants/BOM, completeness, workflow, localization |
| `commerce` | Implementation | Ecommerce | Catalog, orders/checkout/cart, prices/assortments, B2B |
| `search` | Implementation | Repositories / indexing | Indexes, queries, repositories, BuildIndex |
| `users` | Implementation | Users / permissions | Users, groups, the Permission entity store |
| `extend` | Extending | C# API, providers, AddIns | Custom backend code, notification subscribers, scheduled tasks, MCP tools |
| `integration` | Extending | Integration framework | Source/target providers, ERP, BC connector |
| `data` | cross-cutting | C# API / web API / SQL | Data-access surface priority (API > SQL), cache invalidation |
| `source` | cross-cutting | dw10 platform source | Navigating and answering questions from the Dynamicweb source code |
| `demo` | Presales | presales demo builds | The presales demo chain (`dw-demo-base` + sisters); flow skills with demo-only guardrails — see the foundational-vs-demo boundary in `CLAUDE.md` |

### Frontmatter / description

Every `SKILL.md` has `name`, `type` (`knowledge` | `flow`), `group` (the area), and `description`. The description is the activation signal: (1) one sentence on what it does, (2) `Triggers:` the activating conditions, (3) non-triggers + routing to the sibling skill that owns that case. Full frontmatter spec in `CLAUDE.md`.

---

## Repo & folder structure

Flat `skills/<skill>/`; the area is carried by the name prefix, so `ls skills/` reads as a grouped catalog.

```
skills/
  dw-setup-install/        SKILL.md  references/  assets/  scripts/
  dw-render-razor/
  dw-render-viewmodels/
  dw-pim-modelling/
  dw-commerce-orders/
  dw-extend-providers/
  dw-integration-framework/
  dw-demo-base/
  ...
.claude-plugin/marketplace.json
scripts/validate-skills.py
README.md  CLAUDE.md  CHANGELOG.md
```

### Plugin bundles (by developer journey)

| Plugin | Audience | Bundles |
|---|---|---|
| `dynamicweb-setup` | Bootstrapping a solution | `setup-*` |
| `dynamicweb-frontend` | Template / storefront developers | `render-*`, `swift-*`, `headless-*`, `content-*` |
| `dynamicweb-commerce` | PIM / commerce implementers | `pim-*`, `commerce-*`, `search-*`, `users-*` |
| `dynamicweb-backend` | Backend / platform engineers | `extend-*`, `integration-*`, `data-*` |
| `dynamicweb-developer` | Platform developers working from source | developer-relevant foundational skills + `source-explorer` |
| `dynamicweb-presales` | Presales engineers building demos | `demo-*`, `integration-bc`, plus the foundational skills the demo chain links to |

The authoritative bundle contents live in `.claude-plugin/marketplace.json` — the table above is the intent, the JSON is the truth.

(Plugin install names keep the full `dynamicweb-` brand; skills use the short `dw-`.)

---

## Skill catalog

Grouped by pillar; first in each group is the highest-value start.

### Setup
- `dw-setup-install` — bootstrap a DW10 solution: CLI, dev environment, first run.
- `dw-setup-config` — configuration surfaces, environment/connection settings.
- `dw-setup-upgrade` — version upgrades and migration mechanics.

### Implementation — rendering core
- `dw-render-razor` — template hierarchy under `Files/Templates/Designs/`, Razor patterns, canonical "use this API, not URL/string parsing" render surfaces (user/groups, permissions, prices, orders, products, URLs, redirects, custom-head includes).
- `dw-render-viewmodels` — fetching/shaping content with ViewModels; when to drop to the C# API.
- `dw-render-templatetags` — the TemplateTags reference surface.
- `dw-content-modelling` — item types (`<Prefix>_*` discipline), paragraphs, one-concern-per-field modelling, asset organization under `wwwroot/Files/`.

### Implementation — frontend directions
- `dw-swift-building` — extending the Swift storefront; layouts, sections, customer-center; re-skin ladder (config → custom CSS → content-layout).
- `dw-headless-delivery` — the `/dwapi/` delivery API, ViewModels as REST, decoupled frontends.

### Implementation — domains
- `dw-pim-modelling` — structural model (shops vs channels vs data structures, GroupType, repositories), variants (single-axis recipe), BOM bundles, GUID-collision recovery.
- `dw-pim-completeness` — completeness rules, diagnostics, dashboards.
- `dw-pim-workflow` — product workflow engine: states, transitions, notifications, per-state role gating.
- `dw-pim-localization` — translating products/groups across EcomLanguages; AreaCopy language layers.
- `dw-commerce-catalog` — product catalog rendering, `ProductListViewModel`, assortments.
- `dw-commerce-orders` — orders, checkout, cart, prices.
- `dw-commerce-b2b` — B2B patterns: "DC = AccessUser group" → DC-scoped assortments + shipping, CSR/sales-on-behalf.
- `dw-search-indexing` — repositories, queries, indexes, `BuildIndex` + wait-for-Idle.
- `dw-users-permissions` — users, groups, the Permission entity store (permissions live in the `Permission` table, not legacy `*Permission` columns); three-layer permission model.

### Extending
- `dw-extend-csharp-api` — using the C# API (`Dynamicweb.Ecommerce.*`, `Services.*`, `Pageview.*`) when ViewModel properties aren't enough.
- `dw-extend-providers` — providers, notification subscribers, AddIns; master-gate pattern (NotificationSubscriber on `Page.Loaded`).
- `dw-extend-scheduled-tasks` — scheduled tasks, including the built-in `RunSqlScheduledTaskAddIn`.
- `dw-extend-mcp-tools` — authoring MCP tools against the platform.
- `dw-integration-framework` — Integration Framework primer: an external/ERP system is a source AND target (provider + activity), never a `ShopType=3` channel or `EcomFeed`; source/target wiring and anti-patterns.
- `dw-integration-erp` — ERP↔PIM data-shape ownership (which fields the ERP owns vs PIM), connector configuration.
- `dw-integration-bc` — Business Central connector: `/admin/api/BC*` endpoint surface, field-mapping (required), `ForwardedHeaders` deployment, `StaticLinkManager`.

### Cross-cutting
- `dw-data-access` — data-access surface priority (C# API / web API > direct SQL), cache invalidation per surface, SQL-direct gotchas (NOT-NULL columns, slot reservation, post-write restart rules).
- `dw-source-explorer` — navigating the dw10 platform source to answer "how does the platform actually do X".

### Presales / demo (the `dynamicweb-presales` chain)
- `dw-demo-base` — foundation for every demo: host scaffolding, MCP wiring, TLS bypass, customisation ledger, fold-back workflow. Use FIRST; the sisters are Use AFTER.
- `dw-demo-pim` — PIM-focused demo build on top of demo-base.
- `dw-demo-swift` — Swift storefront demo build.
- `dw-demo-erp` — ERP/integration demo build with mock deltas.
(`dw-integration-bc` doubles as the BC connector demo; the foundational-vs-demo boundary rules live in `CLAUDE.md`.)

---

## Validation

`scripts/validate-skills.py` on every commit: folder ≡ `name:` ≡ marketplace basename (all `dw-` prefixed); every marketplace path resolves; relative links resolve; every `description` carries trigger language; non-zero exit on failure. `CLAUDE.md` captures the authoring rules, the frontmatter spec, and the contribution workflow.

---

## Open decision

Prefix **`dw-`** (recommended) vs. **`dynamicweb-`** — everything here is prefix-agnostic.
