/* =============================================================================
 * nav-affordance-probes.mjs — READ-ONLY. The four nav-affordance probes.
 * -----------------------------------------------------------------------------
 * ONE HOME PER REPO. This is the single copy for skills consumers; the owning
 * reference is dw-demo-swift/references/mobile-pass.md (the nav/mega-menu traps)
 * with the affordance rules themselves in dw-swift-building's
 * references/layout-verification.md. The Foundry keeps its own harness copy for
 * its edition gate — tools/harness/nav-affordance-probes.mjs @ f55b3da
 * (Truvio.Commerce.Foundry) — which this file was lifted from; the DemoAgent's
 * vendored third copy is retired. Keep the two in step by porting, never by
 * vendoring a third.
 *
 * Runtime: Node 20+ with `playwright` resolvable from THIS folder (ESM ignores
 * NODE_PATH and resolves from the script's directory), plus a Chromium browser:
 * `npm install playwright && npx playwright install chromium` beside this file.
 * When playwright cannot be resolved the caller reports the leg UNRUNNABLE with
 * the failed lookup named — never a silent pass.
 * -----------------------------------------------------------------------------
 * The four Wave-4 affordance probes (verbatim from
 * learnings/processed/2026-07-nav-default-menu.md, LRN-nav-03/04/05 + 01 validation).
 * -----------------------------------------------------------------------------
 * Drives a real Chromium against the running swift-demo host and asserts the
 * overlay-nav-polish affordance is LIVE:
 *   Probe 1 (caret DOM)        — every top .nav-item.dropdown carries
 *                                data-bs-toggle="dropdown" AND a rendered caret
 *                                (::after border-right-width != 0).
 *   Probe 2 (vertical reach)   — LRN-03: open a dropdown; elementFromPoint at the
 *                                vertical midpoint of the Popper gap resolves INSIDE
 *                                the .nav-item subtree (the item-anchored :has(>.show)
 *                                ::after bridge survives Popper's ~16px translate3d).
 *   Probe 3 (open-state caret)  — LRN-04: with aria-expanded="true" the caret's
 *                                ::after border-right-width != 0 AND position is static
 *                                (the caret must win ::after over Swift's
 *                                text-decoration-*-hover utilities in every open signal).
 *   Probe 4 (horizontal reach)  — LRN-05: .dropdown-menu/.megamenu min-width:100% so
 *                                menu.right >= link.right for the longest-label item.
 *
 * Depth-aware: if the menu bar has NO top .nav-item.dropdown (childless nav — the
 * data prerequisite is unmet), it exits with status "SKIP" and a clear reason rather
 * than a false PASS or a hard FAIL (nav depth is a data gap, not an affordance
 * regression; base.contract.json navDepth owns the obligation).
 *
 * Usage:  node nav-affordance-probes.mjs --url <base url> --path /swift-2/home --out result.json
 *         (--url is mandatory, or set DW_BASE_URL; there is no default host)
 * Exit:   0 = PASS or SKIP (with status in the JSON); 1 = FAIL (a real affordance regression).
 * Requires the `playwright` package + a Chromium browser (the PS wrapper provisions it,
 * or skips the leg with a clear reason when unavailable — never a silent pass).
 * ========================================================================== */

import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}

const url = arg('url', process.env.DW_BASE_URL || null);
if (!url) {
  console.error('nav-affordance-probes: no base URL. Pass --url <base url> or set DW_BASE_URL. There is no default host.');
  process.exit(1);
}
const path = arg('path', '/swift-2/home');
const outPath = arg('out', null);
const target = `${url}${path}`;

const result = { status: 'FAIL', target, probes: [], detail: '' };

function record(name, pass, detail) {
  result.probes.push({ name, result: pass ? 'PASS' : 'FAIL', detail });
  return pass;
}

const browser = await chromium.launch({ args: ['--ignore-certificate-errors'] });
try {
  const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  // 'domcontentloaded' not 'networkidle' — Swift's htmx/alpine long-polling can keep the
  // network busy indefinitely, and a networkidle timeout would throw a false FAIL.
  await page.goto(target, { waitUntil: 'domcontentloaded', timeout: 60000 });
  // Give the header a beat to render; tolerate its absence (handled as SKIP below).
  await page.locator('.megamenu-wrapper > nav').first().waitFor({ state: 'attached', timeout: 15000 }).catch(() => {});

  // A DW cookie-consent modal (#dwCookieModal) opens in every fresh context and
  // intercepts pointer events, so hover can never reach the nav through it. It fades
  // in AFTER load, so wait for it briefly, then dismiss it the way a visitor would
  // (Accept All) before probing; a host without the modal just spends the wait.
  // Ported from the demo gate's vendored copy when that copy was deleted.
  const cookieModal = page.locator('#dwCookieModal, .modal.show[aria-modal="true"]').first();
  await cookieModal.waitFor({ state: 'visible', timeout: 4000 }).catch(() => {});
  if (await cookieModal.isVisible().catch(() => false)) {
    await page.locator('#dwCookieAcceptAll, .modal.show button:has-text("Accept All")').first().click().catch(() => {});
    await cookieModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  }

  // Locate the desktop menu bar and its top-level dropdown items.
  const topItems = page.locator('.megamenu-wrapper > nav > .nav-item');
  const dropdownItems = page.locator('.megamenu-wrapper > nav > .nav-item.dropdown');
  const topCount = await topItems.count();
  const ddCount = await dropdownItems.count();

  if (ddCount === 0) {
    result.status = 'SKIP';
    result.detail =
      `No top .nav-item.dropdown in .megamenu-wrapper > nav (topItems=${topCount}). ` +
      `Nav depth is unmet — the header bar is flat (childless top nodes). The affordance CSS is ` +
      `deployed but cannot be exercised without dropdown depth. Author child nav nodes ` +
      `(save_groups recipe / base.contract.json navDepth) to exercise the real path.`;
    if (outPath) writeFileSync(outPath, JSON.stringify(result, null, 2));
    console.log(`AFFORDANCE SKIP: ${result.detail}`);
    process.exit(0);
  }

  // ---- Probe 1: caret DOM on every top dropdown item ------------------------
  let p1 = true;
  for (let i = 0; i < ddCount; i++) {
    const item = dropdownItems.nth(i);
    const link = item.locator('> .nav-link').first();
    const toggle = await link.getAttribute('data-bs-toggle');
    const borderRight = await link.evaluate((el) => getComputedStyle(el, '::after').borderRightWidth);
    const label = (await link.innerText()).trim().split('\n')[0];
    const ok = toggle === 'dropdown' && borderRight !== '0px' && borderRight !== '';
    p1 = record(`1.caret-dom[${label}]`, ok,
      `data-bs-toggle=${toggle} ::after.borderRightWidth=${borderRight}`) && p1;
  }

  // Pick the longest-label dropdown item as the probe subject for 2/3/4.
  let subjectIdx = 0, longest = -1;
  for (let i = 0; i < ddCount; i++) {
    const w = await dropdownItems.nth(i).locator('> .nav-link').first().evaluate(
      (el) => el.getBoundingClientRect().width);
    if (w > longest) { longest = w; subjectIdx = i; }
  }
  const subject = dropdownItems.nth(subjectIdx);
  const subjectLink = subject.locator('> .nav-link').first();
  const subjectLabel = (await subjectLink.innerText()).trim().split('\n')[0];

  // Open the dropdown via real hover + pointer events (not a synthetic click jump).
  await subjectLink.hover();
  await subjectLink.evaluate((el) => {
    for (const t of ['pointerenter', 'mouseenter', 'mouseover']) {
      el.dispatchEvent(new MouseEvent(t, { bubbles: true }));
    }
  });
  await page.waitForTimeout(350);

  const panel = subject.locator('> .dropdown-menu.show, > .megamenu.show').first();
  const panelVisible = await panel.count() > 0 && await panel.first().isVisible().catch(() => false);

  // ---- Probe 3: open-state caret owns ::after (border + static position) ----
  const openCaret = await subjectLink.evaluate((el) => {
    const s = getComputedStyle(el, '::after');
    const expanded = el.getAttribute('aria-expanded');
    return { borderRightWidth: s.borderRightWidth, position: s.position, aria: expanded };
  });
  const p3 = record(`3.open-caret[${subjectLabel}]`,
    openCaret.borderRightWidth !== '0px' && openCaret.borderRightWidth !== '' &&
      openCaret.position === 'static',
    `aria-expanded=${openCaret.aria} ::after.borderRightWidth=${openCaret.borderRightWidth} ::after.position=${openCaret.position}`);

  // ---- Probe 2: vertical reach — the Popper-gap bridge hit-tests as the item -
  let p2;
  if (!panelVisible) {
    p2 = record(`2.vertical-reach[${subjectLabel}]`, false, 'dropdown panel did not open on hover');
  } else {
    const geo = await subject.evaluate((item) => {
      const link = item.querySelector(':scope > .nav-link');
      const menu = item.querySelector(':scope > .dropdown-menu.show, :scope > .megamenu.show');
      const lr = link.getBoundingClientRect();
      const mr = menu.getBoundingClientRect();
      const x = Math.round(lr.left + lr.width / 2);
      const y = Math.round((lr.bottom + mr.top) / 2);
      const hit = document.elementFromPoint(x, y);
      const contained = item.contains(hit);
      return { x, y, gap: Math.round(mr.top - lr.bottom), hitClass: hit ? hit.className : '(null)', contained };
    });
    p2 = record(`2.vertical-reach[${subjectLabel}]`, geo.contained,
      `gap=${geo.gap}px elementFromPoint(${geo.x},${geo.y})=${geo.hitClass} contained=${geo.contained}`);
  }

  // ---- Probe 4: horizontal reach — panel is at least trigger width ----------
  let p4;
  if (!panelVisible) {
    p4 = record(`4.horizontal-reach[${subjectLabel}]`, false, 'dropdown panel did not open on hover');
  } else {
    const geo = await subject.evaluate((item) => {
      const link = item.querySelector(':scope > .nav-link');
      const menu = item.querySelector(':scope > .dropdown-menu.show, :scope > .megamenu.show');
      const lr = link.getBoundingClientRect();
      const mr = menu.getBoundingClientRect();
      return { linkRight: Math.round(lr.right), menuRight: Math.round(mr.right) };
    });
    p4 = record(`4.horizontal-reach[${subjectLabel}]`, geo.menuRight >= geo.linkRight,
      `menu.right=${geo.menuRight} >= link.right=${geo.linkRight}`);
  }

  // Evidence: capture the open-state menu bar next to the result JSON.
  if (outPath) {
    try { await page.screenshot({ path: outPath.replace(/\.json$/i, '-open.png'), fullPage: false }); } catch {}
  }

  const allPass = p1 && p2 && p3 && p4;
  result.status = allPass ? 'PASS' : 'FAIL';
  result.detail = `dropdownItems=${ddCount} subject="${subjectLabel}"`;
  if (outPath) writeFileSync(outPath, JSON.stringify(result, null, 2));
  console.log(`AFFORDANCE ${result.status}: ${JSON.stringify(result.probes, null, 2)}`);
  process.exit(allPass ? 0 : 1);
} catch (err) {
  result.status = 'FAIL';
  result.detail = `probe harness error: ${err.message}`;
  if (outPath) writeFileSync(outPath, JSON.stringify(result, null, 2));
  console.error(`AFFORDANCE FAIL: ${err.stack || err.message}`);
  process.exit(1);
} finally {
  await browser.close();
}
