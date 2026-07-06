# headless-baseline.md

## Contents

- [1. A headless baseline is its own product line](#1-a-headless-baseline-is-its-own-product-line)
- [2. Layer shape (replace/merge, not a flat content folder)](#2-layer-shape-replacemerge-not-a-flat-content-folder)
- [3. The `Headless_*` item-type layer](#3-the-headless_-item-type-layer)
- [4. Item-instance id floor band](#4-item-instance-id-floor-band)
- [5. EN/NL sibling-area parity](#5-ennl-sibling-area-parity)
- [6. Disk-overlay staging BEFORE host start](#6-disk-overlay-staging-before-host-start)
- [7. Product search surface (repository + query + facets)](#7-product-search-surface-repository--query--facets)
- [8. Deserialize order + Full index build](#8-deserialize-order--full-index-build)
- [9. Verification gate](#9-verification-gate)

> Deserialize the **headless baseline** into a demo host. The headless baseline is a **separate
> serialized product line** from Swift — it carries exactly the content a headless frontend needs
> (catalog navigation/menus, content pages, B2B/customer-center structures) as **zero-custom-code
> YAML**, in a presentation-agnostic `Headless_*` item-type layer that shares **no** item-type rows
> with Swift. Consumer: the Next.js storefront via the Delivery API ([`headless-frontend.md`](headless-frontend.md)).
>
> **Use AFTER `dynamicweb-demo-base`** (Serializer installed) and after the backend is understood
> ([`headless-backend.md`](headless-backend.md)).

## 1. A headless baseline is its own product line

Because a headless frontend and a Swift frontend consume content completely differently, the
headless baseline is packaged as a **distinct product line** (`baseline/headless/2.3`), not a
variant of `swift/2.3`. It has an independent lifecycle and its own gate pass, and it shares no
item-type rows with Swift. The point is independent evolution: Swift item types roll with Swift's
Razor building blocks; `Headless_*` items roll with the Next.js component contract.

**Reuse the domain model, not the item types.** Commerce/PIM data (products, groups, variants,
prices, orders, users, facets) is delivered through the Delivery API product/order endpoints and
captured as `Ecom*` SQL rows — never as item types. Only field-type *conventions* carry over. Do
not port Swift paragraph item types: they are presentation-coupled (template/CSS/layout/colorscheme/
icon fields bound to Razor), and lifting them reintroduces exactly the coupling headless exists to
avoid.

## 2. Layer shape (replace/merge, not a flat content folder)

The serializer keys its merge behaviour off the **mode**, so the headless **surface layer** splits content into
`replace/` (source-wins) and `merge/` (field-level merge), each with its own `schemaVersion: 2`
manifest, `_content/` (page trees), and `_sql/` (commerce rows). The disk-overlay surfaces
(`itemtypes/`, `repositories/`) sit alongside:

```
layers/headless/                     # kind surface, in the Distribution clone
├─ BASELINE.md
├─ config/headless-2.3.json          # serializer predicate list (Content + SqlTable)
├─ itemtypes/Headless_*.json          # D-agnostic item-type defs (disk-overlay, zero code)
├─ repositories/Headless/             # product search surface (disk-overlay, zero code)
│  ├─ Products.index · Products.query · Products.facets
├─ replace/                          # source-wins framework (nav, customer-center, area chrome)
│  ├─ replace-manifest.json
│  ├─ _content/Headless/ …            # EN
│  ├─ _content/Headless Nederlands/ … # NL parity
│  └─ _sql/                           # commerce reference tables (serialize-captured)
└─ merge/                            # customer-owned bootstrap (home, about, catalog landing)
   ├─ merge-manifest.json
   ├─ _content/Headless/ … + _content/Headless Nederlands/ …
   └─ _sql/                           # catalog/prices (serialize-captured)
```

`_sql/` row files are **not hand-authored** — a serialize pass captures them from the live host, the
same way the base layer does. A demo can run headless as an **additional leg on top of the
Swift leg's catalog** in the same DB (shared-catalog): the headless replace/merge manifests list only
`Content` entries, so the `Ecom*` catalog comes from whatever the Swift leg's DB holds and the
headless deserialize never touches it. Note the base layer is scaffolding-only — it ships no
sample catalog — so "the Swift leg's catalog" means the **per-demo catalog authored** on that leg
(via `dw-demo-pim`), not baseline-supplied rows. That is the low-friction path until the headless
package captures its own `_sql`.

## 3. The `Headless_*` item-type layer

New, **presentation-agnostic** item types namespaced `Headless_*`, so they never collide with Swift's
`ItemType_<systemName>` rows (the same namespacing discipline packs use for their ids). None carry
layout/template/colorscheme/icon fields.

| Item type | Category | Purpose |
|---|---|---|
| `Headless_Master` | site | Area master: site name, locale, menu refs, contact. No layout fields. |
| `Headless_PageProperties` | page | Minimal structural page-property item. No Icon/SubmenuType. |
| `Headless_Page` | page | Generic semantic content node (title/slug/summary/SEO). |
| `Headless_ContentPage` | page | Rich content page; body is portable markdown/structured text. |
| `Headless_Menu` | navigation | Menu container keyed by `MenuKey` (header/footer/catalog) → normalized `Menu[]`. |
| `Headless_MenuItem` | navigation | One nav entry → content path or commerce group/product id. No template selection. |
| `Headless_CustomerCenter` | b2b | Customer-center root: auth requirement + permitted access-user groups. |
| `Headless_AccountSection` | b2b | One account section mapped to a Delivery API endpoint + role (orders/reorder/users/addresses). |
| `Headless_SpecSheet` | commerce-content | Presentation-free product spec sheet (JSON spec rows). |
| `Headless_DownloadableAsset` | commerce-content | Presentation-free datasheet/manual metadata. |

The two candidates that are genuinely presentation-free (spec-sheet, downloadable-asset) are defined
**fresh** in this namespace, not lifted from Swift rows.

## 4. Item-instance id floor band

Item-instance ids are **global per itemType across packs and baselines** because `(itemType,
fields.Id)` pairs land as PK rows in the shared `ItemType_<systemName>` tables. Feature packs occupy
the `100000+` band. **The headless baseline reserves `200000–209999`** for all headless item
instances — a distinct band, well clear of the packs.

- EN instances use even offsets, NL instances use the next (odd) offset, so EN and NL never collide
  within the same `ItemType_Headless_*` table (both language layers write the same tables).
- New headless content takes the next free id in `200000+`.

**Live nuance — the band is an authoring convention, not a DB column.** DW's content deserializer
**reassigns** content-item instance ids on landing: the DB `Id` column is *not* the authored
`fields.Id` (a fresh content-page row can land as `Id=1`, not `200100`). Because `Headless_*` tables
are brand-new tables only this baseline writes, there is zero collision risk regardless of the
reassigned DB id. Verify the band **statically in the YAML** (every authored `"Id": "<n>"` sits in
`200000–209999`), and verify **landing dynamically** (rows appear across `ItemType_Headless_*` with no
`Swift-v2_*` table touched) — do not assert the band against the DB `Id` column.

## 5. EN/NL sibling-area parity

The baseline ships an English area (`Headless`) and a Dutch layer (`Headless Nederlands`), mirroring
the Swift precedent of paired language areas. Two facts to respect:

- **The NL layer needs its own `Content` manifest entry.** A single manifest entry creates only EN;
  the replace/merge manifests must carry **paired** EN (`Headless`) + NL (`Headless Nederlands`)
  entries or NL never lands.
- **NL is authored as a sibling area** (`AreaMasterAreaId: 0`) for deterministic, environment-
  independent parity. Wiring it as a *true DW language layer* (a host-assigned master id, like the
  Swift NL area pointing at the EN area's numeric id) is a separate, still-open step — the sibling-area
  form is what deserializes cleanly today.

Parity is asserted as equal authored page counts per area (EN == NL).

## 6. Disk-overlay staging BEFORE host start

Two surfaces must be on disk **before the host starts**, because DW builds them at startup — staging
them after start is a no-op until the next restart. Both are gate tooling / config (zero custom code,
the disk-overlay precedent), never serialized DB content:

1. **Item types.** DW10 materializes item types from `wwwroot\Files\System\Items\ItemType_<systemName>.xml`
   at startup and **ignores standalone JSON item-type files**. The baseline ships human-authored JSON
   under `itemtypes/`; a converter renders each JSON def to the exact DW item-type XML shape (editor
   map: Text→TextEditor, LongText→LongTextEditor, Checkbox→CheckboxEditor, Integer→IntegerEditor,
   List→DropDownListEditor + Static options, Link→LinkEditor) and writes
   `ItemType_<systemName>.xml` into `Files/System/Items`. Write the XML **UTF-8 with BOM** — DW reads
   these files by BOM, not by the declared encoding attribute. Content that references a `Headless_*`
   type whose XML is not staged fails to deserialize.

2. **Repositories.** Copy `repositories/Headless/*` (`.index` / `.query` / `.facets`) into
   `wwwroot\Files\System\Repositories\Headless\` before start (a file-sentinel idempotent copy). See
   §7.

## 7. Product search surface (repository + query + facets)

The PLP/faceted path needs a `RepositoryName` + `QueryName` pair the stock/harness repository does not
supply (its index has no resolvable query). The headless baseline ships its own complete surface under
`repositories/Headless/`:

- **`Products.index`** — a Lucene `ProductIndexBuilder` (single `Products` instance). Use **only
  fields with backing rows in the target DB**: name/number search fields, a manufacturer facet field,
  a price-bucket grouping, a freetext copy-field, a sort field. **Do not** add
  `ProductCategory|*` custom-field sources unless the products actually have them — an index that
  references a field with no backing row fails the Full build ("field not found in products").
- **`Products.query`** — the named query (`QueryName=Products`). Runtime locale/shop scoping via the
  `Dynamicweb.Ecommerce.Context:LanguageID` / `:ShopID` macros; parameters: `q`/`eq` (text search),
  `GroupID` (collection PLP), `sku`, plus facet params. Paging/sort are Delivery API runtime
  parameters (`PageSize`/`PageIndex`/`SortBy`/`SortOrder`).
- **`Products.facets`** — the facet groups (e.g. Manufacturer, Group, Price buckets). A facet group
  with no backing data lands with `optionCount=0` (present but unpopulated) — that is data-shape, not a
  wiring error.

The provider consumes this via `GET /dwapi/ecommerce/products/search?RepositoryName=Headless&QueryName=Products&…`
(see [`headless-backend.md`](headless-backend.md) §5).

## 8. Deserialize order + Full index build

1. **Stage disk overlays before start** (§6) — item-type XML and the repository files.
2. **Start the host.**
3. **Deserialize `replace/` then `merge/`** — POST `/Admin/Api/SerializerDeserialize` per mode, strict
   mode on. If running shared-catalog, deserialize the base layer's replace+merge first so the
   `Ecom*` catalog exists; the headless leg then lands its `Content` entries on top.
4. **Full index build** — after products exist in the DB, trigger a **Full** build of the `Headless`
   repository's `Products` index and poll the index/instance status paths until it completes within
   the verify timeout. The build must run **after** deserialize (the index is empty until the catalog
   rows land); a stale/empty index makes the search endpoint return zero hits even though the query
   resolves.

## 9. Verification gate

Clean-room, shared-catalog, on the supported Swift version:

- **Deserialize** — `replace/` + `merge/` POST return HTTP 200 with zero strict-mode escalations
  (requires the `Headless_*` item-type XML staged pre-start).
- **Areas** — both `Headless` and `Headless Nederlands` area rows exist.
- **Item rows** — rows land across `ItemType_Headless_*` tables with **no `Swift-v2_*` table touched**;
  authored YAML ids all sit in `200000–209999` (static scan — DW reassigns DB ids, §4).
- **Parity** — authored page count per area is equal (EN == NL) and ≥ 1.
- **Delivery-API read** — `GET /dwapi/frontend/navigations/{areaId}` and `GET /dwapi/content/pages/{id}`
  return the nav + content pages with `Headless_*` fields.
- **Search** — `GET /dwapi/ecommerce/products/search?RepositoryName=Headless&QueryName=Products&LanguageId=ENU&ShopId=SHOP1`
  returns 200 with non-zero `totalProductsCount`; a `q=<known term>` request returns ≥ 1 hit.
- **Facets** — the response carries the facet groups under `facetGroups[].facets[]` with ≥ 1
  populated option; a faceted request (e.g. `GroupID=GROUP1`) returns a strict subset.

**Two things are NOT provable in the harness gate — verify them on a real host:** (1) storefront HTML
render (the clean-room does not provision the server-side product-render index); (2)
permission-gated customer-center access (customer-group → page-permission grants do not materialize
in-gate). In-gate, assert only that the pages/rows deserialize and the permission fields persist, not
that access is enforced.
