# fresh-deserialize-sweep.md

> What a freshly deserialized Swift baseline tells a prospect that is false about the customer, and
> the sweep that finds it BEFORE the demo path is built. Everything in this file survives a rebrand
> that edits the pages a build touches — precisely because none of it is on the demo path. Run it as
> Step 0's sibling: [`re-skin.md`](re-skin.md) §"Step 0 — the zero-state pass" retires the stock
> *look*; this file retires the stock *claims*.
>
> Swift 2.x only — never follow `/swift/swift-1/` URLs.

## Contents

- [Why this runs before the demo path, not after](#why-this-runs-before-the-demo-path-not-after)
- [The sweep — seven passes over the RENDERED corpus](#the-sweep--seven-passes-over-the-rendered-corpus)
- [The fiction families a baseline ships](#the-fiction-families-a-baseline-ships)
- [An empty field is not neutral — it can restore the vendor word](#an-empty-field-is-not-neutral--it-can-restore-the-vendor-word)
- [Rolling and stamped baseline values](#rolling-and-stamped-baseline-values)
- [Currency: a default currency with no symbol renders bare numbers](#currency-a-default-currency-with-no-symbol-renders-bare-numbers)
- [A licence-gated surface: retire the branch, do not demo a dead button](#a-licence-gated-surface-retire-the-branch-do-not-demo-a-dead-button)
- [What to leave alone](#what-to-leave-alone)

## Why this runs before the demo path, not after

A crawl of every front-facing page as every persona, run **after** six phases of rebranding had
already touched every page on the demo path, still found the storefront telling a prospect things
that were false about the customer and true only about the platform vendor. None of it had been
missed by carelessness: a meta description is invisible until someone opens view-source, shares a
link preview, or screen-shares dev tools, and the legal, delivery and about pages are reachable from
the footer only. **Fixing only the pages on the demo path is the failure mode**, so the sweep is
scheduled before the demo path exists.

The sweep also earns its keep as a negative control. On the same run, every real-person name and
mailbox from the source engagement, the demo password, bearer fragments, the SQL password, the stock
administrator account name, placeholder prose and `dw-error` all measured zero — so a hit is
signal, not noise.

## The sweep — seven passes over the RENDERED corpus

Fetch every front-facing URL as every persona (anonymous included) and sweep the **raw served
HTML, attributes included**. A source-side check cannot substitute: several of these live in item
field values that no page-level assert reads, and one whole family exists only in attributes.

1. **View-source the home page** for `MetaDescription`, `og:*`, `Twitter*` and `MetaSiteName`.
2. **Render and READ every page reachable from the footer and the secondary nav** — not merely check
   that the link resolves.
3. **Check every numeric claim** against something true about the customer.
4. **Check every promised channel** (live chat, phone, e-mail) against what the demo can actually do.
5. **Read the legal pages** for another industry's boilerplate.
6. **Resolve every `<video>` and `<img>` `src`** — a baseline ships references to files that are not
   on the install.
7. **Grep the whole rendered corpus for empty-state text** — `No <X> found`, `API key is missing`.

Assert, over the rendered corpus as every persona: zero occurrences of the vendor name outside the
cookie notice, zero of the shipped statistics, zero of the placeholder phone, zero of the foreign
legal headings, zero empty-state strings, zero `dw-error`, and zero `<video>`/`<img>` `src` that 404.

## The fiction families a baseline ships

Six families recur. The first three are shipped **content values**; the fourth is a **template
fallback**; the last two are **live chrome links to surfaces that cannot work**.

| Family | Where it lives | Example shape |
|---|---|---|
| Vendor marketing copy as the site's own | `MetaDescription` + `og:description` on the front page; the privacy policy's opening sentence and the vendor domain | "an implementation framework to improve time-to-market…" |
| Invented numeric social proof | the about page | shopper / city / retail-brand counts for a business with none of them yet |
| Foreign-industry legal + placeholder contact copy | the terms, delivery and privacy pages | generated warranty boilerplate carrying a `CREDIT CARD DETAILS` heading on an on-account-only portal; a placeholder phone in another country, a `noreply@` address, and a "chat with us — get a reply instantly" promise on a demo with no live chat |
| Fiction produced by a template FALLBACK | an ATTRIBUTE, never visible text | see the next section |
| Chrome links to an empty state | footer and secondary nav | an employees page rendering "No employees found"; a store locator rendering "Google maps API key is missing" |
| Chrome links to empty content pages | reachable by URL | shipped editorial sections with no rows |

Rewrite the first three rather than hiding them — **a prospect portal with no terms reads worse than
one with bad terms.** Hiding is the right call only for the pages whose content genuinely does not
exist (the employee list, the store locator, the empty editorial sections). Retire those **by page
permission, never by `PageHidden`**: a hidden page still mints its friendly URL and then 404s on it
— see [`../../dw-swift-building/references/component-system-and-reskin.md`](../../dw-swift-building/references/component-system-and-reskin.md)
§6 for the flag semantics and the diagnostic signature.

## An empty field is not neutral — it can restore the vendor word

**Name every field explicitly; never blank one.** The shipped `Swift-v2_Logo` template falls back to
the literal vendor name when `LogoName` is empty, so an empty field does not mean "no name", it means
"the vendor's name" — rendered as `title="…"` on every page that draws the header or the footer. A
baseline ships several logo items all carrying that name and no image, and **blanking the field —
the natural rebrand action — restores the word rather than removing it.** The positive control is
immediate: re-blank the field and the attribute comes straight back.

This is the same mechanism as a shipped placeholder `defaultValue` rendering live copy on a field
nobody opened ([`paragraphs.md`](paragraphs.md), the unwritten-`defaultValue` trap). Two shipped item types now behave this way, which is enough to make it the rule:
**a rebrand sets values, it does not clear them.**

The consequence for the sweep is the load-bearing half: **run it over the raw served HTML including
attributes.** A sweep over rendered text, or a human reading screenshots, reports these pages clean.

## Rolling and stamped baseline values

A baseline can ship a value that was correct when the layer was built and is wrong on every install
afterwards. Add every such value to the post-deserialize checklist and prefer a fixed value upstream
over a creation-time stamp.

The measured member of this family is the RMA claim form's `<BoughtFromDate>`, shipped as the date
the paragraph was authored, which silently hides every order older than the baseline build from the
claim picker — no message, no empty state, no log entry. Widen it on any install where historical
purchases matter; full mechanism and the claims recipe in [`rma-claims.md`](rma-claims.md).

## Currency: a default currency with no symbol renders bare numbers

On any demo whose currency is not the baseline's own, **set symbol, culture, rate and the
positive/negative patterns on the default currency before judging any price rendering.** A currency
row shipped with `CurrencySymbol` NULL, `CurrencyCultureInfo` NULL, `CurrencyRate` 0 and
`CurrencyPositivePattern` -1 renders every storefront price as a bare number with no currency
indication anywhere and no error; the worked counter-example in the same table carries symbol,
culture, rate 1 and pattern 0. `PriceFormatted` simply has no symbol to place. Rate 0 on the
**default** currency is separately dangerous and is harmless only while nothing converts.

Write it with MCP `save_currencies` (`symbol`, `cultureInfo`, `rate`, `symbolPlace`,
`positivePattern`, `negativePattern`). One caveat to plan for: the write is keyed per currency
**code**, so it lands the same culture on every language row carrying that code — a second language
that formats the same currency differently needs its own pass.

**Assert that a currency symbol is PRESENT in the rendered price text on the list page and the
product page**, not merely that the wrong one is absent. "Zero euro signs" passes on a page showing
no currency at all, which is exactly the state this trap produces. (The rate column's own semantics —
it is a percentage against the default currency, so 100.0 is par — are in
[`../../dw-commerce-catalog/references/catalog-publishing.md`](../../dw-commerce-catalog/references/catalog-publishing.md).)

## A licence-gated surface: retire the branch, do not demo a dead button

Some shipped surfaces render completely and fail only at the last click. The measured case is the
product-file download cart: `eCom7/CartV2/Step/DownloadCart.cshtml` renders the whole request form —
asset selection, resolution, format, language selector, submit — and the licence gate is evaluated
**only at submit**, which answers "The solution does not have license to download" in front of the
prospect. Nothing in the page or the layer states the dependency, so the surface looks fully built
until it is demonstrated. The same form's language selector enumerates every `EcomLanguage` on the
install rather than the area's.

**A dead button in front of a prospect is worse than a missing surface.** Retire the branch
reversibly rather than showing it: deactivate the pages, repoint whatever in the chrome pointed at
them, delete the now-pointless mini-cart from the header, and take the surface out of the hero copy.
Each of those is one flip back if the licence ever covers the step, and the deserialized content
survives — which is why retiring beats deleting.

Two things worth recording from the same probe, because they are positive facts:

- The download cart runs on its **own order context**, genuinely separate from the storefront cart:
  adding an asset does not pollute the buyer's shopping cart. Verified empirically rather than
  assumed — the assert is that the storefront cart line count is still 0 after an asset has been
  added to the download cart.
- A live probe of it creates a real order row. Delete it and re-assert the clean-state cart count, or
  the next phase inherits an unexplained row.

## What to leave alone

**The cookie notice naming the platform's own cookies is correct copy.** It names what the platform
actually sets; renaming it would replace true copy with false copy. The same test applies to
everything else the sweep surfaces: the question is whether the string is true of this install, not
whether it mentions the vendor.
