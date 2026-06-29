# Foundational candidate → dw-extend-mcp-tools

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 Backend MCP knowledge — installing the AddIn, the
> auth model, headless token+config provisioning, and the behaviour of MCP create/update tools — staged
> here for a future fold-up into `dw-extend-mcp-tools`. No demo/customer content. When folded, move this
> body into `dw-extend-mcp-tools` and re-target the pointers in the demo skills. Until then, the demo
> skills reference this file.

This is the platform-level knowledge for the Dynamicweb Backend MCP server (`Dynamicweb.MCP`,
exposed at `/admin/mcp`): how to install it, how its auth works, how to provision tokens and configs in
code, and what its create/update tools actually do to the data model.

## 1. Installing the Backend MCP AddIn — NuGet PackageReference (default), AppStore (last resort)

**Default: install the AddIn from NuGet** by adding the package to the host csproj:

```xml
<PackageReference Include="Dynamicweb.MCP" Version="<version>" />
```

Rebuild and restart. The AddIn registers **at host startup**, so `/admin/mcp` flips from 404 to live
with no AppStore click. The host's net10 TFM requirement still applies — the loader's runtime check runs
regardless of how the package arrived (see [`setup-install.md`](setup-install.md) §2).

This is the canonical route for an agent-driven build: deterministic, scriptable, and idempotent (just a
csproj edit), and it sidesteps a flaky UI path — the AppStore "Available apps" grid is a virtualized
component that browser automation struggles to drive reliably. It also aligns with the admin-UI-as-
verification-only discipline (§4): driving the AppStore via automation to install the AddIn treats the
admin UI as an action surface; a `PackageReference` does not.

Pin the version deliberately — `Dynamicweb.MCP` is a beta-track package, and the version must be
compatible with the Suite version the host resolves.

**Last resort: the admin AppStore.** Only when you genuinely cannot edit the host csproj (e.g. a locked,
already-deployed host). Don't drive that install via browser automation — ask the user to click it.

## 2. Auth model — prefer API Key over Claude.ai OAuth

The Backend MCP plugin exposes four auth handlers in `McpAuthMiddleware`: `ApiKey`, `BearerToken`
(OAuth-issued), `Jwt`, `OAuthClient`. The admin UI surfaces two as first-class choices: **API Key** and
**Claude.ai** (the latter is the OAuth + Dynamic Client Registration flow used by claude.ai's hosted
client).

For a programmatic / local client, **API Key is strictly better**:

- **Restart-resilient.** Token validation hits `AccessUserToken` (DB) on every request. When the host
  bounces, the next MCP call revalidates the bearer against the DB row — no interactive re-authorization,
  no "token expired" mid-flow.
- **No client to register.** OAuth/Claude.ai uses Dynamic Client Registration: each client registers
  itself as an OAuth client bound to a session; host restarts and client restarts both interrupt that
  binding. API Key has no client state at all.
- **Same model as the Management API.** Both ride `AccessUserToken` — same `CLAUDE.<hex>` shape, same
  storage, same lifecycle.

Use Claude.ai OAuth only when connecting the hosted claude.ai web client (which can't read a local MCP
config file). The `requires re-authorization (token expired)` failure mid-flow is the OAuth path
talking — switch the config to API Key to make it go away.

## 3. The two `AccessUserToken` rows

A typical DW10 install that an agent drives has **two** bearer tokens, both `CLAUDE.<hex>`-shaped rows in
`AccessUserToken`:

| Token | Issued from | Used for |
|---|---|---|
| **MCP API key** | Admin UI → Settings → Integration → MCP configurations → New (Authentication method = API Key). | `Authorization: Bearer …` header against `/admin/mcp`. Validated against `AccessUserTokenHash` by `McpAuthMiddleware`. |
| **Management API token** | Admin UI → Settings → System → Developer → API keys → New. | `Authorization: Bearer …` header on `/admin/api/...` calls. |

These are distinct rows. The MCP API key is bound to the MCP configuration via `McpConfigurationTokenId`
— established by the admin UI on save, or in code by `McpConfigurationService.LinkToken` (§4). The
Management API token is the unconstrained admin-API key. Don't reuse one for the other without verifying
empirically — the validation paths differ.

## 4. Headless provisioning — create the token + MCP config in code

When the admin UI isn't reachable (a fully headless build / automated provisioning), create both the API
token and the MCP configuration **in code** — e.g. a one-shot `Program.cs` maintenance branch run
*inside the built host* (after `app.UseDynamicweb()`, so DI is live; see
[`../../../dw-extend-csharp-api/SKILL.md`](../../../dw-extend-csharp-api/SKILL.md)). Three pieces, and
the third is the non-obvious one:

1. **Issue the token.** `TokenService.TryCreateToken(new ApiTokenRequestModel { Name = …, Prefix =
   "CLAUDE", ExpiryDate = … }, user)` returns the **unhashed** token; the DB stores only the hash in
   `AccessUserToken`. The public-facing bearer is `CLAUDE.<secret>` — capture it now, it can't be
   recovered later (same as the admin-UI "shown once" behaviour).
2. **Create the MCP configuration.** Insert an `McpConfiguration` row (`Name`, `TokenId`,
   `AllowEverything = 1` for full access — the headless equivalent of `Access = Full access`).
3. **Bind the token to the config through the service — not raw SQL.** A raw `McpConfigurationCredential`
   insert does **NOT** satisfy the auth path; the request still returns `401`. Call
   `McpConfigurationService.LinkToken(configId, tokenId, user)`. That class is **internal**, so invoke it
   by reflection, resolving the instance from the live DI container:

   ```csharp
   var asm = Assembly.Load("Dynamicweb.MCP");
   var t   = asm.GetType("Dynamicweb.MCP.Configuration.Services.McpConfigurationService");
   var svc = app.Services.GetService(t) ?? Activator.CreateInstance(t, true);
   t.GetMethod("LinkToken").Invoke(svc, new object[] { configId, tokenId, user });
   ```

**Then restart the host.** The MCP configuration is cached at startup, so a freshly inserted/bound config
is invisible to `/admin/mcp` until the next boot. (The same startup-cache rule applies to the admin
password and the token — direct SQL writes don't take until restart; for MCP credentials a raw insert is
*insufficient even after restart*, hence the `LinkToken` call.)

> **Brittleness warning.** `McpConfigurationService` is an internal type invoked by reflection — its
> namespace, method name, and signature can change between DW10 releases without notice, and the
> `Dynamicweb.MCP` version pin matters. Prefer the admin-UI route whenever the UI is reachable; use this
> code path only for genuinely headless installs, and re-verify the type/method names against the
> `Dynamicweb.MCP` version in use.

## 5. What MCP create/update tools do to the data model

MCP create-paths (`save_pages`, `save_groups`, product/order/user creates, etc.) call DW's **domain
services** — the same services an admin-UI click invokes. A single MCP create therefore triggers ALL the
bookkeeping a UI click would: ItemRelation cloning, ItemList propagation, sibling-page linking, cache
invalidation, index refresh, child-row creation, validation. This is *why* MCP is the default create
surface and why raw SQL `INSERT` is the last resort — SQL bypasses every service, misses the bookkeeping,
and creates orphans / stale caches. (The admin UI is a SPA client of `/admin/api/...` — every click is an
Admin API call underneath — so the Management API reaches the same services as a second transport, and
"this only exists in the UI" means the endpoint hasn't been found yet, not that one is missing.)

### Silent no-ops — a success status does not guarantee the field was applied

A `succeeded` / `status: ok` response from an MCP or Management API write does NOT guarantee every field
you sent was persisted. Known version-pinned cases where the call reports success, bumps `updatedDate`,
and silently drops part of the input:

| Tool (surface) | What gets silently dropped | Verified | Working fallback |
|---|---|---|---|
| MCP `save_pages` (update path) | `menuText` — the response even echoes the OLD value | DW 10.25.x | SQL `UPDATE Page SET PageMenuText` + host restart (the nav tree caches menu text) |
| Management API `ParagraphSave` | `contentItem.groups[].fields[].value` mutations — the `ItemType_*` column never updates | DW 10.25.x | MCP `set_item_field_values` first; SQL UPDATE last resort. `ParagraphSave` IS still correct for paragraph-level scalars (Header, Sort, GridRow, Template) |

**Rule:** after any demo-critical update through MCP / Management API, round-trip it — read the value back
through a different surface (or curl the rendered page) before declaring it done. When a silent no-op is
confirmed, the SQL fallback is sanctioned; note the cache that needs flushing. (The content-author's view
of these same two no-ops — framed as paragraph/page save bookkeeping — is in
[`content-modelling.md`](content-modelling.md).)
