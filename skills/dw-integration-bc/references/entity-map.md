# Entity map and company keys

Treat this as a starting map, then replace every candidate with an observed source contract.
BC standard API collections, published pages, and the ERP plug-in XML are separate surfaces.
Do not manufacture API v2 collections for ship-to, price-list lines or location-level stock.

| Domain | Candidate BC source | Commerce destination | Key and ownership |
|---|---|---|---|
| Products | API `items`; published `DynamicwebItemCard`; plug-in Products | `EcomProducts`, product groups and units | Tenant/environment/company + item SystemId or number + variant + UOM; BC commercial facts, PIM editorial content |
| Customers | API `customers`; `DynamicwebCustomerCard`; plug-in Customers | `AccessUser`, account and contact relations | Company + customer + contact; distinguish bill-to, sold-to and login |
| Ship-to / plants | Published `DynamicwebShipToAddress` (page 300); plug-in customer addresses | `AccessUserAddress`, explicit account/plant relations | Company + customer + ship-to code; BC owns creation |
| Tier prices | Published `DynamicwebSalesPrices` or `DynamicwebSalesPriceList`; confirmed live price request | `EcomPrices` or live price response | Company + customer/group/all + item + variant + UOM + currency + quantity + validity; BC owns base tiers |
| Locations | `DynamicwebLocations` (page 15); plug-in stock locations | `EcomStockLocation` | Company + location code |
| Availability | `DynamicwebStockKeepingUnitCard` or confirmed plug-in/custom availability response | `EcomStockUnit` | Company + location + item + variant + UOM; quantity semantics must be agreed |
| Order out | Supported ERP plug-in order request, published sales-order page, or API `salesOrders` + `salesOrderLines` | Export ledger and order integration ID | Selling company + Commerce order ID; BC mints its document ID |
| Status back | Confirmed live documents or company API `salesOrders` | Existing Commerce order state | Company + BC document ID + source order reference |
| Invoices back | Live Integration Customer Center or API `salesInvoices` and lines/PDF | Ledger documents and authorised document links | Company + invoice ID; multiple invoices per order |
| Credit | Customer facts plus ERP-owned credit decision contract | Checkout/recurrence admission decision | Company + bill-to customer + currency + attempt ID; not a cached limit subtraction |

## Mapping rules

Use the official OData v4 blueprint as the initial mapping when those pages are published.
Its names are publisher conventions, not standard API v2 endpoints. Check the new or legacy
price experience first; page availability and fields vary with the installed BC application.

Namespace external keys by company before import. A shared item number does not prove a
shared product; merging products across companies needs an explicit canonical item map.
Keep reversible cross-reference rows, rather than stripping punctuation into colliding IDs.
Map a single BC company to a stock location namespace; persist the original location code.

For ship-to imports map `Customer_No` through the account's company-qualified external ID
to the real `AccessUserId`. Map `Code` to `AccessUserAddressExternalId`, address fields to
their named `AccessUserAddress*` columns, and preserve `Location_Code` when supplied.
The blueprint's provider setting resolves the external account ID; a literal BC customer
number is not automatically the platform's numeric user ID. Test the same customer and
ship-to code in two companies and assert the parent account of each imported address.

A zero native delivery-address ID is not ship-to authority. Enrich a legacy same-as-billing
case to an ERP headquarters address only when the immutable admission decision records that
exact policy and evidence. Recheck current account/ship-to masters, actor rights and the posted
supplying company's customer/ship-to mapping. Compare the complete address, including
`Address2`; never ignore that line to make a mismatch pass. Preserve the original native
source and the separately evidenced invoice enrichment, rather than rewriting the source or
guessing a headquarters from the latest master data.

API `items.inventory` is a company total, not per-location availability or available-to-promise.
Stock-keeping unit rows do not necessarily exist for every item/location pair. Capture a
location inventory source that covers the required population, units, reservations and date.

Sources: [BC OData blueprint and mappings](https://doc.dynamicweb.dev/manual/dynamicweb10/integration/guides/blueprints/bc-odata-v4-blueprint.html),
[item API](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/resources/dynamics_item),
[customer API](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/resources/dynamics_customer).
