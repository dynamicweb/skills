# language-layers.md

> Content-side localization in Dynamicweb 10 â€” adding a language layer to a website (sibling Area row), wiring the language management settings, and exposing the `Swift-v2_LanguageSelector` paragraph so visitors can switch. Sister doc to `dynamicweb-pim-demo/references/localization.md` (PIM/product side).
>
> **TL;DR:** A language layer is a **sibling `Area` row** under the same Website, with `AreaMasterAreaId` pointing back to the master area and `AreaCulture` / `AreaEcomLanguageId` set to the new locale. Admin UI flow is Settings â†’ Content â†’ Websites â†’ "+ New website Language" â†’ pick the master to copy from. All pages/paragraphs/grid-rows from the master are cloned into the new Area at create-time; from then on the language management settings (see "The eight knobs" below) decide whether subsequent master changes propagate. Frontend switches between layers via the OOTB `Swift-v2_LanguageSelector` paragraph, which renders one anchor per active sibling area and currency-formats accordingly.

## When to use

- A second-language storefront under the SAME brand/website (different culture, different translated copy, often a different currency/country default).
- Multi-market demos ("we sell into BE / DE / FR" â†’ three language layers under one master).

If the question is "translate product names + descriptions for an existing area," that's PIM-side â€” see [`../../dw-demo-pim/references/localization.md`](../../dw-demo-pim/references/localization.md). Content-side language layers do NOT translate product field values; they read whichever `AreaEcomLanguageId` you wire and PIM serves the right product strings via its own translation tables.

## The two-table mental model

| Side | Table | Identifier | Notes |
|------|-------|-----------|-------|
| Content (this doc) | `Area` | int `AreaId`, sibling rows share `AreaMasterAreaId` | One `Area` row per language layer. The master area has `AreaMasterAreaId=0` or NULL; siblings point back to it. |
| PIM (sister doc) | `EcomLanguages` | string `LanguageId` like `LANG1` | Separate identifier space; bridged via `Area.AreaEcomLanguageId`. |

The legacy `Languages` (content) table is empty in a fresh dw10-suite scaffold. Modern DW10 stores all language-layer state on the `Area` row itself; the `Languages` table is a legacy artefact and can be ignored.

## What gets created when you add a language layer (admin UI)

Per the official doc page `dynamicweb10/content/websites.html`, the flow is:

1. Settings â†’ Content â†’ Websites â†’ context menu on the website â†’ "+ New website Language".
2. Pick which existing website (the **master**) to copy from.
3. Provide a name (e.g. "<brand> NL") and a regional setting (e.g. `nl-NL`).
4. Click Create.

Backstage, DW10 does:

- INSERT into `Area` â€” a new row with:
  - `AreaName` = the name you typed
  - `AreaCulture` = the regional setting you picked
  - `AreaMasterAreaId` = the master's `AreaId`
  - `AreaEcomLanguageId` = inherited from master initially; you change this in the area settings afterwards to bridge to a different PIM language
  - `AreaEcomCurrencyId`, `AreaEcomCountryCode` = inherited from master, change as needed
  - Most other Area-item settings are NULL initially
- For every Page under the master: a sibling Page is created under the new Area with the same structure. Paragraphs + grid rows are cloned.
- The clones are created in whatever state the **Language Management** settings dictate (see next section).

After the flow, the page tree under the new area mirrors the master, and editors translate strings per page/paragraph using the same admin tools (Visual Editor, Translations panel).

## The eight knobs ("Language Management" settings)

Settings â†’ Areas â†’ Content â†’ Language Management. Read but **don't change** during a demo build â€” the defaults are usually right. Each toggle controls cross-website propagation:

| Setting | What it does |
|---------|-------------|
| Unpublish new paragraphs and rows | New paragraphs/rows on master â†’ unpublished on language layer (default: ON so translators review before going live) |
| Unpublish new pages | New pages on master â†’ unpublished on language layer |
| Allow paragraph operations (create/copy/move/delete/sort) | Editors on language layer can structurally edit paragraphs (default: OFF â€” translators only edit text) |
| Copy master changes to language versions if values are the same (Pages) | If a page property on master is edited AND the language layer still had the master's old value, copy the new value. Stops once a translator overrides |
| Copy master changes to language versions if values are the same (Paragraphs) | Same logic for paragraphs |
| Compare paragraphs as text | When detecting "same value," ignore HTML formatting differences |
| Make published / unpublished status independent of master | Master publish/unpublish does NOT cascade to language layers |

These knobs decide whether a demo build that races ahead on the master keeps the language layer in sync, or requires manual re-translation per change.

## Wiring the area to PIM language

After creating the language-layer area, **change `Area.AreaEcomLanguageId`** to the matching PIM `EcomLanguages.LanguageId` (e.g. `LANG2`). Without this, the language layer renders all product values in master language (LANG1) even though the UI chrome is in nl-NL.

```sql
UPDATE Area SET
  AreaEcomLanguageId = N'<LANG2>',
  AreaEcomCurrencyId = N'<EUR>',          -- usually inherited; change for markets with different currency
  AreaEcomCountryCode = N'<NL>',          -- for default VAT/shipping region
  AreaActive = 1
WHERE AreaId = <newAreaId>;
```

PIM must have a matching `LANG2` row + the products you care about translated to that LanguageId. See `dynamicweb-pim-demo/references/localization.md`.

## The Swift OOTB language switcher

Swift ships `ItemType_Swift-v2_LanguageSelector` â€” a paragraph type that renders a dropdown/list of all the active sibling areas for the current master. Schema (verify on your DW version):

| Field | Notes |
|-------|-------|
| `Label` | Optional label shown before the dropdown |
| `Icon` | Optional SVG path |
| `ShowLanguageName` | bit â€” if 0, only the flag/icon shows |
| `ShowLanguageCurrency` | bit â€” appends the area's currency code |
| `HideLanguageFlag` | bit â€” invert from showing-flags |
| `LanguageNameFormat` | "Native" / "English" / "Code" |

To wire it:

1. Add a `Swift-v2_LanguageSelector` paragraph to a header grid row on the **master area** (typically inside the Desktop Header page tree). The same item replicates to language layers via the page clone.
2. Set its fields per the table above. Most demos: Label="", ShowLanguageName=1, LanguageNameFormat="Native", HideLanguageFlag=0.
3. Restart the host so the header grid composition cache reloads.

Frontend behaviour: clicking an entry navigates to the SAME page on the target sibling area â€” DW10 maintains a sibling-page relationship via the clone metadata so `/<master>/some-page` swaps cleanly to `/<lang>/some-page`. If a sibling page doesn't exist (e.g. master added a new page but language layer hasn't been re-synced), the link falls back to the language layer's frontpage.

### Alternative: a master-template toggle (cache-safe, brandable â€” validated 2026-06-09)

When the OOTB selector paragraph is awkward â€” the header grid composition is cached (restart per insert), every language layer needs its own paragraph wired (step 6 below), or the demo wants a branded pill instead of a dropdown â€” a small block in `Swift-v2_Master.cshtml` just before `@ContentPlaceholder()` does the same job with none of the content-cache friction. Razor recompiles live, so iterating on it costs nothing. Note this IS an edit to a stock template, which [re-skin.md](re-skin.md) treats as last-resort: acceptable here because the block is small, self-contained, and uses only canonical APIs â€” keep it clearly comment-delimited and note it in the demo's working notes for upgrade-time diffing.

The sibling-page resolution is two asymmetric lookups:

```csharp
int target = 0;
if (Pageview.Area.ID == <masterAreaId>)
{
    // master â†’ layer: find the clone whose MasterPageId points at the current page
    target = Dynamicweb.Content.Services.Pages.GetPageIDByMasterID(Pageview.Page.ID, <layerAreaId>);
}
else
{
    // layer â†’ master: the clone carries the back-link directly
    target = Pageview.Page.MasterPageId != 0 ? Pageview.Page.MasterPageId : 0;
}
if (target == 0) { target = <counterpartAreaHomePageId>; }  // page only exists on one side
```

Emit `<a href="/Default.aspx?ID=@target" hreflang="...">` â€” DW's URL provider rewrites it to the friendly slug. Round-trip both directions during verification, including a page that only exists on one side (exercises the Home fallback). Two-layer demos can hardcode the two area ids; for 3+ layers, resolve siblings via `Area.AreaMasterAreaId` instead.

## Recipe â€” adding a language layer to a Swift demo

**Hard rule:** a language layer is a multi-table CREATE that DW does ~95 page clones + paragraph/grid-row/item-localization/sibling-link bookkeeping for. The base skill's "Surface priority for CREATES" rule applies in full â€” MCP first, then Management API, then admin UI, **never raw SQL `INSERT INTO Area`**. A SQL clone produces a partially-cloned tree (the 7 stub pages DW auto-creates when it notices a new sibling Area) that looks plausible in the page picker but is missing PDPs, sign-in, customer-center, and the sibling-page links the LanguageSelector relies on. Cleanup is then harder than just using the right surface in the first place. The author of this skill burned an hour on this; you do not need to repeat the lesson.

1. **Confirm master area state.** `SELECT AreaId, AreaName, AreaUrlName, AreaMasterAreaId, AreaCulture, AreaEcomLanguageId, AreaEcomCurrencyId, AreaEcomCountryCode FROM Area`. The master should have `AreaMasterAreaId=0`.
2. **Pre-stage PIM** â€” add the new `EcomLanguages` row (MCP `save_languages` first; Management API `Languages` family as fallback; SQL only as last resort) and translate the hero products + groups per `dynamicweb-pim-demo/references/localization.md`. Doing this first means the language layer has something to render when it's created.
3. **Prereqs (BOTH must be in place â€” verify via `dynamicweb-demo-base/references/setup-checks.md` Â§"MSDTC for cross-connection TransactionScope"):**
   - `Program.cs` has `System.Transactions.TransactionManager.ImplicitDistributedTransactions = true;` set before `WebApplication.CreateBuilder` (see `dynamicweb-demo-base/references/scaffold.md` Â§2.1b â€” the .NET 7+ opt-in).
   - MSDTC service running + inbound/outbound enabled + DTC firewall rules enabled (one-time per machine).

   Without either, the AreaCopy call below fails with `System.Transactions.TransactionException: The operation is not valid for the state of the transaction.` The error LOOKS like it could be transactional logic, but it's environmental â€” fix the prereqs, do not change the input shape.

   **net10 hosts: the prereqs above are NOT sufficient (validated DW 10.25.x, 2026-06-09).** On a net10 single-target host (the scaffold default â€” the AppStore Backend MCP AddIn requires it), a full `StructureAndContent` copy opens a second SQL connection inside the TransactionScope, the transaction tries to promote to MSDTC, and **`System.Data.SqlClient` cannot promote on .NET 10** â€” the same `TransactionException` fires even with `ImplicitDistributedTransactions = true` and MSDTC fully configured. Both the MCP `copy_area` path and the Management API `AreaCopy` path hit it. The working workaround:

   1. Take a DB snapshot/backup (the copy will run non-transactionally â€” no rollback if it dies midway).
   2. Add `Enlist=false` to DW's `<ConnectionString>` in `GlobalSettings.Database.config` and restart the host.
   3. Run the AreaCopy. With enlistment off, the second connection never joins the transaction, so no promotion is attempted.
   4. Revert the connection string and restart again â€” `Enlist=false` is a copy-window setting, not a permanent one.

   Diagnostics: the API response and stdout carry no useful detail â€” the real exception lands in `Files/System/Log/EventViewer/<guid>.log`.

4. **Create the language layer â€” surface order (per base skill rule):**
   - **4a. Management API (proven).** `POST /admin/api/AreaCopy` with body:
     ```json
     {"Model": {"SourceAreaId": <masterId>, "Name": "<brand> <lang>", "Culture": "<culture>", "CopyPermissions": true, "AsWebsite": false}}
     ```
     `AsWebsite=false` = language layer (sibling of master with `AreaMasterAreaId` back-link). `AsWebsite=true` = full separate website (no sibling link). Returns `{status: "ok", modelIdentifier: "<newAreaId>"}` in ~7s for a 95-page Swift tree. DW does the entire clone â€” pages, paragraphs, grid rows, items, item links, color swatches, item-type layouts â€” inside one TransactionScope. On a 10.25.x build the endpoint instead accepted its parameters as `Query.`-prefixed query-string params (e.g. `/Admin/Api/AreaCopy?Query.SourceAreaId=<id>&Query.Name=...`) â€” try the JSON body first, fall back to the query-string shape if the body is ignored.
   - **4b. MCP fallback.** `mcp__dynamicweb-commerce-mcp__copy_area` accepts `{areaId, name}` per its schema, but **as of DW 10.25.6 it returns "Area was not copied" with no actionable detail**. The Management API endpoint above is the working primary surface. If MCP exposes a `language_layer`-specific tool in a future build, prefer it.
   - **4c. Admin UI fallback (ask the user to click).** Settings â†’ Content â†’ Websites â†’ context menu on the master website â†’ "+ New website Language" â†’ name + regional setting â†’ Create. Same `/admin/api/AreaCopy` endpoint under the hood; use only if the API is unavailable â€” and per the base surface-priority rule, Claude doesn't drive `/Admin` for changes, so this route is a user one-click.
   - **4d. SQL is NOT a fallback for the create.** Reserve SQL for post-create wiring (the `AreaEcomLanguageId` update in step 5), for cleanup of a previous bad attempt, and for read-side discovery. Cloning the page tree via SQL is the trap this rule exists to prevent.
5. **Wire the area** to the PIM language + URL slug (small UPDATE â€” MCP `save_areas` preferred, SQL acceptable):
   ```sql
   UPDATE Area SET AreaEcomLanguageId = N'<LANG2>', AreaEcomCurrencyId = N'<EUR>', AreaEcomCountryCode = N'<NL>', AreaUrlName = N'<nl>' WHERE AreaId = <newAreaId>;
   ```
6. **Add `Swift-v2_LanguageSelector` paragraph** to (a) the master header AND (b) each language layer's header â€” because the layer clones happened in step 4 BEFORE the LanguageSelector existed, so it doesn't propagate to them automatically. Insert one paragraph per header page. Set `ParagraphTemplate='Modal.cshtml'` (the OOTB Swift modal launcher). The same `ItemType_Swift-v2_LanguageSelector` item Id can be referenced from all three paragraphs â€” items are shared.
7. **Restart host** so the header grid composition cache reloads â€” paragraphs are cached aggressively. Then `BuildIndex` on the Products repo so the per-language EcomProducts rows from step 2 land in the storefront search index:
   ```
   POST /admin/api/BuildIndex {"Repository":"Products","IndexName":"Products.index","BuildName":"Full","BuildType":"Full"}
   ```
   Without the rebuild, the category/PLP renders the master language strings even on the layer.
8. **Translate header/footer text + key page items** that the demo flow touches. Use the Visual Editor's Translations panel on each paragraph the storyline lands on. Same depth-not-width rule as PIM: localize the **demo path**, not the whole site.
9. **Verify**: switch via the LanguageSelector in the storefront. URL changes to `?ID=<layerHomePageId>` initially (DW resolves friendly slugs once routing context updates). Page title + h1 + breadcrumb + nav + group descriptions render in the new language; product cards on the category page render localized names + descriptions for any SKU that has a per-language EcomProducts row (others fall back to master). Walk a PDP and the customer-center to confirm those pages exist on the layer â€” if they 404, step 4 didn't run a full clone and you need to redo it on the proper surface.

## What a full-content AreaCopy does NOT carry â€” post-copy verification (validated DW 10.25.x, 2026-06-10)

A `StructureAndContent` copy that returns `status: ok` is **not** a complete clone. Four classes of content silently don't make it; all four surfaced on one demo's language layer, and each one renders as a different confusing symptom weeks later. Run this section as a checklist immediately after every AreaCopy.

### 1. Custom items with STRING-id repeater children are dropped (copier bug)

The copier remaps repeater children with an **unquoted** SQL CASE â€” `CASE [ItemListRelationItemId] WHEN acme-home-stat-1 THEN 21 ...` â€” so string item ids parse as column names and the INSERT dies with `Invalid column name 'acme'` (real exception only in `Files/System/Log/EventViewer/<guid>.log`). The paragraph clone still lands, but with `ParagraphItemType`/`ParagraphItemId` wiped â€” a **stub** that renders nothing. Items without children, and items whose children have numeric ids, clone fine. MCP `copy_paragraph` fails the same way on the same items.

- **Detect:** `SELECT p.ParagraphID, p.ParagraphPageID, p.ParagraphHeader FROM Paragraph p JOIN Page pg ON pg.PageID = p.ParagraphPageID WHERE pg.PageAreaId = <layerAreaId> AND p.ParagraphItemType = '' AND p.ParagraphModuleSystemName = ''` â€” every row is a dropped item.
- **Fix (per stub):** manual SQL clone â€” new `ItemList` row per repeater (`ItemListItemType` = the child type), child-row INSERTs into `ItemType_<ChildType>` (translate the text inline while you're there), `ItemListRelation` rows, parent row in `ItemType_<ParentType>` with the new list id in its list column, then `UPDATE Paragraph SET ParagraphItemType=..., ParagraphItemId=...` on the stub. This is a sanctioned SQL exception to the surface-priority rule: MCP and the Management API are both proven broken for this shape.
- **Clean up the orphans** the failed copies leave behind: empty `ItemList` rows referenced by no parent list-column, numeric-id child rows referenced by no `ItemListRelation`, and lists whose relations still point at the MASTER's children.
- **Prevention:** give repeater children **numeric item ids** when seeding custom item types â€” string ids are the natural hand-seeding choice and the one that breaks every future copy.

### 2. `UnifiedPermission` rows are NOT cloned

Anon-gates and role-gates built on the Permission entity store (the canonical pattern â€” see [`dw10-canonical-surfaces.md`](dw10-canonical-surfaces.md)) silently don't apply to the layer: a CSR section gated on the master was visible to every signed-in user on the clone, and the master's anon-gated shop was wide open. Mirror every master row onto the layer's sibling page id (`Page.PageMasterPageId` gives the mapping), then `POST /admin/api/CacheInformationRefresh {"CacheTypeName":"Dynamicweb.Security.Permissions.PermissionService"}` AND restart (the nav tree caches separately).

### 3. Hardcoded page ids in template role-gates miss the clones

Any template gate of the form `if (node.PageId == <dashboardId> && !isRole) { continue; }` stops working on the layer â€” the clone has its own id. Make the check master-aware and it covers every area at once:

```csharp
int MasterId(int id) { var p = Dynamicweb.Content.Services.Pages.GetPage(id); return (p != null && p.MasterPageId > 0) ? p.MasterPageId : id; }
if (MasterId(node.PageId) == <dashboardId> && !isRole) { continue; }
```

Audit candidates: navigation node templates, MyAccount/avatar dropdowns, customer-center masters.

### 4. Component selectors still point at the MASTER's component pages

The clone of a `ProductComponentSelector` (and the `ProductComponentSlider`'s `ListComponentSource`) keeps the master's page id in `ComponentSource`. The layer's PDP then "works" â€” but renders the **master-language** item labels, and both areas share one `RenderGrid` cache entry (whichever context renders first wins â€” see [`paragraphs.md`](paragraphs.md)). Repoint the layer's selector items at the layer's own component-page clones via `set_item_field_values`; each area then has its own cache key and its own translatable label items. Restart afterwards.

### Verification probe â€” enter through the shop route

When probing the layer's PDP, use `/Default.aspx?ID=<layer-shop-page>&ProductID=X[&VariantID=Y]`. Hitting the PDP **wrapper** page id directly renders without ecom product context â€” every product component returns null and the page looks catastrophically broken when nothing is actually wrong.

## The three-layer translation cascade â€” must localize all three

A common surprise: after creating the language layer + translating products, the storefront still shows English chrome in the header (My account / Cart / Favorites), English search placeholder, English button labels in hero CTAs, etc. The reason is that Swift v2 frontend pulls user-visible strings from **three independent sources** â€” none of them cascades into the others. To fully cover a language layer, all three must be addressed.

| Layer | What it contains | Where it lives | When to translate |
|-------|------------------|----------------|-------------------|
| **1. `Translations.xml`** | UI chrome strings called via `@Translate("...")` in cshtml (Search here, Sign in, Add to cart, Page not found, footer headings, etc.) | `Files/Templates/Designs/Swift-v2/Translations.xml` | After enabling a new locale that's not already in the file. Stock Swift ships ~2170 keys with en-GB / da-DK / nb-NO / en-US / en-DK / nl-NL â€” **no fr-FR, no de-DE**. Adding a new locale = bulk-inject `<translation culture="<locale>">` children per key. |
| **2. Per-clone Item `Title` fields** | Header chrome â€” `Swift-v2_MyAccount`, `Swift-v2_MiniCart`, `Swift-v2_Favorites` render their visible label from `Model.Item.GetString("Title")` directly; they do **NOT** fall through to `@Translate`. Same pattern for some navigation labels. | `ItemType_Swift-v2_<Type>` rows in DB | After AreaCopy. The clone copies the English `Title` text into every language-layer's new item row; each one needs an individual UPDATE. Map header-pageâ†’item-id via `Paragraph.ParagraphItemId` filtered by `ParagraphPageId` for that area's header pages. |
| **3. DB content** | Paragraphs, products, groups, page menu text | `ItemType_Swift-v2_Text` / `_Poster` / `_Feature` rows on language-layer page clones; `EcomProducts` / `EcomGroups` per `ProductLanguageId`; `Page.PageMenuText` | After AreaCopy. The clones exist but with master text â€” UPDATE the language-layer Item rows individually. PIM products + groups via [`../../dw-demo-pim/references/localization.md`](../../dw-demo-pim/references/localization.md). |

**How to apply in order:** (1) bulk-inject the new locale's entries into `Translations.xml` for visible keys, (2) UPDATE the cloned MyAccount/MiniCart/Favorites/etc. `Title` fields on the language-layer item rows, (3) translate the DB paragraphs / products / groups. **Restart the host** after editing `Translations.xml` (cached at app startup) and after touching header item rows (paragraph composition cache). The DB content updates for page paragraphs flush via the normal page cache cycle.

### Translations.xml â€” selective fr-FR injection example

Don't try to translate all 2170 keys. Aim for the ~80-150 visible chrome strings â€” the rest fall back to en-GB gracefully. PowerShell pattern (run from project root after backing up the file):

```powershell
[xml]$doc = Get-Content '<host>\wwwroot\Files\Templates\Designs\Swift-v2\Translations.xml' -Raw -Encoding UTF8
$frMap = @{ 'Search here' = 'Rechercher ici'; 'My account' = 'Mon compte'; 'Cart' = 'Panier'; <# ... #> }
foreach ($k in $doc.translations.key) {
    if (-not $frMap.ContainsKey($k.name)) { continue }
    if ($k.translation | ? culture -eq 'fr-FR') { continue }
    $t = $doc.CreateElement('translation'); $t.SetAttribute('culture','fr-FR')
    $t.AppendChild($doc.CreateCDataSection($frMap[$k.name])) | Out-Null
    $k.AppendChild($t) | Out-Null
}
$doc.Save('<...>\Translations.xml')
```

### Per-clone header item Titles â€” map then update

```sql
-- Map: which item IDs of each type belong to each area's header pages
SELECT p.ParagraphItemType, p.ParagraphItemId, p.ParagraphPageId, pg.PageAreaId
FROM Paragraph p JOIN Page pg ON p.ParagraphPageId = pg.PageId
WHERE p.ParagraphItemType IN ('Swift-v2_MyAccount','Swift-v2_MiniCart','Swift-v2_Favorites')
ORDER BY pg.PageAreaId, p.ParagraphItemType;

-- Then UPDATE each language layer's item rows:
UPDATE [ItemType_Swift-v2_MyAccount] SET Title=N'Mon compte' WHERE Id IN (<frHeaderItemIds>);
UPDATE [ItemType_Swift-v2_MiniCart]  SET Title=N'<div class="dw-paragraph">Panier</div>' WHERE Id IN (<frHeaderItemIds>);
UPDATE [ItemType_Swift-v2_Favorites] SET Title=N'<div class="dw-paragraph">Favoris</div>' WHERE Id IN (<frHeaderItemIds>);
```

The MiniCart and Favorites `Title` columns store **HTML fragments** (`<div class="dw-paragraph">...</div>`) per the OOTB content â€” preserve the wrapper.

## Nav-tree leaks the master area on language layers â€” `LocalizeLink` template patch

DW10's `Dynamicweb.Frontend.Navigation.NavigationTreeViewModel` builds nav-tree node `Link` values rooted at the **master area's Shop page** (the first page found with `PageNavigationTag="Shop"`), regardless of the requesting page's area. On a language-layer home page, the header dropdown therefore renders `<a href="/<masterUrlName>/shop?GroupID=GROUP7">` even though the visitor is on `/<langUrlName>/`. Clicking such a link dumps the visitor back into the master area's English storefront. The friendly URL provider itself is correct â€” `/Default.aspx?ID=<layerShopId>&GroupID=...` rewrites cleanly to `/<langUrlName>/shop?...` â€” the bug is in the nav tree's choice of page ID.

**Templates affected** (Swift v2): `Navigation/Navigation.cshtml`, `Paragraph/Swift-v2_MenuRelatedContent/Menu.cshtml`, `Paragraph/Swift-v2_MenuProductGroupImages/Menu.cshtml` (the megamenu typically used on the header for product groups). Plus any custom nav-rendering template that uses `<a href="@node.Link">` straight from the nav tree.

**Fix** â€” drop this helper into each affected template (inside `@functions { ... }` or top of file) and call it everywhere `node.Link` is emitted:

```csharp
string LocalizeLink(string link)
{
    if (string.IsNullOrEmpty(link)) return link;
    var area = Pageview?.Area;
    if (area == null || area.MasterAreaId <= 0) return link;  // master area or no language layer: passthrough
    var master = Dynamicweb.Content.Services.Areas.GetArea(area.MasterAreaId);
    if (master == null || string.IsNullOrEmpty(master.UrlName) || string.IsNullOrEmpty(area.UrlName)) return link;
    var masterPrefix  = "/" + master.UrlName.Trim('/') + "/";
    var currentPrefix = "/" + area.UrlName.Trim('/') + "/";
    if (link.StartsWith(masterPrefix, StringComparison.OrdinalIgnoreCase))
        return currentPrefix + link.Substring(masterPrefix.Length);
    return link;
}
```

Then `href="@node.Link"` â†’ `href="@LocalizeLink(node.Link)"`. Razor recompiles live; no restart needed once the file is saved. Verify by curl'ing the layer's home: `grep -o 'href="[^"]*shop[^"]*"' nl-home.html | sort -u` should show only `/<layerUrlName>/shop?...`, no `/<masterUrlName>/...` leaks.

**Why not fix it upstream?** DW10's `GetPageIdByNavigationTag("Shop")` API does respect the current area when called from a Razor template, but the NavigationTreeViewModel is built earlier in the request pipeline (during header composition) and caches the master-rooted links. Patching the tree builder would mean shipping a custom AddIn; the per-template helper above keeps the fix in the design layer.

## Friendly URL config â€” culture-coded area prefixes

Out-of-the-box Swift demos often use `AreaUrlName='swift-2'` (the dotnet template default) or some demo-specific slug for the master area. For a multi-language demo, switch all areas to culture codes â€” it makes the language switch visible in the URL bar and reads as "standard config" to customers familiar with `<locale>/...` URL conventions.

```sql
UPDATE Area SET AreaUrlName = N'en-us' WHERE AreaId = <master>;
UPDATE Area SET AreaUrlName = N'nl-nl' WHERE AreaId = <nlLayer>;
UPDATE Area SET AreaUrlName = N'fr-fr' WHERE AreaId = <frLayer>;
-- and disable any cruft language layers from earlier failed AreaCopy attempts:
UPDATE Area SET AreaActive = 0 WHERE AreaId = <cruftLayerId>;
```

Restart the host (URL provider caches the area URL map at startup). This is the friendly-URL change customers ask for when they say "I don't want `swift-2` in the URL." Combined with the `LocalizeLink` patch above it makes the language switch behave coherently.

## SQL files with non-ASCII characters â€” encoding pitfall

If translating products / groups via a `.sql` file run through `Invoke-Sqlcmd -InputFile`, beware: sqlcmd defaults to interpreting input as the system codepage (Windows-1252 on western Windows). A UTF-8-encoded `.sql` file containing French/German/Polish multibyte characters gets mangled at parse time â†’ stored corrupted in NVARCHAR columns even though the column is Unicode and the literal is `N'...'`. Symptom in the storefront: `Ã©` renders as `ÃƒÂ©`, `Ã§` as `ÃƒÂ§`, `Ã¼` as `ÃƒÂ¼`.

**The fix is to skip the file entirely.** Build the UPDATE statements in PowerShell directly (its strings are UTF-16 in memory) and pass them to `Invoke-Sqlcmd -Query`:

```powershell
$frProducts = @(
  @{ Id='PROD1'; Name='Casque gaming lÃ©ger GXT 418P Rayne'; Short='Casque gaming circumaural lÃ©ger...' },
  # ...
)
foreach ($p in $frProducts) {
  $nameEsc  = $p.Name.Replace("'", "''")
  $shortEsc = $p.Short.Replace("'", "''")
  Invoke-Sqlcmd -ConnectionString $conn -Query "UPDATE EcomProducts SET ProductName=N'$nameEsc', ProductShortDescription=N'$shortEsc' WHERE ProductId=N'$($p.Id)' AND ProductLanguageId='LANG3'"
}
```

This keeps the strings in UTF-16 from PowerShell source â†’ sqlcmd â†’ NVARCHAR column with no codepage round-trip. Alternative: save the `.sql` file as **UTF-8 with BOM** (sqlcmd detects the BOM and switches to UTF-8 parsing) â€” but the BOM is easy to lose when re-saving from a different editor, so the PowerShell-inline approach is more robust.

## "About Us" / "Privacy" / similar pages 404 after deserialize â€” `PageShortCut` baseline cruft

Some Swift baselines ship pages whose `Page.PageShortCut` column points at a hardcoded old URL (`Default.aspx?Id=107` is the canonical example â€” that's the original Swift "About" page ID, which doesn't exist in any post-deserialize tree). The frontend 301-redirects the page request to that stale `Id=`, which then 404s.

```sql
-- Find them:
SELECT PageId, PageAreaId, PageMenuText, PageShortCut FROM Page
WHERE PageShortCut LIKE '%Default.aspx%' OR PageShortCut LIKE '%Id=10%';

-- Clear:
UPDATE Page SET PageShortCut = N'' WHERE PageId IN (<aboutPageId>, <clonesPageIds>);
```

Restart afterwards (page metadata cached). Add demo content to the now-empty page or it'll render as just header+footer with no body.

## Common gotchas

- **Empty area shows master content.** If the language-layer area renders the same strings as the master, check `Area.AreaEcomLanguageId` is set to a `LanguageId` that actually has product translation rows in `EcomProductTranslation`. Bridging is two-step.
- **LanguageSelector shows only one language.** It only lists areas with `AreaActive=1` AND `AreaMasterAreaId = (current area's master)`. If you forgot to flip `AreaActive=1` after creating the sibling, the selector hides it.
- **URL slug collides.** Two sibling areas with the same `AreaUrlName` will route the second one to 404. Pick distinct slugs (`/`, `/nl`, `/de`).
- **Language layer page count drift.** New pages added to master after the language layer was created land **unpublished** on the layer (per the default "Unpublish new pages" knob). Translators have to publish each one. For a demo, decide upfront: either freeze the master after creating layers, OR turn off "Unpublish new pages" if you want changes to propagate live.
- **Custom CSS / fonts.** Tier-0 Style assets (`Files/System/Styles/{ColorSchemes,Buttons,Typography}/`) are area-row-scoped via `AreaColorSchemeGroupId` etc. Newly-cloned language layers **inherit the master's style IDs** â€” so the brand stays consistent without extra work. But verify if your demo needs a different palette per market.

## Cross-references

- [`../../dw-demo-pim/references/localization.md`](../../dw-demo-pim/references/localization.md) â€” the product side (translate product names, descriptions, custom fields).
- [`styles-assets.md`](styles-assets.md) â€” Style asset inheritance (language layers reuse the master's brand).
- [`re-skin.md`](re-skin.md) â€” escalation ladder for per-language CSS overrides (rarely needed; Tier-0 schemes usually cover).
- Official Dynamicweb docs:
  - `https://doc.dynamicweb.dev/manual/dynamicweb10/content/websites.html`
  - `https://doc.dynamicweb.dev/manual/dynamicweb10/settings/areas/content/languagemanagement.html`


