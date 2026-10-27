# Batch imports and live operations

## Choose an integration route

| Route | Read / apply | Appropriate use |
|---|---|---|
| BC ERP plug-in unit | Scheduled request -> captured XML -> XML source -> platform destination provider | Vendor-supported batch contracts and live price, stock or document operations |
| Published OData pages | OData source -> destination provider, using the BC OData v4 blueprint | The published page schemas and their predefined mappings |
| Standard/custom APIs | Versioned BC API -> controlled staging/transform -> destination provider | Proven API contracts; gaps explicitly assigned to the BC extension owner |
| PIM connector | BC extension -> Commerce Management API `/admin/api/BC*` | Item creation/enrichment exchange; not the commerce transaction transport |

## Configure the first import

1. Capture the exact company-scoped endpoint, supported request and response. Use the
   endpoint screen's request examples or the installed plug-in documentation.
2. In **Integration > Activities**, create one activity per data family. For the plug-in route,
   use XML source with the captured response and the appropriate platform destination.
   Start with explicit mappings. Runtime mappings fit a vendor XML schema only after checking
   its table/column allowlist and field ownership.
3. In **Settings > Integration > Scheduled tasks**, add **Import data with custom request**.
   Select the saved ERP endpoint, the output XML and the import activity. Resolve the current
   add-in from AppStore. Run now once before scheduling.
4. Run dependencies in order: languages/currencies/UOM, groups/items, accounts/contacts,
   ship-to, tier bindings/prices, locations/stock. Leave user and address exports disabled when
   BC owns their creation.
5. Compare input counts and external keys with platform read-back, then build the affected
   indexes and test the rendered buyer view. A successful activity log is only one layer.

For the OData route import the published **Business Central OData v4 blueprint**, then bind
every source and destination endpoint to the selected company. Review its default language,
shop, warehouse, user type, prices, user creation and order mappings before enabling runs.

## Apply and refresh

Use `EcomProvider` for supported product/price/stock imports, `UserProvider` for account and
address relations, and update-only `OrderProvider` mappings for existing orders. Confirm the
actual provider names and configuration from **Integration > Activities** on the target.
Read [`dw-integration-framework`](../../dw-integration-framework/SKILL.md) before changing
mapping keys or provider delete options. Scope missing-row handling to integration-owned rows.

Batch ownership is a field allowlist. ERP item updates preserve PIM descriptions, translation,
media and workflow fields; PIM enrichment back to BC preserves commercial keys and prices.
Start incremental watermarks only after all pages have staged, applied and verified. Use a
bounded overlap with stable-key upsert; replaying a boundary must not create duplicates.

Configure the activity's cache and repository-index steps, then assert the buyer's price and
availability. Follow [`dw-data-write-effects`](../../dw-data-write-effects/SKILL.md) if storage
and storefront disagree. A host restart is an environment change subject to that host's rules.

**Existing MSRP rows:** a narrow XML-to-`DynamicwebProvider` activity
updated `EcomProducts.ProductPrice` by product/variant/language and `EcomPrices.PriceAmount`
by existing `PriceId`, while retaining other price fields and customer/quantity/UOM rows.
This is an update-only alternative when the stable destination IDs are already mapped;
it is not a substitute for resolving the complete identity of newly imported agreements.
A success log and the product getter showed the new base price while the price getter and
buyer page retained a cached amount. Verify the stored amount independently. [dw 10.29.8]

On that host, out-of-product Management API `POST /admin/api/CacheInformationRefresh` with
`{"CacheTypeName":"Dynamicweb.Ecommerce.Prices.PriceService"}` and then
`{"CacheTypeName":"Dynamicweb.Ecommerce.Products.ProductService"}` returned `status: ok`
and made the changed price visible in the buyer PDP and cart without recycling. Confirm the
service names with `GetServiceCaches`, require the acknowledgement, then refresh the actual
indexes and re-read the same buyer/UOM. This is a measured host observation, not a new
corpus compatibility claim or a promise for older versions whose resolved-price cache may
still require a recycle. Complete the reverse source/import/buyer test as well. [dw 10.29.8]

For staged XML, discover the provider's logical source path separately from the file-archive
upload path. An archive path under `/Files/Files/Integration/` was read by the XML provider as
`/Files/Integration/`; confirm with provider-schema preview before running. Pass `isBase64=false`
explicitly for text uploads. Publicly served staging holds public MSRP only, never customer
agreements, addresses or invoices. An empty grouped MCP log listing is not run completion or
failure; pair the exact activity status with its native log and independently counted rows.

## Enable live integration

Copy the saved SOAP endpoint into a separate live request and select **Use in Live Integration**.
Create **Integration > Live** configuration for the intended shop and enable the measured
operations. Capture request and response shapes from that installed extension. Test the same
customer, company, currency, UOM and quantity used in the storefront, including an ERP timeout.

Live data needs a stated cache lifetime and failure policy. Product browsing may show a labelled
stale value when approved; final price, credit and order admission need a fresh decision or a
visible retry/hold. Keep batch and live price writers consistent so one does not overwrite the other.

Sources: [plug-in batch and live setup](https://doc.dynamicweb.dev/manual/dynamicweb10/integration/guides/Plugin-unit-integration/bc-cloud.html),
[OData blueprint](https://doc.dynamicweb.dev/manual/dynamicweb10/integration/guides/blueprints/bc-odata-v4-blueprint.html).
