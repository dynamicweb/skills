---
name: dw-integration-fo
type: flow
group: integration
mcp: optional
dynamo: false
compatibility: Requires Python 3.12+ (scripts/fo_job_files.py) and sqlcmd with Windows authentication to the site database
description: 'Build a DW10 <-> Dynamics 365 F&O integration end to end on the Integration Framework: S2S endpoints, entity map, OData staging, stage-2 views, sales order export, status and invoices back, verification. Triggers: F&O OData endpoint, CustomersV3/ReleasedProductsV2 jobs, order export to F&O. Discovery -> dw-integration-fo-discovery.'
---

# F&O integration

Connect a Truvio Commerce (powered by Dynamicweb) solution to a Dynamics 365 Finance and Operations (F&O)
environment with the platform's own Integration Framework: OData endpoints with service-to-service
authentication, activities that read F&O data entities into staging tables, SQL views that reshape staging
into the platform's tables, and an order export that writes sales orders back. No custom code and no package
deployed into F&O.

This SKILL.md is a nav layer. Each phase links to the reference that owns the recipe and its traps.

## Without MCP

The steps here are Dynamicweb MCP tool calls (endpoints, activities, mappings, runs) plus two surfaces the MCP
does not have: SQL for the staging tables and views, and the job file on disk for any OData activity that has to
exist before its endpoint authenticates. With no MCP server, drop **one** rung to the Management API, then the
serializer; SQL stays local-install only and is used here for the staging schema, never for platform tables.
The ladder is owned by [`dw-data-access`](../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance".
Where no rung reaches a step, produce the endpoint list, the spec file and the SQL for the operator to apply.

## How to run me

| # | Phase | Question it answers | Reference |
|---|---|---|---|
| 0 | **Discovery** | Which entities carry data, per legal entity, and which key is the spine? | [`dw-integration-fo-discovery`](../dw-integration-fo-discovery/SKILL.md) |
| 1 | **Access and endpoints** | Which identity, which resource, one endpoint per entity set, a test that proves an entity read | [references/endpoints-and-auth.md](references/endpoints-and-auth.md) |
| 2 | **Entity map and company pin** | Which F&O entity feeds which platform table, keyed on what, pinned to which `dataAreaId` | [references/entity-map.md](references/entity-map.md) |
| 3 | **Stage 1: land** | OData entity -> staging table, 1:1, mirrored each run | [references/staging-pattern.md](references/staging-pattern.md) |
| 4 | **Stage 2: apply** | Staging -> products, groups, customers, prices, stock through SQL views | [references/staging-pattern.md](references/staging-pattern.md) |
| 5 | **Orders out, status and invoices back** | Platform order -> `SalesOrderHeadersV2` / `SalesOrderLines`; F&O status and invoices -> the order | [references/order-flow.md](references/order-flow.md) |
| 6 | **Verify** | The ladder from token to storefront, and a re-run that changes nothing | [references/verification.md](references/verification.md) |

Discovery comes first when a real customer environment is in scope: its population census decides which
entities are worth an activity and which identifier the storefront is keyed on. Per-engagement outputs (the
spec file, the SQL, the run log, the README with run order and counts) live in the engagement folder, never
inside this skill.

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [fo_job_files.py](scripts/fo_job_files.py) | Writes with `--apply` only | From a pulled `$metadata` and a spec: the entity subset JSON, the staging DDL, and the OData job files (stage 1 reads, order export writes) in the shape the platform writes them |

Run it (see the header for the spec format; a starting spec is
[assets/templates/integration-spec.example.json](assets/templates/integration-spec.example.json)):

```powershell
python3 scripts/fo_job_files.py entities --metadata <metadata.xml> --sets ReleasedProductsV2,CustomersV3 --out <folder>/fo-entities.json --apply
python3 scripts/fo_job_files.py sql --spec <folder>/spec.json --entities <folder>/fo-entities.json --out <folder>/01-staging.sql --apply
python3 scripts/fo_job_files.py jobs --spec <folder>/spec.json --entities <folder>/fo-entities.json --jobs "<wwwroot>/Files/Files/Integration/jobs" --sql-server <server> --database <db> --apply
```

Why a generator at all: MCP `create_integration_activity` validates an OData source by calling the endpoint, so
**no OData activity can be created over MCP until the endpoint authenticates**, and
`get_integration_provider_schema` has nothing to return either. The generator lets the whole integration be
built, reviewed and loaded before credentials exist; once they do, re-saving a mapping over MCP replaces the
generated schema snapshot with the live one.

## Where to find things

| If you need to... | Read |
|---|---|
| Register the Entra app in F&O, create the endpoint collection, the exact S2S parameter labels, why `$metadata` 200 is not access, the readiness probe and its retries | references/endpoints-and-auth.md |
| Pick the entity set for products, names, categories, customers, prices, stock, orders, invoices; their keys; tenant-wide vs company entities; the `cross-company` pin | references/entity-map.md |
| Build staging tables and views; which destination options are destructive; the Ecom provider's group columns; stale schema snapshots; job files | references/staging-pattern.md |
| Export orders safely (state-gated queue, supplied order numbers, lines, mark-sent), map F&O status back, land invoices as ledger entries | references/order-flow.md |
| Prove each rung, count rows, keep the rest of the solution unchanged, re-run for a zero diff | references/verification.md |
| Provider mechanics (key matching, minted ids, OrderProvider insert rules, the XSLT seam) | [`dw-integration-framework`](../dw-integration-framework/SKILL.md) and its [provider-behaviour.md](../dw-integration-framework/references/provider-behaviour.md) |
| Job file format, encoding, schema snapshot | [`dw-integration-framework` job-file-format.md](../dw-integration-framework/references/job-file-format.md) |
| Which system owns which field | [`dw-integration-erp`](../dw-integration-erp/SKILL.md) |

## Always-on rules

- **The ERP is a source and a target in the Integration Framework, never a channel or a feed.**
- **Every company-scoped read names its legal entity:** `cross-company=true` plus `$filter=dataAreaId eq '<CODE>'`.
  Without the pair F&O answers for the integration user's default company and the job looks healthy while
  reading someone else's data. Tenant-wide entities (products' names, categories) are pinned by a name or
  number prefix instead ([references/entity-map.md](references/entity-map.md)).
- **Land first, reshape second.** Stage 1 copies the entity 1:1 into a staging table named after the F&O
  properties; every transform lives in a SQL view read by stage 2. The MCP mapping layer cannot carry a
  transform (no Code or Substring script over MCP), and a view can be read, tested and diffed before any run.
- **Scope every write to rows the integration owns.** Prefixed ids, a dedicated shop, customer groups under a
  dedicated parent, and no "remove missing" option on a platform table that also holds rows from anywhere else.
- **Writes into F&O go only to a legal entity you own.** An export activity is built and reviewed long before it
  is run; its runner refuses any company but the one named for it.
- **A queued run is not a finished run, and a finished run is not a correct one.** Poll the status, read the log,
  count the rows ([references/verification.md](references/verification.md)).
- **Secrets never touch a file.** The client secret goes from a vault into the endpoint's authentication through
  the save call; it is encrypted at rest there and never returned by any tool. Scripts never log request bodies.

## The F&O connector plugin (parked)

The Dynamicweb F&O connector is an X++ model deployed into F&O that exposes a SOAP/WCF service for live
integration. Everything in this skill is **OData-only** and needs no package in F&O. When the plugin is back in
scope, note its known defect: the service and the service group are both named `DWService`, which breaks the
`?wsdl` compilation; the fix renames the **service** to `DWWebservice` (its `ExternalName`) and keeps the
**service group** `DWService`. Deploying a package is an environment-owner decision and out of scope here.

## Top-level pitfalls

- **`$metadata` answering 200 proves nothing.** It answers for any valid token; an entity read returns 403 until
  the app is mapped to an F&O user under *Microsoft Entra applications*. Test with an entity read.
- **A bad credential costs minutes, not a second.** The OData source probes `<entity>?$top=1` and retries ten
  times with a growing delay (5 s up to 300 s) before the job fails. Test the endpoint before queueing a job.
- **`test_integration_endpoint` says only `Unauthorized`.** The Entra error code (`AADSTS...`) is not surfaced;
  get it from a direct token request when the cause is not obvious.
- **`ReleasedProductsV2` has no product name.** Names and descriptions come from `ProductTranslations`
  (tenant-wide, keyed on product number and language).
- **Mirror options are per table, not per row set.** *Remove missing rows after import in the destination
  tables only* on a stage-2 job into `EcomPrices` deletes every price the job did not write. Mirror staging
  tables only.
- **The Ecom provider exposes no group-product relation table.** Group membership rides on `EcomProducts` as
  the `Groups` (comma-separated ids) and `PrimaryGroup` columns.
- **An existing activity validates mappings against its stored schema snapshot.** A column added to a view after
  the activity was created is "not a column" until the activity is recreated (or its snapshot patched).
- **An empty `<conditionals />` element in a job file drops the whole mapping without an error.**
- **An `&` in an activity or group name breaks the MCP log lookup.** Keep it out of names; endpoint collection
  names (database rows) are fine.
- **State written by a job sends no order-state mail**: jobs never call `OrderService.Save`.

## Related skills

- `dw-integration-fo-discovery`: run first; its brief scopes stage 1 and names the spine identifier.
- `dw-integration-framework`: activities, providers, mappings, job files.
- `dw-integration-erp`: the ERP-to-PIM ownership split.
- `dw-data-access`: the surface ladder and the SQL rules the staging schema follows.
