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
- [A site a layer copy already delivered](#a-site-a-layer-copy-already-delivered)
- [Debts](#debts)
- [Verify: probes and ledger checks](#verify-probes-and-ledger-checks)
- [Modes](#modes)
- [Following a recipe by hand](#following-a-recipe-by-hand)
- [Running a recipe](#running-a-recipe)
- [Running a whole build](#running-a-whole-build)
- [Output contract](#output-contract)
- [Adding or promoting a recipe](#adding-or-promoting-a-recipe)

## Where recipes live

| File | What it is |
|---|---|
| `assets/recipes/<area>/<id>.json` | One recipe; `<id>` is its primary ledger function id, such as `users.accounts` |
| [assets/recipe.schema.json](../assets/recipe.schema.json) | The recipe schema (draft 7) |
| [assets/recipe-input.schema.json](../assets/recipe-input.schema.json) | The customer data file: one section per recipe input section |
| [assets/recipe-input.example.json](../assets/recipe-input.example.json) | A generic example input for both example recipes |
| [assets/handlers.json](../assets/handlers.json) | The allowlists: `recipeWriteTools`, `recipeDeleteTools`, `recipeAdminCommands`, and the read lists the ledger shares |
| [recipe-index.md](recipe-index.md) | Every recipe with its functions, input section, modes, proof, run order and what stays planned; generated, so it cannot drift |

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
| `provenOn` | `{dwVersion, mcpVersion, date, evidence}` per measured run, optionally `modes` proven on that release; empty means unproven |
| `traps` | Platform facts that bite this function, one per line |
| `dependsOn` | Optional: `{recipe, why, debtsPaid}` per recipe whose objects this one needs; a recipe set runs that one first, and pays the named debts of it before this one runs |
| `runsLast` | Optional: why a recipe set runs this recipe after every other one (the de-brand) |
| `respell` | Optional `{step, from, to}`: once that step has run, every input text that starts with `from` in other letter case starts with `to` instead. A folder that already exists as `/Files/Images/Rhino` for an input that says `rhino` keeps its real spelling in every later write, compare and read |

No field holds a host, a URL, a machine path, a credential or a customer name: the repository
validator and the runner both refuse one. A password is named by a reference key in the input file
(`passwordRef`) and its value comes from the environment.

A step carries `id`, `title`, `key` (its natural key template), optional `forEach`
(`groups[*].users[*]`), optional `skipWhen` (one of `exists`, `equals`, `notEquals`, `contains` on
an input path; the compared value may be an input token such as `{input.buyer.account}`; a list of
conditions skips when any holds), optional `repeat: "reuse"` (an item whose key an earlier item of the
step already handled is skipped, for a shared object such as a product several order lines name), optional `after` (run an item only when an earlier step reported one of the given
states for the same key), `find` (read bindings), `bindings` (write bindings, in preference order),
`trap` and `source` (the reference file the shapes come from).

## Bindings and the honesty rule

A read binding names a `surface` (`mcp`, `admin-api`, `sql` or `dwapi`), an `operation` and its
`arguments`, `rows` (the member holding the rows; `$` for the response itself), `match` (the
natural-key fields), optionally `compare` (the fields that must equal the input), `expect` (on a
read-back), `produces` (values later steps use, by row path) and, on a probe, `assert`. For rows
that each hold one name and one value (item fields), `compareMap` and `expectMap`
(`{from, key, value}`) compare a whole map name by name: a missing name is a difference, so a
misspelt field shows. `ignoreCase` lists `match` members compared ignoring letter case (a folder
name the host stores in its own case). `unordered` lists `compare` or `expect` members whose list is compared in
any order, each element as often (a state's next states, which the read lists sorted by id). A write binding names `create` and/or `update`
(`{operation, arguments}`) and a `readBack` read binding. An operation may state `resave` (why one save is
measured not to settle): when the read-back still differs, the runner says so in a NOTE, saves once more and
reads back again, and that second read-back decides.

**`status: implemented` means the tool or command name and its argument shape are documented in
this repository**, cited in `source`, and its read projection (the `rows` member and the field
names) is measured. Anything else is `status: planned` with a `reason`, and a planned binding never
executes. When a named field is absent the runner fails loudly with "carries no field", never reads
absence as a mismatch: the MCP read models leave out a member whose value is null, and some leave out
a field their output schema declares. Two exceptions follow from that omission. A `match`, `compare` or
`expect` member the recipe sets to JSON `null` accepts an absent member (a price tier is found by
stating each scope member null). A row that leaves out a member the natural key gives a value does not
match (a contract row is not a tier); a misspelt key member then matches nothing, and the read-back
after the write fails on it. A recipe is proven only by a run recorded in `provenOn`.

Server releases add tools and members, and some change a read's shape. Bindings run in preference
order and the runner takes the first one the target can serve, so a recipe that binds a newer tool keeps
working on an older server through the binding after it. Where only a member tells the releases apart,
an MCP binding names it in `requiresSchema` (`{"input": ["models[*].countryCodes"]}` for an argument,
`{"output": ["data[*].fields"]}` for a member of the structured result): the binding runs only when the
target's own `tools/list` schema carries every member named, otherwise the runner falls to the next
binding with the reason. The schema decides, never a version number. `mcpSince` (`"0.6.6"`) records the
add-in release a binding is first proven on; the runner ignores it, and the validator counts the binding
only for that release and later (see [Modes](#modes)). Tool names resolve against every supported
registry under `scripts/mcp-tools/` (generated from a `tools/list` capture per release).

Allowlists hold the line between data and code. An implemented MCP read must be on `mcpReadTools` (or
`recipeRenderedReadTools`, the rendered-page summary), an
MCP write on `recipeWriteTools`, an MCP delete on `recipeDeleteTools`, a Management API write on
`recipeAdminCommands`, a delivery read on
the ledger's delivery lists (a `{name}` in a delivery route other than `{areaId}` takes the argument of
that name, which then leaves the query). The runner checks again before every call and refuses an operation off
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
| `{scope}`, `{row.<path>}` | In a prune step: the owner being read, and the row being deleted |
| `{build.areaId}` | `areaId`, `defaultLanguage`, `pimShop` from the ledger build file, else the input's `build` |
| `{secret.<path>}` | The value of the reference key at `<path>` in `DW_RECIPE_SECRETS`; write and read-back arguments only |
| `{base64:<token>}`, `{bytes:<token>}`, `{basename:<token>}` | The content (base64), size or file name of the file the value names, relative to the input file; a rooted path or one outside that folder is refused |

A whole-value token keeps its type, so an id stays a number; a token inside text becomes text.
A `[*]` in a path maps the rest of the path over every element (or every value of an object) and
returns one flat list: `data[*].dataModels[*].dataModels` as a read's `rows` gathers the models of
every folder of every shop, and `fields[*].systemName` in `compare` is a rule's field list. Text
around one list-valued token fans out into a list (`"P|{step.categories.id}|{item.specFields[*].key}"`
is one text per spec field), spliced into an enclosing list; lists compare element by element, in
order.
`{text:<token>}` makes a value text, for commands whose ids are strings. `{<token>|<JSON literal>}`
(or `{<token>|<input path>}`, such as `{step.models[item.parent].name|item.name}`) gives a default used only when the path is absent (a user without `passwordRef` gets `null`), never
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
A step with a `scan` instead of a find finds places, not objects: every row its `binding` reads (all
pages of the response with `page`) whose `field` holds the `text`, ignoring case, is one place named by
its `identify` members (`STEP page-texts WOULD-UPDATE Fabrikam@122/PageField/0/MetaTitle`). Apply
writes each place through the first update binding, whose arguments read the row as `{row.<member>}`
and the text with every occurrence replaced as `{replaced:row.<member>}`; with `batch` one call
carries every place, joined on that list member. Each place is read back and must no longer hold the
text. A scan without write bindings reports each place OPEN with its `unwritable` reason.
A step with a `prune` removes what the input does not name: the reset before a demo. Its `scope.values`
is a token naming, from the input, the owners whose rows may go (the buyer the history names); a scope
that resolves to nothing (no value, an empty text, an empty list or the id 0) refuses the step before any
read. For each scope value the `binding` reads the set, its arguments carrying `{scope}` (a read that does
not pass it is refused), and its `match` selects rows. Every row must carry `scope.member` equal to the
scope value: one row outside the scope refuses the whole item and nothing is deleted, so a read that
ignores its filter cannot widen the delete. A row whose `keep.field` equals one of `keep.values` (the
input's natural keys) stays; a row without the field is unnamed and goes. More than `max` rows refuses
the item. Without `-Apply` each row is `STEP reset WOULD-DELETE buyer@example.invalid@CART7`; with it
each is removed through the first eligible binding that declares `delete` (its operation on
`recipeDeleteTools`, MCP only, its arguments reading the row as `{row.<member>}`) and read back: the
binding's `readBack` must no longer return the row. Nothing to remove is UNCHANGED.
A step with a `retire` sets inactive, and never deletes, what the input does not name: the sample
payment and shipping methods a base delivers beside the brand's own. It runs once per natural key
(items that share the key are one set, so `forEach: methods[*]` keyed `payment` runs once when the
input names at least one payment method). `retire.named` is a token for what the input names in the
set; nothing named refuses the item, so a retire never empties a set. A step in `requires` that
blocked an item refuses it too (a named method found twice has no known id). The `binding` reads the
set; a row whose `active.field` holds `active.value` is active, and an active row is kept when its
member equals a value of any `keep` rule: the input's names, or `{step.<id>[*].<field>}`, every value
an earlier step of this run produced under that name. The rest is the set to retire, each named by
its `identify` members; more than `max` refuses the item. Without `-Apply` each row is
`STEP retire-payment WOULD-RETIRE payment@PAY2/Standard invoice`; with it each is written through the
first eligible `update` binding (arguments read the row as `{row.<member>}`), `STEP retire-payment
RETIRED payment@PAY2/Standard invoice`, and read back: the `readBack` must no longer return the row
active. A NOTE counts what was retired and kept. Setting the row active again restores it.
A step with an empty `bindings` list is a lookup: it finds an object another function owns (the
header page a website selects) and produces values for later steps, and never writes. An absent
object is WOULD-CREATE in a verify run and BLOCKED with apply, so its dependants stop too.

## A site a layer copy already delivered

A demo can start from a rewritten sample-data layer copy that already holds the catalogue, prices,
orders and users of the same customer data file. The copy keys some objects its own way: its spec
fields keep the layer's field ids and categories, its groups their own ids, its images their own
folder, its orders their reference instead of the purchase order number. A recipe recognises that
delivery itself, per object, with no flag:

| Member | Effect |
|---|---|
| `find.delivered` | Read bindings in the copy's shape, read only when the find matched nothing. One matching row or more is the object the copy delivered: `STEP <step> DELIVERED <key>` and a passing check. It is never written; values come from it (`produces`) only when exactly one row matched |
| `deliveredWith` `{step, key}` | The object this item belongs to (`key` defaults to the item's own key). When that object is DELIVERED, an item that would be created or changed is DELIVERED too: a NOTE, not a check, and nothing is written into the layer's object. An item found equal still passes |
| `find.conflict` `{reason, skipWhen, bindings}` | Read only when the find and `find.delivered` matched nothing: an object the input does not own that a create would collide with (another page already answers at the input's path, so a new page would be served at the path with -1). A matching row blocks the item, in a verify run and an apply: `STEP <step> BLOCKED <key>`, an OPEN check with the reason, nothing written |
| `matchSuffix` `{member: text}` | A read matches only rows whose member ends with the text, ignoring case: a file the copy stored under its own folder, found by its file name |

A token that reads a DELIVERED object that produced no value makes its item DELIVERED as well; on a
probe, a failing subject of a delivered object is a NOTE (`n subject(s) a layer delivered in its own
shape`). So on such a site a plain set run reports the copy's objects DELIVERED, writes none of them
a second time, and still builds what the copy lacks (the brand, the pages, the de-brand, the
accounts' passwords and checkout). The copy's own shape is verified by the ledger checks of its
build lock. The shared natural keys: products by number, prices by scope and quantity (a group or
contract price without a quantity at quantity 1), users by user name. What a copy keys its own way
and a recipe cannot read in its own shape (a category that is not a CategoryFields category, an
order reference no MCP write sets) is what `find.delivered` names. MCP-only has no category read, so
it cannot tell a layer's category from a recipe's.

## Debts

Debts run once, after the steps, only with `-Apply` and only when a step changed something. Each is
paid by an existing shipped script or function, never by code from the recipe:

| Debt | Paid by | Without the surface |
|---|---|---|
| `flush:<service>` | `Clear-DwServiceCache` (Management API) | OPEN: no MCP tool refreshes service caches |
| `index:<repository>/<index>` | [Build-DwProductIndex.ps1](../../dw-data-access/scripts/Build-DwProductIndex.ps1), builder from `IndexBuildersByRepositoryAndIndexName`; else MCP `build_product_index` and `wait_for_product_index` with both names, gated on a non-zero `documentCount` from `get_product_index_status`. An index `get_index_repositories` does not list is a NOTE, not owed | OPEN with the build to run |
| `assortments` | [Invoke-DwAssortmentBuild.ps1](../../dw-data-access/scripts/Invoke-DwAssortmentBuild.ps1) over the section's `assortmentIds`; else MCP `build_assortments`, gated on each assortment's `lastBuildDate` moving with no rebuild owed (`get_assortments`) | OPEN when none are declared |
| `recycle` | [Restart-DwHost.ps1](../../dw-demo-base/scripts/Restart-DwHost.ps1) for a loopback host given `-SolutionPath` | OPEN with the instruction: no Management API command or MCP tool recycles the application; Dynamicweb Cloud consumes `Files/System/CloudHosting/recycle.txt`, any other hosted install needs its operator |

A debt the run cannot pay is OPEN, so the run exits 1 until it is paid. After paying it, run the
recipe again without `-Apply`: the steps report UNCHANGED and the probes decide.

`-Debts Defer` leaves the debts of a change to the caller and names them in the report
(`debtsOwed`); `-Debts Only -Apply` runs no step and pays the debts (or `-DebtNames` of them) even
though nothing changed: an index build, an assortment build, a flush or a recycle on its own.
`-SkipVerify` runs no probe and no ledger check. The recipe set uses all three.

## Verify: probes and ledger checks

A probe reads through its first eligible binding and asserts `count` (with `op` eq, ge or le),
`equals`, `contains` or `excludes` (no text of the value, or of a list of texts or `{text}` objects,
ignoring case) on the matching rows. Fewer observed subjects than `minimumSubjects` is FAIL,
as in the ledger; a probe whose `forEach` finds no input item to verify is a NOTE. `pollSeconds`
reads a failing subject again until it passes or the time is up, for a state the platform publishes
late or drops for a moment (a new URL answers 404 for seconds). A probe whose
bindings are all planned cannot execute and is a NOTE, never a pass. The persona sign-in probe is the
ledger's own handler, with credentials only from `DW_PERSONA_CREDENTIALS`.

A delivery read is `dwapi-get` (anonymous, on `dwapiReadRoutes`) or `dwapi-signed-in-get` (on
`recipeSignedInReadRoutes`), which signs in as the `signIn` `{username, password}` the binding names,
the password a `{secret.*}` token, and sends the token for that one read only; neither is kept or
printed. A `{name}` in the route takes the argument of that name (`ecommerce/products/{productId}`);
the other arguments are the query. This is how a recipe proves what a visitor and a signed-in buyer
are served, not only what is stored.

`checkIds` run through [Invoke-DwLedgerChecks.ps1](../scripts/Invoke-DwLedgerChecks.ps1) when
`-LedgerBuildFile` and `-Manifest` are given, under that runner's own rules (a clean checkout at the
lock commit); otherwise each is listed as a NOTE to run with the ledger.

## Modes

| Axis | How a recipe serves it |
|---|---|
| Running mode: skills alone or the `/demo:*` command set | The same file and the same runner; a build plan names the recipe id |
| Local install | All surfaces; SQL reads only with `-AllowSql -SqlServer -Database` |
| Hosted install (URL + API key, no SQL) | MCP and Management API only; `modes.hosted` says whether every step has a non-SQL path |
| Build path A: a layer delivered by the serializer | Run the set as for a blank site: the objects the layer delivered report UNCHANGED or, where it keyed them its own way, DELIVERED, and nothing is written twice ([above](#a-site-a-layer-copy-already-delivered)) |
| Build path B: deserialize, then tools | Run with `-Apply`, then without it after paying the debts |
| The in-product agent (MCP tools only, no shell) | Follow the recipe by hand; `modes.mcpOnly` says whether every step has an implemented MCP find, write and read-back |

The validator computes `mcpOnly` and `hosted` from the bindings and refuses a declaration that
disagrees. `modes` is the conservative truth: it counts only the bindings proven on the oldest MCP
release in `provenOn` (a binding with a later `mcpSince` does not count). A `provenOn` entry may state
`modes: {mcpOnly, hosted}` for its own release, computed the same way with that release's bindings; a
recipe with an `mcpSince` binding must state them on at least one entry. The index lists the modes per
release.

## Following a recipe by hand

An agent with MCP tools only follows the same file; [recipe-by-hand.md](recipe-by-hand.md) walks
one recipe through with the calls it makes:

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

A brand kit's `swift2/` folder (brand-kit-extractor) becomes the `brand` section of the input
without hand work; the converter maps the kit's numeric enums to the names the MCP style tools take
and points every file at `/Files/Images/<assetFolder>`:

```powershell
pwsh -NoProfile -File scripts/ConvertFrom-DwBrandKit.ps1 -KitPath ./brand-kit/acme/swift2 -OutPath ./recipe-input.json -RenderCheck /en-us/home, /en-us/shop
```

Set `DW_BASE_URL` and `DW_MCP_TOKEN` and/or `DW_API_TOKEN`. `DW_RECIPE_SECRETS` is a JSON object
from the input's reference keys to their values (`{"buyer": "..."}`); `DW_PERSONA_CREDENTIALS` is the
ledger's persona list. `-McpOnly` restricts the run to MCP as the in-product agent would;
`-AllowSql -SqlServer <local> -Database <name>` permits the local SQL reads. No token or secret is
printed or written to the report.

## Running a whole build

[Invoke-DwRecipeSet.ps1](../scripts/Invoke-DwRecipeSet.ps1) runs every recipe the customer data
file has a section for, in the order [recipe-index.md](recipe-index.md) prints (each recipe's
`dependsOn` first, ties by id, `runsLast` at the end). Same contract as one recipe: without
`-Apply` it writes nothing and runs each recipe once, verify-only.

```powershell
pwsh -NoProfile -File scripts/Invoke-DwRecipeSet.ps1 -InputPath ./recipe-input.json
pwsh -NoProfile -File scripts/Invoke-DwRecipeSet.ps1 -InputPath ./recipe-input.json -Apply -ReportPath ./recipe-set-report.json
```

With `-Apply` it runs three passes:

1. **Apply** every recipe in order with its debts deferred and no probes. A debt a later recipe
   names in `dependsOn.debtsPaid` is paid just before that recipe.
2. **Pay the debts once.** Owed debts are deduplicated across recipes (two recipes that owe the
   same index build get one build, two that owe a recycle get one) and paid in the order
   assortments, flushes, index builds, recycle, each through the recipe that owes it.
3. **Verify** every recipe without `-Apply`: the steps report UNCHANGED and the probes decide.

Paying at the end is safe for the recipes shipped today: no recipe's steps read what another
recipe's debt refreshes. Prices, orders and workflows find products, users, groups and models by
number or name through reads that do not go through an index or a cache a debt flushes; only the
probes do (the storefront group list reads the product index, a buyer's sign-in and the
impersonation list read the user service), and the probes run in pass 3. It is also the faster and
the more correct order: the product index built once after the prices recipe carries the prices the
storefront list needs, where a build after the catalogue would be built again. So no recipe declares
`debtsPaid` yet; one that adds a step reading an index or a cached list another recipe changes must.

| Option | Effect |
|---|---|
| `-Only <ids>` / `-Skip <ids>` | Run only, or leave out, these recipes. A dependency left out is a NOTE: its objects must already be on the site |
| `-PayDebts` | With `-Apply`, pay every debt of the selected recipes in pass 2 even when nothing changed: the host primitives (index build, assortment build, flush, recycle) on their own, `-Only pim.identifiers -PayDebts -Apply` |
| `-LayerDelivered <sections>` | Sections a layer already delivered: their recipes run verify-only in pass 1 even with `-Apply` (unless the recipe declares `layerDelivered: apply`). Not needed to avoid a second copy (each recipe recognises a delivery itself); use it to leave a delivered section untouched altogether, such as an MCP-only run that cannot read a layer's categories |
| `-McpOnly`, `-AllowSql -SqlServer -Database`, `-SolutionPath`, `-LedgerBuildFile -Manifest`, connection | Passed to every recipe run, as for one recipe |

Before anything runs, the set refuses a de-brand whose forbidden text another section of the
input holds: the build would write it, the de-brand replace it, and the next apply write it back.
Each recipe's own lines print under `== <recipe> <pass>`; then one summary table (steps of the
apply pass as C created, U updated, = unchanged, B blocked, WC/WU would create/update, D delivered by a layer; checks of
the last pass; debts owed), one `DEBT <result> <debt> (<owner>, <when>)` line per debt paid, and
last `recipe set: <n> of <m> recipes passed`. Exit 0 only when every selected recipe passed every
pass and every debt was paid. A recipe that needs a recycle on a host the run cannot recycle leaves
`DEBT OPEN recycle`: recycle it, then run the set again without `-Apply`.

## Output contract

```text
STEP <step> <CREATED|UPDATED|DELETED|RETIRED|UNCHANGED|DELIVERED|BLOCKED|WOULD-CREATE|WOULD-UPDATE|WOULD-DELETE|WOULD-RETIRE> <natural key>
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
