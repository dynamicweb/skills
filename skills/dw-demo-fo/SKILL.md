---
name: dw-demo-fo
type: flow
group: demo
mcp: optional
dynamo: false
compatibility: Requires PowerShell 7.x on Windows (the delegated token cache uses DPAPI)
description: 'Give a DW10 demo its own legal entity in a shared live D365 F&O sandbox, seeded from a golden company. Triggers: per-demo F&O company, New-DemoCompany, copy into legal entity, demo reads the wrong dataAreaId. No live tenant -> dw-demo-erp. Use AFTER dw-demo-base.'
---

# F&O demo company

## Without MCP

**This skill's steps are out-of-product by construction.** They are Dynamics 365 Finance and Operations
(F&O) OData calls, Data management runs, PowerShell and the F&O client, not Dynamicweb MCP tool calls, so a
Dynamicweb MCP connection is a convenience here, not a precondition. On the DW side (phase 4, the job pin),
prefer an MCP tool wherever it covers a step. Without one, the whole ladder is still open to this skill: drop
one rung to the Management API, then the serializer, with direct SQL last and local installs only. Name the
rung each step uses.

The ladder those rungs belong to is foundational:
[`dw-data-access`](../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance".

Wire a Dynamicweb 10 demo to a **live F&O tenant**, one legal entity per customer demo, so the audience sees
its own process shape (numbering, dimensions, the spine identifier, catalog structure) instead of stock demo
data. One shared sandbox carries many customer demos side by side. **Use AFTER** `dw-demo-base` (host and
surfaces), and after the engagement's F&O discovery when a real customer environment is in scope: its
data-model brief is the input the company profile is written from.

The pitch this enables: *"configured like yours"*, never *"these are your customisations"*. What can and
cannot be tailored per company is a hard boundary, stated in
[references/company-profile.md](references/company-profile.md), and it is said out loud in the demo.

This SKILL.md is a nav layer. Each phase links to the reference that owns the recipe and its gotchas.

## How to run me

Phases in order; each reference states its done-criteria. Per-demo outputs (the company profile, the seed
scripts, the run log) live in the engagement folder, never inside `customer-context/` (read-only) and never
inside this skill. Under an orchestrator the orchestrator owns phase order
([`../dw-demo-base/references/orchestrator.md`](../dw-demo-base/references/orchestrator.md)); standalone,
this order applies.

## Standing choices

These are decided; follow them unless the environment owner rules otherwise.

- **Seed from a golden company, not a fresh copy per demo.** One golden company per country/region is built
  once with *Copy into legal entity* from the stock donor and repaired until customers, vendors and released
  products import cleanly. Its configuration is exported as a Data management package, and every new demo
  company is seeded by importing that package. A fresh copy per demo costs hours and repeats the same gap
  repair every time ([references/demo-company.md](references/demo-company.md) §2).
- **OData-only.** The Dynamicweb F&O plugin (a deployable package) is parked; every DW job talks to F&O data
  entities through the OData provider ([references/connection-modes.md](references/connection-modes.md)).
- **Retire, do not delete.** A demo company that is no longer needed is marked dormant in the shared list and
  its DW site is unbound from it (the jobs stop pointing at its `dataAreaId`). The legal entity stays
  ([references/demo-company.md](references/demo-company.md) §6).

## Canonical flow

| # | Phase | Question it answers | Reference |
|---|---|---|---|
| 0 | **Access** | Which identity do the scripts use, and does the tenant allow it? | [references/connection-modes.md](references/connection-modes.md) |
| 1 | **Profile** | What does this customer's company look like, and what of that is even per-company? | [references/company-profile.md](references/company-profile.md) |
| 2 | **Company** | Create the legal entity and seed it from the golden company | [references/demo-company.md](references/demo-company.md) §1-2 |
| 3 | **Shape** | Apply the profile: numbering, dimensions, sites, groups, catalog, spine identifier | [references/demo-company.md](references/demo-company.md) §3 |
| 4 | **Wiring** | Pin every DW Integration Framework job to this company and nothing else; build the jobs with `dw-integration-fo` | [references/dw-wiring.md](references/dw-wiring.md) |
| 5 | **Verify / retire** | Round-trip check; a re-runnable seed; dormant, not deleted, at the end | [references/demo-company.md](references/demo-company.md) §5-6 |
| - | **Sandbox discipline** | Sharing one tenant across demos without breaking anyone else's | [references/shared-sandbox.md](references/shared-sandbox.md) |

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [Fo.Api.psm1](scripts/Fo.Api.psm1) | Module | Connection discovery, self-renewing token (S2S secret from `$env:FO_CLIENT_SECRET`, or the delegated cache), OData call with 429 retry, company-scoped counts and rows, the GetExecutionErrors parser |
| [Connect-FoDeviceCode.ps1](scripts/Connect-FoDeviceCode.ps1) | Writes the token cache | Delegated device-code sign-in; stores the refresh token with DPAPI (current user) so the other scripts renew their own tokens |
| [New-DemoCompany.ps1](scripts/New-DemoCompany.ps1) | Writes one row | Idempotent: GET then POST `LegalEntities`; names the UI fallback when the tenant refuses the create |
| [Watch-CopyProgress.ps1](scripts/Watch-CopyProgress.ps1) | Read-only | Polls a copy or package execution per entity; on completion prints the row-level errors grouped by message |
| [Repair-CopyGaps.ps1](scripts/Repair-CopyGaps.ps1) | Writes (dry run unless `-Apply`) | Copies the bank groups, bank accounts, transaction types, company-scoped dimension values and payment methods a copy leaves out, from donor to target, GET before every POST |
| [Export-GoldenPackage.ps1](scripts/Export-GoldenPackage.ps1) | Writes one export project; reads the golden company | Builds the export project over OData from an entity-list JSON (company-scoped entities only), runs `ExportToPackage`, downloads the zip outside the environment with a `.sha256` |
| [Import-GoldenPackage.ps1](scripts/Import-GoldenPackage.ps1) | Writes into the target company only (dry run with `-WhatIf`) | Verifies the `.sha256`, builds the import project, re-points golden-company values inside the package to the target, uploads, runs `ImportFromPackage`, follows it and groups the row errors; refuses any target outside `-AllowedTarget` |
| [Test-DemoCompany.ps1](scripts/Test-DemoCompany.ps1) | Read-only | Company exists; released products, customers, orders, bank accounts, payment methods and number sequences counted **in that company** |

Run them (identity from the `FO_*` environment variables, see the module header):

```powershell
pwsh -NoProfile -File scripts/Connect-FoDeviceCode.ps1 -TenantId <tenant-id> -ClientId <client-id> -EnvironmentUrl https://<env>.operations.dynamics.com -CachePath <file outside any repo>
pwsh -NoProfile -File scripts/New-DemoCompany.ps1 -Code ABC -Name '<Legal name>' -CountryRegionId USA -LanguageId en-us -WhatIf
pwsh -NoProfile -File scripts/Watch-CopyProgress.ps1 -JobId '<execution JobId>'
pwsh -NoProfile -File scripts/Export-GoldenPackage.ps1 -Golden GOLD -DefinitionGroup ABC-GOLDEN-EXP -EntityList <entity list json> -OutDir <folder outside the environment>
pwsh -NoProfile -File scripts/Import-GoldenPackage.ps1 -Package <zip> -Target ABC -AllowedTarget ABC -Golden GOLD -DefinitionGroup ABC-GOLDEN-IMP -EntityList <entity list json> -WhatIf
pwsh -NoProfile -File scripts/Repair-CopyGaps.ps1 -Target ABC -Donor USMF -BankIdPrefix 'USMF '
pwsh -NoProfile -File scripts/Test-DemoCompany.ps1 -Code ABC
```

Secrets come from the environment (`$env:FO_CLIENT_SECRET`) or a vault, never from a file or a parameter.

## Where to find things

| If you need to... | Read |
|---|---|
| Choose the identity for the scripts; why OData-only; the parked plugin and its Dataverse guest-access wall | references/connection-modes.md |
| Turn a discovery brief into a company profile; know what is per-company vs tenant-wide; phrase the demo claim honestly | references/company-profile.md |
| Create the legal entity, build the golden company, seed from its package, repair the measured copy gaps, verify, retire | references/demo-company.md |
| Point DW jobs at exactly one `dataAreaId`; connect a hosted DW install to F&O | references/dw-wiring.md |
| Share one sandbox across several customer demos without collisions | references/shared-sandbox.md |
| Build the jobs themselves: endpoints with S2S auth, the entity map, staging and stage-2 views, the order export, status and invoices back, the verification ladder | [`dw-integration-fo`](../dw-integration-fo/SKILL.md) (after [`dw-integration-fo-discovery`](../dw-integration-fo-discovery/SKILL.md)); provider mechanics in [`dw-integration-framework`](../dw-integration-framework/SKILL.md), ownership split in [`dw-integration-erp`](../dw-integration-erp/SKILL.md) |

## Always-on rules

- **The ERP is a source AND a target in the Integration Framework, never a channel or a feed.** A live F&O
  tenant changes nothing about this; the rule and its anti-patterns are owned by
  [`../dw-demo-erp/SKILL.md`](../dw-demo-erp/SKILL.md) "Always-on rule".
- **One demo, one legal entity, and every job says so.** In a shared sandbox an unfiltered query silently
  reads the *integration identity's default company* (usually the donor) and the demo shows someone else's
  data while looking healthy. Pin the `dataAreaId` on every job ([references/dw-wiring.md](references/dw-wiring.md)).
- **Configured like yours, not your customisations.** Per-company configuration is tailorable; schema, X++
  models and custom fields are tenant-wide and are not. Say which you are showing.
- **The profile comes from evidence, not from the sales story.** Every profile line traces to a discovery
  observation or is marked as an assumption in the engagement folder.
- **Read-only against anything you did not create.** The donor, the golden company and neighbouring demo
  companies are reference data; the demo writes only inside its own `dataAreaId`.
- **No secrets in files.** Client secrets live in the environment or a vault; the engagement folder holds
  hostnames, app names and company codes only.
- **The seed is re-runnable or it does not exist.** A sandbox refresh wipes demo companies without warning; a
  company that cannot be rebuilt from the golden package and the engagement folder dies quietly.

## Sister skills

- **`dw-demo-base`**: foundation (Use FIRST): host, surfaces, customisations ledger, customer-context contract.
- **`dw-demo-erp`**: the DB-staged mock. Use INSTEAD of this skill when no live ERP tenant is in scope, and
  read its ERP-to-PIM data-shape reference either way.
- **`dw-demo-hosted`**: the hosted (online-mode) install this skill's wiring phase may target.
- **`dw-integration-fo`**: the foundational F&O integration build (endpoints, staging, order export,
  verification) this skill's wiring phase uses; its runner refuses an order export into any company but the demo's.
- **`dw-integration-bc`**: Business Central, a structurally different mechanism. Do not reuse these recipes.
- **`dw-demo-pim`** / **`dw-demo-swift`**: the DW side the ERP data lands in.

## Top-level pitfalls

- **Creating the legal entity is the easy half.** An empty company cannot release a product or create a
  customer until its ledger, number sequences, bank accounts, payment methods, dimension groups and sites
  exist. Budget the seed, not the create.
- **A copy without Cash and bank management breaks customers two steps later.** No bank accounts, so the
  payment methods fail, so most customers fail. `Test-DemoCompany.ps1` shows it; `Repair-CopyGaps.ps1` fixes it.
- **Copy into legal entity excludes document, transaction and composite entities** and does not copy
  workflows. It moves configuration, never business data; seed transactions separately.
- **Products, product attributes, category hierarchies, tracking dimension groups, the chart of accounts and
  fiscal calendars are tenant-wide.** Two demos in one sandbox share them; prefix what the demo creates.
- **The ledger and the number sequences live in shared tables.** A package that carries them exports every
  company's rows and its import writes into other companies; write them for the new company over OData first
  ([references/demo-company.md](references/demo-company.md) §2a), then import the package.
- **A sandbox refresh, an environment reset or a database copy from production wipes every demo company.**
  Keep the golden package outside the environment and the seed re-runnable.
