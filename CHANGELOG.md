# Changelog

All notable changes to the Dynamicweb Skills plugin are recorded here. The
`version` field in `.claude-plugin/marketplace.json` tracks these entries.

## [3.6.0]

### Added
- **Visual QA reference — screenshots become a defect hunt, not a confirmation.** Root cause of
  demos shipping with whitespace bands, misaligned/stretched images, dead slider arrows, and
  horizontal scrollbars: the verify-flow recipe checked functional presence only ("N order rows
  visible", "a change landed") and gave no guidance on what a *failing* screenshot looks like, so
  Playwright inspection confirmed pages instead of critiquing them. New
  `dw-demo-base/references/visual-qa.md` owns the polish gate, run on every demo-critical page:
  - **Programmatic detectors first** (one `browser_evaluate` block): horizontal-overflow offenders
    (`scrollWidth` delta + the element whose right edge IS the scrollbar), broken images
    (`naturalWidth === 0` after the lazy-load scroll-sweep), stretched images (natural vs rendered
    aspect ratio under `object-fit: fill`), and whitespace bands (> 120px gaps between consecutive
    sections) — plus `browser_console_messages` (template NREs render as silently missing
    sections) and `browser_network_requests` (404 assets).
  - **Interaction pass**: a static screenshot cannot verify behaviour — click every visible
    control type once (arrows, tabs, accordions, add-to-cart) and assert a state change.
  - **Eyeball checklist** per screenshot (vertical rhythm, alignment grid, image crops, text
    truncation/placeholders, edge padding, control containment, one visual system, empty shells),
    captured at both desktop and mobile breakpoints via `browser_resize`.
  - **Symptom → owning-fix routing table** wiring the checklist into the 3.5.x fold knowledge
    (6rem spacing default, `slider-nav-outside-expand`, `FieldOptionValue` blanks, `ButtonData`
    error blocks, `DisplayGroups` empty shells, one-paragraph-per-column, `GridRowDefinitionId`,
    service-page chrome leaks) so findings route to documented fixes instead of re-diagnosis.
  - **Fix loop + definition of done**: fixes land on the build-phase action surfaces per
    `surface-priority.md` (Playwright stays verification-only), then re-navigate, re-run
    detectors, re-screenshot both breakpoints; a page is done at zero detector findings, a passing
    interaction pass, and a passing checklist at both widths.
  Wired in: `browser-automation.md` verify-flow gains step 6 (run the visual QA pass);
  `dw-demo-base/SKILL.md` and `dw-demo-swift/SKILL.md` where-to-find tables gain the polish-gate
  row.

## [3.5.11]

### Fixed
- **Scroll-sweep before full-page screenshots and image assertions.**
  `dw-demo-base/references/browser-automation.md` verify-flow recipe: Swift lazy-loads images, so
  `fullPage` captures show blank tiles below the fold and `naturalWidth === 0` reads as "broken
  image" on images that are fine. Sweep the viewport down the page first, then capture/measure;
  verify any natural-width-0 finding with a direct fetch before filing it as a defect.

## [3.5.10]

### Fixed
- **`NavigationPlacement: slider-nav-outside-expand` causes page-level horizontal overflow on
  full-width sliders.** New symptom-table row in
  `dw-demo-base/references/foundational/swift-building.md` §3: the outside-expand swiffy arrows
  render past the viewport edge in a full-width row — the arrow IS the horizontal scrollbar. Default
  to inside placement (empty value) for full-width sliders.

## [3.5.9]

### Fixed
- **Always-visible spec component + the category-id trap on display groups.**
  `dw-demo-base/references/foundational/swift-building.md`: the component table now lists
  `Swift-v2_ProductFieldDisplayGroups` (always visible) beside the accordion — its list field is
  `DisplayGroups`, not `FieldDisplayGroups` — and the symptom table gains its empty-shell row:
  product-category ids are NOT display-group system names; a category-id list resolves to nothing
  and renders an empty shell with no error.

## [3.5.8]

### Fixed
- **Standard `Swift-v2_Row` grid columns render exactly one paragraph.**
  `dw-demo-base/references/foundational/swift-building.md` §2: a second paragraph in the same
  `gridRowColumn` is silently dropped (no error, no admin warning). Compose multi-element sections
  inside one item's fields (e.g. Text + its `FirstButton`) or use a `*Flex` row definition, which
  renders one flex column per paragraph.

## [3.5.7]

### Fixed
- **Component-slider service page: three wirings, three failure smells.**
  `dw-demo-base/references/foundational/swift-building.md` §1 gains the wiring triad for the page
  tagged `ProductSliderService`: (1) `Swift-v2_ServicePage.cshtml` layout — missing returns a full
  HTML document and the injector renders nothing; (2) an `eCom_ProductCatalog` app paragraph in a
  real grid row — missing returns an empty body; (3) the app list template `ProductSlider.cshtml`
  (the `ProductListPartial` dispatcher) — left at the shop default the slider leaks facet/sort/
  load-more PLP chrome into the injected section. Same audit applies to the other service pages.

## [3.5.6]

### Fixed
- **ButtonData item fields must never be seeded with plain label strings.**
  `dw-demo-base/references/foundational/content-modelling.md` (Management-API editing section): the
  render path deserializes stored `*Button*` values as ButtonData JSON; a bare `"Shop now"` throws
  `ConverterException` and replaces the section with a Razor error block. Store full JSON or an empty
  string; sweep seeds for non-empty non-JSON button values. Complements the existing GET/save binder
  asymmetry note.

## [3.5.5]

### Fixed
- **Dropdown/multi-select category-field values must store `FieldOptionValue`, not the display
  name.** `dw-demo-base/references/foundational/pim-modelling.md` §2.8: a stored value that does not
  resolve to an `EcomFieldOption.FieldOptionValue` renders as a blank cell with no error on the
  storefront spec components (admin still shows the raw text); options whose value equals their name
  mask the bug for some rows, so it surfaces as "some attributes randomly missing". Documents the
  comma-separated multi-select convention, `create_field_options` with the
  `ProductCategory|<CategoryId>|<FieldId>` id form for adding missing options, and a post-seed
  orphan-value sweep.

## [3.5.4]

### Fixed
- **BOM configurator data shape: `ProductItemBomGroupId` must be a real `EcomGroups` GroupId.**
  `dw-demo-base/references/foundational/pim-modelling.md` §2.6 now splits the two `EcomProductItems`
  row shapes (fixed component vs configurator slot): a configurator slot references an ecom group
  whose products become the selectable options, with `ProductItemDefaultProductId` as the default; a
  synthetic/unresolvable id silently degrades every row into a one-option pseudo-group named after
  `ProductItemName` (looks like a template bug, is a data bug). Also documents the NOT-NULL
  empty-string convention for `BomProductId`/`BomVariantId` and cross-links the Swift render side
  (`Swift-v2_ProductBom` component row in `swift-building.md` §1).

## [3.5.3]

### Fixed
- **Primary-shop trap: a catalog group related to both the storefront shop and a PIM/data shop can
  resolve its primary shop to the data shop** — the storefront ecom navigation then drops the group
  and the friendly-URL provider stops generating its slug (subset-of-groups sidebar + 404 slugs while
  querystring URLs still work). Documented in
  `dw-demo-base/references/foundational/commerce-catalog.md` §2.3 with the publish-time fix:
  re-save the group via `save_groups` with the storefront `shopId` (replaces the shop relations),
  then restart for the nav-tree/URL-provider caches.

## [3.5.2]

### Fixed
- **Page-state flags: the MCP tool surface cannot express "routable but out of nav".** Sharpened
  `dw-demo-base/references/foundational/swift-building.md` §6 with experiment-verified DB column
  mapping (`active` = `PageActive` = nav visibility, `hidden` = `PageHidden` = routing/404;
  `PageShowInLegend` is legacy and ignored by Swift nav templates). The documented `publish_pages`
  both-flags gotcha extends to `save_pages(active:...)` and `set_page_menu(showInMenu:...)` — all
  three couple the columns, so `active:false` also 404s the page. The utility-page state
  (`PageActive=0, PageHidden=0`) needs Management API `PageSave` or SQL plus a host restart for the
  nav-tree/friendly-URL caches.
## [3.5.1]

### Fixed
- **Grid-row authoring pitfalls from a storefront-polish pass** (a furniture-configurator demo build).
  In `dw-demo-base/references/foundational/data-access.md`: `GridRowDefinitionId` must name an existing
  RowDefinition JSON — an unknown id (e.g. a guessed `5Columns`) renders the row and all its paragraphs
  as **nothing, silently**; and GridRow layout columns (spacing/alignment/gap/colorscheme) are
  SQL-only — the MCP `save_grid_rows` model doesn't carry them and a later MCP save silently reverts
  them, while NULL spacing renders as the Swift 6rem default (the single biggest whitespace generator).
  In `cache-invalidation.md`: the "UPDATE existing row = live" rule is now scoped to CONTENT fields —
  layout-composition columns (GridRow spacing/valign/colorscheme, `Page.PageItemType/ItemId/PageColorSchemeId`)
  behave like structure and need a restart; added rows for navigation-flag and group↔shop-relation
  mutations (nav tree + friendly-URL provider are restart-only); and added the mixed-surface ordering
  rule: **all MCP writes first, SQL for unexposed columns last, one restart**.

## [3.5.0]

### Changed
- **Replaced the blanket "admin UI is never an action surface" guardrail with a phase-scoped
  surface contract.** Root cause of demo builds stalling on human intervention during local
  installation: the verification-only rule had no scaffold carve-out — six statements across the
  demo chain routed every awkward admin-UI operation to "ask the user", and `mcp-setup.md` Step 3
  mandated creating the MCP configuration *by hand* even though the shown-once API key is readable
  off the page by browser automation. The original intent of the guardrail — no admin-UI actions
  for operations MCP or the Admin API can perform, especially on hosted/headless installs — is
  kept and enforced *more* strictly, but scoped to the build phase. The new contract
  (`surface-priority.md` is the canonical statement, with a phase × instance-type matrix):
  - **Two phases, split by the MCP verification gate.** *Scaffold* (local, before the gate): the
    admin UI via the Browser MCP **is an action surface** for the bootstrap one-clicks — create
    the MCP configuration + capture the shown-once key (Step 3 is now agent-driven end-to-end),
    create the Management API key (Step 6 likewise), AppStore install when the csproj route is
    closed, portal downloads. Ladder: script/CLI → Admin API → Browser MCP on the admin UI →
    headless code recipe → ask the user (last resort only). *Build* (after the gate): strict —
    every change lands on MCP → Admin API → direct SQL (local last resort); the admin UI is
    verification-only with **no** "ask the user to click" rung; endpoint discovery goes through
    `/admin/api/docs/`, `dw10source`, or read-only Playwright network watching.
  - **Surfaces by instance type made explicit**: local = MCP + Admin API + direct SQL;
    hosted (cloud) and headless = MCP-if-present + Management API, **no SQL ever**; hosted/headless
    have no scaffold phase (credentials are handed over), so build rules apply from the first
    request.
  - **Install ordering fixed**: the Browser MCP moves to the front of the scaffold sequence
    (machine-level, idempotent) so its tools exist when Step 3 needs them; its fresh-session
    constraint is called out with the restart/headless fallbacks.
  - `dw-setup-install`'s three pause-and-wait clauses become self-service recovery ladders
    (re-bootstrap → recreate config via browser automation → verify; escalate only when every
    automated route is exhausted), and failed portal downloads are fetched via browser automation.
  - Files: `surface-priority.md` (rewritten), `dw-demo-base/SKILL.md` (phase-scoped summary +
    step-3 reorder), `mcp-setup.md` (Steps 0/3/5/6), `browser-automation.md` (scope guard),
    `online-mode.md`, `foundational/extend-mcp-tools.md` §1, `dw-setup-install/SKILL.md`,
    `dw-demo-swift/references/admin-ui-authoring.md` (pointer).

## [3.4.4]

### Fixed
- **Purged the pre-v2 leftovers a style/structure audit found, and refreshed the stale meta-docs.**
  Supersedes 3.4.3's reconnect approach: linking the leftover references kept stale knowledge
  reachable — the durable fix is folding their unique content up and deleting the files.
  The v2 restructure carried four legacy files over verbatim that nothing linked and that newer
  knowledge had superseded or contradicted:
  - `dw-pim-completeness/references/dashboard-widgets.md` and
    `dw-search-indexing/references/product-query-authoring.md` — orphaned MCP payload references
    from the deleted legacy skills, partly contradicted by the corrections in the
    `pim-completeness.md` foundational candidate (3.4.2's `userIds` blocker, dead widget types,
    phantom areas). Their still-unique payload contracts are **folded into the foundational
    candidates** (`CreateDashboardModel`/`AddWidgetModel`/`RepositoryCountWidget` params into
    `pim-completeness.md`, reconciled with the blockers — the example now passes `userIds`; the
    `ProductQueryModel` canonical shape, hard constraints, and typical backlog queries into
    `search-indexing.md`, reconciled with the Shared-folder location rule); the files are deleted.
  - `dw-pim-workflow/references/queries-and-dashboards.md` — orphaned, delegated query creation to
    the deleted `dynamicweb-product-query-creator` skill, and its dashboard half was superseded by
    the candidate. Deleted; its backlog-query examples moved into the candidate fold above.
  - `dw-pim-workflow/agents/openai.yaml` — a stray OpenAI-platform agent config referencing the
    retired `dynamicweb-pim-solution-assistant`. Deleted.
  - `dw-pim-workflow/references/completeness-and-workflows.md` was kept (unique
    `create_or_update_workflows` / `create_or_update_completeness` MCP schemas) and is now linked
    from the SKILL.md instead of orphaned.
  Also fixed three stale prose pointers to deleted skills ("the dashboard skill", "the product
  query creator skill" ×2) in `dw-pim-completeness` and `dw-search-indexing`; fixed the
  Non-triggers routing rows that still pointed at retired pre-v2 skills —
  `dw-setup-install` (`dynamicweb-business-setup-agent` → `dw-setup-config`) and
  `dw-swift-building` (`dynamicweb-solution-installer` / `dynamicweb-business-solution-agent` /
  `dynamicweb-business-setup-agent` → `dw-setup-install` / `dw-pim-modelling` /
  `dw-commerce-catalog`) — and removed `dw-setup-install`'s foundational→demo routing row
  (`-> dw-demo-base`, a boundary violation — now "the presales demo bundle"). Meta-docs refreshed to match the repo:
  `CLAUDE.md` now documents the `type:`/`group:` frontmatter fields all 31 skills carry and uses
  the real `dw-pim-completeness` description as its example; `dynamicweb-skills-structure.md`
  catalog/taxonomy/bundle tables updated to the actual skill names (`dw-render-razor`,
  `dw-render-templatetags`, `dw-render-viewmodels`), the `source` and `demo` areas, all six
  bundles, and no longer points to a nonexistent `CONVENTIONS.md`; `CONTENT-GAPS.md` rewritten —
  its coverage table listed only pre-v2 skill names and its top "gaps with no skill" (search,
  commerce, advanced PIM, upgrades, security) all exist as skills now.

## [3.4.3]

### Fixed
- **Reconnected the two MCP authoring references orphaned by the v2 restructure.** (Superseded by
  3.4.4, which folds their unique content into the foundational candidates and deletes the files.)
  The legacy skills' reference files were carried over verbatim (`dashboard-widgets.md` into
  `dw-pim-completeness`, `product-query-authoring.md` into `dw-search-indexing`) but no SKILL.md
  linked them, and three prose pointers still named skills that no longer exist. Both host SKILL.md
  files gained links to their reference, the stale pointers were replaced with resolvable links,
  and the widget payload duplication between the two references was removed.

## [3.4.2]

### Fixed
- **Documented three MCP dashboard/widget construction blockers that look like "nothing rendered".**
  In `dw-demo-base/references/foundational/pim-completeness.md`, after the clickable-widget table:
  (1) a dashboard created via `create_dashboards` **without `userIds` is invisible in admin** — no
  `DashboardAccessUserRelation` row, so Settings → Dashboards shows "No results" and the area renders
  the built-in default; fix is to pass `userIds` or insert the access relation (one row `Default=1`).
  (2) `RepositoryGridWidget` / `RepositoryListWidget` **render blank rows until the column Sources are
  set**, and the product index uses **short field names** (`Name`, `Number`, not `ProductName` /
  `ProductNumber`). (3) `ColorParameterEditor` / `Threshold*Color` is a **`WidgetColor` named-token
  enum** (valid: White/Red/Yellow/Orange/Purple/Pink/LightGreen/DarkGreen/LightBlue/DarkBlue) —
  hex/Bootstrap names coerce to `None`; the colour is the card background. Plus an ordering note that
  `add_widgets_to_dashboards` appends after existing widgets rather than honouring `order`.

## [3.4.1]

### Fixed
- **Index-build cache trap now covers the MCP value-write surface, not only Direct SQL.** The
  `cache-invalidation.md` "Surface scope" section asserted that MCP `save_*` / `patch_products_safe`
  writes invalidate caches inline and therefore never need the cache table — but the Lucene index
  builder reads product + category-field data *through* the `ProductService` /
  `ProductCategoryFieldValueService` / `ProductCategoryService` caches, which a `patch_products_safe`
  value write does **not** flush. Rebuilding the index after such a write bakes the stale (often
  empty) pre-patch value in, so `get_products_by_query` and dashboard widgets return 0/stale while
  the DB and `get_product_by_id` are correct — previously misdiagnosed as an "index quirk". Corrected
  the false carve-out, added a table row for the value-write surface, and generalized the
  "index-build-reads-through-cache ordering trap" to both surfaces in
  `dw-demo-base/references/foundational/cache-invalidation.md`. The
  `search-indexing.md` rebuild recipe now starts with a mandatory **STEP 0** that flushes those three
  caches via `CacheInformationRefresh` before `BuildIndex`, plus a re-verify step;
  `pim-completeness.md` step 5 carries the same flush-before-rebuild gate for governance-widget
  counts. Also notes a host restart is not a reliable substitute (the `dotnet run` parent/child
  process trap can leave the real host running).

## [3.4.0]

### Changed
- **Separated vendor-generic platform knowledge out of all five demo skills.** An audit found the
  demo skills carried large amounts of authoritative DW10 platform knowledge (≈50–75% of body in
  the heaviest cases) that belongs in foundational skills — demo skills should be flow +
  demo-building only. This refactor relocates that knowledge **without folding it into the real
  foundational skills yet** (a deliberate "prepare to fold up" stage), via two mechanisms:
  - **Mechanism A — already in a foundational skill → reference, don't repeat.** The demo file drops
    the duplicated prose and links to the foundational skill. The two skills referenced this way
    (`dw-integration-framework`, `dw-extend-csharp-api`) are added to the `dynamicweb-presales`
    bundle so the links resolve in a presales-only install (presales becomes a superset).
  - **Mechanism B — not yet in a foundational skill → stage as a fold-up candidate.** The
    vendor-generic content moves into a labeled candidate under
    `dw-demo-base/references/foundational/<target>.md` (header: **FOUNDATIONAL CANDIDATE →
    dw-<target>**), and the demo file points at it. Candidates map 1:1 to a future foundational
    owner, so the eventual fold-up is mechanical (move the body, re-target the pointers).
  - **Result:** **22 candidate files** (~4,700 lines of platform knowledge) now staged under
    `dw-demo-base/references/foundational/`; the demo skills are thinned to flow + pointers
    (`dw-demo-pim` ~1500→527 lines, `dw-demo-swift` ~2500→1148, plus `dw-demo-erp`,
    `dw-integration-bc`, and the platform-heavy parts of `dw-demo-base`). **No foundational skill
    file was edited**, and several pre-existing foundational→demo boundary links were removed in the
    process (the one-way rule now holds cleaner). Candidate targets span `dw-pim-*`,
    `dw-commerce-*`, `dw-users-permissions`, `dw-search-indexing`, `dw-content-modelling`,
    `dw-render-*`, `dw-swift-building`, `dw-data-access`, `dw-setup-*`, `dw-extend-*`,
    `dw-integration-*`, and `dw-source-explorer`.
  - **Next:** fold each candidate into its named foundational skill (sanitized), re-target the
    demo pointers, and extend the presales superset accordingly — one foundational skill per future PR.

## [3.3.10]

### Added
- **Added a `.gitignore` that excludes `notes/`** — the local working directory for fold-back
  drafts mined from demo builds. Those drafts routinely carry customer/engagement names and the
  retired codename before sanitization, so a stray `git add -A` must never be able to stage them
  into this public repo. Closes the gap that let an unsanitized draft slip into a commit.

## [3.3.9]

### Added
- **Encoded the recent structural audit rules into `validate-skills.py` and the authoring guidance**
  so folds and PRs can't silently reintroduce them. New validator checks: `description` over the
  **1024-char** frontmatter cap (**error**); **double-encoded UTF-8 / mojibake** anywhere under
  `skills/` (**error**, the fold-back hazard from CHANGELOG 3.3.7); a **SKILL.md body over 500
  lines** (warning); and a **references/ file over 100 lines without a top-of-file table of
  contents** (warning). Documented all four in `CLAUDE.md` (new "Length budgets and references" and
  "Encoding" subsections, plus the frontmatter cap and the Validation summary) and in the
  fold-back's `Step 3 — Validate` note in `dw-demo-base/references/iterate-plugin.md`.

## [3.3.8]

### Changed
- **Added a top-of-file table of contents to every reference file over 100 lines** (35 files). Per
  Anthropic's skill-authoring guidance, long reference files get a TOC at the top so it survives
  partial-preview reads and gives the model a map of the file's sections. The TOC lists H2 sections
  (flat); files organised at H3 under one or two H2s (`structural-model.md`,
  `completeness-and-workflows.md`) get a nested H2+H3 TOC instead. Anchors follow GitHub's
  heading-slug algorithm. Pure additions — no existing content was changed.

## [3.3.7]

### Fixed
- **Repaired double-encoded UTF-8 (mojibake) across 33 skill markdown files** (1101 lines).
  These files carried text that had been UTF-8-encoded, misread as CP1252, and re-encoded —
  so em-dashes rendered as `â€"`, arrows and box-drawing characters, `§` as `Â§`, `…`, `✓`,
  etc. Repaired with `ftfy.fix_encoding`, which reverses only the damaged byte sequences and
  leaves already-correct characters (including genuine em-dashes in mixed files) untouched.
  Verified: zero residual mojibake markers and zero replacement characters (`�`) introduced
  repo-wide; line endings preserved.

## [3.3.6]

### Changed
- **Split `dw-headless-delivery/SKILL.md` under the 500-line budget** (569 → 104 lines). The
  SKILL.md had grown into a flat `/dwapi/` endpoint catalog. Moved the endpoint-family listings
  (Content, Products, Cart, Checkout, Orders, Users, Favorites, Internationalisation, Loyalty
  Points, Forms, Query, Connectivity) verbatim into a new `references/endpoint-reference.md` (with
  a top-of-file table of contents), and kept the gateway concepts in SKILL.md — authentication,
  the headless architecture rules, and a routing table that links each family to its section in
  the reference. No endpoint content was lost or changed.

## [3.3.5]

### Changed
- **Trimmed the `dw-demo-base` description under the 1024-char frontmatter limit** (1093 → 984
  chars). The activation description had grown past the hard cap and risked truncation by
  frontmatter parsers. Dropped redundant route-phrases ("register the skills to GSD", "what runs
  the build", "publish this update") and an explanatory parenthetical; every distinct trigger
  concept — scaffolding, MCP-load failure symptoms, fresh-machine/online modes, the orchestrator
  and fold-back routes, sister-skill ordering, and the read-only `customer-context` contract — is
  preserved.

## [3.3.4]

### Changed
- **Recast bare prohibitions as positive (or paired) instructions across the skill set.** Models
  follow "do A" more reliably than a bare "don't do B" — a bare prohibition raises B's salience and
  leaves the target underspecified. Converted bare directive prohibitions to positive form where the
  target was obvious, and to the paired "do A, not B" form where B is the model's natural pull (raw
  SQL on core tables, URL-parsing to identify a product, disabling strict mode, auto-fixing a
  User-scope mutation, starting new templates on TemplateTags, etc.). The flagship case is
  `dw-demo-swift/references/dw10-canonical-surfaces.md`, whose nine `NEVER:` bullets each now name
  the canonical surface alongside the boundary. Already-paired negations, descriptive prose, few-shot
  anti-pattern blocks, and hard one-way contracts were left as-is.
- **Encoded the principle in the authoring guidance** so new skills and fold-backs follow it: a
  "Phrase instructions positively" rule in `dw-demo-base/references/iterate-plugin.md` (with the test
  for when contrast earns its place, and the few-shot exemption) and a pointer to it from
  `CLAUDE.md`. Applied the rule to the guidance's own prohibitions too.

## [3.3.3]

### Changed
- **Stripped "time-noise" from the skills — wall-clock/effort claims and inline date stamps an LLM
  can't use (sweep across ~25 demo-skill reference files).** Two classes removed: (1) subjective
  duration/effort flourishes (`~30 seconds on a warm SQL Express`, `don't burn a half-day`,
  `you've wasted hours`, `saves time`, `classic time-sink`, `Pay the 15 minutes`) — the actionable
  rule is kept, the time estimate dropped; (2) inline prose date markers (`(verified 2026-05-21)`,
  `(validated DW 10.25.x, 2026-06-10)`, `Superseded 2026-05-08:`, `A 2026-06 demo audit found`) —
  the date already lives in `git log`; where a marker also carried a build version (`DW 10.25.x`)
  the version is preserved and only the date dropped. Dates that are *data* (SQL literals, JSON
  example payloads, the `CUSTOMISATIONS.md` ledger column the audit regex keys on) are untouched,
  as are functional durations (script timeout bounds, schedule intervals, cache TTLs, presenter
  pacing).
- **Added the guardrail to `dw-demo-base/references/iterate-plugin.md`** so folds don't reintroduce
  it: the scrub table now has a "Wall-clock duration / effort claims" row and a strengthened
  "Session-relative time AND inline date stamps" row (resolve to *nothing* — the date is in `git
  log`), and the provenance-citation rule now names roles, never individuals **or** dates.

## [3.3.2]

### Changed
- **Documented the index-build-reads-through-cache ordering trap for SQL product-data writes
  (`dw-demo-pim/references/cache-invalidation.md`).** The cache table had no row for direct SQL
  edits to `EcomProducts` translatable fields, and nothing warned that the Lucene index builder
  reads product data *through* the live `ProductService` cache. Symptom: after translating a
  catalogue into a new ecommerce language via SQL and rebuilding the index, PDP + PLP stayed in the
  default language — because `BuildIndex` ran while the product cache was stale and baked the old
  values in. Added the table row + a dedicated section stating the correct order (write →
  flush/restart → *then* BuildIndex; reindex-then-restart is wrong), and a note that MCP
  `patch_products_safe` with a non-default `languageId` was observed to echo the translation but not
  persist it (verify the DB row; SQL was the reliable write surface).

## [3.3.1]

### Changed
- **Reversed the Backend MCP AddIn install order — NuGet `PackageReference` is now the default,
  the admin AppStore the last resort (`dw-demo-base/references/scaffold.md` §2.1/§2.1c, and the
  surface-priority table in `dw-demo-base/SKILL.md`).** The prior wording called the AppStore the
  "canonical" route and NuGet the headless "alternative" — backwards for an agent-driven build. The
  `PackageReference` route is deterministic, scriptable, and idempotent (a csproj edit), registers the
  AddIn at host startup, and sidesteps the virtualized AppStore "Available apps" grid that Playwright
  can't drive reliably; it also aligns with the standing rule that the admin UI is verification-only,
  never an action surface. The AppStore is now framed as the fallback for when the host csproj can't be
  edited, to be clicked manually rather than driven via Playwright. The MCP *config*-creation ordering
  in `mcp-setup.md` is deliberately left admin-UI-first, because its scriptable alternative is brittle
  reflection into an internal type (`McpConfigurationService.LinkToken`).

## [3.3.0]

### Added
- **Orchestrator abstraction for presales demo builds — `dw-demo-base/references/orchestrator.md`
  plus a native `/demo:*` command set.** Separates the demo skills (domain-knowledge *substrate*)
  from the thing that *drives* a build through its phases — now named the **orchestrator** (the
  industry term; "driver" was rejected to avoid overloading the device-/browser-driver sense). Two
  orchestrators are supported behind a common substrate: **GSD (primary)** — its discuss → plan →
  execute → verify → review → ship pipeline injects the skills into fresh-context agents, with the
  verifier loop and audit-fix; and a **native command set (floor)** — `/demo:scaffold`,
  `/demo:impact`, `/demo:build`, `/demo:status`, scaffolded into the demo project's
  `.claude/commands/demo/` (templates in `dw-demo-base/assets/commands/demo/`). The native commands
  detect GSD (`.planning/` or a `/gsd-*` surface) and defer to it unless passed `--standalone`, so
  the two never drive the same build. One human gate in both modes — the impact sign-off; everything
  else is automated (GSD's convergence loop, or the native single-pass validate against shared
  acceptance criteria). Names the **two gate types** explicitly — a single human sign-off vs the
  automated **validate/gap/buff loop** (builder → fresh-context validator → gap feedback → re-run
  until PASS/cap) — so scaffold and customer build are gated *without* a human pause; documents the
  per-mode assurance ladder and the throwaway-demo escape hatches; and flags the GSD upstream split
  (GSD Core / Open GSD) to verify agent type names and `/gsd-update` before wiring.
- **Lightweight in-skill harness for fully standalone runs (the floor).** With no GSD and no
  `/demo:*` commands, the demo skills are no longer run blind: each guards its own canonical flow —
  walk it in order, gate every step (refuse to skip or to declare the build done before a gate
  passes), and persist progress to a resumable `.demo/<slug>/flow-state.json` artifact that the
  native `state.json` and GSD both read as a superset. Lightweight on purpose — ordering + gate
  discipline + resumability, nothing heavier; promote to the native command set or GSD for real
  assurance.
- **The `agent_skills` keystone — `dw-demo-base/assets/agent_skills.config.json`.** Registers the
  demo skills to GSD agent types, keyed to the **real** agent type names in this install
  (`gsd-project-researcher`, `gsd-phase-researcher`, `gsd-planner`, `gsd-executor`, `gsd-verifier`).
  No skill is rewritten for either orchestrator; both read the same `SKILL.md` files.
- **3-phase roadmap template — `dw-demo-base/assets/ROADMAP.template.md`** (scaffold → customer
  build → polish), with the strictness gradient and acceptance criteria per phase.
- **Per-skill "how to run me" header** on every demo skill (`dw-demo-base`, `dw-demo-pim`,
  `dw-demo-swift`, `dw-demo-erp`, `dw-integration-bc`): the skill holds knowledge, not sequencing;
  an orchestrator owns the phase order, and standalone the skill's own order applies. Disambiguated
  the legacy "this SKILL.md is an orchestrator" nav phrasing to "nav layer" so the term is reserved
  for the build orchestrator.

## [3.2.4]

### Added
- **Invoking internal DW services by reflection — DI-timing constraint in
  `dw-extend-csharp-api/SKILL.md`.** Folded from a headless DW10 install. Adds a "last resort" subsection
  to the service-access patterns: some DW services are `internal` (no compile-time type) but resolvable
  from the DI container at runtime, and reflection-invoking one only works **inside the built host after
  `app.UseDynamicweb()` has run** — from a standalone console/utility process the container is
  uninitialised and the call fails on `Microsoft.Extensions.DependencyInjection.Abstractions`. Shows the
  `Assembly.Load` → `GetType` → resolve-from-`app.Services` → `MethodInfo.Invoke` pattern, flags it as
  version-fragile, and steers callers to public facades / `DependencyResolver` when a public surface exists.

## [3.2.3]

### Added
- **Headless MCP token + configuration binding (`McpConfigurationService.LinkToken`) in
  `dw-demo-base/references/mcp-setup.md`.** Folded from a headless DW10 install. New
  "Step 3 (headless alternative)" documents creating the API token in code
  (`TokenService.TryCreateToken` with an `ApiTokenRequestModel`, returning the unhashed `CLAUDE.<secret>`
  bearer) and the MCP configuration row (`AllowEverything = 1`) when the admin UI isn't reachable — and the
  load-bearing gotcha: a raw `McpConfigurationCredential` insert does **not** satisfy the auth path (still
  401), so the token must be bound via the internal `McpConfigurationService.LinkToken(configId, tokenId,
  user)` invoked by reflection from the live `app.Services`, followed by a host restart (the MCP config is
  cached at startup). Carries a brittleness warning (internal type, version-fragile) steering callers back
  to the admin-UI route when it's reachable. Step 6's binding note updated for consistency.

## [3.2.2]

### Added
- **Headless Backend MCP AddIn install via NuGet PackageReference in `dw-demo-base/references/scaffold.md`
  (new §2.1c).** Folded from a headless DW10 install. The canonical flow installs the MCP AddIn through
  the admin AppStore; when the admin UI isn't reachable (fully headless build / automated provisioning),
  add `<PackageReference Include="Dynamicweb.MCP" Version="…" />` to the host csproj instead — the AddIn
  registers at host startup and `/admin/mcp` goes from 404 to live with no AppStore click. Records that
  the net10 TFM requirement (§2.1) still applies, that this also sidesteps the virtualized AppStore
  "Available apps" grid (which Playwright struggles to drive), and that the beta-track package version must
  match the resolved Suite version. §2.1 cross-reference updated.

## [3.2.1]

### Changed
- **Port-targeted host control + stable host start in `dw-demo-base`.** Folded from a headless
  DW10 install. The "Host lifecycle authority" stop command matched the shared
  `Dynamicweb.Host.Suite` project name (`*Dynamicweb.Host.Suite*`), so stopping one demo's host
  killed *sibling* demos' hosts too — every demo scaffolds that same project name. Stop now
  targets the host by its launchSettings **port** (`Get-NetTCPConnection -LocalPort`), and the
  same fix replaces the name-only kill in the `references/scaffold.md` ring-swap process-lock
  gotcha. The durable-start guidance now **redirects stdout/stderr to log files** (a hidden
  `Start-Process` without redirection proved flaky — the process exits after kickoff), and adds a
  `dotnet run --no-build` caveat (a failed prior build means `--no-build` silently launches the
  stale DLL and can lock the exe).

## [3.2.0]

### Added
- **`manifest.json` + `scripts/build-manifest.mjs` — a generated skill index for the Dynamicweb MCP server ("Dynamo").**
  Dynamo fetches a single `manifest.json` from the repo root to auto-discover skills (grouped by
  `type` then `group`, one-sentence `description` per skill, `path` to each `SKILL.md`). The
  generator (Node, no dependencies) derives the manifest from each skill's frontmatter; `--check`
  mode fails CI on drift via `.github/workflows/manifest-check.yml`. Claude Code behaviour is
  unchanged — it still loads skills through `marketplace.json`. Layout kept flat.

### Changed
- **Added `type` (`knowledge`/`flow`) and `group` frontmatter to every skill.** Nine skills are
  flows (the setup-install/upgrade, swift-building, extend-mcp-tools, and the demo chain); the rest
  are knowledge.
- **Fixed four mislabeled descriptions** whose text had been copied from unrelated agent skills:
  `dw-pim-modelling` (was an enrichment description), `dw-pim-workflow` (was a solution-assistant
  description), `dw-pim-completeness` (was a dashboards description), and `dw-search-indexing` (was a
  product-query description) now describe what their bodies actually cover.
- **Tightened skill lead sentences** so each is a single intent-bearing sentence with no mid-sentence
  periods (Dynamo shows the description up to the first `.`). Corrected stale `dynamicweb-*` sister
  references in the demo skills to the real `dw-*` names.

### Renamed
- **`dw-tbd-source-explorer` → `dw-source-explorer`** (the `tbd` placeholder is resolved). Updated the
  folder, frontmatter `name`, `marketplace.json` path, and README.

## [3.1.4]

### Added
- **Checkout reads the billing address from the user profile, not from `UserAddress` records — in `dw-demo-swift/references/customer-center.md` §4.**
  A recurring 2026-06 build symptom: a buyer seeded with `save_user_addresses` (Billing + Shipping
  `UserAddress`) but a blank profile address could not complete checkout — checkout showed "no address
  selected" on the billing side and the step would not advance. Root cause is stock Swift, not the demo:
  `eCom7/CartV2/Step/InformationUser.cshtml` gates the Continue button on `addressString`, built solely
  from `UserManagement:User.Address/Zip/City`, and `Helpers/AddressUser.cshtml`'s "Same as billing
  address" option reads those same profile fields; the default Shipping `UserAddress` still pre-selects
  for delivery, which is why only the billing side looks empty. Fix: populate the profile address too
  (`update_users` / the `AccessUser` columns), mirroring the Billing `UserAddress`, for every buyer
  persona. Sharpened the previously-incomplete "addresses come from `save_user_addresses`" claim in place
  and updated the SKILL.md routing row.
- **Customer-specific pricing + buyer-dashboard gating in `dw-demo-swift/references/customer-center.md`.**
  Continues the 2026-06 customer-experience build. (1) New §9 on contract / "customer-card" pricing:
  `save_prices`'s `customerGroupId` writes `PriceCustomerGroupId`, which the frontend price resolver does
  **not** match against a logged-in user's groups — the price silently never applies; the reliable scope is
  `PriceUserCustomerNumber` (the account's customer number). Lowest matching price wins (not priority);
  customer prices resolve **live in the cart/checkout**, not on PLP/PDP (index context); prices are cached
  (restart to apply); and `force_price_recalculation` recomputes without a frontend price context so it's
  not a valid test. (2) §6 extended with the inverse gate — hiding the buyer's Account sections from a pure
  CSR persona — and the load-bearing rule that frontend permission resolution takes the **highest** level
  across a user's identities, so you deny the broad role + grant the customer group rather than denying the
  staff group. SKILL.md routing row updated.

## [3.1.3]

### Added
- **Customer-experience seeding + account-type specifics in `dw-demo-swift/references/customer-center.md`.**
  A 2026-06 build that seeded the CSR/account section directly (MCP + SQL) instead of from a
  customer-flavoured baseline hit three stock filters that silently hide correct data, none previously
  documented: (1) `CSR/Accounts/` lists only groups flagged `AccessUserUserAndGroupType = 'SystemAccount'`
  (a group made via `save_user_groups` lands plain, so the page reads empty while its users still show
  under `CSR/Users/`); (2) placed orders appear in "My orders" only when `EcomOrders.OrderComplete = 1`,
  and favorites seeded via SQL need empty-string (not NULL) `ProductVariantId` / `Note` /
  `ProductReferenceUrl` / `UnitId`; (3) the §6 permission gate, when its `Permission` rows are written via
  SQL rather than the admin UI, needs a security-cache refresh/restart to take effect and resolves grants
  by role/group, not by individual user id. SKILL.md routing row updated to surface seeding + the
  "looks empty" symptoms.

## [3.1.2]

### Added
- **Component-first gate in `dw-demo-swift/references/paragraphs.md`.** Swift ships a standard component
  for most PLP/PDP/navigation needs, but the default reflex on a "make the UI do X" request was to author
  or override a `.cshtml` — which accrues off-baseline code a Serializer re-deploy drops, and (on a
  2026-06-21 build) produced a hand-rolled category-banner hero that errored twice when
  `Swift-v2_ProductListGroupPoster` already does exactly that. The reference now leads with a mandatory
  gate (enumerate the standard components → classify the change as place / configure / override / new →
  pick the lowest tier) plus a "common need → standard component" catalogue (group poster/image, subgroup
  nav grid/list/slider, component slider for related/similar, field-display accordion, BOM). Generalises
  the existing "Don't customise this paragraph" callouts; SKILL.md routing row updated to surface it.

## [3.1.1]

### Fixed
- **Browser MCP screenshots no longer land in the demo solution root.** `browser_take_screenshot`
  writes relative filenames against the MCP server's working directory, which is the folder Claude
  Code was launched from — so a verification flow with bare filenames littered the demo repo root
  (~40 stray `.jpeg` files in one build). `dw-demo-base/references/browser-automation.md` now adds a
  "Where screenshots land" section and a `--output-dir` install flag: pin a neutral machine-level
  scratch dir at user scope (cross-demo plumbing, so it must NOT be any one demo's folder), and pass
  an absolute `<demo>\notes\playwright\` filename for keeper shots. The one-line install in
  `mcp-setup.md` carries the same `--output-dir` flag.

## [3.1.0]

### Changed
- **New way of working: every change lands via PR.** Replaced the `## No PRs` rule in
  `CLAUDE.md` with a PR-based workflow — branch off the integration branch (`v2` until it
  merges to `main`), one atomic logical change per PR, validate + version-bump + docs in the
  same commit, squash-merge. The `## Commits` note now ties the commit subject to the PR title
  and keeps the no-`Co-Authored-By` rule.
- **Made the foundational-vs-demo split explicit and one-way.** Added a "Skill categories"
  section to `CLAUDE.md`: foundational skills are vendor-generic and carry zero demo/customer
  content and no links into demo skills; demo skills (`dw-demo-*` + `dw-integration-bc`) build
  on foundational ones; learnings flow demo → foundational only via the sanitized fold-back.
- **Rewrote the maintainer fold-back** (`skills/dw-demo-base/references/iterate-plugin.md`) for
  the migrated repo and the new model. It now targets `dynamicweb/skills` (was
  `justdynamics/dynamicweb-commerce-demo`), bumps the single `metadata.version` in
  `marketplace.json` (the old dual-manifest `plugin.json` rule is retired), runs
  `python3 scripts/validate-skills.py` (was `scripts/validate.py`), uses the current `dw-*`
  skill names, and lands every fold via a PR with the leak-catch window before merge. Added a
  load-bearing first step that routes each learning foundational-vs-demo. The Step 1a
  sanitization and Step 1b content-hygiene gates are preserved. Updated the matching fold-back
  row and section in `dw-demo-base/SKILL.md`.

## [3.0.1]

### Fixed
- **Made the marketplace installable on released Claude Code** (verified against 2.1.181 and
  `claude plugin validate`). Three blockers:
  - `marketplace.json` used a `"marketplace": { ... }` wrapper, leaving the required top-level
    `name` and `owner` undefined so the loader could not parse it. Flattened to top-level
    `name` / `owner` / `plugins`, with `description` and `version` under `metadata`.
  - Plugin entries listed only `skills: [paths]` with no `source`, so there was nothing to
    fetch and install failed. Each of the six bundles now declares `"source": "./"` +
    `"strict": false` and curates its skills via the path list — the
    marketplace-root-source pattern, which is exactly what lets bundles share skills.
  - Stripped the UTF-8 BOM from all 41 BOM-carrying markdown files under `skills/`.
- **Refreshed `README.md` and `CLAUDE.md`** to the current `dw-*` skill layout and six role
  bundles (`dynamicweb-setup` / `frontend` / `commerce` / `backend` / `developer` /
  `presales`), and to the current install commands (`claude plugin marketplace add` /
  `claude plugin install`).

### Added
- `validate-skills.py` now enforces the marketplace top-level schema (`name`/`owner`/
  `plugins`), requires a `source` on every plugin entry, resolves `./`-prefixed skill paths,
  and rejects any markdown file that begins with a UTF-8 BOM.

## [2.1.0]

### Changed
- **Removed the retired "Truvio" codename** across all skills, references, templates, the
  MCP server name (`dynamicweb-commerce-mcp`), and env-var names (`DYNAMICWEB_*`). Fixed the
  broken `truvio-*` skill cross-references and the `../`-depth errors in cross-skill
  reference links they were masking. Renamed `truvio-connector-settings.md` ->
  `dynamicweb-connector-settings.md`.
- **Standardized every SKILL.md description** to the `first sentence + Triggers: +
  Non-triggers:` convention, with non-triggers routed to the correct sibling skill.
- **Role rebalance:** moved `dynamicweb-business-solution-agent` from the `dynamicweb-user`
  bundle to `dynamicweb-implementer` (it is a heavy installer/orchestrator, not an
  end-user tool). The `dynamicweb-user` bundle is now `pim-enrichment` + `pim-query`.

### Fixed
- `dynamicweb-mcp-tool-creator` no longer points at the non-existent
  `dynamicweb-tool-picker` skill; it now directs tool documentation to the Dynamicweb.MCP
  project's own catalog/README.
- Stripped a stray UTF-8 BOM from `dynamicweb-mcp-tool-creator/SKILL.md`.

### Added
- `scripts/validate-skills.py` — structural linter (marketplace integrity, name/folder/path
  agreement, relative-link resolution, codename purge check, description-signal warnings).
- Authoring/validation guidance in `CLAUDE.md` and this `CHANGELOG.md`.

## [2.0.0]
- Baseline: 15 skills bundled into 4 role plugins (developer, implementer, user, presales).
