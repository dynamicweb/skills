/**
 * reskin-engine.mjs: READ-ONLY against the site. Library for a screenshot walkthrough:
 * open a real page of a running Dynamicweb 10 / Swift 2 demo, re-skin it in the browser
 * tab (brand, navigation, text, table rows, blocks composed from the page's own classes),
 * add a caption and a concept label, and save 1920 x 1080 stills. Every change lives in
 * the DOM of this one headless tab; nothing is posted to or stored on the site.
 *
 * Runtime: Node 20+ with `playwright-core` (or `playwright`) and a Chromium channel.
 * Resolution: DW_PLAYWRIGHT_DIR (a folder that holds node_modules/playwright-core), else
 * normal module resolution from this folder (`npm install playwright-core` beside it).
 * DW_BROWSER_CHANNEL names the installed browser to drive (msedge, chrome); unset uses
 * the Chromium that Playwright installed.
 *
 * OWNING REFERENCE: dw-demo-walkthrough/SKILL.md keeps the rules (real source page,
 * grounding table, concept label); this file is the how.
 *
 * SECRETS: none read here. The caller's signIn(page) fills the storefront sign-in form
 * from its own environment (DW_FRONTEND_USER / DW_FRONTEND_PASSWORD); nothing is logged.
 *
 * Library usage (see assets/screens-template.mjs for a complete spec):
 *   import { open, goto, shoot, card } from './reskin-engine.mjs';
 *   const { browser, page } = await open({ base, signIn });
 *   await goto(page, base + '/customer-center/invoices');
 *   await page.evaluate(() => window.RS.rows('main table', rows));
 *   await shoot(page, outDir, [{ name: '03-invoices', caption: { title, sub } }], label);
 *
 * Page-side helpers on window.RS after goto(): css, remove, text, logo, nav, rows, html,
 * badge, caption. Each throws or no-ops visibly: a selector that matches nothing leaves
 * the stock page, which the still then shows.
 */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
function loadPlaywright() {
  const dir = process.env.DW_PLAYWRIGHT_DIR;
  for (const name of ['playwright-core', 'playwright']) {
    try { return require(dir ? path.join(dir, 'node_modules', name) : name); } catch { /* try the next name */ }
  }
  throw new Error('playwright-core not found: set DW_PLAYWRIGHT_DIR to a folder that holds node_modules/playwright-core, or run "npm install playwright-core" beside this script');
}
export const { chromium } = loadPlaywright();

// 1600 x 900 CSS pixels at 1.2 device pixels gives 1920 x 1080 stills at the desktop breakpoint.
export const W = 1600, H = 900, DPR = 1.2;

export async function open({ base, signIn }) {
  const browser = await chromium.launch(process.env.DW_BROWSER_CHANNEL ? { channel: process.env.DW_BROWSER_CHANNEL } : {});
  const ctx = await browser.newContext({ ignoreHTTPSErrors: process.env.DW_ALLOW_SELF_SIGNED === '1', viewport: { width: W, height: H }, deviceScaleFactor: DPR, locale: 'en-US' });
  await ctx.addCookies([{ name: 'Dynamicweb.CookieOptInLevel', value: '2', url: base }]);
  const page = await ctx.newPage(); page.setDefaultTimeout(120000);
  if (signIn) await signIn(page);
  return { browser, ctx, page };
}

// ---- page-side helpers, installed once per navigation as window.RS ----
const pageSide = () => {
  const RS = (window.RS = {});
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  RS.$$ = $$;
  RS.css = (css) => { const s = document.createElement('style'); s.textContent = css; document.head.appendChild(s); };
  RS.remove = (sels) => sels.forEach((s) => $$(s).forEach((e) => e.remove()));
  // replace text in text nodes: [[from, to], ...]; from is a string (all occurrences) or a /regex/flags string
  RS.text = (pairs, root = document.body) => {
    const rx = pairs.map(([f, t]) => [f.startsWith('/') ? new RegExp(f.slice(1, f.lastIndexOf('/')), f.slice(f.lastIndexOf('/') + 1)) : f, t]);
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT); const nodes = []; while (w.nextNode()) nodes.push(w.currentNode);
    for (const n of nodes) { let v = n.nodeValue; for (const [f, t] of rx) v = typeof f === 'string' ? v.split(f).join(t) : v.replace(f, t); if (v !== n.nodeValue) n.nodeValue = v; }
    $$('[placeholder],[title],[aria-label]').forEach((e) => ['placeholder', 'title', 'aria-label'].forEach((a) => { let v = e.getAttribute(a); if (!v) return; for (const [f, t] of rx) v = typeof f === 'string' ? v.split(f).join(t) : v.replace(f, t); e.setAttribute(a, v); }));
  };
  RS.logo = (src, width) => $$('[data-dw-itemtype="swift-v2_logo"] figure').forEach((f) => { f.style.width = width + 'px'; f.innerHTML = `<img src="${src}" style="width:100%;height:auto;display:block" alt="">`; });
  // rebuild a list-group navigation from its own items: [{label, from, active, header}], `from` = label of the stock item whose icon is reused
  RS.nav = (navSel, items) => $$(navSel).forEach((nav) => {
    const stock = {}; $$(':scope > .list-group-item', nav).forEach((d) => { stock[d.textContent.trim()] = d; });
    const head = nav.querySelector(':scope > h6'); const out = [];
    for (const it of items) {
      if (it.header) { const h = head.cloneNode(true); (h.querySelector('a') || h).textContent = it.header; out.push(h); continue; }
      const src = stock[it.from]; if (!src) throw new Error('no stock nav item: ' + it.from);
      const d = src.cloneNode(true); d.classList.toggle('active', !!it.active);
      const spans = d.querySelectorAll('a > span'); spans[spans.length - 1].textContent = it.label; out.push(d);
    }
    nav.replaceChildren(...out);
  });
  // replace the rows of a table: rows = [[cellHtml | null (keep stock cell), ...], ...]
  RS.rows = (tableSel, rows, headers) => {
    const t = document.querySelector(tableSel); const tb = t.querySelector('tbody'); const tpl = tb.querySelector('tr');
    if (headers) $$('thead th', t).forEach((th, i) => { if (headers[i] == null) return; const l = th.querySelector('label'); const tn = [...(l || th).childNodes].find((n) => n.nodeType === 3 && n.nodeValue.trim()); if (tn) tn.nodeValue = ' ' + headers[i] + ' '; });
    tb.replaceChildren(...rows.map((r) => { const tr = tpl.cloneNode(true); [...tr.children].forEach((td, i) => { if (r[i] != null) td.innerHTML = r[i]; }); return tr; }));
  };
  RS.html = (sel, html, how = 'inner') => $$(sel).forEach((e) => { if (how === 'inner') e.innerHTML = html; else e.insertAdjacentHTML(how, html); });
  RS.badge = (label, color) => `<span class="badge lh-sm badge-neutral-light" style="background-color: color-mix(in srgb, ${color} 20%, transparent) !important; color: ${color} !important">${label}</span>`;
  // caption band and concept label (the presenter's layer, in the presenting company's brand)
  // Colours are the presenting company's palette (purple #400685, blue #008FC4), never the customer's:
  // the caption has to read as the presenter talking over the screen, not as part of the product.
  RS.caption = ({ title, sub, tag, label }) => {
    let o = document.getElementById('rs-ov'); if (o) o.remove();
    o = document.createElement('div'); o.id = 'rs-ov';
    o.innerHTML = `<style>#rs-ov{position:fixed;inset:0;pointer-events:none;z-index:2147483647;font-family:'Be Vietnam Pro',Inter,Segoe UI,Arial,sans-serif}
#rs-cap{position:absolute;left:262px;top:49px;max-width:1120px;background:rgba(64,6,133,.96);color:#fff;border-radius:10px;padding:9px 18px 11px;box-shadow:0 6px 24px rgba(0,0,0,.22);border-left:6px solid #008FC4}
#rs-cap i{display:block;font-style:normal;font-size:11px;letter-spacing:.08em;text-transform:uppercase;opacity:.8}
#rs-cap b{display:block;font-size:18px;line-height:1.3}#rs-cap span{display:block;font-size:14px;line-height:1.4;opacity:.92;margin-top:2px}
#rs-lab{position:absolute;left:24px;bottom:24px;background:#fff;color:#400685;border:2px solid #400685;border-radius:999px;padding:7px 16px;font-size:14px;font-weight:600;box-shadow:0 4px 16px rgba(0,0,0,.18)}</style>
${title ? `<div id="rs-cap">${tag ? `<i>${tag}</i>` : ''}<b>${title}</b>${sub ? `<span>${sub}</span>` : ''}</div>` : ''}${label ? `<div id="rs-lab">${label}</div>` : ''}`;
    document.body.appendChild(o);
  };
};

export async function goto(page, url) {
  await page.goto(url, { waitUntil: 'networkidle' }).catch(() => {});
  await page.waitForTimeout(1200);
  await page.evaluate(pageSide);
}

// take the stills of one screen: shots = [{name, scrollTo (selector or y), caption}]
export async function shoot(page, outDir, shots, label) {
  fs.mkdirSync(outDir, { recursive: true });
  for (const s of shots) {
    await page.evaluate((to) => { if (typeof to === 'number') window.scrollTo(0, to); else if (to) { const e = document.querySelector(to); window.scrollTo(0, e.getBoundingClientRect().top + window.scrollY - 185); } else window.scrollTo(0, 0); }, s.scrollTo ?? 0);
    await page.waitForTimeout(400);
    await page.evaluate((l) => window.RS.caption({ label: l }), label);
    await page.screenshot({ path: path.join(outDir, s.name + '.clean.png') });           // for the overview document: no caption, the concept label stays
    await page.evaluate((c) => window.RS.caption(c), { ...s.caption, label });
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(outDir, s.name + '.png') });                 // for the video
    console.log('shot', s.name);
  }
}

// a full-frame card (title, closing) in the presenting company's brand
export async function card(page, outDir, name, { logoSvg, kicker, title, lines = [], rows = [] }) {
  const html = `<!doctype html><html><head><meta charset="utf8"><style>
@import url('https://fonts.googleapis.com/css2?family=Be+Vietnam+Pro:wght@400;600;700&display=swap');
html,body{margin:0;height:100%;background:#400685;color:#fff;font-family:'Be Vietnam Pro',Segoe UI,Arial,sans-serif}
.w{padding:150px 170px}.k{font-size:17px;letter-spacing:.14em;text-transform:uppercase;color:#9fdcf3;margin:44px 0 14px}
h1{font-size:54px;line-height:1.15;margin:0 0 22px;max-width:1150px}p{font-size:23px;line-height:1.5;margin:0 0 10px;max-width:1100px;opacity:.94}
table{border-collapse:collapse;margin-top:18px;font-size:20px;line-height:1.45}td{padding:7px 28px 7px 0;vertical-align:top}td:first-child{color:#9fdcf3;font-weight:600;white-space:nowrap}
.bar{width:150px;height:5px;margin-top:34px;background:linear-gradient(90deg,#008FC4,#2DB34A,#FFB310,#F76336)}</style></head><body><div class="w">
${logoSvg}<div class="k">${kicker}</div><h1>${title}</h1>${lines.map((l) => `<p>${l}</p>`).join('')}
${rows.length ? `<table>${rows.map(([a, b]) => `<tr><td>${a}</td><td>${b}</td></tr>`).join('')}</table>` : ''}<div class="bar"></div></div></body></html>`;
  await page.setContent(html, { waitUntil: 'networkidle' }).catch(() => {}); await page.waitForTimeout(600);
  fs.mkdirSync(outDir, { recursive: true });
  await page.screenshot({ path: path.join(outDir, name + '.png') }); console.log('card', name);
}
