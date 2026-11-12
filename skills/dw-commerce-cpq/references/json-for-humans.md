# Reading CPQ JSON for a person

The CPQ admin shows rule conditions, actions, BOM lines, lookup queries and settings as raw JSON.
This reference is the readable layer: which column holds which shape, how to say it in business
words, and the ten checks that find the mistakes nothing reports. The grammar itself is in
[rules-and-lookups.md](rules-and-lookups.md); evidence and version limits are in
[engine-characterization.md](engine-characterization.md).

## Contents

- [Which column holds which shape](#which-column-holds-which-shape)
- [Saying it in plain language](#saying-it-in-plain-language)
- [Ten checks](#ten-checks)
- [Changing it](#changing-it)

## Which column holds which shape

| Admin field | Column | Shape |
|---|---|---|
| Input rule: Conditions | `CPQInputRule.InputRuleConditions` | Array of condition groups |
| Input rule: Actions / ActionsElse | `InputRuleActions`, `InputRuleActionsElse` | Array of action objects; ActionsElse may be one bare object |
| BOM rule: Conditions / BomItems | `CPQBOMRule.BOMRuleConditions`, `BOMRuleBomItems` | Conditions; array of BOM lines |
| Route rule: Condition / Route items | `CPQRouteRule.RouteRuleCondition`, `RouteRuleRouteItems` | Conditions; array of route lines |
| Price rule: Conditions | `CPQPriceRule.Conditions` | Conditions, beside `Margin`, `Discount`, `DiscountType` |
| Group: Group Condition | `CPQGroup.GroupCondition` | Conditions; empty means the group's rules always run |
| Input: options | `CPQInput.InputOptions` | Array of options; each may carry `bom_items` |
| Input: Data Parameters | `CPQInput.InputDataParameters` | Lookup List query object (`sql_template`, `fields`, `filters`, `params`, `bom_item`) |
| Input: Settings | `CPQInput.InputSettings` | Array of `{"name","value"}` pairs |
| Model version: Settings | `CPQModelVersion.ModelVersionSetting` | One flat object |

Read every JSON column as JSON and keep the row id: it names the screen and the row to change.

## Saying it in plain language

- **One sentence per rule: when, then, otherwise.** Conditions give the "when", Actions the "then",
  ActionsElse the "otherwise". Eight `eq` tests on one input joined by `OR` with `show` / `hide` on a
  second input reads "when the first answer is one of these eight (name them), show the second
  question; otherwise hide it". A rule with no ActionsElse leaves the form as the last answer left it.
- **Resolve every reference first.** Input names become their labels, item numbers become product
  names, group names become group labels. A sentence that still contains an identifier is not finished.
- **Compare the sentence with the rule's own description.** A description saying "twin or greater"
  over a list that contains a single-engine product is the mistake the raw JSON hides.
- **"Why does X (not) appear":** list every input rule, BOM rule and option that names X in evaluation
  order (input, BOM, route, price; by sequence within a group) and say which one decides it for the
  stated answers. Say per hit whether X is read (a condition) or written (an action).
- **A lookup filter is explained by its effect** ("only engines whose length range contains the chosen
  hull's length"), never by reading the SQL aloud. `params` mapping a placeholder to an answer is how
  one question narrows the next.
- **A BOM line** reads as "adds `qty` of item `no` to the BOM group"; when `no` is not a catalogue
  product the line carries its own description, price and cost.

## Ten checks

None of these raises an error in the engine or the admin. Report each finding with the row id, what
goes wrong for the buyer, and the fix.

1. **Broken references.** Every `formInput[...]`, `forminput[...]` and `${forminput[...]}` names an
   existing input (the part before any dot). An unknown name never matches.
2. **Input rule without type.** `InputRuleType` is `CPQOptions`, or the rule is never loaded.
3. **Hidden but still answered.** A rule that hides an input without setting its value to `""` leaves
   the old answer driving later rules and the BOM. Clearing it in the same rule returns the cleared
   answer at once, but lines that hang off the chosen option (`bom_items`) are still priced in that
   response, because they come from the submitted answer; they drop on the next update. Where the line
   must go in the same step, move it into a BOM rule whose conditions test both inputs.
4. **Words that do nothing.** An action verb or operator outside the lists in
   [rules-and-lookups.md](rules-and-lookups.md), a `group_operator` not written `AND` / `OR`, the object
   form of a test, a misspelt `forminput`.
5. **BOM item number from an expression.** `no` containing `forminput` or `var[` adds no line.
6. **Overlapping BOM rules.** Two rules that can match together both add their lines.
7. **Lookup source.** A data source that needs an ERP connection returns an empty, silent option list
   without one; catalogue lists use `dw_sql`.
8. **Free text in SQL.** A `params` value taken from a free-text input is pasted into the query as is.
   Take params from a select, radio, number or another lookup's key only.
9. **Display.** An option input with images and no `option-columns` setting renders as full-width bars.
10. **Group gates.** A group with a `GroupCondition` runs none of its rules while the condition is
    false; check the gate first whenever a rule in that group "does nothing".

## Changing it

Draft the new JSON, show it beside a one-line before/after in plain words, and keep everything not
asked for byte-for-byte, key order and spelling included. Before handing it over: it parses, every
reference resolves (check 1), every item number exists, and checks 2 to 5 pass. Replace the whole
field, never a fragment, and read the row back after the save. Editing an input or group name field
alone leaves every rule that refers to it pointing at nothing; the rename constraint is in
[engine-characterization.md](engine-characterization.md).
