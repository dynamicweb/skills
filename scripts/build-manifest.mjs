#!/usr/bin/env node
// Regenerates manifest.json from each skill's SKILL.md frontmatter.
//
// manifest.json is the one hard contract the Dynamicweb MCP server ("Dynamo")
// depends on: it reads the `skills` array, groups by type/group for discovery,
// and fetches each skill body from `path`. version/generatedAt are for humans.
//
//   node scripts/build-manifest.mjs           # rewrite manifest.json
//   node scripts/build-manifest.mjs --check    # exit 1 if skills[] is stale (CI)
//
// No dependencies — Node built-ins only.

import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { join, relative, dirname, sep } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..");
const SKILLS_DIR = join(REPO, "skills");
const MANIFEST = join(REPO, "manifest.json");

// Every SKILL.md under skills/, at any depth (works for flat or nested layouts).
function findSkillFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...findSkillFiles(p));
    else if (entry.name === "SKILL.md") out.push(p);
  }
  return out;
}

// Minimal frontmatter parse: flat `key: value` lines between the first --- pair.
// Descriptions are single-line, so this is all the YAML we need.
function frontmatter(text) {
  const m = text.match(/^---\s*\n([\s\S]*?)\n---\s*\n/);
  if (!m) return {};
  const fm = {};
  for (const line of m[1].split("\n")) {
    if (/^\s/.test(line) || line.trimStart().startsWith("#")) continue;
    const i = line.indexOf(":");
    if (i === -1) continue;
    fm[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  return fm;
}

// Dynamo shows the description up to the first sentence terminator, capped ~200.
// Skill descriptions lead with a tight, period-terminated summary; everything
// after (Triggers:/Non-triggers:) is for Claude Code and is dropped here.
function firstSentence(desc) {
  const m = desc.match(/^.*?[.](?=\s|$)/);
  return (m ? m[0] : desc).trim().slice(0, 200);
}

function buildSkills() {
  const skills = findSkillFiles(SKILLS_DIR)
    .map((file) => {
      const fm = frontmatter(readFileSync(file, "utf8"));
      const name = fm.name;
      if (!name) return null;
      const type = (fm.type || "").toLowerCase() === "flow" ? "flow" : "knowledge";
      const group = fm.group || (name.match(/^dw-([a-z0-9]+)-/)?.[1] ?? "");
      return {
        name,
        type,
        group,
        description: firstSentence(fm.description || ""),
        path: relative(REPO, file).split(sep).join("/"),
      };
    })
    .filter(Boolean);

  // Stable order: flows before knowledge, then group, then name — deterministic
  // output so CI drift is real drift, not reordering noise.
  const rank = { flow: 0, knowledge: 1 };
  skills.sort(
    (a, b) =>
      rank[a.type] - rank[b.type] ||
      a.group.localeCompare(b.group) ||
      a.name.localeCompare(b.name)
  );
  return skills;
}

const skills = buildSkills();

if (process.argv.includes("--check")) {
  let current;
  try {
    current = JSON.parse(readFileSync(MANIFEST, "utf8")).skills;
  } catch {
    console.error("manifest.json missing or invalid — run: node scripts/build-manifest.mjs");
    process.exit(1);
  }
  // Compare only skills[] — generatedAt is expected to differ between runs.
  if (JSON.stringify(current) !== JSON.stringify(skills)) {
    console.error("manifest.json is stale — run: node scripts/build-manifest.mjs");
    process.exit(1);
  }
  console.log(`manifest.json up to date (${skills.length} skills).`);
} else {
  const manifest = { version: 1, generatedAt: new Date().toISOString(), skills };
  writeFileSync(MANIFEST, JSON.stringify(manifest, null, 2) + "\n");
  console.log(`Wrote manifest.json (${skills.length} skills).`);
}
