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

Run from anywhere: `python3 scripts/validate-skills.py`. Exit code 0 = clean.
"""
from __future__ import annotations

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
    check_script_imports()
    check_orphan_scripts()

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
    sys.exit(main())
