---
name: dynamicweb-dashboard-creator
description: Create and configure Dynamicweb 10 dashboards and widgets using MCP tools. Use when the user wants to create a dashboard, add widgets, configure query widgets, or manage dashboard layouts in Dynamicweb administration.
---

# Dynamicweb Dashboard Creator

## Objective
Create or update Dynamicweb dashboards and attach widgets using the current MCP dashboard tools.

## Read First
Load [references/dashboard-widgets.md](references/dashboard-widgets.md) before creating a dashboard or building widget payloads.

## Core Tools
- `get_dashboard_areas`
- `get_dashboards`
- `create_dashboards`
- `get_available_widgets`
- `get_widget_parameters`
- `add_widgets_to_dashboards`

## Workflow

### Create a Dashboard
1. Call `get_dashboard_areas` and pick the correct area, such as `Products`.
2. Call `get_dashboards` and check whether a matching dashboard already exists.
3. If needed, call `create_dashboards` and note the returned dashboard `Id`.

### Add Widgets
1. Call `get_available_widgets` to find the exact `WidgetSystemName`.
2. Call `get_widget_parameters` for each widget type you plan to use.
3. Call `add_widgets_to_dashboards` with the dashboard `Id`.

### Product Query Widgets
If the dashboard depends on saved product queries:
1. Ensure the query already exists.
2. Use the correct query name in the widget parameters.
3. For `RepositoryCountWidget`, set `WidgetType` to `Count`, `Sum`, or `Avg`.

## Guardrails
- Never guess `WidgetSystemName`.
- Never guess parameter names.
- Use a real persisted dashboard `Id`.
- Create the dashboard first, then add widgets.

## Reference
See [references/dashboard-widgets.md](references/dashboard-widgets.md) for schemas and examples.
