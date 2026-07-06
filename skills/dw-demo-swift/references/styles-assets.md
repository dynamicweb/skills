# styles-assets.md

> Per-demo Style assets (Color Schemes, Buttons, Typography, Fonts) — the higher-leverage re-skin lever above `<customer>_custom.css`. Cross-references out to [`re-skin.md`](re-skin.md) (escalation ladder) and [`admin-ui-authoring.md`](admin-ui-authoring.md) (Day-1 admin-UI workflow).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## The format lives in the foundational skill

Vendor-generic Swift Style-asset knowledge — the four `wwwroot/Files/System/Styles/{ColorSchemes,Buttons,Typography,Fonts}/` directories, the `<brand>.json` + `<brand>.css` pair format, how `Swift-v2_Master.cshtml`'s `Model.TryGet*Style` calls load them, the JSON schemas, the `Area.AreaColorSchemeGroupId` / `AreaButtonStyleId` / `AreaTypographyId` wiring SQL, and the silent empty-state pitfall (`TryGet*Style` returns `false` and adds nothing to `<head>` when the file is absent) — is owned by the `dw-swift-building` foundational skill — staged in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §7 ("Style assets").

Read that section for the asset format and wiring. This file carries the demo-infrastructure that sits on top of it: **where the reference style assets come from** and **how to stage them for a new demo**.

## Reference source: the theme layers in the Distribution

Canonical Style-asset examples ship as **theme layers** — `layers/theme-<name>/` (kind `theme`) in the
Distribution repo (`justdynamics/Truvio.Commerce.Distribution`). `Truvio.Commerce.DemoThemes` is
**archived**; its themes were folded in here. A theme layer is pure disk-overlay (styles + CSS + assets
under `files/`, mirroring the host's `wwwroot\Files\` tree) with **no serialized DB content**, so the
demo's Swift version (from the versions prompt) is only a compatibility check here, not a tag selector.
The theme layer lives in the demo's Distribution checkout at `<demo-root>\distribution\layers\theme-<name>\`;
pin it by the tag `layers/theme-<name>/<semver>` (or an edition that composes it).

```powershell
$demoRoot = (Get-Location).Path
$dist     = "$demoRoot\distribution"                 # the Distribution checkout (from deserialize-flow §3)
$theme    = "$dist\layers\theme-<name>"              # e.g. theme-tech-saas
if (-not (Test-Path "$theme\theme.json")) {
  $repo = if ($env:DW_DISTRIBUTION_REPO) { $env:DW_DISTRIBUTION_REPO } else { "justdynamics/Truvio.Commerce.Distribution" }
  if (-not (Test-Path "$dist\.git")) { git clone "https://github.com/$repo" $dist }
  $tag = git -C $dist tag --list "layers/theme-<name>/*" |
    Sort-Object { [version]($_ -replace '^layers/theme-<name>/','') } -Descending | Select-Object -First 1
  git -C $dist checkout $tag
  Write-Host "Checked out $tag — record it in CUSTOMISATIONS.md (the theme pin)"
}
```

A theme layer's `files/` mirrors the host overlay tree — the Style-asset areas plus brand images and
custom template overrides (each already branded, named after the theme):

```
<demo-root>\distribution\layers\theme-<name>\
├── theme.json                                          ← theme identity / metadata
├── layer.json                                          ← layer manifest (kind: theme)
└── files\                                              ← disk overlay — mirrors wwwroot\Files\
    ├── System\Styles\ColorSchemes\<name>.{json,css}    ← brand colour scheme
    ├── System\Styles\Buttons\<name>.{json,css}         ← button shape
    ├── System\Styles\Typography\<name>.{json,css}      ← typography
    ├── Images\<name>\...                               ← brand images (logo, etc.)
    └── Templates\Designs\Swift-v2\Custom\
        ├── <name>_custom.css                           ← Tier-1 custom CSS
        └── <Name>HeadInclude.cshtml                    ← head include (fonts, meta)
```

To stage for a new demo, overlay the theme layer's `files/` onto the host — it already sits at the
right sub-paths:

```powershell
$src = "$theme\files"
$dst = "<demo>\Dynamicweb.Host.Suite\wwwroot\Files"
Copy-Item -Recurse "$src\*" "$dst\" -Force   # lands ColorSchemes/Buttons/Typography brand + Images + Custom overrides
```

Then hand-edit the JSONs (rename `Id`, swap colors / fonts) and regenerate the CSS following the patterns in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §7, and wire the Area columns per the same section.

## When to use this vs `<customer>_custom.css`

- **Use Style assets (Tier 0) for the brand palette + button shape + typography.** It applies to every paragraph/row that has a scheme attribute, including the deserialized Swift base-layer content. Highest leverage per line of CSS.
- **Use `<customer>_custom.css` (Tier 1) for everything else** — hover effects, navigation polish, footer tweaks, hacks for empty `data-dw-colorscheme=""` paragraphs that the schemes can't reach. Loaded after the Style assets, so `<customer>_custom.css` rules win cascade ties.

## Cross-references

- [`admin-ui-authoring.md`](admin-ui-authoring.md) — admin-UI Day-1 workflow that writes these same files via the Style Tools UI. Use that path when a human is at the keyboard and admin-UI access is the cheapest interface.
- [`re-skin.md`](re-skin.md) — full escalation ladder + `<customer>_custom.css` wiring (the Tier 1 surface this file's Tier 0 sits below).
- [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §7 — the vendor-generic Style-asset format, Master loading, JSON schemas, Area wiring, and empty-state pitfall.
