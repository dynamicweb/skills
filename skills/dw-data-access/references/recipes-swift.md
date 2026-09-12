# Out-of-product recipes — Swift

This reference holds the out-of-product recipes for swift (Swift 2 re-skin, template, theme and asset work that leaves `Files/`): Management API
commands at `/admin/api/...`, serializer layers, and direct SQL. The in-product skills for this
area are `dynamo: true` and carry no instruction on those surfaces, so they keep a one-line pointer
here instead of the recipe.

Every recipe names its surface in the repo convention: MCP tools `snake_case` in backticks,
Management API commands `PascalCase` in backticks with the route on first use in this file,
serializer operations by command or by layer and mode, and `SQL` labelled as such in a fenced `sql`
block. Every SQL recipe states three things inline — why the higher surfaces do not cover it, that
it is **local installs only**, and the cache flush or host restart it owes.

## Contents

- [Field display groups — create, translate and wire](#field-display-groups--create-translate-and-wire)
- [Grid row members no MCP tool reaches](#grid-row-members-no-mcp-tool-reaches)

## Field display groups — create, translate and wire

**Surface: Management API.** There is no MCP tool for display groups, and on 10.26.x cloud the admin
screen at `/Admin/UI/Ecommerce/FieldDisplayGroupList` renders the empty state while
`GET /Admin/Api/FieldDisplayGroupAll` returns the rows — so this verb set is the whole surface.

The write is `FieldDisplayGroupSave` via `/Admin/Api/FieldDisplayGroupSave`, posting

```
{"model": {Id, SystemName, Name, SortIndex, ShopIds[], FieldIds[]}}
```

(`Dynamicweb.Products.UI.Models.Settings.FieldDisplayGroupModel`). Translate with
`FieldDisplayGroupTranslationSave`, then wire the group to a paragraph with the paragraph
item-field verbs.

`FieldDisplayGroupFieldSystemName` must carry the full pipe-delimited form
`ProductCategory|<CategoryId>|<fieldSystemName>`; the rendering code synthesises that form when
matching, so a bare field system name never binds.

**Read back through `FieldDisplayGroupAll`, never off the parent row.** After an `ok` response,
`FieldDisplayGroupName`, `FieldDisplayGroupFieldIds` and `FieldDisplayGroupShopIds` on
`EcomFieldDisplayGroups` are all still empty: those denormalised columns are legacy and are not
populated. The data lands in `EcomFieldDisplayGroupFields`, `EcomFieldDisplayGroupShops` and
`EcomFieldDisplayGroupTranslation`, where the translation row is keyed on the **system name** with
`GroupId = 0`. A parent-row check reports every successful write as a failure.

## Grid row members no MCP tool reaches

**Surface: Management API.** `GridRowCreate` / `GridRowSave` / `GridRowCopy` / `GridRowSort` at
`/admin/api/<Verb>` reach every row member, including `GridRowActive`, `GridRowContainerWidth`, the
`GridRowTopSpacing` / `GridRowBottomSpacing` tokens and `GridRowSort`; `GridRowSave` also mints a
missing row item. `GridRowSave` with `ID:0` answers 404 — it is update-only, and `GridRowCreate` is
the create.

Use these before SQL for every member they carry. Row activation, container width and the spacing
tokens are all on the verb, so a SQL `UPDATE GridRow` for any of them is a rung too low and buys a
restart it did not need.

**Surface: `SQL`.** Two changes no verb expresses:

```sql
-- 1. convert a row's definition in place (also needs a fresh ItemType_* row for the new type)
UPDATE GridRow SET GridRowDefinitionId = '<newDefinition>', GridRowItemType = '<NewItemType>'
WHERE GridRowId = <id>;

-- 2. move a paragraph between columns of its row
UPDATE Paragraph SET ParagraphGridRowColumn = <n> WHERE ParagraphId = <id>;
```

- **Why the higher surfaces do not cover it** — neither column is on the MCP grid-row model nor on
  any `GridRow*` verb.
- **Local installs only** — a hosted install has no SQL surface.
- **The debt it owes** — a **host restart**. Both columns are composition, so the page-composition
  cache serves the old value until the host recycles; verify and gate only after the restart.

Prefer minting a correctly shaped row with `GridRowCreate` and placing the paragraphs into it over
converting a row in place.
