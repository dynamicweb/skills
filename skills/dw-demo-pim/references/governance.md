# governance.md

> PIM governance for a Dynamicweb 10 demo — the demo framing around completeness rules, governance
> dashboards, and recovery. The platform facts (the 7 dashboard areas, the clickable-widget table,
> the `reference_category` mechanic + seed SQL, the completeness 7-condition checklist, the
> dashboard-query-Shared-ONLY rule, the standard-field preflight, the rebuild-index recipe) now
> live in foundational candidates; this file keeps the **demo-pedagogy** layer and routes to them.
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
  [`pim-completeness.md`](../../dw-demo-base/references/foundational/pim-completeness.md).
- **Build the governance dashboard under the `Products` area** — the other areas DW accepts but
  never renders (platform fact: same candidate).

## Where the platform facts live now

| You need… | Foundational candidate |
|---|---|
| The 7 real dashboard areas (don't invent) | [`pim-completeness.md`](../../dw-demo-base/references/foundational/pim-completeness.md) "Dashboards — only 7 real areas" |
| Clickable vs dead-end widget types | [`pim-completeness.md`](../../dw-demo-base/references/foundational/pim-completeness.md) "Clickable widgets" |
| Why completeness rules "don't show" (7-condition checklist) | [`pim-completeness.md`](../../dw-demo-base/references/foundational/pim-completeness.md) "Completeness rules" |
| `reference_category` mechanic + the blank-panel gotcha | [`pim-completeness.md`](../../dw-demo-base/references/foundational/pim-completeness.md) |
| Recovery: seed `reference_category` parent row (SQL) | [`pim-completeness.md`](../../dw-demo-base/references/foundational/pim-completeness.md) "Recovery recipe: Seed `reference_category`" |
| Recovery: rebuild the Products index (SQL/API) | [`search-indexing.md`](../../dw-demo-base/references/foundational/search-indexing.md) "Recovery recipe: Rebuild Products index" |
| Dashboard-query location — Shared ONLY + GUID-collision 500 | [`search-indexing.md`](../../dw-demo-base/references/foundational/search-indexing.md) "Dashboard query location" |
| Standard `ProductField` inventory preflight (before customs) | [`pim-modelling.md`](../../dw-demo-base/references/foundational/pim-modelling.md) "Standard ProductField inventory" |
| Recovery: collapse a custom field back into its standard | [`pim-modelling.md`](../../dw-demo-base/references/foundational/pim-modelling.md) "Recovery recipe: collapse a custom field" |
| Post-mutation cache flush (when to restart) | [`cache-invalidation.md`](cache-invalidation.md) |

## Demo recovery posture

Recovery recipes always run inside Claude with port + DB in conversation state (base's
discover-from-project-files rule), so they live as fenced recipes in the candidates above rather
than standalone `.ps1` files. When a planted-gap demo build goes sideways, the usual order is:
seed `reference_category` if panels are blank → rebuild the index → confirm the widget counts move
→ verify the drill-through opens the offender list. The platform causal explanations behind each
"YES restart" sit in [`cache-invalidation.md`](cache-invalidation.md).
