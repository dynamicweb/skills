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

## Swift v2.3.0 templates + swift/2.3 baseline

Target **Swift v2.3.0 templates** at the GitHub repo alongside the **`base` layer data** at
`<demo-root>\distribution\layers\base\` (a `config/replace/merge` tree; content lives under
`replace\_content\` + `merge\_content\`). The 2.3.0 release headlines (language selector + improved
off-canvas nav) match this base layer. Legacy content-only Swift2.2 baselines predate this model and
are no longer the default.

Reference: https://github.com/dynamicweb/Swift/releases/tag/v2.3.0
