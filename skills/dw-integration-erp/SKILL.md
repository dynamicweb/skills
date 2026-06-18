---
name: dw-integration-erp
description: Configure ERP connectors and data ownership in Dynamicweb 10. Triggers: ERP integration, data shape ownership, connector configuration. Non-triggers: Integration Framework basics -> dw-integration-framework; Business Central -> dw-integration-bc.
---

# ERP Integration

## Integration Approaches

Dynamicweb 10 connects to ERP systems through the **Integration Framework** (activity-based import/export) and through direct OData APIs for supported ERP systems (Business Central, NAV). Most ERP integrations use one or both:

1. **Integration Framework Activities** — scheduled or triggered data sync (products, customers, orders, prices, stock)
2. **ERP Connector Plugins** — live-query connectors that look up prices and stock in real time

See [dw-integration-framework](../dw-integration-framework) for the general Integration Framework architecture.

## Data Ownership Model

The central concept in ERP integration is **data ownership** — which system is the authoritative source for each piece of data.

| Data entity | Typical owner | Direction |
|-------------|--------------|-----------|
| Products / catalog | ERP | ERP → Dynamicweb |
| Stock levels | ERP | ERP → Dynamicweb (or live query) |
| Price lists | ERP | ERP → Dynamicweb |
| Customers / users | ERP | ERP → Dynamicweb |
| Orders | Dynamicweb | Dynamicweb → ERP |
| Shipment confirmations | ERP | ERP → Dynamicweb |
| Customer credit | ERP | Live query |

**Rule:** Never write to ERP-owned fields from the Dynamicweb admin — changes will be overwritten on the next sync. Use field-locking or read-only UI settings to prevent accidental edits.

## Standard Integration Flow Pattern

Most ERP integrations follow this pattern:

1. **Inbound (ERP → DW):** Products, prices, stock, customers imported on schedule or triggered by ERP change
2. **Outbound (DW → ERP):** Orders exported when they reach a certain state (e.g., "Payment confirmed")
3. **Live queries (optional):** Real-time price or stock lookup bypassing the integration cycle

### Scheduling

Use **Scheduled Tasks** with the `RunIntegrationActivityAddIn` task to trigger integration activities on a schedule:

Admin: **Settings > System > Scheduled Tasks → New → DataIntegration.RunIntegrationActivityAddIn**

Select the target activity and set the interval (e.g., every 15 minutes for stock, every hour for catalog).

## Business Central / NAV OData Integration

Dynamicweb includes a **Business Central Connector** that uses BC's OData v4 API (or NAV OData v2/v3) to read and write data.

### Connection Setup

Admin path: **Settings > Integration > Business Central**

Connection parameters:
- **Server URL** — BC OData endpoint (e.g., `https://api.businesscentral.dynamics.com/v2.0/{tenantId}/{env}/ODataV4`)
- **Company** — BC company name
- **Authentication** — OAuth 2.0 (Azure AD app registration) or Basic auth (NAV on-premise)
- **BC Plugin-Unit (BC side)** — AL extension providing custom API pages for Dynamicweb-specific data shapes

For on-premises NAV, OData v2 endpoints are typically at:
`http://server:7048/BC/OData/Company('CompanyName')/`

### Data Mapping

The BC Connector maps BC entities to DW entities:

| BC entity | DW entity | Sync direction |
|-----------|----------|----------------|
| Item | Product | BC → DW |
| Item Variant | Product Variant | BC → DW |
| Customer | User | BC → DW |
| Currency | Currency | BC → DW |
| Price List | Price list | BC → DW |
| Sales Order | Order | DW → BC |

Field mapping is configured per integration activity in the connector's mapping editor.

### AL Plugin-Unit (BC Side)

For complex Dynamicweb integrations, a BC AL extension ("Plugin-Unit") is deployed to the BC environment. It provides:
- Custom API pages with the exact data shape DW expects
- Custom codeunits for order import logic
- Outbound webhook triggers for change notifications

The standard Dynamicweb Plugin-Unit is available from Dynamicweb and covers most standard scenarios. Custom AL extensions extend it for project-specific requirements.

### Live Price/Stock Queries

The BC Connector can be configured to skip the integration cycle for prices/stock and query BC in real time instead:

- **Live prices** — DW calls BC's price calculation API per session/cart. Eliminates price sync delay but adds latency and BC load.
- **Live stock** — DW calls BC's item availability API per product page load. Always shows current stock but requires BC to be reachable.

Live queries are configured on the ERP Connector configuration page. Enable them selectively — live queries on product list pages cause one BC API call per product.

## Generic ERP OData Integration

For non-BC ERP systems (SAP, Navision, AX, etc.) that expose OData, use the **OData Source Provider** in the Integration Framework:

Admin: Integration Activity → Source → select `OData Source Provider`

Configure:
- **Service URL** — OData endpoint root
- **Entity** — OData entity name to read
- **Authentication** — Basic, OAuth, or API key (provider-specific)
- **Filter** — OData `$filter` expression to scope the data

Then map source fields to DW destination fields in the activity's mapping tab.

## Order Export Pattern

Standard order export flow:
1. Order reaches a configured state (e.g., "Payment Confirmed")
2. Notification subscriber (`Ecommerce.Order.State.Changed`) fires
3. Subscriber triggers the integration activity via `ActivityService.RunActivity(activityId)`
4. Activity reads the order and pushes it to the ERP via OData POST

Alternatively, a scheduled task polls for orders in the target state and runs the export.

## Integration Logging and Monitoring

All integration activity runs log to `/Files/System/Log/`. Check the log for:
- Record counts (read, mapped, written, failed)
- Field-level mapping errors
- Authentication failures

Enable **"Log errors only"** mode during go-live testing to reduce log volume. Switch to full logging when diagnosing mapping issues.

Admin: **Settings > Integration > Activities → [Activity] → Log tab**

## Pitfalls

**Sync overwriting manual edits** — if editors enrich ERP-owned fields (like product name or price), the next import overwrites them. Lock ERP-owned fields in the product UI or use field visibility settings to make them read-only in admin.

**Order state timing** — exporting orders too early (before payment capture) can cause issues on the ERP side. Configure the export trigger state carefully and verify with the ERP team.

**Live price queries and performance** — live BC price queries on the product list page fire one API call per product per page load. Cache results or limit to product detail pages only.

**OData pagination** — ERP OData endpoints often return paginated results. The OData Source Provider handles this automatically, but check that your `$top` and `$skip` parameters are not inadvertently limiting the full data set.

## Next Steps

- **Integration Framework architecture?** See [dw-integration-framework](../dw-integration-framework)
- **Business Central specifically?** See [dw-integration-bc](../dw-integration-bc)
- **Custom integration provider in C#?** See [dw-extend-providers](../dw-extend-providers)
- **Notification-triggered export?** See [dw-extend-providers](../dw-extend-providers)
