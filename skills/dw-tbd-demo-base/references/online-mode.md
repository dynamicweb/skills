# online-mode.md — building a demo on a hosted (cloud) install

> Owns the **online/cloud variant** of the demo-base flow: what changes when the demo runs on a vendor-hosted DW10 install reached only by URL + Admin API bearer key — no local scaffold, no SQL, no filesystem, no host-process control. Validated end-to-end on a DW 10.25.x hosted install (2026-06-10): styles, PIM model, shop/channel, products with color variants, content rebuild, and a cheat-sheet page were all built through the Management API alone.
>
> Local installs remain the default; this reference is the fork target from [SKILL.md](../SKILL.md) "Environment fork". The four always-on guardrails (customisations ledger, customer-context read-only, demo philosophy, discover-from-project-files) apply unchanged.

## Recognising online mode

You are in online mode when the engagement hands you a site URL (`https://<host>/`) and a Management API bearer key (`CLAUDE.<hex>`) instead of a machine to scaffold on. Canonical-flow deltas:

| Canonical step (local) | Online mode |
|---|---|
| setup-checks (SDK, SQL Express, vault, MSDTC) | Skip — nothing to install. The vault is still useful read-only if present (see "dw10source as binder disambiguator" below). |
| scaffold (`dotnet new dw10-suite`) | Skip. The per-demo folder still gets created locally for `CUSTOMISATIONS.md`, `customer-context/`, `extracts/`, `scripts/`, screenshots. |
| MCP wiring + TLS bypass | Replaced by the **probe** below. No TLS bypass needed (real certificates). |
| Browser MCP install | Unchanged — Playwright is still the verification surface. |
| Guardrail artefacts | Unchanged. |
| Host lifecycle authority | N/A — you cannot restart a hosted site. Use the **cache-refresh-as-restart** recipe below wherever a sister-skill recipe says "restart the host". |

## Probe order at session start

Tool availability on hosted installs is **version-dependent and a moving target** — hosted sites track the DW10 release train, and the MCP surface in particular varies by version. Never assume; probe:

1. **Management API**: `GET https://<host>/Admin/Api/api.json` with `Authorization: Bearer CLAUDE.<hex>`. Returns the full OpenAPI catalogue (~1,900 operations on 10.25.x) including the platform version in `info.version`. Save it locally — it is the working map for everything below.
2. **MCP**: `POST https://<host>/admin/mcp` with a JSON-RPC `initialize`. A 404 plus zero MCP-related operations in the OpenAPI spec means the install doesn't expose MCP — fall through to the Management API as primary surface. If MCP responds, the normal surface priority applies and most of this file's API recipes become fallbacks.
3. **Admin UI via Playwright**: needs interactive credentials (ask the user). Third surface, for the rare operation the API doesn't expose.

**Surface priority in online mode:** MCP (if the probe finds it) → Management API → admin UI via Playwright → **ask the user**. There is no SQL surface, ever — the "last resort" rung of the local surface-priority table simply does not exist here, which also means every SQL-based sister-skill recipe needs the API equivalent from this file.

## Management API recipe pack (validated DW 10.25.x)

The Management API hits the same DW domain services as MCP and the admin UI, so bookkeeping (ItemRelation cloning, cache invalidation, notifications) fires correctly. The binder, however, has sharp edges:

### Create-vs-update semantics
Most `*Save` commands UPDATE when `Id` is set and CREATE when `Id` is empty (the server assigns `SHOPxx` / `GROUPxx` / `PRODxx` / field ids — capture them from the response `model.id` or `modelIdentifier`). Category product fields create with `Id: ""` + `SystemName: "<field id>"` + `CategoryId`. Posting a chosen `Id` to a save command returns `notFound` ("Shop not found", "Field not found") — that is the create/update fork talking, not a missing entity.

### Binder asymmetries (GET returns strings, POST wants objects)
- `SelectedImage` fields (logos, favicons, posters, product images): GET serialises the value as a plain path string, but the save binder needs `{"Id": "/Files/...", "Name": "<file>", "Ratio": "", "FocalX": 0, "FocalY": 0}` — the `Path` property is obsolete; **`Id` carries the path**. A string (or `Path`-shaped object) saves silently as empty.
- `ButtonData` fields: GET returns a JSON *string*; the binder wants the *object* (`{"Label": ..., "Link": ..., "LinkType": "page", "Style": "primary"}`).
- Some commands put properties at BOTH the command level and inside `Model` (e.g. `VariantCombinationCreate` needs `ProductId` and the cache key in both places). When a payload bounces with "value is required" for a field you sent, mirror it into/out of `Model`.

### dw10source as binder disambiguator
When a payload shape isn't obvious from the OpenAPI spec, read the command class in the `dw10source` vault slot (`Dynamicweb.*.UI/Commands/**/<Name>Command.cs`). Five minutes in the source beats an hour of payload guessing — it resolved every binder mystery in the validation build (SelectedImage `Id`, the create/update fork, the variant wizard below).

### File upload
`POST /Admin/Api/Upload`, multipart form: field `path` = **relative** directory (no leading slash — leading-slash paths are rejected as "outside allowed root"), repeated `files` fields for the payload. The target directory must already exist physically. **`DirectorySave` is rename-only** (returns ok, creates nothing) — create folders via `DirectoryCopy` of any small existing folder to the new path, then `DirectoryEmpty` on it.

### Product images
The default "Images" asset category accepts `bmp/jpeg/jpg/png/tiff` — **not webp**; convert before upload. Name files `{ProductNumber}.<ext>` in the shop's image folder so the category's `{productnumber}` auto-match rule attaches them, and/or attach explicitly via `AssetAddToMultipleProducts {Model: {ProductIds, AssetCategoryGroupId, FilesToAttach, IsDefault}}`. The product model's `image` property is computed — setting it via `ProductSave` is a no-op.

### Variants without SQL
The structural-model recipe's SQL steps (per-variant `EcomProducts` rows) are fully covered by the API chain:
1. `VariantGroupSave` (Id empty creates) + `VariantOptionSave` per option — set `Color` (hex) on options and Swift's PDP renders live swatches.
2. `VariantGroupAdd {ProductId, Ids: [groupId]}`.
3. **`VariantCombinationSave {ProductId, VariantCombinationSelectionCacheKey, Ids: [<variantIds>]}`** — for a single axis the variant ids are the bare option ids. This command persists the combinations AND runs `ExtendAllVariants` (creates the per-variant product rows), clears the variant caches, and rebuilds the product's index entry. Skip `VariantCombinationCreate` — it only fills a UI-wizard cache and persists nothing.
4. Per-variant stock: round-trip `ProductById?Id=<id>&VariantId=<vid>` → set `stock`/`neverOutOfStock` → `ProductSave`. Variants default to 0 stock and render a disabled add-to-cart.

### Cache refresh = the online host restart
Wherever a recipe says "restart the host" (variant seeding, BOM inserts, asset bulk loads), the online equivalent is:
1. `GET /Admin/Api/GetServiceCaches` → collect the `modelIdentifier`s of the Ecommerce Product/Stock/Price/Variant services.
2. `POST /Admin/Api/CacheInformationsRefresh {"Ids": [<those ids>]}`.

This fixed a stale disabled add-to-cart after variant seeding within seconds. (`CacheInformationRefresh` — singular — takes one `CacheTypeName` for targeted flushes; the pim-skill access-surfaces matrix covers the local use of the same endpoints.)

### Content editing
- Paragraph item fields save through `ParagraphSave` round-trips of `GetParagraphById` (mind the binder asymmetries above). String/HTML fields persist directly.
- **`ShowParagraph` cannot be changed via the API** — both the round-trip and `ParagraphChangeActive` silently no-op (observed on copied/master-linked rows). Hide by `ParagraphDelete {DeleteWithRows: true, Ids: [...]}` or by blanking fields — consistent with the cheat-sheet recipe's standing caveat about `active=false`.
- `PageCopy` model: `DestinationType` is `folder|section|website`. **Copies inherit the source's `shortCut`** — Swift baseline About-family pages carry shortcut redirects, so a copied page can 301 elsewhere (`X-DWAPP-REDIR-REASON` header names the middleware). Clear `shortCut` on the copy.
- Grid rows: `GridRowCopy {PageId, Id}` (copy a known row to the target page) is far more reliable than `GridRowCreate`, whose definition lookup is fussy about grid naming. Then point the paragraph's `gridRowId`/`gridRowColumn` at the copied row.

### Known API gaps (verified in source — do not debug, route around)
- **`ShopSave` never persists `Model.Languages`** (only `CompletionLanguages`); `EcomShopLanguageRelation` cannot be written through this API version. A shop created online has no language relation until someone ticks it in the admin UI — flag it as a hand-off step.
- User passwords aren't settable through `UserSave` — backend users created via API need their password set in the admin UI.

## What stays the same

- **Guarded writes**: the customisations ledger matters *more* online — code customisations are impossible, so the ledger should finish empty and that is itself the pitch beat.
- **Customer-context read-only**, demo philosophy (go deep not wide), and the discover-from-project-files rule (URL, key, area ids from chat/files — never hardcoded) all apply unchanged.
- **Shared-install discipline**: hosted demos often share the install with reference sites and other areas. Agree the untouchable area ids up front, keep all writes scoped to the demo's own area/shop/groups, and treat **global** settings (currencies, asset categories, product fields without a category) as shared state — note any global change in the demo's RESUME so other areas' owners can see it.
