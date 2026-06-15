---
name: dynamicweb-business-solution-agent
description: >
  End-to-end Dynamicweb 10 plus Swift 2 solution orchestrator. Use when the user wants a full
  business solution from a plain-language request such as "I want a wine solution". The skill
  installs Swift 2 if needed, bootstraps MCP access, inspects the existing demo installation as a
  baseline, and then delegates to the business setup flow that replaces demo business data with the
  new business while preserving the working Swift 2 shell.
---

# Dynamicweb Business Solution Agent

## Objective
Go from a business request to a working Dynamicweb solution without a manual gap between:
- Swift 2 installation
- MCP bootstrap
- demo-site inspection
- business-specific setup

Treat the installed Swift 2 demo as a reference first and as disposable business data second.

## Delegates
- `dynamicweb-solution-installer` for Swift 2 installation and bootstrap manifest creation
- `dynamicweb-business-setup-agent` for site, catalog, PIM, and commerce customization

## Core Rules
- If Swift 2 is missing, install it first.
- Bootstrap MCP before attempting setup work.
- After bootstrap succeeds, add the Dynamicweb MCP server to the config used by the current agent.
- Treat MCP attachment as mandatory. The workflow is not complete until the active agent config contains the Dynamicweb server entry and the connection has been validated.
- If MCP attachment fails, stop, explain exactly what the user needs to do in the correct config file for the current agent, and resume only after that step is complete.
- Inspect the existing demo setup before deleting demo business data.
- Preserve the working Swift 2 shell: area, shop, core pages, navigation tags, checkout flow, and account flow.
- Only remove demo business data after the baseline has been captured.
- Enforce environment-independent link handling by default (no hardcoded `/en-us`, `/vinhuset`, or host-specific prefixes).

## Core Tools
- Site discovery: `GetAreas`, `GetShops`, `GetPagesByArea`
- Bootstrap validation: `GetAreas`
- Setup handoff context: `GetPageItemValues`, `GetAreaItemValues`, `GetNavigationStructure`
- Link portability handoff context: `GetPageByNavigationTag` and `FetchFrontendPageHtml` (`/Default.aspx?ID={shopPageId}`)

## Workflow

### 1. Parse the Request
Extract:
- business name
- industry
- product types
- primary market
- language
- currency

Default assumption: the user wants the demo business replaced, not kept alongside a new catalog.

### 2. Ask for a Permission Preset
Ask once, with `All` recommended:
- `All`
- `NonDestructive`
- `ReadOnly`

### 3. Ensure Swift 2 Exists
Check whether a Dynamicweb host with Swift 2 is already installed.

If not, delegate to `dynamicweb-solution-installer`.

### 4. Bootstrap MCP
Use the bootstrap manifest in `Files/System/mcp-bootstrap.json`.

Do not attempt bootstrap while Dynamicweb is redirecting `/admin` to `/admin/license`.
If the site is unlicensed, install a trial or real license first and only then continue.

Before calling bootstrap, verify the host is running on `net10.0`.
If `GET /admin/mcp` returns `404`, do not continue until both are true:
- `Custom.Mcp` is deployed under `Files/System/AddIns/Installed/Custom.Mcp.10.0.0`
- `GET /admin/mcp` returns `401` and `HEAD /admin/mcp/bootstrap` returns `405`

Preferred path:
1. call `POST /admin/mcp/bootstrap`
2. determine which agent is currently running the workflow
3. run `scripts/bootstrap-and-attach.ps1` so it writes the Dynamicweb MCP server into the config used by that agent
4. persist credentials outside the repo
5. validate the token by calling `GetAreas`

Agent-specific expectation:
- in Codex, write the Dynamicweb MCP server to `.codex/config.toml`
- in Claude Code, write the Dynamicweb MCP server to the Claude MCP config

Do not continue to setup work until the Dynamicweb MCP server has been attached to the current agent config.

Fallback path:
1. store the bootstrap response in a temp file
2. generate the exact MCP config snippet for the current agent
3. tell the user exactly which config file must be updated for that agent
4. write a resume manifest
5. on resume, verify that the server was added to the agent config, then validate MCP connectivity and continue

If automatic attachment fails at any point:
1. pause the workflow
2. explain the exact config change the user must make for the current agent
3. tell the user to come back after completing that step
4. resume only after verifying the Dynamicweb MCP server is present in the agent config and the connection works

### 5. Inspect the Demo Baseline
Before any destructive cleanup, capture the current example structure:
- area and shop
- page tree and navigation tags
- category structure
- payment, shipping, and order flow setup
- dashboard setup
- representative area and page item values when available

### 6. Delegate to Business Setup
Call `dynamicweb-business-setup-agent` with:
- parsed business details
- the instruction to inspect the demo baseline first
- the instruction to preserve the Swift 2 shell
- the instruction to remove demo business data only after baseline capture
- the instruction to detect canonical shop-root path and build custom links from that path

## Bootstrap Request Shape
```json
{
  "secret": "{secret-from-manifest}",
  "configurationName": "{businessName} MCP",
  "configurationDescription": "Bootstrapped configuration for {businessName}",
  "permissionPreset": "All"
}
```

## Persisted Bootstrap Fields
Store these fields in a temporary local file:
- `bearerToken`
- `configurationId`
- `configurationName`
- `serviceUserName`
- `serviceUserPassword`
- `permissionPreset`
- `grantedToolCount`

Never commit that file.

## Resume Support
Persist a run manifest at `{workspace}/.dw-setup-run.json` after each phase.

If the conversation restarts and the manifest exists, offer to resume.

## Success Criteria
- Swift 2 is installed and reachable
- the Dynamicweb host is running on `net10.0`
- bootstrap returns `201`
- the Dynamicweb MCP server is written into the config used by the current agent
- the returned bearer token can call `GetAreas`
- the setup agent receives the baseline-inspection requirement
- the setup agent receives and applies the link-portability requirement
- the final solution preserves the Swift 2 shell and replaces the demo business with the new one
