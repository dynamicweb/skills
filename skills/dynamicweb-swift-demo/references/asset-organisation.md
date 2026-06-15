# asset-organisation.md

> `wwwroot/Files/` asset organisation conventions for a Swift 2.2 / Dynamicweb 10 demo. Reference layouts at `$env:DW_VAULT\serialized-data\Swift2.2\` and Swift v2.3.0 at https://github.com/dynamicweb/Swift.
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Top-level layout

`<demo>\Dynamicweb.Host.Suite\wwwroot\Files\` is the live host's asset root. Conventional sub-folders:

| Folder | What lives there | Edit policy |
|--------|------------------|-------------|
| `Images/` | Logo, hero imagery, product images dropped in by re-skin or by import_product_images_from_urls (PIM) | Drop-in safe — see [re-skin.md](re-skin.md) §1 |
| `Documents/` | PDF / docx attachments referenced by paragraphs (e.g. credit-note PDFs for off-invoice rebate visualisations) | Drop-in safe |
| `Templates/Designs/Swift-v2/` | Swift 2 design root (templates + assets). `Assets/css/swift.css` and DW-generated CSS under `Files/System/Styles/` are NEVER touched. The canonical override slot is `Custom/<customer>_custom.css` wired via the `Custom/<customer>HeadInclude.cshtml` partial — NOT `Assets/css/` (Swift-shipped output) and NOT overwriting the stock `Custom/custom.css` placeholder (see [re-skin.md](re-skin.md) §"Wiring up project-scoped custom.css"). | Stock `.cshtml` templates: do not modify -- create new content layouts alongside per [re-skin.md](re-skin.md) §Pixel-perfect escalation. `Custom/<customer>_custom.css`: edit/create freely. |
| `Templates/Paragraph/` | Built-in paragraph Razor templates | DO NOT EDIT -- same. Pixel-perfect alternative renderings are NEW content layouts alongside, not edits to these. |
| `Templates/Feeds/` | Feed Razor / XSLT templates (PIM concern) | See `dynamicweb-pim-demo/references/canonical-setup-order.md` step 19 |
| `System/Repositories/` | Index definitions + feed `.query` files (PIM concern) | See `dynamicweb-pim-demo/references/governance.md` "Dashboard query location" |
| `System/SmartSearches/Ecommerce/Shared/` | Dashboard `.query` files (PIM concern) | Shared ONLY — never duplicate to Repositories. See `dynamicweb-pim-demo/references/governance.md` |

## Asset upload via admin UI vs filesystem drop

Two equivalent ways to put a file into `wwwroot/Files/Images/`:

1. **Admin UI**: Settings → File management (or "Files" link in the top nav) → navigate to `Files/Images/` → Upload. Persists immediately; the file is visible to paragraph property pickers right away.
2. **Filesystem drop**: copy the file into `<demo>\Dynamicweb.Host.Suite\wwwroot\Files\Images\<name>`. Visible to admin UI on next directory-listing read; no restart required.

For a customer re-skin: filesystem drop is fine for the logo (it's a one-time op); admin UI upload is fine too. Both are recorded in `git status` the same way.

## Subfolder conventions for demos

When seeding demo content, prefer these subfolder conventions to keep things tidy:

- `Files/Images/products/<sku>/` — per-SKU product images (one folder per hero SKU keeps the demo storytelling clean per `dynamicweb-pim-demo/references/demo-storytelling.md`)
- `Files/Images/branding/` — logo, favicon, hero imagery for re-skin
- `Files/Documents/credit-notes/` — placeholder PDFs for off-invoice rebate visualisations (project-specific; see the demo's `.planning/REQUIREMENTS.md` for the relevant requirement ID)

## What lives OUTSIDE `wwwroot/Files/`

A few demo-relevant directories that are NOT under `wwwroot/Files/`:

- `<demo>\customer-context\` — read-only customer-supplied artefacts. NEVER write here. See [dynamicweb-demo-base/references/customer-context.md](../../dynamicweb-demo-base/references/customer-context.md).
- `<demo>\notes\` — your own working notes during the build. Free to write here.
- `<demo>\extracts\` — transformed / derived data extracted FROM customer-context (write-allowed).
- `<demo>\CUSTOMISATIONS.md` — the customisation budget ledger. See [dynamicweb-demo-base/references/customisations.md](../../dynamicweb-demo-base/references/customisations.md).
- `<demo>\docs\` — late-phase deliverables (e.g., a demo-day-runbook, architectural slides; specific filenames and requirement IDs are project-specific).

The `wwwroot/Files/` distinction matters because admin UI File management surfaces ONLY `wwwroot/Files/` content — anything else is shell-only.
