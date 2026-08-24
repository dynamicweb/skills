# Browser MCP — Playwright install + verification gate

## Contents

- [Why user scope, not per-demo `.mcp.json`](#why-user-scope-not-per-demo-mcpjson)
- [Step 1 — Install at user scope](#step-1--install-at-user-scope)
- [Where screenshots land — set `--output-dir` or they pollute the project root](#where-screenshots-land--set---output-dir-or-they-pollute-the-project-root)
- [Step 2 — Verification gate](#step-2--verification-gate)
- [Step 3 — Tool surface in a fresh Claude Code session](#step-3--tool-surface-in-a-fresh-claude-code-session)
- [Generic verify-flow recipe](#generic-verify-flow-recipe)
- [Probe-harness discipline — measure the right document, prove the measurement](#probe-harness-discipline--measure-the-right-document-prove-the-measurement)
- [Removal / re-install](#removal--re-install)
- [Chromium fallback when `chrome` isn't resolvable](#chromium-fallback-when-chrome-isnt-resolvable)

Wire `@playwright/mcp` (Microsoft's official Playwright MCP server) at **user scope** so every Dynamicweb demo on this machine gets first-class browser tooling — log in, navigate, click, screenshot, inspect DOM. This replaces the friction of asking the user to manually drive a tab and paste back screenshots after each PIM seeding / template edit / customer-center wiring change.

**Scope guard — action surface during scaffold, verification-only during the build.** During the scaffold phase (before the MCP verification gate passes), Playwright is the sanctioned action surface for the bootstrap one-clicks: create the MCP configuration and capture the shown-once API key, create the Management API key, and the AppStore fallback (`references/surface-priority.md` §"Scaffold phase"). Once the gate passes, Playwright's job is to *verify*: walk the storefront as a seeded persona, or navigate `/Admin` read-only to confirm a change landed (screenshot, DOM-grep) — every admin-UI operation is an Admin API call underneath, so a build-phase change itself belongs on MCP / Management API / (local only) SQL per `references/surface-priority.md` §"Admin UI is verification-only during the build".

Three steps in **strict order**:

1. Install Playwright MCP at user scope.
2. Verify the connection gate.
3. Confirm browser tools surface in a fresh Claude Code session.

The verification gate (Step 2) refuses to declare 'browser tooling ready' until `claude mcp list` shows `playwright ✓ Connected`.

---

## Why user scope, not per-demo `.mcp.json`

Browser tooling is **cross-demo plumbing** — like the Backend MCP install or the TLS bypass. Every Dynamicweb demo on this machine needs the same browser tools; per-demo install would create drift and clutter each `.mcp.json`. User scope keeps it canonical:

- One install command, one place to upgrade.
- Tools surface in every Claude Code session on this machine, not just inside a Dynamicweb demo solution folder.
- No leakage to git: per-demo `.mcp.json` is project-tracked; user scope is in `~/.claude.json` (machine-local).

---

## Step 1 — Install at user scope

Run from any directory (the install is global to the user account):

```powershell
claude mcp add --scope user playwright -- npx -y @playwright/mcp@latest --ignore-https-errors
```

(On a real demo machine, add `--output-dir` — see "Where screenshots land" below; the bare command above lets `browser_take_screenshot` write into the demo solution root.)

What each flag does:

| Flag | Why |
|---|---|
| `--scope user` | Registers the MCP in `~/.claude.json` (user-global), not in the current project's `.mcp.json`. Keeps it cross-demo. |
| `--ignore-https-errors` | The Dynamicweb demo host runs on `https://localhost:<port>/` with a self-signed dev cert. Without this flag, every Playwright `browser_navigate` to the host throws `net::ERR_CERT_AUTHORITY_INVALID`. This is the browser-side equivalent of the two-layer TLS bypass in `references/mcp-setup.md` Step 2 — same threat model (localhost only), same scope (developer machine only). |
| `npx -y @playwright/mcp@latest` | Resolves the latest published Playwright MCP on each spawn. No global npm install to maintain; `npx` caches the package. |

**Optional flags** (append before any verification):

| Flag | When to add |
|---|---|
| `--browser msedge` | If Chrome is not installed on this machine. Edge ships on every Windows 11; Chromium would otherwise need a separate `npx playwright install chromium`. Default is `chrome` (the installed channel). |
| `--isolated` | Keeps the browser profile in memory only — no cookies / localStorage persisted between runs. Recommended for verification flows where each "log in as user X, walk to URL Y" should start fresh. Without it, login state leaks across calls. |
| `--headless` | Run without a visible browser window. Default is headed, which is useful when the user is watching the demo machine; flip to headless for CI-like silent runs. |
| `--output-dir <path>` | **Always, on a demo machine.** Sets where `browser_take_screenshot` writes relative filenames. Without it, bare filenames land in the folder Claude Code was launched from — the demo solution root. See "Where screenshots land" below. |

A reasonable default for Dynamicweb verification flows on Windows:

```powershell
claude mcp add --scope user playwright -- npx -y @playwright/mcp@latest --ignore-https-errors --isolated --output-dir "$env:USERPROFILE\.playwright-mcp-output"
```

---

## Where screenshots land — set `--output-dir` or they pollute the project root

`browser_take_screenshot` writes its `filename` relative to the MCP server's working directory when no `--output-dir` is set — and that working directory is **whatever folder Claude Code was launched from**, i.e. the demo solution root. A verification flow that takes a dozen shots with bare filenames (`home.jpeg`, `pdp.jpeg`, …) therefore litters the repo root; one demo build accumulated ~40 stray `.jpeg` files in the solution root this way before anyone noticed. The skill recipe below says "screenshot" but the *where* is the guardrail — without it, the default is the worst place.

Two-part fix:

1. **Pin a neutral machine-level `--output-dir` at install time.** Because the Browser MCP is user-scope (cross-demo plumbing, per "Why user scope" above), this path must NOT be any one demo's folder — pointing it at a demo's `notes\` would funnel *every* demo's screenshots into that one solution. Point it at a throwaway scratch dir so a forgotten bare filename lands there, never in a repo root:

   ```powershell
   claude mcp add --scope user playwright -- npx -y @playwright/mcp@latest --ignore-https-errors --isolated --output-dir "$env:USERPROFILE\.playwright-mcp-output"
   ```

2. **For keeper shots, pass an absolute path under `<demo>\notes\qa\`.** Verification screenshots worth keeping belong *with* the demo, not in the cross-demo scratch dir. Pass an absolute `filename` so it bypasses `--output-dir` entirely: `<demo>\notes\qa\<persona>-<step>.jpeg`. `notes\qa\` is the canonical QA-evidence home from `SKILL.md` "Artifact hygiene"; DOM / accessibility dumps (`browser_snapshot`) go to `<demo>\notes\snapshots\` instead, and each is named for what it IS (`admin-a11y-snapshot-*.md`), never for what it was captured during.

Changing `--output-dir` on an already-registered MCP requires a **fresh Claude Code session** — the running server is pinned to its launch-time argv (same restart rule as Step 3, and the Chromium-fallback gotcha below).

---

## Step 2 — Verification gate

```powershell
$mcpList = claude mcp list 2>&1
if ($mcpList -notmatch 'playwright.*✓.*Connected') {
  Write-Host "FAILED: claude mcp list does not show playwright Connected."
  Write-Host "Triage:"
  Write-Host "  1. Did the npx fetch finish? First run downloads ~50 MB of Playwright bits."
  Write-Host "  2. Re-run 'claude mcp list' once or twice — first connect after install can race."
  Write-Host "  3. Run 'npx -y @playwright/mcp@latest --help' standalone to confirm the package resolves."
  throw "Playwright MCP not connected. Re-run install with --verbose or remove + re-add."
}
Write-Host "OK: playwright ✓ Connected"
```

This is the same gate shape as `references/mcp-setup.md` Step 4a (Backend MCP). Connected is necessary; tool surface (Step 3) is the second half.

---

## Step 3 — Tool surface in a fresh Claude Code session

MCP servers added mid-conversation do **not** retroactively surface their tools in the running conversation — Claude Code's deferred-tool list is built at session start. To verify tools are usable, **start a fresh Claude Code session** (close the running one, reopen) and run:

```
ToolSearch query="select:mcp__playwright__browser_navigate,mcp__playwright__browser_take_screenshot,mcp__playwright__browser_click" max_results=5
```

The skill **refuses to declare browser tooling ready** until that ToolSearch returns the schemas (not "No matching deferred tools found").

If the install was done in the same session that needs to use the tools, the user must restart Claude Code once after Step 1.

---

## Generic verify-flow recipe

After a Dynamicweb demo finishes seeding (PIM content, customer-center pages, paragraph wiring), use this shape to confirm the user-facing surface actually works. Substitute placeholders for the demo's real values — never bake demo-specific URLs / credentials into this file:

1. **Resolve the host URL.** From `Dynamicweb.Host.Suite/Properties/launchSettings.json` HTTPS profile (the discover-from-project-files rule — see `references/mcp-setup.md` Step 1). Format: `https://localhost:<port>/`.
2. **Navigate to the public storefront** (not `/Admin`). Example: `mcp__playwright__browser_navigate url="https://localhost:<port>/<shop-slug>/"`.
3. **Log in as a seeded buyer.** Submit credentials via the storefront login form, NOT against `/Admin` (that's the admin UI, not the customer journey). Credentials come from the demo's per-demo Claude memory (the discover-from-project-files rule); never hardcode.
4. **Walk to the target tab** (e.g. account orders, favorites, recurring orders, checkout).
5. **Screenshot** (pass an absolute `<demo>\notes\qa\` filename so the shot lands with the demo, never in the repo root — see "Where screenshots land" and `SKILL.md` "Artifact hygiene") + **DOM-grep** for the expected entity count. Example: assert at least N order rows visible, or that a specific SKU appears in favorites.
   - **Scroll-sweep before any `fullPage` screenshot or image assertion.** Swift lazy-loads images
     (`loading="lazy"`); a full-page capture stitches below-fold regions whose images never entered
     the viewport, so tiles render as blank wells, and `img.naturalWidth === 0` reads as "broken
     image" when the file is fine. Sweep the page first (`window.scrollTo` in ~500px steps with
     short waits, then back to top), and only then screenshot or measure `naturalWidth`. Treat a
     natural-width-0 finding on an un-swept page as a measurement artifact, not a defect — verify
     with a direct `fetch` of the image URL before filing it.
   - **Dismiss or pre-seed the cookie-consent modal before the first shot.** An isolated context has no
     consent cookie, so the modal covers every page of every run. It renders outside `<main>`, so it does
     not disturb measurements — it destroys only the evidence. See "Probe-harness discipline" below.
6. **Run the visual QA pass** — [`visual-qa.md`](visual-qa.md) owns it: the programmatic detectors (horizontal overflow, broken/stretched images, whitespace bands), the interaction pass, the eyeball checklist, and the symptom→fix routing table. The entity-count check in step 5 proves the data landed; it says nothing about polish, and demo pages are held to "nothing left to fix", not "it renders".
7. **Report findings to chat.** Surface mismatches (wrong count, missing element, NRE in template, visual-QA findings) so the next iteration of the seeding script can patch the root cause.

This pattern replaces the manual loop of "user logs in, observes symptom, pastes error/screenshot to chat" — which is what the Playwright MCP install is for in the first place. The placeholder fields (`<port>`, `<shop-slug>`, seeded user credentials) are deliberately not filled in here; they belong to the per-demo `<demo>\notes\` working notes, not the cross-demo skill.

**What NOT to encode in this file:** specific user names, passwords, shop slugs, customer-center URL paths, or order-count assertions tied to one demo's seed data. Those are per-demo. This file owns the **shape** of verification, not its **values**.

---

## Probe-harness discipline — measure the right document, prove the measurement

Once verification moves from ad-hoc `browser_evaluate` calls into a scripted probe runner (a design/QA gate leg), the runner itself becomes a thing that can lie. What the assert *says* lives in [`visual-qa.md`](visual-qa.md) "Assert design rules"; what the **browser** was served, and whether the harness's own manipulation took effect, lives here.

**A viewport is not a device.** Dynamicweb selects the header server-side by **user-agent**, not by viewport, so `newContext({ viewport: { width: 390, height: 844 } })` with no descriptor is served the *desktop* document at phone width — same URL, ~5 KB smaller, the offcanvas-navigation marker absent, a 3-row 177px header whose clearance is correctly 1px. Four consecutive gate PASSes certified a mobile layout no phone user was ever served. Import `devices` from Playwright and **spread the descriptor into `newContext` before the explicit viewport**, so UA / `isMobile` / `hasTouch` / `deviceScaleFactor` come from the device while declared geometry still wins. Check the runner does not destructure only `vp.width` / `vp.height` — a `userAgent` added to the probe config is then silently dropped, so a config-only fix is impossible *and looks applied*.

**Assert the served artefact, not the setting requested.** Add a `ua-mode` probe: a phone-only DOM marker (Swift's offcanvas navigation) must be **present** at mobile and **absent** at desktop. A silent revert to a desktop UA then fails the leg loudly instead of quietly re-measuring the wrong document. Pair it with a positive control — a computed header-height assert that can only pass with the descriptor actually in play (84px with a real phone UA, 177px without).

**Assert the relationship, never a hand-fitted token.** A clearance token carried the comment "measured against the live header" and was 94px wrong on every real phone: honestly measured, in a real browser, against the wrong document — then frozen into a number nothing could keep in sync with the thing it tracked. A geometry assert reading the *same* wrong document agrees with the wrong token perfectly. Assert `firstContent.top - header.bottom` within a band instead: a relationship is self-maintaining. Rejected alternatives — re-measuring the token more carefully (the next backend change invalidates it again silently), a file-bytes or CSSOM check (both see a perfectly healthy sheet; the rule parsed fine, it was fitted to the wrong page), and a second breakpoint (media queries cannot distinguish two documents served at the same width).

**Screenshot every page at every viewport — and seed consent before the first navigation.** A gate leg that calls `page.screenshot()` zero times cannot be visually verified by anyone; sign-off images sourced from ad-hoc scratch scripts outside the gate are not gate evidence. And a fresh browser context carries no consent cookie, so the cookie modal covers every page of every run — it renders outside `<main>`, so it never disturbs the measurements, it destroys only the evidence, which is the part a human checks. Capture a viewport shot **and** a full-page shot per page per viewport into `<rundir>/shots/`, seed the consent cookie(s) into the context first, and record the seeding as a **PASS/FAIL probe** (`cookie-seed[<viewport>]` reads every declared cookie back after `addCookies`). The first version of that seeding threw silently — Playwright rejects a cookie carrying both `url` and `path` — and the leg carried on photographing the dialog.

**Verify a CSS block in the concatenated sheet, live — never in isolation.** Parsing is context-dependent: an unterminated or early-terminated comment anywhere upstream re-tokenises every following byte, so a block that parses perfectly on its own is silently truncated once concatenated. The isolated test is green, the deploy round-trip is green, a file-bytes compare is green, and the page is wrong (a block whose comment predicted "~394px image bands" measured 480px live — exactly the un-inset value, from a rule that never ran). Load the **live** page, enumerate `document.styleSheets`, and assert (a) every claimed sentinel selector is present in the CSSOM, (b) comment-stripped source block count == parsed rule count, (c) computed-effect triples hold on real elements. Self-test against a deliberately broken fixture every run. A hand-maintained expected rule count rots on every pass; one self-describing marker rule per sentinel does not — but see the marker-**ownership** caveat in `visual-qa.md`.

**Prove your own page manipulation applied.** `page.addStyleTag('img { filter: grayscale(1) !important }')` loses to a more specific `!important` theme rule — among `!important` declarations CSS compares **specificity before source order**, so a themed `… .card img[srcset*="…"] { filter: none !important }` beats a bare element selector no matter which sheet is appended last. The injection succeeded, parsed, and did nothing: on 24 of 32 surfaces the "photos removed" figure was byte-identical to "photos present", and a shot labelled *no-photo* showed a full-colour hero. Apply harness-side manipulation as **inline** properties — `el.style.setProperty('filter', 'grayscale(1)', 'important')`, which outrank any stylesheet — and follow every manipulation with a post-condition that reads the computed value back and **throws** if it did not take. *A measurement tool that cannot prove its own precondition is not evidence.* Raising the injected selector's specificity is an arms race against CSS the harness does not control; background-image carriers get `background-image: none` plus a flat grey rather than a filter (a filter on a container also greys its descendants, hiding real CSS-authored colour painted on top).

**Disable LCD text before counting hue pixels.** Subpixel text rendering paints glyph edges on the R, G and B stripes independently, so every antialiased glyph carries a warm fringe on one edge and a cool one on the other — real pixels with real hues, and a warm fringe lands squarely in an orange/brown band. The noise floor scales with the amount of **text**, not the amount of paint: a page with zero images and zero elements computing a colour in the band scored 5,788 hits with LCD text on and **0** with Chromium launched `--disable-lcd-text`; across a suite, ~1.03M residual hits collapsed to 0. Launch the audit browser with `--disable-lcd-text` and state the flag in the harness — a reader who reproduces the scan without it gets a different answer. Per-surface tolerance thresholds were rejected (they bury the defect class and would have to scale with text volume), as was post-filtering isolated pixels (cannot distinguish a 1px hairline border from a glyph fringe).

**A standing colour assert — no pixel in a retired hue band outside image content.** Geometry and presence asserts are completely insensitive to a brand change: a sitewide palette swap left 197 of 201 design asserts green in *both* states while the highest-blast-radius surface on the site (94 primary buttons) kept the retired colour — visible only to a human looking at a screenshot, which is what the gate exists to replace. Add an assert parameterised by a retired hue band (h-range, S floor, L range) plus the photo-neutralisation pass, asserting **0 hits per surface**; ship it with the neutralisation post-condition and `--disable-lcd-text` above, without which it reports noise. Demonstrate it **fires** before trusting it — re-serve the pre-change stylesheets through `page.route()` under identical flags and confirm a large non-zero score against a 0 on the shipped state; a pass earned without that control is indistinguishable from a detector that stopped looking. Asserting on the CSS *text* is cheaper but misses a generated file the theme sheet never mentions (the exact defect class); asserting on computed styles per element is better than text but still blind to gradients, SVG fills, and colour arriving through a sheet the walker does not attribute.

---

## Removal / re-install

To remove (e.g. for testing the install path on a fresh machine):

```powershell
claude mcp remove --scope user playwright
```

To upgrade to the latest Playwright MCP without changing flags, simply remove + re-add — `npx -y @playwright/mcp@latest` always pulls the latest published version on next spawn, but the registration row in `~/.claude.json` is cached, so re-adding forces a clean entry.

---

## Chromium fallback when `chrome` isn't resolvable

On some Windows machines the install command at Step 1 succeeds and `claude mcp list` shows `playwright ✓ Connected`, but every `browser_navigate` call throws:

```
Error: browserType.launchPersistentContext: Chromium distribution 'chrome' is not found at C:\Program Files\Google\Chrome\Application\chrome.exe
Run "npx playwright install chrome"
```

This happens because Playwright MCP defaults to channel `chrome` (the Google-installed Chrome), and on machines where Chrome is missing or installed only in the user profile (`%LocalAppData%\Google\Chrome\Application\chrome.exe`) the channel resolver doesn't find it. `npx playwright install chrome` requires admin elevation and downloads a system-wide install, which is heavy for what's essentially a "use the chromium that's already on disk" ask.

**Two fixes — pick one.**

### Fix A — Tell Playwright MCP to use bundled Chromium

Re-register with `--browser=chromium` so Playwright uses the chromium bits that `npx playwright install chromium` would have installed (smaller, no admin):

```powershell
claude mcp remove --scope user playwright
claude mcp add --scope user playwright -- npx -y @playwright/mcp@latest --ignore-https-errors --isolated --browser=chromium
npx -y playwright install chromium  # one-time ~150 MB download, no admin required
```

**Gotcha:** changing the registration mid-session does **not** restart the already-running MCP server process. The verification gate must be re-run in a **fresh Claude Code session**, same as the Step 3 tool-surface requirement. A running MCP server is pinned to its launch-time argv.

### Fix B — Node script fallback driver (no MCP changes)

When the MCP server can't be restarted (e.g. in the middle of a session you don't want to lose), bypass the MCP entirely and call Playwright directly via a Node script that uses the already-downloaded chromium binary. This works because `npx -y @playwright/mcp@latest` triggers a chromium download into `%LocalAppData%\ms-playwright\chromium-<rev>\chrome-win64\chrome.exe` even if the MCP can't find a `chrome` channel.

Setup at a per-demo working dir (`%TEMP%\<demo>-playwright\`):

```powershell
mkdir $env:TEMP\<demo>-playwright
cd $env:TEMP\<demo>-playwright
npm init -y
npm install playwright
```

`walk.js` skeleton (reads a plan JSON; logs in once; visits each step; saves screenshot + HTML):

```javascript
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const planPath = process.argv[2];
const plan = JSON.parse(fs.readFileSync(planPath));
(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.LOCALAPPDATA + '/ms-playwright/chromium-1217/chrome-win64/chrome.exe',
    headless: false,
  });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  await page.goto('https://localhost:<port>/<shop>/sign-in/sign-in');
  await page.fill('input[name=username]', plan.user);
  await page.fill('input[name=password]', plan.pass);
  await page.click('button[type=submit]');
  for (const s of plan.steps) {
    await page.goto(s.goto, { waitUntil: 'networkidle' });
    await page.screenshot({ path: path.join(plan.outDir, s.shot), fullPage: !!s.full });
    if (s.html) fs.writeFileSync(path.join(plan.outDir, s.html), await page.content());
    console.log(`${s.tag} SHOT ${s.shot} HTML bytes=${s.html ? fs.statSync(path.join(plan.outDir, s.html)).size : 0}`);
  }
  await browser.close();
})();
```

Plan JSON example (`plan-<persona>.json`):

```json
{
  "user": "<seeded-username>",
  "pass": "<seeded-password>",
  "outDir": "<demo>/notes/qa/<persona>",
  "steps": [
    { "tag": "01-overview", "goto": "https://localhost:<port>/<shop>/overview", "shot": "01-overview.png", "full": true, "html": "01-overview.html" }
  ]
}
```

Run: `node walk.js plan-<persona>.json`. The **HTML-bytes signal** (printed for each step) is a cheap regression diff between two runs of the same plan — when a fix lands, the byte count usually moves (e.g. 85954 → 100040 bytes when an empty `No accounts found` table fills with three rows).

**When to prefer A over B:** Fix A keeps everything inside the MCP and is the durable answer once a session restart is acceptable. Fix B is for mid-session unblock and for verification flows where you want a self-contained script the user can run themselves (`node walk.js ...`) without Claude Code in the loop.

**What NOT to encode:** the specific revision (`chromium-1217`) drifts on every Playwright minor release. Resolve it dynamically with `Get-ChildItem $env:LocalAppData\ms-playwright -Directory | ? Name -like 'chromium-*' | Select -Last 1` and pass it into the script, OR pin the script's `executablePath` to whatever revision is on disk at the time the script was written and note it in the demo's `<demo>\notes\` working notes.
