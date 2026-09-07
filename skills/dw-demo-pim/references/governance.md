# governance.md

## Contents

- [The governance demo is the planted-gap moment](#the-governance-demo-is-the-planted-gap-moment)
- [Derived spec values need a review stage, not a read-back](#derived-spec-values-need-a-review-stage-not-a-read-back)
- [Driving a worklist: what the drill-through actually opens](#driving-a-worklist-what-the-drill-through-actually-opens)
- [Where the platform facts live now](#where-the-platform-facts-live-now)
- [Demo recovery posture](#demo-recovery-posture)

> PIM governance for a Dynamicweb 10 demo — the demo framing around completeness rules, governance
> dashboards, and recovery. The platform facts (the 7 dashboard areas, the clickable-widget table,
> the `reference_category` mechanic + seed SQL, the completeness 7-condition checklist, the
> dashboard-query-Shared-ONLY rule, the standard-field preflight, the rebuild-index recipe) now
> live in the foundational skills; this file keeps the **demo-pedagogy** layer and routes to them.
> Loaded from the PIM demo SKILL.md "Where to find things" table.

## The governance demo is the planted-gap moment

A PIM governance demo lives or dies on one beat: **click a red blocker count, land on the exact
SKUs that are failing.** Everything else is setup for that moment.

- **Planted governance gaps are load-bearing.** Intentionally leave 2–4 products missing a
  channel-critical field so the Completeness panel on those products turns red and the dashboard
  blocker-count widgets show non-zero. A demo where everything is green looks like theater; a demo
  where 2 products block a channel feels real. (See also [demo-storytelling.md](demo-storytelling.md).)
- **Make every governance metric drillable.** Pick a `Repository*Widget` (clickable) over a scalar
  SQL widget (dead end) for every blocker count so the click-through beat works. The full
  clickable-vs-dead widget table + the "only 7 real dashboard areas" rule are platform facts in
  [`pim-completeness.md`](../../dw-pim-completeness/references/rules-and-dashboards.md).
- **Build the governance dashboard under the `Products` area** — the other areas DW accepts but
  never renders (platform fact: same candidate).

## Derived spec values need a review stage, not a read-back

Enriching from a product's own name and description is cheap and it launders the catalogue's own
defects into structured, trustworthy-looking data. A regex derivation pass over 413 masters produced 44
candidates; eyeballed against their source strings, **only 20 survived**. The 24 rejects fall into five
shapes, and four of them would have written a spec derived from ANOTHER product's description:

| Trap | Example |
|---|---|
| copy-paste source | a rodent-bait SKU carrying horse-fly-spray text derived `speciesTargets = equine`; a 12 V charger carrying tattoo-plier text derived `colour = green` |
| negation | "Latex-free head strap" derived `material = Latex`; "Will not harm rubber" derived `material = Rubber` |
| attachment | the ZIPPERS are brass, not the cotton-duck coverall; the JAR is plastic, not the ink; the END PLATE is black plastic, not the battery pack |
| model name | "The Green One" is a model name, not a colour |
| unit or field misfit | "75 G" is 75 grams, not a needle gauge; a 27 in measurement is the SUTURE length, not the needle |

- Treat derivation output as **candidates** and emit `{value, src}` per candidate so the review stage
  shows the matched source string beside every value.
- **Cross-check every candidate against the copy-paste and duplicate worklists before writing.** A
  product on `gov_copy_paste_descriptions` must be excluded from any description-derived enrichment:
  those rows are planted governance gaps the board counts on purpose, and enriching from them removes
  the defect from the story while writing a wrong fact.
- Record the rejects with their trap shape. They are demo material.
- Validate that the governance worklist count is **unchanged** after the pass, alongside the usual
  per-cell read-back.

## Driving a worklist: what the drill-through actually opens

- **A product opened from a governance worklist inherits the QUERY's screen preset, not the full
  editor.** `Screen.PresetId` travels in the URL, so the worklist route
  (`.../ProductEdit/...?Id=<id>&QueryId=<guid>&Screen.PresetId=14`) renders the thin, task-shaped
  form the query carries, while the same product reached from All products
  (`.../ProductOverview?Id=<id>`) renders the full Overview / Details / Prices editor with every
  enrichment attribute. That is deliberate: the worklist shows the work, not the whole record. **Say
  which one you are showing**, and caption demo frames for what they are. The preset grammar and the
  "no tab strip" discriminator live in [`screen-authoring.md`](screen-authoring.md).
- **Shoot grid edit from All products.** `ProductGridEdit` reached from a query worklist renders an
  empty table body while its own header reads "Products grid edit (10)" with "Filtered 10 /
  Changed 0" and all eleven preset columns drawn; it reads as a loading state that never finishes.
  Waiting (up to 29s), scrolling and collapsing the tree pane change nothing. The same action from
  All products (`Type=ProductsAll`, no `QueryId`, no `Screen.PresetId`) populates correctly. The
  cause is not established, so this is a demo-craft rule, not a mechanism: shoot the grid-edit frame
  from All products and do not promise the worklist route in the caption.
- **Per-persona favourites need no forged `Favorites.xml`.** The admin UI does not call `/Admin/Api`
  for this, so the bearer-only rule (`/Admin/Api` 401s a persona session cookie) is true and
  irrelevant here. Every query node in the Products tree carries a context menu with "Add to
  favorites" alongside Manage query / Copy / Move / Delete, and it writes
  `Files/System/SmartSearches/Ecommerce/Favorites/<AccessUserId>/Favorites.xml` for the **signed-in**
  user. Log the persona in with Playwright using their own credentials and click the context-menu
  entry. **Adding a favourite reloads and COLLAPSES the tree, so re-expand Shared queries > `<folder>`
  before every add** or the second and later nodes resolve to "missing". Validate the way the
  presenter sees it: reload `/Admin/UI/Products` as the persona and assert the node labels under
  "My favorites". Calling `MyFavoriteQueryAdd` with the API key and uploading a hand-built
  `Favorites.xml` works, but it proves nothing about what the persona sees and it needs the
  file-overwrite exception.

## Where the platform facts live now

| You need… | Foundational reference |
|---|---|
| The 7 real dashboard areas (don't invent) | [`pim-completeness.md`](../../dw-pim-completeness/references/rules-and-dashboards.md) "Dashboards — only 7 real areas" |
| Clickable vs dead-end widget types | [`pim-completeness.md`](../../dw-pim-completeness/references/rules-and-dashboards.md) "Clickable widgets" |
| Why completeness rules "don't show" (7-condition checklist) | [`pim-completeness.md`](../../dw-pim-completeness/references/rules-and-dashboards.md) "Completeness rules" |
| `reference_category` mechanic + the blank-panel gotcha | [`pim-completeness.md`](../../dw-pim-completeness/references/rules-and-dashboards.md) |
| Recovery: seed `reference_category` parent row (SQL) | [`pim-completeness.md`](../../dw-pim-completeness/references/rules-and-dashboards.md) "Recovery recipe: Seed `reference_category`" |
| Recovery: rebuild the Products index (SQL/API) | [`index-management.md`](../../dw-search-indexing/references/index-management.md) "Recovery recipe: Rebuild Products index" |
| Dashboard-query location — Shared ONLY + GUID-collision 500 | [`index-management.md`](../../dw-search-indexing/references/index-management.md) "Dashboard query location" |
| Standard `ProductField` inventory preflight (before customs) | [`pim-modelling.md`](../../dw-pim-modelling/references/structural-model.md) "Standard ProductField inventory" |
| Recovery: collapse a custom field back into its standard | [`pim-modelling.md`](../../dw-pim-modelling/references/structural-model.md) "Recovery recipe: collapse a custom field" |
| Post-mutation cache flush (when to restart) | [`cache-invalidation.md`](cache-invalidation.md) |

## Demo recovery posture

Recovery recipes always run inside Claude with port + DB in conversation state (base's
discover-from-project-files rule), so they live as fenced recipes in the candidates above rather
than standalone `.ps1` files. When a planted-gap demo build goes sideways, the usual order is:
seed `reference_category` if panels are blank → rebuild the index → confirm the widget counts move
→ verify the drill-through opens the offender list. The platform causal explanations behind each
"YES restart" sit in [`cache-invalidation.md`](cache-invalidation.md).
