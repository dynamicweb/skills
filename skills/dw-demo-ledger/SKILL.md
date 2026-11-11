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
- [Release snapshots](assets/releases/): each directory contains its manifest.

Distribution and Serializer are platform scope. Concrete layer carriage belongs to Distribution; foundational skills never link back into this demo skill.

## Release and layer changes

Follow [the release process](references/release-process.md) for additions/removals and [the layer contract](references/adding-a-layer.md) for Distribution carriage and edition locks. The [PIM breadth profile](assets/profiles/pim-breadth.json) preserves the migrated thresholds.

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [Invoke-DwLedgerChecks.ps1](scripts/Invoke-DwLedgerChecks.ps1) | Reads target; writes local report | Schema/lock verification, discovery, binding selection and evidence |
| [Compare-DwLedgerRelease.ps1](scripts/Compare-DwLedgerRelease.ps1) | Reads snapshots/evidence; writes proposed delta | Release comparison skeleton; never marks a feature measured |
| [Ledger.Core.ps1](scripts/Ledger.Core.ps1) | Definitions only | Schema, digest, safe paths, selection and assertions |
| [Ledger.Transport.ps1](scripts/Ledger.Transport.ps1) | Reads MCP/Admin when called | Discovery and observations using the shared API transport |
| [Ledger.Sql.ps1](scripts/Ledger.Sql.ps1) | Local SELECT when called | Integrated-authentication reads without display truncation |
| [Ledger.Execute.ps1](scripts/Ledger.Execute.ps1) | Reads selected binding | Fixed handlers; missing implementation fails visibly |
| [Pim.Fields.ps1](scripts/Pim.Fields.ps1) | Local reads when called | Declared attribute checks and token validation |
| [Pim.Queries.ps1](scripts/Pim.Queries.ps1) | Local SQL/files when called | Migrated family/widget checks |
| [Ledger.Tests.ps1](scripts/tests/Ledger.Tests.ps1) | Isolated fixtures | Red controls, selection, missing probes and schema checks |

Run from a clean checkout at the build lock's commit:

```powershell
pwsh -NoProfile -File scripts/Invoke-DwLedgerChecks.ps1 -Manifest $manifest -BuildFile $build -OutFile $report
```

Set DW_BASE_URL and DW_MCP_TOKEN or DW_API_TOKEN in the process environment. No credential belongs in a build declaration. Supply SqlServer explicitly only for a local target. DiagnosticVersionMismatch permits investigation of another baseline or uncommitted runner, but cannot produce aggregate PASS.
