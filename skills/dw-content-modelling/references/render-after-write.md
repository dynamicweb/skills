# When the rendered page disagrees with a correct write

Vendor-generic DW10 knowledge for the content writes that land correctly in the database, read back
correctly through every tool, and still do not show on the rendered page: the caches a structural or
child write does not cross, a paragraph that has nothing to render through, and the per-paragraph
lever that scopes one listing. The write surfaces themselves, and the saves that drop part of their
input, are [`page-paragraph-writes.md`](page-paragraph-writes.md).

## Contents

- [A re-parent is invisible to the rendered navigation until the app domain restarts](#a-re-parent-is-invisible-to-the-rendered-navigation-until-the-app-domain-restarts)
- [`place_app_paragraph` leaves `ParagraphItemType` empty, which renders nothing in a Swift 2 grid](#place_app_paragraph-leaves-paragraphitemtype-empty-which-renders-nothing-in-a-swift-2-grid)
- [Repeatable item-list children render from the parent item's cache](#repeatable-item-list-children-render-from-the-parent-items-cache)
- [`<QueryConditions>` in `ParagraphModuleSettings` scopes ONE listing](#queryconditions-in-paragraphmodulesettings-scopes-one-listing)
- [Cross-references](#cross-references)

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

## Repeatable item-list children render from the parent item's cache

`add_repeatable_item`, `remove_repeatable_items` and `set_item_field_values` against a repeatable
parent's child items all return `succeeded: 1` and all land correctly in `ItemListRelation` and the
child's own backing table, and `get_repeatable_item_field` reads the new list back. The rendered
parent keeps serving the old list, including a child that has already been removed from it. A
paragraph and page service cache refresh does not cross it, and `ItemTypeListReload` returns `ok`
and does not cross it either. What the template reads (`Model.Item.GetItems("<field>")`) is the
PARENT item's cached view model, and a child write never touches the parent.

**Two measurements disagree on what crosses it, and they differ in what was written on the parent:**

| Write on the parent after the child writes | Measured result |
|---|---|
| Re-saving the parent paragraph | Did not cross the cache: the old list kept rendering |
| One of the parent's own item fields written with its current value, `set_paragraph_item_fields` | Crossed it: six parents, each page moved from its seven original entries to all twelve on the next request, with no restart, on a host running the platform bin with an older Suite package pinned in the project [dw 10.28] |

The likely reason is that a paragraph save need not save the parent item, while an item field write
does; that is an inference from the two results, not a third measurement. So the item field write is
the cheap attempt and the new parent is the proven fallback.

**The safe order:**

1. Do the child writes and read them back with `get_repeatable_item_field`.
2. Read one of the parent's scalar item fields with `get_paragraph_item_field_values`, and write it
   back unchanged with `set_paragraph_item_fields`. The content does not change; the parent item is
   saved.
3. Fetch the page with `fetch_frontend_page_html` and assert the new children render (their count
   or their titles), not the call status.
4. Only if the old list still renders, rebuild the parent as below.

**The fallback invalidation is a NEW parent item.** Rebuild the parent paragraph rather than editing
its children in place: a new parent gets a new item id and therefore a new `ItemList` with no cache
entry, and renders correctly at once with no app-pool recycle. Iterating a slider or accordion's
child list is then a create-a-fresh-parent motion; park the superseded parent in a grid column its
row definition does not use rather than deleting it, if the old one is still wanted.

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

- [`page-paragraph-writes.md`](page-paragraph-writes.md): the write surfaces, the saves that drop a
  field, and the labels and slugs a save re-derives.
- [dw-data-access](../../dw-data-access/SKILL.md) (`cache-invalidation.md`) — the per-surface cache
  rulebook the restart and flush obligations above come from.
- [`razor-surfaces-and-pitfalls.md`](../../dw-render-razor/references/razor-surfaces-and-pitfalls.md)
  — the render side of a paragraph that returns 200 with nothing on it.
