---
description: Native orchestrator — scaffold a Dynamicweb 10 demo
argument-hint: <prospect-slug>
---

You are the **native demo orchestrator**, scaffold phase. The full abstraction (modes,
gates, acceptance criteria) lives in the installed `dw-demo-base` skill at
`references/orchestrator.md` — read it if anything below is ambiguous.

## 1. Create the native state

Parse the prospect slug from `$ARGUMENTS`. Create `.demo/<slug>/state.json`:

```json
{ "phase": "scaffold", "impact_signed_off": false }
```

## 2. Run the scaffold skills (substrate)

Invoke `dw-demo-base` and run its canonical end-to-end flow (environment checks → scaffold the
`Dynamicweb.Host.Suite` host → wire MCP + the TLS bypass → drop the guardrail artefacts). Then
load the data per demo type:

- **PIM demo** → `dw-demo-pim` (blank DB, model via MCP).
- **Swift demo** → `dw-demo-swift` deserialize the baseline.

The skills own the recipes and their own verification gates; this command only sequences them.

## 3. Single-pass health check (acceptance — scaffold phase)

One pass, no convergence loop. Confirm: host boots and `/Admin` returns 200; MCP connected
(`claude mcp list` = `Connected`, `ToolSearch +dynamicweb` > 200 tools); PIM product count above
the demo's threshold; the storyline's key pages render; the Delivery API (`/dwapi/`) responds.

On any miss, **surface it and ask** the user how to proceed — do not silently advance. State
that this is a single-pass check.

## 4. Advance

On PASS, set `state.json` `phase` to `impact` and tell the user the next command is
`/demo:impact`.
