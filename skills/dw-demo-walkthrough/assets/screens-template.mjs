// Screens spec for one screenshot walkthrough. Copy to <demo>/notes/walkthrough/<brand-slug>-screens.mjs, fill in,
// and run:  node <brand-slug>-screens.mjs <outDir> [scene ...]
// The engine sits in the skill: set RESKIN_ENGINE to the absolute path of scripts/reskin-engine.mjs.
// Environment: DW_BASE_URL (the SOURCE demo site), DW_FRONTEND_USER / DW_FRONTEND_PASSWORD (its demo buyer),
// RESKIN_LOGO (a png or jpeg the customer supplied or published), optional DW_PLAYWRIGHT_DIR, DW_BROWSER_CHANNEL.
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

const need = (n) => { const v = process.env[n]; if (!v) { console.error(`${n} is not set`); process.exit(1); } return v; };
const { open, goto, shoot, card } = await import(pathToFileURL(need('RESKIN_ENGINE')).href);
const BASE = need('DW_BASE_URL').replace(/\/$/, '');
const out = process.argv[2]; const only = process.argv.slice(3); const want = (s) => !only.length || only.includes(s);
if (!out) { console.error('usage: <brand-slug>-screens.mjs <outDir> [scene ...]'); process.exit(1); }
const logoFile = need('RESKIN_LOGO');
const LOGO = `data:image/${logoFile.endsWith('.png') ? 'png' : 'jpeg'};base64,` + fs.readFileSync(logoFile).toString('base64');

// ---- fill in -------------------------------------------------------------------------------------------------
const LABEL = 'Illustrative concept · sample data';            // stays on every still, clean copies included
const PRIMARY = '#000000';                                      // the customer's button colour
const SIGN_IN = '/sign-in';                                     // the source site's storefront sign-in page
const PRESENTER_LOGO_SVG = '';                                  // inline svg of the presenting company, for the cards
const PERSONA = [['<stock persona name>', '<sample persona name>'], ['<stock company>', '<sample company>']];
const NAV = [                                                   // [label shown, label of the STOCK item whose icon is reused]
  ['Overview', 'Overview'], { header: 'Your account' }, ['Invoices', 'Invoices'], ['Account history', 'My orders'],
];
// ---------------------------------------------------------------------------------------------------------------

const { browser, page } = await open({
  base: BASE,
  signIn: async (p) => {
    await p.goto(BASE + SIGN_IN, { waitUntil: 'domcontentloaded' });
    await p.fill('input[name="username"]', need('DW_FRONTEND_USER')); await p.fill('input[name="password"]', need('DW_FRONTEND_PASSWORD'));
    await Promise.all([p.waitForNavigation({ waitUntil: 'domcontentloaded' }).catch(() => null), p.locator('input[name="password"]').press('Enter')]);
  },
});

// Shared by every screen: colours, logo, the header parts the story does not use, the side navigation, the persona.
async function brand(active) {
  await page.evaluate(({ LOGO, NAV, PERSONA, PRIMARY, active }) => {
    const RS = window.RS;
    RS.css(`.btn-primary,[data-dw-button="primary"]{background:${PRIMARY}!important;border-color:${PRIMARY}!important}`);
    RS.remove(['header [data-dw-itemtype="swift-v2_navigation"]', 'header [data-dw-itemtype="swift-v2_minicart"]', 'header [data-dw-itemtype="swift-v2_favorites"]', 'header [data-dw-itemtype="swift-v2_searchfield"]']);
    RS.logo(LOGO, 200);
    RS.nav('main aside nav.list-group:first-of-type', NAV.map((n) => (n.header ? n : { label: n[0], from: n[1], active: n[0] === active })));
    RS.text(PERSONA);
  }, { LOGO, NAV, PERSONA, PRIMARY, active });
}

if (want('title')) await card(page, out, '00-title', { logoSvg: PRESENTER_LOGO_SVG, kicker: '<product> · concept for <customer>', title: '<what this concept is>', lines: ['<one sentence on the story>', 'An illustrative concept with sample data. The screens are real product screens, dressed for <customer>.'] });

// One block per screen: open the REAL page, brand it, change text and rows, shoot. Name the stills NN-<scene>.
if (want('invoices')) {
  await goto(page, BASE + '/customer-center/invoices'); await brand('Invoices');
  await page.evaluate(() => {
    const RS = window.RS;
    RS.rows('main table', [                                     // null keeps the stock cell (here: the actions menu)
      ['<a class="stretched-link text-decoration-none">INV-0001</a>', 'PO-0001', RS.badge('Open', '#b45309'), '1/1/2026', '<div class="text-price">$100.00</div>', '1/31/2026', null],
    ]);
  });
  await shoot(page, out, [{ name: '01-invoices', caption: { tag: 'Invoices', title: '1. Every invoice in one list', sub: '<one sentence, what the customer sees>' } }], LABEL);
}

if (want('end')) await card(page, out, '99-end', { logoSvg: PRESENTER_LOGO_SVG, kicker: '<product> · concept for <customer>', title: 'What this concept shows',
  rows: [['Standard today', '<what is stock>'], ['From the ERP', '<what a project connects>'], ['To be confirmed', '<what is a concept>'], ['Not in scope', '<what was left out>']] });

await browser.close();
