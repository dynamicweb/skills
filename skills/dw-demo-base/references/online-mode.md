# online-mode.md — building on a hosted (cloud) install

> Owns the **online/cloud variant** of the demo-base flow: what changes when the demo runs on a vendor-hosted DW10 install reached only by URL + Admin API bearer key — no local scaffold, no SQL, no filesystem. This reference covers **building** a demo directly on a hosted install (Management API only).
>
> **Publishing an existing local demo onto a hosted install** is a migration, not a build, and has its own failure modes — it is owned by [publish-to-hosted.md](publish-to-hosted.md). Everything below (the probe, the API recipe pack, the upload mechanics, the flush/restart ladder, shared-install discipline) applies to both.
>
> Local installs remain the default; this reference is the fork target from [SKILL.md](../SKILL.md) "Environment fork". The four always-on guardrails (customisations ledger, customer-context read-only, demo philosophy, discover-from-project-files) apply unchanged.

## Contents

- [Recognising online mode](#recognising-online-mode)
- [Probe order at session start](#probe-order-at-session-start)
- [Management API recipe pack](#management-api-recipe-pack-validated-dw-1025x)
  - [dw10source as binder disambiguator](#dw10source-as-binder-disambiguator)
  - [File upload — and why an "ok" upload can change nothing](#file-upload--and-why-an-ok-upload-can-change-nothing)
  - [Flush first; a cloud install can usually be restarted](#flush-first-a-cloud-install-can-usually-be-restarted)
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
| Host lifecycle authority | You do not own a host process. Most hosted installs still restart — drive it through the CloudHosting control files — but confirm the file is consumed; some partner-hosted installs never act on it. Work the flush-first ladder below. |

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
`POST /Admin/Api/Upload`, multipart form: field `path` = **relative** directory (no leading slash — leading-slash paths are rejected as "outside allowed root"), repeated `files` fields for the payload. Many files per request is fine — one request per directory. The target directory must already exist physically. **`DirectorySave` is rename-only** (returns ok, creates nothing) — create folders via `DirectoryCopy` of any small existing folder to the new path, then `DirectoryEmpty` on it.

**Send `allowOverwrite=true` on every upload.** Without it the endpoint refuses to replace an existing file and reports the refusal as *success*: `{"status":"ok","model":{"duplicates":["<name>"]}}`, with the file on disk unchanged. The refusal takes the **whole batch** — one pre-existing name in a multi-file request and the request's *new* files do not land either. `allowOverwrite` is a working form field that is absent from the OpenAPI schema; add it as an ordinary multipart field:

```
POST /Admin/Api/Upload   (multipart: path=<dir>, allowOverwrite=true, files=<name> [, files=<name> …])
  → {"status":"ok","model":["/Files/<dir>/<name>", …]}      # wrote
  → {"status":"ok","model":{"duplicates":[…]}}              # wrote NOTHING (no allowOverwrite)
```

**Success is the shape of `model`, not `status`.** Assert that `model` is a **list whose length equals the batch size**; a `duplicates` object — or an empty list, which is what a 0-byte file returns — means nothing was written. A design push that reports `ok` for every batch while silently keeping the target's old templates is exactly what this catches.

### Flush first; a cloud install can usually be restarted
Wherever a sister-skill recipe says "restart the host" (variant seeding, BOM inserts, asset bulk loads), you have no host process — but a hosted install usually still has a restart surface. Work the ladder:

1. **Targeted flush** — `CacheInformationRefresh` (singular) with one `CacheTypeName`.
2. **Bulk flush** — `GET /Admin/Api/GetServiceCaches` → collect the `modelIdentifier`s → `POST /Admin/Api/CacheInformationsRefresh {"Ids": [...]}`. This clears the stale-read class of symptom: a row written through the API that a later query still reports with its old value (a shop that "doesn't exist", a group tree missing a node, a catalog group still under its pre-publish name), and the stale disabled add-to-cart after variant seeding.
3. **Real restart** — drop a control file in `Files/System/CloudHosting/` (`recycle.txt`, `restart.txt`; `changeversion.txt` also switches release ring). Canonical table: [`dw-setup-config`](../../dw-setup-config/SKILL.md) "cloud control files". Some **global settings do not take effect on a cache flush alone** — a URL-generation change can keep serving the old shape until the app restarts. If a setting reads back correctly from the API but the storefront still renders the old behaviour, restart before diagnosing further. **The CloudHosting watcher fires on a CHANGED token, not on the file's presence — write a value that DIFFERS from the file's current content every time.** Re-uploading `changeversion.txt` with the value it already holds is a silent no-op: the file is never consumed and nothing recycles. Bump to a fresh distinct token on each use (any monotonic suffix works) and record the last-used token in the demo ledger so the next restart bumps past it rather than re-writing it.

**Confirm the restart actually happened — the control files are a Dynamicweb Cloud affordance, not a property of every hosted install.** The platform *consumes* the file: it disappears once acted on. On a partner-hosted install that does not run the watcher, `recycle.txt` and `restart.txt` upload happily, sit there unconsumed, and nothing restarts. So after dropping one, re-list `Files/System/CloudHosting/`; a file still present means **rung 3 does not exist on this host**. That is worth knowing early, because a few things are only reachable by restart — notably a repository whose definition was uploaded into an already-running app ([publish-to-hosted.md](publish-to-hosted.md) "Indexes"). Bulk cache flush does not reach them.

### Index / repository-config writes report `ok` while the host ACL drops them

A partner-hosted site process often runs under an account that cannot write `Files/System/Repositories/**`, and the Management API index commands do not surface that denial. **Read every repository-config field back through a different query immediately after the save; a matching readback is the only proof it landed — the `status: ok` is not.**

- **`IndexBuilderSave` is a lying-success surface.** Setting `ShopsToIndex` (or any builder field) round-trips `status: ok` and bumps `updatedDate` while writing nothing to disk when the ACL denies the `/Files/System/Repositories/**` XML write. An `IndexBuilderByName` readback shows the field still empty, and a following Full rebuild then runs unscoped (the whole catalog indexes instead of the intended shop). Assert the readback, not the `ok`.
- **After a group→product relation write, recycle first, THEN Full `BuildIndex` — the rebuild alone is a no-op.** `ProductIndexBuilder` reads `EcomGroupProductRelation` through an app-lifetime cache that only a process recycle clears. Write a relation (publish-to-channel, group re-parent), run a Full build without a recycle, and the builder re-indexes the stale relation set — doc counts never move, which reads as "API index builds are dead on this host". Drop a rung-3 control file first, wait for the recycle, then POST the identical `BuildIndex {Repository:Products, IndexName:Products.index, BuildName:Full, BuildType:Full}` — it now swaps the online instance and the per-group counts move. (Relation-cache cousin of the value-write read-through-cache ordering trap in [`foundational/cache-invalidation.md`](foundational/cache-invalidation.md): different cache, same fix — clear it before the rebuild.)

## Publishing an existing local demo to a hosted install

Moving a demo that was built locally onto a hosted install is a **migration across three transports**, not a deploy — and its failure modes are not this reference's. It has its own playbook: [publish-to-hosted.md](publish-to-hosted.md) — pre-flight (custom product fields must exist on the target **before** the first deserialize), the transport map, clean-room deserialize semantics, publishing onto an install that already has content (id collisions), the settings that never ride a content export, indexes, and the browser-verified parity sweep.

## What stays the same

- **Guarded writes**: the customisations ledger matters *more* online — code customisations are impossible, so the ledger should finish empty and that is itself the pitch beat.
- **Customer-context read-only**, demo philosophy (go deep not wide), and the discover-from-project-files rule (URL, key, area ids from chat/files — never hardcoded) all apply unchanged.
- **Shared-install discipline**: hosted demos often share the install with reference sites and other areas. Agree the untouchable area ids up front, keep all writes scoped to the demo's own area/shop/groups, and treat **global** settings (currencies, asset categories, product fields without a category) as shared state — note any global change in the demo's RESUME so other areas' owners can see it. A publish is where this bites hardest: the demo's `PROD*`/`GROUP*` ids routinely collide with a stock install's own catalog, and clearing the collision destroys the other areas' product data. Get explicit sign-off before purging anything you did not create.
