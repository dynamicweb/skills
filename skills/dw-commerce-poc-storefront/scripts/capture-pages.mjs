#!/usr/bin/env node
/**
 * capture-pages.mjs - full-page screenshots and review slices for storefront visual QA.
 *
 * READ-ONLY on the Dynamicweb solution. WRITES: PNG, JPEG and manifest.json files under --out.
 *
 * Runtime: Node 18+ with the `playwright` package and a Chromium build available.
 * Owning reference: ../references/visual-qa.md ("Capture").
 *
 * Traps this encodes, all of which produce a screenshot that silently misrepresents the page:
 *   - a cookie or region banner intercepts pointer events and covers the first screenful, so
 *     it is dismissed by label before anything is measured;
 *   - lazy-loaded imagery never resolves in a headless page that does not scroll, so the page
 *     is stepped through with a dwell at each stop and returned to the top;
 *   - images still decoding when the shutter fires render as grey boxes, so every
 *     document.images entry must report complete with a non-zero naturalWidth;
 *   - a browser does not inherit HTTPS_PROXY the way curl does, so the proxy is passed
 *     explicitly;
 *   - a tall page pasted into a review at full height is unreadable, so each page is also cut
 *     into fixed-height slices, and phone-width slices are upscaled.
 *
 * Parameters
 *   --base-url <url>     Origin to capture against. Falls back to $DW_BASE_URL. No default.
 *   --paths <p> [p...]   One or more absolute paths to capture, e.g. /en-gb/home. Required.
 *   --out <dir>          Output directory. Default: ./shots
 *   --viewports <list>   Comma-separated W x H, suffix `m` for a mobile emulation profile.
 *                        Default: 1440x1000,390x844m
 *   --slice-height <px>  Slice height in CSS pixels. Default: 1700 desktop, 2000 mobile.
 *   --quality <1-100>    JPEG quality for slices. Default: 72
 *   --timeout <ms>       Per-navigation timeout. Default: 90000
 *   --insecure           Ignore TLS certificate errors (self-signed dev and demo hosts).
 *   --browser <path>     Chromium executable path, when Playwright cannot resolve its own.
 *   --help               Print this header.
 *
 * Example
 *   node capture-pages.mjs --base-url https://shop.example.com --out shots/round1 \
 *     --paths /en-gb/home /en-gb/shop /en-gb/shop/sofas /en-gb/shop/sofas/model-one
 *
 * Exit codes: 0 every page captured; 1 a usage error, or one or more pages failed.
 */

import { mkdir, writeFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DISMISS_LABELS = ['Accept All', 'Accept all', 'Accept', 'Allow all', 'OK', 'OKAY', 'Got it'];
const LAZY_LOAD_STEP_PX = 400;
const LAZY_LOAD_DWELL_MS = 180;
const IMAGE_DECODE_TIMEOUT_MS = 20000;
const SETTLE_MS = 1500;
const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

function printHelp() {
  const self = fileURLToPath(import.meta.url);
  const src = readFileSync(self, 'utf8');
  const header = src.slice(src.indexOf('/**'), src.indexOf('*/') + 2);
  process.stdout.write(header.replace(/^ *\/?\*+ ?/gm, '') + '\n');
}

function parseArgs(argv) {
  const opts = { paths: [], out: 'shots', viewports: '1440x1000,390x844m', quality: 72, timeout: 90000 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => {
      const v = argv[++i];
      if (v === undefined || v.startsWith('--')) throw new Error(`${a} needs a value`);
      return v;
    };
    if (a === '--help' || a === '-h') return { help: true };
    else if (a === '--base-url') opts.baseUrl = next();
    else if (a === '--out') opts.out = next();
    else if (a === '--viewports') opts.viewports = next();
    else if (a === '--slice-height') opts.sliceHeight = Number(next());
    else if (a === '--quality') opts.quality = Number(next());
    else if (a === '--timeout') opts.timeout = Number(next());
    else if (a === '--insecure') opts.insecure = true;
    else if (a === '--browser') opts.browser = next();
    else if (a === '--paths') {
      while (argv[i + 1] !== undefined && !argv[i + 1].startsWith('--')) opts.paths.push(argv[++i]);
      if (opts.paths.length === 0) throw new Error('--paths needs at least one path');
    } else throw new Error(`unknown argument: ${a}`);
  }
  return opts;
}

function parseViewports(spec) {
  return spec.split(',').map((raw) => {
    const m = /^(\d+)x(\d+)(m?)$/.exec(raw.trim());
    if (!m) throw new Error(`bad --viewports entry "${raw}" - use WIDTHxHEIGHT, e.g. 1440x1000 or 390x844m`);
    return { width: Number(m[1]), height: Number(m[2]), mobile: m[3] === 'm' };
  });
}

function slugify(p) {
  const s = p.replace(/^\/+|\/+$/g, '').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return s || 'root';
}

async function preparePage(page, url, timeout) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout });
  await page.waitForTimeout(2500);

  for (const label of DISMISS_LABELS) {
    try {
      const button = page.locator(`button:has-text("${label}")`).first();
      if (await button.isVisible({ timeout: 500 })) {
        await button.click({ timeout: 2000 });
        await page.waitForTimeout(900);
        break;
      }
    } catch {
      /* banner absent or already dismissed - the next label, or none, is fine */
    }
  }

  await page.evaluate(
    async ([step, dwell]) => {
      const pause = (ms) => new Promise((r) => setTimeout(r, ms));
      for (let y = 0; y < document.body.scrollHeight; y += step) {
        window.scrollTo(0, y);
        await pause(dwell);
      }
      window.scrollTo(0, document.body.scrollHeight);
      await pause(800);
      window.scrollTo(0, 0);
      await pause(400);
    },
    [LAZY_LOAD_STEP_PX, LAZY_LOAD_DWELL_MS]
  );

  await page
    .waitForFunction(
      () => {
        const images = [...document.images];
        return images.length === 0 || images.every((i) => i.complete && i.naturalWidth > 0);
      },
      { timeout: IMAGE_DECODE_TIMEOUT_MS }
    )
    .catch(() => {
      /* a permanently broken image must not cost the whole capture */
    });

  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(SETTLE_MS);

  return page.evaluate(() => ({
    title: document.title,
    height: document.documentElement.scrollHeight,
    images: document.images.length,
    loaded: [...document.images].filter((i) => i.naturalWidth > 0).length,
  }));
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (e) {
    console.error(`capture-pages: ${e.message}\nRun with --help for usage.`);
    return 1;
  }
  if (opts.help) {
    printHelp();
    return 0;
  }

  const baseUrl = opts.baseUrl || process.env.DW_BASE_URL;
  if (!baseUrl) {
    console.error(
      'capture-pages: no base URL.\nFix: pass --base-url https://<host> or export DW_BASE_URL=https://<host>'
    );
    return 1;
  }
  if (opts.paths.length === 0) {
    console.error('capture-pages: no paths.\nFix: pass --paths /en-gb/home /en-gb/shop');
    return 1;
  }

  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch {
    console.error(
      'capture-pages: the playwright package is not installed.\nFix: npm install playwright && npx playwright install chromium'
    );
    return 1;
  }

  const viewports = parseViewports(opts.viewports);
  await mkdir(opts.out, { recursive: true });

  const launch = { args: ['--no-sandbox', '--disable-dev-shm-usage'] };
  if (opts.browser) launch.executablePath = opts.browser;
  if (process.env.HTTPS_PROXY || process.env.https_proxy) {
    launch.proxy = { server: process.env.HTTPS_PROXY || process.env.https_proxy };
  }
  if (opts.insecure) launch.args.push('--ignore-certificate-errors');

  const browser = await chromium.launch(launch);
  const manifest = {};
  let failures = 0;

  try {
    for (const vp of viewports) {
      const context = await browser.newContext({
        viewport: { width: vp.width, height: vp.height },
        // Phone-width slices are unreadable at 1x in a review, so emulate a retina screen.
        deviceScaleFactor: vp.mobile ? 2 : 1,
        ignoreHTTPSErrors: Boolean(opts.insecure),
        isMobile: vp.mobile,
        hasTouch: vp.mobile,
        userAgent: vp.mobile ? MOBILE_UA : undefined,
      });
      const sliceHeight = opts.sliceHeight || (vp.mobile ? 2000 : 1700);

      for (const p of opts.paths) {
        const name = `${vp.mobile ? 'mobile-' : ''}${slugify(p)}`;
        const url = new URL(p, baseUrl).toString();
        const page = await context.newPage();
        try {
          const info = await preparePage(page, url, opts.timeout);
          const full = path.join(opts.out, `${name}.png`);
          await page.screenshot({ path: full, fullPage: true });

          const slices = [];
          for (let y = 0, n = 1; y < info.height; y += sliceHeight, n++) {
            const height = Math.min(sliceHeight, info.height - y);
            const file = path.join(opts.out, `${name}-${n}.jpg`);
            await page.screenshot({
              path: file,
              fullPage: true,
              type: 'jpeg',
              quality: opts.quality,
              clip: { x: 0, y, width: vp.width, height },
            });
            slices.push(file);
          }

          manifest[name] = {
            url,
            title: info.title,
            viewport: `${vp.width}x${info.height}`,
            images: `${info.loaded}/${info.images}`,
            full,
            slices,
          };
          console.log(`OK   ${name}  ${vp.width}x${info.height}  imgs ${info.loaded}/${info.images}  ${slices.length} slices`);
        } catch (e) {
          failures++;
          console.error(`FAIL ${name}  ${url}\n     ${String(e).split('\n')[0]}`);
        } finally {
          await page.close();
        }
      }
      await context.close();
    }
  } finally {
    await browser.close();
  }

  const manifestPath = path.join(opts.out, 'manifest.json');
  await writeFile(manifestPath, JSON.stringify(manifest, null, 1), 'utf8');
  console.log(`\nmanifest: ${manifestPath}  (${Object.keys(manifest).length} pages, ${failures} failed)`);
  return failures > 0 ? 1 : 0;
}

main().then(
  (code) => process.exit(code),
  (e) => {
    console.error(`capture-pages: ${e && e.stack ? e.stack : e}`);
    process.exit(1);
  }
);
