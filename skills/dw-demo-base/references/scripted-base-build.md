# Scripted local base build

## Contents

- [Scope and command](#scope-and-command)
- [Machine prerequisites](#machine-prerequisites)
- [Customer configuration](#customer-configuration)
- [Release and file composition](#release-and-file-composition)
- [Database writes and stable keys](#database-writes-and-stable-keys)
- [Headless access choice](#headless-access-choice)
- [Resume and evidence](#resume-and-evidence)
- [Acceptance](#acceptance)
- [Remaining person and agent work](#remaining-person-and-agent-work)

## Scope and command

This path builds a local Windows Truvio Commerce (powered by Dynamicweb) Swift 2 demo from a
public release bacpac. It restores the edition's existing catalogue, variants, PIM data models,
completion rules, workspace and persona relationships. Customer display values are rewritten
before the host starts. No serializer or YAML delivery runs during this command.

Copy [demo-build.example.json](../assets/demo-build.example.json) into your demo's `notes/`
directory, adjust it, and run the orchestrator from the installed skill directory:

```powershell
pwsh -NoProfile -File scripts/Invoke-DwDemoBaseBuild.ps1 -ConfigPath $config -DemoRoot $demo -SqlServer $server -Port $port -Apply
```

All four paths/connection arguments are explicit. `$config`, `$demo`, `$server` and `$port`
are values the caller supplies, not machine defaults. An optional `-Database` chooses the new
database name; otherwise it is derived from the slug. Omit `-Apply`, or use `-WhatIf`, to list
the steps with no writes. A nonzero exit means NOT READY. Do not infer success from files existing.

The order is preflight, release, scaffold, restore, files, brand files, brand content, start and
license, access, index, acceptance, stamps and report. Every step script can also run separately;
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
| `slug` | Lowercase letters, digits and hyphens, 2-48 characters, starting with a letter |
| `customer.name` | Required display name, up to 120 characters |
| `customer.legalName`, `tagline` | Briefing metadata retained in the config; copy selectors choose where prose lands |
| `customer.country`, `currency`, `language` | Optional; US, USD, en-US respectively |
| `edition` | Optional `swift-demo`; other editions are refused |
| `installMcpBeforeStart` | Optional boolean, default true; stages the public app in AddIns before boot. False is for separate step-script/AppStore workflows |
| `brand.primary`, `secondary`, `accent`, `ink`, `background` | Six-digit hex colours, with neutral defaults |
| `brand.fontFamily`, `fontImportUrl`, `radius` | Font family, optional HTTPS CSS import, px/rem radius |
| `brand.schemes` | Optional object keyed by the seven fixed scheme ids; each overrides the colour model fields |
| `brand.logo` | Optional SVG source path relative to DemoRoot, copied to `Files/Images/Brand/logo.svg` |
| `brand.favicon`, `appleTouchIcon`, `metaImage` | Optional source files copied beneath `Files/Images/<slug>/` |
| `storefront.hero`, `about`, `footer`, `contact` | Optional objects with `paragraphHeader` and `title`, `subtitle` or `text` values, selecting existing Swift Text paragraphs |
| `personas[]` | Existing integer `id`, optional `name`, `email`, `company`, `address`, `zip`, `city`, `country`, `phone` |
| `catalogue.groups[]` | Stable `id`, optional `name` and `description` |
| `catalogue.products[]` | Stable `id`, optional `name`, `number`, `shortDescription`, `longDescription`, numeric `price`, raster `image` path |
| `catalogue.variantGroups[]`, `variantOptions[]` | Stable `id` and display `name` |
| `catalogue.categoryFields[]` | Stable `id` and supported display `name` or `label` |

Asset paths stay inside DemoRoot. Files in `customer-context/` are read and copied, never edited.
Absolute source paths, traversal outside the root and junction/symlink assets are refused.
A missing logo becomes an escaped customer wordmark. Missing icons and meta image become neutral
customer PNGs. No remote image discovery is performed. Raster generation uses Windows System.Drawing.

Example of an explicit catalogue edit, keeping the relation key:

```json
{
  "catalogue": {
    "products": [
      { "id": "TCPROD0001", "name": "Marine Connector Kit", "number": "NMS-0001" }
    ]
  }
}
```

Merge that block into a complete config. An omitted rename keeps the sample catalogue's structure
and copy, with the vendor company display name replaced. Domain-specific product authoring still
needs a complete map or the agent phase. The command does not invent a credible domain catalogue.

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

Brand generation rewrites the brand slot and the default ColorSchemes, Typography and Buttons
JSON/CSS pairs together. Seven scheme ids stay fixed. Button foreground is black or white, selected
by WCAG relative luminance and the larger contrast ratio. This explicitly chooses the shipped
`default` Style group: a later theme restage must be followed by brand generation again.

## Database writes and stable keys

SQL is local installs only. The API is unavailable before the host's first startup, so the fresh
restore is the sanctioned local-install rung. Every rewrite happens while the host is stopped;
first startup pays the cache refresh. The content rewrite uses one transaction and asserts row
counts. Display values are parameterized, and the rename translator selects identifiers from a
closed map. No caller-supplied SQL runs.

The existing administrator and three personas receive password hashes from the published first-login
contract, lowercase hex SHA-512 of UTF-8 password plus `DwSecret`. Set `DW_ADMIN_PASSWORD`,
`DW_BUYER_PASSWORD`, `DW_CSR_PASSWORD` and `DW_ACCOUNT_ADMIN_PASSWORD` before the first run to choose
them. Otherwise random secrets are generated once into ignored local files. To follow the local
demo convention from [scaffold.md](scaffold.md), supply that administrator password through the
environment. No password literal ships in a script. The admin login is `Admin`.

`TC*` primary keys, customer numbers and persona usernames remain intact. Product display-number
changes also update variant numbers and historical line numbers. Product `price` changes the
master's list price only; customer, contract, quantity and variant price ladders remain the sample
scenario and need an explicit agent review. The PIM shop and workspace's generated index-field
binding are renamed together, using an ASCII customer shop name to make that binding deterministic.
This is a base PIM setup, not a replacement for the canonical PIM authoring order.

Vendor-labelled primary PNG tiles are identified through their shipped source SVG and replaced on
the host by neutral PNGs carrying the product's current name. A supplied raster image takes priority.
Supplementary images and documents still require the agent's asset review.

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

The brand-content step provisions both API credentials before the first host start, on the
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
pages and all three persona identity probes. It asserts served brand tokens, stylesheet links, the
customer name on home, nonzero named PLP products and resolving product images. Visible vendor or
placeholder text fails. Internal stable keys and asset paths may still contain the original prefix.

A gate failure is a failure of the whole command, even if a host is running. Inspect the local
receipts and journal, fix the cause, and resume. The command reports remaining work on failure too.

## Remaining person and agent work

- Install PowerShell 7, Git, the .NET 10 SDK and SQL Server once; links live in setup checks.
- Sign into Claude Code and install the complete public presales skills bundle once.
- Open a fresh agent shell to inherit the User-scope TLS setting and load the local MCP entry.
- Supply design sign-off and fine-tune copy, credible domain catalogue, price ladders, supplementary
  assets, localization and the PIM narrative after the scripted base.
- Use `dw-demo-hosted` for a hosted URL/key target; this command has no hosted mode.
- Use Settings > AppStore > Available apps for a separate manual installation workflow.

No admin UI click is claimed to be inherently required for local database restore, password repair,
trial activation or token minting. The concrete proof report accompanying a change records which
chain actually ran and which gate, if any, prevented readiness.
