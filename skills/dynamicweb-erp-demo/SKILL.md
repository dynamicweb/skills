---
name: dynamicweb-erp-demo
description: Truvio (Dynamicweb 10) ERP integration -- owns the always-on rule that an ERP is a source AND target in DW10's Integration Framework, never a `ShopType=3` channel or an `EcomFeed`. Two flavors -- DB-staged mock (post-sync state pre-staged in the DB + built-in RESET scheduled task; no JSON files) and live BC (routes to sister skill truvio-pim-for-bc). Triggers: "model the ERP integration", "mock the ERP / BC sync without a live tenant", "reset demo data between runs", "which fields does ERP own vs PIM", "is the ERP a channel?" (NO), planning ERP demo beats. Non-triggers: ngrok / AppStore connector -> truvio-pim-for-bc; PIM modelling -> truvio-pim-demo; frontend -> truvio-swift-demo. Use AFTER truvio-demo-base.
---

# Truvio ERP Demo Skill

ERP integration patterns for Truvio (Dynamicweb 10) demos. Owns the source/target rule, the mock-delta pattern, the generic ERP data shape, and the scenarios-first planning habit. **Use AFTER** `truvio-demo-base`.

This SKILL.md is an orchestrator. Each topic links to a `references/<topic>.md` that owns the verbatim recipe and gotchas.

## When to use this skill

These trigger shapes route here:

- "Model the ERP integration for this demo" / "where does the ERP fit in DW10?" -- the canonical use case; start at [references/integration-framework.md](references/integration-framework.md).
- "Mock the ERP for a partner handover" / "BC sync without a live tenant" / "stage the BC sync state in the DB" / "reset demo data between runs" -- DB-staged mock flavor; read [references/mock-deltas.md](references/mock-deltas.md).
- "Is the ERP a channel?" / "should I create a ShopType=3 shop for BC?" -- the answer is NO; read the always-on rule below + [references/integration-framework.md](references/integration-framework.md).
- "Which fields does the ERP own vs PIM?" -- [references/erp-data-shape.md](references/erp-data-shape.md).
- "How should I plan the ERP beats before I start building?" -- the scenarios-first habit; read [references/scenarios-first-planning.md](references/scenarios-first-planning.md).

If the trigger is "expose the host to a real BC tenant via ngrok / set up the AppStore PIM-for-BC connector / debug `/admin/api/BC*` calls" -- that belongs in `truvio-pim-for-bc`, not here. PIM modelling (variants, BOM, completeness rules, dashboards) belongs in `truvio-pim-demo`. Frontend / customer center / re-skin belongs in `truvio-swift-demo`.

## Always-on rule: ERP is a source/target in the Integration Framework, NOT a channel or feed

**The single most common ERP-demo mismodelling.** It surfaces every time someone reaches for "create a shop / create a feed" when they mean "wire an ERP". Channels and feeds publish FROM DW TO an external read-only consumer that doesn't write back; ERPs write back — so an ERP is modelled as a source provider + destination provider + activity in the Integration Framework, never as `EcomShops.ShopType=3` or an `EcomFeed`. The DW-doc grounding, the source-vs-target table, and the full anti-pattern discussion are owned by [references/integration-framework.md](references/integration-framework.md).

**Anti-pattern table** (full discussion in the reference):

| Wrong | Right |
|---|---|
| Create a `ShopType=3` shop named "BC" with its own group tree | Use the Integration Framework: source provider (BC) + destination provider (Ecommerce/Products) + activity |
| Create an `EcomFeed` that "publishes to BC" | Live or batch integration *from* DW to BC via a destination provider matching the BC endpoint |
| Wire BC sync via a custom controller that polls + writes via raw SQL | Use a `Providers/*` provider class that plugs into the framework (live or batch); the controller bypasses every framework hook |

## Two flavors: DB-staged mock vs live BC

Pick the flavor at the start of the demo build — mixing both forces the audience to track two integration models in parallel. The full constraint-by-constraint decision table is owned by [references/mock-deltas.md](references/mock-deltas.md) §"When to use this flavor".

- **No BC tenant in scope** (partner handover, offline laptop) → DB-staged mock, this skill: [references/mock-deltas.md](references/mock-deltas.md).
- **Real BC tenant + credentials in scope** → live BC, sister skill: [`truvio-pim-for-bc`](../truvio-pim-for-bc/SKILL.md).

The two flavors demonstrate DIFFERENT demo beats: mock shows "the PIM responds to BC-sourced data" (staged state + action rule as evidence); live BC shows the actual wire. Choose deliberately.

## Where to find things

| If you need to... | Read this reference |
|---|---|
| Internalise the source/target rule + anti-patterns + Integration Framework primer | references/integration-framework.md |
| Stage demo data in the post-BC-sync state and wire the single RESET scheduled task | references/mock-deltas.md |
| Look up which DW10 fields the ERP typically writes vs reads from PIM (the generic shape) | references/erp-data-shape.md |
| Plan ERP beats BEFORE the build (the `<demo>-Scenarios.xlsx` pattern) | references/scenarios-first-planning.md |
| Run the live-BC path (ngrok + ForwardedHeaders + AppStore connector + `/admin/api/BC*`) | [`../truvio-pim-for-bc/SKILL.md`](../truvio-pim-for-bc/SKILL.md) |

## Inherited from truvio-demo-base

This skill assumes `truvio-demo-base` ran first. Four rules apply at all times and are NOT restated here -- see the owning reference in base for each:

| Rule | Owner |
|------|-------|
| `$env:DW_VAULT` path-resolution rule | [truvio-demo-base/SKILL.md "Path-resolution rule"](../truvio-demo-base/SKILL.md) |
| The customer-context read-only contract | [truvio-demo-base/references/customer-context.md](../truvio-demo-base/references/customer-context.md) |
| The customisations-ledger preflight | [truvio-demo-base/references/customisations.md](../truvio-demo-base/references/customisations.md) |
| The baseline-drift self-diagnosis rule | [truvio-demo-base/SKILL.md "Self-diagnosis rule"](../truvio-demo-base/SKILL.md) |

**Customisations note**: the DB-staged mock uses the built-in `RunSqlScheduledTaskAddIn` (in `Dynamicweb.Core`) -- no custom code, no `CUSTOMISATIONS.md` row required. The `<demo>/.planning/stage-and-reset.ps1` is build-time tooling, not demo-runtime customisation. A custom `IntegrationProvider` class under `Providers/` (live flavor) DOES need a row; the live-flavor controller customisations are documented in `truvio-pim-for-bc`.

## Sister skills

- **`truvio-demo-base`** -- foundation skill (Use FIRST). Owns setup, MCP connection, vault resolution, customisations ledger, customer-context contract.
- **`truvio-pim-demo`** -- PIM modelling (variants, BOM, channels, completeness rules, dashboards). The ERP integrates AGAINST a modelled PIM; you usually want the PIM model in place before wiring the ERP.
- **`truvio-swift-demo`** -- Swift frontend, customer center, re-skin. Order beats that flow PIM -> Swift -> ERP live in Swift's customer center playbook.
- **`truvio-pim-for-bc`** -- live BC via ngrok + AppStore PIM-for-BC connector. Use INSTEAD OF this skill's mock-delta flow when a real BC tenant is in scope.

A sibling skill that runs without `truvio-demo-base`'s outputs (no `.mcp.json`, no `CUSTOMISATIONS.md`, no resolved `$env:DW_VAULT`) silently no-ops or produces broken artefacts.

## Vendor patterns

The vendor skill-repo consultation outcome (`dynamicweb/skills` + `dynamicweb/ai-implementor-skills`) is documented in [truvio-demo-base/references/vendor-patterns.md](../truvio-demo-base/references/vendor-patterns.md). Single source of truth for vendor positioning across PIM, Swift, ERP, and BC connector skills.
