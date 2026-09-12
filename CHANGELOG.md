# Changelog

All notable changes to the Dynamicweb Skills plugin are recorded here. The
`version` field in `.claude-plugin/marketplace.json` tracks these entries.

## [4.44.0]

Fold-back sprint: dw-demo-swift, dw-swift-building, dw-swift-page-blocks and dw-swift-page-design. Forty-one demo-build learnings land as three foundational references under dw-swift-building (grid-row mechanics, layout verification, shipped-template defects on Swift 2.4.0) and two demo references (the fresh-deserialize sweep, RMA claims in the customer center), with four rewrites of guidance that was wrong: the visually-hidden idiom that caused the overflow its guard exists to prevent, the paragraph-template restart row, the header mega-menu bridge, and the grid-row copy claim. A demo engagement slug that had leaked into the mobile-pass reference is scrubbed.

The Swift cluster: the layout truths a markup assert cannot see, the row mechanics behind a page that
saves and does not render, and the shipped-template defects a build inherits.

- **A visually-hidden label ships `overflow: hidden` — `clip-path` does not contain overflow.**
  `re-skin.md`'s floating-header recipe prescribed the `clip` + `clip-path` idiom with no `overflow`
  declaration, and shipped a standing guard forbidding `overflow` anywhere under the header. Measured
  A/B/C/D at two device widths: that idiom is the WORST variant (19px and 18px of horizontal overflow
  against 4px and 0px with the label simply left in flow), because `clip-path` crops painting and
  creates no scroll container. The rule is rewritten, not annotated, and the guard is re-scoped to the
  ancestors a megamenu or off-canvas panel escapes through. The accessible name survives in every
  variant, so containment costs nothing.
- **Horizontal overflow needs three numbers, not one, and the offender is named by RIGHT EDGE.**
  `body.scrollWidth <= innerWidth` is satisfied by construction once the browser widens the layout
  viewport to fit unshrinkable content — a 262px stretch reported as zero. Assert `innerWidth` equals
  the requested width as well. And a width-sorted offender walk reliably names a closed Bootstrap
  off-canvas drawer, which tracks the overflow while contributing nothing to it; the element whose
  right edge equals `documentElement.scrollWidth` is the cause. Both legs are now in the mobile pass
  and in a new foundational reference, with the recurring Swift causes (a Bootstrap `g-col-N` span
  over an `auto-fit` grid, the `.mw-75ch` reading measure on authored content).
- **Every viewport pass owes BOTH auth states.** Swift's mobile header renders a ~48px initials button
  signed in and a ~123px labelled anchor anonymous, so a signed-in sweep measuring 0 on ten checks and
  an anonymous sweep measuring 71px on the same pages are both correct. The anonymous control is the
  wider one.
- **New `layout-verification.md`** (`dw-swift-building`) — the four defect classes that clear every
  HTTP and DOM-presence check: horizontal overflow, a control present and styled but under a card's
  stretched row link (only `elementFromPoint` at its centre sees it), an anchor coloured by its row's
  *declared* colour scheme rather than the background the page paints, and a band that renders nothing
  while still paying its spacing. Routed from `dw-swift-page-design`, `dw-demo-swift` and
  `dw-swift-page-blocks`.
- **New `grid-rows-and-binding.md`** (`dw-swift-building`) — one home for the row mechanics that were
  being rediscovered one attribute at a time. `GridRowCopy` carries **five** donor attributes
  (paragraphs, spacing, the paragraph's `ParagraphTemplate`, `GridRowSort`, `GridRowContainerWidth`)
  and does **not** append, correcting the older "copy appends only" claim; normalisation is part of the
  copy step. The column-binding law is stated in full: binding is by `ParagraphGridRowColumn`, never by
  sort, so a one-column row drops every paragraph after the first and a doubled-up multi-column row
  renders the other column empty — with parking-in-an-undefined-column as a clean reversible retire.
  An inert row still pays its spacing plus the flex wrapper's padding, so `GridRowActive = 0` through
  `GridRowSave` is the lever and `ParagraphShowParagraph` is inert. And an idempotency marker must be a
  string the row RENDERS: an id-range check misses on the next run and duplicates the work.
- **New `shipped-template-defects.md`** (`dw-swift-building`) — what the shipped Swift 2 templates do
  not do. Two Swift 2.4.0 templates call `System.Web.HttpUtility` and do not compile on DW 10.29/.NET
  10 (one serves raw Razor to a visitor, the other fails silently because nothing watches an invitation
  mail render); the product-search dropdown dereferences `DefaultImage` unguarded where its shipped
  sibling null-guards the same field, so it throws for every term that MATCHES on a catalogue without
  images; the order list and detail never render the payment method although every sibling detail
  template does, so a payment-method migration has no customer surface to verify on.
- **"No prices" is a claim about display, not delivery.** Swift 2's add-to-cart component posts
  `ProductPrice` / `ProductDiscount` as hidden inputs on the PDP *and* on every product card, and the
  card wrapper emits `data-product-price` for analytics. A template money guard wraps OUTPUT and
  reaches none of them, and a tags-stripped census is blind to them by construction — which is how a
  fifteen-surface audit reports zero currency strings on a page delivering every price twice per
  product. The honest position is "not displayed"; the stronger claim means forking two shipped
  components. Relatedly, a bare currency-symbol `notContains` can never pass on a Swift list page,
  because the shipped `PriceRange` facet emits currency-shaped option labels for every visitor — anchor
  the census on the decimal and pair it with a byte floor.
- **New `fresh-deserialize-sweep.md`** (`dw-demo-swift`) — the prospect-visible fiction a baseline
  ships, swept BEFORE the demo path is built, precisely because none of it is on the demo path and it
  survives a rebrand that edits every page a build touches. Six families, including one that exists
  only in an ATTRIBUTE: the shipped logo template falls back to the vendor name when its name field is
  empty, so blanking the field — the natural rebrand action — restores the word. The sweep therefore
  runs over the raw served HTML, and the rebrand rule is **name every field, never blank one**. Also
  carries the default-currency check (symbol, culture, rate and patterns, asserted by a symbol being
  PRESENT) and the rule that a licence-gated surface is retired rather than demoed as a dead button.
- **New `rma-claims.md`** (`dw-demo-swift`) — a warranty, service or claims surface is the platform's
  own RMA machine renamed, never a parallel entity: the comment trail, the backend transition screen
  and the claim numbering come free, and only the vocabulary and two templates are data. Includes the
  serial-number column that exists with no frontend input, and the shipped `<BoughtFromDate>` that
  silently empties the claim form's order picker on any install that is not brand new.
- **The megamenu needs a PANEL-anchored apron** (`header-menu.md`, platform truth 4). Both documented
  bridges are unavailable there — the caret rules force the stock toggle pseudo to `position: static`,
  and megamenu items carry `.position-static` by design so an item-anchored pseudo cannot anchor — and
  the apron itself fails until `overflow: visible` is restored on the panel, because an auto-overflow
  box clips its own out-of-box pseudo-elements. The older "panel-anchored bridge rejected" line is
  corrected rather than left standing.
- **`ParagraphTemplate`, `ParagraphGridRowColumn` and `ParagraphModuleSettings` are not content
  fields.** `cache-invalidation.md` listed `ParagraphTemplate` under the one SQL pattern that needs no
  restart; all three are measured as needing one, and a module paragraph reads its settings once at
  application start, so a repoint commits and stays invisible with no error and nothing in the log.
  A SQL-written `ParagraphTemplate` also puts its paragraph on the never-whole-model-save list.
- **`AreaSave` writes `AreaDomainLock` wrong**, stringifying the model's boolean into the literal
  `"False"` in a column the URL builder reads as a host name — so every absolute URL for the new area
  points at `https://false:443/`. It rides in on the full-model round trip that the master-binding rule
  makes mandatory. Stated beside the existing `AreaDomain` repair as one rule: the columns `AreaSave`
  does not write correctly are repaired by SQL in the same step, and a green response is not evidence.
- **A customisation ban is scoped to the presales-demo context, and a lifted ban still owes the
  surface.** The payment-provider / checkout-handler ban now names the condition that lifts it (an MVP
  or delivery build whose signed scope names the mechanism), requires the brief to cite the ban it
  overrides, and states that where the corpus carries no recipe, writing one is part of the work.
- Smaller corrections in place: a headless create applies the item type's XML `defaultValue`, so a
  `ButtonEditor` field manufactures the exact bare-label string that aborts the whole paragraph at
  render; a cloned model posted with `id: 0` is not a create path; signing a second persona in over a
  live session transfers the cart and **persists it onto the new user's row**; Swift's checkout hides
  ALL delivery addresses when the user's own billing block is empty (a data gap, not a cache one); the
  shipped dashboard widgets carry no scope parameter at all, so an aggregate board needs alternate
  templates and a zero-orders persona to assert with; `PageHidden` breaks the page's own friendly URL
  while `Default.aspx?ID=n` still redirects to it, which is the diagnostic signature; field display
  groups leave the parent row empty after a successful save because the data lands in three child
  tables; and staging a theme's disk overlay does nothing until the area's `CustomHeadInclude` is
  wired, which the integrity sweep now asserts as a fourth stylesheet.

## [4.43.0]

Fold-back sprint: dw-search-indexing, dw-pim-modelling, dw-pim-localization, dw-demo-base and dw-demo-foldback. Twenty-eight demo-build learnings land the index-file authoring rules that are invisible through the API as one table, sharpen the PIM structural and localization references in their existing homes, and fold the demo-base host and fold-back rules; four supersede sweeps rewrite the scroll-width-only mobile assert, the multipart cart-form rule, the deserialize output-directory option and the governance-metric recommendation where they lived.

- **A `.index` file is authored on the filesystem, and every rule that matters there is invisible from
  the API.** `BuildIndex`, `IndexStatusesByRepository` and `FieldDefinitionBasesByRepositoryAndIndexName`
  all report a healthy index while a declared field is absent, so `dw-search-indexing` now carries one
  table of the authoring rules — `Field/@Source` is a database column while `Copy/@Sources` are index
  system names, a `Copy` field may carry `Analyzer` and `Boost`, `Skip*` settings sit on the `<Build>`
  nodes and are read at build time (no restart), an extension-declared field cannot be overridden from
  the file — plus the standing rule that an index schema is asserted against the Lucene directory,
  never against the API, and the negative fact that no backend free-text or wildcard search setting
  exists on this build.

- **The shipped user index carries a password hash and the whole impersonation graph in the same
  document.** Standing up a user repository writes one hash per account into a Lucene file under the
  web root, from the platform's own schema extender, with no switch; the same extender publishes
  `CanImpersonate` / `CanBeImpersonatedBy`, group-expanded and numeric, which makes a permission-scoped
  user picker one query arm. Both facts are stated together in `dw-search-indexing`, with pointers from
  `dw-users-permissions` where readers of a permission-scoping query actually look.

- **A repository `.query` gets its Lucene query shape from the right-hand side's declared `Type`, and a
  parameter set to the empty string is not an unset one.** A numeric field needs `System.Int32` /
  `System.Int32[]`; a string type against it matches nothing, silently, failing closed. A missing `Type`
  surfaces as `The given key '' was not present in the dictionary`, and `IsIndexed=False` on a stored
  document is not a diagnostic. Separately, an unset parameter drops its arm while an empty one is
  compared and matches nothing — so a caller assigns only the parameters it has a value for.

- **A field declared in the index schema is not thereby queryable.** Custom product fields arrive as
  stored payload and no `Field` or `Copy` declaration makes them filterable; a field the builder
  populates for only some documents produces a sort that works in one direction and looks inert in the
  other; and `IsEmpty` has no working serialization on the Lucene provider, so "this field has no
  value" is expressed positively (a sentinel, or a real value on every document) or not at all. The
  complementary-count check that catches all three is restated where each lands.

- **Say what actually triggers a rebuild.** `ShopAutoBuildIndex` does not fire for a product written
  through the Management API or an MCP tool, so the promise is a scheduled Update build, not a
  save-triggered one. The MCP index tools default `indexName` to a name the repository does not carry
  and then succeed vacuously; pass the index file name, and gate on the document count rather than on
  `completed: true`.

- **PIM structural facts that no read surface reports**: `EcomGroups.GroupType` is the only thing
  separating the data-model tree from the catalogue tree and the MCP group reads omit it, so a
  group-tree cleanup reads it first; `ProductId` is a 30-character column while `ProductNumber` is 255,
  with nothing validating the difference before a bulk import; a per-location attribute has no home
  outside `EcomStockUnit`; asset categories are `EcomDetailsGroup` with two shipped rows, so a
  document's type comes from its own name; and the standard fields `get_standard_fields` lists are
  `EcomProducts` columns that the MCP custom-field path cannot write — the reachable write is a
  `ProductById` → `ProductSave` round trip.

- **"Falls back to the default language" means that one layer and no other.** Translation rows stranded
  under a non-default layer are invisible rather than fallen back, so they are authored under the live
  default language; and a missing translation is never an error — one view model returns the system
  name and another returns the raw id, which makes the delivery API unusable for verifying an
  asset-category translation.

- **Demo-build gates that passed while the thing they guard was broken.** A serializer dry run's entry
  count is the blast radius, not a count, because deserialize is driven by the manifest under
  `SerializeRoot` and ignores the config's predicates and `outputDirectory` — scoping a run means
  swapping the manifest, with a byte-for-byte unstage assertion. A mobile overflow check comparing
  `scrollWidth` to `innerWidth` cannot fire once unshrinkable content has widened the layout viewport,
  so `innerWidth` is asserted against the requested width as well. A PII sweep runs over the rendered
  corpus as each persona, because orders keep their own copy of the customer identity. A form probe
  matches the rendered form's `enctype` instead of assuming multipart. And a scripted edit asserts a
  non-zero diff, with line-wise patterns written `[^\r\n]*\r?\n` against CRLF layer text.

- **Two demo-host hazards**: a restored database routinely carries orphaned shop/group relation rows
  that no surface reports and that make a group audit unreadable — a standing post-restore query now
  catches them; and a package the host csproj already references must be upgraded there, because an
  Add-in-manager install of the same package duplicates type keys and takes the whole site down.

justdynamics/Truvio.Commerce.Foundry#644, justdynamics/Truvio.Commerce.Foundry#672,
justdynamics/Truvio.Commerce.Foundry#674, justdynamics/Truvio.Commerce.Foundry#675,
justdynamics/Truvio.Commerce.Foundry#681, justdynamics/Truvio.Commerce.Foundry#695,
justdynamics/Truvio.Commerce.Foundry#714, justdynamics/Truvio.Commerce.Foundry#715,
justdynamics/Truvio.Commerce.Foundry#721, justdynamics/Truvio.Commerce.Foundry#727,
justdynamics/Truvio.Commerce.Foundry#740, justdynamics/Truvio.Commerce.Foundry#761,
justdynamics/Truvio.Commerce.Foundry#762, justdynamics/Truvio.Commerce.Foundry#763,
justdynamics/Truvio.Commerce.Foundry#765, justdynamics/Truvio.Commerce.Foundry#766,
justdynamics/Truvio.Commerce.Foundry#771, justdynamics/Truvio.Commerce.Foundry#783,
justdynamics/Truvio.Commerce.Foundry#787, justdynamics/Truvio.Commerce.Foundry#803,
justdynamics/Truvio.Commerce.Foundry#804, justdynamics/Truvio.Commerce.Foundry#879,
justdynamics/Truvio.Commerce.Foundry#899, justdynamics/Truvio.Commerce.Foundry#900,
justdynamics/Truvio.Commerce.Foundry#904, justdynamics/Truvio.Commerce.Foundry#945

and the stage/unstage recipe; the engine ask — honour `outputDirectory` on the deserialize path, or
hard-fail when manifest entries are not accounted for by the config predicates — stays with the
serializer), justdynamics/Truvio.Commerce.Foundry#728 (skill half: the `innerWidth` assertion and the
vertical-navigation rule; the harness probe change and the layer fix stay with their owners)

## [4.42.0]

Fold-back sprint: dw-integration-framework, dw-integration-erp and dw-demo-erp. Forty demo-build learnings give the integration framework its first references (the job-file format, destination-side provider behaviour, custom provider authoring), add feed keying to the ERP skill and a two-way mock recipe to the ERP demo skill, and rewrite three measurably wrong claims in the mock-deltas reference.

A Data Integration activity is a file on disk with a frozen schema snapshot, and the shipped
providers each lie about something specific on the way in.

- **`dw-integration-framework` gets a `references/` directory** — it had none, while being the
  emptiest target for the largest issue cluster. Three files: `job-file-format.md` (the on-disk
  activity), `provider-behaviour.md` (what each shipped provider does when it writes), and
  `custom-provider-authoring.md` (the C# material lifted out of SKILL.md, which was over the
  16 KB activation budget). SKILL.md becomes the nav layer with a "Where to find things" table.
- **The job file is the authoring surface nobody documented.** An activity is
  `<wwwroot>/Files/Files/Integration/jobs/<name>.xml` — the doubled `Files\Files` is the archive
  root keeping its own leading segment, so a stored `/Files/X` path is served at `/Files/Files/X`
  and a single-`Files` URL 404s. The file name **is** the activity name a scheduled task binds to;
  `Files/System/Integration/Jobs/` is a shipped-template decoy; the file is UTF-16LE with a BOM, so
  every scripting stack's default UTF-8 write produces a file the runner will not read (and a naive
  `grep` over one is a false clean). The recipe is copy-an-existing-job, decode with a `utf16le`
  codec, round-trip, diff against the source, and re-mint the `<mapping uid>` GUID.
- **A job's `<Schema>` is a cached snapshot, and the failure mode differs by side.** A column added
  after the job was saved is **silently dropped** on the source side and a **hard refusal** on the
  destination side, so every activity on a solution goes stale the moment a custom product or order
  field is created. `does not exists in the schema` now reads as a stale snapshot first, not a
  mapping typo. A SqlProvider job with no authored `<Schema>` expands the entire database into its
  own definition on first run and then validates against that.
- **Two column element shapes, distinguishable only by which end they are on.** A SQL destination
  writer casts every schema column to `ProviderHelpers.SqlColumn`; a SqlProvider source reader does
  not cast at all, so the plain `Integration.Column` form makes the same file half right and the
  `InvalidCastException` points at the destination table instead of the schema. `<limit>` is a
  character count.
- **The shipped providers' destination behaviour, measured.** `EcomProvider` matches on
  ProductId → ProductNumber → ProductName, mints `ImportedPROD<n>` ids for anything it creates
  regardless of the `CreateMissing*` flags, orphans category field values on an in-place re-key,
  clears the primary-group flag on multi-group products every run, requires the whole ten-column
  price identity for `EcomPrices` or throws a `KeyNotFoundException` after the temp tables have
  loaded, and rewrites every language row of a group in its `EcomGroups` merge. `UserProvider`
  writes five tables, expands a 255-character group CSV additively, and **silently deletes**
  unresolved address and impersonation rows while reporting Completed. `OrderProvider` as a
  destination is update-only (its INSERT lists only the mapped columns) and copies the integration
  id straight into the line's parent key; as an export source its cart filter does not exclude
  ledger entries, so imported invoices are posted back as sales orders.
- **A write through a provider is not automatically a cache invalidation.** An `EcomProvider` run
  writing extended or global product fields leaves the `ProductService` read-through cache stale
  even with `DisableCacheClearingAndIndexUpdates=False` — new row in
  `dw-data-access/references/cache-invalidation.md`, with the storage type name the API accepts.
  And a state written by a job (or by SQL) raises **no** order-state notification: those fire on
  `OrderService.Save` only, so "the ERP flips the status and the customer is emailed" is code.
- **Job files are served anonymously.** `.xml` is not on the static-file blocklist, so a
  SqlProvider connection string is a database password on a public URL — and DW re-serializes the
  job on every run, so a hand edit does not hold. Integrated security (`*ServerSSPI`) is the fix;
  the empty-connection-string fallback is **destination-only**, so a SQL *source* must name an
  instance (relatively, if it is local). The legacy `JobRunner.aspx` route executes any job on an
  anonymous GET and the modern authenticated route 404s on affected builds; the only mitigation is
  an IIS path restriction, unavailable on a shared host.
- **Restores and resets built on activities need an order and a marker.** Purge the entities the
  session created **before** restoring tables — the delete half of delete-rows-missing-from-source
  is unreliable while a parent is live, and the log counts rows written, never rows removed. Scope
  every reset by a marker column the generator stamps, and **never null an integration key**: it is
  the already-processed flag, so clearing it re-arms the integration for every row touched.
  SqlProvider round trips also truncate datetime to whole seconds and stage into a clone whose
  unique indexes lose their filters.
- **`dw-integration-erp` gains `references/feed-keying.md`** — the key contract that was entirely
  undocumented: map the ERP's natural key to `ProductNumber` to update a hand-built catalogue in
  place, decide on source-derived ids before the first load, keep group names byte-exact because
  they are the matching key, and apply the three casing fixes the shipped order-export template
  needs (plus the unit-price column that arrives empty).
- **`dw-demo-erp` gains a two-directional mock flavor** (`references/two-way-mock.md`): four
  shipped-provider activities, `OrderStateAfterExport` for the status flip, `OrderIntegrationOrderId`
  for the document-number writeback, staging tables seeded from live rows so the sync is
  value-idempotent, and a reset that does not re-arm the export. Zero custom code, zero
  customisations-ledger rows.
- **Two corrections in `dw-demo-erp/references/mock-deltas.md`.** `RunSqlScheduledTaskAddIn` has
  been measured binding, firing, logging `Run returned: True` and executing no SQL at all, so it is
  demoted below the activity route and no longer treated as self-evidencing. And a far-future
  `TaskNextRun` is **not** a kill switch: DW fires overdue tasks at application start, so a task
  carrying a realistic minute/hour pair self-fires on any pool restart — every schedule column goes
  to `-1` and the cadence lives in the name and a staged execution history. The scheduler-cache
  rule is broadened from SQL-inserted rows to **every** SQL write to the schedule, inserts and
  updates alike.
- **`dw-demo-erp/references/erp-data-shape.md`**: when a rule needs a fact the feed does not carry,
  add the field at generation time. A correlated proxy (range derived from stock quantity) produces
  a plausible-looking result and breaks silently on exactly the rows where the two facts diverge.

justdynamics/Truvio.Commerce.Foundry#655, justdynamics/Truvio.Commerce.Foundry#656,
justdynamics/Truvio.Commerce.Foundry#657, justdynamics/Truvio.Commerce.Foundry#658,
justdynamics/Truvio.Commerce.Foundry#661, justdynamics/Truvio.Commerce.Foundry#662,
justdynamics/Truvio.Commerce.Foundry#692, justdynamics/Truvio.Commerce.Foundry#696,
justdynamics/Truvio.Commerce.Foundry#697, justdynamics/Truvio.Commerce.Foundry#698,
justdynamics/Truvio.Commerce.Foundry#699, justdynamics/Truvio.Commerce.Foundry#700,
justdynamics/Truvio.Commerce.Foundry#701, justdynamics/Truvio.Commerce.Foundry#702,
justdynamics/Truvio.Commerce.Foundry#708, justdynamics/Truvio.Commerce.Foundry#709,
justdynamics/Truvio.Commerce.Foundry#710, justdynamics/Truvio.Commerce.Foundry#729,
justdynamics/Truvio.Commerce.Foundry#730, justdynamics/Truvio.Commerce.Foundry#731,
justdynamics/Truvio.Commerce.Foundry#732, justdynamics/Truvio.Commerce.Foundry#735,
justdynamics/Truvio.Commerce.Foundry#736, justdynamics/Truvio.Commerce.Foundry#754,
justdynamics/Truvio.Commerce.Foundry#826, justdynamics/Truvio.Commerce.Foundry#827,
justdynamics/Truvio.Commerce.Foundry#828, justdynamics/Truvio.Commerce.Foundry#829,
justdynamics/Truvio.Commerce.Foundry#831, justdynamics/Truvio.Commerce.Foundry#876,
justdynamics/Truvio.Commerce.Foundry#882, justdynamics/Truvio.Commerce.Foundry#892,
justdynamics/Truvio.Commerce.Foundry#893, justdynamics/Truvio.Commerce.Foundry#918,
justdynamics/Truvio.Commerce.Foundry#921, justdynamics/Truvio.Commerce.Foundry#922,
justdynamics/Truvio.Commerce.Foundry#923, justdynamics/Truvio.Commerce.Foundry#926

## [4.41.0]

Fold-back sprint: dw-commerce-orders and dw-commerce-catalog. Forty-seven demo-build learnings land as a routed reference set: the RMA and claims surface (previously uncovered), the measured cart-command contracts (the SKILL.md tables described behaviour the platform does not have), checkout configuration, order states and quotes, order notifications, customer-center surfaces, and catalog listing and stock. The SQL-then-API-save ordering is stated once with both measurements.

- **`dw-commerce-orders` is now a routed reference set, not one growing file.** The single 32KB
  `order-lifecycle.md` covered order seeding and saves and nothing else, so every cart, checkout,
  RMA, state-machine and notification learning had no home. Split into
  `cart-commands.md`, `checkout-configuration.md`, `order-states-and-quotes.md`,
  `order-notifications.md`, `customer-center-surfaces.md` and `rma-and-claims.md`, with a
  "Where to find things" routing table in `SKILL.md`; `order-lifecycle.md` keeps seeding, saves,
  invoices, subscriptions, the read surface and CSR impersonation.

- **The RMA / claims surface is documented for the first time.** Which of the three creation
  surfaces writes what (MCP `create_rma` produces a backend-only stub; Admin API `RmaSave` binds an
  empty `Model.Id` and the singular `OrderLineId`; the frontend `addrma` is the complete model and
  the only route that raises the mail), why the customer-center list INNER JOINs the comment and
  order-line tables so a commentless RMA can never appear, that a state rename is three writes
  across two stores plus the backend default-name column, that the API and the frontend write
  different empties into the same column, that every save of an existing RMA logs a customer-block
  comment into the customer-visible history, and the `ReturnMerchandiseAuthorizationService` flush
  every raw-SQL write owes. The customer-center RMA app is ViewModel-driven while the only shipped
  templates are DW9 tag templates, and it is the one app in the family that ignores
  `RetrieveListBasedOn`.

- **Cart commands say what they do, replacing a table that said what they sound like.** `archive`
  clears the active-cart pointer and archives nothing (model archiving as a cart-flow order state);
  `copyExtended` copies the session's active cart and ignores `CartId` — which makes the shipped
  saved-carts link a live defect — and is the only ownership move; `setcart` selects a cart and
  never transfers it, leaving two users pointing at one; `createnew` needs `SetActive`; `setname`
  writes `OrderDisplayName`; `setmulti` SETS quantities, deletes at zero and is last-row-wins for a
  duplicate product. Plus the two gates every scripted cart proof must pass (the bot User-Agent
  refusal that still mints the cart, and the pre-command 301), the redirect that drops the whole
  querystring, the unchecked `AccessUserCartId` adoption that leaks a cart across users, and the
  fact that rendering the cart page persists the order header.

- **Checkout configuration gets the data-side contracts a checkout needs before it can complete.**
  Method country binding (a cart delivering outside the relation set gets zero options, no error
  and no empty state, with payment masking it), the two legal `feeRulesSource` values and the
  flat-rate recipe, the payment radio whose posted name drops a syllable the element id carries,
  validation groups (no admin UI, the hand-written row contract, a dangling reference that
  validates nothing, and the rule that a field gates the step it is posted on), the 1970 sentinel
  on unset date order fields, saved cards as service-only because the checksum hashes the identity
  the INSERT assigns, and the global setting that makes the zero-value add-a-card journey possible.

- **Order-LINE fields need no storage column, and the `EcomOrderField` trap does not generalise.**
  Values live in the `OrderLineFieldValues` blob already present on every line, so adding one is a
  row rather than a maintenance window — but the definition is inert without a shop/group relation
  row, and the entry is materialised at line-creation time, so a line that predates the relation can
  never take a value.

- **The SQL-then-save ordering is stated once.** A raw write to a DW-cached table is not merely read
  stale: the next save of the cached entity writes the whole entity back and destroys it, silently
  and at an unpredictable later moment. The working sequence is UPDATE, flush the owning service
  with `CacheInformationRefresh`, then touch — proven on both sides, by a staged value erased
  without the flush and by a bulk column repoint that survived with it.

- **Order states, removal and the cart/quote conversion.** `delete_order_state` leaves dangling
  transition rows and the id generator re-issues a freed id into any flow, so a two-ended LEFT JOIN
  integrity assertion is mandatory whenever states are touched; `OrderDelete` is a soft delete that
  refuses completed orders, and `OrderCancel {Id}` then `OrderDelete {Ids}` is the working pair
  (note the singular/plural key split); `UpdateCartToQuote` leaves `IsCart` set and
  `DowngradeToCart` renames the original order and inserts a copy under the old id, so any
  bookkeeping row keyed on the order id must be written against the pre-call id. Swift 2's
  Accept-quote button loads its modal from an endpoint that refuses any order that is not a cart,
  so it can never work on a quote.

- **Notification mail: three settings, three resolution roots, and an artefact that under-reports.**
  The order-state template is a bare file name under one fixed folder, the RMA template resolves at
  the Templates root, and the cart app's `Mail1Template` is design-relative — and when
  `Mail1Template` is empty the body is a *page*, leaving the shipped mail template as dead code that
  grep cannot distinguish from the live one. A template that will not load is mailed to the customer
  rather than aborting the send, cart-flow states notify exactly like order-flow states, and the
  honest assertion surface on a black-hole SMTP host is Queue UNION Badmail, on content.

- **`dw-commerce-catalog` gains a listing-and-stock reference.** Any default sort on the catalog
  paragraph or the query replaces search relevance (and the header search shares that paragraph), so
  group listings are ordered with `UseGroupSortInGroupContext` and scaffolding is hidden with
  `ProductExcludeFromIndex`, never with a sort or a root `GroupID` default. `ProductHidden` is
  enforced in the entity SELECT, absent from the index and unwritable by every DW10 API, so a
  listing counts hidden products and renders none — assert rendered rows equal the header count.
  Plus the `AssetCategories` double-listing, what order completion decrements in the two stock
  tables (it follows the stock location on the line, so assume both move and make the inbound sync
  own both), and the `0`-not-`NULL` stock-location convention on unscoped price rows.

## [4.40.0]

Fold-back sprint: the three render skills. Eighteen demo-build learnings land as two new dw-render-razor references (the template compile contract and the paragraph-as-endpoint response contract), a view-model traps reference, a tag-contexts reference, and one rewrite of the stylesheet cache-buster guidance that was wrong rather than incomplete.

- **A Razor template compiles warnings-as-errors at render time, so every compile message is a hard
  render failure.** New `dw-render-razor/references/template-compilation.md` collects everything that
  decides whether a template compiles and which template a request reaches: the symptom table for an
  `[Obsolete]` call site and the current substitutes on DW 10.28.x, the `@using` rule for extension
  methods, which helpers exist on `ViewModelTemplate<T>` versus the classic tag base (`GetGlobalValue`
  and `@Html.Raw()` are absent, with the substitutes that work), `@Include` inlining every partial
  into one compiled scope, and the `RenderPartial<T> : ViewModelBase` constraint with the three-rule
  recipe for sharing one file across both template families. Previously these surfaced one compile
  error at a time, each of which reads as a caching problem because the error page dumps the
  generated listing and names the file nobody edited.

- **`ParagraphTemplate` paths are fully qualified, because a relative path resolves against
  `/Files/Templates/` and its miss is an HTTP 200 with English prose in the layout.** The failure is
  invisible to every metric a storefront gate uses — status code, `dw-error` count, byte size — so
  the same section tells a reader to grep the served markup for `Template file not found`.

- **The paragraph-as-endpoint pattern now has a response contract.** New
  `dw-render-razor/references/paragraph-endpoints.md` is one ordered recipe plus one table:
  `PageClean` + `?ParagraphID=` addressing, keeping the endpoint out of the host page's composition
  with an inactive grid row (MCP `save_grid_rows`) so the page's own response is unchanged, resolving
  the endpoint by item type instead of by navigation tag, and what reaches the wire —
  `Response.StatusCode` yes, `Response.AddHeader` yes, `Response.ContentType` no (the page pipeline
  stamps `text/html` over it), `BinaryWrite` never (synchronous IO is disallowed under the in-process
  IIS host), `Response.Clear()` inert. With delivery shapes that do work (attachment header, base64
  data URI) and the parsing libraries already in bin — EPPlus, MiniExcel, CsvHelper — which make a
  spreadsheet parse free of a deploy. No PDF renderer ships in bin.

- **Surface rung named where SQL is the pull.** `UPDATE Page SET PageNavigationTag = …` leaves
  `GetPageIdByNavigationTag()` returning `0` until the app pool recycles, is local-install only, and
  owes a host restart; the item-type paragraph lookup is cache-fresh and owes nothing, so it is the
  folded recipe and SQL appears only as the rung that does not reach the operation.

- **A template guard decides what is drawn, not what is allowed.** A Dynamicweb app handles its POST
  before its template renders, so a Razor-rendered refusal is a UI affordance; the test that tells
  the two apart is a scripted POST in the same session with a before/after read of the protected
  value, never a re-read of the page. Under impersonation, `Pageview.User` is the effective user and
  cannot see the condition at all — `UserContext.Current.ImpersonatingUser` is the real identity.
  Paired with the notification subscriber that is the rule which holds.

- **`Context.Current.Items["ProductDetails"]` is the last product *rendered* in the request, not the
  page's product** — so it is populated on a list page too, and `product != null` is not a test for
  "this is a PDP". Branch on the page's own item type or an explicit view parameter.

- **View-model properties that are nullable, and properties whose name is not their meaning.** New
  `dw-render-viewmodels/references/viewmodel-traps.md`: `DefaultImage` and `Price` are nullable, and
  in a template that loops the blast radius is the whole surface rather than the one row — one
  image-less product replaces a catalogue with a `dw-error` dump at HTTP 200 with the chrome intact,
  which a status-and-byte-count gate cannot see. Names the two shipped Swift 2.2 templates that
  dereference `product.DefaultImage.Value` unguarded. Plus `MediaViewModel.Name` holding the detail
  id while the friendly `EcomDetails.DetailsName` surfaces as `DisplayName`, and `StockLevel` being a
  label rather than a quantity — a contradiction the skill's own example carried, now corrected.

- **`AddStylesheet` appends the site's own token after any query string the caller supplied.** The
  guidance in `razor-surfaces-and-pitfalls.md` §3 is rewritten rather than annotated: the site token
  can be static across edits, deploys and restarts (observed 10.25.x through 10.28.x), which is why
  an explicit `?v=` buster is needed at all, and the resulting double `?` in the emitted URL is
  cosmetic — it serves 200 and does bust the cache.

- **Tag names get proved from their renderer, because a blank table is not an unpopulated context.**
  New `dw-render-templatetags/references/tag-contexts.md` carries the full RMA notification-email tag
  set, whose prefix is `Ecom:Rma.` (mixed case — the only prefix on the platform that is not the
  upper-cased entity name), whose order id is `OriginalOrderId` (derived from the first RMA order
  line; `EcomRmas` has no order column) and whose status splits into `State` and `StateName`. It also
  names the two things the renderer does not give a template, which still need a subscriber on
  `Ecommerce.Rma.BeforeRmaEmailSend`. This corrects an earlier reading that the context was
  unpopulated.

- **A tag inside a loop may carry the parent entity's value.**
  `Ecom:Cart.ShippingMethod.Price` in Swift's `Shippingmethods` loop is the order's shipping fee,
  identical on every row, and there is no per-method price tag at all. Invisible on a stock install
  where every fee is zero and every row reads "Free"; the first non-zero fee makes every method
  display the selected method's price. With the template-side fix and the general test for any
  in-loop tag.

- **Reference hygiene.** `razor-surfaces-and-pitfalls.md` crossed the 20 KB reference ceiling, so its
  `ViewModelTemplate<>` pitfalls section moved wholesale into `template-compilation.md` and the two
  demo-skill routing rows that pointed at it were repointed. Duplicated worked examples in the two
  render SKILL.md bodies were replaced with pointers to the reference files that already carry them,
  bringing both back inside the 16,000-character activation budget.

justdynamics/Truvio.Commerce.Foundry#750, justdynamics/Truvio.Commerce.Foundry#776,
justdynamics/Truvio.Commerce.Foundry#784, justdynamics/Truvio.Commerce.Foundry#799,
justdynamics/Truvio.Commerce.Foundry#800, justdynamics/Truvio.Commerce.Foundry#844,
justdynamics/Truvio.Commerce.Foundry#848, justdynamics/Truvio.Commerce.Foundry#850,
justdynamics/Truvio.Commerce.Foundry#868, justdynamics/Truvio.Commerce.Foundry#877,
justdynamics/Truvio.Commerce.Foundry#878, justdynamics/Truvio.Commerce.Foundry#880,
justdynamics/Truvio.Commerce.Foundry#881, justdynamics/Truvio.Commerce.Foundry#886,
justdynamics/Truvio.Commerce.Foundry#894, justdynamics/Truvio.Commerce.Foundry#909

## [4.39.0]

**Correction, same release: Dynamo is MCP-only, and the boundary is now mechanical.** The in-product agent that loads `manifest.json` acts through the MCP tool set and read/write under `Files/`, and through nothing else — no Management API, no serializer, no SQL, no shell, no git, no browser, no host restart — so the first cut of this release told twenty in-product skills to drop to a rung that does not exist there, and gave headless installs and Dynamo one shared table column. The per-instance-type table now gives Dynamo its own column (MCP the only action surface; Management API, serializer and SQL absent; `Files/` read-write present; the admin UI named, never driven; asking the user the only fallback) and leaves headless with every rung. The `dynamo: true` boilerplate is MCP-only: when no tool covers the operation, stop and tell the user which admin screen performs it. `dw-data-access` (it ships PowerShell and is a ladder-and-SQL reference) and `dw-headless-delivery` (a `/dwapi/` catalog for a frontend built outside the product) flip to `dynamo: false` and leave the manifest; the two in-product facts the flip would have cost — success is not proof, and which writes owe a rebuild — become the new `dw-data-write-effects` skill, in MCP terms only. Six per-area `recipes-*.md` skeletons in `dw-data-access` give the out-of-product recipes a home for the folds that follow, `dw-skill-authoring` and `dw-demo-foldback` state the rule, and `scripts/validate-skills.py` enforces it against `scripts/dynamo-baseline.json` — a per-file ratchet over the pre-existing backlog, so no `dynamo: true` file may gain a non-MCP instruction.

Contract change: the ladder of surfaces into an instance (MCP tools, Management API, serializer, direct SQL) gets one foundational owner, every skill's no-MCP paragraph names the next rung instead of stopping, and naming the surface becomes an authoring and fold-back gate.

- **The ladder of surfaces into a Dynamicweb instance has one foundational owner, and every reader can reach it.** `dw-data-access/SKILL.md` gains `## Surfaces into a Dynamicweb instance — the action ladder`: four ranked rungs (1 MCP tools `snake_case`, 2 Management API `PascalCase` at `/admin/api/...`, 3 serializer layers, 4 direct SQL — last resort, local installs only), a per-instance-type table saying which rungs exist on a local, hosted and headless/Dynamo install, and the rules that hold at every rung (the admin UI is a rung-2 client and verification only; a verb-registry negative proves a verb absent, never a capability absent; capture the admin UI's own HTTP call read-only and replay it; success is not proof; API writes first, SQL last, nothing re-saves afterwards; never SQL-clone a structural tree). The serializer is on the ladder for the first time, with the rule that a layer beats a long MCP or API loop when the write is bulk or ids must survive. `dw-data-access` is `dynamo: true`, so the ladder now ships in `manifest.json` — previously the only complete statement lived in a demo skill that Dynamo never loads. The existing in-process section is renamed `## In-process C#: Service API vs the Database class` so its scope is unambiguous.

- **"No MCP" no longer means "do nothing".** The `## Without MCP` (15 skills) and `## MCP preflight` (13 skills) boilerplate now names the next rung down — the Management API reaching the same domain services, the serializer for bulk id-preserving loads — states that direct SQL is local-install only and owes a flush or restart, and links to the owner section. Demo skills keep their preflight and gain the link plus a pointer to the demo deltas. `dw-setup-cli`'s `dw command` + `CommandByName` rung is reconciled as a CLI transport of the Management API, not a fifth surface.

- **The demo documents keep only their deltas.** `dw-demo-pim/references/access-surfaces.md` no longer sells four co-equal surfaces to be picked by whichever is fastest, and no longer recommends SQL for structural fixes: it is now the PIM-specific application of the ladder (which rung owns which PIM operation, structural fixes stay on rungs 1-2, the filesystem is a different store and owes a `BuildIndex`) and links up. `dw-demo-base/references/surface-priority.md` keeps the two-phase model, the scaffold-phase bootstrap one-clicks, the Browser MCP scope, the long-form SQL-cloning detail and the silent-no-op round-trip rule, and points its build-phase rule at the owner instead of restating it.

- **Naming the surface is now a contract, checked twice.** `dw-skill-authoring` "Writing the instruction body" states the convention: MCP tools `snake_case` in backticks, Management API commands `PascalCase` in backticks with the route on first use, serializer by command or by layer and mode, SQL labelled `SQL` in a fenced block; "verb" is reserved for Management API commands and "tool" for MCP; a table mixing surfaces carries a `Surface` column; every SQL recipe states why not a higher surface, local installs only, and the flush or restart it owes. `dw-demo-foldback` gains Step 1b.6 (surface-naming sweep) and the matching verification-gate line, so a fold that leaves a recipe surface-less does not pass.

- **Locality sweep.** Per-recipe "SQL last resort" notes that carried no hosting qualifier now say `(local install only)` inline — `modelling-discipline.md`, `permission-layers.md`, `backend-mcp-server.md`, the demo build command and `visual-qa.md` — and the Direct SQL row of `cache-invalidation.md` "Surface scope" states the rung and the local-only rule. The 35 SQL recipes themselves are unchanged here; the per-cluster folds carry them.

## [4.38.0]

The Truvio Commerce rebrand, and the install rule it broke: an AppStore app is installed from the
AppStore, never from a remembered NuGet id.

- **The Backend MCP is now `Truvio.Commerce.MCP`** (AppStore app "Truvio Commerce MCP"), formerly
  `Dynamicweb.MCP`. The pre-rename id still resolves on nuget.org, so an agent writing the id it
  remembers gets a green restore, a green build and a **stale AddIn with no error to react to** —
  the exact failure this release exists to prevent. `/admin/mcp` is unchanged.
- **`backend-mcp-server.md` §1 is inverted.** Was "NuGet `PackageReference` (default), AppStore (last
  resort)"; is now **AppStore first**. A hand-written `<PackageReference>` for an app the AppStore
  carries (Backend MCP, PIM for Business Central connector, `StaticLinkManager`) is a defect. The
  csproj route survives as an **escape hatch that requires an explicit user choice**: report which
  AppStore route failed, state that **the AppStore version could not be resolved**, name the id and
  version proposed and where they came from (a live resolve or the user, never memory), then wait for
  a yes. An existing `Dynamicweb.MCP` reference in a host csproj gets removed.
- **New `install-anatomy.md` §6, "Package naming after the rebrand, and the AppStore boundary"** —
  the platform-level home for both rules. Old §6/§7 renumber to §7/§8; the three cross-references in
  `dw-demo-base/references/scaffold.md` follow.
- **Repo-wide terminology rule** in `CLAUDE.md` ("Product naming") and `dw-skill-authoring`
  ("Naming"): the product is **Truvio Commerce (powered by Dynamicweb)**; the rebrand renames product
  prose only. Namespaces, `Dynamicweb.Suite`, admin paths, `/dwapi/`, DB tables, `GlobalSettings`
  keys, `dw-*` skill names, `dynamicweb-*` bundles, `doc.dynamicweb.dev` and `github.com/dynamicweb`
  all keep "Dynamicweb". Newly published packages carry `Truvio.Commerce.*`. **Never write a package
  id, app name or version from memory.**
- **Reflection snippets stop hardcoding the assembly name.** `backend-mcp-server.md` §4 and
  `dw-extend-csharp-api` now resolve the MCP assembly out of `AppDomain.CurrentDomain` matching either
  id, and find the type by full-name suffix — correct before and after the rename.
- Call sites updated: `dw-demo-base` (`scaffold.md` §2.1, `surface-priority.md` scaffold phase,
  `mcp-setup.md` preamble + triage row), `dw-extend-mcp-tools/SKILL.md`, `dw-setup-install/SKILL.md`,
  and `dw-extend-providers/references/addin-lifecycle.md` (the rule generalized to all AppStore AddIns).
## [4.37.0]

New `dw-extend-admin-ui` skill: extending the administration interface from your own assembly.

- **Nothing in the repo covered building admin screens in C#.** `ScreenInjector`,
  `ListScreenBase`, `EditScreenBase`, `OverviewScreenBase`, `IIdentifiable`,
  `NavigationNodeProvider` and `NavigationSection` had zero occurrences across all 43 skills. The
  two files whose names suggested otherwise cover something else: `dw-demo-swift`'s
  `admin-ui-authoring.md` is about authoring content *through* the admin and the Management API,
  and `dw-demo-pim`'s `screen-authoring.md` is about configuring screens that already exist. This
  skill is the missing piece: writing new ones.
- **`references/screen-anatomy.md`** holds compile-verified skeletons for all three screen types
  and the `IIdentifiable` round-trip — the string a row hands out has to survive being parsed back
  into a key, or the row opens onto nothing.
- **`references/injectors-and-navigation.md`** covers adding to an area tree, an Actions menu and a
  screen you do not own, each with its silent-failure mode: a node action missing `.With(query)`
  renders "No results found" with no error, and an `ActionGroup` given only a `Title` renders
  dimmed and inert.
- **The routing decision comes first.** Subclassing a core screen compiles, deploys and never
  renders. Step 1 decides between your own screen, an injector, an action-menu entry and a custom
  `ScreenType` before any code is written.
- **`mcp: none`, `dynamo: false`, `type: flow`** — matching `dw-extend-mcp-tools`, the sibling whose
  situation is the same: the steps build a project, so they need a csproj, a shell and a browser,
  none of which Dynamo has. `manifest.json` is unchanged at 29 skills.
- Verified end to end on a live 10.29.1 solution: all three screen types, an area and tree node, a
  node injected into an existing Content tree, and an entry injected into an existing Actions menu.
- Registered in `dynamicweb-backend`.

## [4.36.0]

New `dw-setup-cli` skill: the fourth member of the Setup pillar (install, CLI, config, upgrade).

- **`dw-setup-cli` covers operating a solution with the `dw` CLI** — installing `.dll`/`.nupkg`
  add-ins, uploading and updating Files-archive content, exporting the archive, triggering a recycle
  through `System/CloudHosting/recycle.txt`, and the verification steps that matter. API-key auth
  only; `dw login` is unavailable on `*.dynamicweb.cloud`.
- **The recurring theme is that every layer reports success while failing silently.** A `dw files`
  import without `-o` skips the file and 1.1.2+ prints no API response to reveal it; `dw install`
  reports success whether or not the assembly loaded. The skill treats reading the state back as
  mandatory rather than optional.
- **`references/cli-versions.md` records what changes between 1.0.16, 1.1.2 and 1.1.3.** Three
  behaviours differ in ways that bite: before 1.1.3 `dw query`/`dw command` appended `&api-key=` to
  the request URL and printed it on failure, `dw --version` guessed from the working directory (so
  inside a Node project it reported *that* project's version), and `dw swift` died with
  `spawn npx ENOENT` on Windows on any current Node. All three are fixed in 1.1.3.
- **`dw-setup-upgrade` hands over its CLI snippet.** It keeps `dw env` and the `.bacpac` export,
  which are upgrade-specific, and routes template and add-in work to the new skill so there is one
  owner rather than two partial ones.
- **`mcp: none`, `dynamo: false`** — consistent with its three Setup siblings; the skill needs a
  shell, which Dynamo has no surface for, so it stays out of `manifest.json`.
- Registered in `dynamicweb-setup`. Worth considering for `dynamicweb-backend` and
  `dynamicweb-developer` as a separate bundle re-balance.

## [4.35.0]

Dynamo visibility: the manifest stops offering skills an in-product admin cannot act on.

- **New `dynamo: true | false` frontmatter field on every skill.** Since Dynamicweb.MCP
  0.4.4 Dynamo fetches `manifest.json` from this repo and offers every row to an admin
  working inside a running install. It took all 42 skills, demo scaffolds included. Dynamo's
  surface is the MCP tool set plus read/write under `Files/`: no shell, no SQL, no git, no
  browser, no csproj. A skill whose steps need one of those is now `dynamo: false`.
- **`scripts/build-manifest.mjs` omits `false` rows entirely**, so `manifest.json` drops from
  42 to **29 skills**. No MCP-side change is needed; the manifest is generated here. A missing
  field means visible, so a new skill is never silently dropped.
- **`scripts/validate-skills.py` requires the field** to be present and `true`/`false`.
- **13 skills marked `dynamo: false`**: the demo chain (`dw-demo-base`, `-pim`, `-swift`,
  `-headless`, `-erp`, `-hosted`, `-foldback`), `dw-integration-bc` (ngrok), `dw-setup-install`,
  `dw-setup-upgrade`, `dw-setup-config`, `dw-extend-mcp-tools` (builds the MCP project) and
  `dw-source-explorer` (browses GitHub source).
- **Orthogonal to `mcp:`**, and the two disagree often: `dw-demo-base` is `mcp: required` yet
  `dynamo: false`; `dw-render-razor` is `mcp: none` yet `dynamo: true`. Claude Code is
  unaffected -- it loads every skill through `marketplace.json`.
- Authoring rules in `dw-skill-authoring` ("Dynamo visibility"), README ("Manifest") and
  `CLAUDE.md`.

## [4.34.0]

Fold-back sprint: **commerce and PIM**. Dynamic relations get a subsystem section that had no prior
art; the rest lands as fact rows and two corrections.

- **Dynamic product relations, a new section in `catalog-publishing.md`.** `/Admin/Api` cannot create
  one: `DynamicProductRelationDataModel.SourceProductId` is `internal get / internal set`, so
  `DynamicProductRelationSave` answers 200 and persists an ORPHAN row that
  `DynamicProductRelationsByProductAndGroup` cannot see, and the published OpenAPI schema never mentions
  the property. Category, group and all three deletes work normally. The working create is the Ecommerce
  service layer from a disposable Razor runner, `DynamicProductRelationService.Save`, which is the same
  terminal write the admin command ends in. Lookup is **source-only** everywhere, so the reverse hop is
  `GetByDynamicRelationGroupId(g).Where(r => r.TargetProductId == id)`. Calculations: `TotalSum` is
  unimplemented on 10.28.4 (500), `SumByProduct` can report SUCCESS at all 11 steps while generating zero
  rows so only the assert is safe to follow, and `GroupIds` scopes the SUMMED target products.
- **Range category fields (`EcomFieldType` 25) are half-implemented end to end** and now carry one fact
  table in `structural-model.md`: storage as two composite ids, a string-only write binder, language
  invariance, a two-`Double` index projection whose facet must point at the BASE id, `IsEmpty` on every
  index document, no Swift 2.4 facet renderer, product-cache cross-contamination between products,
  re-poisoning on every Full build, and completeness never satisfied. Model two scalar numeric fields
  instead. Only `/Admin/Api/ProductById` reads a range value faithfully.
- **`OrderSave` on an existing order is a reconciliation pass, not a row update.**
  `ForcePriceRecalculation` runs unconditionally and re-prices from the LIVE catalogue, so lines whose
  SKU has left `EcomProducts` go to 0; a missing delivery country blanks a real shipping method; and
  `GetOrderById` returns RESOLVED defaults (the default payment method) that the save then writes back.
  The mints-its-own-id rule is corrected to its real condition, `model.AutoId < 1`.
- **The PIM workflow verb-namespace split** (`Dynamicweb.Products.UI` vs `Dynamicweb.Content.UI`) is now
  the stated parent fact. `WorkflowSave` and `WorkflowDelete` are write-inert on 10.28.4 while
  `WorkflowStateSave`, `WorkflowStateDelete`, `WorkflowNotificationSave` and `GroupWorkflowId` via
  `DataModelGroupSave` all work.
- **Correction: per-language option labels ARE writable.** The flat "no verb" claim in
  `translation-mechanics.md` is scoped to the Management API `ProductFieldOptionSave`; MCP
  `set_option_translations` writes the rows. The wipes-other-languages hazard on that verb stands. Four
  per-language chrome verbs and their three payload shapes are now recorded.
- **Language ROWS come before translations.** `ProductSave` writes exactly one `EcomProducts` row and
  `ProductSetLanguages` is the second verb; `ProductCatalogGroupSave` cannot mint a catalogue-group
  language row at all; and a `400 "Unable to load query parameters"` from any `*ById` query means the row
  is missing, not the parameters. Unused `EcomLanguages` rows cannot be swept: each carries 11
  `EcomCurrencies` rows.
- **Silent no-op rows.** `ProductFieldSave` drops `Sort` and `TemplateName` while echoing them;
  `ProductCategoryFieldSaveSort` needs category-qualified ids; `FieldTemplateTag` is create-only through
  API and admin UI alike; `FeedDelete` answers ok and deletes nothing, with a `FeedService`
  DictionaryCache that must be cleared by fully-qualified `CacheInformationRefresh`; `/Admin/Api/GroupSave`
  is the USER-group verb and mints junk `AccessUser` groups; MCP `save_shops` is a full-entity replace;
  `save_groups` with `parentGroupId` and no `shopId` builds a branch that resolves zero products;
  `DynamicStructureSave` drops a `Levels` collection and `DynamicStructureLevelById` never hydrates
  `UseCompleteness` / `UseRelationOnProductCreate`, so a read-modify-write clears them. `create_category_fields`
  lies the other way: its echo under-reports options and `allowChangesAcrossLanguages` while persisting both.
- **Discontinued products are data-only.** The `discontinuedAction` literals are
  `none | redirectToReplacementProduct | redirectToGroup`, a rejected literal still commits the rest of
  the model, and no shipped handler redirects. The PDP-template guard, including the `GetProductLink`
  internal form that 404s from a `Location` header, is in `templates.md`.
- Also folded: workspace node counts follow the backing query predicate; a data set stores only its
  deltas from the parent data model; `ProductRelatedDelete` needs `ProductId` and leaves the two-way
  mirror row; there is no Channel entity and no `ShopById`, and `ShopAll` is usage-type-filtered;
  `EcomOrders.OrderTotalPrice` is a dead legacy column; MCP `search_orders` cannot see a quote;
  `create_order_state` takes `orderType` as a string and `color` as hex; the Secondary-user index rebuild
  is a two-call builder-name lookup, with the `Repository` vs `RepositoryName` split across sibling index
  queries; and `GetImage.ashx` fits inside `Width x Height` with no crop unless `Crop` is passed.

## [4.33.0]

Fold-back sprint: **content authoring, users and permissions, and the 2026-09-01 retest wave**.

- **Paragraph module settings round-trip read-as-link / write-as-int** (`paragraphs.md`). The published
  root cause was wrong: there IS a representation. `GetParagraphById` renders a page-picker value as
  `Default.aspx?Id=<n>` and `ParagraphSaveCommand` parses the posted value as a page ID, discarding
  anything non-numeric, so posting back what the read just gave you CLEARS the setting and every later
  save must re-post the numeric form. Adds the app-switch recipe (graft the target `contentModule` from a
  reference paragraph; `contentModule:null` answers 500; no `ChangeApp` verb exists), the
  `LinkType=page` querystring strip (a deep link needs `LinkType=external`), `GridRowCopy` arriving
  occupied, and `ParagraphDelete` as a soft delete that cascades to master-linked language copies.
- **`Plain item fields are COPIED DOWN` is false at 10.28.1** (`language-layers.md`). Measured on
  `Swift-v2_Text`: a valued copy field, a never-set copy field and an overridden copy all stay put when
  the master changes. The rule is to write every language layer explicitly, one save at a time,
  re-reading after each; the newly-added-field propagation and the one-pass nesting are scoped to their
  own captures. Adds the master-keyed recycle bin (clear and restore both cascade, the language areas'
  own bins read empty, `totalCount` always reads 0), widens the SECURITY permission mirror from pages to
  `GridRow` and `Paragraph` ids, and records that a "missing" `Translations.xml` key is usually present
  with an empty value that falls back to `DefaultValue`.
- **`GridRowContainer`, not `GridRowItemId`, is the discriminator for a row that saves and never
  renders** (`admin-ui-authoring.md`, `dw-swift-page-blocks`, `management-api-and-sql.md`).
  `GridRowCreate {PageId, GridId:'Page', DefinitionId, Container:'Grid'}` works; omitting `Container`
  answers HTTP 500 **and still writes** a row with `GridRowContainer=''`; `GridRowSave` with `ID:0`
  is 404, it is update-only. The row item mints on the failure path too.
- **`PageSave` is a whole-entity save with page-level blast radius** (`admin-ui-authoring.md`). A partial
  model blanks area, parent, name, item type, sort and meta title, mints a new page-item instance, and
  404s the page. Used as a one-line probe it takes a live storefront page down.
- **The `Default.aspx?ID=<n>` 301 is the only reliable page-URL resolver** (`admin-ui-authoring.md`).
  `GetPageById.friendlyUrl` answers `"Default.aspx?ID=n"` for API-created pages, and the
  derive-a-slug-from-the-name workaround breaks on diacritics.
- **Three rows into the MCP silent-no-op table** (`backend-mcp-server.md`): `save_pages` /
  `save_paragraphs` echo `id:0` on create (resolve the real id through the item instance), `copy_page`
  refuses ordinary content pages while the Admin API `PageCopy` copies them including subtree and
  language mirrors, and `set_page_menu(showInMenu)` writes `PageActive` because the schema has no
  `PageShowInMenu` column.
- **Live item types gain fields non-destructively** (`modelling-discipline.md`). `ItemFieldNew` +
  `ItemFieldSave` ALTERs the table; the delete-and-recreate opening of the create recipe drops it.
  Also: an item-list field can point at an `ItemList` id that does not exist and the read verb answers
  `[]`, indistinguishable from empty.
- **Enum properties on `/Admin/Api` save models bind by NAME** (`management-api-and-sql.md`). An integer
  falls through to `default(TEnum)=0` with `successful:true`, and the read-back echoes the stored value,
  so only a pre/post DB diff catches it. Plus: `UnifiedPermission.PermissionUserId` is nvarchar holding
  the literal `'Anonymous'`, so a bare int join aborts the whole statement.
- **`PermissionSave` IS the Management API write surface on 10.28.x** (`permission-layers.md` §15),
  replacing the "no Management API endpoint" claim. The read side has the inverse trap:
  `PermissionsByIdentifier` returns an empty `data` array when `SubName` is passed as `""`. Static files
  under `/Files` bypass page permissions entirely. Section-level denies hide only Settings on 10.28.
- **New `permission-layers.md` §17 — the Swift 2.4 UserGroups app.** Every management command is gated by
  the ACTING user's permission on their own `User` entity, so the default `AuthenticatedFrontend=read`
  silently kills invite / activate / delete behind a 200 and a rendered button set; the fix is one
  `PermissionSave` on the account group's `User` subset. Also the module's real 20-property set (no
  `ShowInactiveUsers`, no group pre-select, `UserGroups`/`UserSelectableGroups` are invite-time
  settings), `AccountListScope` matching on customer number as the only directory filter,
  `UserChangeType` targeting the admin-rights enum while `UserSave` converts the user-and-group type in
  place, the blank `AccessUserAddress` carrier row every `UserSave` mints, the
  `GroupDelete` / `UserDelete` split with string ids, and the single-account-person modelling deviation.
- **New `customer-center.md` §10 — the storefront account-admin page.** Impersonating from it answers a
  128-byte permission-denied body and that IS the switch succeeding, so assert on the FOLLOWING request.
  The invitation mail can never greet by name (`CreateNewUserViewModel` never assigns `Name`), and a
  failed invitation mail is invisible in the EventViewer: the `EmailHandler` month log is the probe and
  the Pending badge is the in-band delivery check.
- **Stock Swift renders an EMPTY `swift-v2_productprice` div when the area hides prices**
  (`customer-center.md` §11). The only `else` branch is `Pageview.IsVisualEditorMode`, so the call to
  action has to be added; the anchor string occurs TWICE in `Swift-v2_ProductPrice.cshtml` and a
  first-match replace yields a Razor compile error that still answers HTTP 200.
- **PII rule 4: assert a predicate over the table, re-run AFTER the closeout gate** (`pii-sweep.md`).
  An anonymised mailbox reappeared as a NEW row 13 minutes later, so every per-id check reports clean.
- **Auditing does not record API-driven writes** (`dw-data-audit-trail`). With the correct key, one
  config node and a recycled host, a landed `/Admin/Api` `ProductSave` writes zero `Audit` /
  `AuditDetail` rows. Never build a Review-changes beat on it, and drop the "Audit count must increase"
  enablement assertion. The UI-session comparison needs a browser: `/Admin/Api` is bearer-only.
- **`api.json` `info.version` is the version pin** (`online-mode.md`). It carries version plus commit
  sha; the admin shell footer is the fallback where a host answers without one.

Fold-back sprint: **screens, hosted-install traps and the Aug-26/31 misc wave**.

- **New reference `dw-demo-pim/references/screen-authoring.md`.** `ScreenLayout`, `ScreenType`,
  `ScreenPreset` and `ConfigurableColumns` had zero coverage anywhere in the tree. `ScreenType` is a
  fully-qualified .NET type name that no API enumerates (only the "New screen layout" form's option
  list publishes the 627 values), and the short form fails **two different ways** on two 10.28.4
  builds: 500 "Unable to resolve screen type" on one, accepted-stored-and-inert on the other, where
  the edit screen falls back to DW's default tabs. Category editors need the same `CategoryFields|`
  prefix the presets use, and a tab built entirely from un-prefixed editors is **dropped from the tab
  strip** with no error. `ScreenPresetSave` accepts any column string and answers ok;
  `ScreenPresetAccessUserRelation` keeps rows for presets that never existed while preset ids restart
  at 1; `ScreenPresetSetAsDefault` with `SelectedPresetId=0` is the un-set. The "no tab strip" symptom
  folds as one row with its discriminator: does a different row of the same worklist render tabs.
  Grid edit and Bulk update have no Management API surface (`ProductCollectionSave`'s abstract `Query`
  type, `ProductBulkUpdateSave`'s `TransientStorageKey` handshake), **Bulk update writes an EMPTY
  value to every selected row when the dual list is untouched** while its Preview grid renders blank,
  and grid-edit cell authoring lands as the guarded exception with td-index addressing plus a
  Number/Name/Price read-back and abort.
- **`governance.md`: what a worklist drill-through actually opens.** A product opened from a worklist
  inherits the query's screen preset, not the full editor, so say which one a frame is showing. Shoot
  grid edit from All products: the worklist route renders zero rows while its header claims ten
  (cause unestablished). Per-persona favourites come from the query-tree context menu in the persona's
  own session, and the tree collapses after every add.
- **`permission-layers.md`: an empty product editor is a query-string symptom before it is a
  permission symptom.** `ProductEdit` resolves its model from `Type=`, not `Id=`, so a deep link
  without `Type`/`LanguageId` opens a live NEW-product form with a green Save, for a full
  administrator too. The published line attributed exactly that screen to permission starvation.
  `DynamicStructureLevelResultsList` and `QueryListScreen` entered cold 500 or come back empty and
  must be reached by clicking the left nav.
- **`browser-automation.md`: driving the DW 10.28 admin shell.** Every action-menu item is
  pre-rendered hidden in one shared block, so visibility-aware clicks never find Import / Bulk update
  / Export: click via `page.evaluate`, scoped to the open dialog. ~20 hidden "Edit" links sit at
  x=0,y=0, so text-keyed clicks need a box filter and the resulting URL must be asserted. The AI rail
  is a toggle whose two obvious open-state tells are both wrong; a double close translates the shell
  355px, so close idempotently by measuring the ask-input rect (max 3 rounds) and assert
  `.tree-nav` x before every shot. Added the DOM attribute-flip A/B as the way to attribute a geometry
  regression to a change rather than to a standing defect.

- **`GlobalSettingSave` creates ANY key you name** (`dw-setup-config/SKILL.md`). The command does not
  validate the key against a schema, so naming a path that does not exist mints it, the save returns
  ok and `GlobalSettingByKey` reads the invented key back while the app keeps reading the real node.
  The audit flag is `/Globalsettings/Settings/Auditing/EnableAuditing`, not `/System`. Assert the key
  resolves to exactly one node in `Files/GlobalSettings.config` and assert the effect, never the
  read-back. `dw-data-audit-trail/SKILL.md` gains the enablement section it lacked, so "the audit log
  is off" is no longer reported for a flag written to a dead path.
- **`/Admin/Api` is bearer-only** (`management-api-and-sql.md`). A logged-in admin browser session
  gets 401 with an empty body, for a freshly minted full administrator as much as for a restricted
  persona, so a per-user verb such as `MyFavoriteQueryAdd` cannot be called from the persona's own
  session. Drive the real UI control, or call the verb as the key user and replicate the artefact.
- **Post-`CopyDemoSite` `/Files` assert** (`setup-checks.md` §2a). The web-visible `/Files` root on
  these hosted sites is `<site>\Files`, which the clone leaves empty, while DW resolves its archive to
  `<site>\Application\wwwroot\Files`. Every asset 404s and the storefront renders unstyled, which
  reads as a broken deserialize. GET a known file before deserializing anything.

- **What an `/Admin/Api` GET error proves** (`online-mode.md`). "Unable to load query parameters" is a
  real QUERY whose parameters did not bind, and the commonest reason is **entity not found**, so it
  widens from the two verb-specific instances into a family rule. "Unknown query" means it is not a
  query, and says NOTHING about a command of that name: `GridRowCopy`, a known-good command, answers it
  too. Discover commands from the admin UI's own `data-dw-action` attributes and XHR. Added the
  **minimal-body probe ban** (`AssetCategorySave` needs only `Name` and a shape probe created a live
  category) and a cleanup-verb table (`PriceDelete` takes `ProductId` beside `Ids` and works after the
  product is gone; MCP `delete_prices` and `delete_variant_combinations` are non-functional on 10.28.5).
- **`SerializerDeserialize`: `Mode` lives in the body and DEFAULTS TO REPLACE** (`serializer-reference.md`).
  A `Mode` on the query string has no effect and `{"IsDryRun":true}` alone runs a Replace dry run, so an
  empty `{}` body executes a live Replace. Also: dry-run CONTENT counts under-report because a dry run
  cannot create parents, so only `failed > 0` and escalated strict-mode warnings gate.
- **Field display groups, end to end** (`component-system-and-reskin.md`). They are API-only: the admin
  list screen renders "No results found" for a `systemAdministrator` while `FieldDisplayGroupAll`
  returns the rows and the PDP renders them. `SystemName` is immutable after create while the save echo
  reports the new value, `Name` writes the default-language translation only, and the shop binding is
  inert. A spec row needs all five tables and **`EcomProductCategoryTranslation` is the one that gets
  forgotten**: without it `productCategories` and `fieldDisplayGroups` come back `{}` at HTTP 200, and
  the anonymous `GET /dwapi/ecommerce/products/<id>` is the diagnostic that separates data from
  template. A NULL `RangeValue` renders its .NET `ToString` into the PDP. The layout partial resolves
  **by string**, so a new `Components/Specifications/<Name>.cshtml` plus `Layout=<name>` is an
  extension point needing no item type; Swift 2.4 ships no tabs layout.
- **Paragraph write surfaces** (`paragraphs.md`, `modelling-discipline.md`, `backend-mcp-server.md`).
  `ParagraphChangeActive` is inert with a correct body, and its shape (`{"setActive":<bool>,"ids":["<id>"]}`,
  `ids` a `List<string>`) has to be reverse-engineered because a schema mistake answers "No items
  selected" and numeric ids 500. The hide ladder is `GridRow.GridRowActive = 0` for a sole occupant,
  then the `hideFor*` trio, then SQL: the published `ParagraphDelete` prescription is replaced.
  `save_paragraphs` is inert on `active` but DOES write `itemType`, re-minting the item with default
  values. `set_paragraph_item_fields` takes a MAP and reports `succeeded` for field names that do not
  exist on the item type. `patch_products_safe` `customFields` take `{id, value}` with STRING values,
  a multi-select being a comma-joined string, and the wrong shape is a hintless invoke error.
- **`add_product_image` is an ADD and validates nothing** (`asset-organisation.md`). With a `groupId` it
  mints a second detail row instead of moving one, so a category migration needs an explicit remove
  step or every PDP shows its photo twice; and it accepts a `filePath` that does not exist, producing a
  dead asset link that `Swift-v2_ProductMediaTable` hides behind its `File.Exists` guard.
- **Imagery is an orchestrator job, uploading is an executor job** (`asset-organisation.md`). A spool
  executor has no image-generation capability at all, so a brief that asks it to generate is
  unexecutable: deliver the mechanism, prove it with an honest asset, and report the imagery blocked
  rather than shipping a wrong-colourway shot.
- **Derived spec values need a review stage** (`governance.md`). Deriving specs from marketing prose
  propagates the catalogue's own copy-paste defects and misreads negations, attachments, model names
  and units: 24 of 44 candidates were wrong. Exclude any product on the copy-paste worklist from
  description-derived enrichment.

- **`AreaSave` is whole-entity carriage, and it cannot set the domain** (`deserialize-flow.md`). A save
  that omits `websiteItem` blanks `Swift-v2_Master`'s header and footer bindings while the page keeps
  returning 200, so bind the area's commerce columns by SQL or round-trip the FULL `GetAreaById` model,
  and gate after any `AreaSave` on `<header data-swift-page-header>` and `<footer data-swift-page-footer>`
  being present. `domain` / `hostNames` are accepted and no-op on `AreaDomain`, and a full model with
  `hostNames` 500s: the published "or the Management API equivalent" for the root binding is corrected
  to the SQL-plus-restart motion.
- **`EcomCurrencies.CurrencyRate` is a percentage, `100.0` = par** (`deserialize-flow.md`). The Swift
  baseline ships `USD$$<lang>` rows at rate `1.0`, so every price renders at 1 % of value the moment USD
  becomes the default, with the symbol and formatting perfectly correct. Assert the magnitude against
  `ProductPrice`, not the symbol.
- **Cart gates over curl** (`customer-center.md`). DW10 silently skips the cart command for curl's
  default User-Agent: 200, a cart row, zero `EcomOrderLines`, nothing in the log. Set a browser UA, plus
  `-L` / `--post301` for the `Default.aspx` redirect and `-F` for the multipart form. And a lines-only
  SQL delete leaves the cached `Order`, so the next add comes back at doubled quantities: delete the
  `EcomOrders` cart row too and restart the pool.
- **Facet source fields** (`index-management.md`). An `Analyzed="false"` field is one term, so a
  multi-value cell facets as a single giant bucket, and `Analyzed="true"` buckets word fragments
  instead. Source the facet from a single-valued sibling or a real multi-value field type, and assert
  the facet's VALUE COUNT. Also: the Files index build fails on a fresh clone when
  `Files\Digital assets` does not exist, and instances build one per call.
- **The mobile performance pass** (`mobile-pass.md`). A hero preload is a no-op when
  `lcp-discovery-insight` already scores 1, because the preload scanner discovers `<img srcset>` during
  parse and blocking CSS delays paint, not discovery. Below-fold EAGER slider images cost more LCP than
  every insight row Lighthouse ranks above them, because no audit models bandwidth contention: a
  net-new Custom-lane template with `loading="lazy"` and a quality override moved mobile Performance
  86 to 93 in one step.
- **Minifying the custom sheet** (`re-skin.md`). `clean-css` level 1 sorts selector lists, strips
  whitespace inside values Blink serialises verbatim, and rewrites `background-position-x: initial` to
  `0px`: it is not whitespace-only, and no size metric reveals a value-level edit. Ship a tokeniser that
  only drops comments and collapses whitespace outside strings, `url()` and values. A minified sheet
  must carry a `/*! ... */` banner naming its readable master, or the pull-live-and-edit motion
  silently diverges from it.
- **The Tier-0 customer re-skin motion** (`styles-assets.md`). Net-new `<customer>.{json,css}` pairs
  reusing the **seven stock ColorScheme ids verbatim**, because every deserialized
  `data-dw-colorscheme` binds by id name and renaming them unbinds the whole site with no error. Edit
  the hex AND the rgb triplet in BOTH the `.css` and the `.json`, repoint the four `Area` style columns
  by SQL, and load `default_custom.css` before `<customer>_custom.css`.
- **Host restore traps** (`dw-setup-config/SKILL.md`, `publish-to-hosted.md`). A
  `GlobalSettings.Database.config` `<Password>` is ciphertext bound to that host's `appsettings`
  Encryption keys: copied between solutions it decrypts to garbage and the site serves the Setup
  wizard while SQL logs a password mismatch. And a transfer package that is a **source project** keeps
  its own `bin`: ring-symlinking it boots a stock host with every custom extension silently gone.

## [4.32.0]

Fold-back sprint: **screens, hosted-install traps and the Aug-26/31 misc wave**.

- **New reference `dw-demo-pim/references/screen-authoring.md`.** `ScreenLayout`, `ScreenType`,
  `ScreenPreset` and `ConfigurableColumns` had zero coverage anywhere in the tree. `ScreenType` is a
  fully-qualified .NET type name that no API enumerates (only the "New screen layout" form's option
  list publishes the 627 values), and the short form fails **two different ways** on two 10.28.4
  builds: 500 "Unable to resolve screen type" on one, accepted-stored-and-inert on the other, where
  the edit screen falls back to DW's default tabs. Category editors need the same `CategoryFields|`
  prefix the presets use, and a tab built entirely from un-prefixed editors is **dropped from the tab
  strip** with no error. `ScreenPresetSave` accepts any column string and answers ok;
  `ScreenPresetAccessUserRelation` keeps rows for presets that never existed while preset ids restart
  at 1; `ScreenPresetSetAsDefault` with `SelectedPresetId=0` is the un-set. The "no tab strip" symptom
  folds as one row with its discriminator: does a different row of the same worklist render tabs.
  Grid edit and Bulk update have no Management API surface (`ProductCollectionSave`'s abstract `Query`
  type, `ProductBulkUpdateSave`'s `TransientStorageKey` handshake), **Bulk update writes an EMPTY
  value to every selected row when the dual list is untouched** while its Preview grid renders blank,
  and grid-edit cell authoring lands as the guarded exception with td-index addressing plus a
  Number/Name/Price read-back and abort.
- **`governance.md`: what a worklist drill-through actually opens.** A product opened from a worklist
  inherits the query's screen preset, not the full editor, so say which one a frame is showing. Shoot
  grid edit from All products: the worklist route renders zero rows while its header claims ten
  (cause unestablished). Per-persona favourites come from the query-tree context menu in the persona's
  own session, and the tree collapses after every add.
- **`permission-layers.md`: an empty product editor is a query-string symptom before it is a
  permission symptom.** `ProductEdit` resolves its model from `Type=`, not `Id=`, so a deep link
  without `Type`/`LanguageId` opens a live NEW-product form with a green Save, for a full
  administrator too. The published line attributed exactly that screen to permission starvation.
  `DynamicStructureLevelResultsList` and `QueryListScreen` entered cold 500 or come back empty and
  must be reached by clicking the left nav.
- **`browser-automation.md`: driving the DW 10.28 admin shell.** Every action-menu item is
  pre-rendered hidden in one shared block, so visibility-aware clicks never find Import / Bulk update
  / Export: click via `page.evaluate`, scoped to the open dialog. ~20 hidden "Edit" links sit at
  x=0,y=0, so text-keyed clicks need a box filter and the resulting URL must be asserted. The AI rail
  is a toggle whose two obvious open-state tells are both wrong; a double close translates the shell
  355px, so close idempotently by measuring the ask-input rect (max 3 rounds) and assert
  `.tree-nav` x before every shot. Added the DOM attribute-flip A/B as the way to attribute a geometry
  regression to a change rather than to a standing defect.

- **`GlobalSettingSave` creates ANY key you name** (`dw-setup-config/SKILL.md`). The command does not
  validate the key against a schema, so naming a path that does not exist mints it, the save returns
  ok and `GlobalSettingByKey` reads the invented key back while the app keeps reading the real node.
  The audit flag is `/Globalsettings/Settings/Auditing/EnableAuditing`, not `/System`. Assert the key
  resolves to exactly one node in `Files/GlobalSettings.config` and assert the effect, never the
  read-back. `dw-data-audit-trail/SKILL.md` gains the enablement section it lacked, so "the audit log
  is off" is no longer reported for a flag written to a dead path.
- **`/Admin/Api` is bearer-only** (`management-api-and-sql.md`). A logged-in admin browser session
  gets 401 with an empty body, for a freshly minted full administrator as much as for a restricted
  persona, so a per-user verb such as `MyFavoriteQueryAdd` cannot be called from the persona's own
  session. Drive the real UI control, or call the verb as the key user and replicate the artefact.
- **Post-`CopyDemoSite` `/Files` assert** (`setup-checks.md` §2a). The web-visible `/Files` root on
  these hosted sites is `<site>\Files`, which the clone leaves empty, while DW resolves its archive to
  `<site>\Application\wwwroot\Files`. Every asset 404s and the storefront renders unstyled, which
  reads as a broken deserialize. GET a known file before deserializing anything.

- **What an `/Admin/Api` GET error proves** (`online-mode.md`). "Unable to load query parameters" is a
  real QUERY whose parameters did not bind, and the commonest reason is **entity not found**, so it
  widens from the two verb-specific instances into a family rule. "Unknown query" means it is not a
  query, and says NOTHING about a command of that name: `GridRowCopy`, a known-good command, answers it
  too. Discover commands from the admin UI's own `data-dw-action` attributes and XHR. Added the
  **minimal-body probe ban** (`AssetCategorySave` needs only `Name` and a shape probe created a live
  category) and a cleanup-verb table (`PriceDelete` takes `ProductId` beside `Ids` and works after the
  product is gone; MCP `delete_prices` and `delete_variant_combinations` are non-functional on 10.28.5).
- **`SerializerDeserialize`: `Mode` lives in the body and DEFAULTS TO REPLACE** (`serializer-reference.md`).
  A `Mode` on the query string has no effect and `{"IsDryRun":true}` alone runs a Replace dry run, so an
  empty `{}` body executes a live Replace. Also: dry-run CONTENT counts under-report because a dry run
  cannot create parents, so only `failed > 0` and escalated strict-mode warnings gate.
- **Field display groups, end to end** (`component-system-and-reskin.md`). They are API-only: the admin
  list screen renders "No results found" for a `systemAdministrator` while `FieldDisplayGroupAll`
  returns the rows and the PDP renders them. `SystemName` is immutable after create while the save echo
  reports the new value, `Name` writes the default-language translation only, and the shop binding is
  inert. A spec row needs all five tables and **`EcomProductCategoryTranslation` is the one that gets
  forgotten**: without it `productCategories` and `fieldDisplayGroups` come back `{}` at HTTP 200, and
  the anonymous `GET /dwapi/ecommerce/products/<id>` is the diagnostic that separates data from
  template. A NULL `RangeValue` renders its .NET `ToString` into the PDP. The layout partial resolves
  **by string**, so a new `Components/Specifications/<Name>.cshtml` plus `Layout=<name>` is an
  extension point needing no item type; Swift 2.4 ships no tabs layout.
- **Paragraph write surfaces** (`paragraphs.md`, `modelling-discipline.md`, `backend-mcp-server.md`).
  `ParagraphChangeActive` is inert with a correct body, and its shape (`{"setActive":<bool>,"ids":["<id>"]}`,
  `ids` a `List<string>`) has to be reverse-engineered because a schema mistake answers "No items
  selected" and numeric ids 500. The hide ladder is `GridRow.GridRowActive = 0` for a sole occupant,
  then the `hideFor*` trio, then SQL: the published `ParagraphDelete` prescription is replaced.
  `save_paragraphs` is inert on `active` but DOES write `itemType`, re-minting the item with default
  values. `set_paragraph_item_fields` takes a MAP and reports `succeeded` for field names that do not
  exist on the item type. `patch_products_safe` `customFields` take `{id, value}` with STRING values,
  a multi-select being a comma-joined string, and the wrong shape is a hintless invoke error.
- **`add_product_image` is an ADD and validates nothing** (`asset-organisation.md`). With a `groupId` it
  mints a second detail row instead of moving one, so a category migration needs an explicit remove
  step or every PDP shows its photo twice; and it accepts a `filePath` that does not exist, producing a
  dead asset link that `Swift-v2_ProductMediaTable` hides behind its `File.Exists` guard.
- **Imagery is an orchestrator job, uploading is an executor job** (`asset-organisation.md`). A spool
  executor has no image-generation capability at all, so a brief that asks it to generate is
  unexecutable: deliver the mechanism, prove it with an honest asset, and report the imagery blocked
  rather than shipping a wrong-colourway shot.
- **Derived spec values need a review stage** (`governance.md`). Deriving specs from marketing prose
  propagates the catalogue's own copy-paste defects and misreads negations, attachments, model names
  and units: 24 of 44 candidates were wrong. Exclude any product on the copy-paste worklist from
  description-derived enrichment.

- **`AreaSave` is whole-entity carriage, and it cannot set the domain** (`deserialize-flow.md`). A save
  that omits `websiteItem` blanks `Swift-v2_Master`'s header and footer bindings while the page keeps
  returning 200, so bind the area's commerce columns by SQL or round-trip the FULL `GetAreaById` model,
  and gate after any `AreaSave` on `<header data-swift-page-header>` and `<footer data-swift-page-footer>`
  being present. `domain` / `hostNames` are accepted and no-op on `AreaDomain`, and a full model with
  `hostNames` 500s: the published "or the Management API equivalent" for the root binding is corrected
  to the SQL-plus-restart motion.
- **`EcomCurrencies.CurrencyRate` is a percentage, `100.0` = par** (`deserialize-flow.md`). The Swift
  baseline ships `USD$$<lang>` rows at rate `1.0`, so every price renders at 1 % of value the moment USD
  becomes the default, with the symbol and formatting perfectly correct. Assert the magnitude against
  `ProductPrice`, not the symbol.
- **Cart gates over curl** (`customer-center.md`). DW10 silently skips the cart command for curl's
  default User-Agent: 200, a cart row, zero `EcomOrderLines`, nothing in the log. Set a browser UA, plus
  `-L` / `--post301` for the `Default.aspx` redirect and `-F` for the multipart form. And a lines-only
  SQL delete leaves the cached `Order`, so the next add comes back at doubled quantities: delete the
  `EcomOrders` cart row too and restart the pool.
- **Facet source fields** (`index-management.md`). An `Analyzed="false"` field is one term, so a
  multi-value cell facets as a single giant bucket, and `Analyzed="true"` buckets word fragments
  instead. Source the facet from a single-valued sibling or a real multi-value field type, and assert
  the facet's VALUE COUNT. Also: the Files index build fails on a fresh clone when
  `Files\Digital assets` does not exist, and instances build one per call.
- **The mobile performance pass** (`mobile-pass.md`). A hero preload is a no-op when
  `lcp-discovery-insight` already scores 1, because the preload scanner discovers `<img srcset>` during
  parse and blocking CSS delays paint, not discovery. Below-fold EAGER slider images cost more LCP than
  every insight row Lighthouse ranks above them, because no audit models bandwidth contention: a
  net-new Custom-lane template with `loading="lazy"` and a quality override moved mobile Performance
  86 to 93 in one step.
- **Minifying the custom sheet** (`re-skin.md`). `clean-css` level 1 sorts selector lists, strips
  whitespace inside values Blink serialises verbatim, and rewrites `background-position-x: initial` to
  `0px`: it is not whitespace-only, and no size metric reveals a value-level edit. Ship a tokeniser that
  only drops comments and collapses whitespace outside strings, `url()` and values. A minified sheet
  must carry a `/*! ... */` banner naming its readable master, or the pull-live-and-edit motion
  silently diverges from it.
- **The Tier-0 customer re-skin motion** (`styles-assets.md`). Net-new `<customer>.{json,css}` pairs
  reusing the **seven stock ColorScheme ids verbatim**, because every deserialized
  `data-dw-colorscheme` binds by id name and renaming them unbinds the whole site with no error. Edit
  the hex AND the rgb triplet in BOTH the `.css` and the `.json`, repoint the four `Area` style columns
  by SQL, and load `default_custom.css` before `<customer>_custom.css`.
- **Host restore traps** (`dw-setup-config/SKILL.md`, `publish-to-hosted.md`). A
  `GlobalSettings.Database.config` `<Password>` is ciphertext bound to that host's `appsettings`
  Encryption keys: copied between solutions it decrypts to garbage and the site serves the Setup
  wizard while SQL logs a password mismatch. And a transfer package that is a **source project** keeps
  its own `bin`: ring-symlinking it boots a stock host with every custom extension silently gone.

## [4.31.0]

Fold-back sprint: **corrections**. Every entry replaces published guidance that is wrong on current
builds, rather than adding a note beside it.

- **Variants through the Management API are version-forked, and `catalog-publishing.md` §2.14 now says
  so.** The combination id shape is INVERTED between builds: group-qualified `"<VARGRP>.<VO>"` on
  10.25.x, **bare option ids on 10.28.x**, where the group-qualified form answers `{"status":"ok"}` and
  creates zero rows, so a `VariantCombinationsByProductId` count read-back after every
  `VariantCombinationSave` is mandatory. `VariantCombinationCreationSetup` **does not exist on 10.28.5**
  (`400 Unknown command`) and no cache key is needed there; the read model still returns an empty
  `variantCombinationSelectionCacheKey`, so the field is not evidence the verb exists. Per-variant row
  fields (`number`, `stock`, `active`, and 16 more) persist through a round-trip `ProductSave` on
  10.25.x and **do not land at all on 10.28.5**: 0 of 19 on the variant against 4 of 4 on the master in
  the same pass, which is not the `AllowChangesAcrossVariants` gate. `publish-to-hosted.md` and
  `canonical-setup-order.md` step 14 state the same fork; the two files no longer contradict each other.
- **Per-variant price verification.** `PriceSave` carrying `VariantId` stays the only write, and it is
  verified by `PriceById`: MCP `get_prices_by_product_id` is cache-lagged and returns an empty list
  immediately after a successful write. `defaultPrice` on the product model is a different column and is
  never the read-back.
- **A NULL-price variant row drops every variant document from the index build**
  (`index-management.md`). `ProductIndexBuilder.HandlePrices` throws `InvalidCastException` Int32 to
  Double, caught per document: the master indexes, every variant is silently dropped with one log line
  each, the build still reports success, and adding an `EcomPrices` row does not stop it.
- **Group-scoped contract pricing had the wrong remedy published in two files.** The DC scope column is
  `PriceUserGroupId` (Admin API `userGroupId`), written through `/Admin/Api/PriceSave`;
  `PriceCustomerGroupId` (`groupCustomerNumber`) matches a customer NUMBER, and MCP `save_prices`'s
  `customerGroupId` writes that one. `catalog-publishing.md` §2.13 and `dc-scoping.md` now carry the same
  three-column table and the rendered-price assertion.
- **`AssetAddToMultipleProducts.IsDefault` is inert on the raw Admin API verb only.** MCP
  `add_product_image {setAsPrimary:true}` writes the flag on the first call (335/335 measured), so bulk
  attach is two calls per attachment, not three (`catalog-publishing.md`, `asset-organisation.md`).
- **Completeness: the per-language claim is deleted and the four-gate chain lands as an ordered flow.**
  `CompletionLanguages` changes nothing in a query, so a translation-gap worklist cannot be built from
  completeness. The `Completeness feature` flag is stated with **both** scopes: the admin calculation
  path stays OFF, while `CompletionRule|<id>` index fields populate only with the flag ON. Added the
  append-time semantics (`AppendCompletionExpressions` IS the exclude checkbox; the append is
  `NOT(rule == 100)`, so a document with no value PASSES it) and the completion-rule API traps: a missing
  `ProductLanguageId` 500s instead of 400ing, `CompletenessOnAllCategoryFields` injects a phantom rule id
  `0` that must never be round-tripped back, and `CompletionRuleDelete` leaves dangling ids on
  language-only group rows that `CompletionRuleRemoveFromGroup` 404s on.
- **No stock widget shows a sum or an average.** `RepositoryCountWidget` accepts `WidgetType=Sum`/`Avg`
  and renders a Count; `ScalarSqlCountWidget` returns `null` for anything but a COUNT. An inventory-value
  tile cannot be built honestly. The parameter table in `rules-and-dashboards.md` said the opposite.
  Added the widget envelope table (drill-down works once the `.query` files live under the `SmartSearches`
  Shared path; the count honours the query predicate and ignores the query configuration; `Shop`,
  `IconId` and `AvailableForAdmin` are inert or write-only; thresholds take literal operators) and the
  full `WidgetColor` member list. `canonical-setup-order.md` step 19 no longer prescribes a state-keyed
  tile: `ProductWorkflowStateId` is declared and never populated, so the clause is silently dropped.
- **Workspace level sources rewritten** (`structural-model.md` §2.12). Both previous worked examples were
  the two failure modes. A level source must be a **non-analysed string field**: an analysed name field
  tokenises into lower-cased word fragments that all drill to real rows (129 nodes summing to 419 against
  a 358-product query), and a numeric field renders nodes that drill to nothing. Use the ID field and let
  DW resolve the display name (`ManufacturerID` gave 106 nodes summing to 358). Validate by the SUM of
  node counts, not by a drill. `canonical-setup-order.md` no longer repeats `ProductWorkflowStateId`.
- **`GridRowContainerWidth` is not SQL-only** (`management-api-and-sql.md`).
  `GridRowSave?Query.Type=GridRowById` writes it (59/59 rows measured) and mints the `GridRowItemId` that
  MCP `save_grid_rows` leaves NULL; the exact payload shape, the preserved-members behaviour and the
  `DefinitionId`-clears-`mobileLayout` caveat are documented, with the CSS override kept as the fallback.
- **Row spacing has two defaults, one per row template** (`Swift-v2_Row` 6, `Swift-v2_RowFlex` 1), so the
  previous advice to serialize explicit values was itself the defect: a `?? 6` coercion turned 4px into
  96px on every RowFlex row. A whole-entity save passes a null through as null.
- **MCP file tools are sandboxed to `/Files/Images`** (`asset-organisation.md`). `/Files/Documents` is
  unreachable for reads and writes and `move_file` is refused on the destination, so documents go under
  `Files/Images/<subfolder>/`; `Swift-v2_ProductMediaTable` resolves them by asset category, not by path.
- **The TLS guidance is scoped by cert class** (`mcp-setup.md`). The bypass remains the only method for a
  self-signed localhost leaf; on a hosted CA-issued chain, `NODE_EXTRA_CA_CERTS` pointed at a PEM of the
  CA certs is the correct fix and flips `claude mcp list` to Connected.

## [4.30.0]

Wave-1 script 7 (final): the mojibake census.

- **New: `dw-data-access/scripts/Invoke-DwMojibakeCensus.ps1`** — READ-ONLY census of
  double-encoded UTF-8 per table.column across every string column (or a `-Table` subset):
  broken-marker rows vs healthy typographic characters as the partial-vs-wholesale contrast,
  plus U+FFFD context spans with every non-ASCII character escaped (forensics, never readable
  content). Every marker is built from code points, so the file's own encoding can never corrupt
  the needles and the repo validator does not trip on its own detector. Repair stays a separate
  deliberate step; U+FFFD damage is called out as unrecoverable in place.
- **Mojibake guidance consolidated**: `dw-demo-base` `visual-qa.md` (the double-encode-signature
  rule) points at the census as the enforced DB-side form; `dw-content-modelling`
  `modelling-discipline.md` (the sqlcmd codepage pitfall) gains a soft pointer. The repo-file
  side (`ftfy`, the validator) stays where it was.

## [4.29.0]

Wave-1 script 6: the stock-Swift vendor debrand.

- **New: `dw-demo-base/scripts/Remove-SwiftVendorBoilerplate.ps1`** — dry-run by default,
  `-Apply` to write, originals backed up to `_dw_debrand_backup_<timestamp>` first, one SQL
  transaction. Rewrites the stock vendor boilerplate by CONTENT match, never by item id
  (vendor-framed privacy phrases, the stock foreign placeholder phone block, the
  `noreply@noreply.com` mailbox, OSS licence boilerplate replaced with a holding notice — never
  synthesised terms, `<SenderName>DynamicWeb</SenderName>` in module settings). The de-branding
  nuance is enforced by construction: only specific stock phrases are touched, so the platform's
  load-bearing cookie names survive; the script then lists what remains for the manual pass.
  Local installs only. The stock vendor strings inside the script are detection targets — a
  sanitization pass must not strip them.
- **`pii-sweep.md` Rule 2** names the script as the enforced form of the stock-content half.

## [4.28.0]

Wave-1 script 5: the PII scan — the blocking gate that previously existed only as a method.

- **New: `dw-demo-base/scripts/Invoke-DwPiiScan.ps1`** — READ-ONLY, classes and counts only,
  never a value. String-column census (legacy `ntext`/`text` counted separately — they drop out
  of REPLACE-based sweeps), person-PII counts on the platform tables (mailboxes, names,
  addresses, phone shapes, real IPv4 outside the documentation range, gateway XML snapshots,
  live recovery tokens), a whole-database term sweep per `-Term`, a rendered-page pass and an
  anonymous-download probe by URL (`-PagePath`/`-ProbePath` + locale-shaped `-ShapePattern`
  regexes). SQL sections are local-only; hosted installs run the URL sections. The counts are
  the gate, not the exit code — and the rendered-page eyeball pass stays mandatory.
- **`pii-sweep.md`** names the script as the enforced form of the mechanical steps; the method,
  the classification and fix steps, and the eyeball pass stay prose.

## [4.27.0]

Wave-1 script 4: the readiness harness.

- **New: `dw-setup-install/scripts/Test-DwHostReady.ps1`** — READ-ONLY; runs the post-install
  verification contract as one harness: `/admin` reachable and licensed (not redirecting to
  `/admin/license`), `/admin/mcp` -> 401 unauthenticated, `HEAD /admin/mcp/bootstrap` -> 405,
  and with `-McpToken` the JSON-RPC handshake, a >200 tool count, and `get_areas`/`get_shops`
  data probes. `-Expectation <file>.psd1` swaps in a custom check table; `-OutFile` writes a
  markdown report; exit 0/1. Self-contained (the dw-setup-install exception).
- **SKILL.md Verification folded**: the 8-item manual list becomes the harness invocation plus
  the two checks a script cannot see (the `net10.0` TFM, the agent's own MCP config entry).
- **`dw-demo-base` `setup-checks.md`** points host-side readiness at the harness (the machine
  preflight ritual stays).

## [4.26.0]

Wave-1 script 3: the guarded host restart — the highest damage-if-forgotten shape in the survey
(a name-based restart once killed a sibling demo's host).

- **New: `dw-demo-base/scripts/Restart-DwHost.ps1`** — `-Action Start|Stop|Restart` with `-Port`
  and `-SolutionPath` mandatory (no default port or path exists on purpose). Stop resolves the
  PID only from the port and only stops it after the owning process's command line proves it
  belongs to this solution; a mismatch stops nothing. Index-build-in-flight guard (state.json
  heartbeat; `-Force` overrides only this guard, never the ownership check), lock file with
  10-minute stale takeover, durable redirected `dotnet run` start (`--launch-profile`, optional
  `--framework`), `/Admin` readiness poll, `-WhatIf` support. Self-contained: needs no token and
  works when the host is down.
- **`host-lifecycle.md`** names the script as the enforced form; the recipes and launch traps
  stay as the contract it implements. `dw-demo-base` gains `compatibility:` frontmatter and a
  `## Scripts (scripts/)` table.

## [4.25.0]

Wave-1 script 2: the index build. (The originally planned SQL task runner script is dropped —
owner decision: no scheduled-task SQL path ships in the skills; SQL stays local-only.)

- **New: `dw-search-indexing/scripts/Build-DwProductIndex.ps1`** — flushes the three read-through
  product caches, POSTs BuildIndex (a severed response on a long 10.28.x build is caught, and the
  build is never re-fired on a timeout), and polls to a Success with a LastRun newer than this
  run's POST. `State=Error` is terminal only when the instance's `LifecycleState=Failed`; the
  10.28.x `IndexStatusesAll` verb is the automatic fallback when the 10.26.x status verb answers
  400. `-Passes 2` covers multi-instance indexes; `-SkipCacheFlush` only for structural creates.
- **Prose folds**: the fenced flush-build-poll block in `index-management.md` and the two-pass
  probe in `dw-demo-swift` `integrity-sweep.md` (which disagreed on details) now both point at
  the script; each keeps its why (the flush rationale, the status contract, the build-twice and
  instance-freshness rules, the BuildName-from-XML rule).
- `dw-search-indexing` gains `compatibility:` frontmatter and a `## Scripts (scripts/)` table.

## [4.24.0]

First shipped script of the default-scripts wave: the shared connection module. The demo-build
survey found the Admin API / MCP / SQL plumbing re-implemented ~20 times across engagements;
this is the one implementation the other wave-1 scripts import.

- **New: `dw-data-access/scripts/Dw.Api.psm1`** — `Connect-Dw` / `Assert-DwConnection`
  (discovery order parameter > `$env:DW_*` > `launchSettings.json` > fail with the fix; the
  load sentinel for the AMSI-blocked-import trap), `Invoke-DwApi` (UTF-8 byte bodies, depth-50
  serialization, TLS bypass gated to localhost or an explicit opt-in),
  `Remove-DwDisplayOnlyMember` (the `modelIdentifier`/`*Icon` round-trip-save strip),
  `Invoke-DwMcp` / `Get-DwMcpTools` (JSON-RPC handshake, `mcp-session-id`, SSE `data:` unwrap,
  cursor pagination), `Get-DwSqlRows` / `Get-DwSqlScalar` (raw `SqlDataReader` projected to
  `pscustomobject`; one-row results stay arrays; nothing returned can hang `ConvertTo-Json`;
  LOCAL installs only — no remote SQL path ships, by design: arbitrary SQL on a hosted install
  has no remediation short of a backup restore),
  `Clear-DwServiceCache` (targeted + `-All`), `Set-DwDbConnectionTrust`. Tokens masked in all
  output.
- **`dw-data-access` SKILL.md**: `compatibility: Requires PowerShell 7.x`, the
  `## Scripts (scripts/)` table, and the canonical import + assert fenced form.
- **Pointers (one lesson, one home)**: `management-api-and-sql.md` names the module as the
  enforced calling form at the wrapper section and at the strip/unrolling/AMSI traps;
  `dw-demo-base` `mcp-setup.md` points its JSON-RPC fallback at `Invoke-DwMcp` instead of a
  hand-written client.
- **`marketplace.json`**: `dw-data-access` added to the `dynamicweb-commerce` bundle so
  `dw-search-indexing`'s upcoming script can import the module under bundle closure; README
  bundle table updated.

## [4.23.0]

Enforces the machine-checkable half of the 4.22.0 script contract and brings the four existing
`dw-setup-install` scripts up to it, in one PR so `main` never sits between the gate and the
conformance.

- **Validator** (`scripts/validate-skills.py`), new checks over `skills/*/scripts/`:
  script contract (PowerShell files carry `#Requires -Version 7.0` after the help block,
  comment-based help with a `READ-ONLY.`/`WRITES:` `.SYNOPSIS` opener, `.DESCRIPTION`, an
  explicit `param()`; `.EXAMPLE` warns; Python files carry a module docstring); the runtime
  declared in the skill's `compatibility:` frontmatter; `Import-Module`/dot-source targets
  resolve and cross-skill imports honor bundle closure (markdown links into another skill's
  `scripts/` now count as hard dependencies too); token-shaped secrets rejected everywhere
  under `skills/`, plaintext password assignments and environment literals
  (`localhost:<port>`, `*.mydwsite*.com`, the local solutions tree) rejected in scripts; BOM,
  mojibake, and invalid-UTF-8 checks extended from markdown to script files; unlinked scripts
  warn.
- **CI** (`manifest-check.yml`): a `pwsh` step parses every shipped `.ps1`/`.psm1` with the
  PowerShell language parser and fails on parse errors.
- **`dw-setup-install` scripts migrated to PowerShell 7 single-tier**: `#Requires -Version 7.0`
  placed after the help block (a leading `#Requires` silently breaks `Get-Help`'s binding of
  comment-based help — the contract text was corrected on the 4.22.0 branch), the 5.1
  `curl.exe -k` fallbacks and `-UseBasicParsing` removed, `WRITES:` synopsis openers, owning
  reference + traps in `.DESCRIPTION`, `.EXAMPLE` blocks, `Download-File` renamed to the
  approved-verb `Save-RemoteFile`. `-DynamicwebUrl` is now mandatory in
  `bootstrap-and-attach.ps1` and `activate-free-trial.ps1` (the host port is install-specific;
  `https://localhost:5001` defaults dropped per the no-default-host rule).
- **`dw-setup-install` SKILL.md**: `compatibility: Requires PowerShell 7.x` frontmatter, a
  linked `## Scripts (scripts/)` table, PowerShell 7 added to Prerequisites, and all
  invocations switched from `powershell -ExecutionPolicy Bypass -File` to
  `pwsh -NoProfile -File`.

## [4.22.0]

Adopts `skills/<skill>/scripts/` as the packaging convention for runnable scripts, ahead of
shipping a shared module and a first wave of scripts for the operations every demo build
re-implements (Admin API / MCP wrapper, RunSql task runner, guarded host restart, index build,
readiness verify, PII scan, stock-Swift debrand, mojibake census). Docs only; no script changes.

- **`dw-skill-authoring` "Shipping scripts"**: the script contract. Language per job, runtime
  declared in `compatibility:` frontmatter: PowerShell 7 is the default for anything touching a
  Windows Dynamicweb host (`#Requires -Version 7.0`, the version handled by the setup preflight,
  never in scripts); Python or another language where it fits better. Language-neutral rules
  (actionable header with a READ-ONLY / WRITES opener, explicit parameters, exit codes, dry-run
  default beyond one row, connection discovery order with no default host/port/path/token,
  environment-only secrets, encoding), a PowerShell profile (comment-based help,
  `SupportsShouldProcess`, one shared module in `dw-data-access`, `dw-setup-install`
  self-contained) and a Python profile (`argparse`, `--dry-run`/`--apply`, stdlib unless
  declared). Linked `## Scripts` table, forward-slash invocations; script imports count toward
  bundle closure.
- **`dw-demo-foldback` Step 1c**: lifting a script from a demo build. The recurrence bar (two
  engagements, or one plus an existing fenced block), the script-specific sanitization classes
  (hosts, tokens, passwords, ids, paths, task names), one-lesson-one-home for the superseded
  prose, retiring the demo copy, and the smoke-test rule (write scripts local-first; a hosted
  install only afterwards and under `dw-demo-hosted` shared-install discipline).
- **`dw-demo-base` setup-checks**: install-grade fix for a missing `pwsh`
  (`winget install --id Microsoft.PowerShell`).
- **CLAUDE.md, README**: encoding and no-secrets rules extended to `scripts/`; PowerShell 7
  listed under Requirements.

## [4.21.0]

MCP-dependence taxonomy: every skill now declares whether it depends on the Dynamicweb MCP
server, so harnesses without a live connection (plain Claude Code installs) can tell
tool-driven flows apart from standalone platform knowledge.

- New required frontmatter field on every SKILL.md: `mcp: required | optional | none`
  (13 required, 14 optional, 13 none). Orthogonal to `type`/`group`.
- `required` skills open with an `## MCP preflight` section (verify tools, stop if absent —
  never substitute direct SQL/file edits/guessed HTTP); `optional` skills carry a
  `## Without MCP` section stating the standalone/advisory path. `dw-source-doc-lookup`
  gets a tailored fallback (fetch doc.dynamicweb.dev over HTTP); `dw-demo-base` a tailored
  preflight (the flow wires MCP itself).
- `scripts/validate-skills.py` enforces the pair: field present and valid, marker section
  matches the declared level, contradictions are errors.
- `scripts/build-manifest.mjs` emits the `mcp` field into `manifest.json` so Dynamo and
  other consumers can filter on it; manifest regenerated.
- Deliberately NOT encoded in skill names (no renames) or descriptions (several are near
  the 1024-char cap; trigger budget stays intact — the body markers carry the behavior).
- Authoring rules documented in `dw-skill-authoring` ("MCP dependence") and README
  ("Manifest"); the new 4.20.0 skills (`dw-demo-hosted` required, `dw-demo-foldback`)
  classified alongside the rest.

## [4.20.0]

Re-lands the July `dw-demo-base` split chain (PRs #64–#69, originally stacked on `v2`) on
`main`, rebased by hand against 4.19.1. Four of the six legs survive; the `dw-demo-base`
SKILL.md rightsizing (#67) is dropped because fold-back sprint 4.16.0 and the v2 debloat (#79)
reshaped that file since, and its `host-lifecycle.md` / `distribution-checkout.md` extractions
already exist on `main` in another form.

- **New skill `dw-demo-hosted`** — hosted/cloud installs reached only by URL + Admin API key.
  `online-mode.md` and `publish-to-hosted.md` move out of `dw-demo-base/references/` into the
  new skill unchanged in content (including the 4.15.0+ inherited-clone remediation playbook and
  the PII-inheritance pointer); every inbound link (`dw-demo-base` SKILL.md and
  `surface-priority.md` / `pii-sweep.md`, `dw-demo-swift` `cheat-sheet.md` /
  `language-layers.md`, README) is repointed. `dw-demo-base`'s "Environment fork" and its two
  hosted routing rows now route to the skill. Registered in `dynamicweb-presales`.
- **New skill `dw-demo-foldback`** — the maintainer fold-back workflow.
  `dw-demo-base/references/iterate-plugin.md` becomes
  `dw-demo-foldback/references/fold-back-workflow.md`; the trigger-phrase block and routing row
  in `dw-demo-base` SKILL.md collapse to one paragraph routing to the skill, and the base
  description drops its claim on the fold-back (it was 3 chars over the 1024 cap after the
  hosted rename). `customisations.md`, `visual-qa.md`, CLAUDE.md and README repointed.
  Registered in `dynamicweb-presales`.
- **New repo-local skill `.claude/skills/dw-skill-authoring`** — the authoring procedure moves
  out of CLAUDE.md (frontmatter contract, naming, area taxonomy, body voice, length budgets,
  adding a skill, bundle closure, validation, the PR workflow). CLAUDE.md shrinks to what governs
  every edit: the one-way foundational/demo boundary, encoding, and the PR rule. The skill folds
  in what CLAUDE.md gained since July — the area taxonomy table, the bundle-closure validator
  clause, the CI note — plus a new step: regenerate `manifest.json` with
  `node scripts/build-manifest.mjs` after any frontmatter change (CI fails on drift). The
  integration branch is now `main`; the `v2` wording is gone.
- **Validator: SKILL.md bodies are budgeted by characters, not just lines.** A body over
  16,000 characters (~4k tokens on activation) warns alongside the existing 500-line check, and
  the reference-TOC check now descends into nested `references/` folders. Currently flags
  seven skills, warnings only: `dw-content-modelling` (16.3k), `dw-demo-base` (29.6k),
  `dw-demo-swift` (19.8k), `dw-integration-framework` (17.9k), `dw-render-viewmodels` (16.3k),
  `dw-swift-page-blocks` (22.4k) and `dw-swift-page-design` (18.9k). Whether a given one
  warrants a split is a per-skill call; the flow skills that drive live MCP work pay the
  activation cost on every build and are the first candidates.
- **`orchestrator.md` — "Model tier" section.** Choosing a cheaper or stronger model for a demo
  step is the orchestrator's dial, not the skill's: there are no per-tier SKILL.md variants, and
  what a cheaper model cannot be trusted to remember is encoded as a script or detector rather
  than more prose. `dw-skill-authoring` carries the authoring-side corollary.

## [4.19.1]

Two follow-ups to 4.19.0, found while verifying that Custom.Mcp's remote skill fetch
(`DynamoSkillCatalog.GetRemoteSkill`/`BuildRemoteCatalogIndex`) still works end to end against
this repo:

- Folded `integration-activity-setup.md` — the one Custom.Mcp builtin skill from 4.19.0 that
  hadn't landed yet (its commit was pushed to that PR's branch after the PR had already
  merged) — into `dw-integration-framework` as a new "Setting Up Activities via MCP Tools"
  section: the activity/mapping/endpoint tool map, file-import and endpoint-driven-ERP-sync
  flows, diagnosing a failed run, and import rules. The existing skill covered architecture and
  C# provider-building but had no MCP-tool operational layer, same gap-fill pattern as the rest
  of 4.19.0.
- Fixed `scripts/build-manifest.mjs`'s frontmatter parser: it read a `description: '...'`
  line's value verbatim, including the surrounding YAML quotes, so every quoted description (39
  of the 40 skills — everything but `dw-demo-base`, the one skill written unquoted) carried a
  literal leading `'` into `manifest.json`. That string is what `Dynamicweb.MCP`'s remote skill
  catalog shows verbatim to the model, so every remote-fetched skill's one-line summary in the
  Dynamo system prompt has been carrying a stray leading quote. Added an `unquote()` step
  (strips one matching pair of `'...'`/`"..."`, unescaping the YAML `''`/`\"` embedded-quote
  forms) before storing any frontmatter value. `validate-skills.py`'s own frontmatter readers
  were not affected (its strict pass uses real YAML parsing; the lenient pass's off-by-two on
  the description-length cap never mattered in practice).

## [4.19.0]

Ported the remaining portable Custom.Mcp Assistant builtin skills (everything not tied to
Dynamo's own admin-assistant features) into this repo, sanitized of "Dynamo"/"approval card"
framing. Rather than a 1:1 file mapping, each builtin was checked against the existing skill
covering its domain first, since the existing PIM/commerce/search/content skills already carry
some field-validated MCP-tool detail — most builtins turned out to be the missing *procedural*
layer for a domain that already has *reference* depth, not a new domain.

**New skills** (no existing domain home):
- `dw-data-audit-trail` — investigate history/audit trail for any entity (from
  `diagnose-what-changed.md`).
- `dw-content-localization` — translate a page/site or create a language version (from
  `cms-page-translate.md`); mirrors the existing `dw-pim-localization` split from
  `dw-pim-modelling`.
- `dw-source-doc-lookup` — consult doc.dynamicweb.dev via `search_documentation`/
  `fetch_documentation_page` before answering (from `documentation-lookup.md`).

**Folded into existing skills as new sections** (avoids duplicating the domain's existing
reference-layer content with a near-identical new skill):
- `dw-content-modelling` ← `cms-page-publish.md` ("Creating and Publishing a Page").
- `dw-commerce-b2b` ← `commerce-assortment-setup.md` (MCP tool flow added to the existing
  "Assortments" section).
- `dw-commerce-catalog` ← `commerce-currency-pricing.md` ("Currency Conversion").
- `dw-commerce-orders` ← `commerce-order-investigate.md` + `commerce-discount-voucher.md`
  ("Investigating an Order", "Discounts and Vouchers").
- `dw-pim-modelling` ← `commerce-product-create.md` ("Creating a Product") +
  `product-variants-setup.md` (destructive-ordering trap added to "Variant Groups").
- `dw-pim-completeness` ← `pim-completeness.md`'s enrichment flow ("Enriching Products Against
  a Query" — the existing skill only covered rule *configuration*).
- `dw-search-indexing` ← `pim-product-query.md` + `search-index-and-query.md` (new
  `references/mcp-query-tools.md`, the MCP-tool-layer companion to the existing
  Admin-API-layer `query-authoring.md`/`query-expressions.md`).

**Excluded:** `navigation.md` — wraps `dynamo_navigate`, a tool specific to the Dynamo
admin-assistant's own fuzzy nav-index feature; no generic MCP equivalent exists.

Registered `dw-content-localization` in `dynamicweb-frontend`, `dw-data-audit-trail` in
`dynamicweb-backend`, and `dw-source-doc-lookup` in `dynamicweb-developer`.

## [4.18.0]

Ported five skills out of the Custom.Mcp `frn/dw9-to-dw10-migration` branch's builtin skill
set, sanitized to platform-generic knowledge (no Dynamo-specific "workflow"/"approval card"
framing): `dw-pim-migrate-dw9` (structure -> product import -> data-model assignment -> verify
for a DW9-to-DW10 product catalog migration), `dw-swift-page-blocks` (the Swift 2 page-building
vocabulary — row layouts, paragraph components, color schemes, and the MCP tools that compose
them), `dw-swift-page-design` (build a Swift 2 page from a reference page, a mockup, or a live
URL), `dw-swift-migrate-v1` (faithful Swift 1 -> Swift 2 layout-preserving port), and
`dw-swift-migrate-content` (rebuild any site's content as modern Swift 2). Registered
`dw-pim-migrate-dw9` in `dynamicweb-commerce` and the four Swift skills in
`dynamicweb-frontend`.

## [4.17.0]

Debloat pass on `dw-demo-base` itself: SKILL.md drops from ~6,300 to ~3,900 words and reads
as a pure nav layer — the Host lifecycle authority moves to a new `references/host-lifecycle.md`,
the Distribution clone/resolve recipe merges into `references/scaffold.md` §5, the Surface
priority section (previously duplicated verbatim) becomes a summary with
`references/surface-priority.md` as sole owner, and the nav-table rows tighten to routing labels.
`references/tls-bypass.md` merges into `references/mcp-setup.md` Step 2 (now also the canonical
home of the dual-set env-var pattern); `references/audit-customisations.md` merges into
`references/customisations.md` §7; `references/db-update-recovery.md` moves, de-demoed, to
`dw-setup-upgrade/references/`. visual-qa's Assert-design-rules section compresses its
single-incident war stories to claim→fix bullets around the four reusable detector specs;
demo-tactics' post-mortem bullets compress to their transferable tactics (the Swift sign-in-nudge
pattern moves to `dw-demo-swift/references/customer-center.md`); online-mode's inherited-clone
playbook becomes a symptom→cause→fix table; iterate-plugin trims its generic-git mechanics to a
CLAUDE.md pointer and halves the Anti-patterns and leak-recovery narrative. No platform facts
removed — every fact either stays in place or moves to its owning reference.

Fold-up batch B: eight staged foundational candidates leave
`dw-demo-base/references/foundational/` for their owning skills, stripped of
demo framing on the way. `search-indexing.md` → `dw-search-indexing/references/index-management.md`
(plus `query-authoring.md` and `query-expressions.md` moved alongside);
`commerce-catalog.md` → `dw-commerce-catalog/references/catalog-publishing.md`
(and the SKILL.md's duplicated Search Index Setup section is now a link to
dw-search-indexing); `commerce-b2b.md` → `dw-commerce-b2b/references/dc-scoping.md`;
`commerce-orders.md` and `promotions-engines.md` → `dw-commerce-orders/references/`
(`order-lifecycle.md`, `promotions-engines.md`); `users-permissions.md` →
`dw-users-permissions/references/permission-layers.md`. Each target SKILL.md
gains a Deep reference section; ~90 links repointed across the demo corpus;
`dw-commerce-catalog`, `dw-commerce-b2b`, and `dw-commerce-orders` join the
`dynamicweb-presales` bundle to keep it link-closed.

Fold-up batch C: six more staged foundational candidates leave
`dw-demo-base/references/foundational/`. `render-razor.md` →
`dw-render-razor/references/razor-surfaces-and-pitfalls.md`; `render-viewmodels.md` was thinner
than the shipped skill, so its unique facts (Pageview.User accessors, ProductViewModel flattening
traps, Stock vs StockLevel correction) merged into `dw-render-viewmodels/SKILL.md` and the staged
file was deleted; `content-modelling.md` → `dw-content-modelling/references/modelling-discipline.md`;
`swift-building.md` → `dw-swift-building/references/component-system-and-reskin.md`;
`data-access.md` → `dw-data-access/references/management-api-and-sql.md`; and
`cache-invalidation.md` lands whole (no 4-way split) as
`dw-data-access/references/cache-invalidation.md` per the data-area taxonomy, with one-line
"cache invalidation after mutations → dw-data-access" pointers added to `dw-search-indexing`,
`dw-content-modelling`, `dw-commerce-catalog`, and `dw-users-permissions`. Demo links and framing
stripped on the way; ~85 links repointed across the demo corpus; `dw-render-razor`,
`dw-content-modelling`, `dw-swift-building`, and `dw-data-access` join the `dynamicweb-presales`
bundle to keep it link-closed.

Fold-up batch D (final): the last nine staged foundational candidates leave
`dw-demo-base/references/foundational/` and the staging directory is deleted.
`extend-mcp-tools.md` → `dw-extend-mcp-tools/references/backend-mcp-server.md`;
`extend-providers.md` → `dw-extend-providers/references/addin-lifecycle.md`;
`integration-bc-connector.md` → `dw-integration-bc/references/bc-connector-surface.md`;
`integration-erp.md` → `dw-integration-erp/references/ownership-split.md`;
`integration-framework.md` was thinner than the shipped skill, so its unique
content (the named ad-hoc/batch/live taxonomy and the docs' provider
definitions) merged into `dw-integration-framework/SKILL.md` and the staged
file was deleted; `setup-install.md` → `dw-setup-install/references/install-anatomy.md`;
`setup-upgrade.md` → `dw-setup-upgrade/references/upgrade-mechanics.md`;
`source-explorer.md` → `dw-source-explorer/references/assembly-introspection.md`;
`tracking-insights.md` → `dw-setup-config/references/tracking-insights.md`.
Demo framing stripped on the way (demo-corpus links rewritten as vendor-generic
prose); ~35 links repointed across the demo corpus; `dw-setup-install`,
`dw-setup-upgrade`, `dw-source-explorer`, `dw-integration-erp`,
`dw-extend-mcp-tools`, and `dw-extend-providers` join the `dynamicweb-presales`
bundle to keep it link-closed. The CONTENT-GAPS "fold up the foundational
candidates" follow-up is marked done, and the remaining "foundational
candidate" phrasing across the demo corpus now reads "foundational skill /
reference".

Trim pass on `dw-demo-swift` (~25% recoverable with zero knowledge loss):
superseded/correction residue rewritten to current truth in
`admin-ui-authoring.md`, `paragraphs.md`, and `deserialize-flow.md` (git owns
the history); the verify-by-round-trip rule single-owned by
`dw-demo-base/references/surface-priority.md` with one-line standing rules
left in place; four micro-references merged into their neighbours —
`content-modeling.md`'s unsanitised `Swift-v2_Text` escape hatch into
`paragraphs.md`, the `dw10-canonical-surfaces.md` router into SKILL.md as a
canonical-surfaces table (plus the IIS-only dotted-redirect note),
`checkout-order-fields.md` and `b2b-dc-pattern.md` into `customer-center.md`
§9–§10; `zero-state.md` folded into `re-skin.md` as its Step 0; and
`re-skin.md`'s war-story pitfalls rewritten to claim → mechanism → fix →
assert form (~9,300 → ~6,400 words with every platform fact preserved).
All inbound links and nav rows repointed.

## [4.16.0]

Fold-back sprint 4.16.0: lands the skill legs of three triaged learning bundles — zero-state /
design gate / catalogue imagery, the ERP mock's execution path, and query & index truth. The
through-line across all three: **a surface answered `ok` and the thing you asked for did not
happen** — a gate leg that stamps SKIP and reports PASS over a site nobody would show, a RESET that
restores the database while the storefront serves the pre-write price from a read-through cache, a
scheduled task the running app cannot see, an unresolvable expression path that appends instead of
updating, a sort that reads back exactly as saved and is dropped at execution, a rebuild that
targets an index no query reads, and a `BuildName` that is wrong in three mutually exclusive ways
depending on the host.

### Added
- **dw-demo-swift — `references/zero-state.md` (new)**: Step 0 of every re-skin. The stock-copy
  tripwire grep over the served HTML, the identity strings (frontpage title, area name, header and
  footer brand) as first-class steps, the `defaultValue` trap resolved per item type (an unwritten
  field renders shipped marketing copy, which is why three feature cards carry one sentence), "a
  band whose data source is empty gets rewired or deleted, never left as a skeleton", a catalogue
  pixel floor, and the three design asserts armed on gate run one.
- **dw-demo-base — `references/foundational/query-authoring.md` and
  `references/foundational/query-expressions.md` (new, split at the reference size budget)**: the
  `Query*` verb surface, which had no coverage at all. Which of the three read verbs is authoritative for which properties;
  the restart-free query-cache flush (a `QueryById` GET on a throwaway GUID re-runs
  `InitQueriesCache` on the miss); the `QueryCopy` → save-the-name → rename-both-siblings → flush
  order that gets past the duplicate-name guard firing on a query's own file; `QueryMove` as the
  relocation verb that carries the `.configuration` sibling; expression `Path` as a locator, never
  an insertion point (`Path:"0"` rewrites the ROOT group, and `Negate` there inverts the whole
  query); why alternation needs an OR group of single-value nodes; the typed-constant gap that makes
  a numeric predicate hand-authorable only; paging that reports `totalPages` and honours no offset;
  the complementary-count check for declared-but-unpopulated index fields; the repoint-before-rebuild
  order that makes a shop rename fail closed; and the three ways a build verb answers 200 and builds
  nothing.
- **dw-demo-swift — catalogue imagery** (`asset-organisation.md`): the sanctioned autonomous source
  for product photography. The geometric `pdftohtml -xml` join (never extraction order), the poppler
  v23 pin, the `pdftoppm` page-raster fallback for the one colour space the converter mangles, the
  per-pair eyeball stage with its own decision artefact, `GetImage.ashx` returning 0.75x the source
  on the webp path, and the colour-variant coverage cap measured per category rather than as a total.
- **dw-demo-erp — Option 3** (`mock-deltas.md`): DB-staged plus a real Integration Framework
  activity — a `SqlProvider` source over two staged tables into an `EcomProvider` destination. This
  is configuration, not code; the earlier wording conflated "no CUSTOM provider class" with "no
  activity".

### Changed
- **dw-demo-base `orchestrator.md`**: design verification is a property of every gate run, not of
  the design workstream. Overflow, empty-band and stock-copy legs arm against a raw deserialize, and
  the design page set covers every language prefix the build serves — a translated header can carry
  a constant per-language overflow that a default-language page list cannot see.
- **dw-demo-swift `header-menu.md`** Platform truth 2 rewritten: Swift mega-menu parents carry
  `data-bs-toggle` but not `.dropdown-toggle`, so there is no stock caret to restyle, and the
  nav-link `::after` has three claimants — the underline utility, a `swift.css` hover-bridge, and the
  custom caret. Pin `width`/`height`, use `px` borders, suppress hover transforms.
- **dw-demo-swift `re-skin.md`**: a component scoped by a `body` itemtype hook is scoped, not
  portable; a card grid inside a text paragraph inherits Swift's reading measure, so measure the
  rendered tile, never the column count.
- **dw-demo-erp `mock-deltas.md`** Steps 3 and 6 rewritten: `TaskAddInSettings` holds literal XML;
  a SQL-inserted `ScheduledTask` row is invisible until a recycle (so `TaskRun` 404s on a row that
  exists); registration is proven from the task list, not the INSERT; and a cache flush sits between
  RESET and BuildIndex, with definition of done moved from a SQL read to a rendered PDP read.
- **dw-demo-base `foundational/data-access.md`**: `GridRowContainerWidth` joins the SQL-only column
  list, with a `main`-scoped `--dw-container-width` override as the sanctioned substitute.
- **dw-demo-base `foundational/source-explorer.md`**: reflection answers "does the capability exist",
  never "why is this instance not selected" — grep the references for the affordance and for the
  artefact it depends on before reflecting, because the deciding input is frequently data (a
  filesystem-path gate) that a reflection pass cannot see.

### Corrected (published lines that were wrong)
- `foundational/search-indexing.md` and `foundational/cache-invalidation.md`: flushing the
  `Searching:Queries` cache was documented as **restart-only** ("plan the restart cost into your fix
  window"). It is not — the throwaway-GUID `QueryById` GET replaces the restart. Both files corrected
  together, plus the restart-ladder rung that listed the cache as restart-owed.
- `foundational/search-indexing.md`: the `NotSupportedException` at `GetQueryFolderPath` was
  documented as "almost always" a duplicate GUID. With `Type=FavoriteQueries` in the URL it is a
  stock platform bug on a compile-time-constant path, reproducible on an untouched tree — check the
  frame above and the `Type=` before reaching for the duplicate-GUID grep.
- `dw-search-indexing/SKILL.md`: the `In` and `MatchAny` operator rows implied set semantics on an
  authored value list. A comma-joined right-hand side is matched as one opaque term and returns zero;
  `In` as an authored constant is normalised into an Or-group of per-value `Equal` nodes on some
  builds and matches nothing on others.
- `foundational/search-indexing.md` (plus `online-mode.md` and `sql-direct-seeding.md`):
  `ShopsToIndex` read as an isolation guarantee. It bounds index SIZE; channel isolation is enforced
  at query time by the storefront's own `ShopIDs` filter, so an empty value is not a leak to fix.
- `foundational/extend-mcp-tools.md`: the `build_product_index` row attributed the symptom to "no
  Lucene segments written". Same incident, wrong end — the tool builds its own default
  repository/index pair while the queries read a different instance. Row rewritten rather than
  duplicated.
- `foundational/search-indexing.md` and `dw-demo-swift/integrity-sweep.md`: an unresolvable
  `BuildName` was documented as answering `404` in one file and `500` in another. It has also
  answered `200 {"status":"ok"}` while building nothing, so both now require resolving the builder
  **and** asserting build freshness.
## 4.15.1

- `dw-demo-pim` canonical-setup-order step 14 now forks the variant-enrichment route by install type: the Management API chain (`commerce-catalog.md` §2.14) on hosted/API-only installs, the SQL sweep on local installs. Previously only the SQL route was named, leaving hosted sessions without a canonical path.
- `dw-demo-base` commerce-catalog §2.14 gains a lying/no-op catalogue for variant writes: the verbs outside the chain answer ok and write nothing, a master-value read-back means NULL-field fallback (enrichable), and `EcomProductField.AllowChangesAcrossVariants` gates per-variant field writes. Added after a hosted session probed only the no-op verbs and concluded per-variant identity was impossible.

## [4.15.0]

Fold-back sprint 4: lands the skill legs of 77 accepted demo-build learnings (Foundry LRN issues)
across `dw-demo-base` and `dw-demo-swift`, in two parts. The through-lines: **the response model is
an ECHO** (a save that reports `ok` and drops the field, a read verb that serves a cache the write
verb never invalidated, and a *different* read verb that agrees with the lie — so the store or the
rendered screen is the oracle); **write shapes are per field type, and per engine** (the
string-vs-object family stated once, two coexisting discount engines one character apart, an
assembly-qualified condition type whose error echoes nothing); **the platform owns ids, timestamps
and ordering** (`*Save` mints its own id and discards yours; a recalculate re-saves the cached
entity over your SQL; an absolute sort posted from a non-unique key flattens a curated page);
**a verb-registry probe is not free and not conclusive** (every wrong guess writes an Error row onto
the customer's Monitoring dashboard, while the screen route's own `Type=` parameter hands you the
right query); **the numbers on the dashboards are read live from tables nobody looks at**, behind
two shipped settings that discard or degrade all of it; **a clone copies the artefact but not the
ownership, the path or the endpoint that made it work**; and — the loudest one — **a demo host
serves real people's personal data and the vendor's own legal copy until someone sweeps for it, and
a name-based grep reports clean.**

### Added
- **dw-demo-base — new references**: `foundational/promotions-engines.md` (the two discount engines
  and which verb writes the one the admin screen reads, the voucher grid's legacy-row projection,
  v2 condition/reward payload shapes, voucher code constraints, loyalty names living in the
  translation table, encrypted gift-card codes); `foundational/tracking-insights.md` (Insights reads
  `Tracking*` and `Statv2*` is a decoy, `DoNotTrackConnectionCloseHeader` discarding 100% of proxied
  traffic, tracking cookies written after the response has started so 10.28.x can never record a
  returning visitor, a `Tracking/Level` value outside its own enum, the `TrackingSession%` naming
  ban, the three `/Admin/Api` health-provider verbs and the `checkWhatWasRun` technique,
  `ContentDataHealthProvider` 500ing on partially-contained databases, and the log tables nothing
  ever trims); **`pii-sweep.md`** (anonymisation as a whole-database string sweep re-run after every
  pass, stock Swift shipping the platform vendor's own PII and legal copy, and the locale-shaped
  patterns a term-grep can never find) — plus its always-on block in `SKILL.md` and the rendered-page
  PII pass in `visual-qa.md`.
- **dw-demo-base — clone/host posture** (`online-mode.md`): the inherited-clone remediation
  playbook — middleware exceptions escaping DW logging entirely, the create-probe that separates a
  real ACL lockout from a clone-ownership fossil, `Files\System` artefacts owned by the source host
  (delete the fossil, do not edit ACLs), stale scheduled-task import paths, the checks that make
  *disabling* an inherited integration task the correct fix, the GlobalSettings apply-without-
  persisting / persist-without-applying split on an ACL-locked host, and the `Move-Item`-loses-the-ACE
  ban with `Translations.xml` as the DW-owned self-modifying artifact behind it.
- **dw-demo-base — platform surfaces**: admin-screen discovery via the route `Type=` parameter and
  the dashboard cost of every guessed verb name (`foundational/data-access.md`), the legacy
  `text`/`ntext` columns a bulk sweep silently skips, `[ordered]@{}` integer keys indexing by
  position, the `DataRow` single-row indexing footgun fixed inside the helper, and the AMSI-blocked
  dot-source that leaves every comparison reading empty; currency integrity as an index-build
  precondition (`foundational/search-indexing.md`); the unflushable `AccessUser` cache split brain
  (`foundational/cache-invalidation.md`); orders, invoices, subscriptions, RMA and the
  `GetOrderList`↔`EcomShops` inner join (`foundational/commerce-orders.md`); product-field
  registration, per-language and facet-label write surfaces (`foundational/pim-localization.md`);
  `ProductSave` without `RunUpdateIndex` (`foundational/commerce-catalog.md`);
  `UserAddressDelete` resolving through the owning user (`foundational/users-permissions.md`).
- **dw-demo-swift**: the paragraph and page write contracts — the field key shape, item-list arrays
  replacing the whole list, one over-long field aborting every other field, the read verb that
  collapses a repeater (`paragraphs.md`); the `GridRowSort` safety rules — absolute ordering, verify
  against the DB or the DOM rather than the API model, and insert-at-a-position instead of
  re-deriving a total order (`admin-ui-authoring.md`); the demo-clock rules — one anchor row per
  shifter, rewind-and-run as the only proof, discovered date columns, and per-column guards for
  dates a cancel operation overloads as a state marker (`dashboard-seeding.md`); persona sign-in
  field names with the right assertion target, and persona renames as a sweep of every generator
  that can put the name back (`customer-center.md`); case-sensitive `Translations.xml` keys with the
  89 shipped case-variant pairs (`language-layers.md`); two missing guards in stock Swift 2.4
  templates — `GetPage(0)` throwing on the `?? 0` sentinel, and `AssetCategories` null on a stub
  ProductViewModel (`templates.md`); a master-layer `ParagraphSave` writing through to the language
  layers (`language-layers.md`); asset-reference auditing where filenames lie in both directions
  (`asset-organisation.md`).

### Fixed
- `paragraphs.md`: `ButtonData.Label` on a language-version paragraph **is** writable — the
  sprint 1-3 "not writable, record it as a known residual" text is replaced by an explicit
  correction, and the "item-list children carry STRING fields only" claim is narrowed to
  `SelectedImage`.
- `paragraphs.md`: the read-shape-is-a-string / write-shape-is-an-object split is now stated **once**
  as a family rule above the write-shape table, generalising the two earlier single-field notes.
- `paragraphs.md`: supersedes the earlier "`GetParagraphById` is dead on 10.28 / 400 means not
  found" reading — the parameter name was the fault.
- `admin-ui-authoring.md`: corrects "verify a re-sort by re-reading `model.data`". That model is
  served from a cache `GridRowSort` does not invalidate, so the API read-back is stale while the DB
  and the rendered page are correct — and a retry or revert on that basis destroys the correct state.
- `surface-priority.md` + `foundational/commerce-orders.md`: the ordering rule is generalised — any
  API verb that **re-saves** an entity reverts raw-SQL edits made behind it, including verbs that do
  not look like writes (`OrderRecalculate`). API writes first, SQL last, never re-save afterwards.
- `sql-direct-seeding.md` + `foundational/search-indexing.md`: the sprint-3 index-build text absorbs
  the argument-shape `404` rule rather than contradicting it.
- `foundational/users-permissions.md`: the standing do-not-rename-users-via-raw-SQL rule now names
  its mechanism — an in-process user cache reachable by no invalidation verb, failing three
  endpoints away as a `403` on profile switch.

## [4.14.0]

Fold-back sprint 3: lands the skill legs of 60 accepted demo-build learnings (Foundry LRN issues)
across `dw-demo-swift` and `dw-demo-base`. The through-lines: **a read model is not a save model**
(`modelIdentifier` + `emailStateIcon` on `EmailSave`, module page-picker settings on
`ParagraphSave`, and a `ParagraphSave` response that echoes values the row provably never took);
**the 0 that means nothing** (`gridRowColumn` returns 0 from `ParagraphNew` and 0 is a column the
renderer never walks; `ProductsByDynamicStructureLevel` returns 0 for every query missing `Path`;
`$rows[0].Col` reads column 0 off an unrolled `DataRow`); **per-field-type write shapes are not
interchangeable** (`SelectedImage` `{Id}` vs video `{Path}` vs `LinkEditor` bare URL vs
`ButtonEditor` envelope, none of them writable on a projected list child); **verbs that create
instead of update** (`TaskSave` with `Id=0` minted 1,428 duplicate scheduled tasks;
`RelationGroupSave` inverts it); and — the design half — **a green gate can lie in ways a byte
check, a screenshot and a rendered-HTML assert all share**: a rule that parsed and never applied, a
rule that applied to a page written years later, a wrap that is not an overflow, a colour that
appears in no sheet, and a proof whose oracle is the artefact under test.

### Added
- **dw-demo-swift**: the paragraph create contract — 1-based `gridRowColumn`, create-then-save
  field binding, `layout` as the writable twin of `template`, the `Swift-v2_Text` lorem `Subtitle`
  default, and the per-field-type write-shape table incl. the `ButtonData` language-version trap
  (`paragraphs.md`); `GridRowSave` traps (`mobileSortColumns` binds `IEnumerable<ListOption>`, the
  row-family conversion payload) (`admin-ui-authoring.md`); the SQL-runner retirement evidence,
  `TaskSaveCommand` create-vs-update semantics and the corrected index-build status route
  (`sql-direct-seeding.md`); the CSS authoring truths — row colour schemes paint the **section**
  (a radius on a transparent child rounds nothing), the `!important` tell that names a rule dead
  since the day it shipped, selector reach (scope every hide rule; comment every positional one;
  `Row` vs `RowFlex` emit different column markup), effective-alpha contrast, and the
  name-your-retirement-condition rule for workaround blocks (`re-skin.md`); webfonts arriving as an
  `@import` inside the generated Typography sheet (`styles-assets.md`); the post-AreaCopy SECURITY
  checklist, shortcut normalisation, the `GroupMetaPrimaryPage` + `PageNavigationProductPage` pair,
  and the `primaryPageId`-at-the-shop-page blank-PDP trap (`language-layers.md`); nav visibility is
  not access control (`header-menu.md`); the gallery-video 3×-preload payload trap and the
  unused-asset audit method (`asset-organisation.md`).
- **dw-demo-base**: `FileDelete` ACL denial, `allowOverwrite` on every upload, and the
  probe-for-a-reachable-site-DB rule with its credential/scope caveats (`online-mode.md`); short
  command names are not unique, a read model is not a save model, and the `EmailsByFilters` filter
  pairs (`foundational/data-access.md`); product relations through the Management API, the variant
  chain, and channel/feed semantics (`foundational/commerce-catalog.md`); the Dynamic-Workspaces
  empty-state checklist and BOM/category/field contracts (`foundational/pim-modelling.md`);
  `WorkflowUserSave` (`foundational/pim-workflow.md`); the Swift 2.4 `LanguageSelector` item-type
  gap with its creation route, the `TextEditor` = `nvarchar(255)` hard error, and the AreaCopy
  permission SECURITY rewrite (`foundational/content-modelling.md`); the design-gate asserts —
  wrap-is-not-overflow (rail row count), present-in-HTML-is-not-visible, effective-alpha contrast,
  and Accept-aware image sizing (`visual-qa.md`).

### Fixed
- `foundational/content-modelling.md` §2: the item-type recipe attributed table creation to
  `ItemTypeSave`. `ItemFieldSave` materialises `ItemType_<SystemName>`; activation rewrites the XML
  in place, so the host identity needs a **write ACE on `Files\System\Items\**`** or activation
  fails silently (only trace: `Files/System/Log/items/ActivationWorkflow`). Split into Route A
  (XML on disk) and Route B (author through the API); `ItemTypeDelete` demoted to a reset lever and
  the "deadlock" framing retired — the 400 "System name is used already" is the file owning the
  name, not a blocker.
- `foundational/content-modelling.md` + `paragraphs.md`: the repeater-child verification is
  re-ranked — the rendered page is the verification, full stop; the `0` → non-zero pointer mint is
  a **create-only** convenience and must not be what a helper gates on (evidence: pointer constant
  across four saves on an existing `ItemList`, with the `ParagraphSave` response echoing values
  that did not persist).
- `sql-direct-seeding.md` + `foundational/search-indexing.md`: "there is no index-status command on
  10.28.x" was wrong. `BuildIndex` is synchronous server-side and the 120s client timeout severs the
  *response*, not the build — swallow it and poll **`IndexStatusesAll`**; the singular
  `IndexStatus`/`GetIndexes` `400 Unknown query` is what produced the earlier reading.
- `customer-center.md` §6: the platform gate now states the platform honestly rather than the
  workaround that was available at the time.
- `online-mode.md`: "there is no SQL surface, ever" is now "assume none until you probe" — a
  co-located cloud host can carry the site DB reachably, which retires the `Sql-ReadRaw` workaround
  family for reads while leaving the write order unchanged.

## [4.13.0]

Fold-back sprint 2: lands the skill legs of 23 accepted demo-build learnings (Foundry LRN
issues) across `dw-demo-swift` and `dw-demo-base`. The through-lines: a **capability that has
no verb of its own is invisible to a verb-registry probe** (the accordion item-list write rides
inside `ParagraphSave`, which retires a year-old workaround *and* the reasoning that produced
it); **the surfaces that cannot verify a write** (a `ParagraphSave` response echoes the posted
model, `GetParagraphById` collapses a repeater, an item-type XML read proves metadata and not
schema); **rename blast radius** (an ecom-group rename moves every child PDP URL with no
auto-301, while needing neither a translations save nor a recycle); the **merged page+group
navigation tree** and its three-surface fan-out; the **product-asset verb set** as a complete
add/remove/set-default capability; and a **documentation-honesty rule** — never write a comment
asserting a guard you have not read in the config this session.

### Added
- **dw-demo-swift**: the merged page+group nav tree — untagged-child membership, `navigationTag`
  as the suppression flag, shortcut children, pages-always-precede-groups, and the
  one-`NavigationRoot`-feeds-three-surfaces rule (`header-menu.md`); `ProductCatalogGroupSave`
  rename blast radius + the no-translations-save/no-recycle correction, and the
  assert-the-shape-never-guard-past-it rule for authoring scripts (`admin-ui-authoring.md`);
  `Pageview.IsVisualEditorMode` as the stock editor-mode branch, the admin-editor-chrome recipe
  (`<body>` hook in the layout master, offset-never-background), and the template-deploy
  verification procedure with the `FileByName` round-trip (`templates.md`); the destructive
  `SelectedImage` write asymmetry and the `hideFor*` hide motion (`paragraphs.md`); the
  `auto-fit` + `1fr` stretch trap on grid galleries (`re-skin.md`); generated-imagery
  hero-pair review + required prompt/model/quality manifest fields (`asset-organisation.md`).
- **dw-demo-base**: the product-asset verb set — `AssetAddToMultipleProducts` /
  `ProductAssetDelete` / `ProductAssetSetAsDefault` vs the file-archive `AssetDelete`, the inert
  `IsDefault` flag, and the bulk-attach-needs-a-bulk-detach rule
  (`foundational/commerce-catalog.md`); "a verb-registry brute-force proves a VERB absent, never
  a CAPABILITY absent" (`surface-priority.md`); the comment-must-not-claim-an-unread-guard rule
  and its paint-aware clearance assert (`visual-qa.md`); the `CacheTypeName` parameter name
  (`foundational/cache-invalidation.md`).

### Fixed
- `dw-demo-swift/references/paragraphs.md`: **deleted** "`Swift-v2_Accordion`: its items may be
  unreachable from the API" and the hand-authored-Bootstrap-in-a-Text-field workaround it
  prescribed — the items are writable through `ParagraphSave`, and the workaround was itself the
  defect an owner review rejected. Replaced with the accordion payload + a pointer to the
  canonical repeater edit path.
- `foundational/content-modelling.md` §2: the XML-plus-restart item-type recipe produced a type
  that reads perfectly and cannot be written at all (`Invalid object name`), with no restart able
  to fix it — replaced with the `ItemTypeDelete` → `ItemTypeSave` → `ItemFieldSave` → XML-overlay
  sequence.
- `foundational/content-modelling.md`: the "re-`GetParagraphById` and check the child count"
  round-trip guard cannot be performed as written — replaced with the pointer-mint and
  live-render checks that can.
- `foundational/cache-invalidation.md`: the ".cshtml edits are *mostly* cache-bypassing" hedge is
  now a procedure, and the group-rename recycle is scoped to nav membership only.

## [4.12.0]

Fold-back sprint: lands the skill legs of 81 open demo-build learnings (Foundry LRN issues,
filed 2026-07-23..27) across `dw-demo-swift` and `dw-demo-base`. The through-lines: Admin-API
round-trip asymmetries that silently no-op or clobber (ButtonData, item lists, Title-derived
names), the palette/token-swap completeness checklist (generated colour-scheme sheets, rgba
literals, var() fallbacks, alias-not-delete), the floating/overlay-header recipe with its
UA-selected-header and container-cap traps, a "CSS that silently never reaches the browser"
catalogue (comment terminators, digit-leading ids, :has() ancestor collapse, nested sentinels),
API-write vs SQL-write cache visibility, and an assert-design ruleset (a green assert proves
nothing until it has been seen red; geometry never proves legibility; clipping is paint, not
layout).

### Added
- **dw-demo-swift**: ButtonData/ParagraphSave/PageSave/PageCopy round-trip semantics and the
  `Swift-v2_Accordion` unreachable-item-list workaround (`paragraphs.md`,
  `admin-ui-authoring.md`); focal-point inertness + `ContentFileByName` live-template reads
  (`templates.md`); header-height-as-grid-rows recipe (`header-menu.md`); the token-swap
  checklist, floating-header recipe, silent-CSS-drop catalogue, and Bootstrap-`!important`
  override rules (`re-skin.md`, `styles-assets.md`); no-crop-hero mobile stacking + real-device-UA
  probe rule (`mobile-pass.md`); shared-SVG edit-in-place ban + fallback-font measurement
  (`asset-organisation.md`); API-vs-SQL visibility split, `Repository='Products'` rebuild truth,
  scheduled-task semantics (`sql-direct-seeding.md`); anonymous-price analytics leak + cart-probe
  control selection (`b2b-dc-pattern.md`); email-marketing stats/flow/demo-clock seeding
  (`dashboard-seeding.md`).
- **dw-demo-base**: assert-design rules ("what a green assert does not prove") and probe-harness
  discipline (`visual-qa.md`, `browser-automation.md`); blocked-reference re-labelling,
  cap-replacement, and label-vs-CTA process tactics (`demo-tactics.md`); `changeversion.txt` is
  the release-ring pin, never a restart lever (`db-update-recovery.md`, corrected in
  `online-mode.md` too).

### Fixed
- `cheat-sheet.md` wrongly claimed `ParagraphDelete` is the only route around a `ShowParagraph`
  no-op — corrected with the hide-per-device path.
- `online-mode.md` recycle-before-rebuild rule was over-broad — now scoped to raw-SQL relation
  writes; API relation saves are live immediately.

## [4.11.5]

Folds a hosted-demo polish session's learnings across `dw-demo-base`, `dw-extend-scheduled-tasks`, and
`dw-demo-swift`. The through-line is *lying-success on hosted/ACL-locked installs*: several Management API
and SQL surfaces report `ok` while writing nothing, and the fix is always read-after-write verification plus
the right recycle ordering. The rest are Swift 2.4 authoring recipes (facet sidebar, repeater-child editing,
conditional-collapse CSS) that had no documented home.

### Added
- **Hosted index/repository writes report `ok` while the host ACL drops them** (`dw-demo-base/references/online-mode.md`):
  `IndexBuilderSave` is a lying-success surface — `ShopsToIndex` and other builder fields round-trip `ok`
  while the `/Files/System/Repositories/**` XML write is ACL-denied; assert the `IndexBuilderByName` readback,
  not the `ok`. And a Full `BuildIndex` reads `EcomGroupProductRelation` through an app-lifetime cache, so after
  a relation write the canonical order is **recycle first, then Full build** — the rebuild alone is a no-op and
  reads as "API index builds are dead on this host".
- **`RunSqlScheduledTaskAddIn` is write-only** (`dw-extend-scheduled-tasks/SKILL.md`): it surfaces no resultset
  and no message text (`TaskById` gives only `Success`/`Exception`, `lastException` empty even for `SELECT 1/0`).
  Read-verify through it with assertion SQL — `IF (<condition>) RAISERROR(...)` flips the run to `Exception`;
  matched-count probes pin an exact row count. The read path when SQL is only reachable through the task addin.
- **Read a shop with `GetShopByIdQuery` before a round-trip `ShopSave`; set `UsageType` explicitly**
  (`dw-demo-base/references/foundational/commerce-catalog.md`): `GetShopById` returns a `{id,name,permission}`
  stub — the full model comes only from the namespaced `GetShopByIdQuery`, and saving the stub clobbers the
  omitted fields. A `ShopSave` without an explicit `UsageType` defaults `ShopType=0` (none), which hides the
  shop from every typed admin list. Pointer added from `dw-demo-pim/references/canonical-setup-order.md` step 2.
- **Facet sidebar recipe** (`dw-demo-base/references/foundational/swift-building.md` §3): `Swift-v2_ProductListFacets`
  `Layout` (`horizontal`/`vertical`) styles the panel only; sidebar **position** is a 2-column grid row
  (`2Columns_4-8`, facets col 1 / repeater col 2), facets kept on the list page for the AJAX context,
  `mobileLayout=12,12` for phone stacking.
- **Repeater-child storage + the Management API edit path** (`dw-demo-base/references/foundational/content-modelling.md`
  §2): repeater children live in `ItemType_*_Item` rows via `ItemList` + `ItemListRelation`, and
  `GetParagraphById` collapses the repeater to `Items=<listId>` — but that is a read-shape detail, **not** an
  unreachable edit path. Children are created and edited through `POST /Admin/Api/ParagraphSave`: the parent's
  `ContentItem|<Parent>|<Group>|Items` array carries child entries keyed by `ItemId` (empty creates, an existing
  id edits in place), field values ride in the `ModelRawData` JSON string keyed
  `RelationItem|<ChildType>|<Group>|<Field>`, and no recycle is needed (the save fires cache invalidation).
  Proven end-to-end against a Swift 2.4 `Swift-v2_Slider` on DW 10.28.1 (headless create + in-place edit, no
  SQL, storefront rendered the change). `ParagraphSave` is a lying-success surface for this shape — a malformed
  child returns `ok` while creating nothing and can zero the parent list pointer, so round-trip-verify. The
  button/link column is a plain `{Label,Link,LinkType,Style}` JSON binder. (Supersedes the earlier
  "unreachable via API / guarded SQL + recycle" claim, which was wrong.)
- **Conditional-collapse CSS with sibling `:has()` pairs** (`dw-demo-swift/references/re-skin.md`): nesting
  `:has()` inside `:has()` is invalid CSS and the browser drops the whole rule silently (`Element.matches` throws
  `SyntaxError`); use flat `:has()`/`:not(:has())` pairs. Swift grid attribute selectors
  (`[gridrow][container][gridcolumn]`, specificity `0,3,0`) beat a plain `display:none`, so a collapse override
  must be `!important`.

### Changed
- **SQL-via-scheduled-task / SQL-direct content seeding is retired as a demo motion — the corpus is
  API-first** (`dw-demo-swift/references/sql-direct-seeding.md` gutted to a deprecation stub;
  `dw-demo-swift/SKILL.md` trigger + routing; `dw-demo-base/references/foundational/data-access.md`
  "SQL-direct content seeding" reframed as a forensic/teardown reference; `dw-extend-scheduled-tasks/SKILL.md`
  `RunSqlScheduledTaskAddIn` reframed): the admin UI is a SPA over `/Admin/Api`, so if the UI can do it an
  endpoint exists — capture the UI's network call and replay it (MCP → Management API), and **file a learning
  rather than escaping to SQL when the API gets hard**. The developer-extension `RunSql` silent-failure /
  assertion-SQL truth is kept as a diagnostic, with a guard that demo/content work must not use it for edits.
  The one sanctioned scheduled-task-SQL use — the ERP DB-mock's between-demo RESET fixture (`dw-demo-erp`) — is
  unchanged (a deliberate state-reset, not a content-authoring escape hatch).
- **`changeversion.txt`: only a CHANGED token switches the release ring — a same-value re-upload is not a
  reliable no-op** (`dw-demo-base/references/online-mode.md` restart ladder rung 3): observed on an
  `R0-NET…` ring token, re-uploading the current value still recycles the app but leaves the version
  unchanged. Write a distinct token to actually switch (confirm via `info.version`), never re-upload the
  current value expecting a no-op, and record the last-used token so the next switch bumps past it.

## [4.11.4]

Folds the risewell-e2e full-gate run learnings into `dw-demo-base`. The headline is a platform-pinning
correctness rule: a scaffold that validates Distribution content must pin `Dynamicweb.Suite` to the
Distribution's gate-proven platform version — floating `10.*` resolves to latest stable and version-coupled
layers fail *sideways*, green in the static gate and silently broken at runtime. The rest are host-lifecycle,
shell, DB-wizard, and API-key traps that cost real time on a fresh workstation.

### Added
- **Platform pin for content-validating scaffolds** (`dw-demo-base/references/scaffold.md` new §2.2): a scaffold
  that deserializes/validates the Distribution's layers/editions MUST pin `Dynamicweb.Suite` to
  `layers/INDEX.json` `gateProven.dwPlatformVersion` (currently `10.28.1-PreRelease`, == the versions-prompt DW10
  answer). Floating `Dynamicweb.Suite 10.*` resolves to the latest **stable** (`10.27.6`), NOT the gate-proven
  prerelease — `feature-b2b-comms`' flow SQL uses `10.28.1` unprefixed column names that `10.27.6` lacks, so
  strict mode rejects the table and the flow silently can't exist, with the static file-tree gate still green.
  The single exception is a **platform-currency probe** (deliberately floats to test a newer platform). The
  §top "version policy out of scope" note now carries this one carve-out; `SKILL.md` scaffold step, description
  ("pin the platform"), and the "Where to find things" table route to it.
- **pwsh 7+ requirement** (`dw-demo-base/references/setup-checks.md` §1 ritual + note): every recipe/harness verb
  must run from **pwsh 7+**, never Windows PowerShell 5.1 — the null-coalescing `??` (e.g. in `Telemetry.Common.ps1`)
  makes 5.1 parse-fail the whole script before line one. Adds `$PSVersionTable.PSVersion` to the readiness probe.

### Changed
- **Host-launch traps** (`dw-demo-base/SKILL.md` Host lifecycle authority): a **multi-target** scaffold
  (`net8.0;net10.0`) blocks first boot on bare `dotnet run` — pass `--framework <tfm>` (single-target net10 pin
  sidesteps it); and **never capture the PID into `$pid`** — it's a read-only automatic variable, so
  `$pid = (Start-Process …).Id` throws (use `$hostPid`).
- **DB-wizard "Login failed" race + pre-create method** (`dw-demo-base/references/scaffold.md` §3 step 1): the
  setup wizard's "Create database" can report `Login failed` while the DB was in fact created — re-POST Step3 or
  (preferred) pre-create with `Invoke-Sqlcmd -TrustServerCertificate`, **not** `sqlcmd -E -i` (current builds
  reject the `-E`/`-i` combination as mutually exclusive).
- **API-keys are two admin surfaces** (`dw-demo-base/references/mcp-setup.md` Step 6): made explicit that the
  Management API bearer (`CLAUDE.*`) comes from **Settings → System → Developer → Api Keys** while the MCP key
  (`mcp.*` on 10.27.4+/10.28.1) comes from the separate **Settings → Integration → MCP Configurations** surface.

## [4.11.3]

Folds the marine mobile-theming learnings into the demo skills: a new mobile-pass reference for
the Swift frontend, the canvas-fit gate implication in the base visual-QA gate, and routing so
"mobile view" / "canvas stretch" / "overflow at 390" reach it. The through-line is verify-first —
theme-default ≥1.2.0 already ships most of these fixes structurally, so a current-Distribution demo
runs the method to *confirm*, not to re-derive.

### Added
- **Mobile pass reference** (`dw-demo-swift/references/mobile-pass.md`, new): the canvas-fit
  debugging method (measure `document.body.scrollWidth`, NOT `documentElement` — `overflow-x:hidden`
  on body masks a stretched canvas; walk widest-offender-first; finish on a real 390+430 device),
  the Swift 2.4 trap catalogue (fixed-width `swift-v2_menurelatedcontent` mega-menu; non-wrapping
  `NColumnsFlex` rows + the `definitionId`-without-`flexibleColumns` sub-trap; Bootstrap `.flex-fill`
  beating fixed bases → `!important` bases + fixed thumb dims + right-anchored pill; force-open
  `swift-v2_productfielddisplaygroupsaccordion` spec rows; inline-hardcoded logo width with
  SVG-aware `figure`/`svg` selectors; anon CTA living in `swift-v2_productPRICE`), and the
  **verify-first caveat** — theme-default ≥1.2.0 ships most fixes, so patch only the delta.
  Routed from `dw-demo-swift/SKILL.md` (description triggers + "Where to find things" row) and
  cross-linked from `re-skin.md` (the Tier-1 `<customer>_custom.css` slot every fix lands in).

### Changed
- **Mobile canvas-fit is now part of the visual-QA gate**
  (`dw-demo-base/references/visual-qa.md` breakpoints + detector + symptom table + DoD): the
  detector emits `bodyCanvas` (`document.body.scrollWidth - vw`) alongside `overflowX` — the only
  measure that survives body `overflow-x:hidden`; the Definition of done requires `bodyCanvas` 0 at
  390 AND a 390+430 screenshot pair (a single-width pass misses per-row wrap-state divergence — the
  430/390 pill-alignment bug that shipped 14/14 smoke-green on marine). A symptom row routes canvas
  stretch to `dw-demo-swift/references/mobile-pass.md`.

## [4.11.2]

Makes the demo consumption contract mechanical about version currency: the demo skills now pin the
Distribution's latest gate-proven `main` and resolve layers from its machine-readable layer index,
instead of resolving and checking out the newest git tag. A stale or retired layer reference now
fails loudly or auto-corrects to its successor rather than silently materializing a removed layer —
the failure class behind a demo that consumed a layer removed several releases earlier.

### Changed
- **Consumption contract: pin `origin/main` + read `layers/INDEX.json`, never resolve a git tag**
  (`dw-demo-base/SKILL.md` "Versions prompt + Distribution clone/checkout";
  `dw-demo-swift/references/{deserialize-flow,pack-activation,styles-assets}.md`;
  `dw-demo-base/references/{setup-checks,serializer-reference}.md`;
  `dw-demo-swift/references/integrity-sweep.md`): the clone/checkout flow drops the
  `git tag --list … | Sort [version]` newest-tag resolver. Consumers clone once,
  `git pull --ff-only origin main`, assert the index's `gateProven` marker is present, and resolve
  each layer from the live `layers` entries — a name absent from `layers` is looked up under
  `retired` and resolved to its `supersededBy` successor (loud, never silent). Reproducibility is the
  resolved commit SHA recorded in `CUSTOMISATIONS.md`, not a tag.
- **Retired-layer names purged from build instructions** (`dw-demo-swift/references/pack-activation.md`,
  `styles-assets.md`, `header-menu.md`; `dw-demo-base/SKILL.md`): the pack-activation worked example
  and per-pack notes move off the retired `reordering-pricing` / `subscription-orders` bundle names
  onto the live `feature-pricing` / `feature-subscription-orders` layers; the header-nav affordance is
  described as shipping inside `theme-default` without latching onto the retired `theme-nav-polish` /
  overlay names. Retirement notes stay only where they help the reader; instructions no longer build
  from a dead name.

### Added
- **Dead-layer-name sweep in the fold-back content-hygiene gate**
  (`dw-demo-base/references/iterate-plugin.md` Step 1b §5 + verification gate + anti-patterns): every
  fold that names a Distribution layer sweeps the name against `INDEX.json` (the source of truth) and
  rewrites a retired name to its `supersededBy` successor. Deliberately kept out of
  `scripts/validate-skills.py` so the index stays the single source of truth rather than forking a
  retired-name blocklist that drifts on the next rename.

## [4.11.1]

Folds a demo-build session's design-quality-gate learnings into the demo skills' visual-QA,
orchestrator, and re-skin references: a mechanical definition-of-done that catches the polish
defects a screenshot glance skips, plus the authoring traps that make such a gate pass silently.

### Added
- **Image-band height is a Tier-1 visual-QA item, mechanically gated**
  (`dw-demo-base/references/visual-qa.md` detector + eyeball + symptom table + DoD;
  `dw-demo-swift/references/re-skin.md` verification): stock image components carry no
  serialized height field, so a swapped-in portrait crop or slider cover-card renders at full
  column-width height and dominates the fold — a defect distinct from a stretched image. A new
  `tall` detector flags any image band taller than a configured fraction of the viewport; the
  durable fix is a Tier-1 theme-CSS cap (`aspect-ratio` + `max-height` + `object-fit: cover`).
- **PLP list asserts row-presence AND per-row content, not HTTP 200**
  (`dw-demo-base/references/visual-qa.md`): a list-mode product page can return 200 while
  rendering zero rows (empty/not-yet-repopulated index, mis-scoped shop). A new detector asserts
  row count ≥ `minRows` and that each row carries its required-field selectors (thumbnail / SKU /
  price / add-to-cart); an empty or field-short list behind 200 is a named finding, never a pass.
- **The programmatic detectors are the mechanical definition-of-done**
  (`dw-demo-base/references/visual-qa.md`): the `overflowX` / section-gap / stretched-image /
  placeholder detectors are framed as a blocking pass/fail run before eyeballing, not a checklist
  the agent may skip.
- **Design sign-off — taste stays human without blocking automation**
  (`dw-demo-base/references/orchestrator.md` acceptance criteria; `visual-qa.md` DoD): a stamped,
  non-blocking sign-off leg that reports SKIP ("awaiting human sign-off") until a sign-off
  artifact exists, then PASS — so visual taste gets a human decision on the keeper screenshots
  without a build-blocking pause (the one blocking human gate stays the impact sign-off).
- **Authoring detector/probe scripts — three silent-false-green traps**
  (`dw-demo-base/references/visual-qa.md`): Playwright `page.evaluate` passes exactly one arg
  (pass an options object); PowerShell `ConvertTo-Json` unwraps a single-element array to a scalar
  (normalise scalar-or-array on the JS side); and a PowerShell local that is a case-variant of a
  parameter silently aliases it (`$Body`/`$body` — name the local distinctly). A probe run that
  emits zero probes must never be reported as PASS.

## [4.11.0]

Folds eight learnings from two 2026-07 demo-build runs (a customer build dispatch and a
Swift 2.4 profiles key test) into the demo and staged-foundational skills.

### Added
- **Swift 2.4 sign-in profiles / switch user** (`dw-demo-swift/references/customer-center.md`
  §6, routing row + description trigger): profiles (same-username `AccessUser` rows +
  `AccessUserIsLogin`, `ListUserProfiles`/`UserProfilesTemplate` paragraph settings,
  `DwSwitchUserUniqueId` → `StartSwitchUser`) vs impersonation
  (`AccessUserSecondaryRelation` + `CanImpersonate`) — two separate mechanisms, easy to
  conflate; the zero-custom-code picker recipe (clone rows + `NEWID()` unique ids + distinct
  customer numbers, master `IsLogin=1`, one restart; per-profile isolation free via
  `PriceUserCustomerNumber` + `UseUserID`); the `?ShowProfiles=1` sign-in-page picker quirk
  (no stock header entry point); and the platform-honesty rule — the 10.29+ gate does not
  bite on a 10.28.1-PreRelease build (a PreRelease is effectively the next stream), so say
  so when a demo shows features the customer's GA version lacks.
- **Checkout delivery date / custom order fields**
  (`dw-demo-swift/references/checkout-order-fields.md`, new reference + routing row): the
  stock delivery-date beat needs NO custom order field (`EnableDeliveryDate` on the
  checkout paragraph posts into the native `OrderShippingDate` column); order-field values
  live in per-system-name `EcomOrders` columns, so an `EcomOrderField` definition without
  its matching column breaks every order read (`IndexOutOfRangeException` in
  `ExtractOrderFieldValues`); MCP `create_order_field` always violates
  `DW_FK_EcomOrderField_EcomFieldType` (upstream bug — use the SQL contract).
- **Order-line price seeding rules**
  (`dw-demo-base/references/foundational/commerce-orders.md`, pointer from the dw-demo-pim
  order-seeding appendix): change the default currency → restart → THEN seed (pre-restart
  seeding produces ×100 unit-price artifacts); qty-tier `EcomPrices` rows silently reprice
  explicit unit prices; `add_products` writes only unit-price columns, so backfill line and
  order totals in SQL and sanity-sweep for exponent artifacts.
- **In-place platform update: pre-update backup + content-count gate**
  (`dw-demo-base/references/foundational/setup-upgrade.md`, `dw-demo-base/SKILL.md` routing
  row): before any in-place update on a host with non-regenerable content,
  `SELECT COUNT(*) FROM ItemList` + `BACKUP DATABASE`; after, counts must match — an
  in-place update cycle has been observed to empty `ItemList`/`ItemListRelation`/child item
  tables with no error, and without a backup the content is a hand re-author.

### Changed
- **Silent no-op catalogue extended** (`foundational/extend-mcp-tools.md` §5):
  `patch_products_safe` against a variant `EcomProducts` row echoes the requested values
  (the echo is the input model, not a post-write read) while the row stays NULL — the SQL
  sweep is the canonical variant-enrichment surface; `copy_page` with
  `destinationParentPageId=0` lands the copy in area 1 unless `areaId` is passed
  explicitly. `dw-demo-pim/references/canonical-setup-order.md` step 14 now names the SQL
  sweep as canonical and the never-trust-the-echo rule.

## [4.10.0]

Retires the external scrub-list file: the fold-back's sanitize gate now derives the
engagement-token list in-session, from the material being folded, instead of reading a
per-engagement file that routinely did not exist at the documented path.

### Changed
- **`dw-demo-base/references/iterate-plugin.md`** (Step 1a): the grep pack's token list is
  enumerated in-conversation each fold — any token that could leak is by construction present
  in the material being folded (notes, learnings file, demo folder, `CUSTOMISATIONS.md`).
  The enumeration checklist now names the shapes to cover: brand names incl. misspellings and
  slugs, hostnames, persona/account names, engagement domain vocabulary (field names, example
  products), and demo-minted ids/paths/credentials. The constant packs (session-relative time,
  customer-path shape) are unchanged.
- Added a mandatory **adversarial re-read** of the staged diff: for every concrete string, ask
  "Dynamicweb-generic, or engagement-derived?" — the grep catches only enumerated tokens; the
  re-read catches the rest.

### Removed
- The `scrub-list.txt` file mechanism (location contract, stub-creation step, "when to expand
  the known-names list" section) and its `Get-Content` in the final pre-commit grep.

## [4.9.0]

Splits the publish path into its own reference and folds a second hosted-publish build's
learnings into it — including a serializer gap that silently empties every product index.

### Added
- **`dw-demo-base/references/publish-to-hosted.md`** (new): the local→hosted publish playbook,
  moved out of `online-mode.md` (which now owns the hosted *build* only) and extended with:
  - **Pre-flight: create custom product fields on the target before the first deserialize.**
    Product fields are column-backed (`EcomProductField` = a column on `EcomProducts`), and the
    engine's schema-sync only walks `EcomProductGroupField` — so a deserialize lands definitions
    whose columns do not exist. The result is a 500 on every product read *and* a `Full` index
    build that returns `status: ok` while indexing **zero documents**, install-wide. Includes the
    deadlock (the field can then be neither dropped nor created) and its only exit, plus the
    duplicate-SystemName trap that re-creates the same zero-document failure.
  - **Publishing onto an install that already has content**: id collisions on a stock Swift
    catalog — a variant group whose target twin is a colour group swallows the demo's options and
    renders no selector at all while the variant products index perfectly; and the variant
    *combination* table is identity-PK, so its rows never land and **every add-to-cart is silently
    refused** (the only trace is `Not a valid variant combination` in the event log — the POST still
    returns 200). Rebuilding the combinations then overwrites the variant rows' own weight/price from
    the master, which `ProductSave` cannot put back (it no-ops on variant rows) — only a re-deserialize
    can.
  - **Indexes**: the repository *definition* travels, the built segments do not (copying them gives
    a PLP with a product count and no cards); a repository uploaded into a running app needs a
    restart before its facets resolve.
  - **Derive-on-save item fields** do not survive a deserialize (the logo-width canary), and the
    repair must be the **last** write — it is a plain `ParagraphSave`, so any later deserialize
    reverts it and a publish that ends with "re-deserialize to fix X" undoes every such repair.
    Plus `IsDryRun` before every hosted deserialize.
  - Orders ride a plain `SqlTable` predicate, though no shipped example config includes them.

### Changed
- **`online-mode.md`** — now scoped to building on a hosted install; the publish section moved to
  the new reference. Two corrections:
  - **Upload**: `allowOverwrite=true` (an undocumented form field) replaces the delete-before-upload
    workaround. Success is `model` being a **list**, never `status: ok` — a refused batch reports
    `ok` with a `duplicates` object and writes nothing, and one pre-existing name drops the batch's
    new files too.
  - **Restart ladder**: the CloudHosting control files are a Dynamicweb Cloud affordance, not a
    property of every hosted install. Confirm the file is *consumed*; a partner-hosted install can
    accept `recycle.txt`/`restart.txt` and never act on them, which means rung 3 does not exist there.
- **`serializer-reference.md`** — the predicate `mode` enum is version-scoped: **`Replace`/`Merge` on
  0.8.x** (`Deploy`/`Seed` are *rejected*, not aliased — `ConfigLoader.ValidatePredicates` throws), the
  run's mode moves into the JSON body, and `IsDryRun` is available. A config authored for the wrong
  engine major 500s **every** Serializer call, including the read-only settings query — so
  `GET /Admin/Api/SerializerSettings` is now prescribed as the one-call config-validity probe.
- **`dw-demo-swift/references/deserialize-flow.md`** — the 0.6.9-stamped two-pass `?mode=` flow now
  carries a pointer for 0.8.x callers.

## [4.8.0]

Adds the local→hosted **publish path** to the online-mode reference and retracts the
claim that a cloud install cannot be restarted.

### Added
- **Publishing an existing local demo to a hosted install** (`dw-demo-base/references/online-mode.md`):
  the three-transport migration (content via Serializer passes, files via `/Admin/Api/Upload`,
  commerce via `SqlTable` predicates), order of operations, and the deserialize semantics that
  decide the outcome — `Replace` upserts but never deletes (deserialize into an emptied area or
  get a hybrid page tree), the deserializer creates missing areas itself (do not pre-create one),
  orphaned rows hide behind a missing area id, only ACTIVE grid rows are exported, identity-PK
  relation tables collide by auto-id, and a row referencing an absent parent fails the whole batch.
  Plus the settings that never ride a content export (`CustomHeadInclude`, area/market bindings,
  `urlInlcudeAreaType`, `includeProductIdInUrlNames`, sitemap cache, the `1_none.svg` icon sentinel)
  and cross-install page-id remapping.

### Changed
- **`/Admin/Api/Upload` never overwrites** (`online-mode.md` file-upload recipe): an existing name
  comes back as `status: ok` with the skipped names in `model.duplicates` and the file unchanged.
  Delete before re-uploading; assert on `duplicates`, not on `status`. Generalised to list-command
  ids: every `*Delete` taking `Ids` wants the `modelIdentifier` shape, not a bare name.
- **Serializer AddIn versions must match across installs** — the mode names were renamed
  (`Deploy`/`Seed` → `Replace`/`Merge`), so a config authored against one build 500s the other.

### Removed
- **Retracted: "you cannot restart a hosted site"** (`online-mode.md`, `dw-demo-base/SKILL.md`
  routing row). A cloud install has a restart surface — the `Files/System/CloudHosting/` control
  files (`recycle.txt`, `restart.txt`, `changeversion.txt`), canonical in `dw-setup-config`. The
  cache-refresh recipe stays as the first rungs of a flush-then-restart ladder, because some global
  settings do not take effect on a flush alone.

## [4.7.1]

Folds the learnings from a 2026-07 dual demo-host UI pass: two hosts had shipped
with silently-missing Style assets, and several MCP write tools were caught
reporting success without acting.

### Changed
- **Theme staging is now a mandatory deserialize step + readiness gate**
  (`dw-demo-swift/references/deserialize-flow.md` "Stage the theme's Style assets",
  new `integrity-sweep.md` Check 8, `dw-demo-base/references/visual-qa.md`
  definition-of-done): the Swift repo ships only `ColorScheme.config` — no
  `<id>.{json,css}` pairs — while serialized Area rows arrive wired to
  `swift`/`buttons`/`fonts`, so `TryGet*Style` silently emits nothing and the
  storefront renders in serif fallback that "looks almost right". Stage
  theme-default's three pairs + rewire Areas, and gate readiness on the three
  emitted style links plus a designed-looking full-page screenshot.
- **Silent no-op catalogue extended to deletes, index builds and passwords**
  (`foundational/extend-mcp-tools.md` §5, `surface-priority.md`): `delete_area` /
  `delete_users` / `delete_paragraphs` return `succeeded:1` and delete nothing;
  `build_product_index` reports a completed build while writing only the
  `LastUpdated` marker (Admin UI Repositories → Build Full is the working path;
  verify by shard-file mtimes); `update_users` accepts and drops a `password`
  property. Round-trip every demo-critical write.
- **PLP list layout + thumbnail lever** (`foundational/swift-building.md` §3
  symptom table): the surface-serialized shop repeater ships
  `GridLayoutDesktop='list'` — list is the intended layout, keep it; the
  full-bleed-image failure mode is the card image item's `Width='auto'` (→
  `w-100`), and a px value is the thumbnail lever. Also documents the
  `ShowAlternativeImageOnHover` NRE on products without a `DefaultImage`.
- **Local demo-host bootstrap conventions** (`dw-demo-base/references/scaffold.md`
  §3): admin login on local demo hosts is always `Admin`/`Admin1` (zero-lookup
  during live demos; hosted installs keep real secrets), and the wizard-seeded
  `Standard` area (AreaId 1) is deleted before the host counts as scaffolded
  (SQL — MCP `delete_area` is a silent no-op).

## [4.7.0]

Folds the last three Truvio Distribution release cycles into the demo skills
(Swift 2.4 base split, sample-data 2.0.x, theme-default consolidation) plus the
wizardless host bootstrap.

### Changed
- **Staging story rewrite — the Swift 2.4 base split** (`dw-demo-swift/SKILL.md`,
  `references/deserialize-flow.md`, `dw-demo-base/SKILL.md` artifact table): `base` is
  now FRAMEWORK-ONLY (16 SQL sets in `replace/_sql/`, replace-only, zero content/pages);
  ALL Swift content deserializes from the new `surface-swift` surface layer (both areas +
  merge tree + `UrlPath` + its own 128 item-type XMLs); demo catalog + identities ship as
  `sample-data` `merge/_sql` (`catalog.sql` + `identities.sql`). Composition order:
  base → sample-data catalog → content surface(s) → feature fragments. Current cycle:
  Swift 2.4 / DW 10.28.1-PreRelease (stable re-prove pending).
- **Mandatory area binding on DW 10.28+** (`deserialize-flow.md` §7/§8, `customer-center.md`
  pricing notes): bind `AreaEcomShopId`/`AreaEcomCurrencyId`/`AreaEcomLanguageId` after
  deserialize + restart — DW 10.28 resolves an unbound area's currency from the area
  CULTURE (en-US → USD), not `CurrencyIsDefault`.
- **Wizardless host bootstrap** (`dw-demo-base/references/scaffold.md` §3): the setup
  wizard is fully HTTP-drivable (Step2 files → Step3 schema ~6 s / ~260 tables → Step4
  admin), trial license via `POST /Admin/License/TrialInstallStep` — no browser step
  anywhere in bootstrap; ~40 s total vs ~20 min manual. Never pre-provision
  `GlobalSettings.Database.config` against an empty DB (it hides the schema step); the
  DB state (schema + active Administrator) is what decides wizard-or-no-wizard.
- **theme-default consolidation** (`header-menu.md`, `re-skin.md`, `styles-assets.md`):
  the overlay concept is retired — `theme-nav-polish` is folded into `theme-default`'s
  `default_custom.css`; `theme-default` is the ONE presentation layer and the re-skin
  ladder starts FROM it; opt-in nav icons bind to DW stock `/Files/Images/Icons` (no
  custom icon set); the navDepth obligation moved to
  `layers/surface-swift/surface.contract-notes.json`.

## [4.6.0]

Adds the Swift header-menu affordance playbook to `dw-demo-swift`.

### Added
- **`dw-demo-swift/references/header-menu.md`** — "Header menu: make it read as a menu."
  Documents why a fresh Swift bar is flat (childless top nodes → the
  `Swift-v2_MenuRelatedContent/Menu.cshtml` `nodesExist` gate), the `save_groups`
  nav-depth authoring recipe (the data prerequisite), the shared `theme-nav-polish`
  default (composed as an always-on edition `overlays` entry), and the three
  interaction platform-truths that each cost real debugging time: the Popper-gap
  `:has(> .show)` bridge (LRN-nav-03), the `::before`=icon / `::after`=underline caret
  collision (LRN-nav-04), and the dropdown `min-width:100%` reach fix (LRN-nav-05).
  Opt-in icons are keyed on a neutral `data-nav-icon` hook. Linked from SKILL.md and
  `references/templates.md`.

## [4.5.1]

Fixes the frontmatter-load defect that made 31 of 32 skills fail to activate, and
closes the validator gap that let it ship.

### Fixed
- **31 `skills/*/SKILL.md` frontmatter now parse as valid YAML.** Every affected
  `description:` value carried a second `": "` (the `… Triggers: … Non-triggers: …`
  pattern) as an unquoted plain scalar, which a real YAML parser reads as a nested
  mapping and rejects with "mapping values are not allowed here" — the loader's
  "error loading frontmatter". Each description is now single-quoted (content
  verbatim; internal `'` doubled). `dw-demo-base` was already valid and is
  untouched. The ~3,500 `~/.claude/plugins` cache failures were copies of these 31
  and clear once the fixed skills reinstall.

### Changed
- **`scripts/validate-skills.py` gains a strict frontmatter YAML pass.** The prior
  homegrown parser never surfaced the `": "` trap, so the defect passed validation.
  A new `check_frontmatter_yaml()` parses each SKILL.md frontmatter with PyYAML
  (falling back to a targeted `": "` heuristic when PyYAML is absent) and requires a
  mapping carrying both `name` and `description`. Verified to fail on the pre-fix
  frontmatter and pass on the fixed tree.

### Note
- The Verdanta re-validation skill folds (LRN-VRD-03 Swift catalog `ProductsFrontend`
  query, LRN-VRD-05 recipe notes) were already folded in full by v4.4.0 (PR #48);
  re-verified accurate on base 2.4.0 (base still references `ProductsFrontend`, so the
  authoring step stands). No further skill content changes here.

## [4.5.0]

Folds the ten `solmetex-impladent` demo-build learnings into the demo skills
(`dw-demo-base` + `dw-demo-swift`). All demo-side; no bundle or frontmatter changes.

### Added
- **`dw-demo-base` artifact-hygiene rule (SKILL.md).** New always-on output-path
  contract: canonical `notes\qa\` / `notes\logs\` / `notes\snapshots\` scratch layout,
  a demo-root allowlist, and an evidence-naming rule (name for what it IS, never
  security-suggestive). `visual-qa.md`, `browser-automation.md`, the host
  `Start-Process` recipe, and `scaffold.md` §2.1 (`.gitignore`) now name their output
  dirs explicitly. (LRN-01)

### Changed
- **`dw-demo-base` keystone wiring.** `orchestrator.md` + `assets/agent_skills.config.json`
  prefer real project-relative copies into `<demo>\.claude\skills\dw-demo-*`; document the
  gsd-tools loader containment guard (absolute paths and junctions both inject zero skills). (LRN-02)
- **`dw-demo-base` MCP approval pre-seed.** `mcp-setup.md` writes `.claude/settings.local.json`
  with `enabledMcpjsonServers` at `.mcp.json` time; template updated. JSON-RPC stays the
  unattended path. (LRN-03)
- **`dw-demo-base` host lifecycle + scrape preflight.** Stop recipe gains "never force-kill
  during an index build" (LRN-04); `demo-tactics.md` gains a redirect-chain scrape preflight
  into `extracts\` (LRN-10).
- **`dw-demo-swift` index rebuild (integrity-sweep Check 5).** Resolve `BuildName` from the
  `.index` `<Build Name>` (never literal `"Full"`), build twice for 2-instance indexes, assert
  every instance fresh, corrupt-instance recovery recipe. (LRN-04)
- **`dw-demo-swift` Files.index hang, dotted legacy URLs, PDP master price, site-root bind,
  voucher multi-use.** integrity-sweep classifies stock `Files.index` running/0-0 as known
  non-blocking (LRN-05); `dw10-canonical-surfaces` flags `.htm`/`.asp` rows as IIS-only (LRN-06);
  `customer-center` narrates the PDP "from" price as expected (LRN-07); `deserialize-flow` makes
  "bind site root" an explicit post-deserialize step (LRN-08 skill half); `cheat-sheet` documents
  demo-voucher seeding (LRN-09).

## [4.4.0]

Folds from a full clone/layers/editions re-validation on the current Swift 2.3 / DW 10.27.x line.
All demo-side; no bundle or frontmatter changes.

### Changed
- **The Serializer installs from the public NuGet package `Truvio.Commerce.Serializer` (0.6.9-beta+),
  not a repo clone.** Load-bearing: the old `$env:DW_SERIALIZER_REPO` clone requirement blocked a
  verbatim partner at the first deserialize (the engine isn't bundled in the partner toolkit).
  `serializer-reference.md` "Installation" now adds a `PackageReference` + `dotnet restore` (no manual
  DLL build, no copy into `bin/Debug/<TFM>/`); the engine-repo clone is **optional**, for internals
  deep-dives only. The `Serializer.config.json` is staged from the base layer's `config/` tree.
- **Deserialize requires an explicit `?mode=replace` then `?mode=merge` on engine 0.6.9-beta.** A
  mode-less POST targets the legacy `deploy` folder and returns HTTP 400 `deploy contains no YAML
  files`. `deserialize-flow.md` §4 (both passes now name their mode) + `serializer-reference.md`
  "Replace vs Merge".
- **No plaintext user passwords in the git-tracked `CUSTOMISATIONS.md`.** Keep demo logins in the
  gitignored `notes/credentials.local.md` and reference them by pointer. `customisations.md` +
  `assets/CUSTOMISATIONS.md.template`.

### Added
- **`ProductsFrontend` catalog-query authoring is a required PIM step.** The Swift catalog app resolves
  its PLP/PDP index query against a `ProductsFrontend` repository the scaffolding-only `base` layer does
  not ship — an authored catalog with a working `Products.index` still renders an **empty PLP** until
  the query exists. `canonical-setup-order.md` step 17 (author it, or point the catalog paragraphs at
  your own `Products/` repo; no-op if a future base ships a stub).
- **Three MCP/SQL authoring gaps documented as canonical recoveries.** `create_products` ignores
  `languageId` → products land on the master language and are invisible on a non-default-language
  storefront (`pim-localization.md` + `canonical-setup-order.md` steps 9/10); `save_prices` can't scope
  a contract price by customer number → SQL `PriceUserCustomerNumber` (`commerce-b2b.md`, contract price
  is native zero-code); no MCP password tool → the passwordless-user trap, recover via plaintext SQL
  under `EncryptPassword=False` (DW rehashes on first login) (`users-permissions.md` §13).
- **Feature layers may ship a declared, compile-optional provider** via a `layer.json` `customCode`
  block stating what works zero-code vs. what the opt-in compile adds. The base layer stays
  zero-custom-code. `pack-activation.md` §5 + §12 — worked example `reordering-pricing`: contract price
  is zero-code, quantity-tier enforcement needs the §6 opt-in compile.
- **Minor recipe notes.** Cart proof needs a browser — Swift's add-to-cart is client-side JS/AJAX, not
  curl (`commerce-b2b.md`); renaming an Area re-slugs its frontend URLs (`deserialize-flow.md` §3);
  `save_pages` does not persist `urlName` / `navigationTag` / `hidden` → SQL touch-up (`data-access.md`
  + `cheat-sheet.md`); the MCP API key prefix is `mcp.<hex>` on DW 10.27.4 (Management API token stays
  `CLAUDE.<hex>`) (`mcp-setup.md`).

Touched: `dw-demo-base` (`references/serializer-reference.md`, `mcp-setup.md`, `customisations.md`,
`assets/CUSTOMISATIONS.md.template`, `references/foundational/{pim-localization,commerce-b2b,
users-permissions,data-access}.md`), `dw-demo-swift` (`references/{deserialize-flow,pack-activation,
cheat-sheet}.md`), `dw-demo-pim` (`references/canonical-setup-order.md`).

## [4.3.0]

### Changed (BREAKING — distribution model)
- **One consolidated Distribution repo.** The three clone-source repos of 4.2.0
  (`Truvio.Commerce.Serializer.Baselines`, `Truvio.Commerce.DemoThemes`, `Truvio.Commerce.FeaturePacks`)
  collapse into a single repo — `justdynamics/Truvio.Commerce.Distribution`. `DemoThemes` and
  `FeaturePacks` are **archived**; their themes and packs are now **layers** in the Distribution. Demos
  clone the one repo (per-demo, into `<demo-root>\distribution\`) instead of three.
- **Pin moves from commit SHA to an annotated git tag.** 4.2.0 pinned the cloned `main` commit SHA;
  4.3.0 pins the **annotated tag** `layers/<name>/<semver>` (or `editions/<name>/<semver>` for a whole
  gate-proven composition). Resolve the latest patch for the target minor, `git checkout` the tag, and
  record that tag in `CUSTOMISATIONS.md` as the reproducibility pin.
- **Layer + edition vocabulary.** Artifacts are `layers/<name>/` (each a `kind`: base | catalog | feature
  | theme | surface | sample-data) plus `editions/<name>.json` (named compositions). The Swift baseline is
  the `base` layer; a feature pack is a `feature` layer (`pack.json` → `layer.json`); a demo theme is a
  `theme` layer (disk-overlay `files/`, mirrors `wwwroot\Files\`); headless is the `headless` `surface`
  layer. Mode dirs `deploy/`+`seed/` are now `replace/`+`merge/` at the layer root (no
  `baseline-fragment/` wrapper for packs).
- **Serializer mode names `Deploy`/`Seed` → `replace`/`merge`** (engine `v0.6.9-beta`+; `deploy`/`seed`
  remain accepted aliases, and the predicate `"mode"` field keeps the `Deploy`/`Seed` enum spelling). The
  deserialize second pass is `?mode=merge`.
- **Env vars collapsed.** `$env:DW_BASELINE_REPO` / `$env:DW_PACKS_REPO` are replaced by a single optional
  `$env:DW_DISTRIBUTION_REPO` pointer; setup-checks probes `git` + a writable `<demo-root>\distribution\`
  clone target.
- **Unchanged from 4.2.0:** the `base` layer stays **scaffolding-only** (empty catalog by design) and the
  demo catalog is still authored **per-demo via `dw-demo-pim`** — now with the `fixture-catalog` layer /
  `swift-demo` edition as the ready-catalog alternative. Packs remain catalog-self-sufficient (`PACK-<NAME>-*`).
- Touched: `dw-demo-base` (SKILL.md, references/setup-checks.md, serializer-reference.md, scaffold.md),
  `dw-demo-swift` (SKILL.md + deserialize-flow.md, pack-activation.md, styles-assets.md, templates.md,
  paragraphs.md, re-skin.md, asset-organisation.md, customer-center.md, admin-ui-authoring.md,
  integrity-sweep.md), `dw-demo-pim/references/access-surfaces.md`,
  `dw-demo-headless/references/headless-baseline.md`.

## [4.2.0]

### Changed
- **Distribution is `git clone`, not releases.** The Baselines
  (`justdynamics/Truvio.Commerce.Serializer.Baselines`) and FeaturePacks
  (`justdynamics/Truvio.Commerce.FeaturePacks`) repos are now consumed by **cloning `main`** (or a
  sparse-checkout of `packages/swift/2.3` / `packs/<name>/`) — all release tags and zips were deleted,
  so `gh release download` and the `swift/<version>` / `packs/<name>/<version>` tag resolution no
  longer work. The reproducibility pin is the **commit SHA** the demo cloned, recorded in
  `CUSTOMISATIONS.md`. Retired the 4.0.1 "Tag resolution / latest-patch" snippet and the `gh release
  download` recipes; setup-checks now probes `git` (plus `gh` authenticated for private-repo clone
  over HTTPS). `$env:DW_BASELINE_REPO` / `$env:DW_PACKS_REPO` remain as clone-source overrides. Folded
  into `dw-demo-base` (`SKILL.md` "Versions prompt + per-demo artifact clone", `references/setup-checks.md`,
  `references/serializer-reference.md`), `dw-demo-swift` (`references/deserialize-flow.md` §1/§3/§4,
  `references/integrity-sweep.md`, `references/styles-assets.md` — DemoThemes cloned for consistency).
- **The Swift baseline is scaffolding-only.** `packages/swift/2.3` ships framework + starter content
  structure + starter pages and **zero sample catalog** (no EcomProducts/Groups/Prices); a `swift-2.3`
  deserialize lands framework + pages + starter content and an **empty catalog** by design. Dropped
  all catalog row-count expectations; the demo's catalog is authored **per-demo** via the `dw-demo-pim`
  recipes (routed there explicitly). Retired the interim "deploy + seed-content-without-catalog fork"
  framing. Folded into `dw-demo-swift` (`SKILL.md` Step 0 "Baseline shape", `references/deserialize-flow.md`
  §3/§4/§9).
- **Feature packs are catalog-self-sufficient + clone-distributed.** Each pack ships its own demo
  products (`PACK-<NAME>-*`) and never references base-baseline catalog rows, so pack behaviors have
  data even against the scaffolding baseline. Packs clone from the FeaturePacks repo `main` (release
  zip/tag language retired). Documented the subscription-orders disabled `Place recurring orders`
  scheduled task and the reordering-pricing quick-order deactivate→reactivate known-limitation. Folded
  into `dw-demo-swift` `references/pack-activation.md`.

## [4.1.0]

### Added
- **next/image SSRF guard vs local DW backends** (`dw-demo-headless` headless-frontend.md): Next
  15.6+ rejects loopback/private upstream hosts with a 400 even when `remotePatterns` match; gate
  `images.dangerouslyAllowLocalIP` on the backend host being local, and rebuild — the flag is baked
  into the build.
- **Autonomous/headless MCP transport fallback.** The Claude-client project-server approval is an
  interactive-only gate — an unattended agent can wait on "Pending approval" forever. `dw-demo-base`
  `mcp-setup.md` now documents the sanctioned fallback: the DW MCP endpoint (`/admin/mcp`) is plain
  **JSON-RPC 2.0 over HTTPS**, so with the API-Key bearer the full tool surface (~393 tools on DW
  10.27.x) is directly callable (`initialize` → `tools/list` → `tools/call`) — with the caution that
  it bypasses the client's approval layer, so the same guarded-writes discipline still applies.
- **Root `/` binding on DW 10.27.x.** After a baseline deserialize the site root can 404; the binding
  is `Area.AreaDomain` + `Area.AreaFrontpage` (there is **no `AreaDns` table** on 10.27.x), host
  restart required. Folded into `dw-demo-swift` `deserialize-flow.md` §7, cross-linked from the
  `Area`-row cache row.
- **Area/style/item-type restart semantics + nav-label-is-data.** `dw-demo-base`
  `foundational/cache-invalidation.md` now carries three restart-only rows (`Area` row / style asset /
  item-type XML — all startup-materialised, `CacheInformationRefresh` insufficient), the caveat that a
  whole-`Ids` bulk `GetServiceCaches` flush can `500`, and a diagnostic note that nav/menu **labels**
  render live from the **group tree** (group rows, sibling item fields like `Subtitle`), so an
  un-clearable label is usually data, not a "nav cache".
- **Index-instance Warning is benign.** An index-level `State=Warning` caused solely by an unbuilt
  secondary balancer instance is a false alarm — judge by the primary instance's build result + doc
  count. Folded into `dw-demo-pim` `canonical-setup-order.md` Step 16 (both variants).
- **Isolated pack-fragment staging.** Staging a pack fragment into a `SerializeRoot` that still holds
  the base baseline trees **re-deserializes the base seed** — on a re-contented demo that resurrects
  the whole purged sample catalog. `dw-demo-swift` `pack-activation.md` §8 now parks/clears base trees,
  stages the fragment isolated, and restores — stated loudly.
- **MCP recipe gotchas batch** (from live brand-build recipes): `create_variant_combinations` leaves
  `ProductActive`/`ProductPrice` NULL on combos → variants invisible (`foundational/pim-modelling.md`
  §2.5); custom fields index as `CustomField_<SystemName>`, other patterns fail silently
  (`foundational/search-indexing.md`); `import_product_images_from_urls` sets no default image and the
  Swift card NREs on images-but-no-default, degrading the whole PLP (`foundational/pim-modelling.md`
  §2.10); `synchronous: true` on index builds does not actually block — poll
  (`foundational/search-indexing.md`); `save_pages` ignores `urlName` (slug derives from `menuText`) —
  added to the silent-no-op tables in `foundational/extend-mcp-tools.md` §5 + `foundational/content-modelling.md`.
- **Product-completeness checklist.** `dw-demo-pim` `canonical-setup-order.md` now closes with a
  per-product (and per-variant) gate — Active, priced, stocked-or-NeverOutOfStock, a default image,
  texts in every language layer — each with its frontend symptom, run as a SQL sweep.
- **`dw-demo-headless` drift notes.** The two-token trap's failure status is **version-dependent**
  (404 on 10.26.x, 400 on 10.27.x) — assert "a non-401 error", don't pin a code (`headless-backend.md`
  §3); product images live under `assetCategories` **or** `imagePatternImages` — read both
  (`headless-frontend.md` §2); repository/query names must be env-configurable (query name **without**
  the `.query` extension) so a second-backend swap is pure env (`headless-frontend.md` §3 +
  `headless-backend.md` §5); areas can ship with empty ecom bindings (`ecomShopId=""`) so the provider
  must pass `LanguageId`/`ShopId` explicitly on every call (`headless-backend.md` §4).

  All nine folds come from the same autonomous partner-simulation build as [4.0.2] (fresh DW 10.27.4,
  skills followed verbatim), carried through full brand re-content, catalog authoring via MCP recipes,
  feature-pack install, and a headless storefront on a second backend — each verified live.

## [4.0.2]

### Fixed
- **License step folded into the canonical first-run flow.** On a fresh DW 10.27.x install the Setup
  Guide forces `/admin/license` immediately after the database step, before any admin-user setup.
  `dw-demo-base` `scaffold.md` §3 now walks the license step (Suite Trial for demos; ~30-day expiry
  recorded in `CUSTOMISATIONS.md`), with the platform-level detail + headless trial path in
  `foundational/setup-install.md` §7.
- **Headless admin-password recovery documented.** The license gate can skip the set-admin-password
  step, leaving every seeded user inactive with an empty password and no usable admin login.
  `foundational/setup-install.md` §7 documents the one-shot `Program.cs` recovery via
  `Dynamicweb.Security.UserManagement.UserService` (`ChangePassword` + `user.Active = true` + `Save`).
- **Serializer config path corrected (version-sensitive).** On DW 10.27.4 + engine 0.6.8-beta the
  engine reads `Files/System/Serializer/Serializer.config.json`, not the `Files/` root.
  `serializer-reference.md` Step 3 (and the config-path mentions in `deserialize-flow.md`) now stage
  and cite the `Files/System/Serializer/` location; the engine's actual read location wins, confirmed
  by where `SerializeRoot/` is created.
- **Deserialize is a two-POST sequence.** A bare `POST /Admin/Api/SerializerDeserialize` runs the
  Deploy pass only; the Seed pass must be requested explicitly with `?mode=Seed`. `deserialize-flow.md`
  §4 now documents both passes (deploy then seed) for the swift/2.3 deploy+seed baseline.
- **`excludeAreaColumns` semantics clarified.** The setting governs serialize-OUT (which Area columns
  are written to YAML), not deserialize-IN — it does not suppress "source column not present on target
  schema" drift for a baseline captured on an older platform. Recovery (strip the column from the
  STAGED `area.yml`, never the downloaded original) is documented in `deserialize-flow.md` §3 and the
  matching failure pattern in `serializer-reference.md`.

  All five folds come from a fresh-DW-10.27.4 autonomous demo build (Serializer engine 0.6.8-beta)
  following the skills verbatim — each was a real first-run failure.

## [4.0.1]

### Fixed
- **Release-tag resolution: tags carry the patch digit.** The versions prompt collects a *minor*
  Swift version (`2.3`), but distribution release tags are full semver (`swift/2.3.1`) — a literal
  `gh release download swift/<minor>` fails. `dw-demo-base` SKILL.md now ships a latest-patch-for-
  the-minor resolution snippet (gh release list + prefix filter + semver sort), setup-checks and
  styles-assets reference it, and the RESOLVED tag (not the minor) is what gets recorded in
  `CUSTOMISATIONS.md` as the reproducibility pin.

## [4.0.0]

### Changed (BREAKING — distribution model)
- **`$env:DW_VAULT` removed entirely.** The shared machine-wide vault (five slots
  `dw10source/samples/databases/docs/serialized-data`, resolved via `$env:DW_VAULT\INDEX.md`) is
  gone. Demo artifacts are now downloaded **per-demo** into the demo's own `<demo-root>\baselines\`
  folder, so two demos on one machine can pin different versions without collision. `dw-demo-base`
  now asks the user for the demo's **DW10 version** and **Swift version** (the versions prompt,
  recorded in `CUSTOMISATIONS.md`) before any artifact is fetched. `git grep -i dw_vault -- skills/`
  is now zero.
- **Ecosystem distribution repos named directly.** Skills now name the public distribution sources
  instead of "the repo your team designates": serialized baselines from
  `justdynamics/Truvio.Commerce.Serializer.Baselines`, demo themes / style assets from
  `justdynamics/Truvio.Commerce.DemoThemes` (release zips tagged `swift/<version>`), and feature
  packs from `justdynamics/Truvio.Commerce.FeaturePacks` (releases tagged `packs/<name>/<version>`).
  The `$env:DW_BASELINE_REPO` / `$env:DW_PACKS_REPO` indirection now **defaults** to these URLs and
  stays overridable per machine. The Swift design package remains a local clone of
  `https://github.com/dynamicweb/Swift`.
- **`setup-checks.md` reworked.** Dropped the `DW_VAULT` env probe and the five-slot inventory;
  added checks that matter for the download model — `gh` CLI present + authenticated, a writable
  `<demo-root>\baselines\` folder, and the DW10 + Swift versions prompt.
- **DW10 source is now "a local clone (location per machine — ask/discover, never hardcode)".**
  Every `$env:DW_VAULT\dw10source\` citation (PIM/permissions/workflow source-dives, online-mode
  binder disambiguator, canonical-surfaces, surface-priority) was repointed to that wording; the
  source-diving guidance itself is unchanged. The DB fast-restore escape hatch became a per-machine
  local-artifact note (no vault slot).

### Removed
- `dw-demo-base/references/compare-vault.md` (cross-machine vault drift detection — no vault to
  drift) and `dw-demo-base/assets/INDEX.md.template` (vault index template). All links/cross-refs to
  both were removed.
- **Validator `check_no_truvio` purge check removed** (`scripts/validate-skills.py`), per the
  operator policy lifting the `truvio` scrub for the ecosystem repo URLs. The rest of the validator
  (schema, links, BOM, mojibake, TOC/trigger warnings) is intact. `truvio`/`Truvio` now appears only
  in the named distribution-repo URLs.

---

Releases 2.x–3.x: see [docs/CHANGELOG-archive.md](docs/CHANGELOG-archive.md).
