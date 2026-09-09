# CPQ rules and lookups

Everything the engine evaluates: conditions, actions, BOM rules, price rules, evaluation order, and
the catalogue-driven Lookup List.

## Contents

- [Where rules live](#where-rules-live)
- [Conditions](#conditions)
- [Operators](#operators)
- [Actions](#actions)
- [Variables and expressions](#variables-and-expressions)
- [BOM rules](#bom-rules)
- [Price rules](#price-rules)
- [Output rules](#output-rules)
- [Evaluation order](#evaluation-order)
- [Cascading options](#cascading-options)
- [Lookup Lists from the catalogue](#lookup-lists-from-the-catalogue)

## Where rules live

Rules are rows in `CPQInputRule`, `CPQBOMRule`, `CPQRouteRule`, `CPQPriceRule` and `CPQOutputRule`,
and — apart from price and output rules, which key on the model version — they hang off a
`CPQGroup` whose `GroupMode` says which family it holds (`input_rule`, `bom_rule`, `route_rule`).

A group can gate its own rules. `CPQGroup.GroupCondition`, per the admin help: *"For input_rule,
bom_rule, and route_rule groups: run rules in this group only when this condition is true. Leave
empty to always run."* Use it to switch off whole families cheaply rather than repeating a condition
on every rule.

Ordering is `…Seq` within a group, filtered on `…Enabled = 1`.

> Rules were migrated from keying on the model version to keying on a group, with an auto-created
> group named `Group1` per version. Tooling written against the older shape finds nothing and fails
> quietly.

## Conditions

Two dialects parse. The engine detects which by shape, and can migrate between them.

### Tuple dialect

The form the admin seeds into a new rule:

```json
[
  {
    "group_operator": "AND",
    "and": [
      ["formInput[text]", "eq", "text"]
    ]
  }
]
```

The top level is an **array of group objects**. Each group carries `group_operator` (`AND` or `OR`)
and a matching `and` / `or` array. An element is either a three-element array `[left, operator,
right]` or a nested group object. Nesting, mixed operators, and boolean right-hand sides:

```json
[
  {
    "group_operator": "AND",
    "and": [
      ["formInput[General_Usage]", "eq", "Commuting"],
      {
        "group_operator": "OR",
        "or": [
          ["formInput[Frame_BottleCageMounts]", "eq", true],
          ["formInput[Frame_BagMounts]", "eq", true],
          ["formInput[Frame_RackMounts]", "neq", "None"]
        ]
      }
    ]
  }
]
```

### Object dialect

```json
[
  {
    "and": [
      { "left": "forminput[Qty]",  "operator": ">",  "right": 0 },
      { "left": "forminput[Type]", "operator": "==", "right": "Premium" }
    ]
  }
]
```

`group_operator` may be omitted; a bare `and` array is enough.

### Referencing an input

`formInput[GroupName_InputName]` — the group name is prefixed to make the reference unique. Matching
is case-insensitive, so `formInput` and `FormInput` both resolve. A property is addressed with a dot
inside the brackets:

```
FormInput[Frame_InternalCableRouting.visible]
```

### Matching a multi-select

Use `in`. A multi-select control submits its values comma-joined, and `in` tests membership:

```json
[
  {
    "group_operator": "AND",
    "and": [
      ["formInput[General_WhatMattersMost]", "in", "Appearance"]
    ]
  }
]
```

## Operators

The runtime dispatch table:

```
eq   in   nin   notin   not in   gt   gte   contain   neq   ne   lt   lte   start with   end with
```

Two spellings catch people out: **`contain`** is singular, and **`start with` / `end with`** contain
a space. The symbolic forms the admin help advertises — `==`, `!=`, `>`, `>=`, `<`, `<=`, `contains`
— are normalised on the way in, so both styles work; pick one and hold to it.

`hasvalue`, `novalue`, `notempty` and `optional` are presence tests, not comparisons.

Combinators include the negated pairs: `AND`, `OR`, `NAND`, `NOR`, and nested groups.

## Actions

Two shapes, freely mixed in one array:

```json
[
  {
    "action": "setvalue",
    "setvalue": { "FormInput[text.visible]": false }
  },
  {
    "target": "group[text]",
    "action": "show"
  }
]
```

A derivation, computing into a variable and then reading it back:

```json
[
  {
    "target": "var[Extras_Total_plus_3]",
    "action": "sum",
    "data": ["forminput[Extras_LineSellPrice]", "3.3"]
  },
  {
    "target": "forminput[Result]",
    "action": "set",
    "setvalue": { "forminput[Result]": "var[Extras_Total_plus_3]" }
  }
]
```

**Verbs**: `setvalue`, `set`, `setproperty`, `setoptions`, `select`, `sql`, `query`, `concat`, `sum`,
`add`, `sub`, `substract`, `mul`, `multiply`, `div`, `mod`, `round`, `show`, `hide`, `showoptions`,
`hideoptions`, `enableoptions`, `disableoptions`, `setoutputactionvisible`, `debugprint`.

**`required`, `readonly` and the rest are properties, not verbs.** Reach them through `setproperty`,
whose targets are:

```
placeholder  datasource  inputdatatype  stylingtext  fieldwidth  defaultvalue
required  readonly  debug  price  qty  itemno  discount  visible  selected
disabled  image  colourvalue  colorvalue  label  step
```

There is no `clear`, `message`, `error` or `warning` verb. A rule written with one saves without
complaint and does nothing.

### ActionsElse

Runs when the conditions evaluate false. It accepts a bare object as well as an array:

```json
{
  "action": "setvalue",
  "setvalue": {
    "FormInput[Frame_InternalCableRouting.visible]": false,
    "FormInput[Frame_InternalCableRouting]": false
  }
}
```

The admin's own guidance is worth following: put narrow conditions first and broad fallbacks in
`ActionsElse`.

## Variables and expressions

| Form | Resolves to |
|---|---|
| `forminput[Group_Input]` | the input's current value |
| `forminput[Name.prop]` | an input property — `.value`, `.visible`, `.description`, `.labelname`, `.qty` |
| `var[Name]` | a `CPQModelVariable` row, addressed by `ModelVariableName` |
| `gvar[Name]`, `gvar[carditem]` | card-scoped variables, stored as `CPQConfiguration` rows |
| `group[Name]` | an input group — the target of `show` / `hide` |
| `bomitem[ItemNo]`, `route_item[…]` | the BOM or route line under evaluation |
| `salesquote[Field]` | a quote header field |
| `card[…]` | card scope — `card[source]`, `card[address]`, `card[city]`, `card[email]`, and so on |
| `item(N)`, `item(key:value)` | a BOM line by index or by match |

Two names are built in and reserved: **`var[bom_total_sell]`** and **`var[bom_total_cost]`**.

Interpolation is `${forminput[X]}` or `{forminput[X]}`, accepted for `forminput`, `var` and
`salesquote`. Aggregate functions are `sum`, `count`, `avg`, `max`, `min`; row functions are
`select` and `distinct`. Arithmetic verbs are the action list above.

There is **no third-party expression engine** — evaluation is hand-rolled, so the vocabulary above is
the whole of it. Do not reach for `iif`, `abs()`, `substring()` or anything from a spreadsheet.

> A misspelled alias `fominput` is accepted alongside `forminput`. Never write it.

## BOM rules

`CPQBOMRule` holds `BOMRuleConditions` and `BOMRuleBomItems`. The items are a JSON array of lines.

The minimal line, for a SKU that exists in the catalogue:

```json
[{ "no": "10167", "qty": "1", "type": "Item" }]
```

A full custom line, for something the catalogue does not have:

```json
[{
  "bom_group": "TAILGATE",
  "category": "Subcontractor",
  "no": "E-000056",
  "description": "Custom tailgate",
  "qty": "var[ReqQty]",
  "type": "Item",
  "rlc": "var[ReqRlc]",
  "run_time": "var[ReqRunTime]",
  "setup_time": "0",
  "price": "var[CustomPrice]",
  "cost": "var[CustomCost]",
  "unit_cost_per": "var[CustomUnitCostPer]"
}]
```

**The item number is a literal.** Neither `forminput[Input]` nor `${forminput[Input]}` resolves in a
BOM item's `no` — the rule saves, evaluates, and contributes no line, with nothing logged. Expression
references do work in the value fields (`qty`, `price`, `cost` take `var[...]`), but the SKU itself
must be written out. So the shape is **one rule per selectable outcome**, conditioned on that value,
which is exactly how the vendor's own worked example reads ("if use = Commuting, then Frame item =
10167"). For an option list of any size, generate the rules rather than hand-writing them.

This is also why `BomRuleConvertToInputOptionCommand` exists, and why an input option carries its own
`BomItems`: both are ways of avoiding a rule per SKU.

**The rule for what to include**, in the vendor's own words: *"You only include the segments you
need. If the item is in the DynamicWeb Product table, then information is automatically used.
Otherwise, you need to specify it in the BomItems section."*

So `no` and `qty` are always required. When the SKU resolves in `EcomProducts`, description and
pricing come from the product record. When it does not, spell out `description`, `price`, `cost` and
`unit_cost_per`, plus `rlc` / `run_time` / `setup_time` if the line feeds a route. An unresolvable
SKU falls back to a placeholder product rather than failing.

`type` takes `Item`, `Custom Item`, `Budget` or `Resource`. Note the shipped Swift template renders
only `Item` and `Production BOM`, so `Budget` and `Resource` lines exist in the data but not on that
page — a template limit, not an engine one.

Keys accept both snake and camel spelling: `bom_items` / `bomItems`, `bom_group` / `bomGroup`,
`run_time` / `runTime`, `setup_time` / `setupTime`, `unit_cost_per` / `unitCostPer`.

Rules **accumulate** lines. Two matching rules contribute both sets, so make conditions exclusive
rather than depending on sequence.

A BOM rule can be converted into an input option set, but only in its simplest form: one condition
group, a single `AND`, one form-input condition, and the `in` operator.

## Price rules

`CPQPriceRule` carries `Conditions`, `Margin`, `Discount`, `DiscountType` and `CPQPriceRuleSort`.
Margin marks cost up to a sell price; the discount then comes off the sell. `DiscountType` is
`Percent` or `Dollar`.

Evaluation orders by `CPQPriceRuleSort` then id. Whether matching is first-match or cumulative is
not established — verify against your own data before relying on either.

`Margin` and `Discount` are free-text columns and no example of their grammar exists in the product
or its documentation. Establish the shape empirically on a scratch model before designing pricing
around it.

## Output rules

`CPQOutputRule` selects `CPQOutputAction` rows. An output action is a **document, optionally
emailed** — its columns are a file, a filename, a convert-to-PDF flag, and the email fields. There
is no action type vocabulary; behaviour is driven by those flags. Do not plan on output actions
creating records.

## Evaluation order

All evaluation is **server-side**. The client holds no interpreter: it POSTs the whole form and
re-renders what comes back.

```
input rules -> BOM rules -> route rules -> route totals -> price rules -> output rules -> document
```

Groups walk their hierarchy by sequence, gated by `GroupCondition`; rules run in `…Seq` order within
a group.

Every input change triggers a **full re-run** — the client rebuilds the entire value array and posts
it. There is no incremental or dependency-graph evaluation, so a rule cannot rely on being skipped.
In-flight requests are aborted and stale responses dropped.

Each submitted value carries `{name, value, visible}`. **`visible` is transmitted per input**, so a
rule can condition on whether a control is currently shown — and a hidden input still sends its
value, which is a common surprise: hiding a control does not clear it. Set the value explicitly if
hiding should also reset.

Inputs the server set come back flagged `auto_set`.

`InputRuleStop` halts processing at that rule, logged as *"Stop flag encountered at rule …"*.
Whether it stops the group or the whole pass is not established. `CPQBOMRule` and `CPQPriceRule`
have no stop column.

## Cascading options

The central modelling idiom: an answer to one question changes what can be chosen in the next. This
is where a configurator earns its keep, and it is **configuration in the model, not data in the
catalogue**. There are four mechanisms, and choosing the wrong one is the usual reason a model
becomes unmaintainable.

### 1. Narrow the option set — `showoptions` / `hideoptions`

The input keeps its full option set; a rule reveals the subset that applies. Use when the option
list is short, fixed, and authored on the input.

```json
[
  { "target": "forminput[Power_EngineCount]", "action": "hideoptions", "data": ["Triple", "Quad"] }
]
```

Pair it with `ActionsElse` so the options come back when the condition stops holding — a rule that
only ever hides leaves the form in whatever state the last answer left behind.

### 2. Replace the option set — `setoptions`

A rule supplies the options outright, so different answers produce genuinely different lists rather
than subsets of one list. The engine also accepts an option set resolved from a variable, which is
how a long list stays out of the rule body.

Use when the second question's answers have little overlap between branches.

### 3. Enable rather than hide — `enableoptions` / `disableoptions`

Shows the option greyed out instead of removing it. Prefer this when the customer should *see* that
something exists but is not available for their choices — it answers "why can't I have X?" without
them asking, which is worth a great deal in a guided sale.

### 4. Let the data do it — a Lookup List with `params`

When the options come from the catalogue and the relationship is expressible as product data, do not
write a rule at all. Give the second input a `dw_sql` Lookup List whose `filters` reference the first
input through a `params` placeholder:

```json
{
  "fields": { "value": "p.ProductNumber", "label": "p.ProductName" },
  "filters": { "and": [
    "p.fitsMinPower <= ${chosenPower}",
    "p.fitsMaxPower >= ${chosenPower}"
  ]},
  "params": { "chosenPower": "${forminput[Power_TotalPower]}" },
  "sortby": "p.ProductName"
}
```

Now adding a product to the catalogue adds an option, and no rule changes. **This is the mechanism to
reach for whenever the constraint is a property of the product rather than a business decision.**

### Choosing between them

| The relationship is… | Use |
|---|---|
| A property of the product (a size band, a power range, a fitting type) | A Lookup List with `params` — attributes on the product, filtering in the query |
| A business decision with few outcomes (this trim level offers these three finishes) | `showoptions` / `hideoptions` on an authored option set |
| A business decision whose branches share nothing | `setoptions` |
| Something the customer should see but cannot have | `disableoptions` |

**Keep the constraint logic in the model.** Product fields answer *what a thing is* — its size band,
its power range, what it physically fits. The rules answer *what we will sell together*, and those
belong in `CPQInputRule` JSON where they can be read, versioned and changed without touching the
catalogue. Encoding a commercial rule as a product relation splits the logic across two systems and
leaves neither telling the whole story.

### Two behaviours that catch people out

**A hidden input still submits its value.** Hiding a control does not clear it, so a stale answer can
keep driving downstream rules and BOM lines. When hiding should also reset, set the value in the same
rule:

```json
[
  { "action": "setvalue", "setvalue": { "FormInput[Power_Joystick.visible]": false,
                                        "FormInput[Power_Joystick]": "" } }
]
```

**Every input change re-runs every rule.** There is no dependency graph, so a cascade is only as
ordered as its rule sequence within a group. Where B depends on A and C depends on B, put them in
that `Seq` order rather than assuming the engine will work it out.

## Lookup Lists from the catalogue

The reason to use CPQ rather than a hand-maintained option list: an input can read its options from
the product catalogue, so adding a product adds an option.

Set `CPQInput.InputDataSource` to **`dw_sql`** (admin label *DW SQL Query*). The full label set is
`Custom Options`, `DW SQL Query`, `DW Users`, `Number List`, `Table Select`, `BC Lookup`, `BC Odata`;
the runtime discriminators are `options`, `dw_sql`, `dw_user`, `number_list`, `odata`, `bc_get`,
`lookup`.

> **`odata` and `BC Lookup` query Business Central.** With no connector configured they return an
> empty option list and no error. For catalogue-driven options, `dw_sql` is the one you want.

`InputDataParameters` holds the configuration. A complete example reading products, with a
placeholder that makes this lookup depend on another input:

```json
{
  "sql_template": "SELECT DISTINCT {fields} FROM EcomProducts p WHERE {filters}",
  "fields": {
    "value": "p.ProductNumber",
    "label": "p.ProductName",
    "image": "(SELECT TOP 1 d.DetailValue FROM EcomDetails d LEFT JOIN EcomDetailsGroup dg ON DetailsGroupId = EcomDetailsGroupId WHERE d.DetailProductId = p.ProductID AND dg.EcomDetailsGroupSystemName = 'Images')"
  },
  "filters": { "and": ["p.ProductID LIKE '${productTypeCode}'"] },
  "sortby": "p.ProductName",
  "params": { "productTypeCode": "${forminput[Control_ProductType]}" },
  "limit": 20,
  "bom_item": {
    "bom_group": "",
    "no": "{value}",
    "qty": "forminput[Control_Qty]",
    "type": "Item",
    "rlc": "",
    "run_time": "0",
    "setup_time": "0"
  }
}
```

| Key | Behaviour |
|---|---|
| `sql_template` | Optional. Defaults to `SELECT {fields} FROM EcomProducts WHERE {filters}` |
| `fields` | Substituted into `{fields}`. `value`, `label`, `image` — each an arbitrary SQL expression, so `image` can be a correlated subquery |
| `filters` | `{"and":[…]}` or `{"or":[…]}`, substituted into `{filters}`. Defaults to `1=1` |
| `sortby`, `limit` | Become `ORDER BY` and `OFFSET … ROWS FETCH NEXT … ROWS ONLY` |
| `params` | Named `${name}` placeholders used in `filters`; their values may be CPQ expressions, which is how one lookup depends on another input |
| `bom_item` | Optional. Selecting a row emits this BOM line, with `{value}` replaced by the chosen key — the bridge from lookup to BOM |

A shorter form exists when no template is needed:

```json
{
  "key_field": "ProductId",
  "label_field": "ProductName",
  "from": "EcomProducts",
  "where": "ProductActive=1",
  "limit": 20
}
```

Presentation is configured in `InputSettings`, a JSON array of name/value pairs:

```json
[
  {"name":"placeholder","value":"Search products"},
  {"name":"type","value":"list-box"},
  {"name":"show-filter","value":"true"},
  {"name":"list-box-height","value":"420px"},
  {"name":"no-label","value":"false"}
]
```

### Write lookups defensively

**The SQL is string-interpolated, not parameterised.** Values are concatenated into the statement;
there is no parameter binding anywhere in the engine. The engine does validate that referenced
tables exist and rejects author-supplied paging keywords before appending its own, but those are
correctness guards, not injection guards.

So: interpolate values that come from constrained inputs — a select, a radio, a number, another
lookup's key — and keep free-text inputs out of `filters`. Where a free-text search is genuinely
needed, the engine supplies `searchkey` for exactly that purpose; prefer it over interpolating a
text input yourself.

A lookup whose tables or columns do not resolve is skipped with a log line and renders empty, so an
empty option list means either the SQL did not resolve or the data source is pointed at an ERP that
is not connected.
