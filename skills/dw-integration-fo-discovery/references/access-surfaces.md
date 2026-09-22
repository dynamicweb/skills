# Access surfaces — what can be read from outside an F&O environment, and with which identity

## Contents

- [Pick surfaces by what the customer can grant](#pick-surfaces-by-what-the-customer-can-grant)
- [Surface 1 — OData `/data` with an S2S app registration](#surface-1--odata-data-with-an-s2s-app-registration)
- [Surface 2 — the Metadata service `/Metadata`](#surface-2--the-metadata-service-metadata)
- [Surface 3 — the Dynamics 365 ERP MCP server](#surface-3--the-dynamics-365-erp-mcp-server)
- [Surface 4 — ERP Analytics MCP (BPA)](#surface-4--erp-analytics-mcp-bpa)
- [Surface 5 — inside-out exports](#surface-5--inside-out-exports)
- [Record what was and was not reachable](#record-what-was-and-was-not-reachable)
- [Secrets discipline](#secrets-discipline)

## Pick surfaces by what the customer can grant

| Surface | Grants needed | Gives | Use for |
|---|---|---|---|
| OData `/data` (S2S) | Entra app registration + F&O *Microsoft Entra ID applications* row tied to a user with read roles | row counts, samples, config entities, `$metadata` | census, process footprint |
| Metadata service `/Metadata` | same token as OData | entity catalog with category, EDT per property, keys, navigation, labels | structural inventory |
| ERP MCP `/mcp` | ≥10.0.47, Tier-2+ or Unified Developer Environment, client in *Allowed MCP clients*, an interactive user | entity search + metadata + SQL-style queries, security-trimmed | interactive drill-down, not the census |
| ERP Analytics MCP | BPA enabled, BPA user role | DAX over the BPA model (O2C / P2P / R2R) | real aggregations on finance/order data |
| Inside-out exports | a customer admin, no API | installed models, technical-reference reports, DMF exports | ISV inventory when the OData actions are gated |

Rule: **census and structure come from OData + Metadata service; MCP is the conversation layer on top.** MCP output is trimmed to the calling user's roles and blocks admin forms, so counting through it undercounts silently.

## Surface 1 — OData `/data` with an S2S app registration

1. Customer registers an Entra app (client secret or certificate) and adds it in F&O under *System administration > Setup > Microsoft Entra ID applications*, bound to a user whose roles cover the entities to read (for discovery: a read-oriented role set; *System administrator* only when the customer insists — record it in `00-access.md`).
2. Token: client-credentials against `https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token` with scope `https://<env>.operations.dynamics.com/.default` — `assets/scripts/Get-FoToken.ps1`.
3. Calls carry `Authorization: Bearer`, `Accept: application/json`, `OData-MaxVersion: 4.0`.
4. Throttling: HTTP 429 with `Retry-After` under resource-based protection; the throttling key is the app's object id + client id, priority per *Throttling priority mapping*. Discovery is read-only and paced (`-DelayMs`), which keeps it under the historic 6,000-requests-per-5-minutes shape even where user-based limits are off.
5. Companies: every request is scoped to the identity's default company unless `?cross-company=true`; company-scoped entities carry `dataAreaId`. Enum filters need the namespace `Microsoft.Dynamics.DataEntities.<Enum>'<Value>'`.

Unified sandbox environments (`*.operations.dynamics.com`) support all of this; cloud-hosted developer environments (`*.axcloud.dynamics.com`) support OData and the Metadata service but **not** the ERP MCP.

## Surface 2 — the Metadata service `/Metadata`

Same token, GET-only, OData-shaped. Endpoints used by `Export-FoMetadata.ps1`:

| Endpoint | Returns |
|---|---|
| `/Metadata/DataEntities?$select=Name,PublicEntityName,PublicCollectionName,LabelId,DataServiceEnabled,DataManagementEnabled,EntityCategory,IsReadOnly` | every data entity (~5,000 on a current build), including those without an OData contract |
| `/Metadata/PublicEntities` | the OData-exposed entities (~4,500 on 10.0.48) with `Properties[]` (`Name`, `DataType`, `TypeName` = `Edm.*` primitive or enum type — **no EDT names**, `IsKey`, `IsMandatory`, `IsDimension`, `LabelId`), `NavigationProperties[]` (related entity, cardinality, referential constraints), `Actions[]`. ~47 MB on a stock tenant, ~1 min to pull |
| `/Metadata/PublicEnumerations` | enum members and values |
| `/Metadata/Labels(Id='@X:Y',Language='en-us')` | label text — resolve labels for the brief on demand |

Filters use the metadata namespace: `$filter=EntityCategory eq Microsoft.Dynamics.Metadata.EntityCategory'Master'`. Only `Labels` and `DataEntities` are on the official services page; `PublicEntities`/`PublicEnumerations` are stable in practice (two independent client libraries rely on them) — treat a 404 on them as a version signal, not a bug. `/Metadata/PublicEntities` is authorized like the entity reads: an app registration that is not yet mapped to an F&O user gets 200 on `/data/$metadata` and a refusal here, so finish the mapping from Surface 1 step 1 before the structural-inventory pull. `/data/$metadata` (one ~17 MB EDMX) adds nothing the Metadata service lacks except being diff-able against a clean baseline of the same build; pull it once with `-IncludeCsdl` when a baseline diff is planned.

## Surface 3 — the Dynamics 365 ERP MCP server

Endpoint `https://<env>.operations.dynamics.com/mcp`, HTTP transport, feature *Dynamics 365 ERP Model Context Protocol server* (on by default from 10.0.47), client id registered under *System administration > Setup > Allowed MCP clients* with Allowed = true. Every call runs as an authenticated user — interactive OAuth, no shared-service path.

Register in Claude Code (secret stays in the keychain when passed on the command line, never in `.mcp.json`):

```powershell
claude mcp add --transport http --client-id <app-client-id> --client-secret --callback-port 33418 d365-erp https://<env>.operations.dynamics.com/mcp
# then /mcp in Claude Code and complete the browser login against the environment's Entra tenant
```

Tools relevant to discovery:

| Tool | Use |
|---|---|
| `data_find_entity_type` | "which entity holds X" — top hits by description |
| `data_get_entity_metadata` | properties/keys of one entity, role-trimmed |
| `data_find_entities` / `data_find_entities_sql` | read rows; the SQL variant (10.0.48+) allows `COUNT(*)` / `GROUP BY` where OData cannot aggregate; `returnAsResource=true` raises the payload cap |
| `api_find_actions` / `api_invoke_action` | OData actions (e.g. the installed-modules action) |
| `form_*` | drive UI forms — the only route to *Custom fields* and *Allowed MCP clients* screens, but admin/security forms are blocked |

Blocked: security configuration, user info, Entra client table, feature management forms. Consequence: the user/role census comes from the OData security entities ([process-footprint.md](process-footprint.md)), not MCP. The pre-10.0.47 "static" MCP server retires and must not be planned on.

## Surface 4 — ERP Analytics MCP (BPA)

`https://agent365.svc.cloud.microsoft/mcp/environments/<ENVIRONMENT_ID>/servers/msdyn_ERPAnalyticsMCPServer` with tools `get-bpa-dataset-schema` and `execute-dax-query`. Requires Business Performance Analytics with the BPA user role; data refreshes twice daily; covers the order-to-cash, procure-to-pay and record-to-report value chains only. The one surface with real aggregation — use it for "orders per customer per month" style evidence in the brief when the customer has BPA.

## Surface 5 — inside-out exports

When API access is refused or the tenant is behind a partner, ask an admin for:

- `? > About > Show installed models` (screenshot or copy) — the ISV/publisher inventory.
- The *Technical reference reports* (Data entities, Data entity fields, Tables, Config keys, License codes, Workflow types) generated per environment with Microsoft's `fin-ops-doc-scripts` — the only official source for entity → root table mapping and config-key state.
- A DMF export project of the shortlist entities to Excel — a sample for fill rates when `$top` sampling is not possible.
- Legacy AX: see [legacy-ax.md](legacy-ax.md).

## Record what was and was not reachable

`<discovery-dir>/00-access.md` lists, per surface: reachable (yes/no), identity used (app name / user role — never the secret), version seen (`GetApplicationVersion`), companies visible, what was refused (403s, blocked forms, gated actions). Absence of evidence in the brief must be traceable to a line here.

## Secrets discipline

Client secrets live in the session (`$env:FO_CLIENT_SECRET`, the Claude Code keychain) or in an encrypted channel the customer chose — never in the supplied source material, `<discovery-dir>`, notes, or the plugin. Scripts print token expiry, never the token. If a secret lands in a file by accident, rotate it; do not just delete the file.
