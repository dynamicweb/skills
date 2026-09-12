# Out-of-product recipes — Content

This reference holds the out-of-product recipes for content (pages, paragraphs, grid rows, item types and item fields, language layers): Management API
commands at `/admin/api/...`, serializer layers, and direct SQL. The in-product skills for this
area are `dynamo: true` and carry no instruction on those surfaces, so they keep a one-line pointer
here instead of the recipe.

Every recipe names its surface in the repo convention: MCP tools `snake_case` in backticks,
Management API commands `PascalCase` in backticks with the route on first use in this file,
serializer operations by command or by layer and mode, and `SQL` labelled as such in a fenced `sql`
block. Every SQL recipe states three things inline — why the higher surfaces do not cover it, that
it is **local installs only**, and the cache flush or host restart it owes.

## Contents

- [Writing `PageNavigationTag` directly](#writing-pagenavigationtag-directly)

- [Wire a language layer's Area row to the PIM language](#wire-a-language-layers-area-row-to-the-pim-language)
- [Create a language layer — `AreaCopy`, and why never an Area row clone](#create-a-language-layer--areacopy-and-why-never-an-area-row-clone)
- [Mirror permissions onto a fresh language layer](#mirror-permissions-onto-a-fresh-language-layer)
- [Repair repeater children the copier dropped](#repair-repeater-children-the-copier-dropped)
- [Repair a master grid row with a NULL GridRowItemId](#repair-a-master-grid-row-with-a-null-gridrowitemid)
- [Tell a dangling item-list pointer from an empty list](#tell-a-dangling-item-list-pointer-from-an-empty-list)
- [Load translated strings without mojibake — the sqlcmd codepage](#load-translated-strings-without-mojibake--the-sqlcmd-codepage)
- [Culture-coded area URL prefixes](#culture-coded-area-url-prefixes)
- [Clear PageShortCut baseline cruft](#clear-pageshortcut-baseline-cruft)
- [Pin a page slug and set PageNavigationTag](#pin-a-page-slug-and-set-pagenavigationtag)

## Writing `PageNavigationTag` directly

**Surface: `SQL`.** `PageNavigationTag` is not on the MCP `save_pages` model, and no Management API
command at `/admin/api/...` exposes it either, so the column is only reachable from the database.

```sql
UPDATE Page SET PageNavigationTag = 'MyTag' WHERE PageId = <pageId>;
```

Three things this recipe owes:

- **Why the higher surfaces do not cover it** — the field is absent from both the MCP page model and
  the Management API page command on 10.28.x.
- **Local installs only** — a hosted install has no SQL surface at all.
- **The debt it owes** — a host restart. The page cache is not touched by a direct column write, so
  `GetPageIdByNavigationTag()` keeps returning `0` until the application pool recycles.

Because of that third point the tag is the wrong lookup key for anything a template has just
created. Resolve a freshly created page or paragraph **by item type** instead: the paragraph cache
is invalidated by the API write that created the row, so the item-type lookup is cache-fresh on the
very next request and neither the SQL nor the restart is needed. See
[dw-render-razor](../../dw-render-razor/SKILL.md) `references/paragraph-endpoints.md` §1 for that
recipe.

## Wire a language layer's Area row to the PIM language

In-product home: [dw-content-modelling](../../dw-content-modelling/SKILL.md)
(`language-layers.md`, "Wiring the area to PIM language").

After the layer exists its `Area.AreaEcomLanguageId` still points at the master's PIM language, so
the layer renders localized chrome around master-language product values. Inside the product the
write is MCP `save_areas`, or Settings → Content → Websites → the layer → regional settings. `SQL`
is the fallback for the columns `save_areas` does not model on a given build (currency, country
code) and is **local installs only**; it owes a host restart, because the area row is read from the
startup cache.

```sql
UPDATE Area SET
  AreaEcomLanguageId = N'<LANG2>',
  AreaEcomCurrencyId = N'<EUR>',          -- usually inherited; change for markets with another currency
  AreaEcomCountryCode = N'<NL>',          -- drives the default VAT / shipping region
  AreaActive = 1
WHERE AreaId = <newAreaId>;
```

PIM must already hold the matching `LANG2` row with the products translated to it.

## Create a language layer — `AreaCopy`, and why never an Area row clone

In-product home: [dw-content-modelling](../../dw-content-modelling/SKILL.md)
(`language-layers.md`, "Creating the layer").

MCP `create_language_version` and `copy_area` are the in-product surface. Where MCP is unavailable,
or where `copy_area` is the broken one on the build in hand (it answered "Area was not copied" on
DW 10.25.6), the Management API command `AreaCopy` is proven:

```
POST /admin/api/AreaCopy
{"Model": {"SourceAreaId": <masterId>, "Name": "...", "Culture": "<culture>",
           "CopyPermissions": true, "AsWebsite": false}}
-> {"status":"ok", "modelIdentifier":"<newAreaId>"}
```

`AsWebsite=false` means a language layer (a sibling carrying the `AreaMasterAreaId` back-link);
`true` means an independent website. Some 10.25.x builds accept `Query.`-prefixed query-string
parameters instead — try the JSON body first and fall back to the query string.

**Never mint the layer with a SQL `INSERT INTO Area`.** A layer is a multi-table create (roughly 95
page clones plus paragraph, grid-row, item-localization and sibling-link bookkeeping); a row clone
produces a partially-cloned tree missing PDPs, sign-in, customer-center and every sibling-page link,
and no flush or restart repairs it. This is the one content create with no sanctioned SQL form.

The command also has a host-config prereq: it opens a second SQL connection inside a
`TransactionScope`, and without the host's distributed-transaction prereqs it fails with
`System.Transactions.TransactionException: The operation is not valid for the state of the
transaction` — an environmental error that reads as an input-shape error. The prereqs are owned by
[dw-setup-install](../../dw-setup-install/SKILL.md): the `ImplicitDistributedTransactions` opt-in,
the MSDTC service with inbound/outbound and firewall setup, and the net10-host caveat where a
fully-configured host still cannot promote and needs the `Enlist=false` connection-string
workaround.

## Mirror permissions onto a fresh language layer

In-product home: [dw-content-modelling](../../dw-content-modelling/SKILL.md)
(`language-layers.md`, "What a full-content AreaCopy does NOT carry", item 2).

Permissions are not cloned, and `CopyPermissions: true` does not change that for frontend pages — so
every protected page in the copy is public until the rows are mirrored onto the layer's sibling page
ids (`Page.PageMasterPageId` gives the mapping). Write the rows with `PermissionSave`
([`recipes-users.md`](recipes-users.md)), then flush:

```
POST /admin/api/CacheInformationRefresh {"CacheTypeName":"Dynamicweb.Security.Permissions.PermissionService"}
```

The nav tree caches separately, so a host restart is owed as well as the flush.

## Repair repeater children the copier dropped

In-product home: [dw-content-modelling](../../dw-content-modelling/SKILL.md)
(`language-layers.md`, "What a full-content AreaCopy does NOT carry", item 1).

The copier remaps repeater children with an unquoted SQL `CASE`, so STRING item ids parse as column
names, the INSERT dies with `Invalid column name '...'` (the real exception reaches only the event
log), and the paragraph clone lands with `ParagraphItemType` / `ParagraphItemId` wiped. Numeric-id
children clone fine, so the prevention is to give repeater children numeric item ids.

`SQL` is sanctioned for both halves here — MCP and the Management API are both proven broken for
this shape — and stays **local installs only**. The detection query is read-only; the repair owes a
`CacheInformationRefresh` on `ParagraphService` and `PageService`.

```sql
SELECT p.ParagraphID, p.ParagraphPageID
FROM Paragraph p JOIN Page pg ON pg.PageID = p.ParagraphPageID
WHERE pg.PageAreaId = <layerAreaId>
  AND p.ParagraphItemType = '' AND p.ParagraphModuleSystemName = '';
```

Every row is a dropped item. Per stub: clone the `ItemList` row, its child rows, the
`ItemListRelation` rows and the parent item, then re-point the stub paragraph at the clone.

## Repair a master grid row with a NULL GridRowItemId

In-product home: [dw-content-modelling](../../dw-content-modelling/SKILL.md)
(`language-layers.md`, "Every save on a mastered page costs two objects").

On a mastered page `save_grid_rows` gives the MIRROR a real `GridRowItemId` and leaves the MASTER's
row NULL, and a Swift row renders from the item INSTANCE — so the master language renders no columns
while the translation renders correctly. No verb sets `GridRowItemId` on a master row on 10.28.x,
which is why this one is `SQL`, **local installs only**, and owes a `CacheInformationRefresh` on
`ParagraphService` and `PageService`.

Allocate the id through the platform's own per-type allocator, the `ItemTypeId(ItemType, Current,
Seed)` table — never `MAX(Id)+1` on the `ItemType_<name>` table, which collides the next time the
platform allocates:

```sql
UPDATE ItemTypeId SET [Current] = [Current] + 1 WHERE ItemType = 'Swift-v2_Row';
-- then INSERT the instance row carrying the new value and stamp GridRow.GridRowItemId with it
```

## Tell a dangling item-list pointer from an empty list

In-product home: [dw-content-modelling](../../dw-content-modelling/SKILL.md)
(`language-layers.md`, "A DANGLING item-list pointer reads exactly like an empty list").

The in-product discriminator is `add_repeatable_item`, whose error names the missing list. Where the
database is reachable, a read-only `SELECT` answers the same question across a whole deserialize at
once. Read-only, **local installs only** by convention, no flush owed:

```sql
SELECT COUNT(*) FROM ItemList WHERE Id = <pointer>;   -- 0 = dangling, not empty
SELECT COUNT(*) FROM ItemList;                        -- 0 rows after the bad deserialize
SELECT COUNT(*) FROM ItemListRelation;                -- 0 rows with it
```

## Load translated strings without mojibake — the sqlcmd codepage

In-product home: [dw-content-modelling](../../dw-content-modelling/SKILL.md)
(`language-layers.md`, "The three-layer translation cascade").

`sqlcmd` defaults to the system codepage (Windows-1252 on western Windows), so a UTF-8 `.sql` file
carrying multibyte characters is mangled at parse time and stored corrupted in `NVARCHAR` even
though the literal is `N'...'` — an accented character arrives as a two-character double-encoded
sequence. Two fixes, in preference order:

```powershell

# preferred: build the statements in PowerShell (UTF-16 in memory) and never touch a .sql file
Invoke-Sqlcmd -ServerInstance "<server>" -Database "<db>" -Query $updateStatement
```

or save the `.sql` as UTF-8-with-BOM, which `sqlcmd` detects. The inline route is the more robust of
the two, since a BOM is easy to lose on re-save. To measure damage already stored, this skill ships
the read-only census script `Invoke-DwMojibakeCensus.ps1`. Restart the host after editing
`Translations.xml` (cached at startup) and after touching header item rows (composition cache).

## Culture-coded area URL prefixes

In-product home: [dw-content-modelling](../../dw-content-modelling/SKILL.md)
(`language-layers.md`, "Friendly URL config").

Switching every area to a culture code makes the language switch visible in the URL bar. The
in-product write is MCP `save_areas` (url name and the active flag, including deactivating the cruft
area a failed copy left behind). `SQL` covers the same columns where no MCP connection exists, is
**local installs only**, and owes a host restart — the URL provider caches the area URL map at
startup.

```sql
UPDATE Area SET AreaUrlName = N'en-us' WHERE AreaId = <master>;
UPDATE Area SET AreaUrlName = N'nl-nl' WHERE AreaId = <nlLayer>;
UPDATE Area SET AreaActive = 0 WHERE AreaId = <cruftLayerId>;   -- disable failed-copy cruft
```

## Clear PageShortCut baseline cruft

In-product home: [dw-content-modelling](../../dw-content-modelling/SKILL.md)
(`language-layers.md`, "PageShortCut baseline cruft").

Some baselines ship pages whose `Page.PageShortCut` points at a hardcoded old page id that does not
exist after a deserialize; the frontend 301-redirects to it and the visitor gets a 404. No MCP tool
and no Management API verb exposes `PageShortCut`, so this is `SQL`, **local installs only**, and it
owes a host restart (page metadata is cached). Clear only shortcuts whose target id is dead — a
shortcut to an id that exists (a sign-in folder pointing at its form page) is intentional.

```sql
SELECT PageId, PageAreaId, PageMenuText, PageShortCut FROM Page
WHERE PageShortCut LIKE '%Default.aspx%';
UPDATE Page SET PageShortCut = N'' WHERE PageId IN (<aboutPageId>, <clonePageIds>);
```

Add content to the now-empty page or it renders as header plus footer.

## Pin a page slug and set PageNavigationTag

In-product home: [dw-content-modelling](../../dw-content-modelling/SKILL.md)
(`page-paragraph-writes.md`, "Saves that report success but silently drop a field" and
"`save_pages` has no `navigationTag` member").

`save_pages` ignores `urlName` — the slug is derived from `menuText` — and drops `navigationTag`
silently, so both columns need a second surface. The Management API `PageSave` reaches
`PageNavigationTag`; nothing below `SQL` pins `PageUrlName`. The SQL form is **local installs only**
and owes a host restart, so batch both before the restart the job already owes, and assert the
column rather than the call's status.

```sql
UPDATE Page SET PageUrlName = N'<slug>' WHERE PageId = <pageId>;
UPDATE Page SET PageNavigationTag = N'<tag>' WHERE PageId = <pageId>;
```
