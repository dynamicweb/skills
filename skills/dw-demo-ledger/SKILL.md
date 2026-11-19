---
name: dw-demo-ledger
type: flow
group: demo
mcp: optional
dynamo: false
compatibility: Requires PowerShell 7.x and Git
description: 'Build a DW10 demo from one customer data file with replayable recipes, and select and check a release-pinned function ledger. Triggers: run the recipes, recipe for a function, platform coverage, equivalent MCP/API probes, edition check locks, release capability changes. Use AFTER dw-demo-base.'
---

# Demo functionality ledger

Use the Truvio Commerce (powered by Dynamicweb) functionality ledger to distinguish available functions, build requirements and measured proof. Run after [dw-demo-base](../dw-demo-base/SKILL.md).

## Without MCP

Use discovered Management API queries with equivalent observations. File and delivery reads apply only to claims they can establish. SQL is an optional local-install verification binding. If no equivalent read exists, report UNVERIFIED; never turn a missing probe into a pass. This skill's runner requires PowerShell; MCP transport alone does not remove that prerequisite.

## Workflow

1. Read [the contract](references/contract.md). Select an exact-release snapshot and record its commit, path, digest and explicit check set in the build lock. `lock.manifest` is the path from the skills repository root (`skills/dw-demo-ledger/assets/releases/<release>/manifest.json`), and `lock.checkIds` takes check ids from the probes that `functions/<area>.json` lists; the contract shows an example lock.
2. Declare functions and scope before building. Keep breadth expectations in a named profile, separate from platform facts.
3. Discover target surfaces and grants. Prefer MCP, then Management API, using only implemented bindings with the required observation semantics.
4. Run the read-only checks. A failed valid observation stays FAIL; another surface must not be used to shop for a passing answer.
5. Retain the report with the build evidence. Unknown compatibility and missing bindings prevent a readiness claim.

The initial snapshot is a candidate until measured on its exact baseline. A diagnostic run on another release is useful evidence about that host, not proof of baseline compatibility. Functions without executable coverage stay visible.

## Assets

- [Function-area schema](assets/ledger.schema.json)
- [Check schema](assets/check.schema.json)
- [Build and lock schema](assets/build.schema.json)
- [Report schema](assets/report.schema.json)
- [Target capabilities schema](assets/target-capabilities.schema.json)
- [Coverage map schema](assets/coverage.schema.json) and [handler and read-tool allowlists](assets/handlers.json)
- [Release snapshots](assets/releases/): each directory contains its manifest.
- [Recipe schema](assets/recipe.schema.json), [recipe input schema](assets/recipe-input.schema.json), [example input](assets/recipe-input.example.json) and [recipes](assets/recipes/)

Distribution and Serializer are platform scope. Concrete layer carriage belongs to Distribution; foundational skills never link back into this demo skill.

## Release and layer changes

Follow [the release process](references/release-process.md) for additions/removals and [the layer contract](references/adding-a-layer.md) for Distribution carriage and edition locks. The [PIM breadth profile](assets/profiles/pim-breadth.json) preserves the migrated thresholds.

For [dw 10.29.8] matrix fields, follow [the matrix contract](references/matrix-fields.md): explicit feature facts, declared source cells, exact stored comparisons and a read-only red control. Availability in an older release must come from that release's evidence.

The product edit layout and global field placement follow [the edit-layout contract](references/edit-layout.md): declare `editLayout` before building, limits as binding data.

CPQ checks use [independent scope declarations and read-only observations](references/cpq-observations.md). Loaded runtime evidence and complete domain producers remain prerequisites to readiness.

## Recipes

A recipe is the replayable form of one ledger function: ordered steps found by natural key, the debts they owe (flush, index build, assortments, recycle) and how to verify them. It is data first, so an agent with MCP tools only can follow it by hand, and [Invoke-DwRecipe.ps1](scripts/Invoke-DwRecipe.ps1) runs the same file. Read [the recipe contract](references/recipes.md) before writing or running one. Recipes live under `assets/recipes/<area>/`, outside the release snapshots, and an empty `provenOn` means unproven. Look for one before building a function by hand:

```powershell
pwsh -NoProfile -File scripts/Find-DwRecipe.ps1 -Function users.accounts
```

Without `-Apply` a recipe writes nothing: on build path A, where a layer delivered the data, every object reports UNCHANGED and the probes verify it. With `-Apply` it creates and updates, reads every write back and pays its debts. Each recipe states whether it is usable MCP-only and on a hosted install; a step with no eligible binding is BLOCKED, never skipped.

A whole build is one command over one customer data file: [Invoke-DwRecipeSet.ps1](scripts/Invoke-DwRecipeSet.ps1) runs every recipe the file has a section for, dependencies first, pays the debts once and verifies everything ([recipes.md](references/recipes.md) "Running a whole build"). `-Only pim.identifiers -PayDebts -Apply` runs the host primitives alone (index build, assortment build, flush, recycle). The [recipe index](references/recipe-index.md) lists every recipe, its input section, modes, proof, run order and what stays planned; an agent with MCP tools only follows a recipe by hand with [recipe-by-hand.md](references/recipe-by-hand.md).

```powershell
pwsh -NoProfile -File scripts/Invoke-DwRecipeSet.ps1 -InputPath ./recipe-input.json -Apply
```

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [Invoke-DwLedgerChecks.ps1](scripts/Invoke-DwLedgerChecks.ps1) | Reads target; writes local report | Schema/lock verification, discovery, binding selection and evidence |
| [Update-DwLedgerLock.ps1](scripts/Update-DwLedgerLock.ps1) | Reads build file and snapshot; writes a new build file | Re-lock report after a snapshot revision: removed checks and functions, grounds that are gone, new checks |
| [Compare-DwLedgerRelease.ps1](scripts/Compare-DwLedgerRelease.ps1) | Reads snapshots/evidence; writes proposed delta | Release comparison skeleton; never marks a feature measured |
| [Find-DwReleaseFunctions.ps1](scripts/Find-DwReleaseFunctions.ps1) | Reads releases/schema; writes raw scan | General package, flag, schema and changelog discovery before review |
| [Release.Metadata.ps1](scripts/Release.Metadata.ps1) | Reads assembly metadata bytes | Public types, enum constants and feature ancestry without target execution |
| [Release.Evidence.ps1](scripts/Release.Evidence.ps1) | Reads public packages/local schema; writes cache | Version-checked evidence collection |
| [Release.Compare.ps1](scripts/Release.Compare.ps1) | Reads captured evidence | General candidate comparison without feature keywords |
| [Release.Tests.ps1](scripts/tests/Release.Tests.ps1) | Isolated fixtures | Synthetic A/B discovery and missing-evidence red controls |
| [Pim.Matrix.ps1](scripts/Pim.Matrix.ps1) | Local SQL SELECT and in-memory comparisons | Matrix category, parent and exact cell observations |
| [Matrix.Tests.ps1](scripts/tests/Matrix.Tests.ps1) | Isolated fixtures | Green/red matrix controls and incomplete capability evidence |
| [Cpq.Read.ps1](scripts/Cpq.Read.ps1) | Local SELECT | Version-scoped CPQ rows in one read transaction |
| [Cpq.Json.ps1](scripts/Cpq.Json.ps1) | Definitions only | Strict JSON, tuple dialect and references |
| [Cpq.Observations.ps1](scripts/Cpq.Observations.ps1) | In-memory comparisons | Independent stored/configured CPQ assertions |
| [Cpq.Receipts.ps1](scripts/Cpq.Receipts.ps1) | Validated receipt data | Distribution trust boundary and independent price/BOM red checks |
| [tests/Cpq.Tests.ps1](scripts/tests/Cpq.Tests.ps1) | Isolated fixtures | CPQ positive and negative controls |
| [tests/Receipts.Tests.ps1](scripts/tests/Receipts.Tests.ps1) | Producer-shaped fixtures; a Distribution checkout through `CPQ_DISTRIBUTION_ROOT` | Receipt reader verdicts, wrong price and BOM red controls |
| [Invoke-DwRecipe.ps1](scripts/Invoke-DwRecipe.ps1) | Reads target; with -Apply writes the recipe's objects and pays its debts | Runs one recipe: find, apply, read back, debts, probes, ledger checks |
| [Invoke-DwRecipeSet.ps1](scripts/Invoke-DwRecipeSet.ps1) | Reads target; with -Apply writes every selected recipe's objects and pays the debts once | A whole build from one input file: select, order, apply, pay, verify, one summary |
| [Find-DwRecipe.ps1](scripts/Find-DwRecipe.ps1) | Reads recipes | Recipes for a function or area, their modes and proven state |
| [Recipe.Core.ps1](scripts/Recipe.Core.ps1) | Definitions only | Paths, tokens, natural-key matching and binding selection |
| [Recipe.Transport.ps1](scripts/Recipe.Transport.ps1) | Reads target when called | Allowlisted MCP, Management API, delivery and guarded local SQL reads |
| [Recipe.Write.ps1](scripts/Recipe.Write.ps1) | Writes when called with -Apply | One allowlisted MCP or Management API write |
| [Recipe.Steps.ps1](scripts/Recipe.Steps.ps1) | Writes through Recipe.Write.ps1 | Step engine and the STEP and check lines |
| [Recipe.Scan.ps1](scripts/Recipe.Scan.ps1) | Writes through Recipe.Write.ps1 | Scan steps: every place a text shows, replaced or reported |
| [Recipe.Prune.ps1](scripts/Recipe.Prune.ps1) | Deletes through Recipe.Write.ps1 | Prune steps: the rows of the owners the input names that the input does not name, removed (a demo reset) |
| [ConvertFrom-DwBrandKit.ps1](scripts/ConvertFrom-DwBrandKit.ps1) | Writes one local input file | A brand kit's swift2 folder as the input's brand section |
| [Recipe.Verify.ps1](scripts/Recipe.Verify.ps1) | Reads target when called | Probes and the ledger check bridge |
| [Recipe.Debts.ps1](scripts/Recipe.Debts.ps1) | Writes when called | Flush, index build, assortment build and recycle through shipped scripts |
| [Ledger.Core.ps1](scripts/Ledger.Core.ps1) | Definitions only | Schema, digest, safe paths, selection and assertions |
| [Ledger.Transport.ps1](scripts/Ledger.Transport.ps1) | Reads MCP/Admin when called | Discovery and observations using the shared API transport |
| [Ledger.Observations.ps1](scripts/Ledger.Observations.ps1) | Reads collections/local XML when called | Tokens, filtered counts, authenticated API projection and scoped files |
| [Ledger.Repositories.ps1](scripts/Ledger.Repositories.ps1) | Reads repository XML under the local Files root when called | Facet field Analyzed flags through query and index, and macro-shaped query constants |
| [Ledger.Sql.ps1](scripts/Ledger.Sql.ps1) | Local SELECT when called | Single-SELECT guard and integrated-authentication reads in a rolled-back transaction |
| [Ledger.Execute.ps1](scripts/Ledger.Execute.ps1) | Reads selected binding | Fixed handlers; missing implementation fails visibly |
| [Ledger.Facts.ps1](scripts/Ledger.Facts.ps1) | Reads add-in folder names and settings layers when called | App and settings facts for the requested functions' requirements |
| [Ledger.Run.ps1](scripts/Ledger.Run.ps1) | Definitions only | Ruling, then requirements, then observation; functions named by a requirement or a ground |
| [Pim.Fields.ps1](scripts/Pim.Fields.ps1) | Local reads when called | Declared attribute checks and token validation |
| [Pim.Queries.ps1](scripts/Pim.Queries.ps1) | Local SQL/files when called | Migrated family/widget checks |
| [Pim.Layout.ps1](scripts/Pim.Layout.ps1) | Local SQL SELECT and in-memory rules | Edit layout aspects and global field fill |
| [Layout.Tests.ps1](scripts/tests/Layout.Tests.ps1) | Isolated fixtures | Green and red controls per edit layout rule |
| [Placement.Tests.ps1](scripts/tests/Placement.Tests.ps1) | Isolated fixtures | Green and red controls for global field placement |
| [Ledger.Tests.ps1](scripts/tests/Ledger.Tests.ps1) | Isolated fixtures | Red controls, selection, missing probes and schema checks |
| [Observations.Tests.ps1](scripts/tests/Observations.Tests.ps1) | Isolated fixtures | Filter, token, XML, path and authenticated-query controls |
| [Integrity.Tests.ps1](scripts/tests/Integrity.Tests.ps1) | Isolated fixtures, fake connection, mocked MCP | Red controls for the SQL guard, read-tool allowlist, profiles, rulings, requirements and runner errors |
| [Requirements.Tests.ps1](scripts/tests/Requirements.Tests.ps1) | Isolated fixtures, mocked reads | Red controls for requirement facts, evaluation order, cited functions, digest and the delivery read |
| [Handlers.Tests.ps1](scripts/tests/Handlers.Tests.ps1) | Isolated fixtures, mocked delivery reads | Green and red controls for the facet, query-constant, persona sign-in and rendered-value handlers, including the facet check's build-repositories scope, a ruled field that still prints the source unit, and no secret in a row |
| [Runner.Tests.ps1](scripts/tests/Runner.Tests.ps1) | Temporary git checkout, loopback stub | End-to-end runner and re-lock controls: PASS, DISABLED, changed runner, version change, stopped run |
| [LedgerFixture.ps1](scripts/tests/LedgerFixture.ps1) | Writes a temporary fixture checkout | Fixture repository and stub site for the end-to-end controls |
| [Corrections.Tests.ps1](scripts/tests/Corrections.Tests.ps1) | Inline SQL fixtures in tempdb (optional local server) | Green and red controls for corrected and newly inventoried checks, refusal fallback |

Run from a clean checkout at the build lock's commit:

```powershell
pwsh -NoProfile -File scripts/Invoke-DwLedgerChecks.ps1 -Manifest $manifest -BuildFile $build -OutFile $report
```

Set DW_BASE_URL and DW_MCP_TOKEN or DW_API_TOKEN in the process environment. A persona sign-in check reads DW_PERSONA_CREDENTIALS from the environment ([contract](references/contract.md)). No credential belongs in a build declaration. Supply SqlServer explicitly only for a local target. DiagnosticVersionMismatch permits investigation of another baseline or uncommitted runner, but cannot produce aggregate PASS. A run that stops before any check still writes the report: `result` is ERROR and `errors` names the cause. After a snapshot revision an existing build keeps its lock commit; move it with [Update-DwLedgerLock.ps1](scripts/Update-DwLedgerLock.ps1) as the release process describes.
