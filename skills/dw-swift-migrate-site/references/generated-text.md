# Generated product texts: enrichment and translation

Used by [dw-swift-migrate-site](../SKILL.md) only when the user asks for new or translated product
texts. Source texts stay verbatim otherwise. The pattern: a fact file per product, a writer brief,
a reviewed sample, then the full run, with a checker between the writer and the import.

## Contents

- [Why generated texts fail](#why-generated-texts-fail)
- [1. Field policy](#1-field-policy)
- [2. The fact file](#2-the-fact-file)
- [3. The writer brief](#3-the-writer-brief)
- [4. Sample, review, then roll out](#4-sample-review-then-roll-out)
- [5. The checker](#5-the-checker)
- [6. Import](#6-import)

## Why generated texts fail

A migrated catalog often carries a name and a handful of specifications per product and little or
no description. A writer told "only facts, invent nothing" can then only turn the specifications
into sentences, and the text repeats the name. Internal codes among the specifications become
customer copy: a finish or variant code is read as the plain word it resembles, a stock or
assortment flag becomes a sales claim. And anything the brief explains about the data, the writer
may write down as a fact about the product. Every rule below closes one of these.

## 1. Field policy

Before writing anything, sort every field of the data profile (catalog-import.md, "Scrape into
files") into three kinds, with the user:

- **Customer-facing as is**: materials, dimensions, capacities, compatibility, colours, series or
  collection names
- **Customer-facing after translation**: codes whose word means something else, and the
  abbreviations used in product names; give each a plain wording, or "do not mention"
- **Internal**: stock and assortment flags, campaign markers, placeholder brand or collection
  values, editorial tags. These never reach the writer, not even as an explanation.

The specification list on the product page may still show every field; the policy governs
generated prose only.

## 2. The fact file

Build one JSON object per product with a script, from the policy above, never from the raw record:

- the cleaned name and the product's type and category
- the customer-facing fields, translated where the policy says so
- the source's own short notes (dimensions, what is or is not included): real facts, always pass
  them on
- story text from the source's own pages (series or collection pages, a service or guarantee
  concept), attached to the products it applies to
- up to three names of related products from the same series, when relations exist
- **the product's main image.** A writer that can see the product describes it in one pass and
  resolves what codes cannot; send the image with the facts to a vision-capable model, one
  product per request. On a solution with the platform's own AI field suggestions or agents
  configured, those can run the same brief on the products in place

## 3. The writer brief

The brief tells the writer what a good text does for the shopper (picture the product, what its
materials and features mean in use, the practical details, one story or pairing). It gives a
glossary of general facts it may use (materials, standards, grades, care for this kind of
product), how to read the abbreviations in the names, the banned internal words, and one bad and
one good example drawn from the sample.

- **Never explain an internal code in the brief.** Leave the field out of the fact file instead.
- **Ask for a natural description of what the product is and has**, never constructions like
  "X is the motif of this product" or "the defining feature of this product is X".
- **Ration recurring material:** care tips, service lines and closing formulas in at most one text
  of three, worded differently each time.
- **Have it write every text individually**, never through a template script.

## 4. Sample, review, then roll out

Write 20 to 30 products first, chosen to cover every product type plus the special cases (a
series with a story, products with a service concept, every target group, the products with the
richest and the thinnest data, and any product a reviewer already complained about). Show them on
a review page next to the old texts, with the facts each writer had, and let a human who knows the
brand read them. Fold every remark into the brief as a rule, write the sample again, and roll out
to the full catalog only when a sample reads well. A full run on an unreviewed brief costs a
second full run.

## 5. The checker

Run a script on every batch before import, and send a batch back on any finding:

- the internal words of the field policy, and claim words that no fact supports (certifications,
  "handmade", health or safety claims)
- every number in the text present in that product's facts or the glossary, which catches invented
  dimensions
- sentence count and length limits, no two texts in a batch opening with the same three words
- the story or concept mentioned where the fact file carries it

A format check alone passes useless texts; the checker is about content.

## 6. Import

Import only the text columns, per language, through Data Integration or the MCP product patch
tool for small sets, and read one product back on its frontend page. Keep the fact files, the
brief versions, and the checker in the working folder, so the next run starts from them.
