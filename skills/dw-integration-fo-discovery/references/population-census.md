# Population census — which entities carry data, per legal entity, and how recently

## Contents

- [Goal](#goal)
- [Run it](#run-it)
- [What the script measures](#what-the-script-measures)
- [Pacing and throttling](#pacing-and-throttling)
- [Reading the census](#reading-the-census)
- [When `$count` is not enough](#when-count-is-not-enough)
- [Silent-failure traps](#silent-failure-traps)

## Goal

Turn the structural inventory into a *populated* model: rows per entity, split per legal entity, field fill rates on a recent sample, and last-modified recency. This is the evidence that separates "the schema has it" from "the business uses it", and it is the population signal in key centrality.

## Run it

```powershell
& <skill>\assets\scripts\Invoke-FoCensus.ps1 -Model <discovery-dir>\model.odata.json -OutFile <discovery-dir>\census.json
# narrower, faster passes:
& … -Categories Master,Document,Transaction -Exclude '^(Sys|Batch|DMF|Workflow)' -SampleSize 500
& … -Include '^(Sales|Cust|Released|Item|Invent|Warehouse|Price|Trade)' -SkipPerCompany
```

`census.json` (`entities[].{name, collection, category, origin, companyScoped, rows, byCompany{}, sampled, fields[].{name, fillRate}, lastModified, error}`) and `census.md` (populated entities ranked by rows, plus the "present but empty" list).

## What the script measures

| Measure | Call | Notes |
|---|---|---|
| Rows | `GET /data/<Collection>/$count?cross-company=true` | plain-text integer, no payload; every company the identity can see |
| Rows per company | `…/$count?cross-company=true&$filter=dataAreaId eq '<id>'` | only for company-scoped entities; companies from `Companies` (fallback `LegalEntities`) |
| Fill rate | `GET /data/<Collection>?cross-company=true&$top=<n>&$orderby=ModifiedDateTime desc` | per property: share of sampled rows that are non-empty, non-zero, non-1900 dates; ordered by recency when the entity has `ModifiedDateTime` |
| Recency | first row of the ordered sample | most standard F&O entities expose **no** `ModifiedDateTime`; the script orders by `ModifiedDateTime`, then `CreatedDateTime`, then the first `…Date`/`…DateTime` property named like Created/Modified/Order/Invoice/Transaction/Posting/Registration (`recencyField` records which); absent otherwise |

Sampling is limited to Master/Document/Transaction entities with ≤ `-SampleMaxRows` rows by default — large transaction entities are counted, not sampled, unless included explicitly.

## Pacing, throttling, and long runs

Every call is a GET; the script sleeps `-DelayMs` (150 ms default) between calls and, on HTTP 429, waits `Retry-After` (30 s when absent) and retries up to five times. Measured on a stock 31-company sandbox: ~1.5 s per entity with sampling and without per-company counts, so a Master/Document/Transaction pass over ~3,100 entities runs ~80 minutes; per-company counts add one call per company per populated company-scoped entity. That outlives a one-hour token and any single shell session, so:

- pass `-TenantId`/`-ClientId` with `$env:FO_CLIENT_SECRET` set — the script re-acquires the token after 50 minutes or on a 401;
- the script checkpoints `census.json` every `-CheckpointEvery` entities (25); re-run with `-Resume` to continue after an interruption (entities that errored are retried);
- run it detached (`Start-Process pwsh -ArgumentList …` or a background job) with output to a log, and restrict with `-Categories`/`-Include` for a first fast pass over the shortlist. Resource-based throttling reacts to server load, not just call rate: if 429s cluster, raise `-DelayMs` rather than retrying harder. Ask the ERP owner to give the discovery app a *low* throttling priority — discovery must never compete with the environment's own integrations.

## Reading the census

- **Populated per company** — the brief's §1 table. Two legal entities with different populated sets (one has projects, the other only sales) is the earliest sign the portal serves one of them.
- **Present but empty** — schema without rows: configured-but-unused modules or ISV tables installed for one feature. Listed separately in the brief; each becomes a "still in use?" question only when an extension or ISV owns it.
- **Fill rate cliffs** — a field at 96% on one entity and 0% on its quotation sibling shows *where in the process* a value gets assigned. Read cliffs before writing the lifecycle inference in §4 of the brief.
- **Recency** — entities whose newest row is older than a year are historical, not live; they matter for init sizing, not for delta design.
- **Errors** — 403 on a collection means the identity's roles exclude it; 404 means the collection name in the metadata is not routable on this build. Both go into `00-access.md`.

## When `$count` is not enough

- **Group-by evidence** ("orders per customer", "units per reseller") — OData has no aggregation. Use the ERP MCP `data_find_entities_sql` (10.0.48+) for `COUNT(*) … GROUP BY`, the ERP Analytics MCP `execute-dax-query` when BPA is enabled, or a DMF export to Excel of the two entities and aggregate locally.
- **Serial / unit population** — `ItemSerialNumbers` (root `InventSerial`) is the standard entity; on-hand entities are site/warehouse aggregates and carry no serial. An ISV that manages serialized units typically ships its own unit master — count it, and compare with `ItemSerialNumbers` to learn whether serials and units are the same thing in this environment.
- **Legacy AX** — SQL against the business database; see [legacy-ax.md](legacy-ax.md) for the equivalent queries and the `census.json` shape to write by hand.

## Silent-failure traps

- Omitting `cross-company=true` counts the identity's default company only and looks like a valid number.
- A `dataAreaId` filter on a global entity returns zero rows without an error — the script only applies it to company-scoped entities; do the same by hand.
- `$top` samples without `$orderby` are storage-ordered, i.e. old rows; recency and fill rates then describe the past. The script orders by `ModifiedDateTime` whenever the entity has it.
- Read-only BI entities (`*BiEntity`) and aggregate views count fine but are not integration targets; the brief lists them under their source module, not as candidates.
