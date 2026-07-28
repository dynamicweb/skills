# asset-organisation.md

> `wwwroot/Files/` asset organisation for a Swift 2.2 / Dynamicweb 10 demo. Reference layouts at `<demo-root>\distribution\layers\base\` and Swift v2.3.0 at https://github.com/dynamicweb/Swift.
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## Contents

- [Subfolder conventions for demos](#subfolder-conventions-for-demos)
- [Branding assets — a shared SVG is not safe to edit in place](#branding-assets--a-shared-svg-is-not-safe-to-edit-in-place)
- [Generated product imagery — review against the hero, and record the prompt](#generated-product-imagery--review-against-the-hero-and-record-the-prompt)
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
  [dynamicweb-demo-base/references/customer-context.md](../../dw-demo-base/references/customer-context.md).
- `<demo>\notes\` — your own working notes during the build. Free to write here.
- `<demo>\extracts\` — transformed / derived data extracted FROM customer-context (write-allowed).
- `<demo>\CUSTOMISATIONS.md` — the customisation budget ledger. See
  [dynamicweb-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md).
- `<demo>\docs\` — late-phase deliverables (e.g. a demo-day runbook, architectural slides; specific
  filenames and requirement IDs are project-specific).
