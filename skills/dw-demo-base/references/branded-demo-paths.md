# branded-demo-paths.md

> Three ways to reach a branded Dynamicweb 10 demo, what each one costs, and which one to take.
> **Default: path A, YAML first.** Path B is the explicit alternative and stays valid; path C is
> the floor. This file is the routing point every branding instruction in the corpus defers to.

## Contents

- [The verdict](#the-verdict)
- [The three paths](#the-three-paths)
- [Path A, YAML first (default)](#path-a-yaml-first-default)
- [Path B, deserialize first, then tools](#path-b-deserialize-first-then-tools)
- [Path C, tools only from a blank host](#path-c-tools-only-from-a-blank-host)
- [When path B wins](#when-path-b-wins)
- [Traps that cost time on either path](#traps-that-cost-time-on-either-path)

## The verdict

Two arms built the same brief against the same starting layer, on the same platform pins, with
only the write channel differing: one rebranded the shipped demo data through the MCP tools and
the Management API, the other authored a demo-local brand layer in YAML and deserialized it on
top. Measured 2026-09-14, online mode only (site URL, Admin API bearer key, MCP key, a browser).

| Measure | A, YAML first | B, tools |
|---|---|---|
| Wall clock, blank host to a green gate | **60.5 min** | 79.3 min |
| Tokens, orchestrator plus every subagent | **1.43 M** | 2.03 M |
| Hand-made write calls | **19** | 1,833 |
| Brand values landed by Deserialize | **88.02 %** (99.57 % of database values) | 0 % |
| Rebuild the whole branded demo | **176 s**, no tools, no restart | not repeatable as a unit |
| Issues the path itself produced | **4**, none a broken write path | 24, of which 9 are tool-path gaps |

Path B reached one more acceptance item on the rendered storefront (7 of 7 against 6 of 7), and
only after a fix pass; the shortfall on path A was a probe that was not run, not a defect.

**So: take path A unless one of the conditions under [When path B wins](#when-path-b-wins)
holds.** Both paths are supported and the corpus documents both. What is no longer supported is
reaching for the tools *first* on a solution that has a serialized route, because the tool path
pays twice, once to write each value and once to repair what the tools break.

## The three paths

| | A, YAML first | B, deserialize then tools | C, tools only |
|---|---|---|---|
| Starting point | the Distribution's `sample-data` layer | the same layer, delivered as shipped | a blank host |
| Brand channel | a demo-local layer of kind `sample-data`, deserialized | MCP tools plus the Management API | MCP tools plus the Management API |
| Artefact left behind | the layer, the edition, the composed trees | the host | the host |
| Rebuildable | yes, by recompose plus redeploy | no | no |
| Needs a local harness | yes | no | no |
| Use it when | anything above roughly a hundred branded subjects | the conditions below | there is no layer to start from at all |

Path C is the floor, not a recommendation: it re-derives by hand what the `sample-data` layer
already ships (catalogue, personas, orders, storefront copy, imagery, the demo clock). Choose it
only when no Distribution content applies to the demo at all, and then follow the modelling
recipes in [`dw-demo-pim`](../../dw-demo-pim/SKILL.md) rather than this file.

## Path A, YAML first (default)

The `sample-data` layer is the one-shot demo: the browsable catalogue, the three personas on one
B2B account, the twelve orders, the storefront copy, the brand assets and the demo clock. An
agent **rebrands it in place through a layer of its own** rather than assembling a demo.

The layer is read-only to a demo. Branding never edits Distribution YAML: guarded-write rule 3 in
[`../SKILL.md`](../SKILL.md) is the enforcement point, and the brand layer authored below is
demo-local, under the demo root, never under `distribution/layers/`.

### Steps

1. **Resolve the edition and read what it already carries.** Take the edition that sets
   `sampleData: true` and read the layer's own README for its naming rule and subgroup map.
   *Check:* the edition's `expectedCounts` match the layer you resolved, and the resolved
   Distribution commit is recorded in `CUSTOMISATIONS.md` as the reproducibility stamp.
2. **Read the contract before renaming anything.** `layers/base/base.contract.json`,
   `sampleData.guaranteedRows`, names every subject a feature layer's probe binds to: the three
   persona user names and ids, the SKU the quick-order validation feed types, the quantity-tier
   and contract-price products, the BOM master, the delivered order behind the returns page.
   *Check:* list the guaranteed subjects and mark, per subject, whether the brand renames it. A
   renamed subject turns its probe red **by construction**; that is a decision to record in the
   plan doc, not a defect to chase later.
3. **Author the demo-local brand layer**, kind `sample-data`, under the demo root. Three
   document families, authorable in parallel:
   - **Partial `SqlTable` rows with `ownership: replace`** for the renames: names, SKUs, order
     numbers, group titles, category-field values. Partial rows carry only the columns the brand
     changes, so every key the contract pins stays put.
   - **Content YAML at the same paths as the layer it overrides**: page titles, meta, paragraph
     copy, navigation labels, sign-in copy.
   - **`files/`**: wordmark, favicon, touch icon, social image, hero, product tiles, documents.
   *Check:* every content document you wrote overrides an existing path (an override review, not
   a create), and no partial-row file collides with another on the same table and key.
4. **Add the colours as a theme overlay, not as data.** A theme layer is disk-overlay only:
   palette, tokens and the customer stylesheet. List the brand theme **after** the default theme
   in the edition, because delivery uploads theme `files/` after layer `files/`.
   *Check:* the served stylesheet carries the brand tokens and the shipped theme sheet is
   unmodified, per the naming hard rule in
   [`../../dw-demo-swift/references/re-skin.md`](../../dw-demo-swift/references/re-skin.md).
5. **Compose locally into ONE tree per mode.** The composer stages the brand layer after the
   surfaces so its copy wins the paths it shares.
   *Check:* the compose log lists the brand overrides and reports none dropped; the output is one
   `replace` tree and one `merge` tree, each with its mode manifest at the root.
6. **Deliver.** Upload the files and the zips, unzip each mode once, then deserialize replace and
   merge, in that order. The route, the limits and the failure shapes are owned by
   [`serializer-reference.md`](serializer-reference.md). **One zip per mode**: unzipping a second
   zip for the same mode erases the first.
   *Check:* the delivery reports zero failed rows for both modes and the indexes rebuild.
7. **Restart when the delivery says it owes one**, then finish the five subjects Deserialize
   cannot carry. On the master item type, the fields listed under `excludeFieldsByItemType` are
   protected from deserialize by design, so favicon, touch icon, meta site name, meta image and
   its alt text go through `set_item_field_values`. Persona passwords go through
   `UserSetPassword`, never a hash written by hand.
   *Check:* read the five fields back, and sign each persona in on the storefront.
8. **Accept on the rendered storefront, not on an HTTP 200.** Crawl the storyline pages
   anonymous and signed in, at desktop and phone width, and grep the served HTML for the shipped
   vendor's strings.
   *Check:* zero vendor or placeholder strings on the crawled set; the visual-QA detectors in
   [`visual-qa.md`](visual-qa.md) pass.
9. **Prove the rebuild.** Recompose and redeploy over the live host.
   *Check:* every gate leg passes with no tool step and no restart. Measured at 176 s total, 28 s
   to recompose and 147 s to redeploy; the excluded master fields and the persona passwords
   survive a merge redeploy, so step 7 does not repeat.

### What path A leaves behind

The brand layer, the edition that names it, and the composed trees. The host is reproducible from
those three; a successor rebuilds it instead of replaying an agent. Record in the plan doc the
handful of things that live only on the host: the excluded master fields, the persona passwords,
and any local-only script in the layer that has no online route.

## Path B, deserialize first, then tools

Deliver the edition as shipped, then rebrand the live host through the MCP tools and the
Management API. This is the path to take when a condition below holds, and it is a real path: it
reached every acceptance item on the rendered storefront.

### Steps

1. **Deliver the edition as shipped** (steps 5 and 6 of path A, without a brand layer).
   *Check:* the gate passes every leg on the unbranded site before any brand write. A red run
   before the first green is expected when a restart is owed.
2. **Inventory the subjects the brand touches**, from the same contract block path A step 2
   reads, plus the storefront copy the crawl finds.
   *Check:* a written list; it is also the replay script you will not have later.
3. **Unlock the master-only product fields before any variant write.** Product number, price,
   stock and the SEO fields are master-only by default, so a master save copies master values
   over every variant row. Set variant editing on those fields first.
   *Check:* save one master, then read one of its variants back and confirm the variant's own
   number and price survived. Doing this check after the whole catalogue is written costs a
   repair pass.
4. **Write the catalogue, the identities and the orders.** Rename groups and products, add the
   new groups the brief needs, create the personas and the account group, and re-total the orders.
   *Check:* the storefront renders the new SKUs; every order shows a non-zero total in the
   customer centre; the account group is visible to the CSR, which needs a group **type**, not
   just a group.
5. **Write the content and the assets.** Page titles and meta, paragraph copy, colour schemes,
   logos, hero and band imagery, the media rows.
   *Check:* the served HTML carries the new titles. A write that answers 200 and persists nothing
   is a known shape here; verify by reading the rendered page, never by the tool's own echo.
6. **Accept and fix.** Same crawl as path A step 8, then a fix pass for what the crawl finds.
   *Check:* zero vendor strings; the gate legs green except the ones the rename turned red by
   construction, each explained in writing.

### What path B leaves behind

**The host is the only copy of the build.** A recompose re-applies the shipped rows and copy, so
the rebrand would have to be replayed as the whole call sequence in its logged order, with the
variant unlock before any variant write. Neither a script nor a layer captures it. Write the
host-state facts a successor cannot see (the field settings you changed, the group type, any
default a fix pass set) into the plan doc, because nothing else records them.

## Path C, tools only from a blank host

No layer at all: model the catalogue, identities, orders and content from scratch over MCP. This
is the `dw-demo-pim` flow and it is the right answer for a PIM demo that wants no storefront
sample data. As a route to a *branded storefront* demo it is the slowest of the three, because it
re-derives everything the `sample-data` layer already ships and every step of path B applies to
it as well, on top of the modelling.

Take it when: there is no Distribution content that fits the demo, or the demo is a data-model
story where the shipped catalogue would be noise. Otherwise prefer A, or B under a condition
below.

**Path C by accident.** A missing Distribution checkout is a discovery failure until proven
otherwise: the repo is public and named in every clone snippet (`scaffold.md` §5), so "no
Distribution access" is never a build fact an agent establishes on its own. A branded storefront
built on path C because the checkout was skipped pays the whole of path B's tool traps on top of
the modelling, and lands without the three things the `sample-data` layer ships working: the
product index behind the PLP, the personas, and the sign-in. Nor is "YAML first without the
Distribution" a shortcut back to path A: without the `sample-data` layer there is nothing to
override, without the composer there is no override review, and a hand-authored full layer is
path C with extra files. A brief that says "minimum Swift foundation, no sample content" still
takes path A: the brand layer replaces the shipped copy, it does not add to it.

## When path B wins

Taken from the measured comparison; each one removes path A's advantage rather than reversing the
numbers.

1. **A small change set.** Below roughly a hundred branded subjects, the layer's scaffolding (a
   composite root, an edition, mode trees, the override review) costs more than the writes. Path
   A paid about 190 s of compose and composite before authoring anything.
2. **No local compose.** Path A needs a harness, a Distribution checkout and a local composite
   root. The tool path needs only a URL and two keys. On a hosted solution with no local harness,
   B is the only path ([`dw-demo-hosted`](../../dw-demo-hosted/SKILL.md)).
3. **Subjects with no serialized route.** The excluded master fields, the global-settings
   fragments and a layer's local-only scripts are tool-or-nothing on both paths. A brief whose
   brand lives mostly there removes path A's advantage.
4. **A throwaway demo nobody will rebuild.** Repeatability is then not a criterion, and B leaves
   no artefact to maintain.

The verdict moves back to B if the tool-path write gaps close: the two repair passes they forced
were about 1,757 s of path B's window, and without them the two paths land within a few minutes
of each other, with B's simpler surface as the tie-breaker.

## Traps that cost time on either path

**Tools.**

- **Master-only fields reset variants.** A master save with variant editing off copies the
  master's number, price, stock and SEO onto every variant row while echoing the request back as
  a success. Unlock the fields first, then write; the repair is a per-variant rewrite.
- **Orders need their price columns.** Orders built over the tool surface land with zero totals
  unless the line prices are written and the order re-totalled; a zero total is visible in the
  customer centre on demo day.
- **A 200 is not a write.** Several page and product verbs answer success and persist nothing.
  Verify by reading the rendered page or re-reading the row, never by the response body.
- **An account group needs a type, and the CSR group needs a relation over it.** The CSR accounts
  screen lists only groups of type `SystemAccount`, so a group with an empty type does not list even
  though every relation is correct, and the CSR users screen stays empty until the CSR group holds an
  impersonation relation over the account group. A shipped demo layer can arrive with both missing;
  sign in as the CSR on a fresh delivery and read the accounts page before trusting the persona note.
- **A country needs a default shipping method.** With the country's default empty the checkout
  preselects a method by its own rule, not by sort order (a method sorting later was preselected over
  the one sorting first), and when only one method is valid for the country it preselects nothing at
  all, with the hidden empty radio checked. Set the country's default shipping method rather than
  narrowing the method list or relying on sort.

**Assets.**

- **The image handler drops alpha on the no-format route.** The handler answers JPEG for a request
  with no format. For `format=webp` it negotiates on the `Accept` header: a browser (which sends
  `image/webp`) gets WebP with its alpha, and a request without that header gets JPEG; `format=png`
  keeps a PNG's alpha either way. A transparent logo routed with no format paints on a solid box (a
  white inverse mark on a dark footer is where it shows), and a probe that counts `naturalWidth`
  passes it. Request transparent marks with `format=png` or bind them as inline SVG, and check the
  served content type or the first bytes of a request with a browser-shaped `Accept` header
  ([`visual-qa.md`](visual-qa.md)) rather than the source file.
- **An asset id can render as alt text.** The product gallery uses the asset row id for `alt`, so
  the shipped keys leak into the markup of a branded PDP. No verb renames an asset row id, and a
  delete plus re-add loses the default flag, the sort and the variant inheritance, so the online
  path does not reach it: ship a `DetailsName` on every image row in the layer, or override the
  gallery template to use the asset name; a probe asserts no `alt` matches the layer's key prefixes.

**Serialize and deliver.**

- **One zip per mode.** Unzipping a second archive into the same mode folder replaces the whole
  folder. Compose everything the delivery needs into one tree per mode.
- **Row files are read in file-name order.** Within a table directory, the deserializer reads
  every document and ignores the manifest's `files[]` list; the order is culture-sensitive
  string order of the file name, a convention, not a contract. Two documents carrying one
  identity in one directory both merge, and the later file wins, so a partial override row wins
  only because its file name sorts after the full row it overrides. On a blank host a partial
  row at the same path as a full row would INSERT a row holding only those columns, so a partial
  override row is never the only document for its identity. Name brand row files so they sort
  last, deliberately, keep the full row beside them, and say so in the layer README.
- **Theme files land after layer files.** Every edition theme's `files/` uploads after every
  composed layer's `files/`, last writer wins per destination path, so a brand layer cannot
  override a path a theme also ships. The workaround is a theme entry for the brand layer,
  listed after the default theme, with a `theme.json` whose binding matches the default so the
  theme binding writes nothing and only the files land.
- **Five master fields never travel.** The fields under `excludeFieldsByItemType` are protected
  from deserialize by design. They are a tool step on every path, and they survive a later merge
  redeploy.
- **No online restart route on a self-hosted install.** When a delivery reports that a restart is
  owed, the marker file does nothing and no API command restarts the application. Ask the
  operator, record it as a manual intervention, and do not measure the gate before the restart:
  a stale cache reports as content and design failures.
