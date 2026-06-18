---
name: dw-pim-modelling
description: Interactive agent that fills missing completeness fields on the products returned by a saved Dynamicweb product query, page by page, patching only empty fields and never overwriting existing values. Triggers: the user names a saved query and wants its empty or required fields filled, bulk-enrich products from a query, propose-then-confirm field values before writing. Non-triggers: creating or editing the query itself -> dynamicweb-pim-query; defining which fields are required (completeness rules) -> dynamicweb-pim-solution-assistant.
---

# PIM Data Modelling

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

## Reference Groups

**Reference groups** define which other products a product can relate to. Examples:
- "Accessories" — products that are accessories for this product
- "Replacement parts" — compatible spare parts
- "Related items" — upsell suggestions

Create at: **Products > Data > Reference Groups**

Reference group relations are rendered in templates via `ProductViewModel.RelatedProducts` or via the product's category fields.

## Variant Groups

Variant groups define the dimensions along which a product varies (e.g., Color, Size). Each variant group contains **variant options** (e.g., Red, Blue, Green for Color).

Admin path: **Products > Data > Variant Groups**

When a product has variants, its `ProductId` stays the same and the `VariantId` (a combination code like `variantId_Color.Red_Size.M`) identifies the specific variant.

### BOM (Bill of Materials) Products

For configurable/assembled products, use the **BOM product type**. A BOM product contains a list of component products. BOM products are useful for:
- Configurable bundles (choose color, choose size, choose accessories)
- Assembled products where individual parts are tracked separately

Set via: product edit → **Product type: BOM**. Then use the **BOM tab** to define components.

## Dynamic Workspaces

Dynamic Workspaces are personalized views of the PIM for different editor roles. A workspace shows a subset of:
- Product groups/folders
- Data Models
- Specific fields (field set)
- Languages

Admin path: **Products > Workspaces > New Workspace**

Configure: Name, Description, Users/Groups (who sees this workspace), Target folders, Data Models, Field set (which fields are visible).

Use workspaces to:
- Give translators a translation-only view with only language fields
- Give category managers a view restricted to their product families
- Reduce cognitive overload for specialized editors

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

## Next Steps

- **Setting completion rules?** See [dw-pim-completeness](../dw-pim-completeness)
- **Setting up workflow states?** See [dw-pim-workflow](../dw-pim-workflow)
- **Translating products?** See [dw-pim-localization](../dw-pim-localization)
- **Designing the overall PIM structure?** Use the PIM solution assistant skill
