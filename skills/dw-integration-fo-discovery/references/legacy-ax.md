# Legacy AX (2009 / 2012) — the same discovery without OData

## Contents

- [When you are here](#when-you-are-here)
- [Pin the version first](#pin-the-version-first)
- [Inputs, best to worst](#inputs-best-to-worst)
- [Phase mapping](#phase-mapping)
- [Reading an integration footprint XPO](#reading-an-integration-footprint-xpo)
- [Row counts and fill rates without OData](#row-counts-and-fill-rates-without-odata)
- [Hand-off to the integration design](#hand-off-to-the-integration-design)

## When you are here

The ERP owner says "F&O" but the environment is on-premises AX 2009 or AX 2012 (a common mislabel — ask for the
exact version; see below). There is no OData `/data/` service, no Metadata service, no ERP MCP. AIF
services and direct SQL are the only machine-readable surfaces, and both usually require the owner's
AX developer or DBA. Discovery still runs the same phases; only the inputs change.

## Pin the version first

Ask for `About Microsoft Dynamics AX` (Help menu) or the kernel/application version from
`SysInfo`/`SysAboutForm`. Alternatively the `SYSTEMSEQUENCES`/`MODELELEMENT` presence in the database:

| Marker | Version |
|---|---|
| Separate `<db>_model` database with `ModelElement`, `ModelElementData`, `Model` tables | AX 2012 (release 2 or later if a `Partition` column exists on business tables) |
| Single database, `UtilElements` / `UtilIdElements` tables carry the AOT | AX 2009 (and 4.0) |
| Layers `USR`/`CUS`/`VAR`/`ISV` with `USP`/`CUP`/`VAP`/`ISP` patch layers | both — the layer of each object is the origin classification |

The AX version fixes the extraction toolset and the integration architecture (an AX 2012 AIF service or
custom endpoint fronted by a gateway that feeds stage 1 of the staged integration, see SKILL.md).

## Inputs, best to worst

| Input | How to obtain | What it yields |
|---|---|---|
| **Full model export** (AX 2012) | `axutil export /model:<Model> /file:<name>.axmodel` per model, or `axutil exportstore`; then an XPO of the models via the AOT (`Export` on a project containing them) | The whole in-house/ISV layer: every custom table, field, EDT, enum, relation, index. Best structural input — feed the XPO to `ConvertFrom-Xpo.ps1` |
| **Model-store SQL** (AX 2012) | Read-only access to `<db>_model`: `ModelElement` (ElementType 44 = table, 42 = field, 70 = index, 61 = EDT, 40 = enum), `ModelElementData` (layer/model per element), `Model`/`ModelManifest` (installed models and publishers) | Same as above plus **layer and publisher** per element — the authoritative origin classification. `ModelManifest.Publisher` names every ISV |
| **AOT export by layer** (AX 2009) | Log in with the layer (`-aol=USR`, `-aol=VAR`…), select all in the AOT filtered by layer, export an XPO | Custom objects per layer; AX 2009 XPOs use the same `***Element:` sections |
| **Integration footprint XPO** | Whatever the previous integration partner deployed (classes, views, queries, a few tables) | What the previous integration joined on and exported — confirms keys and exposes the earlier team's assumptions. Not the model |
| **Database replica / read-only login** | DBA-provided; AX 2012 business DB (`<db>`) | Row counts, fill rates, activity recency — the census phase. Table names = AOT table names; fields = AOT field names; company column `DATAAREAID`, from AX 2012 release 2 also `PARTITION` |
| **Table-browser screenshots / Excel exports** | Anyone with AX client access | Last resort for sampling values; fine for confirming a specific field's meaning |

## Phase mapping

| Phase (SKILL.md order) | F&O surface | AX equivalent |
|---|---|---|
| Access | ERP MCP / OData S2S | AOS client login per layer; DB read-only login; AIF endpoints list (`AIF > Services`) |
| Structural inventory | Metadata service + `$metadata` | Model export → `ConvertFrom-Xpo.ps1`; or SQL over `ModelElement` joined to `ModelElementData` for layer |
| Population census | OData `$count` / sampling | SQL: `sys.dm_db_partition_stats` for row counts; `COUNT(*) GROUP BY DATAAREAID`; `SUM(CASE WHEN col <> '' …)` for fill rates; `MAX(MODIFIEDDATETIME)` for recency |
| Key centrality | `Measure-KeyCentrality.ps1` on `model.odata.json` | `Measure-KeyCentrality.ps1` on `model.xpo.json` — EDTs are available here, so grouping is precise |
| Process footprint | workflow/batch/DMF/security entities | SQL: `WORKFLOWTABLE`, `BATCHJOB`, `AIFPORT`/`AIFOUTBOUNDPORT`, `SECURITYUSERROLE`, `NUMBERSEQUENCETABLE`/`NUMBERSEQUENCEREFERENCE`, `SYSCONFIG` (config keys) |
| Synthesis | same | same |

## Reading an integration footprint XPO

1. Run the converter with a `-PrefixMap` that names the ISV prefix(es), the in-house prefix and the previous integration's prefix. Every `Origin`/prefix you cannot name goes into the questions list — an unknown prefix is either a second ISV or a forgotten customization.
2. **Views and queries** (`views[].tables`, `queries[].tables`) list the standard tables the footprint joins. That list is the earlier team's answer to "which standard entities matter" — cheap confirmation.
3. **Classes** carry the export logic. `codeUsage` counts which table/field identifiers the code pivots on; identifiers with high usage but no table in the export are tables the code reads from the standard layer or the ISV layer (an ISV unit-master table read dozens of times but not exported is a typical case).
4. **Tables with zero fields** (endpoint-filter or settings tables) are parameter/plumbing tables — ignore for the model, note for the migration.
5. Cross-company tables (`SaveDataPerCompany = No`) in the ISV layer are a strong signal of a unit/asset master shared across legal entities — see the spine pattern in [key-centrality.md](key-centrality.md).

## Row counts and fill rates without OData

```sql
-- AX 2012 business DB, read-only login. Row counts per table (fast, from statistics):
SELECT t.name AS TableName, SUM(p.row_count) AS Rows
FROM sys.dm_db_partition_stats p JOIN sys.tables t ON t.object_id = p.object_id
WHERE p.index_id IN (0,1) GROUP BY t.name ORDER BY Rows DESC;

-- Per company for one table:
SELECT DATAAREAID, COUNT(*) FROM SALESTABLE GROUP BY DATAAREAID;

-- Fill rate + recency for candidate spine fields (one row per table/field of interest):
SELECT 'SALESLINE' AS T, 'XYZUNITID' AS F,   -- XYZUNITID: the candidate field
       SUM(CASE WHEN XYZUNITID <> '' THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(*),0) AS FillRate,
       MAX(MODIFIEDDATETIME) AS LastModified
FROM SALESLINE;
```

Write the results into the same `census.json` shape `Invoke-FoCensus.ps1` produces (`entities[].{name, rows, byCompany, fields[].{name, fillRate}, lastModified}`) so the centrality script can consume it unchanged.

## Hand-off to the integration design

The rule for legacy AX: **transform as little as possible in AX — basic filters only**. Discovery output therefore names *which tables and which columns* the thin reader must expose 1:1 into stage 1 staging, keyed on `RECID` with `MODIFIEDDATETIME` (or `RECVERSION`) as the delta watermark; every reshaping decision moves to stage 2. Confirm `ModifiedDateTime` is enabled on each spine table (`ModifiedDateTime = Yes` in the XPO table properties) — tables without it cannot do watermark deltas and need snapshot + key reconciliation.
