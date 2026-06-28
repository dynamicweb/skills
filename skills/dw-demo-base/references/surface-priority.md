# Surface priority for CREATES — anti-pattern detail

The always-on summary (surface table + 4-step pattern) lives in `SKILL.md` "Surface priority for CREATES". This reference carries the same table for standalone loading, plus the long-form anti-pattern detail on why SQL-cloning structural trees fails.

## The surface table

| Surface | Use for | Why |
|---------|---------|-----|
| 1. **MCP (`dynamicweb-commerce-mcp`)** | **Default — try this first for anything that creates a structural row** (pages, paragraphs, areas, products, groups, orders, users, etc.) | Calls DW's domain services. Triggers ALL the bookkeeping a UI click would: ItemRelation cloning, ItemList propagation, sibling-page linking, cache invalidation, index refresh, child-row creation, validation. ~260 tools. |
| 2. **Management API** (`/admin/api/...`) | Fallback when MCP doesn't expose the operation. Usually admin-grade actions: `BuildIndex`, `CacheInformationRefresh`, `FeatureManagementToggle`, anything in `/admin/api/docs/`. | Same DW domain services as MCP, just a different transport. |
| 3. **Admin UI** (Playwright) | **Verification only** — navigate, screenshot, DOM-grep to confirm a change landed. Never an action surface. | Every admin-UI click is an Admin API call underneath (the admin SPA is a client of `/admin/api/...`), so a "UI-only" operation means you haven't found the endpoint yet — check `/admin/api/docs/` or watch the SPA's network calls. For a genuinely awkward one-click (e.g. AppStore install), ask the user to click manually; don't drive the admin SPA via Playwright to make changes. |
| 4. **Direct SQL** (`sqlcmd ...`) | **LAST RESORT** — only for: (a) cleanup/teardown, (b) bulk schema-drift fixes, (c) reading data, (d) cases where you've confirmed all three higher surfaces don't support the operation and a vendor patch is the only alternative. | Bypasses every DW service. Misses bookkeeping. Creates orphans. Corrupts caches. **You will not figure out the full bookkeeping for a non-trivial create via SQL — DW does too much per service call.** |

## Anti-pattern: SQL-cloning structural trees

Cloning a tree (Area / Page / Paragraph / GridRow / Item) via raw SQL `INSERT INTO ... SELECT FROM` is forbidden unless you have a working *and tested* recipe in this skill. The structural tables look simple but every create-path involves:

- `*MasterPageId` / `*MasterAreaId` sibling-link bookkeeping (DW expects matching ranges across the tree)
- Item instance cloning vs sharing (some item types fork per language layer; some don't — DW knows which)
- Item-localization rows (translated field overlays) in tables you didn't notice
- ItemList relations + sort order propagation
- `*Hidden` / `*TreeSection` / `*MasterType` flags that hide system pages from the content tree
- Cache invalidation on the page-composition + grid-row caches

**The pitfall:** raw SQL clones get the visible page tree partly right, then break things you only notice 10 screens later (missing PDPs, headers appearing in the content tree, sibling-page links going to 404). Cleanup is then harder than just using MCP/API in the first place.

## Pattern to follow

1. Try MCP. If the tool name suggests it (e.g. `copy_area`, `copy_page`, `save_pages`), use it.
2. If MCP errors or doesn't expose the operation, try the Management API (`/admin/api/docs/` for the catalogue).
3. If neither seems to expose it, the operation still exists on the Admin API — the admin UI is a SPA over `/admin/api/...`. Find the endpoint the UI calls (`/admin/api/docs/`, or watch the network tab while the user clicks once), then call it as surface 2. If endpoint discovery stalls, pause and ask the user to do the one-click manually. Playwright on `/Admin` is verification-only — never drive the admin UI to make changes.
4. Only after exhausting 1-3 do you reach for SQL — and even then, prefer SQL for cleanup of a previous bad attempt rather than for the create.

This rule is owned by `dynamicweb-demo-base` and inherited by every sister skill.

## Admin UI is verification-only

The admin UI is a SPA client of the Admin API — every click it makes lands on `/admin/api/...`. Two consequences:

- **No operation exists only in the UI.** When neither MCP nor the documented Management API seems to cover something, the endpoint exists anyway. Find it via `/admin/api/docs/`, or watch the SPA's network calls while the user performs the action once (browser dev tools, or `mcp__playwright__browser_network_requests`), then call the endpoint directly as surface 2.
- **Driving the admin SPA via Playwright to *make* a change is the worst of both worlds** — fragile selectors wrapped around the same service call you could have made directly, with no machine-readable response to verify against. Playwright's job on `/Admin` is verification: navigate, screenshot, DOM-grep to confirm a change landed (see `references/browser-automation.md`). For genuinely awkward one-clicks (e.g. AppStore install) where endpoint discovery stalls, ask the user to click manually.

Sister-skill references that document admin click-paths (e.g. `dynamicweb-swift-demo/references/admin-ui-authoring.md`, `re-skin.md`) are maps of *what is configurable and where* — for a human doing manual authoring, and as verification targets — not instructions for Claude to drive the SPA.

## Silent no-ops on UPDATE surfaces — verify by round-trip, not by status code

A `succeeded` / `status: ok` response from surfaces 1-2 does NOT guarantee the field you sent was applied. Known cases where the call reports success, bumps `updatedDate`, and ignores part of the input:

| Surface | What gets silently dropped | Verified | Working fallback |
|---|---|---|---|
| MCP `save_pages` (update path) | `menuText` — the response even echoes the OLD value | DW 10.25.x | SQL `UPDATE Page SET PageMenuText` + host restart (nav tree caches menu text) |
| Management API `ParagraphSave` | `contentItem.groups[].fields[].value` mutations — the `ItemType_*` column never updates | DW 10.25.x | MCP `set_item_field_values` first; SQL UPDATE last resort. `ParagraphSave` IS still right for paragraph-level scalars (Header, Sort, GridRow, Template) |

**Rule:** after any update through MCP/API where the change is demo-critical, round-trip it (read the value back through a different surface, or curl the rendered page) before declaring it done. When a silent no-op is confirmed, the SQL fallback is sanctioned — log it in the demo's `CUSTOMISATIONS.md` and note the cache that needs flushing.
