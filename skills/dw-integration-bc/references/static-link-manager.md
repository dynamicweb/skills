# static-link-manager.md

> The `StaticLinkManager` AppStore AddIn that owns the `/admin/api/StaticLink*` admin-deeplink surface. The BC connector's "show PIM product page" feature (the embedded webview that opens a PIM product detail page from inside Business Central) requires this AddIn -- it is **NOT** part of the BC connector AppStore package itself, despite being adjacent in functionality. Loaded from `~/.claude/skills/dynamicweb-pim-for-bc/SKILL.md` "Where to find things" table.

## Why this exists as a separate AddIn

DW10's "static link" capability is a generic admin-deeplink mechanism: register a tokenised URL that opens a specific admin object (Product, Group, etc.) without requiring the consumer to authenticate as a DW user. Multiple consumers use it: the BC connector for its embedded webview, future commerce integrations, BI tools that link back into the PIM. So Dynamicweb ships it as a standalone AppStore package (`StaticLinkManager`), not bundled into any single connector.

Practical consequence for BC connector demos: even after you install **PIM for Business Central connector** and the rest of the chain works (tunnel, ForwardedHeaders, BCSettings), the "show PIM product page" beat in BC will fail until **StaticLinkManager is also installed**.

## Detection -- three failure shapes, three fixes

Probe `POST /admin/api/StaticLinkSave` with `{"Model":{"Type":"Product","Argument":"PROD1"}}` and bearer auth. Map the response:

| Response | Meaning | Fix |
|---|---|---|
| `400 {"successful":false,"message":"Unknown command: 'StaticLinkSave'"}` | AddIn not installed | Install `StaticLinkManager` from DW admin -> Settings -> AppStore |
| `500 {"detail":"... TypeInitializationException ... No service for type 'StaticLinkManager.API.StaticLinkService' has been registered ..."}` | AddIn installed but **host not restarted** since install | Restart the host (`dotnet run` cycle); the `StaticLinkManagerPipeline` only registers DI services at startup |
| `200 {"status":"ok","model":{"slug":"<64-hex>",...}}` | AddIn installed, services registered, working | None -- BC's webview should now succeed |

The `TypeInitializationException` shape is the **single most common stuck-state** after AppStore install: the DLL is on disk, the dispatcher routes to its types, but the static constructor of the command can't resolve `StaticLinkService` because no pipeline has registered it. Restart the host. This applies to most DW10 AppStore AddIns with a `*Pipeline` class -- the BC connector's `BCEndpointsPipeline` exhibits the same pattern.

## Install recipe (DW admin, manual)

The `StaticLinkManager` AddIn is not pre-installed by `dotnet new dw10-suite`. Install it post-host-up:

1. Sign into the local DW admin (`https://localhost:31873/Admin`).
2. Navigate **Settings -> AppStore**. The AppStore page lists available DW packages.
3. Search "Static Link" or "StaticLinkManager".
4. Click **Install**. The package downloads to `wwwroot/Files/System/AddIns/Installed/Dynamicweb.Staticlinkmanager.<ver>/`.
5. **Restart the `dotnet run` host process.** The AddIn's `StaticLinkManager.StaticLinkManagerPipeline` runs at startup and registers `StaticLinkManager.API.StaticLinkService` in the DI container. Without restart, all `StaticLink*` endpoints throw 500.
6. Verify: the host log should show `Running pipeline: 'StaticLinkManager.StaticLinkManagerPipeline'.` between the `BCEndpointsPipeline` and `ClassicFrontendPipeline` lines on startup.

## Endpoint surface

Once installed and the host has restarted, the following routes are live:

```
GET  /admin/api/StaticLinkAll                                 -- paginated list of all static links
GET  /admin/api/StaticLinkById?id=<int>                       -- single link by integer id
GET  /admin/api/StaticLinkByArgumentAndType?Type=<T>&Argument=<A>  -- lookup by (type,argument); BC uses this for idempotency checks
POST /admin/api/StaticLinkSave    body { Model: { Type, Argument, ... } }      -- create or update a link
POST /admin/api/StaticLinkDelete  body { Model: { Id: <int> } }                -- revoke a link
GET  /admin/api/StaticLinkSettings                            -- AddIn-level config (template path, default expiration)
POST /admin/api/StaticLinkSettingsSave                        -- update AddIn-level config
```

**Casing matters on query parameters.** DW Management API parameter binding is case-sensitive: `Type=Product` works, `type=Product` returns 500 with `Enum.Parse` failure. PascalCase the parameter names.

## Settings shape

`GET /admin/api/StaticLinkSettings` defaults:

```json
{
  "useCustomTemplate": false,
  "defaultTemplatePath": "",
  "defaultExpirationInMilliseconds": 0
}
```

For most demos the defaults are fine -- links never expire (`0`), and the system template renders the embedded admin page without customisation. If the demo needs a custom landing template (branded skin, reduced chrome), set `useCustomTemplate=true` and point `defaultTemplatePath` at a `.cshtml` under `Files/Templates/StaticLinks/`.

## Save response shape

```json
{
  "status": "ok",
  "message": "Static link saved successfully.",
  "model": {
    "id": 1,
    "slug": "d162458f32524f6f897d60360801deeb...",
    "type": "Product",
    "argument": "PROD1",
    "createdAt": "2026-05-07T11:07:30Z",
    "expirationInMilliseconds": null,
    "expirationTimestamp": null
  }
}
```

The `slug` is a 64-hex-char opaque token. BC composes the embedded webview URL by joining the slug with the DW admin host -- the exact pattern depends on the BC connector version, but it's typically `https://<dw-host>/admin/sl/<slug>` or similar. With `ForwardedHeaders` wired (see [forwarded-headers.md](forwarded-headers.md)), `<dw-host>` resolves to the public ngrok hostname automatically when the slug is generated through the tunnel.

## Why the cloud demo "just works"

`jus.dw10demo.dynamicweb.cloud` ships a fuller default install that includes `StaticLinkManager` out of the box. Local `dw10-suite` template installs do NOT include it. The cloud also has 3 pre-existing `StaticLinkAll` entries (Type=Product, arguments 10001/10059/10005) created earlier -- evidence the BC connector demo flow has been actively used there.

If you're comparing your local install against the cloud and discovering missing endpoints, the AppStore page in admin is the place to check. AddIns that are present on cloud but not local need the install + host-restart cycle.

## Troubleshooting matrix

| Symptom | Likely cause |
|---|---|
| BC's "show PIM product page" silent failure; `/admin/api/StaticLinkSave` returns 400 Unknown command | AddIn not installed |
| Same as above but 500 with `TypeInitializationException` | AddIn installed, host not restarted |
| Save returns 200 but BC's webview shows blank / error | Different layer -- check what URL BC actually loaded (ngrok inspector at `127.0.0.1:4040`); could be `ForwardedHeaders` not honouring `X-Forwarded-Host` (see [forwarded-headers.md](forwarded-headers.md)) |
| `StaticLinkByArgumentAndType` returns 500 with `Enum.Parse` failure | Lowercase parameter names; use `?Type=...&Argument=...` (PascalCase) |
| Save returns 400 `{"Type":["Invalid link type specified."]}` | The `Type` value isn't a recognised link-type enum. Currently only `Product` is documented in the wild; other values may need confirmation against the DW source |
