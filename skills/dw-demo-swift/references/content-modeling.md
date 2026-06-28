# Content modeling — editor-manageable pages, not HTML blobs

> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

**The rule: model one paragraph (or field) per editor concern; rich-text fields carry prose only.** The moment a `class=` attribute, a `<div>`, or a structural `<img>` is needed inside a rich-text field, that is the signal to model a field or an item type instead — see the escalation mechanics in [re-skin.md](re-skin.md) §"separate the styling from the content" and the custom item-type discipline in [dw10-canonical-surfaces.md](dw10-canonical-surfaces.md).

## Why this exists

A demo audit found a family of designed article pages where each page was a single `Swift-v2_Text` paragraph whose `Text` field held a hand-authored HTML blob: an inline hero `<img>`, a custom-class `<blockquote>`, and a hand-built key-figures `<div>` grid — plus raw `<h2>` markup inside the `Title` field. The pages LOOKED right, but:

- An editor could not swap the hero image (no file picker — it's markup), reword the pull-quote, or change one stat without editing HTML in the RTE. The first WYSIWYG touch destroys the class-bearing structure.
- ~150 lines of the demo's `<customer>_custom.css` existed only to style content-embedded classes — including a styled "byline" block that NO content actually used. Dead CSS is undetectable when the markup lives in database rows instead of a template.
- The list page had to scrape "the first paragraph image on each child page" to build its cards, because the detail pages had no modeled hero-image field.
- Page-ID-scoped CSS (`body[data-dw-page-id="42"] … { text-align:left }`, repeated per page) was needed to undo a global rule — so every future article requires a developer to edit CSS.

The page was a developer artifact, not content. That undermines the core CMS pitch: the prospect's content team must be able to imagine THEMSELVES maintaining the page, and prospects do open the editor during/after a demo.

Under time pressure, "one Text paragraph + HTML + CSS" is genuinely the fastest way to make a page look right — which is why the rule has to be enforced at build time, not discovered at audit time.

## The discipline

1. **Decompose by editor concern, not by visual block.** An article page is: hero image + title + body prose + pull-quote + key figures + byline. Each concern is a field or its own paragraph — never spans inside one rich-text blob.
2. **Rich-text fields contain only tags the WYSIWYG itself produces** (`p`, `strong`, `em`, `ul`, `a`, plain `blockquote`). No `class=`, no `<div>`, no `style=` (the inline-`style` RTE-hostility case is covered in [re-skin.md](re-skin.md)).
3. **Images go in image fields** (`ParagraphImage` or an item image field) so editors get the file picker and templates get `/Admin/Public/GetImage.ashx` resizing/format conversion for free. Never `<img>` inside rich text for structural images (hero, card, avatar). Inline images are acceptable only as true in-prose illustrations.
4. **Title/Header fields are plain text.** Markup belongs to the layout template (`<h2 class="dw-h2">@Model.Item.GetString("Title")</h2>`), not the data. (Known OOTB exception: a few stock Swift items — MiniCart/Favorites header titles — ship HTML fragments in `Title`; preserve those wrappers, don't imitate them.)
5. **Structured repeating content (stats, tiers, bylines) = a custom item type** with typed fields, rendered by its own content layout (see [re-skin.md](re-skin.md) §"Pixel-perfect escalation"). The CSS then targets classes the TEMPLATE emits, so markup and style live in one reviewable file — and unused CSS becomes detectable again.
6. **No page-ID-scoped CSS.** A selector containing a page ID is a hard smell: it breaks silently on page copy/re-seed and turns content scaling into developer work. If one page family needs a layout variant, give it its own content layout or an item-driven modifier class (`data-<brand>-variant` per [re-skin.md](re-skin.md)).
7. **List pages read modeled fields, not scraped markup.** Card image = the child page's image field; teaser = the page description or a teaser field. If a list template must parse child pages' paragraphs to find an image, the detail pages are mismodeled — fix the model, not the scraper.
8. **Watch for stacking debris.** Iterating on a hand-built page tends to leave superseded paragraphs in the same grid row/column slot, where DW10's one-paragraph-per-(row,column) rendering hides all but one — invisible on the storefront, confusing in the editor. Delete what you replace.

## The gate — before calling a designed page done

Open the paragraph(s) in the DW editor and ask: **"could a content editor change the image, reword the quote, and edit one stat — without seeing HTML?"** If no, remodel before moving on. Run this per designed page, not once per demo.

Related smell with the same root cause (template-path override hiding hardcoded content behind a Text item): [re-skin.md](re-skin.md) §"Re-skin smell: Swift-v2_Text shim + foreign cshtml".
