---
name: dw-content-localization
type: flow
group: content
description: 'Create a language version of a Dynamicweb 10 website and translate its page content, or translate an existing page/site from one language to another. Triggers: make a French/German/... version of this website, translate the about page, translate all pages in this area, create a language version. Non-triggers: translating PIM product data -> dw-pim-localization; designing item types/paragraphs -> dw-content-modelling; a faithful site rebuild from another platform -> dw-swift-migrate-content.'
---

# Content Localization

Use this skill for "make an <language> version of this website" or "translate this page/site
from one language to another." Translation is the one thing only the model can do here. The
MCP tools are deterministic: they replicate the site structure and move text in and out. **The
model** produces every translated string. There is no "translate" tool and there must be no
hard-coded phrase list anywhere.

## The default path: a whole new language version

This is the right approach for "make an <language> version of this website" and avoids the
per-page copy traps below.

1. **Identify the source website** and the target culture. Use `get_areas` / `get_master_areas`
   to resolve the website the user means (e.g. the English site) and pick the culture code
   (e.g. `fr-FR`). Ask only if it is genuinely ambiguous.
2. **Create the language version** with `create_language_version(sourceAreaId, culture,
   name)`. This creates the new area **and copies every page and its content into it in one
   step** as a language replica. It is idempotent — if a version for that culture already
   exists it is returned unchanged (`Created=false`), so it is safe to call it to "ensure" the
   version exists. The result gives you the new `AreaId` and `PageCount`.
   - `create_language_version` copies the whole site like Dynamicweb's "New website
     language," names the new layer distinctly from the master (so it can be switched to in
     the website dropdown), and leaves it **unpublished** so untranslated content is not live.
     After translation, tell the user it is still unpublished and let them publish it when
     ready.
   - A language version replicates the whole structure correctly in one operation — this is
     the only supported way to bring a whole site across. (Per-page copying of restricted
     item types like product detail pages is blocked by item-type creation rules, which is
     exactly why the language-version path exists.)
   - The copy is transactional: one page whose item type can no longer be resolved aborts the
     whole copy. `create_language_version` checks for this first and, if it finds any, fails
     with the list of offending pages instead of attempting a doomed copy. `
     find_unresolvable_item_pages(sourceAreaId)` gets the full list directly. When this
     happens, surface the pages to the user (page id + item type) and ask them to fix or
     remove those pages — do not try to work around it; the source data must be repaired
     first.
3. **Translate, paginating by UNIT — loop until `HasMore` is false.**
   `get_translatable_content` returns an object with `Units` (this batch) plus `HasMore` and
   `NextSkip`. A large page has more units than one batch can carry, so you **must loop**:
   call `get_translatable_content(areaId: <id>, skip: 0, take: 20)` (or `pageId:` for one
   page), translate that batch's `Units`, write it back with `apply_translation(units)`, and
   **while `HasMore` is true, call again with `skip = NextSkip`** (same `take`). Continue
   until `HasMore` is false. Stopping while `HasMore` is true leaves the rest of the page —
   e.g. an accordion of questions at the bottom — in the source language. Each unit is tagged
   with its `PageId`, so pages don't need to be listed separately. A batch from an area
   normally spans **several pages** — translate the whole batch and pass **all** of its units
   (every page included) in a **single** `apply_translation` call; the server groups them by
   `PageId` and saves each page once, so never make one call per page.
   - Preserve HTML tags, attributes, entities, and any placeholders/merge tokens exactly —
     translate only the human-readable text between them. Do not translate URLs, file paths,
     system names, option keys, or code.
   - Translate faithfully: render the text literally, do not paraphrase, and do not add or
     remove information. Keep the source's meaning, tone, punctuation style and emphasis — do
     not normalise tone, pad, or summarise; change punctuation or emphasis only where the
     target language requires it. Translate the whole unit, leaving no part in the source
     language; if a unit is already in the target language leave it unchanged, and words that
     are identical in the source and target languages may be left as-is.
   - When returning units to `apply_translation`, keep each unit's `PageId`, `Kind`,
     `ParagraphId` and `FieldSystemName` unchanged and set `TranslatedText`. Empty translations
     are rejected, so omit anything you chose not to translate.
   - **Run to completion silently — one job, one message.** Translating a page or a whole
     site is ONE authorized job after the first confirmation. Do **not** post a message,
     summary, or "translated a batch / shall I continue?" between batches **or between
     pages** — that constant check-in is the main annoyance on a big site. Keep calling
     `get_translatable_content` → `apply_translation` back-to-back across every batch (`skip =
     NextSkip` while `HasMore`) and every page in the area, **without pausing or narrating**,
     until the whole job is done. Post exactly ONE message at the very end (a single final
     summary: pages / fields translated / failures). Break only on an unrecoverable tool error
     or an explicit user pause/stop. If the runtime ends the turn before the job is finished,
     resume the loop immediately — do not ask the user whether to continue. Read per-page/
     field errors as you go and re-apply only the failures; do not halt for individual field
     errors.

## Translating an existing language version

If the user points at a website that is already a language version (its area has
`MasterAreaId > 0`), skip creation: it already holds copies of every page. Translate it with
`get_translatable_content(areaId: <id>)` / `apply_translation` as above. Re-running
`create_language_version` is also safe and returns the existing area.

## Translating a single page

For "translate this one page", use `get_translatable_content(pageId: <id>, skip: 0, take:
20)` and **loop while `HasMore` is true, calling again with `skip = NextSkip`** (same rule as
above), translating each batch's `Units` and writing it back with `apply_translation(units)`.
This is exactly what catches a bottom-of-page accordion/FAQ that a single un-looped call would
miss.

## Scoping to a subset (e.g. just the titles)

When the user scopes the request to part of a page — most commonly "translate (only) the page
titles/names" — pass `get_translatable_content`'s `kinds` filter (`kinds="PageField"` for
titles) so the whole site doesn't get translated, and name the scope when confirming
("Translate page titles → French"). The tool description lists the kind values.

## Product detail pages are mostly PIM data

A product detail page (e.g. a product-list/detail page type) renders products dynamically.
The page itself only has template chrome (paragraph/item-field text), which the tools above
handle. The actual product names and descriptions live in the **product**, not the page —
translate those through the PIM product language layers instead (see
[dw-pim-localization](../dw-pim-localization)).

## Confirm before writing

State the scope and target language ("Create French version of the B2C shop", "Translate
About page → French") and roughly how many pages/fields will change and on which website. Ask
for confirmation **once** before starting a whole-site translation; once accepted, the entire
run is authorized — do not raise a new confirmation or stop to check in for each batch. Give
one final summary at the end (pages / fields translated / failures), not a stop-and-wait after
every batch.

## Out of scope

- Inventing target pages or areas the user did not ask for — confirm first.
- Translating PIM product data (use the PIM tools and product language layers — see
  [dw-pim-localization](../dw-pim-localization)).
- Overwriting values that are already correctly translated unless the user asks for a
  re-translation.
