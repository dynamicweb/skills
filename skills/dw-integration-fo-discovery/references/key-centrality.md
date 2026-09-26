# Key centrality — finding the identifier that ties the business processes together

## Contents

- [What this step answers](#what-this-step-answers)
- [The signals](#the-signals)
- [Run it](#run-it)
- [Read the ranking](#read-the-ranking)
- [The serialized-unit spine pattern](#the-serialized-unit-spine-pattern)
- [Worked example — an illustrative footprint](#worked-example--an-illustrative-footprint)
- [What the spine means for the Dynamicweb integration](#what-the-spine-means-for-the-dynamicweb-integration)
- [Pitfalls](#pitfalls)

## What this step answers

Every ERP environment has a handful of identifiers that the business actually runs on. In a distributor it is
`CustAccount` + `ItemId` + `SalesId`; in a make-to-order manufacturer it is the production order; in a
project business it is `ProjId`; in a business that sells and services individual serialized units
(machinery, equipment, instruments) it is the **unit identifier** — the serial or asset number — because
warranty, service cases, ownership changes, recalls and the sales line all hang off it. That identifier is
the **process spine**. Naming it early lets the ERP owner explain their process in their own terms, and it
decides what the Dynamicweb side has to model as a first-class entity instead of a product attribute.

This step ranks candidate keys by evidence, so the spine is *found*, not guessed. The ranking is input to
the clarification questions in [synthesis-brief.md](synthesis-brief.md) — never a conclusion on its own.

## The signals

| Signal | What it measures | Source |
|---|---|---|
| **Spread** | Distinct entities carrying the same concept. Grouping precision, best first: **extended data type** (XPO/model exports), **property `LabelId`** (F&O Metadata service — same label = same concept; it exposes no EDTs), then a **normalized name** (Id/Number/Num/Code suffix stripped, aliases such as ItemId≡ItemNumber, CustAccount≡CustomerAccountNumber applied) | model JSON `entities[].fields` |
| **Relations** | Relation / navigation-property edges the field participates in | `entities[].relations`, OData `NavigationProperty` |
| **Key rate** | Share of carrying entities where it is part of a unique index, alternate key, or OData entity key — a *rate*, so a field that is a key on hundreds of DMF composite entities does not outrank a real business key | `entities[].indexes`, `entities[].keys` |
| **Mandatory rate** | Share of carrying entities where it is mandatory | field property |
| **Code usage** | Occurrences in X++ / integration source — what the existing integration footprint already pivots on | XPO class bodies (`codeUsage`) |
| **Population** | Fill rate in live data from the census (fraction of carrying entities where the field is >50% populated) | `census.json` from [population-census.md](population-census.md) |

Score = `3·ln(spread+1) + 2·ln(relations+1) + 2·keyness + 1·mandatory + 0.02·codeUsage + 2·population·spread`
(weights are a parameter). Surrogate foreign keys (`RefRecId`, `*RecId` EDTs), enum EDTs (`NoYes*`) and
audit/date columns are excluded by default — they carry relations but are never business keys. Pass
`-IncludeSurrogates` to see them.

## Run it

```powershell
$S = "<skill>\assets\scripts"
# Source 1 — AX 2009/2012 XPO or model export
& $S\ConvertFrom-Xpo.ps1 -Path <inputs>\*.xpo -OutFile <discovery-dir>\model.xpo.json `
    -PrefixMap @{ 'XYZ' = 'isv:<vendor>'; 'ABC' = 'custom'; 'INT' = 'integration-footprint' }
# Source 2 — F&O OData metadata (see structural-inventory.md)
& $S\Export-FoMetadata.ps1 -EnvironmentUrl https://<env>.operations.dynamics.com -OutDir <discovery-dir>
# Rank (any number of model files; census optional but strongly recommended)
& $S\Measure-KeyCentrality.ps1 -Model <discovery-dir>\model.*.json -Census <discovery-dir>\census.json `
    -OutFile <discovery-dir>\key-centrality.json -Top 30
```

`key-centrality.md` (sibling of the JSON) is the paste-ready table for the brief.

## Read the ranking

Work down the table and classify each row before drawing any conclusion:

1. **Standard spine** (`CustAccount`, `ItemId`, `SalesId`, `InventLocationId`, `VendAccount`, `ProjId`) — expected on every environment. Their *relative* position tells you which modules matter: `ProjId` above `SalesId` says project-driven business; `VendAccount` absent from the top says procurement is not in the integration footprint.
2. **ISV / in-house keys with high spread** — the interesting rows. An EDT with an ISV or in-house prefix that reaches 3+ entities across *different* modules (sales, service, warranty, inventory) is a spine candidate.
3. **In-house codes with high keyness but low spread** — classification/master lists (a region code, a defect code). They matter for mapping (they become DW field options or categories) but are not the spine.
4. **High code usage, low spread** — something the existing integration hammers on (checkpoints, batch ids). Integration plumbing, not business model.

A row is a **spine** when at least three of these agree: spread across ≥3 modules, unique index / alternate key on its home table, appears on the sales line or order header, appears in service/warranty/ownership entities, has its own number sequence or is externally issued (a serial stamped by a production system or a registry is not drawn from an ERP number sequence — the absence of a number sequence for a highly central key is itself a clue).

## The serialized-unit spine pattern

| Evidence | Reading |
|---|---|
| Home table is a **unit/device/asset master** with an ISV or in-house prefix, one row per physical unit, per-company off (`SaveDataPerCompany = No` / cross-company) | The business tracks individual units, not just SKUs. Serialized items alone (`InventSerial`) rarely produce this shape — a dedicated master does |
| Same EDT on sales lines, service cases, warranty transactions, ownership journals, recall lines | The unit's lifecycle *is* the process: built → sold → delivered → owned by the end customer → serviced → claimed → recalled |
| A `*ModelId` / `*MasterId` sibling with slightly lower spread | Model/spec master (the "type" of unit) — the PIM-shaped half; the unit id is the instance half |
| Reseller / owner fields co-occurring with the unit id | Multi-tier distribution: manufacturer → reseller → end customer. Ownership transitions are a process the portal will need to show |
| The unit id appears in views/queries built for the integration footprint | The previous integration already recognised it as the join key — confirm rather than rediscover |

When this shape appears, the DW model needs a **unit entity** (product instance / serialized asset) separate from the product, with its own natural key, and the customer-center story is "my units → warranty → service history", not "my orders".

## Worked example — an illustrative footprint

The prefixes, names and figures below are invented to show how a ranking is read; they describe no real
environment.

Input: one XPO holding a previous integration's footprint (a few dozen tables, views and classes) against an
AX 2012 environment with an equipment-service ISV installed. Prefix map: ISV prefix `XYZ` →
`isv:<vendor>`, in-house prefix `ABC` → `custom`, the previous integration's prefix `INT` →
`integration-footprint`.

Top of the ranking (surrogates excluded):

| Key (EDT) | Spread | Relations | Key rate | Code usage | Reading |
|---|---|---|---|---|---|
| in-house `ABCRegionCode` | 4 | 3 | 1.00 | 30 | in-house classification list — mapping input, not spine |
| `SalesIdBase` (`SalesId`) | 3 | 3 | 0.67 | 100 | standard spine; highest code usage — the footprint exports orders |
| `CustAccount` | 5 | 4 | 0.20 | 50 | standard spine |
| `ItemId` | 4 | 3 | 0.00 | 160 | standard spine |
| ISV `XYZUnitId` | 4 | 4 | 0.00 | 80 | **spine candidate**: on the service-case table, spec table, ownership journal and warranty transactions; home master not in the footprint |
| ISV `XYZCaseId` | 2 | 4 | 0.50 | 20 | service process keyed by the unit |
| ISV `XYZUnitModelId` | 3 | 3 | 0.00 | 55 | the model/spec half of the unit |

For contrast, the same scorer on a **stock F&O sandbox** (about 4,500 public entities, label grouping, no census) ranks worker → item → legal entity → party → site → product → warehouse → vendor → customer → project → purchase order → sales order: the platform's own spine, with nothing ISV-shaped in the top 25. A real environment's ranking is read against that baseline — the rows that are *not* on it are the business's own story.

Reading: the ISV's unit master is the home of the serialized-unit spine — its id reaches sales, service, warranty and ownership, and the previous integration already joined on it (high code usage without a home table in the export). The footprint is a partial model, so spread is capped by what the export contains; the conclusion is "confirm with the ERP owner", phrased as a question, not "the unit id is your key". See the question shapes in [synthesis-brief.md](synthesis-brief.md).

## What the spine means for the Dynamicweb integration

- **Stage 1 staging** (raw 1:1) must land the unit master and every unit-keyed transaction with the spine column intact and typed — it is the join key for stage 2.
- **Stage 2 entities**: a unit entity with the spine as natural key; product ↔ unit ↔ customer/reseller relations; warranty/service as unit-keyed child rows. Ownership follows [`dw-integration-erp/references/ownership-split.md`](../../dw-integration-erp/references/ownership-split.md): the ERP owns unit identity and ownership history; DW owns presentation and portal-side enrichment.
- **Delta sync** watermarks on unit-keyed transactions, not just orders — ownership and warranty changes are the events the portal user cares about.
- **Storefront/portal**: "my units" precedes "my orders" in the customer-center design.

## Pitfalls

- **A footprint XPO is not the model.** It contains what a previous integration touched. Use it to confirm keys the earlier team relied on; use a full model export, the model-store SQL tables or the OData metadata for true spread — see [legacy-ax.md](legacy-ax.md) and [structural-inventory.md](structural-inventory.md).
- **Name-grouped spread over-counts** on OData metadata (no EDTs): `Name`, `Description`, `Id` collide across unrelated entities. The noise list handles the obvious ones; read the `entities` column before trusting a name-grouped row.
- **Enum EDTs look central** (`NoYesId` on ten tables). Excluded by default; if an in-house enum ranks high with `-IncludeSurrogates`, it is a status/classification, not a key.
- **Census evidence beats structure.** A field on twelve tables that is empty on eleven is not a spine. Run the census before presenting the ranking to the ERP owner.
