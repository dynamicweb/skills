# <Organisation> — ERP data-model discovery brief

Prepared for: <process owner>, <IT lead> · Prepared by: <role> · Status: draft for review

Observations are stated as seen in the environment; inferences are tagged `[to confirm]` and each has a
question in `clarification-questions.md`.

## 1. Environment facts

| Item | Value |
|---|---|
| Product / version | <D365 F&O 10.0.xx / AX 2012 release and CU / …> |
| Environment examined | <name, tier, URL host only> |
| Legal entities | <list> |
| Surfaces used | <ERP MCP / OData S2S / Metadata service / model export / SQL replica> |
| Identity used | <app registration or user role — no secrets> |
| Not accessible | <what was refused or not provisioned> |

Spine table volumes per legal entity (rows, last modified):

| Legal entity | Customers | Products (released) | Sales orders | Sales lines | <spine table> |
|---|---|---|---|---|---|
| <LE> | | | | | |

## 2. Origin map

| Origin | Entities | Fields on standard entities | Publisher / owner |
|---|---|---|---|
| Standard | | — | Microsoft |
| ISV `<prefix>` | | | <vendor> |
| Custom `<prefix>` | | | <in-house team / partner> |
| Unknown `<prefix>` | | | **unknown — see Q<n>** |

## 3. Populated model (per module)

| Module | Entity | Rows (LE) | Fill-rate highlights | Last modified |
|---|---|---|---|---|
| Sales | | | | |
| Products / PIM | | | | |
| Customers / parties | | | | |
| Inventory / warehouse | | | | |
| Pricing | | | | |
| Service / warranty | | | | |
| Projects / production | | | | |

Present but unused (schema, no rows or no recent activity): <list>

## 4. Process spine

Ranked keys (from `key-centrality.md`, top rows):

| # | Key | Spread | Relations | Keyness | Population | Reading |
|---|---|---|---|---|---|---|
| 1 | | | | | | |

Lifecycle implied by the spine `[to confirm]`: <e.g. built → shipped to reseller → sold to end customer → ownership change → serviced → warranty claim → recall>

## 5. Process footprint

- Modules live (config keys / licensed / populated): <list>
- Workflows configured and active in the last 12 months: <list>
- Batch jobs and recurring integrations (DMF projects, recurring data jobs, business events, dual-write): <list with schedule and consumer where known>
- Security: user count, roles with most members, external/partner users: <summary>
- Existing integrations touching the same data: <list> — what they move and in which direction

## 6. Extension inventory

| Entity | Field | Origin | Type | Fill rate | Notes |
|---|---|---|---|---|---|
| | | | | | |

## 7. Implications for the integration

| Topic | Finding | Consequence |
|---|---|---|
| Stage 1 extraction scope | <n> entities, <m> with `ModifiedDateTime` | delta via watermark on …; snapshot + reconciliation on … |
| Stage 2 entity candidates | product / unit / customer / reseller / order / … | natural keys: … |
| Ownership | per `dw-integration-erp` ownership split | ERP-owned: …; DW-owned: … |
| Volumes for init | largest tables and per-LE split | bulk seed strategy … |
| Throttling / reader scope | <F&O OData posture or AX reader footprint> | |

## 8. Open items

See `clarification-questions.md` (<n> questions, <k> owners).
