# Zero-state pass — from stock Swift to customer-neutral

Rung 1 of the presentability ladder. This is the ordered pass that runs **immediately after the
baseline deserialize and area binding**, before any copy is written and before any styling. It is
a numbered build step, not a troubleshooting lookup: every demo needs it, in this order, and it
must be re-run after any bulk paragraph save.

Its output is a site that is *empty of Swift* rather than *full of someone else's demo*. Writing
the customer's story onto a page that still carries stock furniture means authoring around things
that are about to be deleted.

## Contents

- [The mechanism — why this is a step and not a note](#the-mechanism--why-this-is-a-step-and-not-a-note)
- [Step 1 — Arm the tripwire first](#step-1--arm-the-tripwire-first)
- [Step 2 — Kill the source: item-type `defaultValue`](#step-2--kill-the-source-item-type-defaultvalue)
- [Step 3 — De-brand the chrome](#step-3--de-brand-the-chrome)
- [Step 4 — Resolve every empty band](#step-4--resolve-every-empty-band)
- [Step 5 — Page and area identity](#step-5--page-and-area-identity)
- [Step 6 — Alt text and the empty-state string](#step-6--alt-text-and-the-empty-state-string)
- [The re-run rule](#the-re-run-rule)
- [Assert reference](#assert-reference)

## The mechanism — why this is a step and not a note

Swift ships demo copy inside the **`defaultValue` attribute of its content item types**. A field
the author never wrote does not render empty and does not error — it renders that default, as
plausible sentences, in the site's own typography.

Three consequences, and each one is why a rung exists below:

1. **A page can look authored while carrying nothing written for this customer.** Three feature
   cards under three different real headings can all carry the identical stock body, because only
   the headings were written.
2. **Blanking a field by hand is not durable.** A later save of the containing grid row re-applies
   the item-type defaults to fields the save does not carry. Copy that was fixed once comes back.
   This is the single most-repeated regression of the whole phase.
3. **A liveness gate cannot see any of it.** The page renders, returns 200, has text, has a CTA.
   Only a content assert catches it, so the assert is the deliverable — not the checklist.

The durable fix is upstream (blank the defaults in the shipped layer's item-type XML). The
demo-side fix is this pass plus its assert.

## Step 1 — Arm the tripwire first

Arm the regex **before** changing anything, and observe it FAIL on the raw deserialize. An assert
never seen to fail is not evidence.

Scan **`document.body.textContent`** with `script/style/template/noscript` stripped, **not**
`innerText`. `innerText` is render-aware and omits collapsed accordion panels and inactive tabs —
which is exactly where stock copy hides. On one measured page `innerText` returned 2,270 chars
with 0 matches while `textContent` returned 9,544 with 7.

The pattern has three bands. Keep them separate so a false positive can be retired without
weakening the rest.

**Band A — the stock content copy** (the nine item types' defaults, plus the stock page copy).
These strings are enumerable straight out of the layer's `itemtypes/*.xml` `defaultValue`
attributes and the shipped page YAML; generate the pattern from that file set rather than
hand-listing it, so it stays true when the layer version rolls.

```
Celebrate the beauty of our planet|Nurturing nature|Imagine a world where nature thrives|
Embrace the green|Join the movement for a greener tomorrow|Our planet is full of wonder|
Embrace a greener tomorrow|The choices we make today shape the world|Celebrating nature|
Together for a brighter future|Preserve today, enjoy tomorrow|Respect the Earth|
Small changes, big impact|Whether it.s in our homes|Nature.s beauty is in the little things|
Sophie Greene|How can I start living a more eco-friendly lifestyle|
Begin by making small changes in your daily routine|Discover Nature|Explore the Outdoors|
Experience the beauty of nature with our guided tours|Latest travel guides|
Explore the World One Pedal at a Time|Share the fun|Swift Frontpage
```

Note `Whether it.s` and `Nature.s` — the shipped strings use a typographic apostrophe (U+2019),
not `'`. A pattern typed with a straight quote matches nothing.

**Band B — the stock corporate-ipsum signature** (product descriptions, FAQ bodies). Filler is
only *sometimes* the word "lorem"; the reliable signature is the sentence-opener verb set:

```
Phosfluorescently|Holisticly|Authoritatively|Dramatically|Objectively|Synergistically|
Monotonectally|Enthusiastically|Compellingly|Intrinsicly|Proactively|Continually transform|
vortals|e-enable|team building|evisculate|vis-a-vis|window-licker|brand terrorists|
wireless paradigms
```

**Band C — generic filler**:

```
lorem ipsum|\bLorem\b|\bdolor sit amet\b|\bTODO\b|sample[- ]?text|xxxx+|coming soon|\bplaceholder\b
```

**Calibration rules, learned the expensive way:**

- **An assert that fires on good copy is a broken assert, not a strict one.** Bare `synergy` and
  bare `paradigms` occur in legitimate B2B marketing prose — keep `wireless paradigms`, which is
  the discriminating half, and drop the bare words.
- `\bplaceholder\b` is safe in **this** scan and unsafe in a markup scan: Swift emits HTML
  `placeholder=` attributes on search and quantity inputs, and attribute values never appear in
  `textContent`.
- Band A can legitimately fire on a customer whose own business is environmental. Retire the
  specific colliding alternative and record why, in the config, next to the pattern — never
  weaken the whole band.
- Report the **match offset** with every hit so a regression is diffable.

Run it over the full demo-critical page set, not the front page: at minimum home, a category PLP,
a PDP, the cart, and any storyline landing page.

## Step 2 — Kill the source: item-type `defaultValue`

Blanking rendered paragraphs treats the symptom. Blank the **defaults** on the host so no future
paragraph — and no future grid-row save — can re-inherit them.

Nine content item types ship demo copy. Blank every field listed here (configuration, not custom
code — no `.cs`, no ledger row required beyond normal practice):

| Item type | Fields carrying stock copy |
|---|---|
| `Swift-v2_Text` | `Title`, `Subtitle`, `Text` |
| `Swift-v2_Poster` | `Eyebrow`, `Title`, `Text` |
| `Swift-v2_VideoPoster` | `Eyebrow`, `Title`, `Text` |
| `Swift-v2_TextAndImage` | `Eyebrow`, `Title`, `Subtitle`, `Text` |
| `Swift-v2_Card` | `Title`, `Text` |
| `Swift-v2_Feature` | `Title`, `Text` |
| `Swift-v2_Blockquote` | `Quote`, `Author` |
| `Swift-v2_Accordion_Item` | `Title`, `Text` |
| `Swift-v2_Slider_Item` | `Title`, `Subtitle`, `Text` |

Two more carry brand rather than prose and belong to Step 3: `Swift-v2_Logo.LogoName` and
`Swift-v2_Master.Favicon` / `.AppleTouchIcon`.

Then sweep the **instances**: any paragraph of those types already on a page whose field still
equals its default was never authored. Treat equality-with-default as "unwritten", not as
"deliberately the same".

## Step 3 — De-brand the chrome

The wordmark and the browser tab are the two surfaces a prospect reads before any content.

| Surface | Where | Action |
|---|---|---|
| Header logo | `Swift-v2_Logo` paragraph in the desktop header | set the customer's `Image`; blank `LogoName` (it renders as a text wordmark when `Image` is empty) |
| Footer logo | same item type, desktop footer | same |
| Mobile header logo | same item type, mobile header | same |
| Mobile footer logo | same item type, mobile footer | same |
| Favicon | `Swift-v2_Master.Favicon` | point at the customer's icon; the shipped default is the vendor's own `favicon.png` under the design package |
| Apple touch icon | `Swift-v2_Master.AppleTouchIcon` | same |

There are **four** logo paragraphs, not one. Fixing the desktop header and calling it done leaves
the vendor wordmark in the footer and on every phone.

If the serialization manifest excludes `Favicon`/`AppleTouchIcon` from the content tree, the
browser tab falls back to the item-type default — so the icon must be set on the host even when
the rest of the chrome came from a layer.

## Step 4 — Resolve every empty band

**Rule: a band whose data source is empty is rewired or deleted. It is never left as skeletons.**

Skeleton cards, an empty carousel under a real heading, and an accordion shell under
"Frequently asked questions" all read as *unfinished*, which is worse than absent. Each of these
ships wired to a relation that has no child rows on a fresh host:

| Band | Symptom on a fresh host | Disposition |
|---|---|---|
| Accordion (`Swift-v2_Accordion` + `Accordion_Items` relation) | heading with nothing under it; ships on the home page, the contact page and four footer FAQ pages | author real Q&A **or** delete the paragraph *and its orphaned heading* |
| Slider (`Swift-v2_Slider` + `Items` relation) | empty carousel under a real heading | author slides or delete both |
| Post list (`Swift-v2_PostList`) | skeleton cards under a blog heading, plus a "Read more" button below | the shipped post folders contain zero posts — delete the band, its heading and the button, unless the demo has a content story |
| Product slider with an empty relation (`Swift-v2_ProductComponentSlider`, `RelationType: most-sold`) | **renders the entire source product-list page inline**, facet chrome and all | delete, or set a relation that is non-empty on a fresh host. `most-sold` requires order history, which no fresh demo has |
| Empty image paragraph (`Swift-v2_Image` with `Image: ""`) | a full-width dead row between two real sections | populate or delete |

Two heading/title mismatches ship alongside these and read as sloppiness even once the band is
populated: a section heading that disagrees with the slider title inside it, and a shop PLP whose
`HideGroupDescription` is `true` while the sibling component instance has it `false` — so every
category page renders its merchandising copy nowhere.

**Deleting the band means deleting its heading too.** An orphaned "Frequently asked questions"
over nothing is the same defect with fewer pixels.

## Step 5 — Page and area identity

| Field | Stock value | Action |
|---|---|---|
| Home page `metaTitle` | `Swift Frontpage` | the customer's own title — this is the browser-tab text and the search snippet |
| `AreaTitle` / `AreaDescription` / `AreaKeywords` | empty | populate; an empty area title caps any SEO talking point |
| Area name | the stock area name | rename if the URL segment is derived from it — but see the caveat below |

**Caveat on renaming the area.** Absolute links stored in the content tree (footer privacy and
cookie links are the shipped example) hardcode the authoring-time URL segment. Renaming the area
404s them. Convert those two link fields to page references before renaming, or leave the segment
alone.

## Step 6 — Alt text and the empty-state string

- **Alt text.** The shipped surface sets `AltText` on **zero** paragraphs. Author it on every
  image paragraph on a demo-critical page. This is a two-minute pass that turns an accessibility
  question during the demo from a deflection into a talking point.
- **The empty-state message.** The product list ships with the "no products found" message
  **enabled and blank** — so an empty PLP renders a blank band where an explanation belongs. Set
  a real string even if the catalogue is expected to be full; it is the state the page will be in
  the first time an index goes stale mid-demo.

## The re-run rule

**Re-run Step 1's assert after every bulk paragraph or grid-row save, and as the last action
before any "ready" claim.** The re-inheritance mechanism in "The mechanism" above is not
hypothetical: copy fixed by hand has been observed to return in full after a single grid-row save,
across every page carrying the affected item type.

If the assert is only run once, it has measured a state the demo no longer has.

## Assert reference

One assert per step. All of them are cheap; none of them require the design gate to be finished.
Wire them into the gate's design leg so they run on **every** gate run, from the first — a gate
that arms them at re-skin time measures liveness for the whole first half of the build.

| Step | Assert | Passes when |
|---|---|---|
| 1 | Regex bands A+B+C over `document.body.textContent` (script/style/template/noscript stripped) on every demo-critical page | 0 matches; each match reports page + offset |
| 2 | For each of the nine item types, read the field defaults from the host | every field in the Step 2 table is empty |
| 2 | For each paragraph instance of those types on a visited page, compare the stored field value to the item-type default | no instance equals its default |
| 3 | Rendered header and footer contain no `Swift` wordmark; `link[rel~="icon"]` and `link[rel="apple-touch-icon"]` hrefs do not resolve under the Swift design-package assets folder | 0 hits |
| 4 | For each accordion / slider / post-list / product-slider container rendered in `main`, count its item children | every container has >= 1 child, or the container is absent (deleted) |
| 4 | No `<img>` in `main` with an empty `src`; no `Swift-v2_Image` paragraph rendering a zero-height row | 0 hits |
| 5 | `document.title` does not match the stock frontpage title; area title/description/keywords are non-empty | all true |
| 6 | Every `main img` has a non-empty `alt`; the PLP empty-state string is non-empty | 0 hits / true |

**Observe each assert fail before trusting it green.** Run the whole set against the raw
deserialize first: it must FAIL on Steps 1, 3, 4, 5 and 6. A set that goes green on an
un-customised baseline is measuring nothing.
