# Orders out, status and invoices back

## Contents

- [The shape](#the-shape)
- [F&O prerequisites in the legal entity](#fo-prerequisites-in-the-legal-entity)
- [The export queue: a state, not a flag](#the-export-queue-a-state-not-a-flag)
- [Export views](#export-views)
- [The three export activities](#the-three-export-activities)
- [Status back](#status-back)
- [Invoices back](#invoices-back)
- [Why not the Order provider as the export source](#why-not-the-order-provider-as-the-export-source)

## The shape

```
platform order in state "Ready for ERP"
  -> view <P>_v_OrderExportHeaders --(Dynamicweb provider -> OData destination)--> SalesOrderHeadersV2
  -> view <P>_v_OrderExportLines   --(Dynamicweb provider -> OData destination)--> SalesOrderLines
  -> view <P>_v_OrderExportMark    --(Dynamicweb provider, update only)--------> EcomOrders: external id, exported flag, state "In ERP"
F&O
  -> stage 1 SalesOrderHeadersV2 / SalesInvoiceHeadersV2 -> staging
  -> view <P>_v_OrderStatus  --(update only)--> EcomOrders.OrderStateId
  -> view <P>_v_Invoices     --(Order provider)--> ledger entries owned by the order's customer
```

Three activities out, two back, all built from views, none creating an id the platform might also mint.

## F&O prerequisites in the legal entity

Before the first export run, the target legal entity needs:

| Prerequisite | Why |
|---|---|
| The customer accounts the orders name (`OrderCustomerNumber`) | a header with an unknown account is rejected |
| The released items the lines name, under the numbers the view sends | line validation |
| A sales order number sequence that **allows manual numbers** (or is not continuous and accepts lower numbers) | the export supplies `SalesOrderNumber` so the lines, sent in the next activity, can name their header |
| Default site/warehouse, delivery terms and mode on the customer | the header takes them from the customer when not sent |
| A write-capable role on the mapped F&O user | the connection test only proves reads |

If the number sequence cannot be manual, the alternative is a header-only export, a stage-1 read of
`SalesOrderHeadersV2` filtered on `CustomersOrderReference` to learn the F&O number, and a lines export keyed on it:
two extra runs per order batch.

## The export queue: a state, not a flag

The export picks up orders an operator (or a rule) moved into a dedicated order state, for example
*Ready for ERP*, created with MCP `create_order_state` in the order flow. That makes the queue visible in the order
list, keeps existing completed orders out of the first run, and lets a demo or a pilot export one order on purpose.
A second state, *In ERP*, is what the mark step sets.

## Export views

The view emits **F&O property names**, so the OData mapping is 1:1 and the generator can build it:

```sql
-- SQL. Local installs only. Headers: complete, not a ledger entry, not a quote, not exported, in the queue state.
SELECT cfg.DataAreaId AS dataAreaId, N'<P>-' + o.OrderId AS SalesOrderNumber, o.OrderId AS CustomersOrderReference,
       o.OrderCustomerNumber AS OrderingCustomerAccountNumber, o.OrderCustomerNumber AS InvoiceCustomerAccountNumber,
       o.OrderCurrencyCode AS CurrencyCode, NULLIF(o.OrderCustomerEmail, N'') AS Email, o.OrderId AS SourceOrderId
FROM dbo.EcomOrders o CROSS JOIN dbo.<P>_Config cfg
WHERE o.OrderStateId = cfg.ReadyStateId AND o.OrderComplete = 1 AND ISNULL(o.OrderIsLedgerEntry, 0) = 0
  AND ISNULL(o.OrderIsQuote, 0) = 0 AND ISNULL(o.OrderIsExported, 0) = 0 AND ISNULL(o.OrderIntegrationOrderId, N'') = N'';
-- Lines: product lines only (type 0 or empty, no parent line), numbered per order, item number in the ERP's form.
```

Keys on the OData destination are the business key the view supplies (`dataAreaId` + `SalesOrderNumber` for
headers, + `LineNumber` for lines), not the entity key: `SalesOrderLines` is keyed on `InventoryLotId`, which F&O
mints on insert.

## The three export activities

| # | Activity | Source -> destination | Notes |
|---|---|---|---|
| 1 | headers | export headers view -> OData destination on the `SalesOrderHeadersV2` endpoint | built as a generated job file until the endpoint authenticates |
| 2 | lines | export lines view -> OData destination on the `SalesOrderLines` endpoint | same |
| 3 | mark sent | mark view -> `EcomOrders` (Dynamicweb provider, *Update only existing records*) | sets `OrderIntegrationOrderId` = the F&O number, `OrderIsExported` = 1, state *In ERP* |

Run 3 only when 1 and 2 both completed; the mark view reads the same queue, so a failed run leaves the orders in
the queue for the next attempt. A runner script owns that ordering and refuses to run the export against any legal
entity but the one the integration is for.

## Status back

Stage 1 stages `SalesOrderHeadersV2`; the status view joins it to the platform order on
`OrderIntegrationOrderId = SalesOrderNumber` (only orders the integration exported) and translates
`SalesOrderStatus`:

| F&O `SalesOrderStatus` | Platform state (example) |
|---|---|
| `Backorder` (open) | *In ERP* |
| `Delivered` | Shipped |
| `Invoiced` | Completed |
| `Canceled` | Rejected / Cancelled |

Written with the Dynamicweb provider, *Update only existing records*, key `OrderId`. **No state mail is sent**:
order-state notifications fire from `OrderService.Save`, which a job never calls. If the customer must be emailed
on "shipped", that is a subscriber or a scheduled task re-applying the state through the order service: code, and
an estimate line.

## Invoices back

`SalesInvoiceHeadersV2` rows for exported orders become **ledger entries** (`OrderIsLedgerEntry` = 1,
`OrderLedgerType` = `Invoice` or `CreditMemo` by sign) owned by the customer of the originating order, so they list
in the customer center's invoice view:

- Order provider destination; key `OrderIntegrationOrderId` = the invoice number, `OrderId` supplied from the view
  as a prefixed id and **not** a key (the provider cannot mint one; see `dw-integration-framework`
  provider-behaviour, OrderProvider).
- Map `OrderIsExported` = 1: an invoice that came from the ERP is exported by definition, and the order export
  must never post it back as a sales order.
- Paid / open needs the customer transaction (`CustTransactions`: amount, settled amount, due date); stage it
  when the storefront shows balances.
- Invoice header rows repeat per voucher: take one row per invoice number in the view.

## Why not the Order provider as the export source

The Order provider can export (`Export not yet exported Orders`, `Order state after export`, `Only export orders
with state`), but one activity cannot write both `SalesOrderHeadersV2` and `SalesOrderLines` through one OData
destination endpoint, and the provider stamps `OrderIsExported` after the **first** activity, so a second
activity for the lines finds nothing. Its export filter also has no ledger-entry exclusion. Views plus a separate
mark step keep headers, lines and the stamp in the right order and make every run's scope a query you can read
first.
