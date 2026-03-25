# Dynamicweb Global Documentation Sources

## Root Sources
Use these as mandatory entry points:

1. Site index  
   https://doc.dynamicweb.dev/index.html
2. Global sitemap  
   https://doc.dynamicweb.dev/sitemap.xml

## Section Roots
Use these to ensure broad understanding across product and developer docs:

- Fundamentals: https://doc.dynamicweb.dev/documentation/fundamentals/setup/index.html
- Implementing: https://doc.dynamicweb.dev/documentation/implementing/index.html
- Extending: https://doc.dynamicweb.dev/documentation/extending/index.html
- API reference root: https://doc.dynamicweb.dev/api/index.html
- Manual example (DW10 concepts): https://doc.dynamicweb.dev/manual/dynamicweb10/products/concepts/datamodeling.html

## Crawl Scope Defaults
Default include prefixes:

- `/documentation/`
- `/manual/`
- `/api/`

Use exclude prefixes when needed to narrow context to a product area.

## Traversal Strategy
1. Parse the full sitemap for URL discovery.
2. Group URLs by section key:
   - `documentation/<subsection>`
   - `manual/<version-or-product>`
   - `api`
3. Select URLs with balanced section coverage before page fetching.
4. Fetch selected pages and extract ranked snippets.

## Snippet Selection Rules
Prioritize snippets that:

- define concepts, architecture, and behavior
- explain implementation steps and constraints
- describe extension points, APIs, or integration patterns

De-prioritize navigation-only text.

## Output Fields
The generated JSON context should include:

- `crawl`: discovery and selection metadata
- `sections[]`: discovered and selected counts per section
- `top_terms[]`: high-frequency meaningful terms
- `results[]`: per-page evidence with `url`, `section`, `title`, `snippets[]`, `error`
