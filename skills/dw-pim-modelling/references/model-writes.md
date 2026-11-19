# Writing a data model with MCP tools: measured shapes

The argument and response shapes of the MCP tools that build a data model, its category and spec
fields, a field display group and a completeness rule, and the reads that find each of them again
by natural key. Measured on a live install [dw 10.30.6 · mcp 0.6.3-BETA]. Take the argument names
from the tool's own `tools/list` input schema first; a wrong name answers only "An error occurred
invoking".

## Contents

- [Categories and spec fields](#categories-and-spec-fields)
- [Data models and folders](#data-models-and-folders)
- [Field display groups](#field-display-groups)
- [Completeness rules and their assignment](#completeness-rules-and-their-assignment)
- [Workflow states](#workflow-states)
- [Products in a data model](#products-in-a-data-model)

## Categories and spec fields

| Tool | Arguments | Answer |
|---|---|---|
| `create_categories` | `{requests: [{systemName, name, categoryType}]}`, `categoryType` one of `CategoryFields`, `PropertyFields`, `SystemFields`, `MatrixFields` | `{succeeded, failed, items: [{id, isNew, categoryType, translations}]}` |
| `create_category_fields` | `{requests: [{categoryId, fieldModel: {id, label, templateTag, type, allowChangesAcrossLanguages, allowChangesAcrossVariants}}]}` | `{succeeded, failed, items: [...]}`, one item per field |
| `update_category_fields` | `{requests: [{categoryId, fieldId, allowChangesAcrossLanguages, allowChangesAcrossVariants, required, readOnly, useAsFacet, ...}]}` | per-item counts |
| `get_product_category_fields` | `{}` | `{count, data: [{categoryId, fieldId, systemName, label, typeName, allowChangesAcrossLanguages, allowChangesAcrossVariants, options}]}` |

- `create_categories` **drops the hyphens** of a system name (`my-tools` is stored as `mytools`) and
  answers `isNew: false` for a category it has just created. Find the category again by name and
  take its id from the read, never from the system name you sent.
- **No MCP read lists a category.** `get_product_category_fields` lists the fields of the
  `CategoryFields` categories only: a category that has no field yet, and every `PropertyFields`
  category, does not appear in it. A category that must be verified before its first field exists
  is checked on the category screen.
- `get_product_category_fields` leaves `fieldId` empty and carries the id in `systemName` as
  `ProductCategory|<category>|<field>`; `typeName` holds the type id as text (`"1"`). Match a field
  on `systemName`.
- Type `1` is Text (255). `update_category_fields` sets the scope and behaviour flags, not the
  label.

## Data models and folders

| Tool | Arguments | Answer |
|---|---|---|
| `create_data_models` | `{requests: [{parentId, model: {name, type}, categoryId, id}]}`, `type` `DataModelFolder` or `DataModel`; `parentId` a shop id, a folder id or a model id | `{succeeded, failed, items: [{id, name, description, type}]}` |
| `patch_data_models` | `{requests: [{dataModelId, patch: {name, description, type, categoryId}}]}` | per-item counts |
| `get_shops` | `{includeGroupHierarchy: true}` | `{count, data: [shop]}` |

- `get_shops` nests the hierarchy. A folder sits in its shop's `dataModels` with its own models in
  its own `dataModels` (`data[].dataModels[].dataModels[]`, each `{id, name, categoryId, type}`);
  a model created straight under the shop is listed under `topLevelDataModels` instead. A shop of
  usage type `Shop` carries `topLevelProductGroups` and no `dataModels`.
- `create_data_models` stores **any** `categoryId`, also one that no category has, and the model
  then lists that id. Create the category first and bind the id its read returned. `patch_data_models`
  changes the category of an existing model and leaves the rest of the group alone.
- Without `id` the platform mints a group id (`GROUP<n>`); pass `id` only for an id a later step
  must know in advance.

## Field display groups

| Tool | Arguments | Answer |
|---|---|---|
| `save_field_display_group` | `{group: {id, systemName, name, languageId, sortIndex, availableInFrontend, fieldIdsList}}`, **one** object | the saved group `{id, systemName, name, languageId, sortIndex, availableInFrontend, fieldIdsList}` |
| `get_field_display_groups` | `{frontendOnly, languageId}` | `{count, data: [group]}` in the same shape |

- `id: 0` creates and needs a `systemName` no other group has; an update passes the id and leaves
  out the members it does not change. `fieldIdsList` holds field system names
  (`ProductCategory|<category>|<field>` for a category field) and replaces the whole membership; the
  read returns it in the order written.
- On the delivery API a product shows a display group in `fieldDisplayGroups`, keyed by its system
  name, only while `availableInFrontend` is true **and** the product has a value in at least one of
  its fields; an empty field is left out of the group.

## Completeness rules and their assignment

| Tool | Arguments | Answer |
|---|---|---|
| `create_or_update_completeness_rules` | `{models: [{id, name, excludeVariants, fieldSystemNames}]}`, `id: 0` creates | `{succeeded, failed, items: [{success, ruleId, ruleName}]}` |
| `get_completion_rules` | `{}` | `{count, data: [{id, name, description, excludeVariants, fields: [{systemName, ...}]}]}` |
| `assign_completion_rules_to_groups` | `{requests: [{groupId, ruleIds, languageIds}]}` | per-item counts |
| `get_completion_rule_assignments_for_groups` | `{groupIds}` | `{count, data: [{id, rules: [{ruleId, ruleName}], languageIds}]}` |
| `get_completeness_status` | `{productId, shopId, groupIds}` | `{productId, shopId, value}` |
| `calculate_product_completeness_for_products` | `{productIds, ruleIds, groupIds}` | `{count, data: [{productId, value, fieldStatuses: [{fieldSystemName, languageId, hasValue}]}]}` |

- The rule read returns the fields as objects (`fields[].systemName`), in the order written, and
  includes standard fields such as `ProductName`.
- `assign_completion_rules_to_groups` replaces the group's whole assignment.
- `get_completeness_status` answers `value: -1` when no rule reaches the product through the shop or
  the groups passed; with the rule assigned to the product's data model it answers the percentage
  (a product with two of three rule fields filled answers 67).

## Workflow states

| Tool | Arguments | Answer |
|---|---|---|
| `create_or_update_workflow_states` | `{models: [{id, workflowId, name, nextStateIds}]}`, `id: 0` creates | `{succeeded, failed, items: [{success, workflowId, workflowStateId, workflowStateName}]}` |
| `get_workflow_states` | `{}` | `{count, data: [{id, name, states: [{id, name, nextStateIds}]}]}`, one row per **workflow** |

- A state needs an existing workflow: `workflowId: 0` fails the item with "WorkflowId is required
  to create a workflow state". No MCP tool creates the workflow itself; it is created on the
  workflow settings screen.
- `get_workflow_states` reads the workflow containers with their states nested, so it is also the
  read that finds a workflow by name.

## Products in a data model

| Tool | Arguments | Answer |
|---|---|---|
| `assign_data_model_to_products` | `{assignments: [{dataModelId, productIds}]}` | `{succeeded: [...], failed: [...], verified: [{dataModelId, dataModelName, targetType, shopId, productIds}]}` |
| `patch_products_safe` | `{products: [{id, customFields: [{id: "ProductCategory|<category>|<field>", value}]}]}` | the saved products |

A category field value is written with its full system name as the custom field id and reads back in
the product's `customFields`.
