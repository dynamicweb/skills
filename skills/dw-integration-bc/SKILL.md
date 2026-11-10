---
name: dw-integration-bc
type: flow
group: integration
mcp: required
dynamo: false
description: 'Connect live Business Central to a DW10 PIM demo through the PIM for Business Central connector. Triggers: BC* unknown query/command, green Test Connection but no products, StaticLinkManager, connector defaults. Use AFTER dw-demo-base.'
---

# Dynamicweb PIM for Business Central Connector skill

## MCP preflight

This skill drives the Dynamicweb MCP server — its steps are rung-1 tool calls. Before starting,
verify the Dynamicweb MCP tools are available. If they are not, say so and pick the next rung
deliberately: the Management API at `/admin/api/...` reaches the same domain services, and the
serializer carries bulk, id-preserving loads. Direct SQL is local-install only and out of scope for
these steps; guessed HTTP calls and file edits substitute for nothing. Ladder:
[`dw-data-access`](../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance".

Connect a real Business Central tenant to a Dynamicweb host through the **PIM for Business Central connector** AppStore app. Covers the pieces that have to line up on the platform side: the connector's endpoints, its settings (the AppStore app's defaults are usually wrong), the BC-side configuration values, and the `StaticLinkManager` AddIn.

**Prerequisite, not covered here: a public HTTPS URL.** The BC tenant calls the host over the internet, so the host must answer on a public HTTPS address and must see that public scheme and host name on each request, because the connector hands absolute URLs back to BC. A hosted install has this already. How a local host is published (a reverse proxy, a tunnel) is infrastructure outside this skill.

This SKILL.md is a nav layer. Each topic links to a `references/<topic>.md` that owns the verbatim recipe.

## How to run me

This skill holds domain knowledge, not build sequencing. An **orchestrator** owns the phase
order: GSD injects this skill into its agents (via the `agent_skills` block), or the native
`/demo:*` command set invokes it; **standalone**, the skill's own lightweight harness guards its
documented order (gate every step, persist progress to `.demo/<slug>/flow-state.json`). The
orchestrator abstraction (GSD primary, native command set, and the standalone harness) is owned by
[`../dw-demo-base/references/orchestrator.md`](../dw-demo-base/references/orchestrator.md).

## When to use this skill

These trigger shapes route here:

- "Connect BC to the local Dynamicweb host" / "give BC a real URL during the demo" -- the canonical use case.
- After installing the **PIM for Business Central connector** AppStore app and asking "what endpoints did this expose" -- the connector publishes 11 queries + 4 commands under `/admin/api/BC*`.
- The first BC call returns 400 with `{"successful":false,"message":"Unknown query: 'X'"}` -- naming-convention question, see [references/connector-endpoints.md](references/connector-endpoints.md).
- The BC connector errors with "index build key not found" (or a similar settings-shaped failure) -- the AppStore app's `BCSetupUpdateProvider` populates defaults that don't match what's actually in your project. See [references/dynamicweb-connector-settings.md](references/dynamicweb-connector-settings.md).
- "BC connects (green Test Connection) but no products appear" -- the canonical missing-column-mappings stuck state. BC's connector polls `BCLicense` / `BCSettings` / `BCProductFields` / `BCProductCountByLastModified` indefinitely without ever calling `BCProductIdsByLastModified`. See [references/bc-side-config.md](references/bc-side-config.md) "Field mapping setup -- REQUIRED, not optional".
- BC's "show PIM product page" feature fails with `Unknown command: 'StaticLinkSave'` (AddIn missing) or a `TypeInitializationException` (AddIn installed but host not restarted). See [references/static-link-manager.md](references/static-link-manager.md). The `StaticLinkManager` AppStore AddIn is a separate package from the BC connector and is NOT installed by default in `dw10-suite` template scaffolds.

If the trigger is setup-shaped (host won't start, MCP empty, TLS handshake failing), it belongs in `dw-demo-base`, not here. PIM modelling questions belong in `dw-demo-pim`. Frontend re-skin and Swift questions belong in `dw-demo-swift`.

## Where to find things

Each reference is owned end-to-end by a single topic; cross-references between them are explicit.

| If you need to... | Read this reference |
|---|---|
| Look up the exact `/admin/api/BC*` endpoint names + call convention | references/connector-endpoints.md |
| Fix the AppStore connector's wrong defaults (`indexBuildKey` / `buildName` / `workflowStateId`) | references/dynamicweb-connector-settings.md |
| Configure the **Business Central** side (URL + bearer token + first sync) | references/bc-side-config.md |
| Diagnose / install the `StaticLinkManager` AddIn that BC's "show PIM product page" feature requires | references/static-link-manager.md |

## Inherited from dw-demo-base

This skill assumes `dw-demo-base` ran first. Four rules apply at all times and are NOT restated here:

| Rule | Owner |
|------|-------|
| Per-demo artifact download + path-resolution rule | [dw-demo-base/SKILL.md "Path-resolution rule"](../dw-demo-base/SKILL.md) |
| The customer-context read-only contract | [dw-demo-base/references/customer-context.md](../dw-demo-base/references/customer-context.md) |
| The customisations-ledger preflight | [dw-demo-base/references/customisations.md](../dw-demo-base/references/customisations.md) |
| The baseline-drift self-diagnosis rule | [dw-demo-base/SKILL.md "Self-diagnosis rule"](../dw-demo-base/SKILL.md) |

## Sister skills

- **`dw-demo-base`** -- foundation skill (Use FIRST). Owns setup, MCP connection, per-demo artifact download, customisations ledger, customer-context contract.
- **`dw-demo-pim`** -- PIM modelling, structural mental model, completeness rules, dashboards.
- **`dw-demo-swift`** -- Swift frontend, customer center, re-skin recipe.

A sibling skill that runs without `dw-demo-base`'s outputs (no `.mcp.json`, no `CUSTOMISATIONS.md`) silently no-ops or produces broken artefacts.

