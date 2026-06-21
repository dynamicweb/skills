# Browser MCP — Playwright install + verification gate

Wire `@playwright/mcp` (Microsoft's official Playwright MCP server) at **user scope** so every Dynamicweb demo on this machine gets first-class browser tooling — log in, navigate, click, screenshot, inspect DOM. This replaces the friction of asking the user to manually drive a tab and paste back screenshots after each PIM seeding / template edit / customer-center wiring change.

**Scope guard — verification only.** Playwright's job on a Dynamicweb demo is to *verify*: walk the storefront as a seeded persona, or navigate `/Admin` read-only to confirm a change landed (screenshot, DOM-grep). Driving `/Admin` to *make* changes is off-limits — every admin-UI operation is an Admin API call underneath, so the change itself belongs on MCP / Management API per the surface-priority rule (`references/surface-priority.md` §"Admin UI is verification-only").

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
| `--ignore-https-errors` | The Dynamicweb demo host runs on `https://localhost:<port>/` with a self-signed dev cert. Without this flag, every Playwright `browser_navigate` to the host throws `net::ERR_CERT_AUTHORITY_INVALID`. This is the browser-side equivalent of the two-layer TLS bypass in `references/tls-bypass.md` — same threat model (localhost only), same scope (developer machine only). |
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

2. **For keeper shots, pass an absolute path under the demo's `notes\`.** Verification screenshots worth keeping belong *with* the demo, not in the cross-demo scratch dir. Pass an absolute `filename` so it bypasses `--output-dir` entirely: `<demo>\notes\playwright\<persona>-<step>.jpeg`. This matches the `<demo>\notes\` output convention the customer-context contract already mandates (`references/customer-context.md`).

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
5. **Screenshot** (pass an absolute `<demo>\notes\playwright\` filename so the shot lands with the demo, never in the repo root — see "Where screenshots land") + **DOM-grep** for the expected entity count. Example: assert at least N order rows visible, or that a specific SKU appears in favorites.
6. **Report findings to chat.** Surface mismatches (wrong count, missing element, NRE in template) so the next iteration of the seeding script can patch the root cause.

This pattern replaces the manual loop of "user logs in, observes symptom, pastes error/screenshot to chat" — which is what the Playwright MCP install is for in the first place. The placeholder fields (`<port>`, `<shop-slug>`, seeded user credentials) are deliberately not filled in here; they belong to the per-demo `<demo>\notes\` working notes, not the cross-demo skill.

**What NOT to encode in this file:** specific user names, passwords, shop slugs, customer-center URL paths, or order-count assertions tied to one demo's seed data. Those are per-demo. This file owns the **shape** of verification, not its **values**.

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
  "outDir": "<demo>/notes/playwright/<persona>",
  "steps": [
    { "tag": "01-overview", "goto": "https://localhost:<port>/<shop>/overview", "shot": "01-overview.png", "full": true, "html": "01-overview.html" }
  ]
}
```

Run: `node walk.js plan-<persona>.json`. The **HTML-bytes signal** (printed for each step) is a cheap regression diff between two runs of the same plan — when a fix lands, the byte count usually moves (e.g. 85954 → 100040 bytes when an empty `No accounts found` table fills with three rows).

**When to prefer A over B:** Fix A keeps everything inside the MCP and is the durable answer once a session restart is acceptable. Fix B is for mid-session unblock and for verification flows where you want a self-contained script the user can run themselves (`node walk.js ...`) without Claude Code in the loop.

**What NOT to encode:** the specific revision (`chromium-1217`) drifts on every Playwright minor release. Resolve it dynamically with `Get-ChildItem $env:LocalAppData\ms-playwright -Directory | ? Name -like 'chromium-*' | Select -Last 1` and pass it into the script, OR pin the script's `executablePath` to whatever revision is on disk at the time the script was written and note it in the demo's `<demo>\notes\` working notes.
