---
name: dw-commerce-cpq
type: knowledge
group: commerce
mcp: none
dynamo: false
description: 'Build Carrot Solutions CPQ configurators on DW10. Triggers: input/BOM/price rules, Lookup Lists, CPQ pages/cards, ERP requirements, blank pages or empty options. Product variants/BOM -> dw-pim-modelling; discounts -> dw-commerce-orders.'
---

# Dynamicweb CPQ

Carrot Solutions CPQ is a configure-price-quote engine that installs into Dynamicweb 10 as two
NuGet add-ins. A **model** asks questions, **rules** decide what the answers mean, and the result is
a priced bill of materials on a **card** that behaves as a quote or order header.

It is a partner product, not a platform feature, so the platform documentation does not cover it and
the vendor guide is a tutorial rather than a reference. Everything here is grounded in the shipped
assemblies, templates and schema.

## Contents

- [The one question that shapes every project](#the-one-question-that-shapes-every-project)
- [The pieces](#the-pieces)
- [Build order](#build-order)
- [References](#references)
- [Traps that cost an afternoon](#traps-that-cost-an-afternoon)

## The one question that shapes every project

**CPQ does not need an ERP.** A complete configurator — inputs, rules, BOM, routing, pricing,
summary, cart, quote, order and a generated document — runs entirely inside Dynamicweb.

Business Central is reached only to *materialise* a result as an ERP record. Every one of those
paths guards itself and returns early when no connector is configured, so nothing calls out and
nothing fails:

| Local, always | Needs a Business Central connector |
|---|---|
| All rule evaluation (input, BOM, route, price, output) | Creating the BC **item card** |
| Pricing — reads `EcomProducts` and the platform price service | Creating the **production BOM** and **routing** |
| Cart, order and quote via `/dwapi/ecommerce/carts/…` | Creating **sales quote headers and lines** |
| Cards, revisions, templates, configurations | Storing the generated document **in BC** |
| Document generation (OpenXml `.docx`) | Refreshing customer info from a BC quote |

Two consequences worth stating to a customer early. First, a CPQ demo or pilot needs no ERP at all.
Second, the BOM-line table carries `BCStatus`, `BCLineNo` and `BCItemNo` columns that simply stay
null until a connector exists — so adding the ERP later fills those in rather than reworking the
model.

The exception that bites: a **Lookup List authored as `odata`** queries the connector, and with no
connector it renders an empty option list and no error. Author catalogue lookups as `dw_sql`. See
[rules-and-lookups.md](references/rules-and-lookups.md).

## The pieces

**Data model.** `CPQModel` → `CPQModelVersion` → `CPQGroup` → `CPQInput`, with the rule families
hanging off groups. **A version owns a complete independent copy** of its groups, inputs, rules and
outputs — `CPQGroup.GroupModelVersionId`, `CPQPriceRule`, `CPQOutputRule`, `CPQQuickConfigure` and
`CPQConfiguration` all key on `ModelVersionId`, never on `ModelId`.

`CPQGroup.GroupMode` decides what a group holds: `input`, `input_rule`, `bom_rule`, `route_rule` or
`model_variable`. So rules live in groups exactly as inputs do, and a group can carry a
`GroupCondition` that gates whether its rules run at all.

**Rules**, evaluated server-side in a fixed order on every input change:

```
input rules -> BOM rules -> route rules -> route totals -> price rules -> output rules -> document
```

**Cards.** `CPQCard` is a quote or order header, `CPQCardItem` is one configured item on it — holding
the new item number, the exploded BOM, the total, and `ClientInputsJson`, the full set of answers
that produced it. `CPQCardItemBomLines` is the priced BOM. A card links to a Dynamicweb order and
stays in sync with it. See [cards-and-erp.md](references/cards-and-erp.md).

**Frontend.** A `CPQ_Page` bound to one model *version*, built from `CPQ_*` paragraph item types on
`CPQ_Row` grid rows, driven by a single POST to `/cpqapi/model` per change. See
[pages-and-runtime.md](references/pages-and-runtime.md).

## Where the logic lives

The boundary that keeps a model maintainable: **the catalogue is data, the model is logic.**

- **Product fields say what a thing *is*** — its size band, its power range, what it physically fits.
- **CPQ rules say what you will *sell together*** — which options appear, which are excluded, what
  reaches the BOM. That lives in `CPQInputRule` / `CPQBOMRule` JSON, versioned with the model.

So an answer constraining the next question is configuration in the model, not a relation in the
catalogue. Four mechanisms do it — `showoptions` / `hideoptions`, `setoptions`, `disableoptions`, and
a `dw_sql` Lookup List filtered by a `${forminput[...]}` placeholder — and picking the wrong one is
the usual reason a model stops being maintainable. The rule of thumb: when the constraint is a
property of the product, let the lookup query express it; when it is a commercial decision, write it
as a rule. Both, with the choosing table, are in
[rules-and-lookups.md](references/rules-and-lookups.md) ("Cascading options").

Encoding a commercial rule as product data splits the logic across two systems and leaves neither
telling the whole story.

## Build order

1. **Install** the two packages and confirm the schema and templates landed —
   [install.md](references/install.md).
2. **Create the model and its first version**, then set `ModelVersionSetting`: at minimum
   `EcomShopId` (which channel the model reads), `PricingMethod`, and the item-number prefix.
   Settings are listed in [model-and-inputs.md](references/model-and-inputs.md).
3. **Model the input groups and inputs** before writing a single rule. Name inputs meaningfully —
   rules address them as `formInput[GroupName_InputName]`, and renaming later means editing every
   rule that mentions them.
4. **Build the page early**, with a `CPQ_Tabs` paragraph and an explicit `CPQ_Theme`, and preview it
   as soon as one input group exists. Both omissions fail silently (see traps).
5. **Add input rules**, then BOM rules, then price rules — in evaluation order, so each layer is
   observable before the next depends on it.
6. **Drive long option lists from the catalogue** with `dw_sql` Lookup Lists rather than hand-typed
   options, so adding a product adds an option.

## References

| File | Covers |
|---|---|
| [install.md](references/install.md) | The two packages, their dependencies, what the update providers create and when, and how to verify an install |
| [model-and-inputs.md](references/model-and-inputs.md) | Model/version/group/input schema, all 17 input types with their internal tokens, `InputSettings`, model variables, and every `ModelVersionSetting` key |
| [rules-and-lookups.md](references/rules-and-lookups.md) | Condition and action JSON in both dialects, the operator table, `setproperty`, BOM rules, price rules, evaluation order, and the complete `dw_sql` Lookup List configuration |
| [pages-and-runtime.md](references/pages-and-runtime.md) | The 18 item types, page assembly, themes, the `/cpqapi/` surface, and the request cycle |
| [cards-and-erp.md](references/cards-and-erp.md) | Cards, card items, BOM lines, templates, revisions, the Dynamicweb order link, and the ERP boundary in full |

## Traps that cost an afternoon

Each of these fails **silently** — no error, no log a page author would see.

**The templates may land in a design folder the solution does not use.** The install writes the
layouts, row definitions and assets into one particular Swift design folder; if the area's layout
points at a differently-named design, every CPQ template is invisible. The page then renders through
the area layout with no CPQ assets and no CPQ rows, and nothing reports an error. Compare the two
paths first whenever a CPQ page renders as an ordinary page.

**A page with no `CPQ_Tabs` paragraph renders blank.** The CPQ grid row template starts every row at
`display:none`; the tab script is what reveals them. Add the tabs paragraph with the first row.

**An unset `CPQ_Theme` loads no theme stylesheet.** The master interpolates the field value verbatim
as a filename stem and falls back to a value that matches no shipped file. Always set the theme
explicitly on the page.

**A `CPQ_Page` is pinned to a `ModelVersionId`, not to a model.** Publishing a new version does not
move existing pages — re-point every page by hand. The picker labels versions by *model name* only,
so two versions look identical in the dropdown. There is no foreign key, so deleting a model can
leave a live page pointing at a version id that no longer exists.

**A Lookup List authored as `odata` needs Business Central.** With no connector it returns an empty
option list and no error. Use `dw_sql` for catalogue-driven options.

**An input rule with no `InputRuleType` never loads.** The loader filters on
`InputRuleType='CPQOptions'`, so a rule saved without it is enabled, correct, and inert. The engine's
own log names the symptom: `LoadInputRule=0ms`.

**Rules address inputs by `formInput[Group_Name]`.** Renaming a group or an input silently breaks
every rule that referenced it, because an unresolved reference is not an error.

**Lookup SQL is string-interpolated, not parameterised.** A lookup whose filter interpolates a
free-text input is a concatenated query. Keep interpolated values on constrained inputs — a select,
a radio, a number — rather than free text.

**`required` and `readonly` are not action verbs.** They are properties set through `setproperty`.
Writing them as verbs produces a rule that saves cleanly and does nothing.

**Rules accumulate BOM lines rather than replacing them.** Two rules that both match contribute
both lines; use conditions to make matches exclusive rather than relying on order.
