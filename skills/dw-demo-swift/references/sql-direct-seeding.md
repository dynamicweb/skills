# sql-direct-seeding.md — retired

> **This recipe is retired.** "Seed / edit content by writing rows directly to the DB (SQL-direct,
> or SQL through a scheduled task) because MCP/the API is out of reach" is no longer a sanctioned
> demo motion. It taught escaping to SQL whenever the API got hard; that reflex hides real
> `/Admin/Api` endpoints and produces half-wired rows the domain services never bless.

## The rule that replaces it — the Admin UI is API-first

Every admin action lands on `/Admin/Api`. The admin UI is a SPA client of that API — **if the UI
can do it, an `/Admin/Api` call exists.** The path for any content create/edit is:

1. **MCP** (`save_pages` / `save_grid_rows` / `save_paragraphs` / `set_item_field_values` / …) —
   first choice; it runs DW's domain services (cache invalidation, relation wiring, validation)
   that raw SQL skips.
2. **Management API** — when MCP doesn't expose the operation. Discover the endpoint from
   `/admin/api/docs/`, the `dw10source` command classes, or by driving the admin UI **read-only**
   under Playwright and replaying the SPA's own network call.
3. **Never SQL when the API gets hard.** If a surface genuinely seems missing, file a learning
   instead of shipping unblessed rows.

The full surface contract — which surface exists on which instance type, and the narrow,
still-sanctioned SQL cases (cleanup/teardown and reads on a **local** install only) — is owned by
[`../../dw-demo-base/references/surface-priority.md`](../../dw-demo-base/references/surface-priority.md).

## Why it was retired — visibility

An API command that owns an entity invalidates that entity's in-process cache as part of the
write; a SQL row does not, and no API call reliably retro-warms a cache the SQL write went behind.
On a host with no self-service recycle, SQL-seeded rows (group memberships, product relations,
details groups) are **restart-gated**: correct in the DB, invisible on the storefront until the
process recycles — "staged", not "shipped". Some are worse than staged: a details group inserted
without control/inheritance types renders nothing, without logging.

## Diagnosing rows that were already SQL-seeded

Symptoms: data present in SQL but absent from the storefront, `GetCatalogGroupProducts`, or a
fresh index build. Treatment: re-issue the same writes through the owning API command (e.g.
`ProductGroupRelationSave` for both top group and subgroup), or accept a host restart. Cache
mechanics live in
[`../../dw-demo-base/references/foundational/cache-invalidation.md`](../../dw-demo-base/references/foundational/cache-invalidation.md);
scheduled-task SQL semantics in
[`../dw-extend-scheduled-tasks`](../../dw-extend-scheduled-tasks/SKILL.md). The full forensic
walkthroughs this file used to carry are in git history (pre-4.17 revisions of this file).
