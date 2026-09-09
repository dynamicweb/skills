# CPQ models, groups and inputs

The data model behind a configurator, the input vocabulary, and the settings that bind a model to a
solution.

## Contents

- [Model, version, group, input](#model-version-group-input)
- [Model version settings](#model-version-settings)
- [Groups](#groups)
- [Inputs](#inputs)
- [The 17 input types](#the-17-input-types)
- [Input settings](#input-settings)
- [Model variables](#model-variables)
- [Naming, and why it is hard to change later](#naming-and-why-it-is-hard-to-change-later)

## Model, version, group, input

```
CPQModel
  └── CPQModelVersion          <- everything hangs off the VERSION, not the model
        ├── CPQGroup           <- GroupMode says what the group holds
        │     ├── CPQInput
        │     ├── CPQInputRule
        │     ├── CPQBOMRule
        │     ├── CPQRouteRule
        │     └── CPQModelVariable
        ├── CPQPriceRule
        ├── CPQOutputRule / CPQOutputAction
        ├── CPQQuickConfigure
        └── CPQConfiguration
```

`CPQModel` is little more than a container: `ModelName`, `ModelDescription`, `ModelSeq`,
`ModelDefault`. Only one model can be the default; setting it clears the flag on the others.

**`CPQModelVersion` is the working unit.** A version owns a complete, independent copy of its groups,
inputs, rules and outputs. `ModelVersionActive` is *not* exclusive — several versions can be active,
and the flag only breaks ties when the runtime has to guess a version.

## Model version settings

`ModelVersionSetting` is a JSON document on the version. It is where a model meets the solution
around it, and several of its keys are the difference between a model that works and one that
quietly does nothing.

| Key | Purpose |
|---|---|
| `EcomShopId`, `EcomLanguageId` | **which channel and language the model reads.** Set these first — catalogue lookups and pricing resolve through them |
| `PricingMethod`, `DefaultCostUpPercent`, `AllowOverridePrices`, `DecimalPlaces` | how a configured price is calculated and displayed |
| `CustomItemNumberPrefix`, `CustomItemName` | how a configured item's number and name are composed |
| `BaseProductGroup`, `CreateQuoteProductId` | the catalogue anchors for a created item |
| `CreateBomType`, `BomGroupDefaultName` | BOM shape and the default group name for uncategorised lines |
| `DefaultRunTimeRate`, `DefaultRunTimeMarginPercent`, `DefaultRoutingType`, `DefaultBaseUom`, `DefaultRouteCategoryName` | routing defaults |
| `QuickConfigurePageNavigationTag`, `DefaultPageNavigationTag` | **how the model finds its page** — see [pages-and-runtime.md](pages-and-runtime.md) |
| `AutoSelectSingleDefault`, `DefaultIgnoreCondition`, `DefaultImage` | input defaulting behaviour |
| `DataConnectionId`, `DataConnectionCompany` | the ERP target, **per version** |

`DataConnectionId` being per version is worth internalising: a version with no data connection fails
every ERP operation exactly as if no connector were configured anywhere, which is a confusing way to
discover the setting exists.

## Groups

`CPQGroup` is both the visual grouping of inputs and the container for rules. `GroupMode` decides
which:

| `GroupMode` | Contains |
|---|---|
| `input` *(default)* | inputs — a section or tab of questions |
| `input_rule` | input rules |
| `bom_rule` | BOM rules |
| `route_rule` | route rules |
| `model_variable` | model variables |

> `global_variable` is the legacy name for `model_variable` and survives only inside migration
> scripts. Write `model_variable`.

Other columns worth knowing: `GroupParentId` gives nesting, `GroupSeq` the order, `GroupLabel` the
display name (`GroupName` is the identifier that rules use), `GroupCondition` gates whether a rule
group runs at all, and `GroupArray` / `GroupTable` switch a group into repeating-row behaviour.

## Inputs

`CPQInput` columns, grouped by what they do:

- **Identity** — `InputName` (what rules address), `InputLabel` (what the user reads),
  `InputDescription`, `InputNotes`.
- **Behaviour** — `InputType`, `InputDefaultValue`, `InputRequired`, `InputVisible`, `InputReadOnly`,
  `InputEnabled`, `InputSeq`.
- **Options and data** — `InputOptions` for a hand-authored set; `InputDataSource` and
  `InputDataParameters` to drive options from data.
- **Presentation** — `InputImage`, `InputSettings`, `InputFieldWidth`, `InputStylingText`.
- **Other** — `InputExcludeFromCompare`, `InputAffectsCompleteness`, `InputDebug`.

Set `InputLabel` separately from `InputName`. The label is free to change; the name is not (see
below).

## The 17 input types

The admin label and the internal token, which is what appears in rules, templates and the client:

| Label | Internal |
|---|---|
| Button | `button` |
| Button Group | `buttonGroup` |
| Checkbox | `checkbox` |
| Checkbox Large | `checkboxLarge` |
| Colour Selector | `colorselector` |
| Date | `date` |
| Dropdown Select | `select` |
| Long Text | `longtext` |
| Lookup List | `lookup` |
| Number | `number` |
| Pop Up | `popup` |
| Radio | `radio` |
| Radio Box | `radiobox` |
| Rich Text | `richtext` |
| Separator | `separator` |
| Text | `text` |
| Toggle | `toggle` |

Note the spellings: `colorselector` is American and lowercase, `buttonGroup` and `checkboxLarge` are
camel, `radiobox` is not. `listbox` is an additional internal token sharing the *Dropdown Select*
label, and `textarea` is accepted as a synonym in the text branch.

Choosing between them:

- **Checkbox Large** is the multi-select. Its values arrive comma-joined, so rules test membership
  with `in`.
- **Radio Box** and **Button Group** are the picture-and-card presentations — use them where the
  choice is visual and the option count is small enough to show at once.
- **Colour Selector** exists for exactly the case its name suggests, and pairs with the
  `colourvalue` / `colorvalue` properties that `setproperty` can write.
- **Lookup List** is the one that reads from the catalogue — see
  [rules-and-lookups.md](rules-and-lookups.md).
- **Separator** and **Rich Text** carry no value; they are layout and copy.

## Input settings

`InputSettings` is a JSON **array of name/value pairs**, not an object:

```json
[
  {"name":"placeholder","value":"Search products"},
  {"name":"type","value":"list-box"},
  {"name":"show-filter","value":"true"},
  {"name":"list-box-height","value":"420px"},
  {"name":"no-label","value":"false"}
]
```


The names the templates actually read are a closed set — an unrecognised name is stored and ignored,
with nothing to say so. On the shipped Swift components they are:

| Setting | Applies to | Effect |
|---|---|---|
| `option-columns` | any option input | Column count of the option grid, 2–8. **Unset means one column**, which renders a stack of full-width bars — this is the single most common reason a configurator looks like a form rather than a catalogue |
| `option-image-class` | any option input | Class placed on each option's `<img>` |
| `option-inline` | `radio` | Options on one line; defaults to true at two options or fewer |
| `hide-label` / `no-label` | option inputs / any | Suppress the per-option label; suppress the question label and take the full width |
| `min` / `max` / `step` / `readonly` | numeric and text | The usual HTML semantics |
| `value-prefix` / `value-suffix` | numeric and text | Affixes rendered in an input group |
| `value-format` (or `format`) | numeric and text | `currency`, `inch`, `foot-inches`, `kg`. Sets a default affix and decimal places; `foot-inches` also forces read-only |
| `thousands-separator` / `decimal-places` | numeric | Override what `value-format` implied |
| `type` = `list-box`, `show-filter`, `list-box-height` | Lookup List | Render the lookup as a permanent list rather than a search field |

**Presentation belongs in these settings, not in template forks.** A well-built configurator drives
its whole look from `InputSettings` plus `InputStylingText` — the latter is emitted verbatim as a
class on every option element, which is how one input becomes image cards and the next becomes a
swatch tray without either being special-cased in Razor.

`colorselector` is worth knowing separately: it is a first-class input type that renders a tray of
circular swatches from each option's `ColourValue`, falling back to the option value as a CSS
colour. Where the colours are catalogue products with photography rather than flat hex values, a
`radiobox` styled through `InputStylingText` gets closer, because the swatch can be the product shot.

Several of the same names are reachable at runtime through `setproperty`, so a rule can change a
placeholder or a field width as the configuration progresses.

## Model variables

`CPQModelVariable` rows hold `ModelVariableName`, `ModelVariableValue`, a description and notes, and
live in a group whose `GroupMode` is `model_variable`. A rule reads one as `var[Name]`, addressing it
by `ModelVariableName`.

Use them for anything that would otherwise be a magic number repeated across rules — a rate, a
threshold, a default quantity. Changing the rate then means editing one row instead of hunting
through rule JSON.

Two names are built in and cannot be redefined: **`var[bom_total_sell]`** and
**`var[bom_total_cost]`**, which the price rules populate.

The admin ships an Excel import for model variables, which is the practical way to load a rate table
rather than typing rows.

Card-scoped variables are different: they persist as `CPQConfiguration` rows and are read as
`gvar[…]`. They are written version-agnostically, so they survive a model version change.

## Naming, and why it is hard to change later

Rules address an input as `formInput[GroupName_InputName]` — the group name is prefixed to make the
reference unique. Nothing validates that a reference resolves, so **renaming a group or an input
silently breaks every rule that mentioned it**: the rules still save, still run, and simply stop
matching.

So name inputs before writing rules, and name them for what they mean rather than how they read on
screen — `Hull_Length` rather than `WhatLengthWouldYouLike`. `InputLabel` carries the wording the
user sees and can be rewritten freely.

If a rename is unavoidable, search the rule JSON for the old reference across `CPQInputRule`,
`CPQBOMRule`, `CPQRouteRule` and `CPQPriceRule` before changing the name, and treat any lookup
`params` block as another place a reference can hide.
