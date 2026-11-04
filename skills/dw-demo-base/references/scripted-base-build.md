# Scripted local base build

## Contents

- [Scope and command](#scope-and-command)
- [Machine prerequisites](#machine-prerequisites)
- [Customer configuration](#customer-configuration)
- [Release and file composition](#release-and-file-composition)
- [Database writes](#database-writes)
- [Headless access choice](#headless-access-choice)
- [Resume and evidence](#resume-and-evidence)
- [Acceptance](#acceptance)
- [Next step: branding](#next-step-branding)
- [Remaining person and agent work](#remaining-person-and-agent-work)

## Scope and command

This path scaffolds a running, unbranded local Windows Truvio Commerce (powered by Dynamicweb)
Swift 2 base from a public release bacpac. It restores the edition's catalogue, variants, PIM data
models, completion rules, workspace and persona relationships as shipped, and proves the base
serves them. No serializer or YAML delivery runs during this command.

**The command applies no customer branding.** The base keeps the edition's own Truvio Commerce
brand, copy and product tiles. Branding is the next agent step, after the command passes: run
`dw-demo-swift` and its brand guidance on the running base (see [Next step: branding](#next-step-branding)).
This split keeps the script to the deterministic part and leaves branding to the skills' current
knowledge rather than to a frozen token generator.

Copy [demo-build.example.json](../assets/demo-build.example.json) into your demo's `notes/`
directory, set the slug and customer name, and run the orchestrator from the installed skill
directory.

```powershell
pwsh -NoProfile -File scripts/Invoke-DwDemoBaseBuild.ps1 -ConfigPath $config -DemoRoot $demo -SqlServer $server -Port $port -Apply
```

All four paths/connection arguments are explicit. `$config`, `$demo`, `$server` and `$port`
are values the caller supplies, not machine defaults. An optional `-Database` chooses the new
database name; otherwise it is derived from the slug. Omit `-Apply`, or use `-WhatIf`, to list
the steps with no writes. A nonzero exit means NOT READY. Do not infer success from files existing.

The order is preflight, release, scaffold, restore, files, access keys, start and license,
access, index, acceptance, and stamps and report. Every step script can also run separately;
use `Get-Help` for its named parameters. Write scripts preview unless `-Apply` is present.

## Machine prerequisites

Install PowerShell 7, Git, a .NET 10 SDK and local SQL Server with Windows authentication once.
Use [setup-checks.md](setup-checks.md) for installation links and environment diagnosis.
The SQL account needs database-creation rights. SQL Server Express is sufficient.
Alternatively, set both `DW_SQL_USER` and `DW_SQL_PASSWORD` for SQL authentication, including
sqlpackage and the generated host configuration; credentials are never part of the build stamp.
The command neither installs services nor changes IIS or an existing unowned database.

Put the intended SDK's `dotnet` first on PATH and set `DOTNET_ROOT` when the default executable
has no SDK. `dotnet --list-sdks` must report a 10.x SDK. SDK initialization is also bounded:
`dotnet --version` must complete within 45 seconds. Preflight installs the missing public
`Dynamicweb.ProjectTemplates` package and installs `microsoft.sqlpackage` into the demo's
ignored `notes/tools/` when no `sqlpackage` is on PATH. It also ensures a current-user HTTPS
development certificate exists, without changing the machine trust store. NuGet, GitHub and the license service
must be reachable. The generated host targets only `net10.0` and pins Suite from INDEX.json.

## Customer configuration

Only `slug` and `customer.name` are required. The default installs the pinned public MCP app
before first startup. Unsupported localization values fail
before the build; this first path supports the edition's US, USD and en-US data.

| Key | Meaning |
|---|---|
| `slug` | Lowercase letters, digits and hyphens, 2-48 characters, starting with a letter; names the database and flow state |
| `customer.name` | Required display name, up to 120 characters; recorded for the branding step, not written into the site |
| `customer.country`, `currency`, `language` | Optional; US, USD, en-US respectively |
| `edition` | Optional `swift-demo`; other editions are refused |
| `installMcpBeforeStart` | Optional boolean, default true; stages the public app in AddIns before boot. False is for separate step-script/AppStore workflows |

A `brand`, `storefront`, `personas` or `catalogue` block is refused with a pointer to
`dw-demo-swift`: palette, logo, copy, persona and catalogue renames are branding, done on the
running base after the command, not in it.

## Release and file composition

The build clones or fast-forwards public Distribution `main` into `distribution/`. New clones use
a sparse checkout of contracts and assets, avoiding thousands of YAML files this path never reads.
A dirty checkout
is refused. It asserts `gateProven`, the edition proving run, the bacpac DW version and CLEAN scrub
verdict, downloads the public GitHub Release asset without `gh`, and verifies SHA256 against
`layers/INDEX.json`. It records the resolved commit, edition, bacpac hash, Swift tag and app pins.

The Swift Files release comes from the base contract's public asset URL with its SHA256 verified.
Disk overlays follow base, non-sample additions, surfaces, sample additions, the sample-data toggle,
and themes last. Later files win. Required GlobalSettings from the base contract are applied after
the overlay. `GlobalSettings.Database.config` points at the new local integrated-auth database.
The theme layer's `default` Style group (ColorSchemes, Typography and Buttons) is served as shipped.

## Database writes

SQL is local installs only. The API is unavailable before the host's first startup, so the fresh
restore is the sanctioned local-install rung. Every write happens while the host is stopped;
first startup pays the cache refresh. Values are parameterized and no caller-supplied SQL runs.
The command writes two things: restored credentials and the access keys.

The existing administrator and three personas receive password hashes from the published first-login
contract, lowercase hex SHA-512 of UTF-8 password plus `DwSecret`. Set `DW_ADMIN_PASSWORD`,
`DW_BUYER_PASSWORD`, `DW_CSR_PASSWORD` and `DW_ACCOUNT_ADMIN_PASSWORD` before the first run to choose
them. Otherwise random secrets are generated once into ignored local files. To follow the local
demo convention from [scaffold.md](scaffold.md), supply that administrator password through the
environment. No password literal ships in a script. The admin login is `Admin`.

`TC*` primary keys, customer numbers, persona usernames and every display value stay as the
edition shipped them. The branding step renames display values later, keyed by those stable keys.

## Headless access choice

The command stages the exact `gateProven.apps` MCP package from the public NuGet V3 flat
container into the AppStore's AddIns layout before first startup. It verifies SHA512 against
NuGet's public catalog entry, keeps the downloaded archive and metadata under ignored
`notes/tools/`, places the package's `lib/net10.0/` under
`Files/System/AddIns/Installed/<id>.<version>/lib/net10.0/`, and overlays its own `Files/` payload.
That payload contains the runtime Host assembly. The host references only Suite; neither MCP
nor its Host is a csproj dependency. The installer refuses any DLL basename shared between
AddIns `lib/` directories and host `bin/`, which prevents duplicate type registration.

`installMcpBeforeStart` defaults to true. A separate manual workflow can set it false and use
Settings > AppStore > Available apps with the individual step scripts; the complete command
requires the app. No PackageReference escape hatch is used. The proof report records the exact
package version and whether this arrangement passed the live handshake.

The access-keys step provisions both API credentials before the first host start, on the
owned fresh local database. For bearer `<PREFIX>.<secret>`, `AccessUserTokenHash` stores
`<PREFIX>.` plus lowercase hex SHA-512 of UTF-8 `<secret>DwSecret`. This uses the same salt
convention as the published first-login password contract. Set `DW_API_KEY_SECRET` and
`DW_MCP_KEY_SECRET` to secrets of at least 32 characters, or let the build generate them once
into ignored `notes/build-secrets.local.json`. It asserts the administrator-bound token rows,
the full-access `McpConfiguration` and the `McpConfigurationCredential` binding. Tables absent
from the bacpac are created with the measured app schema. A repeated step reuses the same
hashes and binding. The binding must exist at startup.

On MCP 0.6.3 the create command hands the key to a short-lived admin-screen cache; the
Management API overview does not expose plaintext. The build therefore never calls create or
reads an overview. Access proves admin TokenAuthentication, calls `License` with the provisioned
Management API key, initializes MCP and requires more than 200 tools before writing client
settings. No credential code is added to Program.cs. This schema and convention were measured
on the gate-pinned version; a later package schema must be re-proven before changing that pin.

The real key lives only in ignored `.mcp.json` and `notes/credentials.local.md`. Local Claude settings
pre-enable the server and carry the TLS env layer. The User-scope TLS bypass and process layer are
both set per [mcp-setup.md](mcp-setup.md); a fresh agent shell is still needed to inherit it.

## Resume and evidence

Progress lives at `.demo/<slug>/flow-state.json` with the shape in [orchestrator.md](orchestrator.md):
steps, gates_passed and instructions_used JSON properties, plus config hash, connection identity and timings.
Re-running identical inputs resumes the first unfinished step. Changed config/connection inputs are
refused; use a fresh DemoRoot. Preflight, start/license and acceptance run again on resume because
runtime readiness can change. A partial failed import is refused rather than silently dropped.

Receipts, the journal, readiness, storyline and acceptance reports live under ignored `notes/`.
The journal records per-step result, seconds and `Instructions used`. `CUSTOMISATIONS.md` starts from
the shipped template and appends public version/hash provenance. License expiry is read from the authenticated Management API `License` query and recorded in
`notes/license-proof.json` and the customisations ledger.

## Acceptance

The product/content index step resolves builders over the Management API, builds instances and
waits for fresh Lucene segments. Acceptance runs the sibling host-readiness harness, edition critical
pages and all three persona identity probes. It asserts the edition's `default` ColorSchemes,
Buttons and Typography sheets are linked from home and served, nonzero named PLP products and
resolving product images. Placeholder text fails. The edition's Truvio Commerce text is expected
on an unbranded base and does not fail; customer name, palette and copy are not checked here,
because the command does not apply them.

A gate failure is a failure of the whole command, even if a host is running. Inspect the local
receipts and journal, fix the cause, and resume. The command reports remaining work on failure too.

## Next step: branding

A passing build reports `branded: false` and names the next step in `notes/build-report.json`, the
console summary and the `CUSTOMISATIONS.md` stamp. Brand the running base for the customer with
`dw-demo-swift`: rebrand, header and footer, palette and typography Style pairs, logo and icons,
storefront copy, and, where the story needs it, persona and catalogue display names keyed by the
stable `TC*` keys. Use its brand guidance as it stands when you run it; it supersedes anything this
command once generated. The MCP key the build wrote to `.mcp.json` is the surface for that work.

## Remaining person and agent work

- Install PowerShell 7, Git, the .NET 10 SDK and SQL Server once; links live in setup checks.
- Sign into Claude Code and install the complete public presales skills bundle once.
- Open a fresh agent shell to inherit the User-scope TLS setting and load the local MCP entry.
- Brand the base with `dw-demo-swift` (the next step above).
- Supply design sign-off and fine-tune copy, credible domain catalogue, price ladders, supplementary
  assets, localization and the PIM narrative after branding.
- Use `dw-demo-hosted` for a hosted URL/key target; this command has no hosted mode.
- Use Settings > AppStore > Available apps for a separate manual installation workflow.

No admin UI click is claimed to be inherently required for local database restore, password repair,
trial activation or token minting. The concrete proof report accompanying a change records which
chain actually ran and which gate, if any, prevented readiness.
