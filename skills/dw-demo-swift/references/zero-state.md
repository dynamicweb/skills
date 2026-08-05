# zero-state.md — the post-baseline zero-state pass

> **Step 0 of every Swift re-skin.** A freshly deserialized baseline is a complete, plausible site
> whose every plausible surface belongs to the *shipped* demo. This file is the ordered pass that
> retires that content before any brand work starts, plus the asserts that keep it retired. Run it
> immediately after [`deserialize-flow.md`](deserialize-flow.md) and before the ladder in
> [`re-skin.md`](re-skin.md).

## Contents

- [Why a structural gate cannot see this](#why-a-structural-gate-cannot-see-this)
- [Step 1 — Inventory the stock surfaces (tripwire grep)](#step-1--inventory-the-stock-surfaces-tripwire-grep)
- [Step 2 — Retire the identity strings](#step-2--retire-the-identity-strings)
- [Step 3 — Resolve every `defaultValue` field](#step-3--resolve-every-defaultvalue-field)
- [Step 4 — Rewire or delete every empty band](#step-4--rewire-or-delete-every-empty-band)
- [Step 5 — Prove the catalogue has pixels](#step-5--prove-the-catalogue-has-pixels)
- [Step 6 — Arm the asserts on gate run one](#step-6--arm-the-asserts-on-gate-run-one)

## Why a structural gate cannot see this

Every stock surface renders: the bands are present, the templates resolve, the pages answer `200`,
and a link check is clean. What is wrong is *whose* site it reads as — a stock frontpage title, a
hero written for the shipped vertical, a features band whose three cards carry the same shipped
placeholder sentence, an editorial band with four skeleton cards behind it, an empty FAQ shell, and
the platform wordmark in the header and the footer. A build that ships that has passed every
mechanical leg it was given and is still not showable.

The fix is mechanical too, and it is cheap: the stock copy is a **fixed, greppable string set**, an
unwritten item field renders its declared `defaultValue`, and an empty band is detectable from the
served markup. Steps 1–5 below turn each into a check; Step 6 puts those checks in the gate from the
first run rather than at polish time.

## Step 1 — Inventory the stock surfaces (tripwire grep)

Fetch the served HTML of the storyline page set and grep it for the shipped baseline's own copy.
These are the strings the shipped Swift content ships with — a hit means that surface has never been
authored for this prospect:

| Tripwire | Surface it exposes |
|---|---|
| `Swift Frontpage` | the frontpage `<title>` / meta title, never re-titled |
| `Latest travel guides` | the editorial/blog band, still pointed at the shipped article set |
| `One Pedal at a Time` | shipped article titles behind that band |
| `Whether it's in our homes` | the USP / features band rendering an unwritten field's `defaultValue` |
| `High Quality Products and Parts` | the shipped hero headline |
| `Swift` inside `header`/`footer` brand slots | the platform wordmark still standing in for the customer mark |

```powershell
$pages   = @('/', '/shop', '/customer-center')      # plus every storyline page and language prefix
$tripwire = 'Swift Frontpage|Latest travel guides|One Pedal at a Time|Whether it''s in our homes|High Quality Products and Parts'
$hits = foreach ($p in $pages) {
  $html = (Invoke-WebRequest -Uri "$baseUrl$p" -SkipCertificateCheck).Content
  [regex]::Matches($html, $tripwire) | ForEach-Object { [pscustomobject]@{ page = $p; hit = $_.Value } }
}
$hits    # definition of done: empty
```

Extend the list with any string the composed edition adds — the check is the *shape* (a fixed set of
shipped strings, grepped against the **served** markup), not this particular six rows. Grep the
served HTML rather than the database: a string can reach the page from an item field, a template
default, or a shipped article the band still points at, and only the render sees all three.

## Step 2 — Retire the identity strings

Three first-class steps that are routinely treated as cosmetic and left for later, each of which is
visible in the first five seconds of a demo:

1. **Frontpage title and meta title** — `save_pages` on the frontpage with the customer's own
   `metaTitle`; assert the served `<title>` no longer matches the tripwire list.
2. **Area name** — the area's own name surfaces in admin, in the page tree, and in generated meta;
   set it to the customer slug rather than the shipped name.
3. **Header and footer brand** — the logo asset *and* the wordmark text. The footer brand is a
   separate paragraph from the header one and is the one that survives a logo swap. Assert both by
   reading the served `header` and `footer` fragments, not by looking at the logo field.

## Step 3 — Resolve every `defaultValue` field

**An item-type field that was never written renders its declared `defaultValue`, and shipped
`defaultValue`s are written as plausible marketing copy — so an unauthored field is indistinguishable
from an authored one on screen.** This is what produces a features band whose three cards carry the
same sentence: one field, three paragraphs, none of them written.

Resolve it per item type rather than per page:

- Read the item type's field definitions (`get_item_type` / the Management API item-type surface) and
  list every field carrying a non-empty `defaultValue`.
- For each paragraph of that type on the storyline pages, read the stored value. An **empty stored
  value with a non-empty rendered string** is an unwritten field.
- Write the customer's own value, or clear the `defaultValue` on the field definition if the field is
  genuinely optional for this build.

The shipped types that most often carry copy-shaped defaults are the feature/USP card, the slider
item, and the accordion/FAQ item — check those first, then sweep the rest.

Assert: for every paragraph on the storyline pages, no two siblings of the same item type render
byte-identical body copy. Identical siblings are the signature of an unwritten field.

## Step 4 — Rewire or delete every empty band

**A band whose data source is empty gets rewired or deleted — never left standing as a skeleton.**
Once the shipped fixture content is removed, the bands that pointed at it keep rendering: an
editorial band draws four empty cards, an FAQ band draws its heading over nothing, a product band
draws a heading with zero rows. Each reads as a broken site rather than an unfinished one.

Detect from the served markup, per band:

```js
// run against each storyline page; a band with a heading and no content children is a skeleton
[...document.querySelectorAll('section[data-swift-gridrow]')]
  .map(s => ({
    heading: s.querySelector('h1,h2,h3')?.innerText?.trim() ?? '',
    cards:   s.querySelectorAll('article, .card, [data-dw-itemtype]').length,
    text:    s.innerText.replace(/\s+/g, ' ').trim().length
  }))
  .filter(b => b.text < 40 || (b.heading && b.cards === 0));   // definition of done: empty
```

Three dispositions, in preference order: **rewire** the band at the customer's own data (a real
article set, real FAQ entries, a real product query); **delete** the row when the customer has no
equivalent content; **hide** it only when the band is coming back in a later brief, and record the
condition that retires the hide (see [`re-skin.md`](re-skin.md) "A workaround block must name the
condition that retires it"). Leaving a heading over an empty grid is none of the three.

## Step 5 — Prove the catalogue has pixels

`document.images.length` on the frontpage and the shop landing is a one-line check that catches the
whole class: a seeded catalogue with no attached assets renders as a wall of grey placeholder tiles,
and every structural PLP assert passes over it. Assert a floor per surface (`> 0` on the frontpage,
a per-category coverage target on the PLP) as part of this pass rather than at polish.

Sourcing the imagery is its own brief with its own cost — see
[`asset-organisation.md`](asset-organisation.md) "Catalogue imagery is its own brief". What belongs
*here* is only the measurement, so the gap is visible on run one instead of at the rehearsal.

## Step 6 — Arm the asserts on gate run one

**Design verification is a property of every gate run, not of the design brief.** A gate whose design
leg is unconfigured stamps `SKIP` and reports `PASS` over a site with horizontal overflow, skeleton
bands and shipped copy — which is exactly the failure mode a mechanical gate exists to end. Three
legs arm from the first run against a raw deserialize, with no custom design configuration:

1. **Overflow** — `document.body.scrollWidth === window.innerWidth` at desktop and mobile widths.
2. **Skeleton / empty-band scan** — the Step 4 detector, over the storyline page set.
3. **Stock-copy tripwire** — the Step 1 regex, over the served HTML.

Cover **every language prefix the build serves**, not just the default one. Chrome copy is longer in
some languages than the one it was laid out in, so a translated header can carry a constant
horizontal overflow on every page of that language while the default-language pages measure clean —
and a page list that names only default-language URLs cannot see it however correct the assert is.
The overflow value being *constant per language and independent of page content* is the tell that it
lives in chrome rather than in the content of any one page.

Expected first result on a raw baseline is **FAIL**, on all three. That is the point: the legs are
armed so the layer defects and the unauthored content surface on run one, and the pass is earned by
fixing them rather than by leaving the leg unconfigured. The shared acceptance-criteria wording is in
[`../../dw-demo-base/references/orchestrator.md`](../../dw-demo-base/references/orchestrator.md)
"Acceptance criteria".
