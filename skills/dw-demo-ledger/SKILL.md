---
name: dw-demo-ledger
type: flow
group: demo
mcp: optional
dynamo: false
compatibility: Requires PowerShell 7.x and Git
description: 'Select and check a release-pinned DW10 function ledger. Triggers: platform coverage, equivalent MCP/API probes, edition check locks, release capability changes. Use AFTER dw-demo-base.'
---

# Demo functionality ledger

Use the Truvio Commerce (powered by Dynamicweb) functionality ledger to distinguish available functions, build requirements and measured proof. Run after [dw-demo-base](../dw-demo-base/SKILL.md).

## Without MCP

Use discovered Management API queries with equivalent observations. File and delivery reads apply only to claims they can establish. SQL is an optional local-install verification binding. If no equivalent read exists, report UNVERIFIED; never turn a missing probe into a pass. This skill's runner requires PowerShell; MCP transport alone does not remove that prerequisite.

## Workflow

1. Read [the contract](references/contract.md). Select an exact-release snapshot and record its commit, path, digest and explicit check set in the build lock.
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
- [Coverage map schema](assets/coverage.schema.json) and [handler allowlist](assets/handlers.json)
- [Release snapshots](assets/releases/): each directory contains its manifest.

Distribution and Serializer are platform scope. Concrete layer carriage belongs to Distribution; foundational skills never link back into this demo skill.

## Release and layer changes

Follow [the release process](references/release-process.md) for additions/removals and [the layer contract](references/adding-a-layer.md) for Distribution carriage and edition locks. The [PIM breadth profile](assets/profiles/pim-breadth.json) preserves the migrated thresholds.

For [dw 10.29.8] matrix fields, follow [the matrix contract](references/matrix-fields.md): explicit feature facts, declared source cells, exact stored comparisons and a read-only red control. Availability in an older release must come from that release's evidence.

The product edit layout and global field placement follow [the edit-layout contract](references/edit-layout.md): declare `editLayout` before building, limits as binding data.

CPQ checks use [independent scope declarations and read-only observations](references/cpq-observations.md). Loaded runtime evidence and complete domain producers remain prerequisites to readiness.

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [Invoke-DwLedgerChecks.ps1](scripts/Invoke-DwLedgerChecks.ps1) | Reads target; writes local report | Schema/lock verification, discovery, binding selection and evidence |
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
| [Ledger.Core.ps1](scripts/Ledger.Core.ps1) | Definitions only | Schema, digest, safe paths, selection and assertions |
| [Ledger.Transport.ps1](scripts/Ledger.Transport.ps1) | Reads MCP/Admin when called | Discovery and observations using the shared API transport |
| [Ledger.Observations.ps1](scripts/Ledger.Observations.ps1) | Reads collections/local XML when called | Tokens, filtered counts, authenticated API projection and scoped files |
| [Ledger.Sql.ps1](scripts/Ledger.Sql.ps1) | Local SELECT when called | Integrated-authentication reads without display truncation |
| [Ledger.Execute.ps1](scripts/Ledger.Execute.ps1) | Reads selected binding | Fixed handlers; missing implementation fails visibly |
| [Pim.Fields.ps1](scripts/Pim.Fields.ps1) | Local reads when called | Declared attribute checks and token validation |
| [Pim.Queries.ps1](scripts/Pim.Queries.ps1) | Local SQL/files when called | Migrated family/widget checks |
| [Pim.Layout.ps1](scripts/Pim.Layout.ps1) | Local SQL SELECT and in-memory rules | Edit layout aspects and global field fill |
| [Layout.Tests.ps1](scripts/tests/Layout.Tests.ps1) | Isolated fixtures | Green and red controls per edit layout rule |
| [Placement.Tests.ps1](scripts/tests/Placement.Tests.ps1) | Isolated fixtures | Green and red controls for global field placement |
| [Ledger.Tests.ps1](scripts/tests/Ledger.Tests.ps1) | Isolated fixtures | Red controls, selection, missing probes and schema checks |
| [Observations.Tests.ps1](scripts/tests/Observations.Tests.ps1) | Isolated fixtures | Filter, token, XML, path and authenticated-query controls |
| [Corrections.Tests.ps1](scripts/tests/Corrections.Tests.ps1) | Inline SQL fixtures in tempdb (optional local server) | Green and red controls for corrected and newly inventoried checks, refusal fallback |

Run from a clean checkout at the build lock's commit:

```powershell
pwsh -NoProfile -File scripts/Invoke-DwLedgerChecks.ps1 -Manifest $manifest -BuildFile $build -OutFile $report
```

Set DW_BASE_URL and DW_MCP_TOKEN or DW_API_TOKEN in the process environment. No credential belongs in a build declaration. Supply SqlServer explicitly only for a local target. DiagnosticVersionMismatch permits investigation of another baseline or uncommitted runner, but cannot produce aggregate PASS.
