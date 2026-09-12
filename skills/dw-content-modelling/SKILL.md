---
name: dw-content-modelling
type: knowledge
group: content
mcp: optional
dynamo: true
description: 'Design item types, paragraphs, and content models in Dynamicweb 10, and create/publish a page or paragraph through the MCP tools. Triggers: item type discipline, paragraph structure, field modelling, asset organization, create/edit/copy/move/publish a page or paragraph. Non-triggers: rendering content -> dw-render-razor; fetching with ViewModels -> dw-render-viewmodels; translating a page/site -> dw-content-localization.'
---

# Content Modelling

## Without MCP

The knowledge here stands alone; the Dynamicweb MCP tools it names are the way to apply it, and
in-product they are the only way — the MCP tool set plus read/write under `Files/` is the whole
surface these steps may use. When no tool covers the operation, **stop and tell the user**, naming
the admin screen that performs it, rather than substituting a guessed HTTP call, a file edit
outside `Files/`, or SQL. The Management API, the serializer and direct SQL exist only outside the
product, are never a step in this skill, and are owned by
[`dw-data-access`](../dw-data-access/SKILL.md) "Surfaces into a Dynamicweb instance".

## Three Content Model Approaches

| Approach | Best for |
|----------|---------|
| **Content Placeholders** | Standard paragraph-based layouts with flexible editing |
| **Content Grid** | Visual drag-and-drop editing with row definitions |
| **Page-Based Items** | Structured content types (blog posts, events, news) where the page IS the content |

All three use **Item Types** to define the field schema.

## Item Types

An Item Type is a configurable schema — a named set of fields that defines what data a content element (page, paragraph, row) can hold.

### Creating an Item Type

Admin path: **Settings > Areas > Content > Item types**

1. Click **New item type**
2. Set: **Name**, **System name** (permanent; used in templates and API), **Description**, **Category**, **Icon**
3. Set **roles** — where this item type can be used:
   - Page (defines a structured page type)
   - Paragraph (defines paragraph fields)
   - Row (defines row settings in Content Grid)
   - Website settings / Page settings
4. Advanced: "Allow module attachment" (lets editors attach paragraph apps), "Inherit from" (copy fields from another item type)
5. Add **fields**
6. Configure **Item type restrictions** (which websites, parent types, tree sections are allowed)
7. Save

**Note on system names:** System names are permanent — changing a system name breaks template references and API calls. Plan them carefully: use PascalCase, keep them descriptive but concise (e.g., `HeroBlock`, `BlogPost`, `ProductFeature`).

### Item Type Fields

**Text fields:**
- `Text` — short string (up to 255 chars)
- `Long text` — multi-line text
- `Rich text` — WYSIWYG HTML editor
- `Hidden field` — non-visible text
- `Password` — masked input

**Link fields:**
- `Link` — internal page or file URL
- `Link to item` — reference to an item-based page/paragraph
- `Folder` — file folder selector
- `File` — file selector with upload support

**Selection fields:**
- `Dropdown list`, `Checkbox list`, `Radio button list`
  - Options source: Static (manual pairs), SQL query, Item type (dynamic), Folder (files as options)
- `User` — user reference
- `Product` — product reference

**Number and date:**
- `Integer`, `Decimal`, `Date`, `Date and time` (use `NOW` as default for current date)

**Media:**
- `Image` — single image file reference (with focal point support)
- `Color` — color picker with preset options
- `Color swatch` — 11-slot global color scheme

**Structural:**
- `Item relation list` — references to other items (e.g., "Related Articles")
- `Item type` — embeds another item type's fields inline
- `Item tab` — embeds another item type's fields in a separate tab
- `Geolocation` — coordinates derived from address fields
- `Checkbox` — boolean

### Field Configuration Options

Each field has:
- **Name** — display label in the editor
- **System name** — API key (permanent)
- **Description** — editor help text
- **Field group** — visual grouping within the edit form
- **Default value**
- **Do not include in search** — exclude from the content index
- **Required** — validate on save
- **Validation expression** + error message — regex validation

**Field groups** can have visibility conditions (show/hide based on other field values).

## Content Placeholders

Placeholders define named areas in a page layout where paragraphs can be placed. Define in the layout template using the `PageViewModel`:

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Frontend.PageViewModel>

@* Minimal placeholder *@
@Model.Placeholder("content", "Content")

@* Placeholder with settings *@
@Model.Placeholder("sidebar", "Sidebar", "default:false;sort:2;template:sidebar-default.cshtml")
```

**Placeholder settings:**
- `default:true/false` — whether this is the default paragraph drop zone
- `sort:1-99` — display order in the editor
- `template:path.cshtml` — default paragraph template (relative to `Templates/Paragraph/`)

Paragraph templates must be in:
- `/Templates/Paragraph/`
- `/Templates/Designs/Paragraph/`
- `/Templates/Designs/{DesignName}/Paragraph/`

**Important:** The placeholder ID (first argument) is stored in the database. Changing the ID effectively removes all content from that placeholder.

## Content Grid

The Content Grid enables visual row-based layout editing. Define in the layout template:

```razor
@Model.Grid("contentgrid", "Grid", "", "Page")
```

### Row Definitions

Create row definitions at: `/Files/Templates/Designs/{DesignName}/Grid/Page/RowDefinitions.json`

```json
[
  {
    "Id": "1column",
    "Name": "1 Column",
    "Description": "Full-width single column",
    "Template": "1Column.cshtml",
    "ColumnCount": 1,
    "ItemType": "RowSettings",
    "Thumbnail": "thumbnails/1column.svg"
  },
  {
    "Id": "2column",
    "Name": "2 Columns",
    "Template": "2Column.cshtml",
    "ColumnCount": 2
  }
]
```

**`Id` is permanent** — it is stored in the database per row instance. Changing an ID for an existing row definition breaks saved content. Always generate new IDs rather than editing existing ones.

### Row Templates

Place in `/Files/Templates/Designs/{DesignName}/Grid/Page/RowTemplates/`. Inherit `GridRowViewModel`:

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Frontend.GridRowViewModel>

<div class="row">
    <div class="col-md-12">
        @Model.Column(1).Output()
    </div>
</div>
```

For two columns:
```razor
<div class="row">
    <div class="col-md-6">@Model.Column(1).Output()</div>
    <div class="col-md-6">@Model.Column(2).Output()</div>
</div>
```

### Row Item Types

Optionally, assign an Item Type to a row definition (`"ItemType": "RowSettings"`). This lets editors configure per-row settings like background color, padding, or section images. Access in the row template:

```razor
@Model.Item.GetString("BackgroundColor")
@Model.Item.GetFile("BackgroundImage").Path
```

## Page-Based Items (Structured Content)

For content where the page itself is the data record (blog posts, events, news), bind a page directly to an item type.

1. Create an item type with the required fields (e.g., `BlogPost` with fields Title, Author, PublishDate, Body, HeroImage)
2. In the admin, create a page and set its **Item type** to `BlogPost`
3. Create a template named after the item type system name (e.g., `BlogPost.cshtml`) in the design folder root

Template pattern:

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Frontend.PageViewModel>

<article>
    <h1>@Model.Item.GetString("Title")</h1>
    <p class="author">@Model.Item.GetString("Author")</p>

    @if (Model.Item.TryGetDateTime("PublishDate", out DateTime date))
    {
        <time datetime="@date.ToString("yyyy-MM-dd")">@date.ToLongDateString()</time>
    }

    @if (Model.Item.TryGetImageFile("HeroImage", out var img))
    {
        <img src="@img.Path" alt="@img.AlternativeText" />
    }

    <div class="body">@Html.Raw(Model.Item.GetString("Body"))</div>
</article>
```

## Item-Based Paragraphs

Paragraphs can also carry an item type. The paragraph's template is named after the item type system name and placed in `Designs/{DesignName}/Paragraph/`.

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Frontend.ParagraphViewModel>

@{
    // ParagraphViewModel.Item is the ItemViewModel for this paragraph's item type
    string title = Model.Item?.GetString("Title") ?? Model.Header;
    bool showInPage = Model.Item?.GetBoolean("ShowInPage") ?? true;
}

@if (showInPage)
{
    <section>
        <h2>@title</h2>
        <p>@Model.Item?.GetString("Description")</p>
    </section>
}
```

**`Model.Item` can be null** — if the paragraph does not have an item type assigned, `Model.Item` is null. Always null-check.

## ItemViewModel Access Patterns

Key methods available on `ItemViewModel` (same API for `PageViewModel.Item`, `ParagraphViewModel.Item`, `GridRowViewModel.Item`):

```csharp
// Safe reads — return default value if field is null/missing
item.GetString("FieldName")        // null if missing
item.GetBoolean("IsActive")        // false if missing
item.GetInt32("Count")             // 0 if missing
item.GetDecimal("Price")           // 0m if missing
item.GetDateTime("PublishDate")    // default DateTime if missing

// Try pattern — for optional fields
if (item.TryGetString("Subtitle", out string subtitle)) { }
if (item.TryGetImageFile("Image", out ImageFileViewModel img)) { }
if (item.TryGetLink("CtaLink", out LinkViewModel link)) { }
if (item.TryGetButton("Button", out ButtonViewModel btn)) { }

// Lists and relations
IEnumerable<ItemViewModel> related = item.GetItems("RelatedItems");
IEnumerable<ImageFileViewModel> images = item.GetImageFiles("Gallery");
IEnumerable<FileViewModel> files = item.GetFiles("Attachments");
```

## Design and Layout Structure

```
/Files/Templates/Designs/{DesignName}/
    Layout_default.cshtml      ← main layout (inherits PageViewModel)
    {ItemTypeName}.cshtml      ← page-based item template
    Paragraph/
        {ItemTypeName}.cshtml  ← item-based paragraph template
    Navigation/
        {TemplateName}.cshtml  ← navigation templates
    Grid/
        Page/
            RowDefinitions.json
            RowTemplates/
                1Column.cshtml
                2Column.cshtml
```

## Creating and Publishing a Page

Beyond designing the schema, actually creating/editing/copying/moving/publishing a page or
paragraph through the MCP tools has its own discipline.

The page entity is `Dynamicweb.Content.Page`. Before writing, read the **parent** (its item type
and layout constrain the child), the **item type schema** (required fields, localizable flags,
references), one published **sibling** at the same level, and decide the **language layer** —
master or translation — up front.

**`Active` and `Published` are different**, and saving a page does not publish it: `Active`
controls navigation/availability, `Published` controls whether the page is live, so a "make it
live" request is a second call. `LayoutTemplate` / `ParentLayoutTemplate` set wrong is the most
common cause of "the new page looks broken".

**Paragraphs — two insertion paths.** For any type that appears in `get_item_types`, including
custom ones, create with `save_paragraphs` and set `ItemType` to the exact system name. For a
standalone application or module listed in `get_content_apps`, use `place_app_paragraph` — except
on a Swift 2 site, where a grid column renders a paragraph through its item type and
`place_app_paragraph` leaves `ParagraphItemType` empty, so the paragraph is correct in the database
and invisible on the page; copy a working app paragraph of the same module instead. Whichever tool
creates it, `save_paragraphs` / `set_paragraph_item_fields` store field values **verbatim** — read
the target item type's real field names and an existing sibling's value shapes first (button fields
as `ButtonData` JSON, rich-text fields with their own HTML) rather than guessing.

**Confirm before writing.** State the page and parent ("Create About page under Company"), the item
type, language, and whether it will be published. For paragraph edits, name the paragraph and the
page it lives on. If a write fails on item-type or schema validation, re-read the item type schema
and fix the field — do not invent placeholder values to satisfy required fields.

The write surfaces themselves — which saves drop a field, which labels the platform re-derives,
which caches a structural write leaves stale — are in
[references/page-paragraph-writes.md](references/page-paragraph-writes.md).

## Deep reference

| Read it for | Reference |
|---|---|
| Editor-manageable page modelling (one paragraph/field per editor concern) and the custom item-type `<Prefix>_*` discipline: why an XML drop leaves a type readable and unwritable until the definition loads, why that differs by host class, the write-ACE on the items folder, Routes A/B and their zero-restart cost, editor-choice-becomes-column-type, and repeater-child storage | [references/modelling-discipline.md](references/modelling-discipline.md) |
| Writing pages, paragraphs and grid rows: the Management API binder's sharp edges, saves that report success and drop a field, `PageMenuText` re-derived from the item title on every save (`reorder_pages` included), the missing `navigationTag` member, `place_app_paragraph` rendering nothing on Swift 2, the nav-tree cache a re-parent does not invalidate, repeatable-child caching, and `<QueryConditions>` as the per-paragraph query-default lever | [references/page-paragraph-writes.md](references/page-paragraph-writes.md) |
| Language layers and multi-area binding: the `Area` sibling-row model, what `AreaCopy` does not carry, what a save on a mastered page does to its mirror (structure crosses, values do not), the translation cascade, friendly-URL/root wiring, and two areas sharing one host | [references/language-layers.md](references/language-layers.md) |

## Pitfalls

**System names are permanent** — changing an item type system name after templates reference it breaks rendering for all existing pages/paragraphs of that type. Treat system names as write-once.

**Grid row `Id` is permanent** — changing a row definition's `Id` after content has been created causes saved rows to lose their template reference. Always create new row definitions rather than renaming existing ones.

**Placeholder ID changes lose content** — the placeholder ID is stored per paragraph. Renaming a placeholder ID moves the content "out of" the placeholder — paragraphs remain in the DB but are no longer rendered.

**`Model.Item` is null without an item type** — standard paragraphs and pages without an attached item type have `Model.Item == null`. Always null-check before calling item methods.

**Item type restrictions must be configured** — by default, a new item type cannot be used anywhere. Configure restrictions (allowed websites, allowed parents, allowed tree sections) before trying to use the item type in the page tree.

## Next Steps

- **Rendering templates with ViewModels?** See [dw-render-viewmodels](../dw-render-viewmodels)
- **Razor template structure?** See [dw-render-razor](../dw-render-razor)
- **Using TemplateTags for legacy rendering?** See [dw-render-templatetags](../dw-render-templatetags)
- **Cache invalidation after content mutations (SQL-seeded pages/paragraphs, item-type XML drops)?** See [dw-data-access](../dw-data-access/SKILL.md)
- **Translating a page or making a language version of a site?** See [dw-content-localization](../dw-content-localization)
