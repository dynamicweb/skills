# Folding demo-build learnings back into the dynamicweb/skills repo

## Contents

- [When to invoke](#when-to-invoke)
- [Step 0 — Resolve the local skills-repo path](#step-0--resolve-the-local-skills-repo-path)
- [Step 1 — Route the learning: foundational skill or demo skill?](#step-1--route-the-learning-foundational-skill-or-demo-skill)
- [Step 1a — Sanitize the candidate content BEFORE drafting the edit (load-bearing)](#step-1a--sanitize-the-candidate-content-before-drafting-the-edit-load-bearing)
- [Step 1b — Content-hygiene gate (load-bearing — this is how the corpus stays correct)](#step-1b--content-hygiene-gate-load-bearing--this-is-how-the-corpus-stays-correct)
- [Step 2 — Make the edit](#step-2--make-the-edit)
- [Step 3 — Validate](#step-3--validate)
- [Step 4 — Bump the version (one place)](#step-4--bump-the-version-one-place)
- [Step 4a — Update README.md and CHANGELOG.md (mandatory when content/scope changes)](#step-4a--update-readmemd-and-changelogmd-mandatory-when-contentscope-changes)
- [Step 5 — Branch, atomic commit, push, open PR](#step-5--branch-atomic-commit-push-open-pr)
- [Step 6 — After the PR merges: refresh the local marketplace clone](#step-6--after-the-pr-merges-refresh-the-local-marketplace-clone)
- [Step 7 — Tell the user the slash commands to refresh the install](#step-7--tell-the-user-the-slash-commands-to-refresh-the-install)
- [Verification gate — this workflow is NOT complete until](#verification-gate--this-workflow-is-not-complete-until)
- [Recovery from a leak that merged to the integration branch](#recovery-from-a-leak-that-merged-to-the-integration-branch)
- [Anti-patterns](#anti-patterns)
- [Reference: file layout](#reference-file-layout)

When a demo build surfaces a non-trivial learning — a workaround, a gotcha, a corrected
surface order, a missing prereq — that should be captured into a skill, follow this workflow.
The goal is to fold it back **while the demo's context is still fresh in the conversation**,
not from notes a week later.

This workflow is **maintainer-only** — it requires write access to the `dynamicweb/skills`
repo and a local clone of it. Consumers of the plugin can ignore this reference (or open a PR
with their learning instead — the workflow is the same, the access is the only difference).

**Every fold-back lands via a pull request.** There are no direct pushes to the integration
branch (`v2` until it merges to `main`, then `main`). One learning = one atomic commit = one
PR. The repo-wide rule is in [`../../../CLAUDE.md`](../../../CLAUDE.md) ("Contributing: every
change lands via PR"); this reference is its demo-side instance.

## When to invoke

Trigger phrases that should route Claude here:

- "fold this into the skill"
- "fold this learning back"
- "save this back to the plugin"
- "update the plugin from this demo"
- "publish this update"
- "this is worth keeping — add it to the skill"

The conversation should already contain the actual learning content (the gotcha, the fix, the
proven recipe). If it doesn't, ask the user to articulate it first; do not invent.

## Step 0 — Resolve the local skills-repo path

The workflow needs the absolute path to your local clone of `dynamicweb/skills`. Resolution
order:

1. **Env var.** Check `$env:DYNAMICWEB_SKILLS_REPO`. If set and the path exists, use it.
2. **User-scope memory.** Look for a `reference` memory with name `dynamicweb-skills-repo` (or
   similar). If found and the path exists, use it.
3. **Ask.** Use `AskUserQuestion`: *"Path to your local clone of `dynamicweb/skills`? (e.g.
   `C:\VibeCode\dynamicweb-skills`)"*. Once the user answers, verify the path exists and
   contains `.claude-plugin/marketplace.json`, then **save it as a user-scope `reference`
   memory** so future invocations skip this step. Optionally suggest the user
   `setx DYNAMICWEB_SKILLS_REPO "<path>"` for a more permanent fix.

If the path doesn't pass the `.claude-plugin/marketplace.json` sanity check, abort — the user
gave the wrong directory. (There is no `plugin.json` in this repo; the marketplace registry is
the single manifest.)

## Step 1 — Route the learning: foundational skill or demo skill?

The repo enforces a **strict one-way split** (see `CLAUDE.md` → "Skill categories:
foundational vs demo"). Routing the fold correctly is now the *first* decision, not an
afterthought:

- **Is it a platform truth** — something true about Dynamicweb 10 itself (an API shape, a
  surface-order rule, a caching behaviour, a Razor/ViewModel gotcha)? Then it folds **up into
  the owning foundational skill** (`dw-render-*`, `dw-pim-*`, `dw-commerce-*`, `dw-extend-*`,
  `dw-integration-*`, `dw-setup-*`, etc.), **fully sanitized** — foundational skills carry
  zero demo/customer content (Step 1a is mandatory, not optional, for these).
- **Is it a demo-craft technique** — something about *running a demo* (scaffolding order,
  storytelling, the deserialize flow, customer-center playbook)? Then it folds into the owning
  **demo skill** (`dw-demo-base`, `dw-demo-pim`, `dw-demo-swift`, `dw-demo-erp`, or the
  `dw-integration-bc` connector demo).
- **Does the learning only make sense with the customer's name in it?** Then it is
  demo-specific — it does **not** fold anywhere in this repo. Log it in that demo's own
  `.planning/` / notes and stop.

A foundational skill must never link to or depend on a demo skill (one-way rule). If your fold
would add such a link, you have mis-routed — the content belongs in the demo skill instead.

Within the chosen skill, decide:

- **Which reference** is the right home? Read the skill's SKILL.md "Where to find things" /
  routing table to map the learning's topic to a `references/<topic>.md`. If it genuinely fits
  no existing reference, propose a new `references/<topic>.md` and check with the user first.
- **Where in the file** the new content slots in — read enough surrounding context that the
  insertion belongs (correct heading depth, consistent voice, no duplicate content).

If you're not sure, ask the user one focused question — don't guess at structure.

## Step 1a — Sanitize the candidate content BEFORE drafting the edit (load-bearing)

**Hard rule: zero customer identifiers, zero named individuals, zero session-relative time
markers in plugin content.** The repo is public at `github.com/dynamicweb/skills`. Every blob
and every commit message is visible there. Once a name lands in a commit it persists in tags +
release tarballs even after subsequent scrubs — historical leaks are forever unless you
rewrite git history and force-push (a destructive, project-wide operation that this workflow
exists to prevent). **The PR gate (Step 5) is your cheap catch window — use it; once a leak is
squash-merged to the integration branch the recovery is the expensive history rewrite.**

### What to scrub before the edit ever reaches the tree

| Category | Shapes that leak | Replace with |
|---|---|---|
| **Customer / engagement names** (any string that identifies a specific deal, account, brand the demo was built for — past, present, or future) | engagement slug used as folder name; product brand specific to a customer (e.g. a customer's flagship product line); customer's company name in any form | `<demo>` / `<brand>` / `<brand-slug>` / `Acme` / generic ("a recent demo", "a wholesale customer") |
| **Personal names** of customer, partner, OR vendor employees | first+last name in narrative; first name in attribution; surname-only in citations | role-based language (`the Dynamicweb vendor architect`, `the customer CSR`, `the demo presenter`) + the date |
| **Customer-specific paths** | `C:\Projects\Solutions\<customer-slug>\...`; `<customer-slug>/notes/...`; `<customer-slug>/RESUME.md` | `<demo>/...`, `<prior-demo>/RESUME.md` |
| **Brand identifiers in code/JSON** | `<Brand>_<Concept>.xml` worked examples baked with a real prefix; CSS custom-property tokens like `--<brand>-<colour>`; HTML data-attributes like `data-<brand>-variant`; `<brand>_custom.css` filenames; JSON `"Id"`/`"Name"` baked with a real brand | `<Brand>_<Concept>.xml`, `--brand-primary`, `data-<brand>-variant`, `<brand>_custom.css`, `"Name": "Acme"`, `"Id": "acme"` |
| **Session-relative time AND inline date stamps** | `Today's …`, `this morning`, `yesterday's`, `this week we …`; *and* prose date markers — `(verified 2026-05-21)`, `(validated DW 10.25.x, 2026-06-10)`, `Superseded 2026-05-08:` | nothing — the date already lives in `git log`; don't restate it in prose. Keep a build version if the marker carries one (`DW 10.25.x`) and drop only the date. Dates that are *data* (SQL literals; the `CUSTOMISATIONS.md` ledger column) stay. |
| **Wall-clock duration / effort claims** | `~30 seconds on a warm SQL Express`, `saves time`, `don't burn a half-day`, `you've wasted hours`, `classic time-sink` | nothing — an LLM has no notion of wall-clock time. State the actionable rule (`bundle INSERTs behind one restart`), not how long it takes or saves. |
| **Customer hex colors / domain names / phone numbers / addresses** | brand hex codes baked into examples; customer-domain hostnames in code or links; real phone numbers / street addresses in DC band / contact strip examples | `var(--brand-primary)`, `<host>`, `<phone>`, `<address>` |

### The grep pack — run BEFORE the file gets edited AND in the PR gate

A learning's drafted text often sits in `./notes/skill-learnings-*.md` first; that's where to
scrub. The same grep runs against the staged edit before commit. The pack ships in a
per-engagement scrub-list file, NOT committed into the repo — keeping the actual tokens out of
public blobs.

**Location of the scrub-list file:** `$DYNAMICWEB_SKILLS_REPO\..\..\scrub-list.txt` (one level
above the local clone, gitignored by construction since it lives outside the repo). One token
per line; blank lines and `#` comments allowed. The file ships seeded with the known
historical leaks from prior engagements + the current engagement's slug.

If the file doesn't exist, the fold-back creates a stub on first run and asks the user to add
the current engagement's tokens before proceeding.

```powershell
# Build the regex pack from the external list (paths shown — adapt to where you cloned).
$scrubList = "$env:DYNAMICWEB_SKILLS_REPO\..\..\scrub-list.txt"
if (-not (Test-Path $scrubList)) {
    Write-Error "Scrub-list missing at $scrubList — create it (one token per line) before folding."
    return
}
$tokens = Get-Content $scrubList | Where-Object { $_ -and -not $_.StartsWith('#') }
$nameRx = ($tokens | ForEach-Object { [regex]::Escape($_) }) -join '|'

# 1. Source notes
Select-String -Path .\notes\skill-learnings-*.md -Pattern $nameRx
# Staged edit (run from $DYNAMICWEB_SKILLS_REPO before commit)
git diff --staged | Select-String -Pattern $nameRx

# 2. Session-relative time (constant — not engagement-specific, lives inline)
$timeRx = "Today's |today's |This morning|this morning|Yesterday|yesterday(?!'s prices)|This week|this week"
Select-String -Path .\notes\skill-learnings-*.md -Pattern $timeRx
git diff --staged | Select-String -Pattern $timeRx

# 3. Customer-specific paths (constant — matches the path shape, not specific slugs)
Select-String -Path .\notes\skill-learnings-*.md -Pattern 'C:\\Projects\\Solutions\\[a-z0-9-]+'
git diff --staged | Select-String -Pattern 'C:\\Projects\\Solutions\\[a-z0-9-]+'
```

**Any hit in any of those three packs blocks the fold.** Sanitize the source
`notes/skill-learnings-*.md` first (so the demo's own notes can stay concrete) into a
derivative learning that's vendor-generic — then carry only the vendor-generic version into
the edit. Two paragraphs side-by-side in the conversation is fine: "what happened (named)" →
"what's the durable lesson (generic)". Only the generic side gets committed.

### When the structural learning seems to depend on the customer's name

It almost never does. If the rule is "demo X did Y and learned Z", `Z` is the durable part.
`X` is provenance noise. Drop `X`. If you genuinely cannot say `Z` without `X`, the learning is
probably demo-specific and shouldn't be folded — log it as a demo-local note instead (Step 1).

The same rule applies to vendor / partner / customer **individuals**. Architectural advice
"blessed by `<named architect>` at vendor X on `<date>`" loses nothing structural when
rewritten as "vendor-blessed by the `<role>` (`<date>` architecture call)". The provenance
value is the role + date, not the person.

### When to expand the known-names list

When a new customer engagement opens, add the customer slug (and any personal names in play)
to the off-repo scrub-list file BEFORE the first fold for that demo. The fold-back should ask
once per session: *"Any new customer/personal names to add to the scrub pack for this
engagement?"* — additions go to the scrub-list file, never into the repo. Future folds inherit
the expanded pack.

## Step 1b — Content-hygiene gate (load-bearing — this is how the corpus stays correct)

Sanitization protects the customer; this step protects the *corpus*. Fold-backs that skip it
produced, historically: a pivot that left the retracted model live in five other files, a
retracted API claim that survived three releases next to the file that retracted it, and the
same lesson recorded four times in different words. Run all three checks BEFORE drafting the
edit:

### 1. Supersede sweep — when the learning corrects, retracts, or pivots existing guidance

Grep **all of `skills/`** (SKILL.md frontmatter `description:` lines included) for the old
claim's distinctive tokens — the API name, the folder pattern, the error message, the rule
wording. Every hit must be either rewritten to the new guidance or replaced with a **one-line
tombstone**:

> Superseded YYYY-MM-DD: <new rule in one sentence> — see <canonical reference>.

Never leave the old recipe loadable next to the new one: a model that loads only the un-swept
file will follow the retracted guidance, and the skill's own audit may then flag the output it
produced. The sweep is cheap (one grep, a handful of edits); the alternative is a contradiction
that ships until someone audits the whole corpus.

### 2. Dedup check — is this lesson already recorded?

Grep the target skill's `references/` (and sibling skills if the topic straddles) for the
lesson's key tokens. If a version of the lesson already exists:

- **Update the existing canonical home** — sharpen it, add the new evidence, correct it.
- Where other files need to surface it, add a **one-line pointer** to the canonical home,
  never a restated copy.

One lesson, one home. Restatements drift independently and become contradictions later.

### 3. Integrate, don't append

The default move for a fold-back is to **rewrite the existing sentence or section**, not to
append a new dated subsection below it. Specifically:

- If the new learning qualifies an existing claim ("X updates automatically" → "X can be
  static on some builds"), edit the original claim so it no longer over-promises; don't stack a
  warning block under a sentence that still asserts the opposite.
- A "validated on DW 10.X.Y" marker belongs inline on the rule it validates, and only when a
  future reader could otherwise mistake the rule for hypothesis. Don't accumulate per-fold date
  stamps as provenance — the dates live in `git log`.
- Append a genuinely new subsection only for a genuinely new topic.

### 4. Router + size maintenance

- If the fold changes what a reference covers, update the owning SKILL.md "Where to find
  things" row (trigger phrases included) in the same edit. Do NOT grow the frontmatter
  `description:` with recipe detail — descriptions are trigger phrases + scope only; they load
  into every session.
- Avoid literal counts in routing prose ("Five trigger shapes", "Seven references") — they rot
  on the next fold. Use count-free phrasing.
- If the target reference would exceed ~20KB after the edit, stop and propose a split (or a
  different home) to the user instead of appending.

## Step 2 — Make the edit

Edit the file at `$DYNAMICWEB_SKILLS_REPO/skills/<skill>/references/<topic>.md` (or the
SKILL.md if the learning is orchestrator-level, not topic-level).

Voice + structure rules (match what's already there):

- Lead with the **rule or recipe**, then the **why** (often a past incident or surprising
  default), then the **how** (commands, recipes, verification).
- Concrete commands beat prose. Include the exact `dotnet`, `git`, `Invoke-RestMethod`,
  `sqlcmd`, or PowerShell snippet that worked.
- **Phrase instructions positively — say what to do, not just what to avoid.** A model follows
  "DO A" more reliably than "don't do B": a bare prohibition raises B's salience and leaves the
  target underspecified. Reach for contrast only when B is the model's natural pull *and* a
  predictable failure mode, and then prefer the paired form ("serialize with the DW serializer,
  not a raw XML export") over a bare "don't" — it gives both the target and the boundary. A
  one-line reason sharpens it further ("read prices through the ViewModel — a raw `SELECT` leaks
  cross-scope pricing"). A bare "don't do B" is the last resort. A good test: would a competent
  model, reading only "DO A", still plausibly do B? If no, the "not B" is noise; drop it.
  (Few-shot bad→good example pairs are exempt — that's a different mechanism.)
- Prefer rewriting the existing text over appending below it (Step 1b §3). If a future reader
  could mistake the new content for hypothetical advice, mark it as proven inline — sparingly.
  **Keep dates out of the skill body: the date lives in `git log`. Never "today" / "this morning" / a `(verified <date>)` stamp.** (Step 1a).
- **Provenance citations name roles, never individuals or dates.** "Per the Dynamicweb vendor
  architect" — not "Per `<Person Name>` (2026-05-13 …)". Apply
  to customer-side, partner-side, AND vendor-side individuals.
- Keep existing cross-references intact. If you change a heading, search the other skills for
  links to it and update them too. **Links flow one way: a `dw-demo-*` skill may reference a
  foundational one, never the reverse** (the one-way rule).

## Step 3 — Validate

```powershell
cd $env:DYNAMICWEB_SKILLS_REPO
python3 scripts/validate-skills.py
```

Must exit 0. Errors → fix before continuing. The validator checks the marketplace schema,
folder/name/path agreement, relative-link resolution, and absence of UTF-8 BOMs; if you only
edited a reference file under `skills/*/references/`, it should pass trivially. For a deeper
check, also run `claude plugin validate ./`.

## Step 4 — Bump the version (one place)

Read the current version from `.claude-plugin/marketplace.json` (`metadata.version`) and bump
per semver:

- **Patch** (3.0.1 → 3.0.2) — additive learning, bug fix, clarification. Default for
  fold-back operations.
- **Minor** (3.0.2 → 3.1.0) — new skill added, new reference doc, contract change to an
  existing recipe (e.g. surface order rewritten).
- **Major** (3.x.y → 4.0.0) — only when explicitly declaring a breaking change to the bundle
  layout or skill contracts.

There is a **single version** to bump now: `metadata.version` in `marketplace.json`. The old
"bump both plugin.json and marketplace.json, keep them in lockstep" rule is retired — this repo
has no `plugin.json`, and the bundle entries under `plugins[]` no longer carry per-bundle
versions.

## Step 4a — Update README.md and CHANGELOG.md (mandatory when content/scope changes)

Stale docs are the difference between partners seeing the current contents vs. an outdated
picture. In the **same commit** as the skill edit + version bump:

- **`README.md`** — the **Skills** table/section: add a block for any new skill; revise the
  one-line description if a skill's scope materially expanded. The **Plugins** table: update if
  a skill's bundle membership changed. The **Structure** tree: add any new skill directory.
- **`CHANGELOG.md`** — add the entry under the new version heading (matching
  `metadata.version`), describing what changed and why.

Keep all of this in the one atomic commit — don't split into a follow-up "docs:" commit.
Splitting hides the connection between version + content + docs.

## Step 5 — Branch, atomic commit, push, open PR

Fold-backs do **not** push to the integration branch directly. Compose **one atomic commit on
a branch**, then open a PR.

Compose a commit/PR subject that names **what changed** and **why it was worth folding back**.
**The same sanitization rule from Step 1a applies to the commit message and PR body — no
customer names, no personal names, no "Today's"/"this morning" temporal prefixes.** Messages
and PR bodies ship in `git log`, in GitHub's commit view, and in `gh pr view` — anywhere a
clone or a public PR is visible. A leak in a message is the same severity as a leak in a blob.

```
Fold demo-build learning: <one-line topic>

<2–4 sentences describing the learning, why the previous skill content
was wrong or incomplete, and the symptom that surfaced it. Reference the
file(s) changed. Avoid "minor update" / "tweaks" — those rot. Use absolute
dates ("a 2026-05-21 walkthrough") rather than relative markers ("today's
demo"), and refer to demos / vendors / partners / customers by role + date,
never by name.>
```

Do **not** add `Co-Authored-By` or any self-attribution line (repo rule, `CLAUDE.md` →
"Commits").

**Final pre-commit grep** (mandatory; same pack as Step 1a, run one last time against the FULL
staged change including the message):

```powershell
$tokens = Get-Content "$env:DYNAMICWEB_SKILLS_REPO\..\..\scrub-list.txt" |
          Where-Object { $_ -and -not $_.StartsWith('#') }
$nameRx = ($tokens | ForEach-Object { [regex]::Escape($_) }) -join '|'
$timeRx = "Today's |today's |This morning|this morning|Yesterday[^\s]"

git diff --staged | Select-String -Pattern $nameRx
git diff --staged | Select-String -Pattern $timeRx
Get-Content .git\COMMIT_EDITMSG -Raw | Select-String -Pattern $nameRx
Get-Content .git\COMMIT_EDITMSG -Raw | Select-String -Pattern $timeRx
```

Any hit blocks the commit. Sanitize and re-stage / re-edit the message. Then:

```powershell
cd $env:DYNAMICWEB_SKILLS_REPO
git checkout -b fold/<short-topic>           # branch off the integration branch
git add .claude-plugin README.md CHANGELOG.md skills/<skill>/<file>
git commit -m "<the message above>"
git push -u origin fold/<short-topic>
gh pr create --base v2 --title "<the subject>" --body "<the body>"
```

`--base v2` while `v2` is the integration branch; switch to `--base main` once `v2` has merged.
**Do not tag from this workflow** — release tags are cut on the integration branch when a
version ships, not per fold.

## Step 6 — After the PR merges: refresh the local marketplace clone

Once the PR is reviewed and **squash-merged**:

```powershell
cd $env:USERPROFILE\.claude\plugins\marketplaces\dynamicweb-skills
git pull origin <integration-branch>
```

This makes the new version visible to `/plugin update`. Without it, Claude Code's local
marketplace mirror is still at the old version and the update command is a no-op. (If you added
the marketplace as `claude plugin marketplace add dynamicweb/skills`, the clone directory is
named `dynamicweb-skills`.)

## Step 7 — Tell the user the slash commands to refresh the install

Claude cannot issue slash commands. After merge, output a clear final-step message for the
user. Name the **bundle(s)** that include the edited skill (a demo-craft fold affects
`dynamicweb-presales`; a foundational fold affects whichever bundles list that skill — e.g. a
`dw-render-*` edit affects `dynamicweb-frontend`):

> Merged and refreshed the marketplace clone. To activate the new content in this (and other)
> Claude Code sessions, run:
>
> ```
> /plugin update <bundle-name>@dynamicweb-skills
> /reload-plugins
> ```
>
> After `/reload-plugins`, the new content is live without restarting the session.

**`update`, not `install`.** When the bundle is already installed, `/plugin install` is a no-op
that prints *"already installed"* and leaves the active install at the old version.
`/plugin update` is what swings the install to the new cached version. Use `install` only for a
genuine first install on a fresh machine.

## Verification gate — this workflow is NOT complete until

1. The learning was routed correctly (foundational vs demo, Step 1) and adds no
   foundational→demo link.
2. `python3 scripts/validate-skills.py` returned exit 0.
3. `metadata.version` bumped in `marketplace.json`.
4. **README.md + CHANGELOG.md updated** to reflect the new content (Step 4a), in the same
   commit.
5. **Sanitization grep packs (Step 1a + final pre-commit) both returned zero hits** — across
   source notes, the staged diff, AND the commit message / PR body.
6. **Content-hygiene gate passed (Step 1b)** — supersede sweep run over `skills/` if the
   learning corrects anything; no second copy of an existing lesson; owning SKILL.md routing
   row updated if scope changed.
7. The branch is pushed and a **PR is open** against the integration branch (not pushed
   directly).
8. After merge: the marketplace clone is at the new commit, and the user has the
   slash-command pair to run.

If any of these fail, surface the failure — don't silently declare success. A half-folded
learning is worse than not folding it. A **leak that reaches the integration branch** is worse
still: catch it in the PR (amend the branch and force-push *the branch* before merge — cheap);
only a leak that has *merged* forces the project-wide history rewrite below.

## Recovery from a leak that merged to the integration branch

If a customer name or session-relative time marker reaches the integration branch (subject,
body, or blob) despite the gates above, the only clean recovery is full history rewrite +
force-push. This is destructive — every collaborator with a clone must re-clone or
`git reset --hard origin/<branch>` — so it's a last resort.

**Before merge it is cheap:** amend the offending commit on the PR branch (`git commit --amend`
or `git rebase`), re-run the grep pack, and `git push --force-with-lease` *the branch*. The PR
updates in place; nothing public on the integration branch was ever touched. This pre-merge
window is the whole point of the PR gate.

If it already merged, the recipe used during a prior sweep:

1. **Scrub working-tree content** first via direct `Edit`s, replacing customer-named strings
   with `<demo>`/`<brand>`/`Acme`-style placeholders.
2. **Rewrite commit messages** across `--branches --tags` via `git filter-branch --msg-filter
   <python-script>` (per-SHA full-message replacement for affected commits, defensive
   substring-replace fallback for the rest).
3. **Rewrite blob contents** across history via `git filter-branch --tree-filter
   <python-script> --prune-empty` (walk every text file, apply the substitutions, longest
   patterns first).
4. **Drop `refs/original/*` backup refs** so `git log --all` doesn't surface pre-rewrite
   history.
5. **Force-push** with `git push --force-with-lease=<branch>:<pre-rewrite-sha> origin <branch>`
   and `git push --force origin --tags`. Use `--force-with-lease`, never bare `--force`.
6. **Notify collaborators** to `git fetch --tags --force && git reset --hard
   origin/<branch>`.

The cost of this dance is high enough that the Step 1a + final pre-commit grep packs are not
"extra paranoia" — they are the cheaper option by orders of magnitude. Run them.

## Anti-patterns

- **Pushing a fold-back straight to the integration branch.** Every fold goes through a PR.
  The PR is the cheap catch window for leaks and the review gate for correctness.
- **Bundling two unrelated learnings in one PR.** One learning = one atomic commit = one PR.
- **Bumping version without changing skill content.** Defeats the cache-key purpose. If you
  only edited the validator or CI, no version bump is needed.
- **Bumping the version without updating README.md / CHANGELOG.md.** Stale docs ship an
  outdated picture (Step 4a).
- **Skipping the Step 1a sanitization grep.** Customer-name leaks in a public repo are a
  "capital sin". The grep takes seconds; post-merge recovery takes the rest of an afternoon and
  costs every collaborator a clone reset.
- **Letting a personal name through because "they're a vendor employee, not a customer".** The
  rule covers vendor / partner / individual names too — provenance is "the Dynamicweb vendor
  architect (`<date>`)", never `<Person Name>`.
- **Using "Today's …" / "this morning …" / "yesterday …" in commit prose.** The dates are
  already in `git log`. Use absolute dates inline when structurally important; otherwise drop
  the temporal prefix.
- **Folding a learning that's actually demo-specific.** If the gotcha only applies to one
  customer's quirky data, it belongs in that demo's `.planning/`, not in the repo. (A learning
  that *requires* the customer's name to be coherent is a strong signal it's demo-specific.)
- **Folding a platform truth into a demo skill (or vice versa).** Route it per Step 1.
  Platform truths go up into foundational skills, fully sanitized; demo-craft goes into demo
  skills. Adding a foundational→demo link is a boundary violation.
- **Folding without context.** If the user says "save that thing we just figured out" and
  you're not sure exactly which thing, ask. Don't fold a paraphrase.
- **Touching `dw-integration-bc` for non-BC learnings.** Each skill has a tight scope;
  cross-skill demo learnings usually live in `dw-demo-base` (foundation rules) or `dw-demo-erp`
  (integration concerns), or get split.
- **Appending a warning next to a claim it contradicts.** If the learning shows an existing
  sentence is wrong, rewrite that sentence (Step 1b §3).
- **Folding a correction into one file and calling it done.** A pivot or retraction must sweep
  all of `skills/` (Step 1b §1).
- **Recording the same lesson in a second home.** If a grep finds the lesson already exists,
  sharpen the canonical copy and pointer to it (Step 1b §2).

## Reference: file layout

```
$DYNAMICWEB_SKILLS_REPO/
├── .claude-plugin/
│   └── marketplace.json             ← metadata.version here (single manifest; no plugin.json)
├── README.md                        ← updated when content/scope changes (Step 4a)
├── CHANGELOG.md                     ← entry per version bump (Step 4a)
├── scripts/validate-skills.py       ← run before commit (Step 3)
└── skills/
    ├── dw-demo-base/                ← demo: foundation for the presales chain
    │   ├── SKILL.md
    │   └── references/<topic>.md     ← demo-craft learnings land here
    ├── dw-demo-pim/                 ← demo
    ├── dw-demo-swift/               ← demo
    ├── dw-demo-erp/                 ← demo
    ├── dw-integration-bc/           ← demo: live BC connector via ngrok
    ├── dw-render-*/                 ← foundational (platform truths fold up here)
    ├── dw-pim-*/  dw-commerce-*/    ← foundational
    ├── dw-extend-*/ dw-integration-*/  ← foundational
    └── dw-setup-*/ dw-content-modelling/ dw-data-access/ …  ← foundational
```
