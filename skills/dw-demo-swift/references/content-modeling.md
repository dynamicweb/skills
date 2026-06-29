# Content modeling — editor-manageable pages, not HTML blobs

> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

**The rule: model one paragraph (or field) per editor concern; rich-text fields carry prose only.**
The moment a `class=` attribute, a `<div>`, or a structural `<img>` is needed inside a rich-text
field, that is the signal to model a field or an item type instead.

The full vendor-generic discipline — decompose by editor concern, field-purity rules, images in image
fields, plain-text titles, no page-ID-scoped CSS, list pages read modeled fields, watch for stacking
debris — is owned by the `dw-content-modelling` foundational skill, staged in
[`content-modelling.md`](../../dw-demo-base/references/foundational/content-modelling.md) §1
("Editor-manageable pages, not HTML blobs"). The custom item-type `<Prefix>_*` discipline (when a block
needs editor-configurable fields the stock item types don't have) is §2 of the same file. Load both
**before** building any designed page, not as a post-hoc audit.

**The gate — per designed page.** Open the paragraph(s) in the DW editor and ask: *"could a content
editor change the image, reword the quote, and edit one stat — without seeing HTML?"* If no, remodel
before moving on. Run this per designed page, not once per demo.

Related cross-references:
- [re-skin.md](re-skin.md) §"separate the styling from the content" — the item-type + variant + CSS
  escalation that replaces a styled rich-text blob.
- [re-skin.md](re-skin.md) §"Re-skin smell: Swift-v2_Text shim + foreign cshtml" — the same root cause
  (template-path override hiding hardcoded content behind a generic Text item).
