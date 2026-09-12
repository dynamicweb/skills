# Writing pages, paragraphs and grid rows — the surfaces and their sharp edges

Vendor-generic DW10 knowledge for creating and editing page/paragraph/grid-row content
programmatically: which surface reaches what, the saves that report success and drop part of the
input, the labels a save silently re-derives, the caches a structural write does not invalidate,
and the paragraph-level levers that scope one listing. Schema design is
[`modelling-discipline.md`](modelling-discipline.md); the language-mirror half of every write is
[`language-layers.md`](language-layers.md).

## Contents

- [Creating a page or paragraph — the domain anchor and the read-before-write list](#creating-a-page-or-paragraph--the-domain-anchor-and-the-read-before-write-list)
- [Editing page / paragraph / grid-row content through the Management API](#editing-page--paragraph--grid-row-content-through-the-management-api)
- [Saves that report success but silently drop a field](#saves-that-report-success-but-silently-drop-a-field)
- [A page save re-derives `PageMenuText` from the item type's title field](#a-page-save-re-derives-pagemenutext-from-the-item-types-title-field)
- [`save_pages` has no `navigationTag` member, and an unknown key is dropped](#save_pages-has-no-navigationtag-member-and-an-unknown-key-is-dropped)
- [A re-parent is invisible to the rendered navigation until the app domain restarts](#a-re-parent-is-invisible-to-the-rendered-navigation-until-the-app-domain-restarts)
- [`place_app_paragraph` leaves `ParagraphItemType` empty, which renders nothing in a Swift 2 grid](#place_app_paragraph-leaves-paragraphitemtype-empty-which-renders-nothing-in-a-swift-2-grid)
- [Repeatable item-list children render from a cache that no child write crosses](#repeatable-item-list-children-render-from-a-cache-that-no-child-write-crosses)
- [`<QueryConditions>` in `ParagraphModuleSettings` scopes ONE listing](#queryconditions-in-paragraphmodulesettings-scopes-one-listing)
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
re-derived from the item's title field on every save — so name a page by writing its Title.
Both are in this reference.

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
  this reference.

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
  3. `Paragraph.ParagraphShowParagraph = 0` by SQL as a last resort (local install only).

  `ParagraphDelete` is not on that list: it is irreversible and it orphans the grid row.
- **`PageCopy` inherits the source's `shortCut`.** A page that carries a shortcut redirect produces a
  copy that 301s elsewhere (`DestinationType` is `folder|section|website`; the
  `X-DWAPP-REDIR-REASON` header names the middleware). Clear `shortCut` on the copy.
- **Grid rows: `GridRowCopy {PageId, Id}`** (copy a known row to the target page) is far more reliable
  than `GridRowCreate`, whose definition lookup is fussy about grid naming. Then point the paragraph's
  `gridRowId` / `gridRowColumn` at the copied row.

### Saves that report success but silently drop a field

Two content saves report `status: ok`, bump `updatedDate`, and silently drop part of the input — so
**round-trip-verify any critical content edit** (read the value back through a different surface,
or curl the rendered page) before declaring it done:

| Save | Field silently dropped | Verified | Working fallback |
|---|---|---|---|
| MCP `save_pages` (update path) | `menuText` on an item-typed page — the save re-derives it from the item's title field, and the response echoes the derived value | DW 10.25.x-10.28.x | `set_page_item_fields {Title}` then `save_pages {id}` — see "A page save re-derives `PageMenuText`" below. A direct `PageMenuText` write survives only until the next save of that page. |
| MCP `save_pages` (create + update) | `urlName` — ignored; the slug is derived from `menuText` instead | DW 10.27.x | Set `menuText` to drive the slug, or SQL `UPDATE Page SET PageUrlName` + host restart. `urlName` won't pin the slug on its own. |
| Management API `ParagraphSave` | `contentItem.groups[].fields[].value` mutations — the `ItemType_*` column never updates | DW 10.25.x | MCP `set_item_field_values` first; SQL UPDATE last resort (local install only). `ParagraphSave` is still correct for paragraph-level scalars (Header, Sort, GridRow, Template) |

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

**The durable shape for naming or renaming a page** is to write the title field and let the menu
text follow:

```
set_page_item_fields { pageId, fields: { Title: "<label>" } }
save_pages          { pages: [ { id: <pageId> } ] }     // triggers the re-sync
```

Afterwards `PageMenuText` and `Title` agree and no later save can drift them apart. Give every page
matching Title and MenuText at creation time and the whole class of surprise disappears. On a
multi-language solution the same mechanism de-translates language mirrors — see
[`language-layers.md`](language-layers.md) §3 ("Every save on a mastered page …").

## `save_pages` has no `navigationTag` member, and an unknown key is dropped

The `save_pages` input model is `{id, areaId, parentPageId, itemType, layoutTemplate, masterPageId,
menuText, metaTitle, active}`. A `navigationTag` passed alongside is accepted, the call returns
`succeeded`, the page is created — and `PageNavigationTag` stays empty. That matters more than it
looks: Swift templates resolve service and form pages with `GetPageIdByNavigationTag("<tag>")`,
which falls back to `0` and renders a link to `#`, so the page exists and the link goes nowhere.
Set the tag on a separate surface after the create (Admin API `PageSave`, or a SQL `UPDATE Page SET
PageNavigationTag` on a local install, batched before the restart the job already owes) and assert
the column rather than the call's status.

## A re-parent is invisible to the rendered navigation until the app domain restarts

Two writes on the same page tree through the same tool behave differently, and the cached one is
not the one you expect:

| Write | Live on the next request? |
|---|---|
| `set_page_menu {showInMenu:false}` (maps to `PageActive`) | **Yes** — every link to the page leaves the header and sidebar navigation immediately |
| `save_pages {parentPageId}` (a re-parent) | **No** — the row, `get_navigation_structure` and ROUTING all show the new position (the page answers 200 at its new URL with the right page id) while the rendered menu never lists it |
| `PageNavigationTag` | No — same staleness |
| A user GROUP's `AccessUserRedirectOnLogin` (FrontendStartPage) | No — measured across a SQL write, a SQL write plus a group-relation touch, and an MCP group save; only a restart moved it |

The frontend Navigation view model reads a cached page tree that a `PageActive` change invalidates
and a `PageParentPageId` change does not, while routing and the MCP read side use a different view.
**The one-request diagnostic**: if the page ROUTES at its new URL and is absent from the menu, it is
the tree cache, not permissions. **Budget one app-domain restart into any job that re-parents pages
or sets a group-level FrontendStartPage**, and say so in the plan rather than discovering it at the
end. Decide a group FrontendStartPage's destination BEFORE the restart that makes it live: once
live it outranks the sign-in app's own `RedirectToSpecificPage`, and the precedence is user
`AccessUserRedirectOnLogin` > group `AccessUserRedirectOnLogin` > the app setting — so making it
live can silently move the site's landing page.

## `place_app_paragraph` leaves `ParagraphItemType` empty, which renders nothing in a Swift 2 grid

In Swift 2 a paragraph inside a grid column is rendered **through its item type**. A module-only
paragraph — `ParagraphItemType` and `ParagraphItemId` empty, which is exactly what
`place_app_paragraph` creates — has nothing to render through, so the grid column skips it. Every
check passes: the tool returns a paragraph, the page is 200 with no error, the row is live on the
right page and grid row at the right column with readable module settings, and the app is simply
not on the page. Cache flushes change nothing.

**Use `copy_paragraph` from a working app paragraph of the same module instead**: it carries the
`Swift-v2_App` item instance (and the module settings with it), which is what makes the copy
render. Two gaps to repair afterwards, because the copy does not carry them: the copy lands with
`GridRowId 0` / column 0, and on a mastered solution its language mirror lands on the SOURCE page's
grid row. Rebind both — a `GridRow` binding is the narrow sanctioned SQL case here (no verb takes a
paragraph's grid binding on a copy; local installs only), followed by `CacheInformationRefresh` on
`ParagraphService` and `PageService`. A page carrying `ParagraphItemType` empty under a Swift 2 grid
is also the explanation for any pre-existing "dead paragraph" on a solution that once used this
route.

## Repeatable item-list children render from a cache that no child write crosses

`add_repeatable_item`, `remove_repeatable_items` and `set_item_field_values` against a repeatable
parent's child items all return `succeeded: 1` and all land correctly in `ItemListRelation` and the
child's own backing table — and the rendered parent keeps serving the old list, including a child
that has already been removed from it. Re-saving the parent paragraph does not cross it;
`ItemTypeListReload` returns `ok` and does not cross it either.

**The proven invalidation is a NEW parent item.** Rebuild the parent paragraph rather than editing
its children in place: a new parent gets a new item id and therefore a new `ItemList` with no cache
entry, and renders correctly at once with no app-pool recycle. Iterating a slider or accordion's
child list is therefore a create-a-fresh-parent motion; park the superseded parent in a grid column
its row definition does not use rather than deleting it, if the old one is still wanted.

## `<QueryConditions>` in `ParagraphModuleSettings` scopes ONE listing

`Paragraph.ParagraphModuleSettings` carries a `<QueryConditions>` element holding the module's own
query-parameter DEFAULTS. It is the surgical lever for scoping a single listing — a shop root, one
campaign page — when the listing runs on a query shared by several surfaces and filtering the query
itself would empty the others.

Two properties make it safe and two gotchas make it fiddly:

- **A `DefaultValue` applies only when the parameter is ABSENT from the request.** That is exactly
  what makes it safe on a root listing whose child pages pass the parameter themselves — they are
  unaffected.
- The element is **doubly HTML-escaped inside the XML** (`&amp;quot;`), and
  `ParagraphModuleSettings` is `nvarchar`, not `xml` — so an edit is a string operation, never a
  `CONVERT(xml, …)`.

Assert the scope, not the fix: the changed listing AND the unchanged counts on every other surface
that runs the same query, in the same run. A root-listing-only assertion cannot show that the change
was scoped.

Related trap on the same symptom: `ProductShowInProductList` is not a field in the shipped
`Products.index`, and a product list reads the index rather than the table — so setting the flag to
`0` changes nothing on the listing and a build that sets it will believe it worked.

## Cross-references

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
