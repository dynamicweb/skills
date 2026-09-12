# Out-of-product recipes — Content

This reference holds the out-of-product recipes for content (pages, paragraphs, grid rows, item types and item fields, language layers): Management API
commands at `/admin/api/...`, serializer layers, and direct SQL. The in-product skills for this
area are `dynamo: true` and carry no instruction on those surfaces, so they keep a one-line pointer
here instead of the recipe.

Every recipe names its surface in the repo convention: MCP tools `snake_case` in backticks,
Management API commands `PascalCase` in backticks with the route on first use in this file,
serializer operations by command or by layer and mode, and `SQL` labelled as such in a fenced `sql`
block. Every SQL recipe states three things inline — why the higher surfaces do not cover it, that
it is **local installs only**, and the cache flush or host restart it owes.

## Contents

- [Writing `PageNavigationTag` directly](#writing-pagenavigationtag-directly)

## Writing `PageNavigationTag` directly

**Surface: `SQL`.** `PageNavigationTag` is not on the MCP `save_pages` model, and no Management API
command at `/admin/api/...` exposes it either, so the column is only reachable from the database.

```sql
UPDATE Page SET PageNavigationTag = 'MyTag' WHERE PageId = <pageId>;
```

Three things this recipe owes:

- **Why the higher surfaces do not cover it** — the field is absent from both the MCP page model and
  the Management API page command on 10.28.x.
- **Local installs only** — a hosted install has no SQL surface at all.
- **The debt it owes** — a host restart. The page cache is not touched by a direct column write, so
  `GetPageIdByNavigationTag()` keeps returning `0` until the application pool recycles.

Because of that third point the tag is the wrong lookup key for anything a template has just
created. Resolve a freshly created page or paragraph **by item type** instead: the paragraph cache
is invalidated by the API write that created the row, so the item-type lookup is cache-fresh on the
very next request and neither the SQL nor the restart is needed. See
[dw-render-razor](../../dw-render-razor/SKILL.md) `references/paragraph-endpoints.md` §1 for that
recipe.
