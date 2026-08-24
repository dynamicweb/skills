# Content modeling — editor-manageable pages, not HTML blobs

> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

**The rule: model one paragraph (or field) per editor concern; rich-text fields carry prose only.**
The moment a `class=` attribute, a `<div>`, or a structural `<img>` is needed inside a rich-text
field, that is the signal to model a field or an item type instead.

The full vendor-generic discipline — decompose by editor concern, field-purity rules, images in image
fields, plain-text titles, no page-ID-scoped CSS, list pages read modeled fields, watch for stacking
debris — is owned by the `dw-content-modelling` foundational skill, staged in
[`modelling-discipline.md`](../../dw-content-modelling/references/modelling-discipline.md) §1
("Editor-manageable pages, not HTML blobs"). The custom item-type `<Prefix>_*` discipline (when a block
needs editor-configurable fields the stock item types don't have) is §2 of the same file. Load both
**before** building any designed page, not as a post-hoc audit.

**The escape hatch, and its cost.** DW does not sanitise item Text fields on either hop: a
`Swift-v2_Text` paragraph's `Text` field is stored and rendered as opaque markup — `ParagraphSave`
does not strip and the render does not encode event attributes (`@click.prevent`, `onclick`),
`x-data`, `data-*` or inline `<script>`; the served HTML comes back byte-identical to what was
submitted. Since Swift already loads Alpine.js and `bootstrap.bundle.min.js` sitewide, behaviour can
be added purely from content — no template edit, no new script asset, no new JS dependency. That
makes the hatch genuinely available when the modeled path is unreachable (an unpopulatable item
list, a picker field that will not persist — see [paragraphs.md](paragraphs.md)), and it is much
smaller blast radius than forking a template for a content-level behaviour. It is still an HTML
blob, so the gate below still applies: record it as a deliberate exception rather than reaching for
it first. And before designing a fallback ladder around "DW will sanitise this", **probe it**: write
a throwaway paragraph carrying the exact attributes/elements in question, diff the SERVED HTML
against the submitted field (sanitisation could live in either hop, so the `GetParagraphById`
round-trip alone is not enough), then delete the throwaway. Only a non-empty diff justifies a
template change.

**The gate — per designed page.** Open the paragraph(s) in the DW editor and ask: *"could a content
editor change the image, reword the quote, and edit one stat — without seeing HTML?"* If no, remodel
before moving on. Run this per designed page, not once per demo.

Related cross-references:
- [re-skin.md](re-skin.md) §"separate the styling from the content" — the item-type + variant + CSS
  escalation that replaces a styled rich-text blob.
- [re-skin.md](re-skin.md) §"Re-skin smell: Swift-v2_Text shim + foreign cshtml" — the same root cause
  (template-path override hiding hardcoded content behind a generic Text item).
