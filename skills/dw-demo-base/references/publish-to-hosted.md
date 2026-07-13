# publish-to-hosted.md — moving a locally-built demo onto a hosted install

> Owns the **publish path**: taking a demo that was built and proven on a local scaffold and putting it on a vendor-hosted DW10 install reached only by URL + Admin API bearer key. Building *directly* on a hosted install — the probe, the Management API recipe pack, the upload mechanics, the flush/restart ladder, shared-install discipline — is owned by [online-mode.md](online-mode.md); this reference assumes those and covers only what is specific to a migration.
>
> There is no local→hosted "deploy" in DW10. A publish is a **migration across three transports**, and its failure modes are not the from-scratch build's. Scope it honestly with the user before starting — it is not a button.

## Contents

- [Pre-flight — do these before the first deserialize](#pre-flight--do-these-before-the-first-deserialize)
- [Transport map](#transport-map)
- [Order of operations](#order-of-operations)
- [Deserialize semantics that decide the outcome](#deserialize-semantics-that-decide-the-outcome)
- [Publishing onto an install that already has content](#publishing-onto-an-install-that-already-has-content)
- [What never rides the content export](#what-never-rides-the-content-export)
- [Indexes — the definition travels, the built data does not](#indexes--the-definition-travels-the-built-data-does-not)
- [Verify with a browser, not just status codes](#verify-with-a-browser-not-just-status-codes)

## Pre-flight — do these before the first deserialize

**Align the platform version first.** Put `changeversion.txt` (release ring) in `Files/System/CloudHosting/` and let the site recycle, so source and target run the same DW10 build before any content moves. Serialized content deserializing *backwards* across a minor version is a strict-mode drift risk you can simply remove. Confirm `info.version` matches on both sides.

**Create the demo's custom product fields on the target through the API — before any content moves.** This is the single highest-cost trap in a publish.

Custom **product fields** (`EcomProductField`) are **column-backed**: each field is a physical column on `EcomProducts`. A `SqlTable` predicate faithfully deserializes the *definition rows* — and nothing creates the *columns*. The engine's schema-sync walks only `EcomProductGroupField`, so the target lands with field definitions whose columns do not exist. (Product **category** fields, `EcomProductCategoryField`, are row-backed — values live in `EcomProductCategoryFieldValue` — so they need no DDL and are not exposed to this.)

Three symptoms, one cause, and only the first one looks like an error:

1. Every product read through the API returns **HTTP 500 whose `title` is the bare field name** (`"title": "ABV"`).
2. **Every product index build silently produces 0 documents** — install-wide, including the target's own stock repositories. `BuildIndex` returns `status: ok` and `IndexStatus` reports `state: success` while the instance empties. A "successful" build that indexed nothing is the shape to watch for.
3. The storefront PLP renders an empty product grid while still printing its count (`12 out of 12 products`) — the count comes from the query, the cards come from resolving each hit into a product, and that throws.

Create each field on the target with `POST /Admin/Api/ProductFieldSave` **before the first deserialize**, so the columns exist when the `EcomProducts` rows arrive:

```
POST /Admin/Api/ProductFieldSave
{"Model":{"Id":"","SystemName":"<Field>","Name":"<Label>","TemplateName":"<Field>","TypeId":1,"Sort":0}}
```

Two traps live in that call:

- **`ProductFieldSave` cannot set the id** — a create auto-generates `FIELD<nnn>`. If you create the field via the API and *then* deserialize, the payload re-inserts its own row and the target ends up with **two field rows sharing one SystemName**, which zeroes the index build exactly like the missing column did. The end state must be **one row per field with `id == SystemName`**, matching source. Verify with `GET /Admin/Api/ProductFieldAll`.
- **Saving an *existing* field provisions its missing column.** That is the escape hatch if a deserialize already created definitions without columns — and it is the only one. In that state the field can be neither deleted (`ALTER TABLE DROP COLUMN failed because column '<Field>' does not exist`) nor created (`The system name '<Field>' is already in use`). Re-save the existing row, then re-deserialize to populate the values.

**Assert on document count, never on `BuildIndex`'s status.** After the commerce load, a `Full` build that reports `ok` with zero documents is the signature of this bug.

## Transport map

| Layer | Transport |
|---|---|
| Content — pages, paragraphs, grid rows, item XMLs | Serializer `Replace` + `Merge` passes. Push the serialized tree to the target's `Files/System/Serializer/SerializeRoot`, then `POST /Admin/Api/SerializerDeserialize`. |
| Files — brand CSS, fonts, imagery, templates, index/repository definitions | `/Admin/Api/Upload` with `allowOverwrite=true` ([online-mode.md](online-mode.md) "File upload") |
| Commerce — catalog, pricing, stock, variants, discounts, **orders**, logins | Serializer `SqlTable` predicates. Add the tables to the config rather than re-authoring rows through the API — it preserves ids and relations that hand-authoring drifts on. |

The Serializer AddIn must be installed on the target, and **its version must match the source's**: the predicate `mode` enum was renamed (`Deploy`/`Seed` → `Replace`/`Merge`), so a config authored against one engine 500s the other with `Unknown mode '<name>' for predicate`. Align the AddIn versions, or translate the config per side. See [serializer-reference.md](serializer-reference.md) "Replace vs Merge".

**Orders ride a plain `SqlTable` predicate.** No shipped example config includes `EcomOrders` / `EcomOrderLines`, which reads as "transactional data is deliberately excluded" — it is not. Add the two predicates and the full order history crosses (orders, quotes, open carts, order lines), which is what makes customer-center history, reorder, and per-profile order isolation demoable on the target.

Password hashes ride the `AccessUser` row, so **demo logins survive the move** — but only if the predicate actually selects them. A base-layer config filtered to customer-center *groups* silently leaves the personas behind; widen it and re-check. `AccessUser` rows are keyed by **`AccessUserId`**, not username, so a same-username multi-profile login (one username, several account profiles) survives intact.

## Order of operations

1. Align the platform version; confirm `info.version` matches on both sides.
2. **Create the custom product fields on the target** (above).
3. Push files **before** content — item-type XMLs and templates must exist before the content that references them.
4. **Empty the target area, then deserialize** (below).
5. Deserialize content (`Replace`, then `Merge`), then the commerce tables.
6. Re-apply the per-environment bindings the export deliberately excludes (below).
7. Flush caches, **rebuild every index**, clear the sitemap cache.
8. **Repair the derive-on-save fields last** (below) — they are reverted by any deserialize, so this step only holds once no further pass is coming.
9. Verify in a browser (below).

**Dry-run before committing.** `SerializerDeserialize` takes `IsDryRun` — run it and read the `created / updated / skipped / failed` line before the real pass. It is the cheapest safety net a hosted publish has, and it costs one call.

## Deserialize semantics that decide the outcome

- **`Replace` upserts; it never deletes.** Deserializing onto an install that already has content produces a *hybrid* — the target's stock paragraphs survive underneath yours, and the page renders as a mix. The fix is a clean room: delete the target area's pages (they go to the recycle bin) and deserialize into the empty area. That reproduces the source exactly, which is what the source's own first deserialize did.
- **The deserializer creates missing areas itself.** Do not pre-create the target area by hand: the export carries the source area id, and a hand-made area takes the next free id instead, so the content lands in the wrong place. Let the deserialize create it.
- **Orphaned rows can hide behind a missing area.** Entries skipped with *"Area with ID `<n>` not found"* may still have written pages carrying that `AreaId`. They are invisible while no such area exists — and surface as a fully-populated ghost area the moment an area takes that id. If a language layer or second area was dropped from the payload, check for orphans before reusing its id.
- **Only ACTIVE grid rows are exported.** A deliberately parked row — a staged promo banner the demo activates live — never transfers. Rebuild it on the target (copy an existing row of the same shape, repoint its fields, set the row inactive).
- **Identity-PK relation tables do not insert cleanly** (shop↔group relations, variant↔product relations). Rows collide by auto-id against the target's own rows, so the insert lands as an update on an unrelated row. Purge the colliding target rows first, then re-deserialize.
- **A row referencing a parent that doesn't exist fails the whole batch.** Shipping shop↔group rows for shops absent on the target leaves the FK re-enable failing (`Could not re-enable FK constraints for [<table>]`) and the batch's *good* rows missing too — categories quietly never appear. Scope the predicate with a `where` clause to what the target actually has.
- **Cross-install id remapping is yours to do.** Page ids differ between installs. Anything storing a raw page id — redirect targets (`UrlPath`), button links, policy-link fields — must be remapped against a source→target map (match pages by name/path) before it is pushed.
- **Fields the platform derives on save do not survive — and a later deserialize re-breaks them.** A value the platform recomputes when the item is saved is overwritten by that derive, even though the payload carried the authored value. The canary is the Swift logo item's width: the payload's authored width is replaced by the image's **intrinsic** width, so the logo renders at its natural size — a wordmark SVG lands thousands of pixels wide and blows out the header on a page that still returns 200.

  Treat derive-on-save fields as per-environment, and **repair them after the *last* deserialize, not the first**. The repair is a plain `ParagraphSave` of the authored value, so any subsequent `SerializerDeserialize` — a second pass, a re-run to pick up one corrected table — silently reverts it. A publish that ends with "re-deserialize to fix X" has just undone every derive-on-save repair made before it. Diff the payload's item-field values against the target's as the **final** step, and re-diff after any additional pass.

## Publishing onto an install that already has content

A stock Swift install ships its own catalog, and demo catalogs use the same generic id space — `GROUP1`, `VARGRP1`, `VO1…`, `PROD1`. `Replace` upserts by key and never prunes, so the collisions land quietly and the result is a plausible-looking hybrid. **Diff the id space per catalog table before publishing**, and get explicit sign-off before removing anything you did not create ([online-mode.md](online-mode.md) "Shared-install discipline").

Four distinct bites, in the order they cost time:

- **Variant group collision — the expensive one.** The demo's variant group id can already exist on the target as a *different kind of group*. Where the target's `VARGRP1` is a colour group (`variantDisplayType: variantColor`) with its own options, the demo's options deserialize **into that group** — and the storefront renders colour swatches, so the variant selector draws **nothing at all** while the variant *products* index perfectly. The data is right; the group's display type is the target's. Assert on `VariantGroupsByProductId` → name **and** `variantDisplayType` for a known master, and reconcile the group (`VariantGroupSave`) plus prune the target's leftover options.
- **Variant combinations are an identity-PK relation table — and losing them kills add-to-cart silently.** `EcomVariantOptionsProductRelation` carries an auto-id, so the payload's rows collide with the target's own and never land. Nothing in the deserialize reports it, the PDP still renders its variant selector, and the variants still index — but **every add-to-cart is refused**, and the storefront shows no error. The proof is in the event log, not the response: *"Not a valid variant combination for product `<P>` with variant ID `<V>`"*. Assert `VariantCombinationsByProductId` returns a non-zero count for a known master before declaring a publish done. Rebuild the missing rows with `POST /Admin/Api/VariantCombinationSave {"ProductId":"<P>","Ids":["<VO1>","<VO2>",…]}`.
- **Rebuilding combinations resets the variant rows' derived product fields.** `VariantCombinationSave` re-derives the variant products from the master, which **overwrites `ProductWeight` (and `ProductPrice`) on every variant it touches** — so a catalog whose variants carry their own shipping weight silently collapses to the master's weight on every cart line. `ProductSave` **no-ops on variant rows**, so the API cannot put them back, and there is no SQL on a hosted install. Re-run `SerializerDeserialize` (`Replace`) instead: the `EcomProducts` predicate writes the variant rows directly and restores them — then repair the derive-on-save fields again, because that pass reverts those too (below).
- **Hierarchy is the target's unless you ship it.** `EcomGroupRelations` is absent from the usual predicate set, so the *target's* parent/child tree survives and can re-parent the demo's groups under stock ones. Include it when the demo owns its group tree.
- **Relation rows re-attach the stock catalog.** The payload's `EcomShopGroupRelation` may carry rows for group ids that are dead at source but **live on the target** — silently re-attaching the stock catalog to the demo's shop. Scope the predicate to the ids the demo actually owns.
- **Rows collide, neighbours survive.** Overwriting the target's `GROUP1` is fine; the target's *other* groups are untouched and keep rendering. Hiding a group from the storefront (`navigationShowInMenu: false` via `ProductCatalogGroupSave`) is the reversible lever; deleting is not, and on a shared install it destroys another area's data.

## What never rides the content export

The serializer config deliberately excludes per-environment fields, and several **global** settings are not content at all. Each of these silently changes rendering on the target:

| Setting | Symptom when missed |
|---|---|
| Area `CustomHeadInclude` | Brand CSS never loads — the site renders in stock theme colours. |
| Area frontpage / domain / shop / currency / country / language | Root serves the target's old frontpage; prices and market are wrong. |
| `SettingsSystemCustomizedURLs.urlInlcudeAreaType` | Area path source. On `UseAreaRegionalInPath` the path comes from the **culture**, so two areas sharing a culture collide and the second is unreachable (404). `UseAreaNameInPath` gives each area its own segment. |
| `SettingsSystemCustomizedURLs.includeProductIdInUrlNames` | Product URLs render as `?ProductID=<id>` instead of friendly slugs, so friendly PDP URLs — and any redirect pointing at one — 404. |
| Area `includeProductsInSitemap` + the on-disk sitemap cache | Sitemap serves stale content; product URLs missing. Clear `Files/System/SitemapXml/` to force a rebuild. |
| `Files/Icons/1_none.svg` | The "no icon" sentinel. It 404s on an install that never had it (rendering nothing, as intended) but **exists on a stock cloud install**, where it renders a literal **NO ICON** box on every link using the sentinel. Delete it on the target. |

## Indexes — the definition travels, the built data does not

Ship the repository **definition** (`.index` / `.query` / `.facets`) as files and **rebuild natively on the target** (`POST /Admin/Api/BuildIndex {Repository, IndexName, BuildName:"Full"}`). The built segments under `Files/System/Indexes/**` are derived state keyed to the install that produced them.

Copying the built index instead produces a **phantom index**: the PLP prints its product count while rendering **zero cards**, because the count resolves from the index and the cards resolve each hit into a product the target cannot match. Uploading only the definition and building without existing instances fails differently — `state: error`, *"instance '<name> secondary' must be recovered before other instances can build"*, then *"no healthy instance is available"*.

A stale index is equally load-bearing in the other direction: it keeps serving the target's *old* catalog long after the DB is correct — the storefront navigation shows pre-migration categories and category URLs 404.

**A repository the target did not have at startup needs a restart before its facets resolve.** Index *builds* re-read the `.index` file, so indexing recovers as soon as you build — but the facet/repository definitions resolve at app start. Upload a brand-new repository into a running app and the PLP renders products correctly with an **empty facet panel**, even though the `.facets` file is byte-identical to source, the catalog module's `moduleSettings` correctly reference it, the index schema exposes the bound fields, and the documents carry the values. Flushing the service caches does not reach it. Restart the app ([online-mode.md](online-mode.md) "Flush first") — and if the host does not honour the control files, sequence the repository upload before the app comes up, or expect no facets.

## Verify with a browser, not just status codes

An HTTP sweep can return 200 on every page while the site is visibly broken. A derive-on-save field can leave an image rendering thousands of pixels wide; a colour-swatch variant group can leave a PDP with no selector; a phantom index can leave a PLP with a product count and no products. **Screenshot the storefront** and run [visual-qa.md](visual-qa.md) before declaring a publish done; drive one real login and one real add-to-cart.

Assert parity on the numbers that matter, against the source install:

| Assert | Against |
|---|---|
| Page count, product count, index `documentCount` | source totals |
| Variant count + selector renders on a known master | source PDP |
| A signed-in contract price on a known variant | source PDP |
| Order count for a seeded buyer | source customer center |
| The facet panel is non-empty | source PLP |
