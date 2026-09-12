# Host exposure and path wiring

Two ways a correctly configured Dynamicweb 10 host serves something it should not, or stops serving
something it should. Reached from [SKILL.md](../SKILL.md).

## Contents

- [The file archive is public by extension, not by permission](#the-file-archive-is-public-by-extension-not-by-permission)
- [A web.config `<location>` can silently unhook the app from a sub-path](#a-webconfig-location-can-silently-unhook-the-app-from-a-sub-path)

## The file archive is public by extension, not by permission

**Treat every file under `/Files` whose extension is not on the static-file middleware's blocklist as
anonymously downloadable from the internet.** The middleware serves `wwwroot/Files/Files/**` and
blocks by **extension** — `.config`, `.cshtml`, `.query`, `.index` return 404 — and a `/Files`
request is served by the static handler without ever reaching the page pipeline, so **page and role
permissions never enter it**. A gated page whose assets live under `/Files` gates the browser and not
a single byte.

`.xml` and `.json` are **not** on the blocklist. Verified anonymously readable on a stock install,
with a browser user agent and no cookie:

| Path | Response |
|---|---|
| `/Files/Files/Integration/jobs/<job>.xml` | 200 — and a `SqlProvider` activity embeds its connection string, so this publishes a SQL username and password in cleartext |
| `/Files/System/Items/*.xml` | 200 |
| `/Files/System/Serializer/Serializer.config.json` | 200 |
| `/Files/GlobalSettings.Database.config` | 404 (the extension **is** blocked) |

Three things follow:

- **Configure `SqlProvider` activities with integrated security, never a connection string.** The
  provider ships `<SourceServerSSPI>` / `<DestinationServerSSPI>` switches that sit beside the
  existing `<Server>` / `<Catalog>` elements; switching to them re-ran four activities with identical
  row counts and left zero credential bytes on disk and over HTTP — **and it survives Dynamicweb
  re-serialising the job files on every run**, which a one-off hand edit does not. An empty
  connection string with no SSPI is not a third option: the provider throws `The ConnectionString
  property has not been initialized` and does not fall back to the Dynamicweb connection.
- **Grep job files as UTF-16LE.** They carry a BOM, so a naive byte grep for `Password=` finds
  nothing and reports a **false clean**. Decode first, then assert.
- **The durable fix on a customer install is to move the file archive off the web root**, or to put
  the assets behind an authenticated handler. A site-level `web.config`
  `<system.webServer><security><requestFiltering>` deny is **not** available on a typical shared host:
  the `<security>` section is locked at machine level in `applicationHost.config`, so the site answers
  500 on **every** URL including `/Admin` and has to be rolled back.

Where the exposure cannot be closed, assert it deliberately — a gate check that **expects** the 200,
named as a known caveat — so nobody discovers it in front of a customer.

## A web.config `<location>` can silently unhook the app from a sub-path

DW's stock `web.config` declares the ASP.NET Core Module handler (the entry that hosts the whole
application) inside `<location path="." inheritInChildApplications="false">`. That declaration
therefore **does not propagate into a path that `applicationHost.config` configures explicitly**. Add
an IIS-level restriction on a sub-path and IIS starts serving that path with the classic
`PageHandlerFactory-Integrated-4.0` handler instead: every request under it returns the classic
ASP.NET 404 page, while the identical request one path segment higher reaches Dynamicweb and returns
DW's own branded 404.

**Re-declare the `aspNetCore` handler explicitly at the `<location>` for any sub-path you configure**,
and confirm it with `appcmd list config` on both paths — the handler must be present at the sub-path,
not only at the site root.

**Test the restricted path's own response body, not an aggregate.** The IP filter itself keeps
behaving correctly, so a check that only asserts "public 403, loopback not 403" passes while the route
is dead. Assert the loopback request returns 200 **and** the expected body.
