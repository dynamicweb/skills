---
name: dw-setup-cli
type: flow
group: setup
mcp: none
dynamo: false
description: 'Operate a Dynamicweb 10 solution with the `dw` CLI — install `.dll`/`.nupkg` add-ins, upload and update Files-archive content, export the archive, trigger a recycle, and prove the change landed. Triggers: deploy or install an add-in, `dw install`, `dw files`, upload or update templates, export a solution''s files, trigger a recycle, API-key auth for the CLI, `dw install` reported success but nothing changed, an import that silently skipped, deciding whether a task belongs to the CLI or the Dynamicweb MCP server. Non-triggers: upgrading a solution''s platform version -> dw-setup-upgrade; connection strings and environment configuration -> dw-setup-config; installing a solution from scratch -> dw-setup-install; writing the add-in code itself -> dw-extend-providers; content, product or order writes that MCP already covers -> dw-content-modelling.'
---

You are operating a live Dynamicweb 10 solution through the `dw` CLI. Every command here writes to a real
environment, so the order is always: confirm which environment you are pointed at, act, then verify by
reading back from the solution.

## Scope

This skill covers two workflows, both of which move **files**:

1. **Add-in install loop** — build a custom .NET library, push it to a solution, confirm it loaded.
2. **Files archive** — upload/update files (templates, assets) on a solution, or export them to disk.

**It does not cover changing content.** Pages, paragraphs, item fields, products and users live in the
database, not the Files archive, and belong to the Dynamicweb MCP server — see the next section, which
decides which tool a task belongs to before you run anything.

Also not covered: `dw query`, `dw database`, `dw swift`, `dw config` — except that Step 0 records the
version trap that made `dw swift` unusable on Windows before 1.1.3, because it is the command people hit
first and its error blames Node rather than the CLI. `dw command` appears once, only as the last-resort
route for deleting or moving archive files that MCP cannot reach. For working *on* the
CLI's own source, read `CLAUDE.md` in the CLI repository instead.

## Choosing your tool: MCP or the CLI

**Ask one question: am I changing a file, or a record?**

- **A file in the Files archive** — a template, a stylesheet, an asset, an add-in `.dll`, a marker file
  → **`dw` CLI**. This skill.
- **A record in the database** — page, paragraph, item field, product, user, order
  → **Dynamicweb MCP**, if a server is connected.

Everything below is detail on that one split. The two tools barely overlap, so this is a routing
decision, not a preference.

**How to tell which you are dealing with:** if a string is visible on the site but `grep` finds it
nowhere in the Files archive, it is database content — reach for MCP. Page and paragraph text lives in
item fields, not in any `.cshtml`, so no amount of template editing will change it.

### Quick reference

| What you want to change | Use | Why |
|---|---|---|
| A `.cshtml` template, or anything outside `/Files/Images` | `dw files` | MCP cannot write there at all |
| Bulk or recursive archive push/pull | `dw files` | MCP has no recursive or bulk transfer |
| An add-in (`.dll`, `.nupkg`) | `dw install` | MCP has no add-in tool |
| A recycle | `dw files` → `recycle.txt` | MCP cannot write `System/CloudHosting` |
| Database export, Swift release | `dw database`, `dw swift` | MCP has no equivalent |
| Page, paragraph, item field, product, user, order | **MCP** | Typed, validated, read-modify-write |
| Product images, Integration source files | **MCP** | Typed, and inside its writable paths |
| Reading a template just to inspect it | Either | MCP `read_file` is cheaper than an export |
| Anything MCP covers | **MCP**, never `dw command` | See below |
| Nothing above fits and no MCP server exists | `dw command` + `CommandByName` | Last resort |

### Never hand-build an API call when MCP can do it

If a Dynamicweb MCP server is connected, use it rather than `dw command` or a raw `/Admin/Api` POST. MCP
parameters are typed and validated, read-modify-write means a record's untouched fields survive, and
errors come back as errors. A hand-built command POST has none of that: a wrong JSON envelope returns
`status: 'ok'` and changes nothing, and a partial model can overwrite fields you never sent.

Why the CLI cannot simply be replaced by MCP, and the check to run before you write anything through
MCP — the server is not always aimed at the solution you assume — are in
[references/mcp-routing.md](references/mcp-routing.md).

## Step 0 — Preflight

Run these before the first `dw` command in a session. Do not skip; most failures in this workflow are
preflight failures that surface later as a confusing API error.

### Check the version — it changes what is available

```bash
dw --version
```

Trustworthy from 1.1.3 onwards; on older CLIs it guessed from the working directory and could report
another project's version as its own, so fall back to `npm ls -g @dynamicweb/cli` if it prints
`unknown`. Three behaviours that matter differ across the versions in the wild — `dw --version` itself,
whether `--apiKey` leaks into request URLs, and whether `dw swift` runs on Windows at all. Before
relying on any of them, read
[references/cli-versions.md](references/cli-versions.md).

To upgrade:

```bash
npm install -g @dynamicweb/cli
```

### Git Bash on Windows

Git Bash rewrites paths that begin with `/`, which corrupts the **remote** paths these commands take.
The CLI prints a warning about this. Export the guard once per shell session:

```bash
export MSYS_NO_PATHCONV=1
```

The check is an exact string comparison against `1`, so `=true` or `=yes` will not disable the warning or
the conversion.

If you would rather not set it, write remote paths without a leading slash (`Templates`, not `/Templates`).
PowerShell and CMD are unaffected.

### Confirm the target solution

Because every command carries an explicit `--host`, the target is whatever you type — there is no ambient
"current environment" to inherit and no `dw env` switching to do. That puts the burden on you:

**State the host out loud before running any command that writes, and confirm it is the solution the user
meant.** A typo in `--host` is the whole blast radius.

`~/.dwc` may exist on the machine from earlier use. Ignore it — `--host` bypasses it entirely, so a stale
environment in that file cannot redirect a command, and its presence is not a reason to skip `--apiKey`.

### Authentication — always an API key, never `dw login`

**Authenticate with `--host` and `--apiKey`. Do not use `dw login`, and do not suggest it.**

This is not a fallback for when login fails, and not specific to cloud hosting — it is the only
authentication path this skill uses. `dw login` runs an interactive user credential prompt, is unavailable
on `*.dynamicweb.cloud` solutions entirely, and writes a key into `~/.dwc` as a side effect. None of that
is wanted.

**No exceptions:**
- Not when `~/.dwc` already has an environment configured — pass `--host`/`--apiKey` anyway
- Not when a command returns 401 — the fix is a valid key, never "try logging in"
- Not "just this once, to get set up"
- Do not run `dw login` yourself, and do not tell the user to run it

If there is no key, ask the user to create one — tell them exactly where:

> **Settings → System → Developer → Api Keys**

A key has a name, a description, an owner, and an expiry date, and its value is `<prefix>.<key>` — the
admin list only ever shows it masked, so it must be copied at creation time. Pass it per command:

```bash
dw files <args> --host <solution>.dynamicweb.cloud --apiKey "$DW_API_KEY"
```

`--host` bypasses the environment config entirely (`setupEnv` stops looking at `~/.dwc`) and `--apiKey`
bypasses login. `--host` is rejected without `--apiKey`. Add `--protocol http` only for a local HTTP host.

> **Fixed in 1.1.3; a real leak on every version before it.** `dw query` and `dw command` built their
> request parameters as `Object.keys(argv).filter(k => !exclude.includes(k))`, and their `exclude` lists
> contained `apiKey` but not the kebab-case alias `api-key` that yargs also puts in `argv`. So every
> `dw query` / `dw command` call made with `--apiKey` appended `&api-key=<your key>` to the URL -- where
> it reaches server logs and proxies -- and the CLI printed the whole URL, key included, in its error
> output. `dw files` and `dw install` were never affected.
>
> On 1.1.3 the parameter filter compares option names normalised, so no spelling of a reserved switch can
> be forwarded, and credential parameters are redacted before any URL is printed. Verified against a live
> solution: the key appears once in the output of a failing `dw query` on 1.1.2 and not at all on 1.1.3.
>
> **On anything older, rotate every key that has been used with those two commands** and read the log
> through the API with your own request (Authorization header) instead.

**Never accept an API key pasted into the conversation, and never write one into a command line
literally.** Have the user put it in a file and read it at call time, so the value stays out of the
transcript and out of shell history:

```bash
dw files ./templates Templates -i -o --host example.dynamicweb.cloud --apiKey "$(cat ~/.dw-apikey)"
```

Do not "simplify" this by writing the key into `~/.dwc` so later commands can omit `--apiKey`. That
trades an explicit, auditable target for an ambient one, and it is the same implicit-environment problem
that `--host`/`--apiKey` exists to avoid.

## Steps 1 and 2 — the two things this CLI does

Both are covered in full in their own reference. Read the one you need; the traps are in there, not
here.

| Task | Reference | The trap it documents |
|---|---|---|
| Install a `.dll`/`.nupkg` add-in, queued or immediate, and trigger a recycle | [references/addin-install.md](references/addin-install.md) | `dw install` reports success whether or not your assembly loaded |
| Upload, update, export, delete or move Files-archive content | [references/files-archive.md](references/files-archive.md) | without `-o` an import silently skips, and 1.1.2+ prints no API response to tell you |

Whichever you run, Step 3 is not optional.

## Step 3 — Verify (mandatory)

`dw files` cannot report failure structurally, and on 1.0.x neither can `dw install`. Never report success
from the absence of an error. Read the state back.

Confirm files landed, including contents, recursively:

```bash
dw files Templates -l -f -r
```

Confirm an add-in binary reached the solution:

```bash
dw files System/AddIns/Local -l -f
```

Check that the filenames you pushed are actually present. For an update, remember that a missing `-o`
produces a clean-looking run with no change — so if the listing shows the file but you are not sure the
*content* updated, export it back and diff:

```bash
dw files Templates/YourFile.cshtml ./verify -e
```

```bash
diff ./verify/YourFile.cshtml ./templates/YourFile.cshtml
```

Only claim the change is live after a listing or diff confirms it.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Warning about path conversion; remote path lands in the wrong place | Git Bash rewriting `/Templates` | `export MSYS_NO_PATHCONV=1`, or drop the leading slash |
| Import runs clean, exits 0, but the file is unchanged | `-o` omitted, so the server skipped the existing file | Re-run with `-o` |
| Import wrote to an unexpected remote location | Positionals swapped | Import is `<local> <remote>`; export is `<remote> <local>` |
| `dw install` cannot find the file | The path does not exist on disk (or is a wildcard on 1.0.16) | Check the build output path and target framework folder. Both versions exit 1, but they report it very differently — see below |
| Install uploads but the add-in never appears | Wildcard path on 1.0.16 | Pass a fully resolved path, or upgrade |
| 401 / unauthorized | API key missing, expired, or revoked | Ask the user for a new key from **Settings → System → Developer → Api Keys**. Never fall back to `dw login` |
| Add-in installed but the solution still runs old code | Activation was queued with `-q`, so it waits for a recycle | Trigger a recycle by uploading `recycle.txt` to `System/CloudHosting` (with `-o`), or re-run the install without `-q` to hot-load it into the running application |
| Empty local files never arrive | Zero-byte files skipped by default | Add `--createEmpty` |
| `SyntaxError: Unexpected token '<', "<!DOCTYPE "... is not valid JSON` | The solution served an HTML error page (usually 503 mid-recycle) and the CLI called `res.json()` on it | Wait until the site answers 200, then retry. Not fixable from the command line |
| Import prints `Total files: 1` on 1.1.2 but nothing changed | 1.1.2 prints no API response for `dw files`, so a missing-`-o` skip is invisible | Never trust that line. Read the state back with a listing or an export-and-diff |
| `dw install` says `App(s) successfully installed` but the add-in is unusable | The upload and registration succeeded; the assembly still may not have loaded | Check the add-in's own admin list, not the DLL. Suspect package versions built against the solution's runtime |

Self-signed certificates are accepted by design — the CLI's HTTPS agent sets `rejectUnauthorized: false`
so local dev hosts work. A TLS error therefore points at the host or protocol, not the certificate.

## What is verified, and what is not

Claims here do not all carry the same weight — some were tested against a live solution, some read
from the CLI source, some only reported. The breakdown, and the corrections made to earlier drafts of
this skill, are in [references/provenance.md](references/provenance.md). Read it before relying on
anything here that surprises you.

## Source of truth

The published README is behind the source and omits several of the flags used here and in the
references. When something here
disagrees with observed behaviour, read the command source and trust that:

- `bin/commands/files.js` — list, export, import, upload semantics
- `bin/commands/install.js` — add-in upload and activation
- `bin/commands/env.js`, `bin/commands/login.js` — environment and auth resolution

Do **not** trust `CLAUDE.md` in the CLI repository as a flag reference. As of 1.1.2 it documents an
OAuth mode (`--auth`, `--clientId`, `--clientSecret`) and a global `--output json` that exist nowhere in
`bin/`. The only global flags are `--verbose`, `--protocol`, `--host`, `--apiKey`, and `--output json` is
specific to `install`.

Repository: https://github.com/dynamicweb/CLI

Docs: https://doc.dynamicweb.dev/documentation/fundamentals/code/CLI.html
