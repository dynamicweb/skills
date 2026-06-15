# Product Queries & Dashboards (Dynamicweb 10 MCP)

## Product Queries

### Ownership
Query creation is **delegated to the `dynamicweb-product-query-creator` skill**. Do not call `create_or_update_product_query` directly from the PIM assistant. Pass each query's intent (name, filter conditions, completion rule IDs, completion languages) to that skill -- it handles field discovery and payload validation before executing.

### Query Design Guidance
- Create 3--5 queries representing real daily editorial tasks
- Use `get_product_queries` to discover valid `sourceIndex` values to pass to the query skill
- Typical backlog views:
  - `active_missing_short_description` -- `ProductIsActive=True` + `ProductShortDescription IsEmpty`
  - `active_missing_images` -- `ProductIsActive=True` + image field `IsEmpty`
  - `low_stock_active` -- `ProductIsActive=True` + `ProductStock LessThan "5"`
  - `incomplete_products` -- attach completion rule IDs and languages to show % per product

For full expression syntax and worked examples, see the `dynamicweb-product-query-creator` skill.

---

## Dashboards

### Purpose
Dashboards surface query results and system metrics as widgets on the Dynamicweb administration interface. Product query counter widgets help editors see at a glance how many products need attention.

### Execution Order
Dashboards and widgets must be created **after** the data model structure and queries are in place:

```
1. create_data_model_structure              -> shop, folders, fields, completion rules, workflow states
2. dynamicweb-product-query-creator skill   -> one call per query (handles field discovery + execution)
3. get_dashboard_areas -> create_dashboard   -> one dashboard per area (e.g. Products)
4. add_widget_to_dashboard                  -> one call per widget
```

### Creating a Dashboard
```json
// get_dashboard_areas -> e.g. "Products"
// create_dashboard:
{
  "dashboardType": "Products",
  "title": "Product Quality"
}
// -> returns DashboardId: 7
```

### Attaching a Query Counter Widget
```json
// get_available_widgets -> find RepositoryCountWidget SystemName
// get_widget_parameters("...RepositoryCountWidget") -> [Query, WidgetType, RepositoryField]
// add_widget_to_dashboard:
{
  "dashboardId": 7,
  "widgetSystemName": "Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryCountWidget",
  "title": "Missing Short Desc",
  "columns": 4,
  "parameters": { "Query": "active_missing_short_description", "WidgetType": "Count" }
}
```

### Dashboard Design Guidance
- One dashboard per business area (Products, Ecommerce, etc.)
- Use `columns: 4` (third) or `columns: 6` (half) for counter widgets in a row of 3--2
- Attach widgets only where they support daily editorial decisions
- Always verify widget type names with `get_available_widgets` -- never guess SystemName

For full model schemas and additional examples, see the `dynamicweb-dashboard-creator` skill and its `references/dashboard-widgets.md`.
