# Surface priority — scaffold vs build, by instance type

The always-on summary (surface table + pattern) lives in `SKILL.md` "Surface priority for CREATES". This reference is the canonical statement of the surface contract: which surfaces exist on each instance type, which of them are action surfaces in each phase, plus the long-form anti-pattern detail on why SQL-cloning structural trees fails. The *platform mechanism* underneath the discipline — why an MCP create triggers all the domain-service bookkeeping (ItemRelation cloning, ItemList propagation, cache/index refresh) that raw SQL misses, and why the admin UI is a SPA over `/admin/api/...` rather than a separate surface — is owned by [`foundational/extend-mcp-tools.md`](foundational/extend-mcp-tools.md) §5.

## Contents

- [Two phases, one gate](#two-phases-one-gate)
- [Surfaces by instance type](#surfaces-by-instance-type)
- [Build phase — the strict rule](#build-phase--the-strict-rule)
- [Scaffold phase (local) — the bootstrap one-clicks](#scaffold-phase-local--the-bootstrap-one-clicks)
- [Admin UI is verification-only during the build](#admin-ui-is-verification-only-during-the-build)
- [Anti-pattern: SQL-cloning structural trees](#anti-pattern-sql-cloning-structural-trees)
- [Silent no-ops on UPDATE surfaces — verify by round-trip, not by status code](#silent-no-ops-on-update-surfaces--verify-by-round-trip-not-by-status-code)

## Two phases, one gate

A demo engagement has two phases with different surface rules, split by the **MCP verification gate** (`mcp-setup.md` Step 4: `claude mcp list` shows `Connected` AND `ToolSearch +dynamicweb` returns > 200 tools):

- **Scaffold phase** (local installs, before the gate passes): the build surfaces don't exist yet — creating them is the point of the phase. The admin UI driven via the Browser MCP (Playwright) **is an action surface** here, scoped to the bootstrap one-clicks listed below. Work every automated route before involving the user.
- **Build phase** (after the gate — and hosted/headless installs from the first request, since credentials are handed over and there is nothing to scaffold): **strict**. Every change lands on **MCP, the Admin API, or (local only) direct SQL**. The admin UI is verification-only.

## Surfaces by instance type

| Surface | Local install | Hosted (cloud) | Headless |
|---|---|---|---|
| **MCP** (`dynamicweb-commerce-mcp`) | Action surface 1 | Probe first — version-dependent; action surface 1 when present | Probe first; action surface 1 when present |
| **Admin/Management API** (`/admin/api/...`) | Action surface 2 | Action surface 2 (primary when MCP is absent) | Action surface 2 (primary when MCP is absent) |
| **Direct SQL** (`sqlcmd`) | Action surface 3 — last resort, sanctioned cases only | **Does not exist** | **Does not exist** |
| **Admin UI via Playwright** | Scaffold phase: action surface for the bootstrap one-clicks. Build phase: **verification only** | Verification only (needs interactive credentials) | Not reachable |
| **Ask the user** | Scaffold phase: last resort when no automated surface can reach the operation | Last resort for an operation neither MCP nor the API exposes (there is no SQL floor) | Same as hosted |

## Build phase — the strict rule

| Surface | Use for | Why |
|---------|---------|-----|
| 1. **MCP (`dynamicweb-commerce-mcp`)** | **Default — try this first for anything that creates a structural row** (pages, paragraphs, areas, products, groups, orders, users, etc.) | Calls DW's domain services. Triggers ALL the bookkeeping a UI click would: ItemRelation cloning, ItemList propagation, sibling-page linking, cache invalidation, index refresh, child-row creation, validation. ~260 tools. |
| 2. **Management API** (`/admin/api/...`) | Fallback when MCP doesn't expose the operation. Usually admin-grade actions: `BuildIndex`, `CacheInformationRefresh`, `FeatureManagementToggle`, anything in `/admin/api/docs/`. | Same DW domain services as MCP, just a different transport. |
| 3. **Direct SQL** (`sqlcmd ...`, local installs only) | **LAST RESORT** — only for: (a) cleanup/teardown, (b) bulk schema-drift fixes, (c) reading data, (d) cases where you've confirmed both higher surfaces don't support the operation and a vendor patch is the only alternative. | Bypasses every DW service. Misses bookkeeping. Creates orphans. Corrupts caches. **You will not figure out the full bookkeeping for a non-trivial create via SQL — DW does too much per service call.** |

Pattern to follow:

1. Try MCP. If the tool name suggests it (e.g. `copy_area`, `copy_page`, `save_pages`), use it.
2. If MCP errors or doesn't expose the operation, work the Management API. The operation exists there — the admin UI is a SPA over `/admin/api/...`, so every UI click has an endpoint. Discover it via the `/admin/api/docs/` catalogue, a local clone of the DW10 source for binder shapes (see `online-mode.md` "dw10source as binder disambiguator"), or by navigating the admin UI **read-only** with Playwright and reading the SPA's traffic (`mcp__playwright__browser_network_requests`) — reading network calls is verification-grade; clicking Save is not.
3. Local installs only: after 1–2 are exhausted, reach for SQL — and even then, prefer SQL for cleanup of a previous bad attempt rather than for the create.

Driving the admin UI to *make* a build-phase change is off-contract on every instance type. A "UI-only" operation means the endpoint hasn't been found yet — go back to step 2.

This rule is owned by `dynamicweb-demo-base` and inherited by every sister skill.

## Scaffold phase (local) — the bootstrap one-clicks

Until the Backend MCP exists there is nothing at surface 1, and until a bearer exists there is nothing at surface 2 — so the scaffold phase sanctions the admin UI via the Browser MCP as an action surface for exactly these operations:

- **Create the MCP configuration and capture the shown-once API key** (`mcp-setup.md` Step 3).
- **Create the Management API key** (`mcp-setup.md` Step 6).
- **AppStore install of the Backend MCP AddIn** when the csproj `PackageReference` route is closed (`foundational/extend-mcp-tools.md` §1 — `PackageReference` stays the default).
- **Portal downloads** the install scripts can't fetch.

The scaffold ladder: script / CLI / filesystem → Admin API (when a bearer already exists) → **admin UI via the Browser MCP** → headless code recipe (`foundational/extend-mcp-tools.md` §4) → ask the user. Involve the user only when every automated surface is genuinely unreachable — e.g. the Browser MCP tools haven't surfaced in this session yet (they appear in a fresh session; one Claude Code restart loads them) and no API token exists.

Install the Browser MCP **first** in the scaffold sequence (`browser-automation.md`) — it is machine-level and idempotent, and it is the surface the other bootstrap steps drive.

The scaffold phase ends when the MCP verification gate passes; from that point the build-phase rule above applies without exception.

## Admin UI is verification-only during the build

The admin UI is a SPA client of the Admin API — every click it makes lands on `/admin/api/...`. Two consequences:

- **No operation exists only in the UI.** When neither MCP nor the documented Management API seems to cover something, the endpoint exists anyway. Find it via `/admin/api/docs/`, the `dw10source` command classes, or read-only Playwright network watching (`mcp__playwright__browser_network_requests`) — then call the endpoint directly as surface 2.
- **Driving the admin SPA via Playwright to *make* a build-phase change is the worst of both worlds** — fragile selectors wrapped around the same service call you could have made directly, with no machine-readable response to verify against. Playwright's job during the build is verification: navigate, screenshot, DOM-grep to confirm a change landed (see `references/browser-automation.md`).

Sister-skill references that document admin click-paths (e.g. `dynamicweb-swift-demo/references/admin-ui-authoring.md`, `re-skin.md`) are maps of *what is configurable and where* — for a human doing manual authoring, and as verification targets — not instructions for Claude to drive the SPA.

## Anti-pattern: SQL-cloning structural trees

Cloning a tree (Area / Page / Paragraph / GridRow / Item) via raw SQL `INSERT INTO ... SELECT FROM` is forbidden unless you have a working *and tested* recipe in this skill. The structural tables look simple but every create-path involves:

- `*MasterPageId` / `*MasterAreaId` sibling-link bookkeeping (DW expects matching ranges across the tree)
- Item instance cloning vs sharing (some item types fork per language layer; some don't — DW knows which)
- Item-localization rows (translated field overlays) in tables you didn't notice
- ItemList relations + sort order propagation
- `*Hidden` / `*TreeSection` / `*MasterType` flags that hide system pages from the content tree
- Cache invalidation on the page-composition + grid-row caches

**The pitfall:** raw SQL clones get the visible page tree partly right, then break things you only notice 10 screens later (missing PDPs, headers appearing in the content tree, sibling-page links going to 404). Cleanup is then harder than just using MCP/API in the first place.

## Silent no-ops on UPDATE surfaces — verify by round-trip, not by status code

A `succeeded` / `status: ok` response from surfaces 1-2 does NOT guarantee the field you sent was applied. Some MCP / Management API writes report success, bump `updatedDate`, and silently drop part of the input (e.g. `save_pages` drops `menuText`; `ParagraphSave` drops item-field value mutations). The catalogue of these version-pinned no-ops and their working fallbacks lives with the tools themselves: [`foundational/extend-mcp-tools.md`](foundational/extend-mcp-tools.md) §5 (MCP/API tool behaviour) and [`foundational/content-modelling.md`](foundational/content-modelling.md) (the same two no-ops framed as paragraph/page save bookkeeping).

**The always-on demo discipline:** after any update through MCP/API where the change is demo-critical, round-trip it (read the value back through a different surface, or curl the rendered page) before declaring it done. When a silent no-op is confirmed, the SQL fallback is sanctioned — log it in the demo's `CUSTOMISATIONS.md` and note the cache that needs flushing.
