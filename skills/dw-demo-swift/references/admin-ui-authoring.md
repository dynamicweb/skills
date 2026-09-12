# admin-ui-authoring.md

> Swift 2 admin-UI authoring: the configuration-only Day-1 workflow (get 80% of the brand applied via admin Style tools alone, zero CSS / Razor / .cs edits) plus the Visual Editor patterns for editing paragraph properties without touching code. Operates against a deserialized swift/2.3 `base` layer (source-of-truth at `<demo-root>\distribution\layers\base\`).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Contents

- [The workflow + Visual Editor surface map live in the foundational skill](#the-workflow--visual-editor-surface-map-live-in-the-foundational-skill)
- [When to use + executor split](#when-to-use--executor-split)
- [Management API authoring traps (Swift 2.4 / DW 10.28.x)](#management-api-authoring-traps-swift-24--dw-1028x)
- [Resolving a page URL](#resolving-a-page-url)
- [Authoring scripts must ASSERT the shape they expect — a count guard is an anti-pattern](#authoring-scripts-must-assert-the-shape-they-expect--a-count-guard-is-an-anti-pattern)
- [Verification: did the change land via the admin UI?](#verification-did-the-change-land-via-the-admin-ui)
- [What this surface does NOT do (escape hatches)](#what-this-surface-does-not-do-escape-hatches)

## The workflow + Visual Editor surface map live in the foundational skill

Vendor-generic Swift configuration-only authoring — the 5-step Day-1 workflow (mood board → translate into admin Style tools → upload assets → connect styles via Website Settings → build layout in the Visual Editor), the Visual Editor surface map, and the "what the VE covers, and the escalation per gap" table — is owned by the `dw-swift-building` foundational skill — owned by [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §9 ("Re-skin doctrine"). Read that section for the click-paths and the per-gap escalation.

This file carries the demo-specific framing: where the mood board comes from, the executor split, and the escape hatches that are out of scope.

## When to use + executor split

The configuration-only approach is the default starting point for any Swift 2 demo re-skin — it covers most copy / asset / layout work with zero code. **Mood board source:** pull from the demo's read-only `<demo>\customer-context\` (intro-call materials, brand guide, the customer's public site as reference) — never invent.

**Executor split:** the admin click-paths in the foundational §9 surface map are the *map* of what is configurable — for a human doing manual authoring, and as verification targets. When Claude makes a change itself, it resolves the click-path to the equivalent MCP / Management API call (every Visual Editor / Style-tools save is an Admin API call underneath) per the base surface-priority rule — [dw-demo-base/references/surface-priority.md](../../dw-demo-base/references/surface-priority.md) §"Admin UI is verification-only during the build". Claude drives `/Admin` via Playwright only to verify a change landed, never to author.

Escalate to [re-skin.md](re-skin.md) §`<customer>_custom.css` only when the admin Style tools cannot express the visual you need; escalate further (content-layout `.cshtml`) only when a tailored screen requires a new rendering — see [re-skin.md](re-skin.md) §Pixel-perfect escalation. Only the controller/provider `.cs` tier triggers base's customisations-ledger preflight ([dw-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md)).

## Management API authoring traps (Swift 2.4 / DW 10.28.x)

Because every Visual-Editor / Style-tools save resolves to an Admin API call, Claude writes through
those calls directly — and several of them report success in ways that are not true. Standing rule:
**after any write, re-read the entity AND fetch the rendered page. `status=ok` and the POST response
model are not evidence.** (The general verify-by-round-trip rule is owned by
[dw-demo-base/references/surface-priority.md](../../dw-demo-base/references/surface-priority.md)
§"Silent no-ops on write surfaces"; below are the traps specific to this authoring surface.)

**`GridRowSave` — the response model lies.** It *does* accept and persist `colorSchemeId` (stock
Swift vocabulary: `light|lightgrey1|lightgrey2|dark|darksubtle|primary|secondary`), but the POST
response `.model` returns a stale/empty `colorSchemeId` and a blank `successful` flag even on a
successful write. Only a fresh `GET /Admin/Api/GridRowById?Id=<id>` reflects the committed value —
poll it until it equals the target before the next save (serialise + verify), and confirm the live
section wrapper carries `data-dw-colorscheme="<id>"`. Strip `modelIdentifier` from the model before
posting. Section colour-scheme rhythm needs no admin-UI capture/replay; the API is fully sufficient.
Related shape: `GET /Admin/Api/GridRowsByPageId?PageId=<id>` is paginated — the rows live under
`model.data` (already in render/sort order), not `model[]`. `mobileSortColumns` binds
`IEnumerable<ListOption>`, so passing it as a comma string **500s** — leave it `null`. A row-family
conversion (`4Columns` ↔ `4ColumnsFlex`) round-trips through `GridRowSave` with `definitionId`,
`originalDefinitionId` and `itemType` set **together**, and it changes the emitted column markup — which
changes which custom CSS can reach the content ([re-skin.md](re-skin.md) §"Selector reach").

**Grid ROW creation: `GridRowCreate` is the create verb, `GridRowSave` is update-only, `GridRowCopy` only
appends, and position is set exclusively by `GridRowSort`.** `GridRowSave` with `Id=0` returns **404** (it
is update-only, unlike the create/update fork on the commerce saves), and `GridRowCopy` always lands the
new row at the BOTTOM of the page with no positional argument to override it.

**`GridRowCreate` needs `Container`, and omitting it writes a BROKEN row alongside an HTTP 500.**

```
POST /Admin/Api/GridRowCreate {PageId, GridId:'Page', DefinitionId, Container:'Grid'}  -> ok, renders
POST /Admin/Api/GridRowCreate {PageId, GridId:'Page', DefinitionId}                    -> 500, AND a row
                                                                                          with GridRowContainer=''
                                                                                          that never renders
POST /Admin/Api/GridRowCreate {PageId, GridId:'Grid', …}                               -> throws
```

`GridId` is `'Page'` (the value `GridRowSelectorByPage` returns); `'Grid'` is the `Container`, and swapping
the two throws. **`GridRowContainer` is the discriminator for a row that saves and never renders**, not
`GridRowItemId` — the row item mints even on the failure path, so a NULL-`GridRowItemId` check clears a
broken row and a container check catches it. The 500 is not a rollback: assert
`SELECT GridRowContainer FROM GridRow WHERE GridRowId = <new>` is non-empty after every create, and delete
the row if it is not. `GridRowCopy` avoids the whole question (the copy carries the source's container and
renders), at the cost of arriving occupied ([paragraphs.md](paragraphs.md) §`GridRowCopy`).

So inserting a row *between* two existing rows is always **copy-then-sort**:

```
POST /Admin/Api/GridRowCopy  {PageId, Id}            -> new row appended at the bottom
POST /Admin/Api/GridRowSort  {PageId, Ids: ["<id>", "<id>", …]}   -> Ids[] are STRINGS, in target order
```

`GridRowSort` takes the complete ordered id array for the page and the ids are **strings**, not ints —
post them as numbers and the sort is rejected or silently partial. Read the current order from
`GridRowsByPageId` (`model.data` is already in render order), splice the copied row into the position you
want, and post the whole array back.

**Three safety rules govern that call:**

**1. `GridRowSort` is an ABSOLUTE ordering — the id set you post must be exactly the live row set.** A missing
id is how a row silently drops off a page; an extra one is how a sort is rejected. Diff the set you are about
to post against `GridRowsByPageId` and refuse to post on any difference.

**2. Verify the result against the DATABASE or the RENDERED DOM — never against the API model.**
`GridRowsByPageId` is served from a cache the sort verb **does not invalidate**, so after a successful
`GridRowSort` the DB and the rendered page both carry the new order while the API list query still returns the
previous one. A script that verifies its own re-sort through the API concludes **failure** — and a retry or a
revert on that basis **destroys the correct state**. The rendered page is the cheapest honest oracle (assert
the section's position in `main`, e.g. by its offset fraction down the document); the DB row order is the other.

**3. INSERT AT A POSITION — never re-derive a total order from a sort key that is not unique.** Swift pages
routinely carry duplicated `sort` values, so rebuilding the whole order with a `sort` + `id` composite sort
flattens curated layout into ascending row-id order wherever rows tie — and a shared master page ships the
damage across every language layer at once, presenting as a CSS problem.

- **Insert at a position** rather than re-deriving the total order.
- If a total order genuinely must be posted, **assert the resulting sequence against an expected id list
  BEFORE posting it**, and compare the rendered section order against a baseline afterwards.
- A script header comment noting "these sort values are duplicated" is not a guard — assert, don't annotate.

**`flexibleColumns` is inverted: `0` = flexible, `1` = fit-to-content.** In the `GridRowSave`
`flexibleColumns` array the column listed `0` silently absorbs all remaining horizontal space
(computes `flex: 1 1 auto`, `class="flex-fill"`); entries of `1` compute `flex: 0 1 auto` and size
to content. `[0,1,1,1,1,1]` reads as "column 1 is not flexible" and does the opposite — a logo
column swallowing ~960px for a 264px logo is the usual symptom. To make column N flexible, set index
N-1 to `0` and every other entry to `1`, then assert the intended column carries Bootstrap's
`flex-fill` and the others compute content-sized widths.

**`PageSave` re-derives the page `name` from the item `Title`.** When `name` is not supplied in the
same call, DW overwrites the page name from the item `Title` field and then regenerates
`friendlyUrl` from the new name — 404-ing the old URL. This bites hardest on duplicated pages, whose
item `Title` still carries the source page's title while the page `name` was renamed by hand: a save
that touched an unrelated flag renames the page and breaks a URL the demo's gate asserts.
**Never `PageSave` a page without setting `name` AND `Title` in the same call**, and keep the item
`Title` aligned with the page name afterwards or the next save renames it again. Verification: after
any `PageSave`, re-resolve (a) the saved page's own live URL and (b) every URL in the demo's gate
page list, asserting 200 or 301 — a rename shows up **only** as a 404 on the OLD url, which a
`status=ok` check and a page-object diff both miss. Also assert `name` still equals what you
submitted. **Resolve the page's own URL through the `Default.aspx?ID=<n>` redirect, not from
`friendlyUrl`** — on an API-created page that property answers `"Default.aspx?ID=n"` and proves nothing
(§"Resolving a page URL").

**`PageSave` is a WHOLE-ENTITY save, and a partial model blanks the page into a 404.** Properties absent
from the request are persisted as their type defaults, not left unchanged. `PageSave {Model:{Id, ShowInLegend:false}}`
set the flag correctly and simultaneously blanked `PageAreaId`, `PageParentPageId`, `PageMenuText`,
`PageItemType`, `PageItemId`, `PageSort` and `PageMetaTitle`:

```
before  8544 = area 27, parent 0, "About", Swift-v2_Page, item 1169
after   PageSave {Model:{Id:8544}}   ->  area 0, parent 0, name empty, itemType empty, item 1191 (new)
        /en-ca/about -> 404
```

It also does **not honour a supplied `ItemId`**: every save mints a NEW page-item instance, so the item
`Title` is lost, and because DW re-derives `PageMenuText` from that Title the tree name is one UI save away
from blanking too. There is no patch-style verb for the navigation flag, and `{Id, ShowInLegend, Active}`
blanks the same way. Used as a one-line probe against a live storefront page, this takes the page down.

**So: snapshot the `Page` row, send EVERY property back, re-read, diff, then re-set the item `Title` with
`set_page_item_fields`.** Prefer MCP `save_pages` for anything it covers. This is the page-level face of the
general rule that a `*Save` command is a whole-entity save
([`management-api-and-sql.md`](../../dw-data-access/references/management-api-and-sql.md) §"A read model is
not a save model").

**On an ITEM-BASED page, `Model.name` alone is a silent no-op — the rendered label comes from the page item's
`Title` field.** The same-call rule above is not only a rename-safety measure: writing `name` by itself
returns success and updates a value nothing renders, so navigation keeps showing the old label. Re-confirmed
across 76 page saves on one chrome pass. **Set `Model.name` AND the item `Title` in every `PageSave` against
an item-based page**, and assert the *rendered* navigation label, not the API model.

**`GridRowCopy` carries the SOURCE row's spacing tokens — a row-minting helper must reset them.** A page
generator built on "new row + `GridRowCopy`" inherits whatever spacing the copied row happened to carry, so a
whole family of generated pages ends with the same wrong band against the footer — and nothing in any model or
gate reads as wrong. Measured: four pages minted from one generator all carried the breadcrumb row's
`bottomSpacing=4` (2rem), by accident rather than by design; raising it to the definition default produced
exactly +64px clearance on every page at both viewports. Swift's token scale is `0=0, 1=.25rem, 2=.5rem,
3=1rem, 4=2rem, 5=3rem, 6=6rem` — **6 is the Swift default**, which is why an inherited `4` reads as
"slightly tight" rather than as a bug. **Reset `topSpacing` / `bottomSpacing` to the definition default on
every minted row** instead of inheriting from whichever row was convenient to copy, and assert newly minted
content pages end on the default token.

**`ProductCatalogGroupSave` regenerates the friendly URL of the group AND of every child product — with
no automatic 301.** The ecom sibling of the `PageSave` rename above, and the blast radius is larger. A
rename moves `/<lang>/shop/<old-slug>` to `/<lang>/shop/<new-slug>` and 404s the old path immediately, and
because product URLs are composed under the group, **every child PDP moves with it** — dozens of paths per
group. The host mints no redirect for the retired slug, so the damage lands on every authored link,
canonical, `og:url` and gate page list that named it.

- **Sweep for the old slug FIRST, rename, then repoint in the same run.** A rename split across two runs
  leaves a window in which half the demo 404s.
- **Updating a page URL in a gate page list is a POINTER fix, not a weakened assert** — same assertions,
  same page, same thresholds, new address. Say so explicitly in the run notes: a future agent that reads
  "the gate config changed during a rename" and treats it as a banned edit will either revert the pointer
  or leave a whole leg fetching a 404. Where the same slug appears in more than one list (a storyline page
  set *and* a design page set are the common pair) **both must move in the same run**.
- Post-rename assertion list, run explicitly rather than implied: old slug → 404, new slug → 200, at least
  two child PDPs → 200 on the new path, and every URL in every gate page list → 200 or 301.

**A group rename needs no translations save and no recycle.** `ProductCatalogGroupSave` writes the
localized name for the language carried in `modelIdentifier` (`GROUP1|ENU` shape), so a separate
`ProductCatalogGroupTranslationsSave` is not part of the motion. The URL is derived **on request**, not
from a startup-cached table, so the new slug resolves and the storefront serves the new label **before**
any recycle. Only nav MEMBERSHIP is startup-cached ([header-menu.md](header-menu.md)) — which is what makes
earlier passes attribute a whole rename to the recycle they happened to run alongside it, and pay ~3
minutes per rename for it. Verify by asserting the new label in the storefront HTML and the new slug at
200 **before** restarting anything.

**`showInLegend` is not a navigation filter.** It round-trips `false` through `PageSave` and has
ZERO effect on rendered navigation — the navigation providers do not consult it. To suppress a
duplicated nav/footer link, hide it in CSS or remove the page from the menu source; do not spend a
`PageSave` (with the rename risk above) on this flag.

**`PageCopy` is the working clone path for an ordinary content page, and it inherits more than you want.**
`GET /Admin/Api/NewPageInfoForCopy?SourcePageId=<n>&DestinationParentPageId=<m>` returns the model;
`POST /Admin/Api/PageCopy` with it copies an ordinary `Swift-v2_Page` at DW 10.28.1 including the subtree
and the language mirrors. (The "Standard pages are Not allowed" refusal belongs to the MCP `copy_page`
wrapper, not to this verb — see
[`backend-mcp-server.md`](../../dw-extend-mcp-tools/references/backend-mcp-server.md) §5.) Two inheritance
traps ride along:

- Copies carry the source page's paragraph `Button` fields verbatim, with no reset offered. One
  source CTA reappears once per copied paragraph — e.g. a single "Discover more" `FirstButton`
  duplicated across every copied row, on top of each row's own correct inline link. Blank or repoint
  `FirstButton` on every copied paragraph afterwards (as an object with blank members — see
  [paragraphs.md](paragraphs.md) §ButtonData), and assert the source label's rendered count is 0.
- A copy made as a header shortcut (`shortCut=/Default.aspx?ID=<target>`, `publicationState=
  published`) can be the page that actually renders the storefront chrome, while the page carrying
  the `navigationTag` (e.g. `ProductListPage`) sits `hideInMenu` and inert. Editing the tagged page
  then changes nothing while every API read-back reports success — a teaser authored there is
  invisible. **Resolve chrome pages by RENDERED PARAGRAPH ID, never by nav tag**: grep the delivered
  HTML for the paragraph ids you expect (breadcrumb / product-list info / component selector / list
  navigation) before and after the edit, assert the ids of the page you did NOT edit stay absent,
  and re-run the count on more than one list URL.

## Resolving a page URL

**`GET /Default.aspx?ID=<n>` with redirects disabled, reading the `Location` header, is the only reliable
page-URL resolver.** Nothing in the API will tell you a page's friendly URL: `GetPageById.friendlyUrl`
answers `"Default.aspx?ID=8947"` for an API-created page, because the property is not recomputed on that
path. The URL is resolved by the request pipeline at render time, and the pipeline exposes it through the
permanent redirect it already issues for the numeric form:

```
GET /Default.aspx?ID=8932                  -> 301  Location: /en-us/shop-by-boat/sterndrive-drivetrain
GET /Default.aspx?ID=8936                  -> 301  Location: /es-us/comprar-por-embarcacion/ventilacion-de-sala-de-maquinas-y-sentina
GET /Default.aspx?ID=8589&ProductID=PROD12426 -> 301  Location: /en-us/shop?ProductID=PROD12426
```

**Never derive a slug from the page name.** The lowercase-plus-dash-the-non-alphanumerics regex that reads
as the obvious substitute is wrong for any name carrying diacritics: DW transliterates the accent and the
regex eats it, so `"Equipo estandar y de seguridad"` derives `equipo-est-ndar-y-de-seguridad` and the helper
throws on a page that is live and healthy. In PowerShell issue the numeric request with
`-MaximumRedirection 0`, read `Location`, and **prove the result with a real 200 before writing it into
content**. Every button, card link and page map that must carry a URL depends on this step, and it is the
only resolver that works for a product URL too.

## Authoring scripts must ASSERT the shape they expect — a count guard is an anti-pattern

The traps above all fail loudly enough to be caught by a readback. This one produces **no signal at all**:
a script aimed at the wrong entity id exits 0, logs nothing, and reports success.

The shape is a filter followed by a guard:

```powershell
$targets = @($paras | Where-Object { <match> })
if ($targets.Count -ge 1) { <the entire write block> }     # <-- the anti-pattern
```

Point that at an id which holds nothing you were looking for — a footer **shortcut** page instead of the
content page, a grid row that was emptied by an earlier pass — and the filter matches zero, the guard
skips the write block, and the script exits clean with the prepared copy still sitting unused in the file.
Nothing throws, there is no status to check, and the defect is invisible until someone reads the live
site. One recorded case sat on a customer-visible page for weeks after the pass whose whole job was to
replace it.

**Open every authoring script with an assert on the shape it expects, and throw:**

```powershell
$page = Invoke-Api "GetParagraphsByPageId?PageId=$PageId"
if ($page.model.totalCount -ne $ExpectedCount) { throw "page $PageId: expected $ExpectedCount paragraphs, got $($page.model.totalCount)" }
$actualIds = @($page.model.data | Where-Object { $_.id -gt 0 } | ForEach-Object id | Sort-Object)
if (Compare-Object $actualIds $ExpectedIds) { throw "page $PageId: paragraph id set drifted" }
# ...only now the write block, unguarded
```

Generalise it to every DW authoring script: **a count guard around a write block converts "I targeted the
wrong thing" into "nothing happened, successfully".** Assert the count, assert the id set, then write
unconditionally. Prove the assert works by re-pointing the script at a deliberately wrong id and
confirming it THROWS rather than exiting 0 — an assert that has never been seen red is not a guard
([`../../dw-demo-base/references/visual-qa.md`](../../dw-demo-base/references/visual-qa.md) "Assert design
rules"). Empty grid columns come back as synthetic `id=0` placeholders, so filter to `id > 0` before
counting anything ([paragraphs.md](paragraphs.md)).

## Verification: did the change land via the admin UI?

After any Visual Editor / Style-tools edit on a running host, `git status` should show ONLY:
- `Dynamicweb.Host.Suite/wwwroot/Files/Images/<your-uploaded-asset>` (logo / hero swaps)
- `Dynamicweb.Host.Suite/wwwroot/Files/Templates/Designs/Swift-v2/<paragraph-instance-config>.json` (paragraph property persistence — config, not Razor)
- `Files/System/Styles/{ColorSchemes,Buttons,Typography}/*.{json,css}` (Style-tools saves — see [styles-assets.md](styles-assets.md))

You should NEVER see `*.cs` changes in `Controllers/` or `Providers/` (triggers base's customisations-ledger preflight), `*.scss` / `*.ts` changes (recompilation drift), or changes to any file named exactly `custom.css` (Swift-shipped sample code — brand CSS belongs in `<customer>_custom.css`; the hard rule lives in [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §9). New content-layout `.cshtml` files are part of the normal escalation ladder ([re-skin.md](re-skin.md) §Pixel-perfect escalation); *modifications* to existing standard `.cshtml` are the thing to avoid.

## What this surface does NOT do (escape hatches)

Some changes don't have an admin-UI authoring surface and require either preflight-approved customisation or live in a different skill:

- **Customer-center CSR section customisation** — never; see [customer-center.md](customer-center.md) (the stock-CSR rule).
- **Customer-flavoured products / orders seeding** — project-specific data work, not a styling concern.
- **New product fields / completeness rules** — PIM concern. See [dw-demo-pim/references/structural-model.md §2.8](../../dw-demo-pim/references/structural-model.md) and `dw-demo-pim/references/canonical-setup-order.md` step 7.
- **MCP tool wiring** — base concern. See `dw-demo-base/references/mcp-setup.md`.
- **Custom payment provider / shipping carrier / checkout handler** — out of scope **in a presales demo**, where the customisation budget cannot service it (a known trap). **The ban is scoped, and it lifts when the build is an MVP or a delivery build whose signed scope names the mechanism** — a different budget and a different definition of done. Two obligations come with that:
  - **A brief that sanctions a banned mechanism must cite the ban it overrides**, in the brief and in the code that implements it, so the conflict is recorded on the way in rather than argued at the customisation-budget gate, by which time the work is done.
  - **A lifted ban still owes the surface.** A ban with no alternative is what turns a sanctioned customisation into a run of silent platform failures measured out of the assemblies one at a time. Where the corpus carries no recipe for the sanctioned mechanism, say so explicitly in the brief and treat writing one as part of the work — the provider and checkout-handler surfaces live in [`dw-extend-providers`](../../dw-extend-providers/SKILL.md).
- **`<customer>_custom.css` / `.scss` / `.cshtml` work** — the escalation ladder in [re-skin.md](re-skin.md). (Brand CSS never goes in a file named `custom.css` — that's Swift-shipped sample code; hard rule in [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §9.)
