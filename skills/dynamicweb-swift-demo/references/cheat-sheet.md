# cheat-sheet.md — the hidden demo info page

> Owns the canonical recipe for the hidden-from-nav demo info page at `/<area-url>/demo` (typical URL slug `demo`) that the presenter keeps on a side screen during the live demo, plus the customer-safety rules for its content. Driven end-to-end by the `/dynamicweb-cheatsheet` command.

## What the page contains

- The demo logins — one row per user with username, display name, role. **Neutral phrasing only.**
- Key URLs — homepage, shop landing, per-category shop URLs, sign-in, customer center, `/Admin`.
- A small "catalogue at a glance" facts panel — counts, not pitch angles.

## Customer-safety rules

**Keep it customer-safe — assume the customer might glance at it.** Do NOT bake in:

- "Demo angle" / "Story beat" / "What to show" columns that explain HOW to win the demo
- Internal nicknames or segment slang ("the X hero", "Tier-1 retailer", "the closing slide")
- Tech-leaking context ("plaintext for the demo; auto-rehashes to SHA-512", DB versions, .NET runtime)
- Internal phase / decision / pitfall IDs
- Pitch-deck framing ("this is the moment when you say ..."); save those for speaker notes elsewhere

## Hidden-via-sort mechanics

The page is published (`hidden=false`, accessible by URL) but kept out of navigation by setting `sort=1000`-ish (well past the visible nav range) and not adding it to any header/footer menu. Do NOT use `hidden=true` — that excludes the page from frontend routing entirely.

## Build recipe (MCP only) — the canonical 5-step chain

The naive `save_paragraphs` create-with-`itemType=Swift-v2_Text` path does NOT auto-create the underlying item instance — `itemId` stays empty and the Swift Text template renders nothing. The working pattern is **clone an existing Swift-v2_Text paragraph**, then rewrite its content:

1. **`save_pages`** — `id=0, areaId=<area>, urlName='demo', menuText='Demo Info', active=true, hidden=false, navigationTag='DemoInfo', sort=1000, metaTitle='Demo information'`. Capture the new page id.
2. **`save_grid_rows`** — `id=0, pageId=<new>, container='Grid', definitionId='1Column', itemType='Swift-v2_Row', sort=1`. Capture the new grid row id.
3. **`copy_paragraph`** — `paragraphId=<any existing Swift-v2_Text paragraph id from the homepage>`, `targetPageId=<new>`. The clone preserves the underlying `Swift-v2_Text` item instance, giving you a real `itemId` to target. Capture the new paragraph id and its `itemId`.
4. **`set_item_field_values`** — on `(itemType: 'Swift-v2_Text', itemId: <cloned>)`, set `Text` to the cheat-sheet HTML (Bootstrap `table.table-bordered` + `card` grid for the facts panel both work without custom CSS). Set `Title` and `Subtitle` to empty strings to clear what cloned over.
5. **`save_paragraphs`** — update the cloned paragraph: `gridRowId=<from step 2>, gridRowColumn=1, template='TextLeft.cshtml'` (full-width left-aligned), `header=''` (clear the cloned header).

**Caveat:** `active=false` on `save_paragraphs` does NOT reliably persist for already-existing paragraphs — if you need to retire an obsolete paragraph on the page, clear its `text`/`header` fields and let it render empty rather than expecting `active=false` to hide it. (The same no-op applies to `ShowParagraph` via the Management API — there, hide via `ParagraphDelete` instead.)

**Hosted/API-only installs:** the same clone-then-rewrite chain maps onto the Management API — copy a simple page as the carrier (`PageCopy`; clear the inherited `shortCut`), `ParagraphCopy` an existing Swift-v2_Text paragraph onto it, `GridRowCopy` a 1-column row, then `ParagraphSave` round-trips for content and row attachment. Endpoint shapes in [`dynamicweb-demo-base/references/online-mode.md`](../../dynamicweb-demo-base/references/online-mode.md) (validated DW 10.25.x, 2026-06-10).

## Reality-check role

The cheat-sheet page doubles as the "go deep, not wide" gauge (see SKILL.md "Demo philosophy"): if its login table or "key URLs" list doesn't fit on one side-screen at presenter zoom, the demo has gone wide.
