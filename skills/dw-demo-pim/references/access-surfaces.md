# access-surfaces.md

> Four-surface decision matrix for Dynamicweb 10 instance access (MCP / Management API / direct SQL / filesystem). Use this to pick the fastest surface for any given PIM task. Loaded from `~/.claude/skills/dynamicweb-pim-demo/SKILL.md` "Where to find things" table.

## Access surfaces

You have FOUR independent surfaces into a Dynamicweb 10 instance. Use whichever is fastest for the task — they're not redundant:

1. **MCP (`dynamicweb-commerce-mcp`)** — ~260 tools, rich schemas, slow to auth but convenient for create/update. Tokens expire mid-session; re-auth with `/mcp`.

2. **Management API** — `https://localhost:<PORT>/admin/api/` with `Authorization: Bearer CLAUDE.xxx` tokens. **Spec UI at `/admin/api/docs/`**. Best for admin operations the MCP doesn't expose (BuildIndex, IndexStatus, cache invalidation, feature flags, rule-usage inspection). Always reach for the API before restarting the host when you need a cache flush. Full admin-endpoint catalog + the runtime OpenAPI-discovery probe: [`../../dw-demo-base/references/foundational/data-access.md`](../../dw-demo-base/references/foundational/data-access.md).

3. **Direct SQL** — `sqlcmd -S "localhost\SQLEXPRESS" -E -d <DB>` or via PowerShell when heredocs get mangled. Schemas are discoverable via `INFORMATION_SCHEMA.COLUMNS`. Fastest for bulk corrections and structural fixes.

4. **Filesystem** — repositories, queries, feed templates, indexes live as XML/cshtml/xslt files under `wwwroot/Files/System/Repositories/` and `wwwroot/Files/Templates/`. Copy patterns from any Swift reference installation when starting fresh.

Surface choice is task-driven, not preference-driven. Common shortcuts: bulk schema fixes → SQL; cache flush after rule-table mutation → Management API `CacheInformationRefresh`; rich create/update with field schemas → MCP; copy a `.query` or `.index` file from a Swift baseline → filesystem.

## Management API + OpenAPI discovery + per-project reference paths

The Management API admin-endpoint catalog (BuildIndex, IndexStatus, CacheInformationRefresh, GetServiceCaches, FeatureManagementToggle, CompletionSettingsSourceById), the runtime OpenAPI-discovery probe, and the per-project discovery table (host URL/port, SQL Server, DB name, API token) are vendor-generic platform facts — see [`../../dw-demo-base/references/foundational/data-access.md`](../../dw-demo-base/references/foundational/data-access.md).

Two reference sources this demo skill leans on (per-project):

| Ref | How to find it in the current project |
|---|---|
| Swift `base` layer (per-demo checkout) | `<demo-root>\distribution\layers\base\` — the demo's checkout of the canonical swift/2.3 `base` layer (a `config/replace/merge` tree, from the Distribution repo `justdynamics/Truvio.Commerce.Distribution`). Its serialized index XML is the copy-paste source for `Products.index` definitions. |
| DW10 source clone | a local clone of the DW10 source (location per machine — ask/discover, never hardcode) — search `src/Features/Ecommerce` for Ecom internals and `Dynamicweb.Products.UI` for admin UI behavior. Otherwise fall back to https://doc.dynamicweb.dev/ |

When the user gives you a token, port, or path in chat, treat it as scoped to the project in the current working directory — save it in conversation state, not as a global default.
