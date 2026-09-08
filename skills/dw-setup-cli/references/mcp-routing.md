# MCP and the CLI — why both exist, and how to aim MCP at the right solution

The decision table lives in [SKILL.md](../SKILL.md); this is the reasoning behind it and the check to run before writing anything through MCP.

## Why MCP cannot replace this CLI

The MCP file tools are restricted by path. Verified against a 10.29 server:

- `upload_file` writes **only** to `/Files/Images` and `/Files/Files/Integration`. Templates and config
  locations are explicitly **not writable** — deploying a `.cshtml` through MCP is impossible.
- `delete_file` and `move_file` are limited to those same two folders.
- `read_file` reads `/Files/Templates` and `/Files/System/Styles`, but rejects binary files.
- `list_files` is **not recursive** and caps at 1000 entries.
- Uploads cap at 25 MB, one file per call.
- There is **no add-in install tool**.

## Before writing through MCP, confirm which solution it points at

An MCP server is configured against one specific solution, and that may not be the `--host` you are
targeting with the CLI. A write can otherwise land on an entirely different environment than the one
under discussion.

**Do not identify the solution by its area domains.** `get_areas` returns each area's configured
`domain`, and that list routinely omits the hostname you are actually using — a solution reached at
`<name>.dynamicweb.cloud` can report only its internal `*.dynamicweb.dk` domains. Judging by that list
alone gives a false negative and will stop you writing to the right solution.

**Fingerprint it instead.** Read back through MCP something whose exact content you already know from the
CLI side — best of all something you just wrote yourself:

```bash
dw files Templates/Designs/Swift-v2/Swift-v2_Master.cshtml ./check -e --host <host> --apiKey "$(cat ~/.dw-apikey)"
```

then `read_file` the same path through MCP and compare. Matching content means one solution. This works
because `/Files/Templates` is readable through MCP even though it is not writable.
