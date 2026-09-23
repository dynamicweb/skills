#!/usr/bin/env python3
"""Validate the Dynamicweb skills plugin repository.

Checks (errors fail the build, warnings are printed but do not):
  - marketplace.json parses and every referenced skill path exists.
  - Each skill folder name == `name:` frontmatter == marketplace path basename.
  - Each SKILL.md frontmatter has both `name` and `description`.
  - Each SKILL.md frontmatter parses as strict YAML (a mapping with name +
    description) — catches unquoted `description:` values carrying a second
    ": " that fail the real loader with "mapping values are not allowed here".
  - Each skill `description` is within the 1024-char frontmatter cap.
  - Each SKILL.md declares `dynamo: true | false` (manifest visibility).
    `dynamo: true` means usable in Dynamo: the skill is published to the
    in-product assistant and its content is held to what an MCP client can
    execute. It is a visibility flag, never an exclusivity flag: the skill
    runs anywhere an MCP client runs.
  - Each SKILL.md declares `mcp: required | optional | none`, and the body
    carries the matching marker section (`## MCP preflight` for required,
    `## Without MCP` for optional, neither for none).
  - Every relative markdown link in SKILL.md / references resolves to a real file.
  - No markdown file under skills/ begins with a UTF-8 BOM (breaks some
    frontmatter parsers).
  - No markdown file under skills/ contains double-encoded UTF-8 (mojibake).
  - Bundle closure: no skill in a marketplace bundle hard-depends (links into
    references/, assets/, or scripts/) on a skill the bundle does not ship.
  - Script contract (skills/*/scripts/*): PowerShell files carry
    `#Requires -Version 7.0`, comment-based help (.SYNOPSIS opening with
    `READ-ONLY.` or `WRITES:`, .DESCRIPTION) and an explicit param() block;
    Python files carry a module docstring. A skill that ships scripts declares
    the runtime in `compatibility:` frontmatter.
  - AV-safe scripts (skills/*/scripts/*.ps1|.psm1): no Invoke-Expression,
    Add-Type, FromBase64String or legacy web client; no credential literal; no
    TLS bypass the file does not gate on a loopback URL or an opt-in switch; no
    User-Agent set without a `# why:` comment. WARN past 400 lines. Comments
    and help blocks are exempt - the rules score code, not prose. `--self-test`
    runs them against scripts/tests/fixtures/av-nonconforming.
  - Script imports (Import-Module / dot-source) resolve on disk; a cross-skill
    import is a hard dependency and honors bundle closure.
  - No token-shaped secret anywhere under skills/; no plaintext password
    assignment and no environment literal (localhost:<port>, *.mydwsite*.com,
    the local solutions tree) inside scripts/.
  - BOM and mojibake checks cover skills/*/scripts/* files as well as markdown.
  - WARN if a skill description lacks a trigger signal (Triggers:/Use when/Use FIRST).
  - WARN if a scripts/ file is never linked from markdown in its own skill.
  - WARN if a SKILL.md body exceeds 500 lines or 16000 characters (split into
    references/) — the character budget is what actually bounds activation cost.
  - WARN if a references/ file over 100 lines lacks a top-of-file table of contents.
  - Dynamo surface ratchet: a `dynamo: true` skill is served to the agent running
    inside the product, whose whole surface is the MCP tool set plus read/write
    under `Files/`. Its SKILL.md and references/*.md are scanned for instructions
    on a surface Dynamo does not have (`/admin/api`, `sqlcmd`/`Invoke-Sqlcmd`,
    `Invoke-RestMethod`/`Invoke-WebRequest`, fenced powershell/pwsh/bash/sh/sql
    blocks, `git add|commit|push|...`, `dotnet run|build|publish`, `.csproj`,
    `Playwright`, `browser_`), and the per-file count is compared with
    `scripts/dynamo-baseline.json`. A file ABOVE its baseline (a missing entry
    means 0) is an error naming the file, the count, the baseline and the first
    three matching lines; below is fine, so the baseline shrinks as the backlog
    drains. A `scripts/` directory or a `compatibility:` key naming PowerShell in
    a `dynamo: true` skill is always an error, never baselined.
  - Client exclusivity: a `dynamo: true` skill's SKILL.md and references/*.md
    may not carry client-exclusivity wording ("Dynamo only", "Dynamo-only",
    "stops here", "external client stops", "cannot run this skill"), and its
    `compatibility:` frontmatter may not name a client. A skill states a
    precondition and how to test it (`tools/list`); it never tells a client
    to stop because of who it is, and an unmeasured claim never lands as
    instruction. Always an error, never baselined.
    `--update-dynamo-baseline` rewrites the baseline from the current tree.
  - MCP tool names: every backticked snake_case token shaped like a tool name
    must appear in the registry for the MCP version in play or in that file's
    `notTools` allowlist. The registry is per app version —
    `scripts/mcp-tools/<version>.json`, resolved through
    `scripts/mcp-tools/index.json` (`current` + `supported`); an unresolvable
    version falls back to `current`. The flat `scripts/mcp-tools.json` is
    retired and its presence is an error telling the author to move it.
    The error names the file, the line and the closest registered name.
  - `versions.json` (repo root) parses against the one published schema: exactly
    `schema` (1), `worksOn`, `measuredAt`, `policy`; `worksOn` carrying exactly
    `dw`, `swift` and `apps`; each axis exactly `floor` + `measured`, and the
    `dw` axis optionally `ring` (R0-R4) + `tfm` (`net10.0`), the `swift` axis
    optionally `databasePackage` (the portal's database zip name); each app
    `id`/`floor`/`measured`/`required` plus an optional `scope` and an optional
    `predecessors` list (retired package ids the app replaced, never aliases:
    no app may be keyed by one). The `dw` axis and each app may carry a floor
    `reason` (`ref` + `why`) and a `flag` (`untraced`, `no-reason-given`)
    marking what the reason could not settle. `measured` is
    one concrete version (never a range, never `x`); `floor` is a valid range
    (`>=`, `==`, `>`, `~`, `^` or a bare version). Vendor axes only — the file
    never names a distribution or a harness.
  - An optional per-skill `versions:` frontmatter block (axes `dw`, `mcp`,
    `serializer`, `swift`, each `{ floor, measured }`, `dw` also taking
    `ring`/`tfm`) is validated by the same
    rules and may carry no other axis. A skill without the block inherits
    `versions.json`.
  - Version stamps in the body: a version-specific fact ends with one bracketed
    token, `[dw 10.28.11 · mcp 0.6.0]` — axes in the fixed order
    dw · mcp · serializer · swift, ` · ` separated, only the axes that were
    varied, each named once. The `dw` axis may print a hosting ring instead of
    a release, `[dw R1 · mcp 0.6.0]`, for a fact that is true of the ring
    rather than of one build. Every candidate token is found by one regex and
    then checked for order, duplication and version shape. A bare inline
    version number (`10.2x.y`, `0.4.x`, `0.9.x`, `Swift 2.x`) or a bare ring
    (`R0`-`R4`) outside a token,
    a fenced block, a URL or the frontmatter is an ERROR, ratcheted per file
    against `scripts/version-stamp-allowlist.json` the way the Dynamo baseline
    works: a file above its entry fails, below is fine, so the allowlist only
    shrinks. `--update-version-stamp-allowlist` rewrites it from the tree.

Run from anywhere: `python3 scripts/validate-skills.py`. Exit code 0 = clean.
"""
from __future__ import annotations

import difflib
import json
import re
import sys
from pathlib import Path

# A real YAML parser is what the Claude Code skill loader uses to read
# frontmatter. The homegrown parser below is lenient (it never sees the ": "
# nested-mapping trap), so a strict YAML pass is required to catch the class of
# defect where an unquoted `description:` value carries a second ": " (e.g. the
# "… Triggers: …" pattern) and fails to load with "mapping values are not
# allowed here". Import is optional so the other checks still run without it.
try:
    import yaml  # type: ignore
except ImportError:  # pragma: no cover
    yaml = None

# utf-8-sig transparently strips a leading BOM if present, so files authored on
# Windows (UTF-8 with BOM) parse the same as everything else.
ENCODING = "utf-8-sig"
REPO = Path(__file__).resolve().parent.parent
SKILLS_DIR = REPO / "skills"
MARKETPLACE = REPO / ".claude-plugin" / "marketplace.json"

errors: list[str] = []
warnings: list[str] = []

# Hard cap on the activation `description` (frontmatter parsers truncate past this).
DESCRIPTION_MAX = 1024
# Soft budget for a SKILL.md body — past this, split material into references/.
SKILL_BODY_MAX = 500
# The same budget in characters. A line budget alone is gameable: a body of 300
# long table rows costs far more context than 490 short ones, so a SKILL.md can
# sit inside the line budget while injecting three times the tokens. ~16000 chars
# is roughly 4k tokens — the ceiling for something whose job is to be a nav layer.
SKILL_BODY_CHARS_MAX = 16000
# References longer than this should carry a top-of-file TOC (survives partial reads).
REFERENCE_TOC_MIN = 100
# The MCP-dependence axis: required = the skill's steps are MCP tool calls;
# optional = knowledge stands alone, MCP tools are the preferred way to apply it;
# none = pure platform knowledge or an offline flow. Each level pairs with a
# body marker section so the behavioral contract travels with the skill.
MCP_LEVELS = {
    "required": "## MCP preflight",
    "optional": "## Without MCP",
    "none": None,
}
# Substrings that signal double-encoded UTF-8 (mojibake): a UTF-8 byte sequence
# was read as CP1252 and re-encoded. None occur in correct English/code, so a hit
# is reliable. U+FFFD is already-lost data. See CHANGELOG 3.3.7.
MOJIBAKE_MARKERS = (
    "â€",                                # em/en-dash, smart quotes, ellipsis, bullet
    "â†", "â”", "â•", "â‰", "âœ", "â–",   # arrows, box-drawing, math, check/cross marks
    "Â§", "Â·", "Â°", "Â±", "Â»", "Â«",   # Latin-1 punctuation mis-encoded
    "Ã©", "Ã¨", "Ã¢", "Ã ", "Ã¶", "Ã¼",   # accented-letter mojibake
    "�",                            # replacement character (data already lost)
)
# Markdown links: [text](target) — captures the target.
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
# Token-shaped secrets. These are the shapes demo builds actually leak (a
# Dynamicweb Admin API key, an MCP bearer token, any long Bearer literal); none
# occur legitimately in docs or scripts, so every hit is a real leak.
SECRET_RES = (
    re.compile(r"(?i)\b(?:claude|mcp)\.[0-9a-f]{40,}"),
    re.compile(r"Bearer\s+[A-Za-z0-9._~+/-]{40,}"),
)
# Plaintext password assignment inside a script. Values that are a variable,
# env expansion, placeholder, or boolean (EncryptPassword=False) are fine;
# a literal is not. Scripts only — markdown legitimately discusses the pattern.
PASSWORD_RE = re.compile(
    r"(?i)(?:password|pwd)\s*=\s*['\"]?(?!\$|<|%|\{)(?!true\b|false\b)"
    r"[^;'\"\s>]{4,}")
# Environment literals that mark a script as lifted unsanitized from a demo
# build: a hardcoded host:port, a demo-hosting domain, a solutions-tree path.
ENVIRONMENT_LITERAL_RES = (
    re.compile(r"localhost:\d{4,5}"),
    re.compile(r"(?i)\.mydwsite\d*\.com"),
    re.compile(r"(?i)C:\\Projects\\Solutions"),
)
# PowerShell import targets: any quoted path ending in .ps1/.psm1 on an
# Import-Module or dot-source line. The convention is
# `Import-Module (Join-Path $PSScriptRoot '<relative path>')`, so the quoted
# string is the path relative to the importing script's folder.
PS_IMPORT_TARGET_RE = re.compile(r"['\"]([^'\"]+\.psm?1)['\"]")
PS_IMPORT_LINE_RE = re.compile(r"^\s*(?:Import-Module\b|\.\s+\S)")

# --- AV-safe script rules ---------------------------------------------------
# Endpoint protection scores a script on the verbs it co-locates, not on its
# syntax: two harness scripts carrying file upload + admin-account lifecycle +
# arbitrary SQL + a spoofed User-Agent were quarantined and deleted from their
# working trees, while a larger file beside them, with more web-cmdlet calls
# and more TLS bypasses, was untouched. These are the machine-checkable
# clauses of "AV-safe scripts" in dw-skill-authoring ("Shipping scripts").
# Each rule carries an id so the self-test can assert which one fired.
AV_BANNED_RES = (
    ("invoke-expression", re.compile(r"(?i)\bInvoke-Expression\b"),
     "call the cmdlet directly; never build a command as a string"),
    ("add-type", re.compile(r"(?i)\bAdd-Type\b"),
     "compiling inline code is a scored construct; use a cmdlet"),
    ("base64", re.compile(r"(?i)\bFromBase64String\b"),
     "ship the literal, not an encoded payload"),
    ("web-client", re.compile(r"(?i)System\.Net\.WebClient|\bDownloadString\b"),
     "use Invoke-RestMethod / Invoke-WebRequest with named parameters"),
)
# A credential written into the file: a quoted password, a plaintext secure
# string, or a connection string carrying one.
AV_CREDENTIAL_RES = (
    re.compile(r"""(?i)\bpasswords?\s*=\s*['"][^'"]+"""),
    re.compile(r"(?i)ConvertTo-SecureString\b.*-AsPlainText"),
    # A variable (Password=$SqlPassword) is the correct form, not a literal.
    re.compile(r"""(?i)\bServer\s*=[^\n]*;[^\n]*\bPassword\s*="""
               r"""(?!\$|<|%|\{)[^;'"\s]{3,}"""),
)
AV_TLS_RE = re.compile(r"(?i)SkipCertificateCheck")
# The bypass is allowed when the file gates it: an opt-in switch, or a loopback
# base URL. Presence of the token in the file is the machine check; review
# reads the condition.
AV_TLS_GATE_RE = re.compile(r"(?i)AllowSelfSignedCertificate|localhost|127\.0\.0\.1")
AV_UA_RE = re.compile(r"""(?i)(?:['"]?User-Agent['"]?\s*[:=]|-UserAgent\b)""")
AV_WHY_RE = re.compile(r"#\s*why:")
# A small file gives a behavioural engine less to correlate.
AV_LINE_BUDGET = 400


# --- Dynamo surface ratchet -------------------------------------------------
# Dynamo (the in-product agent) can act through the MCP tool set and read/write
# under `Files/`, and through nothing else. Each pattern below is an instruction
# on a surface it does not have. Counted per file and ratcheted against
# DYNAMO_BASELINE so the pre-existing backlog can drain without a flag day.
DYNAMO_BASELINE = REPO / "scripts" / "dynamo-baseline.json"
# The MCP tool registry is per app version. `index.json` names the current
# version and the supported set; `<version>.json` carries that build's tools.
# The flat `scripts/mcp-tools.json` is retired (one-release shim below).
MCP_TOOLS_DIR = REPO / "scripts" / "mcp-tools"
MCP_TOOLS_INDEX = MCP_TOOLS_DIR / "index.json"
MCP_TOOLS_LEGACY = REPO / "scripts" / "mcp-tools.json"
DYNAMO_PATTERNS = (
    ("Management API route", re.compile(r"(?i)/admin/api")),
    ("sqlcmd", re.compile(r"(?i)\bsqlcmd\b")),
    ("Invoke-Sqlcmd", re.compile(r"(?i)\bInvoke-Sqlcmd\b")),
    ("Invoke-RestMethod", re.compile(r"(?i)\bInvoke-RestMethod\b")),
    ("Invoke-WebRequest", re.compile(r"(?i)\bInvoke-WebRequest\b")),
    ("shell/sql fenced block",
     re.compile(r"^\s*```\s*(?:powershell|pwsh|bash|sh|sql)\s*$", re.IGNORECASE)),
    ("git command", re.compile(
        r"(?i)\bgit\s+(?:add|commit|push|pull|clone|checkout|rebase|merge)\b")),
    ("dotnet command", re.compile(r"(?i)\bdotnet\s+(?:run|build|publish)\b")),
    (".csproj", re.compile(r"(?i)\.csproj\b")),
    ("Playwright", re.compile(r"(?i)\bPlaywright\b")),
    ("browser_ tool", re.compile(r"\bbrowser_")),
)
# Client exclusivity. `dynamo:` is a visibility flag, never an exclusivity
# flag: a `dynamo: true` skill runs anywhere an MCP client runs. A skill
# states a precondition and how to test it (`tools/list`); it never tells a
# client to stop because of who it is, and an unmeasured claim never lands as
# instruction. Each phrase below is such a stop instruction. Never baselined.
EXCLUSIVITY_PATTERNS = (
    ("Dynamo only", re.compile(r"(?i)\bDynamo[ -]only\b")),
    ("stops here", re.compile(r"(?i)\bstops here\b")),
    ("external client stops", re.compile(r"(?i)\bexternal client stops\b")),
    ("cannot run this skill", re.compile(r"(?i)\bcannot run this skill\b")),
)
# A `compatibility:` value that names a client asserts who may run the skill
# rather than what runtime it needs.
CLIENT_NAME_RE = re.compile(
    r"(?i)\b(?:Dynamo|Claude(?: Code)?|Codex|Cursor|Copilot|Windsurf|Cline|"
    r"Gemini|MCP client|external client|in-product)\b")


def dynamo_skills() -> list[Path]:
    """Every skill folder whose SKILL.md declares `dynamo: true`."""
    out: list[Path] = []
    for skill_dir in sorted(SKILLS_DIR.iterdir()):
        md = skill_dir / "SKILL.md"
        if not md.is_file():
            continue
        text = read_text_checked(md)
        if text is None:
            continue
        if parse_frontmatter(text).get("dynamo", "").strip().lower() == "true":
            out.append(skill_dir)
    return out


def dynamo_scan_files(skill_dir: Path) -> list[Path]:
    """The files a `dynamo: true` skill ships to the in-product agent."""
    files = [skill_dir / "SKILL.md"]
    files += sorted((skill_dir / "references").glob("*.md"))
    return [f for f in files if f.is_file()]


def dynamo_violations(f: Path) -> list[tuple[int, str, str]]:
    """(line number, pattern label, line text) for every non-MCP instruction."""
    text = read_text_checked(f)
    if text is None:
        return []
    hits: list[tuple[int, str, str]] = []
    for i, line in enumerate(text.splitlines(), 1):
        for label, rx in DYNAMO_PATTERNS:
            if rx.search(line):
                hits.append((i, label, line.strip()))
                break
    return hits


def dynamo_key(f: Path) -> str:
    return rel(f).replace("\\", "/")


def dynamo_counts() -> dict[str, int]:
    """Per-file violation counts across every `dynamo: true` skill."""
    counts: dict[str, int] = {}
    for skill_dir in dynamo_skills():
        for f in dynamo_scan_files(skill_dir):
            n = len(dynamo_violations(f))
            if n:
                counts[dynamo_key(f)] = n
    return counts


def check_dynamo_surface() -> None:
    baseline: dict[str, int] = {}
    if DYNAMO_BASELINE.is_file():
        try:
            baseline = json.loads(DYNAMO_BASELINE.read_text(encoding=ENCODING))
        except json.JSONDecodeError as e:
            err(f"{rel(DYNAMO_BASELINE)}: invalid JSON ({e})")
            return
    else:
        warn(f"{rel(DYNAMO_BASELINE)} is missing — every baseline reads as 0")

    for skill_dir in dynamo_skills():
        skill = skill_dir.name
        # Always an error, never baselined: a skill Dynamo can act on cannot
        # ship executables, and cannot require a shell to be useful.
        if (skill_dir / "scripts").is_dir():
            err(f"{skill}: `dynamo: true` but ships a scripts/ directory — "
                "Dynamo has no shell; flip to `dynamo: false` or move the script")
        compat = parse_frontmatter(
            read_text_checked(skill_dir / "SKILL.md") or "").get("compatibility", "")
        if re.search(r"(?i)powershell", compat):
            err(f"{skill}: `dynamo: true` with `compatibility: {compat.strip()}` — "
                "a PowerShell requirement cannot be true of an in-product skill")
        for f in dynamo_scan_files(skill_dir):
            hits = dynamo_violations(f)
            key = dynamo_key(f)
            allowed = baseline.get(key, 0)
            if len(hits) > allowed:
                first = "; ".join(f"L{n} [{label}] {line[:80]}"
                                  for n, label, line in hits[:3])
                err(f"{key}: {len(hits)} non-MCP instruction(s) in a `dynamo: true` "
                    f"skill, baseline {allowed} — Dynamo's surface is the MCP tools "
                    f"plus read/write under `Files/`. First: {first}")


def exclusivity_hits(f: Path) -> list[tuple[int, str, str]]:
    """(line number, pattern label, line text) for every stop-by-client phrase."""
    text = read_text_checked(f)
    if text is None:
        return []
    hits: list[tuple[int, str, str]] = []
    for i, line in enumerate(text.splitlines(), 1):
        for label, rx in EXCLUSIVITY_PATTERNS:
            if rx.search(line):
                hits.append((i, label, line.strip()))
                break
    return hits


def check_dynamo_exclusivity() -> None:
    """A `dynamo: true` skill never tells a client to stop because of who it is."""
    for skill_dir in dynamo_skills():
        skill = skill_dir.name
        compat = parse_frontmatter(
            read_text_checked(skill_dir / "SKILL.md") or "").get("compatibility", "")
        m = CLIENT_NAME_RE.search(compat)
        if m:
            err(f"{skill}: `dynamo: true` with `compatibility: {compat.strip()}` names "
                f"a client ({m.group(0)}): `dynamo:` is a visibility flag, never an "
                "exclusivity flag; `compatibility:` declares a runtime, not who may run "
                "the skill")
        for f in dynamo_scan_files(skill_dir):
            for n, label, line in exclusivity_hits(f):
                err(f"{dynamo_key(f)}:L{n}: client-exclusivity wording [{label}] in a "
                    f"`dynamo: true` skill: state the precondition and how to test it "
                    f"(`tools/list`), never who may run it: {line[:80]}")


# ---------------------------------------------------------------- MCP tools
# A backticked snake_case token in a skill reads as an MCP tool name, and a
# name that no server registers is a step the agent cannot execute. Every such
# token must resolve in scripts/mcp-tools.json (the merged registered tool set)
# or be listed in that file's `notTools` escape for prose that only looks like
# a tool name (PowerShell parameters, SQL columns, config keys, file stems).
TOOL_SHAPE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$")
INLINE_CODE = re.compile("`([^`\n]{2,120})`")


def mcp_registry_path() -> Path | None:
    """The registry file for the MCP version in play.

    Resolution order: the version `versions.json` says the corpus was measured
    on, else `index.json.current`; a version with no file on disk falls back to
    `current` with a warning, so a new supported version cannot silently
    disable the check.
    """
    # One-release shim: the flat registry moved under scripts/mcp-tools/.
    if MCP_TOOLS_LEGACY.is_file():
        err(f"{rel(MCP_TOOLS_LEGACY)} is retired — move it to "
            f"scripts/mcp-tools/<mcp version>.json and list the version in "
            f"scripts/mcp-tools/index.json")
        return None
    if not MCP_TOOLS_INDEX.is_file():
        err(f"{rel(MCP_TOOLS_INDEX)} is missing — tool names cannot be validated")
        return None
    try:
        index = json.loads(MCP_TOOLS_INDEX.read_text(encoding=ENCODING))
    except json.JSONDecodeError as e:
        err(f"{rel(MCP_TOOLS_INDEX)}: invalid JSON ({e})")
        return None
    current = index.get("current")
    supported = index.get("supported")
    if not isinstance(current, str) or not current:
        err(f"{rel(MCP_TOOLS_INDEX)}: `current` must be a version string")
        return None
    if not isinstance(supported, list) or current not in supported:
        err(f"{rel(MCP_TOOLS_INDEX)}: `supported` must be an array listing "
            f"`current` ({current})")
        return None
    for version in supported:
        if not (MCP_TOOLS_DIR / f"{version}.json").is_file():
            err(f"{rel(MCP_TOOLS_INDEX)}: supported version {version} has no "
                f"scripts/mcp-tools/{version}.json")
    wanted = works_on_mcp_version() or current
    path = MCP_TOOLS_DIR / f"{wanted}.json"
    if not path.is_file():
        warn(f"no scripts/mcp-tools/{wanted}.json — falling back to the "
             f"current registry ({current})")
        path = MCP_TOOLS_DIR / f"{current}.json"
    return path if path.is_file() else None


def mcp_registry() -> tuple[set[str], set[str], Path] | None:
    path = mcp_registry_path()
    if path is None:
        return None
    try:
        doc = json.loads(path.read_text(encoding=ENCODING))
    except json.JSONDecodeError as e:
        err(f"{rel(path)}: invalid JSON ({e})")
        return None
    return set(doc.get("tools", {})), set(doc.get("notTools", [])), path


def tool_tokens(line: str) -> list[str]:
    """Every backticked token in `line` shaped like an MCP tool name.

    A span is a candidate when its leading identifier is snake_case and the
    rest of the span is empty or an argument list — `save_pages`,
    `save_pages(pages)`, `get_row_definitions(areaId)`. A span carrying an
    operator, a path separator or prose is not a tool citation.
    """
    out: list[str] = []
    for span in INLINE_CODE.findall(line):
        head = span.split("(", 1)[0].strip()
        rest = span[len(span.split("(", 1)[0]):].strip()
        if rest and not (rest.startswith("(") and rest.endswith(")")):
            continue
        if TOOL_SHAPE.match(head):
            out.append(head)
    return out


def check_mcp_tool_names() -> None:
    reg = mcp_registry()
    if reg is None:
        return
    registered, not_tools, registry_path = reg
    for f in scan_files():
        text = read_text_checked(f)
        if text is None:
            continue
        fenced = False
        for i, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("```"):
                fenced = not fenced
                continue
            if fenced:
                continue
            for name in tool_tokens(line):
                if name in registered or name in not_tools:
                    continue
                near = difflib.get_close_matches(name, registered, n=1, cutoff=0.72)
                hint = (f"closest registered name is `{near[0]}`" if near
                        else "no registered name is close; say plainly that the "
                             "operation is not on MCP and name the admin screen "
                             "(in-product) or the dw-data-access recipe (outside)")
                err(f"{rel(f)}:{i}: `{name}` is not a registered MCP tool — {hint}. "
                    f"Add it to notTools in {rel(registry_path)} if it is not "
                    f"a tool name.")


def write_dynamo_baseline() -> int:
    counts = dynamo_counts()
    DYNAMO_BASELINE.write_text(
        json.dumps(dict(sorted(counts.items())), indent=2) + "\n", encoding="utf-8")
    print(f"wrote {rel(DYNAMO_BASELINE)}: {len(counts)} file(s), "
          f"{sum(counts.values())} violation(s)")
    return 0


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def parse_frontmatter(text: str) -> dict[str, str]:
    """Minimal YAML frontmatter parser for flat `key: value` pairs and `>`/`|`
    block scalars (folded multi-line values are joined into one string)."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    fields: dict[str, str] = {}
    lines = m.group(1).splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if ":" in line and not line.startswith((" ", "\t")):
            key, _, value = line.partition(":")
            key, value = key.strip(), value.strip()
            if value in (">", "|", ">-", "|-", ">+", "|+"):
                # Block scalar: collect indented (or blank) continuation lines.
                block: list[str] = []
                i += 1
                while i < len(lines) and (
                    lines[i].startswith((" ", "\t")) or not lines[i].strip()
                ):
                    block.append(lines[i].strip())
                    i += 1
                fields[key] = " ".join(b for b in block if b).strip()
                continue
            fields[key] = value
        i += 1
    return fields


def rel(p: Path) -> str:
    return str(p.relative_to(REPO))


def check_marketplace() -> list[str]:
    if not MARKETPLACE.exists():
        err(f"missing {rel(MARKETPLACE)}")
        return []
    try:
        data = json.loads(MARKETPLACE.read_text(encoding=ENCODING))
    except json.JSONDecodeError as e:
        err(f"{rel(MARKETPLACE)} does not parse: {e}")
        return []
    # Top-level schema the Claude Code loader requires: name (string),
    # owner (object), plugins (array). description/version live under metadata.
    if not isinstance(data.get("name"), str):
        err(f"{rel(MARKETPLACE)}: top-level `name` must be a string")
    if not isinstance(data.get("owner"), dict):
        err(f"{rel(MARKETPLACE)}: top-level `owner` must be an object")
    elif not data["owner"].get("name"):
        err(f"{rel(MARKETPLACE)}: `owner.name` is required")
    if not isinstance(data.get("plugins"), list):
        err(f"{rel(MARKETPLACE)}: top-level `plugins` must be an array")

    referenced: list[str] = []
    for plugin in data.get("plugins", []):
        # Every entry needs a source so Claude Code knows where to fetch files;
        # a bare skills list with no source does not install.
        if "source" not in plugin:
            err(f"marketplace plugin '{plugin.get('name')}' has no `source`")
        for skill_path in plugin.get("skills", []):
            referenced.append(skill_path)
            # Skill paths are resolved relative to the source root and may carry
            # a leading "./"; normalise before checking they exist on disk.
            local = skill_path[2:] if skill_path.startswith("./") else skill_path
            if not (REPO / local).is_dir():
                err(f"marketplace plugin '{plugin.get('name')}' references missing "
                    f"skill path: {skill_path}")
    return referenced


def check_skills() -> None:
    for skill_md in sorted(SKILLS_DIR.glob("*/SKILL.md")):
        folder = skill_md.parent.name
        text = skill_md.read_text(encoding=ENCODING)
        fm = parse_frontmatter(text)
        name = fm.get("name")
        if not name:
            err(f"{rel(skill_md)}: frontmatter missing `name`")
        elif name != folder:
            err(f"{rel(skill_md)}: name '{name}' != folder '{folder}'")
        desc = fm.get("description")
        if not desc:
            err(f"{rel(skill_md)}: frontmatter missing `description`")
        else:
            if len(desc) > DESCRIPTION_MAX:
                err(f"{rel(skill_md)}: description is {len(desc)} chars "
                    f"(max {DESCRIPTION_MAX}) — trim it")
            if not re.search(r"Triggers:|Use when|Use FIRST|Use AFTER", desc):
                warn(f"{rel(skill_md)}: description lacks a trigger signal "
                     "(Triggers:/Use when/Use FIRST)")
        body = FRONTMATTER_RE.sub("", text, count=1)
        # MCP-dependence declaration + matching body marker. The marker section
        # is what actually steers behavior at runtime (preflight/fallback), so
        # the field and the section are validated as a pair.
        mcp = fm.get("mcp")
        if mcp not in MCP_LEVELS:
            err(f"{rel(skill_md)}: frontmatter `mcp` must be one of "
                f"{sorted(MCP_LEVELS)} (got {mcp!r})")
        else:
            marker = MCP_LEVELS[mcp]
            if marker and marker not in body:
                err(f"{rel(skill_md)}: mcp: {mcp} requires a `{marker}` "
                    "section in the body")
            for level, other in MCP_LEVELS.items():
                if other and level != mcp and other in body:
                    err(f"{rel(skill_md)}: body has a `{other}` section but "
                        f"frontmatter says mcp: {mcp} — make them agree")
        # Dynamo visibility. Dynamo serves manifest.json to in-product
        # admins, so a skill whose steps need a surface Dynamo does not
        # have (shell, SQL, git, a browser, csproj) declares
        # `dynamo: false` and is left out of the manifest. Orthogonal to
        # `mcp:` — a demo scaffold is mcp: required yet dynamo: false,
        # and dw-render-razor is mcp: none yet dynamo: true.
        dynamo = fm.get("dynamo")
        if dynamo not in ("true", "false"):
            err(f"{rel(skill_md)}: frontmatter `dynamo` must be true or "
                f"false (got {dynamo!r})")
        # Soft budgets on the body (frontmatter stripped): past either, the body
        # is doing reference work that belongs in references/. Both are reported
        # because they catch different shapes of the same defect — many short
        # lines trips the line budget, few long ones trips the character budget.
        body_lines = len(body.splitlines())
        if body_lines > SKILL_BODY_MAX:
            warn(f"{rel(skill_md)}: body is {body_lines} lines "
                 f"(>{SKILL_BODY_MAX}) — split material into references/")
        body_chars = len(body)
        if body_chars > SKILL_BODY_CHARS_MAX:
            warn(f"{rel(skill_md)}: body is {body_chars} chars "
                 f"(>{SKILL_BODY_CHARS_MAX}, ~{body_chars // 4000}k tokens on "
                 "activation) — split material into references/")


def check_frontmatter_yaml() -> None:
    # Strict YAML pass over every SKILL.md frontmatter — this is what the loader
    # does. A plain (unquoted) scalar value containing ": " parses as a nested
    # mapping and blows up ("mapping values are not allowed here"); quoting the
    # value fixes it. Require a mapping carrying both `name` and `description`.
    for skill_md in sorted(SKILLS_DIR.glob("*/SKILL.md")):
        text = skill_md.read_text(encoding=ENCODING)
        m = FRONTMATTER_RE.match(text)
        if not m:
            err(f"{rel(skill_md)}: no YAML frontmatter block at top of file")
            continue
        block = m.group(1)
        if yaml is not None:
            try:
                data = yaml.safe_load(block)
            except yaml.YAMLError as e:  # type: ignore[union-attr]
                first = str(e).splitlines()[0]
                err(f"{rel(skill_md)}: frontmatter is not valid YAML ({first}) "
                    "— quote any value containing ': '")
                continue
            if not isinstance(data, dict):
                err(f"{rel(skill_md)}: frontmatter must be a YAML mapping")
                continue
            if not data.get("name"):
                err(f"{rel(skill_md)}: frontmatter YAML missing `name`")
            if not data.get("description"):
                err(f"{rel(skill_md)}: frontmatter YAML missing `description`")
        else:
            # Fallback when PyYAML is unavailable: flag the exact defect class —
            # an unquoted top-level value that contains a second ": ".
            for line in block.splitlines():
                if line.startswith((" ", "\t")) or ":" not in line:
                    continue
                key, _, value = line.partition(":")
                value = value.strip()
                if value[:1] in ("'", '"', ">", "|", ""):
                    continue
                if ": " in value:
                    err(f"{rel(skill_md)}: frontmatter `{key.strip()}` value "
                        "contains an unquoted ': ' (invalid YAML — quote it)")


def check_links() -> None:
    for md in sorted(SKILLS_DIR.rglob("*.md")):
        text = md.read_text(encoding=ENCODING)
        for target in LINK_RE.findall(text):
            target = target.strip()
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            # Real relative paths have no whitespace or quotes; anything that does
            # is link-like syntax inside a code/PowerShell snippet, not a file link.
            if any(c in target for c in ' "\'\t'):
                continue
            path_part = target.split("#", 1)[0].split("?", 1)[0]
            if not path_part:
                continue
            resolved = (md.parent / path_part).resolve()
            if not resolved.exists():
                err(f"{rel(md)}: broken link -> {target}")


def scan_files() -> list[Path]:
    """Every markdown file under skills/ plus every file under a skill's
    scripts/ folder — the set the encoding and secret checks cover."""
    files = set(SKILLS_DIR.rglob("*.md"))
    for scripts_dir in SKILLS_DIR.glob("*/scripts"):
        files.update(f for f in scripts_dir.rglob("*") if f.is_file())
    return sorted(files)


def script_files() -> list[tuple[str, Path]]:
    """(skill name, file) for every file under a skill's scripts/ folder."""
    out: list[tuple[str, Path]] = []
    for scripts_dir in sorted(SKILLS_DIR.glob("*/scripts")):
        for f in sorted(scripts_dir.rglob("*")):
            if f.is_file():
                out.append((scripts_dir.parent.name, f))
    return out


def read_text_checked(f: Path) -> str | None:
    try:
        return f.read_text(encoding=ENCODING)
    except UnicodeDecodeError:
        err(f"{rel(f)}: not valid UTF-8")
        return None


def check_no_bom() -> None:
    # A leading UTF-8 BOM (EF BB BF) before the opening `---` defeats some YAML
    # frontmatter parsers, so name/description go unread and the skill fails to
    # load. In a script it can break shebang/`#Requires` handling the same way.
    # Read raw bytes — utf-8-sig used elsewhere would silently hide it.
    for f in scan_files():
        if f.read_bytes()[:3] == b"\xef\xbb\xbf":
            err(f"{rel(f)}: starts with a UTF-8 BOM (strip it)")


def check_reference_tocs() -> None:
    # A long reference may be only partially read when reached from a SKILL.md
    # link, so a top-of-file TOC is what survives to map the rest of the file.
    # rglob, not glob: references/ has nested folders (e.g. references/foundational/),
    # and a plain one-level glob skipped their files entirely — the largest
    # references in the repo were exempt from the TOC rule by accident.
    toc_re = re.compile(r"^#{2,}\s+(Contents|Table of [Cc]ontents)\b", re.MULTILINE)
    for md in sorted(SKILLS_DIR.rglob("references/**/*.md")):
        lines = md.read_text(encoding=ENCODING).splitlines()
        if len(lines) <= REFERENCE_TOC_MIN:
            continue
        head = "\n".join(lines[:15])
        if not toc_re.search(head):
            warn(f"{rel(md)}: {len(lines)} lines but no top-of-file table of "
                 "contents (add a `## Contents` block)")


def check_bundle_closure() -> None:
    # Bundles install only their own `skills` list. A relative link from a
    # bundled skill into a skill folder the bundle does not ship dangles at
    # install time — the whole-repo link check above cannot see this. This also
    # enforces the foundational->demo boundary wherever it matters: a
    # foundational skill linking dw-demo-* fails here for every bundle that
    # ships the foundational skill without the demo chain.
    if not MARKETPLACE.exists():
        return
    try:
        data = json.loads(MARKETPLACE.read_text(encoding=ENCODING))
    except json.JSONDecodeError:
        return  # already reported by check_marketplace
    for plugin in data.get("plugins", []):
        shipped = {Path(p).name for p in plugin.get("skills", [])}
        for skill in sorted(shipped):
            skill_dir = SKILLS_DIR / skill
            for md in sorted(skill_dir.rglob("*.md")):
                text = md.read_text(encoding=ENCODING)
                for target in LINK_RE.findall(text):
                    target = target.strip()
                    if target.startswith(("http://", "https://", "#", "mailto:")):
                        continue
                    if any(c in target for c in ' "\'\t'):
                        continue
                    path_part = target.split("#", 1)[0].split("?", 1)[0]
                    if not path_part:
                        continue
                    resolved = (md.parent / path_part).resolve()
                    try:
                        parts = resolved.relative_to(SKILLS_DIR).parts
                    except ValueError:
                        continue  # not under skills/
                    if not parts:
                        continue
                    target_skill = parts[0]
                    # A bare pointer to another skill (its folder or SKILL.md)
                    # is soft routing and fine to dangle; a link into another
                    # skill's references/, assets/, or scripts/ is a hard
                    # content dependency.
                    hard = len(parts) > 1 and parts[1] in (
                        "references", "assets", "scripts")
                    if hard and target_skill != skill and target_skill not in shipped:
                        err(f"bundle '{plugin.get('name')}': {rel(md)} depends on "
                            f"content in '{target_skill}', which the bundle does "
                            f"not ship -> {target}")


def check_no_mojibake() -> None:
    # Double-encoded UTF-8 most often re-enters via a fold-back pasted from a
    # mis-decoded source. Catch it at the door. See CHANGELOG 3.3.7.
    # Covers scripts too: a shipped detector must build its own marker strings
    # from code points ([char]0xFFFD), never literals, or it trips this check.
    for f in scan_files():
        text = read_text_checked(f)
        if text is None:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            for marker in MOJIBAKE_MARKERS:
                if marker in line:
                    err(f"{rel(f)}:{i}: double-encoded UTF-8 (mojibake) "
                        f"near '{marker}' — repair the file's encoding")
                    break  # one report per line is enough


def check_no_secrets() -> None:
    # A credential that ships in the plugin is compromised on publish. The
    # token shapes are checked everywhere under skills/ (markdown included);
    # the password-assignment shape only inside scripts/, where markdown's
    # legitimate discussion of the pattern (EncryptPassword=False, example
    # env vars) cannot false-positive.
    scripts = {f for _, f in script_files()}
    for f in scan_files():
        text = read_text_checked(f)
        if text is None:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            for secret_re in SECRET_RES:
                if secret_re.search(line):
                    err(f"{rel(f)}:{i}: token-shaped secret — replace with an "
                        "$env: lookup or a parameter")
                    break
            else:
                if f in scripts and PASSWORD_RE.search(line):
                    err(f"{rel(f)}:{i}: plaintext password assignment — take "
                        "it from a parameter or the environment")


def check_no_environment_literals() -> None:
    # A hardcoded host:port, demo-hosting domain, or solutions-tree path marks
    # a script lifted unsanitized from a demo build. Connection discovery is
    # parameter > $env:DW_* > launchSettings.json > fail — never a literal.
    for skill, f in script_files():
        text = read_text_checked(f)
        if text is None:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            for lit_re in ENVIRONMENT_LITERAL_RES:
                m = lit_re.search(line)
                if m:
                    err(f"{rel(f)}:{i}: environment literal '{m.group(0)}' — "
                        "make it a parameter or discover it (see the script "
                        "contract in dw-skill-authoring)")
                    break


def check_script_contract() -> None:
    # The machine-checkable half of the script contract in dw-skill-authoring
    # ("Shipping scripts"): an actionable header, an explicit parameter block,
    # and the runtime pinned. Review enforces the rest.
    runtimes_by_skill: dict[str, set[str]] = {}
    for skill, f in script_files():
        ext = f.suffix.lower()
        if ext in (".ps1", ".psm1"):
            runtimes_by_skill.setdefault(skill, set()).add("PowerShell")
        elif ext == ".py":
            runtimes_by_skill.setdefault(skill, set()).add("Python")
        else:
            continue  # .sql etc. ride along with the invoking script
        text = read_text_checked(f)
        if text is None:
            continue
        if ext in (".ps1", ".psm1"):
            # After the help block, not before it: a leading #Requires breaks
            # Get-Help's binding of comment-based help.
            if not re.search(r"(?m)^#Requires -Version 7\.0\b", text):
                err(f"{rel(f)}: no `#Requires -Version 7.0` line (place it "
                    "right after the help block; PowerShell 7 is a preflight "
                    "prerequisite and scripts never branch on the version)")
            for section in (".SYNOPSIS", ".DESCRIPTION"):
                if section not in text:
                    err(f"{rel(f)}: comment-based help lacks `{section}`")
            if ".EXAMPLE" not in text:
                warn(f"{rel(f)}: comment-based help lacks an `.EXAMPLE`")
            if not re.search(r"(?m)^\s*param\s*\(", text):
                err(f"{rel(f)}: no explicit param() block")
            m = re.search(r"\.SYNOPSIS\s*\n\s*(\S[^\n]*)", text)
            if m and not re.match(r"READ-ONLY\.|WRITES:", m.group(1)):
                err(f"{rel(f)}: .SYNOPSIS must open with `READ-ONLY.` or "
                    f"`WRITES: <what>.` (got: {m.group(1)[:60]!r})")
        elif ext == ".py":
            head = "\n".join(text.splitlines()[:10])
            if '"""' not in head and "'''" not in head:
                err(f"{rel(f)}: no module docstring in the first 10 lines "
                    "(the header contract)")
            if "argparse" not in text:
                warn(f"{rel(f)}: no argparse — `--help` should render the "
                     "header")
    # Every runtime a skill's scripts need is declared in its frontmatter.
    for skill, runtimes in sorted(runtimes_by_skill.items()):
        skill_md = SKILLS_DIR / skill / "SKILL.md"
        compat = ""
        if skill_md.exists():
            compat = parse_frontmatter(
                skill_md.read_text(encoding=ENCODING)).get("compatibility", "")
        for runtime in sorted(runtimes):
            if runtime.lower() not in compat.lower():
                err(f"{rel(skill_md)}: ships {runtime} scripts but "
                    f"`compatibility:` frontmatter does not declare {runtime} "
                    "(e.g. `compatibility: Requires PowerShell 7.x`)")


def av_code_lines(text: str) -> list[tuple[int, str, str]]:
    """(line number, code with comments stripped, raw line) for one file.

    The rules below score code, not prose: a help block naming
    -AllowSelfSignedCertificate, or a comment saying never to use
    Invoke-Expression, is documentation and must not fail the file.
    """
    out: list[tuple[int, str, str]] = []
    in_block = False
    for i, raw in enumerate(text.splitlines(), 1):
        code = raw
        if in_block:
            end = code.find("#>")
            if end < 0:
                out.append((i, "", raw))
                continue
            code, in_block = code[end + 2:], False
        while "<#" in code:
            start = code.index("<#")
            end = code.find("#>", start + 2)
            if end < 0:
                code, in_block = code[:start], True
                break
            code = code[:start] + code[end + 2:]
        out.append((i, code.split("#", 1)[0], raw))
    return out


def av_violations(text: str) -> list[tuple[int | None, str, str, str]]:
    """(line or None, severity, rule id, message) for one PowerShell file."""
    out: list[tuple[int | None, str, str, str]] = []
    lines = av_code_lines(text)
    tls_gated = bool(AV_TLS_GATE_RE.search(text))
    for idx, (i, code, raw) in enumerate(lines):
        if not code.strip():
            continue
        for rule, pattern, fix in AV_BANNED_RES:
            if pattern.search(code):
                out.append((i, "error", rule,
                            f"banned construct ({rule}) - {fix}"))
        for pattern in AV_CREDENTIAL_RES:
            if pattern.search(code):
                out.append((i, "error", "credential",
                            "credential literal - read it from $env: or take it "
                            "as a parameter, and mask it in every log line"))
                break
        if AV_TLS_RE.search(code) and not tls_gated:
            out.append((i, "error", "tls-ungated",
                        "ungated TLS bypass - gate it on a loopback base URL or "
                        "an -AllowSelfSignedCertificate switch"))
        if AV_UA_RE.search(code):
            prev = lines[idx - 1][2] if idx else ""
            if not (AV_WHY_RE.search(raw) or AV_WHY_RE.search(prev)):
                out.append((i, "error", "user-agent",
                            "User-Agent set without a `# why:` comment naming "
                            "the protocol reason - an undocumented browser UA "
                            "reads as evasion"))
    if len(lines) > AV_LINE_BUDGET:
        out.append((None, "warn", "size",
                    f"{len(lines)} lines, past the {AV_LINE_BUDGET}-line budget "
                    "- split by capability (read and assert in one file, each "
                    "write family in its own)"))
    return out


def check_av_safe_scripts() -> None:
    for _, f in script_files():
        if f.suffix.lower() not in (".ps1", ".psm1"):
            continue
        text = read_text_checked(f)
        if text is None:
            continue
        for line, severity, _rule, msg in av_violations(text):
            where = f"{rel(f)}:{line}" if line else rel(f)
            (err if severity == "error" else warn)(f"{where}: {msg}")


def run_av_self_test() -> int:
    """Prove the AV rules fire: every rule id must hit the fixture, and the
    fixture must produce errors (the real tree is checked by a normal run)."""
    fixture = REPO / "scripts" / "tests" / "fixtures" / "av-nonconforming"
    expected = {rule for rule, _, _ in AV_BANNED_RES} | {
        "credential", "tls-ungated", "user-agent", "size"}
    seen: set[str] = set()
    failures = 0
    for f in sorted(fixture.rglob("*.ps1")) + sorted(fixture.rglob("*.psm1")):
        found = av_violations(f.read_text(encoding=ENCODING))
        # The size rule needs a file past the budget; assert it on generated
        # text rather than padding the fixture with 400 filler lines.
        found += av_violations("\n".join(["$x = 1"] * (AV_LINE_BUDGET + 1)))
        for line, severity, rule, msg in found:
            seen.add(rule)
            print(f"  {severity.upper():5} {f.name}:{line or '-'} [{rule}] {msg}")
        if not any(s == "error" for _, s, _, _ in found):
            print(f"FAIL {rel(f)}: expected errors, got none")
            failures += 1
    missing = sorted(expected - seen)
    if missing:
        print(f"FAIL rules that never fired: {', '.join(missing)}")
        failures += 1
    clean = REPO / "skills" / "dw-data-access" / "scripts" / "Dw.Api.psm1"
    if clean.is_file():
        conforming = [v for v in av_violations(clean.read_text(encoding=ENCODING))
                      if v[1] == "error"]
        if conforming:
            print(f"FAIL {rel(clean)}: a conforming script must not error: "
                  f"{conforming}")
            failures += 1
    print("self-test FAILED" if failures else
          f"self-test OK - {len(expected)} rule(s) fired on the fixture")
    return 1 if failures else 0


def check_script_imports() -> None:
    # Import-Module / dot-source targets must resolve on disk, and a cross-skill
    # import is a hard dependency: every bundle that ships the consumer must
    # ship the provider, same as a markdown link into references/.
    bundles: list[tuple[str, set[str]]] = []
    if MARKETPLACE.exists():
        try:
            data = json.loads(MARKETPLACE.read_text(encoding=ENCODING))
            for plugin in data.get("plugins", []):
                bundles.append((plugin.get("name", "?"),
                                {Path(p).name for p in plugin.get("skills", [])}))
        except json.JSONDecodeError:
            pass  # already reported by check_marketplace
    for skill, f in script_files():
        if f.suffix.lower() not in (".ps1", ".psm1"):
            continue
        text = read_text_checked(f)
        if text is None:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if not PS_IMPORT_LINE_RE.match(line):
                continue
            for target in PS_IMPORT_TARGET_RE.findall(line):
                resolved = (f.parent / target).resolve()
                if not resolved.exists():
                    err(f"{rel(f)}:{i}: import target does not resolve -> "
                        f"{target}")
                    continue
                try:
                    parts = resolved.relative_to(SKILLS_DIR).parts
                except ValueError:
                    err(f"{rel(f)}:{i}: import escapes skills/ -> {target}")
                    continue
                target_skill = parts[0]
                if target_skill == skill:
                    continue
                for bundle_name, shipped in bundles:
                    if skill in shipped and target_skill not in shipped:
                        err(f"bundle '{bundle_name}': {rel(f)}:{i} imports "
                            f"from '{target_skill}', which the bundle does "
                            f"not ship -> {target}")


def check_orphan_scripts() -> None:
    # A script nothing links to is invisible at activation time: the contract
    # wants a `## Scripts (scripts/)` table row in SKILL.md (a markdown link,
    # so check_links proves the file exists) plus the owning reference.
    for skill, f in script_files():
        skill_dir = SKILLS_DIR / skill
        name = f.name
        if not any(name in md.read_text(encoding=ENCODING)
                   for md in skill_dir.rglob("*.md")):
            warn(f"{rel(f)}: not mentioned by any markdown in '{skill}' — "
                 "add it to the `## Scripts (scripts/)` table")


# ------------------------------------------------------------ version spine
# One vendor compatibility statement for the whole corpus, plus an optional
# per-skill override and a per-fact stamp token. The three rules below are the
# machine-readable half of "which versions was this proven on".
VERSIONS_FILE = REPO / "versions.json"
STAMP_ALLOWLIST = REPO / "scripts" / "version-stamp-allowlist.json"

# The axes a stamp token and a per-skill `versions:` block may name, in the
# fixed order a token prints them.
STAMP_AXES = ("dw", "mcp", "serializer", "swift")
# Keys the `dw` axis may carry beyond `floor` + `measured`. Outward
# compatibility is claimed against the hosting ring, so the ring and the
# framework it served travel with the release number.
DW_AXIS_EXTRAS = frozenset({"ring", "tfm", "reason", "flag"})
# Why a floor sits where it does: `ref` names the issue or PR the floor
# depends on, `why` says what the dependency is. `flag` marks what the reason
# could not settle: `untraced` (no issue or PR), `no-reason-given` (the ref
# exists but names no dependency). A floor without a real dependency says so
# through the flag instead of an invented reason.
FLOOR_FLAGS = frozenset({"untraced", "no-reason-given"})
# `measured` is exactly one concrete version: never a range, never an `x`.
MEASURED_RE = re.compile(r"^\d+(?:\.\d+){1,3}(?:-[0-9A-Za-z][0-9A-Za-z.]*)?$")
# `floor` is a compatibility claim: a comparator (or nothing) plus a version.
# `==` is how a latest-only axis (Swift) states it.
FLOOR_RE = re.compile(
    r"^(?:>=|<=|==|>|<|~|\^)?\d+(?:\.\d+){0,3}(?:-[0-9A-Za-z][0-9A-Za-z.]*)?$")
ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# The Dynamicweb hosting ring a compat claim was proven on. R0 is the current
# milestone under its 30-day soak (demo, test and local dev only); R1 is
# current, R2 current+1, R3 current+2, R4 current+3.
RING_RE = re.compile(r"^R[0-4]$")
# The target framework moniker the ring served that release on.
TFM_RE = re.compile(r"^net\d+\.\d+$")
# The Swift database package name on the downloads portal, stated in full because the
# portal changed its own pattern between releases (swift2.2.0-20260129-database.zip,
# swift-2.4.0-20260702-database.zip): a date stamp alone cannot rebuild it.
DB_PACKAGE_RE = re.compile(r"^swift-?(\d+(?:\.\d+){1,3})-\d{8}-database\.zip$")
SWIFT_AXIS_EXTRAS = frozenset({"databasePackage"})

# One regex finds every candidate stamp token; the contents are then checked
# for axis order, duplication and version shape.
STAMP_TOKEN_RE = re.compile(r"\[((?:dw|mcp|serializer|swift) [^\]\n]*)\]")
# A bare inline version number: the shapes this corpus actually carries, plus
# the hosting ring - a ring is a compat claim the same way a version is, so it
# belongs in a stamp token too.
BARE_VERSION_RE = re.compile(
    r"10\.2\d\.\d+|0\.4\.\d|0\.9\.\d|Swift 2\.\d|\bR[0-4]\b")
URL_RE = re.compile(r"(?:https?://|www\.)\S+")


def check_axis(where: str, axis: str, value: object,
               optional: frozenset[str] = frozenset()) -> None:
    """`{ floor, measured }` for one axis, with both fields well-formed.

    The `dw` axis may also carry `ring` and `tfm`: the hosting ring the claim
    was proven on and the framework that ring served it on. Both are passed in
    through `optional`, so no other axis gains them.
    """
    if not isinstance(value, dict):
        err(f"{where}: `{axis}` must be a mapping with `floor` and `measured`")
        return
    extra = set(value) - {"floor", "measured"} - optional
    if extra:
        allowed = "`floor` + `measured`"
        if optional:
            allowed += " plus " + " / ".join(f"`{k}`" for k in sorted(optional))
        err(f"{where}: `{axis}` carries unknown key(s) {sorted(extra)} - "
            f"an axis is exactly {allowed}")
    if "ring" in value:
        ring = value["ring"]
        if not isinstance(ring, str) or not RING_RE.match(ring):
            err(f"{where}: `{axis}.ring` must be a hosting ring R0-R4 "
                f"(got {ring!r})")
    if "tfm" in value:
        tfm = value["tfm"]
        if not isinstance(tfm, str) or not TFM_RE.match(tfm):
            err(f"{where}: `{axis}.tfm` must be a framework moniker such as "
                f"'net10.0' (got {tfm!r})")
    if "reason" in value:
        reason = value["reason"]
        if (not isinstance(reason, dict) or set(reason) != {"ref", "why"}
                or not all(isinstance(reason[k], str) and reason[k].strip()
                           for k in ("ref", "why"))):
            err(f"{where}: `{axis}.reason` must be exactly {{ ref, why }}, "
                f"both non-empty strings (got {reason!r})")
    if "flag" in value and value["flag"] not in FLOOR_FLAGS:
        err(f"{where}: `{axis}.flag` must be one of {sorted(FLOOR_FLAGS)} "
            f"(got {value['flag']!r})")
    if "databasePackage" in value:
        pkg = value["databasePackage"]
        m = DB_PACKAGE_RE.match(pkg) if isinstance(pkg, str) else None
        if not m:
            err(f"{where}: `{axis}.databasePackage` must be the portal's database "
                f"package name, swift[-]<version>-<yyyymmdd>-database.zip (got {pkg!r})")
        elif m.group(1) != value.get("measured"):
            err(f"{where}: `{axis}.databasePackage` names Swift {m.group(1)} but "
                f"`measured` is {value.get('measured')!r}")
    measured = value.get("measured")
    if not isinstance(measured, str) or not MEASURED_RE.match(measured):
        err(f"{where}: `{axis}.measured` must be one concrete version "
            f"(got {measured!r}) - never a range, never `x`")
    floor = value.get("floor")
    if not isinstance(floor, str) or not FLOOR_RE.match(floor):
        err(f"{where}: `{axis}.floor` must be a version range such as "
            f"'>=10.28.1' or '==2.4' (got {floor!r})")


def load_versions() -> dict | None:
    if not VERSIONS_FILE.is_file():
        err("versions.json is missing - the corpus must state what it works on")
        return None
    try:
        return json.loads(VERSIONS_FILE.read_text(encoding=ENCODING))
    except json.JSONDecodeError as e:
        err(f"versions.json: invalid JSON ({e})")
        return None


# The MCP add-in id. `Dynamicweb.MCP` is its retired predecessor, not an
# alias: versions.json lists it under the app's `predecessors`, and an app
# entry keyed by it is an error.
MCP_APP_ID = "Truvio.Commerce.MCP"


def works_on_mcp_version() -> str | None:
    """The MCP app version `versions.json` was measured on, if it parses."""
    if not VERSIONS_FILE.is_file():
        return None
    try:
        doc = json.loads(VERSIONS_FILE.read_text(encoding=ENCODING))
    except json.JSONDecodeError:
        return None
    if not isinstance(doc, dict):
        return None
    apps = doc.get("worksOn", {}).get("apps", [])
    if not isinstance(apps, list):
        return None
    for app in apps:
        if isinstance(app, dict) and app.get("id") == MCP_APP_ID:
            v = app.get("measured")
            # The registry file is named by the version core: a measured
            # `0.6.0-beta` resolves to `scripts/mcp-tools/0.6.0.json`.
            return v.split("-", 1)[0] if isinstance(v, str) else None
    return None


def check_versions_file() -> None:
    """Rule (a): versions.json parses against exactly the published schema.

    Vendor axes only: the Dynamicweb release, the Swift tag and the AppStore
    apps. Nothing here names a distribution, a harness or any downstream
    artifact - the dependency points up, so downstream cites this repo's tag
    and never the reverse.
    """
    doc = load_versions()
    if doc is None:
        return
    if not isinstance(doc, dict):
        err("versions.json: top level must be an object")
        return
    expected = {"schema", "worksOn", "measuredAt", "policy"}
    if set(doc) != expected:
        err(f"versions.json: top-level keys must be exactly {sorted(expected)} "
            f"(got {sorted(doc)})")
    if doc.get("schema") != 1:
        err(f"versions.json: `schema` must be 1 (got {doc.get('schema')!r})")
    measured_at = doc.get("measuredAt")
    if not isinstance(measured_at, str) or not ISO_DATE_RE.match(measured_at):
        err(f"versions.json: `measuredAt` must be an ISO date (got "
            f"{measured_at!r})")
    if not isinstance(doc.get("policy"), str) or not doc.get("policy"):
        err("versions.json: `policy` must be a non-empty string")

    works_on = doc.get("worksOn")
    if not isinstance(works_on, dict):
        err("versions.json: `worksOn` must be an object")
        return
    if set(works_on) != {"dw", "swift", "apps"}:
        err(f"versions.json: `worksOn` keys must be exactly ['apps', 'dw', "
            f"'swift'] (got {sorted(works_on)})")
    for axis in ("dw", "swift"):
        if axis in works_on:
            check_axis("versions.json", f"worksOn.{axis}", works_on[axis],
                       DW_AXIS_EXTRAS if axis == "dw" else SWIFT_AXIS_EXTRAS)
    apps = works_on.get("apps")
    if not isinstance(apps, list) or not apps:
        err("versions.json: `worksOn.apps` must be a non-empty array")
        return
    for i, app in enumerate(apps):
        where = f"versions.json: worksOn.apps[{i}]"
        if not isinstance(app, dict):
            err(f"{where} must be an object")
            continue
        unknown = set(app) - {"id", "floor", "measured", "required", "scope",
                              "predecessors", "reason", "flag"}
        if unknown:
            err(f"{where} carries unknown key(s) {sorted(unknown)}")
        missing = {"id", "floor", "measured", "required"} - set(app)
        if missing:
            err(f"{where} is missing {sorted(missing)}")
        if "id" in app and not isinstance(app["id"], str):
            err(f"{where}: `id` must be a string")
        if "required" in app and not isinstance(app["required"], bool):
            err(f"{where}: `required` must be a boolean")
        if "scope" in app and not isinstance(app["scope"], str):
            err(f"{where}: `scope` must be a string")
        preds = app.get("predecessors", [])
        if (not isinstance(preds, list)
                or not all(isinstance(p, str) and p for p in preds)):
            err(f"{where}: `predecessors` must be a list of package ids")
        check_axis(where, "app", {k: v for k, v in app.items()
                                 if k in ("floor", "measured", "reason",
                                          "flag")},
                   frozenset({"reason", "flag"}))
    # A predecessor is a retired package, never an alias: no app entry may be
    # keyed by one, or a host carrying only the retired package would read as
    # matching the floor.
    retired = {p for app in apps if isinstance(app, dict)
               for p in (app.get("predecessors") or [])
               if isinstance(p, str)}
    for i, app in enumerate(apps):
        if isinstance(app, dict) and app.get("id") in retired:
            err(f"versions.json: worksOn.apps[{i}]: `{app['id']}` is a retired "
                f"predecessor, not an app id - key the entry by its successor")


# `versions:` in frontmatter is the one nested block in this corpus, so the
# flat parser above cannot see it. PyYAML reads it when installed; this is the
# fallback so the rule holds without the dependency. Both the flow form
# (`dw: { floor: ">=10.28.1", measured: "10.28.10" }`) and the indented form
# are accepted.
VERSIONS_KEY_RE = re.compile(r"^versions:\s*$")
AXIS_LINE_RE = re.compile(r"^(\s+)([A-Za-z0-9_]+):\s*(.*)$")
PAIR_RE = re.compile(r"""([A-Za-z]+)\s*:\s*['"]?([^,'"}\s]+)['"]?""")


def versions_block_fallback(front: str) -> dict | None:
    lines = front.splitlines()
    start = next((i for i, l in enumerate(lines) if VERSIONS_KEY_RE.match(l)), None)
    if start is None:
        return None
    block: dict[str, dict] = {}
    axis: str | None = None
    axis_indent = 0
    for line in lines[start + 1:]:
        if line.strip() and not line.startswith((" ", "\t")):
            break
        m = AXIS_LINE_RE.match(line)
        if not m:
            continue
        indent, key, rest = len(m.group(1)), m.group(2), m.group(3).strip()
        if axis is not None and indent > axis_indent:
            pair = PAIR_RE.match(f"{key}: {rest}")
            if pair:
                block[axis][pair.group(1)] = pair.group(2)
            continue
        axis, axis_indent = key, indent
        block[axis] = {k: v for k, v in PAIR_RE.findall(rest.strip("{} "))}
    return block


def check_skill_versions_blocks() -> None:
    """Rule (b): the optional per-skill `versions:` frontmatter block.

    Same axis keys as a stamp token (dw, mcp, serializer, swift), each
    `{ floor, measured }`, validated by the same rules as versions.json. A
    skill without the block inherits the repo statement; a skill with one is
    claiming a deviation, so the deviation has to be well-formed.
    """
    for skill_md in sorted(SKILLS_DIR.glob("*/SKILL.md")):
        text = skill_md.read_text(encoding=ENCODING)
        m = FRONTMATTER_RE.match(text)
        if not m:
            continue
        block: object = None
        if yaml is not None:
            try:
                data = yaml.safe_load(m.group(1))
            except yaml.YAMLError:  # type: ignore[union-attr]
                continue  # already reported by check_frontmatter_yaml
            if not isinstance(data, dict) or "versions" not in data:
                continue
            block = data["versions"]
        else:
            block = versions_block_fallback(m.group(1))
            if block is None:
                continue
        where = rel(skill_md)
        if not isinstance(block, dict) or not block:
            err(f"{where}: `versions:` must be a non-empty mapping of axes")
            continue
        unknown = set(block) - set(STAMP_AXES)
        if unknown:
            err(f"{where}: `versions:` carries unknown axis/axes "
                f"{sorted(unknown)} - allowed: {list(STAMP_AXES)}")
        for axis in STAMP_AXES:
            if axis in block:
                check_axis(where, f"versions.{axis}", block[axis],
                           DW_AXIS_EXTRAS if axis == "dw" else frozenset())


def stamp_token_problems(token: str) -> str | None:
    """None if the token body is a well-formed stamp, else why it is not."""
    seen: list[str] = []
    for part in token.split(" · "):
        bits = part.split(" ")
        if len(bits) != 2 or bits[0] not in STAMP_AXES:
            return (f"each part is `<axis> <version>` with axes "
                    f"{list(STAMP_AXES)} (got {part!r})")
        axis, version = bits
        if axis in seen:
            return f"axis `{axis}` named twice"
        seen.append(axis)
        if not MEASURED_RE.match(version) and not (
                axis == "dw" and RING_RE.match(version)):
            if axis == "dw":
                return (f"`{axis} {version}` is neither one concrete version "
                        "nor a hosting ring R0-R4")
            return f"`{axis} {version}` is not one concrete version"
    order = [STAMP_AXES.index(a) for a in seen]
    if order != sorted(order):
        return ("axes must print in the fixed order "
                + " · ".join(STAMP_AXES)
                + " (got " + " · ".join(seen) + ")")
    return None


def masked_line(line: str) -> str:
    """`line` with every stamp token and URL blanked out.

    What survives is prose, and a version number in prose is a fact nobody can
    re-measure: the stamp token is where a version belongs.
    """
    line = STAMP_TOKEN_RE.sub(lambda m: " " * len(m.group(0)), line)
    return URL_RE.sub(lambda m: " " * len(m.group(0)), line)


def version_stamp_scan(f: Path) -> tuple[list[tuple[int, str]], list[tuple[int, str]]]:
    """(malformed tokens, bare versions) for one markdown file.

    Skipped, by design: fenced blocks (a literal command output or config
    snippet carries whatever version it carries), the frontmatter (the
    `versions:` block has its own rule), URLs (a release link is not a claim)
    and the inside of a well-formed stamp token.
    """
    text = read_text_checked(f)
    if text is None:
        return [], []
    body = FRONTMATTER_RE.sub(
        lambda m: "\n" * m.group(0).count("\n"), text, count=1)
    malformed: list[tuple[int, str]] = []
    bare: list[tuple[int, str]] = []
    fenced = False
    for i, line in enumerate(body.splitlines(), 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        for m in STAMP_TOKEN_RE.finditer(line):
            problem = stamp_token_problems(m.group(1))
            if problem:
                malformed.append((i, f"{m.group(0)} - {problem}"))
        for m in BARE_VERSION_RE.finditer(masked_line(line)):
            bare.append((i, m.group(0)))
    return malformed, bare


def stamp_files() -> list[Path]:
    return sorted(SKILLS_DIR.rglob("*.md"))


def bare_version_counts() -> dict[str, int]:
    counts: dict[str, int] = {}
    for f in stamp_files():
        _, bare = version_stamp_scan(f)
        if bare:
            counts[dynamo_key(f)] = len(bare)
    return counts


def check_version_stamps() -> None:
    """Rule (c): version-specific facts carry a stamp token, not a bare number.

    A fact that is true of one build ends with one bracketed token -
    `[dw 10.28.10 . mcp 0.4.4]` with a middle dot as the separator - axes in
    the fixed order dw, mcp, serializer, swift, only the axes that were varied.
    A malformed token is always an error. A bare version number left in prose
    is an error too, ratcheted per file against
    scripts/version-stamp-allowlist.json: the file's entry is the count the
    stamp migration has not reached yet, a file above it fails, and below it is
    fine, so the allowlist only ever shrinks.
    """
    allowlist: dict[str, int] = {}
    if STAMP_ALLOWLIST.is_file():
        try:
            allowlist = json.loads(STAMP_ALLOWLIST.read_text(encoding=ENCODING))
        except json.JSONDecodeError as e:
            err(f"{rel(STAMP_ALLOWLIST)}: invalid JSON ({e})")
            return
    else:
        warn(f"{rel(STAMP_ALLOWLIST)} is missing - every allowance reads as 0")

    for f in stamp_files():
        malformed, bare = version_stamp_scan(f)
        key = dynamo_key(f)
        for line_no, detail in malformed:
            err(f"{key}:{line_no}: malformed version stamp {detail}")
        allowed = allowlist.get(key, 0)
        if len(bare) > allowed:
            first = "; ".join(f"L{n} {v}" for n, v in bare[:3])
            err(f"{key}: {len(bare)} bare version number(s) outside a stamp "
                f"token, allowance {allowed} - end the fact with a stamp "
                f"token. First: {first}")


def write_stamp_allowlist() -> int:
    counts = bare_version_counts()
    STAMP_ALLOWLIST.write_text(
        json.dumps(dict(sorted(counts.items())), indent=2) + "\n",
        encoding="utf-8")
    print(f"wrote {rel(STAMP_ALLOWLIST)}: {len(counts)} file(s), "
          f"{sum(counts.values())} bare version number(s)")
    return 0


def main() -> int:
    if not SKILLS_DIR.is_dir():
        print(f"ERROR: {rel(SKILLS_DIR)} not found", file=sys.stderr)
        return 2
    check_marketplace()
    check_skills()
    check_frontmatter_yaml()
    check_links()
    check_no_bom()
    check_reference_tocs()
    check_bundle_closure()
    check_no_mojibake()
    check_no_secrets()
    check_no_environment_literals()
    check_script_contract()
    check_av_safe_scripts()
    check_script_imports()
    check_orphan_scripts()
    check_dynamo_surface()
    check_dynamo_exclusivity()
    check_mcp_tool_names()
    check_versions_file()
    check_skill_versions_blocks()
    check_version_stamps()

    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")

    if errors:
        print(f"\n{len(errors)} error(s), {len(warnings)} warning(s) — FAILED")
        return 1
    print(f"\nOK — 0 errors, {len(warnings)} warning(s)")
    return 0


if __name__ == "__main__":
    if "--update-dynamo-baseline" in sys.argv[1:]:
        sys.exit(write_dynamo_baseline())
    if "--update-version-stamp-allowlist" in sys.argv[1:]:
        sys.exit(write_stamp_allowlist())
    if "--self-test" in sys.argv[1:]:
        sys.exit(run_av_self_test())
    sys.exit(main())
