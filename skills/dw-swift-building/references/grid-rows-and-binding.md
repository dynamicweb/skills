# Swift 2 grid rows — copying, column binding, and the spacing a row pays

> How a Swift 2 grid row is minted, copied and normalised, which paragraph the renderer
> actually draws, and the three ways a row costs layout while rendering nothing. Companion to
> [`component-system-and-reskin.md`](component-system-and-reskin.md) (the component-first gate and the
> paragraph item-field contracts) and [`layout-verification.md`](layout-verification.md) (the browser-side
> checks that catch what markup asserts cannot).
>
> Swift 2.x only — never follow `/swift/swift-1/` URLs.

## Contents

- [Surfaces that write a row](#surfaces-that-write-a-row)
- [Copying a row carries five donor attributes — normalise all five](#copying-a-row-carries-five-donor-attributes--normalise-all-five)
- [Column binding law: a cell renders exactly one paragraph](#column-binding-law-a-cell-renders-exactly-one-paragraph)
- [An inert row still pays its spacing](#an-inert-row-still-pays-its-spacing)
- [The constraint can sit on the grid COLUMN, one level above the paragraph](#the-constraint-can-sit-on-the-grid-column-one-level-above-the-paragraph)
- [Anchor colour comes from the row's DECLARED scheme, not its painted background](#anchor-colour-comes-from-the-rows-declared-scheme-not-its-painted-background)
- [Minting rows idempotently — the marker is what the row RENDERS](#minting-rows-idempotently--the-marker-is-what-the-row-renders)

## Surfaces that write a row

Pick the highest rung that can express the change; each row below states what the rung reaches.

| Surface | Reaches | Notes |
|---|---|---|
| MCP `save_grid_rows`, `get_grid_rows_by_page_id`, `copy_page` | The members the build's tool model exposes — commonly `active`, `colorSchemeId`, `container`, `definitionId`, `sort`, `itemType`, `pageId` | The model is build-dependent; read it before relying on a member. Rows it creates can come back with `GridRowItemId` NULL |
| Admin API `GridRowCreate` / `GridRowSave` / `GridRowCopy` / `GridRowSort` via `/admin/api/<Verb>` | Every row member, including `GridRowActive`, `GridRowContainerWidth`, `GridRowTopSpacing` / `GridRowBottomSpacing`, `GridRowSort`; `GridRowSave` also mints a missing row item | `GridRowSave` with `ID:0` answers 404 — it is update-only, `GridRowCreate` is the create |
| `SQL` on `GridRow` / `Paragraph` | The two changes no verb expresses: converting a row's `GridRowDefinitionId` + `GridRowItemType` (plus a fresh item row), and `Paragraph.ParagraphGridRowColumn` | Local installs only — a hosted install has no SQL surface. Both columns are composition, so the page-composition cache holds the old value: the write owes a **host restart** before it is verified or gated |

**Reach for `GridRowSave` before SQL on every row member it carries.** Row activation, container
width and the spacing tokens are all on the verb; a SQL `UPDATE GridRow` for any of them is a rung
too low and buys a restart it did not need.

## Copying a row carries five donor attributes — normalise all five

`GridRowCopy {Id: <donorRowId>, PageId: <targetPageId>}` is a whole-row copy, not a layout stamp: it
brings the donor's attributes across with it and does not assign the target page a next-in-sequence
position. Five things arrive that a build almost never wants, and they arrive together — treat
normalisation as part of the copy step, not as something done when the page looks wrong.

| What the copy carries | Symptom on the target page | Normalise with |
|---|---|---|
| The donor's **paragraphs** | The "new" row arrives already occupied, so the first paragraph written into it lands in a taken column and never renders | Read occupancy back before writing; see the column law below |
| The donor's **spacing tokens** (`GridRowTopSpacing` / `GridRowBottomSpacing`) | A band of dead vertical space in a rhythm that was designed elsewhere | `GridRowSave` |
| The paragraph's **`ParagraphTemplate`** | `Template file not found (in RenderRazorTemplate())` naming a donor file under the NEW item type's folder | Blank it, or set a file that exists under the new type |
| The donor's **`GridRowSort`** | The copy lands wherever the donor sat — above content already on the page, with nothing in the call naming a position | `GridRowSort` immediately after every copy |
| The donor's **`GridRowContainerWidth`** | A copy into a sidebar or customer-centre column renders as a narrow auto-centred block with a dead gutter beside it | `GridRowSave`; match the width the target page's own rows carry |

**`GridRowCopy` does not append.** A copy whose donor carried sort 5 lands at sort 5 on a page whose
existing row is sort 2, and renders above it. Set `GridRowSort` explicitly after every copy.

**`Paragraph.ParagraphTemplate` is a file name relative to `Paragraph/<ItemTypeSystemName>/`, and an
explicit value always beats the item type's own default template.** So repointing
`ParagraphItemType` on a copied paragraph is only half the move: the stale template name is then
resolved under the new type's folder, where it does not exist, and the page renders a
template-not-found block. Blank `ParagraphTemplate` to fall back to
`Paragraph/<SystemName>.cshtml`, or name a file that exists under the new type.

**Write `ParagraphTemplate` through `ParagraphSave`'s `layout` property, and read `template` back to
confirm the mirror landed** — `template` itself is a read surface, and a save carrying it answers `ok`
while the read-back stays empty and the stock template keeps rendering. Where the mirror does not land
on the build in front of you, the column is SQL-only: local installs only, and it owes a **host
restart** before the alternate template renders. A SQL-written `ParagraphTemplate` then puts that
paragraph on the **never-whole-model-save** list, because a later full-model `ParagraphSave` re-sends an
empty template and the cache drops the alternate one — keep the affected ids in the build's save helper
and have the helper refuse them.

**A custom paragraph template ships as a new item type XML plus `Paragraph/<SystemName>.cshtml`** —
it cannot be a loose `.cshtml` dropped under `Designs/Swift-v2/Custom/`, because the template name
only ever resolves under an item type's own folder. (Dropping a file into an EXISTING type's folder
has its own consequence — it can hijack every paragraph of that type with an empty
`ParagraphTemplate`, by alphabetical sort; see
[`component-system-and-reskin.md`](component-system-and-reskin.md) §4.)

When a page needs a row the copy cannot be normalised into — a different container width AND a
different definition — mint the row with `GridRowCreate` and place the paragraphs, rather than
picking a donor whose attributes happen to be right. A donor chosen for its attributes breaks the
next time the donor page is reordered.

## Column binding law: a cell renders exactly one paragraph

**A paragraph renders only if its `ParagraphGridRowColumn` matches a column the row definition
defines and no other paragraph already holds — binding is by COLUMN, never by sort.** Both shipped
row templates (`Grid/Page/RowTemplates/Swift-v2_Row.cshtml` and `Swift-v2_RowFlex.cshtml`) iterate
`Model.Columns` and render `column.Paragraph` — singular. Everything that loses the cell is dropped
with no error, no log line and `dw-error` 0, while the paragraph read verbs keep listing it, so
every API-level check reports the write succeeded.

- In a **one-column** definition (`1Column`, `1ColumnFlex`) every paragraph after the first is
  silently invisible.
- In a **multi-column** definition, two paragraphs sharing a column number render only the first —
  and the other column renders as an empty `div` with no item type and no id, which is the tell.
- The rule is not item-type specific: a bare `Swift-v2_Text` probe dropped into an occupied column
  is equally invisible. Moving the incumbent to a different column makes the newcomer appear
  immediately, with no restart.

**Stack two blocks visually by giving each its own row, not by stacking them in a cell.** Where a
row must change shape instead, converting it is a `SQL` change (`GridRowDefinitionId` +
`GridRowItemType` + a fresh item row, then each paragraph's `ParagraphGridRowColumn`): no verb
converts a row definition in place, it is local-install only, and it owes a host restart because
both columns are composition.

**Corollary — parking is a reversible retire.** Setting a paragraph's `ParagraphGridRowColumn` to an
index its row definition does not define takes it off the page while leaving the row, its item and
its field values intact, and one write puts it back. Prefer it to a delete when a superseded
paragraph may be wanted again.

## An inert row still pays its spacing

Swift renders **every active** `GridRow` as a `<section>` carrying its
`GridRowTopSpacing` / `GridRowBottomSpacing` classes (2 = 8px, 3 = 16px, 4 = 32px, 5 = 48px,
6 = 96px), and wraps each `1ColumnFlex` paragraph in a `div.d-flex` with 20px/20px padding —
**before** asking the paragraph whether it has anything to say. A row therefore costs its spacing
plus 40px when its paragraph renders an empty string (a variant selector on a product with no
variants, a stock or price block a persona may not see), when the row never got a paragraph at all,
and when the paragraph is parked. Presence and text asserts all pass; the page is simply part air.

Two levers, by whether the row is empty for everyone or only for some:

- **Empty for every product and persona** — deactivate the row: `GridRowSave` with
  `GridRowActive = 0`, and drop the survivors' spacing to 2–3. **`ParagraphShowParagraph` does not
  do this job**: `Paragraph.ShowParagraph` is `get => _showParagraph || GridRowId > 0` ("by design,
  grid row paragraphs must be active"), so a save that clears it reports success, reads back active,
  and still renders.
- **Empty only for some products or personas** — tag it at render time. A `DOMContentLoaded` script
  in the design head include marks every `[data-swift-gridcolumn]` with no element children and no
  text, and one CSS rule hides the enclosing section:

  ```css
  section[data-swift-gridrow="1ColumnFlex"]:has(> [data-swift-container] > .is-empty-col:only-child) { display: none; }
  ```

  The class is required: `:empty` fails on whitespace, and nested `:has()` is invalid per spec — the
  browser drops the whole rule silently.

**The durable guard is a page-height assert per key page**, because every text and presence assert
passes on a page that is 40% dead bands.

## The constraint can sit on the grid COLUMN, one level above the paragraph

Some item types emit their constraint as an inline style on the **column wrapper** the grid renders,
not inside the paragraph markup. `Swift-v2_ProductBom` is the measured case: the grid emits

```html
<div id="<paragraphId>" data-swift-gridcolumn data-dw-itemtype="swift-v2_productbom" style="max-height:640px; overflow:auto">
```

so a bill of materials with ten callout parts is clipped after about three rows inside an inner
scrollbar. **An override scoped to the paragraph or its children sits inside the clipped box and
cannot undo it** — the first attempt looks like a CSS specificity problem and is a targeting problem.
Target the column wrapper by its two attributes:

```css
[data-swift-gridcolumn][data-dw-itemtype="swift-v2_productbom"] { max-height: none; overflow: visible; }
```

Generalise the diagnosis: when an override on a paragraph has no measurable effect, walk up to the
`[data-swift-gridcolumn]` wrapper and read its inline `style` before adding `!important`. Raising the
cap instead of removing it just moves the clip — a cap removed needs a stated replacement (here, the
rows lay out as line rows above the lg breakpoint).

## Anchor colour comes from the row's DECLARED scheme, not its painted background

The generated `ColorSchemes` stylesheet colours the anchors inside a row from the colour-scheme name
the row declares (`data-dw-colorscheme` on `section[data-swift-gridrow]`), regardless of what CSS
ends up actually painting that row. A row authored `dark` and later repainted a light colour in a
project sheet keeps white `tel:` / `mailto:` links — measured at 1.05:1 against the new background,
invisible, with `dw-error` 0 and every markup assert green.

**Any custom paint over a colour-scheme row must set the SCHEME, not just the background.** Change
the row's `ColorSchemeId` to one whose palette matches the paint (`GridRowSave`, or MCP
`save_grid_rows`), and pin the anchor colour explicitly in the project sheet if the scheme's link
colour is still wrong. Only a contrast probe catches this class — see
[`layout-verification.md`](layout-verification.md).

## Minting rows idempotently — the marker is what the row RENDERS

A content-building script that adds a row to a live page must be able to recognise its own work on
the next run. **Ids cannot do that job**: paragraph and item ids are minted per run, so an
idempotency check written as "is there an item of this type with an id above N on this page" misses
on run two and `GridRowCopy` happily creates a duplicate — the page renders its tiles twice, nothing
fails, and nothing is logged.

Three parts, all required:

1. **A content marker.** Find the row by a string it RENDERS — the tile heading, the section label —
   never by an id, an id range or a sort value. The rendered content is the only stable identity a
   content-building script has across runs.
2. **An exact-count assertion in the gate.** `>=` and "the row exists" both pass on the duplicate.
   Assert the page's live grid-row and paragraph counts equal the deserialize invariant plus exactly
   what the build adds, so rows a build wrote and rows a deserialize wrote stay distinguishable.
3. **A documented undo, including its cost.** Deleting a duplicate paragraph is a SOFT delete, so an
   unfiltered `Paragraph` count afterwards reads higher than the live count. Any later step reading
   an unfiltered count must filter `ParagraphDeleted = 0`, and the run that created the gap should
   say so.
