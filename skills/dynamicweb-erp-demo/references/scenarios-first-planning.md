# scenarios-first-planning.md

> Plan ERP beats BEFORE you build. The pattern: author a `<demo>-Scenarios.xlsx` (or `.md` if you don't want Excel) listing every demo scenario as one row, with explicit columns for ERP-side and PIM-side actions, BEFORE staging the database or wiring a connector. Loaded from `dynamicweb-erp-demo/SKILL.md` "Where to find things".

## Why scenarios first

The recurring failure mode without this artefact: the build starts ("let me wire BC and see what falls out"), the team discovers mid-build that scenario 3 needs a customer-contract-price beat they hadn't accounted for, and now the data model has to be retro-fitted with a per-customer price column. By the time scenario 5 lands you have three half-baked beats and one polished one.

Scenarios-first inverts this. The Excel/MD is authored in the customer-context phase (intro call notes + pitch outline) and lives at the solution root, where every demo-build agent reads it FIRST. Reference shape: `<demo>/<Demo>-Scenarios.xlsx` at the solution root + the PDF version under `customer-context/<Customer>_-_PIM_Scenarios_-_<date>_-_<lang>_-_V<n>.pdf` (the customer-context PDF is read-only per the customer-context contract; the working `.xlsx` at the solution root is your editable copy).

## The artefact location

```
<demo>/
    customer-context/
        <Customer>_-_PIM_Scenarios_-_<date>_-_<lang>_-_V<n>.pdf    # read-only, customer-provided
    <Demo>-Scenarios.xlsx                                          # working copy, editable
    .planning/stage-and-reset.ps1                                  # mock flavor: post-sync staging + RESET source
```

The PDF in `customer-context/` is the source of truth from the customer's side (per the customer-context read-only contract). The `.xlsx` at the solution root is your working copy where you flesh out the build-time details (delta IDs, MCP commands, fire order). If the customer hands over scenarios in another format (Confluence page, email thread, Powerpoint), put a Markdown extract at `<demo>/<Demo>-Scenarios.md` with the same column set -- the format isn't load-bearing, the shape is.

## One row = one scenario

Columns (typical shape, adapt as needed):

| Column | What goes here |
|---|---|
| Scenario # | 1, 2, 3... -- presentation order during the demo. |
| Title | Short label the presenter says out loud ("Quarterly pricelist correction"). |
| Trigger | What kicks off the scenario in the live demo. Two flavours: a presenter action ("click Approve in PIM") OR an external event modelled as a delta ("BC posts a price-update delta"). |
| Beat | The narrative beat in 1 sentence ("BC owns price; PIM displays read-only; ecommerce gets a sparse update"). |
| ERP-side action | What BC does (or what the staged post-sync state represents). E.g. "BC writes new defaultPrice for ROLL-COMFORT-PLUS, syncs to PIM via integration framework activity". |
| PIM-side action | What DW does in response. E.g. "PIM stores the new price; action rule X fires if condition Y holds; index rebuild; cache flush". |
| Frontend surface | Where the audience sees the result. E.g. "PDP at /shop/rollator-comfort-plus shows new price; dashboard widget 'Recent price changes' shows the delta". |
| Post-sync DB state | The mock-flavor pre/post field values this scenario stages (the [mock-deltas.md](mock-deltas.md) Step 1 rows). E.g. "PROD1 ProductPrice 249→229". Blank for live-flavor scenarios. |
| Notes / risk | Anything the build-time agent needs to know. E.g. "Action rule X must be re-saved through MCP after raw-SQL changes to GroupMetaUrl, see PIM-demo cache-invalidation.md". |

## What a good row looks like

> | # | Title | Trigger | Beat | ERP-side action | PIM-side action | Frontend surface | Delta files | Notes |
> |---|---|---|---|---|---|---|---|---|
> | 5 | Quarterly pricelist correction | Presenter says "BC just posted the Q3 pricelist" | BC owns price; PIM displays read-only; ecommerce gets a sparse update (only the changed field). | BC writes new defaultPrice for ROLL-COMFORT-PLUS (229 EUR) and ROLL-COMFORT-PRO (459 EUR). Mock: staged post-state + RESET row. Live: BC connector posts. | New price already staged; narrate the sync, rebuild Products index, flush price cache. | Dashboard widget 'Recent price changes' shows two rows; PDPs show new price. | PROD1 249→229, PROD2 449→459 | Index rebuild can take 5-15 sec; warn the presenter. |

A row without every active column filled is half-done and probably mis-scoped. The most-skipped column is "Frontend surface" -- if you can't say where the audience sees the result, the beat doesn't land.

## The build-time contract

Once the scenarios artefact is locked, the build follows it:

- One pre/post row set in the [mock-deltas.md](mock-deltas.md) Step 1 table (and one RESET `UPDATE`) per scenario row that fires from BC.
- ONE static field-mapping artefact total for the PIM->BC direction (mock-deltas.md Step 4) -- not one per scenario row.
- One action rule per scenario row that mentions "action rule" in PIM-side action.
- One dashboard widget per scenario row that needs a "watch this widget change" beat (and watch the [`../dynamicweb-pim-demo/references/governance.md`](../../dynamicweb-pim-demo/references/governance.md) rule: `RepositoryCountWidget` for drill-through, never `ScalarSqlCountWidget`).
- One customer-center / storefront page touch per scenario row that lists a frontend surface.

Each is a small, scoped artefact -- not 200 lines of speculative scaffolding. The "go deep, not wide" rule inherited from base means: only the scenarios drive the build. A paragraph type or page preset that no scenario row needs is wasted demo time.

## Cross-references

- The scenarios artefact informs the delta set: [mock-deltas.md](mock-deltas.md).
- It also informs the field shape: [erp-data-shape.md](erp-data-shape.md).
- The "go deep, not wide" demo philosophy: [`../dynamicweb-demo-base/SKILL.md`](../../dynamicweb-demo-base/SKILL.md) "Demo philosophy".
- The customer-context read-only contract that protects the customer-supplied PDF: [`../dynamicweb-demo-base/references/customer-context.md`](../../dynamicweb-demo-base/references/customer-context.md).
- Reference artefact shape: `<demo>/<Demo>-Scenarios.xlsx` + `customer-context/<Customer>_-_PIM_Scenarios_-_*.pdf`.
