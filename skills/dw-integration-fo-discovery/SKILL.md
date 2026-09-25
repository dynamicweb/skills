---
name: dw-integration-fo-discovery
type: flow
group: integration
mcp: none
dynamo: false
description: 'Discover the data model a Dynamics 365 Finance & Operations (or AX 2009/2012) environment actually runs on, from outside, before DW10 integration mapping. Triggers: F&O entity inventory, ISV/custom origin, population census, central key, AX XPO analysis. ERP ownership -> dw-integration-erp.'
---

# F&O data-model discovery

Outside-in analysis of a Dynamics 365 Finance & Operations environment to find the data model the business
actually runs on, before any integration mapping starts. The output is a brief the ERP owner reviews and a
question list that lets their process knowledge shape the Dynamicweb integration instead of validating
assumptions made for them.

This SKILL.md is a nav layer. Each phase links to a `references/<topic>.md` that owns the recipe, the
scripts to run, and what to write down. Scripts live in `assets/scripts/`, output templates in
`assets/templates/`.

## How to run me

Work the phases in the order below; each phase's reference states its done-criteria. Outputs accumulate in
one discovery output folder, written `<discovery-dir>` in the references, kept apart from the source
material the ERP owner supplied (treat that as read-only input) and never inside this skill. The skill
holds domain knowledge, not sequencing: under an orchestrator the orchestrator owns the phase order;
standalone, this documented order applies.

## Canonical flow

| # | Phase | Question it answers | Reference |
|---|---|---|---|
| 0 | **Access** | Which surfaces can be read, with which identity, and what is refused? | [references/access-surfaces.md](references/access-surfaces.md) |
| 1 | **Structural inventory** | Which entities exist, who put them there (Microsoft / ISV / in-house), keys, EDTs, company scope? | [references/structural-inventory.md](references/structural-inventory.md) |
| 2 | **Population census** | Which of them carry data, per legal entity, how recently, which fields are filled? | [references/population-census.md](references/population-census.md) |
| 3 | **Key centrality** | Which identifier ties the processes together — the spine? | [references/key-centrality.md](references/key-centrality.md) |
| 4 | **Process footprint** | Which modules, automations, integrations and roles are live? | [references/process-footprint.md](references/process-footprint.md) |
| 5 | **Synthesis** | The brief and the questions; hand-off into the staged integration design | [references/synthesis-brief.md](references/synthesis-brief.md) |
| — | **Legacy AX fork** | Same phases when the environment is AX 2009/2012 (XPO / model store / SQL replica instead of OData) | [references/legacy-ax.md](references/legacy-ax.md) |

Phases 1–4 can run on partial access — an XPO alone yields a structural inventory and centrality ranking; a
DMF Excel export alone yields fill rates. Record every gap in `00-access.md` so "not seen" is never read as
"not there".

The hand-off assumes a **staged integration**: stage 1 lands the ERP tables raw and 1:1 in staging, keyed
and watermarked as the source has them; stage 2 reshapes staging into the Dynamicweb entities. Discovery
scopes stage 1 (which tables, which columns, which delta key) and feeds the entity decisions of stage 2.

## Scripts (assets/scripts)

| Script | Phase | What it does |
|---|---|---|
| `Get-FoToken.ps1` | 0 | client-credentials token for `/data`, `/Metadata`; sets `$env:FO_TOKEN` |
| `Export-FoMetadata.ps1` | 1 | installed modules + `/Metadata/DataEntities` + `/Metadata/PublicEntities` (+ enums, `$metadata`) → `model.odata.json`, `entities.csv` |
| `ConvertFrom-Xpo.ps1` | 1 (AX) | XPO → `model.xpo.json` (tables, fields with EDT, indexes, relations, views/queries, code-usage census) |
| `Invoke-FoCensus.ps1` | 2 | `$count` per entity and per company, `$top` samples → fill rates, recency → `census.json` |
| `Measure-KeyCentrality.ps1` | 3 | ranks candidate keys across one or more models (+ census) → `key-centrality.json/.md` |
| `New-ModelDiagram.ps1` | 5 | draws the populated model around the ranked keys for the brief |

All scripts are read-only against the ERP, pace their calls, and honour `Retry-After` on 429. Secrets are
taken from the session only ([access-surfaces.md](references/access-surfaces.md) "Secrets discipline").

## Where to find things

| If you need to… | Read |
|---|---|
| Decide between OData S2S, the Metadata service, the ERP MCP, BPA analytics MCP, or inside-out exports; register the ERP MCP in Claude Code; what the MCP cannot see | references/access-surfaces.md |
| Classify entities and fields as standard / ISV / in-house; detect extension fields and no-code custom fields; diff against a clean baseline | references/structural-inventory.md |
| Count rows per entity and legal entity safely under throttling; sample fill rates and recency; get group-by evidence when OData cannot aggregate | references/population-census.md |
| Find the spine identifier (order-, project- or serialized-unit-shaped), read the ranking, and know what it implies for the DW model | references/key-centrality.md |
| Read number sequences, DMF projects, batch jobs, workflows, business events, dual-write, roles and dimensions as process evidence; tracking-dimension semantics for serials | references/process-footprint.md |
| Write the brief, phrase premise-free questions, route them to owners, hand off into the stage 1 / stage 2 design | references/synthesis-brief.md |
| Run the same discovery on AX 2009/2012 (XPO, model store SQL, replica queries) | references/legacy-ax.md |

## Always-on rules

- **Observation before inference.** Every inference in the brief is tagged `[to confirm]` and has a matching question. The ERP owner corrects inferences; they rarely correct observations.
- **Questions steer, they don't follow.** A question must be answerable without reading the brief and must not carry the brief's conclusion as a premise.
- **Census beats structure.** No entity or field enters the brief on schema evidence alone.
- **Unknown stays unknown.** Unclassified prefixes and label files are listed as unknown with a question — never guessed into "in-house".
- **Read-only, paced, low-priority.** Discovery never competes with the environment's own integrations for throttling budget.
- **No secrets in files.** Tokens and client secrets live in the session; the discovery output folder holds hostnames and app names only.

## Related skills

- `dw-integration-erp` — the ERP ↔ PIM ownership split the brief's §7 applies.
- `dw-integration-framework` — Integration Framework vocabulary for the hand-off (activities, providers, mapping) and for building the jobs this skill scopes.
- `dw-integration-fo` — the build this discovery scopes: endpoints, stage 1 staging, stage 2 views, the order export and the verification ladder.

## Top-level pitfalls

- The ERP MCP is **security-trimmed and blocks admin forms** — never use it as the census layer; count through OData.
- `$count` without `cross-company=true` counts one company and looks correct.
- Neither `/Metadata/PublicEntities` nor `/data/$metadata` exposes extended data types (`TypeName` is `Edm.*` or an enum). Group concepts by property `LabelId` on F&O models; EDT grouping exists only for XPO/model exports.
- `/Metadata/PublicEntities` is authorized like the entity reads: when the app registration is not mapped to an F&O user, `/data/$metadata` still answers 200 while the structural-inventory pull fails. Finish the *Microsoft Entra ID applications* mapping before phase 1.
- A footprint XPO shows what a previous integration touched, not the model; treat its spread numbers as a floor.
- `GetInstalledModules` is undocumented and may be role-gated; have the *Show installed models* screenshot route ready before the review meeting.
