---
name: dynamicweb-product-query-creator
description: Design, validate, and generate Dynamicweb 10 product queries for administration use and follow-up dashboard work. Use when the user wants to build, fix, refactor, or explain Dynamicweb product queries in either the manual UI model or the MCP payload model.
---

# Dynamicweb Product Query Creator

## Objective
Create reliable Dynamicweb product queries that match the current `create_or_update_product_queries` MCP tool.

## Read First
Load [references/product-query-authoring.md](references/product-query-authoring.md) before building or changing a query.

## Core Tools
- `get_standard_fields`
- `get_product_category_fields`
- `get_macro_fields`
- `get_completion_rules`
- `get_product_queries`
- `create_or_update_product_queries`

## Workflow
1. Capture the intent in plain language.
2. Discover available fields from the API before writing any expression.
3. If completeness matters, load real completion rule IDs from `get_completion_rules`.
4. Choose whether the query logic should be strict (`And`) or broad (`Or`).
5. Build the payload using only confirmed field system names.
6. Validate `sourceIndex` in `Repo|Index` format.
7. Return the final payload and any follow-up widget payloads if needed.

## Output Contract
Always return:
1. Query intent summary.
2. Clause table.
3. Final `ProductQueryModel` payload.
4. Widget payloads if the user also asked for dashboard widgets.
5. Validation notes and assumptions.

## Guardrails
- Never assume field system names.
- Never assume completion rule IDs.
- Keep query names lowercase with underscores.
- If the query needs unsupported Dynamicweb test value types such as Parameter or Macro test values, say so clearly and recommend the Dynamicweb UI.

## Reference
See [references/product-query-authoring.md](references/product-query-authoring.md).
