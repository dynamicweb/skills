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
  - Every relative markdown link in SKILL.md / references resolves to a real file.
  - No markdown file under skills/ begins with a UTF-8 BOM (breaks some
    frontmatter parsers).
  - No markdown file under skills/ contains double-encoded UTF-8 (mojibake).
  - WARN if a skill description lacks a trigger signal (Triggers:/Use when/Use FIRST).
  - WARN if a SKILL.md body exceeds 500 lines (split into references/).
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
# References longer than this should carry a top-of-file TOC (survives partial reads).
REFERENCE_TOC_MIN = 100
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
        # Soft line budget on the body (frontmatter stripped): past it, the body
        # is doing reference work that belongs in references/.
        body = FRONTMATTER_RE.sub("", text, count=1)
        body_lines = len(body.splitlines())
        if body_lines > SKILL_BODY_MAX:
            warn(f"{rel(skill_md)}: body is {body_lines} lines "
                 f"(>{SKILL_BODY_MAX}) — split material into references/")


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


def check_no_bom() -> None:
    # A leading UTF-8 BOM (EF BB BF) before the opening `---` defeats some YAML
    # frontmatter parsers, so name/description go unread and the skill fails to
    # load. Read raw bytes — utf-8-sig used elsewhere would silently hide it.
    for md in sorted(SKILLS_DIR.rglob("*.md")):
        if md.read_bytes()[:3] == b"\xef\xbb\xbf":
            err(f"{rel(md)}: starts with a UTF-8 BOM (strip it)")


def check_reference_tocs() -> None:
    # A long reference may be only partially read when reached from a SKILL.md
    # link, so a top-of-file TOC is what survives to map the rest of the file.
    toc_re = re.compile(r"^#{2,}\s+(Contents|Table of [Cc]ontents)\b", re.MULTILINE)
    for md in sorted(SKILLS_DIR.glob("*/references/*.md")):
        lines = md.read_text(encoding=ENCODING).splitlines()
        if len(lines) <= REFERENCE_TOC_MIN:
            continue
        head = "\n".join(lines[:15])
        if not toc_re.search(head):
            warn(f"{rel(md)}: {len(lines)} lines but no top-of-file table of "
                 "contents (add a `## Contents` block)")


def check_no_mojibake() -> None:
    # Double-encoded UTF-8 most often re-enters via a fold-back pasted from a
    # mis-decoded source. Catch it at the door. See CHANGELOG 3.3.7.
    for md in sorted(SKILLS_DIR.rglob("*.md")):
        for i, line in enumerate(md.read_text(encoding=ENCODING).splitlines(), 1):
            for marker in MOJIBAKE_MARKERS:
                if marker in line:
                    err(f"{rel(md)}:{i}: double-encoded UTF-8 (mojibake) "
                        f"near '{marker}' — repair the file's encoding")
                    break  # one report per line is enough


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
    check_no_mojibake()

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
