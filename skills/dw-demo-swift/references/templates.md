# templates.md

> Swift template / page-preset routing. Source-of-truth: `<demo-root>\distribution\layers\base\replace\_content\Swift 2\` deserialized into a running host. Reference Swift v2.3.0 templates at https://github.com/dynamicweb/Swift (requires DW 10.24.6+).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Contents

- [Reading a live `.cshtml` off a hosted host — `ContentFileByName`](#reading-a-live-cshtml-off-a-hosted-host--contentfilebyname)
- [Verifying a template deploy — the procedure, not a hedge](#verifying-a-template-deploy--the-procedure-not-a-hedge)
- [Branching a template on Visual Editor mode — `Pageview.IsVisualEditorMode`](#branching-a-template-on-visual-editor-mode--pageviewisvisualeditormode)
- [Image focal points are inert unless the layout transports them](#image-focal-points-are-inert-unless-the-layout-transports-them)
- [Two missing guards in stock Swift 2.4 templates — a card that vanishes and a card that throws](#two-missing-guards-in-stock-swift-24-templates--a-card-that-vanishes-and-a-card-that-throws)
- [Swift v2.3.0 templates + swift/2.3 baseline](#swift-v230-templates--swift23-baseline)

Vendor-generic Swift template / page / Razor knowledge is owned by the foundational skills —
routed below. The sections that follow the table are owned here.

| If you need… | Read |
|---|---|
| Template categories (baseline), page presets (the Theme primitive), and the **page-state flags** (`published` / `hidden` / `active` = "Hidden in Menu" semantics; the `publish_pages` both-flags gotcha) | [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §6 |
| `ViewModelTemplate<>` Razor pitfalls — `@Html.Raw()` absent, `product.ProductFieldValues` not on `ProductViewModel` (raw-source-renders-on-PDP), `ToggleFavorite.cshtml` no-op at `FavoriteListId=0` | [`razor-surfaces-and-pitfalls.md`](../../dw-render-razor/references/razor-surfaces-and-pitfalls.md) §2 |
| Customer-number-suffix-as-role-flag (`CUST-…-BROWSE` read off `Pageview.User.CustomerNumber` to hide price / gate a storefront affordance) | [`permission-layers.md`](../../dw-users-permissions/references/permission-layers.md) §16 |
| SQL-direct Page/GridRow/Paragraph required columns (the `PageActiveFrom`/`PageActiveTo` silent-404 vector et al.) | [`sql-direct-seeding.md`](sql-direct-seeding.md) → [`management-api-and-sql.md`](../../dw-data-access/references/management-api-and-sql.md) |
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
whose length equals the batch size** — not `status:ok`; assert the length. `FileDownload` exists but is a
POST *command*, not a query — never fire write verbs speculatively while probing a verb registry.

### Verifying a template deploy — the procedure, not a hedge

**`.cshtml` edits are cache-bypassing on a DW10 cloud host — but prove it per deploy rather than
assuming it, and never recycle "to be safe".** Measured on the layout master itself (upload via
`Dw-UploadFiles -RelDir "Templates/Designs/<design>"`, a multipart `POST /Admin/Api/Upload` with
`allowOverwrite=true`): the very next request rendered the new template, with no recycle, no cache flush,
and `changeversion.txt` untouched. That was demonstrated **positively** — a newly added attribute
appeared in the response — not inferred from an absence. The `DashboardTile.cshtml` / `Paragraph/`
hot-reload precedent extends to `Designs/<design>/` root templates. A needless recycle is not free: on a
cloud host the only "restart" levers are the control files, and reaching for `changeversion.txt` is a
version migration in disguise
([`db-update-recovery.md`](../../dw-demo-base/references/db-update-recovery.md)).

The procedure replaces the hedge:

1. **Deploy, then prove the new template is live by asserting on an OBSERVABLE the edit introduces** — a
   new attribute, a new class, a changed string in the delivered HTML. Only if that observable is
   **absent** do you escalate to a recycle.
2. **Round-trip the upload with `FileByName`.** Templates are **not servable over HTTP** — a GET of
   `/Files/Templates/Designs/<design>/<file>.cshtml` 404s — so the re-download-and-compare check that CSS
   deploys use is unavailable, and a run that skips this is trusting the upload response. The metadata
   read is the proof that *is* available:

   ```
   GET /Admin/Api/FileByName?name=Templates/Designs/<design>/<file>.cshtml
     -> model.sizeInBytes, model.updatedAt
   ```

   Assert `sizeInBytes == the local byte count` **and** that `updatedAt` moved. Together those catch a
   silently-dropped upload, which the upload response alone does not. Worth a shared template-deploy
   helper that does upload + `FileByName` assert in one call, mirroring the CSS deploy scripts.

## Branching a template on Visual Editor mode — `Pageview.IsVisualEditorMode`

**`Pageview.IsVisualEditorMode` is the stock, `@using`-free way to tell editor mode from a visitor
request.** It is a `bool` on `Dynamicweb.Frontend.PageView`, inherited via `ViewModelTemplate<T>`, so it is
available in **every** Swift template with no import and no custom code. The canonical example already
ships in the layout master Swift installs — `Swift-v2_Master.cshtml` gates the GTM snippet on it:

```cshtml
@if (!string.IsNullOrWhiteSpace(googleTagManagerID) && !Pageview.IsVisualEditorMode) { … }
```

Reach for it before querystring sniffing, referrer inspection or header parsing — all of which are
reachable first and all of which are wrong.

**It is server-side and auth-gated, which is what makes it safe for admin-only chrome.** An anonymous
`GET /Default.aspx?ID=<pageId>&visualedit=true` renders **byte-identically** to the friendly URL (only
per-request facet GUIDs differ), and so does the same request carrying an admin API bearer — the API key
buys `/Admin/Api`, not a backend UI session (`/Admin/` 302s to the login form even with the bearer set).
**A visitor cannot provoke an editor-only branch by any querystring.** The two URLs worth knowing:

```
admin screen : /Admin/UI/Content/PageVisualEdit?Id=<pageId>&IsEmailMarketing=False&Type=GetPageById&QueryContext=Dynamicweb.CoreUI.Data.DataQueryContext
the iframe it loads, usable standalone with a backend session:
               /Default.aspx?ID=<pageId>&visualedit=true
```

(`/Admin/Authentication/Login` is a **two-step** form — `#Username` → submit → password → submit — which
matters when scripting a headed verification run.)

### The recipe: admin-editor chrome fixes go in the layout master, never the header template

When the ask is "the header floats over the breadcrumb **in the Visual Editor**", the header template is
the obvious edit site and the wrong one — it changes the LIVE SITE for every visitor. Note in particular
that `Swift-v2_Page.cshtml` does not hard-code the header class; it reads it from the **header page's own
item field**:

```cshtml
if ((headerPage.Item?.TryGetString("HeaderPosition", out string headerPosition) ?? false) && …) { headerCss = headerPosition; }
<header data-swift-page-header="@(headerLink.PageId)" class="@headerCss d-print-none">
```

So editing `HeaderPosition` to "fix the editor" silently removes the sticky header for every visitor, and
forking the vendor header template forks a file Swift upgrades overwrite. The correct, smaller, reversible
edit site is the **layout master**, which already carries the flag — one attribute on `<body>`:

```cshtml
class="@(Pageview.IsVisualEditorMode ? "dw-ve" : null)"
```

then style under `body.dw-ve …` in the site custom sheet. A null-valued attribute emits **no attribute at
all** when false, so the visitor's markup is *unchanged* rather than merely equivalent. The header
template is never touched, the `HeaderPosition` item field is never touched, and the whole change is one
line in a file the demo already mirrors and deploys.

**The load-bearing second half: admin-only CSS must add OFFSET, never BACKGROUND.** A design gate
typically classifies a header as an "overlay" via `(position === "absolute" || position === "fixed") &&
bgAlpha < 0.5`, and only applies its clearance floor when that is false. Putting *any* background with
alpha ≥ 0.5 on the header — even inside an admin-only scope, if that scope were ever mis-written — flips
the classification and fails the clearance asserts on the LIVE storefront, for a change that was supposed
to be admin-only. Write the rule so it **names no header element at all**, so it cannot flip the flag by
construction, and make the deploy script refuse to upload if any `body.dw-ve` rule mentions the header
element, a background or a position. Verify both directions: the hook present in an editor-mode response,
**and** anonymous header fingerprints (computed position, background alpha, height, bounding rect, the
verbatim `<header>` open tag) byte-for-byte identical before vs after, across the demo's page set × both
viewports.

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

## Two missing guards in stock Swift 2.4 templates — a card that vanishes and a card that throws

Both are **vendor template defects**, both present in the shipped Swift 2.4 design (and in the mirrored
`Swift-v2` copies), and both fail the same way: **DW swallows the exception and emits empty output**, so the
component simply is not there. Nothing on the page says why. Fix them at the **edition/layer** level so no
demo inherits them; the demo-side obligation is different for each.

### `GetPage(0)` throws — and `?? 0` is precisely the value that throws

`Dynamicweb.Content.Services.Pages.GetPage(0)` throws `ArgumentException` ("Get page requires a page ID
greater than zero") — **it does not return `null`**. Every customer-centre `Swift-v2_Dashboard_*` template
(chart, list, number and product variants — ten files in the live design plus ten mirrored copies) writes:

```cshtml
var basePageId = baseLinkViewModel?.PageId ?? 0;
var basePage   = Dynamicweb.Content.Services.Pages.GetPage(basePageId);   // 0 is NOT a safe sentinel
```

`PageId` is `0` whenever `BaseLink` does not resolve — most often when a **`ButtonEditor` JSON envelope has
been written into what is actually a `LinkEditor` field**, which the link parser accepts while yielding
`PageId 0`. Symptom: dashboard cards silently disappear, with dozens of `ArgumentException` rows written into
`GeneralLog` in a few minutes.

- **Template fix (edition):** `var basePage = basePageId > 0 ? Dynamicweb.Content.Services.Pages.GetPage(basePageId) : null;`
  — no behaviour change when the id is valid, because the next line already null-checks `basePage?.Icon` and
  falls back to the stock icon.
- **Authoring rule (demo):** `BaseLink` is a **`LinkEditor`** and must hold a plain URL string
  (`Default.aspx?ID=<pageId>`), **never** the `ButtonEditor` envelope. The per-field-type write shapes are in
  [`paragraphs.md`](paragraphs.md).
- **Gate:** render a customer-centre dashboard carrying one `Swift-v2_Dashboard_*` paragraph with an **empty**
  `BaseLink` and assert the card renders **and** `GeneralLog` gains zero `ArgumentException` rows.

### `product.AssetCategories` has no null guard — a stub ProductViewModel passes every non-null check

When a product has **no row for the current ecommerce language**, DW hands the template a **stub**
`ProductViewModel` — non-null, so it passes an `is object` check — whose `AssetCategories` is `null`. The four
stock media templates (`Swift-v2_ProductDefaultImage.cshtml`, `ProductMedia`, `ProductMediaGallery`,
`ProductMediaTable`) enumerate `AssetCategories` with no guard, throwing `ArgumentNullException` **once per
product card rendered** on any storefront whose catalogue is not language-complete. The stub-model behaviour
is exactly what makes the usual non-null check useless as a guard.

- **Template fix (edition):** null-guard `product.AssetCategories` in all four templates. This is **upstream
  robustness**, not the demo fix.
- **Demo obligation:** **mint the missing language rows** (`ProductSetLanguages`). A template guard would mask
  a real data gap; the language rows are what makes the localized PLP correct.
- **Gate:** every product reachable from a localized PLP has a language row for that area's ecom language,
  and the localized PLP renders with zero `ArgumentNullException` rows in `GeneralLog`.

## Swift v2.3.0 templates + swift/2.3 baseline

Target **Swift v2.3.0 templates** at the GitHub repo alongside the **`base` layer data** at
`<demo-root>\distribution\layers\base\` (a `config/replace/merge` tree; content lives under
`replace\_content\` + `merge\_content\`). The 2.3.0 release headlines (language selector + improved
off-canvas nav) match this base layer. Legacy content-only Swift2.2 baselines predate this model and
are no longer the default.

Reference: https://github.com/dynamicweb/Swift/releases/tag/v2.3.0
