---
name: dw-demo-erp
type: flow
group: demo
mcp: optional
dynamo: false
description: 'Dynamicweb 10 ERP integration -- owns the always-on rule that an ERP is a source AND target in DW10''s Integration Framework, never a `ShopType=3` channel or an `EcomFeed`. Two flavors -- DB-staged mock (post-sync state pre-staged in the DB + built-in RESET scheduled task; no JSON files) and live BC (routes to sister skill dw-integration-bc). Triggers: "model the ERP integration", "mock the ERP / BC sync without a live tenant", "reset demo data between runs", "which fields does ERP own vs PIM", "is the ERP a channel?" (NO), planning ERP demo beats. Non-triggers: ngrok / AppStore connector -> dw-integration-bc; PIM modelling -> dw-demo-pim; frontend -> dw-demo-swift. Use AFTER dw-demo-base.'
---

# Dynamicweb ERP Demo Skill

## Without MCP

**This skill's steps are out-of-product by construction.** They are host configuration, staged
database state, PowerShell, `/admin/api` calls and filesystem work — not MCP tool calls — so an MCP
connection is a convenience here, not a precondition. With one, prefer an MCP tool wherever it
covers a step. Without one, the whole ladder is still open to this skill: drop one rung to the
Management API, then the serializer, with direct SQL last and local installs only. Name the rung
each step uses.

The ladder those rungs belong to is foundational —
[`dw-data-access`](../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance"; the demo deltas
(phase gate, scaffold one-clicks, Browser MCP) are in
[`dw-demo-base/references/surface-priority.md`](../dw-demo-base/references/surface-priority.md).

ERP integration patterns for Dynamicweb 10 demos. Owns the source/target rule, the mock-delta pattern, the generic ERP data shape, and the scenarios-first planning habit. **Use AFTER** `dw-demo-base`.

This SKILL.md is a nav layer. Each topic links to a `references/<topic>.md` that owns the verbatim recipe and gotchas.

## How to run me

This skill holds domain knowledge, not build sequencing. An **orchestrator** owns the phase
order: GSD injects this skill into its agents (via the `agent_skills` block), or the native
`/demo:*` command set invokes it; **standalone**, the skill's own lightweight harness guards its
documented order (gate every step, persist progress to `.demo/<slug>/flow-state.json`). The
orchestrator abstraction (GSD primary, native command set, and the standalone harness) is owned by
[`../dw-demo-base/references/orchestrator.md`](../dw-demo-base/references/orchestrator.md).

## When to use this skill

These trigger shapes route here:

- "Model the ERP integration for this demo" / "where does the ERP fit in DW10?" -- the canonical use case; start at [references/integration-framework.md](references/integration-framework.md).
- "Mock the ERP for a partner handover" / "BC sync without a live tenant" / "stage the BC sync state in the DB" / "reset demo data between runs" -- DB-staged mock flavor; read [references/mock-deltas.md](references/mock-deltas.md).
- **"Run the sync on camera"** / "show the order going to the ERP and the ERP number coming back" / "the status flips and the customer sees it" -- two-directional mock; read [references/two-way-mock.md](references/two-way-mock.md).
- "Is the ERP a channel?" / "should I create a ShopType=3 shop for BC?" -- the answer is NO; read the always-on rule below + [references/integration-framework.md](references/integration-framework.md).
- "Which fields does the ERP own vs PIM?" -- [references/erp-data-shape.md](references/erp-data-shape.md).
- "How should I plan the ERP beats before I start building?" -- the scenarios-first habit; read [references/scenarios-first-planning.md](references/scenarios-first-planning.md).

If the trigger is "expose the host to a real BC tenant via ngrok / set up the AppStore PIM-for-BC connector / debug `/admin/api/BC*` calls" -- that belongs in `dw-integration-bc`, not here. PIM modelling (variants, BOM, completeness rules, dashboards) belongs in `dw-demo-pim`. Frontend / customer center / re-skin belongs in `dw-demo-swift`.

## Always-on rule: ERP is a source/target in the Integration Framework, NOT a channel or feed

**The single most common ERP-demo mismodelling.** It surfaces every time someone reaches for "create a shop / create a feed" when they mean "wire an ERP". Channels and feeds publish FROM DW TO an external read-only consumer that doesn't write back; ERPs write back — so an ERP is modelled as a source provider + destination provider + activity in the Integration Framework, never as `EcomShops.ShopType=3` or an `EcomFeed`. The DW-doc grounding, the source-vs-target table, and the full anti-pattern discussion are owned by [references/integration-framework.md](references/integration-framework.md).

**Anti-pattern table** (full discussion in the reference):

| Wrong | Right |
|---|---|
| Create a `ShopType=3` shop named "BC" with its own group tree | Use the Integration Framework: source provider (BC) + destination provider (Ecommerce/Products) + activity |
| Create an `EcomFeed` that "publishes to BC" | Live or batch integration *from* DW to BC via a destination provider matching the BC endpoint |
| Wire BC sync via a custom controller that polls + writes via raw SQL | Use a `Providers/*` provider class that plugs into the framework (live or batch); the controller bypasses every framework hook |

## Three flavors: DB-staged mock, two-directional mock, live BC

Pick the flavor at the start of the demo build — mixing both forces the audience to track two integration models in parallel. The full constraint-by-constraint decision table is owned by [references/mock-deltas.md](references/mock-deltas.md) §"When to use this flavor".

- **No BC tenant in scope** (partner handover, offline laptop), one inbound direction → DB-staged mock, this skill: [references/mock-deltas.md](references/mock-deltas.md).
- **No BC tenant, and the beat is the ROUND TRIP** — orders leaving, an ERP document number coming back, a status flip on the customer's order list → two-directional mock, this skill: [references/two-way-mock.md](references/two-way-mock.md). Four shipped-provider activities, zero custom code.
- **Real BC tenant + credentials in scope** → live BC, sister skill: [`dw-integration-bc`](../dw-integration-bc/SKILL.md).

The flavors demonstrate DIFFERENT demo beats: the one-direction mock shows "the PIM responds to BC-sourced data" (staged state + action rule as evidence); the two-directional mock runs the round trip on camera against staged ERP tables; live BC shows the actual wire. Choose deliberately.

## Where to find things

| If you need to... | Read this reference |
|---|---|
| Internalise the source/target rule + anti-patterns + Integration Framework primer | references/integration-framework.md |
| Stage demo data in the post-BC-sync state, wire the RESET scheduled task, and choose an execution option (narrate / RunSql / a real `SqlProvider`→`EcomProvider` activity when the evidence is the storefront) | references/mock-deltas.md |
| Run the sync in BOTH directions on camera with no custom code: four shipped-provider activities, the order-state flip, the document-number writeback, and a reset that does not re-arm the export | references/two-way-mock.md |
| Look up which DW10 fields the ERP typically writes vs reads from PIM (the generic shape), and why a derived fact belongs in the feed | references/erp-data-shape.md |
| Plan ERP beats BEFORE the build (the `<demo>-Scenarios.xlsx` pattern) | references/scenarios-first-planning.md |
| Run the live-BC path (ngrok + ForwardedHeaders + AppStore connector + `/admin/api/BC*`) | [`../dw-integration-bc/SKILL.md`](../dw-integration-bc/SKILL.md) |

## Inherited from dw-demo-base

This skill assumes `dw-demo-base` ran first. Four rules apply at all times and are NOT restated here -- see the owning reference in base for each:

| Rule | Owner |
|------|-------|
| Per-demo artifact download + path-resolution rule | [dw-demo-base/SKILL.md "Path-resolution rule"](../dw-demo-base/SKILL.md) |
| The customer-context read-only contract | [dw-demo-base/references/customer-context.md](../dw-demo-base/references/customer-context.md) |
| The customisations-ledger preflight | [dw-demo-base/references/customisations.md](../dw-demo-base/references/customisations.md) |
| The baseline-drift self-diagnosis rule | [dw-demo-base/SKILL.md "Self-diagnosis rule"](../dw-demo-base/SKILL.md) |

**Customisations note**: the DB-staged mock runs on built-in add-ins only -- a `JobScheduledTaskAddIn` activity, or `RunSqlScheduledTaskAddIn` (in `Dynamicweb.Core`) where its run result is independently verified -- so no custom code and no `CUSTOMISATIONS.md` row is required. The `<demo>/.planning/stage-and-reset.ps1` is build-time tooling, not demo-runtime customisation. A custom `IntegrationProvider` class under `Providers/` (live flavor) DOES need a row; the live-flavor controller customisations are documented in `dw-integration-bc`.

## Sister skills

- **`dw-demo-base`** -- foundation skill (Use FIRST). Owns setup, MCP connection, per-demo artifact download, customisations ledger, customer-context contract.
- **`dw-demo-pim`** -- PIM modelling (variants, BOM, channels, completeness rules, dashboards). The ERP integrates AGAINST a modelled PIM; you usually want the PIM model in place before wiring the ERP.
- **`dw-demo-swift`** -- Swift frontend, customer center, re-skin. Order beats that flow PIM -> Swift -> ERP live in Swift's customer center playbook.
- **`dw-integration-bc`** -- live BC via ngrok + AppStore PIM-for-BC connector. Use INSTEAD OF this skill's mock-delta flow when a real BC tenant is in scope.

A sibling skill that runs without `dw-demo-base`'s outputs (no `.mcp.json`, no `CUSTOMISATIONS.md`) silently no-ops or produces broken artefacts.

