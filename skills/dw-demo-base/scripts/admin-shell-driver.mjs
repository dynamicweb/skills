/**
 * admin-shell-driver.mjs — READ-ONLY by default. The five DW 10.28 admin-shell
 * automation guards, as an importable module plus a small CLI.
 *
 * Runtime: Node 20+ with the `playwright` package resolvable from THIS folder
 * (ESM ignores NODE_PATH; module resolution walks up from the script directory, so
 * run `npm install playwright && npx playwright install chromium` in a folder beside
 * this file, or copy the file next to an existing node_modules/playwright).
 *
 * OWNING REFERENCE: dw-demo-base/references/browser-automation.md, "Driving the DW
 * 10.28 admin shell" — it keeps the five rules and the why; this file is the how.
 * The grid-edit read-back/abort guard's rule is owned by
 * dw-demo-pim/references/screen-authoring.md. No rule lives only here.
 *
 * Verification-only still applies: the admin surface is API-first (dw-data-access's
 * action ladder). Admin-grid authoring is a guarded exception only where no API
 * surface exists, which is exactly why gridEditCell carries a read-back/abort guard.
 *
 * Each guard encodes a defect a naive Playwright recipe walks straight into. Every
 * function takes a Playwright `page` and THROWS on a violated guard. A guard that
 * returns quietly on a miss is worse than no guard: the failure modes below all
 * report success while doing the wrong thing.
 *
 * SECRETS: environment only, no defaults anywhere.
 *   DW_BASE_URL        host base URL (or --base)
 *   DW_ADMIN_USER      admin login name, CLI sign-in only
 *   DW_ADMIN_PASSWORD  its secret, CLI sign-in only — never echoed, never a parameter
 * Prefer `--storage-state <file>` (a session saved by a previous signed-in run) so no
 * credential is read at all. TLS validation is skipped only when the base URL host is
 * localhost/127.0.0.1, or when `--allow-self-signed` is passed explicitly.
 *
 * Library usage:
 *   import { evaluateClick, clickByText, closeAi, openProductEdit, gridEditCell,
 *            assertTreeNav, ADMIN_TREE_NAV_X } from './admin-shell-driver.mjs';
 *
 * CLI usage (prints one JSON object on stdout; exit 0 = guard held, 1 = violated):
 *   node admin-shell-driver.mjs tree-nav     --base <url> [--path /Admin]
 *   node admin-shell-driver.mjs close-ai     --base <url> [--path /Admin]
 *   node admin-shell-driver.mjs click        --base <url> --text "Import" --expect-url "QuickImport" [--scope ".modal.show"]
 *   node admin-shell-driver.mjs open-product --base <url> --nav "PIM|Product structures|Catalog" --product "Chai"
 *   node admin-shell-driver.mjs changed-count --base <url> --path /Admin/UI/Products/ProductGridEdit
 * Common flags: --storage-state <file> --save-state <file> --width 1440 --height 1000
 *   --allow-self-signed --headed --timeout 30000
 */

import { pathToFileURL } from 'node:url';

/**
 * The x coordinate of `.tree-nav` when the shell is NOT translated. Measured at
 * 1440x1000 on DW 10.28.4. A double-closed AI rail translates the whole shell by the
 * rail width (355px) and the tree lands at -163.
 * @type {number}
 */
export const ADMIN_TREE_NAV_X = 192;

/**
 * Default selector for the admin AI assistant's ask input.
 * @type {string}
 */
export const ASK_INPUT_SELECTOR = 'input[placeholder*="Ask anything" i], textarea[placeholder*="Ask anything" i]';

/**
 * Click an element by its exact text through the DOM, not through Playwright's
 * visibility-aware click.
 *
 * WHY (#375): the DW 10.28 admin shell pre-renders EVERY action-menu item for EVERY
 * toolbar on the screen into the document at load time, inside collapsed containers.
 * Clicking each of 15 different `uil-ellipsis-h` buttons on
 * /Admin/UI/Products/ProductList dumps the SAME 40-item list (New query, Add workspace,
 * Manage columns, Import, Export, Add to data model, Bulk update, Translate, Combine as
 * variants, ...), because the list is one shared hidden block rather than per-menu
 * markup. Playwright's `locator.click()` and `isVisible()` correctly report those items
 * as not visible, so a text-matching helper skips them and a click on /^Import$/ returns
 * null every time. `page.evaluate(el => el.click())` on the same text navigates straight
 * to the Quick Import screen.
 *
 * SCOPE IT (#375): when a picker or wizard dialog is open, pass `scope` set to that
 * dialog. An unscoped text click on "Integration" hits the shell nav and navigates away
 * from the wizard.
 *
 * @param {import('playwright').Page} page
 * @param {string} text Exact (trimmed) innerText of the target.
 * @param {object} [opts]
 * @param {string} [opts.scope] CSS selector of the open dialog/modal to search inside.
 *   Required whenever a dialog is open.
 * @param {number} [opts.index=0] Which match to click when several share the text.
 * @returns {Promise<{clicked: boolean, matches: number, href: string|null}>}
 * @throws when no element matches the text inside the scope.
 */
export async function evaluateClick(page, text, opts = {}) {
  const { scope = null, index = 0 } = opts;
  const result = await page.evaluate(
    ({ text, scope, index }) => {
      const root = scope ? document.querySelector(scope) : document;
      if (!root) return { clicked: false, matches: 0, href: null, noRoot: true };
      const all = [...root.querySelectorAll('a, button, [role="menuitem"], .dropdown-item')].filter(
        (el) => el.innerText.trim() === text
      );
      if (all.length <= index) return { clicked: false, matches: all.length, href: null };
      const el = all[index];
      const href = el.getAttribute('href');
      el.click();
      return { clicked: true, matches: all.length, href };
    },
    { text, scope, index }
  );
  if (result.noRoot) throw new Error(`evaluateClick: scope '${scope}' matched no element`);
  if (!result.clicked) {
    throw new Error(
      `evaluateClick: no element with exact text '${text}'${scope ? ` inside '${scope}'` : ''} (matches: ${result.matches}). ` +
        `Hidden pre-rendered items ARE reachable this way, so a zero here means the text is wrong, not that the item is collapsed.`
    );
  }
  return result;
}

/**
 * Click an element by its text after filtering to elements with a REAL bounding box,
 * then assert the resulting URL.
 *
 * WHY (#417): the admin shell also pre-renders the left tree's context menus into the
 * same document. On a product overview there are ~22 anchors whose exact text is "Edit";
 * 21 of them have `getBoundingClientRect()` of 0,0 at x=0,y=0 and point at
 * DynamicStructureOverview / ShopEdit / ProductCatalogGroupEdit. The product's own Edit
 * is a `button.btn-link` inside the details card at roughly x=1391,y=227. Selecting by
 * text alone picks a hidden one, the click reports SUCCESS, the page loads 200, and you
 * land on a data model instead of the product. The only tell is the URL.
 *
 * This is the same family as evaluateClick (#375) but the failure mode is inverted: a
 * SUCCESSFUL click on the wrong target, not a missed click. So the box filter comes
 * first and the post-click URL assert is mandatory.
 *
 * @param {import('playwright').Page} page
 * @param {string} text Exact (trimmed) innerText of the target.
 * @param {object} opts
 * @param {RegExp|string} opts.expectUrl Pattern the resulting URL must match. Mandatory:
 *   never assert only that the click returned true.
 * @param {string} [opts.scope] CSS selector of an open dialog to search inside.
 * @param {number} [opts.timeoutMs=15000] How long to wait for the URL to settle.
 * @returns {Promise<{url: string, box: {x: number, y: number, width: number, height: number}}>}
 * @throws when no boxed element matches, or the resulting URL does not match expectUrl.
 */
export async function clickByText(page, text, opts) {
  const { expectUrl, scope = null, timeoutMs = 15000 } = opts || {};
  if (!expectUrl) throw new Error('clickByText: opts.expectUrl is required. A click that is not URL-asserted proves nothing');
  const pattern = expectUrl instanceof RegExp ? expectUrl : new RegExp(expectUrl);

  const picked = await page.evaluate(
    ({ text, scope }) => {
      const root = scope ? document.querySelector(scope) : document;
      if (!root) return { ok: false, total: 0, boxed: 0, noRoot: true };
      const all = [...root.querySelectorAll('a, button, [role="menuitem"], .dropdown-item')].filter(
        (el) => el.innerText.trim() === text
      );
      // A real box: non-zero size AND a non-zero origin. The pre-rendered context-menu
      // anchors all sit at exactly 0,0.
      const boxed = all.filter((el) => {
        const b = el.getBoundingClientRect();
        return b.width > 0 && b.height > 0 && b.x > 0 && b.y > 0;
      });
      if (boxed.length === 0) return { ok: false, total: all.length, boxed: 0 };
      const el = boxed[0];
      const b = el.getBoundingClientRect();
      el.click();
      return { ok: true, total: all.length, boxed: boxed.length, box: { x: b.x, y: b.y, width: b.width, height: b.height } };
    },
    { text, scope }
  );
  if (picked.noRoot) throw new Error(`clickByText: scope '${scope}' matched no element`);
  if (!picked.ok) {
    throw new Error(
      `clickByText: '${text}' matched ${picked.total} element(s) but NONE had a real bounding box. ` +
        `Every match is a pre-rendered hidden node at 0,0; the visible control is elsewhere in the DOM.`
    );
  }
  try {
    await page.waitForURL(pattern, { timeout: timeoutMs });
  } catch {
    throw new Error(
      `clickByText: clicked '${text}' (${picked.boxed} boxed of ${picked.total} matches) and landed on ${page.url()}, which does not match ${pattern}. ` +
        `The click succeeded on the wrong target.`
    );
  }
  return { url: page.url(), box: picked.box };
}

/**
 * Close the admin AI assistant rail, idempotently.
 *
 * WHY (#409): the rail is a TOGGLE. A helper that called close once on navigation and
 * again inside the screenshot function re-opened and re-closed it, leaving the whole
 * shell translated by the rail width: the left tree pane goes off-canvas, the content
 * column slides under the purple app rail, field labels and the first grid column are
 * clipped. The DOM stays healthy, so every assertion passes while the pictures are
 * unusable.
 *
 * The two obvious open-state tells are BOTH WRONG:
 *   1. "Ask anything" is a PLACEHOLDER attribute, not innerText, so
 *      /Ask anything/.test(document.body.innerText) is always false, even with the rail
 *      visibly open;
 *   2. `button.js-minimize` (title="Minimize") stays in the DOM with a non-zero box
 *      after the rail is minimised, so testing for its presence is always true.
 *
 * The only reliable tell is the ask input's POSITION: open == rect.width > 0 &&
 * rect.x < window.innerWidth - 20. Measured: one click moves the ask input from x=1142
 * to x=1497 (off-canvas) while the tree stays at 192; three clicks put the tree at -163
 * and the General tab at x=85, under the 190px app rail.
 *
 * So: measure, click exactly ONE selector per round, re-measure, max 3 rounds. A second
 * call on an already-closed rail clicks nothing.
 *
 * @param {import('playwright').Page} page
 * @param {object} [opts]
 * @param {string} [opts.askInput=ASK_INPUT_SELECTOR]
 * @param {string} [opts.minimize='button.js-minimize']
 * @param {number} [opts.maxRounds=3]
 * @returns {Promise<{rounds: number, wasOpen: boolean, askRect: object|null}>}
 */
export async function closeAi(page, opts = {}) {
  const { askInput = ASK_INPUT_SELECTOR, minimize = 'button.js-minimize', maxRounds = 3 } = opts;

  const measure = () =>
    page.evaluate((sel) => {
      const el = document.querySelector(sel);
      if (!el) return { present: false, open: false, rect: null };
      const r = el.getBoundingClientRect();
      return {
        present: true,
        // POSITION, not presence. Presence is true whether the rail is open or closed.
        open: r.width > 0 && r.x < window.innerWidth - 20,
        rect: { x: r.x, y: r.y, width: r.width, height: r.height },
      };
    }, askInput);

  let state = await measure();
  const wasOpen = state.open;
  let rounds = 0;
  while (state.open && rounds < maxRounds) {
    // Exactly ONE selector per round. Clicking a second candidate in the same round is
    // how the rail gets toggled back open and the shell ends up translated.
    const clicked = await page.evaluate((sel) => {
      const btn = document.querySelector(sel);
      if (!btn) return false;
      btn.click();
      return true;
    }, minimize);
    rounds += 1;
    if (!clicked) break;
    await page.waitForTimeout(250);
    state = await measure();
  }
  if (state.open) {
    throw new Error(`closeAi: the AI rail is still open after ${rounds} round(s) (ask input at x=${state.rect && state.rect.x})`);
  }
  return { rounds, wasOpen, askRect: state.rect };
}

/**
 * Assert the shell is not translated before taking a screenshot or reading a layout.
 *
 * WHY (#409): a double-closed AI rail translates the shell by the rail width. Run this
 * before EVERY shot: `.tree-nav` sits at x=192 when correct and at -163 when the shell
 * has been translated by the 355px rail.
 *
 * @param {import('playwright').Page} page
 * @param {object} [opts]
 * @param {string} [opts.selector='.tree-nav']
 * @param {number} [opts.expectedX=ADMIN_TREE_NAV_X]
 * @returns {Promise<number>} the measured x
 * @throws when the tree is absent or translated.
 */
export async function assertTreeNav(page, opts = {}) {
  const { selector = '.tree-nav', expectedX = ADMIN_TREE_NAV_X } = opts;
  const x = await page.evaluate((sel) => {
    const el = document.querySelector(sel);
    return el ? el.getBoundingClientRect().x : null;
  }, selector);
  if (x === null) throw new Error(`assertTreeNav: '${selector}' is not in the DOM: the shell did not finish rendering`);
  if (x !== expectedX) {
    throw new Error(
      `assertTreeNav: '${selector}' is at x=${x}, expected ${expectedX}. The shell is translated (a double-closed AI rail shifts it by the 355px rail width), so the tree pane is off-canvas and the content column is clipped behind the app rail. Do not shoot this frame.`
    );
  }
  return x;
}

/**
 * Reach a product's edit screen by CLICKING THE TREE, never by constructing a deep link.
 *
 * WHY (#390): the Products screens resolve their navigation node path from the tree
 * state. Entered cold, /Admin/UI/Products/DynamicStructureLevelResultsList?StructureId=...
 * and QueryListScreen?Type=FavoriteQueries have no DynamicStructureNavigationNodePath and
 * no screenTypeName: the grid comes back with zero rows and "An unhandled error
 * occurred". The URL the UI itself builds carries a per-screen GUID segment plus a
 * 5-segment node path, which cannot be reconstructed from outside.
 * A cold GET of the workspace route yields 0 table rows; the SAME workspace reached by
 * clicking the left-nav item yields 4 nodes and clicking through lands on
 * /Admin/UI/Products/ProductEdit/<screenGuid>?Id=PROD397&QueryId=...&Screen.PresetId=2.
 *
 * So this function walks `navPath` through the left tree, then opens the product, then
 * asserts the resulting URL carries BOTH Screen.PresetId and a QueryId before anything
 * reads the grid.
 *
 * @param {import('playwright').Page} page
 * @param {object} opts
 * @param {string[]} opts.navPath Left-nav item texts to click in order, e.g.
 *   ['PIM', 'Product structures', 'Northwind Master Catalog'].
 * @param {string} opts.productText The product row/link text to open.
 * @param {number} [opts.timeoutMs=20000]
 * @returns {Promise<{url: string}>}
 * @throws when the resulting URL is not a tree-resolved ProductEdit.
 */
export async function openProductEdit(page, opts) {
  const { navPath, productText, timeoutMs = 20000 } = opts || {};
  if (!Array.isArray(navPath) || navPath.length === 0) {
    throw new Error('openProductEdit: opts.navPath is required. A constructed deep link 500s or renders an empty grid');
  }
  for (const item of navPath) {
    await evaluateClick(page, item, {});
    await page.waitForLoadState('networkidle', { timeout: timeoutMs }).catch(() => {});
  }
  await clickByText(page, productText, { expectUrl: /\/Admin\/UI\/Products\/ProductEdit\//i, timeoutMs });

  const url = page.url();
  const missing = [];
  if (!/Screen\.PresetId=/i.test(url)) missing.push('Screen.PresetId');
  if (!/QueryId=/i.test(url)) missing.push('QueryId');
  if (missing.length) {
    throw new Error(
      `openProductEdit: landed on ${url} without ${missing.join(' and ')}. The screen resolved no navigation node path, so its grid will read empty. Reach it through the tree, not a constructed route.`
    );
  }
  return { url };
}

/**
 * Write one cell on the Products grid-edit screen, addressed BY TD INDEX, with a
 * read-back/abort guard.
 *
 * WHY (#457): this is a live data-loss hazard. The grid renders values into `<input>`
 * elements as DOM PROPERTIES, never serialised into markup, so `td.innerText` and
 * `td.outerHTML` are both EMPTY and any content-based cell locator resolves to nothing.
 * Deriving the column index from `<thead>` is also wrong: the header row carries extra
 * selection/filter cells and is not index-aligned with a body row. Driving it that way
 * typed stock figures into the Number and Name columns of two products and SAVED them:
 * PROD391 became Number "96" / Name "120", PROD392 became Number "150" / Name "84".
 * Nothing errored; the grid saved what it was given.
 *
 * Measured body-row shape on ProductGridEdit: td[0]=<td class="changed">, td[1]=flag img,
 * td[2]=<span>PROD391</span>, td[3]=<span></span>, td[4]=input Number, td[5]=input Name,
 * td[6]=input Price, td[7]=input Stock. Skip rows with no inputs: the grid renders a
 * leading and a trailing spacer row.
 *
 * The guard: read `tds[numberTdIndex] input.value` FIRST to identify the row, snapshot
 * every protected cell, write, then re-read and ABORT unless every protected cell is
 * byte-identical. The caller should additionally assert the on-screen "Changed N"
 * counter equals the number of rows it intended before pressing Save.
 *
 * @param {import('playwright').Page} page
 * @param {object} opts
 * @param {string} opts.rowKey The product Number that identifies the row (read from the
 *   Number input's value, not from any text node).
 * @param {number} opts.tdIndex The td index of the cell to write (Stock = 7 on
 *   ProductGridEdit).
 * @param {string} opts.value The value to type.
 * @param {number} [opts.numberTdIndex=4] td index of the Number column (the row key).
 * @param {number[]} [opts.protectedTdIndexes=[4,5,6]] td indexes that must NOT change
 *   (Number, Name, Price).
 * @param {string} [opts.rowSelector='tbody tr']
 * @returns {Promise<{rowKey: string, before: string[], after: string[], written: string}>}
 * @throws when the row is not found, or any protected cell changed.
 */
export async function gridEditCell(page, opts) {
  const {
    rowKey,
    tdIndex,
    value,
    numberTdIndex = 4,
    protectedTdIndexes = [4, 5, 6],
    rowSelector = 'tbody tr',
  } = opts || {};
  if (!rowKey || tdIndex === undefined || value === undefined) {
    throw new Error('gridEditCell: opts.rowKey, opts.tdIndex and opts.value are required');
  }
  if (protectedTdIndexes.includes(tdIndex)) {
    throw new Error(`gridEditCell: tdIndex ${tdIndex} is in protectedTdIndexes: refusing to write a column the guard is supposed to protect`);
  }

  const result = await page.evaluate(
    ({ rowKey, tdIndex, value, numberTdIndex, protectedTdIndexes, rowSelector }) => {
      const readCell = (tds, i) => {
        const td = tds[i];
        if (!td) return null;
        const input = td.querySelector('input');
        // The value lives on the DOM property. innerText is empty for these cells.
        return input ? input.value : td.innerText;
      };
      const rows = [...document.querySelectorAll(rowSelector)].filter((tr) => tr.querySelector('input'));
      const row = rows.find((tr) => {
        const tds = tr.querySelectorAll('td');
        return readCell(tds, numberTdIndex) === rowKey;
      });
      if (!row) return { ok: false, reason: 'row-not-found', rows: rows.length };

      const tds = row.querySelectorAll('td');
      const before = protectedTdIndexes.map((i) => readCell(tds, i));

      const target = tds[tdIndex] && tds[tdIndex].querySelector('input');
      if (!target) return { ok: false, reason: 'no-input-at-tdindex', tdIndex };
      target.focus();
      target.value = value;
      target.dispatchEvent(new Event('input', { bubbles: true }));
      target.dispatchEvent(new Event('change', { bubbles: true }));
      target.blur();

      const after = protectedTdIndexes.map((i) => readCell(tds, i));
      const written = readCell(tds, tdIndex);
      return { ok: true, before, after, written, rows: rows.length };
    },
    { rowKey, tdIndex, value, numberTdIndex, protectedTdIndexes, rowSelector }
  );

  if (!result.ok) {
    if (result.reason === 'row-not-found') {
      throw new Error(
        `gridEditCell: no row whose td[${numberTdIndex}] input value is '${rowKey}' among ${result.rows} input-bearing row(s). ` +
          `Cell values are DOM properties, so a text-based locator finds nothing here.`
      );
    }
    throw new Error(`gridEditCell: td[${result.tdIndex}] on row '${rowKey}' holds no <input>`);
  }

  const changed = result.before.some((v, i) => v !== result.after[i]);
  if (changed) {
    throw new Error(
      `gridEditCell: ABORT. Writing td[${tdIndex}] on row '${rowKey}' also changed a protected column. ` +
        `before=[${result.before.join(' | ')}] after=[${result.after.join(' | ')}]. Do not save; the grid saves whatever it is given.`
    );
  }
  if (`${result.written}` !== `${value}`) {
    throw new Error(`gridEditCell: td[${tdIndex}] on row '${rowKey}' read back '${result.written}' after writing '${value}'`);
  }
  return { rowKey, before: result.before, after: result.after, written: result.written };
}

/**
 * Read the grid's own "Changed N" counter. Assert it equals the number of rows you
 * intended BEFORE pressing "Save and close" (#457): it is a reliable pre-save check.
 *
 * @param {import('playwright').Page} page
 * @param {object} [opts]
 * @param {RegExp} [opts.pattern=/Changed\s+(\d+)/i]
 * @returns {Promise<number|null>} the counter, or null when the shell does not show one.
 */
export async function readChangedCount(page, opts = {}) {
  const source = (opts.pattern || /Changed\s+(\d+)/i).source;
  const flags = (opts.pattern || /Changed\s+(\d+)/i).flags;
  return page.evaluate(
    ({ source, flags }) => {
      const m = document.body.innerText.match(new RegExp(source, flags));
      return m ? Number(m[1]) : null;
    },
    { source, flags }
  );
}

/* ---------------------------------------------------------------------------
 * CLI. Everything below is the runner; the guards above are the contract.
 * ------------------------------------------------------------------------ */

/**
 * Read a `--name value` flag from argv. No defaults for anything that identifies a
 * host, a credential or a path: an omitted flag falls back to the environment or to
 * an explicit error, never to a baked-in value.
 * @param {string} name
 * @param {string|null} [def]
 * @returns {string|null}
 */
export function arg(name, def = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}

/** True when argv carries `--name`. @param {string} name @returns {boolean} */
export function flag(name) {
  return process.argv.includes(`--${name}`);
}

/**
 * Mask a secret for logging: length only, never a prefix (a prefix of an admin
 * credential is still a credential).
 * @param {string|undefined} value
 * @returns {string}
 */
export function maskSecret(value) {
  return value ? `<set, ${String(value).length} chars>` : '<unset>';
}

/**
 * Decide whether TLS validation may be skipped for a base URL. Localhost only,
 * unless the caller opts in explicitly. An unconditional bypass on every call is a
 * scored behaviour and is refused here.
 * @param {string} baseUrl
 * @param {boolean} allowSelfSigned
 * @returns {boolean}
 */
export function tlsBypassAllowed(baseUrl, allowSelfSigned) {
  if (allowSelfSigned) return true;
  try {
    const host = new URL(baseUrl).hostname.toLowerCase();
    return host === 'localhost' || host === '127.0.0.1' || host === '[::1]';
  } catch {
    return false;
  }
}

/**
 * Sign in to the admin when the landing page is the login form. Credentials come
 * from the environment only; the value is never written to stdout or into an error.
 * A `--storage-state` session skips this path entirely.
 * @param {import('playwright').Page} page
 * @returns {Promise<{signedIn: boolean, how: string}>}
 */
export async function signInIfAsked(page) {
  const userSelector = 'input[name="username" i], input[id*="username" i]';
  const secretSelector = 'input[type="password"]';
  const needsLogin = await page.locator(secretSelector).first().isVisible().catch(() => false);
  if (!needsLogin) return { signedIn: true, how: 'already-authenticated' };

  const user = process.env.DW_ADMIN_USER;
  const secret = process.env.DW_ADMIN_PASSWORD;
  if (!user || !secret) {
    throw new Error(
      `the admin login form is showing and no credential is in the environment ` +
        `(DW_ADMIN_USER=${user ? '<set>' : '<unset>'}, DW_ADMIN_PASSWORD=${maskSecret(secret)}). ` +
        `Set both, or pass --storage-state <file> with a session saved by a signed-in run.`
    );
  }
  await page.locator(userSelector).first().fill(user);
  await page.locator(secretSelector).first().fill(secret);
  await page.locator('button[type="submit"], input[type="submit"]').first().click();
  await page.waitForLoadState('domcontentloaded', { timeout: 30000 }).catch(() => {});
  const stillLogin = await page.locator(secretSelector).first().isVisible().catch(() => false);
  if (stillLogin) {
    throw new Error(`sign-in did not take: the credential field is still on screen at ${page.url()} (nothing echoed)`);
  }
  return { signedIn: true, how: `env credential for '${user}'` };
}

/**
 * Open a browser on the admin shell and sign in if asked. Returns the live objects.
 * @param {object} opts
 * @returns {Promise<object>}
 */
export async function openAdmin(opts) {
  const { chromium } = await import('playwright');
  const { baseUrl, path = '/Admin', width, height, storageState, allowSelfSigned, headed, timeoutMs } = opts;
  const bypass = tlsBypassAllowed(baseUrl, allowSelfSigned);
  const browser = await chromium.launch({ headless: !headed, args: bypass ? ['--ignore-certificate-errors'] : [] });
  const context = await browser.newContext({
    ignoreHTTPSErrors: bypass,
    viewport: { width, height },
    ...(storageState ? { storageState } : {}),
  });
  const page = await context.newPage();
  await page.goto(`${baseUrl}${path}`, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
  const auth = await signInIfAsked(page);
  return { browser, context, page, auth, tlsBypass: bypass };
}

async function main() {
  const action = process.argv[2];
  const actions = ['tree-nav', 'close-ai', 'click', 'open-product', 'changed-count'];
  if (!action || !actions.includes(action)) {
    console.error(`admin-shell-driver: first argument must be one of ${actions.join(', ')}. See the header for the flags.`);
    process.exit(1);
  }
  const baseUrl = arg('base') || process.env.DW_BASE_URL;
  if (!baseUrl) {
    console.error('admin-shell-driver: no base URL. Pass --base <url> or set DW_BASE_URL. There is no default host.');
    process.exit(1);
  }
  const timeoutMs = Number(arg('timeout', '30000'));
  const adminPath = arg('path', '/Admin');
  const opened = await openAdmin({
    baseUrl,
    path: adminPath,
    width: Number(arg('width', '1440')),
    height: Number(arg('height', '1000')),
    storageState: arg('storage-state'),
    allowSelfSigned: flag('allow-self-signed'),
    headed: flag('headed'),
    timeoutMs,
  });
  const { browser, context, page } = opened;
  const out = {
    action, target: `${baseUrl}${adminPath}`, tlsBypass: opened.tlsBypass,
    auth: opened.auth.how, status: 'FAIL', result: null,
  };
  try {
    out.aiRail = await closeAi(page);
    if (action === 'tree-nav') {
      out.result = { treeNavX: await assertTreeNav(page) };
    } else if (action === 'close-ai') {
      out.result = out.aiRail;
    } else if (action === 'click') {
      const text = arg('text');
      const expectUrl = arg('expect-url');
      if (!text || !expectUrl) throw new Error('click needs --text and --expect-url (an unasserted click proves nothing)');
      out.result = await clickByText(page, text, { expectUrl, scope: arg('scope'), timeoutMs });
    } else if (action === 'open-product') {
      const navPath = (arg('nav') || '').split('|').map((s) => s.trim()).filter(Boolean);
      const productText = arg('product');
      if (!navPath.length || !productText) throw new Error('open-product needs --nav "A|B|C" and --product <text>');
      await assertTreeNav(page);
      out.result = await openProductEdit(page, { navPath, productText, timeoutMs });
    } else if (action === 'changed-count') {
      out.result = { changed: await readChangedCount(page) };
    }
    const saveState = arg('save-state');
    if (saveState) {
      await context.storageState({ path: saveState });
      out.storageStateSaved = saveState;
    }
    out.status = 'PASS';
    console.log(JSON.stringify(out, null, 2));
    process.exitCode = 0;
  } catch (err) {
    out.detail = err.message;
    console.log(JSON.stringify(out, null, 2));
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
}

// Run only when invoked directly; an import gets the guards and nothing else.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
