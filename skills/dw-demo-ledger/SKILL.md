---
name: dw-demo-ledger
type: flow
group: demo
mcp: optional
dynamo: false
compatibility: Requires PowerShell 7.x
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
