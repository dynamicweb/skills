# The Backend MCP server — install, auth, headless provisioning, write behaviour

## Contents

- [1. Installing the Backend MCP AddIn](#1-installing-the-backend-mcp-addin--appstore-first-csproj-only-as-a-user-approved-escape-hatch)
- [2. Auth model — prefer API Key over Claude.ai OAuth](#2-auth-model--prefer-api-key-over-claudeai-oauth)
- [3. The two AccessUserToken rows](#3-the-two-accessusertoken-rows)
- [4. Headless provisioning — create the token + MCP config in code](#4-headless-provisioning--create-the-token--mcp-config-in-code)
- [5. What MCP create/update tools do to the data model](#5-what-mcp-createupdate-tools-do-to-the-data-model)

This is the platform-level knowledge for the Backend MCP server — the AppStore app **Truvio Commerce
MCP** (package `Truvio.Commerce.MCP`, formerly `Dynamicweb.MCP`), exposed at `/admin/mcp`: how to
install it, how its auth works, how to provision tokens and configs in code, and what its create/update
tools actually do to the data model.

## 1. Installing the Backend MCP AddIn — AppStore first, csproj only as a user-approved escape hatch

**The app was renamed.** The Backend MCP now ships as **Truvio Commerce MCP**, package id
**`Truvio.Commerce.MCP`**. The old **`Dynamicweb.MCP`** id is frozen at its last pre-rename version. It
still resolves on nuget.org, and that is exactly what makes it dangerous: an agent that writes the id it
*remembers* gets a green restore, a green build, and a stale AddIn — with no error anywhere to react to.
The endpoint is unchanged (`/admin/mcp`), so the stale install looks right until a tool is missing.

**Rule: an app that is available in the AppStore is installed from the AppStore.** That covers the
Backend MCP, the PIM for Business Central connector and `StaticLinkManager`. A hand-written
`<PackageReference>` for such an app is a defect, not a shortcut — package id and version must come from
the AppStore listing or a live resolve, never from recall. If you find
`<PackageReference Include="Dynamicweb.MCP" ... />` in a host csproj, remove it and install from the
AppStore instead.

**The route:** admin → **Settings → AppStore → Available apps** → *Truvio Commerce MCP* → install, then
restart the host; `/admin/mcp` flips from 404 to live. Under browser automation expect retries — the
"Available apps" grid is a virtualized component. The host's net10 TFM requirement applies regardless of
how the package arrives (see [`dw-setup-install`](../../dw-setup-install/SKILL.md), reference
`install-anatomy.md` §2); a net8 host makes the install a silent no-op.

**Escape hatch — csproj `PackageReference`, and only on an explicit user choice.** When the AppStore
route genuinely cannot be completed (a locked, already-deployed host; the app not listed; the grid
unreachable after retries), do **not** quietly pin a package. Stop and tell the user, in these terms:

- which AppStore route failed, and how;
- that **the AppStore version could not be resolved**, so the pin cannot be guaranteed to match what the
  AppStore would have installed;
- the exact id and version you propose, and where that version came from — a live resolve
  (`dotnet package search Truvio.Commerce.MCP --prerelease`) or the user, never memory.

Only on an explicit "yes" write the reference, resolved id and version, never a remembered one:

```xml
<PackageReference Include="Truvio.Commerce.MCP" Version="<resolved version>" />
```

Rebuild and restart; the AddIn registers at host startup. Pin deliberately — this is a beta-track
package and the version must be compatible with the Suite version the host resolves.

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
[`dw-extend-csharp-api`](../../dw-extend-csharp-api/SKILL.md)). Three pieces, and
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
   // The MCP assembly name follows the installed package -- `Truvio.Commerce.MCP` since the
   // rebrand, `Dynamicweb.MCP` on a host installed before it. Resolve it, never hardcode it.
   var asm = AppDomain.CurrentDomain.GetAssemblies()
       .First(a => a.GetName().Name is "Truvio.Commerce.MCP" or "Dynamicweb.MCP");
   var t   = asm.GetTypes()
       .First(x => x.FullName!.EndsWith(".Configuration.Services.McpConfigurationService"));
   var svc = app.Services.GetService(t) ?? Activator.CreateInstance(t, true);
   t.GetMethod("LinkToken").Invoke(svc, new object[] { configId, tokenId, user });
   ```

**Then restart the host.** The MCP configuration is cached at startup, so a freshly inserted/bound config
is invisible to `/admin/mcp` until the next boot. (The same startup-cache rule applies to the admin
password and the token — direct SQL writes don't take until restart; for MCP credentials a raw insert is
*insufficient even after restart*, hence the `LinkToken` call.)

> **Brittleness warning.** `McpConfigurationService` is an internal type invoked by reflection — its
> namespace, method name, and signature can change between DW10 releases without notice, and so can the
> assembly name itself (the rebrand moved it from `Dynamicweb.MCP` to `Truvio.Commerce.MCP`), which is
> why the snippet resolves the assembly instead of naming it. Prefer the admin-UI route whenever the UI
> is reachable; use this code path only for genuinely headless installs, and re-verify the type/method
> names against the MCP version actually installed.

## 5. What MCP create/update tools do to the data model

MCP create-paths (`save_pages`, `save_groups`, product/order/user creates, etc.) call DW's **domain
services** — the same services an admin-UI click invokes. A single MCP create therefore triggers ALL the
bookkeeping a UI click would: ItemRelation cloning, ItemList propagation, sibling-page linking, cache
invalidation, index refresh, child-row creation, validation. This is *why* MCP is the default create
surface and why raw SQL `INSERT` is the last resort (local installs only) — SQL bypasses every service, misses the bookkeeping,
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
| MCP `save_pages` (create + update) | `urlName` — the slug you pass is **ignored**; DW derives the slug from `menuText` instead | DW 10.27.x | Set the intended `menuText` (the slug follows it), or SQL `UPDATE Page SET PageUrlName` + host restart. Don't expect `urlName` to pin the slug independently. |
| Management API `ParagraphSave` | `contentItem.groups[].fields[].value` mutations — the `ItemType_*` column never updates | DW 10.25.x | MCP `set_item_field_values` first; SQL UPDATE last resort (local install only). `ParagraphSave` IS still correct for paragraph-level scalars (Header, Sort, GridRow, Template) |
| MCP `delete_area`, `delete_users`, `delete_paragraphs` | The **entire delete** — `succeeded:1` returned, row still in the DB afterwards | DW 10.27.x + 10.28.1-Pre | SQL `DELETE` (children first: paragraphs → grid rows → pages → area), then restart for the page-tree cache. Always round-trip a delete with a `SELECT COUNT(*)` |
| MCP `build_product_index` (+ `wait_for_product_index`) | The **target**. It builds its own default repository/index pair (`Products`/`Products` — its own success message says so) while the solution's queries commonly read a *different* instance (`ProductsBackend\|Products.index`). The index the queries read is never touched, so freshly written values stay invisible across repeated rebuilds and a recycle, and the earlier reading of this row ("no Lucene segments are written") was the same incident diagnosed from the wrong end | DW 10.26.x–10.28.x | Read `sourceIndex` off the queries, then `POST /Admin/Api/BuildIndex {Repository, IndexName, BuildName}` for **that** index, resolving `BuildName` from `IndexBuildersByRepositoryAndIndexName`. Verify with a query whose predicate depends on the freshly written field — its count must move off "matches everything" — not with the tool's status or a marker file |
| MCP `update_users` | A `password` property — the schema has no password field, and an extra `password` property is accepted (`succeeded:1`, `updatedOn` bumped) and dropped | DW 10.28.1-Pre | There is no MCP/API password surface at all — use the plaintext escape hatch documented in [`dw-users-permissions`](../../dw-users-permissions/SKILL.md), reference `permission-layers.md` §13 |
| MCP `patch_products_safe` against a **variant** `EcomProducts` row (`id` + `variantId`) | The **entire patch** — the success items echo the requested values (number, price, isActive) because the echo is the input model, not a post-write read; the variant row's columns stay NULL. The tool writes to the variant *combination* model, not the variant product row (same family as `create_variant_combinations` leaving `ProductActive`/`ProductPrice` NULL — see [`dw-pim-modelling`](../../dw-pim-modelling/SKILL.md), reference `structural-model.md` §2.5) | DW 10.27.x | SQL `UPDATE` on the variant `EcomProducts` row is the canonical variant-enrichment surface. Verify immediately: `SELECT ProductNumber FROM EcomProducts WHERE ProductId=@p AND ProductVariantId=@v` — NULL means the write didn't land |
| MCP `copy_page` with `destinationParentPageId=0` (top-level copy) | The **implied area** — the copy lands as a top-level page of area 1, not the source page's area, when no `areaId` is passed | DW 10.27.x | Always pass `areaId` explicitly on top-level copies; confirm the response's `areaId` equals the requested area |
| MCP `set_paragraph_item_fields` | Any field system name that does **not exist on the item type**. The verb counts the fields it was ASKED to write, not the fields it MATCHED, so `{"succeeded":1,"failed":0,"errors":[]}` comes back for a typo or a guessed name and the paragraph renders nothing | DW 10.26.12 | Read the field list from `get_paragraph_item_field_values` (or `Files/System/Items/ItemType_<name>.xml`) BEFORE writing, then read the specific field back with its specific value |
| MCP `save_paragraphs` | `active` (the response body itself echoes `active: true` back, with a minimal model and with a full model alike; inert, not destructive) | DW 10.28.5 | `hideForPhones` + `hideForTablets` + `hideForDesktops`, which DO write; or `GridRow.GridRowActive = 0` when the paragraph is the sole occupant of its row. `save_paragraphs` DOES write `itemType`, and that write re-mints the item instance with default field values, so every field must be re-stated afterwards |
| MCP `save_pages` / `save_paragraphs` (create path, `id:0`) | The returned **`id`**, which is always `0`. The create path echoes the INPUT model back with `succeeded`/`failed` counts, not the persisted row, so anything built on that id silently attaches to nothing. The only key that survives is `itemId`, the id of the freshly minted item-type instance | DW 10.28.4 | Resolve the real id through the item instance: `SELECT PageId FROM Page WHERE PageAreaId=<a> AND PageItemId='<itemId>'` (`ParagraphItemId` for paragraphs). `copy_page` / `copy_paragraph` DO return real ids — only the create path lies |
| MCP `copy_page` on an ordinary content page | The **whole call** — it refuses with `"Standard pages are Not allowed."` for every destination (top level, a page-preset folder, the source page's own parent), and the message names neither side. The wrapper appears restricted to template/preset pages | DW 10.28.4 | The restriction is the MCP tool's, not the platform's: `GET /Admin/Api/NewPageInfoForCopy?SourcePageId=..&DestinationParentPageId=..` then `POST /Admin/Api/PageCopy` copies an ordinary `Swift-v2_Page` including its subtree and language mirrors (measured DW 10.28.1). Where the wrapper is the only surface, build with `save_pages` and assemble content with `GridRowCopy` + `copy_paragraph` |
| MCP `set_page_menu` (`showInMenu`) | The intent. The verb documents `showInMenu` as "the page's ShowInMenu flag"; **there is no `PageShowInMenu` column on the schema** and the write lands on `PageActive`, so `showInMenu:false` unpublishes the page while `PageShowInLegend` (what Swift navigation reads) stays as it was | DW 10.28.4 | Use `set_page_menu` for `showInSitemap` only. For the navigation flag, `GetPageById` then `PageSave` a COMPLETE model with `ShowInLegend:false` — measured to flip alone with zero collateral on 10.28.1 |
| MCP `add_product_image` with a `groupId` | Nothing is dropped, but it is an **ADD, not a move**: the same `filePath` under a new `groupId` mints a second detail row and only flips `isDefault`. It also accepts a `filePath` that does not exist on disk and returns a healthy `detailId` | DW 10.26.12 | Follow every add with `remove_product_image` on details outside the target group, and check the path against `list_files` first. Read back `GroupedAssetsByProductId` and assert exactly one `isDefault` per product |

### A wrong ARGUMENT SHAPE surfaces as a hintless invocation error

Distinct from the silent no-ops above: the tool throws, nothing is written, and the message is the bare
`"An error occurred invoking '<tool>'."` with no field name and no validation detail. That reads as the
platform rejecting a value, so the shape is the last thing anyone checks. Two measured cases, both from
the schema in `tools/list`:

| Tool | Working shape | Failing shape |
|---|---|---|
| `patch_products_safe` `customFields` | `[{id: "<full path>", value: "<string>"}]`, both members required, both **strings** | `[{systemName: ..., value: 0}]`, which is the shape `/Admin/Api/ProductById` ECHOES when you read the same fields back |
| `set_paragraph_item_fields` `fields` | a MAP: `{Layout:'tabs', Title:'Specifications'}` (`additionalProperties: string`) | a list of `{systemName, value}` objects |

For `customFields` the key is the full `ProductCategory|<cat>|<field>` path and **every value must be
stringified**, numbers included; a multi-select list is a **comma-joined string**, not a JSON array
(`value:["swine","poultry"]` fails, `value:"swine,poultry"` works). Encode with one helper before the
call, `Array.isArray(v) ? v.join(",") : String(v)`, and read back per batch: a 121-cell enrichment run
reported the generic error for every batch and wrote 0 of 121 cells, and there was nothing in the
response to point at the mistake.

**Rule:** after any critical update through MCP / Management API, round-trip it — read the value back
through a different surface (or curl the rendered page) before declaring it done. When a silent no-op is
confirmed, the SQL fallback is sanctioned; note the cache that needs flushing. (The content-author's view
of these same save no-ops — framed as paragraph/page save bookkeeping — is in
[`dw-content-modelling`](../../dw-content-modelling/SKILL.md), reference `modelling-discipline.md`.)
