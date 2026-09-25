# The staging pattern: land 1:1, reshape in views, apply

## Contents

- [Why two stages](#why-two-stages)
- [Stage 1: the staging table](#stage-1-the-staging-table)
- [Stage 1: the activity](#stage-1-the-activity)
- [Job files for OData activities](#job-files-for-odata-activities)
- [Stage 2: views](#stage-2-views)
- [Stage 2: activities and the options that bite](#stage-2-activities-and-the-options-that-bite)
- [Keeping the rest of the solution untouched](#keeping-the-rest-of-the-solution-untouched)
- [Run order](#run-order)

## Why two stages

The MCP mapping tools carry no transform: the script types they can set are None, Append, Prepend, Constant,
CurrentTime, NewGuid and Invert; Code and Substring are read-only there. A derived id, a joined name, a cleaned
placeholder or a status translation therefore cannot live in the mapping. It lives in SQL:

```
F&O entity --(stage 1: OData provider -> Dynamicweb provider)--> <P>_<Entity> staging table
staging tables --(SQL view)--> <P>_v_<Target> --(stage 2: Dynamicweb provider source -> Ecom / User / Order / Dynamicweb provider)--> platform tables
```

Views are visible to the Dynamicweb provider as a source next to tables. They can be queried before any run,
which makes stage 2 reviewable and testable with a handful of hand-written staging rows.

## Stage 1: the staging table

- One table per entity set, named with a prefix the solution does not use otherwise.
- **Column names are the F&O property names**, so the mapping is 1:1 and a column's origin is never a question.
- Primary key = the entity key. Key columns `nvarchar(50)`: `WarehousesOnHandV2` has a 9-column key and a wider
  type overflows the 900-byte index limit.
- Types follow the provider: text and enums `nvarchar`, decimals `decimal(32,10)`, `DateTimeOffset` as
  `datetime2`, and a `LoadedUtc` default column for "when did this row arrive".
- Idempotent DDL (`IF OBJECT_ID(...) IS NULL CREATE TABLE`); `fo_job_files.py sql` writes it from the spec.

## Stage 1: the activity

- Source: OData provider, `Predefined endpoint` = the entity's endpoint id, `Mode` = `Full Replication` (the
  other value is `Delta replication`; neither has an enum in the MCP parameter list), page size 1000,
  *Fail job if endpoint is busy or down* on, *Do not store last response in log file* on (the log stays small
  and holds no payload).
- Destination: Dynamicweb provider, *Remove missing rows after import in the destination tables only* **on**:
  the staging table mirrors the entity each run, including deletes.
- Mapping: entity -> staging table, every staged column, the entity key marked `IsKey`.

## Job files for OData activities

When the endpoint does not authenticate yet, MCP cannot create an OData activity
([endpoints-and-auth.md](endpoints-and-auth.md#building-before-the-secret-exists)). Write the job file instead,
with [`fo_job_files.py jobs`](../scripts/fo_job_files.py):

- UTF-16LE with a BOM and CRLF, under `<wwwroot>/Files/Files/Integration/jobs/<group>/<name>.xml`; the file
  name is the activity name. MCP `get_integration_activities` lists it immediately.
- The OData side of the schema snapshot comes from the environment's own `$metadata` (pulled once with any
  valid token), keys first, in the provider's type mapping. The SQL side is read from `sys.columns` and
  scoped to the one table or view.
- **Never write an empty `<conditionals />` element**: the loader then drops the whole table mapping and
  `get_integration_activity_mappings` shows an activity with no mappings. Omit the element.
- Read every generated activity back with MCP `get_integration_activity_mappings` before relying on it.

Once the endpoints authenticate, re-saving each mapping with MCP `save_integration_activity_mapping` refreshes
the snapshot from the live provider.

## Stage 2: views

One view per target table, reading staging (and platform tables for lookups), output columns named exactly as
the destination columns. Patterns that recur:

```sql
-- SQL. Local installs only: the staging schema has no Management API or MCP surface.
-- Ids from ERP keys: letters and digits only, prefixed so the integration's rows are countable.
N'<P>' + dbo.<P>_Id(r.ItemNumber)                        AS ProductId,
-- Name from the tenant-wide translation entity, falling back to the search name.
COALESCE(NULLIF(t.ProductName, N''), NULLIF(r.SearchName, N''), r.ItemNumber) AS ProductName,
-- Group membership as Ecom provider columns (it has no EcomGroupProductRelation table).
STRING_AGG(N'<P>GRP' + CAST(c.CategoryRecordId AS nvarchar(30)), N',') AS Groups,
-- Unused price scope columns stay NULL, never 0.
CASE WHEN a.CustomerAccountNumber <> N'' THEN CAST(g.AccessUserId AS nvarchar(50)) END AS PriceUserGroupId,
-- Open-ended F&O dates are 1900-01-01.
CASE WHEN a.PriceApplicableToDate > '1900-01-02' THEN a.PriceApplicableToDate END AS PriceValidTo
```

Every view filters on the legal entity it serves (a one-row configuration table holding `DataAreaId` keeps that in
one place), and every lookup into platform tables is restricted to the rows the integration owns. After creating
or altering views, no flush is owed: views hold no data and the platform caches nothing about them. The
activities do cache their schema (next section).

## Stage 2: activities and the options that bite

| Target | Destination provider | Key | Options |
|---|---|---|---|
| `EcomGroups`, `EcomShopGroupRelation`, `EcomGroupRelations` | Dynamicweb | `GroupId`+`GroupLanguageId`; shop+group; group+parent | defaults (upsert) |
| `EcomProducts` | Ecom | `ProductId`+`ProductVariantId`+`ProductLanguageId` | `Shop` = the target shop, *Create missing groups* **off** (it defaults on), *Update only existing products* as the design needs |
| `AccessUserGroup` | User | `AccessGroupExternalId` | *Match parent group by display name* on; create the parent group first (MCP `save_user_groups`) |
| `EcomPrices` | Dynamicweb | `PriceId` | **no** remove-missing option of any kind |
| `EcomStockLocation` | Dynamicweb | `StockLocationExternalId` | run before stock units |
| `EcomStockUnit` | Dynamicweb | product, variant, unit, location | location id looked up in the view |
| `EcomOrders` (status) | Dynamicweb | `OrderId` | *Update only existing records* on |
| `EcomOrders` (invoices as ledger entries) | Order | `OrderIntegrationOrderId`, `OrderId` supplied non-key | [order-flow.md](order-flow.md) |

Traps, each measured:

- **"Remove missing rows after import in the destination tables only" is table-wide.** On a job into
  `EcomPrices` it deletes every price row the job did not write, including prices from any other source. Use it
  on staging tables only.
- **The Ecom provider exposes no `EcomGroupProductRelation` table**; the membership goes on `EcomProducts` as
  `Groups` and `PrimaryGroup`.
- **An existing activity validates new mappings against its stored snapshot, not the live view.** Add a column
  to a view after the activity exists and `save_integration_activity_mapping` answers *has no column named*.
  Delete and recreate the activity (MCP `delete_integration_activity`, `create_integration_activity`) or patch
  the snapshot; design the views before creating the activities.
- **A Dynamicweb-provider activity created over MCP stores the whole database schema** as its destination
  snapshot (several MB). Harmless, but it is why the generated OData jobs scope theirs.
- **The price cache survives both providers.** Recycle the application or clear the price cache before judging
  prices on a page.

## Keeping the rest of the solution untouched

When the solution already has curated data (a demo storyline, a migration in progress), land the ERP data beside
it, not over it, until someone decides the swap:

- a dedicated shop (a PIM shop with no area is invisible to every storefront), prefixed product and group ids;
- customer companies under one dedicated parent group, keyed on a prefixed external id;
- prices and stock only for the integration's own products;
- order status and invoices only for orders the integration itself exported.

Take a copy-only database backup before the first stage-2 run, and count the untouched tables before and after
every run ([verification.md](verification.md)).

## Run order

1. Stage 1, every entity (the order does not matter; each mirrors its own table).
2. Categories apply, then products apply (products reference the groups), then customers apply.
3. Prices apply (reads the customer groups for account prices), stock locations, then stock units.
4. Order status and invoices apply.
5. Recycle or clear caches, rebuild the product index the storefront queries.

The platform runs one activity at a time; a runner that queues the next job only after the previous one reports
`Completed` keeps a failure from cascading.
