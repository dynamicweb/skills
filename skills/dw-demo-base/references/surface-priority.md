# Surface priority — scaffold vs build, by instance type

`SKILL.md` "Surface priority for CREATES" carries the always-on summary; this reference is the sole owner of the full rule — the surface table, the pattern, and the canonical statement of the surface contract: which surfaces exist on each instance type, which of them are action surfaces in each phase, plus the long-form anti-pattern detail on why SQL-cloning structural trees fails. The *platform mechanism* underneath the discipline — why an MCP create triggers all the domain-service bookkeeping (ItemRelation cloning, ItemList propagation, cache/index refresh) that raw SQL misses, and why the admin UI is a SPA over `/admin/api/...` rather than a separate surface — is owned by [`../../dw-extend-mcp-tools/references/backend-mcp-server.md`](../../dw-extend-mcp-tools/references/backend-mcp-server.md) §5.

## Contents

- [Two phases, one gate](#two-phases-one-gate)
- [Surfaces by instance type](#surfaces-by-instance-type)
- [Build phase — the strict rule](#build-phase--the-strict-rule)
- [Scaffold phase (local) — the bootstrap one-clicks](#scaffold-phase-local--the-bootstrap-one-clicks)
- [Admin UI is verification-only during the build](#admin-ui-is-verification-only-during-the-build)
- [Anti-pattern: SQL-cloning structural trees](#anti-pattern-sql-cloning-structural-trees)
- [Silent no-ops on write surfaces (updates, deletes, index builds) — verify by round-trip, not by status code](#silent-no-ops-on-write-surfaces-updates-deletes-index-builds--verify-by-round-trip-not-by-status-code)

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

**Clause (a) covers brand re-content removal — do not mis-route it as create-shaped work.** BULK REMOVAL of the generic/sample rows a baseline ships (the stock demo catalog, sample pages, placeholder groups) while re-contenting a host to a brand is exactly case (a) cleanup/teardown — SQL is sanctioned for it on a local install, subject to the cache/restart the removed table owes (see [`cache-invalidation.md`](../../dw-data-access/references/cache-invalidation.md)). Removal is not a create, so it is not gated by the "MCP-first for structural creates" rule and there is no MCP/recipe prerequisite to clear first. The create-shaped discipline (and the SQL-cloning ban below) governs what you *build* to replace the sample data, not the teardown that clears it. Track what you delete so a re-run converges.

Pattern to follow:

1. Try MCP. If the tool name suggests it (e.g. `copy_area`, `copy_page`, `save_pages`), use it.
2. If MCP errors or doesn't expose the operation, work the Management API. The operation exists there — the admin UI is a SPA over `/admin/api/...`, so every UI click has an endpoint. Discover it via the `/admin/api/docs/` catalogue, a local clone of the DW10 source for binder shapes (see [`dw-demo-hosted/references/online-mode.md`](../../dw-demo-hosted/references/online-mode.md) "dw10source as binder disambiguator"), or by navigating the admin UI **read-only** with Playwright and reading the SPA's traffic (`mcp__playwright__browser_network_requests`) — reading network calls is verification-grade; clicking Save is not.
3. Local installs only: after 1–2 are exhausted, reach for SQL — and even then, prefer SQL for cleanup of a previous bad attempt rather than for the create.

Driving the admin UI to *make* a build-phase change is off-contract on every instance type. A "UI-only" operation means the endpoint hasn't been found yet — go back to step 2.

This rule is owned by `dw-demo-base` and inherited by every sister skill.

## Scaffold phase (local) — the bootstrap one-clicks

Until the Backend MCP exists there is nothing at surface 1, and until a bearer exists there is nothing at surface 2 — so the scaffold phase sanctions the admin UI via the Browser MCP as an action surface for exactly these operations:

- **Create the MCP configuration and capture the shown-once API key** (`mcp-setup.md` Step 3).
- **Create the Management API key** (`mcp-setup.md` Step 6).
- **AppStore install of the Backend MCP AddIn** when the csproj `PackageReference` route is closed (`../../dw-extend-mcp-tools/references/backend-mcp-server.md` §1 — `PackageReference` stays the default).
- **Portal downloads** the install scripts can't fetch.

The scaffold ladder: script / CLI / filesystem → Admin API (when a bearer already exists) → **admin UI via the Browser MCP** → headless code recipe (`../../dw-extend-mcp-tools/references/backend-mcp-server.md` §4) → ask the user. Involve the user only when every automated surface is genuinely unreachable — e.g. the Browser MCP tools haven't surfaced in this session yet (they appear in a fresh session; one Claude Code restart loads them) and no API token exists.

Install the Browser MCP **first** in the scaffold sequence (`browser-automation.md`) — it is machine-level and idempotent, and it is the surface the other bootstrap steps drive.

The scaffold phase ends when the MCP verification gate passes; from that point the build-phase rule above applies without exception.

## Admin UI is verification-only during the build

The admin UI is a SPA client of the Admin API — every click it makes lands on `/admin/api/...`. Two consequences:

- **No operation exists only in the UI.** When neither MCP nor the documented Management API seems to cover something, the endpoint exists anyway. Find it via `/admin/api/docs/`, the `dw10source` command classes, or read-only Playwright network watching (`mcp__playwright__browser_network_requests`) — then call the endpoint directly as surface 2.
- **A verb-registry brute-force proves a VERB absent, never a CAPABILITY absent.** This is the failure mode that makes the rule above easy to talk yourself out of. Enumerating both verb registries and finding no `ItemEntry*` / `ItemList*` / `ItemEntrySave` verb is an *honest, correct* result — and the inference "so item lists are unreachable from the API" was wrong for a year, because the write is **not its own verb**: it rides inside `ParagraphSave` as an array on the parent paragraph's projected list field. No registry probe can ever find a capability that has no verb of its own, so a negative registry result is not evidence of anything except the absence of that name. **Before concluding a surface is closed, capture the admin UI's own HTTP call for the operation** (read-only Playwright + `browser_network_requests`) and replay it. Where the wrong conclusion has already been written down, expect the *more specific* document to be the stale one — and that is the one an agent reaches for first. (Worked example: [`modelling-discipline.md`](../../dw-content-modelling/references/modelling-discipline.md) §"How repeater children are stored".)
- **The positive form of the same discovery: the screen route's `Type=` parameter names its backing query.** Every admin screen route carries `Type=<query name>`, and that value is a Management API query the bearer can call directly — so admin-screen state is assertable with no browser in the loop, once the route→query map has been harvested by driving the admin **read-only** one time. Guessing verb names instead is not free: each unresolvable name writes an `[Application/AddInManager]` Error row onto the customer-visible Insights Monitoring dashboard, so batch the probing, do it early, and clear the log before a demo. Both are owned by [`management-api-and-sql.md`](../../dw-data-access/references/management-api-and-sql.md) "Discovering admin screens and their backing queries".
- **Driving the admin SPA via Playwright to *make* a build-phase change is the worst of both worlds** — fragile selectors wrapped around the same service call you could have made directly, with no machine-readable response to verify against. Playwright's job during the build is verification: navigate, screenshot, DOM-grep to confirm a change landed (see `references/browser-automation.md`).

Sister-skill references that document admin click-paths (e.g. `dw-demo-swift/references/admin-ui-authoring.md`, `re-skin.md`) are maps of *what is configurable and where* — for a human doing manual authoring, and as verification targets — not instructions for Claude to drive the SPA.

## Anti-pattern: SQL-cloning structural trees

Cloning a tree (Area / Page / Paragraph / GridRow / Item) via raw SQL `INSERT INTO ... SELECT FROM` is forbidden unless you have a working *and tested* recipe in this skill. The structural tables look simple but every create-path involves:

- `*MasterPageId` / `*MasterAreaId` sibling-link bookkeeping (DW expects matching ranges across the tree)
- Item instance cloning vs sharing (some item types fork per language layer; some don't — DW knows which)
- Item-localization rows (translated field overlays) in tables you didn't notice
- ItemList relations + sort order propagation
- `*Hidden` / `*TreeSection` / `*MasterType` flags that hide system pages from the content tree
- Cache invalidation on the page-composition + grid-row caches

**The pitfall:** raw SQL clones get the visible page tree partly right, then break things you only notice 10 screens later (missing PDPs, headers appearing in the content tree, sibling-page links going to 404). Cleanup is then harder than just using MCP/API in the first place.

## Silent no-ops on write surfaces (updates, deletes, index builds) — verify by round-trip, not by status code

A `succeeded` / `status: ok` response from surfaces 1-2 does NOT guarantee the operation happened. Some MCP / Management API writes report success, bump `updatedDate`, and silently drop part of the input (e.g. `save_pages` drops `menuText`; `ParagraphSave` drops item-field value mutations) — and some delete/build tools report success while doing nothing at all (`delete_area` leaves the row; `build_product_index` touches a marker file without writing segments). The catalogue of these version-pinned no-ops and their working fallbacks lives with the tools themselves: [`../../dw-extend-mcp-tools/references/backend-mcp-server.md`](../../dw-extend-mcp-tools/references/backend-mcp-server.md) §5 (MCP/API tool behaviour) and [`modelling-discipline.md`](../../dw-content-modelling/references/modelling-discipline.md) (the same two no-ops framed as paragraph/page save bookkeeping).

**The response model is an ECHO, so a read-back through the same API confirms the write that did not happen.**
The known drop classes are all silent and all shaped alike: an unknown item-group key, a field with no
`EcomProductField` registration, a field blocked by `AllowChangesAcrossVariants` / `AllowChangesAcrossLanguages`,
and a complex editor posted as a JSON string instead of a nested object. Several read verbs additionally serve
a cached or merged model rather than the stored row, so even a *different* read verb can agree with the lie —
an API-level verifier once reported 54/54 pass while three paragraphs were still fully untranslated, and only
the direct SQL read showed it. **The store or the rendered screen is the oracle: re-read the row from the
database, or render the page.** Corollary: do not raise a residual off a single API read taken immediately
after a write, and check the persona before calling a feature missing — customer-centre rows are user-group
gated, so testing as the wrong user looks identical to a feature that is not there.

**Any API verb that RE-SAVES an entity silently reverts raw-SQL edits made behind it — so API writes first, SQL last, and never re-save afterwards.** This is the general form of the ordering rule, and it fires on verbs that do not look like writes at all: a *recalculate* verb does not just re-total, it re-saves the whole entity from Dynamicweb's **cached** model, which predates anything SQL wrote behind the API. One build sequence backdated and tagged eight orders and then recalculated them; the recalculate wrote the cached model — still stamped with the creation time, still holding an empty reference — straight back over all eight. No error, no warning, the changes were simply gone. The fix is sequencing, not a flush: **all API writes → then the SQL touch-up → and nothing re-saves the entity after that.** (Worked example and the order-specific sequence: [`order-lifecycle.md`](../../dw-commerce-orders/references/order-lifecycle.md) "A re-saving verb reverts raw-SQL edits". The discount family's version of the same fact: [`promotions-engines.md`](../../dw-commerce-orders/references/promotions-engines.md) "Every legacy write re-persists the CACHED translation".)

**And a read-back can be stale in the other direction — a write can land in the database and on the rendered page while the API model still serves the old value.** A grid re-sort that landed correctly in both the DB and the rendered DOM read back in the *previous* order through the API list query, because the sort verb does not invalidate that model's cache. A script that verifies its own re-sort through the API would conclude failure — and a retry or revert on that basis **destroys the correct state**. Where a write has a rendered or database oracle, use it; treat a disagreeing API read as a cache, not as a failed write, before acting on it.

**The always-on demo discipline:** after any update through MCP/API where the change is demo-critical, round-trip it (read the value back through a different surface, or curl the rendered page) before declaring it done. When a silent no-op is confirmed, the SQL fallback is sanctioned — log it in the demo's `CUSTOMISATIONS.md` and note the cache that needs flushing.
