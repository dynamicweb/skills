---
name: dw-demo-hosted
type: flow
group: demo
description: 'Build or publish a Dynamicweb 10 demo on a vendor-hosted/cloud install reached only by URL + Admin API bearer key — no scaffold, no SQL, no filesystem. Triggers: the engagement hands over a site URL and a `CLAUDE.<hex>` key instead of a machine; "build on the cloud install"; "publish this site"; "push the demo to the hosted install"; "migrate local to hosted"; a Management API write that returns ok but changes nothing; CloudHosting control files (recycle/restart/changeversion). Use AFTER dw-demo-base — it owns the guardrails, the versions prompt, and the surface-priority rule this skill inherits. Non-triggers: a local scaffold on the demo machine -> dw-demo-base; Swift content and templates -> dw-demo-swift.'
---

# Hosted (cloud) demo installs

A hosted install is handed over as a **URL + an Admin API bearer key**. There is no machine to
scaffold on, no SQL floor, and no filesystem — so the canonical demo-base flow forks here.

**Use AFTER [`dw-demo-base`](../dw-demo-base/SKILL.md).** That skill owns the always-on
guardrails (customisations ledger, read-only `customer-context/`, demo philosophy,
discover-from-project-files), the versions prompt, and the surface-priority rule. All of them
apply unchanged on a hosted install; this skill owns only the deltas.

## Two paths, and they are not the same job

| You are... | Read | Why it is separate |
|---|---|---|
| **Building** a demo directly on a hosted install | [references/online-mode.md](references/online-mode.md) | Which canonical steps to skip, the session-start probe, the Management API recipe pack that substitutes for the MCP/SQL recipes, upload mechanics, the flush-then-restart ladder, shared-install discipline |
| **Publishing** an existing local demo onto a hosted install | [references/publish-to-hosted.md](references/publish-to-hosted.md) | A migration across three transports, not a deploy — pre-flight, transport map, clean-room deserialize, id collisions on an install that already has content, what never rides a content export, index rebuild |

Publishing assumes the build reference: the probe, the recipe pack, and the flush ladder apply to
both. Scope a publish honestly with the user before starting — it is a migration, not a button.

## Probe first — tool availability is version-dependent

Hosted installs differ in what they expose. **MCP may or may not be present**, so open the session
with the probe in [references/online-mode.md](references/online-mode.md) "Probe order at session
start" and let the result decide the surface, rather than assuming either way.

## The surface priority collapses

`dw-demo-base` "Surface priority for CREATES" still governs, with two hosted-specific changes:

- **There is no scaffold phase** — credentials are handed over, so the bootstrap one-clicks that
  make the admin UI an action surface locally do not exist here.
- **Surface 3 does not exist. No SQL, ever.** The ladder is MCP-if-present → Management API → ask
  the user for the rare operation neither exposes. The API recipes that replace the SQL rungs are
  in [references/online-mode.md](references/online-mode.md).

## Verify by round-trip, not by status code

The defining hazard of hosted installs is the **lying success**: a Management API write returns
`ok` while a host ACL silently drops it, an upload reports success without changing the file, an
index build reads a cached relation set and no-ops. Assert the read-back, not the response code —
the catalogue of known cases and their verification recipes lives in
[references/online-mode.md](references/online-mode.md).

## Shared installs

A hosted install is frequently shared with the customer or a partner. Announce destructive
operations, keep the demo's writes scoped to its own areas, and record what was changed in
`CUSTOMISATIONS.md` — on a shared install that ledger is the only record anyone else has.
