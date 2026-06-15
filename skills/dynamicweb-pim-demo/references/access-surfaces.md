# access-surfaces.md

> Four-surface decision matrix for Dynamicweb 10 instance access (MCP / Management API / direct SQL / filesystem). Use this to pick the fastest surface for any given PIM task. Loaded from `~/.claude/skills/truvio-pim-demo/SKILL.md` "Where to find things" table.

## Access surfaces

You have FOUR independent surfaces into a Dynamicweb 10 instance. Use whichever is fastest for the task — they're not redundant:

1. **MCP (`truvio-commerce-mcp`)** — ~260 tools, rich schemas, slow to auth but convenient for create/update. Tokens expire mid-session; re-auth with `/mcp`.

2. **Management API** — `https://localhost:<PORT>/admin/api/` with `Authorization: Bearer CLAUDE.xxx` tokens. **Spec UI at `/admin/api/docs/`**. The OpenAPI JSON path is not officially documented and varies by Swashbuckle version — discover at runtime via the probe in §OpenAPI Discovery below. Best for admin operations the MCP doesn't expose: **BuildIndex**, ProductCombine, IndexStatus, **cache invalidation** (clear specific service cache: `POST /admin/api/CacheInformationRefresh {"CacheTypeName":"Dynamicweb.Ecommerce.Shops.ShopService"}`; enumerate all caches via `GET /admin/api/GetServiceCaches`), **feature flags** (`POST /admin/api/FeatureManagementToggle {"FeatureTypeName":"..."}`), and **rule-usage inspection** (`GET /admin/api/CompletionSettingsSourceById?Id=<ruleId>`). Always reach for the API before restarting the host when you need a cache flush.

3. **Direct SQL** — `sqlcmd -S "localhost\SQLEXPRESS" -E -d <DB>` or via PowerShell when heredocs get mangled. Schemas are discoverable via `INFORMATION_SCHEMA.COLUMNS`. Fastest for bulk corrections and structural fixes.

4. **Filesystem** — repositories, queries, feed templates, indexes live as XML/cshtml/xslt files under `wwwroot/Files/System/Repositories/` and `wwwroot/Files/Templates/`. Copy patterns from any Swift reference installation when starting fresh.

Surface choice is task-driven, not preference-driven. Common shortcuts: bulk schema fixes → SQL; cache flush after rule-table mutation → Management API `CacheInformationRefresh`; rich create/update with field schemas → MCP; copy a `.query` or `.index` file from a Swift baseline → filesystem.

## OpenAPI Discovery

The OpenAPI JSON path on a running DW10 host is not officially documented and varies by Swashbuckle version. Probe at runtime:

> Run in PowerShell, not Bash — Bash interpolation eats `$env:` and `$_` before they reach the script.

```powershell
# Probe the Swagger UI to find the actual OpenAPI JSON URL
$port = (Select-String -Path .\Dynamicweb.Host.Suite\Properties\launchSettings.json -Pattern 'https://localhost:(\d+)' | Select-Object -First 1).Matches[0].Groups[1].Value
$swaggerUiHtml = Invoke-WebRequest -Uri "https://localhost:$port/admin/api/docs/" -UseBasicParsing
# Look for the OpenAPI JSON URL in the swagger-initializer.js or inline script
$specMatch = [regex]::Match($swaggerUiHtml.Content, 'url:\s*"([^"]+)"')
if ($specMatch.Success) { Write-Host "OpenAPI JSON: https://localhost:$port$($specMatch.Groups[1].Value)" }
else { Write-Host "Could not auto-discover; open /admin/api/docs/ in browser and inspect the Network tab." }
```

The probe degrades gracefully — if the regex misses, the Network-tab fallback always works. Port discovery follows the discover-from-project-files rule (port from `launchSettings.json`, not hardcoded).

## Reference paths

Always discover per-project — never assume values carry across projects.

| Ref | How to find it in the current project |
|---|---|
| Solution root | The current working directory when the skill is invoked (or the parent folder containing `Dynamicweb.Host.Suite/`) |
| Host URL | `.mcp.json` at solution root, or `Dynamicweb.Host.Suite/Properties/launchSettings.json` under `applicationUrl` |
| SQL Server | Default `localhost\SQLEXPRESS` on Windows dev boxes; verify via `GlobalSettings.Database.config` connection string |
| DB name | From `Dynamicweb.Host.Suite/GlobalSettings.Database.config` — `Database=` or `Initial Catalog=` in the connection string |
| Management API token | Project-specific bearer token in the form `CLAUDE.<hex>`. User provides this per project; don't reuse tokens across projects |
| Swift 2.2 baseline (vault) | `$env:DW_VAULT\serialized-data\Swift2.2\` — the canonical Swift 2.2 baseline. Its serialized index XML is the copy-paste source for `Products.index` definitions. |
| DW10 source clone (vault) | `$env:DW_VAULT\dw10source\` — search `src/Features/Ecommerce` for Ecom internals and `Dynamicweb.Products.UI` for admin UI behavior. Otherwise fall back to https://doc.dynamicweb.dev/ |

When the user gives you a token, port, or path in chat, treat it as scoped to the project in the current working directory — save it in conversation state, not as a global default.
