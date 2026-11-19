# Recipes: the replayable form of a ledger function

A recipe is the proven, replayable form of one Truvio Commerce (powered by Dynamicweb) ledger
function or family: the ordered steps that deliver it, the debts it owes the platform afterwards,
and how to verify it. It is declarative data first, so an agent that has only MCP tools can read it
and follow it by calling the named tools with the stated arguments, and
[Invoke-DwRecipe.ps1](../scripts/Invoke-DwRecipe.ps1) runs the same file.

## Contents

- [Where recipes live](#where-recipes-live)
- [The document](#the-document)
- [Bindings and the honesty rule](#bindings-and-the-honesty-rule)
- [Tokens](#tokens)
- [Steps: find, apply, read back](#steps-find-apply-read-back)
- [Debts](#debts)
- [Verify: probes and ledger checks](#verify-probes-and-ledger-checks)
- [Modes](#modes)
- [Following a recipe by hand](#following-a-recipe-by-hand)
- [Running a recipe](#running-a-recipe)
- [Output contract](#output-contract)
- [Adding or promoting a recipe](#adding-or-promoting-a-recipe)

## Where recipes live

| File | What it is |
|---|---|
| `assets/recipes/<area>/<id>.json` | One recipe; `<id>` is its primary ledger function id, such as `users.accounts` |
| [assets/recipe.schema.json](../assets/recipe.schema.json) | The recipe schema (draft 7) |
| [assets/recipe-input.schema.json](../assets/recipe-input.schema.json) | The customer data file: one section per recipe input section |
| [assets/recipe-input.example.json](../assets/recipe-input.example.json) | A generic example input for both example recipes |
| [assets/handlers.json](../assets/handlers.json) | The allowlists: `recipeWriteTools`, `recipeAdminCommands`, and the read lists the ledger shares |

Recipes stay **outside** `assets/releases/<version>/`. The snapshot digest covers every file in a
release directory, so a recipe added there would change the digest and break every consumer's lock.
A recipe names the release it was measured on in `provenOn` instead.

## The document

| Field | Meaning |
|---|---|
| `id`, `name` | The primary function id, and a human name |
| `functions` | The ledger function ids it delivers. Each must exist in a release listed in `provenOn`, or in the newest snapshot while `provenOn` is empty |
| `skill` | The skill that owns the primary function in the ledger |
| `inputs` | `section`: the input file section it reads; `required`: paths that section must hold |
| `modes` | Per mode, whether the recipe is usable and why not (see [Modes](#modes)) |
| `steps` | Ordered steps; each finds its objects by natural key, then creates or updates and reads back |
| `debts` | What the platform is owed after a change: `flush:<service>`, `index:<repository>/<index>`, `assortments`, `recycle` |
| `verify` | `checkIds`: ledger checks of its functions; `probes`: behavioural reads with an assertion |
| `provenOn` | `{dwVersion, mcpVersion, date, evidence}` per measured run; empty means unproven |
| `traps` | Platform facts that bite this function, one per line |

No field holds a host, a URL, a machine path, a credential or a customer name: the repository
validator and the runner both refuse one. A password is named by a reference key in the input file
(`passwordRef`) and its value comes from the environment.

A step carries `id`, `title`, `key` (its natural key template), optional `forEach`
(`groups[*].users[*]`), optional `skipWhen` (one of `exists`, `equals`, `notEquals`, `contains` on
an input path), optional `after` (run an item only when an earlier step reported one of the given
states for the same key), `find` (read bindings), `bindings` (write bindings, in preference order),
`trap` and `source` (the reference file the shapes come from).

## Bindings and the honesty rule

A read binding names a `surface` (`mcp`, `admin-api`, `sql` or `dwapi`), an `operation` and its
`arguments`, `rows` (the member holding the rows; `$` for the response itself), `match` (the
natural-key fields), optionally `compare` (the fields that must equal the input), `expect` (on a
read-back), `produces` (values later steps use, by row path) and, on a probe, `assert`. For rows
that each hold one name and one value (item fields), `compareMap` and `expectMap`
(`{from, key, value}`) compare a whole map name by name: a missing name is a difference, so a
misspelt field shows. A write binding names `create` and/or `update` (`{operation, arguments}`) and a
`readBack` read binding.

**`status: implemented` means the tool or command name and its argument shape are documented in
this repository**, cited in `source`, and its read projection (the `rows` member and the field
names) is measured. Anything else is `status: planned` with a `reason`, and a planned binding never
executes. When a named field is absent the runner fails loudly with "carries no field", never reads
absence as a mismatch: the MCP read models leave out a member whose value is null, and some leave out
a field their output schema declares. A recipe is proven only by a run recorded in `provenOn`.

Allowlists hold the line between data and code. An implemented MCP read must be on `mcpReadTools` (or
`recipeRenderedReadTools`, the rendered-page summary), an
MCP write on `recipeWriteTools`, a Management API write on `recipeAdminCommands`, a delivery read on
the ledger's delivery lists. The runner checks again before every call and refuses an operation off
the list even when the target offers it, and it checks every MCP call's argument names against the
tool's own `tools/list` input schema, because a wrong name answers only "An error occurred invoking".
SQL is read-only: one guarded `SELECT` (the ledger's own guard), local installs only
(`localOnly: true`), values passed as named `@parameters`, run in a transaction that is rolled back.
A recipe never writes through SQL.

## Tokens

String values in arguments, match, compare, expect and parameters may hold tokens:

| Token | Value |
|---|---|
| `{input.<path>}` | The recipe's input section |
| `{item.<path>}`, `{parent.<path>}` | The forEach item and its enclosing item |
| `{step.<id>.<field>}` | A value an earlier step produced for the same natural key |
| `{step.<id>[<path>,<path>].<field>}` | The same for the key built from those paths, joined with `/` |
| `{found.<path>}` | The row the find matched (update arguments only) |
| `{build.areaId}` | `areaId`, `defaultLanguage`, `pimShop` from the ledger build file, else the input's `build` |
| `{secret.<path>}` | The value of the reference key at `<path>` in `DW_RECIPE_SECRETS`; write and read-back arguments only |

A whole-value token keeps its type, so an id stays a number; a token inside text becomes text.
`{text:<token>}` makes a value text, for commands whose ids are strings. `{<token>|<JSON literal>}`
gives a default used only when the path is absent (a user without `passwordRef` gets `null`), never
when a step result is missing: a child page whose parent was not created is never created at the
website root. When the value comes from an object an earlier step reported WOULD-CREATE, a verify run
reports the dependant WOULD-CREATE too ("depends on pages 'About us', which is would-create"); in an
apply run it is BLOCKED.

## Steps: find, apply, read back

Per item, the first eligible find binding reads the target and the rows are matched on the natural
key. Two matches block the item; one match with equal `compare` fields is UNCHANGED; differing fields
are UPDATE; no match is CREATE.

Without `-Apply` nothing is written: the item reports WOULD-CREATE or WOULD-UPDATE and its check
fails with what apply would do. With `-Apply` the first write binding whose write and read-back can
both run here writes, and the write is read back by natural key: a create can answer id 0 and a save
can drop a field, so the response is never the evidence and the id comes from the read-back. An item
with no eligible binding is BLOCKED with the reasons, and the run exits 1.

A step without a find (a url name pin) runs only behind `after`, for the items an earlier step created or updated.

## Debts

Debts run once, after the steps, only with `-Apply` and only when a step changed something. Each is
paid by an existing shipped script or function, never by code from the recipe:

| Debt | Paid by | Without the surface |
|---|---|---|
| `flush:<service>` | `Clear-DwServiceCache` (Management API) | OPEN: no MCP tool refreshes service caches |
| `index:<repository>/<index>` | [Build-DwProductIndex.ps1](../../dw-data-access/scripts/Build-DwProductIndex.ps1), builder from `IndexBuildersByRepositoryAndIndexName`; else MCP `build_product_index` and `wait_for_product_index` with both names, gated on a non-zero `documentCount` from `get_product_index_status`. An index `get_index_repositories` does not list is a NOTE, not owed | OPEN with the build to run |
| `assortments` | [Invoke-DwAssortmentBuild.ps1](../../dw-data-access/scripts/Invoke-DwAssortmentBuild.ps1) over the section's `assortmentIds` | OPEN when none are declared |
| `recycle` | [Restart-DwHost.ps1](../../dw-demo-base/scripts/Restart-DwHost.ps1) for a loopback host given `-SolutionPath` | OPEN with the instruction (a hosted install recycles through its host) |

A debt the run cannot pay is OPEN, so the run exits 1 until it is paid. After paying it, run the
recipe again without `-Apply`: the steps report UNCHANGED and the probes decide.

## Verify: probes and ledger checks

A probe reads through its first eligible binding and asserts `count` (with `op` eq, ge or le),
`equals` or `contains` on the matching rows. Fewer observed subjects than `minimumSubjects` is FAIL,
as in the ledger; a probe whose `forEach` finds no input item to verify is a NOTE. `pollSeconds`
reads a failing subject again until it passes or the time is up, for a state the platform publishes
late or drops for a moment (a new URL answers 404 for seconds). A probe whose
bindings are all planned cannot execute and is a NOTE, never a pass. The persona sign-in probe is the
ledger's own handler, with credentials only from `DW_PERSONA_CREDENTIALS`.

`checkIds` run through [Invoke-DwLedgerChecks.ps1](../scripts/Invoke-DwLedgerChecks.ps1) when
`-LedgerBuildFile` and `-Manifest` are given, under that runner's own rules (a clean checkout at the
lock commit); otherwise each is listed as a NOTE to run with the ledger.

## Modes

| Axis | How a recipe serves it |
|---|---|
| Running mode: skills alone or the `/demo:*` command set | The same file and the same runner; a build plan names the recipe id |
| Local install | All surfaces; SQL reads only with `-AllowSql -SqlServer -Database` |
| Hosted install (URL + API key, no SQL) | MCP and Management API only; `modes.hosted` says whether every step has a non-SQL path |
| Build path A: a layer delivered by the serializer | Run without `-Apply`: every object reports UNCHANGED, the probes verify (`layerDelivered: verify`) |
| Build path B: deserialize, then tools | Run with `-Apply`, then without it after paying the debts |
| The in-product agent (MCP tools only, no shell) | Follow the recipe by hand; `modes.mcpOnly` says whether every step has an implemented MCP find, write and read-back |

The validator computes `mcpOnly` and `hosted` from the bindings and refuses a declaration that
disagrees.

## Following a recipe by hand

An agent with MCP tools only follows the same file:

1. Read the recipe and the input section it names. Confirm each tool a step needs is in `tools/list`
   and take the argument names from its input schema.
2. For each step and each item of its `forEach`, substitute the tokens, call the find tool, and match
   the rows on `match`. Two matches: stop and report the duplicate.
3. Equal `compare` fields: nothing to do. Otherwise call the write the first MCP binding names, then
   call its `readBack` and check `expect`. Keep the `produces` values for later steps.
4. A step with no implemented MCP binding cannot be done in-product: report it with the binding's
   `reason` and name the admin screen; do not substitute another surface.
5. Owe the debts: an MCP index build where one is listed; for a flush or a recycle, report that it is
   owed.
6. Run the probes with MCP bindings and report each result.

## Running a recipe

Find the recipes for a function:

```powershell
pwsh -NoProfile -File scripts/Find-DwRecipe.ps1 -Function users.user-groups
```

Verify only (writes nothing), then apply:

```powershell
pwsh -NoProfile -File scripts/Invoke-DwRecipe.ps1 -Recipe content.pages -InputPath ./recipe-input.json
pwsh -NoProfile -File scripts/Invoke-DwRecipe.ps1 -Recipe content.pages -InputPath ./recipe-input.json -Apply -ReportPath ./recipe-report.json
```

Set `DW_BASE_URL` and `DW_MCP_TOKEN` and/or `DW_API_TOKEN`. `DW_RECIPE_SECRETS` is a JSON object
from the input's reference keys to their values (`{"buyer": "..."}`); `DW_PERSONA_CREDENTIALS` is the
ledger's persona list. `-McpOnly` restricts the run to MCP as the in-product agent would;
`-AllowSql -SqlServer <local> -Database <name>` permits the local SQL reads. No token or secret is
printed or written to the report.

## Output contract

```text
STEP <step> <CREATED|UPDATED|UNCHANGED|BLOCKED|WOULD-CREATE|WOULD-UPDATE> <natural key>
PASS <check>
FAIL <check>: <reason>
OPEN <check>: <reason>
NOTE <subject>: <text>
<recipe id>: <n> of <m> checks passed
```

A check is one step item (`<step>/<key>`), one debt (`debt/<debt>`), one probe (`probe/<id>`) or one
ledger check (`ledger/<id>`). FAIL is an observation that disagrees; OPEN is one that could not be
made. NOTE lines are not checks. The summary is the last line. The exit code is 0 only when every check
passed and nothing is BLOCKED. `-ReportPath` writes the same steps and checks as JSON, with no values.

## Adding or promoting a recipe

1. Write the recipe at `assets/recipes/<area>/<id>.json`; add its input section to the input schema.
2. Cite a reference for every binding. A shape you cannot cite is `planned` with the reason.
3. A new tool or command is an edit to the allowlists in `handlers.json`, reviewed like code.
4. Run `python scripts/validate-skills.py` and the recipe suite (`tests/Recipe.Tests.ps1`).
5. Measure on a host before adding a `provenOn` entry, and record the evidence; never write one
   from a run on another release.
