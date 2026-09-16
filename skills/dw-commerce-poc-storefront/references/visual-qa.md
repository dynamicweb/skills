# Visual QA and handover

The POC is judged on what a person sees, so the only QA that counts is done against rendered
pixels and rendered HTML. Run rounds: capture, critique, fix, re-capture.

## Contents

- [Capture](#capture)
- [Critic subagents](#critic-subagents)
- [The brief that makes a critic useful](#the-brief-that-makes-a-critic-useful)
- [Checks worth running yourself](#checks-worth-running-yourself)
- [The fix loop](#the-fix-loop)
- [Copy has to survive a click](#copy-has-to-survive-a-click)
- [Definition of done](#definition-of-done)
- [The handover document](#the-handover-document)

## Capture

Use the harness's own browser tool when it has one — screenshot each page at a desktop and a
phone width and hand the images to the critics. When it has none,
`scripts/capture-pages.mjs` takes a base URL and a list of paths and writes, per page, a
full-page PNG plus review-sized JPEG slices and a manifest.

Either way, capture the same page set every round so rounds are comparable:

- front page, catalogue root, one category listing, one product page,
- any secondary catalogue the build has (a material, textile or size library) and one of its
  detail pages,
- the same front page, listing and product page at a phone width.

Capture the **source site** the same way, once, as the baseline. It is the thing the POC has to
beat, and having it on disk stops the comparison from being a memory.

Two capture rules: always take desktop and mobile, and re-capture after every fix round — a
screenshot goes stale the moment a write lands, and reviewing a stale one wastes a whole round.

## Critic subagents

Run several critics in parallel, each with one dimension and the same screenshots:

- **Shopper journey** — can I find, narrow, compare, understand and buy.
- **Visual craft** — grid, alignment, spacing, type, colour, image treatment.
- **Content and data** — does the copy match the data, does the data contradict itself.

Separate dimensions produce sharper findings than one generalist, and the overlap between three
reports is a reliable severity signal: a defect all three name is the one to fix first.

Give critics screenshots and read-only access. A critic that can write starts fixing, and then
nobody is reviewing.

## The brief that makes a critic useful

A critic told to "review this site" returns a list of adjectives. Four things turn it into a
list of defects:

1. **The context** — what this is, who it is for, and that it must beat the source rather than
   copy it. Include the baseline screenshots' paths.
2. **The previous round's findings, as questions.** "Each of these was changed — is it fixed,
   partly fixed, or still broken? Say which, with the evidence."
3. **A known-and-not-worth-reporting list** — the deliberate decisions and the platform
   limitations. Without it, every round re-reports the same non-defects and buries the new ones.
4. **A fixed output format**, so reports are comparable across rounds and dimensions: a score
   out of ten with an anchor for what five and eight mean, the previous findings verified,
   blocking issues, worth-fixing ranked by impact per effort, what is working, and a verdict
   against the source site.

Ask for the page, the slice file and the rough position for every finding. A finding you cannot
locate is a finding you cannot fix.

## Checks worth running yourself

Eyes miss what a string match catches, and none of these needs a browser —
`fetch_frontend_page_html` on the MCP server returns the rendered markup. Before reading a
single screenshot:

- **Fetch the rendered HTML** of the listing pages and read the facet headings and option values
  out of it. Word-fragment options, duplicate headings and comma-split values all show here
  first.
- **Grep every page for the template's demo strings** — the demo brand, its locale prefix, its
  category names — across desktop and mobile markup.
- **Check counts against the catalogue**: the number on a category tile, the result count, and
  any number asserted in copy.
- **Check links resolve**: the hero buttons and the primary calls to action, specifically. A
  prominent button pointing at the wrong page survives many rounds of eyeballing because the
  page it lands on looks fine.

## The fix loop

Work the findings in this order, because each one changes what the next round sees:

1. Anything that renders the demo's content or a dead end.
2. Data contradictions — the same fact stated two ways on one page.
3. Structural page defects.
4. Copy and polish.

Fix, then re-capture, then re-critique. Two full rounds is the realistic minimum; the first
round finds the leftovers and the second finds the real defects underneath them.

When a finding cannot be fixed through the available surface, it does not disappear — it moves
to the handover document, and onto the next round's known-issues list so critics stop
re-reporting it.

## Copy has to survive a click

Every blanket claim in the copy is a promise about the data. Before shipping a sentence that
says "every product states X", count how many products actually carry X. When the answer is a
third of them, hedge the sentence to what is true — the FAQ phrasing "where we hold the figures"
costs nothing and cannot be falsified by the first click.

The same applies to numbers: a range quoted on the front page, in an about page and in a FAQ has
to be one range, and it has to be the range the imported field values support. Reconcile them
against the data, not against each other.

## Definition of done

Per demo-critical page, at both widths:

- no content from the template's own demo, anywhere, including the mobile menu and footer,
- every facet heading and option is a phrase a person would say,
- every card carries an image, a differentiating line and a price,
- the primary calls to action land where their label promises,
- no page states a fact its own specification panel contradicts,
- the page scrolls without horizontal overflow and nothing overlaps.

## The handover document

Write a short limitations document and hand it over with the URL. Group by cause, because the
cause decides who acts:

- **Not reachable through the available tool surface** — the setting exists but no tool writes
  it. Name the property and where a person changes it.
- **Deliberate decisions worth confirming** — VAT display, how variant families are modelled,
  anything mirroring the source that the customer might want changed.
- **Source-data gaps left as they are** — attributes the source does not publish, records whose
  values contradict themselves. Say what was left rather than inventing a value, and say why.
- **Template-level work, out of scope** — anything needing a change to shipped Razor templates
  that are shared with other sites on the instance.

Then report the live URL, what the data model holds, what the site does, and the limitations
list. An honest gap named by you is a smaller problem than the same gap found by the customer.
