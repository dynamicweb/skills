#!/usr/bin/env python3
"""Validate the Dynamicweb skills plugin repository.

Checks (errors fail the build, warnings are printed but do not):
  - marketplace.json parses and every referenced skill path exists.
  - Each skill folder name == `name:` frontmatter == marketplace path basename.
  - Each SKILL.md frontmatter has both `name` and `description`.
  - Every relative markdown link in SKILL.md / references resolves to a real file.
  - The string "truvio" (case-insensitive) appears nowhere.
  - WARN if a skill description lacks a trigger signal (Triggers:/Use when/Use FIRST).

Run from anywhere: `python3 scripts/validate-skills.py`. Exit code 0 = clean.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# utf-8-sig transparently strips a leading BOM if present, so files authored on
# Windows (UTF-8 with BOM) parse the same as everything else.
ENCODING = "utf-8-sig"
REPO = Path(__file__).resolve().parent.parent
SKILLS_DIR = REPO / "skills"
MARKETPLACE = REPO / ".claude-plugin" / "marketplace.json"

errors: list[str] = []
warnings: list[str] = []

# File types scanned for the "truvio" purge check.
TEXT_SUFFIXES = {".md", ".json", ".template", ".ps1", ".yaml", ".yml", ".jsonc"}
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
    referenced: list[str] = []
    for plugin in data.get("plugins", []):
        for skill_path in plugin.get("skills", []):
            referenced.append(skill_path)
            if not (REPO / skill_path).is_dir():
                err(f"marketplace plugin '{plugin.get('name')}' references missing "
                    f"skill path: {skill_path}")
    return referenced


def check_skills() -> None:
    for skill_md in sorted(SKILLS_DIR.glob("*/SKILL.md")):
        folder = skill_md.parent.name
        fm = parse_frontmatter(skill_md.read_text(encoding=ENCODING))
        name = fm.get("name")
        if not name:
            err(f"{rel(skill_md)}: frontmatter missing `name`")
        elif name != folder:
            err(f"{rel(skill_md)}: name '{name}' != folder '{folder}'")
        desc = fm.get("description")
        if not desc:
            err(f"{rel(skill_md)}: frontmatter missing `description`")
        elif not re.search(r"Triggers:|Use when|Use FIRST|Use AFTER", desc):
            warn(f"{rel(skill_md)}: description lacks a trigger signal "
                 "(Triggers:/Use when/Use FIRST)")


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


def check_no_truvio() -> None:
    # Scope the purge check to shipped plugin content (skills/ + marketplace).
    # Root dev docs (CHANGELOG/CLAUDE) may reference the retired codename historically.
    candidates = [MARKETPLACE, *SKILLS_DIR.rglob("*")]
    for path in sorted(candidates):
        if ".git" in path.parts or not path.is_file():
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding=ENCODING)
        except (UnicodeDecodeError, OSError):
            continue
        if "truvio" in text.lower() or "truvio" in path.name.lower():
            err(f"{rel(path)}: contains 'truvio' (should be purged)")


def main() -> int:
    if not SKILLS_DIR.is_dir():
        print(f"ERROR: {rel(SKILLS_DIR)} not found", file=sys.stderr)
        return 2
    check_marketplace()
    check_skills()
    check_links()
    check_no_truvio()

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
