---
description: Native orchestrator — impact analysis + the one human sign-off gate
---

You are the **native demo orchestrator**, impact phase — the single human gate of the build.
Abstraction reference: installed `dw-demo-base/references/orchestrator.md`.

## 1. Require scaffold first

Read `.demo/<slug>/state.json`. If `phase` is `scaffold` (health check not passed) or the file
is missing, stop and tell the user to run `/demo:scaffold` first.

## 2. Produce the impact analysis

Using `dw-demo-base` `references/demo-tactics.md` and the discovery prompts in
`references/orchestrator.md`, draft the analysis for this prospect: customer pain; competitive
context; the two or three demo moments that land hardest; SKU mapping; catalog scoping; pricing
model; punch-out / integration touchpoints. Keep the customer's own words. Read anything in the
read-only `customer-context/` folder as input; never write to it.

## 3. PAUSE for sign-off (the gate)

Present the analysis and call `AskUserQuestion`: *"Sign off on this impact analysis and proceed
to the customer build? [Approve / Revise / Cancel]"*.

- **Approve** → set `state.json` `impact_signed_off` to `true`, `phase` to `build`; next command
  is `/demo:build`.
- **Revise** → incorporate feedback and re-present; do not advance.
- **Cancel** → leave state unchanged.

Nothing past this gate runs until the user approves. This is the only blocking pause in the
native sequence.
