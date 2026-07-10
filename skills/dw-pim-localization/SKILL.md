---
name: dw-pim-localization
type: knowledge
group: pim
description: 'Manage product translation and localization across EcomLanguages in Dynamicweb 10. Triggers: product translation, EcomLanguage setup, AreaCopy language layers. Non-triggers: product structure -> dw-pim-modelling; product completeness -> dw-pim-completeness.'
---

# PIM Localization

## EcomLanguage Setup

Admin path: **Settings > Areas > Products > Internationalization > Languages**

1. Click **New Language**
2. Set **Name** (e.g., "German"), **Native name** (e.g., "Deutsch"), and **Regional setting** (locale, e.g., `de-DE`)
3. Set **permissions**: Action menu → Set permissions → select which user groups can manage this language
4. **Bind to website**: open the Website settings > Ecommerce tab → select which EcomLanguage is the default for that site

Each Dynamicweb website can be bound to one default EcomLanguage. Multi-language sites typically have one website per language, each binding to its own EcomLanguage.

## Product and Group Translation Rules

**Key rule:** Products and product groups **must** be explicitly translated to appear on non-default languages. Other ecommerce content (variants, asset categories, etc.) falls back to the default language if not translated.

This means a product that only exists in the default language is invisible on language-specific storefronts — it returns no results from queries filtered to a non-default language.

## Creating Language Versions for Products

### Bulk creation

1. In the product list, select one or more products
2. **Action menu → Add languages**
3. Select target languages
4. Select the initial state (if using a PIM workflow)
5. Click **Save**

This creates a language version of each selected product in each selected language.

### Removing language versions

Action menu on a product → **Remove language** → select the language to remove.

- Can only remove one language at a time
- Cannot remove the default language version

## Translating Product Fields

### Side-by-side translation view

1. Open any product
2. Click the **Translations** button
3. A side-by-side view opens: default language on the left, target language on the right
4. Edit translatable fields on the right side
5. Save

### Field-level visibility control

Each field can be set as editable or locked per language. This is configured at:

- **Settings > Products > Standard fields** — control standard product field visibility per language
- **Settings > Products > Global custom fields** — control custom field visibility
- **Settings > Products > Attribute group fields** — control attribute visibility

**Field visibility options:**
- Editable per language (default) — each language can have its own value
- Locked to master value — field value is shared across all languages; editing on one changes all

Use "Locked to master value" for fields like SKU/Number that must be consistent across languages.

### Grid edit for translations

The Grid Edit view also supports editing language version fields. Open the product list in Grid Edit mode and switch the language context to translate multiple products in bulk.

## Translating Product Groups

1. Open a product group
2. **Action menu → Manage languages → select languages → Create**
3. Click the **Translations** button on the group edit page → side-by-side translation

**Language coverage overview:** From a channel's context menu → **Languages option** — shows which languages have been added per group, useful for auditing translation coverage.

## What Else Can Be Localized

**Products-related:**
- Countries and country display names
- Currencies
- VAT Groups
- Variant Group options (color names, size labels, etc.)
- Relation group names
- Product units (kg, piece, box, etc.)
- Asset categories

**Commerce-related:**
- Order flow state names
- Cart flow state names
- Quote flow state names
- RMA states and events

## Workflow and Translation State

When creating language versions (via "Add languages"), you can assign the new language versions an initial **workflow state**. This integrates localization with the PIM workflow — for example, a German language version can start in a "Needs Translation" state and move to "Approved" when ready.

See [dw-pim-workflow](../dw-pim-workflow) for workflow setup.

## Completeness per Language

Product completeness is calculated per language context. A product might be 100% complete in English but 40% complete in German. Completion rules and queries can be scoped to a specific language, enabling language-specific workflows for translation progress.

See [dw-pim-completeness](../dw-pim-completeness) for completeness rule setup.

## Auto-Translation

Dynamicweb 10 supports auto-translation of product fields. Configuration is at the product or product group level. Useful for creating initial drafts that translators then review and approve.

## Pitfalls

**Products not appearing on storefront for a language** — the most common cause is missing language version. A product with only a default language version returns no results from language-filtered queries. Use the "Languages" overview on the channel to check coverage.

**Field values not carrying over** — when creating a language version, fields locked to master value share the same value across all languages. Fields not locked start empty in the new language version (they must be translated, not copied automatically).

**Removing a language version is irreversible** — there is no undo for language version removal. All translated field values for that language are deleted permanently.

**Locale format matters** — use IETF BCP 47 format (e.g., `de-DE`, `fr-FR`) for the Regional setting, not just `de` or `German`. An incorrect locale can cause date, number, and currency formatting issues on the storefront.

## Next Steps

- **Setting up workflow states for translation?** See [dw-pim-workflow](../dw-pim-workflow)
- **Checking translation completeness?** See [dw-pim-completeness](../dw-pim-completeness)
- **Product data modelling?** See [dw-pim-modelling](../dw-pim-modelling)
