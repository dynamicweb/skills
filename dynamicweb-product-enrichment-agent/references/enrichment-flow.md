# Product Enrichment Flow Reference (Dynamicweb 10 MCP)

## Completion Rule Details Shape
Each query returned by `get_product_queries` includes entries like:

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

Take the union of all `fieldSystemNames` across the rules. That union is the required field set.

If the query has no completion rules, ask the user which fields to target.

## Field Classification
For each required field, decide whether it is:
- A built-in standard field.
- A custom global product field.
- A category field.

Use `get_standard_fields` and `get_product_category_fields` as the source of truth. Never invent field system names.

## Patch Shape
After approval, build one patch per product containing only the missing fields being filled. Do not include any field that already had a value. Always use `patch_products_safe`, never `update_products`.
