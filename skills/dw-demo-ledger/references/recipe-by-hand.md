# Following a recipe by hand (MCP tools only)

An agent that has the Dynamicweb MCP tools and no shell cannot run
[Invoke-DwRecipe.ps1](../scripts/Invoke-DwRecipe.ps1), but it can do what the script does: a recipe
is a JSON document that names every tool call, its arguments and how to check the answer. This page
shows how to read one. The contract is [recipes.md](recipes.md); which recipes exist, their run order
and what each leaves undone is [recipe-index.md](recipe-index.md).

## Contents

- [Before the first call](#before-the-first-call)
- [Reading a step](#reading-a-step)
- [Worked example: one page](#worked-example-one-page)
- [After the steps](#after-the-steps)
- [What to report](#what-to-report)

## Before the first call

1. Open the customer data file and the recipes whose input section it holds, in the order
   recipe-index.md "Run order" lists.
2. In each recipe read `modes.mcpOnly`. `usable: false` means at least one step has no MCP
   binding; its `reason` names it. Do the other steps; report that one, never substitute SQL or a
   file edit for it.
3. Call `tools/list` once. Every tool a binding names must be there; take the argument names from
   its input schema, because a wrong argument name answers only "An error occurred invoking".

## Reading a step

| Member | What you do with it |
|---|---|
| `forEach` | Repeat the step for each element of that list in the input section (`pages[*]`); the element is `item`, the element it sits in is `parent` |
| `skipWhen` | Skip the item when the condition holds on the input |
| `after` | Do the item only when the earlier step named there reported one of the given states for it |
| `key` | The natural key: how you name the object in your report, never an id |
| `find.bindings` | Use the first binding whose `surface` is `mcp` and `status` is `implemented`. Call `operation` with `arguments`, take the list at `rows` (`data`, or `$` for the whole answer) and keep the rows whose members equal `match` |
| `compare` | One matching row with these members equal: nothing to do (UNCHANGED). Different: update. No row: create. Two rows: stop and report a duplicate |
| `bindings` | The writes: the first `mcp` + `implemented` one. `create` for a new object, `update` for a changed one (`{found.<member>}` is the matched row) |
| `readBack` | After the write, read again and check `expect`. The id comes from this read, never from the write's answer |
| `produces` | Values to remember per key for later steps: `{step.pages[item.parent].id}` is the id the `pages` step produced for the key this item's `parent` names |
| `trap` | A platform fact that bites this step; read it before the call |

Tokens: `{input.x}` is the recipe's input section, `{item.x}` and `{parent.x}` the forEach element,
`{build.areaId}` the input's `build` section, `{secret.x}` a password you were given by reference
(never write it down), and `{a|b}` means "a, or b when a is absent". A whole-value token keeps its
type: an id stays a number.

## Worked example: one page

`content.pages`, step `pages`, for the input item `{"menuText": "About us", "itemType": "Swift-v2_Page", "urlName": "about-us"}` with `build.areaId` 1 and no `parent`:

1. Find: `get_pages_by_parent_id {"parentId": 0, "areaId": 1}` (`{step.pages[item.parent].id|0}`
   is 0 because the item has no parent). Take `data`, keep the rows whose `menuText` is `About us`.
2. One row, `itemType` equal: UNCHANGED, remember its `id` for the child pages. No row: create.
3. Create: `save_pages {"pages": [{"id": 0, "areaId": 1, "parentPageId": 0, "menuText": "About us", "urlName": "about-us", "itemType": "Swift-v2_Page", "active": true, "sort": null}]}`.
4. Read back: the same `get_pages_by_parent_id` call; exactly one `About us` row with that
   `itemType`. Its `id` is what the later steps (`page-title`, `rows`, `paragraphs`) use.

The child page `Our history` with `parent: "About us"` then finds with `parentId` = that id. If
`About us` was not created, its child is not created at the website root: stop that item.

## After the steps

- `debts`: what the platform is owed once anything changed. An index build is MCP
  (`build_product_index` and `wait_for_product_index` with both names, then
  `get_product_index_status` must show documents); an assortment build is `build_assortments`. A
  `flush:<service>` and a `recycle` have no MCP tool: report each as owed, with the recipe's wording.
- `verify.probes`: run the ones with an `mcp` + `implemented` binding and check `assert`
  (`count`, `equals`, `contains`, `excludes`) on the matching rows. A probe that is a delivery read
  (`dwapi`) cannot be observed with MCP tools: report it as not observed, never as passed.

## What to report

One line per step item (`STEP pages CREATED About us`), one per debt (paid, or owed and why), one
per probe (passed, failed with the observed value, or not observed). The same lines
[recipes.md](recipes.md) "Output contract" defines, so a later run with the script reads the same.
