---
name: dw-pim-completeness
type: knowledge
group: pim
mcp: optional
dynamo: true
description: 'Configure PIM completion rules, scoring, automatic query movement, and missing-field enrichment. Triggers: assign rules, calculate completeness, enrich query results. Non-triggers: manual states or transitions -> dw-pim-workflow; schema -> dw-pim-modelling.'
---

# Product Completeness

## Without MCP

The knowledge here stands alone; the Dynamicweb MCP tools it names are the way to apply it, and
in-product they are the only way — the MCP tool set plus read/write under `Files/` is the whole
surface these steps may use. When no tool covers the operation, **stop and tell the user**, naming
the admin screen that performs it, rather than substituting a guessed HTTP call, a file edit
outside `Files/`, or SQL. The Management API, the serializer and direct SQL exist only outside the
product, are never a step in this skill, and are owned by
[`dw-data-access`](../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance".

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

Assign completion rules on the **catalog groups (GroupType=0) that products actually live in** — open the product group → **Workflow tab** → select completion rules. Storage: comma-separated rule IDs in `EcomGroups.GroupCompletionRules` plus matching languages in `GroupCompletionLanguageIds`.

The UI also offers a Workflow tab on data models, but assignments to data-model groups (GroupType=2) do nothing at evaluation time — field-validated; put the assignment on the catalog group.

A product can have different completion requirements depending on which group or channel context it is evaluated in.

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

Add a **Repository Count Widget** to a dashboard that counts products matching a query (e.g., "products with completeness < 100%"). This provides a live quality overview. It is a **counter**: `WidgetType=Sum`/`Avg` is accepted and renders the row count anyway, so no stock widget can show a sum or an average (see [references/rules-and-dashboards.md](references/rules-and-dashboards.md)).

## Per-language completeness needs the Completeness feature flag

**With the "Completeness feature" flag off, completeness has no per-language dimension.**
`CompletionLanguages` changes nothing in a query: `ENU+ESU+FRC` returns the same products as `ENU`
alone, because no `CompletionRule|<id>` index value is written at all on that path.

**With the flag on, every index document carries its own score in its own language.** The product index
builder writes `CompletionRule|<id>` on each document, one per product, variant and language layer,
scored against that layer's values [dw 10.29.6]. Fields that do not vary per language
(`AllowChangesAcrossLanguages` off, the default for category fields) score from the master. A
translation-gap worklist is then one query per language:

1. Flag on: Settings > Feature management > "Completeness feature" (set by the user in the admin, read back).
2. Product index builder `SkipCompletionRules=false`.
3. Every target language in the group's completion languages and in the shop's languages.
4. Full rebuild of every index instance.
5. Query `LanguageID = <lang>` AND `VariantID` empty AND `CompletionRule|<id> < 100`.

Shared image and attribute gaps score the same in every language and drown the translation gap in a
mixed rule. A rule that lists only the copy fields (name, short and long description) separates the
languages. The admin product badge then opens a per-language breakdown, one column per completion
language, and shows their average. The MCP calculation tools do not score per language; see
[references/rules-and-dashboards.md](references/rules-and-dashboards.md) "Per-language scoring with the flag on".

See [dw-pim-localization](../dw-pim-localization) for language setup.

## Enriching Products Against a Query

Configuring rules answers "what must be filled"; this is the separate action of actually
filling the gaps for products matched by a saved query.

**Read-first workflow:**

1. **Source rules** — when the user names a query, read the query-source completion rules.
   Also read any shop-level and group-level rules that apply to the same products (a product
   can be subject to rules from multiple sources — read all relevant ones, not just the one
   named).
2. **Page through products** — fetch matching products page by page. Do not pull the whole
   result set into context at once.
3. **Per product** — compare current field values against the union of relevant rules. List
   only the empty required fields.
4. **Propose values** — propose a value for each empty field from visible context, sibling
   product values, or other already-set attributes on the same product. If no source is
   available, mark the field as needing user input rather than fabricating a value.
5. **Confirm** — present the proposed patch (fields + proposed values, not a generic summary)
   before writing.
6. **Patch only the empty fields** — never overwrite a value that is already set, even if a
   new proposal looks better. The contract is: fill the gaps, not edit what is filled.

**Multi-product chains.** Bulk enrichment is a chain of per-product patches. Treat the chain
as authorized once confirmed; break only on tool error, unknown value, or an explicit pause.

**Language layers.** If the relevant rules count translated fields, fill the master language
first; translations inherit unless explicitly overridden. Filling a translated field can
shadow a future master change in surprising ways — only do so when the user asked for a
specific language.

**Out of scope:** editing fields that already have values (this is enrichment, not curation);
changing a rule's field list itself (that's a rule edit, see "Creating Completion Rules"
above).

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

## Deep reference

[references/rules-and-dashboards.md](references/rules-and-dashboards.md), the field-validated internals: the hidden `reference_category` template category (the #1 cause of "rule defined and assigned but no panel renders"), the four-gate scoring chain, the 7-condition checklist for rules that "don't show", the completion-rule API traps (`ProductCompletenessRulesByProductId` 500s, the phantom auto rule id `0`, dangling ids after `CompletionRuleDelete`), the 7 real dashboard areas, clickable vs dead-end widget types, the widget envelope table, the MCP dashboard/widget payload contracts and their three invisible-dashboard blockers, and the idempotent `reference_category` seed SQL.

## Pitfalls

**Completeness is computed against a read context, not stored on the product**. `ProductById` with no rule context reports `0` for a verifiably complete product, and opening the product from a query supplies the context only if the query configuration carries `CompletionRules`. Check the score in the context that matters, and treat a `0` or `N/A` as a context question first. The four gates that must all be satisfied before anything scores at all are in [references/rules-and-dashboards.md](references/rules-and-dashboards.md).

**The `Completeness feature` flag decides whether completeness is queryable.** `CompletionRule|<id>` index fields populate only with the flag ON, so completeness as a query, dashboard or per-language term requires it. On DW 10.28 the flag-on calculation path was reported as a buggy beta and the flag-off legacy path ran the admin panels; the flag-on path was measured correct, with per-language index scores matching SQL and the admin badge showing the per-language breakdown [dw 10.29.6]. Decide which path the build needs before touching it, and never auto-toggle it.

**A master with variants never reaches 100% on a rule that lists `ProductNumber`.** Combining products as variants stores the master number as an empty string, and the master edit screen has no Number field. Keep `ProductNumber` out of completion rules; reported upstream as [dynamicweb/DynamicWeb#735](https://github.com/dynamicweb/DynamicWeb/issues/735) [dw 10.29.7]. Details in [references/rules-and-dashboards.md](references/rules-and-dashboards.md) "Masters with variants".

**"Use completeness rules to limit results" excludes 100% complete products** — this setting removes complete products from the query, which is the intended behavior for an enrichment backlog. If you want to see all products regardless of completeness, do not enable this setting.

**Empty completion rules count as satisfied** — a completion rule with no fields configured is always satisfied (contributes 100% to its portion). Always add fields to rules before assigning them.

**Completion rules must be assigned** — creating a completion rule at the global level does not automatically apply it to any product. It must be explicitly assigned to a data model or product group's Workflow tab. Assign shop rules with one `assign_completion_rules_to_shops` call per shop: a call with several requests persists only the last one (MCP 0.6.0-BETA). Read the assignment back with `get_completion_rule_assignments_for_shops`.

## Next Steps

- **Setting up PIM workflows?** See [dw-pim-workflow](../dw-pim-workflow)
- **Querying by completeness?** See [dw-search-indexing](../dw-search-indexing)
- **Per-language completeness tracking?** See [dw-pim-localization](../dw-pim-localization)
