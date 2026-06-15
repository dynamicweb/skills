# connector-endpoints.md

> The `/admin/api/BC*` call surface exposed by the **PIM for Business Central connector** AppStore app. 11 queries (read) + 4 commands (write), all bearer-auth via the existing Management API token. Loaded from `~/.claude/skills/dynamicweb-pim-for-bc/SKILL.md` "Where to find things" table.

## Call convention

DW10's Management API is a single-dispatcher pattern at `/admin/api/<name>`. The dispatcher rejects unknown names with HTTP 400 + `{"successful":false,"message":"Unknown query: 'X'"}`.

**The endpoint name is the C# class name MINUS the `Query` or `Command` suffix.** This trips everyone the first time:

| C# class | Endpoint |
|---|---|
| `BCLicenseQuery` | `GET /admin/api/BCLicense` |
| `BCSettingsQuery` | `GET /admin/api/BCSettings` |
| `BCSettingsSaveCommand` | `POST /admin/api/BCSettingsSave` |
| `BCProductByExternalIdQuery` | `GET /admin/api/BCProductByExternalId?externalId=...` |
| `BCBuildIndexCommand` | `POST /admin/api/BCBuildIndex` |

Sending `/admin/api/BCLicenseQuery` (with the suffix) returns `Unknown query: 'BCLicenseQuery'`. Strip the suffix.

## Authentication

All endpoints require `Authorization: Bearer <DW_API_TOKEN>` -- bearer auth with the standard Management API token; issuance (admin path + reuse-vs-dedicated tradeoff) -> [bc-side-config.md](bc-side-config.md) §2.

400 with body `{"successful":false,"message":"Unknown query: 'X'"}` means **auth succeeded** but the route name isn't registered. 401 means auth failed (wrong/expired token).

## Reads -- the 11 queries

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

- **`BCLicense`** -- handshake. BC calls this first to verify the connector is alive and which capabilities are licensed (`pim`, `ecommerce`, `version`).
- **`BCSettings`** -- BC reads the connector configuration to know which Products index to build, which workflow state to stamp on imported products, and how long deletion logs are retained.
- **`BCProductFields`** -- the full PIM field schema (50+ fields in a typical demo). BC uses this to map BC item fields to PIM custom fields. **Includes both standard fields (`ProductImage`, `ProductCost`) and category-specific fields (`ProductCategory|<CategoryName>|<FieldName>`).**
- **`BCProductBy*`** -- single-product reads by various ID dimensions (DW id, BC external id, unique id). Used when BC checks "does this product already exist before I push an update".
- **`BCProductCountByLastModified` / `BCProductIdsByLastModified`** -- delta-sync helpers. BC passes its last-known-sync timestamp; the connector returns count + ids of everything modified since. Standard incremental sync pattern.
- **`BCProductDeleteLogs*`** -- when products are deleted in PIM, the connector's `BCDeletedProductsCleanupHostedService` background service writes a row to a deletion log table (retention controlled by `BCSettings.retentionDays`). BC reads the log and deletes matching items on its side. Three query variants for different lookup patterns.

## Writes -- the 4 commands

```
POST /admin/api/BCBuildIndex
POST /admin/api/BCProductCreate
POST /admin/api/BCProductUpdate
POST /admin/api/BCSettingsSave
```

All POST bodies use the wrapped form: `{ "Model": { ...fields... } }`. **Sending the model unwrapped returns 400 with `{"Command.Model": ["Command.Model cannot be null"]}`** -- this is the easiest mistake to make on the first integration attempt. That validation message is the `*Command` class rejecting a null `Model` property -- it's not a generic "missing field" error.

Roles:

- **`BCBuildIndex`** -- triggers a Products index rebuild. Same effect as `POST /admin/api/BuildIndex {Repository:"Products", IndexName:"Products.index", BuildName:"Full"}` -- the BC variant infers the index target from `BCSettings.indexBuildKey` and `BCSettings.buildName`.
- **`BCProductCreate`** -- BC pushes a new item. Connector creates the DW product, attaches it to the data-model groups, optionally stamps it with `BCSettings.workflowStateId`, optionally triggers a partial index build.
- **`BCProductUpdate`** -- BC pushes an update. Connector resolves the product (typically by external id), patches the changed fields, re-builds index if configured.
- **`BCSettingsSave`** -- writes the connector configuration. See [dynamicweb-connector-settings.md](dynamicweb-connector-settings.md) for the exact payload.

## Background plumbing -- not endpoints

Five types in the AppStore package don't expose endpoints; they're internal pipelines and providers:

- `BCEndpointsPipeline` -- DI-time pipeline that registers all the queries + commands at host startup.
- `BCSettingsEditScreen` + `BCSettingsNodeProvider` -- admin UI surface (Settings -> tree node "BC connector settings" with an edit screen).
- `BCSetupUpdateProvider` -- runs on first host startup after install. Seeds the BCSettings row with default values (which are usually wrong for your project, see [dynamicweb-connector-settings.md](dynamicweb-connector-settings.md)).
- `BCWorkflowUpdateProvider` -- creates the "BC Products" workflow with a single state "New Product From BC". This is `workflowStateId=1` in a fresh install. Verify with `mcp__dynamicweb-commerce-mcp__get_workflow_states`.
- `BCDeletedProductsCleanupHostedService` -- background service that prunes old `BCProductDeleteLog` rows past the `retentionDays` window.
- `BCFileStreams` -- update-provider helper for streaming connector files into the AddIn folder during install.

## Discovering this surface yourself

The endpoint inventory is not documented anywhere user-visible by DW. To re-derive it for a future connector version, read the metadata of the installed assembly. PowerShell-only, no decompiler needed:

```powershell
Add-Type -AssemblyName System.Reflection.Metadata -ErrorAction SilentlyContinue
$dll = "<your-host>\wwwroot\Files\System\AddIns\Installed\Dynamicweb.Pimforbusinesscentralconnector.<ver>\lib\net10.0\Dynamicweb.PimForBusinessCentralConnector.dll"
$stream = [System.IO.File]::OpenRead($dll)
try {
  $peReader = [System.Reflection.PortableExecutable.PEReader]::new($stream)
  $mr = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)
  $names = foreach ($h in $mr.TypeDefinitions) {
    $td = $mr.GetTypeDefinition($h)
    $ns = $mr.GetString($td.Namespace); $n = $mr.GetString($td.Name)
    if ($ns) { "$ns.$n" } else { $n }
  }
  "-- QUERIES --";  $names | Where-Object { $_ -match '\.Queries\.[A-Z][A-Za-z]+Query$' } | Sort-Object
  "-- COMMANDS --"; $names | Where-Object { $_ -match '\.Commands\.[A-Z][A-Za-z]+Command$' } | Sort-Object
} finally { $peReader.Dispose(); $stream.Dispose() }
```

Why `MetadataReader` rather than `Assembly.LoadFrom`: the `Query<>`/`Command<>` base types live in DW assemblies that don't load in PowerShell's default context, so `Assembly.LoadFrom` raises `ReflectionTypeLoadException` and silently drops the query/command types. `MetadataReader` reads names directly from the PE file without resolving dependencies.

`PEReaderExtensions.GetMetadataReader` is an extension method -- PS doesn't auto-discover it, so call it as a static (`[System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)`).
