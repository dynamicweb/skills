---
name: dw-integration-framework
type: knowledge
group: integration
mcp: optional
dynamo: true
description: 'Understand Dynamicweb 10 Integration Framework architecture and patterns, and set up, run, schedule, or diagnose a Data Integration activity through the MCP tools. Triggers: Integration Framework, external systems, source/target providers, import/export products/users/orders via CSV/XML/Excel/OData, a failed or hanging integration activity. Non-triggers: ERP specifics -> dw-integration-erp; Business Central -> dw-integration-bc.'
---

# Integration Framework

## Where to find things

| If you need to... | Read this reference |
|---|---|
| Author, copy or patch a job file on disk — the doubled `Files\Files` path, the UTF-16LE encoding, the `<Schema>` snapshot, the two column element shapes, SqlProvider connection nodes, file-destination paths, and what a job file publishes over HTTP | [references/job-file-format.md](references/job-file-format.md) |
| Know what a shipped provider actually does when it writes — Ecom key matching and minted ids, the `EcomPrices` identity, the five user tables, the update-only OrderProvider destination and the missing ledger filter, SqlProvider staging clones and datetime precision, the XSLT seam, and restore/reset ordering | [references/provider-behaviour.md](references/provider-behaviour.md) |
| Write a provider in C# because no shipped provider fits | [references/custom-provider-authoring.md](references/custom-provider-authoring.md) |

## Without MCP

The knowledge here stands alone; the Dynamicweb MCP tools it names are the way to apply it, and
in-product they are the only way — the MCP tool set plus read/write under `Files/` is the whole
surface these steps may use. When no tool covers the operation, **stop and tell the user**, naming
the admin screen that performs it, rather than substituting a guessed HTTP call, a file edit
outside `Files/`, or SQL. The Management API, the serializer and direct SQL exist only outside the
product, are never a step in this skill, and are owned by
[`dw-data-access`](../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance".

## Architecture Overview

The Integration Framework moves data between Dynamicweb and external systems via **Activities**. Each activity has a **Source** (reads data) and a **Destination** (writes data), connected by a **mapping** (field-level translation between source and destination schemas).

```
External system / API
        ↓
    Source Provider (ISource + ISourceReader)
        ↓
    Table/Column Mapping  ←→  Column scripting (Append, Constant, Substring, etc.)
        ↓
Destination Provider (IDestination + IDestinationWriter)
        ↓
    Dynamicweb DB / API / External system
```

## The three integration approaches (by name)

The framework supports three approaches, distinguished by *when* the data moves:

1. **Ad-hoc activities** — run on demand (a manual import/export of a data set, one execution at a time).
2. **Batch (scheduled) integration** — activities run by scheduled tasks at fixed intervals
   (hourly / daily / weekly), moving accumulated changes on each run.
3. **Live (real-time) integration** — retrieves data from a remote system in real time, e.g. live
   prices or stock states. The remote system is queried per request rather than on a schedule, so
   the displayed value is always current.

The same activity shape (source provider + destination provider + field mapping) underlies all three;
only the trigger differs — manual, scheduled, or per-request. In the DW docs' terms, an
**integration provider** is "a piece of software for moving data between Dynamicweb and an external
data source, like an XML file, a CSV file or an SQL database", and an activity requires two of them:
a source provider matching the data source and a destination provider matching the data destination.

## Admin: Creating and Running Activities

Admin path: **Integration > Activities**

### Create an Activity

1. Click **New custom activity** (or use a blueprint for standard scenarios)
2. **General tab:** Name, Group, "Create mappings at runtime" checkbox (auto-maps columns with the same name)
3. **Source tab:** Select and configure the source provider
4. **Destination tab:** Select and configure the destination provider
5. **Notification tab:** Email on completion/failure
6. **Cache tab:** Cache services to clear after the run
7. **Repository index tab:** Search indexes to rebuild after the run

### Configure Mappings

After creating the activity:
1. Click **New table mapping** — pick source table and destination table
2. Set **key columns** (used for upsert logic; defaults to primary key, override with e.g., `ProductNumber`)
3. Add **column mappings** manually or via "Add multiple column mappings"
4. Set **conditionals** per table mapping (filter which source rows are processed)
5. Optionally apply **scripting** to individual column mappings (Append, Constant, Substring, Prepend, etc.)
6. Set **null handling** per column: Default (type default), Constant value, or Skip row

### Running Activities

- **Run now** — from the Activity Info widget in admin
- **Scheduled** — via Settings > Scheduled Tasks → `DataIntegration.RunIntegrationActivityAddIn` task
- **Triggered from code** — `ActivityService.RunActivity(activityId)`

**Logs** are stored in `/Files/System/Log/Data integration/` as `_lastrun.log` and `_lastrunresult.log`.

**An activity is a file, not a database row.** It lives at
`<wwwroot>/Files/Files/Integration/jobs/{activityFolder}/{jobName}.xml` — note the doubled
`Files/Files` — the file name **is** the activity name, and the file is UTF-16LE with a BOM.
Copying one between solutions works; so does scripting a family of them. The whole format,
including what re-configuration a copy needs, is in
[references/job-file-format.md](references/job-file-format.md).

## Setting Up Activities via MCP Tools

Everything above describes the admin-UI mechanics; this is the same concept model driven
through MCP tools instead.

**Concept model, mapped to tools:**
- **Activity** — one import/export job, identified as `group\name`. List with
  `get_integration_activities`, inspect with `get_integration_activity`.
- **Providers** — where data comes from and goes to. Both sides are providers; discover them
  with `get_integration_providers`, their settings with `get_integration_provider_parameters`,
  and the tables/columns they expose with `get_integration_provider_schema`.
- **Mappings** — source table → destination table, then column → column. **Key columns**
  (`IsKey`) decide insert-vs-update: without a key, every run inserts duplicates.
  **Conditionals** filter rows. Manage with `get_integration_activity_mappings` /
  `save_integration_activity_mapping`.
- **Endpoints** — authenticated remote requests (OAuth S2S, Basic, Bearer, ...), grouped in
  collections that can share authentication. The OData provider references an endpoint by id.
  Manage with `get_integration_endpoints` / `save_integration_endpoint`, verify with
  `test_integration_endpoint`.
- **Runs & logs** — `run_integration_activity` QUEUES a run (asynchronous — a queued result is
  not a completed run). Poll `get_integration_activity_status`; verify the outcome in
  `get_integration_activity_logs`. Row counts appear only as log text.
- **Schedules** — `schedule_integration_activity` binds a scheduled task to the activity
  (manage further with the scheduled-task tools — see
  [dw-extend-scheduled-tasks](../dw-extend-scheduled-tasks)).

**Choosing a destination provider for imports:**
- **Ecom provider** — ecommerce data with conveniences: auto-creates missing IDs, language
  rows, groups, manufacturers. First choice for product imports; costs ~3x the memory of the
  Dynamicweb provider.
- **Dynamicweb provider** — generic access to the whole database. Precise but manual:
  relation tables (e.g. group-product relations) must be mapped explicitly.
- **User / Order providers** — users and orders, with domain settings (user key field, "export
  not yet exported orders", order state after export). The user provider writes five tables and the
  order provider's export filter has no ledger exclusion — see
  [references/provider-behaviour.md](references/provider-behaviour.md).
- **OData provider** — reads/writes a remote OData API via an endpoint. Source modes: full
  replication vs **delta** (changed-since-last-run; never deletes; first run falls back to
  full).
- **SQL / XML / CSV / Excel providers** — external databases and files. File providers resolve
  paths under `/Files`.

**Flow: file import (CSV/XML/Excel → Dynamicweb/Ecom):**
1. `get_integration_providers`, then `get_integration_provider_parameters` for the file
   provider — identify the source-file/folder parameters.
2. If the source file doesn't exist in the archive yet, upload it to
   `/Files/Files/Integration` (the archive folder integration file providers read from) — pass
   the resulting virtual path to the provider's source parameter.
3. `create_integration_activity` with the file provider as source and Ecom/Dynamicweb as
   destination.
4. `get_integration_provider_schema` for both sides of the new activity, then
   `save_integration_activity_mapping` per table: map columns, mark the natural key (e.g.
   `ProductNumber`) `IsKey=true`.
5. `run_integration_activity` (confirm first), poll `get_integration_activity_status`, verify
   in `get_integration_activity_logs`.

**Flow: endpoint-driven ERP sync (e.g. Business Central OData):**
1. `save_integration_endpoint` — URL, collection, and inline authentication (OAuth S2S needs
   client id, tenant id, client secret). `test_integration_endpoint` before going further.
2. `create_integration_activity` with the OData provider as source (its endpoint parameter
   takes the endpoint id) and Ecom/Dynamicweb/User as destination; map with
   `save_integration_activity_mapping`.
3. Run once manually and verify, then `schedule_integration_activity` for the recurring sync.
4. Dependent activities (customers before orders, groups before products) must run in
   dependency order — schedule them accordingly.

**Flow: diagnose a failed run:**
1. `get_integration_activity_status` — still running? failed? when did it last succeed?
2. `get_integration_activity_logs` — the error lines usually name the offending table, column,
   or remote error; page back for context, or read the previous run's log to compare.
3. Typical causes: authentication expired (test the endpoint), schema drift (a mapped column
   no longer exists — re-check with `get_integration_provider_schema`), bad source data (see
   rules below), or the remote system rate-limiting.

**Rules:**
- Explicitly set IDs in imported data (ProductID etc.) may contain ONLY letters and digits —
  spaces, commas, dots, or special characters break the import.
- **Excel provider source path**: splitting the file across "Source folder" (folder path) +
  "Source file" (file name) — the split the parameter labels suggest — can fail validation
  with "Excel file '...' does not exist" even when the file is really there. If that happens,
  put the FULL virtual path (e.g. `/Files/Files/Integration/order_for_customer.xlsx`) in
  "Source file" and leave "Source folder" empty; re-validate before concluding the file is
  genuinely missing.
- Never claim a run succeeded from a queued result: the log is the evidence.
- `deleteRowsMissingFromSource` and "remove missing" options are destructive — enable only
  when the source is the complete truth for that table.
- After a product import, storefront lists driven by index queries show new products only
  after the repository index rebuilds — if products are "missing," check the index (see
  [dw-search-indexing](../dw-search-indexing)) before blaming the import.
- Do not guess provider parameter names or table/column names — read them with the provider
  tools; the save tools reject unknown names and list valid candidates.
- If `get_integration_provider_schema` comes back with zero tables for an *existing*
  activity's file-based source (CSV/XML/Excel) right after uploading or replacing that source
  file, don't conclude the schema is unreadable: call it with the activity id (not a
  reconstructed provider-type-name + parameters guess, which is exactly where the Excel path
  pitfall above bites) and retry once. `save_integration_activity_mapping` reads the same live
  schema at save time and can succeed even when a prior schema read looked empty.

## Built-in Source/Destination Providers

| Provider | Direction | Use for |
|---------|----------|--------|
| SQL Provider | Both | Read/write Dynamicweb or any SQL Server DB |
| OData Source Provider | Source | Read from OData v4 APIs (ERP, BC, etc.) |
| CSV Provider | Both | Flat file import/export |
| XML Provider | Both | XML file import/export |
| JSON Provider | Source | JSON API import |
| HTTP Provider | Source | Generic HTTP endpoint |
| Ecom / Product Provider | Destination | Import products into the DW product catalog |
| User Provider | Destination | Import users, accounts, addresses and impersonation relations |
| Order Provider | Both | Export orders from DW; as a destination it **updates** orders and cannot create one unless the ids are supplied |

What each of these does once it starts writing — key matching, minted ids, required identity
columns, silent deletes, and the caches it does and does not invalidate — is in
[references/provider-behaviour.md](references/provider-behaviour.md).

## Column Mapping Scripting

Column mappings support transformations at the mapping layer:

| Script type | Purpose |
|------------|--------|
| `Constant` | Replace the source value with a fixed constant |
| `Append` | Append a string to the source value |
| `Prepend` | Prepend a string to the source value |
| `Substring` | Extract a portion of the source value |
| `New Guid` | Generate a new GUID (ignores source value) |
| `Current time` | Replace with current timestamp |
| `Invert` | Invert a boolean |
| `Code` | C# expression evaluated at runtime (via `ScriptTypeProvider`) |

That list is the whole set: **there is no value-lookup or conversion table at the mapping layer.**
Translate a source system's codes into the site's own ids with an **XSLT on the source document**
instead — it runs before the reader and the column mapper, and it keeps the payload
source-system-native. Per-column null handling is equally narrow: `NullEmptyActionType` is
`None | Default | Constant | SkipRow`, and `SkipRow` skips the **whole row**, so a per-row exception
belongs in the source data. Both are worked through in
[references/provider-behaviour.md](references/provider-behaviour.md).

## Mapping Conditionals

Filter which source rows to process using expressions on the table mapping:

| Operator | Description |
|----------|-------------|
| `Equals` | Exact match |
| `Contains` | Substring match |
| `In` | Value is in a comma-separated list |
| `Less than` / `Greater than` | Numeric/date comparison |

Context-sensitive values in conditionals and scripting:
- `@Request(key)` — HTTP request value
- `@Session(key)` — session value
- `@User(property)` — current user property
- `@Page(property)` — current page property
- `@Code(...)` — inline C# expression

## Activity Groups

Activities can be organized in groups (folders). Groups can inherit source/destination configuration, and subgroups override inherited settings. Groups are just subfolders of the job storage at `/Files/Files/Integration/jobs/`; `Files/System/Integration/Jobs/` holds the platform's shipped quick-setup templates and nothing placed there becomes an activity.

## Pitfalls

**A job carries a frozen schema snapshot.** Every activity on a solution goes stale the moment a
custom product, order or order-line field is added: on the source side the new column is silently
dropped, on the destination side mapping it is a hard refusal. Read
`does not exists in the schema` as a stale snapshot, and re-save the mapping through
`save_integration_activity_mapping` (which reads the live schema) or patch the snapshot by hand —
[references/job-file-format.md](references/job-file-format.md#the-schema-block-is-a-snapshot-not-a-live-read).

**`Job succeeded` proves rows were processed, not that the effect you wanted exists.** An export
that wrote its file to the wrong directory, an import whose unresolvable rows were deleted before
the merge, and a restore whose delete half did nothing all log the same success line. Verify the
artefact path, the destination row count, or the rendered page.

**A write through a provider does not always invalidate the domain cache.** An EcomProvider import
that writes product fields leaves the `ProductService` read-through cache stale even with cache
clearing enabled — the flush verb and the exact storage type name are in
[references/provider-behaviour.md](references/provider-behaviour.md#ecomprovider-as-a-destination).

**Job files are served anonymously.** `.xml` is not on the static-file blocklist, so a job file and
anything in it — including a SQL-auth connection string — answers an anonymous HTTP GET. Use
integrated security and sweep the job folder for credentials
([references/job-file-format.md](references/job-file-format.md#what-a-job-file-publishes)).

**Writing a provider in C#?** The `RunJob` / `LoadSettings` contract and the rest of the authoring
pitfalls live in [references/custom-provider-authoring.md](references/custom-provider-authoring.md).

## Next Steps

- **ERP-specific integration?** See [dw-integration-erp](../dw-integration-erp)
- **Business Central connector?** See [dw-integration-bc](../dw-integration-bc)
- **Triggering activities from code?** See [dw-extend-providers](../dw-extend-providers)
- **Custom scheduled trigger?** See [dw-extend-scheduled-tasks](../dw-extend-scheduled-tasks)
- **Writing your own provider?** See [references/custom-provider-authoring.md](references/custom-provider-authoring.md)
