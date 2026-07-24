# sql-direct-seeding.md — DEPRECATED (retired motion)

> **This recipe is retired.** "Seed / edit content by writing rows directly to the DB (SQL-direct, or
> SQL through a scheduled task) because MCP/the API is out of reach" is no longer a sanctioned demo
> motion. It taught escaping to SQL whenever the API got hard; that reflex hides real
> `/Admin/Api` endpoints and produces half-wired rows the domain services never bless.

## The rule that replaces it — the Admin UI is API-first

Every admin action lands on `/Admin/Api`. The admin UI is a SPA client of that API — **if the UI can do
it, an `/Admin/Api` call exists.** So the path for any content create/edit is:

1. **MCP** (`save_pages` / `save_grid_rows` / `save_paragraphs` / `set_item_field_values` / …) — first choice;
   it runs DW's domain services (cache invalidation, `ItemList`/`ItemListRelation` wiring, sibling links,
   validation) that raw SQL skips.
2. **Management API** — when MCP doesn't expose the operation. Discover the endpoint from `/admin/api/docs/`,
   the `dw10source` command classes, or by driving the admin UI **read-only** under Playwright and reading
   the SPA's own traffic (`mcp__playwright__browser_network_requests`), then replay that call headlessly. This
   is exactly how the repeater-child (`Swift-v2_Slider` slide) edit path was recovered —
   `POST /Admin/Api/ParagraphSave`, no SQL, no recycle — see
   [`../../dw-demo-base/references/foundational/content-modelling.md`](../../dw-demo-base/references/foundational/content-modelling.md)
   §2 "How repeater children are stored — and the Management API edit path".
3. **Do NOT reach for SQL — direct or via `RunSqlScheduledTaskAddIn` — when the API gets hard.** If the API
   genuinely seems to lack a surface, **file a learning** so the gap is captured and closed, rather than
   escaping to SQL and shipping unblessed rows.

The full surface contract (which surface exists on which instance type, and the narrow, still-sanctioned
SQL cases — cleanup/teardown and reads on a **local** install only) is owned by
[`../../dw-demo-base/references/surface-priority.md`](../../dw-demo-base/references/surface-priority.md).

## If you are diagnosing rows that were already SQL-seeded

The historical NOT-NULL column schema (why a hand-INSERTed `Page`/`GridRow`/`Paragraph`/`ItemType_*` row
renders wrong) is retained as a **forensic / teardown reference only** — not a seeding recipe — in
[`data-access.md`](../../dw-demo-base/references/foundational/data-access.md) "SQL-direct content seeding".
The post-mutation cache rules a direct write owes are in
[`../../dw-demo-base/references/foundational/cache-invalidation.md`](../../dw-demo-base/references/foundational/cache-invalidation.md).

## Cross-references

- [`templates.md`](templates.md) — `PageActive` vs `PageHidden` ("Hidden in Menu") page-state semantics.
- [`paragraphs.md`](paragraphs.md) — the empty-`ParagraphTemplate` alphabetical-fallback hazard and the
  `ProductListComponentSelector` cache rule.
