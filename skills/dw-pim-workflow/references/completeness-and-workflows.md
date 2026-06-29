# Completeness Rules & Workflows (Dynamicweb 10 MCP)

## Contents

- [Completeness Rules](#completeness-rules)
  - [Purpose](#purpose)
  - [MCP Tool](#mcp-tool)
  - [CompletionRuleModel Schema](#completionrulemodel-schema)
  - [Field System Names](#field-system-names)
  - [Inclusion in create_data_model_structure](#inclusion-in-create_data_model_structure)
  - [Connecting Rules to Queries](#connecting-rules-to-queries)
  - [Design Guidance](#design-guidance)
- [Workflows](#workflows)
  - [Purpose](#purpose-1)
  - [MCP Tool](#mcp-tool-1)
  - [WorkflowStateModel Schema](#workflowstatemodel-schema)
  - [Typical Three-State Workflow](#typical-three-state-workflow)
  - [Design Guidance](#design-guidance-1)

## Completeness Rules

### Purpose
Completion rules define which fields a product must have filled in to be considered "complete". Used in product queries to show a per-product completeness percentage in the administration UI.

### MCP Tool
`create_or_update_completeness(CompletionRuleModel)`
- Omit `id` (or set to `0`) to create a new rule.
- Provide `id` to update an existing rule.

### CompletionRuleModel Schema
```json
{
  "id": 0,
  "name": "Basic Content",
  "description": "Mandatory fields for editorial completeness",
  "excludeVariants": true,
  "fieldSystemNames": [
    "ProductName",
    "ProductShortDescription",
    "ProductLongDescription"
  ]
}
```

| Field | Type | Notes |
|-------|------|-------|
| `id` | int | 0 = create new |
| `name` | string | Unique rule name |
| `description` | string | Optional description |
| `excludeVariants` | bool | Default `true` -- exclude product variants from rule evaluation |
| `fieldSystemNames` | string[] | Standard field names (`ProductName`) and category field system names |

### Field System Names
- **Standard fields**: from `get_standard_fields` (e.g. `ProductName`, `ProductShortDescription`, `ProductLongDescription`)
- **Category fields**: from `get_product_category_fields` (e.g. `custom_color`, `custom_weight`)

### Inclusion in create_data_model_structure
```json
{
  "completionRules": [
    {
      "name": "Basic Content",
      "excludeVariants": true,
      "fieldSystemNames": ["ProductName", "ProductShortDescription"]
    },
    {
      "name": "Rich Content",
      "excludeVariants": true,
      "fieldSystemNames": ["ProductName", "ProductShortDescription", "ProductLongDescription", "custom_image"]
    }
  ]
}
```

### Connecting Rules to Queries
After creating rules, use the returned IDs in product query configuration:
```json
{
  "configuration": {
    "completionRules": [1, 2],
    "completionLanguages": ["LANG1"]
  }
}
```
This causes the query to display completeness % for each returned product in the DW admin UI.

### Design Guidance
- Define 2--4 rules that reflect real publish gates (e.g. "Basic", "Rich", "Ready for Webshop")
- Keep rule scope narrow -- each rule should represent a meaningful editorial milestone
- Standard mandatory fields go in the first rule; enrichment fields in subsequent rules

---

## Workflows

### Purpose
Workflow states define an editorial approval flow for products (e.g. Draft -> Review -> Approved). Products are assigned a workflow state that editors and managers track.

### MCP Tool
`create_or_update_workflows(WorkflowStateModel)`
- States belong to a workflow via `workflowId`.
- Use `workflowId: 0` when creating states for a new workflow (DW creates the workflow automatically).
- Transitions between states are set via `nextStateIds`.

### WorkflowStateModel Schema
```json
{
  "id": 0,
  "workflowId": 0,
  "name": "Draft",
  "availableStates": "",
  "nextStateIds": []
}
```

| Field | Type | Notes |
|-------|------|-------|
| `id` | int | 0 = create new state |
| `workflowId` | int | 0 for new workflow; use existing ID to add states to it |
| `name` | string | State display name |
| `availableStates` | string | Legacy field -- leave empty |
| `nextStateIds` | int[] | IDs of states this state can transition to |

### Typical Three-State Workflow
```json
{
  "workflowStates": [
    { "id": 0, "workflowId": 0, "name": "Draft",    "nextStateIds": [] },
    { "id": 0, "workflowId": 0, "name": "Review",   "nextStateIds": [] },
    { "id": 0, "workflowId": 0, "name": "Approved", "nextStateIds": [] }
  ]
}
```

> **Note**: `nextStateIds` can only reference IDs of states that already exist. For a fresh workflow (all states new), leave `nextStateIds` empty on initial creation, then update states with correct IDs in follow-up calls if transitions are needed.

### Design Guidance
- Define one workflow that mirrors real editorial handoffs
- Typical states: `Draft` -> `Under Review` -> `Approved` -> `Published`
- Keep it simple -- avoid more than 4--5 states unless the client's process genuinely requires it
