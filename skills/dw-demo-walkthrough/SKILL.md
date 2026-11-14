---
name: dw-demo-walkthrough
type: flow
group: demo
mcp: none
dynamo: false
compatibility: Requires Node.js 20+ with Playwright and a Chromium browser, and ffmpeg
description: 'Make a short captioned walkthrough video and screenshot overview for a prospect from real pages of an existing DW10 demo, re-skinned in the browser, without building a site. Triggers: screenshot walkthrough, concept for a first call, overview with screenshots, no demo budget. Use AFTER dw-demo-base.'
---

# Demo walkthrough from screenshots

A walkthrough for a prospect made from stills of **real pages of a demo that already runs**, dressed for the
prospect in the browser tab: logo, colours, navigation, a sample customer and sample rows. No site is built
and nothing is written to the source site. The output is a silent captioned video of two to four minutes,
the clean stills for an overview deck or document, and a grounding table that says what every screen rests on.

**Use AFTER [`dw-demo-base`](../dw-demo-base/SKILL.md)** for the folder conventions and the customer-context
contract. This skill has one mode today, screenshot mode. A recorded walkthrough of a built demo (scripted
clicks, screencast) is a different job and is not covered here.

## When this is the right tool

| Situation | Use |
|---|---|
| First conversation, the prospect asked for "something to pass around", no meeting with the owners yet | Screenshot walkthrough |
| A sales lead asks for a demo with minimal effort and the scope fits pages an existing demo already has | Screenshot walkthrough |
| The prospect wants to see it work, a live call is planned, or the story needs a click, a search or a checkout | Build the demo ([`dw-demo-base`](../dw-demo-base/SKILL.md)) |
| The story needs a page no running demo has | Build the demo. Do not draw the page |

Measured once: about an hour from brief to video, deck and ten stills, against half a day or more for a
narrow built demo. It proves nothing about the platform. It shows what the platform looks like.

## Rules

1. **Every screen starts from a real page.** Open the page on a running demo and change it. A screen with no
   real page behind it is not made. If the source demo lacks the page, pick another source or leave the screen
   out and say so.
2. **Nothing is written to the source site.** All changes are DOM changes in one headless tab. No form is
   submitted, no order placed, no setting saved. Sign in as an existing demo buyer.
3. **Every screen is checked against the functionality ledger** ([`dw-demo-ledger`](../dw-demo-ledger/SKILL.md))
   before it is shown. A screen may show a function whose ledger status is documented. A block that is
   project or template work is allowed only when it is named as such in the grounding table, and a block the
   platform cannot do is not made.
4. **The concept label is in the still.** "Illustrative concept · sample data" sits on every still, the clean
   copies included, so a cropped or forwarded image still carries it. A block that is a concept carries its
   own badge, and a button that would send, pay or save says in the page that it does not.
5. **The caption layer is the presenter's.** Captions and the opening and closing cards use the presenting
   company's brand, never the prospect's, so the viewer can tell the product from the commentary.
6. **Sample data is invented and consistent.** A made-up customer in the prospect's territory, numbers that
   add up across screens (the open balance is the sum of the open invoices), no real customer of the prospect,
   no real person. Run the copy through the wording glossary of
   [`demo-tactics.md`](../dw-demo-base/references/demo-tactics.md).
7. **Scope follows the prospect, by removal.** Take out what the prospect cannot adopt (navigation items,
   cart, search) instead of leaving it visible and unexplained.
8. **The closing card separates four things:** standard today, comes from the ERP in a project, still to be
   confirmed, not in scope.

## Screenshot mode, step by step

1. **Storyline.** Six to ten screens from the discovery notes, in the order the prospect's customer would
   meet them. One sentence per screen. Write the list down before opening a browser.
2. **Source.** Find a running demo that has those pages. Earlier walkthrough videos are the fastest index:
   make a contact sheet of each (one frame every ten seconds) and look for the pages. Record which site and
   which page each screen starts from.
3. **Capture raw.** Sign in as the demo buyer and take a full-page still of each source page first, unchanged.
   Read them. They show which parts can stay and which item types the page is made of
   (`data-dw-itemtype` on the grid columns).
4. **Re-skin and shoot.** Copy [`assets/screens-template.mjs`](assets/screens-template.mjs), fill in the brand
   block and one block per screen, and run it. The engine gives the page-side helpers:

   | Helper | Does |
   |---|---|
   | `RS.css(text)` | Adds a style sheet (button colour, top border, footer) |
   | `RS.remove([selectors])` | Removes header parts the story does not use |
   | `RS.logo(dataUri, width)` | Replaces every `swift-v2_logo` figure |
   | `RS.nav(selector, items)` | Rebuilds a list-group navigation from its own items, reusing stock icons |
   | `RS.text([[from, to]])` | Replaces text in text nodes, placeholders and titles; `/regex/flags` strings work |
   | `RS.rows(table, rows, headers)` | Replaces table rows by cloning the first stock row; `null` keeps a stock cell |
   | `RS.html(selector, html, how)` | Sets or inserts markup. Compose new blocks from classes the page already uses |
   | `RS.badge(label, colour)` | A status badge in the stock badge markup |

   ```
   node <demo>/notes/walkthrough/<brand-slug>-screens.mjs <demo>/notes/walkthrough/stills
   ```

   Each scene writes `NN-name.png` (captioned, for the video) and `NN-name.clean.png` (label only, for the
   deck). Look at every still. Fix and run the scene again by name.
5. **Video.** Run [`scripts/build-video.mjs`](scripts/build-video.mjs):

   ```
   node scripts/build-video.mjs --shots <demo>/notes/walkthrough/stills --out <demo>/deliverables/<brand-slug>-walkthrough.mp4
   ```

   Ten seconds per scene reads a two-line caption. Check a contact sheet of the result before sharing it.
6. **Overview.** Place the clean stills in the presenting company's deck template, two or three per slide
   with a one-line caption each, and end on the four-column slide of rule 8.
7. **Grounding table.** One row per screen: the real page it started from, the ledger function ids, what was
   changed in the browser, and what is not standard and how it is marked. It ships with the stills to the
   person who decides whether they are sent.
8. **Put the source back.** A site started for the capture is stopped again.

## A screen library tied to the ledger

A library is the same idea without a customer: every screen of one standing site, captured once per release and
tied to the function ledger, so a walkthrough can be put together from stock screens without starting a site.

1. **Pick the site the release is proven on.** The standing site of the estate, the one every edition is delivered
   to and gated on, carries the widest set of functions and moves with each release. A customer demo is the wrong
   source: its data and brand are someone's.
2. **Capture.** `node scripts/capture-library.mjs <base> <outDir> --storefront --admin --details` with the back
   office sign-in in `DW_USER` and `DW_PASS`. It follows links and opens tabs; it saves nothing. The assistant
   panel is closed first (`dw-admin-assistant-sidekick-collapsed`), or every back office still loses a third of
   its width.
3. **Tie.** [ledger-screen-map.json](assets/ledger-screen-map.json) holds rules `{match, ledger: [ids]}`: a regex
   over `surface|area|screen|path|title|url` of a screen and the function ids it shows. A rule names a screen type
   or a path, never one site's record. An id the release does not have is reported, not dropped in silence.
4. **Report coverage.** List per ledger area the functions with a screen and the ones without. A function with no
   screen of its own (an API, a scheduled job, a setting inside another screen) stays in the list as uncovered: a
   library that claims 100 percent has tied screens to functions they do not show.
5. **Refresh with the release.** A new ledger snapshot means a new capture from the same site after it is on the
   new version, the map checked against the snapshot's added and removed ids, and the coverage report redone.
   The step is in the ledger's release process (`dw-demo-ledger/references/release-process.md`).

What the capture does not reach: pages behind a storefront sign-in when no persona sign-in is passed, dialogs,
and anything that needs a write (a cart with lines, a checkout step).

## What goes wrong

- **The caption covers the content.** Bottom corners are where tables and totals are. On a Swift header with
  the navigation removed, the band between logo and account chip is empty: the engine puts the caption there.
- **A scrolled still loses its heading under the sticky header.** `shoot` scrolls to the selector minus the
  header height. Pass the selector of the block above the one you want when the heading is still cut.
- **Stock widgets load after the page.** The Swift dashboard widgets fill through htmx. `goto` waits for the
  network to go idle; change widget contents only after that, or the stock values come back.
- **Added blocks look finished.** A block composed from the page's own classes is indistinguishable from a
  stock one. That is the point and the risk: it must be in the grounding table, and a concept needs its badge.
- **The chart keeps the source's data.** Retitling a chart does not change its bars. Leave it out of the
  story or say in the grounding table that it is the source's chart.
- **A small logo.** A logo taken from a mail signature holds at header size only. Do not enlarge it on a card.
- **The phone view.** Swift picks the mobile header by device type, not by width. This mode shoots desktop only.

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [reskin-engine.mjs](scripts/reskin-engine.mjs) | READ-ONLY against the site; writes stills to the folder you pass | Library: open a signed-in tab, install the `RS` helpers, shoot captioned and clean stills, render title and closing cards |
| [build-video.mjs](scripts/build-video.mjs) | WRITES one mp4 and a `clips/` folder beside it | Joins the captioned stills into a silent video: stills held without motion, a fade at both ends |
| [capture-library.mjs](scripts/capture-library.mjs) | READ-ONLY against the site (GET links, tree nodes expanded, tabs clicked, nothing saved); writes `shots/` and `screens.json` to the folder you pass | Crawls the storefront and the back office of one site into a screen library: every navigation page, one or two detail pages per list, every back office list with its first row's detail screen and tabs |

Both are imported or run, not retyped. The engine needs `playwright-core` resolvable (`DW_PLAYWRIGHT_DIR`
or `npm install playwright-core` beside it) and takes the sign-in from the caller's environment.
