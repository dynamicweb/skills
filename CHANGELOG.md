# Changelog

All notable changes to the Dynamicweb Skills plugin are recorded here. The
`version` field in `.claude-plugin/marketplace.json` tracks these entries.

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

## [3.9.0]

### Added
- **New skill `dw-demo-headless` — headless-commerce demos (Next.js storefront + DW10 Delivery
  API).** A new `flow` demo skill in the presales cluster, sister to `dw-demo-swift` and
  "Use AFTER `dw-demo-base`", covering the fifth demo consumer: a `vercel/commerce`-based Next.js
  storefront driven by the Dynamicweb 10 Delivery API (`/dwapi/**`) over a dedicated,
  presentation-agnostic serialized baseline that is its own product line — fully decoupled from
  Swift, sharing no item-type rows. Three references:
  - `references/headless-backend.md` — configure/verify the DW10 backend for headless: the Delivery
    API surface map (endpoint/auth table; REST/JSON only, no GraphQL/OData), the **two-token trap**
    (the admin/Management token 401s on `/dwapi`; the frontend needs a JWT from
    `POST /dwapi/users/authenticate {UserName,Password}` → `{token}`), the locale gotcha (product
    data lives under `ENU`, not `LANG1` — always pass `LanguageId`+`ShopId`), the PLP
    repository/named-query requirement (`GET /dwapi/ecommerce/products/search?RepositoryName=…&QueryName=…`;
    `POST /dwapi/ecommerce/products` 400s — count at `totalProductsCount`, facets at
    `facetGroups[i].facets[j]`), and the item-type-XML-materialized-at-startup fact.
  - `references/headless-frontend.md` — work with the Next.js storefront: the provider-module
    data-layer swap (replace `lib/shopify/` with `lib/dynamicweb/`, keep every UI component), `DW_*`
    env wiring, the self-signed-TLS dev bypass (`NODE_TLS_REJECT_UNAUTHORIZED=0`, dev-only), the
    build-time RSC fetch caveat (`next build` needs a reachable provider), slug conventions (product
    number = handle; group id = collection handle), and `@vercel/*` self-host disposition.
  - `references/headless-baseline.md` — deserialize the headless baseline: the `Headless_*`
    presentation-agnostic item-type layer, the `200000–209999` id floor band (an authoring
    convention verified in YAML — DW reassigns DB ids), EN/NL sibling-area parity (paired manifest
    entries), disk-overlay staging of `itemtypes/` + `repositories/` BEFORE host start, and the Full
    index build after deserialize.
  Registered the skill in `.claude-plugin/marketplace.json` (dynamicweb-presales plugin) and
  regenerated `manifest.json`. Added the headless demo path to `dw-demo-base` SKILL.md (sister-skill
  list + the baseline "explicit non-step") so it is discoverable from the foundation skill. Routes
  to the existing `dw-headless-delivery` knowledge skill for the raw endpoint catalog rather than
  duplicating it.

## [3.8.6]

### Fixed
- **Framework-preservation claim corrected to the mode that actually governs framework rows.**
  `dw-demo-swift` SKILL.md Step 0 and `deserialize-flow.md` §3 claimed a PIM-set-up host's
  SHOP1/DE/EUR/LANG1 rows were preserved because "`seed` mode is destination-wins" — but framework
  `_sql/` travels in the **deploy** tree, and `deploy` is **source-wins**: the baseline's framework
  rows UPDATE matching curated rows. Both spots now warn to review/trim `deploy/_sql/` before
  deserializing into a host with hand-curated framework data; only the `seed` (catalog) pass is
  destination-wins.
- **`baselines\` staging wording de-contradicted.** `deserialize-flow.md` §3 both designated
  `<demo-root>\baselines\` as the canonical download/staging location and kept the legacy warning
  that a `baselines/` copy is "invisible". Reworded: `baselines\` is the staging copy the snippet
  copies FROM; `SerializeRoot/` remains the only path the deserialize endpoint reads.
- **Icon set added to the design-package copy list.** `Files/Images/Icons/` (~80 SVGs incl.
  `Flags/` and `LoginProviders/`) is verified present in the Swift clone and is the set
  `integrity-sweep.md` Check 6 verifies — it is now an explicit copy-list entry instead of only a
  recovery path.

## [3.8.5]

### Changed
- **Baseline and feature-pack distribution repointed from personal vault slots to per-demo
  downloads.** The `dw-demo-swift` deserialize and pack-activation flows no longer resolve
  baselines, packs, or Swift-repo assets from `$env:DW_VAULT` slots. Instead, a demo build
  downloads the baseline release (e.g. tag `swift/2.3`) and any pack releases (tag
  `packs/<name>/<version>`) from the distribution repo the team designates into the demo's own
  `baselines\` folder (`<demo-root>\baselines\swift-2.3\`,
  `<demo-root>\baselines\feature-packs\<name>\<version>\`), and the Swift design package comes from
  a local clone of `https://github.com/dynamicweb/Swift` (`<demo-root>\dw-swift\`). Swept the
  read-only inspection paths in the companion references (`templates`, `paragraphs`,
  `customer-center`, `asset-organisation`, `admin-ui-authoring`, `re-skin`), repointed
  `integrity-sweep.md` Check 6 icon recovery at the same Swift clone the deserialize flow copies
  assets from (reproducibility now recorded as baseline name + release tag in the per-demo
  `CUSTOMISATIONS.md`), updated the `dw-demo-pim/access-surfaces` baseline row, and noted in the
  `dw-demo-base` INDEX template that the `serialized-data` vault slot is a legacy/local mirror.

## [3.8.4]

### Added
- **`dw-demo-swift/references/pack-activation.md` — install a feature pack into a demo host.** A new
  consumer-facing reference documenting the L3→demo-host install path: download the pack release
  (tag `packs/<name>/<version>`) from the feature-pack distribution repo into the demo's
  `baselines\feature-packs\` folder, read `pack.json`, source-drop the `.cs` into the host's
  `Packs\<name>\` and rebuild, copy disk-overlay templates/item types, and deserialize the
  `baseline-fragment` mode trees (seed/deploy) strictly AFTER the base baseline. Documents the confirmed
  pack zip anatomy (pack.json, src/*.cs, templates/, itemtypes/, baseline-fragment/{seed,deploy}/) and
  the activation model (code compiles into the host; the fragment is additive and never edits base YAML).
  Added the router row to `dw-demo-swift/SKILL.md` and completed the swift/2.3 baseline-shape supersede in
  SKILL.md Step 0 (retiring the content-only `Swift2.2` framing).

## [3.8.3]

### Changed
- **`dw-demo-swift` deserialize-flow repointed off the retired content-only `Swift2.2` baselines to
  the canonical `swift-2.3` baseline.** The `swift-2.3` baseline is a full `config/deploy/seed`
  tree (framework `_sql/` + content in `deploy/`, catalog `_sql/` + content in `seed/`), not the
  content-only `_content/`-at-root shape the older `Swift2.2` baselines used. Repointed the `$baseline`
  default and staging snippet in `dw-demo-swift/references/deserialize-flow.md` to stage both mode
  trees from `swift-2.3`, rewrote the "baseline shape" and §9 schema-drift notes for the
  `_sql/`-shipping baseline, and swept baseline-slot source-of-truth paths in the companion
  references (`templates`, `paragraphs`, `customer-center`, `asset-organisation`,
  `admin-ui-authoring`, `re-skin`, `integrity-sweep`) plus `dw-demo-pim/access-surfaces` and the
  `dw-demo-base` INDEX template to the `swift-2.3\deploy\_content\` location. Swift-2.2-era
  mechanics prose left intact (per-hit sweep, not a blanket rename). The two-pass deploy+seed
  deserialize is flagged for host verification.

## [3.8.2]

### Changed
- **Group-scoped page/paragraph gates work — via the deny+grant pair; 3.8.1's role-string-only rule
  was a misdiagnosis.** Further live verification on the same 10.26.x host: a **bare** group-id
  grant does not gate because highest-wins resolution lets the inherited broad
  `AuthenticatedFrontend` grant override it — which is what previously read as "group gating is
  non-functional". The working shape (verified at page AND paragraph level): an explicit
  `AuthenticatedFrontend → None` deny **plus** a `<group id> → Read` grant on the same entity.
  Also live-verifies the `PermissionName='Paragraph'` row shape (previously hedged), with the
  deny+grant pair written via the paragraph's Permissions panel or direct SQL + security-cache
  flush. Rewrote the §15 role-string rule in
  `dw-demo-base/references/foundational/users-permissions.md` around the pair (including the
  two-step hide-a-subtree recipe, whose step-2 group grants are effective exactly because of the
  step-1 deny), the restrict-a-page recipe in `dw-users-permissions/SKILL.md` (the broad-role deny
  named as load-bearing), and the `dw10-canonical-surfaces.md` routing row.

## [3.8.1]

### Changed
- **Page/paragraph render-time permission storage corrected to `UnifiedPermission`.** The corpus
  described a distinct `Permission` table (`PermissionOwnerName`/`PermissionOwnerKey`/
  `PermissionExplicitDeny`) as the render-time entity store; live verification on a DW 10.26.x host
  shows those rows land in the same `UnifiedPermission` table as Layer-A entity grants, keyed
  `PermissionName='Page'` with role strings (`Anonymous`/`AuthenticatedFrontend`) as
  `PermissionUserId` and `PermissionLevel` bit values `None=1, Read=4`. Rewrote
  `dw-demo-base/references/foundational/users-permissions.md` §15 (physical storage, role-string
  rule, anonymous-deny → auto-redirect to the UserAuthentication page, the signed-in-first
  storefront recipe, and the write-surface escalation: no MCP tool and no Management API endpoint —
  drive the admin Permissions panel headless and verify with read-only SQL). Swept the stale
  `Permission`-table phrasing from `dw-demo-swift` (SKILL router, `dw10-canonical-surfaces.md`,
  `re-skin.md`, `customer-center.md`), `dw-demo-pim/references/permissions-model.md`,
  `swift-building.md`, `pim-workflow.md`, `dynamicweb-skills-structure.md`, and qualified
  the group-grant step in `dw-users-permissions` (group-scoped page rows failed to gate on 10.26.x).

### Added
- **Single-storefront clean-root recipe** in
  `dw-demo-base/references/foundational/content-modelling.md` §Friendly URL config:
  `urlIgnoreForChildren=true` + deactivating leftover sibling areas gives one area ownership of `/`
  with unprefixed child URLs (restart required — URL provider caches at startup), plus the
  post-switch rendered-HTML sweep for the three stale-link classes the URL provider cannot rewrite
  (dead-id item-field links — outside `find_unresolvable_item_pages` scope, which detects
  unresolvable item *types* only; one logo item per header/footer chrome variant; hand-typed
  rich-text hrefs) and the benign module-emitted `Default.aspx` lookalikes to leave alone.

## [3.8.0]

### Changed
- **Index build/status contract corrected to the DW 10.26.x models.** The corpus polled
  `GET /admin/api/IndexStatus` for a `Status` field reaching `Idle` — neither the endpoint shape nor
  the field exists on 10.26.x, so the recipe could wait out its timeout against a build that actually
  succeeded. Verified against a live host's `api.json` catalog and end-to-end builds: status is served
  by `IndexStatusByRepositoryAndIndexName` (`State: Success|Warning|Error`, `LastRun`) and
  `InstanceStatusByName` (`LifecycleState: NeverBuilt|...|Completed|Failed`, `LastSuccessfulBuild`).
  Folded into `dw-demo-swift/references/integrity-sweep.md` Check 5, the
  `foundational/search-indexing.md` rebuild recipe, and the `foundational/data-access.md` endpoint
  catalog, with three empirically-earned rules: pass = `Success` PLUS a build timestamp fresher than
  this run's POST (a stale prior build satisfies a state-only check); a never-built index reports
  index-level `State=Error` while its first build is still writing (terminal only when the instance
  `LifecycleState` is `Failed`); live JSON responses are camelCase despite the PascalCase catalog.
  Repository/index names are called out as solution-specific (a stock Swift solution ships
  `ProductsFrontend`/`ProductsBackend`) — never hardcode `Repository=Products` in gating checks.
- **The hardcoded Serializer repo path is retired.** A clean-machine standup failed at the Serializer
  build/copy steps: the install recipe hardcoded a legacy repo directory that no longer exists, and a
  legacy DLL filename that fails the copy even where a directory resolves (the assembly filename
  follows the csproj `AssemblyName`, which renamed with the product).
  `dw-demo-base/references/serializer-reference.md` now resolves the clone root from
  `$env:DW_SERIALIZER_REPO` (new Step 0, dual-set pattern) and derives the project folder + DLL
  filename from the repo itself; the upstream docs/source/tools pointers resolve the same way. Prose
  occurrences of the legacy product name across dw-demo-base and dw-demo-swift are swept to the
  generic "the DW Serializer".
- **Vault `databases` slot documented as the canonical in-vault fast-restore source.** The
  INDEX.md.template row now requires naming the artifact when the slot is populated (never
  "reserved/empty" while drift detection and the setup-checks probe expect the artifact there);
  serializer-reference.md routes fast-restore to `$env:DW_VAULT\databases\` instead of a bacpac copy
  inside the Serializer repo's tools folder.
- **net8-vs-net10 addon rule stated with its mechanism** (`dw-setup-upgrade/SKILL.md`): TFM-gated
  addon *loaders* (Backend MCP AddIn) require the **host process** on net10 even though their packages
  ship net6/net8 binaries (symptom: install 200, files drop, AddIn never registers, `/admin/mcp` 404),
  while plain net8 class libraries back-load onto a net10 host via standard roll-forward. Replaces the
  blunt "a .NET 8 addon will not work on a .NET 10 host".
- **MCP OAuth authenticate named as a hard human gate** (`dw-demo-base/references/mcp-setup.md`): the
  legacy OAuth path's authenticate click + restart cannot be cleared headlessly and stalled autonomous
  standups silently — automation must surface "human action required" and stop; the API-Key default
  (and its headless alternative) is what keeps standup automatable end-to-end. Same file: one-shot
  `Program.cs` bootstrap branches (password-set / token-mint / MCP-link) are standup scaffolding —
  remove before final delivery, rebuild, restart; never ship live credential-minting code.
- **Startup-cached SQL surfaces added to the cache rulebook**
  (`foundational/cache-invalidation.md` + `foundational/pim-modelling.md` §2.5): missing
  `EcomVariantOptionsProductRelation` combination rows make a variant add-to-cart POST return HTTP 200
  while adding nothing, and direct SQL junction INSERTs must be existence-guarded (`IF NOT EXISTS`) so
  re-runs converge — restart owed after. Credential/token rows written via direct SQL (`AccessUser`
  password columns, `AccessUserToken`) keep validating the pre-write state until a restart.
- **PIM catalogue ID discipline** (`dw-demo-pim/references/canonical-setup-order.md`): the MCP
  `create_*`/`save_*` tools auto-assign entity IDs and ignore requested ones — capture `items[].id`
  from every response, key subsequent steps off captured ids, and clean up auto-IDed leftovers before
  any re-run.
## [3.7.4]

### Changed
- **RESET runbook: the admin "Run task now" needs its confirmation dialog, fires on the next
  scheduler poll, and stale duplicate tasks get deleted.** `mock-deltas.md` Step 6 rewritten: the
  Run-task-now click opens an OK dialog and does nothing until confirmed (a dismissed dialog leaves
  no trace — it reads as "the reset silently failed"); execution happens on the scheduler's next
  poll, so success is verified by the task's Last-run timestamp flipping, not by the click; and
  abandoned earlier registrations leave near-identical sibling tasks a presenter will mis-fire
  under stage pressure — superseded copies are deleted as part of the idempotent re-registration.

## [3.7.3]

### Changed
- **Host lifecycle: `dotnet run` is the only launch surface; two silent-failure triage rules.**
  `dw-demo-base/SKILL.md` "Host lifecycle authority" gains: (1) launching the built
  `bin\Debug\<TFM>\Dynamicweb.Host.Suite.exe` directly boots a host that serves pages but is
  silently degraded — item-based paragraphs fall back to defaults, product lists render empty,
  nothing is logged; the symptom reads as data loss and cost a demo test run hours of
  misdiagnosis, so "check how the host was started" is now the first diagnostic for that symptom
  set. (2) A freshly started host that exits silently minutes after start (no exception, no
  shutdown log) while sibling DW hosts run on the machine is retested with siblings stopped before
  deeper diagnosis; demo-day runbook line: run only the demo's own host and confirm sustained
  uptime before presenting.

## [3.7.2]

### Added
- **Two re-skin CSS pitfalls in `render-razor.md` §5** (both hit in a B2B demo visual audit):
  - *Colorscheme rules out-specify simple header/footer brand rules.* `.navbar` paints the desktop
    category sidebar (not the page header); header grid-row sections carrying a colorscheme repaint
    their own background over `header[data-swift-page-header]` at specificity (0,3,0); link colours
    inside colorscheme scopes come from a ~(0,5,1) swift.css rule. Worked selectors provided for
    all three layers, including the structural `.offcanvas */.dropdown-menu *` exclusions that keep
    header menus readable.
  - *Declared typography fonts must be vendored — Swift ships no webfont files.* A bare
    `--dw-font-family: <Font>` renders the browser default serif when the font isn't installed;
    CDN `@import` masks it until the demo runs offline, and removing the import without vendoring
    reintroduces the serif fallback. Recipe: local woff2 + `@font-face` (`font-display: swap`),
    generic-terminated stacks, canvas-width verification (`document.fonts.check()` alone is
    misleading). `re-skin.md`'s pitfall index gained pointer lines for both.

## [3.7.1]

### Changed
- **Reorder appends to the ACTIVE cart — both surfaces silently no-op without one.**
  `commerce-orders.md` "Reorder a past order" presented `cartcmd=copyorder` as copying lines "into
  the active cart" without stating the precondition: neither `cartcmd=copyorder` nor the
  customer-center `CustomerCenterCmd=Reorder&OrderId=` command creates a cart — with no active cart
  in the session they do nothing, render no error, and log nothing. Surfaced in a B2B demo test run
  where the scripted Reorder beat sat right after checkout (cart just emptied) and the button
  no-oped on the very order it had appended correctly minutes earlier. The section now documents
  both surfaces, the append-with-quantity-merge behaviour verified on DW 10.26, and the demo-script
  rule: put any line in the cart first or place the reorder beat before checkout.
  `customer-center.md` §3's pointer line updated to match.

## [3.7.0]

### Changed
- **Host lifecycle: flush-first discipline and ownership-verified process stops.** Root cause of
  agents restarting the local host constantly (instead of cache flushing) and of one agent killing
  another agent's host on multi-demo machines: `dw-demo-base/SKILL.md`'s always-on "Host lifecycle
  authority" section ended its stop recipe with *"Use this freely — restart is cheap, locked-in-cache
  state is the bigger risk"* — a standing license to restart that overrode the flush-first rulebook in
  `cache-invalidation.md` (a reference that only loads when consulted). And the resolution ladder
  jumped from targeted flush straight to restart "when you can't identify which cache holds the stale
  value", even though the bulk flush (`GetServiceCaches` → `CacheInformationsRefresh`) is documented
  as the mandatory substitute for *every* "YES restart" row on hosted installs. Changes:
  - `dw-demo-base/SKILL.md` "Host lifecycle authority": the restart-freely line is replaced with the
    **flush-first ladder** — targeted `CacheInformationRefresh` → bulk flush → restart only when the
    symptom survives both or the cache is documented as not service-exposed (`Searching:Queries`).
    Owed restarts (AddIn deploys, TFM changes, restart-only rows) are **batched, one per authoring
    pass** (MCP-first → SQL-last → one-restart), and verified to have cold-started (the `dotnet run`
    parent/child trap).
  - **Stop is now port-scoped AND ownership-verified**: the stop snippet resolves the PID from THIS
    demo's launchSettings port and confirms the owning process's command line points at THIS demo's
    solution folder before `Stop-Process`; a mismatch warns and aborts instead of killing. Name/
    command-line matching (`*Dynamicweb.Host.Suite*`, `Stop-Process -Name dotnet`) named explicitly
    as the sibling-host killer. The inheritance line now also declares restart-where-a-flush-exists
    and unverified kills as contract violations.
  - `cache-invalidation.md` "When a mutation doesn't show up" gains the **bulk-flush rung** between
    targeted flush and restart (run it locally before any restart — it clears every service-backed
    cache in one call and covers the can't-identify-the-cache case), and its restart rung now carries
    the batch + port-scoped/ownership-verified + verify-cold-start discipline.
  - `dw-demo-pim/references/cache-invalidation.md` demo note reworked to the same flush-first order
    (it previously told builds to "budget the 30-second host bounce" per SQL seed).

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
