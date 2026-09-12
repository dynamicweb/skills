# Modelling discipline: editor-manageable content and custom item types

Vendor-generic DW10 content-modelling knowledge: editor-manageable page modelling and the custom
item-type `<Prefix>_*` discipline, including the XML/`ItemFieldSave` activation mechanics and the
repeater-child edit path. Two siblings carry the rest of the content-modelling depth:
[`page-paragraph-writes.md`](page-paragraph-writes.md) for the page/paragraph/grid-row write
surfaces, and [`language-layers.md`](language-layers.md) for language layers and multi-area binding.

## Contents

- [1. Editor-manageable pages, not HTML blobs](#1-editor-manageable-pages-not-html-blobs)
- [2. Custom item types — the `<Prefix>_*` discipline](#2-custom-item-types--the-prefix_-discipline)
- [Cross-references](#cross-references)

## 1. Editor-manageable pages, not HTML blobs

> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

**The rule: model one paragraph (or field) per editor concern; rich-text fields carry prose only.**
The moment a `class=` attribute, a `<div>`, or a structural `<img>` is needed inside a rich-text
field, that is the signal to model a field or an item type instead — see the escalation mechanics in
[`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) ("separate the styling from the content") and the custom
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
   case is covered in [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md)).
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
designed page, not once per site.

## 2. Custom item types — the `<Prefix>_*` discipline

When a paragraph block needs editor-configurable fields that aren't on the stock item types, create a
**new item type** with a project prefix (`<Prefix>_PointsDashboard`, `<Prefix>_RebateTracker`) — not
"another `Swift-v2_Text` variant". This explicitly forbids the "generic-item-type shim + foreign
cshtml" pattern.

### What this looks like in practice

**Dropping the XML makes the type fully READABLE and leaves it unwritable until the definition is
LOADED — and which event loads it differs by host class.** Three independent subsystems are
involved and the file only reaches one of them:

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

So an XML-only deployment produces a type that is fully introspectable and, until something loads
the definition, completely unwritable: a `ParagraphSave` or an `INSERT` against the type returns
**`Invalid object name 'ItemType_<Prefix>_<Concept>'`** (HTTP 500 through the API), which reads like
a SQL typo rather than a timing problem because every read verb already reports the type and its
fields.

**What loads it is host-class-dependent, so state the condition rather than an absolute.** On a
local IIS host on 10.28.x an app-pool restart alone materialises the table and the same `INSERT`
succeeds on the next request — the definition is read when the application starts. On hosted cloud
installs the same sequence was measured twice with no table after any number of restarts, and the
API route below was the only fix. **What holds on every host class is the ORDERING**: the table
does not exist at the moment the file lands, so never write the first row in the same batch as the
XML drop, put the load step (a restart locally, `ItemFieldSave` everywhere) between the two, and
gate item-type readiness on a REAL WRITE rather than on a metadata read.
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

**Route B costs no restart and no cache flush.** Measured on 10.28.x with the worker process
unchanged across the whole sequence: `ItemTypeSave` created the `ItemType_<SystemName>` table AND
wrote the `Files/System/Items/<SystemName>.xml` descriptor in one call; eight `ItemFieldSave` calls
added their eight columns; a paragraph of the brand-new type placed on a brand-new page rendered
with its own template and every field read through `Model.Item.GetString()` **on the next request**.
Field VALUES are live on the next request too — `set_paragraph_item_fields` on the new type changed
what the paragraph rendered with no cache verb at all. This is the positive half of the loud XML-drop
trap above, and it is what makes a new paragraph type affordable inside a change window that allows
no restart.

`POST ItemTypeDelete {SystemName, DeletePages:false}` frees the name **and** removes the XML — it is the
reset lever when a type is genuinely mis-authored, not a required step on the way to a working table.

**To ADD a field to a type that already holds live content, call `ItemFieldNew` + `ItemFieldSave` and
nothing else. Never re-run a create-the-type script against a type that holds content.** The
delete-and-recreate opening of Route A/B above (`ItemTypeDelete` then `ItemTypeNew`/`ItemTypeSave`) reads
like "the way to change an item type" and it is not: `ItemTypeDelete` DROPS the `ItemType_<X>` table and
every row of content in it. The field-level verbs are independent of it — `ItemFieldNew` returns a field
shell for an existing type and `ItemFieldSave` ALTERs the table to add the column, leaving every existing
row intact:

```
GET  /Admin/Api/ItemFieldNew?ItemTypeSystemName=<Type>&ItemFieldGroupSystemName=General
POST /Admin/Api/ItemFieldSave { Model: { …, systemName:"<Field>", isNew:true,
       editorType:"Dynamicweb.Content.Items.Editors.TextEditor, Dynamicweb",
       underlyingType:"System.String, System.Private.CoreLib" } }   -> status ok

ItemType_<Type>: 15 -> 16 columns, rows 12 -> 12, new column <Field> nvarchar(255)
```

**Guard it with a before/after content fingerprint plus a row count**, so "I added a column" cannot quietly
mean "I lost the content": snapshot the column list, the row count and a per-row digest of the existing
values, then assert exactly one new column with the expected name and type, an unchanged row count, and an
identical fingerprint. The editor decides the column width the same way it does at create time
(`TextEditor` backs as `nvarchar(255)`, `LongTextEditor` as `nvarchar(max)`).

**The editor you pick becomes a column type — a `TextEditor` field materialises as `nvarchar(255)`.**
`ItemFieldSave` issues the DDL from the editor, and a value longer than the column is a **hard error, not
a truncation**: a 259-character alt text bounced the whole `ParagraphSave` with a **500**, while 250
characters landed. Nothing in the field definition surfaces the limit. Choose `TextArea` / `RichText` for
anything that can grow (descriptions, alt text, any authored prose) and keep `TextEditor` for values you
can guarantee ≤ 255 — and note that the choice is baked at field-create time, so changing it later is the
create-alongside-and-migrate motion ([dw-pim-modelling](../../dw-pim-modelling/SKILL.md) (`structural-model.md`) §2.8), not an edit.

**A successful `ItemTypeById` / `ItemFieldsByItemTypeSystemName` read is NOT evidence the type is
usable** — it is exactly the state an XML-only deployment produces. Any new-item-type helper must gate on
a real write and must refuse to report success on metadata reads alone; make it re-runnable so a second
run reports "already writable — nothing to do", record the before/after writable state per type, and read
`Files/System/Log/items/ActivationWorkflow` on any failure before theorising. Rejected escapes:
hand-writing the `CREATE TABLE` in SQL (leaves DW's own metadata/schema bookkeeping out of the loop) and
rotating `changeversion.txt` for a "harder" restart (that file is the host's release-ring pin, not a
restart lever (see [dw-setup-upgrade](../../dw-setup-upgrade/SKILL.md)) — and a restart is not the missing
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
its save is a plain HTTP call you can capture and replay (no operation exists only
in the UI — the admin SPA is a client of `/Admin/Api`). **This was proven end-to-end against a
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
  honoured for it either. The honest fallback for such a field is a single edit in the admin UI.
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
  (see "Saves that report success but silently drop a field" below).

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
reports values back to you that the row never took (observed with `SelectedImage` on a child: `Title`/`Subtitle`/`Text` persist and `Image` does not, out of one payload that echoes all four). A
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
  copy on a `ProductGroup` field instead — see [`razor-surfaces-and-pitfalls.md`](../../dw-render-razor/references/razor-surfaces-and-pitfalls.md) "Per-category
  behavior".

### Audit query

To list all paragraph templates that don't match `Swift-v2_*` and aren't in a project-prefixed
folder (a "shim" smell — refactor to a custom item type):

```powershell
Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2\Paragraph\Swift-v2_*\*" -Filter '*.cshtml' `
    | Where-Object { $_.Name -notlike 'Swift-v2_*' }
```

This is also grep #6 of the discipline audit grep-pack in [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md).

## Cross-references

- [`page-paragraph-writes.md`](page-paragraph-writes.md) — creating and editing pages, paragraphs
  and grid rows: the Management API binder's sharp edges, the saves that drop a field, and the
  caches a structural write does not invalidate.
- [`language-layers.md`](language-layers.md) — the `Area` sibling-row model, `AreaCopy`, the
  translation cascade, and what a save does to a language mirror.
- [dw-extend-mcp-tools](../../dw-extend-mcp-tools/SKILL.md) — MCP create/update tool behaviour and the silent-no-op
  table from the tool's perspective.
- [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) — Style assets, the re-skin escalation ladder / item-type
  + variant + CSS separation, the discipline grep-pack, and the `RenderGrid` composition cache.
- [`razor-surfaces-and-pitfalls.md`](../../dw-render-razor/references/razor-surfaces-and-pitfalls.md) — per-category behavior via `ProductGroupFieldValues`; canonical
  URL/redirect surfaces the language switcher relies on.
- [dw-render-viewmodels](../../dw-render-viewmodels/SKILL.md) — `Pageview.User.GetGroups()` and other viewmodel
  accessors used by template role-gates.
- [dw-users-permissions](../../dw-users-permissions/SKILL.md) (`permission-layers.md`) — the Permission entity store that AreaCopy fails to
  clone.
- [dw-pim-localization](../../dw-pim-localization/SKILL.md) (`translation-mechanics.md`) — the product side (translate product names,
  descriptions, custom fields).
