# Out-of-product recipes: Integration

This reference holds the out-of-product recipes for the Integration Framework: an activity on
10.28.x is a **file on disk**, not a database row, so moving, copying and validating one is file
work on the host, not a tool call. The in-product skill for this area
([dw-integration-framework](../../dw-integration-framework/SKILL.md)) is `dynamo: true` and carries
no instruction on those surfaces, so it keeps a one-line pointer here instead of the recipe.

Every recipe names its surface in the repo convention: MCP tools `snake_case` in backticks,
Management API commands `PascalCase` in backticks with the route on first use in this file, and
`SQL` labelled as such. There is **no** `SQL` recipe in this file and there cannot be one: a
`sys.tables` sweep for `%Integration%` / `%Job%` returns only `ScheduledTask`,
`ScheduledTaskExecution` and `ScheduledTaskFolder`. There is no activity table to write.

## Contents

- [Copy an integration activity between installs](#copy-an-integration-activity-between-installs)
- [Validate a job file before running it](#validate-a-job-file-before-running-it)
- [Bind an activity to a scheduled task](#bind-an-activity-to-a-scheduled-task)

## Copy an integration activity between installs

In-product home: [dw-integration-framework](../../dw-integration-framework/SKILL.md)
(`job-file-format.md`), which owns the format itself — the `<Schema>` snapshot, the two column
element shapes, the SqlProvider connection nodes and what a job file publishes over HTTP.

**Surface: the file system on the host.** Prefer MCP `create_integration_activity` /
`save_integration_activity_mapping` when they reach the operation, because they read the **live**
provider schema at save time. The file is the surface for moving an activity between installs,
scripting a family of near-identical activities, and any edit those tools refuse — chiefly patching
a stale `<Schema>` snapshot. It is also the only authoring surface on a build where a restart is
not available.

**The rules, and the why:**

- **Copy a job that already WORKS, never a template.** The working file carries the element shapes,
  the provider node names and the schema block a template does not.
- **The archive root doubles `Files\Files`.** Activities live at
  `<wwwroot>\Files\Files\Integration\jobs\<Activity name>.xml`. The DW file archive root is
  `wwwroot/Files`, and a stored archive path keeps its own leading `/Files` segment, so a job
  setting of `/Files/Integration/x` resolves to `wwwroot/Files/Files/Integration/x` and is served at
  the doubled URL. **A single-`Files` URL 404s, which is how a reachable folder gets written off as
  unreachable.** `Files/System/Integration/Jobs/` is a decoy: it holds the platform's shipped
  quick-setup templates and nothing placed there becomes an activity.
- **The file name IS the activity name** — the string a scheduled task's `Activity` parameter binds
  to and what appears in Settings > Integration > Data integration. Keep `&` out of it: the same
  string has to survive a filename and an XML attribute value.
- **A job file is UTF-16LE with a BOM** (first two bytes `FF FE`) and its declaration says
  `encoding="utf-16"`. Every scripting stack writes UTF-8 by default, so a hand-authored file is
  simply not a job and the runner will not read it.
- **A naive `grep` over a job file is a FALSE CLEAN.** The UTF-16 bytes hide whatever you were
  searching for, so a secrets sweep that does not decode first reports zero occurrences of a
  credential that is sitting in the file. Decode, then assert. Sweep
  `Files/Files/Integration/jobs` alongside `/Files/System/Items/*.xml` and
  `/Files/System/Serializer/Serializer.config.json`, which are anonymously readable on the same
  build ([dw-setup-config](../../dw-setup-config/SKILL.md) `host-exposure-and-paths.md`).
- **Re-mint every `<mapping uid="...">`.** It is a GUID and a copy inherits it; two live jobs
  sharing one mapping uid is a collision waiting to happen.
- **Round-trip and diff before running anything.** Decode the written bytes again and compare with
  what you meant to write, then diff the decoded copy against the decoded source — it is the only
  cheap way to see that a 36 KB or 418 KB file differs in exactly the lines you intended.

**The script:** [`../scripts/Copy-DwIntegrationJob.ps1`](../scripts/Copy-DwIntegrationJob.ps1) is
that sequence enforced — it refuses a source that is not UTF-16LE, re-mints the mapping uids,
re-points named elements, prints the diff, and round-trips the written bytes before reporting
success. Dry run by default.

```powershell
pwsh -NoProfile -File scripts/Copy-DwIntegrationJob.ps1 -SourcePath "<wwwroot>/Files/Files/Integration/jobs/Orders export.xml" -DestinationPath "<wwwroot>/Files/Files/Integration/jobs/Orders export nightly.xml" -SetNode @{ Catalog = 'TargetDb' } -Apply
```

## Validate a job file before running it

In-product home: [dw-integration-framework](../../dw-integration-framework/SKILL.md)
(`job-file-format.md`), which carries the element shapes and the connection-node table in full.

**Surface: the file system on the host.** A job carries a cached snapshot of each provider's view
of its tables, captured when the job was authored or last saved, and **never re-read at run time**.
Every job on a solution therefore goes stale the moment a custom order, order-line or product field
is added, and nothing tells you until someone maps the new column.

The faults worth asserting up front, because each one fails at run time with a message that points
somewhere else:

- **A mapped column missing from the `<Schema>`.** On the **source** side it is *silently dropped*:
  no error, no log line, the payload column simply does not arrive. On the **destination** side it
  is a hard refusal before a row is read — `Source table(<T>) has column mappings: <cols> that does
  not exists in the schema`. **Read that as a stale snapshot first, not a mapping typo**: the column
  usually does exist on the table. The repair, best first: re-save through
  `save_integration_activity_mapping` (live schema at save time), re-author with
  `CreateMappingAtRuntime` enabled, or patch the `<Schema>` block by hand.
- **The wrong column element shape on a SQL-backed destination.** `SqlDestinationWriter` casts
  every schema column to `Dynamicweb.DataIntegration.ProviderHelpers.SqlColumn` unconditionally, so
  the plain `Dynamicweb.DataIntegration.Integration.Column` throws `InvalidCastException` the moment
  writing starts. A SqlProvider **source** reader does not cast, so the same file reads fine and
  dies at the first write — which sends the investigation to the destination table, the mapping keys
  or the connection instead of to the element type.
- **A connection written under a UI alias.** SqlProvider's `AddInParameter` names (`SourceServer`,
  `SourceDatabase`, `SourceUsername`, `SourcePassword`, `SourceConnectionString` and the
  `Destination*` twins) are aliases; the `XmlNode` constructor reads the backing property names
  (`SqlConnectionString`, `ManualConnectionString`, `Server`, `Catalog`, `Username`, `Password`), and
  anything under an alias is ignored **with no warning**. A fully populated, completely inert source
  block is the natural first attempt, and the failure signature — `The ConnectionString property has
  not been initialized` from `BaseSqlReader..ctor` or `SqlProvider.RunJob` — reads like a platform
  defect and is a naming one.
- **An empty connection node on a SqlProvider SOURCE.** The empty-node fallback is
  **destination-only**: a destination picks up the site's own connection, a source resolves its own
  and has no default.
- **A credential in a connection node.** `.xml` is not on the static-file middleware's blocklist, so
  a job file answers HTTP 200 anonymously, and DW **re-serializes the job on every run** — a one-off
  hand edit does not hold. Use integrated security (`<SourceServerSSPI>` / `<DestinationServerSSPI>`
  beside `<Server>` / `<Catalog>`).

**The script:** [`../scripts/Test-DwJobSchema.ps1`](../scripts/Test-DwJobSchema.ps1) checks all of
the above over one file or a whole jobs folder, on the decoded text, and also fails a mapping uid
shared between two files. Read-only.

```powershell
pwsh -NoProfile -File scripts/Test-DwJobSchema.ps1 -Path "<wwwroot>/Files/Files/Integration/jobs"
```

Running a job is still a separate act of proof: MCP `run_integration_activity` **queues** a run, so
poll `get_integration_activity_status` and read `get_integration_activity_logs`
(`Files/System/Log/Data integration/<Activity>_lastrun.log`). **`Job succeeded` means the rows were
processed, not that the artefact you expected exists** — an export that wrote its file to the wrong
directory logs exactly the same success line.

## Bind an activity to a scheduled task

A scheduled task binds to one activity through
`Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn, Dynamicweb.DataIntegration`, whose
only parameter is `Activity`, taking the activity name (the file name). The row contract, the
register flush and the paged verification read are in
[`recipes-extend.md`](recipes-extend.md) §"Register a scheduled task by `SQL`", and the script that
enforces them is [`../scripts/Register-DwScheduledTask.ps1`](../scripts/Register-DwScheduledTask.ps1).
