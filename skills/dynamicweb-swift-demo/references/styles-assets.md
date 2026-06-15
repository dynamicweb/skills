# styles-assets.md

> Per-demo Style assets (Color Schemes, Buttons, Typography, Fonts) — the higher-leverage re-skin lever above `<customer>_custom.css`. Cross-references out to [`re-skin.md`](re-skin.md) (escalation ladder) and [`admin-ui-authoring.md`](admin-ui-authoring.md) (Day-1 admin-UI workflow).
>
> **TL;DR:** Drop a `<brand>.json` + `<brand>.css` pair into each `wwwroot/Files/System/Styles/{ColorSchemes,Buttons,Typography}/`, point the Area row's `AreaColorSchemeGroupId` / `AreaButtonStyleId` / `AreaTypographyId` columns at `<brand>`, restart host. The Master template's `Model.TryGet*Style` calls auto-load the matching CSS file; every `data-dw-colorscheme="<id>"` attribute on a paragraph/row resolves against `<brand>.json`'s `Schemes[].Id` entries. Reference vault: **`$env:DW_VAULT\dw-swift-styles\`** (carries Swift defaults + a Fixaflex example).

## Why this is the higher-leverage tier

The re-skin escalation ladder in [re-skin.md](re-skin.md) lists four tiers:

| Tier | Surface | What it touches |
|------|---------|-----------------|
| 0 | Admin UI Style Tools (Settings → Content → Styles) | Color schemes, button shape, typography — generates the `Styles/*.{json,css}` pairs covered here |
| 1 | `Custom/<customer>_custom.css` | Brand variables, hover states, hacks the schemes don't cover |
| 2 | New layout-only `.cshtml` content layouts | Pixel-perfect reshaping of an item type's render |
| 3 | Controller / provider `.cs` (customisations-ledger preflight) | Anything that needs server-side logic |

**This file owns Tier 0 done by hand** — when MCP / a headless agent / a fresh-machine setup needs to drop the brand styles into a demo without admin-UI clicks. The output is identical to what admin Style Tools would write.

## The four asset directories

All under `wwwroot/Files/System/Styles/`:

| Directory | Purpose | Files | Area column that points here |
|-----------|---------|-------|------------------------------|
| `ColorSchemes/` | Named color schemes (Light, Dark, Primary…) — each is a set of background/foreground/button colors emitted as CSS variables under `[data-dw-colorscheme="<id>"]`. Also contains `ColorScheme.config` listing the predefined SCHEME NAMES that admin UI offers. | `<brand>.json` (group), `<brand>.css` (generated) | `Area.AreaColorSchemeGroupId` (group id) + `Area.AreaColorSchemeId` (default scheme id within the group) |
| `Buttons/` | Button shape, padding, border-radius, border-width — emitted as CSS variables on `[data-dw-button]`. | `<id>.json`, `<id>.css` | `Area.AreaButtonStyleId` |
| `Typography/` | Font families, weights, scale, line-heights for body/heading/button — emitted as CSS variables on `body`, `h1..h6, .dw-h1..h6`, `[data-dw-button]`. | `<id>.json`, `<id>.css` (CSS may also `@import` Google Fonts or `@font-face` `Files/System/Styles/Fonts/*.{ttf,otf}`) | `Area.AreaTypographyId` |
| `Fonts/` | Individual `@font-face` definitions — referenced from a Typography JSON's `ParagraphCustomFontId` / `HeadingCustomFontId` / `ButtonCustomFontId`. | `<font-id>.json`, `<font-id>.css`, `<file>.{ttf,otf,woff2}` | (none — Typography JSON refers by id) |

The `<brand>.json` files are the source of truth — they're what admin Style Tools writes when you save in the UI. The `<brand>.css` files are mechanically generated from the JSON. **Hand-authoring works** because the Master template only loads the CSS; the JSON is consumed by admin Style Tools (and by Visual Editor previews), so your hand-written CSS works at runtime even if the JSON is technically inconsistent — keep them in sync anyway because the next admin-UI save will regenerate the CSS from the JSON.

## How the Master template loads them

`wwwroot/Files/Templates/Designs/Swift-v2/Swift-v2_Master.cshtml` (lines ~32-46 in stock Swift 2.2):

```cshtml
AddStylesheet("/Files/Templates/Designs/Swift-v2/Assets/css/swift.css");

@if (Model.TryGetColorSchemeStyle(out string? colorSchemeStyle)) {
    AddStylesheet(colorSchemeStyle);
}
@if (Model.TryGetButtonStyle(out string? buttonStyle)) {
    AddStylesheet(buttonStyle);
}
@if (Model.TryGetTypographyStyle(out string? typographyStyle)) {
    AddStylesheet(typographyStyle);
}
```

`TryGet*Style` returns the URL to the file at `Files/System/Styles/{ColorSchemes,Buttons,Typography}/<area-column-value>.css` if it exists. **Returns `false` (and adds nothing to `<head>`) if the file is absent on disk.** That's the silent-no-op pitfall in §"Empty-state pitfall" below.

## JSON schemas

### ColorSchemes/`<brand>`.json

```json
{
  "Name": "Acme",
  "Id": "acme",
  "Schemes": [
    {
      "GroupId": "acme",
      "Name": "Light",
      "Id": "light",
      "BackgroundColor": "#FFFFFF",
      "ForegroundColor": "#1F2937",
      "PrimaryButtonColor": "#C8202F",
      "SecondaryButtonColor": "#1F2937",
      "CustomColors": []
    },
    { "...more schemes..." }
  ]
}
```

The `Id` at root is what `Area.AreaColorSchemeGroupId` points at. Each `Schemes[].Id` is what a paragraph's `data-dw-colorscheme` resolves against. Convention is to ship the same scheme `Id`s as Swift's defaults (`light`, `lightgrey1`, `lightgrey2`, `dark`, `darksubtle`, `primary`, `secondary`) so the deserialized Swift content's existing `data-dw-colorscheme="dark"` attributes etc. map cleanly to your brand's schemes.

The corresponding CSS emits one rule per scheme:

```css
.dw-colorscheme-light, [data-dw-colorscheme="light"] {
    --dw-color-background: #FFFFFF;
    --dw-color-background-rgb: 255, 255, 255;
    --dw-color-foreground: #1F2937;
    --dw-color-foreground-rgb: 31, 41, 55;
    --dw-color-button-primary: #C8202F;
    --dw-color-button-primary-rgb: 200, 32, 47;
    --dw-color-button-primary-contrast: #ffffff;
    --dw-color-button-secondary: #1F2937;
    --dw-color-button-secondary-rgb: 31, 41, 55;
    --dw-color-button-secondary-contrast: #ffffff;
}
```

The `*-rgb` companions are required for `rgba(var(--dw-color-foreground-rgb), 0.5)` opacity tricks elsewhere in Swift.

### Buttons/`<id>`.json

```json
{
  "Id": "acme",
  "Name": "Acme",
  "Shape": 1,
  "BorderSize": 1,
  "PaddingY": 0.7,
  "PaddingX": 1.5
}
```

`Shape` enum: **1** = slight rounded (`border-radius: 0.25-0.35rem`), **2** = pill (`border-radius: 50rem`). `PaddingY` and `PaddingX` are in `rem`.

CSS:

```css
.dw-button, [data-dw-button] {
    --dw-btn-padding-x: 1.5rem;
    --dw-btn-padding-y: 0.7rem;
    --dw-btn-border-radius: 0.25rem;
    --dw-btn-border-width: 1px;
}
```

### Typography/`<id>`.json

```json
{
  "Id": "acme",
  "Name": "Acme",
  "BaseFontSize": 16,
  "BaseFontScale": 1.25,
  "ParagraphFont": "Inter",
  "ParagraphFontWeight": 500,
  "ParagraphLineHeight": 1.55,
  "HeadingFont": "Inter",
  "HeadingFontWeight": 700,
  "HeadingLetterSpacing": -0.015,
  "HeadingLineHeight": 1.2,
  "ButtonFont": "Inter",
  "ButtonFontWeight": 600,
  "ButtonLineHeight": 1.1
}
```

For a custom local font (not a Google Font), use `ParagraphCustomFontId: "Fixaflex-3"` instead of `ParagraphFont` — that ID resolves against `Fonts/<id>.json`'s `Family`.

CSS:

```css
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@500;600;700&display=swap');

body, .preview {
    --dw-base-font-size: 16px;
    --dw-type-scale: 1.25;
    --dw-font-family: Inter;
    --dw-font-weight: 500;
    --dw-line-height: 1.55;
    --dw-letter-spacing: 0;
    --dw-text-transform: none;
}

h1, h2, h3, h4, h5, h6, .dw-h1, .dw-h2, .dw-h3, .dw-h4, .dw-h5, .dw-h6 {
    --dw-font-family: Inter;
    --dw-font-weight: 700;
    --dw-letter-spacing: -0.015em;
    --dw-line-height: 1.2;
}

[data-dw-button] {
    --dw-font-family: Inter;
    --dw-font-weight: 600;
    --dw-line-height: 1.1;
}
```

### Fonts/`<id>`.json + `<id>`.css (when using local fonts)

JSON:

```json
{
  "Id": "Fixaflex-1",
  "Name": "Ubuntu-Light",
  "Family": "Ubuntu",
  "FilePath": "/Files/System/Styles/Fonts/Ubuntu-Light.ttf",
  "Weight": 300,
  "Style": "normal"
}
```

CSS:

```css
@font-face {
    font-family: 'Ubuntu';
    font-style: normal;
    font-weight: 300;
    font-display: swap;
    src: url('/Files/System/Styles/Fonts/Ubuntu-Light.ttf') format('truetype');
}
```

The `.ttf` / `.otf` file lives alongside in `Fonts/`. Reference vault has the full Ubuntu / Neutra Text family.

## Wiring the Area to a brand

```sql
UPDATE Area SET
  AreaColorSchemeGroupId = '<brand>',   -- root Id from ColorSchemes/<brand>.json
  AreaColorSchemeId      = 'light',     -- which scheme is the area default
  AreaButtonStyleId      = '<brand>',   -- root Id from Buttons/<brand>.json
  AreaTypographyId       = '<brand>'    -- root Id from Typography/<brand>.json
WHERE AreaId = <area>;
```

Restart host so the area's resolved style URLs reload from disk. Verify with `curl -ks <host>/ | grep -E 'Styles/(ColorSchemes|Buttons|Typography)/'` — should show three new `<link rel="stylesheet">` entries pointing at your brand files.

## Empty-state pitfall (silent no-op)

A fresh `dw10-suite` scaffold leaves `Area.AreaColorSchemeGroupId='swift'` (Swift's default brand id) but the Suite project does NOT ship `Files/System/Styles/{ColorSchemes,Buttons,Typography}/swift.{json,css}` files on disk. So:

- `Model.TryGetColorSchemeStyle(out url)` returns `false`
- No color-scheme stylesheet is added to `<head>`
- Every `data-dw-colorscheme="dark"` paragraph renders against the default body styles (white background, black text)
- The page LOOKS like the styles work — Swift.css ships baseline rules — but the BRAND palette never lands

**Diagnostic:** `curl -ks <host>/ | grep -c 'Styles/ColorSchemes'`. Returns 0 → empty-state. Returns 1 → wired. The fix is exactly the §"Wiring the Area to a brand" SQL above, paired with on-disk `<brand>.{json,css}` files.

## Reference vault: `$env:DW_VAULT\dw-swift-styles\`

Carries the canonical examples — copy and rename when starting a new demo:

```
$env:DW_VAULT\dw-swift-styles\
├── ColorSchemes\
│   ├── ColorScheme.config        ← list of predefined scheme NAMES Swift offers in admin UI
│   ├── swift.{json,css}          ← Swift's own default brand
│   └── Fixaflex.{json,css}       ← worked example: Fixaflex demo's blue brand
├── Buttons\
│   ├── buttons.{json,css}        ← Swift default (pill, 2.5rem padding)
│   └── FixaFlex.{json,css}       ← Fixaflex example (slight rounded, 1.5rem padding)
├── Typography\
│   ├── fonts.{json,css}          ← Swift default (Inter 500/600)
│   └── FixaFlex.{json,css}       ← Fixaflex (Ubuntu local + Google)
└── Fonts\
    ├── Fixaflex-1.{json,css}     ← Ubuntu-Light @font-face definition
    ├── Fixaflex-2.{json,css}     ← ...etc
    ├── Ubuntu-*.ttf              ← actual font files
    └── neutra-text-*.otf
```

To clone for a new demo:

```powershell
$src = "$env:DW_VAULT\dw-swift-styles"
$dst = "<demo>\Dynamicweb.Host.Suite\wwwroot\Files\System\Styles"
Copy-Item "$src\ColorSchemes\swift.json" "$dst\ColorSchemes\<brand>.json"
Copy-Item "$src\ColorSchemes\swift.css"  "$dst\ColorSchemes\<brand>.css"
Copy-Item "$src\Buttons\buttons.json"    "$dst\Buttons\<brand>.json"
Copy-Item "$src\Buttons\buttons.css"     "$dst\Buttons\<brand>.css"
Copy-Item "$src\Typography\fonts.json"   "$dst\Typography\<brand>.json"
Copy-Item "$src\Typography\fonts.css"    "$dst\Typography\<brand>.css"
```

Then hand-edit the JSONs (rename `Id`, swap colors / fonts) and regenerate the CSS following the patterns above.

## When to use this vs `<customer>_custom.css`

- **Use this (Tier 0) for the brand palette + button shape + typography.** It applies to every paragraph/row that has a scheme attribute, including the deserialized Swift baseline content. Highest leverage per line of CSS.
- **Use `<customer>_custom.css` (Tier 1) for everything else** — hover effects, navigation polish, footer tweaks, hacks for empty `data-dw-colorscheme=""` paragraphs that the schemes can't reach. Loaded after the Style assets, so `<customer>_custom.css` rules win cascade ties.

## Cross-references

- [`admin-ui-authoring.md`](admin-ui-authoring.md) — admin-UI Day-1 workflow that writes these same files via the Style Tools UI. Use that path when a human is at the keyboard and admin-UI access is the cheapest interface.
- [`re-skin.md`](re-skin.md) — full escalation ladder + `<customer>_custom.css` wiring (the Tier 1 surface this file's Tier 0 sits below).
- [`templates.md`](templates.md) — Master template anatomy; line-numbered breakdown of where `Model.TryGet*Style` is called.
