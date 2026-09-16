# Crawling the source site

The crawl decides the ceiling of the whole build: attributes you fail to capture cannot be
modelled, filtered or written about later. Capture more than you think you need, into local
files, and model from the files rather than from the live site.

## Contents

- [Delivery API first](#delivery-api-first)
- [HTML crawl as the fallback](#html-crawl-as-the-fallback)
- [Browser driving that survives real sites](#browser-driving-that-survives-real-sites)
- [What to capture per product](#what-to-capture-per-product)
- [Images](#images)
- [Editorial content](#editorial-content)
- [Write it to disk, in one shape](#write-it-to-disk-in-one-shape)
- [Politeness and rate](#politeness-and-rate)

## Delivery API first

Before writing a single selector, probe for a structured feed. A Dynamicweb 9 or 10 source
exposes the delivery API at `/dwapi/`; other platforms expose their own JSON or a sitemap of
product URLs. One request tells you which world you are in:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://<source>/dwapi/
```

A delivery API gives typed fields, the category tree, prices and stock without parsing, and it
pages deterministically. Prefer it for everything it covers and fall back to HTML only for what
it omits. The endpoints and their shapes are owned by
[dw-headless-delivery](../../dw-headless-delivery).

Two habits pay for themselves on any paged source: page until the reported total is reached
rather than until a page looks short, and record the total alongside the records so a later
reader can tell a partial crawl from a complete one.

## HTML crawl as the fallback

Work in three passes, saving after each, so a failure in pass three does not cost passes one
and two.

1. **Discover** product URLs — from the sitemap when one exists, otherwise by walking the
   category listings and their pagination. Deduplicate by canonical URL.
2. **Fetch** each product page once, saving the raw HTML.
3. **Parse** the saved HTML into records. Parsing from files means a selector mistake costs a
   re-parse rather than a re-crawl.

Parse from the page's own structured data before its markup: `application/ld+json` Product
blocks, Open Graph tags and microdata carry name, SKU, price, availability and images in a
stable shape, while the markup around them changes between templates. Treat a spec table as the
attribute source and the marketing copy as prose to rewrite, not to import.

## Browser driving that survives real sites

Most of a crawl needs no browser at all: a server-rendered source yields to plain HTTP, and
structured data in the markup carries the fields. Reach for a browser only when the listing or
the specs are built client-side — and then use whatever the harness already gives you (a browser
tool, if it has one) before installing a driver. A headless driver such as Playwright is the
fallback for a harness with neither.

Whichever you use, the traps that cost the most time are the same four:

- **A cookie or region interstitial** intercepts every click and blocks the first paint.
  Dismiss it before doing anything else, matching several button labels, and continue when none
  of them is present.
- **Lazy-loaded imagery** never resolves in a headless page that does not scroll. Step down the
  page in small increments with a dwell at each stop, then return to the top.
- **Images still decoding** when the screenshot fires produce grey boxes. Wait until every
  `document.images` entry reports `complete` with a non-zero `naturalWidth`, with a timeout.
- **A proxied or self-signed environment** needs its proxy passed to the browser explicitly;
  browsers do not inherit `HTTPS_PROXY` the way `curl` does.

`scripts/capture-pages.mjs` encodes all four for the QA capture, and the same three helpers —
banner dismissal, lazy-load pass, image-decode wait — belong in whatever you drive the crawl
with.

## What to capture per product

The temptation is to capture what the current page design shows. Capture instead what a
*filter* would want, because that is what the POC is judged on.

| Group | Examples | Why it matters |
|---|---|---|
| Identity | name, SKU, canonical URL, category path | Keys, URLs and the group tree |
| Commercial | price, currency, availability, lead time, warranty, origin | The buy box and the honest claims |
| Dimensions | every numeric measurement, with its unit | Size filters and the spec panel |
| Classification | type, family, collection, style, room, key features | Almost every facet worth having |
| Materials | frame, surface, filling, finish, and any option list | Cross-sell and material filters |
| Media | every image URL in order, plus its role | Primary image choice |
| Prose | short and long description, as written | The rewrite baseline, not the final copy |

Two rules save a re-crawl:

- **Keep units and raw values separate from formatted strings.** `"85 000 cycles"` is a label;
  `85000` is a filter. Capture both when the source shows only the formatted one.
- **Keep every attribute you do not understand.** An attribute whose meaning is unclear at crawl
  time is frequently the one that turns into the most interesting facet after you see the
  distribution across the catalogue.

## Images

Collect the image URLs during the crawl and import them into the solution as a separate step —
`import_product_images_from_urls` pulls them server-side, which is dramatically cheaper than
routing bytes through the conversation.

Order matters: the first image on a product page is not reliably the best primary image, and a
source frequently leads with a detail crop. After import, review the primary images as a grid
and repoint the ones that do not show the product; this is a small fix that visibly changes the
listing page.

## Editorial content

Capture the pages that make the demo a shop rather than a table: the about page, delivery and
returns, FAQ, care or sizing guides, and any category introduction. Take them as text, and plan
to rewrite rather than paste — the source's copy carries its own site's assumptions, and the
POC's claims have to match the data actually imported.

Record the brand essentials while you are there: logo, colours, and the handful of facts the
copy will lean on (founding year, product counts, warranty terms, lead times). Write them into
one short brand-facts file, and let every later copy step assert only what is in it. That file
is what stops a generated sentence from inventing a claim.

## Write it to disk, in one shape

One record shape, one file per phase, in the scratch directory:

```
crawl/urls.json        discovered product URLs
crawl/raw/<sku>.html   fetched pages, unparsed
crawl/products.json    parsed records, one object per product
crawl/images.json      product number -> ordered image URLs
crawl/content/*.md     editorial pages as text
crawl/brand.md         the facts copy is allowed to assert
```

Everything downstream reads `products.json`. Keeping it the single source means the data model,
the import, the teasers and the QA all agree by construction, and a re-run of any later phase
is cheap.

## Politeness and rate

Sequential requests with a short delay, one connection, and a descriptive user agent. A
few hundred product pages at a human-ish rate finishes inside an hour and leaves no mark; a
parallel flood gets the crawl blocked halfway and loses the pages already fetched. Cache
aggressively — never fetch a URL twice in one build.
