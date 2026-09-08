# Files archive — import, export, delete and move

The `dw files` surface, including the silent-skip trap that makes a failed import look like a successful one. Reached from [SKILL.md](../SKILL.md).

## Contents

- [Uploading and updating files (import)](#uploading-and-updating-files-import)
- [Deleting and moving: not `dw files`, but not impossible](#deleting-and-moving-not-dw-files-but-not-impossible)
- [Exporting files (export)](#exporting-files-export)

One command, `dw files [dirPath] [outPath]`, does listing, export, and import.

> **The two positionals swap meaning between export and import.** This is the single most common mistake.
>
> - **Export (`-e`)** — `dirPath` is **remote**, `outPath` is **local**. Pulls *from* the solution.
> - **Import (`-i`)** — `dirPath` is **local**, `outPath` is **remote**. Pushes *to* the solution.
>
> Getting it backwards on an import means you name a local directory as the destination, and the upload
> goes somewhere unintended on the solution.

## Uploading and updating files (import)

Push one local folder's files into `/Templates` on the solution:

```bash
dw files ./templates Templates -i -o
```

Push a whole local tree, subdirectories included:

```bash
dw files ./templates Templates -i -r -o
```

Update one specific file — `dirPath` may be a file rather than a directory, and `outPath` stays the remote
*directory* it belongs in:

```bash
dw files ./templates/YourFile.cshtml Templates -i -o
```

> **`-o` / `--overwrite` is required to update anything that already exists.** Without it the CLI sends
> `skipExistingFiles=true` and the server silently skips every existing file. The command still prints
> `status: 'ok'`, still says `Finished uploading files. Total files: 1`, and still exits 0 —
> **nothing changed**. If the task is "update a file on the solution", `-o` is mandatory.

**On 1.0.16 there is a tell; on 1.1.2 there is none.** This is the one place where the newer version is
worse, and it is tested on both.

1.0.16 prints the API response, so a skip is visible immediately:

```text
model: [ '/Files/_dwcli-test/probe.txt' ]   <- written
model: []                                   <- skipped, despite "Total files: 1" and exit 0
```

1.1.2 prints **no API response at all** for `dw files`. A skipped import looks exactly like a successful
one:

```text
Uploading files
Uploading chunk 1 of 1
Finished uploading files. Total files: 1, total chunks: 1
```

That is the output whether the file was written or silently skipped, and the exit code is 0 either way.
The cause is structural: `uploadFiles` now routes the response through `output.addData()`, which is a
no-op unless `--output json` is set — and `dw files` has no `--output json` on any version.

**Consequence: on 1.1.2 the only way to know an import landed is to read the state back** (Step 3). Do not
skip it, and do not treat "Total files: 1" as confirmation of anything.

Other import flags:

- `-r`, `--recursive` — walk subdirectories. Without it, only files directly in `dirPath` are sent.
- `--createEmpty` — sets `createEmptyFiles=true` on the upload call. Per the flag's own description, an
  empty file is otherwise not created at the destination.

Behaviour worth knowing:

- Missing remote directories are created automatically.
- Large pushes are chunked automatically, so pushing a whole template tree in one call is fine.
- **`dw files` has no `--output json` on any version.** The response body is console-printed, not a
  structured envelope, and the exit code is 0 whether or not anything was written. Read the `model` array
  as the immediate signal, and confirm anything that matters with a listing or diff (Step 3).

## Deleting and moving: not `dw files`, but not impossible

`dw files` only lists, downloads, and uploads — there is no delete, rename, or move flag on either
version. Uploading a renamed copy therefore leaves the original in place and silently doubles the file.

The capability does exist through the Management API via `dw command`. **MCP does not rescue you here
for most paths:** its `delete_file` and `move_file` only work under `/Files/Images` and
`/Files/Files/Integration`, so deleting or moving a *template* is one of the few cases where
`dw command` is the only route, not a fallback. Use MCP's file tools when the target is inside those two
folders; otherwise use the commands below. Verified present on a 10.29 solution:

| Command | JSON model |
|---|---|
| `FileDelete` | `{ "DirectoryPath": "...", "Ids": ["..."] }` |
| `DirectoryDelete` | `{ "Path": "..." }` |
| `FileMove` | (query `CommandByName` for the current shape) |

Verified working call — note the body is **bare, with no `model` wrapper**:

```bash
dw command FileDelete --json '{"DirectoryPath":"_scratch","Ids":["_scratch/probe.txt"]}' --host <host> --apiKey "$(cat ~/.dw-apikey)"
```

Returns `status: 'ok'` and the file is gone from the next listing.

**The JSON envelope is not consistent across commands.** These file commands take the model's fields at
the top level, exactly as `dw files` posts them to `FileDownload`. Other commands do not: the CLI README
shows `PageCopy` wrapped as `{"model":{...}}` and `PageDelete` bare as `{"id":"..."}`. Do not assume a
wrapper. Mirror how `dw files` calls the same family of endpoints where you can, otherwise try bare first
and read the response — a wrong envelope comes back `ok` with nothing changed, the same silent-success
failure mode as a missing `-o`.

**Discovering a command's parameters:** `dw command <name> -l` does not work — `getProperties()` returns
the string `"This option currently doesn't work"` before it reaches the API call, so the README's `-l`
documentation is wrong. Query the endpoint directly instead; it is a GET, so it is safe to probe:

```bash
curl -s -H "Authorization: Bearer $KEY" "https://<host>/Admin/Api/CommandByName?name=FileDelete"
```

A real command returns HTTP 200 with a `model` field holding the JSON shape; an unknown name returns 500.
That request/response pair is the reliable way to build any `dw command` call.

## Exporting files (export)

Pull `/Templates` from the solution into `./templates`, files included, recursive:

```bash
dw files Templates ./templates -f -r -e
```

Pull a single file:

```bash
dw files Templates/Translations.xml ./templates -e
```

Export flags:

- `-r`, `--recursive` — include subdirectories.
- `-f`, `--includeFiles` — include files, not just the directory skeleton.
- `--raw` — keep the downloaded `.zip` instead of unpacking it.
- `--iamstupid` — also export `system/log` and `.cache`. Effectively never wanted; these are huge.

Whether a path is treated as a file or a directory is inferred from whether it has an extension. Override
when that inference is wrong:

- `-ad`, `--asDirectory` — a directory whose name contains a dot (`templates/templates.v1`).
- `-af`, `--asFile` — a file with no extension (`templates/testfile`).

Running `-e` with no `dirPath` triggers a full-archive export behind an interactive confirmation. Do not
do this unless the user asked for it.
