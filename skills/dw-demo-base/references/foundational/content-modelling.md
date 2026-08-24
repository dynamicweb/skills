# Foundational candidate → dw-content-modelling

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 content-modelling knowledge — editor-manageable
> page modelling, the custom item-type `<Prefix>_*` discipline, and content-side language layers —
> staged here for a future fold-up into `dw-content-modelling`. No demo/customer content. When
> folded, move this body into `dw-content-modelling` and re-target the pointers in the demo skills.
> Until then, the demo skills reference this file.

## Contents

- [1. Editor-manageable pages, not HTML blobs](#1-editor-manageable-pages-not-html-blobs)
- [2. Custom item types — the `<Prefix>_*` discipline](#2-custom-item-types--the-prefix_-discipline)
- [3. Content-side language layers](#3-content-side-language-layers)

## 1. Editor-manageable pages, not HTML blobs

> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

**The rule: model one paragraph (or field) per editor concern; rich-text fields carry prose only.**
The moment a `class=` attribute, a `<div>`, or a structural `<img>` is needed inside a rich-text
field, that is the signal to model a field or an item type instead — see the escalation mechanics in
[`swift-building.md`](swift-building.md) ("separate the styling from the content") and the custom
item-type discipline in §2 below.

### Why this matters

A page built as a single rich-text paragraph holding a hand-authored HTML blob (inline hero `<img>`,
custom-class `<blockquote>`, hand-built key-figures `<div>` grid, raw `<h2>` inside a `Title` field)
LOOKS right but:

- An editor cannot swap the hero image (no file picker — it's markup), reword a pull-quote, or change
  one stat without editing HTML in the RTE. The first WYSIWYG touch destroys the class-bearing
  structure.
- CSS accumulates only to style content-embedded classes, including dead rules no content uses. Dead
  CSS is undetectable when the markup lives in database rows instead of a template.
- A list page has to scrape "the first paragraph image on each child page" to build cards, because
  the detail pages have no modeled hero-image field.
- Page-ID-scoped CSS (`body[data-dw-page-id="42"] … {}`, repeated per page) is needed to undo a
  global rule — so every future page requires a developer to edit CSS.

The page becomes a developer artifact, not content. Under time pressure, "one Text paragraph + HTML
+ CSS" is genuinely the fastest way to make a page look right — which is why the rule has to be
enforced at build time, not discovered at audit time.

### The discipline

1. **Decompose by editor concern, not by visual block.** An article page is: hero image + title +
   body prose + pull-quote + key figures + byline. Each concern is a field or its own paragraph —
   never spans inside one rich-text blob.
2. **Rich-text fields contain only tags the WYSIWYG itself produces** (`p`, `strong`, `em`, `ul`,
   `a`, plain `blockquote`). No `class=`, no `<div>`, no `style=` (the inline-`style` RTE-hostility
   case is covered in [`swift-building.md`](swift-building.md)).
3. **Images go in image fields** (`ParagraphImage` or an item image field) so editors get the file
   picker and templates get `/Admin/Public/GetImage.ashx` resizing/format conversion for free. Never
   `<img>` inside rich text for structural images (hero, card, avatar). Inline images are acceptable
   only as true in-prose illustrations.
4. **Title/Header fields are plain text.** Markup belongs to the layout template
   (`<h2 class="dw-h2">@Model.Item.GetString("Title")</h2>`), not the data. (Known OOTB exception: a
   few stock Swift items — MiniCart/Favorites header titles — ship HTML fragments in `Title`;
   preserve those wrappers, don't imitate them.)
5. **Structured repeating content (stats, tiers, bylines) = a custom item type** with typed fields,
   rendered by its own content layout (§2). The CSS then targets classes the TEMPLATE emits, so
   markup and style live in one reviewable file — and unused CSS becomes detectable again.
6. **No page-ID-scoped CSS.** A selector containing a page ID breaks silently on page copy/re-seed
   and turns content scaling into developer work. If one page family needs a layout variant, give it
   its own content layout or an item-driven modifier class.
7. **List pages read modeled fields, not scraped markup.** Card image = the child page's image
   field; teaser = the page description or a teaser field. If a list template must parse child pages'
   paragraphs to find an image, the detail pages are mismodeled — fix the model, not the scraper.
8. **Watch for stacking debris.** Iterating on a hand-built page tends to leave superseded paragraphs
   in the same grid row/column slot, where DW10's one-paragraph-per-(row,column) rendering hides all
   but one — invisible on the storefront, confusing in the editor. Delete what you replace.

### The gate — before calling a designed page done

Open the paragraph(s) in the DW editor and ask: **"could a content editor change the image, reword
the quote, and edit one stat — without seeing HTML?"** If no, remodel before moving on. Run this per
designed page, not once per demo.

## 2. Custom item types — the `<Prefix>_*` discipline

When a paragraph block needs editor-configurable fields that aren't on the stock item types, create a
**new item type** with a project prefix (`<Prefix>_PointsDashboard`, `<Prefix>_RebateTracker`) — not
"another `Swift-v2_Text` variant". This explicitly forbids the "generic-item-type shim + foreign
cshtml" pattern.

### What this looks like in practice

**Dropping the XML makes the type fully READABLE but never WRITABLE until a FIELD is saved — and no
restart will ever fix it.** Three independent subsystems are involved and the file only reaches one of
them:

- The item-type **metadata** provider parses the XML **on demand**, which is why every read verb works
  immediately — `ItemTypeById` returns the type with its `displayName`, category and `fieldsCount`, and
  `ItemFieldsByItemTypeSystemName` returns every field with its editor and static options. **No restart is
  needed for discovery** — the restart the old recipe prescribed is not even the thing that made reads
  work.
- The item-type **schema** — the `ItemType_<SystemName>` SQL table that stores the field values — is
  materialised by **`ItemFieldSave`**. The first field save is what issues the DDL. Neither the file drop,
  nor host startup, nor `ItemTypeSave` on its own puts the table on disk: `ItemTypeSave` registers the type,
  and a registered type with no saved field still has no table.
- **Activation REWRITES the XML file in place**, so the process identity running the host (the app-pool
  account on IIS) needs a **write ACE on `Files\System\Items\**`**. Without it, activation fails **silently**
  — the command answers, no table appears, and the only trace is a line in
  `Files/System/Log/items/ActivationWorkflow`. One such denial sat unnoticed for weeks, breaking every write
  to a single `ItemType_<Prefix>_<Concept>.xml` while every read of it looked perfect.

So an XML-only deployment produces a type that is fully introspectable and completely unwritable: a
`ParagraphSave` of that type returns **HTTP 500 `Invalid object name 'ItemType_<Prefix>_<Concept>'`**.
`ItemTypeHealthAll` has no row for an XML-dropped type (health only compares types it already knows have
schema), `ItemTypeListReload` returns `ok` and changes nothing, and repeated sanctioned recycles change
nothing. `ItemTypeSave` will not adopt the orphan either — it is create-only and returns **HTTP 400 "System
name is used already."** while the XML owns the name. **That 400 is the file owning the name, not an error
to debug** — and it is not a deadlock, because the command that actually creates the table is
`ItemFieldSave`, which does not care who owns the name.

**Route A — the XML is already on disk (the drop-and-activate path).** Cheapest, and the one that keeps
your authored XML as authored:

1. **Grant the host's process identity write on `Files\System\Items\**`** — activation cannot complete
   without it, and its absence is silent. Confirm by tailing `Files/System/Log/items/ActivationWorkflow`
   across the next step.
2. `GET ItemFieldNew?ItemTypeSystemName=<name>&ItemFieldGroupSystemName=General` → per field →
   `POST ItemFieldSave {Model}` — **this materialises the `ItemType_<SystemName>` table and its columns.**
3. **Verify with a REAL WRITE** (create and delete a throwaway paragraph of the type).

**Route B — no XML yet, author the type through the API.** **Child type before parent**, so the parent's
`ItemRelationListEditor` can reference it, and **zero recycles**:

1. `GET ItemTypeNew?Category=<category>` → set `systemName` / `name` / `enabledFor` / `restrictions` on
   the returned model → `POST ItemTypeSave {Model}` — this **registers** the type. (If the name is already
   owned by a dropped XML, this returns the 400 above; switch to Route A rather than deleting the file.)
2. `GET ItemFieldNew?…` → `POST ItemFieldSave {Model}` per field — **this creates the table and the
   columns.**
3. Re-upload the **authored** XML — `Files\System\Items\<Prefix>\<Prefix>_<ConceptName>.xml`, same shape
   as the stock `Swift-v2_*.xml` files, `Swift-v2_Text.xml` as the starting template — over DW's generated
   one. Metadata only; the table already exists and the column names are the field `systemName`s, which
   are unchanged. This restores the restriction rules, the layout groups and any deliberately-empty
   defaults. Same write-ACE requirement as Route A.
4. **Verify with a REAL WRITE.**
5. Place the layout at
   `Templates\Designs\Swift-v2\Paragraph\<Prefix>\<Prefix>_<ConceptName>\<Prefix>_<ConceptName>.cshtml`.
   The type is then a new "Add paragraph" picker entry in the Visual Editor under your project's category,
   and the storefront renders it on the next GET.

`POST ItemTypeDelete {SystemName, DeletePages:false}` frees the name **and** removes the XML — it is the
reset lever when a type is genuinely mis-authored, not a required step on the way to a working table.

**The editor you pick becomes a column type — a `TextEditor` field materialises as `nvarchar(255)`.**
`ItemFieldSave` issues the DDL from the editor, and a value longer than the column is a **hard error, not
a truncation**: a 259-character alt text bounced the whole `ParagraphSave` with a **500**, while 250
characters landed. Nothing in the field definition surfaces the limit. Choose `TextArea` / `RichText` for
anything that can grow (descriptions, alt text, any authored prose) and keep `TextEditor` for values you
can guarantee ≤ 255 — and note that the choice is baked at field-create time, so changing it later is the
create-alongside-and-migrate motion ([`pim-modelling.md`](../../../dw-pim-modelling/references/structural-model.md) §2.8), not an edit.

**A successful `ItemTypeById` / `ItemFieldsByItemTypeSystemName` read is NOT evidence the type is
usable** — it is exactly the state an XML-only deployment produces. Any new-item-type helper must gate on
a real write and must refuse to report success on metadata reads alone; make it re-runnable so a second
run reports "already writable — nothing to do", record the before/after writable state per type, and read
`Files/System/Log/items/ActivationWorkflow` on any failure before theorising. Rejected escapes:
hand-writing the `CREATE TABLE` in SQL (leaves DW's own metadata/schema bookkeeping out of the loop) and
rotating `changeversion.txt` for a "harder" restart (that file is the host's release-ring pin, not a
restart lever — [`../db-update-recovery.md`](../db-update-recovery.md) — and a restart is not the missing
ingredient in the first place).

### Repeater fields

When a block has N repeating children (tiers, rules, list items), create both:
- `<Prefix>_<Concept>.xml` (the parent) with an `ItemRelationListEditor` field
- `<Prefix>_<Concept>_<Child>.xml` (the sub-item)

Reference: stock `Swift-v2_Accordion.xml` + `Swift-v2_Accordion_Item.xml`. **Give repeater children
numeric item ids** when seeding — string ids are the natural hand-seeding choice and the one that
breaks every future AreaCopy (§3 "What a full-content AreaCopy does NOT carry").

#### How repeater children are stored — and the Management API edit path

A repeater's children (e.g. `Swift-v2_Slider` slides, accordion items) live in
`ItemType_<Prefix>_<Concept>_<Child>` rows, joined to the parent through an `ItemList` +
`ItemListRelation`. `GetParagraphById` returns the parent's `contentItem` with the repeater **collapsed**
to a single scalar — the `Items` field holds the `ItemList` id, not the expanded children. That collapse
is a read-shape detail, **not** a dead end: the children are edited through the Management API like any
other paragraph item content. The admin Visual Editor's slide editor is a SPA client of `/Admin/Api`, and
its save is a plain HTTP call you can capture and replay (surface-priority rule: "no operation exists only
in the UI" — [`../surface-priority.md`](../surface-priority.md)). **This was proven end-to-end against a
Swift 2.4 `Swift-v2_Slider` on DW 10.28.1: a headless `POST /Admin/Api/ParagraphSave` created a slide and
then edited it in place — no SQL, no recycle — and the storefront rendered the change on the next GET.**

The edit path — `POST /Admin/Api/ParagraphSave?Query.Type=GetParagraphById` (Bearer token):

- The parent paragraph's list field is `ContentItem|<ParentItemType>|<Group>|<ListField>` — an **array of
  child entries** (for the slider: `ContentItem|Swift-v2_Slider|General|Items`). You send the full desired
  child set; DW reconciles the `ItemList` / `ItemListRelation` / child rows for you.
- Each child entry identifies itself by **`ItemId`**: an **empty string creates** a new child (DW assigns
  the id and wires the relation); an **existing id edits that child in place** (verified: the child count
  stayed constant and the row's fields changed — it is a true update, not a duplicate).
- The child's field values ride in **`ModelRawData`** — a JSON *string* whose keys are
  `RelationItem|<ChildItemType>|<Group>|<Field>` (e.g. `RelationItem|Swift-v2_Slider_Item|General|Title`,
  `|Subtitle`, `|Text`, `|Image`, `|Text_LinkEditor`, `|Button`). The sibling `RelationItem.Groups` array
  is sent **empty** by the UI — the values live in `ModelRawData`, so populate that.
- **`ModelRawData` is a flat `string → string` map, so a child carries STRING fields only.** Any field whose
  editor needs a binder OBJECT — `SelectedImage` above all — cannot be expressed here and is not writable on
  a child through the Admin API at any shape; the structured `RelationItem.Groups[].Fields[]` channel is not
  honoured for it either. The measured shapes and the honest fallback (one click in the admin UI) are in
  [`../../../dw-demo-swift/references/paragraphs.md`](../../../dw-demo-swift/references/paragraphs.md).
- A "button"/"link" field on a child (`Text_LinkEditor` / `Button`) is a **plain transparent JSON
  link-binder** — `{Label, Link, LinkType, Style}` — not an opaque encoded blob.
- **No recycle.** `ParagraphSave` runs DW's domain service, which invalidates the render cache; the slide
  renders on the next storefront GET. (MCP `set_item_field_values` on the child's `(itemType, itemId)` is
  the equivalent surface-1 path once the child exists.)

Minimal payload (edit the existing child `1`; use `"ItemId": ""` to create):

```jsonc
POST /Admin/Api/ParagraphSave?Query.Type=GetParagraphById
{
  "QueryData": { "Id": <paragraphId> },
  "model": {
    "ItemType": "Swift-v2_Slider",
    "Layout": "CardCoverNavInline.cshtml",
    "ContentItem|Swift-v2_Slider|General|Items": [
      {
        "ItemId": "1",                       // "" creates; an existing id edits in place
        "ItemType": "Swift-v2_Slider_Item",
        "Label": "<slide label>",
        "ContentInfo": { "AreaId": 3, "PageId": 153, "GridRowId": 185, "ParagraphId": <paragraphId> },
        "RelationItem": { "Groups": [] },
        "ModelRawData": "{\"RelationItem|Swift-v2_Slider_Item|General|Title\":\"<p>…</p>\", \"RelationItem|Swift-v2_Slider_Item|General|Text\":\"<p>…</p>\", \"RelationItem|Swift-v2_Slider_Item|General|Button\":null}"
      }
    ]
  }
}
```

- **Round-trip-verify — `ParagraphSave` is a lying-success surface for this shape.** A malformed child
  entry (e.g. field values missing from `ModelRawData`) still returns `status: ok` while creating nothing —
  and can reset the parent's `Items` list pointer to `0`, silently emptying the repeater. Confirm the edit
  through a second surface after every save — but **not** through either of the two obvious ones; see the
  next subsection. This is the same round-trip discipline the `ParagraphSave` item-field no-op carries
  (see "Saves that report success but silently drop a field" below and
  [`../surface-priority.md`](../surface-priority.md) "Silent no-ops").

#### Verifying a repeater-child write — the two surfaces that cannot decide it

**Neither the `ParagraphSave` response nor `GetParagraphById` can distinguish a successful child write
from no write at all.** Two individually-harmless projection details combine to make the natural
round-trip check unperformable, and the natural reading of both is the wrong one — one run came within a
step of concluding "`ParagraphSave` is a lying success on this payload" and abandoning a migration that
had in fact worked.

1. **The `ParagraphSave` RESPONSE echoes the model you POSTED**, not a re-read of what was persisted. A
   created child comes back with `"itemId": ""` exactly as it was sent, whether or not DW created a row.
   **An empty `itemId` in the response carries NO information** — it is not evidence of failure.
2. **`GetParagraphById` returns the parent with the repeater COLLAPSED to a scalar** — the field holds the
   `ItemList` id, not the children — so the child COUNT is not visible from there at all. On an
   **existing** list that pointer is a stable id: measured constant across create *and* delete of a child
   (`324` → `324` → `324`). The count never appears.

**The rule, stated once: an item-list child write is verified by the RENDERED PAGE, full stop.** The
list-pointer mint is a **create-only convenience**, not the general check — treat it as a nice-to-have on a
fresh parent and never as the verification a helper gates on:

- **(a) On a FRESH parent only, the list-pointer transition `0` → non-zero is observable** through
  `GetParagraphById`. DW mints the `ItemList` and wires the relation on the first successful child write.
- **(b) In every case — and the only check that generalises — assert the child's field values in a live GET
  of the rendered page.**

The asymmetry is what makes (a) a trap, and the far more common editorial case is the one it cannot serve:
**editing a child of a list that ALREADY EXISTS.** There the pointer is a constant, measured unchanged
across four separate `ParagraphSave` calls on one slider card, and unchanged across create *and* delete of a
child on another parent:

```
GET  /Admin/Api/GetParagraphById?Id=<paragraphId>
  -> contentItem.groups[0].fields[0] {name: "Items", value: 323}    # before all four saves
  -> …                               {name: "Items", value: 323}    # after all four saves
POST /Admin/Api/ParagraphSave?Query.Type=GetParagraphById
  -> {status: "ok", exception: null}   with model…Items.value echoing the posted ModelRawData VERBATIM —
                                       including field values that provably did NOT persist
```

That last clause is the sharp edge: the echo is not merely uninformative, it is **actively wrong** — it
reports values back to you that the row never took (see the `SelectedImage`-on-a-child case in
[`../../../dw-demo-swift/references/paragraphs.md`](../../../dw-demo-swift/references/paragraphs.md), where
`Title`/`Subtitle`/`Text` persist and `Image` does not, out of one payload that echoes all four). A
repeater-write helper should take the expected rendered string and perform the live GET itself, so a caller
cannot accidentally verify against the echo; log the echoed `itemId` alongside the verdict so the false
negative stays visible in the artefact rather than being re-derived next time. Do **not** answer this by
brute-forcing a child-row read verb (none exists — the write rides inside `ParagraphSave`, so no registry
probe can find one) or by escaping to SQL to read `ItemListRelation` joined to the child table: that is the
only surface that carries ground truth, and reaching for it re-establishes exactly the belief this section
retires.

Watch for red-herring empty tables — a concept can have a similarly-named `ItemType_<Prefix>_<Concept>`
(e.g. a `Card` table) that is empty because the real content lives in the `_Item`/`_<Child>` rows. Confirm
which table `ItemListRelation` points at before reasoning about the shape.

> Historical note: earlier revisions of this section claimed the child rows were "unreachable through the
> Management API — editable only by guarded SQL plus a recycle." That was wrong; the SQL-plus-recycle
> motion is retired. The storage shape above is correct and useful for understanding, but the **edit path is
> the API** — capture the UI's `/Admin/Api` call and replay it; if a payload seems impossible, file a
> learning rather than escaping to SQL.

### What to put where

1. **Editor copy** (labels, microcopy, hero copy, fineprint, CTA labels) → ALWAYS a field. Even
   one-off strings. Editors will want to change them.
2. **Data-shape transformations / math / lookups** → cshtml. Computing dial degrees, formatting
   currency, deriving "is unlocked" booleans → cshtml.
3. **Magic numbers** (threshold = 10000, windowDays = 90, maxChips = 8) → fields with sensible
   defaults. The default lives in the XML; the editor can override.

### Things to NEVER do

- ❌ **Repurpose a generic item type** (`Swift-v2_Text`) and attach a foreign cshtml. The editor sees
  `Title/Subtitle/Text/FirstButton/SecondButton`; the template ignores most of them and embeds the
  real fields as hardcoded strings.
- ❌ **One cshtml per "variant"** with hardcoded forks. Use a field with a multi-select / radio for
  the variant.
- ❌ **Bake category-aware copy into cshtml** with `.Contains("...")` chains. Put the category-aware
  copy on a `ProductGroup` field instead — see [`razor-surfaces-and-pitfalls.md`](../../../dw-render-razor/references/razor-surfaces-and-pitfalls.md) "Per-category
  behavior".

### Audit query

To list all paragraph templates that don't match `Swift-v2_*` and aren't in a project-prefixed
folder (a "shim" smell — refactor to a custom item type):

```powershell
Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2\Paragraph\Swift-v2_*\*" -Filter '*.cshtml' `
    | Where-Object { $_.Name -notlike 'Swift-v2_*' }
```

This is also grep #6 of the discipline audit grep-pack in [`swift-building.md`](swift-building.md).

## 3. Content-side language layers

> Content-side localization — adding a language layer to a website. Sister concern to the PIM/product
> side ([`pim-localization.md`](../../../dw-pim-localization/references/translation-mechanics.md)), which translates product names / descriptions
> / custom fields.

**TL;DR:** A language layer is a **sibling `Area` row** under the same Website, with
`AreaMasterAreaId` pointing back to the master area and `AreaCulture` / `AreaEcomLanguageId` set to
the new locale. Admin flow is Settings → Content → Websites → "+ New website Language" → pick the
master to copy from. All pages/paragraphs/grid-rows from the master are cloned at create-time; from
then on the Language Management settings decide whether subsequent master changes propagate. Frontend
switches between layers via the OOTB `Swift-v2_LanguageSelector` paragraph.

### The two-table mental model

| Side | Table | Identifier | Notes |
|------|-------|-----------|-------|
| Content | `Area` | int `AreaId`, sibling rows share `AreaMasterAreaId` | One `Area` row per language layer. Master has `AreaMasterAreaId=0` or NULL; siblings point back to it. |
| PIM | `EcomLanguages` | string `LanguageId` like `LANG1` | Separate identifier space; bridged via `Area.AreaEcomLanguageId`. |

The legacy `Languages` (content) table is empty in a fresh dw10-suite scaffold and can be ignored —
modern DW10 stores all language-layer state on the `Area` row itself.

### What gets created (admin UI)

Settings → Content → Websites → context menu → "+ New website Language" → pick master → name +
regional setting → Create. Backstage DW10 INSERTs an `Area` row (`AreaName`, `AreaCulture`,
`AreaMasterAreaId` = master's id, `AreaEcomLanguageId`/`AreaEcomCurrencyId`/`AreaEcomCountryCode`
inherited from master), then clones every Page/paragraph/grid-row under the master into the new Area.
Clones are created in whatever state the Language Management settings dictate.

### The eight Language Management knobs

Settings → Areas → Content → Language Management. Read but **don't change** during a build — defaults
are usually right. Each toggle controls cross-website propagation:

| Setting | What it does |
|---------|-------------|
| Unpublish new paragraphs and rows | New master paragraphs/rows → unpublished on layer (default ON) |
| Unpublish new pages | New master pages → unpublished on layer |
| Allow paragraph operations (create/copy/move/delete/sort) | Layer editors can structurally edit paragraphs (default OFF — translators only edit text) |
| Copy master changes to language versions if values are the same (Pages) | Copy edited master page value when the layer still held the old value; stops once a translator overrides |
| Copy master changes to language versions if values are the same (Paragraphs) | Same logic for paragraphs |
| Compare paragraphs as text | When detecting "same value," ignore HTML formatting differences |
| Make published / unpublished status independent of master | Master publish/unpublish does NOT cascade |

### Wiring the area to PIM language

After creating the layer, **change `Area.AreaEcomLanguageId`** to the matching PIM
`EcomLanguages.LanguageId`. Without this, the layer renders all product values in master language
even though the UI chrome is localized.

```sql
UPDATE Area SET
  AreaEcomLanguageId = N'<LANG2>',
  AreaEcomCurrencyId = N'<EUR>',          -- usually inherited; change for markets with different currency
  AreaEcomCountryCode = N'<NL>',          -- for default VAT/shipping region
  AreaActive = 1
WHERE AreaId = <newAreaId>;
```

PIM must have the matching `LANG2` row + the products translated to that LanguageId — see
[`pim-localization.md`](../../../dw-pim-localization/references/translation-mechanics.md).

### The Swift OOTB language switcher

`ItemType_Swift-v2_LanguageSelector` renders a list of all active sibling areas for the current
master. Fields (verify per DW version): `Label`, `Icon`, `ShowLanguageName`, `ShowLanguageCurrency`,
`HideLanguageFlag`, `LanguageNameFormat` ("Native"/"English"/"Code").

**Swift 2.4 ships the selector's Razor but NOT its item type — verify the type exists before planning
around the paragraph.** The 2.4 deserialize set omits `Swift-v2_LanguageSelector`: the template is present
under `Designs/Swift24`, there is no item-type XML and no backing table, and the paragraph therefore cannot
be placed at all. It is not a broken install and no restart produces it. Create the type through the
normal API route — `ItemTypeNew` → `ItemTypeSave` → `ItemFieldSave` per field (six fields for the shape
above), per §2 "Route B" — then place it on the header rows. An edition that promises a language selector
should carry the item type rather than leaving every build to re-derive this.

Add it to a header grid row,
set fields, restart the host (header grid composition is cached). Clicking an entry navigates to the
same page on the target sibling area via the clone metadata; if a sibling page doesn't exist, the
link falls back to the layer's frontpage.

**Alternative: a master-template toggle (cache-safe, brandable).** When the OOTB selector paragraph
is awkward (header grid is cached → restart per insert; every layer needs its own paragraph; or you
want a branded pill), a small comment-delimited block in `Swift-v2_Master.cshtml` just before
`@ContentPlaceholder()` does the same job with none of the content-cache friction (Razor recompiles
live). The sibling-page resolution is two asymmetric lookups:

```csharp
int target = 0;
if (Pageview.Area.ID == <masterAreaId>)
    // master → layer: find the clone whose MasterPageId points at the current page
    target = Dynamicweb.Content.Services.Pages.GetPageIDByMasterID(Pageview.Page.ID, <layerAreaId>);
else
    // layer → master: the clone carries the back-link directly
    target = Pageview.Page.MasterPageId != 0 ? Pageview.Page.MasterPageId : 0;
if (target == 0) { target = <counterpartAreaHomePageId>; }  // page only exists on one side
```

Emit `<a href="/Default.aspx?ID=@target" hreflang="...">` — DW's URL provider rewrites to the
friendly slug. For 3+ layers, resolve siblings via `Area.AreaMasterAreaId` instead of hardcoding ids.

### Creating the layer — surface order + host-config prereqs

A language layer is a multi-table CREATE (DW does ~95 page clones + paragraph/grid-row/
item-localization/sibling-link bookkeeping). The "Surface priority for CREATES" rule applies in full
— MCP first, then Management API, then admin UI, **never raw SQL `INSERT INTO Area`** (a SQL clone
produces a partially-cloned tree missing PDPs, sign-in, customer-center, and the sibling-page links).

**Host-config prereq — AreaCopy needs distributed transactions.** The AreaCopy opens a second SQL
connection inside a `TransactionScope`; without the host's distributed-transaction prereqs in place it
fails with `System.Transactions.TransactionException: The operation is not valid for the state of the
transaction` (the error LOOKS transactional but is environmental — fix the prereqs, don't change the
input shape). Those host-config prereqs are owned by [`setup-install.md`](setup-install.md): the
`Program.cs` `ImplicitDistributedTransactions = true` opt-in (§3.1), the MSDTC service +
inbound/outbound + firewall setup (§4), and the **net10-host caveat** where even a fully-configured
host can't promote to MSDTC and needs the `Enlist=false` connection-string workaround (§4.1). Verify
all of those before treating an AreaCopy `TransactionException` as a content problem.

**Management API (proven):** `POST /admin/api/AreaCopy` with body
`{"Model": {"SourceAreaId": <masterId>, "Name": "...", "Culture": "<culture>", "CopyPermissions":
true, "AsWebsite": false}}`. `AsWebsite=false` = language layer (sibling with `AreaMasterAreaId`
back-link). Returns `{status:"ok", modelIdentifier:"<newAreaId>"}`. Some 10.25.x builds instead
accept `Query.`-prefixed query-string params — try the JSON body first, fall back to query-string.
MCP `copy_area` is documented but observed broken ("Area was not copied") as of DW 10.25.6.

### What a full-content AreaCopy does NOT carry (validated DW 10.25.x)

A `StructureAndContent` copy that returns `status: ok` is **not** a complete clone. Four classes of
content silently don't make it — run this as a checklist immediately after every AreaCopy.

1. **Custom items with STRING-id repeater children are dropped (copier bug).** The copier remaps
   repeater children with an **unquoted** SQL CASE, so string item ids parse as column names and the
   INSERT dies with `Invalid column name '...'` (real exception only in the EventViewer log). The
   paragraph clone lands with `ParagraphItemType`/`ParagraphItemId` wiped — a stub that renders
   nothing. Numeric-id children clone fine. Detect:
   `SELECT p.ParagraphID, p.ParagraphPageID FROM Paragraph p JOIN Page pg ON pg.PageID =
   p.ParagraphPageID WHERE pg.PageAreaId = <layerAreaId> AND p.ParagraphItemType = '' AND
   p.ParagraphModuleSystemName = ''` — every row is a dropped item. Fix per stub: manual SQL clone of
   the `ItemList` + child rows + `ItemListRelation` + parent, then re-point the stub paragraph. A
   sanctioned SQL exception (MCP + Management API both proven broken for this shape). **Prevention:
   give repeater children numeric item ids.**
2. **SECURITY — permissions are NOT cloned, and `CopyPermissions: true` does not change that for
   frontend pages.** Anon-gates and role-gates on the Permission entity store silently don't apply to
   the layer, so **every protected page in the copy is public until you mirror the rows by hand** — an
   observed state is a customer-center dashboard served in full to an anonymous visitor on the layer
   while the master stayed correctly gated. `UnifiedPermission` rows are not cloned and the
   `CopyPermissions` flag is not the frontend-page-permission switch; nothing in the `status: ok`
   distinguishes the two. Probe **anonymously, per language, per protected URL** after every copy (the
   pass state is a redirect to the localised sign-in, not a 200) — demo-side checklist in
   [`../../../dw-demo-swift/references/language-layers.md`](../../../dw-demo-swift/references/language-layers.md).
   Mirror every master row onto the layer's sibling page id
   (`Page.PageMasterPageId` gives the mapping), then
   `POST /admin/api/CacheInformationRefresh {"CacheTypeName":"Dynamicweb.Security.Permissions.PermissionService"}`
   AND restart (the nav tree caches separately). See [`permission-layers.md`](../../../dw-users-permissions/references/permission-layers.md).
3. **Hardcoded page ids in template role-gates miss the clones.** A gate like
   `if (node.PageId == <dashboardId> && !isRole) continue;` stops working on the layer (the clone has
   its own id). Make it master-aware:
   ```csharp
   int MasterId(int id){ var p = Dynamicweb.Content.Services.Pages.GetPage(id); return (p!=null && p.MasterPageId>0)?p.MasterPageId:id; }
   if (MasterId(node.PageId) == <dashboardId> && !isRole) { continue; }
   ```
4. **Component selectors still point at the MASTER's component pages.** The clone of a
   `ProductComponentSelector` (and the slider's `ListComponentSource`) keeps the master's page id in
   `ComponentSource`; the layer's PDP renders master-language labels and both areas share one
   `RenderGrid` cache entry. Repoint the layer's selector items at the layer's own component-page
   clones via `set_item_field_values`. (The shared-cache mechanics live in
   [`swift-building.md`](swift-building.md) "ProductListComponentSelector".)

**Verification probe — enter through the shop route.** When probing the layer's PDP use
`/Default.aspx?ID=<layer-shop-page>&ProductID=X[&VariantID=Y]`. Hitting the PDP wrapper page id
directly renders without ecom product context — every product component returns null and the page
looks catastrophically broken when nothing is wrong.

### The three-layer translation cascade — localize all three

Swift v2 pulls user-visible strings from **three independent sources** — none cascades into the
others:

| Layer | What it contains | Where it lives |
|-------|------------------|----------------|
| **1. `Translations.xml`** | UI chrome strings called via `@Translate("...")` (Search here, Sign in, Add to cart…) | `Files/Templates/Designs/Swift-v2/Translations.xml`. Stock ships ~2170 keys with en-GB/da-DK/nb-NO/en-US/en-DK/nl-NL — no fr-FR, no de-DE. Adding a locale = bulk-inject `<translation culture="<locale>">` children. |
| **2. Per-clone Item `Title` fields** | Header chrome — `Swift-v2_MyAccount`, `_MiniCart`, `_Favorites` render their label from `Model.Item.GetString("Title")`, NOT `@Translate` | `ItemType_Swift-v2_<Type>` rows. The clone copies English `Title` into every layer's item row — each needs an UPDATE. Map header-page→item-id via `Paragraph.ParagraphItemId` filtered by `ParagraphPageId`. |
| **3. DB content** | Paragraphs, products, groups, page menu text | `ItemType_Swift-v2_Text`/`_Poster`/`_Feature` rows on layer page clones; `EcomProducts`/`EcomGroups` per `ProductLanguageId`; `Page.PageMenuText` |

Apply in order: (1) inject the locale into `Translations.xml` for visible keys (aim for ~80-150
chrome strings, the rest fall back to en-GB gracefully); (2) UPDATE cloned header `Title` fields
(MiniCart/Favorites store HTML fragments `<div class="dw-paragraph">…</div>` — preserve the wrapper);
(3) translate DB paragraphs/products/groups. Restart after editing `Translations.xml` (cached at
startup) and after touching header item rows (composition cache). Same depth-not-width rule as PIM:
localize the **demo path**, not the whole site.

**SQL files with non-ASCII characters — encoding pitfall.** `sqlcmd` defaults to the system codepage
(Windows-1252 on western Windows); a UTF-8 `.sql` file with multibyte characters gets mangled at
parse time and stored corrupted in NVARCHAR even though the literal is `N'...'` (symptom: an accented
character such as `é` renders as a two-character double-encoded mojibake sequence). Fix: skip the file — build the UPDATE statements in PowerShell (UTF-16 in memory) and pass
via `Invoke-Sqlcmd -Query`, or save the `.sql` as UTF-8-with-BOM (sqlcmd detects the BOM). The
PowerShell-inline approach is more robust (the BOM is easy to lose on re-save).

### Nav-tree leaks the master area on layers — `LocalizeLink` patch

DW10's `NavigationTreeViewModel` builds nav node `Link` values rooted at the **master area's Shop
page**, regardless of the requesting page's area. On a layer home page the header dropdown renders
`<a href="/<masterUrlName>/shop?GroupID=…">` — clicking it dumps the visitor into the master's
storefront. The friendly URL provider itself is correct; the bug is the nav tree's choice of page id.
Affected Swift v2 templates: `Navigation/Navigation.cshtml`,
`Paragraph/Swift-v2_MenuRelatedContent/Menu.cshtml`,
`Paragraph/Swift-v2_MenuProductGroupImages/Menu.cshtml`, plus any custom nav template using
`@node.Link`. Drop this helper into each affected template and call it everywhere `node.Link` is
emitted:

```csharp
string LocalizeLink(string link)
{
    if (string.IsNullOrEmpty(link)) return link;
    var area = Pageview?.Area;
    if (area == null || area.MasterAreaId <= 0) return link;  // master or no layer: passthrough
    var master = Dynamicweb.Content.Services.Areas.GetArea(area.MasterAreaId);
    if (master == null || string.IsNullOrEmpty(master.UrlName) || string.IsNullOrEmpty(area.UrlName)) return link;
    var masterPrefix  = "/" + master.UrlName.Trim('/') + "/";
    var currentPrefix = "/" + area.UrlName.Trim('/') + "/";
    if (link.StartsWith(masterPrefix, StringComparison.OrdinalIgnoreCase))
        return currentPrefix + link.Substring(masterPrefix.Length);
    return link;
}
```

Then `href="@node.Link"` → `href="@LocalizeLink(node.Link)"`. Razor recompiles live; no restart.
(Patching the tree builder upstream would mean shipping a custom AddIn; the per-template helper keeps
the fix in the design layer.)

### Friendly URL config — culture-coded area prefixes

For a multi-language site, switch all areas to culture codes so the language switch is visible in the
URL bar and reads as standard config:

```sql
UPDATE Area SET AreaUrlName = N'en-us' WHERE AreaId = <master>;
UPDATE Area SET AreaUrlName = N'nl-nl' WHERE AreaId = <nlLayer>;
UPDATE Area SET AreaActive = 0 WHERE AreaId = <cruftLayerId>;   -- disable failed-AreaCopy cruft
```

Restart the host (URL provider caches the area URL map at startup). Combined with `LocalizeLink`
above this makes the language switch behave coherently.

### Single-storefront clean root — one area owning `/`

For a single-storefront site (the common demo shape), make the storefront area answer `/` with no
`/<area-slug>/` prefix on child URLs:

1. Set `urlIgnoreForChildren = true` on the storefront area (`save_areas` exposes it; admin: Website
   settings → Domain and URL). Child pages then live at `/` — `/<area-slug>/shop` becomes `/shop`.
2. Deactivate leftover sibling areas (`active = false`) — e.g. the stock "Standard" area a suite
   scaffold ships alongside the deserialized storefront — so root routing has one candidate.
3. Restart the host: the URL provider and nav tree cache the area URL map at startup; the change is
   invisible until then.

**After the switch, sweep the rendered HTML for legacy links** — the URL provider rewrites only the
links it generates; three classes of stale link survive it:

- **Item-field links carrying dead page ids** (`Default.aspx?ID=<id>` where the id predates the
  deserialize). The MCP `find_unresolvable_item_pages` tool does NOT find these — it detects
  paragraphs whose item *type* no longer resolves, not stale *values* inside link/rich-text fields.
  Find them by fetching the rendered page (`curl`) and grepping for `Default.aspx`, then tracing each
  `<a href>` to its paragraph via the paragraph-id attribute DW renders on each grid column.
- **One item per chrome variant.** Stock Swift ships a separate `Swift-v2_Logo` item per
  header/footer variant page (desktop header, mobile header, desktop footer, mobile footer) — all
  carrying the same baked link. Repointing only the one visible in the first scan leaves the rest
  stale; enumerate every instance with `search_paragraphs` filtered by item type and repoint them
  all (`set_item_field_values`).
- **Hand-typed hrefs in rich-text fields.** Editor-authored `<a href="/<area-slug>/...">` markup
  keeps the old prefix verbatim; update the field value.

Not every `Default.aspx?ID=` hit is cruft: stock module output emits some by design (the
UserAuthentication app's sign-up / forgot-password / redirect sub-links, Swift's CartSummary AJAX
endpoint). Verify the target page id exists in the area and leave module-emitted links alone —
patching them means customizing stock module rendering. A `PageShortCut` holding `Default.aspx?ID=`
of an id that EXISTS (e.g. a sign-in folder shortcutting to its form page) is likewise intentional;
only clear shortcuts whose target id is dead (next section).

### `PageShortCut` baseline cruft — "About Us"/"Privacy" 404 after deserialize

Some baselines ship pages whose `Page.PageShortCut` points at a hardcoded old URL
(`Default.aspx?Id=107` is the canonical example — an original page id that doesn't exist
post-deserialize). The frontend 301-redirects to that stale id, which 404s.

```sql
SELECT PageId, PageAreaId, PageMenuText, PageShortCut FROM Page
WHERE PageShortCut LIKE '%Default.aspx%' OR PageShortCut LIKE '%Id=10%';
UPDATE Page SET PageShortCut = N'' WHERE PageId IN (<aboutPageId>, <clonesPageIds>);
```

Restart afterwards (page metadata cached). Add content to the now-empty page or it renders as just
header+footer.

### Common gotchas

- **Empty layer shows master content.** Check `Area.AreaEcomLanguageId` points at a `LanguageId` that
  actually has translation rows in `EcomProductTranslation`. Bridging is two-step.
- **LanguageSelector shows only one language.** It lists only areas with `AreaActive=1` AND
  `AreaMasterAreaId = (current area's master)`. Flip `AreaActive=1` after creating the sibling.
- **URL slug collides.** Two siblings with the same `AreaUrlName` route the second to 404. Pick
  distinct slugs.
- **Page-count drift.** New master pages land **unpublished** on the layer (default "Unpublish new
  pages"). Either freeze the master after creating layers, or turn that knob off.
- **Custom CSS / fonts.** Tier-0 Style assets are area-row-scoped via `AreaColorSchemeGroupId` etc.;
  newly-cloned layers **inherit the master's style ids** — brand stays consistent for free. Verify if
  a market needs a different palette. See [`swift-building.md`](swift-building.md).

## Editing page / paragraph / grid-row content through the Management API

The Management API hits the same DW domain services as MCP and the admin UI, so the bookkeeping
(ItemRelation cloning, cache invalidation, notifications) fires correctly. The binder has sharp edges
worth knowing when authoring content programmatically (validated DW 10.25.x):

- **Paragraph item fields** save through `ParagraphSave` round-trips of `GetParagraphById`. String /
  HTML fields persist directly. `ButtonData` fields have a binder asymmetry: GET returns a JSON
  *string*, but the save binder wants the *object*
  (`{"Label": ..., "Link": ..., "LinkType": "page", "Style": "primary"}`).
  - **Never seed a `ButtonData` field with a plain label string.** The render side deserializes the
    stored value as ButtonData JSON; a bare `"Shop now"` in `Button`/`FirstButton`/`SecondButton`
    throws `ConverterException: Cannot deserialize json string to … ButtonData` and replaces the whole
    paragraph (often the whole section) with a Razor error block. Store a full JSON object
    (`{"SelectedValue":"","Label":"…","Link":"/…","LinkType":"url","Style":"primary"}`) or an **empty
    string** for "no button" — templates guard on empty via `TryGetButton`. Seed/import sweeps should
    treat any non-empty non-JSON value on a `*Button*` item field as a defect.
- **`ShowParagraph` cannot be changed via the API** — both the `ParagraphSave` round-trip and
  `ParagraphChangeActive` silently no-op (observed on copied / master-linked rows). Hide a paragraph by
  `ParagraphDelete {DeleteWithRows: true, Ids: [...]}` or by blanking its fields instead.
- **`PageCopy` inherits the source's `shortCut`.** A page that carries a shortcut redirect produces a
  copy that 301s elsewhere (`DestinationType` is `folder|section|website`; the
  `X-DWAPP-REDIR-REASON` header names the middleware). Clear `shortCut` on the copy.
- **Grid rows: `GridRowCopy {PageId, Id}`** (copy a known row to the target page) is far more reliable
  than `GridRowCreate`, whose definition lookup is fussy about grid naming. Then point the paragraph's
  `gridRowId` / `gridRowColumn` at the copied row.

### Saves that report success but silently drop a field

Two content saves report `status: ok`, bump `updatedDate`, and silently drop part of the input — so
**round-trip-verify any demo-critical content edit** (read the value back through a different surface,
or curl the rendered page) before declaring it done:

| Save | Field silently dropped | Verified | Working fallback |
|---|---|---|---|
| MCP `save_pages` (update path) | `menuText` — the response even echoes the OLD value | DW 10.25.x | SQL `UPDATE Page SET PageMenuText` + host restart (the nav tree caches menu text) |
| MCP `save_pages` (create + update) | `urlName` — ignored; the slug is derived from `menuText` instead | DW 10.27.x | Set `menuText` to drive the slug, or SQL `UPDATE Page SET PageUrlName` + host restart. `urlName` won't pin the slug on its own. |
| Management API `ParagraphSave` | `contentItem.groups[].fields[].value` mutations — the `ItemType_*` column never updates | DW 10.25.x | MCP `set_item_field_values` first; SQL UPDATE last resort. `ParagraphSave` is still correct for paragraph-level scalars (Header, Sort, GridRow, Template) |

The tool-behaviour root cause (why these MCP / Management API writes drop fields, and the surface model)
is in [`extend-mcp-tools.md`](extend-mcp-tools.md) §5.

## Cross-references

- [`extend-mcp-tools.md`](extend-mcp-tools.md) — MCP create/update tool behaviour and the silent-no-op
  table from the tool's perspective.
- [`swift-building.md`](swift-building.md) — Style assets, the re-skin escalation ladder / item-type
  + variant + CSS separation, the discipline grep-pack, and the `RenderGrid` composition cache.
- [`razor-surfaces-and-pitfalls.md`](../../../dw-render-razor/references/razor-surfaces-and-pitfalls.md) — per-category behavior via `ProductGroupFieldValues`; canonical
  URL/redirect surfaces the language switcher relies on.
- [`dw-render-viewmodels`](../../../dw-render-viewmodels/SKILL.md) — `Pageview.User.GetGroups()` and other viewmodel
  accessors used by template role-gates.
- [`permission-layers.md`](../../../dw-users-permissions/references/permission-layers.md) — the Permission entity store that AreaCopy fails to
  clone (point 2 above).
- [`pim-localization.md`](../../../dw-pim-localization/references/translation-mechanics.md) — the product side (translate product names,
  descriptions, custom fields).
