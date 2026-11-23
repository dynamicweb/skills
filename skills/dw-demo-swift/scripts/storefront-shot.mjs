/* =============================================================================
 * storefront-shot.mjs — READ-ONLY against the site. Saves full-page screenshots of
 * storefront paths at one viewport, signed out or signed in as one user, and prints
 * one JSON result. Writes PNG files under --out-dir and nothing else.
 * -----------------------------------------------------------------------------
 * Called by Save-DwStorefrontShot.ps1 beside it, once per viewport; that wrapper
 * owns the parameters and the merged result. Owning reference:
 * dw-demo-swift/references/storefront-browser-checks.md (the measured selectors);
 * the consent cookie and the scroll-sweep before a full-page shot are in
 * dw-demo-base/references/browser-automation.md "Generic verify-flow recipe".
 *
 * The password is never an argument: --password-env names the environment variable
 * that holds it, and every message this file prints has it masked.
 *
 * Runtime: Node 20+ with `playwright` resolvable from THIS folder (module resolution
 * walks up from the script's directory), plus a Chromium browser:
 * `npm install playwright && npx playwright install chromium` beside this file.
 *
 * Usage:
 *   node storefront-shot.mjs --url <base url> --path /en-us/home --path /en-us/shop \
 *     --width 1440 --height 900 --label desktop-1440 --out-dir notes/qa \
 *     [--device "iPhone 12"] [--user <name> --password-env DW_SHOT_PASSWORD \
 *      --sign-in-path /en-us/sign-in/sign-in --identity-path /en-us/customer-center \
 *      --identity-text "<text the signed-in page shows>"] [--allow-self-signed]
 *
 * Result: { status: PASS|FAIL|UNRUNNABLE, viewport, signIn, shots: [ { path, status,
 *   file, finalUrl, error } ], detail } on stdout.
 * Exit:   0 = every shot saved with a status below 400 and any sign-in proven,
 *         1 = a shot or the sign-in failed, 2 = could not run.
 * ========================================================================== */

import { mkdirSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}
function argAll(name) {
  const out = [];
  process.argv.forEach((a, i) => {
    if (a === `--${name}` && i + 1 < process.argv.length) out.push(process.argv[i + 1]);
  });
  return out;
}
const flag = (name) => process.argv.includes(`--${name}`);

// TLS validation is skipped only for a localhost base URL or an explicit opt-in.
function tlsBypassAllowed(baseUrl, allowSelfSigned) {
  if (allowSelfSigned) return true;
  try {
    const host = new URL(baseUrl).hostname.toLowerCase();
    return host === 'localhost' || host === '127.0.0.1' || host === '[::1]';
  } catch {
    return false;
  }
}

// A file name for a path: /en-us/shop?GroupID=G1 -> en-us-shop-GroupID-G1.
function slug(p) {
  const s = String(p).replace(/^\/+|\/+$/g, '').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return s ? s.slice(0, 80) : 'root';
}

const baseUrl = String(arg('url', process.env.DW_BASE_URL || '')).replace(/\/+$/, '');
const paths = argAll('path').length ? argAll('path') : ['/'];
const width = parseInt(arg('width', '1440'), 10);
const height = parseInt(arg('height', '900'), 10);
const deviceName = arg('device', null);
const label = arg('label', `${width}x${height}`);
const outDir = resolve(arg('out-dir', '.'));
const timeoutMs = parseInt(arg('timeout', '60000'), 10);
const user = arg('user', null);
const passwordEnv = arg('password-env', 'DW_SHOT_PASSWORD');
const signInPath = arg('sign-in-path', '/en-us/sign-in/sign-in');
const identityPath = arg('identity-path', '/en-us/customer-center');
const identityText = arg('identity-text', null);
const secret = user ? (process.env[passwordEnv] || '') : '';

const result = {
  status: 'FAIL',
  viewport: { label, width, height, device: deviceName },
  signIn: user ? { user, attempted: false, proven: false, detail: '' } : null,
  shots: [],
  detail: '',
};

const mask = (text) => (secret ? String(text).split(secret).join('****') : String(text));
function finish(code) {
  console.log(mask(JSON.stringify(result, null, 2)));
  process.exit(code);
}

// The consent modal: accepting stores the choice and RELOADS the document, so wait for
// the reloaded document, not for the modal to go.
async function clearConsent(page) {
  const modal = page.locator('#dwCookieModal');
  if (!(await modal.isVisible().catch(() => false))) return false;
  await Promise.all([
    page.waitForEvent('load', { timeout: 15000 }).catch(() => {}),
    page.locator('#dwCookieAcceptAll').first().click({ timeout: 5000 }).catch(() => {}),
  ]);
  await page.waitForLoadState('domcontentloaded').catch(() => {});
  return true;
}

// Scroll the page so lazy images lay out before a full-page capture.
async function sweep(page) {
  await page.evaluate(async () => {
    const step = Math.round(window.innerHeight * 0.8);
    for (let y = 0; y < document.body.scrollHeight; y += step) {
      window.scrollTo(0, y);
      await new Promise((r) => setTimeout(r, 80));
    }
    window.scrollTo(0, 0);
    await new Promise((r) => setTimeout(r, 300));
  });
}

async function signIn(page) {
  const s = result.signIn;
  s.attempted = true;
  if (!secret) {
    s.detail = `$${passwordEnv} is empty; no sign-in was tried.`;
    return false;
  }
  await page.goto(`${baseUrl}${signInPath}`, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
  await clearConsent(page);
  // Scope to main: the header carries a sign-in form too.
  const form = page.locator('main form:has(input[name="password" i])').first();
  if (!(await form.count())) {
    s.detail = `no sign-in form with a password field in main at ${signInPath}.`;
    return false;
  }
  await form.locator('input[name="username" i]').first().fill(user);
  await form.locator('input[name="password" i]').first().fill(secret);
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: timeoutMs }).catch(() => {}),
    form.locator('button[type="submit"], input[type="submit"]').first().click(),
  ]);
  // Proof: the identity page is not the sign-in page, shows no password field in main,
  // and carries the identity text when one is given.
  const r = await page.goto(`${baseUrl}${identityPath}`, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
  const finalUrl = page.url();
  const onSignIn = new URL(finalUrl).pathname.toLowerCase().startsWith(signInPath.toLowerCase());
  const loginForm = await page.locator('main input[type="password"]').count();
  const text = await page.locator('body').innerText().catch(() => '');
  const textOk = identityText ? text.includes(identityText) : null;
  s.identityPath = identityPath;
  s.identityStatus = r ? r.status() : null;
  s.finalUrl = finalUrl;
  s.proven = !onSignIn && loginForm === 0 && (textOk !== false) && !!r && r.status() < 400;
  s.detail = s.proven
    ? `${identityPath} answered ${s.identityStatus} with no sign-in form` +
      (identityText ? ' and carries the identity text.' : '; pass -IdentityText for a stronger proof.')
    : `not signed in: ${onSignIn ? 'redirected to the sign-in page; ' : ''}` +
      `${loginForm ? 'a password field is still on the page; ' : ''}` +
      `${textOk === false ? 'the identity text is missing; ' : ''}HTTP ${s.identityStatus}.`;
  return s.proven;
}

async function main() {
  if (!baseUrl) {
    result.status = 'UNRUNNABLE';
    result.detail = 'no base URL. Pass --url or set DW_BASE_URL; there is no default host.';
    finish(2);
  }
  let chromium, devices;
  try {
    ({ chromium, devices } = await import('playwright'));
  } catch (e) {
    result.status = 'UNRUNNABLE';
    result.detail = `playwright is not resolvable from ${here}: ${e.message}. ` +
      'Run `npm install playwright && npx playwright install chromium` in this folder.';
    finish(2);
  }
  if (deviceName && !devices[deviceName]) {
    result.status = 'UNRUNNABLE';
    result.detail = `playwright does not know device "${deviceName}".`;
    finish(2);
  }
  mkdirSync(outDir, { recursive: true });
  const bypass = tlsBypassAllowed(baseUrl, flag('allow-self-signed'));
  const browser = await chromium.launch({ args: bypass ? ['--ignore-certificate-errors'] : [] });
  try {
    // Spread the descriptor BEFORE the viewport: Dynamicweb picks the header by user-agent.
    const dev = deviceName ? { ...devices[deviceName] } : {};
    delete dev.defaultBrowserType;
    const context = await browser.newContext({ ignoreHTTPSErrors: bypass, ...dev, viewport: { width, height } });
    // Seed the consent choice before the first navigation; the modal is still dismissed
    // below if it shows anyway.
    await context.addCookies([{ name: 'Dynamicweb.CookieOptInLevel', value: '2', url: baseUrl }])
      .catch(() => {});
    const page = await context.newPage();

    if (user && !(await signIn(page).catch((e) => {
      result.signIn.detail = `sign-in failed: ${e.message}`;
      return false;
    }))) {
      result.detail = `sign-in as ${user} was not proven; no shots were taken, so no signed-out page is mistaken for a signed-in one.`;
      await browser.close();
      finish(1);
    }

    const suffix = user ? '-signed-in' : '';
    for (const p of paths) {
      const shot = { path: p, status: null, file: null, finalUrl: null, error: null };
      try {
        const r = await page.goto(`${baseUrl}${p}`, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
        shot.status = r ? r.status() : null;
        if (await clearConsent(page)) shot.consentDismissed = true;
        await page.waitForLoadState('load', { timeout: 15000 }).catch(() => {});
        await sweep(page);
        shot.finalUrl = page.url();
        const file = join(outDir, `${label}-${slug(p)}${suffix}.png`);
        await page.screenshot({ path: file, fullPage: true });
        shot.file = file;
      } catch (e) {
        shot.error = e.message;
      }
      result.shots.push(shot);
    }
    await browser.close();
  } catch (e) {
    await browser.close().catch(() => {});
    result.status = 'UNRUNNABLE';
    result.detail = `harness error: ${e.message}`;
    finish(2);
  }
  const bad = result.shots.filter((s) => !s.file || s.error || s.status === null || s.status >= 400);
  result.status = bad.length === 0 ? 'PASS' : 'FAIL';
  result.detail = `${result.shots.length - bad.length}/${result.shots.length} shot(s) saved with a status below 400 at ${label}` +
    (user ? `, signed in as ${user}.` : ', signed out.');
  finish(bad.length === 0 ? 0 : 1);
}

main();
