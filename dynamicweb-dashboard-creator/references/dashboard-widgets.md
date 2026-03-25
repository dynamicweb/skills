# Dashboard and Widget Reference (Dynamicweb 10 MCP)

## MCP Tools

| Tool | Input | Returns |
|------|-------|---------|
| `get_dashboard_areas` | none | `DashboardAreaModel[]` with `Name` |
| `get_available_widgets` | none | `DashboardWidgetTypeModel[]` with `SystemName`, `Name`, and `Description` |
| `get_dashboards` | none | `DashboardConfigModel[]` with `Id`, `DashboardType`, `Path`, `Title`, and `WidgetCount` |
| `create_dashboards` | `CreateDashboardModel[]` | created dashboard models with `Id` |
| `get_widget_parameters` | `widgetSystemName` | `WidgetParameterModel[]` with `Name`, `Label`, and `Type` |
| `add_widgets_to_dashboards` | `AddWidgetModel[]` | added widget results |

## CreateDashboardModel
```json
{
  "dashboardType": "Products",
  "path": null,
  "title": "Product Quality Dashboard",
  "userIds": []
}
```

## AddWidgetModel
```json
{
  "dashboardId": 7,
  "widgetSystemName": "Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryCountWidget",
  "title": "Missing Descriptions",
  "columns": 4,
  "order": null,
  "parameters": {
    "Query": "active_missing_short_description",
    "WidgetType": "Count"
  }
}
```

## Common Widget Types

| Widget | Notes |
|--------|-------|
| `RepositoryCountWidget` | Shows query result count, sum, or average |
| analytics widgets | depends on the solution |
| ecommerce widgets | depends on installed modules |

Always use `get_available_widgets` to get the exact `SystemName`.

## RepositoryCountWidget Parameters

| Parameter | Values | Notes |
|-----------|--------|-------|
| `Query` | query system name | must match an existing saved query |
| `WidgetType` | `Count`, `Sum`, `Avg` | `Sum` and `Avg` also require `RepositoryField` |
| `RepositoryField` | field system name | only needed for `Sum` and `Avg` |

## Worked Example
```json
// Step 1: get_dashboard_areas -> choose "Products"
// Step 2: get_dashboards -> check for an existing dashboard
// Step 3: create_dashboards
[
  {
    "dashboardType": "Products",
    "title": "Product Quality"
  }
]

// Step 4: get_available_widgets -> find RepositoryCountWidget
// Step 5: get_widget_parameters("...RepositoryCountWidget")
// Step 6: add_widgets_to_dashboards
[
  {
    "dashboardId": 7,
    "widgetSystemName": "Dynamicweb.Application.UI.Dashboard.Widgets.RepositoryCountWidget",
    "title": "Missing Short Desc",
    "columns": 4,
    "parameters": {
      "Query": "active_missing_short_description",
      "WidgetType": "Count"
    }
  }
]
```

## Important
If a structure flow creates a dashboard, later widget payloads still need a real dashboard `Id`.
Create the dashboard first, then add the widgets.
