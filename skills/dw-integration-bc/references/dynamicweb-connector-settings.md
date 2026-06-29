# dynamicweb-connector-settings.md

(Formerly bc-settings-correction.md.)

> Per-demo recipe for correcting the connector's `BCSettings` row against the host you're demoing on.
> The AppStore app installs default settings that are almost always wrong for the host it lands in;
> *why* (the UpdateProvider-seeds-host-unaware-defaults pattern) is the foundational candidate
> [`extend-providers.md`](../../dw-demo-base/references/foundational/extend-providers.md) §1, and the
> BC-specific default values + which fields are wrong are in
> [`integration-bc-connector.md`](../../dw-demo-base/references/foundational/integration-bc-connector.md)
> "BC default settings". This file is the hands-on correction you run against a live demo host.

## Before correcting — verify against the actual host

The seeded defaults (`indexBuildKey`, `buildName`, `workflowStateId`) are host-unaware guesses. Read
[`integration-bc-connector.md`](../../dw-demo-base/references/foundational/integration-bc-connector.md)
"BC default settings" for what each field means and how it's typically wrong, then verify each one
against the host you're demoing on:

- `indexBuildKey` — list `wwwroot/Files/System/Repositories/`; use the real repo name (usually
  `Products`, not `ProductsBackend`).
- `buildName` — `Select-String -Path Products.index -Pattern '<Build Name'` to confirm the named
  build exists.
- `workflowStateId` — MCP `get_workflow_states`; confirm the "New Product From BC" state's id.

## The corrected save

Build the corrected payload after verifying each field against the demo host's actual state:

```powershell
$base = "https://localhost:31873"   # local URL is fine for setup; tunnel not required yet
$token = (Get-Content ".\.claude\settings.local.json" | ConvertFrom-Json).env.DW_API_TOKEN
$h = @{ "Authorization" = "Bearer $token"; "Accept" = "application/json"; "Content-Type" = "application/json" }

$body = @{
    Model = @{   # <-- the {"Model": ...} wrapper is required, do not send the fields unwrapped
        indexBuildKey   = "Products|Products.index"  # <-- corrected: use the actual repo name on disk
        buildName       = "Partial"                  # <-- verify a <Build Name="Partial"> element exists
        retentionDays   = 30
        workflowStateId = 1                          # <-- verify via get_workflow_states
    }
} | ConvertTo-Json

Invoke-RestMethod -Uri "$base/admin/api/BCSettingsSave" -Method POST -Headers $h -Body $body
```

The `{"Model": {...}}` wrapper rule and the exact 400 you get when you forget it are in
[connector-endpoints.md](connector-endpoints.md) "Two diagnostics" /
[`integration-bc-connector.md`](../../dw-demo-base/references/foundational/integration-bc-connector.md)
"Writes".

Successful save returns:

```json
{
  "status": "ok",
  "message": null,
  "exception": null,
  "model": { ...the settings just written... },
  "modelIdentifier": null
}
```

## Verifying the corrected state

```powershell
Invoke-RestMethod -Uri "$base/admin/api/BCSettings" -Headers $h | ConvertTo-Json -Depth 3
```

The `model` block should match what you sent (modulo the read-only `permissionLevelCurrentUser` field).
`BCSettingsSave` is upsert, not append — re-running the corrected save is idempotent.

## Workflow state — keep it for the governance demo beat

`workflowStateId: 1` is the auto-created "New Product From BC" state. **Keep it** when the demo's
governance dashboard is a centerpiece: every product BC pushes via `BCProductCreate` gets stamped
with that state, so the "BC just pushed 12 items, all in 'New Product From BC' state" pattern becomes
a strong demo beat (governance baked into the integration). Zero it (`workflowStateId: 0`) only when
the demo wants BC pushes to land directly in the active catalog with no state stamp — simpler
narrative, less governance theatre.

## If defaults LOOK right but BC still fails

If `BCSettings` already shows correct values (the install happened to guess right) but BC still errors
on `BCBuildIndex` or `BCProductCreate`, the failure is downstream of settings:

- Confirm `Products.index` exists in `wwwroot/Files/System/Repositories/Products/`.
- Confirm the workflow state exists via `get_workflow_states`.
- Confirm the bearer token's permission level. The connector inspects `permissionLevelCurrentUser`;
  an under-permissioned token returns a right-shaped response but the writes silently no-op. (The
  admin-issued Management API token is full-access by default; only an issue if you've narrowed it.)
