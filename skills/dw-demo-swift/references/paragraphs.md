# paragraphs.md

## Contents

- [Writing paragraph fields via the Management API (Swift 2.4 / DW 10.28.x)](#writing-paragraph-fields-via-the-management-api-swift-24--dw-1028x)
- [`Swift-v2_Accordion`: its items may be unreachable from the API](#swift-v2_accordion-its-items-may-be-unreachable-from-the-api)
- [Where to find a paragraph's wiring (read-only baseline inspection)](#where-to-find-a-paragraphs-wiring-read-only-baseline-inspection)
- ["Don't customise this paragraph" callouts](#dont-customise-this-paragraph-callouts)

> Swift 2.2 paragraph guardrails for demos. Source-of-truth: paragraphs are exposed in admin UI under each page; backing definitions live in `wwwroot/Files/Templates/Paragraph/` (built-in — read-only) and the page-preset YAML at `<demo-root>\distribution\layers\base\replace\_content\Swift 2\<area>\<page>\<grid-row>\paragraph-*.yml`.
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

The vendor-generic paragraph survey (component-first gate, paragraph categories, item-field
configuration, the cache pitfalls) has been folded up into the foundational candidates. What stays
here is the demo guardrail: the paragraph types you must NOT replace.

| If you need… | Read |
|---|---|
| Component-first gate (map a requirement to a standard `Swift-v2_*` component before customising); paragraph categories; configuring paragraph item-type fields (PDP enrichment, `FieldDisplayGroups`/`SelectedGroups`, `EcomFieldDisplayGroups` cache, aspect-ratio token, `Swift-v2_Row` knobs, `ProductDetailRenderGrid` sourcing) | [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §1, §3 |
| Empty-`ParagraphTemplate` resolves to first cshtml alphabetically (silent hijack) + both mitigations | [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §4 |
| Grid-composition cache (host-restart for paragraph deletion) + `ProductListComponentSelector` `RenderGrid` cache (CSS-hide is the only lever) | [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §5 |
| ProductHeader **ProductViewModel field inventory** (`ManufacturerName` not `Manufacturer.Name`; what's available vs what only looks like it is) | [`render-viewmodels.md`](../../dw-demo-base/references/foundational/render-viewmodels.md) |
| SQL-direct Paragraph INSERT required columns | [`sql-direct-seeding.md`](sql-direct-seeding.md) |

## Writing paragraph fields via the Management API (Swift 2.4 / DW 10.28.x)

`ParagraphSave` is the write verb behind every Visual-Editor field edit, but the projected
`contentItem` fields do not all behave alike. Plain text / HTML fields persist exactly as posted;
several editor types have their own binding contract, and each of the traps below fails **silently**
— the save returns success and the re-read looks plausible.

**`ButtonData` (`FirstButton` / `SecondButton`)** — `Dynamicweb.CoreUI.Editors.Selectors.ButtonData`,
three stacked traps:

- *Asymmetric round-trip.* Write it as an OBJECT (`{SelectedValue, Label, Link, LinkType, Style}`);
  it reads back from `GetParagraphById` as a JSON **string** (with embedded CRLF). Parse the value
  before inspecting it — a read-modify-write that expects an object gets nulls and then either
  blanks the button or hard-codes a `Style` it should have inherited. Always write the full object.
- *An empty string is a no-op.* Posting `""` (or the round-tripped JSON string) fails server-side
  model binding; the field keeps its prior value and no error is returned. **Clear a button by
  posting an object with blank members**: `{SelectedValue:"", Label:"", Link:"", LinkType:"page",
  Style:"primary"}`.
- *It renders from `Link`, not `SelectedValue`.* The Swift button partial emits the `Link` member
  verbatim and treats `SelectedValue` as admin-picker metadata only. An object with `SelectedValue`
  set and `Link` empty saves, reads back with the id intact, and renders **zero** anchors —
  indistinguishable from a silent save failure. Populate BOTH. `LinkType` `page` and `product` are
  both confirmed working; `Style: "link"` is in the stock vocabulary and renders
  `class="btn btn-link" data-dw-button="link"`.

Verify every ButtonData write against the RENDERED page (expected `href` + label present, old label
count dropped), never against the API re-read — a re-read proves storage, never effect.

**`SelectedImage` (poster / image paragraph `Image` field)** —
`Dynamicweb.CoreUI.Editors.Selectors.SelectedImage` does **not** persist through `ParagraphSave`:
setting the projected field `.value` is ignored (the top-level paragraph `image` / `imageUrl` are
null on Swift item posters, because the value is stored via the selector), so the field keeps
whatever a `GridRowCopy` brought in, while sibling `Title` / `Text` / `Eyebrow` / `AltText` on the
same item persist normally. When the picker is not reachable, place the image as markup in a Text
field instead — `<figure><img src="/Files/..." style="width:100%;max-height:70vh;object-fit:cover">
</figure>` (height-capped under the 85vh band limit) renders live on the next request with no
recycle. Treat that as a recorded exception, not a default — see
[content-modeling.md](content-modeling.md) §"The escape hatch, and its cost".

**List fields (e.g. `FieldDisplayGroups`)** — `GetParagraphById` returns the value as a comma-joined
STRING (`"specs_a,specs_b"`), while `ParagraphSave` persists whatever it is given as a JSON ARRAY. A
read-modify-write therefore stores `["specs_a,specs_b"]`, and a second cycle stores
`["[\"specs_a,specs_b\"]"]`. A single wrap already matches no display group and the renderer fails
silently — the PDP Specifications accordion emits
`<div class="accordion accordion-flush w-100" id="Specifications_<id>"></div>` with no children, a
correct-looking empty shell. Re-set every list field explicitly as an ARRAY of names on **every**
save (including saves that only touch unrelated fields, e.g. spacing), and throw if the read-back is
not an array of names.

**`Height` on `Swift-v2_Poster`** — a `BoxedRadioEditor` over `System.String` with no server-side
range validation. Only `1|2|3|4` (= 15/35/55/85vh) match a `[data-swift-poster-height]` rule; any
other value silently falls back to the 15vh default with no error, and a global theme vh-cap can
mask the collapse entirely. Assert `Height ∈ {1,2,3,4}` rather than trusting the save.

**The paragraph `name` is overwritten from `Title`.** On save DW re-derives `name` from the `Title`
item field with tags stripped and concatenated, discarding whatever `name` the model carried. The
standard recipe creates the paragraph (setting `name`) and writes the item fields (setting `Title`)
in two separate `ParagraphSave` calls, so a check straight after create sees the intended name and
is reassured — the second call replaces it. Key idempotency, resume and revert logic on the
paragraph **ID** captured at creation and recorded in the run ledger, never on the name; a
name-keyed re-run creates a duplicate instead of updating. If a name lookup is unavoidable, derive
the expected name the way DW does (strip tags from `Title`, concatenate). `PageSave` has the same
Title-derives-name behaviour, with worse blast radius — see
[admin-ui-authoring.md](admin-ui-authoring.md).

**Empty grid columns come back as `id=0` placeholders.** `GetParagraphsByPageId` emits a synthetic
object per EMPTY grid column — `id=0`, `itemType=null`, `name` set to the column number. It is the
API describing an empty slot, not a paragraph. So the standard "`GridRowCopy` an existing row, then
delete the clone to empty it" recipe looks like it failed: after a successful `ParagraphDelete` the
listing still returns an object for that row, and a script that verifies its own delete aborts a run
that in fact worked. Filter to real paragraphs (`id > 0`) before counting emptiness.

## `Swift-v2_Accordion`: its items may be unreachable from the API

The Accordion paragraph's content lives in `Accordion_Items`, an item LIST. On DW 10.28.x hosts the
Admin API exposes **no item-list read or write verb** — brute-forcing both verb registries returns
schema verbs only (`GetItemType` / item-type field metadata); no `ItemEntry*` / `ItemList*` verb
exists. With no way to add items the paragraph renders ZERO DOM, which reads as a styling or
visibility bug and is not one.

Workaround: author Bootstrap 5 `.accordion` markup directly into a `Swift-v2_Text` paragraph's
`Text` field — `bootstrap.bundle.min.js` is loaded sitewide, so Collapse works with no new JS. Leave
the first panel open deliberately: collapsed panels drop out of `innerText`, so a copy/placeholder
scan sees LESS text after the change and at least one answer must stay visible to it. Verify
behaviourally (click each header, assert the target panel's `.show` class flips and its height
changes) — a collapsed-only snapshot cannot tell working markup from dead markup.

To hide the now-dead Accordion paragraph: `showParagraph=false` is **silently ignored** via the
Management API, but `hideForDesktops` / `hideForTablets` / `hideForPhones = true` do take effect.
Assert the hidden paragraph contributes 0 rendered height.

## Where to find a paragraph's wiring (read-only baseline inspection)

To trace what a specific paragraph does on a Swift 2.2 page: note the page in admin (e.g.
`Customer center/CSR/Orders`); the corresponding YAML lives at
`<demo-root>\distribution\layers\base\replace\_content\Swift 2\Customer center\CSR\Orders\grid-row-1\paragraph-c1-1.yml`;
the YAML's `Type` field names the paragraph definition and the rest carries its configured properties.
This is read-only inspection — you don't edit the downloaded baseline YAML; you edit paragraph properties via the
Admin UI Visual Editor on the live host (which writes to the host's project DB, not back to the baseline copy).

## "Don't customise this paragraph" callouts

A few paragraph types are stock-load-bearing for typical B2B-distributor demo differentiators
(sales-on-behalf, mixed-source orders, complex pricing) and must NEVER be replaced with custom Razor:

- **Customer center / CSR / Orders paragraph** — the stock paragraph already supports impersonation +
  mixed-source order viewing + the `OrderSource` discriminator badge; rebuilding loses that wiring. See
  [customer-center.md](customer-center.md).
- **Cart summary / Checkout step paragraphs** — high regression risk; touching these triggers the
  customisations-ledger preflight in base. See [re-skin.md](re-skin.md) "What NOT to touch".
- **Product detail paragraph** — relies on the Lucene index + the PIM completeness rules; modifying it
  can mask "rules don't show" symptoms. See
  [dynamicweb-pim-demo/references/governance.md](../../dw-demo-pim/references/governance.md).

These callouts generalise into the component-first gate (enumerate the standard component, configure it,
override only as a last resort) owned by
[`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §1.
