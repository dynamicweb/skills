# language-layers.md

> Content-side localization in Dynamicweb 10 — adding a language layer to a website. Sister doc to `dynamicweb-pim-demo/references/localization.md` (the PIM/product side).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

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
