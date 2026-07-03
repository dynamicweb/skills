# styles-assets.md

> Per-demo Style assets (Color Schemes, Buttons, Typography, Fonts) — the higher-leverage re-skin lever above `<customer>_custom.css`. Cross-references out to [`re-skin.md`](re-skin.md) (escalation ladder) and [`admin-ui-authoring.md`](admin-ui-authoring.md) (Day-1 admin-UI workflow).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## The format lives in the foundational skill

Vendor-generic Swift Style-asset knowledge — the four `wwwroot/Files/System/Styles/{ColorSchemes,Buttons,Typography,Fonts}/` directories, the `<brand>.json` + `<brand>.css` pair format, how `Swift-v2_Master.cshtml`'s `Model.TryGet*Style` calls load them, the JSON schemas, the `Area.AreaColorSchemeGroupId` / `AreaButtonStyleId` / `AreaTypographyId` wiring SQL, and the silent empty-state pitfall (`TryGet*Style` returns `false` and adds nothing to `<head>` when the file is absent) — is owned by the `dw-swift-building` foundational skill — staged in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §7 ("Style assets").

Read that section for the asset format and wiring. This file carries the demo-infrastructure that sits on top of it: **where the reference style assets come from** and **how to stage them for a new demo**.

## Reference source: the DemoThemes release, downloaded per-demo

Canonical Style-asset examples ship as release zips in the **DemoThemes** distribution repo
`https://github.com/justdynamics/Truvio.Commerce.DemoThemes`, tagged `swift/<version>` (per-theme
zips). Download the theme for the demo's Swift version into the demo's own
`<demo-root>\baselines\themes\` folder (the versions prompt in `dw-demo-base` captured the Swift
version). Themes are pure disk-overlay (styles + CSS + assets) and carry no serialized DB content.

```powershell
$demoRoot = (Get-Location).Path
$themes   = "$demoRoot\baselines\themes"
$swiftVer = "2.3.0"                     # the demo's Swift version (from the versions prompt)
New-Item -ItemType Directory -Path $themes -Force | Out-Null
gh release download "swift/$swiftVer" --repo justdynamics/Truvio.Commerce.DemoThemes `
   --pattern '*.zip' --dir $themes      # per-theme zips for this Swift version
Get-ChildItem "$themes\*.zip" | ForEach-Object { Expand-Archive $_.FullName -DestinationPath $themes -Force; Remove-Item $_.FullName }
```

A downloaded theme unpacks with the four Style-asset directories at its root:

```
<demo-root>\baselines\themes\<theme>\
├── ColorSchemes\
│   ├── ColorScheme.config        ← list of predefined scheme NAMES Swift offers in admin UI
│   ├── swift.{json,css}          ← Swift's own default brand
│   └── <theme>.{json,css}        ← worked example brand
├── Buttons\
│   ├── buttons.{json,css}        ← Swift default (pill, 2.5rem padding)
│   └── <theme>.{json,css}        ← example (slight rounded, 1.5rem padding)
├── Typography\
│   ├── fonts.{json,css}          ← Swift default (Inter 500/600)
│   └── <theme>.{json,css}        ← example (local + Google fonts)
└── Fonts\
    ├── <theme>-*.{json,css}      ← @font-face definitions
    └── *.ttf / *.otf             ← actual font files
```

To stage for a new demo, copy from the downloaded theme into the host's Styles folder:

```powershell
$src = "$themes\<theme>"
$dst = "<demo>\Dynamicweb.Host.Suite\wwwroot\Files\System\Styles"
Copy-Item "$src\ColorSchemes\swift.json" "$dst\ColorSchemes\<brand>.json"
Copy-Item "$src\ColorSchemes\swift.css"  "$dst\ColorSchemes\<brand>.css"
Copy-Item "$src\Buttons\buttons.json"    "$dst\Buttons\<brand>.json"
Copy-Item "$src\Buttons\buttons.css"     "$dst\Buttons\<brand>.css"
Copy-Item "$src\Typography\fonts.json"   "$dst\Typography\<brand>.json"
Copy-Item "$src\Typography\fonts.css"    "$dst\Typography\<brand>.css"
```

Then hand-edit the JSONs (rename `Id`, swap colors / fonts) and regenerate the CSS following the patterns in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §7, and wire the Area columns per the same section.

## When to use this vs `<customer>_custom.css`

- **Use Style assets (Tier 0) for the brand palette + button shape + typography.** It applies to every paragraph/row that has a scheme attribute, including the deserialized Swift baseline content. Highest leverage per line of CSS.
- **Use `<customer>_custom.css` (Tier 1) for everything else** — hover effects, navigation polish, footer tweaks, hacks for empty `data-dw-colorscheme=""` paragraphs that the schemes can't reach. Loaded after the Style assets, so `<customer>_custom.css` rules win cascade ties.

## Cross-references

- [`admin-ui-authoring.md`](admin-ui-authoring.md) — admin-UI Day-1 workflow that writes these same files via the Style Tools UI. Use that path when a human is at the keyboard and admin-UI access is the cheapest interface.
- [`re-skin.md`](re-skin.md) — full escalation ladder + `<customer>_custom.css` wiring (the Tier 1 surface this file's Tier 0 sits below).
- [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §7 — the vendor-generic Style-asset format, Master loading, JSON schemas, Area wiring, and empty-state pitfall.
