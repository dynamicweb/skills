---
name: dynamicweb-swift-demo
description: Dynamicweb 10 Swift frontend -- owns the baseline content deserialize (Swift2.2 vault content via DynamicWeb.Serializer strict-mode POST + mandatory post-deserialize integrity sweep), templates, paragraph types, Visual Editor, asset organisation, the customer-center / sales-on-behalf playbook (stock CSR section -- never rebuild it), and the customer re-skin escalation ladder. Triggers: starting a Swift demo (load the baseline), re-skinning to a customer brand, "where do I edit the header/footer", customer-center / impersonation flows, paragraph renders empty or stale, Razor pitfalls in custom layouts, language layers, gating pages or paragraphs by group, SQL-direct content seeding. Non-triggers: demo setup/MCP/TLS -> dynamicweb-demo-base; PIM data modelling -> dynamicweb-pim-demo; ERP integration -> dynamicweb-erp-demo. Swift 2 only -- never follow `doc.dynamicweb.dev/swift/swift-1/` URLs. Use AFTER dynamicweb-demo-base (host running, Serializer installed).
---

# Dynamicweb Swift Demo Skill

Baseline content deserialize, frontend / Swift / customer-center playbook, and re-skin recipe for Dynamicweb 10 demo builds. **Use AFTER** `dynamicweb-demo-base` -- assumes a host is running, `$env:DW_VAULT` resolves, and the Serializer is installed in the host (per base's [`../dynamicweb-demo-base/references/serializer-reference.md`](../dynamicweb-demo-base/references/serializer-reference.md) "Installation").

This SKILL.md is pure nav. Swift is a knowledge book, not a recipe -- see references for any specific topic.

## Step 0 — Load the Swift baseline (every Swift demo)

Before any frontend work (templates, paragraphs, re-skin), load the Swift content baseline into the host's project DB. Swift demos depend on `Swift-v2_*` item types, `Swift2.2` paragraph wiring, and the **content rows** (Area, Pages, grid-rows, paragraphs) that the baseline ships. `dynamicweb-demo-base` deliberately does NOT deserialize — that step lives here.

**Baseline shape — content-only (as of 2026-05-08).** The Swift2.2 vault baseline ships **only `_content/`** — no framework rows (no currencies, no countries, no languages, no shops). Framework data must already exist in the target DB; the area's YAML uses string FKs (`AreaEcomShopId: "SHOP1"`, `AreaEcomCountryCode: "DE"`) that resolve against existing rows. A PIM-set-up host (per `dynamicweb-pim-demo/references/canonical-setup-order.md` Steps 1-4: currencies, countries, languages, manufacturers, SHOP1 with language relation) is the canonical clean target — the deserialize is **naturally additive** and does not conflict with PIM-curated framework rows or product data. See [`references/deserialize-flow.md`](references/deserialize-flow.md) §3 for the full shape contract.

1. **Verify framework prerequisites in target DB** — at minimum: `SHOP1` (or whichever ShopId the area's YAML references), `DE` country (or whichever AreaEcomCountryCode), `LANG1` with shop language relation, EUR currency. PIM-skill `canonical-setup-order.md` Steps 1-4 covers this. If you ran the PIM flow already, you're done.
2. **Verify Serializer is installed** in the host per [`../dynamicweb-demo-base/references/serializer-reference.md`](../dynamicweb-demo-base/references/serializer-reference.md) "Installation".
3. **Deploy the Swift design package** — npm build, Items XMLs + Designs + Styles copy, the ProductsBackend/ProductsFrontend skip rule, catalog-paragraph path rewrite, and the slider card-template fix all live in [`references/deserialize-flow.md`](references/deserialize-flow.md) §"Design-package deploy (before any deserialize)".
4. **Run the deserialize flow** -> [`references/deserialize-flow.md`](references/deserialize-flow.md). HTTP POST `/Admin/Api/SerializerDeserialize` with strict mode on. Surfaces FK orphans / missing templates / schema drift as `CumulativeStrictModeException` HTTP 4xx.
5. **Run the post-deserialize integrity sweep** -> [`references/integrity-sweep.md`](references/integrity-sweep.md). The skill refuses to declare baseline restored until all of its checks pass.

PIM-only demos can skip this step entirely — see `dynamicweb-pim-demo` for the blank-DB modelling flow that does NOT need a Swift frontend.

## Always-on convenience: demo cheat-sheet page

Every Swift demo gets a hidden-from-nav info page at `/<area-url>/demo` for the presenter's side screen: demo logins, key URLs, catalogue-at-a-glance counts. Keep it **customer-safe** (no pitch framing, no internal phase / decision / pitfall IDs) and out of navigation via high `sort`, not `hidden=true`. The canonical 5-step MCP build recipe + the full safety rules live in [references/cheat-sheet.md](references/cheat-sheet.md); the `/dynamicweb-cheatsheet` command drives it end-to-end.

## Always-on rule: stock CSR section

**For sales-on-behalf demos, the stock Swift 2.2 CSR section under `Customer center/CSR/{Orders, Accounts, Carts, Users}` is the answer -- never re-build it.** The CSR section already supports impersonation, mixed-source order viewing, and exit-impersonation; re-building loses paragraph wiring and burns the customisation budget. See [references/customer-center.md](references/customer-center.md) for the deeper playbook.

## Demo philosophy — go deep, not wide

Inherited principle from [`../dynamicweb-demo-base/SKILL.md` "Demo philosophy"](../dynamicweb-demo-base/SKILL.md). Swift-specific guardrails:

- **Logins: floor of 2 (one buyer + one CSR).** The buyer is the demo's protagonist; the CSR exists so impersonation / sales-on-behalf has somewhere to land via the stock CSR section (see "Always-on rule: stock CSR section" above). Do NOT scaffold a roster of buyer personas, secondary admins, "test user 1/2/3", or per-role accounts the storyline doesn't visit — every extra login is a row the customer scans on the demo cheat-sheet page that buys nothing. If the customer's pitch genuinely needs a third persona (e.g. an approver in a multi-step approval flow), add it deliberately and log it in `CUSTOMISATIONS.md` rationale-style; otherwise stop at 2.
- **Customer-center sections: storyline-driven, not platform-tour.** The stock Swift 2.2 sections under `Customer center/CSR/{Orders, Accounts, Carts, Users}` already exist after the baseline deserialize — pick the one or two the storyline actually lands on (typically Orders + one of Accounts/Carts/Users to make the impersonation flow concrete), don't tour all four. Same rule for the Account-side sections.
- **Paragraph types + page presets: as the storyline demands.** Don't pre-scaffold every paragraph type the Swift design package ships. Add a paragraph type the first time the storyline needs it; resist the "while I'm here" temptation. The cheat-sheet recipe ([references/cheat-sheet.md](references/cheat-sheet.md)) is the pattern — clone, edit content, move on.
- **Product catalogue: deep AND wide — exception case.** Rich product data is welcome on the storefront. PIM owns the modelling depth; Swift just renders it. See `dynamicweb-pim-demo` for the modelling recipes.

The demo cheat-sheet page is your reality-check: if its login table or "key URLs" list doesn't fit on one side-screen at presenter zoom, the demo has gone wide.

## Where to find things

Each reference is an independent file owned end-to-end by a single topic; cross-references between them are explicit.

| If you need to... | Read this reference |
|---|---|
| **Load the Swift baseline content into the host** (POST `/Admin/Api/SerializerDeserialize`; includes the design-package deploy step) | **references/deserialize-flow.md** |
| **Verify post-deserialize integrity** (mandatory) | **references/integrity-sweep.md** |
| **Start a new demo's frontend** (configuration-only Day-1 workflow) or use the Visual Editor effectively | **references/admin-ui-authoring.md** |
| Understand Swift template / page / paragraph conventions; debug Razor pitfalls in custom layouts (`@Html.Raw`, `ProductFieldValues`, raw Razor source rendering on the PDP, role gates by customer-number suffix) | references/templates.md |
| Pick the right paragraph type for a section; debug "paragraph renders empty / stale after delete" (`RenderGrid` cache, `SelectedGroups` deserialization, alphabetical template fallback) | references/paragraphs.md |
| **Content-modeling discipline for designed pages** — one paragraph/field per editor concern, rich-text = prose only, images in image fields, no page-ID-scoped CSS, list pages read modeled fields. Load BEFORE building any designed page, not as a post-hoc audit. | **references/content-modeling.md** |
| Build the demo cheat-sheet page (canonical 5-step MCP chain + customer-safety rules) | references/cheat-sheet.md |
| Customer-center playbook (Account vs CSR; impersonation flow) | references/customer-center.md |
| **B2B DC pattern** (one AccessUser group per Stock Location → unlocks DC-scoped Assortments + Shipping methods + Shipping fees; the canonical DW10 mechanic for any multi-DC wholesale demo; vendor-blessed by the Dynamicweb vendor architect) | references/b2b-dc-pattern.md |
| Re-skin a demo (configuration → `<customer>_custom.css` → content-layout escalation ladder; the never-write-to-stock-`custom.css` hard rule) | references/re-skin.md |
| **DW10 canonical surfaces** — the "use X, not Y" cheat sheet for surfaces routinely re-implemented in Razor (user/groups, permissions, prices, orders, products, URLs, redirects, per-category, custom-head includes). Also owns the **Permission entity store** (permissions live in the `Permission` table, NOT the legacy `*Permission` columns — required reading before any gate-by-group work) and the **custom item-type `<Prefix>_*` discipline**. Loaded on every demo build. | **references/dw10-canonical-surfaces.md** |
| **DW10 discipline audit** — one-shot grep pack to verify a demo's templates against the canonical surfaces before "ready" / fold-back | **references/dw10-canonical-surfaces.md** §"Discipline audit — grep pack" |
| Drop per-demo Style assets by hand (Color Schemes / Buttons / Typography / Fonts JSON+CSS pairs in `Files/System/Styles/`; Area row wiring; reference vault at `$env:DW_VAULT\dw-swift-styles\`) | references/styles-assets.md |
| Add a language layer to a website (sibling `Area` rows, language management settings, OOTB `Swift-v2_LanguageSelector` wiring; sister doc is `dynamicweb-pim-demo/references/localization.md` for the PIM/product side) | references/language-layers.md |
| Organise assets under `wwwroot/Files/` | references/asset-organisation.md |
| **SQL-direct seeding** of Page / GridRow / Paragraph / ItemType rows when MCP isn't available (required NOT-NULL columns, `ItemInstanceType=''`, `MAX(Id)` lies → `TRY_CAST`, `GridRowSort × 10` slot reservation, post-INSERT restart rules) | references/sql-direct-seeding.md |

## Inherited from dynamicweb-demo-base

This skill assumes `dynamicweb-demo-base` ran first. Four rules apply at all times and are NOT restated here -- see the owning reference in base for each:

| Rule | Owner |
|------|-------|
| `$env:DW_VAULT` path-resolution rule | [dynamicweb-demo-base/SKILL.md "Path-resolution rule"](../dynamicweb-demo-base/SKILL.md) |
| Customer-context read-only contract | [dynamicweb-demo-base/references/customer-context.md](../dynamicweb-demo-base/references/customer-context.md) |
| Customisations-ledger preflight | [dynamicweb-demo-base/references/customisations.md](../dynamicweb-demo-base/references/customisations.md) |
| Baseline-drift self-diagnosis rule | [dynamicweb-demo-base/SKILL.md "Self-diagnosis rule"](../dynamicweb-demo-base/SKILL.md) |

Runtime enforcement: the per-demo `CLAUDE.md` drop installed by base (`dynamicweb-demo-base/references/customer-context.md` recipe) reminds Claude of these rules regardless of which skill loaded first.

If you find yourself running this skill standalone with no base context, fix that before continuing -- see the description's "Use AFTER" hint. If `~/.claude/skills/dynamicweb-demo-base/` is not installed, install it first -- this skill's inherited rules require it.

## Sister skills

- **`dynamicweb-demo-base`** -- foundation skill (Use FIRST). Owns all setup + path resolution + Serializer install + customisations + customer-context. Does NOT deserialize a baseline — that's owned here.
- **`dynamicweb-pim-demo`** -- PIM modelling (Use AFTER, can pair with this skill in either order on the host). Starts from a blank/fresh DB and skips the baseline deserialize entirely.

A sibling skill that runs without `dynamicweb-demo-base`'s outputs (no `.mcp.json`, no `CUSTOMISATIONS.md`, no resolved `$env:DW_VAULT`) silently no-ops or produces broken artefacts.

## Vendor patterns

The vendor skill-repo consultation outcome (`dynamicweb/skills` + `dynamicweb/ai-implementor-skills`) is documented in [dynamicweb-demo-base/references/vendor-patterns.md](../dynamicweb-demo-base/references/vendor-patterns.md) -- the same shared note covers both PIM and Swift sister skills.
