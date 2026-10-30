# Verification and evidence

## Read-only connection probe

Run [Test-BcConnection.ps1](../scripts/Test-BcConnection.ps1) with explicit company GUIDs.
It lists companies and samples items, customers, sales orders and invoices in each selected
company. Non-empty collection counts prove connectivity only. It does not prove the custom
price, ship-to, availability, credit or order-export contracts.

## Acceptance ladder

| Scenario ID | Required independent evidence |
|---|---|
| `authentication` | Environment identity, selected company and an authorised entity read |
| `products` | Source key and imported product read-back; PIM editorial fields preserved |
| `customers` | Source customer/contact and buyer's real parent account |
| ship_to | BC-managed plant/address belongs to the selected account; frontend creation policy |
| tier_prices | Base/group/customer examples, quantity/date/currency/UOM, rendered buyer price |
| `promotions` | Commerce promotion applies once over the agreed ERP base; ERP reconciliation |
| `inventory` | Company/location/item detail, available definition and timestamp, rendered aggregate |
| `fulfilment` | Selling and source companies, ship-to tax/legal policy, actual ERP routing result |
| `bundles` | Cart components, allocated totals, ERP lines and invoice components agree |
| `credit` | Allow/hold/deny/timeout plus concurrent recurrence attempts under the ERP decision contract |
| order_export | One source reference, one complete ERP order, independent line/total read-back |
| `status` | ERP state/line change and the correct existing platform order updated |
| `invoices` | Partial/multiple invoice links, content access as the correct buyer, cross-account denial |
| `replay` | Two runs and an ambiguous retry keep stable keys/counts; partial failure resumes |
| `isolation` | Duplicate numbers in another company/account cannot cross-price, cross-ship or expose documents |

Build a report from [the evidence template](../assets/templates/acceptance.example.json).
Each required scenario has exactly one result per selected company, `passed` as a JSON boolean,
two or more independent relative proof paths, mode, UTC timestamp and a concrete assertion.
Store proof files alongside the report. Use an order ID or customer number in the assertion;
do not place credentials, personal data dumps or endpoint authentication bodies in proofs.

Run [verify_bc_acceptance.py](../scripts/verify_bc_acceptance.py) from the skill directory:

```powershell
python scripts/verify_bc_acceptance.py --spec <integration-spec.json> --evidence <acceptance.json> --mode live --max-age-hours 24
```

The verifier checks report structure, coverage, company/environment binding, timestamp and
existing non-empty proof files. It refuses mock results for live acceptance. It cannot judge
whether a screenshot or capture proves its assertion; review those contents independently.
Synthetic fixtures and a successful offline test suite are not live integration acceptance.
Native financial contract probes also remain distinct from the business path: require an actual
approved completed Commerce origin, protected fresh full-hierarchy source, committed BC receipt,
posted component invoice, native platform return and authorised buyer detail. A native empty
invoice page proves configuration and page gates only. Test the same real detail URL as another
owner/account and ungranted CSR, including every query parameter. Report partial-document,
payment/credit return or concurrency cases as pending until their own evidence exists.

Helper compilation and fixtures do not prove Razor include resolution or live ViewModel rows.
After an approved stock-rendering exception, render default/each/case as anonymous and two
separate authorised accounts in each required language. Match native source rows, label,
visible options, quantity cap and prices. Prove a real variant, an existing natural zero that
disables quantity/step/Add controls, and native visual-editor fallback without saving. Keep
these actual proofs distinct from fixture counts. Preserve all existing carts/pointers; wait
for the actual native update and loading overlay to finish before capturing a settled screen.

A controlled application-identity post, one standing-mandate recurrence and its native invoice
return can establish those bounded paths. They do not cover every producer or scheduled
operation. Preserve the existing authority for each financial scope: where an exact run
requires separate operator approval, record it before execution. Selected cart/UI cases
cannot substitute for posted financial proof.

Posted alternate UOM is proved only by one real checkout whose lines carry the selected units
(for example each and case of one item) admitted, posted and returned: read `unitOfMeasureCode`,
quantity and amount of every posted `salesInvoiceLines` row, match them to the stored ledger
rows' unit, quantity and amount, confirm the customer balance moved by exactly the invoice and
the supplying location by exactly the base quantities, and render the invoice detail as the
owner in each language so the Unit cell shows the selected unit while default-unit rows stay
blank. Replay the frozen, expired request afterwards: the response must carry the replay flag,
the original request hash and the same invoice, and the document counts must not change.

Cart-preservation guards around buyer probes compare rows field by field: a native sign-in can
re-save the signed-in persona's active cart (new `OrderModified`, null line fields materialised
as empty strings) without changing lines, quantities, units, prices or pointers. Report that
re-save as a touch with its before/after values and keep every other field change as drift.
A hash over whole rows cannot tell the two apart.

## Version provenance

Capture the target's platform build, MCP build, installed BC extension versions, BC application
version and chosen API metadata with live results. The repository `versions.json` remains the
corpus compatibility statement. Offline validation does not advance its `measured` values
or `measuredAt`. An environment-specific statement belongs with that run's evidence until
the normal measured-release process accepts it.
