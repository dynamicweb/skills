# Folding demo-build learnings back into the truvio-commerce-demo plugin

When a demo build surfaces a non-trivial learning — a workaround, a gotcha, a corrected surface order, a missing prereq — that should be captured into a skill, follow this workflow. The goal is to fold it back **while the demo's context is still fresh in the conversation**, not from notes a week later.

This workflow is **maintainer-only** — it requires write access to the `justdynamics/truvio-commerce-demo` repo and a local clone of it. Consumers of the plugin can ignore this reference (or open a PR with their learning instead).

## When to invoke

Trigger phrases that should route Claude here:

- "fold this into the skill"
- "fold this learning back"
- "save this back to the plugin"
- "update the plugin from this demo"
- "publish this update"
- "this is worth keeping — add it to the skill"

The conversation should already contain the actual learning content (the gotcha, the fix, the proven recipe). If it doesn't, ask the user to articulate it first; do not invent.

## Step 0 — Resolve the local plugin repo path

The workflow needs the absolute path to your local clone of `justdynamics/truvio-commerce-demo`. Resolution order:

1. **Env var.** Check `$env:TRUVIO_PLUGIN_REPO`. If set and the path exists, use it.
2. **User-scope memory.** Look for a `reference` memory with name `truvio-plugin-repo` (or similar). If found and the path exists, use it.
3. **Ask.** Use `AskUserQuestion`: *"Path to your local clone of `justdynamics/truvio-commerce-demo`? (e.g. `C:\VibeCode\truvio-commerce-demo`)"*. Once the user answers, verify the path exists and contains `.claude-plugin/plugin.json`, then **save it as a user-scope `reference` memory** so future invocations skip this step. Optionally suggest the user `setx TRUVIO_PLUGIN_REPO "<path>"` for a more permanent fix.

If the path doesn't pass the `.claude-plugin/plugin.json` sanity check, abort — the user gave the wrong directory.

## Step 1 — Identify which file should change

From the conversation context, decide:

- **Which skill** owns the learning (`truvio-demo-base`, `truvio-pim-demo`, `truvio-pim-for-bc`, or `truvio-swift-demo`)?
- **Which reference** within that skill is the right home? Read the skill's SKILL.md "Where to find things" table to map the learning's topic to a `references/<topic>.md` file. If the learning genuinely doesn't fit any existing reference, propose a new `references/<topic>.md` and check with the user before creating.
- **Where in the file** does the new content slot in? Read enough surrounding context to make the insertion feel like it belongs (correct heading depth, consistent voice, no duplicate content).

If you're not sure, ask the user one focused question — don't guess at structure.

## Step 1a — Sanitize the candidate content BEFORE drafting the edit (load-bearing)

**Hard rule: zero customer identifiers, zero named individuals, zero session-relative time markers in plugin content.** The plugin is public. Every blob and every commit message is visible at `github.com/justdynamics/truvio-commerce-demo`. Once a name lands in a commit it persists in tags + release-tarball downloads even after subsequent scrubs — historical leaks are forever unless you rewrite git history and force-push (a destructive, project-wide operation that this workflow exists to prevent). A 2026-05-21 sweep had to do exactly that: rewrite all messages + blobs across 14 commits and 11 tags because several customer engagement names AND one vendor employee's personal name had leaked into release prose and worked examples. **Don't make that sweep necessary again.**

### What to scrub before the edit ever reaches the plugin tree

| Category | Shapes that leak | Replace with |
|---|---|---|
| **Customer / engagement names** (any string that identifies a specific deal, account, brand the demo was built for — past, present, or future) | engagement slug used as folder name; product brand specific to a customer (e.g. a customer's flagship product line); customer's company name in any form | `<demo>` / `<brand>` / `<brand-slug>` / `Acme` / generic ("a recent demo", "a wholesale customer") |
| **Personal names** of customer, partner, OR vendor employees | first+last name in narrative; first name in attribution; surname-only in citations | role-based language (`the Dynamicweb vendor architect`, `the customer CSR`, `the demo presenter`) + the date |
| **Customer-specific paths** | `C:\Projects\Solutions\<customer-slug>\...`; `<customer-slug>/notes/...`; `<customer-slug>/RESUME.md` | `<demo>/...`, `<prior-demo>/RESUME.md` |
| **Brand identifiers in code/JSON** | `<Brand>_<Concept>.xml` worked examples baked with a real prefix; CSS custom-property tokens like `--<brand>-<colour>`; HTML data-attributes like `data-<brand>-variant`; `<brand>_custom.css` filenames; JSON `"Id"`/`"Name"` baked with a real brand | `<Brand>_<Concept>.xml`, `--brand-primary`, `data-<brand>-variant`, `<brand>_custom.css`, `"Name": "Acme"`, `"Id": "acme"` |
| **Session-relative time** | `Today's …`, `this morning`, `yesterday's`, `this week we …` | absolute date (`2026-05-21`), or nothing (the date already lives in `git log` — don't restate it in prose) |
| **Customer hex colors / domain names / phone numbers / addresses** | brand hex codes baked into examples; customer-domain hostnames in code or links; real phone numbers / street addresses in DC band / contact strip examples | `var(--brand-primary)`, `<host>`, `<phone>`, `<address>` |

### The grep pack — run BEFORE the file gets edited AND in the verification gate

A learning's drafted text often sits in `./notes/skill-learnings-*.md` first; that's where to scrub. The same grep runs against the staged edit before commit. The pack ships in a per-engagement scrub-list file, NOT committed into the plugin repo — keeping the actual tokens out of plugin blobs.

**Location of the scrub-list file:** `$TRUVIO_PLUGIN_REPO\..\..\scrub-list.txt` (one level above the local clone, gitignored by construction since it lives outside the repo). One token per line; blank lines and `#` comments allowed. The file ships seeded with the known historical leaks from prior engagements + the current engagement's slug.

If the file doesn't exist, the fold-back command creates a stub on first run and asks the user to add the current engagement's tokens before proceeding.

```powershell
# Build the regex pack from the external list (paths shown — adapt to where you cloned).
$scrubList = "$env:TRUVIO_PLUGIN_REPO\..\..\scrub-list.txt"
if (-not (Test-Path $scrubList)) {
    Write-Error "Scrub-list missing at $scrubList — create it (one token per line) before folding."
    return
}
$tokens = Get-Content $scrubList | Where-Object { $_ -and -not $_.StartsWith('#') }
$nameRx = ($tokens | ForEach-Object { [regex]::Escape($_) }) -join '|'

# 1. Source notes
Select-String -Path .\notes\skill-learnings-*.md -Pattern $nameRx
# Staged edit (run from $TRUVIO_PLUGIN_REPO before commit)
git diff --staged | Select-String -Pattern $nameRx

# 2. Session-relative time (constant — not engagement-specific, lives inline)
$timeRx = "Today's |today's |This morning|this morning|Yesterday|yesterday(?!'s prices)|This week|this week"
Select-String -Path .\notes\skill-learnings-*.md -Pattern $timeRx
git diff --staged | Select-String -Pattern $timeRx

# 3. Customer-specific paths (constant — matches the path shape, not specific slugs)
Select-String -Path .\notes\skill-learnings-*.md -Pattern 'C:\\Projects\\Solutions\\[a-z0-9-]+'
git diff --staged | Select-String -Pattern 'C:\\Projects\\Solutions\\[a-z0-9-]+'
```

**Any hit in any of those three packs blocks the fold.** Sanitize the source `notes/skill-learnings-*.md` first (so the demo's own notes can stay concrete) into a derivative learning that's vendor-generic — then carry only the vendor-generic version into the plugin edit. Two paragraphs side-by-side in the conversation is fine: "what happened (named)" → "what's the durable lesson (generic)". Only the generic side gets committed.

**Why the scrub-list lives outside the repo.** If the token list itself were committed, every customer / personal name would appear in `git log -p` of the plugin — exactly the leak the policy exists to prevent. Keeping the list one directory level up (or in `$env:USERPROFILE\.truvio\scrub-list.txt`, or wherever the maintainer prefers off-repo) means the policy ships in the plugin (this file) while the concrete tokens stay private to the maintainer's machine.

### When the structural learning seems to depend on the customer's name

It almost never does. If the rule is "demo X did Y and learned Z", `Z` is the durable part. `X` is provenance noise. Drop `X`. If you genuinely cannot say `Z` without `X`, the learning is probably demo-specific and shouldn't be folded — log it as a demo-local note instead, per the "Folding a learning that's actually demo-specific" anti-pattern below.

The same rule applies to vendor / partner / customer **individuals**. Architectural advice "blessed by `<named architect>` at vendor X on `<date>`" loses nothing structural when rewritten as "vendor-blessed by the `<role>` (`<date>` architecture call)". The provenance value is the role + date, not the person.

### When to expand the known-names list

When a new customer engagement opens, add the customer slug (and any personal names in play) to the off-repo scrub-list file BEFORE the first fold for that demo. The truvio-fold-back command should ask once per session: *"Any new customer/personal names to add to the scrub pack for this engagement?"* — additions go to the scrub-list file, never into the plugin repo. Future folds inherit the expanded pack.

## Step 1b — Content-hygiene gate (load-bearing — this is how the corpus stays correct)

Sanitization protects the customer; this step protects the *plugin*. Fold-backs that skip it produced, historically: a pivot that left the retracted model live in five other files (three references + two command files), a retracted API claim that survived three releases next to the file that retracted it, and the same lesson recorded four times in different words. Run all three checks BEFORE drafting the edit:

### 1. Supersede sweep — when the learning corrects, retracts, or pivots existing guidance

Grep **all of `skills/` AND `commands/`** (command frontmatter `description:` lines included) for the old claim's distinctive tokens — the API name, the folder pattern, the error message, the rule wording. Every hit must be either rewritten to the new guidance or replaced with a **one-line tombstone**:

> Superseded YYYY-MM-DD: <new rule in one sentence> — see <canonical reference>.

Never leave the old recipe loadable next to the new one: a model that loads only the un-swept file will follow the retracted guidance, and the skill's own audit may then flag the output it produced. The sweep is cheap (one grep, a handful of edits); the alternative is a contradiction that ships until someone audits the whole corpus.

### 2. Dedup check — is this lesson already recorded?

Grep the target skill's `references/` (and sibling skills if the topic straddles) for the lesson's key tokens. If a version of the lesson already exists:

- **Update the existing canonical home** — sharpen it, add the new evidence, correct it.
- Where other files need to surface it, add a **one-line pointer** to the canonical home, never a restated copy.

One lesson, one home. Restatements drift independently and become contradictions later.

### 3. Integrate, don't append

The default move for a fold-back is to **rewrite the existing sentence or section**, not to append a new dated subsection below it. Specifically:

- If the new learning qualifies an existing claim ("X updates automatically" → "X can be static on some builds"), edit the original claim so it no longer over-promises; don't stack a warning block under a sentence that still asserts the opposite.
- A "validated on DW 10.X.Y" marker belongs inline on the rule it validates, and only when a future reader could otherwise mistake the rule for hypothesis. Don't accumulate per-fold date stamps as provenance — the dates live in `git log`.
- Append a genuinely new subsection only for a genuinely new topic.

### 4. Router + size maintenance

- If the fold changes what a reference covers, update the owning SKILL.md "Where to find things" row (trigger phrases included) in the same edit. Do NOT grow the frontmatter `description:` with recipe detail — descriptions are trigger phrases + scope only; they load into every session.
- Avoid literal counts in routing prose ("Five trigger shapes", "Seven references") — they rot on the next fold. Use count-free phrasing.
- If the target reference would exceed ~20KB after the edit, stop and propose a split (or a different home) to the user instead of appending.

## Step 2 — Make the edit

Edit the file at `$TRUVIO_PLUGIN_REPO/skills/<skill>/references/<topic>.md` (or the SKILL.md if the learning is orchestrator-level, not topic-level).

Voice + structure rules (match what's already there):

- Lead with the **rule or recipe**, then the **why** (often a past incident or surprising default), then the **how** (commands, recipes, verification).
- Concrete commands beat prose. Include the exact `dotnet`, `git`, `Invoke-RestMethod`, `sqlcmd`, or PowerShell snippet that worked.
- Prefer rewriting the existing text over appending below it (Step 1b §3). If a future reader could mistake the new content for hypothetical advice, mark it as proven inline — sparingly, per Step 1b §3. **Use absolute dates, never "today" / "this morning" / etc.** (Step 1a).
- **Provenance citations name roles + dates, never individuals.** "Per the Dynamicweb vendor architect (2026-05-13 architecture call)" — not "Per `<Person Name>` (2026-05-13 …)". Apply this to customer-side, partner-side, AND vendor-side individuals.
- Don't break existing cross-references. If you change a heading, search the other skills for links to it and update them too.

## Step 3 — Validate

```powershell
cd $env:TRUVIO_PLUGIN_REPO
python scripts/validate.py
```

Must exit 0. Errors → fix before continuing. The validator checks JSON manifests and SKILL.md frontmatter; if you only edited a reference file under `skills/*/references/`, it should pass trivially.

## Step 4 — Bump the version (BOTH manifests, MUST match)

Read the current version from `.claude-plugin/plugin.json` and bump per semver:

- **Patch** (0.1.1 → 0.1.2) — additive learning, bug fix, clarification. Default for fold-back operations.
- **Minor** (0.1.2 → 0.2.0) — new skill added, new reference doc, contract change to existing recipe (e.g. surface order rewritten).
- **Major** (0.x.y → 1.0.0) — only when explicitly declaring API stability.

Update **both** files with the same new version:

- `.claude-plugin/plugin.json` → `"version": "X.Y.Z"`
- `.claude-plugin/marketplace.json` → the `plugins[].version` field for `truvio-commerce-demo` (currently `"version": "X.Y.Z"` inside the plugin entry; the top-level `metadata.version` should also be bumped to match)

Keeping them in lockstep matters: Claude Code keys its install cache by the plugin's version, and a marketplace listing that disagrees with the plugin manifest will surface "available version" mismatches in `/plugin` UI later.

## Step 4a — Update README.md (mandatory on every version bump)

**This step is non-optional.** Stale README is the difference between partners installing from the marketplace and seeing the current plugin contents vs. an outdated picture. Justin caught a v0.3.0 push that shipped without a README update — the README still listed only the original four skills and made no mention of the `commands/` directory or the new `truvio-erp-demo` sibling. That gap is what this step exists to prevent.

Sections that must stay current on every push:

- **"What's in this plugin"** table — add a row for any new skill; revise descriptions if a skill's scope materially expanded.
- **"Slash commands"** section (add it if it doesn't exist yet) — list each `/truvio-*` command with a one-line description matching the command's frontmatter `description:` field.
- **Repository layout** tree — add `commands/` if not yet listed; add any new skill directory under `skills/`.
- **Prerequisites** table — only if a new skill / new command introduces a fresh prereq (e.g. a new Node package, a new env var).
- **Versioning** note — if this push is a milestone (first 1.0.0, first deprecation), update the narrative. For routine bumps, no change needed.

The change to README.md belongs in the SAME commit as the version bump and the skill-content edit — don't split into a follow-up "docs: update README" commit. Splitting hides the connection between version + content + docs and risks the README commit getting lost.

## Step 5 — Commit, push, tag

Compose a commit message that names **what changed** and **why it was worth folding back**. **The same sanitization rule from Step 1a applies to the commit message body — no customer names, no personal names, no "Today's"/"this morning" temporal prefixes.** Commit messages ship in `git log`, in release tarballs, in GitHub's commit view, and in `gh pr view` — anywhere a tag is published. A leak in a message is the same severity as a leak in a blob.

```
Fold demo-build learning: <one-line topic>

<2–4 sentences describing the learning, why the previous skill content
was wrong or incomplete, and the symptom that surfaced it. Reference
the file(s) changed. Avoid "minor update" / "tweaks" — those rot.
Use absolute dates ("a 2026-05-21 walkthrough") rather than relative
markers ("today's demo"), and refer to demos / vendors / partners /
customers by role + date, never by name.>

Co-Authored-By: <the attribution line the harness specifies for the current model — do NOT hardcode a model name in this template>
```

**Final pre-commit grep** (mandatory; same pack as Step 1a, run one last time against the FULL staged change including the message):

```powershell
# Rebuild $nameRx from the external scrub-list (see Step 1a "Location of the scrub-list file").
$tokens = Get-Content "$env:TRUVIO_PLUGIN_REPO\..\..\scrub-list.txt" |
          Where-Object { $_ -and -not $_.StartsWith('#') }
$nameRx = ($tokens | ForEach-Object { [regex]::Escape($_) }) -join '|'
$timeRx = "Today's |today's |This morning|this morning|Yesterday[^\s]"

# Staged diff
git diff --staged | Select-String -Pattern $nameRx
git diff --staged | Select-String -Pattern $timeRx
# Drafted commit message (write to a file first if using a HEREDOC)
Get-Content .git\COMMIT_EDITMSG -Raw | Select-String -Pattern $nameRx
Get-Content .git\COMMIT_EDITMSG -Raw | Select-String -Pattern $timeRx
```

Any hit blocks the commit. Sanitize and re-stage / re-edit `COMMIT_EDITMSG`. **If a hit slips through and lands on origin/main, the recovery is full history rewrite + force-push** (see "Recovery from a leak that made it to origin" below). Cheaper to grep twice now.

Then:

```powershell
cd $env:TRUVIO_PLUGIN_REPO
git add .claude-plugin README.md skills/<skill>/<file>
git commit -m "<the message above>"
git push
git tag -a v<X.Y.Z> -m "<short tag annotation>"
git push origin v<X.Y.Z>
```

Skip the tag step only if explicitly told to (rare — tags are how rollback later finds a working state).

## Step 6 — Refresh the local marketplace clone

```powershell
cd $env:USERPROFILE\.claude\plugins\marketplaces\truvio-commerce-demo
git pull origin main
```

This makes the new version visible to `/plugin install`. Without this step, Claude Code's local marketplace mirror is still at the old version and the install command will be a no-op.

## Step 7 — Tell the user the slash commands to refresh the install

Claude cannot issue slash commands. Output a clear final-step message for the user, exactly:

> Pushed `v<X.Y.Z>` and refreshed the marketplace clone. To activate the new content in this (and other) Claude Code sessions, run:
>
> ```
> /plugin update truvio-commerce-demo
> /reload-plugins
> ```
>
> After `/reload-plugins`, the new content is live without restarting the session.

**`update`, not `install`.** When the plugin is already installed (which it always is, in the iterate-plugin workflow — you have to have it installed to be folding learnings back), `/plugin install` is a no-op that prints *"Plugin '...' is already installed globally"* and leaves the active install at the old version. `/plugin update` is what actually swings the `installPath` in `~/.claude/plugins/installed_plugins.json` to the new cached version. The old workflow text said `install` and it silently did nothing; verified on Claude Code 2026-05-11.

If you ever need a true fresh install (different machine, plugin not yet installed): then `/plugin install truvio-commerce-demo@truvio-commerce-demo` is the right call. That's a different audience than this workflow's.

## Verification gate — this workflow is NOT complete until

1. `validate.py` returned exit 0
2. The version bumped (both files agree)
3. **README.md updated to reflect the new content** (per Step 4a)
4. **Sanitization grep packs (Step 1a + final pre-commit) both returned zero hits** — across the source notes, the staged diff, AND the commit message body
5. **Content-hygiene gate passed (Step 1b)** — supersede sweep run over `skills/` + `commands/` if the learning corrects anything; no second copy of an existing lesson introduced; owning SKILL.md routing row updated if scope changed
6. `git push` succeeded for both the commit and the tag
7. The marketplace clone at `~/.claude/plugins/marketplaces/truvio-commerce-demo` is at the new commit (`git log -1 --oneline`)
8. **Post-push verification grep against `origin/main`** — confirm the leak pack returns zero against the just-pushed commit (`git fetch && git log origin/main -1 --format=%B | Select-String -Pattern $nameRx`). If a hit shows up here, jump immediately to "Recovery from a leak that made it to origin" below — do not announce success to the user.
9. The user has the slash-command pair to run

If any of these fail, surface the failure — don't silently declare success. A half-folded learning is worse than not folding it, because it advertises a fix that nobody can install yet. A **leak** is worse than a half-folded learning, because the cost of recovery is project-wide history rewrite + force-push.

## Recovery from a leak that made it to origin

If a customer name or session-relative time marker lands in a public commit (subject, body, or blob) despite the gates above, the only clean recovery is full history rewrite + force-push. This is destructive — every collaborator with a clone must re-clone or `git reset --hard origin/main` — so it's a last resort, not a routine cleanup.

The recipe that was used during the 2026-05-21 sweep:

1. **Scrub working-tree content** first via direct `Edit`s, replacing customer-named strings with `<demo>`/`<brand>`/`Acme`-style placeholders.
2. **Rewrite commit messages** across `--branches --tags` via `git filter-branch --msg-filter <python-script>` where the script does per-SHA full-message replacement for the affected commits and a defensive substring-replace fallback for everything else.
3. **Rewrite blob contents** across history via `git filter-branch --tree-filter <python-script> --prune-empty` where the script walks every text file and applies the same substring substitutions (longest patterns first).
4. **Drop `refs/original/*` backup refs** so `git log --all` doesn't accidentally surface the pre-rewrite history.
5. **Force-push** with `git push --force-with-lease=main:<pre-rewrite-sha> origin main` and `git push --force origin --tags`. Use `--force-with-lease` (not bare `--force`) so a concurrent collaborator's push isn't silently obliterated.
6. **Notify collaborators** to `git fetch --tags --force && git reset --hard origin/main`. Any clones / forks still carry the leaked history; the public repo no longer does.

The cost of this dance is high enough that the Step 1a + final pre-commit grep packs are not "extra paranoia" — they are the cheaper option by orders of magnitude. Run them.

## Anti-patterns

- **Bumping version without changing skill content.** Defeats the cache-key purpose. If you only edited the validator or CI, no version bump is needed.
- **Bumping only one of plugin.json / marketplace.json.** Will diverge silently. Always edit both.
- **Bumping the version without updating README.md.** Stale README ships an outdated picture of the plugin to anyone installing from the marketplace. Per Step 4a, README update is mandatory on every version bump.
- **Skipping the Step 1a sanitization grep.** Customer-name leaks in a public plugin are a "capital sin" per the project's standing rule. The grep takes seconds; the recovery (full history rewrite + force-push, see above) takes the rest of an afternoon and costs every collaborator a clone reset.
- **Letting a personal name through because "they're a vendor employee, not a customer".** The standing rule covers vendor / partner / individual names too — provenance is "the Dynamicweb vendor architect (`<date>`)", never `<Person Name>`. A 2026-05-21 sweep had to retroactively scrub a vendor architect's personal name from blobs and messages for exactly this reason.
- **Using "Today's …" / "this morning …" / "yesterday …" in commit prose.** The dates are already in `git log`'s commit metadata. Repeating relative timestamps in the message body rots immediately and reads as session noise. Use absolute dates inside prose when the date is structurally important; otherwise drop the temporal prefix.
- **Folding a learning that's actually demo-specific.** If the gotcha only applies to one customer's quirky data, it belongs in that demo's `.planning/`, not in the plugin. Ask: "would this help every Truvio demo, or only this one?" If only this one, skip the fold. (A learning that *requires* the customer's name to be coherent is a strong signal it's demo-specific.)
- **Folding without context.** If the user says "save that thing we just figured out" and you're not sure exactly which thing, ask. Don't fold a paraphrase.
- **Touching `truvio-pim-for-bc` for non-BC learnings.** Each skill has a tight scope; cross-skill learnings usually live in `truvio-demo-base` (foundation rules), `truvio-erp-demo` (integration concerns), or get split.
- **Appending a warning next to a claim it contradicts.** If the learning shows an existing sentence is wrong or over-confident, rewrite that sentence (Step 1b §3). A ⚠ block stacked under an unqualified claim leaves the file disagreeing with itself.
- **Folding a correction into one file and calling it done.** A pivot or retraction must sweep `skills/` AND `commands/` (Step 1b §1). The v0.6.0 ERP pivot updated one reference and left the retracted model live in five other files — including a command that actively scaffolded it.
- **Recording the same lesson in a second home.** If a grep finds the lesson already exists, sharpen the canonical copy and pointer to it (Step 1b §2). Duplicates drift into contradictions.

## Reference: file layout

```
$TRUVIO_PLUGIN_REPO/
├── .claude-plugin/
│   ├── plugin.json                  ← version field here
│   └── marketplace.json             ← plugins[].version AND metadata.version here
├── README.md                        ← updated on EVERY version bump (Step 4a)
├── commands/                        ← /truvio-* slash commands
├── skills/
│   ├── truvio-demo-base/
│   │   ├── SKILL.md
│   │   └── references/<topic>.md    ← most additive learnings land here
│   ├── truvio-pim-demo/
│   ├── truvio-erp-demo/             ← ERP integration (mock + cross-link to live BC)
│   ├── truvio-pim-for-bc/           ← live BC connector via ngrok
│   └── truvio-swift-demo/
└── scripts/validate.py              ← run before commit
```
