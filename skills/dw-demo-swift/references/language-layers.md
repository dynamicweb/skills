# language-layers.md

> Content-side localization in Dynamicweb 10 — adding a language layer to a website. Sister doc to `dynamicweb-pim-demo/references/localization.md` (the PIM/product side).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Contents

- [What the foundational skill owns](#what-the-foundational-skill-owns)
- [SECURITY — an AreaCopy publishes every protected page in the new layer](#security--an-areacopy-publishes-every-protected-page-in-the-new-layer)
- [Normalise page shortcuts BEFORE the copy — a leading slash defeats the link remapper](#normalise-page-shortcuts-before-the-copy--a-leading-slash-defeats-the-link-remapper)
- [Localised ecom URLs need BOTH settings on the layer's shop page](#localised-ecom-urls-need-both-settings-on-the-layers-shop-page)
- [Audit group `primaryPageId` after every AreaCopy — at the shop page it blanks every PDP](#audit-group-primarypageid-after-every-areacopy--at-the-shop-page-it-blanks-every-pdp)
- [A master-layer `ParagraphSave` writes THROUGH to the language layers](#a-master-layer-paragraphsave-writes-through-to-the-language-layers)
- [`Translations.xml` keys are case-sensitive — and the shipped file carries case-variant pairs](#translationsxml-keys-are-case-sensitive--and-the-shipped-file-carries-case-variant-pairs)
- [Demo judgement — localize the demo path, not the whole site](#demo-judgement--localize-the-demo-path-not-the-whole-site)
- [Cross-references](#cross-references)

## What the foundational skill owns

The entire vendor-generic content-side language-layer model is owned by the `dw-content-modelling`
foundational skill — staged in
[`content-modelling.md`](../../dw-demo-base/references/foundational/content-modelling.md) §3
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
([`content-modelling.md`](../../dw-demo-base/references/foundational/content-modelling.md) §3, "What a
full-content AreaCopy does NOT carry") — and it is the one with a security consequence, so treat it as a
blocking post-copy step, not a polish item.

- **Mirror every master page-permission row onto the layer's sibling page ids explicitly** (`PermissionSave`
  per row; `Page.PageMasterPageId` gives the master → clone mapping). On one three-language build that was
  34 rows by hand.
- **Then probe anonymously, per language, per protected URL** — a signed-in check proves nothing here. The
  passing state is a redirect to the *localised* sign-in page, not a 200 with content. Any gate persona leg
  must walk protected URLs in **every** language layer, not only the master's.
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

**Language layers are reconciled against the master on every save, and the reconciliation is destructive in
two different ways.** Neither is announced, and both are easy to mistake for someone else's edit:

- **Item lists are DELETE-AND-RECREATE.** Saving the master's accordion/slider deletes the layers' children
  and recreates them **carrying the master's copy**, with **new ids**. `ItemId=<existing>` means edit-in-place
  only for the layer you post to. Measured on one page: saving the master deleted two layers' children and
  recreated them under a fresh id block with English text, while the master's own children survived in place.
- **Plain item fields are COPIED DOWN.** On simple types (`Swift-v2_Text`, `Swift-v2_Feature`) the master's
  value is written into the language layers. On one run, six layer paragraphs had already been rewritten in
  English *before* their own translation write ran — nothing had touched them but a master-side save.

Two rules follow, and the second is the one that saves a run:

1. **Never cache language-layer child ids across a master save — re-read them.** Any id captured before the
   save points at a deleted row.
2. **Guard every language-layer write with a fingerprint of the ORIGINAL text**, read from SQL immediately
   before the write, and **skip if the fingerprint is gone**. Without it, writing a layer after an unrelated
   later master edit silently reverts that layer to English. The guard is what turned "six paragraphs
   mysteriously back in English" into six correctly-skipped writes on the run that measured this.

Sequencing rule for a translation pass: do the master edits first, then the layers — and re-read, never
assume, the layer state in between. (Item-list saves are authoritative in the other direction too: posting a
subset deletes the omitted children outright — [`paragraphs.md`](paragraphs.md).)

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

The file is also **DW-owned and self-modifying** — `Translate()` on an unknown literal appends a key at render
time, which is why it must stay additive and why DW must retain write access to it; that, and the
`Move-Item`-loses-the-ACE hazard, are in
[`../../dw-demo-base/references/online-mode.md`](../../dw-demo-base/references/online-mode.md)
"Never `Move-Item` over a file in a DW-managed folder".

## Demo judgement — localize the demo path, not the whole site

Same depth-not-width rule as PIM: translate header/footer text + the key page items the demo flow
touches, using the Visual Editor's Translations panel on each paragraph the storyline lands on.
**Localize the demo path, not the whole site** — don't try to translate all ~2170 `Translations.xml`
keys or every page on the layer; the rest fall back to the master language gracefully.

## Cross-references

- [`content-modelling.md`](../../dw-demo-base/references/foundational/content-modelling.md) §3 — the
  full content-side language-layer model and verification checklists.
- [`../../dw-demo-pim/references/localization.md`](../../dw-demo-pim/references/localization.md) — the
  product side (translate product names, descriptions, custom fields).
