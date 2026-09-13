# Writing pages, paragraphs and grid rows — the surfaces and their sharp edges

Vendor-generic DW10 knowledge for creating and editing page/paragraph/grid-row content
programmatically: which surface reaches what, the saves that report success and drop part of the
input, and the labels and slugs a save silently re-derives. A correct write the rendered page does
not show (the caches a write does not cross, a paragraph that renders nothing, the per-listing query
lever) is [`render-after-write.md`](render-after-write.md). Schema design is
[`modelling-discipline.md`](modelling-discipline.md); the language-mirror half of every write is
[`language-layers.md`](language-layers.md).

## Contents

- [Creating a page or paragraph — the domain anchor and the read-before-write list](#creating-a-page-or-paragraph--the-domain-anchor-and-the-read-before-write-list)
- [Editing page / paragraph / grid-row content through the Management API](#editing-page--paragraph--grid-row-content-through-the-management-api)
- [Saves that report success but silently drop a field](#saves-that-report-success-but-silently-drop-a-field)
- [A page save re-derives `PageMenuText` from the item type's title field](#a-page-save-re-derives-pagemenutext-from-the-item-types-title-field)
- [`save_pages` persists `urlName`, and no page read projects it](#save_pages-persists-urlname-and-no-page-read-projects-it)
- [A `RichTextEditor` value round-trips byte for byte through the MCP write path](#a-richtexteditor-value-round-trips-byte-for-byte-through-the-mcp-write-path)
- [Cross-references](#cross-references)

## Creating a page or paragraph — the domain anchor and the read-before-write list

**Domain anchor.** The page entity is `Dynamicweb.Content.Page`. Key fields:

- **`AreaId`** — the website. Every page belongs to exactly one area, set at construction and
  effectively immutable.
- **`ParentPageId`** — tree position. `0` means top-level under the area.
- **`Active`** vs **`Published`** — these are different. `Active` controls inclusion in
  navigation/availability; `Published` controls whether the page is live. A page can be
  `Active` but unpublished, or vice versa. `ActiveTo` adds a time-bound expiry.
- **`IsFolder`** / **`IsTemplate`** — folders hold structure but render nothing; templates are
  the source for `CopyOf` clones. Don't treat them as content pages.
- **`NavigationTag`**, **`MenuText`**, **`Sort`** — navigation surface. `Sort` is integer order
  among siblings.
- **`LayoutTemplate`**, **`ParentLayoutTemplate`**, `LayoutApplyToSubPages` — layout
  inheritance. Setting these wrong is the most common cause of "the new page looks broken".
- **Items** — a page is item-typed via `Dynamicweb.Content.Items.Item`. The item type is the
  schema (above); required fields, references, and translatable flags live there.

**Read before write:**

1. **Parent** — confirm the parent page or area. The parent's item type and layout often
   constrain the child.
2. **Item type** — read the item type schema: required fields, localizable flags, references
   (image, file, page link).
3. **Sibling** — read one published sibling at the same level. Copy conventions for layout,
   navigation, access.
4. **Language layer** — decide up front whether to write on the master or on a specific
   translation; mixing the two is the most common source of "the change is not visible"
   reports. On a mastered solution every `save_*` call creates the mirror too, carrying the
   structure and not the field values
   ([`language-layers.md`](language-layers.md)).

**Required field shortlist.** Most installations require at minimum: `AreaId`,
`ParentPageId`, item type, name. Many add: `MenuText`, `NavigationTag`, `Sort`,
`LayoutTemplate`, access permissions. Two of those need a second call: `save_pages` has no
`navigationTag` member and drops the key silently, and on an item-typed page `MenuText` is
re-derived from the item's title field on every save — so name a page by writing its Title, and
pin its `urlName` in the same pass, because on a page with no pinned slug the Title write moves the
address too. Both are in this reference.

**Publish is a separate write.** Saving a page sets `Active`/data; it does not set
`Published`. After the create/edit, propose a follow-up publish call as its own step if the
user said "make it live". If the user said "draft only", stop after save.

**Paragraphs — two insertion paths.** Choosing the wrong one fails silently or with a
confusing error:

- **Item-typed paragraph** (`save_paragraphs`) — for any item-typed component, i.e. any type
  that appears in `get_item_types`, including any custom solution-specific paragraph types.
  Create with `save_paragraphs`, setting `ItemType` to the exact system name from
  `get_item_types`.
- **App/module paragraph** (`place_app_paragraph`) — for a standalone Dynamicweb application
  or module (e.g. a product list, search module, form). These appear in `get_content_apps`; if
  the component is NOT listed there, this path fails. **On a Swift 2 site, prefer
  `copy_paragraph` from a working app paragraph of the same module**: a grid column renders a
  paragraph through its item type, and `place_app_paragraph` leaves `ParagraphItemType` empty,
  so the paragraph is live and correct in the database and invisible on the page. See
  [`render-after-write.md`](render-after-write.md).

To pick: call `get_item_types` and check if the type exists there (→ `save_paragraphs`); if
not, call `get_content_apps` (→ `place_app_paragraph`, with the Swift 2 caveat above); if found
in neither, find an existing paragraph of that type on another page to copy its structure.
Whichever tool creates it,
`save_paragraphs`/`set_paragraph_item_fields` store field values **verbatim** — read the
target item type's real field names and an existing sibling's value shapes first (button
fields as `{"Label","Link","Style"}` JSON, rich-text fields with their own HTML) rather than
guessing.

**Confirm before writing.** State the page and parent ("Create About page under Company"),
the item type, language, and whether it will be published. For paragraph edits, name the
paragraph and the page it lives on.

**Recovery.** If the write fails on item-type or schema validation, read the item type schema
again, fix the missing or wrong field, and retry. Do not invent placeholder values to satisfy
required fields.

## Editing page / paragraph / grid-row content through the Management API

The Management API hits the same DW domain services as MCP and the admin UI, so the bookkeeping
(ItemRelation cloning, cache invalidation, notifications) fires correctly. The binder has sharp edges
worth knowing when authoring content programmatically (validated DW 10.25.x):

- **Paragraph item fields** save through `ParagraphSave` round-trips of `GetParagraphById`. String /
  HTML fields persist directly. `ButtonData` fields have a binder asymmetry: GET returns a JSON
  *string*, but the save binder wants the *object*
  (`{"Label": ..., "Link": ..., "LinkType": "page", "Style": "primary"}`).
  - **Never seed a `ButtonData` field with a plain label string.** The render side deserializes the
    stored value as ButtonData JSON; a bare `"Shop now"` in `Button`/`FirstButton`/`SecondButton`
    throws `ConverterException: Cannot deserialize json string to … ButtonData` and replaces the whole
    paragraph (often the whole section) with a Razor error block. Store a full JSON object
    (`{"SelectedValue":"","Label":"…","Link":"/…","LinkType":"url","Style":"primary"}`) or an **empty
    string** for "no button" — templates guard on empty via `TryGetButton`. Seed/import sweeps should
    treat any non-empty non-JSON value on a `*Button*` item field as a defect.
  - **The producer is the shipped item-type XML itself.** Several stock Swift types (the text,
    poster and slider-item families) declare a string `defaultValue` on a `ButtonEditor` field whose
    runtime type is the `ButtonData` object, so **any programmatic create that lets the schema
    default apply stores that bare string** and the paragraph renders the error block. Content
    created through the backend editor is unaffected — an untouched button field saves as `NULL` —
    which is why the defect appears the first time a solution creates that content over the API or
    from a headless surface. Write the full `ButtonData` JSON into every button field on create, and
    repair an affected item **through the item-field API rather than by clearing the column in SQL**:
    the item is cached, so a SQL-only clear leaves the bad value rendering.
- **`ShowParagraph` cannot be changed via the API** — both the `ParagraphSave` round-trip and
  `ParagraphChangeActive` silently no-op. `ParagraphSave {"showParagraph": false}` on the full model
  returns 200 and leaves `Paragraph.ParagraphShowParagraph = 1`; a **correctly shaped**
  `ParagraphChangeActive` returns `{"status":"ok"}` and changes nothing either. Its body shape is
  undocumented and worth recording, because a schema mistake is reported as a domain error: the shape
  is `{"setActive":<bool>,"ids":["<id>", ...]}` where `ids` is a `List<string>`, so **numeric ids 500**
  and **any other key name answers `{"status":"invalid","message":"No items selected"}`** rather than
  naming the field. Hide a paragraph in this order:
  1. **`GridRow.GridRowActive = 0`** when the paragraph is the sole occupant of its row. It removes the
     whole band rather than its contents, so no empty padded `<section>` is left behind, and it is one
     UPDATE to reverse.
  2. **`hideForDesktops` + `hideForTablets` + `hideForPhones` all `true`** for a paragraph that shares
     a row. Server-side suppression, fully reversible.
  3. `Paragraph.ParagraphShowParagraph = 0` by SQL as a last resort (local install only; on a hosted install use step 2, which `save_paragraphs` writes).

  `ParagraphDelete` is not on that list: it is irreversible and it orphans the grid row.
- **`PageCopy` inherits the source's `shortCut`.** A page that carries a shortcut redirect produces a
  copy that 301s elsewhere (`DestinationType` is `folder|section|website`; the
  `X-DWAPP-REDIR-REASON` header names the middleware). Clear `shortCut` on the copy.
- **Grid rows: `GridRowCopy {PageId, Id}`** (copy a known row to the target page) is far more reliable
  than `GridRowCreate`, whose definition lookup is fussy about grid naming. Then point the paragraph's
  `gridRowId` / `gridRowColumn` at the copied row.

### Saves that report success but silently drop a field

These content saves report `status: ok`, bump `updatedDate`, and silently drop part of the input — so
**round-trip-verify any critical content edit** (read the value back through a different surface,
or curl the rendered page) before declaring it done:

| Save | Field silently dropped | Verified | Working fallback |
|---|---|---|---|
| MCP `save_pages` (update path) | `menuText` on an item-typed page — the save re-derives it from the item's title field, and the response echoes the derived value | DW 10.25.x-10.28.x | `set_page_item_fields {Title}` then `save_pages {id, urlName}` carrying the current slug — see "A page save re-derives `PageMenuText`" below. A direct `PageMenuText` write survives only until the next save of that page. |
| MCP `save_pages` (create + update) | `navigationTag` — a documented member of the input schema, accepted and then not persisted; `PageNavigationTag` stays empty | DW 10.27.x-10.28.x, MCP 0.4.4 | Assert the rendered link that resolves through the tag, not the call status; writing the column is out of product ([dw-data-access](../../dw-data-access/SKILL.md) `recipes-content.md` §"Set `PageNavigationTag`"). `urlName` is **not** in this class — it persists, see below. |
| MCP `save_paragraphs` on a `Swift-v2_Logo` paragraph | `header`, observed once: the header sent was ignored, and the call returned and stored the paragraph's `LogoName` item field as the header. Only the admin tree label is affected; the rendered logo reads the item field | A single observation [dw 10.28.10 · mcp 0.4.4] | Set `LogoName` with `set_paragraph_item_fields` and treat the header as derived from it. Confirm with `get_paragraphs_by_ids`: a `header` equal to `LogoName` rather than to the header sent is this behaviour |
| Management API `ParagraphSave` | `contentItem.groups[].fields[].value` mutations — the `ItemType_*` column never updates | DW 10.25.x | MCP `set_item_field_values` is the working surface. `ParagraphSave` is still correct for paragraph-level scalars (Header, Sort, GridRow, Template) |

The tool-behaviour root cause (why these MCP / Management API writes drop fields, and the surface model)
is in [dw-extend-mcp-tools](../../dw-extend-mcp-tools/SKILL.md) §5.

## A page save re-derives `PageMenuText` from the item type's title field

On an item-typed page whose type has a `TitleFieldSystemName`, Dynamicweb rewrites `PageMenuText`
from that item field **on every page save**. So the item's title field is the only durable label,
and a `PageMenuText` written directly is a time bomb that fires the next time anything saves the
page — including calls whose stated job has nothing to do with content:

- **`reorder_pages` re-saves every child page it orders**, so a call made only to fix a duplicate
  sort order silently renames every sibling whose item Title differs from its menu text. Measured:
  thirteen pages reordered, `succeeded: 13 / failed: 0`, four navigation labels quietly replaced,
  nothing logged, and the links kept working because they resolve by URL — so it is visible only by
  diffing the tree.
- **`set_page_menu` cannot repair it.** It returns `succeeded` and the value does not change, for
  the same reason: the item field wins.

**The durable shape for naming or renaming a page** is to write the title field, let the menu text
follow, and pin the slug in the same pass:

```
set_page_item_fields { pageId, fields: { Title: "<label>" } }
save_pages          { pages: [ { id: <pageId>, urlName: "<current slug>" } ] }   // re-syncs the menu text, keeps the address
```

**The `urlName` is not optional, because a Title write also moves the address.** On an item-typed
page with no pinned `urlName`, the URL name is derived from the item Title, and a write to the Title
re-derives it. Measured [dw 10.28.10 · mcp 0.4.4]: `set_item_field_values` writing only `Title` on
four pages moved all four served addresses. The old addresses answered 404 while the site's own links
followed the new slugs, `menuText` still carried the old label, and `save_pages` returned `urlName`
as undefined, so no tool response showed the move. A `save_pages` pinning each page's original
`urlName` brought the old addresses back to 200.

Take the slug to pin from the address the page answers at **before** the write (the rendered
navigation link, or the URL a sitemap or gate already asserts): no page read projects `urlName`, see
the next section. After the pass, fetch the old address with `fetch_frontend_page_html` and poll it
to 200 as that section describes; a 404 that outlasts the polling window means the slug moved. To
move the address on purpose, send the new slug as `urlName` instead and update every hard-coded link
to the old one, since nothing redirects it.

Afterwards `PageMenuText` and `Title` agree and no later save can drift them apart. Give every page
matching Title and MenuText at creation time, and a pinned `urlName`, and the whole class of surprise
disappears. On a multi-language solution the same mechanism de-translates language mirrors — see
[`language-layers.md`](language-layers.md) §3 ("Every save on a mastered page …").

## `save_pages` persists `urlName`, and no page read projects it

On DW 10.28.x with MCP 0.4.4 `urlName` is written through to `Page.PageUrlName` and **wins over the
`menuText`-derived slug**. A page created with `menuText: "guide-draft"` and `urlName: "guide"`
serves at `…/guide` and answers **404** at `…/guide-draft`. So **set `urlName` to the slug you want**
and let `menuText` carry the human label; planning the URL map from `menuText` and then sending a
different `urlName` ships a link map whose every internal link 404s.

What is missing is a **read**, not the write. No page getter in the 0.4.4 tool set projects
`urlName` — `get_pages_by_ids` and `get_pages_by_parent_id` return `menuText` and carry no slug
member at all — so the read-back that confirms a slug is **the served URL**. Inferring the slug
from a page read is what produced the older "`urlName` is not persisted" reading: the read-model gap
is real, the write-path drop is not.

**Never carry an absolute page id between runs.** Page ids are minted per host and a re-deserialize
re-mints them, so an id captured in an earlier pass, copied from another host, or written into a note
addresses a different page — or nothing — the next time it is used. Resolve pages by **path or title**
at the point of use (`search_pages`, or `get_pages_by_parent_id` down the branch) and use the id only
within the run that read it. An id that appears in a worked example is an illustration of a response,
never a value to reuse.

**Poll that URL; do not fetch it once.** The slug is written immediately at the data layer, but the
frontend URL resolution runs through a cache the save does not flush synchronously, so the composed
URL answers **404 for several seconds after a successful save** and 200 shortly afterwards — measured
on one page, 404 at one second and 200 at six, with the superseded slug going the other way over the
same window. A single unconditional fetch therefore reproduces, on a correct write, exactly the 404
this section exists to explain, and sends the reader back to planning the URL map from `menuText`.

So: retry the composed URL until it answers 200, for **at least 15 seconds**, before reading a 404 as
a failure — a 404 on the first fetch is not evidence the write was dropped. Only once the slug form has
answered 200 is the discriminator meaningful: then assert a **404** on the `menuText`-derived form,
where label and slug differ.

`navigationTag` is the member that genuinely is accepted and dropped. On MCP 0.4.4 `navigationTag`,
`showInMenu`, `sort` and `treeSection` are all **first-class members** of the `save_pages` input
schema, each with its own description — so a `navigationTag` write is a documented call that is
accepted and then dropped, not an unknown argument, and there is no better-named tool to switch to.
The call returns `succeeded`, the page is created — and `PageNavigationTag` stays empty. That matters
more than it looks: Swift templates resolve service and form pages with
`GetPageIdByNavigationTag("<tag>")`, which falls back to `0` and renders a link to `#`, so the page
exists and the link goes nowhere. Create the page with `save_pages`, then check the tag from the
**frontend**: no page read in the 0.4.4 tool set projects `navigationTag` either, so the runnable
assert is that the template link resolving through `GetPageIdByNavigationTag("<tag>")` points at the
page instead of `#`. A link rendering as `#` means the member was dropped, and setting it is an
out-of-product write ([dw-data-access](../../dw-data-access/SKILL.md) `recipes-content.md`
§"Set `PageNavigationTag`"). Assert the rendered link rather than the call's status.

## A `RichTextEditor` value round-trips byte for byte through the MCP write path

`set_paragraph_item_fields` stores a `RichTextEditor` value (Swift's paragraph `Text` among them)
**verbatim**. Measured on DW 10.28.x with MCP 0.4.4: a 51-character value carrying three consecutive
newlines and a `<pre>` block with internal blank lines came back from
`get_paragraph_item_field_values` as the identical 51-character string. So write the value you mean
and read it back through the field getter to confirm it.

The normalisation that eats empty lines belongs to the **admin UI's rich-text editor**, which
rewrites the markup client-side before it posts. A value authored or re-saved there is not the value
a tool wrote, so a paragraph whose copy matters should be written and verified through the tool
rather than opened and saved in the editor. Nothing about the MCP write path requires spacing to be
expressed as markup — that stays a rendering choice (see
[dw-swift-page-design](../../dw-swift-page-design/SKILL.md)), not a data-loss workaround.

## Cross-references

- [`render-after-write.md`](render-after-write.md): the correct writes the rendered page does not
  show: the re-parent nav cache, `place_app_paragraph` on Swift 2, repeatable-child caching, and
  `<QueryConditions>`.
- [`modelling-discipline.md`](modelling-discipline.md) — item-type design, the `<Prefix>_*`
  discipline, and the activation mechanics behind `Invalid object name 'ItemType_<X>'`.
- [`language-layers.md`](language-layers.md) — what every one of these writes does a second time in
  the language layer.
- [dw-extend-mcp-tools](../../dw-extend-mcp-tools/SKILL.md) — the same no-ops framed as MCP/API tool
  behaviour, and the properties a tool accepts and does not write.
- [dw-data-access](../../dw-data-access/SKILL.md) (`cache-invalidation.md`) — the per-surface cache
  rulebook the restart and flush obligations above come from.
- [`razor-surfaces-and-pitfalls.md`](../../dw-render-razor/references/razor-surfaces-and-pitfalls.md)
  — the render side of a paragraph that returns 200 with nothing on it.
