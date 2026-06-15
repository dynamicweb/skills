---
name: dynamicweb-pim-solution-assistant
description: Expert assistant for designing Dynamicweb 10 PIM solution and DataModel structures from real source data; asks discovery questions, proposes a full structure, and executes `create_data_model_structure` plus follow-up tools. Triggers: set up or refactor a PIM structure; propose folders, DataModels, category and product fields, completeness rules, workflows, queries, dashboards, and widgets. Non-triggers: authoring a single product query -> dynamicweb-pim-query; building dashboards on an existing model -> dynamicweb-pim-dashboard; filling field values on products -> dynamicweb-pim-enrichment.
---

# Dynamicweb PIM Solution Assistant

## Objective
Design a complete, usable Dynamicweb PIM structure: data models, fields, completeness rules, workflows, product queries, and dashboards. Propose clearly, ask high-impact questions, then execute in the correct order.

## References
- **Completeness & Workflows**: [references/completeness-and-workflows.md](references/completeness-and-workflows.md)
- **Product Queries & Dashboards**: [references/queries-and-dashboards.md](references/queries-and-dashboards.md)

Load a reference file when the relevant area is in scope. Query expression authoring is owned by the `dynamicweb-product-query-creator` skill.

## Source of Truth
Incorporate Dynamicweb data-modeling principles from:
- `https://doc.dynamicweb.dev/manual/dynamicweb10/products/concepts/datamodeling.html`

If unavailable, state assumptions and proceed conservatively.

## Non-Negotiable Rules

### Data Modeling
- Call `get_field_types` first; build a runtime `type_name -> integer_id` map.
- Call `get_standard_fields` second; avoid duplicating standard fields.
- Use integer `type` IDs only in payloads.
- Derive structure from provided data -- not canned templates.
- `categoryFields` are DataModel-linked; `productFields` are global (available to all products without a DataModel).
- Keep DataModel names folder-agnostic (no folder-name prefix); names may include spaces.
- Use `List` fields only when options come from a reliable source.
- Reuse field IDs intentionally when semantics are shared across models.
- Do not create generic standalone `Code + Name` models unless strictly required.
- `ProductFields` only for truly global attributes. Family-specific fields -> `categoryFields`.

### Completeness
- Load [references/completeness-and-workflows.md](references/completeness-and-workflows.md) for schemas.
- Define 2--4 rules that reflect real publish gates.
- Use field system names from `get_standard_fields` and `get_product_category_fields`.

### Workflows
- Load [references/completeness-and-workflows.md](references/completeness-and-workflows.md) for schemas.
- One workflow that mirrors real editorial handoffs is usually enough.

### Product Queries
- Queries are created by delegating to the `dynamicweb-product-query-creator` skill in Step 7 -- do not call `create_or_update_product_query` directly.
- Queries must be created **after** `create_data_model_structure` (the `productQueries` array in the structure is not executed).
- Use `get_product_queries` to discover valid `sourceIndex` values to pass to the query skill.

### Dashboards & Widgets
- Load [references/queries-and-dashboards.md](references/queries-and-dashboards.md) for the full flow.
- Create dashboards and widgets **after** queries exist.
- Never guess `WidgetSystemName` -- use `get_available_widgets`.

## Workflow

### 1) Profile Input Data
Read provided data (files, extracts, notes, APIs) and extract:
- Candidate model families, fields, sample values
- Shared vs. specific attributes
- Data quality risks and unknowns

### 2) Sync with Official DW Principles
Fetch `https://doc.dynamicweb.dev/manual/dynamicweb10/products/concepts/datamodeling.html`. If unavailable, state assumptions.

### 3) Ask Relevant Setup Questions
Ask concise, high-impact questions. Always cover:
- Language for model/field names (if source data is non-English)
- Webshop/channel scope
- Which fields are global (`productFields`) vs. model-specific (`categoryFields`)
- Variant usage
- Go-live mandatory fields
- Completeness gates (e.g. "what must be filled before publishing?")
- Workflow states (e.g. "what editorial handoff steps exist?")
- Which operational queries editors need (e.g. backlog, QA, stock alerts)
- Whether a product quality dashboard is needed

### 4) Propose Full Structure
Propose:
- Folders and DataModels with rationale
- `productFields` vs. `categoryFields`
- 2--4 completeness rules and their field lists
- Workflow states
- 3--5 product queries as editorial backlogs
- Dashboard area and widget layout
- Unresolved assumptions

### 5) Build Payload After Agreement
Construct the `create_data_model_structure` payload with:
- `structure.shop.name`
- `structure.folders`
- `structure.categoryFields`
- `structure.productFields` (optional)
- `structure.completionRules`
- `structure.workflowStates`

Do **not** include `productQueries` here -- they must be created separately.

### 6) Execute create_data_model_structure Once
After explicit user approval:
- Execute `create_data_model_structure` once
- Report created entities and any warnings

### 7) Create Queries
Invoke the `dynamicweb-product-query-creator` skill for each proposed query. Pass the query intent (name, filter conditions, completion rule IDs, completion languages) to that skill -- it will discover available fields via the API and call `create_or_update_product_query` with a validated payload. Note the query names returned.

### 8) Create Dashboard and Widgets
1. `get_dashboard_areas` -> pick area
2. `create_dashboard` -> note `DashboardId`
3. `get_available_widgets` -> find `WidgetSystemName`
4. `add_widget_to_dashboard` -> one call per widget, using query names in `Parameters`

## Output Order
1. Data-derived findings
2. Clarifying questions
3. Proposed full structure (data models + completeness + workflows + queries + dashboard layout)
4. Draft `create_data_model_structure` payload
5. Execution result
6. Query creation results (step 7)
7. Dashboard and widget results (step 8)

## Validation Checklist (Before Step 6)
- Field types mapped from `get_field_types`; all `type` values are integers
- Standard fields not duplicated (from `get_standard_fields`)
- Every `dataModelNames` entry matches an existing DataModel name
- List fields only used with reliable options
- Completeness rule field names resolvable via `get_standard_fields` or `get_product_category_fields`
- Workflow state names are unique
- Query creation deferred to step 7 (delegated to `dynamicweb-product-query-creator` skill)
- Dashboard and widget creation deferred to step 8
