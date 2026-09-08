# CLI versions — what changes between 1.0.16, 1.1.2 and 1.1.3

Behaviour differs by version and the differences bite. Reached from [SKILL.md](../SKILL.md) Step 0.

## Check the version — it changes what is available

```bash
dw --version
```

Trustworthy from 1.1.3 onwards. Before that it was not, and the failure was worse than it looks: yargs
was never given a version, so it guessed one by walking up from the **working directory** for a
`package.json`. From a directory with none it printed `unknown`; from inside any Node project it
confidently printed *that project's* version as if it were the CLI's. So an older CLI does not merely
fail to answer — it can answer wrongly, which quietly invalidates any support conversation that starts
with "what version are you on?". If `dw --version` prints `unknown`, or you need certainty on an older
install, read it from npm instead:

```bash
npm ls -g @dynamicweb/cli
```

Behaviour differs by version, and the differences matter. These are the versions actually verified — if
you are on something in between, confirm with `dw <command> --help` rather than assuming:

| Capability | 1.0.16 | 1.1.2 | 1.1.3 |
|---|---|---|---|
| `dw install --output json` (machine-readable envelope, exit code 1 on failure) | absent | present | present |
| Wildcards in the `dw install` path | **broken — do not use** | works | works |
| `dw --version` reports the CLI's own version | no | no | yes |
| `--apiKey` stays out of the request URL on `dw query` / `dw command` | no | no | yes |
| `dw swift` runs on Windows | **broken** | **broken** | works |

The `dw swift` row matters out of proportion to its place in this skill. On Windows before 1.1.3 the
command died immediately with `error: spawn npx ENOENT` on any current Node: it spawned npx without a
shell, and Node removed the implicit shell for `.cmd` files in the CVE-2024-27980 fix (18.20.2 / 20.12.2
/ 21.7.3). It is often the first command someone runs after installing the CLI, so it reads as a broken
Node install rather than a CLI bug. `dw swift --list` was unaffected, because that path returns before
npx is invoked. If you are stuck on an older CLI, take the tag from `--list` and run degit yourself —
this is exactly what the CLI would have run:

```bash
npx degit dynamicweb/swift#<tag> C:\path\to\swift
```

The wildcard case on 1.0.16 is a real bug, not just a missing feature: `install.js` passes the raw
`argv.filePath` to the upload step while only the activation step resolves the glob. Tested on 1.0.16, the
upload therefore tries to open a literal `*` path and the process dies with an unhandled
`ENOENT ... Acme.AddIn*.dll` and a Node stack trace. It fails loudly and exits 1 — nothing
is uploaded and nothing is half-installed. On 1.0.x, always pass a fully resolved path.

To upgrade:

```bash
npm install -g @dynamicweb/cli
```
