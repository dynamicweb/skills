# Changelog

All notable changes to the Dynamicweb Skills plugin are recorded here. The
`version` field in `.claude-plugin/marketplace.json` tracks these entries.

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
