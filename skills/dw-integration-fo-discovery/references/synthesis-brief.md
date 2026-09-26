# Synthesis — the data-model brief and the clarification questions

## Contents

- [Outputs and where they live](#outputs-and-where-they-live)
- [The data-model brief](#the-data-model-brief)
- [Clarification questions — steer, don't follow](#clarification-questions--steer-dont-follow)
- [Question shapes that work](#question-shapes-that-work)
- [Hand-off into the Dynamicweb integration design](#hand-off-into-the-dynamicweb-integration-design)
- [Done criteria](#done-criteria)

## Outputs and where they live

Everything discovery produces goes under the discovery output folder `<discovery-dir>` — never inside the
source material the ERP owner supplied (read-only input) and never inside the plugin. Raw pulls are inputs; the two documents
at the bottom are the deliverables.

| File | Produced by | Role |
|---|---|---|
| `00-access.md` | access phase | which surfaces were reachable, with which identity, and what was refused |
| `metadata/…` | `Export-FoMetadata.ps1` | raw Metadata-service JSON + `$metadata` CSDL (large; git-ignore) |
| `model.odata.json`, `model.xpo.json` | exporter / converter | normalized structural model(s) |
| `entities.csv` | structural inventory | one row per entity: name, collection, category, origin, company-scoped, field count |
| `census.json`, `census.md` | `Invoke-FoCensus.ps1` | rows per entity per company, fill rates, recency |
| `key-centrality.json`, `key-centrality.md` | `Measure-KeyCentrality.ps1` | ranked keys |
| `process-footprint.md` | process phase | modules, workflows, batch/DMF jobs, integrations, roles |
| **`data-model-brief.md`** | you | the deliverable — from `assets/templates/data-model-brief.template.md` |
| **`clarification-questions.md`** | you | the deliverable — from `assets/templates/clarification-questions.template.md` |

## The data-model brief

Audience: the customer's process owner and IT lead, plus the Dynamicweb integration team. It must be
readable without opening any of the raw files. Sections, in order (the template carries them):

1. **Environment facts** — product and version, legal entities with row counts of the four spine tables, tenants/tiers, surfaces used for discovery, what was not accessible.
2. **Origin map** — standard / ISV / custom split of entities and fields, with every ISV named (from model manifests, prefixes, or the customer). Unknown prefixes are listed as unknown, not guessed.
3. **Populated model** — the entities that carry live data per legal entity (census), grouped by module. Entities with schema but no rows are listed separately as "present, unused".
4. **Process spine** — the ranked keys with the reading from [key-centrality.md](key-centrality.md) and the lifecycle the spine implies (sold → custody → service → warranty …), stated as observation + inference, each inference tagged `[to confirm]`.
5. **Process footprint** — which modules are live, active workflows, scheduled/batch integrations, DMF projects and recurring integrations, dual-write, business events; existing integrations and what they already move.
6. **Extension inventory** — custom fields on standard entities and custom entities, with fill rates, so the integration team knows which extensions actually carry data.
7. **Implications for the integration** — entity candidates for stage 2, natural keys, ownership per [`dw-integration-erp/references/ownership-split.md`](../../dw-integration-erp/references/ownership-split.md), delta watermark availability per spine table, throttling posture (F&O) or reader-service scope (AX).
8. **Open items** — pointer to `clarification-questions.md`.

Write observations as observations ("`<field>` is present on 4 of 23 exported tables and populated on 96% of sales lines in company X") and keep inferences visibly separate. The customer corrects observations rarely and inferences often — the separation is what makes the review productive.

## Clarification questions — steer, don't follow

The questions are the mechanism by which the customer's process knowledge shapes the integration design.
Rules:

- **Premise-free and standalone.** A question must be answerable by someone who has not read the brief and carries none of its conclusions. "We assume the unit number is your key — correct?" invites a yes; "Which identifier do your resellers use when they call about a unit?" produces knowledge.
- **One unknown per question.** Split fact questions (what is) from decision questions (what should be).
- **Show the evidence, ask for the meaning.** "The field `X` is filled on 96% of sales lines but empty on all quotation lines — at which point in your process does it get assigned, and by whom?"
- **Route each question to its owner** — process owner, ERP admin, ISV partner, IT/security. Note the owner in the list; the customer will redirect anyway, so make it easy.
- **Retire answered questions.** When an answer arrives, fold it into the brief and delete the question; do not re-ask it in a later round.
- **Ask about absence.** Populated schema is easy to see; what the customer does *outside* the ERP (Excel pricing, a separate warranty portal, a reseller system) is invisible in the census and decides the integration scope.

## Question shapes that work

| Discovery finding | Question (owner) |
|---|---|
| A central unit identifier with an ISV home table | Walk through the life of one unit from build to end-customer ownership: which systems and which identifiers does it pass through, and where does each identifier get assigned? (process owner) |
| Custom fields with high fill rate on a standard entity | What does field `<label>` on `<entity>` record, who fills it, and does anything downstream depend on it? (ERP admin / key user) |
| Custom fields with ~0% fill rate | Is `<field>` still in use anywhere, or can the integration ignore it? (ERP admin) |
| Two legal entities with very different populated models | What is the business role of each legal entity, and which of them will the portal/storefront serve? (process owner) |
| A DMF project or batch export to a file share | What consumes the `<project>` export today, on what schedule, and what would happen if it stopped? (IT) |
| Number sequence present for an identifier the census shows as externally shaped (e.g. fixed-format regulatory number) | Where does `<identifier>` originate — assigned in the ERP, imported, or entered by hand — and who validates its format? (process owner) |
| Prices only in trade agreements with manual overrides in orders | How are the prices a reseller sees decided, and where do exceptions get approved? (sales ops) |
| Workflow configured but no active instances in the last 12 months | Is `<workflow>` still part of the process, or has it been replaced by something outside the ERP? (process owner) |
| Serialized tracking dimension active on some item groups only | Which product families are tracked per unit, and what should the portal show for the ones that are not? (product/master-data owner) |
| Multiple ISV prefixes | Which vendor supports each of `<prefix list>`, and are any of them scheduled for replacement or upgrade? (IT) |

## Hand-off into the Dynamicweb integration design

The brief feeds the staged integration design (stage 1 raw staging, stage 2 reshaping; see SKILL.md) directly:

- **Stage 1 (raw 1:1 staging)** — the populated-model list (§3) plus spine tables (§4) *is* the extraction scope; per table: natural key, `ModifiedDateTime`/`RecVersion` availability, company scope, row volume (from the census) for init sizing.
- **Stage 2 (Dynamicweb entities)** — the spine and its lifecycle decide which DW entities exist (product vs unit vs customer/reseller), and the ownership split decides direction per field.
- **Mapping work** — entities.csv + extension inventory seed the mapping repository; approved/unmapped counts start from here.
- **F&O only** — the throttling posture and whether OData-only carries the entity set or a SQL-staged / plugin path is needed; the Integration Framework side of that choice is in `dw-integration-framework`.

## Done criteria

Discovery is complete when: the brief has all eight sections with nothing marked "TBD"; every inference is tagged `[to confirm]` and has a matching question; the census covers every entity named in the brief; every unknown prefix has a question; the ERP owner has received the brief and the question list in the same hand-over; `00-access.md` records what could not be examined so nobody mistakes "not seen" for "not there".
