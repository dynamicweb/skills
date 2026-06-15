---
name: dynamicweb-pim-dashboard
description: Create and configure Dynamicweb 10 dashboards and widgets using MCP tools. Use when the user wants to create a dashboard, add widgets, configure query widgets, or manage dashboard layouts in Dynamicweb administration.
---

# Dynamicweb Dashboard Creator

## Objective
Create or update Dynamicweb dashboards and attach widgets using the current MCP dashboard tools.

## Core Tools
- `get_dashboard_areas`
- `get_dashboards`
- `create_dashboards`
- `get_available_widgets`
- `get_widget_parameters`
- `add_widgets_to_dashboards`

## Workflow

### Create a Dashboard
1. call `get_dashboard_areas` and pick the correct area, such as `Products`
2. call `get_dashboards` and check whether a matching dashboard already exists
3. if needed, call `create_dashboards` and note the returned dashboard `Id`

### Add Widgets
1. call `get_available_widgets` to find the exact `WidgetSystemName`
2. call `get_widget_parameters` for each widget type you plan to use
3. call `add_widgets_to_dashboards` with the dashboard `Id`

### Product Query Widgets
If the dashboard depends on saved product queries:
1. ensure the query already exists
2. use the correct query name in the widget parameters
3. for `RepositoryCountWidget`, set `WidgetType` to `Count`, `Sum`, or `Avg`

## Guardrails
- Never guess `WidgetSystemName`.
- Never guess parameter names.
- Use a real persisted dashboard `Id`.
- Create the dashboard first, then add widgets.

## Reference
See [references/dashboard-widgets.md](references/dashboard-widgets.md) for schemas and examples.
