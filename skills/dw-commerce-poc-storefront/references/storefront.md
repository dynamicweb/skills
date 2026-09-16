# Assembling the Swift 2 storefront

The component vocabulary — row definitions, paragraph types, variants, colour schemes and the
tools that compose them — belongs to [dw-swift-page-blocks](../../dw-swift-page-blocks), and
composing a page well belongs to [dw-swift-page-design](../../dw-swift-page-design). Read those
first. This file carries only what a catalogue POC adds on top, and the behaviours that silently
do nothing.

## Contents

- [The shape of the site](#the-shape-of-the-site)
- [Starting from a working area](#starting-from-a-working-area)
- [Traps that silently do nothing](#traps-that-silently-do-nothing)
- [Repeatable item lists need structural edits](#repeatable-item-lists-need-structural-edits)
- [Renaming a page without changing its URL](#renaming-a-page-without-changing-its-url)
- [The product page](#the-product-page)
- [The listing page](#the-listing-page)
- [Navigation](#navigation)
- [De-demoing everything the template brought with it](#de-demoing-everything-the-template-brought-with-it)

## The shape of the site

A catalogue POC needs less than it looks: a front page that explains the brand and routes into
the catalogue, the catalogue itself, a product page worth reading, and the handful of editorial
pages that make it feel like a shop.

Front page — a hero, a typed entry tile per category with real counts, one editorial band, a
few proof points, and a short FAQ. Then: catalogue root, category pages, product detail, about,
delivery, FAQ, and the policy pages. Resist more; every extra page is another surface to QA.

## Starting from a working area

Copying a working Swift 2 area is usually faster than assembling one, because the header,
footer, cart and component pages arrive already wired. It also imports the source area's
content wholesale, so budget for the de-demoing below.

**A copied area keeps pointers into the area it came from.** Component sources, off-canvas menu
sources and any page-reference field can still address the original area's page ids, which
renders the wrong site's content inside your pages. After copying, walk every page-reference
field and repoint it at this area's equivalent.

## Traps that silently do nothing

Each of these accepts the write, reports success, and changes nothing visible. They are the
reason a build feels haunted.

- **A grid column renders exactly one paragraph.** A second paragraph placed in the same column
  is ignored without error. One block per column; add a row when you need another.
- **A paragraph with its own `colorSchemeId` gets container padding.** It shows up as a block of
  text mysteriously indented relative to its neighbours. Let the row carry the scheme and leave
  the paragraph's empty unless you want the inset.
- **Rows created with `save_grid_rows` have no item instance, and on component pages such rows
  do not render at all.** Build component-page rows with `copy_grid_row` from a row that already
  works.
- **A paragraph inside a grid row cannot be deactivated.** `Active: false` is a no-op; remove the
  block with `delete_paragraphs`.
- **Mobile column order is not writable.** A freshly created multi-column row can come back with
  a scrambled mobile order, and `copy_grid_row` from a correctly ordered row inherits the good
  one. Four-column rows swapping within pairs on mobile is shipped behaviour.
- **A page's meta description is not writable** through the page tools — only the meta title is.
  Record it as a limitation.

## Repeatable item lists need structural edits

Off-canvas menu sections, accordion rows, slider slides and anything else built from a
repeatable item-list field behave differently from ordinary paragraph fields: **editing a child
item's fields does not reliably reach the rendered page.** The read-back shows the new value
while the frontend keeps serving the old one, which reads exactly like caching and is not.

Changing the list's *structure* does take effect. So to change such a child, remove it with
`remove_repeatable_items` and add a replacement with `add_repeatable_item` carrying the new
field values, at the sort position you want.

Two consequences worth internalising: verify these edits by fetching the rendered page rather
than by reading the item back, and when a field edit appears not to work anywhere in this
family, reach for the remove-and-re-add before concluding the platform is caching.

## Renaming a page without changing its URL

An item-typed page derives its menu text from its item's title field, and `save_pages` rewrites
the menu text from that field on every save — so `set_page_menu` alone does not stick. Renaming
also moves the friendly URL, which breaks links already rendered elsewhere.

The sequence that renames cleanly and keeps the URL:

1. `set_page_item_fields` — set the item's title field to the new name.
2. `save_pages` — same page, with `urlName` pinned to the existing segment and `metaTitle` set
   to the fuller title you want in the browser tab.

This is how a footer link becomes short enough to fit a phone column without losing its address
or its page title.

## The product page

Order the page the way a buyer asks questions: name, one-sentence teaser, the four or five facts
that decide the purchase, price, add to cart — then the description, then the full specification
in accordions, then cross-sell.

- Put a **short display group beside the price**, not an accordion. The buying decision is made
  there.
- Give the description **real structure**: key features as a list, then a sentence built from the
  product's own fields, then a muted line for design and warranty.
- **Link out to the choice the shopper has to make next** — the material, textile or size
  library — from inside the buy box. A product page that mentions options without offering a
  route to them reads as unfinished.
- Configure cross-sell as a **product relation** so it excludes the current product. A generic
  relation type will recommend the page you are standing on.

## The listing page

- **Show the facets that matter, on the catalogue root as well as the categories.** A root with
  no product-type filter cannot be narrowed at all.
- **Put a spec line on the card.** Name and price alone make a grid of near-identical products
  unshoppable; one generated line naming the differentiating attributes makes it shoppable.
- **Raise the page size** past the template default so the grid looks like a catalogue.
- **Check the card text alignment** — title, description and price share one left edge. A
  description indented relative to its title is the `colorSchemeId` padding trap above.

## De-demoing everything the template brought with it

A Swift starting point arrives full of the demo's own content, and it hides in the places nobody
screenshots. Sweep all of them before the first critic round:

- the footer link lists and the copyright line,
- the off-canvas and mobile menus, which often keep the demo's categories and its locale prefix,
- the mobile header, logos and any second logo variant,
- every editorial page inherited from the template, including the ones not linked from the
  navigation,
- blog or employee pages, which invent people; hide or delete them,
- meta titles across every page.

Then read the whole site once at a phone width. The desktop view is the one you have been
building in, so the mobile view is where the leftovers survive.
