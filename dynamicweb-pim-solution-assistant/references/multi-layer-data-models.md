# Multi-Layer Data Models (Dynamicweb 10 MCP)

How to design and build PIM structures that nest more than one level deep, and how to decide when nesting is the right tool.

## The tree

A DataStructure shop holds a tree of groups:

```
Shop
 ├─ Folder (organizational only)
 │   └─ DataModel            ← carries category fields, receives products
 │        └─ DataModel       ← nested: inherits ancestor fields + adds its own
 │             └─ DataModel  ← nested deeper, any depth
 └─ DataModel                ← top-level, no folder layer
```

`create_data_model_structure` builds the whole tree in one call:
- `folders[]` — organizational containers under the shop. Each folder has `dataModels[]`.
- each `DataModelItem` has its own `dataModels[]` — child models nested **inside** it, to any depth.
- structure-level `dataModels[]` — models placed **directly under the shop**, no folder.

Provide `folders`, top-level `dataModels`, or both.

## Why nesting matters: group membership drives inherited fields

In Dynamicweb a product's **category fields are the union of the categories of every group it belongs to**. A product assigned to a nested data model belongs to that model *and* its ancestor models, so it sees the category fields of the whole chain.

Consequence: **nesting is how you layer shared → specific attributes.** Put attributes shared by a broad family on an ancestor model; put progressively more specific attributes on deeper descendants. Each deeper model adds its own category fields *on top of* what it inherits.

```
Apparel            category fields: Material, CareInstructions, Brand
 └─ Footwear       adds: SoleType, Closure
      └─ Running shoes   adds: Pronation, DropMm, Cushioning
```
A product on **Running shoes** is complete only when the union — Material, CareInstructions, Brand, SoleType, Closure, Pronation, DropMm, Cushioning — is considered. That layering is the entire point of nesting.

## Folders vs. data models

| | Folder | Data model |
|---|---|---|
| Purpose | Organize the tree | Hold category fields, receive products |
| Carries category fields? | No | Yes |
| Products assigned to it? | No | Yes |
| Contributes inherited fields to descendants? | No | Yes |

**Do not model a real, attribute-bearing family as a bare folder.** If "Footwear" has attributes its children share (SoleType, Closure), it must be a *data model* so those fields are inherited — not a folder. Use a folder only when the node is purely for grouping and carries no shared attributes (e.g. a "Hardlines" / "Softlines" merchandising split with nothing in common).

## When to nest vs. keep flat

Nest when:
- There is a genuine **is-a specialization** (`Running shoes` *is a* kind of `Footwear` *is a* kind of `Apparel`), and
- deeper levels **add attributes on top of** the shared ones, and
- you want completeness/queries to reason about the shared layer once.

Keep flat (siblings under one folder, or top-level models) when:
- families are **peers** with little shared attribute surface (e.g. `Books`, `Garden tools`, `Groceries`), or
- a would-be parent has **no attributes of its own** to contribute — then it is a folder, not a model layer.

Heuristics:
- 2–4 levels is typical. Going deeper than ~4 usually signals you are encoding *values* (e.g. individual SKUs or option values) as models — push those into list fields or product data instead.
- If a candidate parent contributes zero category fields, demote it to a folder.
- If two sibling models share many fields, consider lifting the shared fields into a new parent model and nesting both under it.

## Worked example (end to end)

### 1. Input data (profiled from a sample catalog extract)
A mixed catalog with two clusters plus a standalone line:
- **Footwear** rows share `Brand, Material, Gender`; running rows add `DropMm, Pronation`; trail rows further add `LugDepthMm`. Boots rows add `Waterproof, ShaftHeightCm`.
- A separate **Accessories** line (belts, bags) shares only `Brand, Material` with the rest — a peer, not a child of Footwear.

### 2. Proposed structure (3+ levels)
```
Shop: "Outdoor Brand PIM"
 └─ Folder "Footwear"
      └─ DataModel "Footwear"            (Brand, Material, Gender)
           ├─ DataModel "Running shoes"  (DropMm, Pronation)
           │    └─ DataModel "Trail"     (LugDepthMm)
           └─ DataModel "Boots"          (Waterproof, ShaftHeightCm)
 └─ (top-level, no folder) DataModel "Accessories"  (Brand, Material)
```
Rationale: Footwear is a real attribute-bearing family → a model, not a folder; the "Footwear" *folder* is just the organizational container. Running/Boots specialize it; Trail specializes Running. Accessories is a peer with no shared specialization, so it sits directly under the shop as a top-level model (no folder needed).

### 3. `create_data_model_structure` payload (nested `dataModels`)
Category fields are attached to categories and linked to models via `categoryFields` / `dataModelCategoryLinks` (see the main skill rules); the nesting itself lives in the `dataModels` arrays:

```json
{
  "shop": { "name": "Outdoor Brand PIM" },
  "folders": [
    {
      "name": "Footwear",
      "dataModels": [
        {
          "name": "Footwear",
          "dataModels": [
            {
              "name": "Running shoes",
              "dataModels": [
                { "name": "Trail" }
              ]
            },
            { "name": "Boots" }
          ]
        }
      ]
    }
  ],
  "dataModels": [
    { "name": "Accessories" }
  ]
}
```

- `folders[].dataModels[]` nests the Footwear family; each model's own `dataModels[]` carries its children to any depth.
- structure-level `dataModels[]` holds the folderless top-level `Accessories` model.
- Optionally set `externalId` on any `DataModelItem` to preserve a caller-supplied group id (idempotent re-runs / aligning ids with an external source). Omit it to let the platform generate the id.

### 4. Read-back
After creation, `get_shops` renders the nesting intact: folder-based models under `dataModels[].dataModels[]` (recursive), and folderless models under the shop's `topLevelDataModels[]` (also recursive). Use this to verify the tree before assigning fields/products.

## Pitfalls
- A model name can repeat across branches (e.g. two `Standard` models). Completeness rules and category links that reference a name apply to **every** model with that name — name your models so that is what you intend, or keep names unique where it matters.
- Don't nest purely to mirror a folder hierarchy from the source system. Nest only where inherited fields are actually shared; otherwise use folders.
