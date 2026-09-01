# PII and vendor-boilerplate sweep — a blocking pre-demo leg

> **Read this before any demo is shown, published, screenshared or handed over.** A Dynamicweb demo host —
> cloned *or* freshly built from stock Swift — routinely serves **real people's personal data** and the
> **platform vendor's own legal copy** to a customer audience. Both are live privacy and brand exposures, not
> polish items. This file owns the method; it is deliberately a method and not a checklist of names, because
> the recurring failure is a name-based checklist that reports clean.

## Contents

- [The three rules, stated once](#the-three-rules-stated-once)
- [Rule 1 — anonymisation is a whole-database string sweep, re-run after every pass](#rule-1--anonymisation-is-a-whole-database-string-sweep-re-run-after-every-pass)
- [Rule 2 — stock Swift ships the VENDOR's own PII and legal copy](#rule-2--stock-swift-ships-the-vendors-own-pii-and-legal-copy)
- [Rule 3 — a term-grep cannot find placeholder data containing none of your terms](#rule-3--a-term-grep-cannot-find-placeholder-data-containing-none-of-your-terms)
- [The sweep, end to end](#the-sweep-end-to-end)
- [Cross-references](#cross-references)

## The three rules, stated once

1. **Renaming the user rows fixes nothing.** Every other layer holds an independent denormalised copy that no
   user-table edit touches. Enumerate by **scanning every string column in the database**, not by querying the
   tables you expect.
2. **A clean clone is not a clean demo.** Stock Swift demo content ships the *platform vendor's* legal pages,
   corporate addresses and an internal author mailing list. Nothing in a normal build removes them.
3. **A vocabulary sweep cannot find what contains none of your vocabulary.** Add locale-*shaped* patterns and
   keep a rendered-page eyeball pass as a **required** step, not an optional one.

Each rule below is stated as a class of exposure. **Never quote the leaked values** into notes, commits,
tickets, transcripts or skill text — recording the class is the useful part, and copying the data forward is
itself a leak.

## Rule 1 — anonymisation is a whole-database string sweep, re-run after every pass

A brief to retire **one** real identity on an inherited demo named four user rows. The real inventory was
**nine** user rows plus content, orders, addresses, tokens and log text — and behind that sat **25 further
real people** on a presenter-visible admin screen. **Three passes were needed, and each one found a genuinely
new CLASS of exposure.**

**Why the obvious fix under-reaches:** renaming `AccessUser` reaches the user row only. The layers that hold
independent copies, none of which a user-table fix touches:

| Layer | Shape of the copy | Why a targeted query misses it |
|---|---|---|
| **User rows** | more rows than the brief names — clone leftovers, plus rows whose surname sits only in the surname column behind an unrelated display name | a display-name search finds neither |
| **Content** | a customer-facing testimonial, present in **every language layer** | one hit per layer; fixing the master leaves the others |
| **Order snapshots** | hundreds of rows carrying name/email **and postal-address columns** captured at order time | the address columns survive a name/email rename — they are a second pass |
| **Address rows** | private mailboxes and **real home street addresses** | not a name at all |
| **API-key / token labels** | a token labelled with a person's name | nothing about a token suggests PII |
| **Log / debugging text** | hundreds of rows of captured request text | legacy `ntext` columns that a naive bulk `REPLACE` silently skips |
| **JSON merge-field snapshots** | the same identities serialised one layer down inside a recipient-tags blob | invisible to any column-name heuristic |

**The method is the rule:**

1. **Enumerate by scanning EVERY string column** in the database (thousands of them) for the identity — not
   by targeted queries against the tables you predicted. The inventory above was found this way and could not
   have been found the other way.
2. **Classify each hit by SAMPLING THE VALUES, not by table name.** person / vendor-branding / infrastructure
   are three different dispositions, and the table name predicts none of them.
3. **Fix, then RE-SCAN.** Fixing one layer exposes the next — the postal-address columns only became visible
   after the name/email pass, and the JSON snapshot only after that.
4. **Search mailbox local-parts and postal addresses, not just names.** The most dangerous single row on one
   host survived the entire first sweep because the mailbox local-part contained neither the first nor the
   last name. That is not an edge case; it is the normal shape of the last surviving hit.
5. **Legacy column types must be named explicitly.** `REPLACE` refuses `ntext` as its first argument, so a
   bulk sweep silently skips exactly the tables where long strings live and then reports a clean pass —
   `CAST(… AS nvarchar(max))` inside the `REPLACE`, and assert zero remaining hits in those columns too
   ([`management-api-and-sql.md`](../../dw-data-access/references/management-api-and-sql.md) "Bulk string edits").

**Gate:** a clone-time sweep asserts **zero hits** for the configured real-person term list across **all**
string columns, with documented audit-trail exemptions named explicitly rather than assumed.

## Rule 2 — stock Swift ships the VENDOR's own PII and legal copy

**This is not clone residue — it is stock template seed data**, so it is present on demos built cleanly from
the shipped content, and nothing in a normal build removes it. Observed on a boat-builder storefront: the
site was serving the **platform vendor's corporate privacy policy verbatim**, naming the vendor's own
third-party data processors as though they were this customer's, while the backend Email-marketing screen
listed the **template authors by name on real vendor mailboxes** — on a screen the demo storyline had already
put on the presentation path.

The classes to sweep, all of them stock:

- **Legal pages** — privacy, cookie and terms copy belonging to the platform vendor, including its named
  third-party data processors and its own CRM/mail vendors. The terms page additionally carries
  **open-source software-licence boilerplate** ("Covered Code", "Licensor", warranty exclusion) on what is
  presented as a retailer.
- **Corporate addresses** — vendor office addresses seeded as user address rows.
- **An internal author mailing list** — named staff on vendor mailboxes in the email-marketing recipient
  table, including names embedded inside third-party email-preview addresses.
- **Contact blocks** — placeholder phone numbers in the vendor's home locale (see Rule 3).

**Two fixes, at two levels:**

- **Edition/layer level:** strip or neutralise vendor legal copy, corporate addresses and the author mailing
  list from the shipped demo content, so no demo inherits them again.
- **Demo level:** add a **vendor-boilerplate sweep** to the demo checklist covering privacy, cookie, terms,
  unsubscribe and the email-recipient table. The enforced form of the stock-content half is
  [`../scripts/Remove-SwiftVendorBoilerplate.ps1`](../scripts/Remove-SwiftVendorBoilerplate.ps1)
  (dry-run by default, `-Apply` to write, originals backed up; local installs only) — it rewrites
  the stock phrases by content match and then lists what remains for the manual pass.

**The de-branding nuance that works:** some vendor strings are *technically load-bearing* — the platform's
own cookies genuinely are named after the platform, and renaming them in the cookie policy makes the page a
lie. **Describe those by purpose rather than inventing false identifiers.** De-brand the marketing and legal
copy; keep technical references accurate.

**Gate:** the rendered corpus contains zero vendor-company strings outside deliberately retained technical
references, and the email-recipient table contains no vendor-domain mailboxes.

## Rule 3 — a term-grep cannot find placeholder data containing none of your terms

A vocabulary-driven sweep over the whole corpus reported **clean** while a placeholder phone number in the
vendor's home country sat on the contact block of a US company, on two live legal pages, in **all three
language layers**. It is unmistakable residue and it matches no word in any term list. It was caught only by
**looking at the rendered page**.

Add **locale-SHAPED patterns** alongside the vocabulary:

- foreign dialling codes / country prefixes that do not belong to the customer's market
- foreign postcode shapes and foreign street suffixes
- company-registration-number formats (`reg. no`, VAT/organisation-number shapes)
- currency and date formats from the wrong locale

And keep the **rendered-page eyeball pass as a required step**. The mechanical sweep and the eyeball pass
fail on disjoint sets: the sweep catches volume and hidden layers, the eyeball catches everything that
matches no pattern anyone thought to write. Neither substitutes for the other — this is the same relationship
as the mechanical detectors vs the human taste sign-off in [`visual-qa.md`](visual-qa.md).

## The sweep, end to end

Run this as a **blocking leg**, not a polish item, on every demo — hardest on an inherited/cloned host.
The mechanical steps (1, 4, and the mechanical half of 6) have an enforced form —
[`../scripts/Invoke-DwPiiScan.ps1`](../scripts/Invoke-DwPiiScan.ps1) (READ-ONLY, classes and
counts only; SQL sections are local-only, the rendered/probe sections run by URL) — run it rather
than retyping the census queries. Steps 2, 3, and 5 remain yours:

1. **Enumerate** — scan every string column for the identity terms **and** the locale-shaped patterns.
2. **Classify by sampling values** — person / vendor-branding / infrastructure.
3. **Fix** — at the layer that owns each hit, not at the user table.
4. **RE-SCAN** — a pass that finds nothing new is the first pass you may believe.
5. **Render and read** — walk the legal pages, the contact blocks, the email/marketing screens and every
   language layer with your eyes.
6. **Assert** — zero term hits across all string columns (documented exemptions only), zero vendor strings in
   the rendered corpus, zero vendor-domain mailboxes in the recipient table, zero foreign dialling codes on
   contact blocks.
7. **Do not record the values.** Write down the classes and the counts; never the data.

**A persona rename is a superset of this problem, not a subset** — the retired identity also lives in
harnesses, generators, seeders and secret stores that will *re-publish* it on their next run. See
[`../../dw-demo-swift/references/customer-center.md`](../../dw-demo-swift/references/customer-center.md)
"Renaming a persona is a sweep, not a user edit".

## Cross-references

- [`online-mode.md`](../../dw-demo-hosted/references/online-mode.md) — the cloned-host remediation playbook; a clone is where rules 1 and 3
  bite hardest.
- [`visual-qa.md`](visual-qa.md) — the rendered-page pass this file makes mandatory, and the same
  mechanical-gate-plus-human-eyeball relationship.
- [`management-api-and-sql.md`](../../dw-data-access/references/management-api-and-sql.md) — legacy `text`/`ntext` columns that silently
  drop out of a bulk string sweep.
- [`customer-context.md`](customer-context.md) — the read-only contract on customer-supplied materials; this
  file is its mirror on the *host* side.
