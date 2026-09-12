# cheat-sheet.md — the hidden demo info page

> Owns the canonical recipe for the hidden-from-nav demo info page at `/<area-url>/demo` (typical URL slug `demo`) that the presenter keeps on a side screen during the live demo, plus the customer-safety rules for its content. Driven end-to-end by the `/dynamicweb-cheatsheet` command.

## What the page contains

- The demo logins — one row per user with username, display name, role. **Neutral phrasing only.**
- Key URLs — homepage, shop landing, per-category shop URLs, sign-in, customer center, `/Admin`. **Measure the prefix before writing any of them**: it is the area culture as a path segment (`en-US` → `/en-us/`), not the area's url name, which is commonly decorative — fetch a known page under each candidate and keep the one that answers 200 (`dw-swift-building` Core Rules). A cheat-sheet full of 404s is worse than none.
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

## Build recipe (MCP only) — the canonical 4-call chain

**A bare `save_paragraphs` create mints the item instance.** On DW 10.28.x with MCP 0.4.4 a create with `id=0` and `itemType='Swift-v2_Text'` returns a populated `itemId`, and `set_paragraph_item_fields` writes straight to it — so the page is built in the four-call order `save_pages` → `save_grid_rows` → `save_paragraphs` → `set_paragraph_item_fields` ([`dw-swift-page-design`](../../dw-swift-page-design/SKILL.md) §"The create order", which also owns the button-blanking rule below). Clone-then-rewrite over `copy_paragraph` survives only as a fallback for a build where `itemId` comes back empty; it costs a donor read plus a copy per paragraph and imports the donor's field values as a starting state nobody chose.

**Blank `FirstButton` and `SecondButton` in the same `set_paragraph_item_fields` call as the copy.** A bare create materialises the item type's shipped string defaults into those `ButtonEditor` fields, whose runtime type is a `ButtonData` object, so the paragraph renders a `ConverterException` block inside an HTTP 200 page — invisible to a status check and to a field read-back alike. The clone path never hit this because a clone inherits the donor's already-cleared buttons.

1. **`save_pages`** — `id=0, areaId=<area>, urlName='demo', menuText='Demo Info', active=true, hidden=false, navigationTag='DemoInfo', sort=1000, metaTitle='Demo information'`. Capture the new page id. **The slug comes from `urlName`.** On DW 10.28.x with MCP 0.4.4 `urlName` is persisted and wins over the `menuText`-derived slug, so pass the slug you want and let `menuText` carry the label. No page read projects `urlName`, so confirm it by **polling** the composed URL until it answers 200 (allow at least 15 seconds — URL resolution is cached and lags the save, so an immediate fetch 404s on a correct write) — never by reading the page back and inferring the slug from `menuText`. **Product limit:** `navigationTag` and the visibility members ARE members of the `save_pages` input schema, each with its own description — they are accepted and then **not persisted** (verified 10.27.x-10.28.x), so the page lands with no navigation tag and default visibility no matter what you pass, and the response echoes what you sent. Do not go looking for a better-named tool; there is none. Keep `hidden=false` and rely on the `sort=1000` mechanic below for nav exclusion, and drive menu placement with `set_page_menu` instead of the tag column.

**Out-of-product fallback, labelled as one:** the column writes for the navigation tag and `PageHidden` live in [`dw-data-access`](../../dw-data-access/SKILL.md) `recipes-content.md` §"Set `PageNavigationTag`". They are a last resort under the retirement notice in [`sql-direct-seeding.md`](sql-direct-seeding.md), not a default step: never reach for them because the API got hard, only because the API provably cannot express the result.
2. **`save_grid_rows`** — `id=0, pageId=<new>, container='Grid', definitionId='1Column', itemType='Swift-v2_Row', sort=1`. Capture the new grid row id.
3. **`save_paragraphs`** — `id=0, pageId=<new>, itemType='Swift-v2_Text', template='TextLeft.cshtml'` (full-width left-aligned), `gridRowId=<from step 2>, gridRowColumn=1, sort=100, active=true`. The response carries the new paragraph id and a populated `itemId`.
4. **`set_paragraph_item_fields`** — on the new paragraph id, in ONE call: `Text` = the cheat-sheet HTML (Bootstrap `table.table-bordered` + a `card` grid for the facts panel both work without custom CSS), `Title` and `Subtitle` = `""`, and `FirstButton` and `SecondButton` = `""`. Write vertical spacing in `Text` as markup (`<p>` elements or a `<br>` pair) — the field renders raw, so a blank line is whitespace in the markup rather than a gap on the page. The value itself round-trips byte for byte through `set_paragraph_item_fields` ([`dw-content-modelling/references/page-paragraph-writes.md`](../../dw-content-modelling/references/page-paragraph-writes.md)).
5. **Render it.** Fetch the page and assert the table is there, with zero `ConverterException` and zero emitted `<pre class="dw-error">` blocks. A `succeeded` write plus an HTTP 200 does not prove the paragraph rendered.

**Caveat:** `active=false` on `save_paragraphs` does NOT reliably persist for already-existing paragraphs — if you need to retire an obsolete paragraph on the page, clear its `text`/`header` fields and let it render empty rather than expecting `active=false` to hide it. (The same no-op applies to `showParagraph` via the Management API — it is silently ignored. There, hide via `hideForDesktops` / `hideForTablets` / `hideForPhones = true`, which do take effect, and reserve `ParagraphDelete` for paragraphs you actually want gone.)

**Hosted/API-only installs:** where MCP is not the surface, the clone-then-rewrite chain maps onto the Management API — copy a simple page as the carrier (`PageCopy`; clear the inherited `shortCut`), `ParagraphCopy` an existing Swift-v2_Text paragraph onto it, `GridRowCopy` a 1-column row, then `ParagraphSave` round-trips for content and row attachment. Endpoint shapes in [`dw-demo-hosted/references/online-mode.md`](../../dw-demo-hosted/references/online-mode.md) (validated DW 10.25.x). Two `PageCopy` inheritance traps bite this chain — copied paragraphs keep the source page's `Button` fields, and a shortcut copy can out-render the page carrying the `navigationTag`; both in [admin-ui-authoring.md](admin-ui-authoring.md) §"Management API authoring traps". Also note the paragraph `name` you pass on create is overwritten from `Title` by the next save, so capture the returned paragraph id for any later update ([paragraphs.md](paragraphs.md)).

## Demo voucher / coupon hygiene (presenter runbook, not page content)

A demo coupon is **single-use per completed order by default** — and a completed rehearsal order silently kills the pricing-cascade beat on demo day (the voucher no longer applies). Note the asymmetry: **applying a voucher at checkout does not consume it; completing an order does.** So a rehearsal that stops before order completion is safe; one that places the order burns the coupon.

Two ways to keep it from biting — record whichever you chose in the demo's runbook (speaker notes / `notes\`, **not** the customer-safe cheat-sheet page, which must stay free of tech-leaking context per "Customer-safety rules"):

- **Seed demo vouchers unlimited-use by default** — the simplest safe posture for a demo coupon that only needs to *show* a discount, not enforce a limit.
- **When single-use is deliberate** (the story is about redemption limits), the runbook MUST carry the **reset SQL** that re-arms the voucher after a rehearsal order, plus the "applying ≠ consuming" note so the presenter knows exactly when it was spent.

## Reality-check role

The cheat-sheet page doubles as the "go deep, not wide" gauge (see SKILL.md "Demo philosophy"): if its login table or "key URLs" list doesn't fit on one side-screen at presenter zoom, the demo has gone wide.


