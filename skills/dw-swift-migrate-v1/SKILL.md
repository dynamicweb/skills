---
name: dw-swift-migrate-v1
type: flow
group: swift
description: 'Migrate pages from a Swift 1 (Swift v1) solution to Swift 2 and KEEP THE LAYOUT — a faithful, structure-preserving port (Swift 1 and Swift 2 share the same grid model, so the layout carries over 1:1). Reuses site extraction + page-build tools in faithful mode with an explicit Swift 1 -> Swift 2 component/layout mapping. Triggers: migrate a Swift 1 site to Swift 2 keeping the layout, port Swift v1 pages 1:1, faithful Swift 1 -> Swift 2 conversion. Non-triggers: a free content re-design or a non-Swift-1 source -> dw-swift-migrate-content; a plain new page with no migration source -> dw-swift-page-design.'
---

# Swift 1 → Swift 2 Migration

Use this skill when the user wants to migrate pages from a **Swift 1** (Swift v1) solution to
**Swift 2** and **keep the layout** — as faithful and structure-preserving as the pipeline
allows, not a free re-design. The fact that makes this worth a dedicated skill: **Swift 1 and
Swift 2 are the same grid model** (paragraphs positioned by row + column; the row
`DefinitionId` set overlaps almost 1:1), so the original layout can carry over instead of
being re-imagined.

This is the faithful sibling of [dw-swift-migrate-content](../dw-swift-migrate-content). That
skill rebuilds ANY source into *standard, modern* Swift 2 and **deliberately re-flows content
into new compositions (not 1:1)**. Choose by intent:
- "migrate all the pages/content from this site, make it modern" →
  [dw-swift-migrate-content](../dw-swift-migrate-content).
- "it's a Swift 1 site, port it and **keep the layout / don't redesign / 1:1**" → THIS skill.
- a single new page with design intent, no migration source → [dw-swift-page-design](../dw-swift-page-design).

**Load [dw-swift-page-blocks](../dw-swift-page-blocks) first** for the target vocabulary.

## Mechanism — and exactly what you can and cannot steer (read this)

The MCP server runs against ONE solution (the **target** Swift 2 site); it does **not** read
the Swift 1 database directly. The Swift 1 source comes in through the same pipeline
`dw-swift-migrate-content` uses: `extract_site_content(sourceUrl)` reads it over `/dwapi` →
page tree → `Rows` → `Columns` → `Blocks` (each block has a stable id; each row a
`LayoutHint`). You then author per-page `Plan`s and `build_pages` writes them. Content can
neither be lost nor invented — a verbatim ledger enforces it, and a failed plan falls back
loudly to the deterministic mapper.

What the **Plan actually controls** (verified against the build pipeline — do not promise
more):
- **Row layout** — set the Plan row's `DefinitionId` from the source `LayoutHint`. It is
  honored **as long as every column keeps at least one block**. If a column ends up empty,
  the build drops it and **re-derives the layout from the real column count** (e.g. a
  `3Columns` with one empty cell becomes `2Columns`). So: one block per column, no empties,
  and the layout survives.
- **Per-row color band** — set the Plan row's `ColorSchemeId`. **You assign this**; the
  source banding is NOT extracted. Use it to recreate section contrast (hero/`primary`,
  alternating `light`/`lightgrey2`).
- **Component choice — only for six block types**: `Swift-v2_Text`, `Swift-v2_Poster`,
  `Swift-v2_Image`, `Swift-v2_Card`, `Swift-v2_Slider`, `Swift-v2_Accordion`. For these, the
  Plan's `Component` (+ `Variant`) is honored. **For every other block, omit `Component` —
  the deterministic mapper picks the v2 component by content shape, and you cannot override
  it from the Plan.**
- **Dispositions** — each block is `used`, `merged-into:<id>`, or `dropped:<reason>` (reason ∈
  chrome|breadcrumb|empty|duplicate-nav|product-list|product-detail|ecommerce|out-of-scope).
  For a faithful port, merge ONLY true noise — keep each real block as its own paragraph.

So "faithful" here means: **layout preserved + banding assigned + every block kept in place +
the six steerable components pinned + the rest mapped faithfully-by-shape.** It is NOT
byte-identical, and for non-steerable blocks the component is the mapper's choice, not yours.
Say so.

## Mapping table (Swift 1 → Swift 2), tiered by what you can steer

**Tier 1 — pin in the Plan** (set `Component`, it is honored):

| Swift 1 | Plan `Component` | Variant |
|---|---|---|
| `Swift_Text`, `Swift_TextAdvanced` | `Swift-v2_Text` | TextLeft/Center/Right |
| `Swift_Poster`, `Swift_TextBanner` | `Swift-v2_Poster` | TextMiddleLeft / TextBottomLeft |
| `Swift_Image` | `Swift-v2_Image` | Plain |
| `Swift_Slider`, `Swift_Carousel` (+ items) | `Swift-v2_Slider` | (from children) |
| `Swift_Accordion` (+ items) | `Swift-v2_Accordion` | Flush |

**Tier 2 — omit `Component`; the mapper maps by content shape** (you can't pin the exact
type, but it lands faithfully for normal content): `Swift_Feature`, `Swift_Button`,
`Swift_TextAndImage`, `Swift_Blockquote`, `Swift_Employee`, `Swift_Logo`,
`Swift_VideoPlayer`/`VideoPoster`, `Swift_SectionHeader` (→ centered text), navigation/
breadcrumb chrome. State in the summary that these were mapper-chosen, not Plan-pinned.

**Tier 3 — side-list and skip from the automated rebuild** (no clean target; `build_pages`
creates fresh pages and cannot carry these over verbatim): `Swift_MegaMenu` (no v2
equivalent), the Article/Blog subsystem (`ArticleHeader`/`ArticleList` — v2 uses a different
`PostList` model), product list/detail, e-commerce, modules/apps (`eCom_*`, `App`, Cart/
Checkout), and RawHTML / custom `.cshtml`. These need a human; never guess or silently drop
them.

Row `DefinitionId`s map near 1:1 (`1Column`, `2Columns`, `2Columns_4-8/8-4/3-9/9-3`,
`3/4/6Columns`, `*Flex`). `5ColumnsFlex` has no v2 twin → nearest (`6ColumnsFlex`) or split;
flag it.

## Flow

1. **Confirm once.** State the source + target and that it is a **faithful,
   layout-preserving** Swift 1 → Swift 2 port. Once the user agrees, run to completion — one
   final summary, no per-batch stop.
2. **Target precondition.** Build into a real Swift 2 area (`save_areas` with the v2 master
   `LayoutTemplate`, `Active` + `Published`); confirm the design folder name from
   `get_layouts`.
3. **Discover target vocabulary once.** `get_row_definitions`, `get_item_types`,
   `get_paragraph_templates`, `get_layout_containers`.
4. **Extract the Swift 1 source.** `extract_site_content(sourceUrl, [auth])` → tree + brand +
   media + warnings. Note `SourceHost`.
5. **Brand & chrome before pages.** `apply_brand_color_scheme(targetAreaId, sourceHost)`, then
   `setup_website_chrome(targetAreaId, sourceHost)`; carry Master/area settings by meaning
   (`get_item_type_fields` on the area item type). `import_site_media(sourceHost)`.
6. **Port pages in batches — faithful Plans.** Per page: `get_extracted_page` → author a Plan
   that (a) sets each row's `DefinitionId` from its `LayoutHint`, (b) keeps one real block per
   column (no empties → layout survives), (c) pins `Component`+`Variant` for the Tier-1 types
   and omits it for the rest, (d) assigns each row a `ColorSchemeId` for banding, (e) marks
   every block `used`/`merged-into`/`dropped:<reason>` — dropping only chrome/breadcrumb/
   empty. `build_pages(targetAreaId, [specs], sourceHost)`; repeat while `HasMore`, re-send
   only failures.
7. **Verify + one final summary.** Confirm every extracted block is accounted for (the
   validator enforces it). Side-list explicitly: Tier-2 blocks (mapper-chosen, name the
   component it picked if surprising), every Tier-3 item skipped for a human, any row whose
   layout re-derived because a column emptied, the `5ColumnsFlex` nearest-pick, and any page
   whose plan fell back to the faithful mapper.

## Honesty floor

- "Faithful" ≠ "identical": extraction is content-shape based, the Plan only steers six
  component types, and layout survives only when columns stay populated. State what was
  preserved vs mapper-chosen vs approximated.
- Account for EVERY block in `Dispositions`; drops only for the closed reason set. Never
  silently re-flow or drop.
- Tier-3 (article/product/commerce/module/custom/MegaMenu): side-listed and skipped, never
  guessed or faked.

## Out of scope

The article/blog subsystem, product list/detail and e-commerce, modules/apps, custom HTML/
`.cshtml`, MegaMenu, and in-place platform upgrades (see [dw-setup-upgrade](../dw-setup-upgrade)).
Pixel-identical reproduction is not achievable through extraction — faithful structure +
banding + content is the goal.
