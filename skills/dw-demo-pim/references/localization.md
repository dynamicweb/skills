# localization.md

> PIM-side localization in Dynamicweb 10 â€” translating products, product groups, and the eight other ecommerce objects that can carry translations. Loaded from `~/.claude/skills/dynamicweb-pim-demo/SKILL.md` "Where to find things". Sister doc to `dynamicweb-swift-demo/references/language-layers.md` (content/area side).
>
> **TL;DR:** PIM languages live in `EcomLanguages` (the PRODUCT-side language table) and are completely separate from CONTENT-side area language layers (`Area.AreaMasterAreaId`). Translating a product is a write-per-language to `EcomProductTranslation` (and friends) keyed by (ProductId, LanguageId, VariantId). Everything else (variant options, attribute fields, RMA states, countries, currencies, VAT, units, asset categories, custom-field labels) **falls back to the default language** if no row exists â€” translations are additive. Products + product groups are the only objects that **must** be translated to appear in non-default-language frontends.

## When to use

- A demo asks for a second (or third) language on the storefront and the products need localized names / descriptions.
- A customer's pitch includes "we sell into <country>" and the storefront should switch into that language with native field values.
- You need to demo the side-by-side translation UI in PIM.

If the question is "add another **website** in another language," that's [`dynamicweb-swift-demo/references/language-layers.md`](../../dw-demo-swift/references/language-layers.md) (content side). The two surfaces are independent â€” you can have area=da-DK but product values still in en-US (just with a different culture-derived UI chrome) and vice versa.

## The two-table mental model

| Surface | Table | Default seeded | Driver of |
|---------|-------|----------------|-----------|
| **PIM / product** | `EcomLanguages` (`LanguageId` string keys like `LANG1`, `LANG2`) | Yes â€” `LANG1`/en-US/IsDefault=1 | Per-language product names, descriptions, custom-field values, group names, etc. |
| **Content / area** | `Area` (with `AreaMasterAreaId` pointing back) + (legacy) `Languages` table | No â€” `Languages` is empty in a fresh suite scaffold | Page tree, paragraphs, header/footer item references, URL slugs, culture (date/number formatting) |

Both surfaces have a `LanguageId` concept but they are **different ID spaces**. `Area.AreaEcomLanguageId` is the FK that bridges content â†’ PIM (tells the frontend "when rendering this area, fetch product values in language X").

The `Languages` (content) table is empty in a fresh dw10-suite scaffold because language layers are now created via the website-language flow (Settings â†’ Websites â†’ "+ New website Language"), which creates a sibling **Area** row directly â€” the legacy `Languages` table is not populated.

## What can be translated (and what falls back)

Per the official doc page `dynamicweb10/products/concepts/localization.html`:

**Must be translated** (won't appear in non-default-language storefront otherwise):
- Products (`EcomProductTranslation` row per LanguageId)
- Product groups (`EcomGroupTranslation` row per LanguageId)

**Fall back to default language** (translations are nice-to-have, not required):
- Countries
- Currencies
- VAT Groups
- Standard fields
- Global custom fields (the per-product fields you defined)
- Attribute group fields
- Variant Group options
- Relation groups
- Product units
- Asset categories
- Order/Cart/Quote/RMA flow states + RMA events

**Variant rule:** Each language version of a product can have its own variant text per `EcomVariantOptionsTranslation`. But variant **groups** themselves fall back.

## The admin-UI flow (what a human does)

1. Settings â†’ Ecommerce â†’ Languages â†’ add a new language row (give it `LanguageId` like `LANG2`, ISO `Culture` like `nl-NL`, native name "Nederlands").
2. PIM â†’ product list â†’ select one or more products â†’ action menu **"Add languages"** â†’ pick languages + state (Draft/Active) â†’ Save.
3. Open a product â†’ **"Translations"** button â†’ side-by-side editor â†’ fill in fields. Field-locking is controlled by per-field "Editable on language version" config (column `EcomProductField.ProductFieldAllowChangesAcrossLanguages`). **On a fresh dw10-suite scaffold none of the standard text fields have this set â€” every field appears disabled in the side-by-side editor.** See "Enable per-language editing on standard fields" below for the one-time seed.
4. Product groups: open group edit view â†’ action menu **"Manage languages"** â†’ select languages â†’ Create. Then "Translations" same as products.
5. For the eight fallback objects (countries, currencies, etc.): open the object's edit view â†’ **"Translations"** button â†’ side-by-side. Skip unless the storyline cares.

## Backstage data model

`EcomLanguages` (product-side language registry):

| Column | Type | Notes |
|--------|------|-------|
| `LanguageId` | nvarchar | String key, e.g. `LANG1`. Stable across deserializes. |
| `LanguageCulture` | nvarchar | e.g. `en-US`, `nl-NL`, `da-DK`. Drives number/date formatting. |
| `LanguageCode2` | nvarchar | ISO 2-letter code, e.g. `US`, `NL`, `DK`. |
| `LanguageName` | nvarchar | English-language name shown in admin. |
| `LanguageNativeName` | nvarchar | Native-language name, e.g. "Nederlands". Shown in the LanguageSelector dropdown. |
| `LanguageIsDefault` | bit | Exactly one row should be 1; others 0. |

Product translation row (one per product per language):

- `EcomProductTranslation` (verify exact name via `sys.tables LIKE 'EcomProduct%Translation%'` â€” the table also stores a copy of every per-product field with localizable values, including custom fields)

Group translation row:

- `EcomGroupTranslation` (similarly stores per-language name, navigation name, description for each `EcomGroup.GroupId`)

**Schema discovery rule:** When in doubt, `SELECT name FROM sys.tables WHERE name LIKE 'Ecom%Translation%' OR name LIKE 'Ecom%Language%'` first, then `SELECT name FROM sys.columns WHERE object_id = OBJECT_ID('<table>')` to confirm column shape on the demo's specific DW version. Schemas drift between minor DW versions.

## Surfaces â€” which MCP tools do what

Vendor MCP tool naming used here matches `mcp__dynamicweb-commerce-mcp__*` (rename in your demo if the alias differs):

| Want to... | MCP tool (preferred) | SQL fallback |
|---|---|---|
| List existing languages | `get_languages` | `SELECT * FROM EcomLanguages` |
| Create a new EcomLanguage | `save_languages` | `INSERT INTO EcomLanguages (...)` |
| List which language each product is translated to | (none â€” admin-only "Languages overview" page) | `SELECT ProductId, LanguageId FROM EcomProductTranslation` |
| Create a language version of a product | (none â€” admin-only "Add languages" action) | Cloning rows in `EcomProductTranslation` (and any per-field tables) |
| Set/update translated field values | `update_products` with `languageId` param OR `patch_products_safe` | Update column on `EcomProductTranslation` (and per-field translation tables) |
| Translate a group | (none) | Insert + update `EcomGroupTranslation` |

**Important MCP gotcha:** `update_products` accepts a `languageId` parameter. Pass the language string ID (e.g. `LANG2`) to write to that language version. Omitting it writes to the default (master) language. **First call must be against `LANG1` (master)** before `LANG2` can exist â€” DW10 forbids creating language versions of a product whose master row is missing.

**Cache invalidation:** After bulk-translating products, run `mcp__dynamicweb-commerce-mcp__build_assortments` + a full Products `BuildIndex` (`POST /admin/api/BuildIndex {Repository:Products, IndexName:Products.index, BuildName:Full, BuildType:Full}`). The catalog frontend pulls names + facets from the index; without a rebuild, the storefront still renders the master language strings even when the storefront context switches.

## Enable per-language editing on standard fields (one-time seed)

**Symptom:** "I opened a product, clicked Translations, selected Dutch side-by-side with English, and every field is disabled â€” I can't type anything in the Dutch column."

**Root cause:** DW10 has ~40 standard product fields hardcoded in `Dynamicweb.Ecommerce.Products.ProductField.GetStandardProductFieldFallbackInstance` â€” they're presented in the admin product editor whether or not a corresponding `EcomProductField` row exists. **But `AllowChangesAcrossLanguages` defaults to `False`** when there's no DB row, which is what gates the side-by-side editor. A fresh scaffold ships zero standard-field rows in `EcomProductField` (only the 5 custom dimension fields Weight/Height/Width/Depth/Volume are persisted by default), so the side-by-side editor renders every field as read-only.

The fix is to INSERT one `EcomProductField` row per standard field that **needs translation** â€” name, descriptions, meta. Leave physical dimensions, prices, stock, dates, manufacturer FK, etc. alone (they should NOT be per-language). The user's instinct "don't blanket-enable" is exactly right.

```sql
-- Seed standard text fields with AllowChangesAcrossLanguages=1.
-- ProductFieldAutoId is IDENTITY â€” let SQL Server assign it; do NOT include it in the column list.
-- ProductFieldId: stable string key. Convention is FIELD<n> continuing the existing sequence
-- (FIELD1-FIELD7 reserved for the scaffold's dimensions).
INSERT INTO EcomProductField (
  ProductFieldId, ProductFieldName, ProductFieldSystemName, ProductFieldTypeId, ProductFieldTypeName,
  ProductFieldLocked, ProductFieldSort, ProductFieldDoNotRender, ProductFieldIsStandard,
  ProductFieldAllowChangesAcrossLanguages, ProductFieldAllowChangesAcrossVariants,
  ProductFieldRequired, ProductFieldReadOnly,
  ProductFieldShowFieldOnBothMasterAndVariant, ProductFieldUseAsFacet
)
VALUES
  (N'FIELD8',  N'Name',              N'ProductName',             1, N'Text',       1, 0, 0, 1, 1, 1, 0, 0, 0, 0),  -- variants can differ
  (N'FIELD9',  N'Short description', N'ProductShortDescription', 14, N'EditorText', 1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD10', N'Long description',  N'ProductLongDescription',  14, N'EditorText', 1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD11', N'Meta title',        N'ProductMetaTitle',        1, N'Text',       1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD12', N'Meta description',  N'ProductMetaDescription',  2, N'LargeText',  1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD13', N'Meta keywords',     N'ProductMetaKeywords',     2, N'LargeText',  1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD14', N'Meta canonical',    N'ProductMetaCanonical',    1, N'Text',       1, 0, 0, 1, 1, 0, 0, 0, 0, 0),
  (N'FIELD15', N'Meta URL',          N'ProductMetaUrl',          1, N'Text',       1, 0, 0, 1, 1, 0, 0, 0, 0, 0);
```

| SystemName | TypeId/Name | LangEdit | VarEdit | Notes |
|---|---|---|---|---|
| `ProductName` | 1 / Text | âœ“ | âœ“ | Variants often differ ("Red Headset" / "Blue Headset") |
| `ProductShortDescription` | 14 / EditorText | âœ“ | â€“ | RTE field |
| `ProductLongDescription` | 14 / EditorText | âœ“ | â€“ | RTE field |
| `ProductMetaTitle` | 1 / Text | âœ“ | â€“ | SEO |
| `ProductMetaDescription` | 2 / LargeText | âœ“ | â€“ | SEO |
| `ProductMetaKeywords` | 2 / LargeText | âœ“ | â€“ | SEO |
| `ProductMetaCanonical` | 1 / Text | âœ“ | â€“ | SEO |
| `ProductMetaUrl` | 1 / Text | âœ“ | â€“ | Friendly URL slug per language |

**What NOT to seed:** `ProductPrice` (currency-localized via area, not per-language), `ProductStock` / `ProductStockGroupId` (per-warehouse), `ProductNumber` / `ProductEAN` (identifiers), `ProductWeight` / `ProductHeight` / `ProductWidth` / `ProductDepth` / `ProductVolume` (physical attributes â€” already seeded as Lang=0/Var=0 in a fresh scaffold; leave them), `ProductCreated` / `ProductUpdated` (timestamps), `ProductManufacturerId` (FK â€” manufacturer names translate via their own table). The blanket-enable temptation is wrong; surfacing those as editable per-language confuses translators and lets them desync data they shouldn't touch.

**Legacy XML config** (`Files/GlobalSettings.config` â†’ `/Globalsettings/Ecom/ProductLanguageControl/Variant` and `/Language`): older DW10 versions read this XML to populate `EcomProductField` rows at first run. Modern DW10 (â‰¥10.25) marks the migration as complete via `/Globalsettings/Ecom/ProductLanguageControl/MigrationToDatabaseDone = true` after the first walk, after which the XML is ignored and the DB rows are authoritative. **Don't edit the XML â€” it's vestigial.** Insert/UPDATE the DB rows directly per the recipe above.

**Cache:** the EcomProductField list is loaded at startup. Restart the host after seeding before reopening a product translation page.

## Recipe â€” adding a new language to a PIM-only demo

1. **Verify the demo's framework readiness** â€” does the host have countries/currencies/area set up? Check `EcomLanguages` for default row first.
2. **Insert the new EcomLanguage row** (admin UI: Settings â†’ Ecommerce â†’ Languages â†’ "+ New", or via SQL if scripted):
   ```sql
   INSERT INTO EcomLanguages (LanguageId, LanguageCulture, LanguageCode2, LanguageName, LanguageNativeName, LanguageIsDefault)
   VALUES (N'<langId>', N'<culture>', N'<iso2>', N'<englishName>', N'<nativeName>', 0);
   ```
3. **Pick the products to translate**. For a demo, translate **only the hero SKUs the storyline lands on** (typically 5-12 products) plus all the catalog group names â€” translating the full catalogue is wasted demo budget.
4. **Translate group names** first (groups must be translated so the navigation tree localizes). Use `update_groups` MCP with `languageId=<new>` OR direct SQL `INSERT INTO EcomGroupTranslation`. **This step is load-bearing, not cosmetic (validated DW 10.25.x, 2026-06-10):** `Services.ProductGroups.GetGroup(id)` resolves against the CURRENT language context, and with no group rows for the new language it returns null â€” group-driven frontend components (`Swift-v2_ProductGroupGrid`, group-name surfaces) render **empty**, not English-fallback. The proven shape on 10.25 is a per-language `EcomGroups` row per group (clone the default-language rows overriding `GroupLanguageId` + `GroupName` via a dynamic column-list INSERT that excludes identity columns). A blank category grid on a language layer is this gap, every time.
5. **Translate the hero products' name + short description** via `update_products`/`patch_products_safe` with `languageId=<new>`. Skip custom-field translation in a first pass; the fallback handles it.
6. **Rebuild the index** + run `build_assortments` if assortments are in play.
7. **Wire the area** to the new language as a SECOND language layer â€” see [`dynamicweb-swift-demo/references/language-layers.md`](../../dw-demo-swift/references/language-layers.md). On the area side you need a sibling `Area` row with `AreaEcomLanguageId=<langId>` so the storefront actually serves the translated values.

## Demo philosophy

PIM localization sells the "single product master, multiple market storefronts" story â€” high-leverage. But:

- **Translate depth, not width.** Localize 8-12 SKUs that the demo flow touches (hero PLPs + PDPs). Don't translate the long-tail; the customer can't see it during a 45-minute demo and you've wasted hours.
- **Translate at least one custom field** (e.g. a marketing tagline) to show the "all field types translatable" point. Translating ONLY the name leaves the demo feeling shallow.
- **Translate group names** (navigation localizes) â€” this is the most visible win per minute of effort.
- **Skip variant options + assets translation** unless the customer's pitch specifically lands on them. Fallback covers the rest.

## Cross-references

- [`dynamicweb-swift-demo/references/language-layers.md`](../../dw-demo-swift/references/language-layers.md) â€” the area / content side of the same picture; how to add a website language layer + wire the Swift `LanguageSelector` paragraph type so the frontend can actually switch.
- [`dynamicweb-pim-demo/references/canonical-setup-order.md`](canonical-setup-order.md) â€” fits between Step 3 (languages) and Step 4 (manufacturers); the first EcomLanguage row is set up there, additional languages follow this doc.
- Official Dynamicweb doc: `https://doc.dynamicweb.dev/manual/dynamicweb10/products/concepts/localization.html`


