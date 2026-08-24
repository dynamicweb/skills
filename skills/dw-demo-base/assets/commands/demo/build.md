---
description: Native orchestrator — build customer-specific elements, then single-pass validate
argument-hint: [--standalone]
---

You are the **native demo orchestrator**, customer-build phase. Abstraction reference: installed
`dw-demo-base/references/orchestrator.md`.

## 1. Detect GSD and defer

Same check as the other commands. If GSD is present and `--standalone` was not passed, print:
> GSD detected. Use `/gsd-plan-phase --bounce` → `/gsd-execute-phase` → verify for the convergence
> loop. Re-run with `--standalone` to force the native single pass.
Then **STOP**.

## 2. Require the sign-off

Read `.demo/<slug>/state.json`. If `impact_signed_off` is not `true`, **refuse** and tell the
user to run `/demo:impact` and sign off first. The build never runs on an unapproved analysis.

## 3. Build the customer-specific elements (substrate)

From the signed-off analysis, build the demo moments using the right skills:

- Customer-center, personas, pricing, re-skin → `dw-demo-swift`.
- Catalog scoping, assortments, completeness → `dw-demo-pim`.
- ERP / integration beats → `dw-demo-erp` (mock) or `dw-integration-bc` (live BC).

Honour the surface-priority rule (MCP → Management API → admin UI verify-only → SQL last resort)
and the `CUSTOMISATIONS.md` ledger preflight from `dw-demo-base`.

## 4. Single validation pass (acceptance — customer-build phase)

One pass against the acceptance criteria in `references/orchestrator.md`: every signed-off demo
moment is reachable in the live UI; personas log in (floor of 2); customer pricing resolves in
the cart; the re-skin reads as the customer's brand; the ledger accounts for every custom-code
row.

Surface every gap. **Offer a fix pass** (the user opts in) — do not loop automatically; that is
GSD's job. State the assurance level.

## 5. Advance

On PASS (or after the offered fix pass), set `state.json` `phase` to `polish`. Polish is
freeform — no gate, no validation.
