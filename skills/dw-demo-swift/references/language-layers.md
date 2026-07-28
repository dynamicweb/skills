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
