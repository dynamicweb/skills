---
name: dw-integration-bc
type: flow
group: integration
mcp: optional
dynamo: false
compatibility: Requires PowerShell 7.x for API probes and Python 3.12+ for the offline acceptance verifier
description: 'Build BC integration on the DW10 Integration Framework and ERP plug-in unit. Triggers: company-scoped products, tier prices, ship-to, stock, order export, status, invoices and credit checks. Discover -> dw-integration-bc-discovery.'
---

# Business Central integration

Connect Truvio Commerce (powered by Dynamicweb) to Business Central (BC) through its
Integration Framework. Use the BC ERP plug-in unit for XML batch and supported live
operations; use published OData pages or standard APIs where their measured contracts fit.
Keep the PIM connector's product-enrichment flow separate from ERP commerce integration.

## Without MCP

Prefer Dynamicweb MCP for endpoints, activities, mappings, runs and read-back. Without it,
drop one rung to the Management API, then the serializer; direct SQL is last and local-install
only. Where the available surface does not reach an operation, produce configuration and
name the admin screen for the operator. The ladder belongs to
[`dw-data-access`](../dw-data-access/SKILL.md). BC HTTP calls are external ERP APIs.

## How to run me

| Phase | Checkable result | Reference |
|---|---|---|
| 0. Discover | Owner-reviewed source map per tenant/environment/company | [`dw-integration-bc-discovery`](../dw-integration-bc-discovery/SKILL.md) |
| 1. Authenticate | App token and a company-scoped entity read both succeed | [references/endpoints-and-auth.md](references/endpoints-and-auth.md) |
| 2. Map | Stable keys, field ownership and actual ERP surfaces captured | [references/entity-map.md](references/entity-map.md) |
| 3. Import | Products, accounts, ship-to, tiers and stock applied and read back | [references/batch-and-live.md](references/batch-and-live.md) |
| 4. Govern | Price precedence, bundle expansion, fulfilment and credit contracts proved | [references/commerce-contracts.md](references/commerce-contracts.md) |
| 5. Round trip | One order exported; line acknowledgement, status and invoices reconciled | [references/order-flow.md](references/order-flow.md) |
| 6. Verify | Replay, isolation and negative cases pass with evidence | [references/verification.md](references/verification.md) |

The [integration specification](assets/templates/integration-spec.example.json) records
company GUIDs and required scenarios. Keep actual URLs, identities, mappings, captures and
results in the integration folder, outside the skill. Configure only sources the environment
actually exposes. A standard API, published page, and plug-in request have different schemas.

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [Bc.Api.psm1](scripts/Bc.Api.psm1) | Read-only BC module | S2S or environment token; pinned company URLs; bounded retries and pagination; refuses redirects and escaping next links |
| [Test-BcConnection.ps1](scripts/Test-BcConnection.ps1) | Read-only | Tests companies and selected company item/customer/order/invoice collections; emits counts, never tokens |
| [verify_bc_acceptance.py](scripts/verify_bc_acceptance.py) | Read-only local evidence | Checks all required scenarios, company coverage, independent proofs, run mode and report freshness |

Run from this skill directory:

```powershell
pwsh -NoProfile -File scripts/Test-BcConnection.ps1 -CompanyIds <company-guid>
python scripts/verify_bc_acceptance.py --spec <integration-spec.json> --evidence <acceptance.json> --mode live
```

## The two connectors

The **ERP plug-in unit in BC** supplies commerce data and live calculations to the Integration
Framework. The **PIM connector** uses Management API `/admin/api/BC*` on the Commerce host,
initiated by the BC extension, to exchange product records. PIM connection success proves no
ERP price, stock, order or credit capability. Route field ownership through
[`dw-integration-erp`](../dw-integration-erp/SKILL.md) before enabling both writers.

The BC tenant owns multiple environments; an environment owns companies; a company owns
locations. Pin every request to a company. A location is not a legal entity, and a company
GUID is not an F&O `dataAreaId`.
