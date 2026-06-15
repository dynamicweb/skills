# dynamicweb-connector-settings.md

(Formerly bc-settings-correction.md.)

> The PIM for Business Central connector AppStore app installs with default settings -- the Dynamicweb/DW-side `BCSettings` row -- that are **almost always wrong** for the project you're dropping it into. This reference tells you what's wrong, what to set instead, and how. Loaded from `~/.claude/skills/dynamicweb-pim-for-bc/SKILL.md` "Where to find things" table.

## What ships, and why it's wrong

Right after the AppStore app installs and the host restarts, `BCSetupUpdateProvider` writes a default `BCSettings` row. Reading `GET /admin/api/BCSettings` shows shape:

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

Three of those four fields are typically wrong:

1. **`indexBuildKey: "ProductsBackend|Products.index"`** -- format is `<RepositoryName>|<IndexFileName>`, but the AppStore app guesses `ProductsBackend` as the repo name (presumably from the historical Swift1 `ProductsBackend`/`ProductsFrontend` split). Most modern Dynamicweb demos have a single `Products` repo. Verify by listing `wwwroot/Files/System/Repositories/`. If you see `Products` (not `ProductsBackend`), the default is dangling -- BC's `BCBuildIndex` will fail with "repository not found".

2. **`buildName: "Partial"`** -- valid only if your `Products.index` actually has a `<Build Name="Partial">` element. Most Dynamicweb demos do (it's stock in the canonical index template), but a hand-trimmed index might only have `Full`. Verify with `Select-String -Path Products.index -Pattern '<Build Name'`.

3. **`workflowStateId: 1`** -- assumes the BC workflow state has been created. `BCWorkflowUpdateProvider` runs on first host startup post-install and creates a workflow named "BC Products" with a single state "New Product From BC", typically with id=1. Verify via MCP: `get_workflow_states` should return `[{id:1, name:"BC Products", states:[{id:1, name:"New Product From BC", ...}]}]`. If it returns `[]`, the workflow update didn't run -- bounce the host once and re-check; if still empty, the AppStore install didn't complete cleanly.

`retentionDays: 30` is fine as a default and rarely needs to change.

## The corrected save

Build the corrected payload after verifying each field against your project's actual state:

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

The `{"Model": {...}}` wrapper rule and the exact 400 you get when you forget it are documented in [connector-endpoints.md](connector-endpoints.md) "Writes".

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

## Workflow state -- when to keep it, when to zero it

`workflowStateId: 1` is the auto-created "New Product From BC" state. Keeping it means every product BC pushes via `BCProductCreate` is stamped with that state -- useful for dashboards that want to surface "what did BC just push" or for governance flows that require BC-imported products to go through review before they show up on shopfront.

Zero it (`workflowStateId: 0`) if the demo wants BC pushes to land directly into the active catalog with no state stamp -- simpler narrative, less governance theatre.

For demos where the governance dashboard is a centerpiece, **keep the state**. The "BC just pushed 12 items, all in 'New Product From BC' state" pattern is a strong demo beat.

## What to do if defaults LOOK right but BC fails

If `BCSettings` already shows correct values out of the box -- the AppStore install happened to guess right -- but BC still errors on `BCBuildIndex` or `BCProductCreate`, the failure is downstream of settings:

- Check that `Products.index` actually exists in `wwwroot/Files/System/Repositories/Products/`.
- Check that the workflow state exists via `get_workflow_states`.
- Check that the bearer token has the correct permission level. The connector inspects `permissionLevelCurrentUser` -- if your token has insufficient permissions, the response is shaped right but the writes silently no-op. (The current Dynamicweb Management API token issued via admin UI is full-access by default; only an issue if you've narrowed permissions.)

Re-running the corrected save above is idempotent -- `BCSettingsSave` is upsert, not append.
