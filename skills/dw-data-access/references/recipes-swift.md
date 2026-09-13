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
- [Style assets: replay a palette from a stored file](#style-assets-replay-a-palette-from-a-stored-file)
- [Area master item fields: which save writes which editor, and the cached area](#area-master-item-fields-which-save-writes-which-editor-and-the-cached-area)

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
  There, mint a correctly shaped row with `GridRowCreate` and place the paragraphs into it with
  `place_paragraph_in_grid` (below) instead of converting a row or moving a paragraph in place.
- **The debt it owes** — a **host restart**. Both columns are composition, so the page-composition
  cache serves the old value until the host recycles; verify and gate only after the restart.

Prefer minting a correctly shaped row with `GridRowCreate` and placing the paragraphs into it over
converting a row in place.

## Style assets: replay a palette from a stored file

**Surface: Management API.** Each Style-asset MCP tool has a Management API twin, so a palette can be
applied from a script (a brand replay, a gate fixture, an unattended rebuild) without an interactive
MCP client:

| MCP tool | Management API verbs |
|---|---|
| `save_color_schemes` | `ColorSchemeSave` via `/Admin/Api/ColorSchemeSave`, `ColorSchemeGroupSave`; read back with `ColorSchemesByGroupId` or `ColorSchemeById` |
| `save_typographies` | `TypographySave`; read back with `TypographiesAll` or `TypographyById` |
| `save_button_styles` | `ButtonSave`; read back with `ButtonsAll` or `ButtonById` |
| `save_fonts` | `FontSave`; read back with `FontsAll` or `FontById` |

`ColorSchemeSave` posts a flat model, and `ColorSchemeGroupSave` posts `{"Model": {IsNew, Id, Name}}`:

```
{"Model": {IsNew, GroupId, Id, Name, BackgroundColor, ForegroundColor,
           PrimaryButtonColor, SecondaryButtonColor, CustomColors: [{Id, Name, Color}]}}
```

The scheme model is a field-for-field match for a `Schemes[]` entry in
`Files/System/Styles/ColorSchemes/<design>.json`, so the palette half of a re-skin replays straight
from a stored copy of that file: one `ColorSchemeSave` per entry, `GroupId` set to the file's root
`Id`. The verb regenerates the `.json` and `.css` pair together, which is why it is the route and a
hand-edit of the generated pair is not. Read every scheme back with `ColorSchemesByGroupId` and compare
`BackgroundColor`, `PrimaryButtonColor` and every `CustomColors` entry, then fetch the served
`ColorSchemes/<design>.css` and count the new brand hex and its `r, g, b` triplet. Measured: seven
schemes replayed with zero readback mismatches, and the regenerated sheet carried the same hex and
triplet counts the MCP write had produced. [dw 10.28.10]

## Area master item fields: which save writes which editor, and the cached area

**Surface: Management API and MCP.** A whole-entity save that carries an item model splits by the
field's editor type, not by field or item type: through `ParagraphSave`, and measured the same through
`AreaSave` on the area's `Swift-v2_Master` website item, every `System.String` field persists while
every `SelectedImage` field (`Favicon`, `AppleTouchIcon`, `MetaImage`), and a `ButtonData` field sent
back as the read returned it, is dropped with HTTP 200, `Successful: true` and no warning; treat
`PageSave`'s `PageItem` and `PropertyItem` the same until a readback proves otherwise. Write those
fields with the MCP tool `set_item_field_values` and read every sent field back, comparing
`SelectedImage` values by resolved path, and never probe object shapes on a live `SelectedImage` field,
because a wrong shape can empty it for good. The MCP write then carries its own trap:
`set_item_field_values` on the master item commits the row and `get_item_field_values` reads the new
value, but the storefront keeps serving the cached area (old head include, site name, favicon) until a
no-op round trip, `GetAreaById` via `/Admin/Api/GetAreaById` then `AreaSave` posting that complete model
unchanged (a partial model wipes what it omits), or a host recycle. Verify on the served head, never on
the item readback. Measured: the next request after the round trip served the new head, and the
`SelectedImage` values written over MCP survived the round trip. [dw 10.28.10 · mcp 0.4.4]
