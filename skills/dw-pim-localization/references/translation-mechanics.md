# Product translation mechanics — tables, verbs, flags, traps

PIM-side localization in Dynamicweb 10 — translating products, product groups, and the eight other
ecommerce objects that can carry translations. Field-validated internals: the two-table mental model,
the `EcomProductField` flag gates, the facet-label wipe hazard, and the new-language platform steps.

## Contents

- [The two-table mental model](#the-two-table-mental-model)
- [What can be translated (and what falls back)](#what-can-be-translated-and-what-falls-back)
- [The admin-UI flow (what a human does)](#the-admin-ui-flow-what-a-human-does)
- [Backstage data model](#backstage-data-model)
- [Surfaces — which MCP tools do what](#surfaces--which-mcp-tools-do-what)
- [Enable per-language editing on standard fields (one-time seed)](#enable-per-language-editing-on-standard-fields-one-time-seed)
- [Read `EcomProductField` BEFORE planning any per-language or per-variant product write](#read-ecomproductfield-before-planning-any-per-language-or-per-variant-product-write)
- [Per-product category field VALUES are language-invariant by configuration](#per-product-category-field-values-are-language-invariant-by-configuration--the-language-column-is-a-decoy)
- [Facet option labels: the MCP route writes them, and an admin edit destroys them](#facet-option-labels-the-mcp-route-writes-them-and-an-admin-edit-destroys-them)
- [Minting the language ROW comes first](#minting-the-language-row-comes-first-and-a-400-unable-to-load-query-parameters-means-the-row-is-missing)
- [Per-language PIM chrome IS writable: four verbs, three payload shapes](#per-language-pim-chrome-is-writable-four-verbs-three-payload-shapes)
- [Order / quote / cart state badges — `OrderStateTranslationSave`](#order--quote--cart-state-badges--orderstatetranslationsave-no-sql-needed)
- [Adding a new language — the platform steps](#adding-a-new-language--the-platform-steps)
- [Cross-references](#cross-references)

**TL;DR:** PIM languages live in `EcomLanguages` (the PRODUCT-side language table) and are completely
separate from CONTENT-side area language layers (`Area.AreaMasterAreaId`). Translating a product is a
write-per-language to `EcomProductTranslation` (and friends) keyed by (ProductId, LanguageId,
VariantId). Everything else (variant options, attribute fields, RMA states, countries, currencies,
VAT, units, asset categories, custom-field labels) **falls back to the default language** if no row
exists — translations are additive. Products + product groups are the only objects that **must** be
translated to appear in non-default-language frontends.

## The two-table mental model

| Surface | Table | Default seeded | Driver of |
|---------|-------|----------------|-----------|
| **PIM / product** | `EcomLanguages` (`LanguageId` string keys like `LANG1`, `LANG2`) | Yes — `LANG1`/en-US/IsDefault=1 | Per-language product names, descriptions, custom-field values, group names, etc. |
| **Content / area** | `Area` (with `AreaMasterAreaId` pointing back) + (legacy) `Languages` table | No — `Languages` is empty in a fresh suite scaffold | Page tree, paragraphs, header/footer item references, URL slugs, culture (date/number formatting) |

Both surfaces have a `LanguageId` concept but they are **different ID spaces**. `Area.AreaEcomLanguageId`
is the FK that bridges content → PIM (tells the frontend "when rendering this area, fetch product
values in language X").

The `Languages` (content) table is empty in a fresh dw10-suite scaffold because language layers are now
created via the website-language flow (Settings → Websites → "+ New website Language"), which creates a
sibling **Area** row directly — the legacy `Languages` table is not populated.

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

**Variant rule:** Each language version of a product can have its own variant text per
`EcomVariantOptionsTranslation`. But variant **groups** themselves fall back.

### "Falls back" means to the DEFAULT language row, and only to that one

The fallback reads one layer: the language marked `LanguageIsDefault=1`. It is not a search across
the other layers, so **rows authored under a non-default layer are invisible, not "fallen back"** —
`StockLocation.GetName(languageId)` and its siblings look for the requested language, then the
default, and stop. A restored or cloned database is where this bites: a translation set can exist
only under a dead layer (`EcomUnitTranslations`, `EcomStockLocationTranslations` and
`EcomDetailsGroupTranslation` all under one legacy `LanguageId`) while the live site's default is a
different one, and the result is empty unit names on the PDP and MCP `get_stock_locations` returning
`name: ""` for every location. Marking a different language default does not rescue them either —
measured before and after exactly that fix, with the same empty result both times.

**So author or migrate those rows under the site's live default language rather than relying on
cross-language fallback.** Establish which layer that is (`SELECT LanguageId FROM EcomLanguages WHERE
LanguageIsDefault = 1`) before writing anything, then write through the verb that owns the object
where one exists — MCP `save_unit_translation`, `save_group_translations`, `set_option_translations`,
`save_country_translation` and the rest of the chrome table below. `EcomDetailsGroupTranslation` has
no verb on 10.28.x, so asset-category names are a SQL insert (local install only; restart the host
afterwards to flush the ecommerce caches). Re-run the empty-string probe on the rendered surface to
confirm.

### A missing translation is never an error — and each view model hides it differently

Nothing reports a missing translation row, and the delivery API's fallbacks differ **within one
response**, so a name that looks right can mean the row is absent:

| Surface | What a missing row returns | Consequence |
|---|---|---|
| `assetCategories[].name` (`/dwapi/ecommerce/products/{id}`) | the **SystemName** — the view model is SystemName-derived on this build and never consults `EcomDetailsGroupTranslation` | asking for a language with zero translation rows in any layer still returns a plausible English name, so this endpoint **cannot verify an asset-category translation** |
| `relatedGroups[].name` | the **raw id** (`{"id":"<RELGROUPID>","name":"<RELGROUPID>"}`) | a name equal to the id is a missing-row signal, not a label |

Verify an asset-category translation by reading `EcomDetailsGroupTranslation` directly, or by
rendering one of the templates that actually call `DetailsGroup.GetName()`. Make the two checks
standing assertions: every group referenced by a live product has `name != id`, and every
`EcomDetailsGroup` has a row in the default language before any surface trusts `assetCategories[].name`.

## The admin-UI flow (what a human does)

1. Settings → Ecommerce → Languages → add a new language row (give it `LanguageId` like `LANG2`, ISO `Culture` like `nl-NL`, native name "Nederlands").
2. PIM → product list → select one or more products → action menu **"Add languages"** → pick languages + state (Draft/Active) → Save.
3. Open a product → **"Translations"** button → side-by-side editor → fill in fields. Field-locking is controlled by per-field "Editable on language version" config (column `EcomProductField.ProductFieldAllowChangesAcrossLanguages`). **On a fresh dw10-suite scaffold none of the standard text fields have this set — every field appears disabled in the side-by-side editor.** See "Enable per-language editing on standard fields" below for the one-time seed.
4. Product groups: open group edit view → action menu **"Manage languages"** → select languages → Create. Then "Translations" same as products.
5. For the eight fallback objects (countries, currencies, etc.): open the object's edit view → **"Translations"** button → side-by-side. Skip unless these objects need translating.

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

- `EcomProductTranslation` (verify exact name via `sys.tables LIKE 'EcomProduct%Translation%'` — the table also stores a copy of every per-product field with localizable values, including custom fields)

Group translation row:

- `EcomGroupTranslation` (similarly stores per-language name, navigation name, description for each `EcomGroup.GroupId`)

**Schema discovery rule:** When in doubt, `SELECT name FROM sys.tables WHERE name LIKE 'Ecom%Translation%' OR name LIKE 'Ecom%Language%'` first, then `SELECT name FROM sys.columns WHERE object_id = OBJECT_ID('<table>')` to confirm column shape on the specific DW version. Schemas drift between minor DW versions.

## Surfaces — which MCP tools do what

| Want to... | MCP tool (preferred) | SQL fallback |
|---|---|---|
| List existing languages | `get_languages` | `SELECT * FROM EcomLanguages` |
| Create a new EcomLanguage | `save_languages` | `INSERT INTO EcomLanguages (...)` |
| List which language each product is translated to | (none — admin-only "Languages overview" page) | `SELECT ProductId, LanguageId FROM EcomProductTranslation` |
| Create a language version of a product | (none — admin-only "Add languages" action) | Cloning rows in `EcomProductTranslation` (and any per-field tables) |
| Set/update translated field values | `update_products` with `languageId` param OR `patch_products_safe` | Update column on `EcomProductTranslation` (and per-field translation tables) |
| Translate a group | (none) | Insert + update `EcomGroupTranslation` |

**Important MCP gotcha:** `update_products` accepts a `languageId` parameter. Pass the language string
ID (e.g. `LANG2`) to write to that language version. Omitting it writes to the default (master)
language. **First call must be against `LANG1` (master)** before `LANG2` can exist — DW10 forbids
creating language versions of a product whose master row is missing.

**`create_products` ignores `languageId` — every new product lands on the master (default) language.**
Unlike `update_products`, the `create_products` tool honors no language parameter: it writes each
product to the default `EcomLanguages` row (`LanguageIsDefault=1` — typically `LANG1`/en-US, i.e. ENU).
If the storefront's area serves a **different** language layer, those products are **invisible on that
PLP** — products are on the must-translate list (above), so a product with no translation row for the
served language does not render (the PLP comes up empty even though the products exist in admin). Two
recoveries, depending on intent:

- The product should exist in the served language *in addition* to the default → after `create_products`,
  add the language version and write name/description via `update_products` with `languageId=<served>`
  (or SQL on `EcomProductTranslation`), then rebuild the Products index.
- The served language should itself be the default the products land on → set that `EcomLanguages` row
  `LanguageIsDefault=1` **before** `create_products`, or SQL-repoint the created rows' language column,
  then rebuild the index.

**Validate:** after the index rebuild, the product is visible on the served-language PLP (not just in
the admin product list).

**The group-translation null gotcha (validated DW 10.25.x):** translating group names is **load-bearing,
not cosmetic.** `Services.ProductGroups.GetGroup(id)` resolves against the CURRENT language context, and
with no group rows for the new language it returns **null** — group-driven frontend components
(`Swift-v2_ProductGroupGrid`, group-name surfaces) render **empty**, not English-fallback. The proven
shape on 10.25 is a per-language `EcomGroups` row per group (clone the default-language rows overriding
`GroupLanguageId` + `GroupName` via a dynamic column-list INSERT that excludes identity columns). A
blank category grid on a language layer is this gap, every time. Use `update_groups` MCP with
`languageId=<new>` OR direct SQL `INSERT INTO EcomGroupTranslation` / per-language `EcomGroups` rows.

**Cache invalidation:** After bulk-translating products, run the `build_assortments` MCP tool
plus a full Products `BuildIndex`
(`POST /admin/api/BuildIndex {Repository:Products, IndexName:Products.index, BuildName:Full, BuildType:Full}`).
The catalog frontend pulls names + facets from the index; without a rebuild, the storefront still renders
the master language strings even when the storefront context switches.

## Enable per-language editing on standard fields (one-time seed)

**Symptom:** "I opened a product, clicked Translations, selected a second language side-by-side with
English, and every field is disabled — I can't type anything in the second column."

**Root cause:** DW10 has ~40 standard product fields hardcoded in
`Dynamicweb.Ecommerce.Products.ProductField.GetStandardProductFieldFallbackInstance` — they're presented
in the admin product editor whether or not a corresponding `EcomProductField` row exists. **But
`AllowChangesAcrossLanguages` defaults to `False`** when there's no DB row, which is what gates the
side-by-side editor. A fresh scaffold ships zero standard-field rows in `EcomProductField` (only the 5
custom dimension fields Weight/Height/Width/Depth/Volume are persisted by default), so the side-by-side
editor renders every field as read-only.

The fix is to INSERT one `EcomProductField` row per standard field that **needs translation** — name,
descriptions, meta. Leave physical dimensions, prices, stock, dates, manufacturer FK, etc. alone (they
should NOT be per-language).

```sql
-- Seed standard text fields with AllowChangesAcrossLanguages=1.
-- ProductFieldAutoId is IDENTITY — let SQL Server assign it; do NOT include it in the column list.
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
| `ProductName` | 1 / Text | ✓ | ✓ | Variants often differ ("Red Headset" / "Blue Headset") |
| `ProductShortDescription` | 14 / EditorText | ✓ | – | RTE field |
| `ProductLongDescription` | 14 / EditorText | ✓ | – | RTE field |
| `ProductMetaTitle` | 1 / Text | ✓ | – | SEO |
| `ProductMetaDescription` | 2 / LargeText | ✓ | – | SEO |
| `ProductMetaKeywords` | 2 / LargeText | ✓ | – | SEO |
| `ProductMetaCanonical` | 1 / Text | ✓ | – | SEO |
| `ProductMetaUrl` | 1 / Text | ✓ | – | Friendly URL slug per language |

**What NOT to seed:** `ProductPrice` (currency-localized via area, not per-language), `ProductStock` /
`ProductStockGroupId` (per-warehouse), `ProductNumber` / `ProductEAN` (identifiers), `ProductWeight` /
`ProductHeight` / `ProductWidth` / `ProductDepth` / `ProductVolume` (physical attributes — already
seeded as Lang=0/Var=0 in a fresh scaffold; leave them), `ProductCreated` / `ProductUpdated`
(timestamps), `ProductManufacturerId` (FK — manufacturer names translate via their own table). Surfacing
those as editable per-language confuses translators and lets them desync data they shouldn't touch.

**Legacy XML config** (`Files/GlobalSettings.config` → `/Globalsettings/Ecom/ProductLanguageControl/Variant`
and `/Language`): older DW10 versions read this XML to populate `EcomProductField` rows at first run.
Modern DW10 (≥10.25) marks the migration as complete via
`/Globalsettings/Ecom/ProductLanguageControl/MigrationToDatabaseDone = true` after the first walk, after
which the XML is ignored and the DB rows are authoritative. **Don't edit the XML — it's vestigial.**
Insert/UPDATE the DB rows directly per the recipe above.

**Cache:** the EcomProductField list is loaded at startup. Restart the host after seeding before
reopening a product translation page.

## Read `EcomProductField` BEFORE planning any per-language or per-variant product write

`ProductSave` returns `status: ok` for fields it never writes. Three separate registration/flag facts decide
whether a field can take the value, and none of them produce an error — the save echoes the posted model and
`ProductById` reads it back, which makes the round trip look convincing.

- **An unregistered field is DISCARDED.** `EcomProductField` ships rows for `ProductMetaTitle` and
  `ProductMetaUrl` but, on a fresh install, **no row at all for `ProductMetaDescription` or
  `ProductMetaKeywords`** — and the save pipeline drops fields it has no row for. Measured on one translation
  run: 148 saves carried translated `metaTitle`, `metaDescription` and `metaKeywords` in the same model;
  `metaTitle` landed for every language, and **0 of 194 localized rows differed from the master** on either of
  the other two, anywhere in the table. Net effect on the storefront: localized PDPs serve a translated
  `<title>` with an untranslated `<meta name="description">` and `og:description`. The fix is **registration**
  — the seed above already includes `ProductMetaDescription` / `ProductMetaKeywords`, after which the same
  `ProductSave` path works unchanged.
- **`AllowChangesAcrossVariants=False` silently ignores a per-variant write of that field.**
  `ProductShortDescription` ships `False` (while `ProductName` and `ProductLongDescription` ship `True`), so
  the master value is pushed to every variant row and a per-variant write of that one field is discarded —
  `ProductSave` returns `ok` and the row keeps the master text. What makes it look arbitrary is that names and
  long descriptions on the **same rows in the same call** save correctly and stay variant-specific.
- **`AllowChangesAcrossLanguages=False` does the same for a per-language write** (§"Enable per-language
  editing on standard fields" above is the seed that flips it).

**Rule: for each field you intend to write, read its `EcomProductField` flags first and verify the result
against `EcomProducts`, never against the `ok` response.** A harness leg that asserts the flag permits the
write before attempting it turns a silent no-op into a red step.

## Per-product category field VALUES are language-invariant by configuration — the language column is a decoy

`EcomProductCategoryFieldValue` carries a `FieldValueProductLanguageId` column, which reads as "spec values are
translatable". They are not, unless the field says so: with `FieldAllowChangesAcrossLanguages=False` on the
category field, the VALUE is language-invariant by configuration and `ProductById` reports every one of those
fields `readonly: true`. Measured on one catalogue: 56 attribute fields all carrying the flag `False`, and
**zero** localized values differing from their master twin anywhere in the table — PDP specification values
stay in the master language no matter how they are written.

**A language column on a table does not imply a translatable value.** Localizing spec values is a **PIM
data-model change first** (flip `FieldAllowChangesAcrossLanguages` via `ProductFieldSave`), not a translation
task — so scope it as a modelling decision, or exclude it explicitly from the language pass rather than
attempting it and reporting a failure.

## Facet option labels: the MCP route writes them, and an admin edit destroys them

Two facts that turn "translate the PLP filters" from a write into a project:

- **The index value is the option KEY and must never be translated** (`StainlessSteel`, `Zinc`) — translating
  it breaks the filter. The PLP sidebar renders `facetOption.Label`, and the per-language display name lives in
  **`EcomFieldOptionTranslation`**.
- **The Management API `ProductFieldOptionSave` has no language dimension, but MCP
  `set_option_translations` does.** `ProductFieldOptionSave`'s model is
  `{OptionId, FieldId, Name, Value, IsDefault, Sort, Image}`, one `Name` only, so that verb cannot express a
  per-language option label. The MCP route writes them directly:
  `set_option_translations {requests:[{fieldId:"ProductCategory|<cat>|<field>", optionValue:"corrosive",
  languageId:"FRC", name:"Corrosif"}]}` landed 88/88 rows, `EcomFieldOptionTranslation` FRC rows 0 → 88,
  SQL-verified. Reach for that before SQL. Option ids live in the
  `ProductCategory|reference_category|<field>` bucket, not the per-type qualified twins
  ([dw-pim-modelling structural-model.md](../../dw-pim-modelling/references/structural-model.md) §2.8).
- **The option collection is cached in-process and does not pick the rows up.** Neither a cache-busted request
  (`?cb=<guid>`) nor a `ProductFieldOptionSave` round-trip on the same option surfaced the inserted labels —
  the localized PLP kept rendering master-language options. **Facet option labels require an app-pool recycle
  to go live**, so sequence any language work that includes them against a recycle window.
- **STANDING HAZARD: `ProductFieldOptionSave` WIPES that option's other-language rows.** The save replaces the
  option's translation set from a model carrying a single `Name`, so every other-language row is dropped —
  measured directly, and it fires on **normal admin use**: an editor tweaking one facet option in the UI
  silently destroys its localizations. **Re-apply the per-language names after any facet option edit**, and
  assert the `EcomFieldOptionTranslation` row count per option is unchanged across one.

## Minting the language ROW comes first, and a `400 "Unable to load query parameters"` means the row is missing

A translation write needs a row to write into, and the two creates work differently.

- **`ProductSave` writes exactly ONE `EcomProducts` row, the language it was called with.** It does not
  fan out to the other site languages, so a freshly created product is single-language. Measured on one
  host: 11 969 of 12 059 products had exactly 1 language row; the 90 with 3 were the ones a translation
  pass had explicitly minted. `ProductCreated` on a minted row is COPIED from the master, so it falsely
  suggests the rows were created together. **`ProductUpdated` is the field that tells the truth.**
- **Creating a multi-language product is a two-verb sequence.** `ProductNew`/`ProductSave`, then
  `ProductSetLanguages {Model:{ProductKeys:["<PROD>|ENU|"], LanguageIds:["ENU","ESU","FRC"],
  ActivateNewLanguages:true, CopyMainProduct:true, RemoveExistingLanguages:false, VariantId:""}}`. Assert
  the expected language-row count after any create that is meant to be multilingual, before attempting
  translation. (MCP `add_products_to_language` is the tool-side equivalent: it CREATES the layers and
  does not populate them.)
- **`ProductCatalogGroupSave` cannot CREATE a catalogue-group language row.** It is an UPDATE path only:
  it resolves the target through `Dynamicweb.Ecommerce.Products.GroupService` keyed on
  (GroupId, LanguageId), and when no row exists for that language the resolve misses, the handler falls
  through without inserting, and it **still answers `{"status":"ok"}`**. Four shapes were measured, all
  `ok`, all zero rows inserted: `Model.LanguageId` set with the default `modelIdentifier`;
  `modelIdentifier` rewritten to `GROUP513|ESU`; `LanguageId` passed as a sibling command parameter; and
  `modelIdentifier` removed entirely. The recipes that appear to work with this verb only work because
  those groups already HAD the target language row. Create the row as a clone of the default-language
  row through the sanctioned scheduled-task SQL runner (`INSERT INTO EcomGroups (<every column except
  the identity GroupAutoId>) SELECT <same columns, GroupLanguageId and GroupName substituted> FROM
  EcomGroups WHERE GroupId=@g AND GroupLanguageId='ENU'`), then
  `POST /Admin/Api/CacheInformationRefresh {"CacheTypeName":"Dynamicweb.Ecommerce.Products.GroupService"}`
  or every subsequent read is stale. After that `ProductCatalogGroupSave` works normally on the new row.
  `ProductCatalogGroupTranslationsSave` is the auto-translate action and needs a configured translation
  provider; `ProductCatalogGroupNew` requires a `ParentId` and mints a new group, not a language row.
- **A `400 {"successful":false,"message":"Unable to load query parameters for query type: '<Verb>ById'"}`
  from any `*ById` query means the requested ROW does not exist, not that the parameters are wrong.**
  Measured on both `ProductById?Id=<new product>&LanguageId=ESU` and
  `ProductCatalogGroupById?Id=GROUP513&LanguageId=ESU`, while the identical shape returns 200 for an
  entity that has the language row. The message names the QUERY PARAMETERS, so it sends you probing
  `VariantId` / `ModelIdentifier` variants that cannot help. **Check for the row first.**

## Per-language PIM chrome IS writable: four verbs, three payload shapes

Field labels, group names, option labels and variant names all take a per-language write. Each surface
takes a DIFFERENT payload shape, and the wrong shape answers either a bare
"An error occurred invoking `<tool>`" with no field detail (MCP) or a 400 naming a property that is in
no read model (`/Admin/Api`), which is what makes this read as "there is no write path". All four
verified by SQL row counts on one 10.28.4 host:

| Surface | Verb | Payload | Verified |
|---|---|---|---|
| Category-field LABEL | `POST /Admin/Api/ProductCategoryFieldTranslationSave` | flat `Model:{CategoryId, FieldId, LanguageId, Name}`, where `Name` carries the LABEL | 160/160 rows, 0 failures, `EcomProductCategoryFieldTranslation` FRC rows appear |
| Catalogue-group NAME | MCP `save_group_translations` | `{translations:[{groupId, languageId, name}]}` | 56 succeeded, `EcomGroups` FRC rows 0 → 56 |
| Field-option LABEL | MCP `set_option_translations` | `{requests:[{fieldId:"ProductCategory\|<cat>\|<field>", optionValue, languageId, name}]}` | 88/88, `EcomFieldOptionTranslation` FRC rows 0 → 88 |
| Variant group / option NAME | MCP `save_variant_groups` / `save_variant_options` | a per-language `names` array of `{id, value}` where **`id` is the LANGUAGE id** | 5 groups + 40 options, `EcomVariantsOptions` FRC rows 0 → 40 |

- **The variant verbs take `{id: <languageId>, value: <name>}`, not the natural `{languageId, name}`**,
  and the natural shape fails with no diagnostic.
- **Both variant verbs are whole-entity replaces: read the current model first and APPEND the new
  language to `names`,** or the existing name is dropped. Assert the prior-language rows still exist
  afterwards.
- Shapes rejected on the way, for the label verb: `{Label:…}`, `{SystemName:…}` and `{Id:…}` all answer
  `400 "FieldId: The value is required"`, and sending BOTH `Model` and `model` keys answers 500
  "An item with the same key has already been added. Key: model".
- This covers the CHROME. Per-product field VALUES on a non-master language layer are a separate
  question, governed by `EcomProductField` flags (see the section above).

## Order / quote / cart state badges — `OrderStateTranslationSave` (no SQL needed)

State labels live in `EcomOrderStateTranslations`, which typically ships master-language rows only — so
localized customer-centre order lists render master-language badges and the fix *looks* SQL-only. It is not:
there is a first-class verb.

```
POST OrderStateTranslationSave { Model: { OrderStateId, LanguageId, Name, Description } }
```

One row per (state × language); on one pass 27 states × 2 languages = 54 rows, all read back from
`EcomOrderStateTranslations`. It covers order, quote and cart states alike (including the workflow-specific
and `cart_*` states). **Use the verb — do not reach for SQL on this table.** (`EcomOrderStates` *column*
changes such as `OrderStateColor` are a different surface — those are cached and owe a host restart.)

## Adding a new language — the platform steps

1. **Verify framework readiness** — does the host have countries/currencies/area set up? Check `EcomLanguages` for the default row first.
2. **Insert the new EcomLanguage row** (admin UI: Settings → Ecommerce → Languages → "+ New", or via SQL if scripted):
   ```sql
   INSERT INTO EcomLanguages (LanguageId, LanguageCulture, LanguageCode2, LanguageName, LanguageNativeName, LanguageIsDefault)
   VALUES (N'<langId>', N'<culture>', N'<iso2>', N'<englishName>', N'<nativeName>', 0);
   ```
3. **Translate group names** first (groups must be translated so the navigation tree localizes) — see the group-translation null gotcha above. Use `update_groups` MCP with `languageId=<new>` OR direct SQL.
4. **Translate product name + short description** via `update_products`/`patch_products_safe` with `languageId=<new>`. Custom-field translation can be deferred; the fallback handles it.
5. **Rebuild the index** + run `build_assortments` if assortments are in play.
6. **Do NOT sweep the unused `EcomLanguages` rows.** Currency records are per language: every unused
   locale still owns **11 `EcomCurrencies` rows**, and individual locales carry more (one host: `DAN`
   also owned 7 shippings and 2 payments, `ESM` owned an `EcomShopLanguageRelation`). Deleting a locale
   cascades into the currency table. On the measured host 16 of 20 locales were unused by products,
   groups and areas and **none was cleanly removable**. Broken cultures (a locale row pointing at an
   unrelated culture) are cosmetic in the picker and not worth the cascade. Count
   `EcomCurrencies` / `EcomShippings` / `EcomPayments` per `LanguageId` before proposing any deletion,
   and expect the answer to be "leave them".
7. **Wire the area** to the new language as a SECOND language layer — on the area side you need a sibling `Area` row with `AreaEcomLanguageId=<langId>` so the storefront actually serves the translated values. The content-side language-layer flow (website language + `LanguageSelector`) is covered by [dw-content-modelling](../../dw-content-modelling/SKILL.md).

## Cross-references

- [dw-content-modelling](../../dw-content-modelling/SKILL.md) — the area / content side of the same picture; how to add a website language layer + wire the `LanguageSelector` paragraph type so the frontend can actually switch.
- Official Dynamicweb doc: `https://doc.dynamicweb.dev/manual/dynamicweb10/products/concepts/localization.html`
