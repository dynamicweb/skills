# Structural inventory

Capture BC application/platform versions, installed extensions and publishers, the ERP
plug-in unit and PIM connector versions, enabled pricing experience and relevant setup.
Use **Extension Management**, **Web Services**, the application API metadata and the ERP
owner's extension inventory. Public metadata alone does not identify all installed business logic.

For every candidate source record:

| Fact | Evidence |
|---|---|
| Surface | API v2, custom publisher/group/version, OData published page, or plug-in request |
| Company pin | GUID and published company-specific URL |
| Schema | Entity set, keys, properties, types and child collections from that exact surface |
| Extension origin | Standard, vendor, partner or customer, with publisher and owning team |
| Direction | Read, write, computed operation or unsupported |
| Behaviour | Pagination, modification timestamp, deletes, bound actions and idempotency |

Start with `items`, `customers`, `salesOrders` and `salesInvoices` in standard API v2. Discover
ship-to, detailed price lines, per-location availability, credit decisions and order/shipment
relations from the actual published pages or extensions. A published page name in the vendor
blueprint is not proof that the environment has published that page.

Keep `$metadata` separately for standard APIs, each custom API version and the OData service.
Copy supported plug-in request examples and one sanitised response into the engagement folder.
Record the original hash before extracting the subset used by activities.

Done: every proposed mapping has a real source name, key, schema capture and owning extension;
unknown/custom contracts are explicit review questions.

Sources: [API overview](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/),
[OData web services](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/webservices/odata-web-services).
