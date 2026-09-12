# styles-assets.md

> Per-demo Style assets (Color Schemes, Buttons, Typography, Fonts) — the higher-leverage re-skin lever above `<customer>_custom.css`. Cross-references out to [`re-skin.md`](re-skin.md) (escalation ladder) and [`admin-ui-authoring.md`](admin-ui-authoring.md) (Day-1 admin-UI workflow).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Contents

- [The format lives in the foundational skill](#the-format-lives-in-the-foundational-skill)
- [Reference source: `theme-default` in the Distribution](#reference-source-theme-default-in-the-distribution)
- [The Tier-0 motion for a customer re-skin: net-new PAIRS, stock scheme ids](#the-tier-0-motion-for-a-customer-re-skin-net-new-pairs-stock-scheme-ids)
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

**Do not pull here — assert the scaffold SHA.** The scaffold pass owns the Distribution checkout and
recorded its SHA in `CUSTOMISATIONS.md` as the build's reproducibility stamp
([`dw-demo-base/references/scaffold.md`](../../dw-demo-base/references/scaffold.md) "This pass owns
the checkout"). Read `git -C $dist rev-parse HEAD`, compare it with the recorded stamp, and **stop**
on a mismatch with "distribution checkout moved since scaffold, <recorded> -> <current>" rather than
continuing on layer content the earlier passes never saw. The clone branch below stays only for a
checkout that does not exist yet; record its SHA as the stamp if this is the first pass to run.

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

**Staging the files is not the last step — wire the head include, or none of it loads.** The overlay
lands `DefaultHeadInclude.cshtml` and `default_custom.css` on disk, and the include is only ever
reached through the area item field `Swift-v2_Master.CustomHeadInclude`, which nothing in the overlay
sets. Until that field points at the staged include, the theme's custom sheet and its CSS custom
properties are simply absent from every rendered page — with no error, and with the Style-asset
sheets themselves loading normally, so three of the four sheets link and the fourth does not.

```
Swift-v2_Master.CustomHeadInclude = /Files/Templates/Designs/Swift-v2/Custom/DefaultHeadInclude.cshtml
```

Set it once per environment, by SQL or by a full `websiteItem` round-trip through `AreaSave`. **The
field is environment-owned** — it sits in the serializer config's `excludeFieldsByItemType`, so the
deserializer will neither write it nor overwrite it: it must be set on the host rather than shipped
in content, and it survives a re-deserialize afterwards.

Gate it on the rendered page, not on the file copy: fetch `/` and assert **all four** theme sheets
are linked (the three Style-asset sheets plus `Custom/default_custom.css`) and at least one of the
theme's inline custom properties is present; then re-run the deserialize and re-assert, which is what
proves the field is environment-owned rather than merely set. **Run that gate after every deserialize,
not only during a re-skin.** A one-shot deserialize leaves the field empty, the three Style-asset sheets
link normally, nothing errors, and a structural proof reports green over a site missing its entire
Tier-1 token block — so the gate belongs in the deserialize flow
([`deserialize-flow.md`](deserialize-flow.md)) and the missing `Custom/default_custom.css` is a FAIL,
not a polish item.

**The field holds ONE path, and `default_custom.css` is registered from inside the default include.**
Pointing `CustomHeadInclude` at a customer head include therefore *unloads* `theme-default`'s Tier 1
unless the customer include registers it again — the natural reading, point the field at the customer
include and expect both sheets, loses the theme silently and with no error. The customer include carries
**both** `AddStylesheet` calls, in the load order the Tier-0 motion below prescribes
(`default_custom.css` first, `<customer>_custom.css` second). Assert on the served head: five sheets,
the two `Custom/` sheets last and in that order.

For a customer re-skin, leave `theme-default`'s files as staged and add the customer's own Styles
JSON+CSS pairs plus `<customer>_custom.css` on top ([`re-skin.md`](re-skin.md)); hand-edit patterns
and Area-column wiring follow [`component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md) §7.

## The Tier-0 motion for a customer re-skin: net-new PAIRS, stock scheme ids

A customer brand pass has two tempting wrong moves. The first is editing `theme-default`'s `default.*`
Style assets in place, which the re-skin hard rule forbids and which the next layer update reverts. The
second is the silent one: creating a net-new ColorScheme group with the **customer's own scheme ids**.
Every deserialized content row carries a `data-dw-colorscheme` referencing a scheme id **by name**, so
renaming the ids makes each row resolve to nothing and the site loses its banding with no error.
`Swift-v2_Master.TryGetColorSchemeStyle` resolves
`/Files/System/Styles/ColorSchemes/<Area.AreaColorSchemeGroupId>.css`, so the **group** is repointable
per area while the ids inside the file are the binding key.

**The surface is the style tools, not a hand-edit.** `save_color_schemes`, `save_typographies` and
`save_button_styles` write the `.json` model and regenerate the `.css` in one operation (the group is
created if it does not exist), and `save_areas` repoints the area at the result. Read the current state
back with `get_color_schemes`, `get_typographies` and `get_button_styles` first: everything below is a
partial edit of what the theme layer already staged, not a build from nothing.

**First, choose the group — the two answers behave differently and the choice has to be recorded.**

| Choice | When it is right | What it costs |
|---|---|---|
| **Write the shipped group** (`default`) in place | The area already binds it and the demo will not be re-staged from the theme layer again | A re-stage of `theme-default`'s `files/` reverts the palette; record that in the ledger as an accepted consequence |
| **Create a net-new `<customer>` group** and repoint the area | The shipped group must survive a layer refresh, or the host serves more than one branded area | One extra `save_areas` call, and every later read has to name the customer group rather than `default` |

Either way the ids inside the group stay the stock seven — that half is unchanged and is the load-bearing one.

The prescribed motion:

1. Write the palette with `save_color_schemes`, tagging every row with the chosen `groupId`. One call
   carries all seven schemes. The tool writes the `.json` model and regenerates the `.css` together, so
   the "edit the `.json` too" rule below governs a hand-edit and not the tool path.
2. **Reuse the seven stock scheme ids verbatim** (`light`, `lightgrey1`, `lightgrey2`, `dark`,
   `darksubtle`, `primary`, `secondary`) so every existing `data-dw-colorscheme` maps over unchanged.
3. Write typography with `save_typographies` and the button style with `save_button_styles`.
   **Button shape is a name, never a number**: the model takes one of `Squared`, `Rounded` or `Pill`.
   A brief that specifies a shape as an integer is unresolvable — a zero-based reading and a one-based
   reading name different shapes and produce visibly different buttons — so settle it against the
   brief's own gloss before writing, read the shipped value back with `get_button_styles`, and record
   the name. Write shape names into every downstream artefact (brief, asserts, ledger) so the number
   never travels. The unambiguous fields (`borderSize`, `paddingX`, `paddingY`) matching the shipped
   style exactly is what makes a contested shape easy to miss.
4. Repoint the area with `save_areas`, setting `colorSchemeGroupId`, `colorSchemeId`, `typographyId`
   and `buttonStyleId`. This is a tool call; no SQL is needed and none is owed. (A host whose area rows
   must be repointed outside the product has the column-level recipe in
   [`dw-data-access/references/recipes-swift.md`](../../dw-data-access/references/recipes-swift.md).)
5. Put brand-accent work on `theme-default`'s declared hooks: `--td-accent` / `--td-accent-soft` first
   (they recolour nav hover, mega-menu hover, the underline caret, outline/ghost hover and chips in a
   handful of lines), then `--dw-color-accent` as the brand slot. When a token cannot be expressed by
   the Style-asset `.json` model, declare it in `<customer>_custom.css` **with a written retirement
   condition** rather than in the generated sheet, so the model never lies.
6. Head load order is load-bearing: `default_custom.css` **then** `<customer>_custom.css`.

**Two brand tokens the model cannot reach — both are Tier-1 declarations, so plan for them.**

- **The contrast half of the accent pair.** A custom colour id is letters, digits and underscore only and
  emits `--dw-color-{id}`, so `accent` is writable and a hyphenated `accent-contrast` is not — and the
  underscored spelling emits a `--dw-color-` token no consumer reads. The generator also derives `--dw-color-button-primary-contrast` itself and
  overwrites a brand value there. `theme-default`'s accent convention is a *pair*, so declare
  `--dw-color-accent-contrast` (and `--dw-color-button-primary-contrast` where the brand names one) in
  `<customer>_custom.css`, scoped to the seven scheme selectors and loaded after the generated sheet so
  source order wins, with the retirement condition written into the block.
- **The font fallback stack.** `ParagraphFont` and `HeadingFont` take one family name each and the
  generated sheet emits `--dw-font-family` with that single name and nothing after it, plus one `@import`
  per face per weight from a third-party font host — so a blocked or slow font host drops the whole site
  to the browser default rather than to the specified near-match. Multi-word families are fine: the
  generator percent-encodes the spaces and the resulting URL resolves. Declare the full stacks in
  `<customer>_custom.css` against the **three** selector groups the generated sheet sets the variable on
  — body, the heading group and the button group — loaded after the generated sheet, so source order wins
  and no `!important` is needed.

Also rejected: renaming `Area.AreaName` for portal branding. That breaks the composed serializer
manifests, whose `files[]` paths key off the area name; `MetaSiteName`, the page title and the logo
name carry the naming instead — this is the rule, and [`re-skin.md`](re-skin.md) Step 0.2 names
`MetaSiteName` as the identity edit for exactly this reason. Gate on the **served** site: the head links
all four sheets in order, the served sheets carry the new accent, every `data-dw-colorscheme` in the
served HTML is one of the seven stock ids and resolves to a rule, and the stock files keep their
pre-pass mtimes.

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
