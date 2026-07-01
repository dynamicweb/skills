---
name: dw-search-indexing
type: knowledge
group: search
description: Build and configure Dynamicweb 10 search indexes on Lucene — index types, builders, analyzers, scoring, and product index setup. Triggers: set up a product, content, user, or SQL index, configure repositories and index instances, tune analyzers or field boosts, understand Lucene scoring. Non-triggers: PIM data modelling -> dw-pim-modelling; product completeness -> dw-pim-completeness.
---

# Search Indexing

## Engine

Dynamicweb 10 uses **Lucene.NET 3.0.3** as its search engine. The old `Dynamicweb.SmartSearch` module from DW9 was deprecated and removed; the DW10 replacement is the Repositories/Indexing framework (referred to as "Lucene4" in upgrade documentation).

## Index Types

Admin path: **Settings > System > Repositories**

Five index types are available:

| Index type | Builder class | What it indexes |
|-----------|--------------|----------------|
| Product | `Dynamicweb.Ecommerce.Indexing.ProductIndexBuilder` | Products, variants, prices, groups, assortments, campaigns, stock |
| Content | `Dynamicweb.Content.ContentIndexBuilder` | Pages, paragraphs, item type fields |
| User | `Dynamicweb.Security.UserManagement.Indexing.UserIndexBuilder` | Users |
| File | `Dynamicweb.Content.Files.FileIndexBuilder` | File metadata |
| SQL | `Dynamicweb.Indexing.Builders.SqlIndexBuilder` | Custom data via SQL query |

## How Lucene Indexing Works

Three steps:

1. **Documents collected** — each product/page/user becomes a Lucene document with fields
2. **Fields analyzed and indexed** — each field is classified:
   - **Stored**: value kept for retrieval and display
   - **Indexed**: added to the inverted index as a single term (exact-match searches)
   - **Analyzed**: tokenized and normalized (full-text search). Uses a tokenizer + analyzer.
3. **Inverted index built** — maps terms to document IDs for fast lookups

**Scoring (ranking):**
- TF (Term Frequency) — how often a term appears in the document
- IDF (Inverse Document Frequency) — how rare the term is across all documents
- **Boost values** — fields can have a boost multiplier (e.g., ProductName boost 5 ranks title matches higher than description matches)

## Setting Up a Product Index

Full process in order: **Repository → Index → Instances → Build configuration → Fields → Query → Build**

1. Go to **Settings > Repositories** → create or open a repository
2. Add a new **Index**:
   - Name
   - **Balancer**: `ActivePassive` (serves from live instance while rebuilding passive) or `LastUpdated` (serves from most recently completed)
3. Add **two instances** (call them A and B) using `LuceneIndexProvider`
   - Stored at `/Files/System/Indexes/[RepoName]/[IndexName]/[InstanceName]`
4. Create a **Build configuration**:
   - Select `ProductIndexBuilder` (or other builder)
   - **Builder action**: Full (rebuild all), Update (products updated in last N hours), UpdateWithIds (batch saves from PIM)
5. Add **fields** using `ProductIndexSchemaExtender` or `ConfigurableProductIndexSchemaExtender`
6. Add a **Query** under the index for use by the Product Catalog app
7. Optionally add **Facet groups** under the query
8. Click **Build**

### Key ProductIndexBuilder Settings

| Setting | Description |
|---------|-------------|
| `OnlyIndexActiveProducts` | Only include active products |
| `HoursToUpdate` | Lookback window for Update builds (default 24h) |
| `SkipPrices` / `SkipStock` | Skip expensive price/stock loading |
| `SkipGrouping` / `SkipImages` / `SkipAssortments` | Skip specific data loading |
| `EmptyStringReplacement` | Value used when a field is NULL (Lucene cannot index NULL) |
| `ShopsToIndex` | Comma-separated shop IDs to scope the index |
| `BulkSize` | Products per indexing batch (default 500) |

## Analyzers

| Analyzer | Use for |
|---------|--------|
| `StandardAnalyzer` | General text (tokenizes, lowercases, removes stop words) |
| `KeywordAnalyzer` | IDs, URLs, exact values (no tokenization) |
| `WhiteSpaceAnalyzer` | Fields split at whitespace only |
| `SimpleAnalyzer` | Lowercase + letter tokenization |

**Important:** The same analyzer must be used for **indexing** and **querying**. A mismatch causes no results or unexpected results.

**Custom stop words:** Create `/Files/System/Repositories/stopwords.txt` with one stop word per line to override the default English stop word list.

## Field Types for Facets

Fields used as facets have strict requirements:

| Requirement | Reason |
|-------------|--------|
| Indexed = Yes | Must be in the inverted index |
| Analyzed = No | Analyzed fields split multi-word values ("Light Blue" → "light" + "blue"), corrupting facet grouping |

**Grouping fields** — for range-based facets (e.g., price ranges "0-200", "200-500"):
- Map a numeric source field to string labels
- Create via "Grouping field" in the field type selector
- These are then usable as facet options

### Facet Types

| Type | Use for |
|------|--------|
| Field facets | One option per unique field value (brand, category) |
| List facets | Group values under custom labels |
| Term facets | Top 2048 most frequent values; for high-cardinality fields like tags |

**Conditional facets** — show a facet only when another facet parameter has a value (or specific value). Example: show "Battery Type" facet only when Category = "Electric Bikes".

## Auto-Rebuilding the Index

Three triggers:

| Trigger | Where to configure |
|---------|------------------|
| On product save (in PIM) | Channel settings → Advanced Information tab → select a product index |
| After integration activity | Integration activity settings → Repositories to rebuild |
| On schedule | Settings > Scheduled Tasks → "Build repository index" task |

**Note:** Auto-rebuild on save does NOT remove deleted products from the index. Deletions require a Full build.

The recommended approach is a scheduled Full rebuild at a quiet time (e.g., nightly) plus an Update build during business hours for near-real-time updates.

## Queries

A query defines how the Product Catalog app retrieves results. Three components:

1. **Parameters** — dynamic values from user input (search term, facet selection, page number)
2. **Expressions** — filter conditions (field + operator + test value); can be grouped with AND or OR logic
3. **Sorting** — field + direction

### Expression Operators

| Operator | Description |
|----------|-------------|
| `Contains` | Prefix match (starts with term) |
| `ContainsExtended` | Anywhere match (higher performance cost) |
| `MatchAny` / `MatchAll` | Array matching |
| `In` | Array — matches any value in set; URL syntax: `&Color=[Red],[Blue]` |
| `IsEmpty` | Null/empty check |

### Expression Groups

- **OR group** — any expression matches (used for full-text search: "ProductName contains term OR ProductDescription contains term")
- **AND group** — all expressions match (used for facet filtering)

## Browsing the Index (Debugging)

From the index overview: context menu → **Browse index**

Shows all indexed documents, allows changing visible columns, and lets you inspect individual document fields. Use to verify field values, confirm field storage/indexing settings, and debug missing search results.

Check for:
- Field value present and correct
- Field marked Indexed (not just Stored)
- Analyzed setting matches expectation (no analysis for facets)

## Content Index

Builder: `Dynamicweb.Content.ContentIndexBuilder`

- Only Full build (no incremental)
- Indexes pages, paragraph headers, paragraph text, all item type fields
- Item type field format in index: `[item.SystemName]_[itemField.SystemName]`
- `ItemListEditor` fields are never indexed

## Spell Check ("Did You Mean")

Configured on the **Product Catalog app** → Spell Check section:
- **Field to check** — index field containing the combined searchable text
- **Query parameter** — query parameter that carries the user's search term

Template tags: `QueryResult.SpellCheck` (top suggestion), `SpellCheckerSuggestions` loop (additional suggestions).

## Pitfalls

**Analyzed facet fields** — the most common indexing mistake. A color facet on "Light Blue" analyzed into "light" and "blue" shows as two separate facets. Always set facet fields to Not Analyzed.

**Two instances required** — the `ActivePassive` balancer requires at least two instances (A and B) to function. With only one instance, the balancer has nowhere to build while serving.

**Deletions need Full builds** — Update builds (hourly, on-save) do not detect or remove deleted products. A nightly Full rebuild is required to keep the index clean of stale products.

**NULL values** — Lucene cannot index NULL. Always set `EmptyStringReplacement` on the index to a sentinel value (e.g., `"__empty__"`) and use `IsEmpty` expressions in queries to filter/detect empty fields.

## Next Steps

- **Setting up the Product Catalog app?** See [dw-commerce-catalog](../dw-commerce-catalog)
- **Completeness-driven queries?** See [dw-pim-completeness](../dw-pim-completeness)
- **C# custom index provider?** See [dw-extend-providers](../dw-extend-providers)
