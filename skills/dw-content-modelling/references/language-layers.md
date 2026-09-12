# Content-side language layers and multi-area binding

Vendor-generic DW10 knowledge for running a site in more than one language or on more than one
content area: the `Area` sibling-row model, `AreaCopy` and what it does not carry, the three-layer
translation cascade, what a save on a mastered page does to its mirror, friendly-URL and root
wiring, and two areas sharing one host. Item-type and paragraph schema design is
[`modelling-discipline.md`](modelling-discipline.md); the write surfaces themselves are
[`page-paragraph-writes.md`](page-paragraph-writes.md).

## Contents

- [3. Content-side language layers](#3-content-side-language-layers)
- [The two-table mental model](#the-two-table-mental-model)
- [What gets created (admin UI)](#what-gets-created-admin-ui)
- [The eight Language Management knobs](#the-eight-language-management-knobs)
- [Wiring the area to PIM language](#wiring-the-area-to-pim-language)
- [The Swift OOTB language switcher](#the-swift-ootb-language-switcher)
- [Creating the layer — surface order + host-config prereqs](#creating-the-layer--surface-order--host-config-prereqs)
- [What a full-content AreaCopy does NOT carry (validated DW 10.25.x)](#what-a-full-content-areacopy-does-not-carry-validated-dw-1025x)
- [Every save on a mastered page costs two objects — and the mirror inherits unevenly](#every-save-on-a-mastered-page-costs-two-objects--and-the-mirror-inherits-unevenly)
- [A save on a mirror page pulls the master's menu text down over the translation](#a-save-on-a-mirror-page-pulls-the-masters-menu-text-down-over-the-translation)
- [A DANGLING item-list pointer reads exactly like an empty list](#a-dangling-item-list-pointer-reads-exactly-like-an-empty-list)
- [The three-layer translation cascade — localize all three](#the-three-layer-translation-cascade--localize-all-three)
- [Nav-tree leaks the master area on layers — `LocalizeLink` patch](#nav-tree-leaks-the-master-area-on-layers--localizelink-patch)
- [Friendly URL config — culture-coded area prefixes](#friendly-url-config--culture-coded-area-prefixes)
- [Single-storefront clean root — one area owning `/`](#single-storefront-clean-root--one-area-owning-)
- [Two content areas on ONE host — same domain, `PageExactUrl` addressing](#two-content-areas-on-one-host--same-domain-pageexacturl-addressing)
- [`PageShortCut` baseline cruft — "About Us"/"Privacy" 404 after deserialize](#pageshortcut-baseline-cruft--about-usprivacy-404-after-deserialize)
- [Common gotchas](#common-gotchas)
- [Cross-references](#cross-references)

## 3. Content-side language layers

> Content-side localization — adding a language layer to a website. Sister concern to the PIM/product
> side ([dw-pim-localization](../../dw-pim-localization/SKILL.md) (`translation-mechanics.md`)), which translates product names / descriptions
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
[dw-pim-localization](../../dw-pim-localization/SKILL.md) (`translation-mechanics.md`).

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
input shape). Those host-config prereqs are owned by [dw-setup-install](../../dw-setup-install/SKILL.md): the
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
   pass state is a redirect to the localised sign-in, not a 200). Mirror every master row onto the layer's sibling page id
   (`Page.PageMasterPageId` gives the mapping), then
   `POST /admin/api/CacheInformationRefresh {"CacheTypeName":"Dynamicweb.Security.Permissions.PermissionService"}`
   AND restart (the nav tree caches separately). See [dw-users-permissions](../../dw-users-permissions/SKILL.md) (`permission-layers.md`).
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
   [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) "ProductListComponentSelector".)

### Every save on a mastered page costs two objects — and the mirror inherits unevenly

On a solution with a language layer (`Page.PageMasterPageId` / `Paragraph.ParagraphMasterParagraphId`
set), the MCP/Management-API save path mirrors structural writes into the layer automatically. What
crosses and what does not is **not uniform**, and the two halves are what a build gets wrong:

| Created by one master-side call | Crosses into the mirror | Does NOT cross |
|---|---|---|
| `save_pages` on a master | The page itself, and its `PageMenuText` copied verbatim | — |
| `save_grid_rows` on a master | A mirror row **with** a real `GridRowItemId` | The MASTER's row is left with `GridRowItemId` NULL |
| `save_paragraphs` on a master | A mirror paragraph **and** its own grid row, carrying the master's fully-qualified `ParagraphTemplate` | The item field VALUES — the mirror gets the item type's DEFAULTS |

Three rules follow, and each one costs a debugging cycle when it is missed:

1. **Create on the MASTER only.** Calling `save_grid_rows` + `save_paragraphs` once per page, master
   AND mirror — the sequence a reader of "the mirror gets defaults, set them explicitly" reasonably
   writes — produces duplicates: measured, eight intended paragraphs came out as twelve, four of them
   minted by the mirroring and four hand-made in their own rows on the same pages. One sentence
   prevents it: the mirror's STRUCTURE is created for you; only its VALUES are not.
2. **Then set the mirror's values explicitly** — `set_page_item_fields`, `set_paragraph_item_fields`
   and the menu text — or the mirrored page renders, in the right place, with plausible content, in
   the wrong mode and in the master's language. That is the most expensive failure shape there is:
   it looks right.
3. **Repair the master's missing grid-row item instance through the platform's own per-type
   allocator**, the `ItemTypeId(ItemType, Current, Seed)` table — never `MAX(Id)+1` on the
   `ItemType_<name>` table, which collides the next time the platform allocates. A Swift row renders
   from the item INSTANCE, so a master row with a NULL `GridRowItemId` renders no columns at all
   while its own translation renders correctly: a page that is empty in the master language and
   right in the mirror is this, every time.

```sql
-- local install only: no verb sets GridRowItemId on a master row (10.28.x)
UPDATE ItemTypeId SET [Current] = [Current] + 1 WHERE ItemType = 'Swift-v2_Row';
-- then INSERT the instance row and stamp GridRow.GridRowItemId with the new value,
-- followed by CacheInformationRefresh on ParagraphService and PageService.
```

**Cleanups are soft deletes.** `delete_paragraphs` and `delete_grid_rows` both report success and
neither `COUNT(*)` falls, so any structural invariant over those tables must count
`WHERE ...Deleted = 0` — otherwise a sweep reports the rows it deliberately removed.

### A save on a mirror page pulls the master's menu text down over the translation

Any save on a language-mirror page re-derives `PageMenuText` from the item's title field, and on a
mirror the save resolves that title **through the MASTER's item** — so a call that mentions no menu
text at all replaces the translated navigation label with the master's wording. Measured on two
different calls: a `save_pages` re-parent, and a `set_page_menu` that set only `showInMenu` (whose
own schema says an omitted property is left unchanged — the contract is honoured for the property;
the damage happens afterwards, in the platform's title derivation). Both responses echoed the
master's text as though it were the current value. `reorder_pages` does it to a whole sibling set at
once, because it re-saves every child it orders.

**The restore is the mirror's OWN title field, not another `set_page_menu`:**

```
set_page_item_fields { pageId: <mirrorId>, fields: { Title: "<translated label>" } }
```

after which `PageMenuText` and the mirror's `Title` agree and no later save can drift them apart.
The discriminator for which mirrors survive a bulk navigation change is exactly this: the ones whose
translated string was already in the item Title keep it; the ones carrying the translation only in
`PageMenuText` lose it. So **capture every mirror's `PageMenuText` before a bulk navigation change
and diff afterwards**, do bulk navigation work on the master, and re-assert the mirrors' titles as a
scripted step. The underlying rule and the page-save half live in
[`page-paragraph-writes.md`](page-paragraph-writes.md).

### A DANGLING item-list pointer reads exactly like an empty list

Same shape of damage as class 1 above, from a different cause, and the read side cannot tell you which you
are looking at. **An item-list field can point at an `ItemList` id that no longer exists, and the read verb
answers `[]` — indistinguishable from "nobody has added items yet".** Observed after a serializer
deserialize left `ItemList` and `ItemListRelation` **completely empty** while the parent items still
carried their pointers (`ItemType_Swift-v2_Slider.Items = 323`, an accordion's `Accordion_Items = 324`).
The paragraphs render as heading-plus-subline shells with no children, and a punch list records them as
empty bands:

```
SELECT * FROM ItemList          -> 0 rows
SELECT * FROM ItemListRelation  -> 0 rows
get_repeatable_item_field       -> []
add_repeatable_item             -> "Field Accordion_Items references item list 324, which no longer exists"
```

**Reset the pointer to the STRING `"0"`** with `set_paragraph_item_fields` (an empty string is rejected
with "The input string was not in a correct format" — it is an int field), which makes the field
list-less. The next `add_repeatable_item` then mints a fresh `ItemList` and links it; `ItemList` gains a
row and the child appears in `ItemType_<child>`. **Distinguish the two states before treating a `[]` as
empty**: `SELECT COUNT(*) FROM ItemList WHERE Id = <pointer>` is the cheap discriminator, and
`add_repeatable_item`'s own error message names it. A presence-only design assert passes on a shell, so
gate the section on RENDERED HEIGHT, not on the element existing.

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

**A key with no row for the SITE's own culture renders its shipped `DefaultValue`, and nothing looks
untranslated.** The stock defaults are written for a multi-store retail shop ("In stock in 1 shops",
"Stock information"), so a B2B, wholesale or dealer storefront on an English site reads like a
webshop in exactly the places that matter — the stock and price blocks — while `Translations.xml`
looks complete because the keys are all present. Ship a `<translation culture="<site culture>">` row
for the handful of keys whose default wording is wrong for the business, not only for the added
locales. Insert rows with a script that finds the key block and checks the culture row is absent,
and **write the file in place** — a move-then-replace strips the app-pool ACL that DW needs to write
the file itself.

Apply in order: (1) inject the locale into `Translations.xml` for visible keys (aim for ~80-150
chrome strings, the rest fall back to en-GB gracefully); (2) UPDATE cloned header `Title` fields
(MiniCart/Favorites store HTML fragments `<div class="dw-paragraph">…</div>` — preserve the wrapper);
(3) translate DB paragraphs/products/groups. Restart after editing `Translations.xml` (cached at
startup) and after touching header item rows (composition cache). Same depth-not-width rule as PIM:
localize the **pages a visitor actually reaches first**, not the whole site.

**SQL files with non-ASCII characters — encoding pitfall.** `sqlcmd` defaults to the system codepage
(Windows-1252 on western Windows); a UTF-8 `.sql` file with multibyte characters gets mangled at
parse time and stored corrupted in NVARCHAR even though the literal is `N'...'` (symptom: an accented
character such as `é` renders as a two-character double-encoded mojibake sequence). Fix: skip the file — build the UPDATE statements in PowerShell (UTF-16 in memory) and pass
via `Invoke-Sqlcmd -Query`, or save the `.sql` as UTF-8-with-BOM (sqlcmd detects the BOM). The
PowerShell-inline approach is more robust (the BOM is easy to lose on re-save). To measure damage
already in a database, the [dw-data-access](../../dw-data-access/SKILL.md) skill ships a read-only
census script (`Invoke-DwMojibakeCensus.ps1`).

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

For a single-storefront site (a common solution shape), make the storefront area answer `/` with no
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

### Two content areas on ONE host — same domain, `PageExactUrl` addressing

For a second surface on the same site (a dealer portal, a partner area) with no second domain, no
DNS and no certificate: **area resolution is by DOMAIN, not by url name.** `AreaUrlName` mints no
path prefix for an area that shares a host — it is decorative there — and an area with an EMPTY
`AreaDomain` is unreachable on every URL (DW builds its absolute URLs against a host of literally
`false`, and the intended path 404s).

The shape that works, measured on 10.28.x:

1. Set the **same `AreaDomain`** on both areas.
2. Keep the primary area at the **lower `AreaSort`** — it keeps `/` and the whole culture namespace
   — and give the second a high sort.
3. `AreaUrlIgnoreForChildren = 1` on the second area. At `0`, DW prefixes the SHARED culture segment
   and de-duplicates colliding page names, so the second site's home lands on `/<culture>/home-1`
   and its sign-in on `/<culture>/sign-in/sign-in-1`.
4. Address the second area's pages through **`Page.PageExactUrl`, which accepts slashes** — so the
   whole tree lives under one path segment (`<prefix>/<slug>`, `<prefix>/news/<slug>`) without
   taking over the domain.
5. **Leave the layer's Header/Footer CONTAINER pages alone** — unaddressed and ungated. The Swift
   master renders them for every request, including the anonymous sign-in page, so gating them for
   tidiness breaks the chrome on the one page an anonymous visitor must reach.
6. Gate the second area's CONTENT pages with ROLE rows (`Anonymous = none`,
   `AuthenticatedFrontend = all`), which deny correctly; group-only grants do not
   ([dw-users-permissions](../../dw-users-permissions/SKILL.md), `page-gating.md` §15).

The second area rides the same host and the same `AccessUser` session, so a user signed in on the
primary site is already signed in on the second surface and its sign-in page is only ever seen cold
— which is usually the reason for putting both on one host in the first place. Assert the primary
area's own routes (`/`, its shop, its sign-in) in the same run: the whole claim is that the second
surface takes nothing away from the first.

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
  a market needs a different palette. See [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md).

## Cross-references

- [`modelling-discipline.md`](modelling-discipline.md) — item-type design and the custom item-type
  discipline the layer clones.
- [`page-paragraph-writes.md`](page-paragraph-writes.md) — the write surfaces every one of these
  mirrors doubles, and the `PageMenuText`-from-Title rule.
- [dw-users-permissions](../../dw-users-permissions/SKILL.md) (`page-gating.md`) — permission rows
  are not language-layered: gating a master page leaves its mirrors open.
- [dw-pim-localization](../../dw-pim-localization/SKILL.md) (`translation-mechanics.md`) — the
  product side (product names, descriptions, custom fields).
- [dw-content-localization](../../dw-content-localization/SKILL.md) — the translation flow itself.
