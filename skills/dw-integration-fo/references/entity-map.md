# Entity map: F&O data entities to platform tables

## Contents

- [Company-scoped vs tenant-wide](#company-scoped-vs-tenant-wide)
- [The read surface](#the-read-surface)
- [The write surface](#the-write-surface)
- [Keys and identifiers](#keys-and-identifiers)
- [Enums, dates and empty values](#enums-dates-and-empty-values)
- [Choosing the entity version](#choosing-the-entity-version)

## Company-scoped vs tenant-wide

Most F&O entities carry `dataAreaId` and belong to one legal entity. A read without `cross-company=true` returns
only the **default company of the integration user**; a read with `cross-company=true` and no filter returns
**every company**. Every company-scoped endpoint therefore carries both:

```
cross-company=true
$filter=dataAreaId eq '<CODE>'
```

Tenant-wide entities have no `dataAreaId`, and a company filter on them is rejected. Pin them by the value the
engagement controls:

| Entity | Pin by |
|---|---|
| `ProductCategories`, `ProductCategoryAssignments` | `ProductCategoryHierarchyName eq '<hierarchy>'` |
| `ProductTranslations` | `ProductNumber eq '<prefix>*' and LanguageId eq '<lang>'` (F&O OData has no `startswith()`: it answers 400 "The type 'System.String' for the query operator is not Queryable"; `eq` takes a `*` wildcard), or the list of released item numbers |
| `LegalEntities` | none (it is the connection test) |

## The read surface

Stage 1 lands each of these 1:1 in a staging table; stage 2 applies them through views
([staging-pattern.md](staging-pattern.md)). Column lists are the minimum a storefront needs; add what discovery
found populated.

| Platform target | F&O entity set | Key | Columns worth staging | Stage-2 notes |
|---|---|---|---|---|
| Products (`EcomProducts`) | `ReleasedProductsV2` | `dataAreaId`, `ItemNumber` | `SearchName`, `ProductSearchName`, `ProductType`, `ProductSubType`, `ProductGroupId`, `ItemModelGroupId`, `SalesUnitSymbol`, `InventoryUnitSymbol`, `SalesPrice`, `SalesPriceQuantity`, `NetProductWeight`, `ProductLifecycleStateId`, `SellStartDate` | there is **no product name** on this entity |
| Product name, description | `ProductTranslations` | `ProductNumber`, `LanguageId` | `ProductName`, `Description` | tenant-wide; join on `ProductNumber` = `ItemNumber` |
| Groups (`EcomGroups`, `EcomGroupRelations`, `EcomShopGroupRelation`) | `ProductCategories` | `ProductCategoryHierarchyName`, `CategoryName` | `CategoryCode`, `CategoryDescription`, `ParentProductCategoryName`, `FriendlyCategoryName`, `CategoryRecordId` | parent is by **name**; `CategoryRecordId` makes a stable group id |
| Product-group membership | `ProductCategoryAssignments` | `ProductNumber`, `ProductCategoryName`, `ProductCategoryHierarchyName` | `DisplayOrder` | via the Ecom provider's `Groups` / `PrimaryGroup` product columns |
| Customer companies (user groups) | `CustomersV3` | `dataAreaId`, `CustomerAccount` | `OrganizationName`, `CustomerGroupId`, `DiscountPriceGroupId`, `PaymentTerms`, `CreditLimit`, `SalesCurrencyCode`, `Address*`, `PrimaryContactEmail`, `PrimaryContactPhone`, `OnHoldStatus` | User provider, table `AccessUserGroup`, key `AccessGroupExternalId` |
| Prices (`EcomPrices`) | `SalesPriceAgreements` | `dataAreaId`, `RecordId` | `ItemNumber`, `PriceCustomerGroupCode`, `CustomerAccountNumber`, `PriceApplicableFromDate`, `PriceApplicableToDate`, `FromQuantity`, `ToQuantity`, `Price`, `PriceCurrencyCode`, `QuantityUnitySymbol` | no natural key: `RecordId` is the price id; filter to agreements in force |
| Stock locations (`EcomStockLocation`) | `Warehouses` | `dataAreaId`, `WarehouseId` | `WarehouseName`, `OperationalSiteId`, `PrimaryAddressCity`, `PrimaryAddressStateId` | key on `StockLocationExternalId` |
| Stock (`EcomStockUnit`) | `WarehousesOnHandV2` | `dataAreaId`, `ItemNumber`, the five product dimensions, `InventorySiteId`, `InventoryWarehouseId` | `AvailableOnHandQuantity`, `OnHandQuantity`, `ReservedOnHandQuantity`, `OnOrderQuantity`, `TotalAvailableQuantity` | sum per item and warehouse; the 9-column key needs short key columns in staging |
| Order status back | `SalesOrderHeadersV2` | `dataAreaId`, `SalesOrderNumber` | `CustomersOrderReference`, `SalesOrderStatus`, `SalesOrderProcessingStatus`, `ConfirmedShippingDate`, `DeliveryModeCode`, `OrderTotalAmount` | [order-flow.md](order-flow.md) |
| Order lines back | `SalesOrderLines` | `dataAreaId`, `InventoryLotId` | `SalesOrderNumber`, `LineNumber`, `ItemNumber`, `OrderedSalesQuantity`, `SalesPrice`, `LineAmount`, `SalesOrderLineStatus` | |
| Invoices back | `SalesInvoiceHeadersV2` | `dataAreaId`, `InvoiceNumber`, `InvoiceDate`, `LedgerVoucher` | `SalesOrderNumber`, `CustomersOrderReference`, `InvoiceCustomerAccountNumber`, `TotalInvoiceAmount`, `TotalTaxAmount`, `CurrencyCode` | ledger entries; open/paid needs `CustTransactions` |

## The write surface

| Platform source | F&O entity set | What the row must carry |
|---|---|---|
| A completed order | `SalesOrderHeadersV2` | `dataAreaId`, `SalesOrderNumber` (when the sequence allows manual numbers), `OrderingCustomerAccountNumber`, `InvoiceCustomerAccountNumber`, `CurrencyCode`, `CustomersOrderReference` = the platform order id |
| Its product lines | `SalesOrderLines` | `dataAreaId`, `SalesOrderNumber`, `LineNumber`, `ItemNumber`, `OrderedSalesQuantity`, `SalesPrice` |

Everything else on the write side (customer creation, quotes, returns) follows the same view-to-OData shape; build
it only when a scenario needs it. The recipe and its ordering are in [order-flow.md](order-flow.md).

## Keys and identifiers

- **Key the platform's rows on the ERP's own identifiers from the first import.** `ProductNumber` = `ItemNumber`,
  a customer group's `AccessGroupExternalId` = `CustomerAccount`, a price id derived from `RecordId`. A provider
  that mints its own ids forces a cross-table migration later.
- **Platform ids accept letters and digits only.** Derive ids in the view (strip `-`, `_`, `.`, spaces, `/`,
  `:`) and keep the readable ERP value in the number column.
- **Prefix every id the integration mints** (`<P>GRP<recid>`, `<P><item>`, `<P>P<recid>`) so the rows it owns are
  one `LIKE` away from being counted, verified or removed, and never collide with rows from anywhere else.
- **Tenant-wide product numbers in a shared environment carry a prefix** (`<CODE>-<item>`); the view maps the
  prefix away or keeps it, but decides it in one place.

## Enums, dates and empty values

- F&O enums arrive as their symbol text (`Delivered`, `Invoiced`, `Yes`); the provider types them
  `System.Object`, staging stores them as `nvarchar`. Compare against the symbol, not a number.
- An open-ended date is `1900-01-01T00:00:00Z`, not null. Treat anything before `1900-01-02` as "no date".
- F&O writes placeholders (`NA`, `N/A`) into empty text fields in some models: clean them in the view
  (`NULLIF`) and keep case-sensitive values that only look like placeholders.
- `$count` answers start with a byte-order mark: trim `U+FEFF` before casting.

## Choosing the entity version

Use the entity version discovery measured as populated (`ReleasedProductsV2`, `CustomersV3`,
`SalesOrderHeadersV2`, `SalesInvoiceHeadersV2`, `WarehousesOnHandV2`). Newer versions (`SalesOrderHeadersV3`,
`SalesOrderLinesV3`, `SalesInvoiceHeadersV4`) exist on current releases; switching is a spec change, and the
staging columns follow the property names of the version chosen. Always check a property in the environment's
own `$metadata` before mapping it: the generator refuses a column the metadata does not list.
