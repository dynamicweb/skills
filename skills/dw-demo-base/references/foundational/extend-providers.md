# Foundational candidate → dw-extend-providers

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 AddIn lifecycle patterns, staged here for a future
> fold-up into `dw-extend-providers`. No demo/customer content. When folded, move this body into
> `dw-extend-providers` and re-target the pointers in the demo skills. Until then, the demo skills
> reference this file. Do not add demo specifics here.

Three durable patterns that recur across DW10 AppStore AddIns. The generic provider/AddIn/discovery
mechanics (`UpdateProvider`, reflection-based discovery, `[AddInName]`) are already owned by
`dw-extend-providers`; these three nuances extend that base.

## 1. The UpdateProvider-seeds-defaults pattern

An `UpdateProvider` does more than schema migration — it's the standard hook a package uses to
**seed a default configuration row on first host startup after install**. An AddIn commonly ships
two of them:

- A **setup** UpdateProvider that writes a default settings row (index keys, retention windows,
  build names, a default workflow-state id).
- A **workflow** UpdateProvider that creates a companion workflow + state so the default settings
  row's `workflowStateId` resolves to something real.

The seeded defaults are **best-guess, not host-aware** — the provider can't read the actual
repository names, index build names, or existing workflow ids of the host it lands in, so it writes
plausible placeholders. Treat any AddIn's first-startup settings row as a draft to verify against
the host's real state (list `wwwroot/Files/System/Repositories/`, grep the index for `<Build Name>`,
list workflow states), then correct it through the AddIn's own save endpoint. The save is typically
upsert/idempotent, so re-running the correction is safe.

UpdateProviders run **once**, keyed by their permanent GUID update ids (tracked in `dbo.Updates`).
If first-startup seeding didn't happen (settings row empty, workflow missing), the install didn't
complete cleanly — bounce the host once; if still empty, re-install.

## 2. `*Pipeline` DI registration needs a host restart

Many AddIns register their services via a `*Pipeline` class that runs **only at host startup**.
Until the host is restarted after install, the DLL is on disk and the dispatcher routes to its
types, but the service container has no registration — so the type's static constructor throws.

The canonical stuck-state signature:

```
500 {"detail":"... TypeInitializationException ...
     No service for type '<Package>.API.<Service>' has been registered ..."}
```

This `TypeInitializationException` is the **single most common stuck state** after an AppStore
install: install succeeded, but the pipeline that registers the service hasn't run because the
host process is still the pre-install one. **Restart the host** (`dotnet run` cycle). On startup the
host log shows a `Running pipeline: '<Package>.<Pipeline>'.` line — its presence confirms the DI
registration ran.

Three-way probe to classify the state (probe any of the AddIn's POST endpoints with bearer auth):

| Response | Meaning | Fix |
|---|---|---|
| `400 {"successful":false,"message":"Unknown command: '<Name>'"}` | AddIn not installed | Install from admin → Settings → AppStore |
| `500 ... TypeInitializationException ... No service for type ...` | Installed but **host not restarted** | Restart the host |
| `200 {"status":"ok", ...}` | Installed, services registered, working | None |

## 3. The admin-deeplink ("static link") mechanism

DW10 ships a generic **admin-deeplink** capability as a standalone AppStore package
(`StaticLinkManager`): register a tokenised URL that opens a specific admin object (Product, Group,
etc.) **without** requiring the consumer to authenticate as a DW user. It's a shared service —
multiple consumers use it (connectors with embedded webviews, BI tools linking back into the admin),
which is why DW ships it standalone rather than bundling it into any single connector. It is **not**
installed by default by the `dw10-suite` template; it needs the install + host-restart cycle in §2.

### Endpoint surface

Once installed and the host has restarted:

```
GET  /admin/api/StaticLinkAll                                      -- paginated list of all links
GET  /admin/api/StaticLinkById?id=<int>                            -- single link by integer id
GET  /admin/api/StaticLinkByArgumentAndType?Type=<T>&Argument=<A>  -- lookup by (type,argument); idempotency checks
POST /admin/api/StaticLinkSave    body { Model: { Type, Argument, ... } }  -- create or update a link
POST /admin/api/StaticLinkDelete  body { Model: { Id: <int> } }            -- revoke a link
GET  /admin/api/StaticLinkSettings                                 -- AddIn-level config (template, expiration)
POST /admin/api/StaticLinkSettingsSave                             -- update AddIn-level config
```

**Casing matters on query parameters.** DW Management API parameter binding is case-sensitive:
`Type=Product` works, `type=Product` returns 500 with an `Enum.Parse` failure. PascalCase the names.

### Settings shape (defaults)

```json
{
  "useCustomTemplate": false,
  "defaultTemplatePath": "",
  "defaultExpirationInMilliseconds": 0
}
```

Defaults are usually fine — links never expire (`0`), and the system template renders the embedded
admin page without customisation. For a branded/reduced-chrome landing, set `useCustomTemplate=true`
and point `defaultTemplatePath` at a `.cshtml` under `Files/Templates/StaticLinks/`.

### Save response shape

```json
{
  "status": "ok",
  "message": "Static link saved successfully.",
  "model": {
    "id": 1,
    "slug": "<64-hex>",
    "type": "Product",
    "argument": "PROD1",
    "expirationInMilliseconds": null,
    "expirationTimestamp": null
  }
}
```

The `slug` is a 64-hex-char opaque token. A consumer composes the embedded webview URL by joining
the slug with the admin host (`https://<host>/admin/sl/<slug>` or similar — the exact pattern depends
on the consuming AddIn version). When the host sits behind a reverse proxy/tunnel with forwarded
headers wired, `<host>` resolves to the public hostname automatically at slug-generation time.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| `StaticLinkSave` returns 400 `Unknown command` | AddIn not installed |
| `StaticLinkSave` returns 500 `TypeInitializationException` | Installed, host not restarted (§2) |
| Save returns 200 but the consumer's webview shows blank/error | Different layer — check the URL the consumer actually loaded; could be forwarded-headers not honouring `X-Forwarded-Host` |
| `StaticLinkByArgumentAndType` returns 500 `Enum.Parse` failure | Lowercase parameter names; PascalCase to `?Type=...&Argument=...` |
| Save returns 400 `{"Type":["Invalid link type specified."]}` | The `Type` value isn't a recognised link-type enum (`Product` is the documented one) |
