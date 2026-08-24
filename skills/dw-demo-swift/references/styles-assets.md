# styles-assets.md

> Per-demo Style assets (Color Schemes, Buttons, Typography, Fonts) — the higher-leverage re-skin lever above `<customer>_custom.css`. Cross-references out to [`re-skin.md`](re-skin.md) (escalation ladder) and [`admin-ui-authoring.md`](admin-ui-authoring.md) (Day-1 admin-UI workflow).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Contents

- [The format lives in the foundational skill](#the-format-lives-in-the-foundational-skill)
- [Reference source: `theme-default` in the Distribution](#reference-source-theme-default-in-the-distribution)
- [Hand-editing a generated Style asset — edit the `.json` model too](#hand-editing-a-generated-style-asset--edit-the-json-model-too)
- [Webfonts arrive as an `@import` INSIDE the generated Typography sheet](#webfonts-arrive-as-an-import-inside-the-generated-typography-sheet)
- [When to use this vs `<customer>_custom.css`](#when-to-use-this-vs-customer_customcss)
- [Cross-references](#cross-references)

## The format lives in the foundational skill

Vendor-generic Swift Style-asset knowledge — the four `wwwroot/Files/System/Styles/{ColorSchemes,Buttons,Typography,Fonts}/` directories, the `<brand>.json` + `<brand>.css` pair format, how `Swift-v2_Master.cshtml`'s `Model.TryGet*Style` calls load them, the JSON schemas, the `Area.AreaColorSchemeGroupId` / `AreaButtonStyleId` / `AreaTypographyId` wiring SQL, and the silent empty-state pitfall (`TryGet*Style` returns `false` and adds nothing to `<head>` when the file is absent) — is owned by the `dw-swift-building` foundational skill — owned by [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §7 ("Style assets").

Read that section for the asset format and wiring. This file carries the demo-infrastructure that sits on top of it: **where the reference style assets come from** and **how to stage them for a new demo**.

## Reference source: `theme-default` in the Distribution

The Distribution ships **one theme layer** — `layers/theme-default/` (kind `theme`). There is no
theme choice and no overlay layers: every edition composes `theme-default` (`themes: ["default"]`),
and customer re-skins start FROM it ([`re-skin.md`](re-skin.md)). The former standalone demo-theme
repo is **archived**; the header-nav affordance CSS ships **inside** `theme-default`'s
`default_custom.css`. A theme layer is pure disk-overlay (styles + CSS + assets
under `files/`, mirroring the host's `wwwroot\Files\` tree) with **no serialized DB content**, so the
demo's Swift version (from the versions prompt) is only a compatibility check here, not a version selector.
The layer lives in the demo's Distribution clone at `<demo-root>\distribution\layers\theme-default\`;
it resolves from the live `layers/INDEX.json` on the latest gate-proven `main` (the usual demo consume).

```powershell
$demoRoot = (Get-Location).Path
$dist     = "$demoRoot\distribution"                 # the Distribution clone (from deserialize-flow §3)
$theme    = "$dist\layers\theme-default"
if (Test-Path "$dist\.git") {
  git -C $dist pull --ff-only origin main             # main IS the version — fast-forward to the gate-proven tip
} else {
  $repo = if ($env:DW_DISTRIBUTION_REPO) { $env:DW_DISTRIBUTION_REPO } else { "<owner>/<distribution-repo>" }
  git clone "https://github.com/$repo" $dist
}
$index = Get-Content "$dist\layers\INDEX.json" -Raw | ConvertFrom-Json
if (-not ($index.layers | Where-Object { $_.name -eq 'theme-default' })) {
  throw "theme-default absent from INDEX.json — check the retired tombstones for its successor."
}
Write-Host "On main $(git -C $dist rev-parse --short HEAD) — record the commit SHA in CUSTOMISATIONS.md (theme reproducibility stamp)"
```

The layer's `files/` mirrors the host overlay tree — the Style-asset areas plus the default custom
CSS and head include (no custom icon set: nav icons bind to the DW stock `/Files/Images/Icons` —
see [`header-menu.md`](header-menu.md)):

```
<demo-root>\distribution\layers\theme-default\
├── layer.json                                          ← layer manifest (kind: theme)
└── files\                                              ← disk overlay — mirrors wwwroot\Files\
    ├── System\Styles\ColorSchemes\default.{json,css}   ← colour scheme
    ├── System\Styles\Buttons\default.{json,css}        ← button shape
    ├── System\Styles\Typography\default.{json,css}     ← typography
    └── Templates\Designs\Swift-v2\Custom\
        ├── default_custom.css                          ← Tier-1 CSS incl. the header-nav affordance core
        └── DefaultHeadInclude.cshtml                   ← head include (fonts, meta)
```

To stage for a new demo, overlay the theme layer's `files/` onto the host — it already sits at the
right sub-paths:

```powershell
$src = "$theme\files"
$dst = "<demo>\Dynamicweb.Host.Suite\wwwroot\Files"
Copy-Item -Recurse "$src\*" "$dst\" -Force   # lands ColorSchemes/Buttons/Typography + Custom defaults
```

For a customer re-skin, leave `theme-default`'s files as staged and add the customer's own Styles
JSON+CSS pairs plus `<customer>_custom.css` on top ([`re-skin.md`](re-skin.md)); hand-edit patterns
and Area-column wiring follow [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §7.

## Hand-editing a generated Style asset — edit the `.json` model too

The `<design>.css` under `System/Styles/ColorSchemes/` is **generated output**, not the source of truth: the sibling `<design>.json` holds the same values as a model (`Schemes[].{Id, BackgroundColor, ForegroundColor, PrimaryButtonColor, SecondaryButtonColor, CustomColors}`) and the admin Styles editor writes both in a single operation — the two files carry the same `Last-Modified` to the second. Edit only the emitted `.css` and the model still carries the old value, so any regeneration (the next time anyone opens and saves the design) silently reverts the site, days later, with no deploy to blame.

So: when a demo must hand-edit a Style asset, **edit the `.json` in the same pass and upload both**; pre-flight should parse the `.json` and assert every scheme carries the new value, and the post-upload check should re-fetch both files and confirm zero literals of the retired value.

This is not an edge case for a palette change: primary buttons paint from `--dw-color-button-primary`, which is declared **only** in the generated colour-scheme CSS (as a hex *and* an `rgb` triplet, once per scheme). A `<customer>_custom.css` loaded afterwards cannot override a variable it never mentions, and declaring the variable there instead is the wrong fix — it leaves the model lying and the admin swatch stale. Full sweep: [`re-skin.md`](re-skin.md) §"A palette swap is a multi-file, multi-notation sweep".

## Webfonts arrive as an `@import` INSIDE the generated Typography sheet

**A Swift theme injects its webfont with `@import url(https://fonts.googleapis.com/css2?…)` on line 3 of
`/Files/System/Styles/Typography/<theme>.css` — there is no `<link>` in the head to act on.** A performance
report attributing ~933ms of render-blocking to `fonts.googleapis.com` therefore has no visible target: the
rendered HTML contains **zero** references to the font host, so the usual fixes (add a `preconnect` before
the `css2` link, or self-host and delete the link) find nothing to edit and read as "the tool is wrong".

An `@import` there is the worst case for the critical path — it is discovered only *after* the Typography
sheet downloads and parses, so the font CSS and then the woff2 files are two further serialised round trips
to a third party. Strip the `@import` from the generated sheet and declare `@font-face` in the Tier-1
custom sheet instead, with the woff2 files uploaded beside it (see the online-mode upload rule about
landing assets in a folder that already exists). Measured on one build: mobile Performance 74 → 82,
FCP 3.4s → 2.4s, Speed Index 3.4s → 2.4s, third-party font requests 2 → 0. `preconnect` alone saves only
the DNS/TLS portion and leaves the serialisation intact.

- **Regeneration caveat — this is a hand-edit of generated output.** Opening and saving the theme in admin
  restores the `@import`, exactly like the palette hand-edit above. Re-check the served Typography sheet
  after any design save, and record the edit in the demo ledger.
- **Prove the rendered face is unchanged, not just that the font "still loads".** Compare canvas text-run
  widths per weight, element geometry, and the browser's loaded-face list before and after — on the run
  that produced this rule, 13 self-hosted woff2 files reproduced all five weights plus the mono face
  byte-identically on every measure.

## When to use this vs `<customer>_custom.css`

- **Use Style assets (Tier 0) for the brand palette + button shape + typography.** It applies to every paragraph/row that has a scheme attribute, including the deserialized Swift base-layer content. Highest leverage per line of CSS.
- **Use `<customer>_custom.css` (Tier 1) for everything else** — hover effects, navigation polish, footer tweaks, hacks for empty `data-dw-colorscheme=""` paragraphs that the schemes can't reach. Loaded after the Style assets, so `<customer>_custom.css` rules win cascade ties — *except* against variables the Style assets declare and the custom sheet does not (see above).

## Cross-references

- [`admin-ui-authoring.md`](admin-ui-authoring.md) — admin-UI Day-1 workflow that writes these same files via the Style Tools UI. Use that path when a human is at the keyboard and admin-UI access is the cheapest interface.
- [`re-skin.md`](re-skin.md) — full escalation ladder + `<customer>_custom.css` wiring (the Tier 1 surface this file's Tier 0 sits below).
- [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §7 — the vendor-generic Style-asset format, Master loading, JSON schemas, Area wiring, and empty-state pitfall.
