# Process footprint — how the environment is used, from its configuration

## Contents

- [Goal](#goal)
- [The configuration entities to pull](#the-configuration-entities-to-pull)
- [Reading each signal](#reading-each-signal)
- [Existing integrations — the map of what already moves](#existing-integrations--the-map-of-what-already-moves)
- [Serialized and unit-level tracking](#serialized-and-unit-level-tracking)
- [What has no entity](#what-has-no-entity)
- [Output](#output)

## Goal

Structure says what *could* be used and the census says what *is* populated; the process footprint says how the organisation *operates* the system — which modules are live, what is automated, who works in it, and which integrations already exist. It is the part of the brief that lets the customer recognise their own process and correct it.

## The configuration entities to pull

All via OData GET with `cross-company=true` where the entity is company-scoped; `$top`/`$select` to keep payloads small. Collection names verified on a current build; a 404 on one is a version signal — record it and move on.

| Signal | Collection | Scope | Fields worth keeping |
|---|---|---|---|
| Legal entities | `LegalEntities`, `Companies` | global | `DataArea`, `Name`, country, currency |
| Number sequences | `SequenceV2Tables` (codes), `NumberSequencesV2References` (which identifier uses which sequence) | per company | code, format, `NextRec`, `Manual`, reference area/datatype |
| DMF projects | `DataManagementDefinitionGroups`, `DataManagementDefinitionGroupDetails` | project-level | name, entities per project, direction, source type |
| DMF execution history | `DataManagementExecutionJobDetails` | — | last runs per project, status, row counts |
| Batch jobs | `BatchJobs` | global | caption, status, recurrence, company, last run |
| Workflows | `Workflows`, `WorkflowWorkItems`, `ApprovalHistories` | mixed | type, active/enabled, work items in the last 12 months |
| Business events | `BusinessEventsCatalogs`, `BusinessEventsEndpoints`, `BusinessEventsConfigurations` | per LE | which events are active and where they go |
| Dual-write | `DualWriteProjectConfigurations` | global | mapped entities to Dataverse |
| Database log | `DatabaseLogs` | per company | which tables are audited — the customer's own list of sensitive data |
| Users and roles | `SystemUsers`, `SecurityUserRoleAssociations`, `SecurityUserRoleOrganizations`, `SecurityRoles`, `SecurityRoleDuties` | global / org-scoped | enabled users, role membership counts, external users, per-company role restrictions |
| Financial dimensions | `DimensionAttributes`, `DimensionSets`, `FinancialDimensionValues` | global | active dimensions — these are what the customer reports on |
| Tracking / serials | `TrackingDimensionGroups`, `ItemSerialNumbers` | per company | which groups activate serial/batch and how (physical vs sales-process) |

## Reading each signal

- **Number sequences** — every business identifier with a sequence reference is *assigned by the ERP*. A central identifier from key centrality with **no** sequence reference is issued elsewhere (a regulatory registry, a manufacturer plant system, manual entry) — a hand-off point the integration must respect, and a question.
- **DMF projects + execution history** — the customer's existing bulk integrations. Recently executed export projects show which entities already leave the system, to whom, and how often; import projects show which data arrives from other systems (a PIM, a reseller system, a pricing sheet). These are candidates to *replace* or *coexist with*, never to ignore.
- **Batch jobs** — the automation rhythm: nightly invoicing, price updates, MRP, and any ISV job. Recurring batch jobs referencing ISV classes name the processes that vendor runs.
- **Workflows** — configured but without recent work items means the approval moved outside the ERP (email, a portal) — ask where.
- **Business events / dual-write** — event-driven and Dataverse integrations already in place; if dual-write maps the customer and product entities, the Dataverse side may be the cheaper integration surface for those.
- **Users and roles** — role membership per company shows where the people are: many *Sales clerk*/*Customer service* users in one company and only *Accountant* in another says which company is operational. External domains among enabled users reveal partners already inside the ERP (resellers keyed in directly).
- **Financial dimensions** — active dimension attributes (e.g. `Channel`, `Brand`, `Region`) are the customer's reporting axes; when one of them matches a key-centrality candidate, the business already thinks in that key.

## Existing integrations — the map of what already moves

Compile one table for the brief: source → target, mechanism (DMF/recurring integration, business event, dual-write, ISV service, custom class), entities, schedule, last successful run, owner (if visible). Recurring integrations have no entity — their activity ids surface via the DMF definition groups they wrap and via `DataManagementExecutionJobDetails`. Custom integration classes (an X++ web service, a partner's model) appear in installed modules, batch jobs, and sometimes as OData actions on `PublicEntities.Actions[]`.

## Serialized and unit-level tracking

`TrackingDimensionGroups` tells you *how* serials behave: **Active in sales process** captures a serial at sale and clears physical inventory (traceability, no serialized on-hand); **Active with physical/financial inventory** is the configuration that supports unit-level stock. Which item groups use which tracking group, together with `ItemSerialNumbers` counts, answers whether the business runs on serials at all. Units with their own attributes (build year, configuration, registration, owner) are not on the serial dimension: they live in *Service objects* (`SMAServiceObjectTable`, BI entity only), *Asset management* objects, fixed assets, or an ISV unit master. Key centrality plus the ISV inventory says which.

## What has no entity

- Configuration keys / license codes — technical-reference reports only.
- Recurring-integration definitions — DMF groups + execution details only.
- The no-code custom-field catalog — UI form only.
- Installed models — the undocumented `GetInstalledModules` action or *About > Show installed models*.

List each of these in `00-access.md` as "obtained via …" or "not obtained".

## Output

`<discovery-dir>/process-footprint.md` with the sections: modules live, automation (batch/DMF/events), integrations map, users and roles per company, reporting axes (dimensions), tracking configuration, and the questions each section raised. Feed §5 of the brief from it verbatim.
