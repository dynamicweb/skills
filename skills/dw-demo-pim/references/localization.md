# localization.md

> PIM-side localization for a Dynamicweb 10 demo — **demo-flavoured** guidance only. The vendor-generic
> platform mechanics (two-table model, must-translate/fallback list, `AllowChangesAcrossLanguages`
> seed + SQL, `EcomLanguages` columns, MCP-tool surfaces + gotchas, the `GetGroup()`-returns-null
> group-translation gotcha, the vestigial XML config) live in
> [`../../dw-pim-localization/references/translation-mechanics.md`](../../dw-pim-localization/references/translation-mechanics.md).
> Read that first; this file holds only the demo deltas. Loaded from `~/.claude/skills/dw-demo-pim/SKILL.md`
> "Where to find things". Sister doc to `dw-demo-swift/references/language-layers.md` (content/area side).

## When to use

- A demo asks for a second (or third) language on the storefront and the products need localized names / descriptions.
- A customer's pitch includes "we sell into <market>" and the storefront should switch into that language with native field values.
- You need to demo the side-by-side translation UI in PIM.

If the question is "add another **website** in another language," that's
[`../../dw-demo-swift/references/language-layers.md`](../../dw-demo-swift/references/language-layers.md)
(content side). The two surfaces are independent — you can have area=da-DK but product values still in
en-US (just with a different culture-derived UI chrome) and vice versa.

## Recipe — adding a new language to a PIM-only demo

The platform steps (insert `EcomLanguages` row, translate group names, translate product fields, rebuild
index, wire the area) are in the candidate's
[Adding a new language — the platform steps](../../dw-pim-localization/references/translation-mechanics.md#adding-a-new-language--the-platform-steps).
The demo deltas on top of that sequence:

1. **Pick the products to translate.** For a demo, translate **only the hero SKUs the storyline lands on** (typically 5-12 products) plus all the catalog group names — translating the full catalogue is wasted demo budget.
2. **Translate group names first.** This is the highest-visibility win for the least work and is load-bearing (the `GetGroup()`-null gotcha in the candidate) — a blank category grid on a language layer is that gap, every time.
3. **Translate the hero products' name + short description.** Skip custom-field translation in a first pass; the fallback handles it.
4. This recipe fits between **Step 3 (languages)** and **Step 4 (manufacturers)** of [`canonical-setup-order.md`](canonical-setup-order.md); the first `EcomLanguage` row is set up there, additional languages follow this doc.

## Translation worklist that opens side by side

A translation dashboard whose rows open the product in the side-by-side language view is native, and
no widget setting carries it: the query does [dw 10.29.6].

1. **The query**: a translation-gap predicate (with the Completeness feature flag on, a per-language
   `CompletionRule|<id> < 100` query; see
   [`../../dw-pim-localization/SKILL.md`](../../dw-pim-localization/SKILL.md) "Per-language completeness"),
   *Edit screen languages* set to every language to compare (MCP `editScreenLanguageIds`), an edit preset
   (`editScreenViewPresetId`), and *Open product in edit mode* on.
2. When those languages resolve to more than one language the product has, a row click opens
   `/Admin/UI/Products/MultiEdit?...&Type=MultiEditByQuery` with the languages side by side and the edit
   preset applied. Any product-aware row inherits this from the query.
3. **The widget**: `Dynamicweb.Products.UI.Dashboard.Widgets.ProductQueryListWidget` renders the query's
   rows as product list rows, so a click opens Multi Edit. It is `[AddInActive(false)]` and absent from
   the Add widget picker, but `add_widgets_to_dashboards` with that system name (parameters `Query`,
   `TitleField`, `HintField`, `RightField`) adds it and it renders. It cannot be re-added from the picker
   once removed. `RepositoryGridWidget` rows are not product-aware and open the plain editor. A
   `RepositoryCountWidget` tile opens the query list, whose rows then open Multi Edit.

Validate by clicking a widget row: the URL is `MultiEdit` with one model identifier per configured
language.

## Demo philosophy

PIM localization sells the "single product master, multiple market storefronts" story — high-leverage. But:

- **Translate depth, not width.** Localize 8-12 SKUs that the demo flow touches (hero PLPs + PDPs). Don't translate the long-tail; the demo flow never lands on it.
- **Translate at least one custom field** (e.g. a marketing tagline) to show the "all field types translatable" point. Translating ONLY the name leaves the demo feeling shallow.
- **Translate group names** (navigation localizes) — this is the highest-visibility win for the least work.
- **Skip variant options + assets translation** unless the customer's pitch specifically lands on them. Fallback covers the rest.

## Cross-references

- [`../../dw-pim-localization/references/translation-mechanics.md`](../../dw-pim-localization/references/translation-mechanics.md) — the vendor-generic platform mechanics this demo guidance builds on.
- [`../../dw-demo-swift/references/language-layers.md`](../../dw-demo-swift/references/language-layers.md) — the area / content side; how to add a website language layer + wire the Swift `LanguageSelector` paragraph type so the frontend can actually switch.
- [`canonical-setup-order.md`](canonical-setup-order.md) — where the language steps fit in the build order.
