# paragraphs.md

> Swift 2.2 paragraph-type survey. Source-of-truth: paragraphs are exposed in admin UI under each page; backing definitions live in `wwwroot/Files/Templates/Paragraph/` (built-in â€” DON'T edit) and the page-preset YAML at `$env:DW_VAULT\serialized-data\Swift2.2\_content\Swift 2\<area>\<page>\<grid-row>\paragraph-*.yml`. Reference Swift v2.3.0 at https://github.com/dynamicweb/Swift.
>
> Swift 2.x guidance â€” never follow `/swift/swift-1/` URLs (different content model, phased out).

## Paragraph categories (Swift 2.2)

Paragraphs in Swift are added to grid rows on a page. Each grid row holds 1+ paragraph; paragraph type determines what's rendered (text, product list, customer-center widget, etc.). Common categories:

| Category | Example types | Where used |
|----------|---------------|------------|
| **Text & content** | Text, Heading, Image, Button | Service pages, page-with-hero layouts |
| **Product** | Product list, Product detail, Product slider, Cross-selling | Shop, Product Components |
| **Customer center** | Order list, Cart list, User profile, Address book, Impersonation control | Customer center/Account, Customer center/CSR |
| **Navigation & layout** | Top nav, Footer nav, Breadcrumbs, Mega-menu | Header _ Footer, Navigation |
| **Forms** | Contact form, Newsletter signup, Login, Register | Service Pages, Sign in |
| **E-commerce flow** | Mini-cart, Cart summary, Checkout step, Payment, Order confirmation | Shopping cart |
| **Search** | Search box, Search results, Facets | Search result page |

The exact paragraph-type list on a running host is enumerable via Admin UI â†’ "Add paragraph" dropdown when editing any grid row.

Picking the type is half the job â€” how many paragraphs a designed section becomes, and what goes in fields vs. rich text, is owned by [content-modeling.md](content-modeling.md).

## Component-first: map the requirement to a standard component BEFORE customising

Swift is a component system. **Before writing or overriding any `.cshtml`, enumerate the standard
components and map the requirement to one.** Most PLP / PDP / navigation needs are already shipped;
reaching for a custom template first is the most common way a Swift demo accrues off-baseline,
unmaintainable code that a Serializer re-deploy silently drops. This generalises the "Don't customise this
paragraph" callouts below into a gate that runs for *every* rendering requirement:

1. **Enumerate candidates** â€” `ls Files/Templates/Designs/Swift-v2/Paragraph/Swift-v2_*` and
   `â€¦/eCom/ProductCatalog/*`; grep the dir for keywords from the requirement (`group`, `poster`, `image`,
   `slider`, `facet`, `related`, `bom`).
2. **Classify** the change: **place** a component on a page Â· **configure** an existing one via its
   item-fields (`get_paragraph_item_field_values` â†’ `set_paragraph_item_fields`) and/or grid placement
   (`save_grid_rows`, `place_paragraph_in_grid`) Â· **override** its template Â· **new `.cs`**.
3. **Pick the lowest tier that works.** Author or override a template only when no standard component +
   configuration fits â€” and log which components you considered and why each was insufficient (the
   `re-skin.md` variant rule + base customisations-ledger). "Customisation" in Swift is mostly
   **placement + item-field config**, not new markup.

**Common need â†’ standard component** (always confirm the live item-type fields; names per Swift v2.3):

| Need | Standard component | Key fields / notes |
|---|---|---|
| Category banner (image + title + desc hero) | `Swift-v2_ProductListGroupPoster` | reads the group `LargeImage` asset; `PosterHeight`, `Layout`, `ImageFilter`, `HideGroupTitle/Description` |
| Category image only | `Swift-v2_ProductListGroupImage` | group image asset |
| Group title + description (no image) | `Swift-v2_ProductListInfo` | `HideGroupTitle`, `HideGroupDescription`, `TitleFontSize` |
| Subgroup navigation (tiles / list / carousel) | `Swift-v2_ProductGroupGrid` / `ProductGroupList` / `ProductGroupSlider` | needs child groups; see `SelectedGroups` + aspect-ratio pitfalls below |
| Related / "similar" products | `Swift-v2_ProductComponentSlider` (+ `eCom/ProductCatalog/ProductSlider.cshtml` service) | `RelationType` (variants/most-sold/trending/latest/related-products); lazy-loads from a Catalog-app **service page** â€” an `eCom_ProductCatalog` app placed in a grid row (an app at `gridRowId=0` never renders, and the service page must be active) |
| Spec / attribute groups | `Swift-v2_ProductFieldDisplayGroupsAccordion` | `FieldDisplayGroups`, `Layout` (bullets/list/table), `HideFieldLabels` |
| BOM / assembled-from | `Swift-v2_ProductBom` | `ListComponentSource` = a Product-card component page |

> Proven 2026-06-21: a "category banner" requirement was first met with a hand-rolled hero template (which
> errored twice) when `Swift-v2_ProductListGroupPoster` already does exactly that. The gate above â€” grep
> the component dir first, classify, configure the standard component â€” is the cheaper and on-baseline path.

## Where to find a paragraph's wiring

To trace what a specific paragraph does on a Swift 2.2 page:

1. Note the page in admin (e.g. `Customer center/CSR/Orders`)
2. The corresponding YAML lives at `$env:DW_VAULT\serialized-data\Swift2.2\_content\Swift 2\Customer center\CSR\Orders\grid-row-1\paragraph-c1-1.yml`
3. The YAML's `Type` field names the paragraph definition; the rest of the YAML carries that paragraph's configured properties

This is read-only inspection â€” you don't edit the vault YAML; you edit paragraph properties via Admin UI Visual Editor on the live host (which writes to the host's project DB, not back to the vault).

## "Don't customise this paragraph" callouts

A few paragraph types are stock-load-bearing for typical B2B-distributor demo differentiators (sales-on-behalf, mixed-source orders, complex pricing) and must NEVER be replaced with custom Razor:

- **Customer center / CSR / Orders paragraph** â€” the stock paragraph already supports impersonation + mixed-source order viewing + the `OrderSource` discriminator badge; rebuilding loses that wiring. See [customer-center.md](customer-center.md).
- **Cart summary / Checkout step paragraphs** â€” high regression risk; touching these triggers the customisations-ledger preflight in base. See [re-skin.md](re-skin.md) "What NOT to touch".
- **Product detail paragraph** â€” relies on the Lucene index + the PIM completeness rules; modifying it can mask "rules don't show" symptoms. See [dynamicweb-pim-demo/references/governance.md](../../dw-demo-pim/references/governance.md).

## Empty `ParagraphTemplate` resolves to the first cshtml alphabetically (silent footgun)

When a `Paragraph` row has `ParagraphTemplate IS NULL` or `ParagraphTemplate = ''`, Swift's template resolver renders it with the **first `.cshtml` alphabetically** in the item-type's `wwwroot/Files/Templates/Designs/Swift-v2/Paragraph/<ItemType>/` folder.

This is a **runtime resolver fact, not a surface-specific gotcha** â€” paragraphs created via MCP `save_paragraphs` (which can leave `template` unset), via SQL `INSERT INTO Paragraph` (where the seeder forgot the column), or via admin UI on an item type that has no default template all hit it the same way. The fix is per-paragraph, regardless of how the row got there.

**The trap.** When you author a custom variant `.cshtml` under `Paragraph/<ItemType>/` for a *specific* page (e.g. a brand-themed hero), if its filename sorts earlier than the stock variants (`Acme*.cshtml` beats `TextCenter.cshtml` / `TextLeft.cshtml` / `TextRight.cshtml` alphabetically), it will **hijack every paragraph of that item type whose `ParagraphTemplate` is empty** â€” including footer paragraphs, header paragraphs, and other pages you didn't write. The symptom is "I added one custom Text variant for one page and now half the site renders with that styling."

### Mitigation 1 â€” naming convention (filesystem surface)

Prefix custom variants with `Z` (or any letter that sorts after the stock variants) so the alphabetical fallback never lands on yours. The stock Swift variants for `Swift-v2_Text` are `TextCenter` / `TextLeft` / `TextRight` â€” a `ZAcmeFoo.cshtml` sorts last and is safe.

Do NOT use `_`-prefixed filenames as the sort-last strategy without verifying â€” some template resolvers in DW filter out `_`-prefixed files entirely as a partials convention; the empty-template fallback may skip them and land on the first non-`_` file instead.

### Mitigation 2 â€” backfill `ParagraphTemplate` (SQL or MCP, surface-tagged)

The more durable fix is to ensure no paragraph relies on the fallback. Both surfaces work; pick by context.

**Preferred surface â€” MCP `save_paragraphs`** (one paragraph at a time):

```
save_paragraphs(id=<paragraphId>, template='TextLeft.cshtml')
```

Use this when you're already editing the paragraph for another reason, or when there are only a handful of paragraphs to backfill. Cache invalidation is automatic.

**SQL-fallback surface â€” bulk UPDATE** (many paragraphs at once, seed-script flows):

```sql
UPDATE Paragraph
SET ParagraphTemplate = 'TextLeft.cshtml'
WHERE ParagraphItemType = 'Swift-v2_Text'
  AND (ParagraphTemplate IS NULL OR ParagraphTemplate = '');
```

This is an UPDATE on an existing `Paragraph` row â€” per [`dynamicweb-pim-demo/references/cache-invalidation.md`](../../dw-demo-pim/references/cache-invalidation.md) "edit-vs-insert rule", **field UPDATEs on existing rows are live, no host restart required.** Confirmed by browsing to the affected pages â€” `ParagraphTemplate` is read live on the next render. Choose a stock variant that produces the right default (`TextLeft.cshtml` is the conventional full-width-left for Swift `Swift-v2_Text`).

Run this BEFORE introducing any `<Brand>*`-prefixed custom variant under that item type's folder; once the backfill is in, the alphabetical fallback no longer fires.

### Where to flag this rule

This rule is referenced from [`re-skin.md` "What NOT to touch"](re-skin.md) â€” when a re-skin introduces a custom variant `.cshtml`, the re-skin recipe's verification step must check whether any paragraphs of the affected item type still have empty `ParagraphTemplate`, and either rename the variant to sort-last or backfill the templates first.

## SQL-direct Paragraph INSERTs â€” see the seeding reference

When seeding Paragraph rows via direct SQL (MCP not available, bulk seed flow, sister-demo replay), the required NOT-NULL columns â€” `ParagraphUniqueId`, `ParagraphGlobalId` (INT despite the name), `ParagraphValidFrom/To`, `ParagraphCreatedDate`/`UpdatedDate`, `ParagraphGridRowColumn` (1-based), `ParagraphTemplate` (do NOT leave empty; see alphabetical-fallback above) â€” plus the matching `ItemType_*` instance-row INSERT (`ItemInstanceType=''`, `MAX(Id)` â†’ `TRY_CAST(Id AS int)`) live in [`sql-direct-seeding.md`](sql-direct-seeding.md). Page-composition cache requires a host restart after every SQL-direct Paragraph INSERT â€” that's bundled into the seeding reference's verification step.

## Configuring paragraph item-type fields (PDP enrichment learnings)

When you create a Swift v2 product paragraph via MCP `save_paragraphs` and the page renders with empty headings or an empty body, the paragraph row exists but its **item-type fields** have not been set. Every Swift v2 paragraph that ships under category `Swift-v2/Paragraphs/ProductPartial` or `Swift-v2/Paragraphs/ProductDetails` is backed by an item type with its own field schema (read the XML at `wwwroot/Files/System/Items/ItemType_<systemName>.xml` for the authoritative list). After creating a paragraph, fill its item-type fields with `set_item_field_values` keyed by `(itemType, itemId, fieldSystemName)`. The `paragraph.header` you set on `save_paragraphs` is the **admin-side row label only** and is NOT rendered on the frontend by stock product paragraphs â€” the visible heading comes from the item-type's `Title` field.

Common pitfalls and the field that fixes each:

| Symptom | Item type | Field to set | Notes |
| --- | --- | --- | --- |
| Empty `<h2></h2>` above the block | any product paragraph | `Title` | Must be non-empty unless `HideTitle=True`. `paragraph.header` is unused. |
| Heading too large/small | any product paragraph | `TitleFontSize` | Static enum: `display-1`..`display-6`, `h1`..`h6`. Defaults vary per type. |
| Specifications accordion renders empty | `Swift-v2_ProductFieldDisplayGroupsAccordion` | `FieldDisplayGroups` | Comma-separated `EcomFieldDisplayGroups.FieldDisplayGroupSystemName` list. **Empty selection = empty render.** |
| Specs include "0" / "No" / blank rows | same | `HideFieldsWithZeroValue` | Set `True` to drop falsy values. |
| Spec layout is bullet/list when you want a table | same | `Layout` | Static enum: `list \| columns \| table \| bullets \| commas`. `table` is cleanest for spec sheets. |
| Documents paragraph shows product images | `Swift-v2_ProductMediaTable` | `ImageAssets` | Comma-separated `EcomDetailsGroup.EcomDetailsGroupSystemName` list. Stock groups: `Images`, `Manuals`. Default = all. Set to `Manuals` for downloads-only. |
| Downloads list shows giant thumbnails | same | `HideThumbnails` | `True` for a clean filename + filetype + size table. |
| Long description has too-wide lines | `Swift-v2_ProductLongDescription` | `TextReadability` | `max-width-on` (default) constrains to a comfortable reading column; `max-width-off` lets text fill the column. |
| Paragraph renders as an empty `<div>` after SQL-direct seed | `Swift-v2_ProductGroupGrid` | `SelectedGroups` | See Â§`ProductGroupGrid.SelectedGroups` below â€” SQL CSV/JSON inserts silently return `null`; needs an MCP save or a variant-cshtml fallback. |

For `IEnumerable<string>` fields (the checkbox-list editors â€” `FieldDisplayGroups`, `ImageAssets`), pass a **comma-separated string** as `value`. The MCP serializer accepts that form and DW renders it correctly. Bracketed-array or JSON encodings are NOT recognised by the stock editors.

### `EcomFieldDisplayGroups` cache invalidation

`ProductFieldDisplayGroupsAccordion` resolves its `FieldDisplayGroups` selection against an in-memory cache of `EcomFieldDisplayGroups` that is populated at host startup. **Inserts/updates to the four backing tables (`EcomFieldDisplayGroups`, `EcomFieldDisplayGroupFields`, `EcomFieldDisplayGroupShops`, `EcomFieldDisplayGroupTranslation`) are NOT picked up live** â€” even when the admin "Cache â†’ Clear all" is clicked. Reliable refresh is a host process restart. Symptom is exactly what it sounds like: the editor's checkbox list shows the new groups (because the editor re-queries SQL on every load), but the rendered accordion is empty.

For seed-script flows that need the accordion to work end-to-end without a manual restart, the workaround is to (a) seed the four tables, (b) issue a `dotnet run` recycle, then (c) configure the paragraph's `FieldDisplayGroups` field. If the paragraph is configured before the cache reload, its stored selection is fine â€” it just won't render until the next process start.

### `ProductGroupGrid.SelectedGroups` â€” SQL-direct seeds don't deserialize

DW10's `ProductCatalogGroupEditor` (the admin Visual Editor's group-picker) stores its `SelectedGroups` field in a format only its own editor understands. SQL-direct seeds with `["GROUP8","GROUP9"]` JSON or `GROUP8,GROUP9` CSV silently return `null` from `Model.Item.GetValue<IList<ProductGroupViewModel>>("SelectedGroups")` â€” the stock `Swift-v2_ProductGroupGrid` template gives up and renders the paragraph as an empty `<div>`.

**Two surfaces work; pick by context:**

**Preferred â€” MCP `set_item_field_values`** on `(itemType: 'Swift-v2_ProductGroupGrid', itemId: <id>)` with the field set the way the admin editor expects. Cache invalidation is automatic; the paragraph renders correctly on next request.

**SQL-fallback â€” variant cshtml with `GetRawValueString` parse.** When SQL is the only available surface (bulk seed flows, headless agent without MCP), extend the variant template to fall through to the raw string when the typed lookup returns empty:

```csharp
@{
    var groupList = Model.Item.GetValue<IList<ProductGroupViewModel>>("SelectedGroups")
                    ?? new List<ProductGroupViewModel>();
    if (groupList.Count == 0)
    {
        string raw = Model.Item.GetRawValueString("SelectedGroups", "").Trim().Trim('[', ']');
        foreach (string token in raw.Split(new[]{',', ';'},
                                           StringSplitOptions.RemoveEmptyEntries))
        {
            var gid = token.Trim().Trim('"');
            var g = Services.ProductGroups.GetGroup(gid);
            if (g != null)
                groupList.Add(ViewModelFactory.CreateView(new ProductGroupViewModelSettings(), g));
        }
    }
    /* render groupList as the variant normally would */
}
```

Authoring a variant cshtml lands in [`re-skin.md`](re-skin.md) Â§Pixel-perfect escalation territory â€” it's a new content layout for an existing item type, doc-sanctioned, no customisations-ledger preflight. Pair with the alphabetical-fallback rule above (a `Z<Brand>*`-prefixed variant or a `ParagraphTemplate` backfill) so the fallback variant doesn't hijack stock ProductGroupGrid paragraphs you didn't seed yourself.

**Likely fires on other Swift list-fields backed by `ProductCatalog*Editor` item editors** â€” `Subgroups`, `SelectedManufacturers`, and similar. Before SQL-seeding any item-type field whose admin editor is a custom picker (`ProductCatalogGroupEditor`, `ProductCatalogManufacturerEditor`, etc.), check whether the typed lookup returns the data; if it returns null, you've hit the same gotcha and the same `GetRawValueString` workaround applies.

### Bootstrap `.ratio` aspect-ratio token vs CSS custom-property

DW10's `Swift-v2_ProductGroupGrid` admin editor stores aspect-ratio as a Bootstrap token (`1x1`, `4x3`, `16x9`) and emits it on the card as `style="--bs-aspect-ratio: 1x1"`. **Bootstrap's `.ratio` class expects `--bs-aspect-ratio` to be a percentage (`100%`, `75%`, `56.25%`)** â€” the token form is invalid CSS, the rule silently no-ops, and the card collapses to `height: 0` with `position: absolute` children spilling outside the parent. Symptom: 192 px of dead grey space where the category tile should be (2026-05-13).

**Fix in `<customer>_custom.css`** â€” override the rule per `ProductGroupGrid` card with a real percentage and re-enable layout:

```css
.item_swift-v2_productgroupgrid .ratio,
.item_swift-v2_productgroupgrid [class*="ratio"] {
    aspect-ratio: 1 / 1;
    height: auto;
    --bs-aspect-ratio: 100%;
    overflow: hidden;
    position: relative;
}
```

The CSS-side fix is faster than parsing the token in the variant cshtml â€” and the token form is editor-stored, so a variant cshtml fix would also need to translate `1x1` â†’ `100%`, `4x3` â†’ `75%`, `16x9` â†’ `56.25%`. Custom.css beats variant Razor for one-line aspect-ratio repairs.

This pitfall composes with `SelectedGroups` above: SQL/JSON-seeded `ProductGroupGrid` paragraphs hit both the typed-lookup-returns-null bug AND the aspect-ratio bug. Fix order is: seed via MCP (preferred) OR add `GetRawValueString` fallback + `aspect-ratio` CSS override (SQL fallback path).

### Field-system-name format

Display-group field links use the pipe-delimited form `ProductCategory|<CategoryId>|<fieldSystemName>` (e.g. `ProductCategory|HeadsetsAttributes|audio_driver_size`). This matches the `id` returned by `mcp__dynamicweb-commerce-mcp__get_product_by_id` in `customFields[].id`. Underlying storage in `EcomProductCategoryFieldValue` splits the parts (`FieldValueFieldCategoryId` + `FieldValueFieldId`); the rendering code synthesises the pipe form when matching against the display group, so the stored `FieldDisplayGroupFieldSystemName` MUST be the full pipe form.

### `Swift-v2_Row` has no item-type fields

The row item type ships with zero custom fields â€” its layout knobs (column definition, container, color scheme, background image) live on the row entity itself and are written via `mcp__dynamicweb-commerce-mcp__save_grid_rows`, not via `set_item_field_values`. Useful row knobs: `definitionId` (1Column / 2Columns / 3Columns / etc.), `colorSchemeId`, `backgroundImage`, `container`. Alternating `colorSchemeId` between adjacent rows on a long PDP gives visual rhythm without touching templates.

### Where the PDP page is sourced from

`ProductDetailRenderGrid.cshtml` is a one-line shim: `RenderGrid(Model.PrimaryOrDefaultGroup.PrimaryPageId > 0 ? Model.PrimaryOrDefaultGroup.PrimaryPageId : detailPage)`. For every product, DW first checks the product's **primary group's `PrimaryPageId`** (`EcomGroups.GroupMetaPrimaryPage`); if it's empty, DW falls back to the page tagged `ProductDetailPage` via navigation tag. **Practical implication:** to roll one PDP layout across the entire catalogue, leave `GroupMetaPrimaryPage` blank on all groups and edit the nav-tag page. To diverge per category (e.g. richer spec accordion for Webcams than for Chairs), set each category's `GroupMetaPrimaryPage` to a category-specific page id.

## ProductHeader inline-enrichment escalation

When the stock `Swift-v2_ProductHeader` paragraph renders a thin PDP (just name + add-to-cart) and the missing context is **per-product data already on the `ProductViewModel`** (manufacturer, SKU, stock pill, short description), the cleanest escalation is a **NEW content layout** of the ProductHeader paragraph â€” not a new paragraph type and not extra grid rows. The customer-extension paths at `Files/Templates/Designs/Swift-v2/Paragraph/Swift-v2_ProductHeader/<MyVariant>.cshtml` are doc-sanctioned per [re-skin.md](re-skin.md) Â§Pixel-perfect escalation.

**ProductViewModel fields that ARE available** (verified in `Dynamicweb.Ecommerce.ProductCatalog.ProductViewModel`):
- `Name`, `Number` (SKU), `ShortDescription`, `LongDescription`
- `ManufacturerName` (NOT `Manufacturer.Name` â€” the relation flattens on the view model)
- `Stock` (decimal), `StockLevel` (string), `NeverOutOfStock` (bool)
- `DefaultImage` (image VM), `Images` (collection)
- `Price` (price VM with `.Formatted`)

**Fields that look like they should exist but DON'T:**
- `product.DefaultUnit` and `product.DefaultUnitName` â€” neither resolves on `ProductViewModel`. The unit data lives on `product.PriceUnitDescription` if at all; for "per box / each" suffixes prefer a static string in the layout or pull from a custom field via `product.GetField("...")`.
- `Manufacturer` as a navigation property â€” use `ManufacturerName` directly.
- `Html` extension methods (`Html.Raw`, etc.) â€” not available in DW Razor layouts the same way as in ASP.NET MVC. `ShortDescription` and `LongDescription` are already HTML strings; emit them directly (`@product.ShortDescription`) and DW renders without escaping. Wrapping in `@Html.Raw(...)` is a compile error.

**Inline-styles vs. CSS file:** for a one-paragraph enrichment, prefer inline `style="..."` that consumes the project's CSS variables (e.g. `style="color: var(--brand)"`) over adding more rules to `<customer>_custom.css`. The layout file becomes self-contained and the upgrade diff stays one file.

## Grid composition cache â€” host restart required for paragraph deletion

DW10 caches a page's **grid composition** (which paragraphs are in which grid rows) in-memory after the first request. **Deleting a paragraph or grid row via SQL, MCP, or admin UI does NOT immediately stop the frontend from rendering it.** Symptom: you delete `Paragraph` row 24 (or its containing `GridRow`), confirm the row is gone from SQL, refresh the page, and the rendered HTML still contains the stale block â€” sometimes only the inner item-type fields go blank (because the field cache invalidated independently) but the wrapper markup persists.

The composition cache survives:
- Admin â†’ Settings â†’ Cache â†’ Clear all (clears content cache, not grid composition)
- DELETE on `Paragraph` / `GridRow` tables
- MCP `delete_paragraphs` / `delete_grid_rows`
- Browser hard refresh / cache disable

The composition cache does NOT survive a host process restart. On Windows + DW10 with `dotnet run`:

```powershell
Get-Process dotnet -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt (Get-Date).AddDays(-2) } | Stop-Process -Force
Start-Process dotnet -ArgumentList "run","--no-build" -WorkingDirectory "<demo>\Dynamicweb.Host.Suite" -RedirectStandardOutput "<demo>\host.log" -NoNewWindow
```

After restart, wait for the host to listen on its port (`netstat -ano | findstr :<port>`) then hit the page once to warm JIT before re-walking.

**Practical rule:** schedule paragraph deletion just BEFORE a host restart you were already planning to do (e.g. after a seed batch, after a styles refresh). Bundling deletion with a deliberate restart avoids the "where did this stale block come from?" hour spent on a phantom symptom.

**Related:** the user/group cache for `AccessUserSecondaryRelation` and `AccessUserUserAndGroupType` updates has the same property â€” see [customer-center.md](customer-center.md) Â§5/Â§6. The general DW10 rule: **any table whose rows are joined into a render-time composition tree (paragraphs, users, groups, navigation) is cached in-memory and needs a process restart to repopulate.**

### `ProductListComponentSelector` caches even harder â€” CSS-hide is the only lever

There's a worse case nested inside the grid-composition cache: when a paragraph's cshtml uses `@RenderGrid(componentPage.ID)` to embed another page's grid into itself, the **inner grid's HTML is cached** and DW10 does NOT observe `ParagraphDeleted = 1` or `ParagraphShowParagraph = 0` on paragraphs inside that nested grid â€” **even after a host restart**. The cache for `RenderGrid`-of-another-page survives the process bounce that flushes everything else in this section.

The canonical surface is Swift's PLP dual-page pattern: a wrapper page hosts a `Swift-v2_ProductListComponentSelector` paragraph that does `@RenderGrid(<inner-page-id>)`; the inner page has its own paragraphs (facets, item-repeater, often a bottom `Swift-v2_ProductListInfo`). Soft-hiding or deleting paragraphs on the inner page leaves them rendered on the wrapper page indefinitely. **The same applies to the PDP's component-source pages** (the product-info / purchase-panel pages a Swift PDP composes via the same pattern) â€” confirmed on a 10.25.x build where a duplicate `ProductVariantSelector` paragraph on a PDP component page ignored `ShowParagraph = 0` even after a host restart (2026-06-09).

**The "two ProductListInfo paragraphs" anatomy.** Swift's stock catalog setup ships a PLP wrapper page (e.g. PageId 71) that hosts `Breadcrumb + ProductListInfo (h3, large title) + ProductListComponentSelector + ProductListNavigation`, plus an inner component-source page (e.g. PageId 57) that the selector renders via `@RenderGrid`. The inner page carries `ProductListFacets + ProductListItemRepeater + a second ProductListInfo (h6, small title)`. The small h6 ProductListInfo lands *under* the product grid + counter â€” visually identical to an orphan category title floating at the bottom of the PLP. SQL `ParagraphDeleted=1` / `ParagraphShowParagraph=0` on the inner paragraph does not hide it (per the cache rule above). CSS-hide the bottom variant explicitly (2026-05-13):

This inverts the [`cache-invalidation.md`](../../dw-demo-pim/references/cache-invalidation.md) "edit-vs-insert rule": UPDATEs on existing rows are normally live, but a `ParagraphDeleted` / `ParagraphShowParagraph` flip on a paragraph rendered through `RenderGrid` is *not*. The `RenderGrid` HTML cache is keyed by the source page id, not by individual paragraph row state.

**The only reliable lever is CSS-hide â€” and it must be cache-proof.** Prefer an inline `<style>` block in `Custom/<customer>HeadInclude.cshtml` over `<customer>_custom.css`: on some builds the CSS file is served under a static version token that browsers never re-fetch (see [`re-skin.md`](re-skin.md) Â§"Wiring up project-scoped custom.css"), so a hide that only lives in the CSS file can silently fail to reach the page. The rule itself:

```css
/* Hide the orphan ProductListInfo on the wrapper PLP */
.item_swift-v2_productlistinfo h1.h6 { display: none !important; }
```

Scope the rule as tightly as possible â€” by item-type class, by paragraph-level data attribute, by parent-page wrapper class â€” so the hide doesn't bleed into other pages where the same paragraph type renders legitimately. Document the workaround inline in the CSS file so the next reader knows to delete it once Swift fixes the cache invariant (don't hold your breath).

**Practical rule:** if a paragraph is inside a page that is `@RenderGrid`-rendered from another page, **assume soft-hide and delete won't work** and reach for CSS-hide on first attempt. Likely fires anywhere a Swift component-selector pattern is in play (the PLP wrapper is the most common, but the pattern is generic to any `RenderGrid(<otherPageId>)` invocation).

**Cross-AREA corollary (validated 2026-06-10):** the cache is keyed by source page id only â€” not by area or culture. If a language layer's component selectors still point at the MASTER's component pages (which is what AreaCopy leaves behind), both areas share one cache entry and whichever context renders first wins: the layer can serve master-language labels, or the master can serve a render produced in the layer's anonymous context. The durable fix is to repoint the layer's `ComponentSource` at the layer's own component-page clones â€” separate page ids, separate cache entries, separately translatable items. See [`language-layers.md`](language-layers.md) Â§"What a full-content AreaCopy does NOT carry".


