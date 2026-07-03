---
name: dw-integration-bc
type: flow
group: integration
description: Dynamicweb 10 live "PIM for Business Central connector" demos -- expose the local DW host publicly via ngrok so a real BC tenant can call the connector's `/admin/api/BC*` surface. Triggers: "connect BC to the local Dynamicweb host", "give BC a real URL", expose localhost publicly for a connector demo, `Unknown query`/`Unknown command` errors from `BC*` endpoints, connector defaults wrong after AppStore install, BC's Test Connection is green but no products appear, StaticLinkManager errors on "show PIM product page". Non-triggers: PIM data modelling -> dw-demo-pim; DB-mocked ERP sync without a live tenant -> dw-demo-erp; demo setup/MCP/TLS -> dw-demo-base. Use AFTER dw-demo-base (assumes MCP connected, host up).
---

# Dynamicweb PIM for Business Central Connector skill

Expose the local Dynamicweb host as a stable public HTTPS URL so a real Business Central tenant can connect through the **PIM for Business Central connector** AppStore app. Covers the four pieces that have to line up: ngrok tunnel, ASP.NET Core `ForwardedHeaders`, BC connector settings (the AppStore app's defaults are usually wrong), and the BC-side configuration values.

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
- "Expose `https://localhost:31873` publicly with a stable URL" -- ngrok recipe applies more broadly than just BC, but the BC connector is the most demanding consumer because it expects absolute URLs to round-trip cleanly (hence `ForwardedHeaders`).
- The first BC call returns 400 with `{"successful":false,"message":"Unknown query: 'X'"}` -- naming-convention question, see [references/connector-endpoints.md](references/connector-endpoints.md).
- The BC connector errors with "index build key not found" (or a similar settings-shaped failure) -- the AppStore app's `BCSetupUpdateProvider` populates defaults that don't match what's actually in your project. See [references/dynamicweb-connector-settings.md](references/dynamicweb-connector-settings.md).
- "BC connects (green Test Connection) but no products appear" -- the canonical missing-column-mappings stuck state. BC's connector polls `BCLicense` / `BCSettings` / `BCProductFields` / `BCProductCountByLastModified` indefinitely without ever calling `BCProductIdsByLastModified`. See [references/bc-side-config.md](references/bc-side-config.md) "Field mapping setup -- REQUIRED, not optional".
- BC's "show PIM product page" feature fails with `Unknown command: 'StaticLinkSave'` (AddIn missing) or a `TypeInitializationException` (AddIn installed but host not restarted). See [references/static-link-manager.md](references/static-link-manager.md). The `StaticLinkManager` AppStore AddIn is a separate package from the BC connector and is NOT installed by default in `dw10-suite` template scaffolds.

If the trigger is setup-shaped (host won't start, MCP empty, TLS handshake failing), it belongs in `dynamicweb-demo-base`, not here. PIM modelling questions belong in `dynamicweb-pim-demo`. Frontend re-skin and Swift questions belong in `dynamicweb-swift-demo`.

## Where to find things

Each reference is owned end-to-end by a single topic; cross-references between them are explicit.

| If you need to... | Read this reference |
|---|---|
| Bring the public tunnel up against the HTTP launch profile | references/tunnel.md |
| Wire `ForwardedHeaders` in `Program.cs` so DW emits public URLs | references/forwarded-headers.md |
| Look up the exact `/admin/api/BC*` endpoint names + call convention | references/connector-endpoints.md |
| Fix the AppStore connector's wrong defaults (`indexBuildKey` / `buildName` / `workflowStateId`) | references/dynamicweb-connector-settings.md |
| Configure the **Business Central** side (URL + bearer token + first sync) | references/bc-side-config.md |
| Diagnose / install the `StaticLinkManager` AddIn that BC's "show PIM product page" feature requires | references/static-link-manager.md |

## Inherited from dynamicweb-demo-base

This skill assumes `dynamicweb-demo-base` ran first. Four rules apply at all times and are NOT restated here:

| Rule | Owner |
|------|-------|
| Per-demo artifact download + path-resolution rule | [dynamicweb-demo-base/SKILL.md "Path-resolution rule"](../dw-demo-base/SKILL.md) |
| The customer-context read-only contract | [dynamicweb-demo-base/references/customer-context.md](../dw-demo-base/references/customer-context.md) |
| The customisations-ledger preflight | [dynamicweb-demo-base/references/customisations.md](../dw-demo-base/references/customisations.md) |
| The baseline-drift self-diagnosis rule | [dynamicweb-demo-base/SKILL.md "Self-diagnosis rule"](../dw-demo-base/SKILL.md) |

**Customisations note**: `Program.cs` edits to add `ForwardedHeaders` middleware ARE customisations and need a row in `CUSTOMISATIONS.md`. The recipe in [references/forwarded-headers.md](references/forwarded-headers.md) calls this out and provides the exact ledger entry to write.

## Sister skills

- **`dynamicweb-demo-base`** -- foundation skill (Use FIRST). Owns setup, MCP connection, per-demo artifact download, customisations ledger, customer-context contract.
- **`dynamicweb-pim-demo`** -- PIM modelling, structural mental model, completeness rules, dashboards.
- **`dynamicweb-swift-demo`** -- Swift frontend, customer center, re-skin recipe.

A sibling skill that runs without `dynamicweb-demo-base`'s outputs (no `.mcp.json`, no `CUSTOMISATIONS.md`) silently no-ops or produces broken artefacts.

## Vendor patterns

The vendor skill-repo consultation outcome (`dynamicweb/skills` + `dynamicweb/ai-implementor-skills`) is documented in [dynamicweb-demo-base/references/vendor-patterns.md](../dw-demo-base/references/vendor-patterns.md). Single source of truth for vendor positioning across PIM, Swift, and BC connector skills.




