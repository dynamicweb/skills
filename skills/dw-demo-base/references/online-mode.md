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
  - [`FileDelete` can be ACL-denied for pre-existing files](#filedelete-can-be-acl-denied-for-pre-existing-files--know-the-per-host-answer-before-you-plan-a-cleanup)
  - [Flush first; a cloud install can usually be restarted](#flush-first-a-cloud-install-can-usually-be-restarted)
- [Inheriting a CLONED demo host — the remediation playbook](#inheriting-a-cloned-demo-host--the-remediation-playbook)
  - [A clean Monitoring dashboard does not mean a clean site](#a-clean-monitoring-dashboard-does-not-mean-a-clean-site)
  - [Test whether the process can CREATE before calling it an ACL lockout](#test-whether-the-process-can-create-before-calling-it-an-acl-lockout)
  - [Clone-inherited files under `Files\System` are owned by the source host](#clone-inherited-files-under-filessystem-are-owned-by-the-source-host)
  - [A red scheduled task on a clone is usually a stale PATH string](#a-red-scheduled-task-on-a-clone-is-usually-a-stale-path-string)
  - [Check what a repaired integration task would IMPORT before repairing it](#check-what-a-repaired-integration-task-would-import-before-repairing-it)
  - [GlobalSettings on an ACL-locked host: the API applies without persisting, the disk edit persists without applying](#globalsettings-on-an-acl-locked-host-the-api-applies-without-persisting-the-disk-edit-persists-without-applying)
  - [Never `Move-Item` over a file in a DW-managed folder — and `Translations.xml` is DW-owned](#never-move-item-over-a-file-in-a-dw-managed-folder--and-translationsxml-is-dw-owned)
- [Personal data on an inherited host](#personal-data-on-an-inherited-host)
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
4. **Site database reachability — probe it before assuming API-only reads.** "Cloud-hosted" does not imply "database out of reach": on a co-located host class the site DB is reachable from the VM the agent runs on, and the connection string sits in `Files/GlobalSettings.Database.config`. A plain SqlClient connection with those credentials returns **full result sets** — which retires the whole `Sql-ReadRaw` double-UPDATE / `RAISERROR`-peek family of workarounds that exist only because the API offers no `SELECT` channel. Probe once at session start (read the config, open a connection, run a trivial `SELECT`), record the answer in the demo ledger, and plan the session's verification reads from the result rather than from a remembered host.

   **Caveats, all load-bearing:** the file contains **live credentials for a shared production-class host** — never copy it into the demo folder, an extract, a transcript or a commit, and reference it by path only. A direct connection is outside DW's bookkeeping, so it stays a **read** channel by default: reads through it are the safe, high-value part, while writes re-open every cache/notification hazard the surface-priority rule exists to prevent (`surface-priority.md`, and the API-write-vs-SQL-write visibility split in [`../../dw-demo-swift/references/sql-direct-seeding.md`](../../dw-demo-swift/references/sql-direct-seeding.md)). On a shared install the connection reaches **other tenants' areas** as well as the demo's — scope every query explicitly.

**Surface priority in online mode:** MCP (if the probe finds it) → Management API → **ask the user** for the rare operation neither exposes. Assume there is **no SQL surface** until probe 4 proves otherwise — the "last resort" rung of the local surface-priority table is absent on most hosted installs, which is why every SQL-based sister-skill recipe needs the API equivalent from this file. Where the DB *is* reachable it changes the **verification** picture (a real `SELECT` channel), not the write order: writes stay MCP → Management API. The admin UI stays verification-only, same as every build phase (`surface-priority.md`).

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

**`Upload` will not create a missing directory, and `FilesByDirectory` is NOT an existence check.** The two combine into a confusing failure: the listing query answers happily for a path that does not exist, so the folder looks present right up until the upload throws a 500 naming the missing physical path. There is no directory-create verb hiding under a better name — every obvious candidate is unregistered:

```
GET  /Admin/Api/FilesByDirectory?…&Path=/Files/System/Styles/Fonts
  -> well-formed model, totalCount 0            # NOT a 404 — cannot be used as an existence test
POST /Admin/Api/Upload            (same path)
  -> 500  "Could not find a part of the path …\Files\System\Styles\Fonts\…"
POST /Admin/Api/DirectorySave     {Name:"Fonts", Model:{Name:"Fonts", Path:"/Files/System/Styles"}}
  -> {"status":"ok"}, model null                # no folder on disk; the upload 500s identically
DirectoryCreate | FolderCreate | DirectoryNew | CreateDirectory | FileManagerCreateFolder
  -> Unknown command  (all five)
```

**So land assets in a folder that already exists**, and prefer the folder the referencing file already lives in — self-hosted webfonts belong next to the sheet that `@font-face`s them (`Templates/Designs/<design>/Custom/`), not in a new `System/Styles/Fonts/` tree that has to be conjured first. If a new folder is genuinely required, use the `DirectoryCopy` + `DirectoryEmpty` trick above and verify the path lists before uploading into it.

### `FileDelete` can be ACL-denied for pre-existing files — know the per-host answer before you plan a cleanup

On a cloud-co-located host class the `Files` ACL grants the FTP group `Modify` and `BUILTIN\Users` only `ReadAndExecute`, and the app-pool identity falls in `Users`. Every `FileDelete` against a **pre-existing** (stock or FTP-delivered) file then fails **loudly**:

```
POST /Admin/Api/FileDelete       -> 400  "Access to the path '…' is denied."
POST /Admin/Api/DirectoryDelete  -> succeeds ONLY for folders the app pool itself created
```

This is a different failure from the earlier-recorded host where `FileDelete` silently no-ops — same intent, opposite signal — so **probe one file before scripting a bulk delete** and pick the strategy from the result rather than from a remembered host.

**Strategy: API first; fall back to a disk-side delete when the agent is co-located with the files.** A disk delete under the agent's own account bypasses the app-pool ACL entirely and is the working path on a co-located host. It goes behind DW, so it owes a **three-way verification** on a sample of the batch — anything less can leave a file that is gone from one surface and serving from another:

1. absent on disk,
2. absent from the DW `FilesByDirectory` listing,
3. public `GET` returns **404**.

An assets-cleanup leg on a co-located host should carry the disk path as a first-class option, not as an emergency escape.

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
3. **Real restart** — drop a control file in `Files/System/CloudHosting/` (`recycle.txt`, `restart.txt`). Canonical table: [`dw-setup-config`](../../dw-setup-config/SKILL.md) "cloud control files". Some **global settings do not take effect on a cache flush alone** — a URL-generation change can keep serving the old shape until the app restarts. If a setting reads back correctly from the API but the storefront still renders the old behaviour, restart before diagnosing further. **`changeversion.txt` is NOT a restart lever — it is the release-ring/runtime version pin.** Never rotate it to force a recycle: any changed value is a real version migration, and a same-value re-upload is not a reliable no-op either (observed on an `R0-NET…` ring token: it still recycles the app while leaving the version in place). Use `recycle.txt`/`restart.txt` for restarts; touch `changeversion.txt` only to deliberately switch ring/version, confirm the switch with `info.version` (a recycle alone is not proof), and record the last-used token in the demo ledger so the next switch bumps past it. Full treatment: [db-update-recovery.md](db-update-recovery.md).

**Confirm the restart actually happened — the control files are a Dynamicweb Cloud affordance, not a property of every hosted install.** The platform *consumes* the file: it disappears once acted on. On a partner-hosted install that does not run the watcher, `recycle.txt` and `restart.txt` upload happily, sit there unconsumed, and nothing restarts. So after dropping one, re-list `Files/System/CloudHosting/`; a file still present means **rung 3 does not exist on this host**. That is worth knowing early, because a few things are only reachable by restart — notably a repository whose definition was uploaded into an already-running app ([publish-to-hosted.md](publish-to-hosted.md) "Indexes"). Bulk cache flush does not reach them.

### Index / repository-config writes report `ok` while the host ACL drops them

A partner-hosted site process often runs under an account that cannot write `Files/System/Repositories/**`, and the Management API index commands do not surface that denial. **Read every repository-config field back through a different query immediately after the save; a matching readback is the only proof it landed — the `status: ok` is not.**

- **`IndexBuilderSave` is a lying-success surface.** Setting `ShopsToIndex` (or any builder field) round-trips `status: ok` and bumps `updatedDate` while writing nothing to disk when the ACL denies the `/Files/System/Repositories/**` XML write. An `IndexBuilderByName` readback shows the field still empty, and a following Full rebuild then runs unscoped (the whole catalog indexes instead of the intended shop). Assert the readback, not the `ok`.
- **After a raw-SQL group→product relation write, recycle first, THEN Full `BuildIndex` — the rebuild alone is a no-op.** `ProductIndexBuilder` reads `EcomGroupProductRelation` through an app-lifetime cache that only a process recycle clears. Insert a relation via SQL, run a Full build without a recycle, and the builder re-indexes the stale relation set — doc counts never move, which reads as "API index builds are dead on this host". Relations written through `ProductGroupRelationSave` need no recycle: the API write invalidates the relation cache in-process (the visibility split is owned by `dw-demo-swift/references/sql-direct-seeding.md` "API write vs SQL write"). Either way the Full build must target `Repository='Products'` — the `ProductsFrontend`/`ProductsBackend` pair only enqueues and never refreshes the `GroupID` facet. Drop a rung-3 control file first, wait for the recycle, then POST the identical `BuildIndex {Repository:Products, IndexName:Products.index, BuildName:Full, BuildType:Full}` — it now swaps the online instance and the per-group counts move. (Relation-cache cousin of the value-write read-through-cache ordering trap in [`foundational/cache-invalidation.md`](foundational/cache-invalidation.md): different cache, same fix — clear it before the rebuild.)

## Inheriting a CLONED demo host — the remediation playbook

A large share of hosted demo work is not a build on a fresh install but an **inherited clone** of somebody
else's site: files copied verbatim, scheduled tasks copied verbatim, settings copied verbatim, onto a host
with a different app-pool identity and a different disk layout. The faults that produces are a family, not a
list of unrelated bugs, and they share one shape — **the clone copied the artefact but not the ownership,
the path, or the endpoint that made it work.** Work this section before diagnosing anything on an inherited
host; a fault that matches a row here is not the mystery it looks like.

Run all of it early: nearly every item below is invisible from the admin UI and several of them are writing
customer-visible errors every few minutes while the site *looks* fine.

### A clean Monitoring dashboard does not mean a clean site

**Exceptions thrown inside middleware escape DW's logging pipeline entirely.** A route can return HTTP 500
with a zero-byte body and no content-type on every request for months while `GeneralLog` — and therefore the
Insights Monitoring dashboard, the screen an owner is told to trust — shows nothing at all, because no row is
ever written. The only record is the **ASP.NET Core stdout log on disk** (`Application\logs\stdout_*.log`),
where the same failures appear under the IIS `HttpServer` category.

- **Add the stdout log path to the standard diagnostic checklist**, and read it whenever a route misbehaves
  with no corresponding log row. "Nothing in GeneralLog" is not evidence of health above the DW pipeline.
- **Probe the non-page routes by HTTP status, never by inferring health from logs** — `/sitemap.xml`,
  `/robots.txt` and friends. The gate assertion is status + content-type + non-zero body
  (`GET /sitemap.xml` → `200 application/xml`, body length > 0).
- Log-volume hygiene and what the Monitoring counters do and do not count:
  [`foundational/tracking-insights.md`](foundational/tracking-insights.md).

### Test whether the process can CREATE before calling it an ACL lockout

**An `UnauthorizedAccessException` is not automatically a host ACL problem you must hand to an operator.**
Two different faults produce the identical exception:

| Fault | What the process can do | Fix |
|---|---|---|
| **Real ACL lockout** | cannot write the directory at all | needs an operator / an ACL grant |
| **Clone-ownership fossil** | **can create**, only fails to replace or delete a *foreign-owned* file | delete the fossil — no ACL edit, no operator |

Both can exist side by side on one host, which is exactly how the self-serviceable one gets triaged as
operator-only and left standing. **Make a scratch-file create in the target directory the first triage step
of any `UnauthorizedAccessException`** — it separates the two cases in one command, and the second case is
usually fixable in three.

The tell for the second case is **orphaned `.tmp` files next to the failing artefact** (one per failed
attempt), or a stale artefact dated before the demo sitting in a folder the process is demonstrably writing.

### Clone-inherited files under `Files\System` are owned by the source host

The clone copies `Files\` verbatim, including files owned by the **source** host's deploy account. The
destination app pool inherits `BUILTIN\Users = ReadAndExecute + CreateFiles + CreateDirectories` on those
folders — so it **can create files but cannot delete or replace one owned by another principal**. Every
platform code path that unconditionally deletes-then-regenerates its own artefact throws forever. *The folder
being writable is exactly what makes it look like something else.*

Three unrelated-looking features broken for weeks to months on one inherited host, all with this single
cause:

- **`/sitemap.xml` 500s on every request** — `UnauthorizedAccessException` at `System.IO.File.Delete` inside
  the sitemap middleware. The stale file still on disk was months old, owned by the source host's account,
  and its URLs still pointed at the *source* site's domain.
- **The product index build aborts in about a second, daily** — "Failed to persist index build state" for
  `.../IndexBuildState/.../state.json`. Both state files were frozen months earlier carrying the **source**
  host's server id, with dozens of orphaned `.tmp` files beside them — creates worked, only the atomic
  replace failed.
- **An item-type reload fails a dozen times a day** — same shape, different artefact.

**The fix is to DELETE the fossil, not to edit ACLs.** The app pool then creates the replacement and *owns*
it; these folders carry an inherit-only `CREATOR OWNER` full-control ACE, so the fix is durable across every
later regeneration (proven by two back-to-back fetches where the second deleted and rewrote the file the
first had created). Granting `Modify` per folder is a live-server ACL change that needs an operator and buys
nothing extra.

**Provisioning obligation:** the clone pipeline should exclude — or re-own — `Files\System` artefacts
(sitemap output, index build state, item-type caches). A clone-time sweep asserting **no file under
`Files\System` is owned by a principal other than the destination app pool** catches the whole family before
anyone sees a 500.

### A red scheduled task on a clone is usually a stale PATH string

A single task that has never once succeeded since the clone can be a large share of the host's entire error
volume — one inherited host had it at **39% of all errors**, from a task firing every 15 minutes and emitting
three rows per run (`Scheduled task failed` + a `DirectoryNotFoundException` on job creation + the
`Total executed … Failed 1` summary).

The cause is prosaic: **the clone renamed the integration job tree and left one task pointing at the old
path.** Every sibling task points at a path that resolves, which is precisely why only one is red and why it
reads as a broken integration rather than a broken string.

**Add a clone-time sweep asserting that every enabled task's import-activity path resolves on disk** — same
shape as the `Files\System` ownership sweep above, and just as cheap.

### Check what a repaired integration task would IMPORT before repairing it

**Repointing the stale path is usually the wrong fix.** A clone inherits integration tasks whose endpoints,
source payloads and destinations no longer exist; repairing the symptom re-arms a job whose destination,
source *and* endpoint are all wrong. On one host, "fixing" the red task would have run a never-tested user
import against the live demo users — the identities behind a live portal — every 15 minutes, from an empty
stub file, forever.

Make these four checks a **precondition** for repairing any inherited integration task:

1. **Destination table** — what does the job write, and is it live demo data? (A job declared as a
   transaction against the user table is a stop sign, not a repair candidate.)
2. **Source payload** — does the source file actually contain records, or is it a stub?
3. **Endpoint reachability** — can the host reach the remote service at all? Unreachable endpoints are why
   the *green* sibling tasks succeed: they succeed with empty output.
4. **The rest of the chain** — if the downstream import leg is already disabled, a repaired staging leg
   imports nothing anyway.

**The correct fix for a dead-endpoint clone task is to DISABLE it, not to repoint it.** Disable in place
(leave it in its folder) so the integration story still renders on screen and simply stops being red. Gate:
no enabled task targets a live demo table from an unreachable endpoint.

### GlobalSettings on an ACL-locked host: the API applies without persisting, the disk edit persists without applying

The single most misread behaviour on a locked-down host, because it produced **three different wrong
conclusions in one day**: a 500 read as a rejected setting when the setting had in fact applied; a disk edit
read as a fix when the running app never saw it; and a half-applied save read as damage from an unrelated
file write.

The mechanism: `ConfigurationManager.SetValue` updates the **in-memory settings cache BEFORE** the XML
provider persists the file. Where the app pool has only `ReadAndExecute` on the GlobalSettings files, the
persist throws and the verb returns `500` — **but the value is already live**. Conversely the app caches
settings at start-up with **no file watcher**, so an out-of-band file edit is invisible until a restart.

```
POST /Admin/Api/<Area>SettingsSave   -> 500 {"title":"Access to the path is denied."}
GET  /Admin/Api/GlobalSettingByKey   -> reads back the NEW value immediately   # it applied
(edit the .config file on disk only)
GET  /Admin/Api/GlobalSettingByKey   -> still the OLD value                    # it did not apply
```

Measured independently on both the platform and the ecommerce settings files.

- **The durable recipe is BOTH steps, in either order:** the API save to apply it live (catch and ignore the
  500), **plus** an out-of-band file edit from an account with `Modify` so the value survives the next start.
- **A partially applied save can leave the subsystem it configures FAULTED**, rebuildable only by a recycle.
  One cookie/consent save applied far enough to take the consent modal off every page in every language
  site-wide, while the persist failed — and a parallel workstream first attributed that to its own unrelated
  file write. **Batch settings changes on an ACL-locked host and verify them; do not retry them one at a
  time.**
- **Verification contract:** for each changed key, assert the API read-back and the on-disk file **agree**,
  then smoke-test the subsystem the setting actually drives.
- **Hosting fix worth asking for:** grant the app pool `Modify` on the two GlobalSettings files.

### Never `Move-Item` over a file in a DW-managed folder — and `Translations.xml` is DW-owned

**A moved file keeps the SOURCE file's ACL.** Building a temp file and moving it over the target — the
safe-looking atomic write — silently strips the design folder's explicit `IIS APPPOOL\<site> : FullControl`
ACE from the replacement, leaving only inherited `BUILTIN\Users : ReadAndExecute`.

DW can still **read** the file, so everything renders normally and the site looks fine. The failure surfaces
later and elsewhere: **DW also writes this file itself.** `Translate()` on a literal it does not know calls
through to the translation source's `Save()` → `WriteDocument` → a writer over the same path. That write
throws, the exception escapes the renderer, and a single page renders a full "Error executing template" stack
dump — in every language — while the rest of the site is untouched.

- **Write IN PLACE** (open the existing path with a stream writer) instead of moving a temp file over it, and
  **assert the app-pool ACE afterwards** in any tooling that touches a DW-managed folder.
- Smoke-test a route whose template registers a **new** `Translate()` literal, in every language layer — that
  is the only shape that exercises the write path.

**`Translations.xml` is a DW-owned, self-modifying artifact — not a static design file.** `Translate()` on an
unknown literal appends a key node at render time, so keys appear that nobody authored and the file grows on
its own (measured: >100KB of growth across a single session, partly from DW's own writes). Two consequences:

- **Merge additively and never treat a diff against a stored copy as corruption.** Tooling that "restores"
  the file to a known state deletes keys the platform registered.
- **It is the facet-label store.** PLP facet *group* names are declared in the repository's facets file and
  rendered through `@Translate(facet.Name)`, so DW auto-registers them here on first render — which is why
  they are translatable from this file at all, and why the `Ecom*Translation` tables are the wrong place to
  look for them.
- Key matching is **case-sensitive**, and the shipped file carries case-variant duplicate keys — the tooling
  rules for that are in
  [`../../dw-demo-swift/references/language-layers.md`](../../dw-demo-swift/references/language-layers.md)
  "`Translations.xml` keys are case-sensitive".

This ACL hazard and the self-modifying behaviour are the same fact seen twice: **DW must retain write access
to this file**, so any tool that touches it owes the ACE assertion.

## Personal data on an inherited host

A cloned demo host is also a **personal-data inheritance**. Real customer identities, real order snapshots,
real addresses and the platform vendor's own stock legal/marketing copy all ride the clone into a customer
presentation, and none of it is visible from a rename of the obvious user rows. Treat it as a blocking
pre-demo leg with its own method: [`pii-sweep.md`](pii-sweep.md).

## Publishing an existing local demo to a hosted install

Moving a demo that was built locally onto a hosted install is a **migration across three transports**, not a deploy — and its failure modes are not this reference's. It has its own playbook: [publish-to-hosted.md](publish-to-hosted.md) — pre-flight (custom product fields must exist on the target **before** the first deserialize), the transport map, clean-room deserialize semantics, publishing onto an install that already has content (id collisions), the settings that never ride a content export, indexes, and the browser-verified parity sweep.

## What stays the same

- **Guarded writes**: the customisations ledger matters *more* online — code customisations are impossible, so the ledger should finish empty and that is itself the pitch beat.
- **Customer-context read-only**, demo philosophy (go deep not wide), and the discover-from-project-files rule (URL, key, area ids from chat/files — never hardcoded) all apply unchanged.
- **Shared-install discipline**: hosted demos often share the install with reference sites and other areas. Agree the untouchable area ids up front, keep all writes scoped to the demo's own area/shop/groups, and treat **global** settings (currencies, asset categories, product fields without a category) as shared state — note any global change in the demo's RESUME so other areas' owners can see it. A publish is where this bites hardest: the demo's `PROD*`/`GROUP*` ids routinely collide with a stock install's own catalog, and clearing the collision destroys the other areas' product data. Get explicit sign-off before purging anything you did not create.
