# Roadmap — <prospect-slug> demo

Three phases. The orchestrator (GSD or the native `/demo:*` command set) drives these; the
phases hold no recipes — those live in the demo skills. See
`dw-demo-base/references/orchestrator.md`.

## Phase 1 — Scaffold

Stand up the substrate. Host (`Dynamicweb.Host.Suite`) + DB + MCP + TLS bypass + guardrail
artefacts via `dw-demo-base`; then load data (`dw-demo-pim` for a PIM demo, `dw-demo-swift`
deserialize for a Swift demo).

- **Enforcement:** automated. GSD — execute → verify → `VERIFICATION.md`, then `/gsd-audit-fix`.
  Native — single-pass health check.
- **Acceptance (scaffold):** host boots / `/Admin` 200; MCP connected (> 200 tools); PIM count
  above threshold; key pages render; Delivery API responds.

## Phase 2 — Customer build

The one human gate sits at this phase's start. Produce the impact analysis (customer pain,
competitive context, the hardest-landing demo moments, SKU mapping, catalog scoping, pricing,
punch-out) and **sign off** before building. Then build the customer-specific elements
(customer-center, personas, pricing, re-skin, integration beats) from the signed-off analysis.

- **Enforcement:** human sign-off on the analysis, then automated build + validate. GSD —
  `/gsd-discuss-phase` (approval gate) → `/gsd-plan-phase --bounce` → execute → verify. Native —
  `/demo:impact` pause → `/demo:build` single validate + offered fix.
- **Acceptance (customer build):** every signed-off demo moment reachable live; personas log in
  (floor of 2); customer pricing resolves in the cart; re-skin reads as the brand; ledger
  accounts for every custom-code row.

## Phase 3 — Polish

Freeform. No gate, no validation loop. GSD — `/gsd-quick` / `/gsd-fast` / `/gsd-verify-work`.
Native — by hand.

- **Acceptance (polish):** no broken links on the storyline path; no placeholder content on
  visited pages; the demo runs end-to-end in one pass.
