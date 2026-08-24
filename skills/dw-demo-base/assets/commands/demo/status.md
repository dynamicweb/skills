---
description: Native orchestrator — print the demo's current phase and the next command
argument-hint: [<prospect-slug>]
---

Read-only. Do not change any state.

1. Find the demo state: `.demo/<slug>/state.json` (use the slug in `$ARGUMENTS`, or the single
   folder under `.demo/` if there is only one). If none exists, say so and point to
   `/demo:scaffold <slug>`.
2. Print, in a compact block:
   - **Prospect**: `<slug>`
   - **Phase**: `<phase>` (scaffold → impact → build → polish)
   - **Impact signed off**: yes/no
   - **Next command**: derive from phase — `scaffold`→`/demo:impact`, `impact`→`/demo:build`
     (only if signed off, else `/demo:impact` to sign off), `build`→`/demo:build` for the fix
     pass or polish freeform, `polish`→done.
3. If a GSD `.planning/` directory is present, note that the build can also be driven through the
   `/gsd-*` flow.
