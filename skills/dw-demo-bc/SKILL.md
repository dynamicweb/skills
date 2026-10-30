---
name: dw-demo-bc
type: flow
group: demo
mcp: required
dynamo: false
compatibility: Requires Python 3.12+ for the local mock fixture and PowerShell 7.x for live BC probes
description: 'Stage a DW10 BC demo with isolated companies, a labelled mock, sync rehearsal and reset. Triggers: BC sandbox demo, ERP ownership story, reproducible BC seed or replay. Use AFTER dw-demo-base. Build jobs -> dw-integration-bc.'
---

# Business Central demo

## MCP preflight

Verify the Dynamicweb MCP tool set before modifying the Truvio Commerce (powered by
Dynamicweb) demo. If unavailable, name the next rung in
[`dw-data-access`](../dw-data-access/SKILL.md), the Management API followed by the serializer,
and the operator screen where neither reaches a step. Local fixture generation can run
offline; it does not establish a live ERP connection.

Use AFTER [`dw-demo-base`](../dw-demo-base/SKILL.md). Inherit its customer-context read-only
contract, customisations ledger, host/version controls and evidence gates. Keep per-demo
artifacts outside `customer-context/` and outside the installed skills.

## Canonical flow

| Phase | Result | Reference |
|---|---|---|
| Access | Owner selects a sandbox; capture environment type and allowed company GUIDs | [references/sandbox-and-company.md](references/sandbox-and-company.md) |
| Profile | Storyline, ERP ownership, company/location map and acceptance rows | [references/demo-profile.md](references/demo-profile.md) |
| Rehearse | Explicit mock fixture, real Integration Framework activities, staged sync | [references/staged-sync.md](references/staged-sync.md) |
| Connect | Actual ERP endpoints replace mock inputs; repeat acceptance in live mode | [`dw-integration-bc`](../dw-integration-bc/SKILL.md) |
| Reset | Restore only demo-owned inputs and verify a second identical rehearsal | [references/reset-and-isolation.md](references/reset-and-isolation.md) |
| Optional PIM | BC-initiated enrichment sync, separate from ERP jobs | [references/bc-side-config.md](references/bc-side-config.md) |

Use discovery outputs from [`dw-integration-bc-discovery`](../dw-integration-bc-discovery/SKILL.md).
With no authorised sandbox, finish the mock rehearsal and label it **mock** everywhere.
Live acceptance remains pending. A tenant-admin role is not the owner's choice of sandbox.

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [bc_demo_fixture.py](scripts/bc_demo_fixture.py) | Writes a local fixture only with `--apply` | Deterministic baseline/change/reset fixture for two companies; no ERP or Commerce writes |

Run from this skill directory:

```powershell
python scripts/bc_demo_fixture.py --out <demo-integration-dir> --phase baseline
python scripts/bc_demo_fixture.py --out <demo-integration-dir> --phase baseline --apply
python scripts/bc_demo_fixture.py --out <demo-integration-dir> --phase changed --apply
python scripts/bc_demo_fixture.py --out <demo-integration-dir> --phase reset --apply
```

## Optional PIM connector references

These preserve the existing connector troubleshooting recipes. Use the current integration
skill for the ERP side. Copy actual app names and versions from AppStore and the installed
BC extension; historical snippets are not an instruction to install a remembered version.

| Need | Reference |
|---|---|
| Connector calls, dispatch convention and defaults | [references/bc-connector-surface.md](references/bc-connector-surface.md) |
| Which call occurs during sync | [references/connector-endpoints.md](references/connector-endpoints.md) |
| Fix repository, build and workflow settings | [references/dynamicweb-connector-settings.md](references/dynamicweb-connector-settings.md) |
| Public HTTPS for a locally hosted PIM | [references/tunnel.md](references/tunnel.md) |
| Forwarded headers, when required by the host topology | [references/forwarded-headers.md](references/forwarded-headers.md) |
| Product-page deep links | [references/static-link-manager.md](references/static-link-manager.md) |

A scheduled import, an index build, and a rendered buyer view are separate checks. Freeze
windows and active-session leases apply before any host, app, template or data change.
