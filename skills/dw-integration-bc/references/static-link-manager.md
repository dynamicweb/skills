# static-link-manager.md

> Install the `StaticLinkManager` AppStore AddIn so the BC connector's "show PIM product page" beat
> works during the demo. The generic admin-deeplink mechanism, the full `/admin/api/StaticLink*`
> endpoint surface, its settings/save shapes, the case-sensitive-parameter gotcha, and the
> `*Pipeline`-DI-needs-restart pattern are vendor-generic and live in the foundational candidate
> [`extend-providers.md`](../../dw-demo-base/references/foundational/extend-providers.md) §2–§3. This
> file is the demo-specific "install it or the beat fails" recipe.

## Why it matters for the BC demo

The "show PIM product page" feature (the embedded webview that opens a PIM product detail page from
inside Business Central) uses DW10's generic static-link deeplink capability. That capability ships
as a **separate** AppStore package (`StaticLinkManager`), NOT as part of the BC connector package,
and it is NOT installed by `dotnet new dw10-suite`. So even after the tunnel, ForwardedHeaders, and
`BCSettings` are all working, the "show PIM product page" beat will fail until StaticLinkManager is
also installed and the host restarted.

The generic three-failure-shape probe (`Unknown command` → not installed; `TypeInitializationException`
→ installed but host not restarted; `200` → working) and the full endpoint surface are in
[`extend-providers.md`](../../dw-demo-base/references/foundational/extend-providers.md). The BC
connector's own `BCEndpointsPipeline` exhibits the same restart requirement.

## Install recipe (DW admin, manual)

Install it post-host-up:

1. Sign into the local DW admin (`https://localhost:31873/Admin`).
2. Navigate **Settings → AppStore**.
3. Search "Static Link" or "StaticLinkManager".
4. Click **Install**. The package downloads to
   `wwwroot/Files/System/AddIns/Installed/Dynamicweb.Staticlinkmanager.<ver>/`.
5. **Restart the `dotnet run` host process.** The AddIn's `StaticLinkManager.StaticLinkManagerPipeline`
   runs at startup and registers `StaticLinkManager.API.StaticLinkService` in the DI container.
   Without the restart, all `StaticLink*` endpoints throw 500 (`TypeInitializationException`).
6. Verify: the host log should show `Running pipeline: 'StaticLinkManager.StaticLinkManagerPipeline'.`
   between the `BCEndpointsPipeline` and `ClassicFrontendPipeline` lines on startup.

## Quick post-install check

Probe `POST /admin/api/StaticLinkSave` with `{"Model":{"Type":"Product","Argument":"PROD1"}}` and
bearer auth. A `200 {"status":"ok","model":{"slug":"<64-hex>",...}}` means BC's webview should now
succeed; `400 Unknown command` means not installed; `500 TypeInitializationException` means installed
but the host wasn't restarted. Classify and fix per
[`extend-providers.md`](../../dw-demo-base/references/foundational/extend-providers.md) §2.

When the embedded webview is reached through the tunnel, the slug-composed URL resolves to the public
ngrok hostname automatically as long as `ForwardedHeaders` is honouring `X-Forwarded-Host` (see
[forwarded-headers.md](forwarded-headers.md)).

## A note on cloud vs local installs

A fuller cloud/hosted DW install may already include `StaticLinkManager` out of the box; local
`dw10-suite` template installs do not. If you're comparing a local host against a hosted one and find
`StaticLink*` endpoints missing locally, the AppStore page in admin is where to install it — then run
the install + host-restart cycle above.

## Demo-time troubleshooting

| Symptom | Likely cause |
|---|---|
| BC's "show PIM product page" silent failure; `StaticLinkSave` returns 400 `Unknown command` | AddIn not installed |
| Same but 500 `TypeInitializationException` | AddIn installed, host not restarted |
| Save returns 200 but BC's webview shows blank/error | Different layer — inspect what URL BC actually loaded via the ngrok inspector (`127.0.0.1:4040`); could be `ForwardedHeaders` not honouring `X-Forwarded-Host` (see [forwarded-headers.md](forwarded-headers.md)) |
