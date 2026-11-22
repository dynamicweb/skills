# Debrand: find and replace a name across a website with MCP tools

How to find every stored place a name shows on one website and replace it in place, with the MCP
shapes measured on one host [dw 10.30.6 · mcp 0.6.3-BETA].

## Contents

- [The scan: get_translatable_content](#the-scan-get_translatable_content)
- [The write: apply_translation in place](#the-write-apply_translation-in-place)
- [Website settings, website name and shops](#website-settings-website-name-and-shops)
- [What no scan reads](#what-no-scan-reads)

## The scan: get_translatable_content

`get_translatable_content {areaId, take, skip}` walks every page of a website, the header and footer
pages and system mail pages included, and answers `{units, skip, take, returned, hasMore, nextSkip}`.
Each unit is one stored text: `{pageId, kind, paragraphId, fieldSystemName, label, editorType, isHtml,
sourceText}`, plus `itemType` and `itemId` for a `NestedItemField` (a slide, an accordion entry).
`kind` is `PageField` (`MetaTitle`, and `MenuText` on a page without an item title), `PageItemField`
(the item title that names an item-typed page), `ParagraphField` (`Header`) or `ParagraphItemField`.
The call returns fewer units than `take` when a page ends (one call with `take: 200` returned 44): loop
on `hasMore` with `skip = nextSkip` until it is false. `{pageId, take}` reads one page.

`sourceText` is the stored value: rich text keeps its markup and HTML entities, so a name with `&`
matches as `&amp;`.

## The write: apply_translation in place

`apply_translation {translations: [{pageId, kind, paragraphId, fieldSystemName, itemType, itemId,
translatedText}]}` writes each unit back onto the page it names and answers `{succeeded, failed,
errors}`; on the master language that is an in-place text write. Copy the locator members from the
unit unchanged; an empty `translatedText` is refused. **Send every unit of a batch in one call**, as
the tool asks: sent one call per unit, a paragraph's `Header` write that followed a separate write of the
page's title answered success and read back unchanged; the same units in one call all landed. Measured: a `PageField` `MetaTitle` and a
`ParagraphItemField` `Text` were rewritten, the scan read them back changed, and the served page title
changed on the next request.

A `PageItemField` `Title` write re-derives the page's menu text and, unless the url name is pinned,
its address.

## Website settings, website name and shops

- The website settings item (`get_area_by_id` gives `itemType` `Swift-v2_Master` and `itemId`):
  `get_item_field_values {itemType, itemId}` lists `{fieldSystemName, value}`; write one field with
  `set_item_field_values {values: [{itemType, itemId, fieldSystemName, value}]}`. `MetaSiteName` is the
  brand's name on the website. The storefront serves these settings from its cache until the host
  recycles.
- The website's own `name` (`get_area_by_id`) is reported, not renamed: the serializer's manifests key
  their file paths off it.
- Shop and channel names (`get_shops`, `{count, data: [{id, name, …}]}`) are reported for the shop
  settings.

## What no scan reads

Product and group names, template literals and translation keys, and the mail template files under
`/Files/Templates` are not text units. `fetch_frontend_page_html {path}` checks a rendered page's
`title` and `h1Tags`; the rest of a rendered page is checked by reading it.
