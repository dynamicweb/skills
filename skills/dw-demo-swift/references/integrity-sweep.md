# integrity-sweep.md

## Contents

- [Prerequisites](#prerequisites)
- [Why this sweep is mandatory](#why-this-sweep-is-mandatory)
- [Check 1: FK orphans (strict-mode-delegated)](#check-1-fk-orphans-strict-mode-delegated)
- [Check 2: `reference_category` parent row](#check-2-reference_category-parent-row)
- [Check 3: Query GUID dedup across `Repositories/` and `SmartSearches/Shared/`](#check-3-query-guid-dedup-across-repositories-and-smartsearchesshared)
- [Check 4: Template-reference walk (defense-in-depth)](#check-4-template-reference-walk-defense-in-depth)
- [Check 5: BuildIndex (by the `.index` Build Name) + wait for a fresh successful build](#check-5-buildindex-by-the-index-build-name--wait-for-a-fresh-successful-build)
- [Check 6: Icon set populated under `Files/Images/Icons/` (Pitfall: blank-blue-button storefront)](#check-6-icon-set-populated-under-filesimagesicons-pitfall-blank-blue-button-storefront)
- [Check 7: Raw SQL in paragraph templates (DW10 discipline)](#check-7-raw-sql-in-paragraph-templates-dw10-discipline)
- [Check 8: Style assets staged + emitted (the theme gate)](#check-8-style-assets-staged--emitted-the-theme-gate)
- [Sweep complete](#sweep-complete)

> Mandatory post-deserialize integrity sweep. Eight sequential checks. Run after [`deserialize-flow.md`](deserialize-flow.md) returns 2xx. The skill refuses to declare deserialize complete until ALL eight pass. Strict-mode Serializer is the first line of defence — this sweep is the second, catching DW10-specific failures strict mode does not detect.

## Prerequisites

- [`deserialize-flow.md`](deserialize-flow.md) returned HTTP 2xx (no `CumulativeStrictModeException` body).
- Project context already discovered (see [`deserialize-flow.md`](deserialize-flow.md) Section 2):
  - `$port` from `Dynamicweb.Host.Suite/Properties/launchSettings.json`
  - `$db` from `Dynamicweb.Host.Suite/GlobalSettings.Database.config`
  - `$token` from `AskUserQuestion` (`CLAUDE.<hex>`, conversation-only, never persisted)

If any of those is unset, return to [`deserialize-flow.md`](deserialize-flow.md) and re-run from Section 2 — the sweep depends on those three values throughout.

## Why this sweep is mandatory

Strict mode (in the Serializer) raises four broad categories of failure as `CumulativeStrictModeException`: FK orphans, missing templates, cache failures, schema drift. **Strict mode does NOT detect:**

- DW10 completeness rules without their `reference_category` parent row (silent invisibility: rules validate, assignments persist, API returns correct data, but admin UI panels render empty).
- Dashboard query GUIDs duplicated across `Repositories/Products/<sub>/` and `SmartSearches/Ecommerce/Shared/` (the `QueryHelper.InitQueriesCache` overwrite trap — breaks admin's Shared-queries tree and widget drill-through).
- Index staleness immediately after a deserialize (products invisible until a fresh BuildIndex, by the `.index` Build Name, completes on every instance).

The sweep adds defense-in-depth for these categories. Skipping it produces a deserialized DB that *looks* clean but is silently broken on demo day.

## Check 1: FK orphans (strict-mode-delegated)

**What is verified:** No FK orphans were introduced by the deserialize.

**How:** the DW Serializer's strict mode (default-on for API callers — see [`deserialize-flow.md`](deserialize-flow.md) Section 5) raises FK orphans as `CumulativeStrictModeException` during the deserialize POST. The sweep does NOT run a separate per-pair orphan SQL loop — that would be redundant and costly. Instead, this check is satisfied by:

1. [`deserialize-flow.md`](deserialize-flow.md) was followed (strict mode default — disabling strict mode is forbidden by that flow).
2. The deserialize POST returned HTTP 2xx (no `CumulativeStrictModeException` body).

If both of those are true, Check 1 passes. If either is false, Check 1 fails — return to [`deserialize-flow.md`](deserialize-flow.md) and re-run with strict mode on.

**Why no separate SQL loop:** Strict mode is the canonical FK-orphan detector for the DW Serializer. Adding an `INFORMATION_SCHEMA`-driven per-pair count would duplicate work the Serializer already did, with worse performance and worse error messages.

**Reference:** [`deserialize-flow.md`](deserialize-flow.md) Section 5 — Strict-mode contract, category 1 of 4.

## Check 2: `reference_category` parent row

**What is verified:** The hidden `reference_category` parent row exists in `EcomProductCategory` with `CategoryType = 2`. Without this row, the entire DW10 admin UI rule/completeness lookup machinery has nothing to resolve against — rules validate, assignments persist, the `ProductCompletenessRulesByProductId` API returns correct data, but product/group completeness panels in admin render empty.

**Probe:**

```powershell
$query = @"
SELECT COUNT(*) AS RefCatRows
FROM EcomProductCategory
WHERE CategoryId = 'reference_category' AND CategoryType = 2
"@
$result = sqlcmd -S "localhost\SQLEXPRESS" -E -d $db -Q $query -h -1
if ([int]$result.Trim() -lt 1) {
  throw "reference_category parent row missing. See ../../dw-demo-pim/references/governance.md 'Completeness rules' for the seed pattern."
}
```

**Scope note:** Check 2 only **detects** the missing row. The seed-rule context (the four-rows-per-field SQL pattern) lives in the PIM skill — see [`../../dw-demo-pim/references/governance.md`](../../dw-demo-pim/references/governance.md) "Completeness rules — why they sometimes don't show" for the seed pattern.

## Check 3: Query GUID dedup across `Repositories/` and `SmartSearches/Shared/`

**Background rationale:** a query GUID duplicated across `Repositories/Products/<sub>/` and
`SmartSearches/Ecommerce/Shared/` makes `QueryHelper.InitQueriesCache` return the Repositories copy on
collision, which 500s the admin Shared-queries tree and breaks widget drill-through; there is no
cache-invalidation API for `Searching:Queries`, so recovery requires a host restart. The full
mechanism (and the rule — feed queries → `Repositories/<RepoName>/` only; dashboard queries →
`SmartSearches/Ecommerce/Shared/` only; never both) is vendor-generic and owned by the
`dw-search-indexing` foundational skill — staged in [`search-indexing.md`](../../dw-demo-base/references/foundational/search-indexing.md) ("Dashboard query location — Shared ONLY").

**Probe:**

```powershell
$repoQueries = Get-ChildItem -Recurse "Dynamicweb.Host.Suite/wwwroot/Files/System/Repositories/Products" -Filter "*.query" -ErrorAction SilentlyContinue
$sharedQueries = Get-ChildItem -Recurse "Dynamicweb.Host.Suite/wwwroot/Files/System/SmartSearches/Ecommerce/Shared" -Filter "*.query" -ErrorAction SilentlyContinue

function Get-QueryGuid($f) {
  $xml = [xml](Get-Content $f.FullName -Raw)
  return $xml.Query.ID
}

$repoGuids   = $repoQueries   | ForEach-Object { @{ Guid = Get-QueryGuid $_; Path = $_.FullName } }
$sharedGuids = $sharedQueries | ForEach-Object { @{ Guid = Get-QueryGuid $_; Path = $_.FullName } }

$dupes = $repoGuids | Where-Object { $g = $_.Guid; $sharedGuids.Guid -contains $g }
if ($dupes) {
  Write-Host "Duplicate query GUIDs detected (Repositories/ vs SmartSearches/Shared/):"
  $dupes | ForEach-Object { Write-Host "  $($_.Guid)  in  $($_.Path)" }
  throw "Resolve duplicates before declaring deserialize complete."
}
```

**Recovery if Check 3 fails:** Delete the duplicate from the wrong location per the rule above (feed queries stay in `Repositories/`, dashboard queries stay in `SmartSearches/Shared/`), then **restart the host** — the in-memory cache will not invalidate without it. Do not retry the sweep until the host is back up.

## Check 4: Template-reference walk (defense-in-depth)

**What is verified:** Every `<Parameter Name="Template" Value="...">` reference inside `EcomFeed.FeedProviderConfiguration` resolves to an existing file under `wwwroot/Files/Templates/`. Strict-mode Serializer should already raise these as part of its "missing templates" category (Section 5 of [`deserialize-flow.md`](deserialize-flow.md), category 2 of 4). Check 4 is defense-in-depth.

**Probe (verify the XPath against the actual `EcomFeed` schema at run time):**

```powershell
$feedQuery = @"
SELECT FeedProviderConfiguration FROM EcomFeed WHERE FeedProviderConfiguration IS NOT NULL
"@
$feeds = sqlcmd -S "localhost\SQLEXPRESS" -E -d $db -Q $feedQuery -h -1 -W
$missing = @()
foreach ($cfgXml in $feeds) {
  if ([string]::IsNullOrWhiteSpace($cfgXml)) { continue }
  try {
    $cfg = [xml]$cfgXml
    $cfg.SelectNodes("//Parameter[@Name='Template']") | ForEach-Object {
      $tpl = $_.Value
      if ($tpl -and -not (Test-Path "Dynamicweb.Host.Suite/wwwroot/Files/Templates/$tpl")) {
        $missing += $tpl
      }
    }
  } catch { Write-Host "Skipping malformed FeedProviderConfiguration: $_" }
}
if ($missing) {
  Write-Host "Missing templates referenced by EcomFeed:"
  $missing | ForEach-Object { Write-Host "  $_" }
  throw "Stage missing templates before declaring deserialize complete."
}
```

**Note:** If strict-mode Serializer already raised these, Check 4 is a no-op. If Check 4 fires and strict mode did NOT, strict mode missed a category — document it in the per-demo `CUSTOMISATIONS.md` as an environmental drift note so the next deserialize on this machine inherits the warning.

## Check 5: BuildIndex (by the `.index` Build Name) + wait for a fresh successful build

**What is verified:** The products index rebuilds end-to-end and reaches a successful terminal state within 15 minutes, with a build timestamp newer than this run's trigger, on **every instance**. Without a fresh build, products are invisible to dashboards, feeds, and storefront facets even though the deserialize succeeded.

**Repository and index names are solution-specific** — read them from `wwwroot/Files/System/Repositories/<Repository>/<Name>.index` on the host before firing the build (a stock Swift solution ships `ProductsFrontend`/`ProductsBackend` repositories, not a `Products` one). Never hardcode `Repository = "Products"`.

**Resolve `BuildName` from the `.index` file — never post the literal string `"Full"`.** The Management API `BuildName` must be the `<Build Name="…">` value declared inside the `.index` XML (e.g. `Content builder`), not a generic label. `POST /admin/api/BuildIndex {"BuildName":"Full"}` returns **500 "Unable to load build 'Full'"** on a solution whose build is named anything else. Read the name off the file:

```powershell
$idxPath   = "wwwroot/Files/System/Repositories/$repo/$idx"   # $idx already includes .index
$buildName = ([xml](Get-Content $idxPath -Raw)).SelectSingleNode('//Build/@Name').Value
if (-not $buildName) { throw "No <Build Name> in $idxPath — cannot resolve BuildName." }
```

**Multi-instance indexes must be built TWICE.** DW multi-instance Lucene indexes (a `LastUpdated` rolling balancer with 2 instances) refresh **one instance per build run** — a single build leaves the sibling instance stale, reporting "must be recovered". Fire the build once, wait for a fresh Success, then fire it again so both instances become current. The probe below wraps the build-and-wait in a two-pass loop and asserts every instance reports a fresh successful build at the end.

**Status contract (DW 10.26.x):** the index status models carry no `Status`/`Idle` field — the wait-for-Idle recipe predates them. Two status queries exist:

- `GET /admin/api/IndexStatusByRepositoryAndIndexName?Repository=<repo>&IndexName=<name>.index` → model `{ State: Success|Warning|Error, StateDescription, LastRun, ... }`
- `GET /admin/api/InstanceStatusByName?Repository=<repo>&IndexName=<name>.index&InstanceName=<instance>` → model `{ State: Completed|Failed|Running, LifecycleState: NeverBuilt|Starting|Running|Completed|Failed|Interrupted, LastSuccessfulBuild, CurrentCount, TotalCount }`

Confirm the exact paths against the host's own catalog (`GET /admin/api/api.json`, bearer-authed) when in doubt. Live JSON responses come back **camelCase** even though the catalog declares PascalCase — PowerShell property access is case-insensitive so the probe below is unaffected; case-sensitive consumers must expect camelCase.

**Probe:**

```powershell
$repo = '<Repository>'   # read from Files/System/Repositories/ — solution-specific
$idx  = '<Name>.index'
$idxPath   = "wwwroot/Files/System/Repositories/$repo/$idx"
$buildName = ([xml](Get-Content $idxPath -Raw)).SelectSingleNode('//Build/@Name').Value  # NEVER "Full"
if (-not $buildName) { throw "No <Build Name> in $idxPath — cannot resolve BuildName." }

# Build TWICE — one instance refreshes per run on a 2-instance index.
foreach ($pass in 1..2) {
  $posted = Get-Date
  Invoke-RestMethod `
    -Uri "https://localhost:$port/admin/api/BuildIndex" `
    -Method POST `
    -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
    -Body (@{ Repository = $repo; IndexName = $idx; BuildName = $buildName } | ConvertTo-Json) `
    -SkipCertificateCheck

  # Poll the index status query until Success with a build timestamp fresh against $posted
  $timeout = (Get-Date).AddMinutes(15)
  do {
    Start-Sleep -Seconds 5
    $status = Invoke-RestMethod `
      -Uri "https://localhost:$port/admin/api/IndexStatusByRepositoryAndIndexName?Repository=$repo&IndexName=$idx" `
      -Headers @{ Authorization = "Bearer $token" } `
      -SkipCertificateCheck
    Write-Host "Pass $pass  State: $($status.Model.State)  LastRun: $($status.Model.LastRun)"
    if ($status.Model.State -eq 'Error') {
      # A never-built index reports index-level State=Error ("no healthy instance is available")
      # WHILE its first build is still writing — no instance is online until that build
      # completes. Error is terminal only when the instance's LifecycleState is Failed.
      $inst = Invoke-RestMethod `
        -Uri "https://localhost:$port/admin/api/InstanceStatusByName?Repository=$repo&IndexName=$idx&InstanceName=$($idx -replace '\.index$','')" `
        -Headers @{ Authorization = "Bearer $token" } `
        -SkipCertificateCheck
      if ($inst.Model.LifecycleState -eq 'Failed') { throw "BuildIndex failed: instance LifecycleState=Failed." }
    }
  } until (($status.Model.State -eq 'Success' -and [datetime]$status.Model.LastRun -gt $posted) -or (Get-Date) -gt $timeout)

  if (-not ($status.Model.State -eq 'Success' -and [datetime]$status.Model.LastRun -gt $posted)) {
    throw "BuildIndex pass $pass did not reach a fresh Success state within 15 minutes."
  }
}
```

**Assert every instance is current, not just one.** After the two passes, confirm each instance of the index reports a fresh successful build — a single healthy instance masks a stale sibling. Query `InstanceStatusByName` per instance and check `LastSuccessfulBuild` is fresh against the run; any instance still reporting "must be recovered" means the second pass didn't take — recover it (below).

**Freshness is part of the pass condition:** a prior run's successful build satisfies a state-only check, so always compare `LastRun`/`LastSuccessfulBuild` against this run's POST timestamp. An instant pass on a large catalog is the smell that you verified a stale build, not this one.

**DoS-bound:** The polling loop is hard-bounded at 15 minutes. On timeout the check throws — there is no infinite-loop path.

**Recovery if Check 5 fails (generic):** the host needs a restart; verify the Lucene index files on disk and re-run Check 5 after the restart.

**Recovery for a corrupt / "blocking repair candidate" instance.** A `Stop-Process -Force` during a build (see `dw-demo-base/SKILL.md` "Host lifecycle authority" — never force-kill mid-build) leaves an instance stale or corrupt: persistent "blocking repair candidate", or a sibling reporting "must be recovered" that a single rebuild won't clear. Recipe:

1. **Stop the host** gracefully (no `-Force`).
2. **Delete the index instance dirs + the build state:**
   - `wwwroot/Files/System/Indexes/<Repository>/<index>/` (the Lucene instance directories)
   - `wwwroot/Files/System/Diagnostics/IndexBuildState/<Repository>/<index>.index` (the stale build-state marker)
3. **Restart the host** and wait for `/Admin` 200.
4. **Rebuild twice** via the probe above (both instances current).

Deleting only the instance dirs without the `IndexBuildState` marker re-hydrates the corrupt state on restart — remove both.

### Files.index stuck running/0-0 — known non-blocking, don't chase it mid-deserialize

Stock `Files.index` ships **2 instances with an empty `<Folder>`**; under the concurrent build triggers of the post-deserialize churn its instances can lock-contend and hang at `State=Running` / `CurrentCount-TotalCount = 0-0`. This kills admin **file search** but leaves the **storefront unaffected** — it is a known non-blocking signature, not a generic Check-5 failure. When the sweep sees `Files.index` running/0-0:

- **Classify it as the known case**, report it with the remedy, and do **not** treat it as a blocker or chase it mid-deserialize.
- **Remedy in a quiet phase:** host restart, then **one sequential build per instance** for `Files.index` (not concurrent) — the sequential build clears the lock contention the concurrent triggers created.

## Check 6: Icon set populated under `Files/Images/Icons/` (Pitfall: blank-blue-button storefront)

**What is verified:** The `wwwroot/Files/Images/Icons/` folder exists and contains the SVG set Swift's templates expect — at minimum `heart.svg`, `cart-shopping.svg`, `eye.svg`, `ellipsis.svg`, `chevron-left.svg`, `chevron-right.svg`, `arrow-left-from-bracket.svg`, `magnifying-glass.svg`, `trash-can.svg`. The full Swift baseline ships ~80 icons under `Files/Images/Icons/{root, Flags, LoginProviders}/`; this check is satisfied by `heart.svg` existing.

**Why this matters:** The `dw10-suite` `dotnet new` template scaffolds `wwwroot/Files/Images/` empty. Swift's design package (under `Files/Templates/Designs/Swift-v2/**`) references **54 distinct icons** via `ReadFile("/Files/Images/Icons/<name>.svg")` calls in templates like `Components/ToggleFavorite.cshtml`, `eCom/CustomerExperienceCenter/Favorites/Detail/FavoriteDetail.cshtml`, `Users/UserView/Detail/UserAvatar.cshtml`, `Paragraph/Swift-v2_MyAccount/UserAvatar.cshtml`, the side-nav templates, the orders-list ACTIONS column, and many more.

`ReadFile()` returns an empty string for a missing file — it does NOT throw and does NOT log. The wrapper element renders without content. Combined with Swift's stock pattern of icon-only buttons (`<button class="btn btn-primary"><span>@ReadFile(...)</span></button>`), every icon-bearing control becomes a literal blue square: favorites toggle, side-nav menu items, orders-list ACTIONS column, role avatars, the lot. The page still loads, no errors in the logs, but the storefront looks broken in a way that's impossible to triage from the symptoms.

This is **not** a Serializer concern (icons aren't in the data baseline) and **not** a re-skin concern (`<customer>_custom.css` can't conjure missing files). It's pure asset hygiene that the dw10-suite template doesn't cover.

**Probe:**

```powershell
$iconRoot = "Dynamicweb.Host.Suite/wwwroot/Files/Images/Icons"
$probe = "heart.svg", "cart-shopping.svg", "eye.svg", "ellipsis.svg", "chevron-left.svg", "chevron-right.svg"
$missing = $probe | Where-Object { -not (Test-Path (Join-Path $iconRoot $_)) }
if ($missing) {
    Write-Host "Missing icons under $iconRoot :"
    $missing | ForEach-Object { Write-Host "  $_" }
    throw "Icon set incomplete. Copy from the local Swift clone's Files\Images\Icons\ (e.g. <demo-root>\dw-swift\Files\Images\Icons\) before declaring deserialize complete."
}
```

**Recovery if Check 6 fails:** Copy the entire icon directory from the local Swift repo clone — the SAME clone [`deserialize-flow.md`](deserialize-flow.md) §"Design-package deploy" copies templates and styles from (`<demo-root>\dw-swift\`, a clone of `https://github.com/dynamicweb/Swift`). It carries the canonical set (~80 files including `Flags/` and `LoginProviders/` subdirs):

```powershell
$src = "<demo-root>\dw-swift\Files\Images\Icons"
$dst = "Dynamicweb.Host.Suite\wwwroot\Files\Images\Icons"
Copy-Item -Path $src -Destination $dst -Recurse -Force
```

No host restart required — `ReadFile` reads on every render.

**Pitfall:** if the deserialize used a non-Swift baseline (e.g. a customer-flavoured baseline with a curated icon subset), do NOT blanket-copy the generic Swift icon set — start from the baseline's own asset set and merge in any missing files individually. Audit the result with `git status` so the demo's `CUSTOMISATIONS.md` can record the asset-source provenance.

## Check 7: Raw SQL in paragraph templates (DW10 discipline)

**What is verified:** No paragraph template under `Templates\Designs\Swift-v2\Paragraph\` reaches around the DW10 service layer with raw `Database.*` calls. Raw `Database.CreateDataReader` / `ExecuteScalar` / `ExecuteReader` / `ExecuteNonQuery` in a `.cshtml` is a known hot-path maintenance trap — it fails silently on DW10 schema renames and routinely leaks pricing / permissions / cross-tenant data because the SQL bypasses the per-context scoping the `Services.*` APIs apply.

**Probe:**

```powershell
$Root = "Dynamicweb.Host.Suite\wwwroot"
$hits = Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2\Paragraph" -Recurse -Filter '*.cshtml' `
  | Select-String -Pattern 'Database\.(CreateDataReader|ExecuteScalar|ExecuteReader|ExecuteNonQuery)'
if ($hits) {
    Write-Host "Raw DB access in paragraph templates:"
    $hits | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)  $($_.Line.Trim())" }
    throw "Replace each hit with the appropriate Services.* API. See dw10-canonical-surfaces.md."
}
```

**Why this matters:** the storefront still renders during the failure mode — the affected paragraph swallows its SQL error and emits empty content, the page returns 200, and the bug only surfaces when the customer notices missing data on demo day.

**Recovery:** for each hit, identify the canonical `Services.*` / `Pageview.*` surface and replace the
raw SQL with it (e.g. `SELECT FROM AccessUserGroupRelation` → `Pageview.User.GetGroups()`;
`SELECT FROM EcomPrices` → `Services.Prices.GetByProductId(...)`; per-customer `EcomOrders` →
`Services.Orders.GetCustomerOrdersByType(...)`; `EcomProducts` → `Services.Products.GetProductById(...)`;
URL-substring → `GetPageIdByNavigationTag(...)`). The full substitution table and the surface
inventory are vendor-generic and owned by the `dw-render-razor` foundational skill — staged in
[`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §1 ("Canonical surfaces
— use these, don't re-implement").

Pair with the wider discipline grep pack — vendor-generic, owned by the `dw-swift-building` foundational
skill — staged in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md)
§10 ("Discipline audit — grep pack"). Check 7 is the gating subset (raw DB access only); the audit
pack covers URL substring scans, hard-coded slugs, category-name branching, master-inline
`AddStylesheet`, etc.

## Check 8: Style assets staged + emitted (the theme gate)

**What is verified:** the Areas' style wiring resolves to real files, and the storefront actually
emits the three style links. `TryGet*Style` fails **silently** when the file behind an Area's
style id is absent, and `swift.css` alone renders a page that looks "almost right" — structural
layout intact, every font in the browser's serif fallback, buttons unstyled. Hosts have shipped
in that state without anyone noticing, because nothing errors.

**Probe:**

```powershell
# 1. Files on disk match the Area wiring
$styles = "Dynamicweb.Host.Suite\wwwroot\Files\System\Styles"
$wiring = sqlcmd -S $server -E -d $db -h -1 -Q "SET NOCOUNT ON;
  SELECT AreaColorSchemeGroupId + '|' + AreaButtonStyleId + '|' + AreaTypographyId
  FROM Area WHERE AreaId = <main-area-id>"
$ids = $wiring.Trim() -split '\|'
foreach ($pair in @("ColorSchemes\$($ids[0])", "Buttons\$($ids[1])", "Typography\$($ids[2])")) {
    if (-not (Test-Path "$styles\$pair.css") -or -not (Test-Path "$styles\$pair.json")) {
        throw "Style asset missing: $pair.{json,css} — stage the theme (deserialize-flow 'Stage the theme') before continuing."
    }
}
# 2. The rendered page emits all three links, each returning 200
$html = (Invoke-WebRequest "https://localhost:$port/" -SkipCertificateCheck -UseBasicParsing).Content
foreach ($dir in 'ColorSchemes','Buttons','Typography') {
    if ($html -notmatch "Styles/$dir/[^""]+\.css") { throw "Home <head> emits no $dir stylesheet — empty-state pitfall." }
}
```

**Beyond the mechanical probe:** a full-page screenshot of the home page must read as a
*designed* page — brand or neutral-theme typography, styled buttons, coherent color schemes.
A page in serif fallback with browser-default buttons fails this check even when it renders
without errors. Run the polish gate in
[`visual-qa.md`](../../dw-demo-base/references/visual-qa.md) before declaring the host ready.

**Recovery:** stage the theme's three pairs and rewire the Areas per
[`deserialize-flow.md`](deserialize-flow.md) "Stage the theme's Style assets" +
[`styles-assets.md`](styles-assets.md); restart so the resolved style URLs reload.

## Sweep complete

When all eight checks pass, deserialize is verified complete. The skill may now declare "baseline restored" to the user.

Log the result + layer name + timestamp in the per-demo `CUSTOMISATIONS.md` as a deserialize event row, and record the resolved commit SHA there too. This is structural — every deserialize is reproducible by re-running this flow against the same layer name at the commit SHA recorded in `CUSTOMISATIONS.md` (consumers pin `origin/main`; the SHA is the forensic reproducibility stamp).


