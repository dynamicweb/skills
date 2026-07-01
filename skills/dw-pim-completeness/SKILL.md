---
name: dw-pim-completeness
type: knowledge
group: pim
description: Configure Dynamicweb 10 product completeness — completion rules, completeness scoring, and query-driven automatic workflows. Triggers: create completion rules, assign rules to data models or product groups, understand completeness scoring, set up completeness-driven query movement. Non-triggers: manual workflow states -> dw-pim-workflow; the Data Model schema -> dw-pim-modelling.
---

# Product Completeness

## What Completeness Is

Completeness is a calculated percentage score that represents how complete a product's data is in a given context. The score is derived from **completion rules** — configured sets of fields that must be filled. Products reach 100% completeness when all required fields have values.

Completeness powers two things:
1. **Editorial oversight** — editors can see and filter products by their completeness score in product queries and dashboards
2. **Automatic workflows** — queries can be configured to automatically move products as completeness changes (see below)

## Completion Rules

### What a Completion Rule Is

A completion rule is a named group of fields. Each rule contributes equally to the overall completeness percentage. A product satisfies a rule when all fields in that rule have non-empty values.

**Example:** If there are 4 completion rules and a product satisfies 3 of them, its completeness is 75%.

### Creating Completion Rules

Admin path: **Settings > Products > Advanced > Completion Rules** (or via the Workflow tab on a data model or product group)

1. Click **New completion rule**
2. Provide a **name** (e.g., "Basic content", "SEO fields", "B2B attributes")
3. Add **fields** — select from standard fields and category/custom fields
4. Save

### Assigning Completion Rules to Contexts

Completion rules are assigned at two levels:

**Data model level:** Open a data model → **Workflow tab** → select which completion rules apply to products of this model

**Product group (channel) level:** Open a product group → **Workflow tab** → select completion rules for this group

A product can have different completion requirements depending on which data model or channel context it is evaluated in.

## Completeness as an Automatic Workflow Engine

Completion rules on **product queries** create a form of automatic workflow where products move between queries as their completeness score changes.

### Setup

1. Create a product query (e.g., "Needs enrichment")
2. On the query settings, enable **"Use completeness rules to limit results"**
3. When checked, products that have reached **100% completeness** are automatically **excluded** from this query

This means:
- Query "Needs enrichment" shows all incomplete products
- As products reach 100%, they drop off this query automatically
- A second query "Complete — ready to publish" can filter for products at 100%

This is the "automatic workflow" — products progress through queries without manual state changes.

### Combining with Manual Workflows

For teams needing explicit state tracking (e.g., "In Review" before "Approved"), combine completion queries with the **PIM Workflow** feature. Products move automatically when completion rules are met, then require a manual workflow state change for the final approval step.

See [dw-pim-workflow](../dw-pim-workflow) for workflow configuration.

## Viewing Completeness in the Admin

### In product list

The product list displays a **Completeness** column showing each product's percentage for the current query context. Filter and sort by this column.

### Completion status in dashboards

Add a **Repository Count Widget** to a dashboard that counts products matching a query (e.g., "products with completeness < 100%"). This provides a live quality overview.

See [references/dashboard-widgets.md](references/dashboard-widgets.md) for the MCP tools, widget schemas, and payload examples to build these widgets.

## Per-Language Completeness

Completeness is calculated **per language**. A product may be 100% complete in English but 40% complete in German if the required fields have not been translated.

Completion queries can be scoped to a specific language, enabling language-specific editorial backlogs.

See [dw-pim-localization](../dw-pim-localization) for language setup.

## Completion Rule API

```csharp
using Dynamicweb.Ecommerce.Services;

// Get all completion rules
var rules = Services.CompletionRules.GetCompletionRules();

// Get completion rules for a specific data model
var modelRules = Services.CompletionRules.GetCompletionRulesByDataModel(dataModelId);

// Get completeness score for a product
double score = Services.CompletionRules.GetCompletenessScore(product, languageId, context);
```

## Pitfalls

**Completeness context matters** — a product's completeness score can differ between channels and languages. Always check completeness in the relevant context, not just the default.

**"Use completeness rules to limit results" excludes 100% complete products** — this setting removes complete products from the query, which is the intended behavior for an enrichment backlog. If you want to see all products regardless of completeness, do not enable this setting.

**Empty completion rules count as satisfied** — a completion rule with no fields configured is always satisfied (contributes 100% to its portion). Always add fields to rules before assigning them.

**Completion rules must be assigned** — creating a completion rule at the global level does not automatically apply it to any product. It must be explicitly assigned to a data model or product group's Workflow tab.

## Next Steps

- **Setting up PIM workflows?** See [dw-pim-workflow](../dw-pim-workflow)
- **Querying by completeness?** See [product query authoring](../dw-search-indexing/references/product-query-authoring.md) in dw-search-indexing
- **Per-language completeness tracking?** See [dw-pim-localization](../dw-pim-localization)
