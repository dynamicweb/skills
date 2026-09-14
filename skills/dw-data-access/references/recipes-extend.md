# Out-of-product recipes: Extend

This reference holds the out-of-product recipes for extend (providers, notification subscribers and
AddIns: the host restart an install owes, install-state probes, and the commands an AddIn adds):
Management API commands at `/admin/api/...`, host process operations, and direct SQL. The in-product
skills for this area are `dynamo: true` and carry no instruction on those surfaces, so they keep a
one-line pointer here instead of the recipe.

Every recipe names its surface in the repo convention: MCP tools `snake_case` in backticks,
Management API commands `PascalCase` in backticks with the route on first use in this file,
serializer operations by command or by layer and mode, and `SQL` labelled as such in a fenced `sql`
block. Every SQL recipe states three things inline: why the higher surfaces do not cover it, that
it is **local installs only**, and the cache flush or host restart it owes.

## Contents

- [Restart the host and probe an AddIn's install state](#restart-the-host-and-probe-an-addins-install-state)
- [StaticLinkManager requests](#staticlinkmanager-requests)

## Restart the host and probe an AddIn's install state

In-product home: [dw-extend-providers](../../dw-extend-providers/SKILL.md)
(`addin-lifecycle.md` §2), which carries the stuck-state signature and the three-way response table.

**Surface: the host process.** After an AppStore install, the pipeline that registers the AddIn's
services has not run until the host process restarts. On a local development host that is a full
`dotnet run` cycle: stop the parent process, not only the child worker, because a bounce of the child
alone may not cold-start. On a hosted install the restart goes to whoever operates the host, since no
MCP tool and no Management API command restarts it. Confirm the restart in the host log: a
`Running pipeline: '<Package>.<Pipeline>'.` line.

**Surface: Management API.** Probe any command the AddIn adds, with bearer auth:

```
POST https://localhost:<PORT>/admin/api/<AddInCommand>
Authorization: Bearer <api-key>
Content-Type: application/json
{"Model":{}}
```

Read the response against the table in `addin-lifecycle.md` §2: `400 Unknown command` means not
installed, `500 TypeInitializationException ... No service for type` means installed and not
restarted, `200 {"status":"ok"}` means working. A hosted install runs the same call against
`https://<host>`.

- **Why the higher surfaces do not cover it**: no MCP tool restarts the host or calls an arbitrary
  AddIn command.
- **The debt it owes**: none; the restart is itself the fix.

## StaticLinkManager requests

In-product home: [dw-extend-providers](../../dw-extend-providers/SKILL.md)
(`addin-lifecycle.md` §3), which carries the settings shape, the save response and the
troubleshooting table.

**Surface: Management API**, available once the package is installed and the host has restarted:

```
GET  /admin/api/StaticLinkAll                                      -- paginated list of all links
GET  /admin/api/StaticLinkById?id=<int>                            -- single link by integer id
GET  /admin/api/StaticLinkByArgumentAndType?Type=<T>&Argument=<A>  -- lookup by (type,argument); idempotency checks
POST /admin/api/StaticLinkSave    body { Model: { Type, Argument, ... } }  -- create or update a link
POST /admin/api/StaticLinkDelete  body { Model: { Id: <int> } }            -- revoke a link
GET  /admin/api/StaticLinkSettings                                 -- AddIn-level config (template, expiration)
POST /admin/api/StaticLinkSettingsSave                             -- update AddIn-level config
```

Query parameter names are case-sensitive: `Type=Product` works, `type=Product` answers `500` with an
`Enum.Parse` failure.

- **Why the higher surfaces do not cover it**: no MCP tool reaches the static-link commands.
- **Hosted installs included**: these are API calls, not SQL.
- **The debt it owes**: none; read a `StaticLinkSave` back through `StaticLinkByArgumentAndType`.
