---
name: dw-integration-bc-discovery
type: flow
group: integration
mcp: none
dynamo: false
compatibility: Requires PowerShell 7.x for the optional read-only BC API inventory
description: 'Discover a BC or NAV integration before mapping DW10 data. Triggers: sandbox inventory, published APIs, pricing ownership, ship-to hierarchy, company and location keys, NAV migration gaps. Build -> dw-integration-bc.'
---

# Business Central discovery

Discover the Business Central (BC) model that a Truvio Commerce (powered by Dynamicweb)
integration will actually use. Separate documented capability, observed environment facts,
and the ERP owner's decisions. A tenant administrator role proves neither a populated sandbox
nor permission for an unattended integration identity.

## How to run me

| Phase | Output | Reference |
|---|---|---|
| Access | Tenant, environment type, company GUIDs, owners, application permissions | [references/access-surfaces.md](references/access-surfaces.md) |
| Structure | BC version, extensions, API metadata, published pages and connector versions | [references/structural-inventory.md](references/structural-inventory.md) |
| Population | Non-empty sources and sample joins in each company | [references/population-census.md](references/population-census.md) |
| Ownership | One writer per field; pricing, plants, inventory, bundles and credit policies | [references/ownership-and-process.md](references/ownership-and-process.md) |
| Migration | NAV source gaps and BC target contracts kept distinct | [references/nav-migration.md](references/nav-migration.md) |
| Review | Evidence-backed entity map, unanswered questions and implementation gates | [references/synthesis-brief.md](references/synthesis-brief.md) |

Save outputs outside the installed skill using
[assets/templates/data-model-brief.template.md](assets/templates/data-model-brief.template.md).
Review the brief with the ERP owner before using
[`dw-integration-bc`](../dw-integration-bc/SKILL.md) to build activities.

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [Get-BcInventory.ps1](scripts/Get-BcInventory.ps1) | Reads BC; writes evidence only with `-Apply` | Lists accessible companies and reads one item/customer sample per selected company; metadata is optional |

Run from this skill directory; authentication comes from the `BC_*` environment variables
described in the access reference. The default prints counts without writing files:

```powershell
pwsh -NoProfile -File scripts/Get-BcInventory.ps1 -CompanyIds <company-guid>
pwsh -NoProfile -File scripts/Get-BcInventory.ps1 -CompanyIds <company-guid> -IncludeMetadata -OutDirectory <discovery-dir> -Apply
```

An inaccessible source is a gap, an empty source is an observation, and an unqueried source is
unknown. Preserve all three in the review; none is evidence that a feature is unsupported.
