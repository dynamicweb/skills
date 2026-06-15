---
name: dynamicweb-pim-enrichment
description: Interactive agent that fills missing completeness fields on the products returned by a saved Dynamicweb product query, page by page, patching only empty fields and never overwriting existing values. Triggers: the user names a saved query and wants its empty or required fields filled, bulk-enrich products from a query, propose-then-confirm field values before writing. Non-triggers: creating or editing the query itself -> dynamicweb-pim-query; defining which fields are required (completeness rules) -> dynamicweb-pim-solution-assistant.
---

# Dynamicweb Product Enrichment Agent

## Objective
Fill only the missing fields on products returned by a saved product query.

The query determines:
- which products to work on
- which fields matter, via its completion rules

Never overwrite a field that already has a value.

## Tools
- `get_product_queries`
- `get_standard_fields`
- `get_product_category_fields`
- `get_products_by_query`
- `patch_products_safe`

Always use `patch_products_safe` for enrichment.

## Workflow

### 1. Load the Query and Required Fields
Call in parallel:
- `get_product_queries`
- `get_standard_fields`
- `get_product_category_fields`

Find the named query and read its `completionRuleDetails`.

Each query response includes entries like:
```json
"configuration": {
  "completionRuleDetails": [
    {
      "id": 1,
      "name": "Basic content",
      "fieldSystemNames": ["ProductName", "ProductShortDescription"]
    }
  ]
}
```

Take the union of all `fieldSystemNames`. That is the required field set.

If the query has no completion rules, ask the user which fields to target.

### 2. Classify the Fields
For each required field, decide whether it is:
- a built-in standard field
- a custom global product field
- a category field

Use `get_standard_fields` and `get_product_category_fields` as the source of truth.

### 3. Fetch Products Page by Page
Use `get_products_by_query` with a manageable page size.

For each product, identify only the required fields that are empty.

Skip products that already satisfy the required field set.

### 4. Propose Values
Use this priority order:
1. infer from other data on the same product
2. apply a page-level strategy if many products share the same missing field
3. ask the user when the value cannot be inferred safely

Show proposed values before writing anything.

### 5. Patch Only the Missing Fields
After approval, build one patch per product containing only the missing fields being filled.

Do not include any field that already had a value.

### 6. Continue or Stop
After each page, ask whether to continue to the next page.

At the end, report:
- products reviewed
- products updated
- fields filled
- remaining gaps

## Safety Rules
- Never use `update_products` for this flow.
- Never invent field system names.
- Never set `defaultPrice` or `stock` to `0` without explicit confirmation.
- If a required field from `completionRuleDetails` is unknown, stop and flag it.
- If `patch_products_safe` returns an error, show it and ask whether to retry or skip.
