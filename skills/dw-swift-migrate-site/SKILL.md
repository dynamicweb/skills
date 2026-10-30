---
name: dw-swift-migrate-site
type: flow
group: swift
mcp: required
dynamo: false
description: 'Migrate any existing website or webshop to a Truvio Commerce Swift 2 site: content, PIM catalog import, and a review loop. Triggers: migrate, convert, or replatform a site to Dynamicweb or Swift 2. Faithful Swift 1 layout port -> dw-swift-migrate-v1.'
---

# Site migration to Swift 2

The master flow for moving an existing website, on any platform, into Truvio Commerce (powered by
Dynamicweb) as a standard Swift 2 site: its content pages, and when in scope its product catalog
as a PIM data model with imported products. The result is an improved version of the source,
never a pixel copy. "Improved" means better structure, navigation, filtering, and mobile layout;
it never means rewritten text.

This skill is self-contained: everything a step needs is in this file and its `references/`.
This file is the overview; each step names the reference that holds its recipe.

## MCP preflight

The work runs through the Dynamicweb MCP server connected to the target solution. Before the
intake, list the server's tools and its websites to confirm it is the target solution. When no
Dynamicweb MCP server is connected, stop and ask the user to connect one: the migration cannot be
planned without reading the target. When a single operation has no MCP tool, use the Management
API next, then the serializer; raw SQL only as the last resort and only on a local install.

Besides MCP, the flow needs a working folder, a scripting runtime the agent can run (Node.js or
Python), and a way to take full-page screenshots. A catalog migration also needs the dw CLI with
an API key for bulk uploads ([catalog-import.md](references/catalog-import.md), "Uploading
files"). Check each one before the step that uses it.

## Intake: collect every input before any work

A migration starts only when every input below is known. Find each value first in the user's
messages and in `RUN-STATE.md` in the working folder. Then ask the user for **all** missing values
in one message, one short question per value, offering the suggested default where the table has
one. Never guess a URL, a website, or the scope.

| Input | What it is | Needed when | Suggested default |
|---|---|---|---|
| Source URL | The site to migrate | Always | — |
| Target solution | The Dynamicweb solution URL the connected MCP server belongs to | Always | The connected server's host, confirmed by the user |
| Target website | A new website in the solution, or which existing one | Always | A new website |
| Scope: what | Content pages, the product catalog, or both | Always | Both, when the source sells products |
| Scope: how much | The whole site, or a first subset of categories and pages proposed after the survey | Always | A subset first, then the rest |
| Website language | The language of the new website | Always | The source's main language |
| Currency and VAT | The currency, and whether prices include VAT | Catalog in scope | The source's currency and VAT display |
| Permission | Confirmation that the user may copy the source's content | Always | — (must be a yes) |
| Bulk upload | The dw CLI installed, and an API key for the target solution stored in a file the agent can read | Catalog in scope | — |
| Review rounds | The maximum number of critic rounds in step 7 | Always | 6 |

Never ask for the API key's value in the conversation; ask where the file that holds it is.

When the answers are in, restate every value in one short list and wait for the user's go-ahead.
Write the confirmed values into the `Inputs` section of `RUN-STATE.md`. That confirmation
authorizes the run up to the first checkpoint; it never replaces a checkpoint.

A request for one page or one designed layout is not a migration, and neither is a Swift 1 site
the user wants kept 1:1. Say so, and use a page-design or Swift 1 port skill when one is
installed.

## Run state

The working folder holds two Markdown files, so a stopped run continues in a new session:

- `RUN-STATE.md`, written by you after every step: the confirmed inputs, what is done, the ids and
  settings created (enough to delete them again), decisions, a `Next` section, and a tool defect
  list (what you called, what it returned, what actually happened)
- `PITFALLS.md`, maintained with the user: known tool and platform problems. Read it before each
  step and add every new problem you hit

At the start of a session, read `RUN-STATE.md` when it exists and continue from its `Next`
section; the intake only asks for what it does not already record.

## Rules for every step

- **Respect the source.** Read `robots.txt` first and keep its crawl delay (one request per second
  when it states none). When it blocks pages the migration needs, stop and ask.
- **Keep content verbatim.** Names, descriptions, and specifications stay as scraped, also when a
  tool description lists field writing rules. Cleaned values (spelling, units, decimal separators)
  go in separate facet fields; the displayed value stays as scraped. Never invent data.
- **Bulk data never passes through the conversation or subagents.** Scripts write files, the dw
  CLI uploads them, and Data Integration activities import them.
- **Read back every write.** A success response or a row count is not proof; for catalog data,
  the frontend is the proof.
- **Keep the new website out of search engines** (noindex) until the owner approves it.
- **Ask before anything that affects other users of the solution:** restarting the application,
  changing shared templates or indexes, binding a domain. Put custom templates and CSS in new files
  named after the source site. Collect these questions for the next checkpoint where you can.
- **Stop at every checkpoint**, show the result, and wait for the user's go-ahead.

## Flow

The scope decides which steps run: a content-only migration runs steps 1, 5, and 7; a catalog
migration runs all seven.

### Step 1: Survey

Read `robots.txt` and the sitemaps, find how listings and pages load their data, and note the
source platform, its languages, and its VAT display. When the scope is a subset, propose
categories and pages that cover every product shape and page type.
[catalog-import.md](references/catalog-import.md) ("Survey") has the detail.
**Checkpoint:** the proposed scope with product, variant, image, and page counts.

### Step 2: Scrape

Save listings, product pages, content pages, and images to resumable JSON Lines files in the
working folder, keeping the raw responses so parsing can rerun without crawling again.
[catalog-import.md](references/catalog-import.md) ("Scrape into files").
**Checkpoint:** record counts per file, five sample products, and any field empty in more than
10% of records.

### Step 3: Data model

Propose one data model per product category, a category field for every specification, variant
groups for the specifications that pick a variant, and one clean product group tree.
[catalog-import.md](references/catalog-import.md) ("Data model").
**Checkpoint:** the proposal and a table mapping each source specification to its field, before
anything is created.

### Step 4: Import

Create the data models and groups, then import manufacturers, variant groups and options,
products and variants, group relations, variant relations and field values, prices, and images
from CSV files with Data Integration. Let the platform generate product ids and read them back for
the later files. [catalog-import.md](references/catalog-import.md) ("Import order" through
"Proving an import").
**Checkpoint:** product, variant, price, and image counts in the solution, checked on the frontend
pages of products nobody has opened yet. When caches hide imported data, tell the user rather
than working around it.

### Step 5: Website

First propose the page tree, the color scheme and logo, and which standard Swift 2 component each
source section becomes. **Checkpoint:** the proposal. Then build: the website with its header and
footer, the shop page with the product catalog shell when the catalog is in scope, and the
content pages. Set the navigation tags Swift needs on the shop and service pages, point every
internal link at the new pages, and check the frontend health of every page.
[content-rebuild.md](references/content-rebuild.md).
**Checkpoint:** links to all pages.

### Step 6: Catalog experience

Facet on non-analyzed fields, show category facets only where they apply, set a default sort that
puts core products before accessories, show variant selectors and specifications on product
pages, and make sure search finds products. [catalog-tuning.md](references/catalog-tuning.md).
**Checkpoint:** the facets per category with sample values, and links to three filtered listings.

### Step 7: Review loop

Screenshot the same pages on the source and the new site, desktop and phone, have a fresh critic
agent score them, fix its top issues, and repeat until the score levels off or the agreed number
of rounds is reached. [review-loop.md](references/review-loop.md).
**Final report:** the score history, the open issues, links to all pages, and the tool defect list.

## Scaling up

When the user approves a subset, widen the scope and run steps 1 to 7 again for the rest. The
scripts, data model, and import activities from the first run are reused, so the full catalog
costs little more agent work than the subset.

## Out of scope

Order flows, payment and shipping setup, customer accounts, personal prices, and ERP integration
are separate work. Unpublished source pages cannot be read and are reported, not rebuilt.
