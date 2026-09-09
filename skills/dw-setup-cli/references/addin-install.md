# Add-in install loop — flags, recycle, and asserting success

Everything `dw install` does and does not guarantee. Reached from [SKILL.md](../SKILL.md); read that first for auth and the target check.

## Contents

- [Flags](#flags)
- [Choosing between immediate and queued](#choosing-between-immediate-and-queued)
- [Triggering a recycle](#triggering-a-recycle)
- [Asserting success](#asserting-success)
- [A successful install does not prove the add-in loaded](#a-successful-install-does-not-prove-the-add-in-loaded)
- [Wildcards (1.1.2; do not use on 1.0.16)](#wildcards-112-do-not-use-on-1016)

```bash
dotnet build -c Release
```

```bash
dw install ./bin/Release/net10.0/YourProject.dll
```

`dw install` accepts `.dll` and `.nupkg`. It does two things: uploads the file to the solution's
`System/AddIns/Local` folder (always overwriting), then calls the `AddinInstall` API to activate it.

## Flags

- `-q`, `--queue` — queue activation for the next Dynamicweb recycle instead of applying it now.
- `--output json` — structured envelope on stdout, exit code 1 on failure (**1.1.2; absent in 1.0.16**).
- `-v`, `--verbose` — log the resolved path.

## Choosing between immediate and queued

**Neither variant recycles the solution.** `dw install` never restarts the application, so the choice is
not about avoiding downtime:

- **Without `-q`** — the assembly is loaded into the *running* application straight away. No restart, no
  dropped requests. This is what makes the dev loop fast.
- **With `-q`** — activation is deferred until the next recycle, so the new code does not go live until
  a recycle happens.

So `-q` is about *when the new code takes effect*, not about protecting the site from a restart. Pick on
that basis:

- Local or dev environment: omit `-q`. Immediate load is the point.
- Shared, test or production: use `-q` when you do not want new code becoming live at an unannounced
  moment, then activate deliberately at a planned recycle. Say plainly that the install is staged.

Do not describe a non-queued install as "forcing a recycle" — it is not one. The CLI's own flag text
("Queues the install for next Dynamicweb recycle") describes only the deferred case and is easy to
over-read in the other direction.

## Triggering a recycle

On a cloud-hosted solution there is no `dw` command that restarts the application. You trigger a recycle
by dropping a marker file named `recycle.txt` into `/Files/System/CloudHosting` — the same folder that
already holds the platform's other control files (`ChangeVersion-Readme.txt`, `BackupRestoreDB/`):

```bash
echo recycle > ./recycle.txt
dw files ./recycle.txt System/CloudHosting -i -o --host <host> --apiKey "$(cat ~/.dw-apikey)"
```

This is the companion to `dw install -q`: queue the add-in, then recycle when the disruption is
acceptable.

**The platform consumes the marker.** Tested: `recycle.txt` was absent before the upload and absent
again afterwards — it is deleted once the recycle is triggered. So it never accumulates, and `-o` is not
actually required for this to work a second time. Passing `-o` anyway is harmless and saves you from
depending on that cleanup, which is why it is in the command above.

**Verified: this really does restart the solution.** During the recycle the site returned HTTP 503, then
came back at 200 after a short window. In-flight requests are dropped. Do not trigger one on a shared
environment without asking.

> **`dw files` breaks while the solution is down.** Any `dw files` call during the recycle window dies
> with `SyntaxError: Unexpected token '<', "<!DOCTYPE "... is not valid JSON` — `getFilesStructure` calls
> `res.json()` on the HTML error page the platform serves at 503. It is not a CLI bug you can work
> around; just wait for the site to answer 200 and retry.

**Templates do not need a recycle.** A `.cshtml` pushed with `dw files` renders on the very next request
— verified by pushing a change to `Swift-v2_Master.cshtml` and seeing it live immediately, with no
recycle and no cache clear. Recycles are for add-in assemblies, not for templates or other Files content.
Do not restart a solution just because a template edit "hasn't shown up"; check `-o` and the `model` array
first, since a silently skipped upload looks exactly like a caching problem.

## Asserting success

Where the envelope exists, prefer it — it is the only reliable signal:

```bash
dw install ./bin/Release/net10.0/YourProject.dll --output json
```

`ok: true` plus exit code 0 means uploaded and activated. On failure `ok` is `false`, `errors[]` carries
the API detail, and the process exits 1.

Verified on 1.1.2, a failure gives a clean envelope and no crash:

```json
{ "ok": false, "status": 1, "data": [],
  "errors": [ { "message": "Could not find any files with the name ./bin/.../DoesNotExist.dll" } ] }
```

exit 1. A success carries two `data` entries — `type: "upload"` and `type: "install"` (the latter with
`"message": "App(s) successfully installed"`) — plus `meta.resolvedPath`, `meta.queued` and
`meta.filesProcessed`.

**On 1.0.16 the same bad path behaves completely differently:** there is no envelope, and the upload step
opens the raw path before anything validates it, so the process dies with an unhandled
`ENOENT ... open '<path>'` and a Node stack trace. It still exits 1, but you never see
`Could not find any files with the name ...` — that message is unreachable from `dw install` on 1.0.16.
Another reason to be on 1.1.2 in any automated context.

On 1.0.x there is no envelope. Check the exit code and read the human output. Verified on 1.0.16, a
successful queued install prints the upload response with the target path, then the activation line:

```text
model: [ '/Files/System/AddIns/Local/YourProject.dll' ]
Installing addin
Addin installed
```

and exits 0; a missing file exits 1. Then verify via Step 3.

## A successful install does not prove the add-in loaded

**`ok: true` and "App(s) successfully installed" only mean the file was uploaded and the API accepted the
registration call. They are not evidence that the assembly loaded or that its types are usable.**

Tested on a live 10.29 solution with a purpose-built `BaseScheduledTaskAddIn`:

- the upload landed (`model: [ '/Files/System/AddIns/Local/...dll' ]`), the DLL persisted in the archive
- the install returned `ok: true`, `status: 200`, `"App(s) successfully installed"`, exit 0
- **the add-in type never appeared** in the solution's scheduled-task type list — not after the
  non-queued install, and not after a full recycle either

**The cause is now established: the assembly was built against newer packages than the solution runs.**
An A/B test with identical source settled it — compiled against `Dynamicweb` 10.28.9 (stable) the add-in
loaded and its type appeared; recompiled against `Dynamicweb.Suite 10.29.2-PreRelease` the same code
stopped loading and the type disappeared again. `dw install` reported success identically both times.

So when an installed add-in is missing, check the package versions it was built against before suspecting
the CLI or the upload. `Version="10.*"` (latest stable) is the safe default; a prerelease or a version
newer than the host loads nothing and says nothing.

**So verify against the feature, not the command.** Confirming the DLL is in `System/AddIns/Local` proves
only the upload. Confirm the add-in itself is present — its type in the relevant admin list, its provider
selectable, its task creatable — and if it is missing, suspect the assembly's package versions against
the solution's runtime before suspecting the CLI.

## Wildcards (1.1.2; do not use on 1.0.16)

The path is glob-matched against the directory and the **first** match wins, which is useful when the
filename carries a version:

```bash
dw install "./bin/Release/net10.0/YourProject*.dll"
```

Quote the pattern so the shell does not expand it first. If more than one file matches you get whichever
the directory listing returns first.

Verified on 1.1.2. You do not have to guess which file it picked — `--output json` reports it:

```json
"meta": { "resolvedPath": "C:\...\net10.0\YourProject.dll", "filesProcessed": 1 }
```

Read `meta.resolvedPath` whenever the pattern could match more than one file.
