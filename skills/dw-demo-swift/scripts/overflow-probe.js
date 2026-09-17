/* =============================================================================
 * overflow-probe.js — READ-ONLY. The generic canvas-fit / legibility / overlap
 * core: does the page fit the canvas it was asked for, can a human read it, and
 * does any text collide with other text.
 * -----------------------------------------------------------------------------
 * OWNING REFERENCE: dw-demo-swift/references/mobile-pass.md ("The debugging method
 * that works" + "Gate implication") keeps the rules, the Swift 2 causes and the
 * trap catalogue; this file is the how. Nothing is asserted here that is not
 * stated there. Lifted from the Foundry's tools/demo-gate/design-probes.mjs
 * @ ed3ee0b (Truvio.Commerce.Foundry); the Swift-2-specific detectors of that file
 * (image bands, stretch, section gaps, PLP rows, CSSOM, header clearance, required
 * sections, mojibake) stay with the Foundry gate and its config contract.
 *
 * Four checks, per page per viewport:
 *
 *   canvas-fit    innerWidth === the REQUESTED width, AND body.scrollWidth ===
 *                 innerWidth. Both halves are load-bearing. body, not
 *                 documentElement: `overflow-x: hidden` on body hides the stretch
 *                 from documentElement.scrollWidth. And scrollWidth === innerWidth
 *                 alone certifies a broken page, because once the browser widens
 *                 the layout viewport to fit unshrinkable content the two are equal
 *                 BY CONSTRUCTION (measured: body.scrollWidth 652, innerWidth 652,
 *                 requested 390 — a 262px stretch reported as zero). The innerWidth
 *                 leg is what catches the widened layout viewport.
 *
 *   offender      names the element whose RIGHT EDGE is the overflow, never the
 *                 widest element. A closed Bootstrap drawer (Swift's
 *                 #DynamicOffcanvas) is `position: fixed`, visibility:hidden and
 *                 translated off the right edge, so it sits outside the scrollable
 *                 overflow and tracks the stretch while contributing nothing to it
 *                 — and at a full viewport wide it outranks the real offender in
 *                 every width-sorted list. Such elements (fixed subtree,
 *                 display:none, visibility:hidden) are set aside as
 *                 `ignoredOffender` and NAMED as set aside, so the reader is not
 *                 sent hunting a CSS width bug that is not there.
 *
 *   contrast      WCAG ratio of every text LEAF (own text nodes only) against the
 *                 nearest ancestor painting an opaque-enough background. An element
 *                 with no text of its own has no defined contrast. Thresholds are
 *                 parameters (--min-contrast / --min-contrast-large); large is
 *                 >=24px, or >=18.66px bold.
 *
 *   text-overlap  no two painted LINE boxes intersect by more than
 *                 --max-overlap-ratio of the smaller box. getClientRects(), not
 *                 getBoundingClientRect(): the bounding box of a wrapped inline is
 *                 the UNION of its line boxes, so two ordinary adjacent links in one
 *                 paragraph report a 0.44 intersection with nothing overlapping on
 *                 screen. A rect ENTIRELY outside a clipping ancestor is skipped:
 *                 clipping hides paint, not layout, so rows scrolled out of a capped
 *                 overflow:auto container keep their full layout rectangle and would
 *                 otherwise "collide" with every section below them.
 *
 * A VIEWPORT IS NOT A DEVICE. Dynamicweb picks the header SERVER-SIDE by
 * user-agent, so a sub-desktop viewport with no device descriptor measures the
 * DESKTOP document at phone width and nothing measured is what a phone user gets.
 * Below --desktop-breakpoint this probe REFUSES to measure without --device (a
 * Playwright device descriptor): a refusal, not a silent pass.
 *
 * Runtime: Node 20+ with `playwright` resolvable from THIS folder (module
 * resolution walks up from the script's directory), plus a Chromium browser:
 * `npm install playwright && npx playwright install chromium` beside this file.
 *
 * Usage:
 *   node overflow-probe.js --url <base url> --path /home --path /products \
 *     --width 390 --height 844 --device "iPhone 12" --out result.json
 *   (--url is mandatory, or set DW_BASE_URL; there is no default host.)
 *
 * Flags: --url --path (repeatable, default /) --width --height --device
 *   --desktop-breakpoint --scroll-tolerance --min-contrast --min-contrast-large
 *   --max-overlap-ratio --text-selector --scope-selector --max-report --out
 *   --allow-self-signed --timeout
 *
 * Result: { status: PASS|FAIL, target, requested, probes: [ { name, result,
 *   detail, value } ], detail } on stdout, and to --out when given.
 * Exit:   0 = PASS, 1 = FAIL, 2 = the probe could not run (say so, never a pass).
 * ========================================================================== */

'use strict';

const { writeFileSync } = require('node:fs');

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

function flag(name) {
  return process.argv.includes(`--${name}`);
}

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

/* ---- the in-page detectors. Serialised into the browser, so they take plain
 * options and return plain data. ---------------------------------------------- */

function canvasDetector() {
  const de = document.documentElement;
  const vw = window.innerWidth;
  const bodyScroll = document.body ? document.body.scrollWidth : de.scrollWidth;
  const docScroll = de.scrollWidth;

  // The offender is the element whose RIGHT EDGE is the overflow. Anything out of
  // flow (a fixed subtree, display:none, visibility:hidden) is a symptom, not a
  // cause: it is kept apart so the message can say what was set aside.
  const fixedRoots = [];
  for (const el of document.querySelectorAll('body *')) {
    if (getComputedStyle(el).position === 'fixed') fixedRoots.push(el);
  }
  let offender = null;
  let ignored = null;
  for (const el of document.querySelectorAll('body *')) {
    const r = el.getBoundingClientRect();
    if (!(r.width > 0 && (r.right > vw + 1 || r.left < -1))) continue;
    const cs = getComputedStyle(el);
    const hit = {
      tag: el.tagName,
      id: el.id || null,
      cls: String(el.className || '').slice(0, 60),
      right: Math.round(r.right),
      width: Math.round(r.width),
    };
    const outOfFlow = cs.display === 'none' || cs.visibility === 'hidden' ||
      fixedRoots.some((f) => f.contains(el));
    if (outOfFlow) {
      if (!ignored || r.right > ignored.right) ignored = hit;
      continue;
    }
    if (!offender || r.right > offender.right) offender = hit;
  }
  return { innerWidth: vw, bodyScrollWidth: bodyScroll, docScrollWidth: docScroll, offender, ignoredOffender: ignored };
}

function contrastDetector(opts) {
  const { textSelector, minContrast, minContrastLarge, maxReport } = opts;
  const parseRGB = (s) => {
    const m = String(s).match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const p = m[1].split(/[\s,/]+/).filter(Boolean).map(Number);
    if (p.length < 3 || p.some(Number.isNaN)) return null;
    return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
  };
  const lum = (c) => {
    const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
  };
  const ratio = (a, b) => {
    const l1 = lum(a), l2 = lum(b);
    return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
  };
  // Nearest ancestor painting an opaque-enough background; the page default is white.
  const bgOf = (el) => {
    let n = el;
    while (n) {
      const c = parseRGB(getComputedStyle(n).backgroundColor);
      if (c && c.a > 0.5) return c;
      n = n.parentElement;
    }
    return { r: 255, g: 255, b: 255, a: 1 };
  };
  // Own text = direct child text nodes. Contrast of an element with no text of its
  // own is undefined: its colour is inherited by children that carry their own.
  const ownText = (el) => {
    let t = '';
    for (const n of el.childNodes) if (n.nodeType === 3) t += n.nodeValue;
    return t.trim();
  };
  const describe = (el) => {
    const id = el.id ? `#${el.id}` : '';
    const cls = String(el.className || '').trim().split(/\s+/).filter(Boolean).slice(0, 2).join('.');
    return `${el.tagName.toLowerCase()}${id}${cls ? '.' + cls : ''}`;
  };

  const out = { checked: 0, fails: [] };
  for (const el of document.querySelectorAll(textSelector)) {
    const txt = ownText(el);
    if (!txt) continue;
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none' ||
        parseFloat(cs.opacity) < 0.05 || r.width < 1 || r.height < 1) continue;
    const fg = parseRGB(cs.color);
    if (!fg) continue;
    const fs = parseFloat(cs.fontSize) || 16;
    const bold = (parseInt(cs.fontWeight, 10) || 400) >= 700;
    const large = fs >= 24 || (fs >= 18.66 && bold);
    const need = large ? minContrastLarge : minContrast;
    const got = ratio(fg, bgOf(el));
    out.checked++;
    if (got < need) {
      const bg = bgOf(el);
      out.fails.push({
        el: describe(el), text: txt.slice(0, 34), ratio: +got.toFixed(2), need,
        fs: Math.round(fs), color: cs.color, bg: `rgb(${bg.r}, ${bg.g}, ${bg.b})`,
      });
    }
  }
  out.fails.sort((a, b) => a.ratio - b.ratio);
  out.worstRatio = out.fails.length ? out.fails[0].ratio : null;
  out.count = out.fails.length;
  out.fails = out.fails.slice(0, maxReport);
  return out;
}

function overlapDetector(opts) {
  const { scopeSelector, maxRatio, maxReport } = opts;
  const root = document.querySelector(scopeSelector) || document.body;

  // CLIPPING HIDES PAINT, NOT LAYOUT. Only skip a rect ENTIRELY outside a clipping
  // ancestor's box — a rect merely straddling the edge is still compared, because
  // half of it is visible.
  const clippedOutOfView = (el, r) => {
    let p = el.parentElement;
    while (p && p !== document.documentElement) {
      const cs = getComputedStyle(p);
      const clipY = cs.overflowY !== 'visible', clipX = cs.overflowX !== 'visible';
      if (clipY || clipX) {
        const pr = p.getBoundingClientRect();
        if (clipY && (r.top >= pr.bottom - 0.5 || r.bottom <= pr.top + 0.5)) return true;
        if (clipX && (r.left >= pr.right - 0.5 || r.right <= pr.left + 0.5)) return true;
      }
      p = p.parentElement;
    }
    return false;
  };

  const els = [];
  for (const el of root.querySelectorAll('*')) {
    let own = '';
    for (const n of el.childNodes) if (n.nodeType === 3) own += n.nodeValue;
    if (!own.trim()) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none' || parseFloat(cs.opacity) < 0.05) continue;
    for (const r of el.getClientRects()) {
      if (r.width <= 0 || r.height <= 0) continue;
      if (clippedOutOfView(el, r)) continue;
      els.push({ el, r, t: own.trim().slice(0, 28) });
    }
  }
  els.sort((a, b) => (a.r.top + a.r.height / 2) - (b.r.top + b.r.height / 2));
  const hits = [];
  for (let i = 0; i < els.length; i++) {
    const A = els[i], mi = A.r.top + A.r.height / 2;
    for (let j = i + 1; j < els.length; j++) {
      const B = els[j], mj = B.r.top + B.r.height / 2;
      if (mj - mi > 200) break;                   // spatial bucketing keeps this O(n*k)
      if (A.el === B.el || A.el.contains(B.el) || B.el.contains(A.el)) continue;
      const ix = Math.max(0, Math.min(A.r.right, B.r.right) - Math.max(A.r.left, B.r.left));
      const iy = Math.max(0, Math.min(A.r.bottom, B.r.bottom) - Math.max(A.r.top, B.r.top));
      const inter = ix * iy;
      if (inter <= 0) continue;
      const rt = inter / Math.min(A.r.width * A.r.height, B.r.width * B.r.height);
      if (rt > maxRatio) hits.push({ a: A.t, b: B.t, ratio: +rt.toFixed(2) });
    }
  }
  hits.sort((a, b) => b.ratio - a.ratio);
  return { scanned: els.length, count: hits.length, hits: hits.slice(0, maxReport) };
}

/* ---- the runner ------------------------------------------------------------- */

async function main() {
  const baseUrl = arg('url', process.env.DW_BASE_URL || null);
  const outPath = arg('out', null);
  if (!baseUrl) {
    console.error('overflow-probe: no base URL. Pass --url <base url> or set DW_BASE_URL. There is no default host.');
    process.exit(2);
  }
  const paths = argAll('path').length ? argAll('path') : ['/'];
  const width = Number(arg('width', '390'));
  const height = Number(arg('height', '844'));
  const deviceName = arg('device', null);
  const desktopBreakpoint = Number(arg('desktop-breakpoint', '992'));
  const scrollTolerance = Number(arg('scroll-tolerance', '1'));
  const minContrast = Number(arg('min-contrast', '4.5'));
  const minContrastLarge = Number(arg('min-contrast-large', '3'));
  const maxOverlapRatio = Number(arg('max-overlap-ratio', '0.25'));
  const textSelector = arg('text-selector', 'main *, header *, footer *');
  const scopeSelector = arg('scope-selector', 'main');
  const maxReport = Number(arg('max-report', '6'));
  const timeoutMs = Number(arg('timeout', '60000'));

  const result = {
    status: 'FAIL', target: baseUrl,
    requested: { width, height, device: deviceName },
    thresholds: { desktopBreakpoint, scrollTolerance, minContrast, minContrastLarge, maxOverlapRatio },
    probes: [], detail: '',
  };
  const record = (name, pass, detail, value) => {
    result.probes.push({ name, result: pass ? 'PASS' : 'FAIL', detail, value: value === undefined ? null : value });
    return pass;
  };
  const finish = (code) => {
    if (outPath) writeFileSync(outPath, JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
    process.exit(code);
  };

  let chromium, devices;
  try {
    ({ chromium, devices } = await import('playwright'));
  } catch (e) {
    result.status = 'UNRUNNABLE';
    result.detail = `playwright is not resolvable from ${__dirname}: ${e.message}. ` +
      'Run `npm install playwright && npx playwright install chromium` in this folder. ' +
      'An unrunnable leg is never a pass.';
    finish(2);
  }

  // A viewport is not a device: refuse to measure a sub-desktop width with no descriptor.
  if (width < desktopBreakpoint && !deviceName) {
    result.detail = `requested width ${width}px is below the ${desktopBreakpoint}px desktop breakpoint and no --device was given. ` +
      'Dynamicweb selects the header server-side by user-agent, so Chromium keeps its desktop UA and the DESKTOP document ' +
      'is what gets measured — a layout no phone user receives. Pass --device "iPhone 12". No assert ran.';
    record('device-descriptor', false, result.detail, null);
    finish(1);
  }
  if (deviceName && !devices[deviceName]) {
    result.detail = `playwright does not know device "${deviceName}"; the run would have measured the desktop document. No assert ran.`;
    record('device-descriptor', false, result.detail, null);
    finish(1);
  }

  const bypass = tlsBypassAllowed(baseUrl, flag('allow-self-signed'));
  const browser = await chromium.launch({ args: bypass ? ['--ignore-certificate-errors'] : [] });
  try {
    // Spread the descriptor BEFORE the explicit viewport so the device's identity
    // (UA, isMobile, hasTouch, deviceScaleFactor) is kept while declared geometry wins.
    const dev = deviceName ? { ...devices[deviceName] } : {};
    delete dev.defaultBrowserType;
    const context = await browser.newContext({
      ignoreHTTPSErrors: bypass,
      ...dev,
      viewport: { width, height },
    });
    const page = await context.newPage();

    for (const p of paths) {
      const target = `${baseUrl}${p}`;
      try {
        await page.goto(target, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
        // Scroll-sweep so lazy-loaded content lays out before anything is measured.
        await page.evaluate(async () => {
          const step = Math.round(window.innerHeight * 0.8);
          for (let y = 0; y < document.body.scrollHeight; y += step) {
            window.scrollTo(0, y);
            await new Promise((r) => setTimeout(r, 60));
          }
          window.scrollTo(0, 0);
          await new Promise((r) => setTimeout(r, 120));
        });
      } catch (e) {
        record(`load[${p}]`, false, `page did not load: ${e.message}`, null);
        continue;
      }

      const c = await page.evaluate(canvasDetector);
      const widthOk = c.innerWidth === width;
      const scrollOk = Math.abs(c.bodyScrollWidth - c.innerWidth) <= scrollTolerance;
      const named = c.offender
        ? `${c.offender.tag}${c.offender.id ? '#' + c.offender.id : ''}${c.offender.cls ? '.' + c.offender.cls.trim().split(/\s+/)[0] : ''} right=${c.offender.right}`
        : '(no in-flow element crosses the right edge)';
      const setAside = c.ignoredOffender
        ? ` Set aside as out of flow (fixed / hidden — a closed drawer is the usual one): ${c.ignoredOffender.tag}.${String(c.ignoredOffender.cls).trim().split(/\s+/)[0]} right=${c.ignoredOffender.right}.`
        : '';
      record(`canvas-fit[${p}]`, widthOk && scrollOk,
        `innerWidth=${c.innerWidth} requested=${width}${widthOk ? '' : ' — the layout viewport was WIDENED, so body.scrollWidth === innerWidth is true by construction and proves nothing'}` +
        `; body.scrollWidth=${c.bodyScrollWidth} (documentElement.scrollWidth=${c.docScrollWidth}). ` +
        `Offender by right edge: ${named}.${setAside}`,
        Math.max(c.innerWidth - width, c.bodyScrollWidth - c.innerWidth));

      const ct = await page.evaluate(contrastDetector, { textSelector, minContrast, minContrastLarge, maxReport });
      record(`contrast[${p}]`, ct.count === 0,
        ct.count === 0
          ? `${ct.checked} text leaf/leaves all at or above ${minContrast}:1 (large text ${minContrastLarge}:1)`
          : `${ct.count} of ${ct.checked} text leaves below threshold; worst ${ct.worstRatio}:1 — ` +
            ct.fails.map((f) => `${f.el} "${f.text}" ${f.ratio}<${f.need} (${f.color} on ${f.bg})`).join('; '),
        ct.count);

      const ov = await page.evaluate(overlapDetector, { scopeSelector, maxRatio: maxOverlapRatio, maxReport });
      record(`text-overlap[${p}]`, ov.count === 0,
        ov.count === 0
          ? `${ov.scanned} line box(es) in '${scopeSelector}', none intersecting by more than ${maxOverlapRatio}`
          : `${ov.count} colliding pair(s) of ${ov.scanned} line boxes — ` +
            ov.hits.map((h) => `"${h.a}" x "${h.b}" ${h.ratio}`).join('; '),
        ov.count);
    }
  } catch (e) {
    result.status = 'UNRUNNABLE';
    result.detail = `probe harness error: ${e.message}`;
    await browser.close();
    finish(2);
  }
  await browser.close();

  const failed = result.probes.filter((x) => x.result === 'FAIL');
  result.status = failed.length === 0 && result.probes.length > 0 ? 'PASS' : 'FAIL';
  result.detail = result.probes.length === 0
    ? 'no probe ran — nothing was measured, so this is not a pass'
    : `${result.probes.length - failed.length}/${result.probes.length} probe(s) passed across ${paths.length} path(s)`;
  finish(result.status === 'PASS' ? 0 : 1);
}

main();
