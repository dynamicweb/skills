# online-mode.md — building on, and publishing to, a hosted (cloud) install

> Owns the **online/cloud variant** of the demo-base flow: what changes when the demo runs on a vendor-hosted DW10 install reached only by URL + Admin API bearer key — no local scaffold, no SQL, no filesystem. Two shapes are covered: **building** a demo directly on a hosted install (Management API only), and **publishing** an existing local demo onto one (the migration playbook at the bottom).
>
> Local installs remain the default; this reference is the fork target from [SKILL.md](../SKILL.md) "Environment fork". The four always-on guardrails (customisations ledger, customer-context read-only, demo philosophy, discover-from-project-files) apply unchanged.

## Contents

- [Recognising online mode](#recognising-online-mode)
- [Probe order at session start](#probe-order-at-session-start)
- [Management API recipe pack](#management-api-recipe-pack-validated-dw-1025x)
  - [dw10source as binder disambiguator](#dw10source-as-binder-disambiguator)
  - [File upload — and why an "ok" upload can change nothing](#file-upload--and-why-an-ok-upload-can-change-nothing)
  - [Flush first; a cloud install CAN be restarted](#flush-first-a-cloud-install-can-be-restarted)
- [Publishing an existing local demo to a hosted install](#publishing-an-existing-local-demo-to-a-hosted-install)
  - [Transport map](#transport-map)
  - [Order of operations](#order-of-operations)
  - [Deserialize semantics that decide the outcome](#deserialize-semantics-that-decide-the-outcome)
  - [What never rides the content export](#what-never-rides-the-content-export)
  - [Verify with a browser, not just status codes](#verify-with-a-browser-not-just-status-codes)
- [What stays the same](#what-stays-the-same)

## Recognising online mode

You are in online mode when the engagement hands you a site URL (`https://<host>/`) and a Management API bearer key (`CLAUDE.<hex>`) instead of a machine to scaffold on. Canonical-flow deltas:

| Canonical step (local) | Online mode |
|---|---|
| setup-checks (SDK, SQL Express, MSDTC) | Skip — nothing to install. A local DW10 source clone, if present, is still useful read-only (see "dw10source as binder disambiguator" below). |
| scaffold (`dotnet new dw10-suite`) | Skip. The per-demo folder still gets created locally for `CUSTOMISATIONS.md`, `customer-context/`, `extracts/`, `scripts/`, screenshots. |
| MCP wiring + TLS bypass | Replaced by the **probe** below. No TLS bypass needed (real certificates). |
| Browser MCP install | Unchanged — Playwright is still the verification surface. |
| Guardrail artefacts | Unchanged. |
| Host lifecycle authority | You do not own a host process, but a cloud install is **not** un-restartable — drive it through the CloudHosting control files. Work the flush-first ladder below. |

## Probe order at session start

Tool availability on hosted installs is **version-dependent and a moving target** — hosted sites track the DW10 release train, and the MCP surface in particular varies by version. Never assume; probe:

1. **Management API**: `GET https://<host>/Admin/Api/api.json` with `Authorization: Bearer CLAUDE.<hex>`. Returns the full OpenAPI catalogue (~1,900 operations on 10.25.x) including the platform version in `info.version`. Save it locally — it is the working map for everything below.
2. **MCP**: `POST https://<host>/admin/mcp` with a JSON-RPC `initialize`. A 404 plus zero MCP-related operations in the OpenAPI spec means the install doesn't expose MCP — fall through to the Management API as primary surface. If MCP responds, the normal surface priority applies and most of this file's API recipes become fallbacks.
3. **Admin UI via Playwright**: needs interactive credentials (ask the user for them). Verification surface only — build-phase rules apply from the first request on a hosted install, since there is nothing to scaffold.

**Surface priority in online mode:** MCP (if the probe finds it) → Management API → **ask the user** for the rare operation neither exposes. There is no SQL surface, ever — the "last resort" rung of the local surface-priority table simply does not exist here, which also means every SQL-based sister-skill recipe needs the API equivalent from this file. The admin UI stays verification-only, same as every build phase (`surface-priority.md`).

## Management API recipe pack (validated DW 10.25.x)

The Management API hits the same DW domain services as MCP and the admin UI, so bookkeeping (ItemRelation cloning, cache invalidation, notifications) fires correctly. The binder has sharp edges. Most of these recipes are vendor-generic Management API mechanics that the online build leans on more heavily (no MCP, no SQL) — they are owned by the foundational candidates, not by this online fork:

- **Create-vs-update fork** (UPDATE when `Id` set, CREATE when empty; `notFound` is the fork talking), the **`SelectedImage` binder asymmetry**, **product images** (`AssetAddToMultipleProducts`, no webp, computed `image`), the **variant chain** (`VariantGroupSave` → `VariantCombinationSave`/`ExtendAllVariants`, skip `VariantCombinationCreate`), and the **`ShopSave` languages gap** → [`foundational/commerce-catalog.md`](foundational/commerce-catalog.md) §2.14.
- **Paragraph / page / grid-row editing** (`ParagraphSave` round-trips, the `ButtonData` object binder, `ShowParagraph` can't be set, `PageCopy` inherits `shortCut`, `GridRowCopy` over `GridRowCreate`) → [`foundational/content-modelling.md`](foundational/content-modelling.md) "Editing page / paragraph / grid-row content through the Management API".
- **`UserSave` can't set passwords** → [`foundational/users-permissions.md`](foundational/users-permissions.md) §13.

Some commands also mirror a property at BOTH the command level and inside `Model` (e.g. `VariantCombinationCreate`); when a payload bounces with "value is required" for a field you sent, mirror it into/out of `Model`.

**List-command ids are full paths, not names.** Every `*Delete` command that takes an `Ids` array wants the entity's `modelIdentifier` from the matching list query — `/Files/Images/<brand>/logo.png` for a file, `GROUP1|ENU` for a product group, `<child>|<parent>` for a group relation. Passing a bare name returns `status: ok` and deletes nothing. Read one row from the list query and copy the `modelIdentifier` shape before scripting a bulk delete.

### dw10source as binder disambiguator
When a payload shape isn't obvious from the OpenAPI spec, read the command class in a local clone of the DW10 source (location per machine — ask/discover, never hardcode): `Dynamicweb.*.UI/Commands/**/<Name>Command.cs`. Reading the source resolved every binder mystery in the validation build (SelectedImage `Id`, the create/update fork, the variant wizard).

### File upload — and why an "ok" upload can change nothing
`POST /Admin/Api/Upload`, multipart form: field `path` = **relative** directory (no leading slash — leading-slash paths are rejected as "outside allowed root"), repeated `files` fields for the payload. The target directory must already exist physically. **`DirectorySave` is rename-only** (returns ok, creates nothing) — create folders via `DirectoryCopy` of any small existing folder to the new path, then `DirectoryEmpty` on it.

**Upload never overwrites.** When a file of that name already exists, the response is still `{"status":"ok"}` — with the skipped names in `model.duplicates` — and the file on disk is unchanged. Treat `model.duplicates` as a failure, and **delete before re-uploading** so an overwrite actually lands:

```
POST /Admin/Api/FileDelete  {"DirectoryPath":"/Files/<dir>","Ids":["/Files/<dir>/<name>"]}
POST /Admin/Api/Upload      (multipart: path=<dir>, files=<name>)
```

A push that reports `ok` for every batch while silently keeping the target's old templates is the failure this catches — assert on `duplicates`, not on `status`.

### Flush first; a cloud install CAN be restarted
Wherever a sister-skill recipe says "restart the host" (variant seeding, BOM inserts, asset bulk loads), you have no host process — but a cloud install still has a restart surface. Work the ladder:

1. **Targeted flush** — `CacheInformationRefresh` (singular) with one `CacheTypeName`.
2. **Bulk flush** — `GET /Admin/Api/GetServiceCaches` → collect the `modelIdentifier`s → `POST /Admin/Api/CacheInformationsRefresh {"Ids": [...]}`. This clears the stale-read class of symptom: a row written through the API that a later query still reports with its old value (a shop that "doesn't exist", a group tree missing a node), and the stale disabled add-to-cart after variant seeding.
3. **Real restart** — drop a control file in `Files/System/CloudHosting/` (`recycle.txt`, `restart.txt`; `changeversion.txt` also switches release ring). Canonical table: [`dw-setup-config`](../../dw-setup-config/SKILL.md) "cloud control files". Some **global settings do not take effect on a cache flush alone** — a URL-generation change can keep serving the old shape until the app restarts. If a setting reads back correctly from the API but the storefront still renders the old behaviour, restart before diagnosing further.

## Publishing an existing local demo to a hosted install

There is no local→hosted "deploy" in DW10. Publishing a built local demo is a **migration across three transports**, and its failure modes differ from a from-scratch online build. Scope this honestly with the user before starting — it is not a button.

**Align the platform version first.** Put `changeversion.txt` (release ring) in `Files/System/CloudHosting/` and let the site recycle, so source and target run the same DW10 build before any content moves. Serialized content deserializing *backwards* across a minor version is a strict-mode drift risk you can simply remove.

### Transport map

| Layer | Transport |
|---|---|
| Content — pages, paragraphs, grid rows, item XMLs | Serializer `Replace` + `Merge` passes. Push the serialized tree to the target's `Files/System/Serializer/SerializeRoot`, then `POST /Admin/Api/SerializerDeserialize`. |
| Files — brand CSS, fonts, imagery, templates, index/repository definitions | `/Admin/Api/Upload`, delete-before-upload (above) |
| Commerce — catalog, pricing, stock, variants, discounts, orders, logins | Serializer `SqlTable` predicates. Add the tables to the config rather than re-authoring rows through the API — it preserves ids and relations that hand-authoring drifts on. |

The Serializer AddIn must be installed on the target, and **its version must match the source's**: the mode names were renamed (`Deploy`/`Seed` → `Replace`/`Merge`) between builds, so a config authored against one 500s the other with `Unknown mode '<name>' for predicate`. Translate the config per side, or align the AddIn versions.

Password hashes ride the `AccessUser` row, so **demo logins survive the move** — but only if the predicate's `where` clause actually selects them. A base-layer config filtered to customer-center *groups* silently leaves the personas behind; widen the clause and re-check.

### Order of operations

1. Align the platform version (above); confirm `info.version` matches on both sides.
2. Push files **before** content — item-type XMLs and templates must exist before the content that references them.
3. **Empty the target area, then deserialize** (see below).
4. Deserialize content (`Replace`, then `Merge`), then the commerce tables.
5. Re-apply the per-environment bindings the export deliberately excludes (below).
6. Flush caches, rebuild every index, clear the sitemap cache.
7. Verify in a browser (below).

### Deserialize semantics that decide the outcome

- **`Replace` upserts; it never deletes.** Deserializing onto an install that already has content produces a *hybrid* — the target's stock paragraphs survive underneath yours, and the page renders as a mix. The fix is a clean room: delete the target area's pages (they go to the recycle bin) and deserialize into the empty area. That reproduces the source exactly, which is what the source's own first deserialize did.
- **The deserializer creates missing areas itself.** Do not pre-create the target area by hand: the export carries the source area id, and a hand-made area takes the next free id instead, so the content lands in the wrong place. Let the deserialize create it.
- **Orphaned rows can hide behind a missing area.** Entries skipped with *"Area with ID `<n>` not found"* may still have written pages carrying that `AreaId`. They are invisible while no such area exists — and surface as a fully-populated ghost area the moment an area takes that id. If a language layer or second area was dropped from the payload, check for orphans before reusing its id.
- **Only ACTIVE grid rows are exported.** A deliberately parked row — a staged promo banner the demo activates live — never transfers. Rebuild it on the target (copy an existing row of the same shape, repoint its fields, set the row inactive).
- **Identity-PK relation tables do not insert cleanly** (shop↔group relations, variant↔product relations). Rows collide by auto-id against the target's own rows, so the insert lands as an update on an unrelated row. Purge the colliding target rows first, then re-deserialize.
- **A row referencing a parent that doesn't exist fails the whole batch.** Shipping shop↔group rows for shops absent on the target leaves the FK re-enable failing (`Could not re-enable FK constraints for [<table>]`) and the batch's *good* rows missing too — categories quietly never appear. Scope the predicate with a `where` clause to what the target actually has.
- **Cross-install id remapping is yours to do.** Page ids differ between installs. Anything storing a raw page id — redirect targets (`UrlPath`), button links, policy-link fields — must be remapped against a source→target map (match pages by name/path) before it is pushed.

### What never rides the content export

The serializer config deliberately excludes per-environment fields, and several **global** settings are not content at all. Each of these silently changes rendering on the target:

| Setting | Symptom when missed |
|---|---|
| Area `CustomHeadInclude` | Brand CSS never loads — the site renders in stock theme colours. |
| Area frontpage / domain / shop / currency / country / language | Root serves the target's old frontpage; prices and market are wrong. |
| `SettingsSystemCustomizedURLs.urlInlcudeAreaType` | Area path source. On `UseAreaRegionalInPath` the path comes from the **culture**, so two areas sharing a culture collide and the second is unreachable (404). `UseAreaNameInPath` gives each area its own segment. |
| `SettingsSystemCustomizedURLs.includeProductIdInUrlNames` | Product URLs render as `?ProductID=<id>` instead of friendly slugs, so friendly PDP URLs — and any redirect pointing at one — 404. |
| Area `includeProductsInSitemap` + the on-disk sitemap cache | Sitemap serves stale content; product URLs missing. Clear `Files/System/SitemapXml/` to force a rebuild. |
| `Files/Icons/1_none.svg` | The "no icon" sentinel. It 404s on an install that never had it (rendering nothing, as intended) but **exists on a stock cloud install**, where it renders a literal **NO ICON** box on every link using the sentinel. Delete it on the target. |

Rebuild every index after the commerce load. A stale Lucene index keeps serving the target's *old* catalog — the storefront navigation shows the pre-migration categories, and category URLs 404 — long after the DB is correct.

### Verify with a browser, not just status codes

An HTTP sweep can return 200 on every page while the site is visibly broken. A field that fails to deserialize (a logo width) can leave an image rendering at its natural size — thousands of pixels wide — blowing out the layout on a page that still reports 200. **Screenshot the storefront** and run [visual-qa.md](visual-qa.md) before declaring a publish done; drive one real login and one real add-to-cart. Assert parity on the numbers that matter (page count, product count, variant count on a known master product) against the source install.

## What stays the same

- **Guarded writes**: the customisations ledger matters *more* online — code customisations are impossible, so the ledger should finish empty and that is itself the pitch beat.
- **Customer-context read-only**, demo philosophy (go deep not wide), and the discover-from-project-files rule (URL, key, area ids from chat/files — never hardcoded) all apply unchanged.
- **Shared-install discipline**: hosted demos often share the install with reference sites and other areas. Agree the untouchable area ids up front, keep all writes scoped to the demo's own area/shop/groups, and treat **global** settings (currencies, asset categories, product fields without a category) as shared state — note any global change in the demo's RESUME so other areas' owners can see it. A publish is where this bites hardest: the demo's `PROD*`/`GROUP*` ids routinely collide with a stock install's own catalog, and clearing the collision destroys the other areas' product data. Get explicit sign-off before purging anything you did not create.
