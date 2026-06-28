# templates.md

> Swift 2.2 template / page-preset catalogue. Source-of-truth: `$env:DW_VAULT\serialized-data\Swift2.2\_content\Swift 2\` deserialized into a running host. Reference Swift v2.3.0 templates at https://github.com/dynamicweb/Swift (requires DW 10.24.6+).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Template categories (vault baseline)

The Swift 2.2 baseline ships these template / page-preset surfaces under `_content\Swift 2\`. Backtick-quote folder names with spaces or underscores when copying into other tools.

| Folder | Role | Re-skin touchpoint |
|--------|------|---------------------|
| `Customer center/` | Logged-in customer self-service + CSR sales-on-behalf section | See [customer-center.md](customer-center.md) — DO NOT re-build |
| `Header _ Footer/` | Site-wide header and footer | Logo + nav + copy edits via Visual Editor (see [re-skin.md](re-skin.md) §1, §3) |
| `Navigation/` | Top nav + footer nav structure | Copy edits via Visual Editor |
| `Page presets/` | Template page-preset definitions (the `_theme` and layout primitives) | Theme tokens via Visual Editor (see [re-skin.md](re-skin.md) §2) |
| `Product Components/` | Product detail page paragraphs | Copy edits only — DO NOT add custom controllers |
| `Search result page/` | Search results page | Copy edits via Visual Editor |
| `Service Pages/` | FAQ, Privacy, About, etc. | Standard CMS pages — copy edits |
| `Shop/` | Catalog browse | Copy edits + product-list paragraph configuration |
| `Shopping cart/` | Cart + checkout flow | Stock — DO NOT customise (high regression risk) |
| `Sign in/` | Login + register | Stock |
| `Newsletter Emails/` + `System emails/` | Email templates | Subject / body copy edits via admin UI |

The baseline ships content-only — no `_sql/` framework-data folder. Framework rows (shops, currencies, countries, languages) must already exist in the target DB before the deserialize lands the area + pages. See [`deserialize-flow.md`](deserialize-flow.md) §3 for the baseline-shape contract.

## Page presets (the Theme primitive)

The `Page presets/` folder is where the Swift theme system lives. Each preset is a paragraph-driven layout:

- **Theme** — color palette, typography, spacing scales. The Visual Editor surface for re-skinning.
- **Header** / **Footer** presets — referenced by every page; one edit cascades site-wide.
- **Page-with-hero**, **Page-narrow**, **Page-full** — layout variants for content pages.

To find the actual preset list on a deserialized host, navigate Admin UI → Pages → Page presets in the navigation tree.

## Page state flags — `active` is "Hidden in Menu", not route availability

The `EcomPages` row carries three orthogonal flags. Misreading them leads to false-alarm "this page is broken" findings during audits, or the opposite mistake of polluting the navigation menu when you only meant to publish a route.

| Flag | What it controls | Default for utility pages |
|---|---|---|
| `published` | Whether the page is in the publish graph (live versus draft) | `true` once content is set |
| `hidden` | Whether the page is **excluded from frontend routing** entirely | `false` — keep routable |
| `active` | Whether the page **appears in the navigation menu** ("Hidden in Menu" toggle in admin) | `false` for cart steps, product detail, asset info |

A page with `published=true, hidden=false, active=false` is **fully reachable** by direct URL and by JS-driven navigation from other pages (asset cards → Cart Service, product cards → Product Detail, etc.). It is correctly hidden from the top navigation. This is the right state for almost every utility page in a Swift demo.

**Gotcha — `mcp__dynamicweb-commerce-mcp__publish_pages` flips both flags.** Despite the name, that tool sets `Active=true, Hidden=false` together. Calling it on a Cart Service or Product Detail page that was deliberately `active=false` will add an unwanted entry to the main nav. To toggle only one flag, use `save_pages` with the field you want.

When auditing a page's runtime reachability, check `published=true` and `hidden=false`. Do **not** flag `active=false` as a problem on its own — that's what keeps the menu clean.

For SQL-direct INSERTs of `Page` / `GridRow` / `Paragraph` rows (bulk seed flows, MCP not available), the full required-NOT-NULL column list — including `PageActiveFrom` / `PageActiveTo` (the silent 404 vector), `ParagraphGlobalId` (INT, not GUID), `ItemInstanceType=''`, the `MAX(Id)` → `TRY_CAST` rule, and the `GridRowSort × 10` slot-reservation pattern — lives in [`sql-direct-seeding.md`](sql-direct-seeding.md).

## Razor pitfalls inside `ViewModelTemplate<>` layouts

Three pitfalls land repeatedly when authoring custom variants under `Paragraph/<ItemType>/` or editing standard `Designs/Swift-v2/` `.cshtml` layouts. All three compile-time fail in subtle ways — the error often surfaces under the *wrong* file.

### `@Html.Raw()` does NOT exist in `ViewModelTemplate<>`

DW10 Razor layouts inheriting `Dynamicweb.Rendering.ViewModelTemplate<>` (e.g. `Swift-v2_Master.cshtml`, every `Paragraph/*` layout) do not expose the MVC `Html` helper. Using `@Html.Raw(value)` fails with `'Html' does not exist in the current context`.

**The error surfaces misleadingly.** The compile error is reported against `Swift-v2_Page.cshtml` as a flood of duplicate-using directives and nullable-annotation warnings — scroll past them to find the real `'Html' does not exist` line at the bottom. If you've added an `@Html.Raw(...)` call somewhere and the build complains about `Swift-v2_Page.cshtml`, that's where to look.

**Fix.** Default to plain `@var`. Razor encodes, but for content without HTML-special characters (`<`, `>`, `&`, `"`, `'`) — CSS custom-property values, brand strings, numeric tokens — the encoding is a no-op. `ShortDescription` / `LongDescription` are already HTML strings; emit them directly (`@product.ShortDescription`) and DW renders them un-escaped. If a value can legitimately contain HTML-special characters, pre-escape in C# before emitting.

### `product.ProductFieldValues` is NOT on `ProductViewModel`

`product.ProductFieldValues` lives on the underlying `Dynamicweb.Ecommerce.Products.Product` entity, NOT on `Dynamicweb.Ecommerce.ProductCatalog.ProductViewModel`. Razor templates that call it against `Model.Product` (a `ProductViewModel`) **compile to a runtime error that surfaces as raw source rendered as page text** on the PDP — typically a wall of Razor markup appearing below the price stack (demo-blocker).

**Fix.** Resolve the underlying entity and read the field collection off it:

```cshtml
@{
    var entity = Dynamicweb.Ecommerce.Services.Products.GetProductById(
        product.Id, product.VariantId ?? "", true);
    var fields = entity?.ProductFieldValues;
}
```

The third argument (`true`) materialises `ProductFieldValues`. Without it the property returns `null` even on a valid entity. See [`dw10-canonical-surfaces.md`](dw10-canonical-surfaces.md) §Products for the canonical accessor.

### `ToggleFavorite.cshtml` silently no-ops when `FavoriteListId=0`

The Swift "Add to favorites" icon embedded inside `Swift-v2_ProductAddToCart` calls `RenderPartial("Components/ToggleFavorite.cshtml", product)` **without** the `ListId` view parameter. ToggleFavorite's resolver then runs:

```csharp
int favoriteListId = GetViewParameter("ListId") != null ? GetViewParameterInt32("ListId") : 0;
```

i.e. `favoriteListId = 0` regardless of how many lists the user has. The rendered button ships `FavoriteListId=0` and the AJAX call to `swift.Favorites.Toggle` either silently fails, adds to "list 0" (no-op), or opens an empty offcanvas panel — depending on whether the user is in single-list or multi-list mode.

**Fix.** Auto-resolve `favoriteListId` to the user's first list when exactly one exists, and route zero-list users to the favorites overview page so they can create one. Patch lives in the project's `Components/ToggleFavorite.cshtml` override (re-skin Tier 2 — sibling layout, stock base untouched):

```cshtml
@{
    var favLists = ...; // resolve via the existing Swift call
    if (favoriteListId == 0 && favLists?.Count() == 1)
        favoriteListId = favLists.First().ListId;
    bool userHasNoLists = favLists == null || !favLists.Any();
    // in the button: if userHasNoLists → onclick navigates to /favorites
}
```

This is a content-layout-only override of an existing item type — doc-sanctioned per [`re-skin.md`](re-skin.md) §Pixel-perfect escalation, no `.cs` involved.

### Customer-number suffix as a role-flag (B2B-friendly)

For "hide prices for installer / browse-only" demos, the lowest-overhead role gate is to bake the role into the user's `AccessUserCustomerNumber` suffix (e.g. `CUST-002-BROWSE`) and read it off `Pageview.User?.CustomerNumber` in any paragraph that needs to gate behavior:

```csharp
bool isBrowseOnly = Pageview.User?.CustomerNumber?.EndsWith("-BROWSE",
    StringComparison.OrdinalIgnoreCase) ?? false;
bool hidePrice = (anonLimitations.Contains("price") && anonymousUser) || isBrowseOnly;
```

No new user group, no `AccessUserPermissions` plumbing, no admin-side wiring beyond seeding the `AccessUserCustomerNumber` field. Extends the existing `Pageview.AreaSettings.AnonymousUsers` machinery rather than introducing a parallel role system.

**When to escalate.** The suffix-as-role pattern is right when the role is a *visibility flag* on the storefront templates (hide price, hide add-to-cart, suppress +POINTS chip) — i.e. you're already touching the relevant paragraph layout. When the role needs to drive Assortments / Shipping methods / Shipping fees / cart-time pricing, escalate to **DC user groups** instead — see [`b2b-dc-pattern.md`](b2b-dc-pattern.md). The two patterns compose: a buyer is both a member of `DC-OMA` (group → unlocks Assortments + Shipping) and carries `CUST-002-BROWSE` as their customer number (suffix → suppresses price display).

## Swift v2.3.0 vs v2.2 baseline

CLAUDE.md endorses targeting **Swift v2.3.0 templates** at the GitHub repo while keeping **Swift 2.2 baseline data** at `$env:DW_VAULT\serialized-data\Swift2.2\`. The 2.3.0 release headlines (language selector + improved off-canvas nav) don't break 2.2 content; you can pull 2.3.0 template files alongside the 2.2 baseline. Pin baseline regeneration to a future polish phase.

Reference link: https://github.com/dynamicweb/Swift/releases/tag/v2.3.0
