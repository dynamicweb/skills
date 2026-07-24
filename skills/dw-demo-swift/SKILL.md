---
name: dw-demo-swift
type: flow
group: demo
description: 'Dynamicweb 10 Swift 2 frontend demos — baseline content deserialize, templates, paragraph types, Visual Editor, asset organisation, the customer-center playbook, the customer re-skin ladder, and the mobile pass. Triggers: starting a Swift demo (load the baseline), re-skinning to a customer brand, "where do I edit the header/footer", "mobile view" / "mobile pass" / "canvas stretch" / "overflow at 390" / mega-menu won''t collapse, customer-center / impersonation flows, sign-in profiles / switch user, checkout delivery date or custom order fields, paragraph renders empty or stale, Razor pitfalls in custom layouts, language layers, gating pages or paragraphs by group, editing repeater/slider children via the Admin API. Non-triggers: demo setup/MCP/TLS -> dw-demo-base; PIM data modelling -> dw-demo-pim; ERP integration -> dw-demo-erp. Swift 2 only -- never follow `doc.dynamicweb.dev/swift/swift-1/` URLs. Use AFTER dw-demo-base (host running, Serializer installed).'
---

# Dynamicweb Swift Demo Skill

Baseline content deserialize, frontend / Swift / customer-center playbook, and re-skin recipe for Dynamicweb 10 demo builds. **Use AFTER** `dynamicweb-demo-base` -- assumes a host is running, the demo's versions are captured, and the Serializer is installed in the host (per base's [`../dw-demo-base/references/serializer-reference.md`](../dw-demo-base/references/serializer-reference.md) "Installation").

This SKILL.md is pure nav. Swift is a knowledge book, not a recipe -- see references for any specific topic.

## How to run me

This skill holds domain knowledge, not build sequencing. An **orchestrator** owns the phase
order: GSD injects this skill into its agents (via the `agent_skills` block), or the native
`/demo:*` command set invokes it; **standalone**, the skill's own lightweight harness guards its
documented order (gate every step, persist progress to `.demo/<slug>/flow-state.json`). The
orchestrator abstraction (GSD primary, native command set, and the standalone harness) is owned by
[`../dw-demo-base/references/orchestrator.md`](../dw-demo-base/references/orchestrator.md).

## Step 0 — Load the Swift baseline (every Swift demo)

Before any frontend work (templates, paragraphs, re-skin), load the Swift content baseline into the host's project DB. Swift demos depend on `Swift-v2_*` item types, Swift paragraph wiring, and the **content rows** (Area, Pages, grid-rows, paragraphs) that the baseline ships. `dynamicweb-demo-base` deliberately does NOT deserialize — that step lives here.

**Staging story — the base split (Swift 2.4).** The `base` layer is **FRAMEWORK-ONLY**: `replace/_sql/` ships 16 framework SQL sets (currencies, countries, languages, shops, payments, shippings, VAT, order flow/states, AccessUser) and **nothing else — zero content, zero pages, zero catalog**. ALL Swift content deserializes from the **`surface-swift` surface layer**: both areas (`Swift 2` + `Swift 2 Nederlands`), the merge tree, `UrlPath`, and its **own item-type XMLs** (`itemtypes/`, 128 `ItemType_Swift-v2_*.xml` — content item types no longer come from the design-package clone). **Composition order: base → sample-data catalog → content surface(s) → feature fragments** (features FK into surface-carried areas). The demo catalog + identities come from the `sample-data` layer (ALL its content is SQL files in `merge/_sql/` — `catalog.sql` + `identities.sql`, activated when an edition sets `sampleData: true`, e.g. the `swift-demo` edition) or are authored **per-demo** via the PIM modelling recipes — route it to [`../dw-demo-pim/SKILL.md`](../dw-demo-pim/SKILL.md), do not expect base or surface to supply products (each demo tailors its own catalog, not a pre-baked store). The surface's area YAML uses string FKs (`AreaEcomShopId: "SHOP1"`, `AreaEcomCountryCode: "DE"`) that resolve against the framework rows the base pass lands. Caution: framework rows travel in `replace`, which is **source-wins** — on a host with hand-curated SHOP1/DE/EUR/LANG1 rows the base layer UPDATES those rows. See [`references/deserialize-flow.md`](references/deserialize-flow.md) §3 for the full shape contract, the PIM-curated-host warning, and the **mandatory post-deserialize area binding** (unbound areas on DW 10.28+ derive their currency from the area CULTURE, not from `CurrencyIsDefault`).

1. **Framework prerequisites in target DB** — the `base` layer's `replace/_sql/` ships the framework (currencies, countries, languages, shops, payments, shippings, VAT), so a fresh DB no longer needs it pre-seeded. When you WANT a PIM-curated framework instead, set up `SHOP1` (or whichever ShopId the area's YAML references), `DE` country (or whichever AreaEcomCountryCode), `LANG1` with shop language relation, and EUR currency first (PIM-skill `canonical-setup-order.md` Steps 1-4) — and then TRIM the matching rows from the base layer's `replace/_sql/` before deserializing: `replace` is source-wins, so untrimmed base framework rows would overwrite your curated ones.
2. **Verify Serializer is installed** in the host per [`../dw-demo-base/references/serializer-reference.md`](../dw-demo-base/references/serializer-reference.md) "Installation".
3. **Deploy the Swift design package** — npm build, Designs + Styles + icons copy (item-type XMLs now ship with `surface-swift`), the ProductsBackend/ProductsFrontend skip rule, catalog-paragraph path rewrite, and the slider card-template fix all live in [`references/deserialize-flow.md`](references/deserialize-flow.md) §"Design-package deploy (before any deserialize)".
4. **Run the deserialize flow** -> [`references/deserialize-flow.md`](references/deserialize-flow.md). HTTP POST `/Admin/Api/SerializerDeserialize` with strict mode on. Surfaces FK orphans / missing templates / schema drift as `CumulativeStrictModeException` HTTP 4xx.
5. **Run the post-deserialize integrity sweep** -> [`references/integrity-sweep.md`](references/integrity-sweep.md). The skill refuses to declare baseline restored until all of its checks pass.

PIM-only demos can skip this step entirely — see `dynamicweb-pim-demo` for the blank-DB modelling flow that does NOT need a Swift frontend.

## Always-on convenience: demo cheat-sheet page

Every Swift demo gets a hidden-from-nav info page at `/<area-url>/demo` for the presenter's side screen: demo logins, key URLs, catalogue-at-a-glance counts. Keep it **customer-safe** (no pitch framing, no internal phase / decision / pitfall IDs) and out of navigation via high `sort`, not `hidden=true`. The canonical 5-step MCP build recipe + the full safety rules live in [references/cheat-sheet.md](references/cheat-sheet.md); the `/dynamicweb-cheatsheet` command drives it end-to-end.

## Always-on rule: stock CSR section

**For sales-on-behalf demos, the stock Swift 2.2 CSR section under `Customer center/CSR/{Orders, Accounts, Carts, Users}` is the answer -- never re-build it.** The CSR section already supports impersonation, mixed-source order viewing, and exit-impersonation; re-building loses paragraph wiring and burns the customisation budget. See [references/customer-center.md](references/customer-center.md) for the deeper playbook.

## Demo philosophy — go deep, not wide

Inherited principle from [`../dw-demo-base/SKILL.md` "Demo philosophy"](../dw-demo-base/SKILL.md). Swift-specific guardrails:

- **Logins: floor of 2 (one buyer + one CSR).** The buyer is the demo's protagonist; the CSR exists so impersonation / sales-on-behalf has somewhere to land via the stock CSR section (see "Always-on rule: stock CSR section" above). Do NOT scaffold a roster of buyer personas, secondary admins, "test user 1/2/3", or per-role accounts the storyline doesn't visit — every extra login is a row the customer scans on the demo cheat-sheet page that buys nothing. If the customer's pitch genuinely needs a third persona (e.g. an approver in a multi-step approval flow), add it deliberately and log it in `CUSTOMISATIONS.md` rationale-style; otherwise stop at 2.
- **Customer-center sections: storyline-driven, not platform-tour.** The stock Swift 2.2 sections under `Customer center/CSR/{Orders, Accounts, Carts, Users}` already exist after the baseline deserialize — pick the one or two the storyline actually lands on (typically Orders + one of Accounts/Carts/Users to make the impersonation flow concrete), don't tour all four. Same rule for the Account-side sections.
- **Paragraph types + page presets: as the storyline demands.** Don't pre-scaffold every paragraph type the Swift design package ships. Add a paragraph type the first time the storyline needs it; resist the "while I'm here" temptation. The cheat-sheet recipe ([references/cheat-sheet.md](references/cheat-sheet.md)) is the pattern — clone, edit content, move on.
- **Product catalogue: deep AND wide — exception case.** Rich product data is welcome on the storefront. PIM owns the modelling depth; Swift just renders it. See `dynamicweb-pim-demo` for the modelling recipes.

The demo cheat-sheet page is your reality-check: if its login table or "key URLs" list doesn't fit on one side-screen at presenter zoom, the demo has gone wide.

## Where to find things

Each reference is an independent file owned end-to-end by a single topic; cross-references between them are explicit.

| If you need to... | Read this reference |
|---|---|
| **Load the Swift layers into the host** (framework-only `base` + `surface-swift` content surface; POST `/Admin/Api/SerializerDeserialize`; includes the design-package deploy step and the mandatory area binding) | **references/deserialize-flow.md** |
| **Verify post-deserialize integrity** (mandatory) | **references/integrity-sweep.md** |
| **Install a feature pack into a demo host** (check out the feature layer from the Distribution, source-drop the `.cs`, copy disk overlays, deserialize the fragment AFTER the base layer) | **references/pack-activation.md** |
| **Start a new demo's frontend** (configuration-only Day-1 workflow) or use the Visual Editor effectively | **references/admin-ui-authoring.md** |
| Understand Swift template / page / paragraph conventions; debug Razor pitfalls in custom layouts (`@Html.Raw`, `ProductFieldValues`, raw Razor source rendering on the PDP, role gates by customer-number suffix) | references/templates.md |
| **Component-first gate** — map a rendering requirement to a standard `Swift-v2_*` component (catalogue: category banner, subgroup nav, related/similar, specs, BOM) BEFORE customising; pick the right paragraph type for a section; debug "paragraph renders empty / stale after delete" (`RenderGrid` cache, `SelectedGroups` deserialization, alphabetical template fallback) | references/paragraphs.md |
| **Content-modeling discipline for designed pages** — one paragraph/field per editor concern, rich-text = prose only, images in image fields, no page-ID-scoped CSS, list pages read modeled fields. Load BEFORE building any designed page, not as a post-hoc audit. | **references/content-modeling.md** |
| Build the demo cheat-sheet page (canonical 5-step MCP chain + customer-safety rules) | references/cheat-sheet.md |
| Customer-center playbook (Account vs CSR; impersonation flow; **Swift 2.4 sign-in profiles / switch user** — same-username `AccessUser` rows + `IsLogin`, the zero-custom-code picker recipe, profiles-vs-impersonation disambiguation, the 10.29+/PreRelease platform gate; seeding the section's orders/quotes/carts/favorites; why CSR/Accounts or My-orders looks empty; gating buyer dashboards away from the CSR; customer-specific / contract pricing) | references/customer-center.md |
| **Checkout delivery date / custom order fields** — the stock `EnableDeliveryDate` → `OrderShippingDate` beat (no custom field needed), the `EcomOrderField` ⇔ `EcomOrders.<SystemName>` column contract (`IndexOutOfRangeException` on every order read when violated), the broken `create_order_field` MCP tool | references/checkout-order-fields.md |
| **B2B DC pattern** (one AccessUser group per Stock Location → unlocks DC-scoped Assortments + Shipping methods + Shipping fees; the canonical DW10 mechanic for any multi-DC wholesale demo; vendor-blessed by the Dynamicweb vendor architect) | references/b2b-dc-pattern.md |
| Re-skin a demo (configuration → `<customer>_custom.css` → content-layout escalation ladder; the never-write-to-stock-`custom.css` hard rule) | references/re-skin.md |
| **Mobile pass** — make the storefront fit the phone canvas: the `document.body.scrollWidth`-not-documentElement measure (`overflow-x:hidden` masks the stretch), widest-offender iteration, the 390+430 real-device finish; the Swift 2.4 trap catalogue (fixed-width mega-menu, non-wrapping `NColumnsFlex` + `flexibleColumns`, `.flex-fill` beating fixed bases, force-open spec accordions, inline-hardcoded logo width, anon CTA in `productPRICE`); and the "verify first — theme-default ≥1.2.0 already ships most fixes" caveat. Triggers: "mobile view", "mobile pass", "canvas stretch", "overflow at 390", mega-menu won't collapse | references/mobile-pass.md |
| **Header menu: make it read as a menu** — why a fresh bar is flat (childless top nodes), the `save_groups` nav-depth recipe, the affordance CSS shipped inside `theme-default`'s `default_custom.css`, and the three interaction platform-truths (Popper-gap bridge, `::before`=icon/`::after`=underline caret collision, dropdown `min-width`); opt-in `data-nav-icon` icons bound to DW stock `/Files/Images/Icons` | references/header-menu.md |
| **Polish gate before "ready"** — hunt every demo-critical page for whitespace bands, misaligned/stretched images, dead arrows, horizontal scrollbars: programmatic detectors + interaction pass + eyeball checklist + symptom routing | [dynamicweb-demo-base/references/visual-qa.md](../dw-demo-base/references/visual-qa.md) |
| **DW10 canonical surfaces** — the "use X, not Y" cheat sheet for surfaces routinely re-implemented in Razor (user/groups, permissions, prices, orders, products, URLs, redirects, per-category, custom-head includes). Also owns the routing to the **permission entity store** (render-time page/paragraph permissions live in `UnifiedPermission` rows keyed `PermissionName='Page'`, NOT the legacy `*Permission` columns — required reading before any storefront gating work) and the **custom item-type `<Prefix>_*` discipline**. Loaded on every demo build. | **references/dw10-canonical-surfaces.md** |
| **DW10 discipline audit** — one-shot grep pack to verify a demo's templates against the canonical surfaces before "ready" / fold-back | **references/dw10-canonical-surfaces.md** §"Discipline audit — grep pack" |
| Drop per-demo Style assets by hand (Color Schemes / Buttons / Typography / Fonts JSON+CSS pairs in `Files/System/Styles/`; Area row wiring; the single `theme-default` layer from the Distribution, checked out per-demo into `<demo-root>\distribution\layers\theme-default\`) | references/styles-assets.md |
| Add a language layer to a website (sibling `Area` rows, language management settings, OOTB `Swift-v2_LanguageSelector` wiring; sister doc is `dynamicweb-pim-demo/references/localization.md` for the PIM/product side) | references/language-layers.md |
| Organise assets under `wwwroot/Files/` | references/asset-organisation.md |
| Content create/edit is **API-first** — capture the admin UI's `/Admin/Api` call and replay it (MCP → Management API); SQL-direct / `RunSql`-scheduled-task seeding is a **retired** motion (why it's retired + forensic schema for diagnosing already-seeded rows) | references/sql-direct-seeding.md |

## Inherited from dynamicweb-demo-base

This skill assumes `dynamicweb-demo-base` ran first. Four rules apply at all times and are NOT restated here -- see the owning reference in base for each:

| Rule | Owner |
|------|-------|
| Per-demo artifact download + path-resolution rule | [dynamicweb-demo-base/SKILL.md "Path-resolution rule"](../dw-demo-base/SKILL.md) |
| Customer-context read-only contract | [dynamicweb-demo-base/references/customer-context.md](../dw-demo-base/references/customer-context.md) |
| Customisations-ledger preflight | [dynamicweb-demo-base/references/customisations.md](../dw-demo-base/references/customisations.md) |
| Baseline-drift self-diagnosis rule | [dynamicweb-demo-base/SKILL.md "Self-diagnosis rule"](../dw-demo-base/SKILL.md) |

Runtime enforcement: the per-demo `CLAUDE.md` drop installed by base (`dynamicweb-demo-base/references/customer-context.md` recipe) reminds Claude of these rules regardless of which skill loaded first.

If you find yourself running this skill standalone with no base context, fix that before continuing -- see the description's "Use AFTER" hint. If `~/.claude/skills/dynamicweb-demo-base/` is not installed, install it first -- this skill's inherited rules require it.

## Sister skills

- **`dynamicweb-demo-base`** -- foundation skill (Use FIRST). Owns all setup + path resolution + Serializer install + customisations + customer-context. Does NOT deserialize a baseline — that's owned here.
- **`dynamicweb-pim-demo`** -- PIM modelling (Use AFTER, can pair with this skill in either order on the host). Starts from a blank/fresh DB and skips the baseline deserialize entirely.

A sibling skill that runs without `dynamicweb-demo-base`'s outputs (no `.mcp.json`, no `CUSTOMISATIONS.md`) silently no-ops or produces broken artefacts.

## Vendor patterns

The vendor skill-repo consultation outcome (`dynamicweb/skills` + `dynamicweb/ai-implementor-skills`) is documented in [dynamicweb-demo-base/references/vendor-patterns.md](../dw-demo-base/references/vendor-patterns.md) -- the same shared note covers both PIM and Swift sister skills.




