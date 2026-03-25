---
name: dynamicweb-doc-context-fetcher
description: Traverses Dynamicweb documentation globally to produce a reusable context payload with section coverage, ranked snippets, and traceable source URLs. Use when you need comprehensive documentation context from doc.dynamicweb.dev across multiple sections.
---

# Dynamicweb Doc Context Fetcher

## Overview
Traverse Dynamicweb documentation globally, not just a single page, and produce a reusable context payload with section coverage, ranked snippets, and traceable source URLs.

Read `references/dynamicweb-doc-sources.md` first to align crawl scope and section priorities.

## Workflow
1. Build a full URL inventory from `https://doc.dynamicweb.dev/sitemap.xml`.
2. Select a balanced set of pages across sections (`documentation/*`, `manual/*`, `api/*`).
3. Fetch and rank snippets from selected pages.
4. Return context with source links, coverage statistics, and explicit inference boundaries.

## Crawl Commands
Create a global inventory (whole-site traversal metadata):

```bash
python scripts/fetch_dynamicweb_context.py --inventory-only --output dynamicweb-inventory.json
```

Create broad context with balanced sampling across sections:

```bash
python scripts/fetch_dynamicweb_context.py \
  --max-pages 180 \
  --max-pages-per-section 30 \
  --output dynamicweb-global-context.json
```

Create targeted context on top of the global crawl:

```bash
python scripts/fetch_dynamicweb_context.py \
  --query "commerce checkout order integration" \
  --include-prefix "/documentation/" \
  --include-prefix "/manual/" \
  --max-pages 140 \
  --output dynamicweb-targeted-context.json
```

## Output Contract
Always return:
- `crawl` metadata: sitemap source, discovered URL count, selected URL count
- `sections[]` with per-section discovered and selected counts
- `top_terms[]` representing broad site concepts
- `results[]` with `url`, `section`, `title`, `snippets[]`, and `error` (if fetch failed)

## Quality Gates
- Always start from `index.html` and `sitemap.xml` to avoid narrow context.
- Keep section coverage balanced unless the user requests a focused section.
- Ground claims in extracted snippets and include source URLs.
- If crawling fails for some pages, preserve those failures in output and continue.

## Web-Tool Fallback
When shell/network crawling is blocked:
1. use `web.search_query` to locate official `doc.dynamicweb.dev` pages by section
2. use `web.open` on selected results
3. build the same output contract manually (coverage + snippets + links)
