# Product imagery — where the images come from

Rung 3 of the presentability ladder. `asset-organisation.md` (in `dw-demo-swift`) owns where image
files **go** and how generated imagery is reviewed; `commerce-catalog.md` (staged under
`dw-demo-base/references/foundational/`) owns the **attach** verbs. Neither answers the question
that actually blocks a first pass: **where do the images come from at all?**

A non-interactive dispatched session has no operator-fed image inbox. Left with no sanctioned
source, a build seeds a real catalogue and ships it as a wall of grey placeholder tiles — hundreds
of products, zero images, every PLP card and every PDP hero identical. That is the single largest
visual gap between a first pass and a finished demo, and it is a *sourcing* problem, not an
attaching problem.

## Contents

- [Source priority](#source-priority)
- [The primary autonomous source: the customer's catalogue PDF](#the-primary-autonomous-source-the-customers-catalogue-pdf)
- [Step 1 — Pin the toolchain](#step-1--pin-the-toolchain)
- [Step 2 — Extract the page-ordered SKU list](#step-2--extract-the-page-ordered-sku-list)
- [Step 3 — Extract the tiles](#step-3--extract-the-tiles)
- [Step 4 — Pair by page order](#step-4--pair-by-page-order)
- [Step 5 — The eyeball reject pass (mandatory)](#step-5--the-eyeball-reject-pass-mandatory)
- [Step 6 — Attach](#step-6--attach)
- [Step 7 — A branded fallback for everything unpaired](#step-7--a-branded-fallback-for-everything-unpaired)
- [Coverage targets and the assert](#coverage-targets-and-the-assert)

## Source priority

Work down this list. Stop at the first source that covers the hero categories the storyline
visits — full-catalogue coverage is not the goal, **the pages the demo lands on** are.

| # | Source | When it applies | Notes |
|---|---|---|---|
| 1 | **Customer-supplied asset pack** (image zip, DAM export, media FTP) | the customer handed one over | always first; already label-correct and rights-clear |
| 2 | **Customer catalogue PDF** | a print or digital catalogue is on disk in `customer-context\` | the recipe below. Most prospects have one, and its product tiles are exactly the label-forward shots a PLP needs |
| 3 | **Customer website product pages** | a public storefront exists | only with the customer's material; respect the read-only `customer-context\` contract and do not crawl at volume |
| 4 | **Generated imagery** | no customer source exists for a *hero* SKU | last resort, and it carries its own review rules — see `asset-organisation.md` "Generated product imagery" (review hero-vs-new **pairs**, never a solo contact sheet) |
| 5 | **Branded fallback tile** | everything unpaired | Step 7. Not a failure state — a *designed* one |

**Never present generated imagery as the customer's own product.** Generation is for filling a
grid behind the storyline, not for a hero SKU the prospect will look at closely and recognise as
wrong. And never source from a stock-photo service for a real prospect's real SKUs: a plausible
photo of the wrong object is worse than an honest placeholder.

## The primary autonomous source: the customer's catalogue PDF

A print catalogue is a near-ideal source because it is **already page-ordered against the SKU
list**. Products appear as tiles, in the same sequence as their part numbers, on the same page.
That co-location is what makes pairing tractable without any image recognition.

Read the PDF out of `customer-context\`. That directory is **read-only** — extract to the demo's
scratch area (`notes\` per the artifact-hygiene rule), never in place.

## Step 1 — Pin the toolchain

Two poppler binaries do the work: `pdfimages` (raster extraction) and `pdftotext` (the layout
dump). **Pin poppler at v23.** Newer builds (v26 observed) crash with `0xC0000005` on Windows
Server 2019 — an access violation on start, not a bad-PDF error, so it looks like a corrupt input
rather than a bad binary and costs an hour to diagnose.

Stage the pinned binaries under the demo's own tools directory rather than on `PATH`, so the pin
survives a machine that has a different poppler installed.

Verify the pin before extracting:

```
<tools>\pdfimages.exe -v      # must report 23.x
<tools>\pdftotext.exe  -v      # must report 23.x
```

If the version does not match the pin, stop. Do not "try it anyway" — the failure mode is a hard
crash mid-batch that leaves a partially populated output directory that looks like a successful
short run.

## Step 2 — Extract the page-ordered SKU list

```
pdftotext -layout catalogue.pdf catalogue.txt
```

`-layout` is load-bearing: without it the text stream loses column structure and the SKU order
stops matching the visual order on the page, which destroys the pairing in Step 4.

Parse `catalogue.txt` into `(page, order-on-page, sku, label)` records using the customer's own
part-number shape. Derive that shape from the seeded catalogue rather than guessing — the SKUs are
already in the PIM, so the pattern is knowable, and a regex fitted to the PDF alone will happily
match page numbers and prices.

## Step 3 — Extract the tiles

```
pdfimages -png -f <first-page> -l <last-page> catalogue.pdf <out>\tile
```

Extract **per page range**, not the whole document in one call: it keeps page provenance in the
output filenames, and it bounds the blast radius if one page's images are malformed.

Then drop the obvious non-products before any pairing:

- **Below a minimum pixel floor** — logos, icons, rule lines, bullet glyphs.
- **Extreme aspect ratios** — banners, page furniture, colour bars.
- **Duplicates by content hash** — the header logo repeats on every page and will otherwise pair
  itself to a different SKU each time.
- **Masks and separated channels** — `pdfimages` emits soft masks alongside their base images on
  some PDFs; a mask extracted as its own file is a black or white rectangle.

## Step 4 — Pair by page order

For each page: the *n*-th surviving tile pairs to the *n*-th SKU on that page. That is the whole
algorithm, and it works because print layout keeps a product's image adjacent to its part number.

Rules that keep it honest:

- **Pair within a page, never across one.** A page whose tile count and SKU count disagree is
  **unpaired in full**, not best-effort shifted. One misalignment early cascades through every
  remaining product on the page and produces confidently wrong pairs, which are far more damaging
  in front of a prospect than blanks.
- **Prefer label-forward tiles.** Where a page yields more tiles than SKUs, keep the ones showing
  the product with its label or packaging facing the camera — that is what a PLP card needs to
  read at thumbnail size. Lifestyle and in-use shots are the ones to drop.
- **Record the provenance** (`sku -> page, tile index, source file`) as a working artifact. It is
  what makes the Step 5 rejects fixable rather than re-runnable-from-scratch.

## Step 5 — The eyeball reject pass (mandatory)

Pairing is mechanical; acceptance is not. Build a contact sheet of `label + image` pairs and
review it. Reject:

- blurry or low-resolution tiles that will not survive the PLP thumbnail size,
- tiles cropped through the product,
- **wrong pairs** — anything where the image is plainly not the labelled product,
- tiles that are page furniture the Step 3 filters missed.

A rejected pair becomes unpaired and falls through to Step 7. **Do not substitute a
near-neighbour** to keep the coverage number up; an honest branded placeholder beats a confidently
wrong photo.

This pass is not optional and it is not deferrable to the human sign-off at rung 8. A wrong image
on a real product is the one presentability defect a prospect will notice *and remember*.

## Step 6 — Attach

The attach mechanics are already owned — see `commerce-catalog.md` ("The product-asset verb set")
under `dw-demo-base/references/foundational/`. The two facts that most often cost a batch:

- **`AssetAddToMultipleProducts.IsDefault` is inert.** Attaching is one call; making an attached
  asset the primary is a **second** call (`ProductAssetSetAsDefault`). Skipping it leaves every
  product in the images-but-no-default state.
- **Images-but-no-default is frontend-breaking, not cosmetic.** The Swift card template throws on
  a product with images and no default, and because the PLP renders cards in a loop, one such
  product takes down the **whole product-list page** — so a half-finished imagery batch is more
  visibly broken than no batch at all. Set exactly one default per product/variant/language, then
  flush the cache.

Land the files under the per-SKU convention in `asset-organisation.md`
(`Files/Images/products/<sku>/`), so a later re-run can tell sourced assets from seeded ones.

## Step 7 — A branded fallback for everything unpaired

Whatever is left after Step 5 gets a **designed** empty state, not the platform's grey default.

The stock `nopic.png` shipped with the design package is frequently ACL-locked on a hosted install
— it cannot be overwritten in place, and a build that plans to swap the file silently ships the
grey tile anyway. So do the fallback in **CSS**, in the customer stylesheet, keyed on the image
whose `src` is the stock placeholder:

- target the card's image wrapper where the `src` matches the stock placeholder filename,
- paint the customer's brand surface (a tinted background plus a low-contrast mark or the
  product's initials), sized to the same aspect box the real thumbnails use,
- keep it quiet — the goal is a grid that reads as *deliberately minimal*, not as broken.

Because it is CSS in the customer sheet, it also survives a re-seed of the catalogue, and it is
covered by the CSS marker asserts that protect the rest of the sheet.

## Coverage targets and the assert

Coverage is measured **per demo-critical page**, not across the whole catalogue.

| Target | Value |
|---|---|
| Hero-category PLP: real label-forward images | >= 80% of visible cards |
| Every remaining card | the branded fallback, never the stock grey tile |
| Every PDP the storyline visits | a real image, and it is the default |
| Every `<img>` on a demo-critical page | resolves 200 |

Wire two asserts into the design leg so this is proven on every gate run, not once:

1. **Image resolution** — every `<img>` rendered in `main` returns 200. This is the assert that
   catches referenced-but-missing imagery, which no geometry or text check can see.
2. **PLP thumbnail presence** — on the subject rows of the hero-category PLP, the per-row
   `thumbnail` required field is present, and the fraction of rows whose image `src` is the stock
   placeholder is below the coverage threshold.

Observe both fail before trusting them green: run them against the catalogue *before* the imagery
pass, where they must FAIL.
