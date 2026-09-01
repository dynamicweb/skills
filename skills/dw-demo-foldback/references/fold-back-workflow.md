# Folding demo-build learnings back into the dynamicweb/skills repo

## Contents

- [When to invoke](#when-to-invoke)
- [Step 0 — Resolve the local skills-repo path](#step-0--resolve-the-local-skills-repo-path)
- [Step 1 — Route the learning: foundational skill or demo skill?](#step-1--route-the-learning-foundational-skill-or-demo-skill)
- [Step 1a — Sanitize the candidate content BEFORE drafting the edit (load-bearing)](#step-1a--sanitize-the-candidate-content-before-drafting-the-edit-load-bearing)
- [Step 1b — Content-hygiene gate (load-bearing — this is how the corpus stays correct)](#step-1b--content-hygiene-gate-load-bearing--this-is-how-the-corpus-stays-correct)
- [Step 1c: Lifting a script from a demo build](#step-1c-lifting-a-script-from-a-demo-build)
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
surface order, a missing prereq — fold it back **while the demo's context is still fresh in the
conversation**, not from notes a week later. **Maintainer-only** (needs write access + a local clone
of `dynamicweb/skills`; consumers can open a PR instead — same workflow). **Every fold-back lands
via a pull request** — one learning = one atomic commit = one PR; the repo-wide rule is
[`../../../CLAUDE.md`](../../../CLAUDE.md) "Contributing".

## When to invoke

The trigger phrases live in `SKILL.md` "Folding demo-build learnings back" ("fold this into the
skill", "save this back to the plugin", …). The conversation should already contain the actual
learning (the gotcha, the fix, the proven recipe); if it doesn't, ask the user to articulate it
first — do not invent.

## Step 0 — Resolve the local skills-repo path

Resolve the absolute path to the local `dynamicweb/skills` clone, in order: (1)
`$env:DYNAMICWEB_SKILLS_REPO`; (2) a user-scope `reference` memory named `dynamicweb-skills-repo`;
(3) ask via `AskUserQuestion`, then save the answer as a user-scope `reference` memory (and suggest
`setx DYNAMICWEB_SKILLS_REPO "<path>"`). Sanity check: the path must contain
`.claude-plugin/marketplace.json` (the single manifest — there is no `plugin.json`); abort if not.

## Step 1 — Route the learning: foundational skill or demo skill?

The repo enforces a **strict one-way split** (`CLAUDE.md` → "The one-way boundary (foundational
vs demo)"); routing is the *first* decision:

- **A platform truth** (an API shape, surface-order rule, caching behaviour, Razor/ViewModel gotcha)
  folds **up into the owning foundational skill** (`dw-render-*`, `dw-pim-*`, `dw-commerce-*`,
  `dw-extend-*`, `dw-integration-*`, `dw-setup-*`, …), **fully sanitized** — foundational skills
  carry zero demo/customer content.
- **A demo-craft technique** (scaffolding order, storytelling, the deserialize flow,
  customer-center playbook) folds into the owning **demo skill** (`dw-demo-base`, `dw-demo-pim`,
  `dw-demo-swift`, `dw-demo-erp`, `dw-integration-bc`).
- **A learning that only makes sense with the customer's name in it** is demo-specific — it does
  **not** fold; log it in that demo's own `.planning/` notes and stop.

A foundational skill must never link to or depend on a demo skill; a fold that would add such a
link is mis-routed. Within the chosen skill, pick the reference via the SKILL.md routing table (a
genuinely new topic → propose a new `references/<topic>.md` and check with the user first), and read
enough surrounding context that the insertion lands at the right heading depth with no duplicate
content. If unsure, ask one focused question — don't guess at structure.

## Step 1a — Sanitize the candidate content BEFORE drafting the edit (load-bearing)

**Hard rule: zero customer identifiers, zero named individuals, zero session-relative time
markers in plugin content.** The repo is public at `github.com/dynamicweb/skills`; every blob and commit
message is visible there, and a merged leak persists in history until a destructive rewrite + force-push.
**The PR gate (Step 5) is the cheap catch window — use it.**

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

A learning's drafted text often sits in `./notes/skill-learnings-*.md` first — scrub there; the same grep
runs against the staged edit before commit. **There is no scrub-list file — the token list is derived
in-session, every fold**: enumerate the engagement's tokens explicitly and write the list out in the
conversation for the user to review. Enumerate at least:

- customer / brand / engagement names, **including misspellings and slugs** (folder names,
  hostnames, `<sub>.mydwsiteN.com` subdomains);
- persona and account names (buyers, CSRs, admins, distributor/dealer accounts);
- engagement domain vocabulary — field names, category names, example products only this
  customer would use. A winery demo's `GrapeVariety` field or a "Reserve Pinot" example
  product identifies the engagement as surely as its name does;
- ids, paths, and credentials minted for the demo.

```powershell
# 1. Engagement tokens — enumerated from the session context above, never read from a file.
$tokens = @('BrandName', 'brand-slug', 'brand.mydwsiteN.com', 'Persona Name' <# … #>)
$nameRx = ($tokens | ForEach-Object { [regex]::Escape($_) }) -join '|'

# Source notes
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

**Any hit in any of those three packs blocks the fold.** Sanitize the source notes into a vendor-generic
derivative first; only the generic side gets committed. **The grep only catches tokens you enumerated; the
re-read catches the rest** — after drafting, read the staged diff once as an outsider and ask of every
concrete string "is this Dynamicweb-generic, or engagement-derived?" This re-read is mandatory: enumeration
misses exactly the tokens you didn't think of.

### When the structural learning seems to depend on the customer's name

It almost never does: in "demo X did Y and learned Z", `Z` is the durable part and `X` is
provenance noise — drop `X`. If you genuinely cannot say `Z` without `X`, the learning is
demo-specific and shouldn't be folded (Step 1). Same for individuals: "blessed by `<named
architect>`" rewrites to "vendor-blessed by the `<role>` (`<date>` architecture call)" — the
provenance value is the role + date, not the person.

## Step 1b — Content-hygiene gate (load-bearing — this is how the corpus stays correct)

Sanitization protects the customer; this step protects the *corpus* — skipping it has left retracted
claims live next to their retractions and the same lesson recorded four times. Run these checks BEFORE
drafting the edit:

### 1. Supersede sweep — when the learning corrects, retracts, or pivots existing guidance

Grep **all of `skills/`** (frontmatter `description:` lines included) for the old claim's
distinctive tokens — API name, folder pattern, error message, rule wording. Every hit is either
rewritten to the new guidance or replaced with a one-line tombstone ("Superseded YYYY-MM-DD: <new
rule> — see <canonical reference>"). Never leave the old recipe loadable next to the new one — a
model that loads only the un-swept file follows the retracted guidance.

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

### 5. Dead-layer-name sweep — when the fold references a Distribution layer

Before folding anything that names a Distribution layer (`base`, `surface-swift`, `feature-*`,
`theme-default`, editions), sweep every layer name against `layers/INDEX.json` on the latest
gate-proven `main`: **live** (`active`/`deprecated`) — use it, preferring the successor over a
`deprecated` layer; **retired** — rewrite the instruction to the entry's `supersededBy` successor (a
retirement *note* may stay; an *instruction* building from the dead name goes); **absent** — stop,
the name is wrong. Keep the retired-name list in `INDEX.json`, never hardcoded into
`scripts/validate-skills.py` — a blocklist forks a second source of truth that drifts on the next
rename.

## Step 1c: Lifting a script from a demo build

A demo build's `scripts/` folder is a fold-back source like its notes, with one extra bar and a
few extra leaks. The target contract (PowerShell 7, help block, `-WhatIf`, connection discovery,
the `## Scripts` table) is owned by `dw-skill-authoring` ("Shipping scripts"); this step owns
what changes on the way from a demo copy to a shipped one.

**Lift a script only when the shape recurs.** The bar is two or more engagements with their own
implementation of the same operation, or one engagement plus a fenced block already in a
reference that the script replaces. Iterations inside one engagement (`translate-v3.sql`,
`fix-again.ps1`) are that demo's business and stay in its folder. Route the shipped script with
Step 1: the foundational skill that owns the platform lesson, or the demo skill that owns the
demo-only guardrail.

**Sanitize per Step 1a, plus the shapes a script adds.** Every environment literal becomes a
parameter, an `$env:` variable, or discovery from project files; sample data moves to a
`-DataFile` the caller supplies. The grep pack gains these classes:

| Class | Leaks as | Replace with |
|---|---|---|
| Hosts and ports | `<sub>.mydwsiteN.com`, `localhost:<port>`, `<server>\SQLEXPRESS;Database=<demo>` | `-BaseUrl` / `-Port` / `-ConnectionString` (mandatory, no default) or `launchSettings.json` discovery |
| Tokens and keys | any `CLAUDE.<hex>` / `mcp.<hex>` literal, a key as a parameter default, a customer-named `$env:` name | `$env:DW_API_TOKEN` / `$env:DW_MCP_TOKEN`, masked in output |
| Passwords and connection strings | `Password=...` in a string, a credentials file as a default path | `$env:DW_SQL_CONNECTION`; Integrated Security in examples |
| Ids and personas | user names, profile / group / page ids, SKUs, VINs, `_<demo>*` scratch tables | `-DataFile`; examples use `SKU-0001` |
| Paths | `C:\Projects\Solutions\<slug>\...`, `notes\credentials.local.md` | `-SolutionPath` (mandatory), `$PSScriptRoot`-relative |
| Task and object names | `<Customer> Demo - SQL Runner` | vendor-generic (`DW SQL Runner (agent)`) |

A detector keeps its detection targets (the stock Swift vendor strings, `noreply@noreply.com`)
with an inline note saying so, so a later sanitization pass does not strip the detector.

**One lesson, one home.** The fenced block the script supersedes becomes a one-line pointer to
the script in the same PR, and the Step 1b §1 supersede sweep runs on the block's distinctive
tokens (`RunSqlScheduledTaskAddIn`, `Get-NetTCPConnection`, ...) so no second copy survives in
another reference. The demo's own copy is retired, or its header points at the shipped script,
so the next engagement extends the shipped one instead of forking it again.

**Smoke-test rule.** A write script is smoke-tested on a local host you own before its PR is
opened. A hosted install is never the first target: only after the script has passed locally,
and then under the shared-install discipline in
[`../../dw-demo-hosted/SKILL.md`](../../dw-demo-hosted/SKILL.md) (writes scoped to the demo's
own areas, destructive operations announced, changes recorded in `CUSTOMISATIONS.md`). Hosted
installs are frequently shared with the customer or a partner, and their "lying success" (a
write returns `ok` and changes nothing) means a smoke test there proves nothing anyway.
Read-only scripts may run against a hosted install where the surface exists; most hosted
installs expose no SQL, so the SQL-based scripts have no target there.

## Step 2 — Make the edit

Edit the file at `$DYNAMICWEB_SKILLS_REPO/skills/<skill>/references/<topic>.md` (or the
SKILL.md if the learning is orchestrator-level, not topic-level).

Voice + structure rules (match what's already there):

- Lead with the **rule or recipe**, then the **why** (often a past incident or surprising
  default), then the **how** (commands, recipes, verification).
- Concrete commands beat prose. Include the exact `dotnet`, `git`, `Invoke-RestMethod`,
  `sqlcmd`, or PowerShell snippet that worked.
- **Phrase instructions positively — say what to do, not just what to avoid.** A model follows
  "DO A" more reliably than "don't do B" (the prohibition raises B's salience and leaves the target
  underspecified). Keep contrast only when B is the model's natural pull and a predictable failure
  mode, preferring the paired form ("serialize with the DW serializer, not a raw XML export") over a
  bare "don't". Test: would a competent model, reading only "DO A", still plausibly do B? If no, the
  "not B" is noise. (Few-shot bad→good pairs are exempt.)
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

Must exit 0; fix errors before continuing. What it checks (schema, links, description cap, BOM,
mojibake — repair the latter with `ftfy.fix_encoding`, not by hand) is documented in the repo
[`CLAUDE.md`](../../../CLAUDE.md) "Validation". For a deeper check, also run `claude plugin validate ./`.

## Step 4 — Bump the version (one place)

Bump `metadata.version` in `.claude-plugin/marketplace.json` — the **single** version (no
`plugin.json`, no per-bundle versions) — per semver: **patch** for an additive learning / fix /
clarification (the fold-back default); **minor** for a new skill, new reference doc, or a contract
change to an existing recipe; **major** only for a declared breaking change to bundle layout or
skill contracts.

## Step 4a — Update README.md and CHANGELOG.md (mandatory when content/scope changes)

In the **same atomic commit** as the skill edit + version bump (never a follow-up "docs:" commit):
**`README.md`** — Skills table (new skill block / revised one-liner on a scope change), Plugins table
(bundle-membership changes), Structure tree (new directories); **`CHANGELOG.md`** — an entry under
the new version heading describing what changed and why.

## Step 5 — Branch, atomic commit, push, open PR

The git mechanics are the repo-wide contract in [`../../../CLAUDE.md`](../../../CLAUDE.md)
"Contributing: every change lands via PR": branch off the integration branch, one learning = one
atomic commit = one PR (`gh pr create` targeting the integration branch), squash-merge, no
`Co-Authored-By` or self-attribution, and no tags from this workflow — releases are tagged when a
version ships, not per fold.

Two fold-specific rules on top:

- **The commit message and PR body are sanitization surfaces.** Step 1a applies to them too — no
  customer names, no personal names, no session-relative time prefixes. Name **what changed** and
  **why it was worth folding back**; refer to demos / vendors / partners / customers by role + date,
  never by name; avoid "minor update" / "tweaks".
- **Final pre-commit grep (mandatory)** — the same pack as Step 1a, run one last time against the
  FULL staged change including the message:

```powershell
$tokens = @('BrandName', 'brand-slug' <# the same in-session token list from Step 1a #>)
$nameRx = ($tokens | ForEach-Object { [regex]::Escape($_) }) -join '|'
$timeRx = "Today's |today's |This morning|this morning|Yesterday[^\s]"

git diff --staged | Select-String -Pattern $nameRx
git diff --staged | Select-String -Pattern $timeRx
Get-Content .git\COMMIT_EDITMSG -Raw | Select-String -Pattern $nameRx
Get-Content .git\COMMIT_EDITMSG -Raw | Select-String -Pattern $timeRx
```

Any hit blocks the commit — sanitize, re-stage / re-edit the message, and only then push and open
the PR.

## Step 6 — After the PR merges: refresh the local marketplace clone

Once the PR is squash-merged, `git pull origin <integration-branch>` in
`$env:USERPROFILE\.claude\plugins\marketplaces\dynamicweb-skills` — without it the local
marketplace mirror stays at the old version and `/plugin update` is a no-op.

## Step 7 — Tell the user the slash commands to refresh the install

Claude cannot issue slash commands — after merge, tell the user to run
`/plugin update <bundle-name>@dynamicweb-skills` then `/reload-plugins` (live without a session
restart), naming the bundle(s) that include the edited skill (demo-craft → `dynamicweb-presales`;
a foundational fold → whichever bundles list that skill). **`update`, not `install`** — on an
already-installed bundle `/plugin install` is a no-op that leaves the old version active.

## Verification gate — this workflow is NOT complete until

1. Routed correctly (foundational vs demo, Step 1); no foundational→demo link added.
2. `python3 scripts/validate-skills.py` exit 0.
3. `metadata.version` bumped; **README.md + CHANGELOG.md updated in the same commit** (Step 4a).
4. **Both sanitization grep packs returned zero hits** — source notes, staged diff, AND commit
   message / PR body.
5. **Content-hygiene gate passed (Step 1b)** — supersede sweep run if the learning corrects
   anything; no second copy of an existing lesson; routing row updated on a scope change; every
   Distribution layer name checked against `INDEX.json`.
6. Branch pushed and a **PR open** against the integration branch; after merge, the marketplace
   clone is at the new commit and the user has the slash-command pair.

If any of these fail, surface the failure — a half-folded learning is worse than not folding it,
and a leak that *merges* forces the history rewrite below (catch it in the PR instead — cheap).

## Recovery from a leak that merged to the integration branch

**Before merge it is cheap:** amend the offending commit on the PR branch, re-run the grep pack,
and `git push --force-with-lease` *the branch* — the PR updates in place and nothing public was
touched. That window is the whole point of the PR gate.

If a leak **merged**, the only clean recovery is a full history rewrite + force-push — destructive:
every collaborator must re-clone or hard-reset. The recipe:

1. Scrub working-tree content via direct `Edit`s (named strings → `<demo>`/`<brand>`/`Acme` placeholders).
2. Rewrite commit messages across `--branches --tags` via `git filter-branch --msg-filter`.
3. Rewrite blob contents across history via `git filter-branch --tree-filter … --prune-empty`
   (longest patterns first).
4. Drop the `refs/original/*` backup refs so `git log --all` doesn't surface pre-rewrite history.
5. `git push --force-with-lease=<branch>:<pre-rewrite-sha> origin <branch>` and
   `git push --force origin --tags` — `--force-with-lease`, never bare `--force`.
6. Notify collaborators: `git fetch --tags --force && git reset --hard origin/<branch>`.

This cost is why the Step 1a + Step 5 grep packs are mandatory, not paranoia.

## Anti-patterns

- **Pushing a fold-back straight to the integration branch** — every fold goes through a PR, the
  cheap catch window for leaks and the review gate for correctness.
- **Bundling two unrelated learnings in one PR** — one learning = one atomic commit = one PR.
- **Bumping the version without changing skill content**, or **without updating README.md /
  CHANGELOG.md** (Step 4a).
- **Skipping the Step 1a sanitization grep** — it takes seconds; post-merge recovery costs every
  collaborator a clone reset.
- **Letting a personal name through because "they're a vendor employee"** — the rule covers
  vendor / partner / customer individuals alike; provenance is role + date, never a name.
- **"Today's …" / "this morning …" in commit prose** — dates live in `git log`; use absolute
  dates only when structurally important.
- **Folding a learning that's actually demo-specific** — one that *requires* the customer's name
  to be coherent belongs in that demo's `.planning/`, not the repo.
- **Mis-routing across the foundational/demo boundary** (Step 1) — platform truths fold up,
  sanitized; demo-craft folds into demo skills; a foundational→demo link is a violation.
- **Folding without context** — if unsure which "thing we just figured out", ask; don't fold a
  paraphrase.
- **Touching `dw-integration-bc` for non-BC learnings** — cross-skill demo learnings live in
  `dw-demo-base` or `dw-demo-erp`, or get split.
- **Appending a warning next to a claim it contradicts** — rewrite the claim (Step 1b §3).
- **Folding a correction into one file and calling it done** — a retraction sweeps all of
  `skills/` (Step 1b §1).
- **Recording the same lesson in a second home** — sharpen the canonical copy and pointer to it
  (Step 1b §2).
- **Leaving a retired Distribution layer name as a build instruction** — rewrite to the
  `supersededBy` successor per `INDEX.json` (Step 1b §5).

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
    │   ├── references/<topic>.md     ← demo-craft learnings land here
    │   └── scripts/<Verb-Noun>.ps1   ← lifted scripts land here (Step 1c)
    ├── dw-demo-pim/                 ← demo
    ├── dw-demo-swift/               ← demo
    ├── dw-demo-erp/                 ← demo
    ├── dw-integration-bc/           ← demo: live BC connector via ngrok
    ├── dw-render-*/                 ← foundational (platform truths fold up here)
    ├── dw-pim-*/  dw-commerce-*/    ← foundational
    ├── dw-extend-*/ dw-integration-*/  ← foundational
    └── dw-setup-*/ dw-content-modelling/ dw-data-access/ …  ← foundational
```
