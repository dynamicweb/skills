# asset-organisation.md

> `wwwroot/Files/` asset organisation for a Swift 2.2 / Dynamicweb 10 demo. Reference layouts at `<demo-root>\distribution\layers\base\` and Swift v2.3.0 at https://github.com/dynamicweb/Swift.
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

## Branding assets — a shared SVG is not safe to edit in place

Logo and icon SVGs under `Files/Images/branding/` are typically referenced by **more than one** page: the desktop and mobile header pages routinely inline the *same* file at two different pinned widths (e.g. 210px and 170px). An SVG `viewBox` trim changes the asset's intrinsic **aspect**, so every consumer that pins only a width silently gets a new height — trimming in place roughly doubles the mobile logo's height, grows the mobile header, and breaks a "mobile unchanged" guarantee, with a deploy-ordering window where both pages are wrong.

- **Upload the trimmed asset under a new filename and repoint exactly one reference.** Verify the untouched page still resolves to the original path, that the original asset still returns 200, and that its rendered height is unchanged.
- **Image/icon fields are `SelectedImage`** — the binder needs the object shape `{Id, Name, Ratio, FocalX, FocalY}`. A bare path string saves **empty**.
- **Measure before mandating that SVG text be outlined.** The usual argument — "if the webfont fails, the fallback reflows the text and a tight `viewBox` clips it" — is an assumption about relative font metrics, and it is cheap to test: render the asset twice, once normally and once with the font host aborted, and compare ink bboxes. A fallback is often *narrower*, and the vertical envelope is frequently set by a non-text element and is font-independent entirely. Size the `viewBox` to the wider of the two states and keep vector text. Outlining is also often not achievable faithfully: a site serving a single **variable** woff2 cannot be parsed by `opentype.js` (Brotli) nor reliably instanced on its axes, so the outline would ship subtly wrong glyph shapes — a worse defect than the one being mitigated. Reserve it for a measured overflow with a faithful static font instance available.
- Definition of done either way: with the font host aborted, the ink bbox stays inside the `viewBox` on all four sides and the rendered box geometry is identical across both font states.

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
