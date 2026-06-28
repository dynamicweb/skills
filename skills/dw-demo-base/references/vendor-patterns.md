# vendor-patterns.md

> Outcome of the vendor skill-repo consultation (before authoring the sister skills). Two vendor repos reviewed: [`dynamicweb/skills`](https://github.com/dynamicweb/skills) (Python agent skills targeting MCP + Management API) and [`dynamicweb/ai-implementor-skills`](https://github.com/dynamicweb/ai-implementor-skills) (Claude Code skill bundle, incl. `dw-extend` extension scaffolding).
> Sister skills cross-reference this file from their vendor-patterns section instead of restating it â€” single source for vendor positioning across all sister skills.
> Default posture: **adopt vendor patterns whenever they apply**; deviate only with a documented lived-experience reason, recorded below. Re-check the vendor repos before each major skill revision in case new patterns appear.

## Adopted vs deviated â€” summary

**Adopted from the vendor repos:**

- Description shape for skill routing: `<one-sentence what>. Use when <triggers>.`
- Verify widget / field system names via API lookups, never assumptions â€” including the full `ProductCategory|<CategoryId>|<FieldId>` field format (lives in `dynamicweb-pim-demo` structural-model + governance references).
- `patch_products_safe` only; never `update_products` (lives in `dynamicweb-pim-demo/references/canonical-setup-order.md`).
- Upgrade-safe extension points â€” no monkey-patching `Dynamicweb.*` assemblies (enforced conceptually by the customisations-ledger preflight, `references/customisations.md`).

**Deliberate deviations (each motivated by lived demo-build experience):**

- PowerShell recipes fenced inside Markdown references, not Python scripts â€” Windows-native stack, no interpreter dependency.
- Composition routing ("Use FIRST" / "Use AFTER") instead of independent atomic skills â€” our use-case is a build pipeline; sisters loaded standalone silently no-op.
- Four surfaces (MCP / Management API / Direct SQL / Filesystem) instead of MCP + API only â€” bulk SQL fixes and `wwwroot/Files/` manipulation are unavoidable in real demo builds.
- Explicit inline recovery recipes instead of abstract "report transparently with retry options" â€” the recipes are load-bearing.
- Heavy-split layout (orchestrator SKILL.md + topic `references/`) instead of flat skill directories â€” reduces SKILL.md context cost, improves topic-targeted routing.

## Vendor-blessed architectural patterns (from direct consultation)

Patterns recommended in customer-facing architecture conversations with Dynamicweb staff (not from the vendor repos above, which are agent-skill conventions). Documented here so sister skills can cite the source.

| Pattern | Source | Owning reference |
|---|---|---|
| **DC = AccessUser group** for any multi-DC B2B portal â€” unlocks DC-scoped Assortments, Shipping methods, and Shipping fees with no custom code. Naming convention: `DC-<code>`, with `AccessUserCustomerNumber` set to the same value. Treat as default for wholesale demos, not as an upgrade path. | Dynamicweb vendor architect | [`dynamicweb-swift-demo/references/b2b-dc-pattern.md`](../../dw-demo-swift/references/b2b-dc-pattern.md) |
| **ERP-imported pre-graduated prices** for any demo that needs cart-time qty-break behavior. `EcomPrices.PriceQuantity > 0` tier rows are silently ignored by the stock cart resolver â€” the production pattern is one row per (product, user-group, qty-band) with the resolved price baked in, indexed via the same user-group mechanic as the DC pattern. | Dynamicweb vendor architect | [`dynamicweb-pim-demo/references/structural-model.md` Â§2.11](../../dw-demo-pim/references/structural-model.md) |


