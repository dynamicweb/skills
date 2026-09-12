# language-layers.md

> Content-side localization in Dynamicweb 10 — adding a language layer to a website. Sister doc to `dw-demo-pim/references/localization.md` (the PIM/product side).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Contents

- [What the foundational skill owns](#what-the-foundational-skill-owns)
- [SECURITY — an AreaCopy publishes every protected page in the new layer](#security--an-areacopy-publishes-every-protected-page-in-the-new-layer)
- [Normalise page shortcuts BEFORE the copy — a leading slash defeats the link remapper](#normalise-page-shortcuts-before-the-copy--a-leading-slash-defeats-the-link-remapper)
- [Localised ecom URLs need BOTH settings on the layer's shop page](#localised-ecom-urls-need-both-settings-on-the-layers-shop-page)
- [Audit group `primaryPageId` after every AreaCopy — at the shop page it blanks every PDP](#audit-group-primarypageid-after-every-areacopy--at-the-shop-page-it-blanks-every-pdp)
- [A master-layer `ParagraphSave` writes THROUGH to the language layers](#a-master-layer-paragraphsave-writes-through-to-the-language-layers)
- [The recycle bin is keyed to the MASTER row, and `totalCount` always reads 0](#the-recycle-bin-is-keyed-to-the-master-row-and-totalcount-always-reads-0)
- [`Translations.xml` keys are case-sensitive — and the shipped file carries case-variant pairs](#translationsxml-keys-are-case-sensitive--and-the-shipped-file-carries-case-variant-pairs)
- [Demo judgement — localize the demo path, not the whole site](#demo-judgement--localize-the-demo-path-not-the-whole-site)
- [Cross-references](#cross-references)

## What the foundational skill owns

The entire vendor-generic content-side language-layer model is owned by the `dw-content-modelling`
foundational skill — staged in
[`language-layers.md`](../../dw-content-modelling/references/language-layers.md) §3
("Content-side language layers"). That section owns:

- The sibling-`Area`-row mental model (`AreaMasterAreaId` back-link; the two-table
  `Area` ↔ `EcomLanguages` bridge via `AreaEcomLanguageId`).
- What the admin "+ New website Language" flow creates, and the eight Language Management knobs.
- The OOTB `Swift-v2_LanguageSelector` paragraph and the cache-safe master-template toggle alternative.
- Creating the layer — surface order (MCP → Management API `AreaCopy` → admin UI; never raw SQL) and
  the **AreaCopy host-config prereqs** (MSDTC + `ImplicitDistributedTransactions`; the net10
  `Enlist=false` workaround).
- **What a full-content AreaCopy does NOT carry** (string-id repeater children dropped; `UnifiedPermission`
  not cloned; hardcoded-page-id template gates miss the clones; component selectors still point at the
  master's pages) — the post-copy verification checklist.
- The three-layer translation cascade (`Translations.xml` / per-clone Item `Title` fields / DB content),
  the `LocalizeLink` nav-tree patch, culture-coded friendly-URL prefixes, the `PageShortCut` 404 cruft,
  the non-ASCII `.sql` encoding pitfall, and the common gotchas.

## SECURITY — an AreaCopy publishes every protected page in the new layer

**`AreaCopy` with `CopyPermissions: true` does NOT carry frontend page permissions. Every gated page in
the copy starts permissionless, which means public.** The parameter is not a no-op in general — it is
simply not the frontend-page-permission switch, and nothing in the `status: ok` says so. The observed
state after a routine language-layer creation: the customer-center dashboard served in full to an
**anonymous** visitor at the layer's localised path, while the master language stayed correctly gated.
This is the same class as the `UnifiedPermission` rows the copier drops
([`language-layers.md`](../../dw-content-modelling/references/language-layers.md) §3, "What a
full-content AreaCopy does NOT carry") — and it is the one with a security consequence, so treat it as a
blocking post-copy step, not a polish item.

**The same hole exists one and two levels down: `UnifiedPermission` rows are NOT language-layered at
GridRow or Paragraph level either.** Pages, grid rows and paragraphs are all language-layered (a master row
plus one row per language area) while `UnifiedPermission` is keyed by the **entity id of the row it
gates** — and the layer rows have DIFFERENT ids. A permission written against `GridRow/19100` therefore
does not reach `GridRow/19196` (es) or `GridRow/19576` (fr). Creating a language layer copies the content
and silently drops the gating. Measured on one three-language host: all 26 `PermissionName='GridRow'` rows
keyed area-29 ids, zero rows for the es or fr ids, and a plain buyer switching to `/es-us/…` or `/fr-ca/…`
saw the CSR tiles and the account-admin tiles that are correctly hidden from them on the master page. Page
weight was the tell: the es/fr Overview stayed at 153-164 KB for every persona while the master ranged
100-143 KB by role.

- **Mirror every master permission row onto the layer's sibling ids explicitly, at every entity level the
  master gates: `Page`, `GridRow` AND `Paragraph`** (`PermissionSave` per row; `Page.PageMasterPageId`
  gives the master to clone mapping for pages, and the layer's row/paragraph ids come from the layer's own
  page). Read the master rows' owner/level pairs and `PermissionSave` each pair against the mirror id.
  Levels are `None=1 Read=4 Edit=20 Create=84 Delete=340 All=1364`. On one three-language build the page
  level alone was 34 rows by hand, and the ten Overview grid rows were another 20.
- **Then probe anonymously, per language, per protected URL** — a signed-in check proves nothing here. The
  passing state is a redirect to the *localised* sign-in page, not a 200 with content. Any gate persona leg
  must walk protected URLs in **every** language layer, not only the master's, and must assert per persona
  that the tiles a role should not see are absent (page weight is a cheap secondary signal: on the run that
  measured this, mirroring the rows dropped the es/fr Overview from 153702 to 104767 bytes for the admin
  persona).
- Flush the permission cache and restart afterwards (the nav tree caches separately) before believing
  either result.

## Normalise page shortcuts BEFORE the copy — a leading slash defeats the link remapper

**The AreaCopy link remapper rewrites `Default.aspx?ID=n` and does not rewrite `/Default.aspx?ID=n`.**
The two shortcut forms are interchangeable everywhere else on the platform, so the slashed one is written
routinely and looks identical in admin — and the copies that carry it keep pointing at **master-language**
pages, silently leaking visitors out of the layer they are browsing. Normalise every `PageShortCut` to the
slash-less form before running the copy (10 fixed by hand on one build after the fact), and verify after by
extracting the shortcut targets on the layer and asserting every one resolves to a page whose
`PageAreaId` is the layer's.

## Localised ecom URLs need BOTH settings on the layer's shop page

**A localised PLP that still links to English product and group URLs is missing one of two independent
settings, and setting either alone leaves the leak.** They are:

- `GroupMetaPrimaryPage` on the group (typically **empty** after the copy), and
- `Page.PageNavigationProductPage` on the layer's shop page (typically still pointing at the **master's**
  shop page id).

Set both, per layer. Measured on one build: cross-language link leaks went 30/48 → 4/48 once both were in
place, with the localised paths (`/<lang>/<localised-shop-slug>/…`) serving 200 with local links. Assert it
by fetching a localised PLP and counting anchors whose path prefix is not the layer's.

## Audit group `primaryPageId` after every AreaCopy — at the shop page it blanks every PDP

**Never point a product group's `primaryPageId` at the shop/PLP page.** Swift's
`ProductDetailRenderGrid.cshtml` prefers `PrimaryPageId` over the detail page, so a group whose
`primaryPageId` targets the shop page makes the catalogue app re-render that page inside itself; the
recursion guard then empties it and **every** PDP in the shop renders an empty `<article>` — with no error
anywhere, in any log or API response. Measured recovery on one build: a PDP went from 89KB / 6 rows to
310KB / 61 rows once the value was cleared via `ProductCatalogGroupSave`.

**An AreaCopy stamps `primaryPageId` per-area onto every group row**, so a language-layer creation is
exactly the motion that plants it: 48 rows (16 groups × 3 areas) carried the three areas' shop page ids on
one build. Note the tension with the section above — those values are sometimes set *deliberately*, reaching
for localised group URLs. That is the wrong lever: the durable fix is `PageNavigationProductPage`, and
`primaryPageId` must stay clear. Audit the whole group set after every copy, and make the warmup/gate PDP
probe assert **non-trivial article content** (byte size or row count), which is what catches the blank
state before a human does.

## A master-layer `ParagraphSave` writes THROUGH to the language layers

**Item lists are DELETE-AND-RECREATE across the language layers, and the reconciliation is destructive.**
Saving the master's accordion/slider deletes the layers' children and recreates them **carrying the
master's copy**, with **new ids**. `ItemId=<existing>` means edit-in-place only for the layer you post to.
Measured on one page: saving the master deleted two layers' children and recreated them under a fresh id
block with English text, while the master's own children survived in place. Nothing announces it, and it is
easy to mistake for someone else's edit.

**Plain item fields do NOT propagate. Write every language layer explicitly, one save at a time, re-reading
after each.** Measured on `Swift-v2_Text` at DW 10.28.1-PreRelease: with the master changed, a copy field
that already held a value, a copy field that had never been set, and an overridden copy all stayed exactly
where they were. There is no master-to-copy copy-down to rely on and none to defend against, so a
translation pass that edits only the master leaves every layer holding its stale body.

Two version-scoped riders on the same surface, both measured on other builds and neither reproducible at
10.28.1. Treat each as a property of its capture, not as a rule:

- A field **newly added to the item type** after the copies were created has no per-copy override, so on
  10.28.3 the master value was observed landing on the copies on the first save. If the demo depends on
  that, measure it on the build in front of you.
- Saving a master and its layers **in one loop** produced body-inside-body nesting at 10.28.4, growing by a
  fixed byte count per preceding save in the pass. A one-pass double save at 10.28.1 produced no nesting.

Three rules follow, and the middle one is the one that saves a run:

1. **Never cache language-layer child ids across a master save — re-read them.** Any id captured before the
   save points at a deleted row.
2. **Guard every language-layer write with a fingerprint of the ORIGINAL text**, read from SQL immediately
   before the write, and **skip if the fingerprint is gone**. Without it, writing a layer after an unrelated
   later master edit silently reverts that layer to English.
3. **One save at a time, re-read every layer after every save**, and assert a content marker occurs exactly
   once per layer. Never batch a master and its layers in one loop.

Sequencing rule for a translation pass: do the master edits first, then the layers — and re-read, never
assume, the layer state in between. (Item-list saves are authoritative in the other direction too: posting a
subset deletes the omitted children outright — [`paragraphs.md`](paragraphs.md).)

## The recycle bin is keyed to the MASTER row, and `totalCount` always reads 0

Three facts that between them decide whether a purge or a restore on a multi-language site is safe.

**Deleting or clearing a MASTER entity cascades to its language copies, so a "the total fell by exactly 1"
guard fires on correct behaviour.** `RecycleBinClear {EntityType:"Page", Ids:["8944"]}` on a master page in
area 29 took the bin from 516 to 513: the master plus the two master-linked copies `PageSave` had
auto-created in areas 30 and 31, a delta of **3 for a single id**. On a host carrying hundreds of unrelated
soft-deleted pages a blanket clear is destructive, so the guard is load-bearing and must be the right one:
**snapshot the SET of soft-deleted ids before the purge, and afterwards assert the ids that went away are a
SUBSET of your own.** Never assert a count delta. `ParagraphDelete` has the same cascade
([`paragraphs.md`](paragraphs.md)).

**Restore is keyed to the master too, and the language areas' own bins read EMPTY.**
`GetRecycleBins?AreaId=<layer>&EntityType=GridRow` returns zero entries for language-layer rows that are
demonstrably soft-deleted in SQL, because those rows are never independently deleted or restored: they
follow the master. So a layer's deleted content looks unrecoverable when it is one call away.
`RecycleBinRestore {EntityType:"GridRow", Ids:["<masterRowId>"]}` restored the master row, both language
mirrors and all nine child paragraphs in one operation. **Always operate on the MASTER area's entity; do
not go hunting in the language areas' bins.** `RecycleBinEntityType` is
`None=0 Area=1 Page=2 GridRow=3 Paragraph=4`.

**`GetRecycleBins` reports `model.totalCount = 0` while `model.data` carries rows.** Measured at 58 and 69
entries against a `totalCount` of 0. Any paging or emptiness check on `totalCount` is wrong by
construction: **count `model.data`.**

## `Translations.xml` keys are case-sensitive — and the shipped file carries case-variant pairs

**A translation is present in the file and the page still renders English.** DW matches the `Translate()`
literal **exactly**, and the shipped Swift file carries **89 pairs of keys differing only in case** — an
in-stock/in-Stock pair, update/Update, all/All, item/Item, products/Products, and so on. Adding a translation
to one member of the pair while the template calls the other is a silent no-op that gets recorded as a
mystery.

**The natural tooling actively hides it, in two independent ways:**

- **A PowerShell hashtable is case-INSENSITIVE**, so a merge reports the case-variant keys as *already done*.
- **`ConvertFrom-Json` collapses case-variant properties into one member**, so the parsed document is already
  wrong before any comparison runs.

On one file, a first merge pass would have written 15 translations onto the wrong node.

**Mandate ordinal, case-sensitive handling in any `Translations.xml` tooling:** index into a
`Dictionary[string,object]` constructed with an **ordinal** string comparer — `[StringComparer]::Ordinal` —
and parse with `System.Text.Json`, never `ConvertFrom-Json`.

**Assert the RENDERED page contains the translated literal — not merely that the key exists in the file.**
Key-presence is exactly the check that passes on a case-variant miss. (The shipped duplicate case-variant
keys are worth raising with the vendor as a shipped-file defect.)

**A key that "is missing" is almost always PRESENT with an EMPTY value, and an empty value falls back to
`DefaultValue`, which is the English source string.** DW writes every unseen `Translate()` literal back
into the design register at render time, so by the time anyone notices English on a localised page the key
already exists in `Translations.xml` with empty CDATA per culture:

```xml
<key name="Ref" DefaultValue="Ref">
  <translation culture="es-US"><![CDATA[]]></translation>
  <translation culture="fr-CA"><![CDATA[]]></translation>
</key>
```

**Diagnose by reading the key, never by observing English output**, and **FILL the existing CDATA** rather
than appending new `<key>` blocks. Appending is the natural first diagnosis and it is wrong: the original
node is found first, so the duplicate never wins. The harvest is live and observable, which is the cheapest
proof the mechanism is real: rendering a new template once took one shipped file from 2408 to 2411 keys
before anything had been authored.

Two mechanical rules for editing the file. Set `CDataSection.Value` (assigning `InnerText` replaces the
CDATA with a text node). And round-trip with `XmlWriterSettings` `Indent = true`, `IndentChars` two spaces
and `UTF8Encoding($true)`: that reproduces the shipped file byte for byte, whereas a default `[xml]`
load/save collapses the indentation and loses about 79 KB (894,927 bytes against 974,201 on one file).
**Re-serialise the UNMODIFIED file first and assert byte-identity with what was fetched before making any
edit**, then assert the key/culture node counts moved by exactly the expected amount, then re-render and
assert the English literals are gone.

The file is also **DW-owned and self-modifying** — `Translate()` on an unknown literal appends a key at render
time, which is why it must stay additive and why DW must retain write access to it; that, and the
`Move-Item`-loses-the-ACE hazard, are in
[`../../dw-demo-hosted/references/online-mode.md`](../../dw-demo-hosted/references/online-mode.md)
"Never `Move-Item` over a file in a DW-managed folder".

## Demo judgement — localize the demo path, not the whole site

Same depth-not-width rule as PIM: translate header/footer text + the key page items the demo flow
touches, using the Visual Editor's Translations panel on each paragraph the storyline lands on.
**Localize the demo path, not the whole site** — don't try to translate all ~2170 `Translations.xml`
keys or every page on the layer; the rest fall back to the master language gracefully.

## Cross-references

- [`language-layers.md`](../../dw-content-modelling/references/language-layers.md) §3 — the
  full content-side language-layer model and verification checklists.
- [`../../dw-demo-pim/references/localization.md`](../../dw-demo-pim/references/localization.md) — the
  product side (translate product names, descriptions, custom fields).
