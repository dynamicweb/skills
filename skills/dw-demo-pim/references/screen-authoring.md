# screen-authoring.md

## Contents

- [The entity chain](#the-entity-chain)
- [`ScreenType` is a fully-qualified .NET type name](#screentype-is-a-fully-qualified-net-type-name)
- [Three column grammars, and only the platform picker lists them](#three-column-grammars-and-only-the-platform-picker-lists-them)
- [Screen presets: create, audience, default](#screen-presets-create-audience-default)
- ["No tab strip" has two causes and one discriminator](#no-tab-strip-has-two-causes-and-one-discriminator)
- [Grid edit and Bulk update have no Management API surface](#grid-edit-and-bulk-update-have-no-management-api-surface)
- [Bulk update writes an EMPTY value when the dual list is untouched](#bulk-update-writes-an-empty-value-when-the-dual-list-is-untouched)
- [Grid-edit cell authoring: the guarded exception](#grid-edit-cell-authoring-the-guarded-exception)

> The PIM editor surface: `ScreenLayout` (which tabs, groups and editors the product edit screen
> shows), `ScreenPreset` (which columns a worklist grid shows and which editors survive on the edit
> screen), and the two grid-authoring screens (grid edit, Bulk update). Verified on DW 10.28.4 /
> Swift 2.4 unless a row says otherwise. Every write verb here answers `status: ok` for shapes it
> never applies, so every recipe ends in a read-back against the **rendered screen**, not the table.

## The entity chain

| Table | Holds | Written by |
|---|---|---|
| `ScreenLayout` | one row per screen type, `ScreenLayoutScreenType` | `ScreenLayoutSave` |
| `ScreenLayoutTab` / `ScreenLayoutGroup` | the tab strip and its cards | `ScreenLayoutTabSave` / `ScreenLayoutGroupSave` |
| `ScreenLayoutEditor` | one row per field placed on a group, `ScreenLayoutEditorSystemName` | `ScreenLayoutEditorSave` |
| `ScreenPreset` / `ScreenPresetColumns` | a named column set for a model type | `ScreenPresetSave` |
| `ScreenPresetAccessUserRelation` | which users may pick a preset | `ScreenPresetSetRelations` |
| `ScreenPresetDefaultScreenRelation` | the per-user default preset per screen type | `ScreenPresetSetAsDefault` |

Build a layout in **one pass** so group ids are never guessed. `ScreenLayoutMultipleEditorsAdd` is
an ambiguous alias on 10.28.4 (two registered types share the name) and answers 500 "Unable to
determine the correct type from alias", so editors go in one at a time via `ScreenLayoutEditorSave`.
`ScreenLayoutDelete` takes `{"Ids":["1"]}`, an array of **strings**; an array of ints is a 500.

## `ScreenType` is a fully-qualified .NET type name

`ScreenLayoutSave.ScreenType` must be the fully-qualified type name without assembly, for example
`Dynamicweb.Products.UI.Screens.ProductEditScreen`. **No API enumerates the valid values.**
`ScreenLayoutMultipleEditorsAdd` returns an empty selection model (`systemNames:[]`), not a
catalogue, and `ScreenLayoutsAll` is empty on a fresh solution, so there is no example to copy. The
627 valid values are published in exactly one place: the `ScreenType` option list of the "New screen
layout" form, rendered server-side at `/Admin/UI/Settings/ScreenLayoutList?Type=ScreenLayoutsAll`.
Harvest that `dw-select[name=ScreenType]` option list once and pin the value in the recipe.

**The short form fails in two different ways on two 10.28.4 builds, and both are silent enough to
cost a day.** On one host every short guess (`ProductEditScreen`, `ProductEdit`, `ProductDataModel`)
answers 500 "Unable to resolve screen type". On another the short form is **accepted, echoed back in
the response, and persisted verbatim** into `ScreenLayout.ScreenLayoutScreenType`, where it never
matches the screen: the layout is inert and the product edit screen renders DW's default
"General | Categories" tabs as if no layout existed. The advice converges on the FQN either way, and
the read-back that distinguishes them is the rendered `<ul id="tabs">` strip, not the table row,
which is correct in both failure modes.

## Three column grammars, and only the platform picker lists them

A `ProductDataModel` column or editor system name is one of three shapes:

```
bare model property   Name  Number  Completeness  WorkflowStateId  Image  LanguageId
category attribute    CategoryFields|ProductCategory|<Cat>|<field>
completeness rule     CompletenessFields|CompletionRule|<id>
```

**The screen LAYOUT uses the identical grammar the presets use, and this is easy to miss because
`ScreenLayoutEditorSave` accepts the bare form without complaint.** A category editor written as
`ProductCategory|<category>|<field>`, without the `CategoryFields|` prefix, is stored and never
resolves. A tab built **entirely** from such editors has nothing renderable, and DW **drops the whole
tab from the strip** with no error, no log line and no clue: 4 of 5 configured tabs render, the
missing tab's 3 groups and 30 editors are all correct in the database, and deleting, recreating,
recycling and renaming all change nothing. Tabs that mix in at least one bare product property
survive and mask the problem. Diagnostic: **if a whole tab is missing from the strip while its rows
are correct, its editors are all unresolvable. Check the `CategoryFields|` prefix first.**

`ScreenPresetSave` has the same hole: it accepts any string in `ConfigurableColumns` and answers
`status: ok`, so a wrong column name is indistinguishable from a right one until the grid renders
blank. No API enumerates the columns either: `ScreenPresetNew` returns `configurableColumns:[]` and
the product list API returns `columnDefinitions:null`. The 122-entry catalogue is rendered
server-side into the Add-preset form (`/Admin/UI/Settings/ScreenPresetEdit`, `<select
id="ConfigurableColumns_excluded">`) only after `ModelTypeName` is chosen. Harvest that option list,
validate every intended column against it, then post:

```json
{"Model":{"PresetName":"Catalog - standard",
          "ModelTypeName":"Dynamicweb.Products.UI.Models.ProductDataModel",
          "ConfigurableColumns":["Image","Name","Number","Completeness","WorkflowStateId"],
          "FrozenColumns":[],"UserGroupIds":[]}}
```

A plain string array binds fine despite the DTO declaring `IEnumerable<ScreenPresetColumn>`. Validate
by `SELECT COUNT(*) FROM ScreenPresetColumns` per preset against the intended column count, and by
the worklist grid rendering the named headers.

## Screen presets: create, audience, default

**Sweep `ScreenPresetAccessUserRelation` before creating the first preset.** `ScreenPresetDelete` does
not cascade to the relation table and `ScreenPreset` ids are an identity that restarts on an empty
table, so a solution with **zero** presets can hold relation rows binding presets 1-13 to users who
no longer exist in `AccessUser`. Creating the first seven presets makes ids 1-7 immediately inherit
that stale audience:

```sql
DELETE r FROM ScreenPresetAccessUserRelation r
WHERE NOT EXISTS (SELECT 1 FROM ScreenPreset p WHERE p.ScreenPresetId = r.PresetRelationPresetId);
```

**`ScreenPresetSetAsDefault` with `SelectedPresetId = 0` is the un-set.** There is no Remove / Clear /
Unset verb and the UI offers no affordance on the edit screen. The set verb doubles as the un-set:
`{Model:{ModelTypeName, ScreenTypeName, SelectedPresetId:0, SubscreenId:"", UserId, PresetIds:[...]}}`
**deletes** the `ScreenPresetDefaultScreenRelation` row for that (user, screen type) pair rather than
writing a row pointing at preset 0. Nothing in the DTO, the response or the OpenAPI description says
so, and the response is the same `status: ok` as a real set. It is idempotent, it leaves the other
screen type's default untouched, and it leaves `ScreenPresetAccessUserRelation` untouched
(the preset stays granted to the user). `ScreenPresetDelete` is not the alternative: it removes the
preset for everyone.

## "No tab strip" has two causes and one discriminator

A product editor rendering two unlabelled cards (Identity, Classification) and **no tab strip** is
pixel-identical in two unrelated situations. Both are the same mechanism: a preset filters the
layout's editors, and when the survivors all live in the base group the platform drops the strip.

| Cause | Shape |
|---|---|
| A per-user **default** preset on `ProductEditScreen` | `ScreenPresetSetAsDefault` put a list-shaped preset (Image, Name, Number, Completeness, WorkflowStateId) on the EDIT screen for that user. On the edit screen a preset does not add columns, it filters editors. The layout is still correct and still active, and nothing about that is readable from the UI. |
| A **worklist** preset meeting a product whose data model carries none of its fields | The preset names the packaging fields of the Propulsion, Provisions and Boat models; the row that broke was a Safety product. Correct behaviour meeting a preset/worklist mismatch. |

**The discriminator: does a DIFFERENT row of the same worklist render tabs?** If another row with the
same `Screen.PresetId` renders its tab strip, the preset is fine and this product's data model simply
carries none of its fields. If no row renders tabs, look for a per-user default on
`Dynamicweb.Products.UI.Screens.ProductEditScreen`.

Two more facts that make this cheap to confirm and expensive to trip over:

- Appending `&Screen.PresetId=0` (or `=-1`) to the `ProductEdit` URL restores the full layout;
  `Screen.PresetId=` (empty) and the bare URL both keep the narrowed view. Demo frames that need the
  full record are shot with `&Screen.PresetId=0` and captioned honestly.
- **Grid row order is not stable between users**, so "click the first row" lands on a coin toss. Pin
  the product a verification or a demo beat opens, per worklist. Assert per `gov_*` query that every
  product it returns belongs to a data model carrying at least one field of the query's edit preset;
  a row failing that test shows the no-tab-strip screen.

## Grid edit and Bulk update have no Management API surface

Both look API-shaped in the command list and neither can be called headlessly, so a harness that
tries to prove them by API silently has no path:

- **`ProductCollectionSave`** (the verb the grid-edit spreadsheet screen posts) declares its `Query`
  property as the abstract generic `DataQueryListByModelIdentifiersBase` of
  (`ProductDataModel`, `Product`, `ProductListModel`, `String`), which `System.Text.Json` refuses:
  500 "Deserialization of interface or abstract types is not supported. Path: $.Query". Omitting
  `Query` changes the model binder and 500s with a different message.
- **`ProductBulkUpdateSave`** answers 400 `{"status":"invalid","message":"No field to save found"}`
  for every payload, with `FieldValueEditors` lifted verbatim from a live product model and
  `FieldSystemName` given in both the bare and the `ProductCategory|<cat>|<field>` form. The
  read-side query `ProductBulkUpdate` takes a `TransientStorageKey` parameter: the selection must be
  parked server-side by the UI first.

**Treat grid edit and Bulk update as UI-only demo beats.** Prove them with Playwright screenshots, and
when a harness needs the values in place, write the same data change with per-row `ProductSave`. Do
not budget API time for the two verbs above.

## Bulk update writes an EMPTY value when the dual list is untouched

**Highest-severity item on this screen: silent data destruction.** Products list > Actions > Bulk
update, pick "Field to update", then "Save and close" without setting a value, and DW writes an empty
value to **every selected row**. On eight SKUs this wiped a seeded, correct `agCertification=csaal`
along with the seven that were already blank. No warning, no confirm.

The value editor is rendered per field TYPE after the field is chosen. For an option field it is an
Available/Selected **dual list**, and an untouched dual list posts an empty selection, which the bulk
updater treats as "set to empty" rather than "leave alone". There is no control named `Value`, so a
script looking for one finds nothing, sets nothing, and still saves. The built-in Preview grid
renders `CurrentValue` and `NewValue` as empty cells, which reads as "nothing will change" rather
than "everything will be cleared".

- Drive the dual list explicitly: `select.js-excluded-fields` holds the AVAILABLE options. Set
  `option.selected`, dispatch `change`, then click the mover button whose icon class matches
  `/angle-right/`.
- **Always read the Preview grid `NewValue` column before saving.** It is the built-in dry run and it
  is accurate: it must be non-blank for every row.
- Snapshot `EcomProductCategoryFieldValue` for the selected products before the run and diff after.
  Assert no row went from non-empty to empty.
- Bulk update on category fields additionally requires that all selected products share the field.

## Grid-edit cell authoring: the guarded exception

The standing rule is API-first: Claude drives `/Admin` via Playwright to **verify**, never to author
([`../../dw-demo-base/references/surface-priority.md`](../../dw-demo-base/references/surface-priority.md)).
Grid edit is the guarded exception, because `ProductCollectionSave` gives no API surface at all
(above). It is only sanctioned with the read-back/abort guard below, and `update_products` /
`ProductSave` remains the first choice whenever the same values can be written that way.

The hazard is live data loss. The grid renders values into `<input>` elements as DOM **properties**,
so `td.innerText` and `td.outerHTML` are both empty and any content-based cell locator resolves to
nothing. Deriving the column index from `<thead>` is also wrong: the header row carries extra
selection and filter cells that shift its indices relative to a body row. Driving it that way typed
stock figures into the Number and Name columns of two products and saved them (PROD391 became Number
"96" / Name "120"). Nothing errored; the grid saved what it was given.

Body row DOM on `ProductGridEdit`: `td[0]` = `<td class="changed">`, `td[1]` = flag img, `td[2]` =
`<span>` product id, `td[3]` = `<span>`, `td[4]` = Number `<input type=text>`, `td[5]` = Name
`<input type=text>`, `td[6]` = Price `<input type=number>`, `td[7]` = Stock `<input type=number>`,
every input rendered with **no** `value` attribute.

The guard, all four parts mandatory:

1. Address cells by **td index**, never by header text or by coordinate click.
2. Read `tds[4].querySelector("input").value` FIRST to identify the row.
3. Snapshot Number / Name / Price before and after, and **abort** unless every touched row still
   reports its original three values.
4. Assert the on-screen "Changed N" counter equals the number of rows intended, before clicking Save
   and close. Skip rows with no inputs: the grid renders a leading and a trailing spacer row.

Validate out of band by diffing `EcomProducts.ProductNumber`, `ProductName`, `ProductPrice` and
`ProductStock` for the selected products. Only the intended column may differ. `keyboard.type` into a
clicked cell is rejected: the click lands by coordinate on whatever column the mis-derived index
resolved to, which is exactly how the damage happened.

**Reach the screen by clicking, not by URL.** `ProductGridEdit` and the workspace routes resolve
their navigation node path from the tree state, and entered cold they have no
`DynamicStructureNavigationNodePath` and no `screenTypeName`. See
[`governance.md`](governance.md) for the worklist entry points and their caveats, and
[`../../dw-demo-base/references/browser-automation.md`](../../dw-demo-base/references/browser-automation.md)
"Driving the DW 10.28 admin shell" for the click mechanics.
