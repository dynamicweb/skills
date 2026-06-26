---
description: Native orchestrator — scaffold a Dynamicweb 10 demo (defers to GSD if present)
argument-hint: <prospect-slug> [--standalone]
---

You are the **native demo orchestrator**, scaffold phase. The full abstraction (modes,
detection, acceptance criteria) lives in the installed `dw-demo-base` skill at
`references/orchestrator.md` — read it if anything below is ambiguous.

## 1. Detect GSD and defer

Check for GSD: does `.planning/` exist, or a `/gsd-*` command surface (`commands/gsd/`)?

- **GSD present AND `--standalone` not in `$ARGUMENTS`** → print:
  > GSD detected. Use it for higher assurance (fresh-context agents + convergence loop):
  > `/gsd-new-project` → roadmap (scaffold → customer build → polish), then `/gsd-discuss-phase`.
  > Register the demo skills via the `agent_skills` block in
  > `dw-demo-base/assets/agent_skills.config.json`. To force the native path anyway, re-run with
  > `--standalone`.
  Then **STOP**. Do not act.
- **GSD absent, or `--standalone` passed** → continue.

## 2. Create the native state

Parse the prospect slug from `$ARGUMENTS`. Create `.demo/<slug>/state.json`:

```json
{ "phase": "scaffold", "impact_signed_off": false }
```

## 3. Run the scaffold skills (substrate)

Invoke `dw-demo-base` and run its canonical end-to-end flow (environment checks → scaffold the
`Dynamicweb.Host.Suite` host → wire MCP + the TLS bypass → drop the guardrail artefacts). Then
load the data per demo type:

- **PIM demo** → `dw-demo-pim` (blank DB, model via MCP).
- **Swift demo** → `dw-demo-swift` deserialize the baseline.

The skills own the recipes and their own verification gates; this command only sequences them.

## 4. Single-pass health check (acceptance — scaffold phase)

One pass, no convergence loop. Confirm: host boots and `/Admin` returns 200; MCP connected
(`claude mcp list` = `Connected`, `ToolSearch +dynamicweb` > 200 tools); PIM product count above
the demo's threshold; the storyline's key pages render; the Delivery API (`/dwapi/`) responds.

On any miss, **surface it and ask** the user how to proceed — do not silently advance. State
that this is a single-pass check and GSD is the stronger orchestrator for high-stakes demos.

## 5. Advance

On PASS, set `state.json` `phase` to `impact` and tell the user the next command is
`/demo:impact`.
