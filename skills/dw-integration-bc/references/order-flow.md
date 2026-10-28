# Orders out, status and invoices back

## Contents

- [Admit and export](#admit-and-export)
- [Financial transaction and posting boundary](#financial-transaction-and-posting-boundary)
- [Recover a posted document without rewriting its receipt](#recover-a-posted-document-without-rewriting-its-receipt)
- [Bring status back](#bring-status-back)
- [Bring invoices back](#bring-invoices-back)
- [Native persisted invoice import](#native-persisted-invoice-import)
- [Numbering and native customer-center pages](#numbering-and-native-customer-center-pages)
- [Required failure rehearsal](#required-failure-rehearsal)

## Admit and export

Keep a durable export ledger keyed by tenant/environment/selling company plus Commerce order
ID. Store the request fingerprint, producer release, BC document GUID/number, acknowledged
component lines and last error. Keep protected source captures beside that binding; use a
supported ledger or provider extension rather than an in-memory flag.

Queue explicitly completed native orders only. Independently check complete, cart, quote,
deleted and recurring-template flags; the thin MCP projection can omit these and BOM children.
Bind the purchasing principal, account and approval to a protected producer release. Resolve
sold-to/bill-to, BC-managed ship-to, currency, sale UOM and the supplying/invoicing company before
export. Freeze the full native header, persisted hierarchy, independent rich line amounts,
reviewed catalogue map and normalized economic snapshot. Expand phantom bundles and allocate
all discounts before calculating the fingerprint. A saved JSON file alone is not a fresh native
source read. Recompute from the current complete hierarchy before financial admission or return.

Choose one order writer:

| Surface | Configuration / sequence | Success proof |
|---|---|---|
| ERP plug-in / Live Integration | Use the installed shop/company request and response contract | ERP document and all accepted lines independently read back |
| BC published pages | Adapt the OData export blueprint to the company-scoped service | Header and lines reconciled by stable source reference |
| BC standard API | POST company salesOrders and lines, or a measured deep insert | Persist header ID; verify every line and final total |
| Approved BC extension | Unique source request, company route, locked credit admission and receipt in one reviewed transaction | Committed receipt plus independent native document/line read-back |

On the standard API path, `externalDocumentNumber` can carry a source reference but is not a
promised unique idempotency key. Serialise exports for the source key. Concurrent exactly-once
admission needs an ERP-side unique request key or equivalent atomic contract. Reconcile an
ambiguous timeout by committed receipt, company and source reference before retrying.

A source-wide route registry can prevent the same Commerce order from being submitted to two
companies. Commit that route with its company-local receipt and native document; separate commits
leave a route stranded or permit duplicate admission. Hash canonical economic fields with an
explicit schema/ordering policy. Replaying the same approved request retains identity; a changed
commercial snapshot is a conflict requiring a new approval, not an overwrite.

When a line fails, retain any acknowledged native IDs and reconcile the incomplete draft; do
not create a second header. Set `OrderIntegrationOrderId` and exported state only after complete
ERP acknowledgement. Inspect source-provider side effects: a provider marking an order exported
while staging is not an ERP receipt. Initial order acceptance, shipment and posting are separate
states and operations.

## Financial transaction and posting boundary

Keep customer credit, stock/source locks, request receipt and native order creation within the
reviewed BC transaction. Use one lock order across submit, post, reset and event subscribers;
order cross-company source/destination item locks consistently. Recheck live exposure and
availability after obtaining the locks. A preceding HTTP credit check cannot reserve exposure
for concurrent attempts by itself.

Read recovery receipts with an explicit committed isolation policy. An uncommitted receipt can
briefly report accepted or invoiced while the financial transaction later rolls back. Where
applicable, set `Record.ReadIsolation` to `IsolationLevel::ReadCommitted` and treat a blocked/timed-out
read as unknown until reconciliation succeeds.

Before posting, reconcile the native header and every accepted line to the stored immutable
snapshot, including account, company/route, currency, source references, SKU/UOM, quantity and
amounts. Matching only the total permits an economic or identity substitution. Repeat the checks
against the resulting posted invoice. Preserve the original accepted header/line fingerprint.

Review native posting and all installed subscribers for transaction boundaries. A Boolean-return
`Codeunit.Run` can commit implicitly; `CommitBehavior` does not suppress that implicit boundary.
Use the reviewed non-Boolean throwing call where the design requires an enclosing transaction,
and native suppress-commit support where available. Those choices still need a target-build
failure injection after native posting. Independently verify invoice, customer/item ledgers,
stock, balances, route and receipt after rollback. A successful posting return alone proves none
of that rollback behaviour. Installed read dependencies are covered in
[endpoints-and-auth.md](endpoints-and-auth.md).

A bounded reset uses the native corrective credit/cancellation process for a posted invoice,
then reconciles its linked entries. Restrict test resets to owned proof references and fully
applied native correction links. Preserve the financial audit trail; deleting receipt or posted
ledger rows is not a reset.

## Recover a posted document without rewriting its receipt

A native operator can finish posting after an application-side attempt was held. Reconcile the
resulting invoice and shipment through the immutable accepted route, customer, source references,
currency, location and every header/line economic field. Require the complete accepted component
census, quantities, prices, discounts and totals; hold multiple, partial or extra economic lines.
A draft-invoice identity is not a promised sales-order GUID, and the posted header may not expose
the original order GUID. Discover and verify the actual document relations.

A read-only recovery response may then report the native invoice while its persisted request
receipt still says accepted. Return the recovered document identity and explicitly state whether
the receipt was updated. Keep the durable receipt and recovered observation distinguishable on
replay. An existing operator's successful post proves neither the application's unattended posting
permissions nor a completed Commerce invoice return. Keep those acceptance checks separate.

## Bring status back

Poll or read confirmed live documents in the same company. Map BC facts to existing platform
workflow IDs and pin the permitted worker transitions in the private binding. Distinguish ERP
acceptance, release, shipment, invoice and cancellation; the standard order status alone may not
express each state. Preserve fulfilment history after an unposted order disappears.

Use update-only mappings for the original order, scoped by company and source identity. Read
state metadata before changing it and exclude states that send an unintended email. Re-read the
original financial/address flags and complete hierarchy around the status write. A native
order-service state save can materialise a null top-level `OrderParentOrderId` as an empty string.
Permit precisely that root-order equivalence when measured; hold a foreign parent or any
financial/line change. [dw 10.29.8]

A missing ERP row is unknown, not cancellation. Importing an invoice and changing the original status are
separate platform operations; use a durable replayable checkpoint rather than claiming combined
atomicity. An unchanged replay keeps keys, counts, amounts and state stable.

## Bring invoices back

Choose live Integration Customer Center documents or a persisted native invoice import. Keep
invoices as ledger documents separate from the original order. Persist company plus native
invoice GUID as identity; an invoice number alone can collide between companies. Retain number,
original order link, owner/customer, currency, due date, tax, full amount and each component line.
Discover the actual order-to-invoice relation; matching customer and amount is insufficient.

BC API `salesInvoices(<id>)/pdfDocument` supplies metadata. Follow its content link server-side
with ERP authentication, then authorise the buyer against the account, original order and company.
Keep capabilities and tokens out of browser URLs and public Files paths. An unpaid invoice must
not acquire a payment-completion date. Use an agreed receivable source for settlement.

## Native persisted invoice import

On the measured native surface, Management API `InvoiceSave` (`/admin/api/InvoiceSave`) sets `OrderReference` from
`InvoiceNumber`, maps `RefId` to `CustomerRefId`, adds a fixed total line on each call and does not set
`OrderParentOrderId`. Its projection alone is insufficient for an idempotent component invoice.
Discover the installed schema and implementation before relying on those field names. [dw 10.29.8]

Native Integration Framework `OrderProvider` exposes `EcomOrders` and `EcomOrderLines`; `EcomProvider`
on that surface does not expose order tables. A dedicated XML-to-`OrderProvider` activity can map
one new ledger header plus the real native BC invoice component lines. Use company/invoice/line
qualified deterministic IDs, actual `OrderParentOrderId`, `OrderIsLedgerEntry`, `OrderLedgerType=Invoice`,
`OrderReference` and explicit source net/tax/gross amounts. Native fixed line type (`2`) preserves a posted
component amount when that provider contract is verified. Retain SKU, product/variant, sale UOM
and quantity; leave phantom parents out. Discounts already included in native net amounts are
not reapplied as Commerce promotions. Reconcile line sums and the complete original total.

Use protected `App_Data` staging and one native transaction. Disable missing-row removal,
duplicate discard and successful-row persistence on failures. Pin mappings and source path, lock
the return worker for its owned order, and fail before altering a divergent existing ledger.
An identical completed ledger replay needs no import. Pin the queued native log and its actual
provider completion markers. The measured `OrderProvider` logs `Finished import to temporary table
for <table>.` and `Job succeeded.` without the `EcomProvider` affected-row counter strings. Record
expected counts separately and independently reconcile the exact stored header/line census and
every parent/owner/flag/amount field. Then check Management API `InvoiceList` (`/admin/api/InvoiceList`)
and buyer detail. [dw 10.29.8] Local-install read-only storage verification is a last rung when actual projections
omit those fields; it does not authorise a SQL write or a hosted-store fallback.

Prove the first full invoice before enabling partial invoices, multiple invoices, payment or
credit return. Native posting/rollback contract probes without a real approved completed Commerce
origin cannot establish an end-to-end return. Mock EA/case line transforms establish no native
posting or buyer acceptance.

## Numbering and native customer-center pages

Preflight the actual native numbering source before cloning shipping/payment/state entities.
A lagging Commerce counter can allocate an already-used ID and a native save can overwrite the
existing row. Capture the complete owned baseline, compare allocated IDs with existing keys,
repair the counter through its supported native command when authorised, and verify both donor
and new entity. A plausible copy response is not a collision proof. Deterministic invoice IDs
still require ownership/conflict checks before their first write.

Native content page identities are separate from Commerce numbering. Use existing Account,
CSR and Personal Orders shells with native invoice templates and keep their role gates and
`UseCustomerNumber`, `UseImpersonationIds` and `UseUserID` scopes. Generic `OrderListTemplate` and
`DetailTemplate` keys apply to `LedgerEntry` apps. An installed MCP `copy_page` can fail under a
strict no-standard-pages host when `CopyPageInfo` omits `ItemType`. Keep that gate: native MCP
`save_pages` with the source item type plus `copy_grid_row` can create the typed page and copy its
app body. Journal page/paragraph/grid IDs and automatic language mirrors before configuration,
configure unpublished, read back all settings/permissions, then publish. Preserve the source
body, inherited header and sibling order, and detect automatic mirrors before another copy.

The shipped invoice-history list provides a read-only View action. Its detail renders Comment
and real SKU/UOM/quantity lines, but has no `ParentOrderId` hyperlink and labels `CompletedDate` as
Payment date. Preserve the stored original-order relation and distinguish it from an actual UI
link. Test the authorised positive and wrong-role/anonymous negative on the same page IDs.
Empty-view gates do not prove invoice-detail isolation; repeat with an actual owned invoice and
all detail query parameters as another owner, account and CSR scope.

## Required failure rehearsal

Interrupt after header, after one line and after native posting; repeat an accepted request;
time out after acceptance; deny or expire credit; race two attempts; alter an accepted native
header or line; submit the same source to another company; and exercise native reversal.
Retain one coherent financial record and audit trail. Then return an actual approved completed
Commerce order's invoice, prove component totals and buyer isolation, and rehearse partial and
multiple documents wherever required by the agreed contract.

Sources: [sales order API](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/resources/dynamics_salesorder),
[`Record.ReadIsolation`](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/methods-auto/record/record-readisolation-method),
[`Codeunit.Run` transaction semantics](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/methods-auto/codeunit/codeunit-run-method),
[invoice PDF](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/api/dynamics_salesinvoice_pdfdocument),
[Integration Customer Center](https://doc.dynamicweb.dev/documentation/implementing/content/apps/integration-customer-center-app.html).
