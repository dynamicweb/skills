# CPQ engine evidence and characterization

This reference separates recorded behavior from experiments still needed for a new runtime
combination of Truvio Commerce (powered by Dynamicweb) and CPQ. It is a test plan, not a live
measurement report. No case below certifies the target platform merely by being written down. [dw 10.29.8]

## Contents

- [Evidence and version scope](#evidence-and-version-scope)
- [Seven authoring constraints](#seven-authoring-constraints)
- [Read surfaces and complete observations](#read-surfaces-and-complete-observations)
- [Truth-table experiments](#truth-table-experiments)
- [Model and handoff experiments](#model-and-handoff-experiments)
- [Evidence to retain](#evidence-to-retain)

## Evidence and version scope

The reviewed vendor package profile is explicit below. These are app versions, not a platform
compatibility stamp or a claim that this combination has passed a new installation:

```text
CPQ_Admin = 10.24.2
DW_CPQ_API = 10.24.2
Truvio.Commerce.CpqStudio = 0.7.0
```

Source corroboration is Studio commit `4a99413bf184217d9d110ee33dda8bac3eef7f44`:

- [Conditions reader and operator allowlist](https://github.com/truvio-commerce/Truvio.Commerce.CpqStudio/blob/4a99413bf184217d9d110ee33dda8bac3eef7f44/src/Native/Core/Conditions.cs).
- [Model checker](https://github.com/truvio-commerce/Truvio.Commerce.CpqStudio/blob/4a99413bf184217d9d110ee33dda8bac3eef7f44/src/Native/Core/Checker.cs) and
  [embedded CPQ guidance](https://github.com/truvio-commerce/Truvio.Commerce.CpqStudio/blob/4a99413bf184217d9d110ee33dda8bac3eef7f44/dynamo-skill/cpq-json-assistant.md).
- [Studio behavior and access contract](https://github.com/truvio-commerce/Truvio.Commerce.CpqStudio/blob/4a99413bf184217d9d110ee33dda8bac3eef7f44/README.md).

Repository access may be required. These identify the reviewed implementation and its recorded
engine findings; Studio's parser is not an independent execution of the vendor runtime. The
public skill contains no vendor decompiled source, customer model or host-specific receipt.

The condition correction follows the engine-inspection finding `k-fc9cc59c`. Related measured
failure records are `k-5723ae2a` (package/assembly identity), `k-dd71594c` (page-bound cart button),
`k-0c4523ab` (unobservable cart failure) and `k-78bb5b39` (SQL options losing selection before BOM).
They are provenance identifiers, not passing receipts for another installation. A newer package
must be characterized again. Record the installed package and loaded assembly hashes first.

## Seven authoring constraints

| Recorded vendor-profile behavior | What to check |
|---|---|
| A model variable/default containing `forminput[...]` stays literal. | Compare stored text and runtime result; a diagram must not infer an evaluated dependency. |
| An input rule without `InputRuleType=CPQOptions` never loads. | Check type, enabled state, group mode and version before testing actions. |
| Rule conditions/actions/lines use JSON textareas; list-screen classes do not establish reachable UI paths. | Read the actual editor and JSON; only assert routes discovered on the installed app. |
| Vendor rename crosses models/versions and misses price/output rules, line quantities, gates and lookups. | Resolve references within each version; use a scoped rename and compare untouched versions. |
| Groups, inputs, rules and outputs are version-owned; a page pins `ModelVersionId`. | Follow ownership joins and compare concrete IDs, not model names or active flags. |
| Vendor Duplicate creates a new model from the active version, or the newest if none is active. | Verify model and version IDs; test Studio's within-model version copy separately. |
| Settings save drops unknown `ModelVersionSetting` keys. | Keep custom ownership/spec metadata in a separate manifest and check supported settings after save. |

Studio 0.7.0 changes neither the vendor schema nor its rule JSON. Its variable-behavior diagram
is on by default, and BOM-grid row keys carry `id.stamp` to refuse stale edits. Neither change
proves the engine's cart/quote path or the SQL option-selection defect is fixed.

## Read surfaces and complete observations

Use equivalent exposed **MCP** tools first, then authenticated **Management API** queries found
on the target. Consume every page and verify scope and projection before comparing results.
SQL is a last observation surface for local installs only when higher surfaces omit raw JSON or
ownership fields; a SELECT needs no cache flush. No direct SQL write recipe is supplied here.

Studio's read and analyze operations belong to its own Dynamo tool pack, not the base MCP registry.
The [reviewed implementation](https://github.com/truvio-commerce/Truvio.Commerce.CpqStudio/blob/4a99413bf184217d9d110ee33dda8bac3eef7f44/src/Dynamo/CpqStudioTools.cs)
checks for the `/admin/dynamo` request context and administrator access; external
MCP requests are refused. Discover the current tool surface rather than assuming these operations are
externally callable. Follow `nextCursor` until `complete=true`; a denial or partial page is not an
empty model. Use authorized available queries for external inspection.

Runtime evaluation uses the vendor `/cpqapi` controller, a separate surface. Save, rename, copy,
cart, quote and document experiments mutate fixture state and belong in an isolated test target.
A read-only checker consumes matched evidence; it does not create those records itself.

## Truth-table experiments

Use neutral inputs named `Choice`, `Count` and `Flag`. Capture the stored condition JSON and the
submitted answers. Test the same expression in a group gate, input rule, BOM rule and price rule;
do not infer equivalence from the column containing JSON. All cases remain unexecuted for a new
package combination until an actual response is retained.

| Case | Recorded expectation or question to measure |
|---|---|
| Tuple `eq`/`neq`, equal and unequal strings | Positive and negative branches must agree with the declared comparison. |
| `group_operator=AND`/`OR`, all four two-boolean combinations | Measure truth tables, then nested combinations and multiple top-level groups. |
| Lowercase/missing group operator; `NAND`/`NOR` values | Recorded fallback is the `and` list; use discriminating inputs that distinguish fallback from the intended operator. |
| `left/operator/right` object with a false comparison | Recorded result is true (empty group). The authoring validator must reject it. |
| `contains`: answer `A`, right `AB`; then swap | Recorded results true then false: right contains answer. |
| `contain`, `==`, `!=`, `>`, `>=`, `<`, `<=`, `novalue`, `notempty`, `optional` | Outside the recorded allowlist; capture unsupported/false behavior and reject them in generated rules. |
| `in`: answer `A`, right `["A","B"]` versus `"A,B"` | Distinguish an alternatives array from one literal string. |
| `nin`, aliases, comma-joined checkbox answers | Measure each shape separately; do not assume scalar alternatives prove multiselect behavior. |
| `gt/gte/lt/lte` at below/equal/above a boundary | Measure numbers, numeric strings, decimal separators and nonnumeric text; coercion remains unresolved. |
| `hasvalue`, null, missing, empty string, zero and false | Measure separately; a stored default and a missing submitted answer may differ. |
| Empty group/list, mixed `and/or/nand/nor` lists, malformed JSON | Capture result/error; characterize legacy forms before accepting them. |
| Actual InputName, case variant, group-prefixed name not present in the table | Recorded lookup is the actual name, case-insensitively; detect unresolved references. |

Include valid controls beside invalid inputs so an unavailable endpoint cannot look like every
negative case passed. Restore fixtures after each mutation and compare the original model digest.

## Model and handoff experiments

- Verify loader type, rule ordering, ActionsElse and hidden-answer clearing. Measure the scope of
  `InputRuleStop`; the existing evidence does not settle group-only versus whole-pass stopping.
- Price fixtures distinguish first-match from cumulative rules, cost-up/margin grammar, discount
  order and decimal rounding. Expected monetary results come from the declared business case,
  not a second copy of the same rule interpreter.
- Test `dw_sql` options with `lookup`, `radiobox`, `select` and `checkbox`, retaining the selected
  option and emitted BOM before/after a dependent answer changes. Stable BOM's bounded replay
  addresses clearing in the same request; it is not evidence that option rebuilding is correct.
- Save and reopen cards against their original version; copy a version and create a card revision
  separately. Test scoped rename, stale grid edits and settings save from the seven-row table.
- Test cart controls on two unrelated page IDs and after restart. An HTTP 200 with no cart ID,
  no lines or a missing operation result is a failed handoff. Verify configured prices survive
  the Swift multi-line cart path rather than reverting to catalogue prices.
- Discover local quote routes and record whether the installed path requires an ERP connector.
  A local quote must return an ID, correct owner, lines, amounts and card linkage. On disposable
  synthetic users, anonymous and wrong-owner calls must not create or alter another user's quote.
  A reported missing authorization check on `CreateQuoteWithCard` is a regression case, not a
  supported access pattern. `SaveCardItem` needs the same ownership proof.
- Generate local DOCX without sending mail; PDF conversion has a separate dependency. Assert
  unavailable ERP operations explicitly when no connector is declared.

## Evidence to retain

Retain exact DW/package/assembly versions and hashes, model/version identity, canonical spec and
catalogue digests, fixture inputs, expected and observed results, request surface, complete-read
status, run/delivery identity and times. Compare facts before and after the run. A missing result,
partial enumeration, changed version or receipt from another host cannot pass. Preserve failures
and unknowns separately; writing this test plan does not turn either into a measurement.
