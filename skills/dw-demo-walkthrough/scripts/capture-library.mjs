#!/usr/bin/env node
/**
 * capture-library.mjs: READ-ONLY against the site. Crawls one Truvio Commerce (DW10 with
 * Swift 2) site into a screen library: storefront pages and back office screens, one
 * 1920x1080 png each, and `screens.json` that says what every still is.
 *
 * Runtime: Node 20+ with `playwright-core` and a Chromium channel. Resolution:
 * DW_PLAYWRIGHT_DIR (a folder that holds node_modules/playwright-core), else normal module
 * resolution from this folder. DW_BROWSER_CHANNEL picks the channel (default msedge).
 * DW_ALLOW_SELF_SIGNED=1 accepts a self-signed certificate on a local host.
 *
 * OWNING REFERENCE: dw-demo-walkthrough/SKILL.md, "A screen library tied to the ledger".
 *
 * What it does and does not do: it follows GET links, expands navigation tree nodes, opens
 * the first row of a list and clicks the tabs of that detail screen. It never submits a
 * form and saves nothing. The back office sign-in comes from DW_USER and DW_PASS in the
 * caller's environment and is never written anywhere.
 *
 * Traps it encodes:
 *   - The back office sign-in is two steps: user name, then password.
 *   - The assistant panel takes a third of the width: it is collapsed through its own
 *     localStorage switch before the first still.
 *   - The area buttons on the left carry role="tab" too: only tabs inside the screen
 *     (right of the tree, near the top) are clicked.
 *   - A tree with hundreds of nodes never ends: expansion and stills per area are capped,
 *     and a second pass takes --skip-urls with what the first pass already has.
 *
 * Parameters:
 *   <base> <outDir>          site root and the folder to write (required, in this order)
 *   --storefront             crawl the storefront from / (navigation pages, two detail pages per list)
 *   --admin                  crawl the back office areas
 *   --details                with --admin: the first row's detail screen, its tabs and its edit screen
 *   --areas=A,B              only these back office areas, by their name in the left bar
 *   --max-per-area=N         stills per area, default 45
 *   --expand-rounds=N        tree expansion rounds per area, default 3; --expand-per-round=N, default 40
 *   --skip-urls=<file>       one url per line that is already captured (a path relative to the working
 *                            directory: PowerShell cuts an argument like --x=F:/path at the colon)
 *
 * Output: <outDir>/shots/<key>.png and <outDir>/screens.json
 *   {site, capturedAt, dwVersion, screens: [{key, surface, area, title, url, screen, path, file}]}
 *
 * Example:
 *   node capture-library.mjs https://demo.example.com ./library --storefront --admin --details
 */
import fs from 'node:fs'; import path from 'node:path'; import {createRequire} from 'node:module';
const require = createRequire(import.meta.url);
const args = process.argv.slice(2); const [BASE, out] = args;
if (!BASE || !out || BASE.startsWith('--')) { console.error('usage: node capture-library.mjs <base> <outDir> [--storefront] [--admin] [--details]'); process.exit(2); } const flag = n => args.includes('--' + n);
const {chromium} = require(process.env.DW_PLAYWRIGHT_DIR ? path.join(process.env.DW_PLAYWRIGHT_DIR, 'node_modules', 'playwright-core') : 'playwright-core');
const maxPer = +(args.find(a => a.startsWith('--max-per-area=')) || '=45').split('=')[1];
fs.mkdirSync(path.join(out, 'shots'), {recursive: true});
const slug = s => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 90);
let dwVersion = null; const screens = []; const keys = new Set();
const save = () => fs.writeFileSync(path.join(out, 'screens.json'), JSON.stringify({site: BASE, capturedAt: new Date().toISOString(), dwVersion, screens}, null, 1));
const browser = await chromium.launch({channel: process.env.DW_BROWSER_CHANNEL || 'msedge'});
const ctx = await browser.newContext({ignoreHTTPSErrors: process.env.DW_ALLOW_SELF_SIGNED === '1', viewport: {width: 1920, height: 1080}});
await ctx.addCookies([{name: 'Dynamicweb.CookieOptInLevel', value: '2', url: BASE}]);
const page = await ctx.newPage();
async function shoot(entry) {
  let k = entry.key, i = 2; while (keys.has(k)) k = entry.key + '-' + i++; keys.add(k); entry.key = k;
  entry.file = `shots/${k}.png`; await page.screenshot({path: path.join(out, entry.file)});
  screens.push(entry); save(); console.log(entry.surface, k, '|', entry.title);
}
if (flag('storefront')) {
  const seen = new Set(), queue = [['/', 0]]; let n = 0;
  while (queue.length && n < 120) {
    const [p, depth] = queue.shift(); if (seen.has(p)) continue; seen.add(p);
    let r; try { r = await page.goto(BASE + p, {waitUntil: 'networkidle', timeout: 45000}); } catch { continue; }
    if (!r || r.status() >= 400) continue; await page.waitForTimeout(600);
    const u = new URL(page.url()); if (seen.has('@' + u.pathname + u.search)) continue; seen.add('@' + u.pathname + u.search);
    const title = (await page.title()).trim();
    const h1 = await page.evaluate(() => (document.querySelector('main h1, main h2, h1')?.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 80));
    await shoot({key: 'sf-' + (slug(u.pathname.replace(/^\/en-us/, '') + u.search) || 'home'), surface: 'storefront', area: u.pathname.split('/')[2] || 'home', title: h1 || title, pageTitle: title, url: u.pathname + u.search, path: u.pathname}); n++;
    if (depth >= 3) continue;
    const links = await page.evaluate(() => [...document.querySelectorAll('a[href]')].map(a => a.getAttribute('href')).filter(h => h && h.startsWith('/') && !/\.(pdf|jpg|png|zip|docx?)$/i.test(h) && !/cartcmd|logout|\/Admin|sign-out|\/Files\//i.test(h)));
    const nav = links.filter(h => h.split('/').length <= 5 && !/[?&]/.test(h));
    const pdp = links.filter(h => !nav.includes(h) && !/[?&](PageNum|SortBy|GroupID)=/i.test(h)).slice(0, 2); // one or two detail pages per list
    for (const h of new Set([...nav, ...pdp])) if (!seen.has(h)) queue.push([h, depth + 1]);
  }
}
if (flag('admin')) {
  await page.goto(BASE + '/Admin', {waitUntil: 'networkidle'});
  await page.locator('input[name=Username]').fill(process.env.DW_USER); await page.locator('input[name=Username]').press('Enter');
  const pw = page.locator('input[type=password]').first(); await pw.waitFor({timeout: 20000}); await pw.fill(process.env.DW_PASS); await pw.press('Enter');
  await page.waitForTimeout(5000);
  dwVersion = await page.evaluate(() => ([...document.querySelectorAll('button[title^="Version:"]')][0]?.title.match(/Version: ([\d.]+)/) || [])[1] || null);
  const tidy = async () => { // the assistant panel is not part of the screen being shown: minimise it, hide what is left
    const c = page.locator('[aria-label="Close Dynamo"]').first(); if (await c.isVisible().catch(() => false)) { await c.click({timeout: 2000}).catch(() => {}); await page.waitForTimeout(500); }
    await page.evaluate(() => { window.scrollTo(0, 0); document.querySelectorAll('[aria-label="Open Dynamo"]').forEach(e => e.style.visibility = 'hidden'); }).catch(() => {}); };
  await page.evaluate(() => localStorage.setItem('dw-admin-assistant-sidekick-collapsed', 'true')).catch(() => {});
  const TABS = '[role="tab"], .nav-tabs .nav-link, .nav-underline .nav-link, .nav-pills .nav-link';
  // one detail screen per list (the first row's own link), then each of its tabs
  const shootTabs = async (base, pt, href, screen) => {
    const inContent = t => t.offsetParent && !t.closest('.tree-nav') && t.getBoundingClientRect().left > 480 && t.getBoundingClientRect().top < 400;
    const tabs = await page.evaluate(([sel, f]) => { const ok = new Function('t', 'return (' + f + ')(t)'); return [...document.querySelectorAll(sel)].filter(ok).map(t => t.textContent.trim().split(/\s+/).join(' ')).filter(Boolean); }, [TABS, inContent.toString()]).catch(() => []);
    const home = page.url();
    for (const t of [...new Set(tabs)].slice(1, 10)) {
      const tab = page.locator(TABS).filter({hasText: t}).filter({visible: true}).last();
      if (!(await tab.count())) continue;
      await tab.click({timeout: 3000}).catch(() => {}); await page.waitForLoadState('networkidle', {timeout: 15000}).catch(() => {}); await page.waitForTimeout(700); await tidy();
      await shoot({...base, key: base.key + '-' + slug(t), title: pt + ': ' + t, path: base.path + ' / ' + t, tab: t});
    }
  };
  // one detail screen per list (the first row), its tabs, then its edit screen and tabs
  const details = async (entry) => {
    if (!flag('details')) return;
    const before = page.url();
    let href = await page.evaluate(() => document.querySelector('table tbody tr a[href^="/Admin/UI/"]')?.getAttribute('href') || null).catch(() => null);
    if (href && /Delete|Permission|Logout|Create|Copy|Move/i.test(href)) href = null;
    try {
      if (href) { if (done.has(href)) return; await page.goto(BASE + href, {waitUntil: 'networkidle', timeout: 45000}); }
      else { const row = page.locator('table tbody tr[data-dw-action*="NavigateScreen"]').first(); if (!(await row.count())) return;
        await row.locator('td').nth(2).click({timeout: 3000}); await page.waitForLoadState('networkidle', {timeout: 30000}).catch(() => {}); await page.waitForTimeout(800);
        if (page.url() === before) return; const u = new URL(page.url()); href = u.pathname + u.search; if (done.has(href)) return; }
    } catch { return; }
    done.add(href); await page.waitForTimeout(900); await tidy();
    const screen = href.split('?')[0].split('/').pop(); const pt = (await page.title()).replace(/ - DynamicWeb 10$/, '');
    const base = {key: entry.key + '-detail', surface: 'admin', area: entry.area, title: pt, pageTitle: pt, url: href, screen, path: entry.path + ' / ' + screen, detailOf: entry.key};
    await shoot({...base}); await shootTabs(base, pt, href, screen);
    const edit = await page.evaluate(() => { for (const a of document.querySelectorAll('a[href^="/Admin/UI/"]')) { if (a.closest('.tree-nav') || a.getBoundingClientRect().left < 480 || !a.offsetParent) continue; const h = a.getAttribute('href'); if (/Edit\?/.test(h) && !/Delete|Permission|Copy|Move|Create/i.test(h)) return h; } return null; }).catch(() => null);
    if (!edit || done.has(edit) || /Overview|List/.test(screen) === false) return; done.add(edit);
    try { await page.goto(BASE + edit, {waitUntil: 'networkidle', timeout: 45000}); } catch { return; }
    await page.waitForTimeout(900); await tidy();
    const es = edit.split('?')[0].split('/').pop(); const et = (await page.title()).replace(/ - DynamicWeb 10$/, '');
    const eb = {key: entry.key + '-edit', surface: 'admin', area: entry.area, title: et, pageTitle: et, url: edit, screen: es, path: entry.path + ' / ' + es, detailOf: entry.key};
    await shoot({...eb}); await shootTabs(eb, et, edit, es);
  };
  const areas = await page.evaluate(() => [...document.querySelectorAll('a[href^="/Admin/UI/"]')].map(a => [a.getAttribute('href'), a.textContent.trim()]).filter(([h]) => /^\/Admin\/UI\/[A-Za-z]+$/.test(h)));
  const opt = (n, d) => (args.find(x => x.startsWith('--' + n + '=')) || '=' + d).split('=').slice(1).join('=');
  const skipFile = opt('skip-urls', ''); // a file with one already captured url per line: a second pass leaves those out
  const done = new Set(skipFile ? fs.readFileSync(skipFile, 'utf8').split('\n').map(x => x.trim()).filter(Boolean) : []);
  const rounds = +opt('expand-rounds', '3'), perRound = +opt('expand-per-round', '40');
  const only = (args.find(x => x.startsWith('--areas=')) || '=').split('=')[1].toLowerCase().split(',').filter(Boolean);
  for (const [areaHref, areaName] of areas) {
    if (only.length && !only.includes(areaName.toLowerCase())) continue;
    await page.goto(BASE + areaHref, {waitUntil: 'networkidle', timeout: 60000}).catch(() => {}); await page.waitForTimeout(1500);
    for (let round = 0; round < rounds; round++) { // expand the tree, bounded
      const btns = page.locator('.js-tree-expand-button.collapsed'); const c = Math.min(await btns.count(), perRound); if (!c) break;
      for (let i = 0; i < c; i++) { await btns.nth(0).click({timeout: 3000}).catch(() => {}); await page.waitForTimeout(350); }
    }
    const links = await page.evaluate(() => [...document.querySelectorAll('.tree-nav__item a.tree-nav__link[href^="/Admin/UI/"]')].map(a => ({href: a.getAttribute('href'), text: a.textContent.trim().replace(/\s+/g, ' '), nav: a.closest('[data-navigation-path]')?.getAttribute('data-navigation-path') || ''})));
    await tidy(); const u0 = new URL(page.url());
    await shoot({key: 'ad-' + slug(areaName + '-start'), surface: 'admin', area: areaName, title: areaName, pageTitle: (await page.title()).replace(/ - DynamicWeb 10$/, ''), url: u0.pathname + u0.search, screen: u0.pathname.split('/').pop(), path: areaName});
    done.add(u0.pathname + u0.search);
    const perScreen = {}; let n = 0;
    for (const l of links) {
      if (n >= maxPer) break; if (/Logout|Authentication|Delete|PermissionList/i.test(l.href) || done.has(l.href)) continue;
      const screen = l.href.split('?')[0].split('/').pop(); perScreen[screen] = (perScreen[screen] || 0) + 1; if (perScreen[screen] > 4) continue;
      done.add(l.href);
      try { await page.goto(BASE + l.href, {waitUntil: 'networkidle', timeout: 45000}); } catch { continue; }
      await page.waitForTimeout(900); await tidy();
      const navPath = l.nav.split('/').filter(s => s && s !== '--').map(s => s.split('.').pop().replace(/(Area|Section|NodeProvider)$/, '')).join(' / ');
      await shoot({key: 'ad-' + slug(areaName + '-' + screen + '-' + l.text), surface: 'admin', area: areaName, title: l.text || screen, pageTitle: (await page.title()).replace(/ - DynamicWeb 10$/, ''), url: l.href, screen, path: navPath}); n++;
      await details(screens[screens.length - 1]);
    }
  }
}
save(); await browser.close(); console.log('screens', screens.length);
