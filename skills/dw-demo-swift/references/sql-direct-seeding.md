# sql-direct-seeding.md

> Required-field reference for Page / GridRow / Paragraph SQL-direct INSERTs when MCP / admin UI / Management API are out of reach (bulk demo seed flows, headless agents, sister-demo replay scripts).
>
> **This is the SQL-fallback surface.** The preferred surface for content seeding is MCP `save_pages` / `save_grid_rows` / `save_paragraphs` — those invalidate caches inline and don't require the field disciplines below. Read [`../../dw-demo-base/SKILL.md` "Surface priority for CREATES"](../../dw-demo-base/SKILL.md) before reaching for SQL. This file is the router for cases where you have already decided SQL is the right surface.

## When this file applies

- You're seeding many Pages / GridRows / Paragraphs in one batch and MCP round-trips are prohibitively
  slow.
- MCP session died mid-batch and the remaining rows need to land via SQL fallback.
- A sister-demo replay script needs to drop pages into a fresh host before the MCP session is even warm.
- An item type does not have a corresponding MCP surface (rare, but happens for newer or
  project-prefixed `<Prefix>_*` types until you register the type via admin).

Everything below assumes you've already chosen SQL. If you're still deciding, escalate to MCP first
per the surface-priority rule above.

## The schema reference lives in the foundational skill

The vendor-generic SQL-direct content-row schema — the required NOT-NULL columns for `Page`
(including the `PageActiveFrom`/`PageActiveTo` silent-404 vector), `GridRow`, and `Paragraph`
(`ParagraphGlobalId` INT-not-GUID, the do-not-leave-empty `ParagraphTemplate`), the `ItemType_*`
instance rows (`ItemInstanceType=''` not NULL, `MAX(Id)` lies → `TRY_CAST`), the `GridRowSort × 10`
slot-reservation pattern, and the post-INSERT cache/restart rules — is owned by the `dw-data-access`
foundational skill — staged in
[`data-access.md`](../../dw-demo-base/references/foundational/data-access.md) ("SQL-direct content
seeding — Page / GridRow / Paragraph").

## Cross-references

- [`templates.md`](templates.md) — `PageActive` vs `PageHidden` ("Hidden in Menu") page-state
  semantics for the `Page` columns (routes to `swift-building.md` §6).
- [`paragraphs.md`](paragraphs.md) — the empty-`ParagraphTemplate` alphabetical-fallback hazard and the
  `ProductListComponentSelector` cache rule that makes soft-hide unreliable.
- [`data-access.md`](../../dw-demo-base/references/foundational/data-access.md) — the full required-field
  schema and post-mutation cache rules.
- [`b2b-dc-pattern.md`](b2b-dc-pattern.md) → `commerce-b2b.md` — the sister `AccessUser` NOT-NULL list
  for DC-group SQL-direct INSERTs.
