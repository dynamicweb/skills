# The demo company recipe: create, seed, shape, verify, retire

## Contents

- [Prerequisites](#prerequisites)
- [1. Create the legal entity](#1-create-the-legal-entity)
- [2. Seed the configuration](#2-seed-the-configuration)
  - [2a. Seed a demo company from the golden package](#2a-seed-a-demo-company-from-the-golden-package)
  - [2b. Build the golden company once: Copy into legal entity](#2b-build-the-golden-company-once-copy-into-legal-entity)
  - [2c. Measured gaps after a copy](#2c-measured-gaps-after-a-copy)
  - [2d. Reading the copy's errors](#2d-reading-the-copys-errors)
  - [2e. Export the golden package](#2e-export-the-golden-package)
- [3. Apply the company profile](#3-apply-the-company-profile)
- [4. Seed the demo data](#4-seed-the-demo-data)
- [5. Verify the round-trip](#5-verify-the-round-trip)
- [6. Make it re-runnable, and retire it](#6-make-it-re-runnable-and-retire-it)

## Prerequisites

- A sandbox (not production) where an admin allows new legal entities, and agreement on the code prefix
  ([shared-sandbox.md](shared-sandbox.md)).
- An identity the scripts can use ([connection-modes.md](connection-modes.md) "Access for the scripts"), and
  an interactive admin for the UI-only steps.
- A written company profile ([company-profile.md](company-profile.md)): the seed is cheap to run and
  expensive to run twice with a different answer.
- A **golden company** for the demo's country/region (§2b builds it once), or, while there is none, a
  **donor**: an existing, working company in the same sandbox (a standard demo-data company such as USMF).
  Region matters: seeding from a company configured for another country/region produces validation errors on
  the localisation-specific fields.

## 1. Create the legal entity

`LegalEntities` is a global (tenant-wide) entity. The key `LegalEntityId` is **4 characters at most**,
read-only after create. Minimum useful payload:

```json
{
  "LegalEntityId": "<CODE>",
  "Name": "<Legal name>",
  "NameAlias": "<Search name>",
  "CompanyCountry": "<ISO country/region id>",
  "AddressCountryRegionId": "<ISO country/region id>",
  "AddressDescription": "<Primary>",
  "AddressStreet": "<street>",
  "AddressCity": "<city>",
  "AddressState": "<state>",
  "AddressZipCode": "<zip>",
  "LanguageId": "<lang>"
}
```

Routes, in order of preference:

| Route | When | Note |
|---|---|---|
| [`New-DemoCompany.ps1`](../scripts/New-DemoCompany.ps1) (OData `POST /data/LegalEntities`) | scripted, repeatable | idempotent: GETs first, creates only when absent |
| The F&O MCP server's `data_create_entities` on `LegalEntities` | an interactive session already on that server | same entity, same payload |
| **Create** on the Copy-into-legal-entity project's *Legal entities* FastTab | the OData create is refused | the copy project can create its own destination company; the documented UI path |
| *Organization administration > Organizations > Legal entities > New* | last resort, fully manual | also where you check the result |

The OData create is measured working on a current unified sandbox: one `POST /data/LegalEntities` with the
fields above returned `201` and the company appeared in `Companies` immediately. A tenant may still refuse it
(the entity is exposed but the create path is gated on some builds); the script says so and names the
copy-project route, which produces the same company. Record which route was used in the engagement folder.

Currency, ledger and fiscal calendar are **not** part of this record; they arrive with the seed in step 2 (or
must be set on the *Ledger* page before anything can post).

## 2. Seed the configuration

A new legal entity is empty. Two mechanisms fill it:

| Mechanism | Use it for | Cost |
|---|---|---|
| **Import the golden package** (§2a) | every demo company | one package import, no repair |
| **Copy into legal entity** from the stock donor (§2b) | building the golden company, once per country/region | hours of copy, then a measured repair (§2c) |

The golden route is the standing choice: the copy's gaps are the same every time, so they are repaired once
in the golden company and every demo company inherits the repaired configuration.

### 2a. Seed a demo company from the golden package

The Data management package actions are bound to `DataManagementDefinitionGroups` and exposed over OData,
so the import needs no UI. Parameters as the environment's `$metadata` declares them:

| Action (`POST /data/DataManagementDefinitionGroups/Microsoft.Dynamics.DataEntities.<Action>`) | Parameters | Returns |
|---|---|---|
| `ExportToPackage` | `definitionGroupId`, `packageName`, `executionId`, `reExecute`, `legalEntityId` | execution id |
| `GetExportedPackageUrl` | `executionId` | a short-lived download URL for the package zip |
| `GetAzureWriteUrl` | `uniqueFileName` | a blob URL to upload a package to before import |
| `ImportFromPackage` | `packageUrl`, `definitionGroupId`, `executionId`, `execute`, `overwrite`, `legalEntityId` | execution id |
| `GetExecutionSummaryStatus` | `executionId` | `Unknown`, `NotRun`, `Executing`, `Succeeded`, `PartiallySucceeded`, `Failed`, `Canceled` |
| `GetExecutionErrors` | `executionId` | the row-level errors (§2d) |

Measured end to end on a 10.0.48 unified sandbox (a US golden company into a new demo company, all over OData, no
UI). The run order, and what each step taught:

1. **Ledger and number sequences first, over OData.** `Ledger`, `Number sequence code`, `Number sequence group` and
   `Number sequence references` are rows in **shared** tables (`DataManagementEntities.IsShared` = Yes). In a package
   they export every company's rows, and the import would write into the other companies. Write them for the new
   company instead: `POST /data/Ledgers` with the golden company's chart of accounts, fiscal calendar and currencies
   (`Name` is not insertable: leave it out), then one `SequenceV2Tables` row per golden sequence (company segment of
   `Format`/`AnnotatedFormat` swapped, `Next` = `Smallest`) and one `NumberSequencesV2References` row per reference.
   Measured: 631 of 633 sequences (two test sequences scoped `LegalEntity` are refused, annotated format) and 487
   references in minutes. Both keys contain the `ScopeType` enum: a GET by key path answers 404 even when the row
   exists, so check existence with `$filter` (`ScopeValue` + code), not the key. Without a ledger, most
   configuration entities fail validation.
2. **Import the package into the new company.** [`Import-GoldenPackage.ps1`](../scripts/Import-GoldenPackage.ps1):
   `GetAzureWriteUrl`, PUT the zip to the blob URL (`x-ms-blob-type: BlockBlob`), `ImportFromPackage` with
   `legalEntityId` = the new company, `execute` and `overwrite` true. The script first **re-points golden-company
   values inside the package**: company-scoped entities still carry the golden code as a value (measured: journal
   names `VOUCHERSERIESCOMPANYID`, ledger allocation rules `COMPANY`/`FROMCOMPANY`, subledger transfer rule and
   allocation basis source `LEGALENTITYID`, tracking number groups `NUMBERSEQUENCESCOPEDATAAREA`: 114 values).
   Copy into legal entity remaps those; a package import does not.
3. **Poll, never re-send.** `ImportFromPackage` answers only once the package is unpacked into staging; a
   228-entity package outlived a 180-second client timeout while the server carried on. The script recovers the
   execution id from `DataManagementExecutionJobDetails` (filter `DefinitionGroupId`) and follows it.
4. **Read the result.** Measured: 228 entities in 62 minutes, *PartiallySucceeded*, 3 entities in error with 3 row
   errors, 31,706 rows created. The three: a customer group whose write-off reason lives in a shared table
   (`Customer write-off reason codes`), Customer parameters (the Sales parameters record already exists), and
   Inventory parameters (the fallback warehouse was not in the package, by design). None blocks a demo. The bank
   and payment chain arrived intact; `Repair-CopyGaps.ps1` then found only the company-scoped financial dimension
   values (§2c) missing.
5. `Test-DemoCompany.ps1`: bank accounts, payment methods and number sequences non-zero before the profile goes on.

### 2b. Build the golden company once: Copy into legal entity

Microsoft's **Copy into legal entity** moves configuration, not transactions, from a source company to one or
more destinations in the same environment
([docs](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/copy-configuration)).
It is a UI/batch feature: drive it as an interactive admin or through the F&O MCP server's form tools.

**Step 0: check the templates exist.** The copy is driven by the default templates, and a freshly provisioned
environment can have **none** loaded: *Data management* > **Templates** tile > if the list is empty, **Load
default templates** > **Load all**. That runs as a background operation; when it returns, every template
shows status *Validated*. Skipping this leaves only hand-picked entities, which fail on dependency order.

1. *Data management* workspace > **Enhanced view** > **Copy into legal entity** tile > **New**.
2. Operation type **Copy into legal entity**, project category **Configuration**.
3. Source legal entity = the **donor**.
4. *Legal entities* FastTab > **Select** the company from step 1 (or **Create** it here).
5. **Copy number sequences = Yes**, and **reset to smallest = Yes** for a fresh company; otherwise the new
   company inherits the donor's next-number state and the first seeded ids look wrong.
6. Add entities via the default templates, **including Cash and bank management** (§2c shows what happens
   without it), then remove what the demo does not need. Templates carry the execution unit, level and
   sequence that make the load order work.
7. **Trim the global address book.** The System Setup template pulls in postal codes, districts, cities,
   counties, states and country/regions. All are tenant-wide (`RootTableIsGlobal` is true), so they already
   exist for the new company, and they are by far the slowest part of the run. Tick **Disable** on those rows
   in *Selected entities*: the supported way to skip an entity without breaking the template's ordering, and
   reversible from the same checkbox. A run that dies part-way is most likely stuck on one of these.
8. Run it **in batch, and tick the box that makes it batch.** The *Copy in batch* dialog opens with only a
   collapsed *Run in the background* tab; expand it and tick **Batch processing**, which is off by default,
   before OK. Left off, the copy runs inside the interactive session, dies with any session or service
   interruption, and repeat presses can silently create no job at all. The infolog saying the job *is added to
   the batch queue* is the proof. The same tab prints the server clock: the batch grid's "scheduled start" and
   the dialog can disagree on time zone, and a copy that appears scheduled hours away is usually a different
   job.
9. Follow it headlessly: a row appears in `DataManagementExecutionJobs` (`Copy legal entity <SRC> to <DST> -
   <timestamp>`), and `DataManagementExecutionJobDetails` carries one row per entity with `StagingStatus` and
   `TargetStatus`. `Watch-CopyProgress.ps1 -JobId '<that JobId>'` polls it and summarises the errors at the end.

**Scale, measured.** A copy from a stock US donor with the System Setup, GL Shared, General ledger, Tax,
Accounts receivable, Inventory, Product information management and Sales-and-marketing templates ran **365
entities in 2 h 14 min** and ended *PartiallySucceeded*: 356 entities finished, 9 in error, **3,506 row-level
errors**. Plan the session around it; it is a batch job, not an interactive step.

What the copy will not do, by design:

- **Document, transaction and composite entities are excluded.** No orders, no invoices, no on-hand.
- **Workflows are not copied.** Rebuild any workflow the demo needs by hand.
- Some entities are global and cannot be copied at all (retail channel and POS-register-class entities).
- Intercompany accounting and intercompany master-plan associations are not supported.

**A dead run blocks the next one.** Data management refuses to start a project while a previous execution
still has an entity in `Executing`, which is what a killed run leaves behind. Clear it from *Job history*: mark
the run and use **Delete**. That removes the job history and staging only; if the dead run never reached the
target step (`TargetStatus` still `NotRun` everywhere), nothing was written into the new company.

**If the environment goes away mid-copy.** The per-entity state lives in the database, so *Job history* still
shows which entities reached staging and which reached target. When the environment answers again, check
that view first rather than assuming the job resumed. **View staging data** and **Copy data to target** work
per entity for what is already staged, and the whole project can be re-run, since the copy updates what exists
rather than duplicating it. Re-running is the safe default; the per-entity path is worth it only for a small
tail.

Sharp edges from the Microsoft documentation and from the measured run:

| Symptom | Cause / fix |
|---|---|
| Customers or vendors fail validation | Their default site/warehouse must exist first: include sites and warehouses, load them first, or unmap those fields. Also the payment chain, §2c |
| Customer/vendor numbers rejected on import | The number sequence forbids lower numbers. Set *Allow user to change to a lower number* = Yes (or, with reset-to-smallest, the higher-number equivalent) |
| Fixed-asset depreciation manual schedules fail | Depreciation profiles must run before them: move them later in the sequence |
| Account structures import as Draft | The active-group composite entities export only active structures; re-activate after import |
| `The entity '<X> active group' cannot be copied into another legal entity because type 'Composite entity' is not supported` | Expected: the account-structure and advanced-rule-structure active groups are composite and are skipped |
| `Configuration key not enabled for the entity '<X>'` | Expected: the module is off in this environment; the entity is skipped |
| `Entity '<X>' doesn't have primary or unique key` | A warning on parameter-style entities, not a failure |
| Re-runs are slower than expected | Enable change tracking on the entities so the copy pushes incrementally |

### 2c. Measured gaps after a copy

The copy above left the destination unable to hold customers, through one chain:

1. **The templates did not include Cash and bank management**, so the destination had **no bank groups, bank
   accounts or bank transaction types**.
2. **Customer and vendor payment methods failed**, because their bank-type methods reference a bank account
   and a transaction type that did not exist.
3. **Most customers failed**, because they reference a payment method. The released products imported; the
   customers did not (two of the donor's customers made it).

Two more gaps sit outside that chain:

- **Company-scoped values of custom-list financial dimensions are not copied** (measured on `ItemGroup`). The
  dimension definition is tenant-wide, but a custom list's values can be scoped per legal entity, and those
  values are in no copy template. Anything posting with that dimension fails in the new company.
- **Ledger parameters fail** with `'Rev Rec' ... not found in the related table 'Name of journal'`
  (`RevRecJournalNameId`): journal names load after ledger parameters. Ledger parameters is **not an OData
  entity**, so no script can repair it. Re-run **Copy data to target** for that one entity from the copy's
  *Job history* after the rest has loaded, or set the field on the *General ledger parameters* page.

[`Repair-CopyGaps.ps1`](../scripts/Repair-CopyGaps.ps1) closes the OData-reachable part, idempotently and
inside the target only: bank groups used by the donor's accounts, bank accounts with the donor's id prefix
removed (`-BankIdPrefix`, or `-BankIdMap` pairs), bank transaction types, the company-scoped dimension values
(`-Dimension`, default `ItemGroup`), then customer and vendor payment methods with their bank account
remapped. It is a dry run until `-Apply`. Payloads are stripped of empty strings and `LastFileDate`: an empty
string trips field validators (a QR-IBAN check on bank accounts) that an absent field does not. After it runs,
re-run the customer (and vendor) entities of the copy with **Copy data to target**.

Run order for a golden company: copy (§2b) > `Repair-CopyGaps.ps1 -Apply` > ledger parameters re-run > customer
and vendor re-run > `Test-DemoCompany.ps1` > export (§2e).

### 2d. Reading the copy's errors

`GetExecutionErrors` (table in §2a) returns a JSON array **serialised into a string**, one record per failed
row (`RecordId`, `Field`, `ErrorMessage`). The messages carry unescaped quotes and line breaks, so
`ConvertFrom-Json` fails part-way through a large result. Split on the record boundary (`},{"RecordId"`) and
read the three fields with one regex per record; `ConvertFrom-FoExecutionErrors` in
[`Fo.Api.psm1`](../scripts/Fo.Api.psm1) does exactly that and parsed all 3,506 records of the measured run.

Group the messages, quoted values masked, before reading them: the entity-level *Error* status only means "at
least one row failed". The measured run with a stock US donor, grouped:

| Row-level error (grouped) | Rows | Why, and whether it matters |
|---|---|---|
| `The value '*' in field '*' is not found in the related table '*'` | 2,100 | Group again by the related table. Sales tax authorities 1,404 and Sales tax codes 390 (the tax setup references vendor accounts, and vendors failed with the payment chain, §2c): matters as soon as the demo posts a taxed order, so re-run the tax entities after the repair. Vendors 93, Methods of payment - customers 30: the §2c chain. Sales tax period setup 90, Items 67 and a tail of single digits: re-check after the repair |
| `Product dimension '*' is not active` | 495 | the donor's variant demo products; harmless unless the demo shows those variants |
| `The entered attribute enumeration value is not unique` | 405 | tenant-wide attribute types already populated; harmless |
| `Field '*' must be filled in` | 57 | read the field: often a payment method or bank reference, §2c |
| `The product master of the product variant that you try to release has not been released` | 51 | variant release ordering; harmless unless the demo shows those variants |
| `User not found with User ID '*'` | 45 | the donor's demo users do not exist in this tenant; harmless |
| `Default value is not within the range for attribute type <name>` | 134 | the donor's retail attribute demo data; harmless |
| `update not allowed for field 'Party ID'` / `'Company'` | 3 | the donor's own legal-entity and party rows; they must not overwrite the new company |
| `There are transactions for this main account` | 2 | the chart of accounts is shared and already populated |
| `'Rev Rec' ... not found in the related table 'Name of journal'` | 1 | ledger parameters, §2c |
| `Matching record with key 'NumberSequenceCode' ... does not exist` | 1 | a reference to a sequence the copy skipped; recreate only if the demo needs that document type |

About a third of the rows (product dimensions, attributes, users, variant releases; 1,130 of 3,506) are harmless noise from the
donor's retail and attribute demo data. The rest trace back to two causes worth fixing in the golden company:
the payment chain (§2c) and the tax setup that hangs off vendors.

`Watch-CopyProgress.ps1 -JobId '<JobId>' -ErrorsOnly -ErrorsOut errors.csv` prints this grouping and writes
every row for filtering.

### 2e. Export the golden package

When the golden company passes `Test-DemoCompany.ps1` with bank accounts and payment methods present, export its
configuration with [`Export-GoldenPackage.ps1`](../scripts/Export-GoldenPackage.ps1). Measured on a 10.0.48
sandbox: `DataManagementDefinitionGroups` and `DataManagementDefinitionGroupDetails` both accept POST, so the export
project needs no UI.

**The entity list.** Start from the golden company's copy project (its `DataManagementDefinitionGroupDetails`, with
the levels and sequences the default templates set) and keep only entities with
`DataManagementEntities.IsShared` = No: the global address book, chart of accounts, financial dimensions, products
and attributes, currencies, units, users and the number sequence tables are shared, and a shared entity in a
package writes into every company on import. Drop what the demo seeds itself (customers, released products and
their satellites, sites, warehouses and locations), drop what failed in the copy with no value to a demo company,
add the *Cash and bank* chain the copy lacked (`Bank groups`, `Bank transaction type`, `Bank parameters`,
`Bank accounts`, `Vendor payment method`) and move `Ledger parameters` after `Journal names` in its level (the
copy failed it on the `Rev Rec` journal name). Measured: 366 copy entities -> 228 in the package.

**Every detail row needs `AutoGenerateMapping = Yes` on POST.** Without it the row has no field mapping
(`ValidationStatus` No): the export stages 0 rows for it and the execution then sits in *Executing* indefinitely
(measured: 228 entities, 0 rows, still Executing after 40 minutes). With it the row comes back
`ValidationStatus` Yes. Measured with the flag: *Succeeded* in 30 minutes, a 351 KB zip. Download it through
`GetExportedPackageUrl` and keep it **outside the environment** with its `.sha256` and the entity list: a sandbox
refresh removes the golden company too, and the package is what rebuilds it.

**A one-entity package fills an OData gap.** Where an entity refuses OData POST on a build (measured:
`ProductGroups`, *The field with ID '0' does not exist in table 'InventProductGroupEntity'*), take that entity's
manifest node and one exported row from the golden package as the template, write the demo's rows, and import it
with the same script and a one-entity list.

Done-criteria for step 2: the company opens, has a ledger and currency, bank accounts and payment methods,
and can create a customer and release a product without an error dialog.

## 3. Apply the company profile

Everything in [company-profile.md](company-profile.md) §2-§6, applied inside the new `dataAreaId`. Order
matters; each group depends on the previous:

1. **Number sequences**: the formats the audience will read (item, customer, sales order, quotation,
   invoice). Non-continuous unless the customer's process is genuinely continuous.
2. **Inventory dimension groups**: storage and tracking groups per the profile. If the spine identifier is a
   serial, the tracking group with *Serial number* active is referenced by every released product that
   carries it. Tracking dimension groups are **tenant-wide**: create it with the company prefix.
3. **Sites and warehouses**: the customer's names, not the donor's. Warehouse locations only where the demo
   shows them.
4. **Item groups, item model groups, units**: the vocabulary the catalog will use.
5. **Customer groups, terms of payment, delivery terms, price/discount groups.**
6. **Category hierarchy and product attributes**: **tenant-wide**; create them prefixed with the company
   code, never by renaming a shared one.

Route: OData writes for anything with a data entity (scriptable, repeatable, and what the seed script
contains); an interactive admin or the F&O MCP server's form tools for the wizard-driven ones, the
number-sequence wizard in particular.

**OData coverage check before you promise a scripted profile.** Search the environment's `$metadata` (or the
F&O MCP server's `data_find_entity_type`) for each object type. Measured on a current unified sandbox:
`TrackingDimensionGroups`, `ProductCategoryHierarchies` + `ProductCategories`, `AttributeGroups` +
`ProductAttributes`, `OperationalSitesV2`, `Warehouses`, `ProductGroups` (item groups), `CustomerGroups`,
`PriceCustomerGroups` / `LineDiscountCustomerGroups`, `PaymentTerms`, `DeliveryTerms`, `SequenceV2Tables` and
`NumberSequencesV2References` exist. **No entity exists for storage dimension groups or item model groups**
(`InventoryPolicies` only exposes the item-model-group inventory policies) or for attribute-group membership.
Plan around that: reuse a stock tenant-wide storage group (`SiteWH` is Site + Warehouse), keep the item model
groups the seed brings, and log attribute-group membership as a UI step.

Write-side traps measured on the same build: `ProductGroups` refuses POST (use a one-entity package, §2e);
`Warehouses` needs `WarehouseType` = `Standard` (the entity default is rejected); `ProductCategories` takes
`ParentProductCategoryName` but refuses `ParentProductCategoryHierarchyName` on insert;
`ReleasedProductCreationsV2` creates the product master, the release and the en-us translation in one POST, but has
no price: PATCH `ReleasedProductsV2.SalesPrice` and `ProductDefaultOrderSettings` (sales site and warehouse)
afterwards; `SalesPriceAgreements` POST writes a price-group or account agreement directly (no journal to post);
inventory journals (`InventoryCountingJournalHeaders` + `Lines`) can be created but have **no posting action**, so
seeding on-hand ends with one UI step (*Inventory management > Journal entries > Item counting > Counting > Post*).

## 4. Seed the demo data

Only now do products, customers and transactions make sense:

- **Products are shared, released products are not.** Create the product master once (tenant-wide,
  prefixed), then release it into the demo company; the released record carries the item group, dimension
  groups, default order settings and price.
- **Transactions are per company and are what the demo shows.** Seed enough sales orders and quotations for
  the storyline and no more; volume is not realism.

Serial-controlled units: create the released product with the serial tracking group, then the serial numbers
themselves, the identifiers the audience will type into the DW front end.

Everything in this step belongs in a re-runnable seed script in the engagement folder (§6).

## 5. Verify the round-trip

[`Test-DemoCompany.ps1`](../scripts/Test-DemoCompany.ps1) covers the read side. The full check:

| Check | How |
|---|---|
| Legal entity exists | `GET /data/LegalEntities('<CODE>')` |
| The company has its own catalog | `GET /data/ReleasedProductsV2/$count?cross-company=true&$filter=dataAreaId eq '<CODE>'` |
| ...its own customers, orders, bank accounts, payment methods | same shape on `CustomersV3`, `SalesOrderHeadersV2`, `BankAccounts`, `CustomerPaymentMethods` |
| Number sequences assigned | `NumberSequencesV2References` is global: filter on `ScopeValue eq '<CODE>'`, not `dataAreaId` |
| Number formats applied | create one record through the UI or API and read the id back; the format is the assertion |
| Spine identifier resolves | look up one seeded serial or unit id and confirm it returns exactly one row |
| DW sees the same rows | run the import job and compare counts on the DW side ([dw-wiring.md](dw-wiring.md)) |

**The `cross-company=true` + `dataAreaId` pair is the whole point.** A count without it answers for the
identity's default company and looks plausible while being someone else's data.

## 6. Make it re-runnable, and retire it

A sandbox refresh, an environment reset or a point-in-time restore removes demo companies without notice. The
deliverable is not the company, it is the recipe that rebuilds it:

- the golden package (§2e), kept outside the environment, and the golden company's run log;
- `demo-companies/<slug>/company-profile.md` in the engagement folder: the intent;
- `demo-companies/<slug>/seed/`: create, package import, profile writes, product/customer/transaction seeds,
  in run order, each idempotent;
- a one-page run log: what was created, by which route, and what needed a UI step.

**Reset between demo runs**: delete the transactions the demo creates (orders and quotations placed live) and
re-run the transaction seed, not a full company rebuild.

**Retire, do not delete.** When a demo is over, mark its company **dormant** in the shared list
([shared-sandbox.md](shared-sandbox.md) "Announce and record") and **unbind its DW site**: disable or remove the
DW jobs that carry its `dataAreaId`, so nothing reads from or writes to it. The legal entity stays. Deleting
one is possible only while it holds no transactions and gains nothing; a dormant company can be handed to the
next demo by re-running the package import and the seed over it.
