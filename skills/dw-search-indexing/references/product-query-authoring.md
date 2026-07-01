# Product Query Authoring (Dynamicweb 10 MCP)

## Documentation Links
- [Product Queries (manual)](https://doc.dynamicweb.dev/manual/dynamicweb10/products/queries.html)
- [Queries and Expressions](https://doc.dynamicweb.dev/manual/dynamicweb10/settings/system/repositories/queries.html)
- [Product Indexes](https://doc.dynamicweb.dev/manual/dynamicweb10/settings/system/repositories/productindexes.html)

## MCP Tool
Use `create_or_update_product_queries`. The input is a `ProductQueryModel`.

- omit `id` when creating
- provide `id` when updating

## SourceIndex
`sourceIndex` must be `RepositoryName|IndexName` with a pipe and no spaces.

Use `get_product_queries` on an existing solution if you need to discover valid values.

## Canonical Shape
```json
{
  "name": "query_name",
  "sourceIndex": "EcommerceRepository|EcommerceIndex",
  "folderPath": "/Files/System/SmartSearches/Ecommerce",
  "configuration": {
    "completionRules": [],
    "completionLanguages": []
  },
  "groupExpressions": [
    {
      "operator": "And",
      "negate": false,
      "rootExpressions": [
        { "field": "ProductIsActive", "operator": "Equal", "value": "True" }
      ],
      "expressions": []
    }
  ]
}
```

## Hard Constraints
- `value` is always a string
- there must be exactly one item in `groupExpressions`
- the MCP model supports only constant test values

If the query needs Parameter, Macro, Term, or Code test values, recommend the Dynamicweb UI.

## Field Discovery
Before writing expressions, call:
- `get_standard_fields`
- `get_product_category_fields`
- `get_macro_fields`

Use only field system names returned by those tools.

## Completion Rules
If completeness is needed:
- call `get_completion_rules`
- use the returned integer IDs in `completionRules`
- use language ID strings in `completionLanguages`

## Dashboard Attachment
Widgets are separate from the query payload. Create the query first with `create_or_update_product_queries`, then attach widgets.

Widget tools, schemas, and payload examples are canonical in [dashboard-widgets.md](../../dw-pim-completeness/references/dashboard-widgets.md) (dw-pim-completeness) — follow that reference for the widget steps instead of duplicating payloads here.

## Quality Gate
- `sourceIndex` uses `Repo|Index`
- all `value` entries are strings
- `IsEmpty` uses `value: ""`
- unsupported test value types are called out explicitly
