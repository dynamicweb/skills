---
name: dw-commerce-poc-storefront
type: flow
group: commerce
mcp: required
dynamo: false
compatibility: Needs a way to render pages and capture screenshots - a browser tool where the harness provides one, otherwise Node 18+ with Playwright and Chromium for the bundled capture script
description: 'Build a complete Dynamicweb 10 proof-of-concept storefront from a public source website — catalogue crawl, PIM data model, product and media import, Swift 2 site assembly, and a critic-driven visual QA loop, run autonomously from one brief. Triggers: scrape a prospect or customer site and build it as a shop in Dynamicweb, build a POC/demo storefront from their website, "put all their products in a good data model in a new shop", turn a live webshop into a DW10 catalogue plus a Swift 2 site, rebuild their site improved rather than copied. Non-triggers: content pages with no catalogue -> dw-swift-migrate-content; a DW9 product export already in hand -> dw-pim-migrate-dw9; a faithful Swift 1 layout port -> dw-swift-migrate-v1; one page from a mockup -> dw-swift-page-design; Data Model design with no source site -> dw-pim-modelling.'
---

# POC storefront from a source website

## MCP preflight

This skill builds through the Dynamicweb MCP server: the data model, the catalogue and the
site are all tool calls. Verify the tools are available **at the step that first needs them —
the first write** — rather than before the first step. The crawl runs entirely against the
source site and needs nothing from the solution, so when the connection is not up yet, crawl
first and bring the server up before modelling.

When the tools are missing at that point, say so and wait for the connection rather than
substituting direct SQL, file edits or guessed HTTP calls. Nothing is lost by pausing there —
the crawl output is on disk and the import resumes from it.

Tool families vary per installation. This skill uses only the base catalogue, content and
index tools. When a server also ships the site-extraction add-in (`extract_site_content`,
`build_pages`, `import_site_media`, `apply_brand_color_scheme`, `setup_website_chrome`), the
content half of the build is faster through `dw-swift-migrate-content` — check with one call
before choosing the manual path.

## What this builds

A prospect or customer has a public webshop. The deliverable is their catalogue and their
story, rebuilt in Dynamicweb 10 as something **better than the source** — a real PIM data
model with filterable attributes, products with images and prices, and a Swift 2 storefront
that demos end to end. It is an argument for the platform, so it is judged the way a shopper
judges a shop: can I find, compare, understand and buy.

## Run it autonomously

The shape of this job is one brief in, a finished storefront out. Two facts have to come from
the user because nothing else can supply them — **which site to build from** and **which
solution to build into**. Everything else you determine yourself, state in a line as you go,
and proceed on.

That includes the decisions it is tempting to ask about: catalogue breadth, locale and
currency, whether prices show with or without VAT, new area and shop versus an existing one,
naming, which attributes become facets, how the pages are arranged, and what the copy says.
Each is answerable from the source site and the solution, each is visible in the result, and
each is cheap to change afterwards. A POC stalls on questions.

Stop and ask only where continuing would be unsafe or wasted:

- no solution you can reach, or none with a Swift 2 design to build on,
- the connected MCP server cannot be shown to be the solution the user means,
- the source origin does not resolve, or its catalogue sits behind a login you were not given,
- the request is to crawl a site the user has no relationship with.

Report determinations as you make them — a line each, in passing — so the user can correct one
without being asked to approve all of them.

## Ground truth, and when each piece is due

Establish these in two groups, at the point each is actually needed.

**Before crawling** — nothing here touches the solution:

1. **The source origin.** One canonical host, confirmed by fetching it: `example.com`,
   `www.example.com` and a regional subdomain often serve different catalogues and prices.
   Probe `/dwapi/` while you are there — a delivery API turns the crawl from parsing into
   paging.
2. **Scope, read off the source.** Which families exist, roughly how many products, which
   locale the demo should show, and whether the source quotes prices with or without VAT.

**Before the first write** — now the solution matters:

3. **A solution able to host a storefront.** Not merely reachable: a frontend that answers, a
   Swift 2 design that is actually the area's design, a language and a currency, a shop, and an
   index repository whose real name you record. `get_frontend_health`, `get_areas`,
   `get_layouts`, `get_languages`, `get_shops`, `get_index_repositories`.
4. **Proof the MCP server is that solution.** A server connected to a *different* install
   answers every call happily, and the mistake surfaces hundreds of writes later. Match the
   public site against `get_areas` before writing.

[`references/preflight.md`](references/preflight.md) carries the checks, what "ready" means for
each, and how to derive the scope decisions instead of asking for them.

## The five phases

1. **Crawl** the source into local files — product records, attributes, images, prices,
   category tree, and the editorial content worth keeping.
   → [`references/crawl.md`](references/crawl.md)
2. **Model and import** — derive the data model from the attributes the crawl actually found,
   create the shop and groups, then import products, prices, images and relations.
   → [`references/catalogue.md`](references/catalogue.md)
3. **Assemble the storefront** — area, Swift 2 pages, navigation, product list and detail,
   facets, and the editorial pages.
   → [`references/storefront.md`](references/storefront.md)
4. **QA in rounds** with critic subagents reading real screenshots, fixing what they find, and
   re-capturing. → [`references/visual-qa.md`](references/visual-qa.md)
5. **Hand over** — the live URL, what was built, and an honest list of what a person still has
   to finish in the CMS. The handover section of `visual-qa.md` owns the format.

Phases 2 and 3 overlap in practice: build the catalogue far enough to have something to render,
assemble the storefront, then enrich against what the pages reveal. QA is not a final step
either — run a round as soon as a page renders, because a structural mistake found at round 1
costs a paragraph and at round 3 costs a rebuild.

## Reference map

| Reference | Read it when |
|---|---|
| [preflight.md](references/preflight.md) | Establishing ground truth — before the crawl, and again before the first write |
| [crawl.md](references/crawl.md) | Extracting the source: delivery API first, HTML crawl as fallback |
| [catalogue.md](references/catalogue.md) | Data model, field types, product/price/image import, the index |
| [storefront.md](references/storefront.md) | Swift 2 assembly, and the traps that silently do nothing |
| [visual-qa.md](references/visual-qa.md) | Capture, critic subagents, the fix loop, the handover document |

Sibling skills own the depth this flow only touches: [dw-pim-modelling](../dw-pim-modelling)
for Data Models and field storage, [dw-commerce-catalog](../dw-commerce-catalog) for catalogue
rendering and assortments, [dw-swift-page-blocks](../dw-swift-page-blocks) for the Swift 2
component vocabulary, [dw-swift-page-design](../dw-swift-page-design) for composing a page well,
and [dw-search-indexing](../dw-search-indexing) for indexes and queries.

## How this flow reaches a browser

Two capabilities carry the crawl and the QA, and each has a preference order.

- **Rendered HTML** — for facet options, leftover demo strings, link targets and counts. Use the
  MCP server's `fetch_frontend_page_html` for the target solution; it needs no browser and it is
  the fastest check in the flow. Reach for a browser only when a page builds its content
  client-side.
- **Screenshots** — for anything judged by eye. Use the harness's own browser tool when it has
  one. When it has none, `scripts/capture-pages.mjs` drives a headless Chromium instead.

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [capture-pages.mjs](scripts/capture-pages.mjs) | READ-ONLY on the solution; writes PNG/JPEG files locally | Fallback for harnesses with no browser tool: full-page screenshots at desktop and mobile widths, cookie banners dismissed, lazy-loaded imagery forced to resolve, each page sliced into review-sized JPEGs with a manifest |

```bash
node scripts/capture-pages.mjs --base-url https://<solution-host> --out shots/round1 \
  --paths /en-gb/home /en-gb/shop /en-gb/shop/<category> /en-gb/shop/<category>/<product>
```

Skip the script entirely when a browser tool is available — capture the same page set with it,
at the same two widths, and feed those images to the critics.

## Where the quality is won

Five decisions separate a POC that wins the room from one that looks like an import.

- **Field type decides whether a facet works.** A text-typed category field is analysed by the
  index, so "Made to order" becomes the two useless facet options `made` and `order`. Every
  field that drives a filter is a list field. `catalogue.md` has the rule and its siblings.
- **Teasers do the selling.** The source's own card text is usually one generic sentence
  repeated across a family. Generate a teaser per product from its real attributes so two
  neighbouring cards are visibly different products.
- **Claims must survive a click.** Copy that says "every model lists its comfort system" is
  checked by the first person who opens a product without one. Measure the fill rate of a field
  before writing a sentence that depends on it, and hedge to what the data supports.
- **Improve, do not transcribe.** The brief is a better shop, so fix what the source does
  badly: missing filters, category names buried under the product list, unreadable spec dumps,
  no route from a product to the material or textile it is offered in.
- **Say what is unfinished.** Every POC leaves gaps — source data that contradicts itself,
  settings the tool surface cannot write, template-level work out of scope. A short, honest
  limitations document is worth more in the meeting than a silent gap someone else finds.

## Non-goals

Leave these to their owners: content-only rebuilds with no catalogue
([dw-swift-migrate-content](../dw-swift-migrate-content)); a DW9 export already in hand
([dw-pim-migrate-dw9](../dw-pim-migrate-dw9)); layout-faithful Swift 1 ports
([dw-swift-migrate-v1](../dw-swift-migrate-v1)); checkout, payment and shipping configuration
([dw-commerce-orders](../dw-commerce-orders)); and editing the shipped Swift Razor templates,
which are shared with every other site on the instance — a POC stays configuration-only, and
anything that needs a template change belongs in the limitations document.
