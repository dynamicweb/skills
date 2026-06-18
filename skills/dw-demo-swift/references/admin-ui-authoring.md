# admin-ui-authoring.md

> Swift 2 admin-UI authoring: the configuration-only Day-1 workflow (get 80% of the brand applied via admin Style tools alone, zero CSS / Razor / .cs edits â€” per [doc.dynamicweb.dev/swift/design/configuration-only.html](https://doc.dynamicweb.dev/swift/design/configuration-only.html)) plus the Visual Editor patterns for editing paragraph properties without touching code. Operates against a deserialized Swift 2.2 baseline (source-of-truth at `$env:DW_VAULT\serialized-data\Swift2.2\`).
>
> Swift 2.x guidance â€” never follow `/swift/swift-1/` URLs (different content model, phased out).

## When to use

The configuration-only approach is the default starting point for any Swift 2 demo re-skin â€” it covers most copy / asset / layout work with zero code. **Executor split:** the admin click-paths in this file are the *map* of what is configurable â€” for a human doing manual authoring, and as verification targets. When Claude makes a change itself, it resolves the click-path to the equivalent MCP / Management API call (every Visual Editor / Style-tools save is an Admin API call underneath) per the base surface-priority rule â€” [dynamicweb-demo-base/references/surface-priority.md](../../dw-demo-base/references/surface-priority.md) Â§"Admin UI is verification-only". Claude drives `/Admin` via Playwright only to verify a change landed, never to author. Escalate to [re-skin.md](re-skin.md) Â§`<customer>_custom.css` only when the admin Style tools cannot express the visual you need; escalate further (content-layout `.cshtml`) only when a tailored screen requires a new rendering â€” see [re-skin.md](re-skin.md) Â§Pixel-perfect escalation. Only the controller/provider `.cs` tier triggers base's customisations-ledger preflight.

## The 5-step Day-1 workflow (configuration-only)

1. **Mood board.** Pull from the demo's read-only `<demo>\customer-context\` (intro-call materials, brand guide, the customer's public site as reference). Capture: primary brand color, secondary palette, typography preferences, button shape, logo, icon style, hero imagery.
2. **Translate mood board into Style tools.** Admin UI:
   - Settings â†’ Content â†’ Styles â†’ **Color Schemes** (primary palette + scheme variants)
   - Settings â†’ Content â†’ Styles â†’ **Typography** (font family, scale, weights)
   - Settings â†’ Content â†’ Styles â†’ **Buttons** (shape, padding, hover states)
3. **Upload assets via Assets manager** â€” logo, favicon, hero imagery into `Files/Images/branding/` per [asset-organisation.md](asset-organisation.md).
4. **Connect styles to website settings.** Admin UI:
   - Website Settings â†’ **Layout** tab â†’ bind the new color scheme + typography
   - Content section â†’ Design section â†’ **Favicon** â†’ upload + bind
5. **Build layout in Visual Editor.** Admin UI: Pages â†’ page-preset â†’ grid row â†’ paragraphs. See the Visual Editor sections below and [templates.md](templates.md).

The configuration-only doc is candid that the approach "will consequently not be able to do everything" â€” if the customer's brand requires something the style tools can't express, escalate per [re-skin.md](re-skin.md), don't fight the configuration surface.

## Visual Editor surfaces (where it lives in admin UI)

- **Pages** â†’ any page-preset or content page â†’ grid row â†’ paragraph: clicking a paragraph opens its property panel; that panel IS the Visual Editor for that paragraph type.
- **Settings** â†’ **Areas** â†’ **SHOP1** â†’ **Site Settings**: site-level affordances (title, default language, fallback layout).
- **Pages** â†’ **Theme** (the `Theme` page-preset): theme-tokens-as-paragraph-properties; the standard re-skin entrypoint per [re-skin.md](re-skin.md).

The Style-tools admin paths in workflow step 2 + 4 above are the same forms the Visual Editor theme work uses â€” one set of paths, stated once.

## What the Visual Editor covers, and the escalation per gap

| Change | Visual Editor | Escalation if VE cannot do it |
|--------|---------------|------------------------------|
| Theme tokens (colors, typography) | YES (Style tools paths in step 2; bind via Website Settings â†’ Layout) | `<customer>_custom.css` overrides consuming `--dw-*` variables ([re-skin.md](re-skin.md) â€” never the stock `custom.css`) |
| Logo / hero image swap | YES (paragraph property â†’ asset file path) | n/a (VE handles fully) |
| Header / footer copy | YES (paragraph text content) | n/a (VE handles fully) |
| Add a new content paragraph to a page | YES (Admin UI â†’ page â†’ "Add paragraph" â†’ pick type) | n/a (VE handles fully) |
| Need a layout shape no existing page-preset matches; new column / alternative rendering for a paragraph type | NO | New content layout `.cshtml` per [re-skin.md](re-skin.md) Â§Pixel-perfect escalation â€” **not** a customisations-ledger preflight hit (see Razor-glob note below) |
| Site title | YES (Settings â†’ Areas â†’ SHOP1 â†’ Site Settings) | n/a (VE handles fully) |
| Data-shape transformation, conditional rendering, external calls / business logic | NO | Controller / provider `.cs` â€” triggers base's customisations-ledger preflight (Approve+log / Refactor / Cancel). See [dynamicweb-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md). |

**Razor `.cshtml` is NOT in the customisations-ledger glob.** The right-column escalations do not all trigger the preflight â€” only `.cs` controllers / providers do. Per [dynamicweb-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md) Â§5, Razor content layouts are conventional, normal demo-build flow per the Swift docs ([doc.dynamicweb.dev/swift/design/pixel-perfect.html](https://doc.dynamicweb.dev/swift/design/pixel-perfect.html)).

## Verification: did the change land via the admin UI?

After any Visual Editor / Style-tools edit on a running host:

```powershell
# In the demo solution folder
git status
```

You should see ONLY these classes of file change:
- `Dynamicweb.Host.Suite/wwwroot/Files/Images/<your-uploaded-asset>` (logo / hero swaps)
- `Dynamicweb.Host.Suite/wwwroot/Files/Templates/Designs/Swift-v2/<paragraph-instance-config>.json` (paragraph property persistence â€” these are config, not Razor)
- `Files/System/Styles/{ColorSchemes,Buttons,Typography}/*.{json,css}` (Style-tools saves â€” see [styles-assets.md](styles-assets.md))

You should NEVER see:
- `*.cs` changes in `Controllers/` or `Providers/` (would mean a custom controller was added â€” triggers the customisations-ledger preflight in base)
- `*.scss` / `*.ts` changes (would mean asset-pipeline source was touched â€” recompilation drift)
- Changes to any file named exactly `custom.css` (Swift-shipped sample code â€” brand CSS belongs in `<customer>_custom.css`; hard rule in [re-skin.md](re-skin.md) Â§What NOT to touch, audit grep #9 in [dw10-canonical-surfaces.md](dw10-canonical-surfaces.md))

If `*.cshtml` changes appear, that is **not automatically a preflight hit** (Razor-glob note above). New content-layout `.cshtml` files are part of the normal escalation ladder ([re-skin.md](re-skin.md) Â§Pixel-perfect escalation); modifications to existing standard `.cshtml` templates under `Files/Templates/Designs/Swift-v2/` or `Files/Templates/Paragraph/` are the thing to avoid â€” per the pixel-perfect doc quoted in [re-skin.md](re-skin.md) Â§Pixel-perfect escalation: extend or create new templates, never modify standard ones.

## What this surface does NOT do (escape hatches)

Some changes don't have an admin-UI authoring surface and require either preflight-approved customisation or live in a different skill:

- **Customer-center CSR section customisation** â€” never; see [customer-center.md](customer-center.md) (the stock-CSR rule).
- **Customer-flavoured products / orders seeding** â€” project-specific data work, not a styling concern.
- **New product fields / completeness rules** â€” PIM concern. See [dynamicweb-pim-demo/references/structural-model.md Â§2.8](../../dw-demo-pim/references/structural-model.md) and `dynamicweb-pim-demo/references/canonical-setup-order.md` step 7.
- **MCP tool wiring** â€” base concern. See `dynamicweb-demo-base/references/mcp-setup.md`.
- **Custom payment provider / shipping carrier** â€” out of scope for Dynamicweb demos (a known customisation trap).
- **`<customer>_custom.css` / `.scss` / `.cshtml` work** â€” the escalation ladder in [re-skin.md](re-skin.md). (Brand CSS never goes in a file named `custom.css` â€” that's Swift-shipped sample code; hard rule in re-skin.md Â§What NOT to touch.)


