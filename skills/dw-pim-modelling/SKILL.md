---
name: dw-pim-modelling
type: knowledge
group: pim
mcp: optional
description: 'Model Dynamicweb 10 PIM data — Data Models, category fields, variant groups, and global vs category field storage — and create products, variant groups/combinations through the MCP tools. Triggers: design or refactor a Data Model, choose global vs category fields, structure variant groups, organize category groups vs product folders, create/clone a product or variant, set up variant options/combinations. Non-triggers: workflow states and transitions -> dw-pim-workflow; completeness rules and scores -> dw-pim-completeness; translating products -> dw-pim-localization.'
---

# PIM Data Modelling

## Without MCP

The knowledge here stands alone; the Dynamicweb MCP tools it names are the preferred way to
apply it. When no Dynamicweb MCP server is connected, work in advisory mode — explain,
review, or produce payloads and configuration for the user to apply — and do not substitute
direct SQL, file edits, or guessed HTTP calls for those tool calls.

## Core Concepts

### Data Models

A **Data Model** is the primary structural unit in Dynamicweb PIM. It defines:
- Which **category fields** (attributes) products of this model have
- The **variant groups** used for product variants
- Which **completion rules** apply
- Which **workflow** applies

Data Models are not product categories — they are schemas. One product can belong to multiple category groups (folders), but its Data Model is fixed and defines its attribute set.

Admin path: **Products > Data > Data Models**

### Category Groups vs. Product Folders

Dynamicweb PIM uses two distinct organizational structures:

| Structure | Purpose |
|-----------|---------|
| **Channel groups / Folders** | Navigation/hierarchy that customers see; used for product grouping in storefronts |
| **Data Models** | Define the attribute schema for products; invisible to customers |

A product can appear in multiple channel groups (via relations or assortments) but belongs to exactly one Data Model.

### Global Product Fields vs. Category Fields

| Field type | Where stored | Scope |
|-----------|-------------|-------|
| **Global product fields** | `EcomProducts` table columns | All products, regardless of Data Model |
| **Category fields** | `EcomProductCategoryFieldValue` | Only products linked to a specific Data Model |

Use **global product fields** for truly universal attributes (SKU, weight, active status). Use **category fields** for model-specific attributes (electronics: wattage, connectivity; clothing: fabric, care instructions).

## Creating a Data Model

Admin path: **Products > Data > Data Models > New Data Model**

1. **Name** the Data Model (e.g., "Electronics", "Clothing — Tops")
2. Add **Category groups** — groups of related category fields
3. Within each category group, add **Category fields**
4. Add **Variant groups** (if the model uses product variants)
5. On the **Workflow tab**: assign completion rules and a workflow
6. Save

### Field Types

Common field types for category fields:

| Type | Use for |
|------|--------|
| Text | Short strings (color name, brand) |
| Text area | Longer descriptions |
| Number | Integers and decimals |
| Checkbox | Boolean flags |
| List | Pre-defined option sets (dropdown) |
| Date | Date values |
| Image | Single image reference |
| Image list | Multiple image references |
| Link | URL or page reference |
| Relation | Reference to another product (for accessories, related parts) |

### System Names

Every field has a **system name** (e.g., `ElecWattage`, `ClothFabric`) — this is the key used to read/write the field value in API calls, templates, and integration mappings. System names cannot be changed after creation without data migration.

**Naming convention:** Use a model prefix (2-4 chars) + field name in PascalCase. This avoids collisions across models.

## Creating a Product

The product entity is `Dynamicweb.Ecommerce.Products.Product`. It is **language-layered**
(`LanguageId`) and **shop-scoped through groups** (`Groups` is a collection, not a single shop
pointer). Custom fields live in `ProductFieldValues`, keyed by `ProductField.SystemName`. The
default-language value of a translated field is the master — translations inherit until
overridden.

**Read before write.** Never draft the create call before every required field has a concrete
value:

1. **Schema** — read the product schema and the active `ProductField` definitions. Required,
   computed, and translatable fields all live here.
2. **Sibling** — read one existing product in the same group/shop/language. The sibling
   reveals which optional fields are conventionally set (VAT group, unit, stock unit,
   manufacturer, primary group).
3. **References** — confirm IDs of shop, primary product group, language, currency, VAT
   group, manufacturer. Reuse IDs already available rather than asking the user to repeat
   them.

**Required field shortlist.** Most installations require at minimum: language, name, number
(SKU), and at least one group assignment (a product without a group is orphaned). Many add:
VAT group, unit, stock unit, default price.

**BOM ("composite") products** use the product's items collection — only set this when the
user explicitly asked for a bundle. See "BOM (Bill of Materials) Products" below.

**Multi-step writes.** A "create product" goal often chains: create master → create variants
→ assign categories → set prices → attach images. Treat the chain as authorized once
confirmed; move to each next step immediately. Break the chain only on tool error, unknown
args, or an explicit pause.

**Flat bulk creation is not a multi-step chain.** When the user asks to create many products of
the same shape in one request (e.g. "create 1000 products from this list"), that is a single
bulk-create operation, not a chain of per-product steps. Build the full list of product-create
models and call `create_products` once (or in the fewest calls the payload size allows),
confirmed as one batch. Do not treat each product, or each small group of products, as its own
step requiring re-confirmation before continuing.

**Recovery.** If the create returns a foreign-key or validation error, the missing reference
is almost always shop, language, group, currency, or VAT group. Read the error, correct,
retry — do not invent values to satisfy validators.

## Reference Groups

**Reference groups** define which other products a product can relate to. Examples:
- "Accessories" — products that are accessories for this product
- "Replacement parts" — compatible spare parts
- "Related items" — upsell suggestions

Create at: **Products > Data > Reference Groups**

Reference group relations are rendered in templates via `ProductViewModel.RelatedProducts` or via the product's category fields.

## Variant Groups

Variant groups define the dimensions along which a product varies (e.g., Color, Size). Each variant group contains **variant options** (e.g., Red, Blue, Green for Color). A product becomes variant-enabled by assigning one or more variant groups to it, then creating combinations from those groups' options.

Admin path: **Products > Data > Variant Groups**

### Setting Up Variants via MCP Tools

| Intent | Tool |
|---|---|
| List / inspect variant groups | `get_variant_groups`, `get_variant_group_by_id`, `get_variant_groups_by_product_id` |
| Create / update a group (`DisplayType` controls storefront UI) | `save_variant_groups` |
| List / create / update options in a group | `get_variant_options`, `save_variant_options` |
| Assign variant groups to a product | `assign_variant_groups_to_product` |
| List a product's combinations | `get_variant_combinations` |
| Create combinations | `create_variant_combinations` |
| Remove a group from a product | `remove_variant_groups_from_product` |
| Delete groups / options / combinations | `delete_variant_groups`, `delete_variant_options`, `delete_variant_combinations` |

**The destructive ordering trap — read before doing anything.**
`assign_variant_groups_to_product` and `remove_variant_groups_from_product` **DELETE all
existing combinations on that product**, and they are **not atomic**:

- Assign **all** the groups a product needs in a **single** `assign_variant_groups_to_product`
  call, **before** creating any combinations. Assigning Color, creating combinations, then
  later assigning Size wipes the Color combinations.
- A partial failure mid-assign can leave the product with some groups assigned and
  combinations already gone. After any assign/remove, always re-read with
  `get_variant_groups_by_product_id` and `get_variant_combinations` before proceeding.
- If the user wants to add a dimension to a product that already has combinations, warn them
  the existing combinations will be cleared and must be recreated, and confirm before
  proceeding.

**The correct flow:** ensure the needed groups and options exist (`save_variant_groups` +
`save_variant_options`; `DisplayType` on the group controls storefront rendering — dropdown,
swatch, etc.) → assign **all** groups at once (`assign_variant_groups_to_product`) → create
combinations (`create_variant_combinations` — each combination's option ids must contain
**exactly one option per assigned group**, no more, no fewer) → verify
(`get_variant_combinations`, confirm the expected matrix, e.g. 3 colors × 2 sizes = 6
combinations).

Full matrix size is the product of option counts across assigned groups. Decide with the user
whether they want the full matrix or only specific sellable combinations — create only the
combinations actually sold, since each is an individually sellable variant with its own
stock/price. State plainly whenever existing combinations will be cleared, so the wipe is
never a surprise, and report the combination count created vs. the expected matrix size.

When a product has variants, its `ProductId` stays the same and the variant id identifies the specific variant. For multi-axis variants it is the dot-joined variant option ids (e.g. `VO1.VO4`); for single-axis variants it is the bare `VariantOptionId` (e.g. `VO3`). The full 3-table shape (relation tables, per-variant `EcomProducts` rows, unique-`ProductNumber` rule, and MCP/API/SQL surface gotchas) lives in [references/structural-model.md](references/structural-model.md) §2.5 / §2.5a.

### BOM (Bill of Materials) Products

For configurable/assembled products, use the **BOM product type**. A BOM product contains a list of component products. BOM products are useful for:
- Configurable bundles (choose color, choose size, choose accessories)
- Assembled products where individual parts are tracked separately

Set via: product edit → **Product type: BOM**. Then use the **BOM tab** to define components.

## Dynamic Workspaces

Dynamic Workspaces are the modern PIM workbench UI — multi-level groupings built from a product query. They are **query-backed projections, not storage**: they do not own or move products, they slice the catalog by attribute axes (`DataModelKey` or `ProductField` levels). The canonical product home stays the group relations under the DataStructure shop.

Use workspaces to:
- Show products by supplier, workflow state, or any product-field axis (1 level, `ProductField`)
- Drill category → sub-category by data-model membership (2 levels, `DataModelKey`)
- Replace a status dashboard for editors who live in the catalog tree

Gated by the PIM license feature. The storage tables (`DynamicStructures`, `DynamicStructureLevels`), the `UseRelationOnProductCreate` orphan trap, the `Path`-parameter probe gotcha, and the empty-workspace 3-cause checklist live in [references/structural-model.md](references/structural-model.md) §2.12.

## Linking Products to Data Models

A product is linked to a Data Model by placing it in a **category group** that belongs to the Data Model. The Data Model → Category Group → Product hierarchy is:

```
Data Model: "Electronics"
  └── Category Group: "Technical specs"
       └── Category Fields: Wattage, Voltage, Connectivity
  └── Products linked to "Electronics":
       └── Product SKU-123 → has Wattage, Voltage, Connectivity fields
```

Products not linked to any Data Model have only standard/global fields.

## Pitfalls

**Category fields vs. global fields confusion** — if a field is added as a global product field but should be model-specific, it appears (empty) on all products. Audit field scope before creating.

**System names are permanent** — once a field system name is in use (referenced in templates, integration mappings, API calls), renaming it requires updating all references. Plan system names carefully before first use.

**Variant group option order** — variant options display in the order they are configured in the variant group, not alphabetically. Pre-sort options or control order explicitly.

**BOM product stock** — BOM product stock is the minimum stock of all components. If one component has 0 stock, the BOM product shows as out of stock even if other components are available.

**Data Model assignment happens through category group placement** — there is no "assign Data Model" button on the product. Move the product into a category group linked to the target Data Model.

## Deep reference

[references/structural-model.md](references/structural-model.md) — the field-validated structural mental model: shop types (`EcomShops.ShopType`) and admin-nav mapping, group types (`EcomGroups.GroupType`), variants (3-table shape, single-axis lean shape, unique-`ProductNumber` rule, MCP `create_variant_combinations` NULL gotcha), BOM bundles (`EcomProductItems` row shapes, `ProductItemAdd` payload), category/field internals (`EcomProductCategoryField`, option-value storage, `reference_category` option buckets, `ProductFieldSave` retype trap), assets (`EcomDetails`, default-image gate), Dynamic Workspaces internals, the standard `ProductField` inventory preflight, and the collapse-custom-field-into-standard recovery recipe.

## Next Steps

- **Setting completion rules?** See [dw-pim-completeness](../dw-pim-completeness)
- **Setting up workflow states?** See [dw-pim-workflow](../dw-pim-workflow)
- **Translating products?** See [dw-pim-localization](../dw-pim-localization)
- **Designing the overall PIM structure?** Use the PIM solution assistant skill
