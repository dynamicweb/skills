# Orders out, status and invoices back

## Admit and export

Keep a durable export ledger keyed by tenant/environment/selling company plus Commerce order
ID. Store the request fingerprint, attempt ID, BC document GUID/number, acknowledged component
lines and last error. Use a supported ledger or provider extension, not an in-memory flag.

Queue completed orders only: exclude carts, quotes, ledger documents, already acknowledged
orders and orders still awaiting approval or credit. Freeze the accepted commercial snapshot.
Resolve sold-to/bill-to, BC-managed ship-to, currency, UOM and fulfilment route before export.
Expand phantom bundles and allocate all discounts before calculating the payload fingerprint.

Choose one order writer:

| Surface | Configuration / sequence | Success proof |
|---|---|---|
| ERP plug-in / Live Integration | Enable supported order transfer for the selected shop and company; use the installed request/response contract | Returned ERP document and all accepted lines, read back independently |
| BC published pages | Adapt the OData blueprint's order export mappings to the company-scoped sales-order service | Header and lines reconciled by stable source reference |
| BC standard API | POST company `salesOrders`, then `salesOrders(<id>)/salesOrderLines`, or a measured deep insert | Persist returned header ID; verify every line and final totals before marking sent |

On the API path `externalDocumentNumber` can carry a source order reference, but BC does not
promise it is unique or an idempotency key. After an ambiguous timeout reconcile by the ledger
and company-scoped ERP reference before retrying. Serialise exports for the source key; an
ERP-side unique request key or equivalent atomic contract is needed for concurrent exactly-once
admission. Do not claim a GET-before-POST alone guarantees it.

When a line fails, retain the returned header ID and acknowledged line IDs. Resume/reconcile
the incomplete draft; do not create a second header. Set `OrderIntegrationOrderId` and exported
state through the platform only after the ERP acknowledges the complete intended order.
Capture the initial BC status; order creation is not shipment or posting. Financial bound
actions such as `Microsoft.NAV.shipAndInvoice` are separate authorised operations.

## Bring status back

Poll or use confirmed live documents in the same company. Map BC statuses to the platform's
actual workflow IDs in the integration specification. Preserve the distinction between ERP
acceptance, release, partial shipment, shipment, partial invoice, invoice and cancellation;
the standard order status field may not express every one of these. Add shipment/line sources
when the story requires them. Preserve fulfilment history if a posted order disappears from
the unposted-order API.

Use update-only order mappings scoped by company and integration ID. A missing ERP row or
transient error does not cancel an order. Record watermark only after the whole update is
applied and re-read. Repeat an unchanged import and assert unchanged counts and states.

## Bring invoices back

Choose either live **Integration Customer Center** documents or a persisted invoice import.
Keep invoices as ledger documents, separate from the original order. Persist company + invoice
GUID, number, order link, currency, tax, total and line references; support multiple invoices
and credit memos per order. Discover how the actual API/extension relates invoice lines to
the source order; matching on customer and amount is insufficient.

BC API `salesInvoices(<id>)/pdfDocument` supplies document metadata. Follow its content link
with ERP authentication server-side, then authorise the requesting buyer against the parent
account and company before delivery. Keep tokens out of browser URLs. Unposted invoice state
does not prove settlement; paid/open status needs the agreed ledger/receivable source.

## Required failure rehearsal

Interrupt after header creation, interrupt after one line, repeat an accepted order, time out
after ERP acceptance, deny credit, import partial shipment and two invoices, and attempt an
invoice read as a different account. Each case retains one coherent export record and proves
the intended buyer sees only its own documents.

Sources: [sales order API](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/resources/dynamics_salesorder),
[order-line creation](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/api/dynamics_salesorderline_create),
[invoice PDF](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/api/dynamics_salesinvoice_pdfdocument),
[Integration Customer Center](https://doc.dynamicweb.dev/documentation/implementing/content/apps/integration-customer-center-app.html).
