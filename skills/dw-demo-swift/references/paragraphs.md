# paragraphs.md

> Swift 2.2 paragraph guardrails for demos. Source-of-truth: paragraphs are exposed in admin UI under each page; backing definitions live in `wwwroot/Files/Templates/Paragraph/` (built-in — read-only) and the page-preset YAML at `$env:DW_VAULT\serialized-data\Swift2.2\_content\Swift 2\<area>\<page>\<grid-row>\paragraph-*.yml`.
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

The vendor-generic paragraph survey (component-first gate, paragraph categories, item-field
configuration, the cache pitfalls) has been folded up into the foundational candidates. What stays
here is the demo guardrail: the paragraph types you must NOT replace.

| If you need… | Read |
|---|---|
| Component-first gate (map a requirement to a standard `Swift-v2_*` component before customising); paragraph categories; configuring paragraph item-type fields (PDP enrichment, `FieldDisplayGroups`/`SelectedGroups`, `EcomFieldDisplayGroups` cache, aspect-ratio token, `Swift-v2_Row` knobs, `ProductDetailRenderGrid` sourcing) | [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §1, §3 |
| Empty-`ParagraphTemplate` resolves to first cshtml alphabetically (silent hijack) + both mitigations | [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §4 |
| Grid-composition cache (host-restart for paragraph deletion) + `ProductListComponentSelector` `RenderGrid` cache (CSS-hide is the only lever) | [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §5 |
| ProductHeader **ProductViewModel field inventory** (`ManufacturerName` not `Manufacturer.Name`; what's available vs what only looks like it is) | [`render-viewmodels.md`](../../dw-demo-base/references/foundational/render-viewmodels.md) |
| SQL-direct Paragraph INSERT required columns | [`sql-direct-seeding.md`](sql-direct-seeding.md) |

## Where to find a paragraph's wiring (read-only vault inspection)

To trace what a specific paragraph does on a Swift 2.2 page: note the page in admin (e.g.
`Customer center/CSR/Orders`); the corresponding YAML lives at
`$env:DW_VAULT\serialized-data\Swift2.2\_content\Swift 2\Customer center\CSR\Orders\grid-row-1\paragraph-c1-1.yml`;
the YAML's `Type` field names the paragraph definition and the rest carries its configured properties.
This is read-only inspection — you don't edit the vault YAML; you edit paragraph properties via the
Admin UI Visual Editor on the live host (which writes to the host's project DB, not back to the vault).

## "Don't customise this paragraph" callouts

A few paragraph types are stock-load-bearing for typical B2B-distributor demo differentiators
(sales-on-behalf, mixed-source orders, complex pricing) and must NEVER be replaced with custom Razor:

- **Customer center / CSR / Orders paragraph** — the stock paragraph already supports impersonation +
  mixed-source order viewing + the `OrderSource` discriminator badge; rebuilding loses that wiring. See
  [customer-center.md](customer-center.md).
- **Cart summary / Checkout step paragraphs** — high regression risk; touching these triggers the
  customisations-ledger preflight in base. See [re-skin.md](re-skin.md) "What NOT to touch".
- **Product detail paragraph** — relies on the Lucene index + the PIM completeness rules; modifying it
  can mask "rules don't show" symptoms. See
  [dynamicweb-pim-demo/references/governance.md](../../dw-demo-pim/references/governance.md).

These callouts generalise into the component-first gate (enumerate the standard component, configure it,
override only as a last resort) owned by
[`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §1.
