# Dynamics 365 Finance & Operations: the ERP-side traps

## Contents

- [Prove the endpoint before the first run](#prove-the-endpoint-before-the-first-run)
- [Filtering by prefix: `eq` with a wildcard, never `startswith()`](#filtering-by-prefix-eq-with-a-wildcard-never-startswith)
- [Sales order lines: never send an empty unit](#sales-order-lines-never-send-an-empty-unit)
- [Posting what OData cannot post: the environment's ERP MCP server](#posting-what-odata-cannot-post-the-environments-erp-mcp-server)
- [A legal entity from a template company over a data management package](#a-legal-entity-from-a-template-company-over-a-data-management-package)
- [The F&O connector package: the service and its group share a name](#the-fo-connector-package-the-service-and-its-group-share-a-name)

> What a Dynamics 365 Finance & Operations (F&O) environment does that the Truvio Commerce (powered
> by Dynamicweb) side cannot see, measured against F&O 10.0.47 and 10.0.48 environments over OData.
> The platform side (the OData source provider, job files, schema snapshots, the run queue) is owned
> by [`../../dw-integration-framework/SKILL.md`](../../dw-integration-framework/SKILL.md); this
> reference is the F&O side. Loaded from the SKILL.md "Deep reference" table.

## Prove the endpoint before the first run

An OData source on a failing credential does not fail fast: the provider retries until the
activity's request timeout and holds the run queue meanwhile, and MCP `test_integration_endpoint`
answers only `Unauthorized`
([job-file-format.md](../../dw-integration-framework/references/job-file-format.md#running-a-job-and-proving-it-did-something)).
So the credential is proven outside the platform first, with the same Entra application:

1. **Request a client-credentials token** for `https://<env>.operations.dynamics.com/.default`. A
   failure here carries the `AADSTS` code the platform never shows: bad secret, wrong tenant, or an
   application without consent.
2. **Read one entity, not `$metadata`.** `$metadata` answers 200 for any valid token. An entity
   read answers 403 until the application is registered in F&O under *Microsoft Entra
   applications* and mapped to a user whose roles can read the entity.
3. Only then save the secret into the endpoint's authentication, run `test_integration_endpoint`
   and expect rows, and only then create, run or schedule an OData activity.

## Filtering by prefix: `eq` with a wildcard, never `startswith()`

F&O's OData provider cannot translate `startswith()`: the request answers **400** with the inner
error *The type System.String for the query operator is not Queryable!* (a `NotSupportedException`),
and a platform stage job carrying that filter fails with `HttpStatusCode BadRequest`. F&O's `eq`
accepts a trailing `*` as a wildcard, so the prefix filter is:

```text
$filter=ProductNumber eq 'ABC-*'
```

Measured on 10.0.48 against `ProductTranslations`: the `startswith()` form answered 400 and the `eq`
form returned exactly the matching products. The same form pins any tenant-wide entity (one with no
`dataAreaId`) to the integration's own rows.

## Sales order lines: never send an empty unit

Platform order lines usually carry no unit id. An OData destination that maps a NULL or empty
`SalesUnitSymbol` onto `SalesOrderLines` writes it as given, and F&O stores the line **with no sales
unit** instead of defaulting it from the item. Nothing fails; the line is simply unit-less in F&O.
Resolve the unit in the source (the staging view the export reads): the order line's unit, else the
released product's sales unit, else a fixed default such as `ea`. Re-export one order and read the
line back from F&O before scheduling the export.

## Posting what OData cannot post: the environment's ERP MCP server

F&O's OData surface creates inventory journals (`InventoryCountingJournalHeaders` and `Lines`) but
has **no action that posts one**, so counted stock stays at 0 on hand. Posting does not need a person
in the F&O client: the environment's own MCP endpoint (`https://<env>.operations.dynamics.com/mcp`,
server *Dynamics 365 ERP MCP Server*) accepts the same client-credentials bearer token as OData and
exposes form tools that drive a form the way a user does. It acts as the F&O user the Entra
application is mapped to (the server's current-user tool shows which), so that user's roles decide
what it may post.

The measured sequence for a counting journal, **all in one MCP session**:

```text
form_open_menu_item  InventJournalTableCount (Display) in the target company
select the journal's row in the overview grid
form_click_control   postJournal                -> dialog "Post journal <n>"
set the dialog field "Transfer all posting errors to a new journal" to Yes
form_click_control   OkButton                   -> "Journal has been posted."
```

Then read `WarehousesOnHandV2` for the company: it returns the counted quantities, and the
platform's stock apply writes non-zero rows.

**Every MCP HTTP session is its own F&O client session, and a dialog left open locks the journal.**
A session that opened *Check journal* or *Post journal* and ended without OK or Cancel leaves the
journal marked in use: the next session's post answers *Journal <n> is being used by <user>*, the
check button is disabled, and an unlock button appears. Recovery is `InventJournalUnlockButton`, then
Yes in the confirmation box (*... is unlocked and available for edits or posting*), then post again.
Finish or cancel every dialog in the session that opened it.

## A legal entity from a template company over a data management package

Seeding a new legal entity from a template company over the data management OData entities (no F&O
client) has two traps on export and one on import. Measured on a 10.0.48 unified sandbox: 228
entities, about 31,700 rows.

- **Every definition group detail needs `AutoGenerateMapping = Yes` on POST.** A
  `DataManagementDefinitionGroupDetails` row posted without it has no field mapping
  (`ValidationStatus` No): the export stages 0 rows for it and the execution then sits in
  *Executing* indefinitely. With the flag the same export succeeded in about 30 minutes.
- **Shared entities do not belong in the package.** Entities with `DataManagementEntities.IsShared`
  = Yes (the ledger, number sequence codes, groups and references, the global address book, chart
  of accounts, products, currencies, units) export every company's rows and import into every
  company. Keep them out of the entity list and write the new company's rows over OData before the
  import, ledger first: `Ledgers` (`Name` is not insertable), then one `SequenceV2Tables` row per
  template sequence with the company segment swapped, then `NumberSequencesV2References`. Their keys
  contain the `ScopeType` enum, so a GET by key path answers 404 even when the row exists: check
  existence with `$filter` on `ScopeValue` and the code.
- **A package import does not remap the template company's code inside field values.**
  `ImportFromPackage` sets the target legal entity, but company-valued fields keep the template code
  as exported (measured: journal names `VOUCHERSERIESCOMPANYID`, ledger allocation rules `COMPANY` /
  `FROMCOMPANY`, subledger transfer rules and allocation basis sources `LEGALENTITYID`, tracking
  number groups `NUMBERSEQUENCESCOPEDATAAREA`; 114 values in one package). *Copy into legal entity*
  remaps these; a package import does not. Rewrite the template code to the target code in those
  fields of each entity file, in a copy of the package, before the upload, and assert that no
  template-code value remains in a company-valued field.

## The F&O connector package: the service and its group share a name

The Dynamicweb F&O connector is an X++ model that exposes a SOAP service for live integration. As
shipped, the service (`AxService` `DWService`, `ExternalName` `DWWebservice`) and its service group
(`AxServiceGroup` `DWService`) have the same name. The WCF contract then fails to compile: calls to
`/soap/services/DWService` answer 500, and `?wsdl` answers *Service compilation failed* (event 447).
Renaming only the service gives *contract filter mismatch*, because two other objects still point
at the old name.

The fix, all three in one model change:

| Object | Change |
|---|---|
| The service | Name `DWService` to `DWWebservice` (its `ExternalName`) |
| The service group's member | `Name` / `Service` to `DWWebservice` |
| The `DWWebService` privilege's entry point | `ObjectName` to `DWWebservice` |

The service **group** keeps the name `DWService`, so the endpoint URL and the SoapAction
(`.../DWWebservice/Process`, taken from `ExternalName`) do not change for the platform. Measured on a
10.0.47 dev environment: build with 0 errors, `?wsdl` 200 with port type `DWWebservice`, and a
`Process` POST with that SoapAction answering 200 `ProcessResponse`. Deploying a package into an
environment is the environment owner's decision.
