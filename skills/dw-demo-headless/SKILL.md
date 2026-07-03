---
name: dw-demo-headless
type: flow
group: demo
description: Dynamicweb 10 headless-commerce demos — a Next.js storefront (vercel/commerce starter) driven by the DW10 Delivery API, plus a dedicated presentation-agnostic serialized baseline. Triggers: building a headless/decoupled storefront demo, wiring a Next.js/vercel-commerce frontend to a DW10 backend, "the /dwapi call returns 401 with my admin token", product search returns 400 on POST /dwapi/ecommerce/products, PLP needs a repository+query, product data missing under a language, deserializing a headless baseline, Headless_* item types, running/building the storefront against a self-signed dev host. Non-triggers: server-side Swift storefront -> dw-demo-swift; PIM data modelling -> dw-demo-pim; raw Delivery API endpoint catalog (non-demo) -> dw-headless-delivery; demo setup/MCP/TLS -> dw-demo-base. Use AFTER dw-demo-base (host running, Serializer installed). Headless is its own baseline product line, fully decoupled from Swift.
---

# Dynamicweb Headless Demo Skill

Build a **headless-commerce demo**: a Next.js storefront (from the `vercel/commerce`
starter) that reads a Dynamicweb 10 backend through the **Delivery API** (`/dwapi/**`), backed
by a **dedicated, presentation-agnostic serialized baseline** that is its own product line —
fully decoupled from the Swift baseline. **Use AFTER** `dynamicweb-demo-base` — assumes a host
is running, TLS bypass is wired, and the Serializer is installed in the host (per base's
[`../dw-demo-base/references/serializer-reference.md`](../dw-demo-base/references/serializer-reference.md)
"Installation").

This SKILL.md is pure nav. Headless is a knowledge book, not a recipe — see references for any
specific topic.

## How to run me

This skill holds domain knowledge, not build sequencing. An **orchestrator** owns the phase
order: GSD injects this skill into its agents (via the `agent_skills` block), or the native
`/demo:*` command set invokes it; **standalone**, the skill's own lightweight harness guards its
documented order (gate every step, persist progress to `.demo/<slug>/flow-state.json`). The
orchestrator abstraction (GSD primary, native command set, and the standalone harness) is owned by
[`../dw-demo-base/references/orchestrator.md`](../dw-demo-base/references/orchestrator.md).

## Headless vs Swift — pick the right demo flow

A headless demo and a Swift demo are **separate product lines**, not two skins of one baseline:

- **Swift demo** (`dynamicweb-swift-demo`) — DW renders the storefront server-side with Razor;
  content is presentation-coupled (`Swift-v2_*` paragraph item types carry template/layout/
  colorscheme/icon fields). Loads the `swift-2.3` baseline.
- **Headless demo** (this skill) — a **separate** Next.js app renders the storefront; DW is a pure
  JSON backend behind `/dwapi/**`. Content is presentation-agnostic (`Headless_*` item types carry
  no layout fields). Loads a **separate** `headless/2.3` baseline that shares **no** item-type rows
  with Swift.

Do not port Swift paragraph item types into a headless demo — that reintroduces the presentation
coupling headless exists to avoid. Reuse the commerce/PIM **domain** model (products, groups,
variants, prices, orders, users, facets — all delivered through the Delivery API, never as item
types) and field-type conventions only.

## Step 0 — Stand up the headless demo (every headless demo)

Walk these in order; each reference owns its own verification gate.

1. **Configure and verify the DW10 backend for headless** -> [`references/headless-backend.md`](references/headless-backend.md)
   Confirm the Delivery API (`/dwapi/**`) is reachable, learn the endpoint/auth surface map, and
   clear the **two-token trap** (the admin/Management token 401s on `/dwapi`; the frontend needs a
   JWT from `POST /dwapi/users/authenticate`). Owns the locale gotcha (product data lives under
   `ENU`, not `LANG1` — always pass `LanguageId`+`ShopId`) and the PLP repository/named-query
   requirement (search is `GET /dwapi/ecommerce/products/search?RepositoryName=…&QueryName=…`;
   `POST /dwapi/ecommerce/products` 400s).

2. **Deserialize the headless baseline** -> [`references/headless-baseline.md`](references/headless-baseline.md)
   Stage the disk-overlay `itemtypes/` and `repositories/` **before** host start (DW materializes
   item types and repositories at startup), deserialize the `deploy/` then `seed/` mode trees, and
   run a **Full** index build afterwards. Owns the `Headless_*` item-type layer, the id floor band,
   and EN/NL sibling-area parity.

3. **Wire and run the Next.js storefront** -> [`references/headless-frontend.md`](references/headless-frontend.md)
   Swap the starter's default provider for a DynamicWeb data-layer module, wire the `DW_*` env vars,
   apply the self-signed-TLS dev bypass, and run/build it against the backend. Owns the slug
   conventions (product number = handle; group id = collection handle) and the build-time RSC fetch
   caveat (the starter cannot `next build` without a reachable provider).

## Where to find things

| If you need to... | Read this reference |
|---|---|
| **Configure/verify the DW10 backend for headless** — Delivery API surface map + auth model, the two-token trap, the ENU/ShopId locale gotcha, the PLP repository+query requirement, item-type XML materialization | **references/headless-backend.md** |
| **Deserialize the headless baseline** — `Headless_*` item-type layer, id floor band, EN/NL parity, disk-overlay staging of `itemtypes/`+`repositories/` before host start, Full index build after deserialize | **references/headless-baseline.md** |
| **Work with the Next.js storefront** — provider-module/data-layer swap, `DW_*` env wiring, self-signed-TLS dev bypass, build-time RSC fetch caveat, slug conventions | **references/headless-frontend.md** |
| **The raw Delivery API endpoint catalog** (non-demo reference — content/commerce/users/forms/query families, request/response shapes) | [`../dw-headless-delivery/SKILL.md`](../dw-headless-delivery/SKILL.md) |
| **Build a per-demo product search index** by hand (Lucene `ProductIndexBuilder`, query + facets) | [`../dw-search-indexing/SKILL.md`](../dw-search-indexing/SKILL.md) |

## Inherited from dynamicweb-demo-base

This skill assumes `dynamicweb-demo-base` ran first. Its always-on rules are NOT restated here —
see the owning reference in base for each:

| Rule | Owner |
|------|-------|
| Customer-context read-only contract | [dynamicweb-demo-base/references/customer-context.md](../dw-demo-base/references/customer-context.md) |
| Customisations-ledger preflight | [dynamicweb-demo-base/references/customisations.md](../dw-demo-base/references/customisations.md) |
| Baseline-drift self-diagnosis rule | [dynamicweb-demo-base/SKILL.md "Self-diagnosis rule"](../dw-demo-base/SKILL.md) |

If you find yourself running this skill standalone with no base context, fix that before
continuing — see the description's "Use AFTER" hint. If `dynamicweb-demo-base` is not installed,
install it first — this skill's inherited rules require it.

## Sister skills

- **`dynamicweb-demo-base`** — foundation skill (Use FIRST). Owns all setup + Serializer install +
  customisations + customer-context. Does NOT deserialize a baseline.
- **`dynamicweb-swift-demo`** — the Swift (server-side Razor) storefront line. A headless demo is
  the decoupled peer of a Swift demo, not a variant of it; the two baselines never share item-type
  rows.
- **`dynamicweb-pim-demo`** — PIM modelling from a blank DB. The headless baseline reuses the same
  commerce/PIM domain model PIM builds; pair them when a headless demo needs richer catalog data.
- **`dynamicweb-headless-delivery`** — the raw `/dwapi/` knowledge skill (endpoint catalog, auth,
  architecture rules). This demo skill routes to it for endpoint detail rather than duplicating it.
