# asset-organisation.md

> `wwwroot/Files/` asset organisation for a Swift 2.2 / Dynamicweb 10 demo. Reference layouts at `<demo-root>\distribution\layers\base\` and Swift v2.3.0 at https://github.com/dynamicweb/Swift.
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Contents

- [Subfolder conventions for demos](#subfolder-conventions-for-demos)
- [Branding assets — a shared SVG is not safe to edit in place](#branding-assets--a-shared-svg-is-not-safe-to-edit-in-place)
- [Generated product imagery — review against the hero, and record the prompt](#generated-product-imagery--review-against-the-hero-and-record-the-prompt)
- [Catalogue imagery is its own brief](#catalogue-imagery-is-its-own-brief)
- [Video in a PDP media gallery — stock Swift preloads it three times](#video-in-a-pdp-media-gallery--stock-swift-preloads-it-three-times)
- [Auditing which assets are actually referenced](#auditing-which-assets-are-actually-referenced)
- [What lives OUTSIDE `wwwroot/Files/` (demo working folders)](#what-lives-outside-wwwrootfiles-demo-working-folders)

The vendor-generic `wwwroot/Files/` layout (the top-level folder table + edit policies, admin-UI
upload vs filesystem drop, and the "admin File management surfaces only `wwwroot/Files/`" rule) is
owned by the `dw-swift-building` foundational skill — staged in
[`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §8 ("Asset
organisation under `wwwroot/Files/`"). This file carries the demo-specific subfolder conventions on top
of it.

## Subfolder conventions for demos

When seeding demo content, prefer these subfolder conventions to keep things tidy:

- `Files/Images/products/<sku>/` — per-SKU product images (one folder per hero SKU keeps the demo
  storytelling clean per `dw-demo-pim/references/demo-storytelling.md`)
- `Files/Images/branding/` — logo, favicon, hero imagery for re-skin
- `Files/Documents/credit-notes/` — placeholder PDFs for off-invoice rebate visualisations
  (project-specific; see the demo's `.planning/REQUIREMENTS.md` for the relevant requirement ID)

## Branding assets — a shared SVG is not safe to edit in place

Logo and icon SVGs under `Files/Images/branding/` are typically referenced by **more than one** page: the desktop and mobile header pages routinely inline the *same* file at two different pinned widths (e.g. 210px and 170px). An SVG `viewBox` trim changes the asset's intrinsic **aspect**, so every consumer that pins only a width silently gets a new height — trimming in place roughly doubles the mobile logo's height, grows the mobile header, and breaks a "mobile unchanged" guarantee, with a deploy-ordering window where both pages are wrong.

- **Upload the trimmed asset under a new filename and repoint exactly one reference.** Verify the untouched page still resolves to the original path, that the original asset still returns 200, and that its rendered height is unchanged.
- **Image/icon fields are `SelectedImage`** — the binder needs the object shape `{Id, Name, Ratio, FocalX, FocalY}`. A bare path string saves **empty**.
- **Measure before mandating that SVG text be outlined.** The usual argument — "if the webfont fails, the fallback reflows the text and a tight `viewBox` clips it" — is an assumption about relative font metrics, and it is cheap to test: render the asset twice, once normally and once with the font host aborted, and compare ink bboxes. A fallback is often *narrower*, and the vertical envelope is frequently set by a non-text element and is font-independent entirely. Size the `viewBox` to the wider of the two states and keep vector text. Outlining is also often not achievable faithfully: a site serving a single **variable** woff2 cannot be parsed by `opentype.js` (Brotli) nor reliably instanced on its axes, so the outline would ship subtly wrong glyph shapes — a worse defect than the one being mitigated. Reserve it for a measured overflow with a faithful static font instance available.
- Definition of done either way: with the font host aborted, the ink bbox stays inside the `viewBox` on all four sides and the rendered box geometry is identical across both font states.

## Generated product imagery — review against the hero, and record the prompt

Two rules that only bite once a demo starts *generating* product images rather than sourcing them.

**Check a generated ADDITIONAL view against the product's EXISTING hero, not just against the prompt.**
A generation prompt describes the subject in the abstract; it carries no knowledge of the colourway
already live on the product's primary image, so the model picks a plausible one — and
plausible-but-different is exactly the failure the "do these read as several views of ONE thing?" test
exists to catch. A solo contact sheet cannot see it: reviewing generated images on their own passed 45 of
46, and placing each beside its product's existing hero failed **four more** — the same product in a
different colour, reading as two products in one gallery strip (black handheld unit vs yellow/black; navy
jug vs silver; black panel with amber controls vs brushed stainless with red; navy case vs black).

- Put the primary's **colour, material and form** into the prompt whenever the product already has one.
- Review as **hero-vs-new PAIRS**, never as a sheet of new images. Build the pair sheet as the artefact;
  every accepted image must be recognisably the same object as its hero.
- Keep a subject-level check alongside it — the same batch had one rejection on subject alone (a part
  rendered with the wrong defining geometry, decorative rather than functional), which the pair test does
  not catch.

**For a generated asset the PROMPT is the identifier — make it a required manifest field.** An images
manifest schema written for stock-photo sourcing (where a photo id and URL fully identify the asset) has
no field for it, so generated entries land carrying only `generator: "<model> (quality high)"` and nothing
else. Those assets cannot be reproduced, refined or restyled at all — the only option is to start over.
Record **`prompt` (verbatim), `model` and `quality` as REQUIRED** alongside `generator` for any generated
asset, and record the prompt **actually sent**, so a regenerated image carries the prompt that produced
the shipped file rather than the first attempt. Definition of done: a second run can re-issue the recorded
prompt and get a comparable image.

## Catalogue imagery is its own brief

A seeded catalogue with no attached assets renders every PLP and PDP as grey placeholder tiles, and
the imagery recipes elsewhere assume either an operator-fed image inbox or a generator — neither of
which a dispatched, non-interactive session has. Most prospects **do** hand over a print catalogue
PDF, and its product tiles are exactly the label-forward shots a PLP needs. That is a sanctioned
autonomous source, with one standing caveat: **scope it as its own brief.** Extraction is minutes;
the per-pair review below is the actual cost, it is judgement per asset, and it does not compress or
parallelise. An imagery item budgeted alongside header, pricing and redirect work finishes as either
"not delivered" or, worse, as unreviewed pairings on live PDPs.

### 1. Extract geometry and images in one pass — `pdftohtml -xml`

```bash
pdftohtml -xml -zoom 1 catalogue.pdf out.xml     # emits out.xml + every embedded image
```

`pdfimages` gives pixels and page numbers but **no placement**, so it can only support an
order-based join — and image order matches text order on only some pages of a typical InDesign
layout, so an order-based join mispairs silently. `pdftohtml -xml` emits every `<image top left
width height src>` and every `<text top left width height>` on **one coordinate system**, which
turns a tile grid into a pure geometric join. It also converts CMYK→RGB correctly, so no separate
colour step is needed. Keep `pdfimages -list` for reconnaissance only (page/colour-space census).

- **Pin poppler to v23.** v26 crashes `0xC0000005` on Windows Server 2019.
- **Poppler emits `height` before `width` on `<page>`.** A width-first regex matches nothing and the
  page count comes back `0` — which reads as "the PDF has no pages" rather than "the pattern is
  wrong". Assert the parsed page count equals the PDF's own.

### 2. Bucket text and images into grid cells

Derive column x-bands and row y-bands from the tile grid (a 4-across layout gives four x-bands and
as many y-bands as tile rows), then assign every `<text>` and `<image>` node to a `(column, row)`
cell. The SKU in a cell pairs with the images in that same cell — derived, not guessed.

Assert **zero ambiguous cell assignments** (no node straddling two bands) before joining anything.
Then join cell SKUs to live products by product number and report the funnel explicitly: tiles found
→ tiles carrying a SKU → tiles carrying an image → tiles with both → live products matched.

### 3. Recover the images the converter mangles

A **DeviceN / separation** colour space is the one `pdftohtml` gets wrong: it renders as a grey shape
on solid black, and it would ship as a black rectangle on the PLP. Census the colour spaces with
`pdfimages -list` first — cmyk, gray and index convert correctly, `devn` does not.

Recover by re-rendering the page and cropping instead of re-extracting the object:

```bash
pdftoppm -png -r 400 -f <page> -l <page> catalogue.pdf page      # 400 dpi page raster
# crop the tile bbox from the XML, scaled by dpi/72
```

Worth knowing generally: **the page raster is a valid source when the embedded object is unusable**,
and it is frequently *larger* than the embedded original and on clean white. Note that the XML can
carry a **negative `height`** on a placed image — that is a y-flip, so the real box is
`top+height .. top`.

### 4. Eyeball every pair — a required stage with its own artefact

**A SKU join cannot detect a wrong photo.** A pairing can be structurally perfect — right page, right
tile, right SKU — and still be the wrong product, because the source catalogue carries image defects
alongside its copy defects. Four classes, all invisible to extraction, join and every `status: ok`:

| Class | What it looks like |
|---|---|
| Brand mismatch | a different manufacturer's packaging on the tile for this product |
| Model mismatch | the right brand, the neighbouring model's carton |
| Section mismatch | a photo from an adjacent product family entirely |
| Duplicate-SKU collision | two tiles carry one SKU, so an unrelated tile is dragged onto the product |

Plus **burned-in third-party watermarks**, which are invisible at native size.

- Record **one decision row per product-image pair** — subject, verdict, reason — as the stage's own
  artefact, not as a review of the output. The worksheet is the deliverable; the attachments follow it.
- **Zoom 4× before accepting or rejecting anything whose label you cannot read at native size.** That
  is what surfaces watermarks and settles ambiguous pack markings.
- Report **NOT DELIVERED and ship the branded fallback** rather than attaching unreviewed pairings to
  hit a coverage target. Attaching everything unreviewed is the defect the coverage target exists to
  prevent, not a way of meeting it.

### 5. Cap coverage honestly on colour-variant families

**Coverage dies on flat-colour variant families, and the shortfall is per category, never a total.**
A print catalogue prints ONE photo for a tile that lists every colourway. Two opposite rules, and
which applies is decided by whether the distinguishing attribute is *legible at rendered size*:

- **The photo makes a visible colour claim** (tags, wraps, crayons, sprays) → it goes to the SKU of
  that colour only. The same photo across seven SKUs is six wrong-product pairings.
- **The distinguishing attribute is not legible at any rendered size** (pack count, volume, width, a
  marking inside a sealed pack) → one family shot honestly serves every variant.

Measure coverage **per category from the live product records and per PLP from the served HTML**, so
the cost of the rule is visible per screen instead of hidden in a catalogue-wide percentage.
Categories dominated by colour variants land far below the target while
single-photo-per-family categories reach 100%, and reporting only the total hides both.

### 6. Size the asset for the FRAME, not for the file

**`GetImage.ashx` returns 0.75× the source pixels on the `webp` path and full size on `png`** — a
silent 25% resolution loss. Swift requests `format=webp` in its `srcset`, `GetImage.ashx` will not
upscale, and the `img` carries `mw-100 mh-100` so it caps but never scales up: whatever the handler
returns is what the visitor sees. A small source asset therefore renders as a postage stamp floating
in a large PDP frame while the file itself is correct.

Ship a **2× resample of the frame size** (long edge capped, alpha flattened, comfortably under
300 KB) so the webp path still delivers enough pixels. Verify the same URL with `format=png` to read
the true source dimensions, and assert `naturalWidth`/`naturalHeight` **and** the rendered bounding
box off the live PDP — the DPI metadata is not the lever and reading it proves nothing.

### 7. Attach, then verify per product

Upload and attach through the asset verbs, then read the attachment back **per product** rather than
trusting the attach response — including which asset is primary (`AssetAddToMultipleProducts`'s
`IsDefault` behaviour is verb-specific; see
[`../../dw-demo-base/references/foundational/commerce-catalog.md`](../../dw-demo-base/references/foundational/commerce-catalog.md)).
Unpaired products fall through to a **branded placeholder**: a CSS fallback keyed on the placeholder
image's own `src` (`.ratio:has(img[src*=nopic])`) paints a brand-tinted tile with the customer mark,
capped and centred — the shipped placeholder file itself is usually ACL-locked, so the fallback is
CSS rather than a file swap.

Definition of done: the hero-category PLP renders the agreed share of real label-forward images
counted **from the served markup**, every remaining card shows the branded fallback rather than the
stock grey tile, every shipped pairing has a verdict row, and every reject has a stated cause.

## Video in a PDP media gallery — stock Swift preloads it three times

**Attaching one 5MB video to a product media gallery took a PDP to 15,318 KB on load.** The `Swift-v2`
media templates emit **every** gallery asset three times — the gallery itself, the modal and the thumb —
each with a hard-coded `preload="auto"`, so a single video is fetched in full three times before the
visitor interacts with anything. Nothing about the paragraph or the asset record signals it; the page just
renders, slowly, and the Lighthouse damage is total.

- **Do not put video in a stock gallery for a demo that will be measured.** Ship a click-to-load lane
  instead: a poster image in the gallery slot and a deferred fetch on click. Measured with such a lane
  installed: **133 KB** on load with **0** media bytes preloaded, then a 5.2MB fetch on click with playback
  verified (`currentTime` advancing).
- Definition of done: a PDP carrying a gallery video loads under 200KB of media-free payload before any
  interaction, and the video still plays on click.
- The lane is a net-new `Custom/` script, not an edit to a stock template — the never-touch rule stands.

## Auditing which assets are actually referenced

Two rules that decide whether an "unused asset" claim is worth acting on. Getting either wrong deletes
live files or preserves gigabytes of nothing.

**Never use `Select-String` to prove an asset is unreferenced over a DB dump — it silently returns 0 on
megabyte-long lines.** A single serialized DB row is routinely multi-MB on one line, and `Select-String`
**drops** those lines with no error and no warning: one audit reported an image with **656** real
occurrences as completely absent. Every deletion decision downstream of that reads as evidence and is
noise. Stream the corpus and match with `String.IndexOf` instead — same corpus, same pattern:
`Select-String` 0, `IndexOf` 656.

**Filenames lie in BOTH directions — only pixels count.** A descriptive filename is authored independently of
the content and drifts from it, and generated or stock-library assets are the worst offenders. On one audit,
three plausibly-named subject photos turned out to be a camera on a white sweep, a flat-lay of maps and
guidebooks, and an underwater shot — while the genuinely off-subject image actually live on the site was named
`Content/Details/details-8.jpg`. A filename-based audit therefore **both** misses real contamination **and**
would introduce more by sourcing "matching" replacements from the same pile. Any image audit or asset-reuse
step must **eyeball or vision-check the file itself**, in both directions, and a folder of plausibly named
assets is not a trusted source. Record a visual check per swapped image rather than a filename match.

**Resolve the file indexes' `StartFolder`s FIRST — the unindexed sibling is the deletion candidate.**
A stock install can ship an 8+ GB pile of asset-shaped folders with near-identical names (a `Digital
assets` tree beside a `Digital assets - DEMO` tree) and nothing in the folder names says which is
load-bearing. The index configs do: `Files.index` and `Assets.index` build from `StartFolder` `Digital
assets`, so the `- DEMO` sibling has no index behind it — and with 0 template hits and only `CommandLog`
audit rows referencing it, it is safe to drop. On one build that removed **1,226 files / 3,029 MB** with
per-file evidence and a clean 8-page zero-broken-asset regression afterwards. Order of work: read the
index `StartFolder`s → grep the corpus with the streaming matcher above → keep per-file evidence → delete
→ re-run a broken-asset sweep across the demo's page set.

## What lives OUTSIDE `wwwroot/Files/` (demo working folders)

A few demo-relevant directories that are NOT under `wwwroot/Files/` (and therefore shell-only — admin
UI File management never surfaces them):

- `<demo>\customer-context\` — read-only customer-supplied artefacts. NEVER write here. See
  [dw-demo-base/references/customer-context.md](../../dw-demo-base/references/customer-context.md).
- `<demo>\notes\` — your own working notes during the build. Free to write here.
- `<demo>\extracts\` — transformed / derived data extracted FROM customer-context (write-allowed).
- `<demo>\CUSTOMISATIONS.md` — the customisation budget ledger. See
  [dw-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md).
- `<demo>\docs\` — late-phase deliverables (e.g. a demo-day runbook, architectural slides; specific
  filenames and requirement IDs are project-specific).
