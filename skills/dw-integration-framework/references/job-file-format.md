# The Data Integration job file

## Contents

- [Surface: when the file is the thing you edit](#surface-when-the-file-is-the-thing-you-edit)
- [Where an activity lives, and what names it](#where-an-activity-lives-and-what-names-it)
- [Editing a job file: copy, decode, splice, round-trip](#editing-a-job-file-copy-decode-splice-round-trip)
- [The `<Schema>` block is a snapshot, not a live read](#the-schema-block-is-a-snapshot-not-a-live-read)
- [An OData activity before its endpoint authenticates](#an-odata-activity-before-its-endpoint-authenticates)
- [Column elements: which shape belongs to which provider](#column-elements-which-shape-belongs-to-which-provider)
- [SqlProvider connection nodes](#sqlprovider-connection-nodes)
- [File destinations: folder, file name, and what neither of them does](#file-destinations-folder-file-name-and-what-neither-of-them-does)
- [What a job file publishes](#what-a-job-file-publishes)
- [Running a job and proving it did something](#running-a-job-and-proving-it-did-something)

> On 10.28.x an Integration Framework activity is a **file on disk**, not a database row. This
> reference owns the file format: the path, the encoding, the schema snapshot, the column element
> shapes, the connection nodes, and the security consequences. Loaded from the SKILL.md
> "Where to find things" row for job-file authoring.

## Surface: when the file is the thing you edit

Reach for the surfaces in this order.

| Surface | Use it for |
|---|---|
| MCP `create_integration_activity`, `save_integration_activity_mapping`, `get_integration_provider_schema` | Creating an activity and its mappings. The create call reads the **live** provider schema, which is the whole reason to prefer it, and also why it needs a reachable, authenticated source: an OData activity cannot be created before its endpoint authenticates. A mapping save on an existing activity does not always re-read the source ([below](#the-schema-block-is-a-snapshot-not-a-live-read)). |
| **The job file on disk** (`Files/Files/Integration/jobs/`) | Moving an activity between installs, scripting a family of near-identical activities, building an OData activity before its credential exists, and any edit the tools above refuse, chiefly patching a stale `<Schema>` snapshot. It is the only authoring surface on a build where a restart is not available. |
| `SQL` | Nothing. There is no activity table to write; a `sys.tables` sweep for `%Integration%` / `%Job%` returns only `ScheduledTask`, `ScheduledTaskExecution` and `ScheduledTaskFolder`. |

Those two are the whole surface. When neither the tools nor the file reaches the operation, name the
Data Integration admin screen that does it rather than reaching for another transport.

A job file is **build output** whenever it can be: generate it from a script and edit the
generator, so a schema change is a regeneration rather than a hand-patch. **The generator reads its
template from a pristine copy that nothing ever writes, never from the live job file it produces.**
A generator that patches the file it wrote last time re-applies its own patch on every run, so the
output drifts further from the template each time and a regeneration never diffs clean.

## Where an activity lives, and what names it

```
<wwwroot>\Files\Files\Integration\jobs\<Activity name>.xml
```

Three facts that are each a separate wrong turn:

- **The path doubles `Files\Files`.** The DW file archive root is `wwwroot/Files`, and a stored
  archive path keeps its own leading `/Files` segment, so a job setting of `/Files/Integration/x`
  resolves to `wwwroot/Files/Files/Integration/x` and is *served* at the doubled URL
  `/Files/Files/Integration/x`. A single-`Files` URL 404s, which is how a reachable folder gets
  written off as unreachable.
- **The file name is the activity name.** The string before `.xml` is what appears in
  Settings > Integration > Data integration and what a scheduled task's single `Activity`
  parameter binds to. Keep `&` out of it: the same string has to survive a filename and an XML
  attribute value.
- **`Files/System/Integration/Jobs/` is a decoy.** It holds the platform's shipped quick-setup
  templates. Nothing placed there becomes an activity.

Activity groups are just subfolders of `jobs/`.

## Editing a job file: copy, decode, splice, round-trip

**A job file is UTF-16LE with a BOM** (first two bytes `FF FE`) and its declaration says
`encoding="utf-16"`. Every scripting stack writes UTF-8 by default, so a hand-authored file is
simply not a job — the runner will not read it.

The recipe that holds:

1. **Copy an existing job that already works** rather than authoring one from a template. The
   working file carries the element shapes, the provider node names and the schema block that a
   template does not.
2. Read the source with a `utf16le` decoder, do string surgery, write it back with a `utf16le`
   encoder. For a surgical single-node change on a large file, splice on **bytes** and assert the
   prefix and suffix are byte-identical afterwards, BOM intact.
3. **Round-trip decode and compare** to what you meant to write, before running anything.
4. **Diff the decoded copy against the decoded source.** It is the only cheap way to see that a
   36 KB or 418 KB file differs in exactly the lines you intended.
5. **Re-mint `<mapping uid="...">`.** It is a GUID and a copy inherits it; two live jobs sharing
   one mapping uid is a collision waiting to happen.
6. A naive `grep` over a job file is a **false clean** — decode first, or the UTF-16 bytes hide
   whatever you were searching for.
7. **Never write an empty `<conditionals />` element.** The loader drops the whole table mapping
   it belongs to, with no error and no log line: the activity lists, opens, and has no mappings
   [dw 10.28.11]. A generator writes the element only when the mapping has at least one
   conditional. Read every written job back with MCP `get_integration_activity_mappings` and
   compare the column count per table with what the file carries.

## The `<Schema>` block is a snapshot, not a live read

A job carries a cached snapshot of each provider's view of its tables, captured when the job was
authored or last saved (with `CreateMappingAtRuntime=False`). It is never re-read at run time.
Two consequences, and they differ by side:

| Side | A column added after the job was saved |
|---|---|
| Source | **Silently dropped.** No error, no log line; the payload column simply does not arrive. |
| Destination / provider | **Hard refusal** before a row is read: `Source table(<T>) has column mappings: <cols> that does not exists in the schema`. |

So **every job on a solution goes stale the moment a custom order, order-line or product field is
added**, and nothing tells you until someone maps the new column. Read a
`does not exists in the schema` error as a stale snapshot first, not a mapping typo — the column
usually does exist on the table.

Repair options, best first:

- Re-save the activity through MCP `save_integration_activity_mapping`. This does not refresh
  every snapshot: on an **existing** activity with a SQL view as source, a column added to the
  view after the activity was created is refused by the save as unknown (*has no column named*),
  because the save validates against the stored snapshot [dw 10.28.11]. When the save refuses a
  column that the source really has, go to the next option.
- Delete and recreate the activity (MCP `delete_integration_activity`, then
  `create_integration_activity` and its mappings): the new activity captures the current source,
  and the same mapping then saves. Design the source views before creating their activities, and
  recreate after every view change that adds a mapped column.
- Re-author the job with `CreateMappingAtRuntime` enabled so it re-reads the live table.
- Patch the `<Schema>` block by hand, adding the `<column>` element in the shape the file already
  uses (below). Assert the column name is present in the schema string before writing the file, so
  the failure cannot silently return.

**Always author a `<Schema>` for a SqlProvider job, scoped to the tables the activity touches.**
With no `<Schema>`, the provider introspects the whole database on first run and persists that
snapshot into the job file — a multi-megabyte document listing every table, which then becomes the
truth the mapping is validated against. A scoped, generated schema (from `sys.columns`, for exactly
the tables in play) keeps the file in the tens of KB, makes the activity's blast radius readable in
its own definition, and is regenerable after any DDL change. The exception is an EcomProvider
**destination** schema: that is the platform's own table catalogue and does not drift, so leave it
to DW.

## An OData activity before its endpoint authenticates

MCP `create_integration_activity` with the OData provider as source fetches the source schema from
the endpoint while it creates. With no authentication on the endpoint it answers *Credentials not
set for endpoint*; with a wrong or placeholder secret, *Unauthorized*. No job file is written in
either case, so nothing OData-backed can be created over MCP until `test_integration_endpoint`
returns rows [dw 10.28.11].

When the integration has to be built before the credential arrives, write the job files instead:

- Everything else can exist first: the endpoint collection and its endpoints (URL and query
  options, no authentication), and the destination side.
- Generate the file (UTF-16LE with a BOM, one file per activity, under the group folder) with a
  `<Schema>` scoped to the mapped tables and columns only, the OData side taken from the service's
  own metadata document (no MCP tool reads a remote service's metadata, so the user supplies that
  file under `Files/`). The rules above hold: no empty `<conditionals />`, a fresh mapping uid per
  file.
- MCP `get_integration_activities` lists a written file immediately. Read each back with
  `get_integration_activity_mappings` before relying on it.
- Once the endpoint authenticates, prove it with `test_integration_endpoint`, then run one activity
  and read its log. A generated snapshot that disagrees with the live service is repaired the way
  any stale snapshot is ([above](#the-schema-block-is-a-snapshot-not-a-live-read)).

## Column elements: which shape belongs to which provider

Two element shapes exist and the file format does not distinguish them by position.

`Dynamicweb.DataIntegration.Integration.Column` — the shape every XmlProvider schema uses:

```xml
<column type="Dynamicweb.DataIntegration.Integration.Column">
  <name>OrderId</name><type>System.String</type>
  <isNew>False</isNew><isPrimaryKey>False</isPrimaryKey>
</column>
```

`Dynamicweb.DataIntegration.ProviderHelpers.SqlColumn` — what a **SQL-backed destination** requires,
with the type repeated on both attributes and the full child set:

```xml
<column type="Dynamicweb.DataIntegration.ProviderHelpers.SqlColumn"
        columnType="Dynamicweb.DataIntegration.ProviderHelpers.SqlColumn">
  <name>OrderId</name><type>System.String</type><isNew>False</isNew>
  <limit>50</limit><isIdentity>False</isIdentity><sqlDbType>NVarChar</sqlDbType>
  <isPrimaryKey>False</isPrimaryKey>
</column>
```

- **`SqlDestinationWriter` casts every schema column to `SqlColumn` unconditionally**, so the plain
  form throws `Unable to cast object of type 'Dynamicweb.DataIntegration.Integration.Column' to type
  'Dynamicweb.DataIntegration.ProviderHelpers.SqlColumn'` the moment writing starts.
- **A SqlProvider *source* reader does not cast**, so it tolerates the plain form. The same file can
  therefore be half right: it reads fine and dies at the first write, which sends the investigation
  to the destination table, the mapping keys or the connection instead of to the element type. Read
  that `InvalidCastException` as a schema-shape fault.
- `<limit>` is a **character count**, not bytes: halve `sys.columns.max_length` for `nvarchar` /
  `nchar`; `-1` stays `-1`.
- The OrderProvider's own schema uses the `SqlColumn` shape too, which is the shape to inject when
  adding a custom order field to an existing job.

## SqlProvider connection nodes

SqlProvider is the one provider whose **parameter list and file format disagree**. The
`AddInParameter` names (`SourceServer`, `SourceDatabase`, `SourceUsername`, `SourcePassword`,
`SourceServerSSPI`, `SourceConnectionString`, and the `Destination*` equivalents) are UI aliases.
The `XmlNode` constructor reads the **backing property names**, and anything serialized under a
`Source*` / `Destination*` name is ignored with no warning — a fully populated, completely inert
source block is the natural first attempt.

| Write this node | Not this alias |
|---|---|
| `<SqlConnectionString>` (alone is enough) | `<SourceConnectionString>` |
| `<ManualConnectionString>` (alone is enough) | — |
| `<Server>` + `<Catalog>` | `<SourceServer>` / `<SourceDatabase>` |
| `<Username>` / `<Password>` | `<SourceUsername>` / `<SourcePassword>` |
| `<SourceServerSSPI>` / `<DestinationServerSSPI>` | — (these two are read under their own names) |

The failure signature for the alias mistake is
`The ConnectionString property has not been initialized`, raised from `BaseSqlReader..ctor` or from
`SqlProvider.RunJob` — it reads like a platform defect and is a naming one.

**The empty-node fallback is destination-only.** A job that carries `<SqlConnectionString />`
empty and works is, every time, an XmlProvider source with a SqlProvider **destination**: the
destination picks up the site's own connection. A SqlProvider **source** resolves its own
connection and has no default, so an empty node there means "no connection string" and the job
cannot start. Every activity that reads from SQL — every restore, every staged-mock feed, every
view-backed job — therefore carries a literal connection string.

## File destinations: folder, file name, and what neither of them does

For an XmlProvider (or any file) **destination**:

```xml
<DestinationFile>orders.xml</DestinationFile>
<DestinationFolder>/Files/Integration/outbox</DestinationFolder>
<DestinationXslfile />
<IncludeTimestampInFileName>True</IncludeTimestampInFileName>
<Encoding>utf-8</Encoding>
<SkipTroublesomeRows>False</SkipTroublesomeRows>
<Schema>...one <table> per destinationTableName...</Schema>
```

- **`DestinationFolder` is the directory; `DestinationFile` contributes only its file name.** Any
  directory part inside `DestinationFile` is discarded silently, so
  `/Files/Integration/outbox/orders.xml` plus a folder of `/Files` writes
  `wwwroot/Files/Files/orders<timestamp>.xml` and the outbox you were watching stays empty.
- **The destination needs its own `<Schema>`**, with one `<table><tableName>` per mapping's
  `destinationTableName` and the *output* column names; the source schema does not stand in for it.
  Without it the job dies with `Destination table(s) not found in schema: ...` before a row is read.
- **`DestinationFolder` accepts an absolute physical path** outside the web root and creates into it
  on the first run. That turns "our integration outbox is served anonymously" from an
  infrastructure problem into a one-node configuration change: point it at a sibling of the
  application directory and the payloads stop having a URL at all.
- **There is no skip-when-empty option.** The file is created before the row count is known, so an
  XSLT cannot suppress it either: an export on a short interval grows a directory of identical
  empty files forever, and the only lever is the task's interval.

## What a job file publishes

Job files sit in the file archive, and on a stock DW 10.28.x install the static-file middleware
blocks `.config`, `.cshtml`, `.query` and `.index` **by extension but not `.xml`** — so a job file
answers HTTP 200 to an anonymous request. Whatever the file contains is public.

| Exposure | What to do |
|---|---|
| A SQL-auth connection string in a job file is a database username and password on a public URL, and DW **re-serializes the job on every run**, so a one-off hand edit does not hold | Use integrated security: `<SourceServerSSPI>` / `<DestinationServerSSPI>` alongside `<Server>` / `<Catalog>`. Activities re-run with identical row counts and the credential stays absent. |
| A SqlProvider **source** cannot use the empty-node fallback, so it must name an instance | If the SQL instance is local, name it relatively (`Server=.\<instance>`): the host name and the topology leave the file and only a database name remains. |
| Job folders are missed by a secrets sweep because the naive grep is a false clean on UTF-16 | Add `Files/Files/Integration/jobs` to the secrets sweep and **decode before grepping**. Also sweep `/Files/System/Items/*.xml` and `/Files/System/Serializer/Serializer.config.json`, which are anonymously readable on the same build. |
| Generated job XML from a SQL-auth install carries the credential into any repo, backup or transfer package | Do not commit or ship it. |
| The legacy job-runner route `.../integrationv2/JobRunner.aspx?jobsToRun=<job>` executes **any** job on an anonymous GET — no cookie, no bearer — and on builds where the modern job-runner route 404s it is the only route that works | Treat every install as exposed until proven otherwise, and keep nothing in a job file that an anonymous run could leak. Closing the route is an IIS host edit, not an in-product one: outside the product, see dw-data-access `management-api-and-sql.md` §Restricting the legacy Data Integration job-runner route. |

A demo or dev install records the exposure; an install destined for go-live asserts zero
occurrences of `Password=` under the decoded job folder.

## Running a job and proving it did something

- MCP `run_integration_activity` **queues** a run. Poll `get_integration_activity_status`, then read
  `get_integration_activity_logs`; the log is the evidence, never the queued result.
- **An OData source never fails fast on a bad credential.** Every run starts with a readiness probe
  (`<entity>?$top=1`) and on failure retries with growing delays (5, 15, 30, 45, 60, 180, 300,
  600 s) until the activity's request timeout elapses, then fails with *Request has timed out after
  <n> milliseconds*. With a 20-minute timeout the run occupied the queue for 20 minutes and nothing
  queued behind it started [dw 10.28.11]. `test_integration_endpoint` green, with rows, comes before
  the first run, and a chain of activities is never scheduled on an endpoint that has not passed it.
  Its failure answer is only `Unauthorized`: the identity provider's error code (which says bad
  secret, wrong tenant or missing consent) is not surfaced by any MCP tool, so ask the user for a
  direct token request outside the product when the cause is not obvious.
- A scheduled task binds to one activity through
  `Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn`, whose only parameter is
  `Activity`, taking the activity name (the file name).
- Logs land in `Files/System/Log/Data integration/` as `<Activity>_lastrun.log` and
  `<Activity>_lastrunresult.log`.
- **`Job succeeded` means the rows were processed, not that the artefact you expected exists.** An
  export that wrote its file to the wrong directory logs exactly the same success line. A runner
  verifies the artefact path, the destination row count, or the rendered page — not the exit line.
