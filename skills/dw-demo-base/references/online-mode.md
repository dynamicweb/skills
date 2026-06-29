# online-mode.md — building a demo on a hosted (cloud) install

> Owns the **online/cloud variant** of the demo-base flow: what changes when the demo runs on a vendor-hosted DW10 install reached only by URL + Admin API bearer key — no local scaffold, no SQL, no filesystem, no host-process control. Validated end-to-end on a DW 10.25.x hosted install: styles, PIM model, shop/channel, products with color variants, content rebuild, and a cheat-sheet page were all built through the Management API alone.
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

The Management API hits the same DW domain services as MCP and the admin UI, so bookkeeping (ItemRelation cloning, cache invalidation, notifications) fires correctly. The binder has sharp edges. Most of these recipes are vendor-generic Management API mechanics that the online build leans on more heavily (no MCP, no SQL) — they are owned by the foundational candidates, not by this online fork:

- **Create-vs-update fork** (UPDATE when `Id` set, CREATE when empty; `notFound` is the fork talking), the **`SelectedImage` binder asymmetry**, **product images** (`AssetAddToMultipleProducts`, no webp, computed `image`), the **variant chain** (`VariantGroupSave` → `VariantCombinationSave`/`ExtendAllVariants`, skip `VariantCombinationCreate`), and the **`ShopSave` languages gap** → [`foundational/commerce-catalog.md`](foundational/commerce-catalog.md) §2.14.
- **Paragraph / page / grid-row editing** (`ParagraphSave` round-trips, the `ButtonData` object binder, `ShowParagraph` can't be set, `PageCopy` inherits `shortCut`, `GridRowCopy` over `GridRowCreate`) → [`foundational/content-modelling.md`](foundational/content-modelling.md) "Editing page / paragraph / grid-row content through the Management API".
- **`UserSave` can't set passwords** → [`foundational/users-permissions.md`](foundational/users-permissions.md) §13.

Some commands also mirror a property at BOTH the command level and inside `Model` (e.g. `VariantCombinationCreate`); when a payload bounces with "value is required" for a field you sent, mirror it into/out of `Model`.

### dw10source as binder disambiguator
When a payload shape isn't obvious from the OpenAPI spec, read the command class in the `dw10source` vault slot (`Dynamicweb.*.UI/Commands/**/<Name>Command.cs`). Reading the source resolved every binder mystery in the validation build (SelectedImage `Id`, the create/update fork, the variant wizard).

### File upload (online provisioning)
`POST /Admin/Api/Upload`, multipart form: field `path` = **relative** directory (no leading slash — leading-slash paths are rejected as "outside allowed root"), repeated `files` fields for the payload. The target directory must already exist physically. **`DirectorySave` is rename-only** (returns ok, creates nothing) — create folders via `DirectoryCopy` of any small existing folder to the new path, then `DirectoryEmpty` on it.

### Cache refresh = the online host restart (the load-bearing online delta)
Wherever a sister-skill recipe says "restart the host" (variant seeding, BOM inserts, asset bulk loads), there is no host to restart online. The equivalent is:
1. `GET /Admin/Api/GetServiceCaches` → collect the `modelIdentifier`s of the Ecommerce Product/Stock/Price/Variant services.
2. `POST /Admin/Api/CacheInformationsRefresh {"Ids": [<those ids>]}`.

This fixes a stale disabled add-to-cart after variant seeding. (`CacheInformationRefresh` — singular — takes one `CacheTypeName` for targeted flushes; the pim-skill access-surfaces matrix covers the local use of the same endpoints.)

## What stays the same

- **Guarded writes**: the customisations ledger matters *more* online — code customisations are impossible, so the ledger should finish empty and that is itself the pitch beat.
- **Customer-context read-only**, demo philosophy (go deep not wide), and the discover-from-project-files rule (URL, key, area ids from chat/files — never hardcoded) all apply unchanged.
- **Shared-install discipline**: hosted demos often share the install with reference sites and other areas. Agree the untouchable area ids up front, keep all writes scoped to the demo's own area/shop/groups, and treat **global** settings (currencies, asset categories, product fields without a category) as shared state — note any global change in the demo's RESUME so other areas' owners can see it.
