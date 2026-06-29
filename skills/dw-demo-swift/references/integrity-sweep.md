# integrity-sweep.md

## Contents

- [Prerequisites](#prerequisites)
- [Why this sweep is mandatory](#why-this-sweep-is-mandatory)
- [Check 1: FK orphans (strict-mode-delegated)](#check-1-fk-orphans-strict-mode-delegated)
- [Check 2: `reference_category` parent row](#check-2-reference_category-parent-row)
- [Check 3: Query GUID dedup across `Repositories/` and `SmartSearches/Shared/`](#check-3-query-guid-dedup-across-repositories-and-smartsearchesshared)
- [Check 4: Template-reference walk (defense-in-depth)](#check-4-template-reference-walk-defense-in-depth)
- [Check 5: BuildIndex Full + wait-for-Idle](#check-5-buildindex-full--wait-for-idle)
- [Check 6: Icon set populated under `Files/Images/Icons/` (Pitfall: blank-blue-button storefront)](#check-6-icon-set-populated-under-filesimagesicons-pitfall-blank-blue-button-storefront)
- [Check 7: Raw SQL in paragraph templates (DW10 discipline)](#check-7-raw-sql-in-paragraph-templates-dw10-discipline)
- [Sweep complete](#sweep-complete)

> Mandatory post-deserialize integrity sweep. Seven sequential checks. Run after [`deserialize-flow.md`](deserialize-flow.md) returns 2xx. The skill refuses to declare deserialize complete until ALL seven pass. Strict-mode Serializer is the first line of defence — this sweep is the second, catching DW10-specific failures strict mode does not detect.

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
- Index staleness immediately after a deserialize (products invisible until BuildIndex Full + wait-for-Idle).

The sweep adds defense-in-depth for these categories. Skipping it produces a deserialized DB that *looks* clean but is silently broken on demo day.

## Check 1: FK orphans (strict-mode-delegated)

**What is verified:** No FK orphans were introduced by the deserialize.

**How:** DynamicWeb.Serializer strict mode (default-on for API callers — see [`deserialize-flow.md`](deserialize-flow.md) Section 5) raises FK orphans as `CumulativeStrictModeException` during the deserialize POST. The sweep does NOT run a separate per-pair orphan SQL loop — that would be redundant and costly. Instead, this check is satisfied by:

1. [`deserialize-flow.md`](deserialize-flow.md) was followed (strict mode default — disabling strict mode is forbidden by that flow).
2. The deserialize POST returned HTTP 2xx (no `CumulativeStrictModeException` body).

If both of those are true, Check 1 passes. If either is false, Check 1 fails — return to [`deserialize-flow.md`](deserialize-flow.md) and re-run with strict mode on.

**Why no separate SQL loop:** Strict mode is the canonical FK-orphan detector for DynamicWeb.Serializer. Adding an `INFORMATION_SCHEMA`-driven per-pair count would duplicate work the Serializer already did, with worse performance and worse error messages.

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

## Check 5: BuildIndex Full + wait-for-Idle

**What is verified:** The `Products` repository's `Products.index` rebuilds end-to-end and reaches `Status = Idle` within 15 minutes. Without a fresh build, products are invisible to dashboards, feeds, and storefront facets even though the deserialize succeeded.

**Probe:**

```powershell
$buildResp = Invoke-RestMethod `
  -Uri "https://localhost:$port/admin/api/BuildIndex" `
  -Method POST `
  -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
  -Body (@{ Repository = "Products"; IndexName = "Products.index"; BuildName = "Full" } | ConvertTo-Json) `
  -SkipCertificateCheck

# Poll IndexStatus
$timeout = (Get-Date).AddMinutes(15)
do {
  Start-Sleep -Seconds 5
  $status = Invoke-RestMethod `
    -Uri "https://localhost:$port/admin/api/IndexStatus?Repository=Products&IndexName=Products.index" `
    -Headers @{ Authorization = "Bearer $token" } `
    -SkipCertificateCheck
  Write-Host "IndexStatus: $($status.Status)  LastBuildTime: $($status.LastBuildTime)"
} until ($status.Status -eq 'Idle' -or (Get-Date) -gt $timeout)

if ($status.Status -ne 'Idle') {
  throw "BuildIndex did not reach Idle within 15 minutes."
}
```

**DoS-bound:** The polling loop is hard-bounded at 15 minutes. On timeout the check throws — there is no infinite-loop path.

**Recovery if Check 5 fails:** the host needs a restart; verify the Lucene index files on disk and re-run Check 5 after the restart.

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
    throw "Icon set incomplete. Copy from $env:DW_VAULT\<swift-baseline-slot>\Dynamicweb.Host.Suite\wwwroot\Files\Images\Icons\ before declaring deserialize complete."
}
```

**Recovery if Check 6 fails:** Copy the entire icon directory from a known-good Swift baseline. The vault's Swift baseline carries the canonical set (~80 files including `Flags/` and `LoginProviders/` subdirs):

```powershell
$src = "$env:DW_VAULT\<swift-baseline-slot>\Dynamicweb.Host.Suite\wwwroot\Files\Images\Icons"
$dst = "Dynamicweb.Host.Suite\wwwroot\Files\Images\Icons"
Copy-Item -Path $src -Destination $dst -Recurse -Force
```

Substitute `<swift-baseline-slot>` for whatever the vault's `INDEX.md` names as the Swift baseline slot for this project (e.g. `Swift2.2`). No host restart required — `ReadFile` reads on every render.

**Pitfall:** if the deserialize used a non-Swift baseline (e.g. a customer-flavoured baseline with a curated icon subset), do NOT blanket-copy from the generic Swift slot — start from the baseline-flavoured slot and merge in any missing files individually. Audit the result with `git status` so the demo's `CUSTOMISATIONS.md` can record the asset-source provenance.

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

## Sweep complete

When all seven checks pass, deserialize is verified complete. The skill may now declare "baseline restored" to the user.

Log the result + baseline name + timestamp in the per-demo `CUSTOMISATIONS.md` as a deserialize event row. This is structural — every deserialize is reproducible by re-running this flow against the same baseline plus the vault commit recorded in `$env:DW_VAULT\INDEX.md`'s `serialized-data` row.


