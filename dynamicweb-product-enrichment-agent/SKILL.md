---
name: dynamicweb-product-enrichment-agent
description: Interactive agent for filling missing completeness fields on products returned by a Dynamicweb product query. Use when the user names a saved query and wants the agent to read its required fields, fetch matching products page by page, propose values for empty fields, confirm the plan, and patch only the missing fields without touching existing values.
---

# Dynamicweb Product Enrichment Agent

## Objective
Fill only the missing fields on products returned by a saved product query.

The query determines:
- Which products to work on.
- Which fields matter, via its completion rules.

Never overwrite a field that already has a value.

## Read First
Load [references/enrichment-flow.md](references/enrichment-flow.md) before reading completion rules or building patches.

## Core Tools
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

Find the named query, read its `completionRuleDetails`, and take the union of all `fieldSystemNames` as the required field set. See the reference for the exact response shape.

If the query has no completion rules, ask the user which fields to target.

### 2. Classify the Fields
For each required field, decide whether it is a built-in standard field, a custom global product field, or a category field.

Use `get_standard_fields` and `get_product_category_fields` as the source of truth.

### 3. Fetch Products Page by Page
Use `get_products_by_query` with a manageable page size.

For each product, identify only the required fields that are empty.

Skip products that already satisfy the required field set.

### 4. Propose Values
Use this priority order:
1. Infer from other data on the same product.
2. Apply a page-level strategy if many products share the same missing field.
3. Ask the user when the value cannot be inferred safely.

Show proposed values before writing anything.

### 5. Patch Only the Missing Fields
After approval, build one patch per product containing only the missing fields being filled.

Do not include any field that already had a value.

### 6. Continue or Stop
After each page, ask whether to continue to the next page.

At the end, report:
- Products reviewed.
- Products updated.
- Fields filled.
- Remaining gaps.

## Guardrails
- Never use `update_products` for this flow.
- Never invent field system names.
- Never set `defaultPrice` or `stock` to `0` without explicit confirmation.
- If a required field from `completionRuleDetails` is unknown, stop and flag it.
- If `patch_products_safe` returns an error, show it and ask whether to retry or skip.

## Reference
See [references/enrichment-flow.md](references/enrichment-flow.md) for the completion rule response shape, field classification, and patch shape.
