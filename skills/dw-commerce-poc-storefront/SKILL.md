---
name: dw-commerce-poc-storefront
type: flow
group: commerce
mcp: required
dynamo: false
compatibility: Needs a way to render pages and capture screenshots - a browser tool where the harness provides one, otherwise Node 18+ with Playwright and Chromium for the bundled capture script
description: 'Build a complete Dynamicweb 10 proof-of-concept storefront from a public source website — readiness preflight, catalogue crawl, PIM data model, product and media import, Swift 2 site assembly, and a critic-driven visual QA loop. Triggers: scrape a prospect or customer site and build it as a shop in Dynamicweb, build a POC/demo storefront from their website, "put all their products in a good data model in a new shop", turn a live webshop into a DW10 catalogue plus a Swift 2 site, rebuild their site improved rather than copied. Non-triggers: content pages with no catalogue -> dw-swift-migrate-content; a DW9 product export already in hand -> dw-pim-migrate-dw9; a faithful Swift 1 layout port -> dw-swift-migrate-v1; one page from a mockup -> dw-swift-page-design; Data Model design with no source site -> dw-pim-modelling.'
---

# POC storefront from a source website

## MCP preflight

This skill drives the Dynamicweb MCP server — every write in it is a tool call. Before
starting, verify the Dynamicweb MCP tools are available and answer against the solution you
intend to build in. When they are not, stop and tell the user the MCP connection is missing;
keep the direct SQL, file edits and guessed HTTP calls out of it, and let them reconnect.

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

The work splits into a readiness gate and five phases. Run the gate first, every time.

## Phase 0 — the readiness gate

Four things must be true before any crawling or modelling. Establish each one explicitly and
report what you found; when one fails, stop at that line and ask, rather than building on a
guess.

1. **A Dynamicweb 10 solution that is ready to be used.** Not merely reachable — able to host
   a storefront: a frontend that answers, a design with Swift 2 installed, a language and
   currency, and an index repository. `get_frontend_health`, `get_areas`, `get_layouts`,
   `get_languages`, `get_shops`, `get_index_repositories`.
2. **The MCP connection points at that same solution.** A connected server against a
   *different* install is the most expensive failure in this flow, because it surfaces
   hundreds of writes later. Prove the identity before writing.
3. **A source URL, reachable and in scope.** One canonical origin, confirmed by fetching it.
   Establish that the user is entitled to crawl it — a prospect's own public site for a POC
   they commissioned is the normal case, and worth stating out loud once.
4. **An agreed build scope.** Which product families, roughly how many products, which
   locale, whether prices are shown with or without VAT, and whether this is a new area and
   shop or an addition to an existing one.

[`references/preflight.md`](references/preflight.md) carries the checks, the exact calls, and
what "ready" means for each one.

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
| [preflight.md](references/preflight.md) | Before anything else — the four preconditions and their checks |
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

Two capabilities carry the crawl and the QA, and each has a preference order. Establish which
one you have at the gate rather than discovering it mid-round.

- **Rendered HTML** — for facet options, leftover demo strings, link targets and counts. Use the
  MCP server's `fetch_frontend_page_html` for the target solution; it needs no browser and it is
  the fastest check in the flow. Reach for a browser only when the page builds its content
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

Skip the script entirely when a browser tool is available - capture the same page set with it,
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
