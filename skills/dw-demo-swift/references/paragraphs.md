# paragraphs.md

## Contents

- [Writing paragraph fields via the Management API (Swift 2.4 / DW 10.28.x)](#writing-paragraph-fields-via-the-management-api-swift-24--dw-1028x)
- [Reading paragraphs — the parameter is `Id`, and neither read verb is complete](#reading-paragraphs--the-parameter-is-id-and-neither-read-verb-is-complete)
- [Creating a paragraph — the two-step, the 1-based column, and the writable template twin](#creating-a-paragraph--the-two-step-the-1-based-column-and-the-writable-template-twin)
- [`Swift-v2_Accordion`: the items ARE writable — the write rides inside `ParagraphSave`](#swift-v2_accordion-the-items-are-writable--the-write-rides-inside-paragraphsave)
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

**The field KEY is `ContentItem|<itemType>|<group>|<field>`, and the GROUP segment is unvalidated — an
unknown group is dropped without an error.** This is the cheapest way to write a whole page of successful
no-ops: every save returns `status: ok` with the posted model echoed back, and not one field changes in the
database. The group names are not guessable from the field's purpose — Swift's `Swift-v2_Button` fields sit
in group `General`, not the intuitive `ButtonSettings`:

```
ContentItem|Swift-v2_Button|ButtonSettings|Label   -> 200, nothing written
ContentItem|Swift-v2_Button|General|Label          -> 200, written
```

**Harvest the group map from a LIVE paragraph of the same item type** (`GetParagraphById` returns
`contentItem.groups[].fields[]`) or from the type's XML, never from the field name — and re-read every
item-field write from the `ItemType_*` row, because an acknowledged key and a written key look identical
from the API side.

**`ButtonData` (`FirstButton` / `SecondButton`)** — `Dynamicweb.CoreUI.Editors.Selectors.ButtonData`,
three stacked traps:

- *Asymmetric round-trip — and the read shape is the failing write shape.* Write it as a real nested
  OBJECT (`{SelectedValue, Label, Link, LinkType, Style}`); it reads back from `GetParagraphById` as a
  JSON **string** (typeName `Dynamicweb.CoreUI.Editors.Selectors.ButtonData`, with embedded CRLF).
  Posting that string back — even byte-identical to what the read just returned — is **accepted and
  discarded**: `ParagraphSave` returns `200`, another field mutated in the same call round-trips
  perfectly, the response model looks correct, and the button field persists **NULL**. Only a real
  nested object binds. In PowerShell that means building a hashtable and letting
  `ConvertTo-Json -Depth 40` emit it as an object — a depth that truncates the object back to a string
  is the same failure wearing a different hat. Always write the full object.
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

- *The rule holds at every nesting level — including inside an item-list child's `ModelRawData`.* One level
  deeper the same string write looks ~80% successful: `Title`, `Text`, `Sort` and the sibling fields in the
  **same** `ModelRawData` persist while the button keeps its old value, which reads as "buttons aren't
  writable on children" rather than "the shape is wrong". Write the nested object there too.

> **Correction (supersedes earlier revisions of this file).** A `Label` on a LANGUAGE-VERSION paragraph was
> previously recorded as "not writable — silently restored from the master", with only `Link` round-tripping,
> and readers were told to record it as a known residual. **That reading was the string-shaped write
> failing**, not a language-layer restriction: `Link` is a bare-string field and survived, the object-shaped
> `Label` / `SelectedValue` did not. A translated CTA label **is** writable on a language paragraph through
> `ParagraphSave` — post the full nested object. Do not carry the residual forward.

Verify every ButtonData write against the RENDERED page (expected `href` + label present, old label
count dropped), never against the API re-read — a re-read proves storage, never effect.

**`SelectedImage` (poster / image `Image` field, `Swift-v2_Feature.Icon`, any `FileEditor`-backed
selector) — read-only through `ParagraphSave`, and DESTRUCTIVE on a wrong-shaped write.**
`Dynamicweb.CoreUI.Editors.Selectors.SelectedImage` does **not** persist through `ParagraphSave`:
setting the projected field `.value` is ignored (the top-level paragraph `image` / `imageUrl` are
null on Swift item posters, because the value is stored via the selector), so the field keeps
whatever a `GridRowCopy` brought in, while sibling `Title` / `Text` / `Eyebrow` / `AltText` on the
same item persist normally. The round-trip is **asymmetric, and the asymmetry is a trap**:

- A **string** value is discarded and the prior value is retained — a harmless-looking no-op that reads
  as "the save didn't take".
- A **non-string** value (any object) is **accepted and stored as empty**. From then on string writes are
  still discarded, so the field is stuck empty and **no subsequent `ParagraphSave` can restore it** —
  measured across the bare filename, the `Files/`-relative path, the `/Files/`-absolute path and several
  object shapes, all reading back `""` every time.

Two rules follow. **(1) Treat every `SelectedImage`-typed field as read-only through `ParagraphSave`** —
the proven route for paragraph imagery is an inline `<figure><img src="/Files/..."
style="width:100%;max-height:70vh;object-fit:cover"></figure>` in a Text field (height-capped under the
85vh band limit), which renders live on the next request with no recycle. Treat that as a recorded
exception, not a default — see [content-modeling.md](content-modeling.md) §"The escape hatch, and its
cost". **(2) NEVER probe write shapes against a `SelectedImage` field on live content.** The failure mode
is destructive and irreversible, so one exploratory payload permanently empties a field a demo is showing:
probe on an expendable paragraph or not at all. Worth a guard in the shared save helper that refuses to
write any field whose `typeName` is `SelectedImage` unless explicitly forced — assert the helper throws
when handed one, and that a round-trip save of a paragraph carrying an icon leaves the icon byte-identical.
(The **product/logo/favicon** binders are a different surface with a working object shape — `{Id, Name,
Ratio, FocalX, FocalY}`, `Id` carrying the path — see
[`catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md) §"Product images".
Do not carry that shape back to a paragraph item field on the strength of the shared type name.)

**Every item-field editor has its OWN write shape, and the four in play are mutually incompatible.**
The editors share one projected `field.value` slot, so a payload built for the wrong one is accepted by
the binder and fails downstream — at render, or not at all. Name-matching ("it's a media field, use the
image shape") is what produces each row's failure column. Read the editor's `typeName` off
`ItemFieldsByItemTypeSystemName` (or the type's XML) and pick the shape from it:

| Item field editor | Write shape through `ParagraphSave` | What the wrong shape does |
|---|---|---|
| `SelectedImage` (on the paragraph's OWN `contentItem`) | `{Id:"/Files/…", Name, Ratio, FocalX, FocalY}` — **`Id` carries the path**, `Path` is obsolete | a plain string is discarded; any object on a *list child* stores empty and is then unrecoverable (below) |
| `SelectedMedia` (video / media field) | `@{Path="/Files/Videos/<file>.mp4"}` — a **`Path`** object | a JSON **string** (including the one the read just returned) is accepted and discarded — `status: ok`, sibling plain-string fields in the same save persist, the media field keeps its old broken path; the `SelectedImage` `Id` shape fails or corrupts the field |
| `LinkEditor` | a **bare URL string**, e.g. `"/en-us/<page>"` | a `ButtonEditor` JSON envelope stores an unresolvable link → the consuming widget throws `Get page requires a page ID greater than zero` |
| `ButtonEditor` / `ButtonData` | the full JSON **object** `{SelectedValue, Label, Link, LinkType, Style}` | a bare label string throws `ConverterException` at render and replaces the section with an error block |

`Path` and `Id` are the same one-word difference as the asset verbs — the two media shapes are not
interchangeable in either direction, so probe on a disposable paragraph, never on live content.

**The family rule, stated once: for EVERY complex editor field the read shape is a quoted JSON STRING and the
write shape is a real nested OBJECT.** `SelectedImage`, `SelectedMedia` and `ButtonData` are three instances
of one asymmetry, and each was diagnosed separately because the read actively suggests the failing write. The
tell is always the same shape of evidence — `status: ok`, the response model echoing what you posted, plain
string fields in the *same* save persisting, and the one complex field unchanged or `NULL`. So: read the
field's `typeName`, pick the object shape from the table above, and **verify in the `ItemType_*` row or on the
rendered element (a media `src` that returns non-404, an anchor with the expected `href`) — never in the save
response**.

**A `SelectedImage` field inside a PROJECTED ITEM-LIST CHILD is not writable at all — the child carries
STRING fields only.** Distinct from the paragraph's own `contentItem` above, where the binder object does
work. A child's values ride in `ModelRawData`, which is a flat `string → string` map and cannot
structurally carry a binder object; the alternative structured channel (`RelationItem.Groups[].Fields[]`)
is not honoured for this field either. Four shapes were probed on a disposable slider card — all four
returned `status: ok`, all four read back `""` from the row, while `Title` / `Subtitle` / `Text` on the
**same** child in the **same** payload persisted every time:

```
ModelRawData Image = "/Files/Images/<brand>/<file>.jpg"           -> ""
ModelRawData Image = "{\"Id\":…,\"Name\":…,\"Ratio\":…,\"FocalX\":…,\"FocalY\":…}"  -> ""
ModelRawData Image = "/Images/<brand>/<file>.jpg"   (no /Files)   -> ""
RelationItem.Groups[].Fields[].Value = binder object / plain path -> "" for both
```

**Scope this to `SelectedImage`.** The "children carry STRING fields only" reading it first produced is too
broad: a `ButtonData` field on a child DOES bind when written as a real nested object inside the same
`ModelRawData` (above), so the flat-string-map inference was the probe's *shapes* failing, not the channel.
What stands is the measured fact — no shape reaches a child's `SelectedImage`.

So a card image inside a slider/accordion/repeater is **one click in the admin UI**, and saying so is the
honest answer. Do not design a data fix around it, do not overwrite the file at the old path to fake one
(the file is referenced by other surfaces), and do not escape to SQL — the write would be reverted by the
next `ParagraphSave` anyway ([sql-direct-seeding.md](sql-direct-seeding.md) §"Why an API write and a SQL
write are not equivalent").

**Posting an item-list array REPLACES the whole list — omitted children are DELETED, rows and all.** The
array in a `ParagraphSave` payload is authoritative, not a patch: children absent from it are deleted along
with their `ItemType_*` rows. A single-entry probe intended to test one field on a four-card slider destroyed
three cards and their backing rows; the survivor was the one card included in the test payload. There is no
undo — the recreated children come back with **new ids**.

**Never post a subset of an item list, not even to test one field.** Read the full list, mutate it in place,
post it back complete, and assert the child count is unchanged after any save that carries an item list. Pair
it with the language-layer rule below: a master-layer save re-mints the layers' children, so child ids must be
re-read after every save rather than cached
([language-layers.md](language-layers.md) §"A master-layer `ParagraphSave` writes THROUGH to the language
layers").

**One over-long field aborts every OTHER field on the same paragraph — and the error names the wrong field.**
The item row is written as a unit, so a single value exceeding its column width makes SQL reject the whole
row, and the failure is reported against the over-long column no matter which field you were writing. Three
perfectly valid writes to unrelated fields can all fail with a truncation error naming a field nobody was
touching, which is close to undiagnosable from the message alone.

The usual trigger is translation: translated copy is routinely longer than its English source, and short
`nvarchar(255)` fields (alt text, labels, short callouts) are where it lands first. **Length-check every
translated string against its target column width (`INFORMATION_SCHEMA.COLUMNS`) before posting a translation
batch**, and remember alt attributes are plain text — HTML entities only spend bytes against the limit
without rendering as anything.

**`ParagraphSave` silently BLANKS module settings it cannot round-trip — page-picker values are the known
class.** The save model omits settings the API has no representation for, and posting that model back
writes the omission as blank. One unrelated `ParagraphSave` on a sign-in module wiped three page-picker
settings with no error and no failed status; they had to be restored by hand from a diff. **Before any
`ParagraphSave` on a MODULE paragraph, snapshot the paragraph's settings, and diff them after the save** —
this is not covered by the standard "re-read the entity" check, because the re-read agrees with the model
you posted. Restore anything the diff shows missing in the same run.

**Hiding a paragraph: `showParagraph=false` is inert; the three `hideFor*` flags are the working motion.**
`ParagraphSave {showParagraph:false}` returns `status: ok`, reads back `showParagraph: True`, and the
paragraph keeps rendering — the field is not honoured through the headless save. Setting
`hideForDesktops` + `hideForTablets` + `hideForPhones` all `true` does take effect, and it is **better than
the `ParagraphDelete` workaround**: identical served-HTML outcome, fully reversible, and no orphaned grid
row to clean up afterwards. It is a **server-side** suppression, not a CSS hide — the markup is absent from
the delivered HTML, so content tripwires that grep served HTML do see the change. Verify with both halves:
all three flags read back `true`, **and** a string unique to that paragraph has zero occurrences in the
served page.

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

## Reading paragraphs — the parameter is `Id`, and neither read verb is complete

Both paragraph read verbs have failure modes that read as "the verb is dead" or "the work is done", and both
have written off real work.

**`GetParagraphById` takes `?Id=`, not `?ParagraphId=` — and a `400` has TWO meanings.** Two independent
workstreams concluded the verb had been removed in 10.28 and abandoned it. It had not:

```
GET GetParagraphById?ParagraphId=<id>   -> 400 Unable to load query parameters for query type: GetParagraphById
GET GetParagraphById?<ModelIdentifier>  -> 500 The input string Paragraph was not in a correct format
GET GetParagraphById?Id=<id>            -> 200 full contentItem.groups[].fields[] model
```

The first `400` is the wrong parameter NAME and reads as "verb unavailable". The second meaning is a
**soft-deleted row**: a paragraph that exists in the `Paragraph` table with `ParagraphDeleted=1` answers `400`
to a *correct* `?Id=` call, which reads as "paragraph not found". (This supersedes earlier notes recording the
`400` as simply paragraph-not-found, and the verb as dead.) **Any DB-driven content sweep must filter
`ParagraphDeleted` / `PageDeleted`** or it spends the run chasing ghosts it can never write.

**`GetParagraphsByPageId` silently OMITS paragraphs that exist and are visible.** It is not a complete
enumeration: on one pass three of twelve target paragraphs were absent from the listing while present in the
`Paragraph` table with `ParagraphShowParagraph=True` and `ParagraphDeleted=0` — including two carrying the
exact strings the run existed to remove. The save loop driven by the listing reported complete success and
left them untouched.

**Never let an API listing define the work set for a completeness-critical sweep.** Cross-check the listing
against SQL (`SELECT COUNT(*) FROM Paragraph WHERE ParagraphPageId=<id> AND ParagraphDeleted=0`) before
claiming coverage, and note that the fallback path — SQL plus a content-cache flush — is available here,
because content caches, unlike the user cache, are reachable. (Empty grid columns also come back as synthetic
`id=0` placeholders; filter to `id > 0` before counting anything.)

## Creating a paragraph — the two-step, the 1-based column, and the writable template twin

`ParagraphNew` + `ParagraphSave` does not produce a finished paragraph in one pass. Three independent
defects in the create path each end in the same place — a paragraph that saves, reads back correctly, and
**renders nothing** — so a create helper that checks only `status` and a re-read reports success on all
three.

**1. `gridRowColumn` is 1-based, and `ParagraphNew` returns `0`.** The Swift grid renderer indexes columns
from 1, so a paragraph left at the created default sits in a column the renderer never walks. It is not
dropped and not flagged: the save returns `200`, `GetParagraphById` returns the paragraph with all its
fields, and the served HTML simply does not contain it.

```
ParagraphNew                        -> gridRowColumn = 0
POST ParagraphSave (column left 0)  -> 200, present in GetParagraphById, ABSENT from rendered HTML
POST ParagraphSave  gridRowColumn=1 -> renders
```

**Set `gridRowColumn` explicitly to a 1-based index on every create**, and assert the paragraph's own text
appears in a live GET — no API surface distinguishes column 0 from column 1.

**2. Item field values do NOT bind on create — a second `ParagraphSave` is required.** The create path
ignores the item-field values in the payload; they bind only on a subsequent save of the now-existing
paragraph. A required field therefore lands empty even though it was in the create body, which on a widget
paragraph means the widget throws before it renders. Where the *required* flag blocks the create outright,
the working sequence is: `ItemFieldSave` to toggle `required` off → create the paragraph → set the value on
a **second** `ParagraphSave` → `ItemFieldSave` to restore `required`. Assert the value after the second
save, never after the create.

**3. `template` is read-only; `layout` is the writable twin, and DW mirrors it into `template`.** A
`ParagraphSave` carrying `template=<file>.cshtml` is rejected or ignored — the API exposes `template` as a
read surface only. Write the `layout` property instead, then read `template` back to confirm the mirror
landed. The same pair appears on the page save model. (This is why the repeater payload above sets
`Layout`, not the `template` a reader would expect.)

**A field you never set is not a field that renders nothing — `Swift-v2_Text` ships a lorem default on
`Subtitle`.** The item type declares a placeholder default value, so a paragraph created and populated
normally renders lorem ipsum under its heading on the live page, from a field the author never opened. It
is not a leftover from seed content and it survives every save that does not name the field. **Blank
`Subtitle` explicitly on every `Swift-v2_Text` create** (the same discipline as trap 2 above: name the
field, do not rely on what the create path leaves behind), and keep the content tripwire that flags
placeholder prose pointed at the rendered page — this is exactly the state it exists to catch
([`../../dw-demo-base/references/visual-qa.md`](../../dw-demo-base/references/visual-qa.md), and note the
stock filler is verb-opener ipsum containing no "lorem" at all). An edition should strip the defaults from
the shipped type rather than leaving every build to blank them.

## `Swift-v2_Accordion`: the items ARE writable — the write rides inside `ParagraphSave`

> **Correction.** Earlier revisions of this file stated the Accordion's items were unreachable from the
> Admin API and prescribed hand-authored Bootstrap `.accordion` markup pasted into a `Swift-v2_Text`
> field. **That workaround is retired — it was itself the defect** (an owner review rejected exactly it:
> raw HTML and styling in a text field where a Swift item type with styling on top belongs). Do not
> reach for it, and if you find it on an existing demo, migrate it.

The Accordion's content lives in `Accordion_Items`, an item LIST — the same storage shape as
`Swift-v2_Slider`'s slides, and the same edit path:
[`content-modelling.md`](../../dw-demo-base/references/foundational/content-modelling.md) §"How repeater
children are stored — and the Management API edit path" is canonical. The accordion-specific bindings:

- **Parent list field** — `ContentItem|Swift-v2_Accordion|General|Accordion_Items`, an ARRAY of child entries.
- **Child item type** — `Swift-v2_Accordion_Item`.
- **Child fields** (group `General`) — `Icon`, `Title`, `Text`, keyed as
  `RelationItem|Swift-v2_Accordion_Item|General|<Field>` inside `ModelRawData`.

```jsonc
POST /Admin/Api/ParagraphSave?Query.Type=GetParagraphById
{ "QueryData": { "Id": <paragraphId> },
  "model": { "ItemType": "Swift-v2_Accordion",
    "ContentItem|Swift-v2_Accordion|General|Accordion_Items": [
      { "ItemId": "",                       // "" creates; an existing id edits in place
        "ItemType": "Swift-v2_Accordion_Item",
        "Label": "<child label>",
        "ContentInfo": { "AreaId": <areaId>, "PageId": <pageId>, "GridRowId": <rowId>, "ParagraphId": <paragraphId> },
        "RelationItem": { "Groups": [] },   // the UI sends this empty — values live in ModelRawData
        "ModelRawData": "{\"RelationItem|Swift-v2_Accordion_Item|General|Icon\":\"\",\"RelationItem|Swift-v2_Accordion_Item|General|Title\":\"<title>\",\"RelationItem|Swift-v2_Accordion_Item|General|Text\":\"<p>…</p>\"}" } ] } }
```

DW mints the `ItemList` and wires the relation for you — on a fresh Accordion the parent's
`Accordion_Items` pointer transitions `'0'` → a non-zero list id — and the storefront renders it on the
next GET with **no recycle**. Verify per
[`content-modelling.md`](../../dw-demo-base/references/foundational/content-modelling.md) §"Verifying a
repeater-child write": the `ParagraphSave` response and `GetParagraphById` **cannot** decide it — the
response is a verbatim echo of what you posted (including values that did not persist) and the parent's
`Items` field is a constant list id on any accordion that already has items. **The verification is the
child's field values in a live GET of the rendered page, full stop.** The `'0'` → non-zero pointer mint is
a create-only convenience: it is real on a fresh Accordion and structurally unavailable on the far more
common case of editing an item in a list that already exists, so never gate a helper on it.
The child-field group is `General` and the field names are confirmed against
`Files/System/Items/ItemType_Swift-v2_Accordion.xml` + `ItemType_Swift-v2_Accordion_Item.xml` — read the
XML rather than guessing when adapting this to another repeater.

**Why the wrong belief survived so long, and the general rule it teaches.** The brute-force that produced
it was *correct*: there is no `ItemEntry*` / `ItemList*` / `ItemEntrySave` verb, and there still is not.
The inference was wrong. The write is not its own verb — it rides inside `ParagraphSave` as an array on
the parent's projected list field, so **a verb-registry probe can never find it.** A negative registry
result proves a VERB absent, never a CAPABILITY absent; the general form of that rule lives in
[`../../dw-demo-base/references/surface-priority.md`](../../dw-demo-base/references/surface-priority.md).

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
  [dw-demo-pim/references/governance.md](../../dw-demo-pim/references/governance.md).

These callouts generalise into the component-first gate (enumerate the standard component, configure it,
override only as a last resort) owned by
[`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §1.
