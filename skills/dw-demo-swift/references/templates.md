# templates.md

> Swift template / page-preset routing. Source-of-truth: `<demo-root>\distribution\layers\base\replace\_content\Swift 2\` deserialized into a running host. Reference Swift v2.3.0 templates at https://github.com/dynamicweb/Swift (requires DW 10.24.6+).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

This file is now a router. The vendor-generic Swift template / page / Razor knowledge that used to
live here has been folded up into the foundational candidates; the demo skill points at them.

| If you need… | Read |
|---|---|
| Template categories (baseline), page presets (the Theme primitive), and the **page-state flags** (`published` / `hidden` / `active` = "Hidden in Menu" semantics; the `publish_pages` both-flags gotcha) | [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §6 |
| `ViewModelTemplate<>` Razor pitfalls — `@Html.Raw()` absent, `product.ProductFieldValues` not on `ProductViewModel` (raw-source-renders-on-PDP), `ToggleFavorite.cshtml` no-op at `FavoriteListId=0` | [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §2 |
| Customer-number-suffix-as-role-flag (`CUST-…-BROWSE` read off `Pageview.User.CustomerNumber` to hide price / gate a storefront affordance) | [`users-permissions.md`](../../dw-demo-base/references/foundational/users-permissions.md) §16 |
| SQL-direct Page/GridRow/Paragraph required columns (the `PageActiveFrom`/`PageActiveTo` silent-404 vector et al.) | [`sql-direct-seeding.md`](sql-direct-seeding.md) → [`data-access.md`](../../dw-demo-base/references/foundational/data-access.md) |
| Paragraph types + the component-first gate | [`paragraphs.md`](paragraphs.md) |
| Header nav that reads as a menu — carets/hover/reachable dropdowns, the `save_groups` nav-depth recipe, and the three Razor/Bootstrap interaction platform-truths (Popper-gap bridge, `::after` caret/underline collision, dropdown `min-width`) | [`header-menu.md`](header-menu.md) |

## Reading a live `.cshtml` off a hosted host — `ContentFileByName`

Backing up a live template before editing it is the mandatory first step of any non-CSS deploy, and
neither obvious route works: templates under `/Files/Templates` are **not** served over HTTP by the
delivery side (a GET of the template URL 404s), and the Management API read verb is named
`ContentFileByName` — `FileContent`, `FileText`, `FileByPath`, `Download` and `FileInfo` all return
`Unknown query`, while `FilesByDirectory` and `FileByName` return metadata only, so they read as
near-misses rather than wrong verbs.

```
GET /Admin/Api/ContentFileByName?FilePath=/Files/Templates/Designs/<design>/Paragraph/<name>.cshtml
  -> model.fileContents = the whole file as a string
```

That makes templates fully round-trippable: pull → sha256-diff against the local staging mirror
(record the drift; live wins) → edit → upload → verify. On upload, the response `model` is a **LIST
whose length equals the batch size** — not `status:ok`; assert the length. Then fetch a page that
renders the template with `Cache-Control: no-cache`: a `Paragraph/*.cshtml` change is live on the
FIRST request after upload — no recycle, no `changeversion.txt` touch (the `DashboardTile.cshtml`
hot-reload precedent extends to `Paragraph/`). `FileDownload` exists but is a POST *command*, not a
query — never fire write verbs speculatively while probing a verb registry.

## Image focal points are inert unless the layout transports them

Before recommending or writing `FocalX` / `FocalY` on an image binder, probe what the rendered
`<img>` actually receives — otherwise you store numbers that change nothing, which reads as an
applied fix at the next read. Two independent reasons they do nothing:

- The image is served as `GetImage.ashx?width=<w>&format=webp` with **no** `Ratio` and no crop
  params, so the delivered file keeps the source aspect (e.g. 1680×1119 = the source 3:2) and the
  crop happens entirely in CSS `object-fit: cover`.
- The Swift **image** layout emits no `object-position` on the `<img>` (`class="img-fluid"`, inline
  style null); only the **poster** layout does (`class="object-fit-cover"`,
  `style="object-position: 50% 50%"`). With no `object-position`, the focal value has no transport
  to the browser.

`FocalX` additionally can never act when the rendered box is WIDER than the source aspect — `cover`
then only ever trims height. If neither transport exists, either set `Ratio` on the binder so the
crop is baked server-side, or express the correction as CSS `object-position`, keyed on the image
file name rather than `nth-of-type` so it survives a row reorder. Assert the **computed**
`object-position` on the target `<img>`; a binder read-back proves storage, never effect.

## Swift v2.3.0 templates + swift/2.3 baseline

Target **Swift v2.3.0 templates** at the GitHub repo alongside the **`base` layer data** at
`<demo-root>\distribution\layers\base\` (a `config/replace/merge` tree; content lives under
`replace\_content\` + `merge\_content\`). The 2.3.0 release headlines (language selector + improved
off-canvas nav) match this base layer. Legacy content-only Swift2.2 baselines predate this model and
are no longer the default.

Reference: https://github.com/dynamicweb/Swift/releases/tag/v2.3.0
