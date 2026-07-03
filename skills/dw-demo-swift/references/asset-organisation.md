# asset-organisation.md

> `wwwroot/Files/` asset organisation for a Swift 2.2 / Dynamicweb 10 demo. Reference layouts at `<demo-root>\baselines\swift-2.3\` and Swift v2.3.0 at https://github.com/dynamicweb/Swift.
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

The vendor-generic `wwwroot/Files/` layout (the top-level folder table + edit policies, admin-UI
upload vs filesystem drop, and the "admin File management surfaces only `wwwroot/Files/`" rule) is
owned by the `dw-swift-building` foundational skill — staged in
[`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §8 ("Asset
organisation under `wwwroot/Files/`"). This file carries the demo-specific subfolder conventions on top
of it.

## Subfolder conventions for demos

When seeding demo content, prefer these subfolder conventions to keep things tidy:

- `Files/Images/products/<sku>/` — per-SKU product images (one folder per hero SKU keeps the demo
  storytelling clean per `dynamicweb-pim-demo/references/demo-storytelling.md`)
- `Files/Images/branding/` — logo, favicon, hero imagery for re-skin
- `Files/Documents/credit-notes/` — placeholder PDFs for off-invoice rebate visualisations
  (project-specific; see the demo's `.planning/REQUIREMENTS.md` for the relevant requirement ID)

## What lives OUTSIDE `wwwroot/Files/` (demo working folders)

A few demo-relevant directories that are NOT under `wwwroot/Files/` (and therefore shell-only — admin
UI File management never surfaces them):

- `<demo>\customer-context\` — read-only customer-supplied artefacts. NEVER write here. See
  [dynamicweb-demo-base/references/customer-context.md](../../dw-demo-base/references/customer-context.md).
- `<demo>\notes\` — your own working notes during the build. Free to write here.
- `<demo>\extracts\` — transformed / derived data extracted FROM customer-context (write-allowed).
- `<demo>\CUSTOMISATIONS.md` — the customisation budget ledger. See
  [dynamicweb-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md).
- `<demo>\docs\` — late-phase deliverables (e.g. a demo-day runbook, architectural slides; specific
  filenames and requirement IDs are project-specific).
