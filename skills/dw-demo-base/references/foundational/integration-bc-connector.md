# Foundational candidate → dw-integration-erp

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 PIM-for-Business-Central connector product
> surface, staged here for a future fold-up into `dw-integration-erp`. No demo/customer content.
> When folded, move this body into `dw-integration-erp` and re-target the pointers in the demo
> skills. Until then, the demo skills reference this file. Do not add demo specifics here.

The **PIM for Business Central connector** AppStore app exposes a `/admin/api/BC*` call surface on
the Dynamicweb host: 11 queries (read) + 4 commands (write), all bearer-auth via the standard
Management API token. The BC tenant's connector extension drives this surface.

## Call convention — single dispatcher

DW10's Management API is a single-dispatcher pattern at `/admin/api/<name>`. The dispatcher rejects
unknown names with HTTP 400 + `{"successful":false,"message":"Unknown query: 'X'"}`.

**The endpoint name is the C# class name MINUS the `Query` or `Command` suffix.**

| C# class | Endpoint |
|---|---|
| `BCLicenseQuery` | `GET /admin/api/BCLicense` |
| `BCSettingsQuery` | `GET /admin/api/BCSettings` |
| `BCSettingsSaveCommand` | `POST /admin/api/BCSettingsSave` |
| `BCProductByExternalIdQuery` | `GET /admin/api/BCProductByExternalId?externalId=...` |
| `BCBuildIndexCommand` | `POST /admin/api/BCBuildIndex` |

Sending `/admin/api/BCLicenseQuery` (with the suffix) returns `Unknown query: 'BCLicenseQuery'`.
Strip the suffix.

## Authentication — 400 vs 401

All endpoints require `Authorization: Bearer <token>` — the standard Management API token.

- **400** with body `{"successful":false,"message":"Unknown query: 'X'"}` means **auth succeeded**
  but the route name isn't registered (usually the suffix mistake above).
- **401** means auth failed (wrong/expired token).

This 400-vs-401 split is the fastest first-line diagnostic: it tells you whether you have a token
problem or a routing/naming problem.

## Reads — the 11 queries

```
GET /admin/api/BCLicense
GET /admin/api/BCSettings
GET /admin/api/BCProductFields
GET /admin/api/BCProductById?id=<DW_id>
GET /admin/api/BCProductByExternalId?externalId=<BC_item_no>
GET /admin/api/BCProductByUniqueId?uniqueId=<unique>
GET /admin/api/BCProductCountByLastModified?lastModified=<ISO_8601>
GET /admin/api/BCProductIdsByLastModified?lastModified=<ISO_8601>
GET /admin/api/BCProductDeleteLogsAll
GET /admin/api/BCProductDeleteLogsByLastDeleted?lastDeleted=<ISO_8601>
GET /admin/api/BCProductDeleteLogsByLastId?lastId=<int>
```

Roles in BC's sync flow:

- **`BCLicense`** — handshake. BC calls this first to verify the connector is alive and which
  capabilities are licensed (`pim`, `ecommerce`, `version`).
- **`BCSettings`** — BC reads the connector configuration to know which Products index to build,
  which workflow state to stamp on imported products, and how long deletion logs are retained.
- **`BCProductFields`** — the full PIM field schema. BC uses this to map BC item fields to PIM
  custom fields. Includes both standard fields (`ProductImage`, `ProductCost`) and
  category-specific fields (`ProductCategory|<CategoryName>|<FieldName>`).
- **`BCProductBy*`** — single-product reads by various ID dimensions (DW id, BC external id, unique
  id). Used when BC checks "does this product already exist before I push an update".
- **`BCProductCountByLastModified` / `BCProductIdsByLastModified`** — delta-sync helpers. BC passes
  its last-known-sync timestamp; the connector returns count + ids of everything modified since.
  Standard incremental sync pattern.
- **`BCProductDeleteLogs*`** — when products are deleted in PIM, the connector's
  `BCDeletedProductsCleanupHostedService` background service writes a row to a deletion log table
  (retention controlled by `BCSettings.retentionDays`). BC reads the log and deletes matching items
  on its side. Three query variants for different lookup patterns.

## Writes — the 4 commands

```
POST /admin/api/BCBuildIndex
POST /admin/api/BCProductCreate
POST /admin/api/BCProductUpdate
POST /admin/api/BCSettingsSave
```

All POST bodies use the wrapped form: `{ "Model": { ...fields... } }`. **Sending the model
unwrapped returns 400 with `{"Command.Model": ["Command.Model cannot be null"]}`** — that
validation message is the `*Command` class rejecting a null `Model` property, not a generic
"missing field" error.

Roles:

- **`BCBuildIndex`** — triggers a Products index rebuild. Same effect as
  `POST /admin/api/BuildIndex {Repository:"Products", IndexName:"Products.index", BuildName:"Full"}`
  — the BC variant infers the index target from `BCSettings.indexBuildKey` and `BCSettings.buildName`.
- **`BCProductCreate`** — BC pushes a new item. Connector creates the DW product, attaches it to the
  data-model groups, optionally stamps it with `BCSettings.workflowStateId`, optionally triggers a
  partial index build.
- **`BCProductUpdate`** — BC pushes an update. Connector resolves the product (typically by external
  id), patches the changed fields, re-builds index if configured.
- **`BCSettingsSave`** — writes the connector configuration. Upsert, not append — idempotent.

## Internal types — not endpoints

Several types in the AppStore package don't expose endpoints; they're internal pipelines and
providers. The generic DW10 patterns behind them (UpdateProviders that seed defaults, `*Pipeline`
classes that register DI services at startup) are documented in
[`extend-providers.md`](extend-providers.md); the BC-specific instances are:

- `BCEndpointsPipeline` — DI-time pipeline that registers all the queries + commands at host startup.
- `BCSettingsEditScreen` + `BCSettingsNodeProvider` — admin UI surface (Settings → tree node "BC
  connector settings" with an edit screen).
- `BCSetupUpdateProvider` — runs on first host startup after install. Seeds the `BCSettings` row
  with default values (see "BC default settings" below).
- `BCWorkflowUpdateProvider` — creates the "BC Products" workflow with a single state "New Product
  From BC". This is `workflowStateId=1` in a fresh install.
- `BCDeletedProductsCleanupHostedService` — background service that prunes old `BCProductDeleteLog`
  rows past the `retentionDays` window.
- `BCFileStreams` — update-provider helper for streaming connector files into the AddIn folder
  during install.

## BC default settings — what the install seeds, and why it's usually wrong

After the AppStore app installs and the host restarts, `BCSetupUpdateProvider` writes a default
`BCSettings` row. `GET /admin/api/BCSettings` shows the shape:

```json
{
  "model": {
    "indexBuildKey": "ProductsBackend|Products.index",
    "buildName": "Partial",
    "retentionDays": 30,
    "workflowStateId": 1,
    "permissionLevelCurrentUser": null
  },
  "successful": true,
  "message": ""
}
```

Three of the four fields are typically wrong for the host the app is dropped into:

1. **`indexBuildKey: "ProductsBackend|Products.index"`** — format is `<RepositoryName>|<IndexFileName>`.
   The app guesses `ProductsBackend` as the repo name (from the historical `ProductsBackend`/
   `ProductsFrontend` split). Most modern hosts have a single `Products` repo. Verify by listing
   `wwwroot/Files/System/Repositories/`. If the repo is `Products` (not `ProductsBackend`), the
   default is dangling and `BCBuildIndex` fails with "repository not found".
2. **`buildName: "Partial"`** — valid only if `Products.index` actually has a
   `<Build Name="Partial">` element. Most hosts do (stock in the canonical index template), but a
   hand-trimmed index might only have `Full`. Verify with
   `Select-String -Path Products.index -Pattern '<Build Name'`.
3. **`workflowStateId: 1`** — assumes the BC workflow state exists. `BCWorkflowUpdateProvider`
   creates it on first host startup post-install (id=1 typically). Verify via MCP `get_workflow_states`;
   if it returns `[]`, bounce the host once and re-check. Setting `workflowStateId: 0` lands BC pushes
   directly in the active catalog with no state stamp.

`retentionDays: 30` is fine as a default and rarely changes.

The corrected `BCSettingsSave` recipe is per-host and environment-specific (it has to read the
actual repo name, index build names, and workflow id off the host), so it is applied at deploy time
rather than specified here.
