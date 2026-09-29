<#
.SYNOPSIS
  Population census of a D365 F&O environment: row counts per entity (and per legal entity), field fill rates on a sample,
  and last-modified recency. Output: census.json (+ census.md) in the shape Measure-KeyCentrality.ps1 consumes.

.DESCRIPTION
  Reads model.odata.json from Export-FoMetadata.ps1. For every entity matching -Categories / -Include / -Exclude:
    GET /data/<Collection>/$count?cross-company=true                       total rows (all companies the identity can see)
    GET /data/<Collection>/$count?cross-company=true&$filter=dataAreaId eq 'X'   per company, for company-scoped entities
  For entities with rows > 0 and matching -SampleInclude (default: Master/Document/Transaction with <= 200k rows):
    GET /data/<Collection>?cross-company=true&$top=<SampleSize>[&$orderby=ModifiedDateTime desc]
    -> fill rate per field (non-empty, non-zero, non-1900 date), last modified from the newest sampled row.
  Throttling: -DelayMs between calls; on HTTP 429 the script sleeps Retry-After (or 30 s) and retries the call up to 5 times.
  Everything is read-only GETs. Stay well under the 6,000 requests / 5 min service-protection budget: ~3,000 entities at 150 ms is ~8 min.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Model,
  [string]$EnvironmentUrl = $env:FO_ENV_URL,
  [string]$Token = $env:FO_TOKEN,
  [string]$OutFile = '.\discovery\census.json',
  [string[]]$Categories = @('Master','Document','Transaction','Reference','Parameters','Configuration',''),
  [string]$Include = '.*',
  [string]$Exclude = '^$',
  [string]$SampleInclude = '.*',
  [string[]]$SampleCategories = @('Master','Document','Transaction'),
  [int]$SampleMaxRows = 200000,
  [int]$SampleSize = 200,
  [int]$DelayMs = 150,
  [switch]$SkipPerCompany,
  [switch]$SkipSampling,
  [switch]$Resume,
  [int]$CheckpointEvery = 25,
  [string]$TenantId,
  [string]$ClientId
)
$ErrorActionPreference = 'Stop'
if (-not $EnvironmentUrl -or -not $Token) { throw 'EnvironmentUrl and Token are required (run Get-FoToken.ps1 first).' }
$EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')
$headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json'; 'OData-MaxVersion' = '4.0' }
$utf8 = [System.Text.UTF8Encoding]::new($false)
$calls = 0
$tokenAcquired = Get-Date

# A full census outlives a one-hour token: refresh on 401 (or proactively after 50 min) when -TenantId/-ClientId and $env:FO_CLIENT_SECRET are available.
function Refresh-Token {
  if (-not ($TenantId -and $ClientId -and $env:FO_CLIENT_SECRET)) { throw 'token expired and no -TenantId/-ClientId + $env:FO_CLIENT_SECRET to refresh with' }
  $new = & (Join-Path $PSScriptRoot 'Get-FoToken.ps1') -TenantId $TenantId -ClientId $ClientId -EnvironmentUrl $EnvironmentUrl 6>$null
  $script:headers['Authorization'] = "Bearer $new"; $script:tokenAcquired = Get-Date
}
function Invoke-Fo([string]$url, [switch]$Raw) {
  if (((Get-Date) - $script:tokenAcquired).TotalMinutes -gt 50 -and $TenantId -and $ClientId) { Refresh-Token }
  for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
      Start-Sleep -Milliseconds $DelayMs; $script:calls++
      if ($Raw) { return ((Invoke-WebRequest -Uri $url -Headers $headers -Method Get).Content).Trim([char]0xFEFF, ' ', "`r", "`n") }   # $count replies carry a UTF-8 BOM
      return (Invoke-RestMethod -Uri $url -Headers $headers -Method Get)
    } catch {
      $status = $_.Exception.Response.StatusCode.value__
      if ($status -eq 429) {
        $ra = $_.Exception.Response.Headers['Retry-After']; $wait = if ($ra) { [int]$ra } else { 30 }
        Write-Warning "429 on $url — sleeping $wait s (attempt $attempt)"; Start-Sleep -Seconds $wait; continue
      }
      if ($status -eq 401 -and $attempt -lt 5) { Write-Warning '401 — refreshing token'; Refresh-Token; continue }
      throw
    }
  }
  throw "gave up after 5 attempts: $url"
}

$outPath = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutFile)) }
New-Item -ItemType Directory -Force -Path (Split-Path $outPath -Parent) | Out-Null
function Save-Census($companies, $results) {
  $census = [ordered]@{ environment = $EnvironmentUrl; companies = $companies; calls = $script:calls; entities = $results }
  [System.IO.File]::WriteAllText($outPath, ($census | ConvertTo-Json -Depth 8), $utf8)
}

$m = Get-Content -LiteralPath $Model -Raw | ConvertFrom-Json
$targets = @($m.entities | Where-Object { $_.collection -and ($Categories -contains "$($_.category)") -and $_.name -match $Include -and $_.name -notmatch $Exclude })
Write-Host ("census over {0} entities" -f $targets.Count)

# Legal entities
$companies = @()
if (-not $SkipPerCompany) {
  try { $companies = @((Invoke-Fo "$EnvironmentUrl/data/Companies?`$select=DataArea,Name").value | ForEach-Object { [ordered]@{ id = $_.DataArea; name = $_.Name } }) }
  catch { try { $companies = @((Invoke-Fo "$EnvironmentUrl/data/LegalEntities?`$select=DataArea,Name").value | ForEach-Object { [ordered]@{ id = $_.DataArea; name = $_.Name } }) } catch { Write-Warning "could not list companies: $($_.Exception.Message)" } }
}

function Test-Filled($v, [string]$type) {
  if ($null -eq $v) { return $false }
  if ($v -is [datetime]) { return ($v.Year -gt 1900) }            # ConvertFrom-Json yields DateTime objects; 1900-01-01 / 0001-01-01 are F&O "empty" dates
  $s = "$v"
  if ($s -eq '' -or $s -eq '0' -or $s -eq '0.0' -or $s -eq 'False' -or $s -eq 'No' -or $s -eq 'None' -or $s -eq '00000000-0000-0000-0000-000000000000') { return $false }
  if ($type -match 'date' -and ($s.StartsWith('1900-01-01') -or $s.StartsWith('0001-01-01'))) { return $false }
  return $true
}

$results = @()
$done = [System.Collections.Generic.HashSet[string]]::new()
if ($Resume -and (Test-Path $outPath)) {
  $prev = Get-Content -LiteralPath $outPath -Raw | ConvertFrom-Json
  foreach ($r in @($prev.entities)) { if (-not $r.error) { $results += $r; [void]$done.Add($r.name) } }
  if (-not $companies -and $prev.companies) { $companies = @($prev.companies) }
  Write-Host ("resuming: {0} entities already censused" -f $done.Count)
}
$i = 0
foreach ($e in $targets) {
  $i++
  if ($done.Contains($e.name)) { continue }
  if ($CheckpointEvery -gt 0 -and ($i % $CheckpointEvery) -eq 0) { Save-Census $companies $results }
  $col = $e.collection
  $row = [ordered]@{ name = $e.name; collection = $col; category = "$($e.category)"; origin = $e.origin.origin; companyScoped = [bool]$e.saveDataPerCompany; rows = $null; byCompany = [ordered]@{}; sampled = 0; fields = @(); lastModified = $null; error = $null }
  try {
    $row.rows = [int64](Invoke-Fo "$EnvironmentUrl/data/$col/`$count?cross-company=true" -Raw)
  } catch { $row.error = $_.Exception.Message; $results += $row; Write-Host ("[{0}/{1}] {2}: ERROR {3}" -f $i, $targets.Count, $col, $row.error); continue }
  if ($row.rows -gt 0 -and $row.companyScoped -and $companies.Count -gt 1) {
    foreach ($c in $companies) {
      try { $row.byCompany[$c.id] = [int64](Invoke-Fo "$EnvironmentUrl/data/$col/`$count?cross-company=true&`$filter=dataAreaId eq '$($c.id)'" -Raw) } catch { $row.byCompany[$c.id] = $null }
    }
  }
  $doSample = (-not $SkipSampling) -and $row.rows -gt 0 -and $row.rows -le $SampleMaxRows -and ($SampleCategories -contains "$($e.category)") -and $e.name -match $SampleInclude
  if ($doSample) {
    # Most standard F&O entities expose no ModifiedDateTime; fall back to the first audit/date-like UtcDateTime/Date property.
    $recencyField = $null
    foreach ($cand in @('ModifiedDateTime','CreatedDateTime')) { if ($e.fields | Where-Object { $_.name -eq $cand }) { $recencyField = $cand; break } }
    if (-not $recencyField) { $recencyField = ($e.fields | Where-Object { $_.type -in 'utcdatetime','date' -and $_.name -match '^(Modified|Created|Creation|Order|Invoice|Transaction|Posting|Registration)Date|(Modified|Created|Creation)DateTime$' } | Select-Object -First 1).name }
    $hasMod = [bool]$recencyField
    $q = "$EnvironmentUrl/data/$col`?cross-company=true&`$top=$SampleSize" + $(if ($hasMod) { "&`$orderby=$recencyField desc" } else { '' })
    try {
      $sample = @((Invoke-Fo $q).value)
      $row.sampled = $sample.Count
      if ($sample.Count -gt 0) {
        $typeByName = @{}; foreach ($f in $e.fields) { $typeByName[$f.name] = "$($f.type)" }
        $names = @($sample[0].PSObject.Properties.Name | Where-Object { $_ -notlike '@odata*' })
        $row.fields = @(foreach ($n in $names) { $filled = @($sample | Where-Object { Test-Filled $_.$n $typeByName[$n] }).Count; [ordered]@{ name = $n; fillRate = [math]::Round($filled / $sample.Count, 3) } })
        if ($hasMod) { $row.lastModified = "$($sample[0].$recencyField)"; $row.recencyField = $recencyField }
      }
    } catch { $row.error = "sample: $($_.Exception.Message)" }
  }
  $results += $row
  Write-Host ("[{0}/{1}] {2}: rows={3} sampled={4}" -f $i, $targets.Count, $col, $row.rows, $row.sampled)
}

Save-Census $companies $results

$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine("| Entity | Category | Origin | Rows | Per company | Last modified | Sampled |")
[void]$md.AppendLine('|---|---|---|---|---|---|---|')
foreach ($r in ($results | Where-Object { $_.rows -gt 0 } | Sort-Object rows -Descending)) {
  $bc = ($r.byCompany.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
  [void]$md.AppendLine("| $($r.name) | $($r.category) | $($r.origin) | $($r.rows) | $bc | $($r.lastModified) | $($r.sampled) |")
}
[void]$md.AppendLine(); [void]$md.AppendLine("Present but empty: " + (@($results | Where-Object { $_.rows -eq 0 } | ForEach-Object { $_.name }) -join ', '))
[System.IO.File]::WriteAllText([System.IO.Path]::ChangeExtension($outPath, '.md'), $md.ToString(), $utf8)
Write-Host ("done: {0} entities, {1} populated, {2} errors, {3} calls -> {4}" -f $results.Count, @($results | Where-Object { $_.rows -gt 0 }).Count, @($results | Where-Object { $_.error }).Count, $calls, $outPath)
