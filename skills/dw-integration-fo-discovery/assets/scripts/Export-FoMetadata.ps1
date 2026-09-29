<#
.SYNOPSIS
  Pull the structural model of a D365 F&O environment into the normalized discovery model JSON.

.DESCRIPTION
  Sources, in order:
    1. POST /data/SystemNotifications/Microsoft.Dynamics.DataEntities.GetInstalledModules  (undocumented action; ISV/publisher inventory — tolerated failure)
    2. POST /data/DataManagementEntities/Microsoft.Dynamics.DataEntities.GetApplicationVersion + GetPlatformBuildVersion (tolerated failure)
    3. GET  /Metadata/DataEntities   (all data entities: category, DM/OData enablement, read-only, LabelId)
    4. GET  /Metadata/PublicEntities (OData-exposed entities with Properties[] incl. TypeName = EDT, IsKey, IsMandatory; NavigationProperties[])
    5. GET  /Metadata/PublicEnumerations (optional, -IncludeEnums)
    6. GET  /data/$metadata          (optional, -IncludeCsdl; saved verbatim for baseline diffing — large)
  Origin classification per entity: label file of LabelId (@SYS*, known Microsoft files -> standard), publisher from installed
  modules, and -PrefixMap on the entity/field name. Unknown label files are listed in labelFiles[] for manual classification.
  Company scope = presence of a `dataAreaId` property.

.PARAMETER EnvironmentUrl  https://<env>.operations.dynamics.com (defaults to $env:FO_ENV_URL)
.PARAMETER Token           Bearer token (defaults to $env:FO_TOKEN from Get-FoToken.ps1)
.PARAMETER OutDir          Folder for raw pulls + model.odata.json (default .\discovery)
#>
[CmdletBinding()]
param(
  [string]$EnvironmentUrl = $env:FO_ENV_URL,
  [string]$Token = $env:FO_TOKEN,
  [string]$OutDir = '.\discovery',
  [hashtable]$PrefixMap = @{},
  [hashtable]$LabelFileMap = @{},
  [switch]$IncludeEnums,
  [switch]$IncludeCsdl
)
$ErrorActionPreference = 'Stop'
if (-not $EnvironmentUrl -or -not $Token) { throw 'EnvironmentUrl and Token are required (run Get-FoToken.ps1 first).' }
$EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')
$headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json'; 'OData-MaxVersion' = '4.0' }
New-Item -ItemType Directory -Force -Path $OutDir, (Join-Path $OutDir 'metadata') | Out-Null
$utf8 = [System.Text.UTF8Encoding]::new($false)
function Save([string]$name, $obj) { [System.IO.File]::WriteAllText((Join-Path $OutDir "metadata\$name"), ($obj | ConvertTo-Json -Depth 12), $utf8) }

function Get-All([string]$url) {
  $items = @(); $next = $url
  while ($next) {
    $r = Invoke-RestMethod -Uri $next -Headers $headers -Method Get
    if ($null -ne $r.value) { $items += $r.value } else { $items += $r }
    $next = $r.'@odata.nextLink'
  }
  return $items
}
function Try-Action([string]$path) {
  try { return (Invoke-RestMethod -Uri "$EnvironmentUrl$path" -Headers $headers -Method Post -Body '{}' -ContentType 'application/json') }
  catch { Write-Warning "action $path failed: $($_.Exception.Message)"; return $null }
}

# 1-2. Versions and installed modules (undocumented actions; may be role-gated)
$modulesRaw = Try-Action '/data/SystemNotifications/Microsoft.Dynamics.DataEntities.GetInstalledModules'
$appVersion = Try-Action '/data/DataManagementEntities/Microsoft.Dynamics.DataEntities.GetApplicationVersion'
$platVersion = Try-Action '/data/DataManagementEntities/Microsoft.Dynamics.DataEntities.GetPlatformBuildVersion'
$modules = @()
if ($modulesRaw) {
  foreach ($line in @($modulesRaw.value)) {
    $m = [ordered]@{ raw = "$line" }
    foreach ($kv in ("$line" -split '\|')) { if ($kv -match '^\s*(\w+)\s*:\s*(.*?)\s*$') { $m[$Matches[1]] = $Matches[2] } }
    $modules += $m
  }
  Save 'installed-modules.json' $modules
}
$publishers = @($modules | ForEach-Object { $_['Publisher'] } | Where-Object { $_ } | Sort-Object -Unique)
$isvModules = @($modules | Where-Object { $_['Publisher'] -and $_['Publisher'] -notmatch 'Microsoft' })

# 3. DataEntities
Write-Host 'pulling /Metadata/DataEntities …'
$dataEntities = Get-All "$EnvironmentUrl/Metadata/DataEntities?`$select=Name,PublicEntityName,PublicCollectionName,LabelId,DataServiceEnabled,DataManagementEnabled,EntityCategory,IsReadOnly"
Save 'data-entities.json' $dataEntities
$deByPublic = @{}; foreach ($d in $dataEntities) { if ($d.PublicEntityName) { $deByPublic[$d.PublicEntityName] = $d } }

# 4. PublicEntities (full; can be tens of MB — paged when the service pages)
Write-Host 'pulling /Metadata/PublicEntities …'
$publicEntities = Get-All "$EnvironmentUrl/Metadata/PublicEntities"
Save 'public-entities.json' $publicEntities

# 5. Enumerations
if ($IncludeEnums) { Write-Host 'pulling /Metadata/PublicEnumerations …'; Save 'public-enumerations.json' (Get-All "$EnvironmentUrl/Metadata/PublicEnumerations") }

# 6. CSDL
if ($IncludeCsdl) {
  Write-Host 'pulling /data/$metadata (large) …'
  Invoke-WebRequest -Uri "$EnvironmentUrl/data/`$metadata" -Headers @{ Authorization = "Bearer $Token" } -OutFile (Join-Path $OutDir 'metadata\metadata.edmx') | Out-Null
}

# Origin classification
$microsoftLabelFiles = @('SYS','SYP','GLS','SYM','APM','ApplicationPlatform','ApplicationFoundation','ApplicationSuite','AccountsReceivable','AccountsPayable','SCM','Retail','Warehousing','ProductInformationManagement','Procurement','Project','Fleet','HumanResources','CashManagement','Budget','Tax','Ledger','FixedAssets','Sales','Inventory','ProductionControl','MasterPlanning','CostAccounting','Expense','GeneralLedger','ServiceManagement','AssetManagement','TransportationManagement','BusinessEvents','DataManagement','DualWrite','Copilot','Personnel','Payroll','Directory','GlobalAddressBook','Cases','Commerce','PublicSector','Electronic')
# Baseline of Microsoft label files observed on a stock tenant (assets/data/microsoft-label-files.txt) — the hard-coded list above is the fallback.
$baselineFile = Join-Path $PSScriptRoot '..\data\microsoft-label-files.txt'
if (Test-Path $baselineFile) { $microsoftLabelFiles += @(Get-Content $baselineFile | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }) }
$microsoftModuleNames = @($modules | Where-Object { $_['Publisher'] -match 'Microsoft' } | ForEach-Object { @($_['Module'], $_['Name']) } | Where-Object { $_ } | Sort-Object -Unique)
# When every installed module is published by Microsoft there is no ISV/custom layer: every label file is standard.
$allMicrosoft = ($modules.Count -gt 0) -and ($isvModules.Count -eq 0)
function Get-LabelFile([string]$labelId) { if ($labelId -match '^@([A-Za-z0-9_]+?)(?::|\d)') { return $Matches[1] }; if ($labelId -match '^@(\w+)') { return $Matches[1] }; return '' }
function Get-Origin([string]$name, [string]$labelId) {
  $lf = Get-LabelFile $labelId
  if ($lf -and $LabelFileMap.ContainsKey($lf)) { return [pscustomobject]@{ prefix = $lf; origin = $LabelFileMap[$lf] } }
  $hit = $PrefixMap.Keys | Where-Object { $name.StartsWith($_, [System.StringComparison]::Ordinal) } | Sort-Object Length -Descending | Select-Object -First 1
  if ($hit) { return [pscustomobject]@{ prefix = $hit; origin = $PrefixMap[$hit] } }
  if ($lf -and ($allMicrosoft -or ($microsoftLabelFiles -contains $lf) -or ($microsoftModuleNames -contains $lf))) { return [pscustomobject]@{ prefix = $lf; origin = 'standard' } }
  if ($lf) {
    $isv = $isvModules | Where-Object { $_['Name'] -eq $lf -or $_['Module'] -eq $lf } | Select-Object -First 1
    if ($isv) { return [pscustomobject]@{ prefix = $lf; origin = "isv:$($isv['Publisher'])" } }
    return [pscustomobject]@{ prefix = $lf; origin = 'unknown' }
  }
  if ($name -cmatch '^([A-Z]{2,5}_?)(?=[A-Z][a-z])') { return [pscustomobject]@{ prefix = $Matches[1]; origin = $(if ($allMicrosoft) { 'standard' } else { 'unknown' }) } }
  return [pscustomobject]@{ prefix = ''; origin = 'standard' }
}

$labelFileCounts = @{}
$entities = foreach ($pe in $publicEntities) {
  $de = $deByPublic[$pe.Name]
  $lf = Get-LabelFile $pe.LabelId; if ($lf) { $labelFileCounts[$lf] = [int]$labelFileCounts[$lf] + 1 }
  $props = @($pe.Properties)
  $fields = foreach ($p in $props) {
    $flf = Get-LabelFile $p.LabelId
    [ordered]@{
      name = $p.Name; type = "$($p.DataType)".ToLower()
      edt = $null   # the Metadata service exposes no EDTs: TypeName is an Edm.* primitive or the enum type name
      enum = $(if ("$($p.TypeName)" -like 'Microsoft.Dynamics.DataEntities.*') { "$($p.TypeName)".Split('.')[-1] } else { $null })
      labelId = $p.LabelId   # same LabelId across entities = same business concept; the grouping key for key centrality on OData models
      mandatory = [bool]$p.IsMandatory; isKey = [bool]$p.IsKey; allowEdit = [bool]$p.AllowEdit; isDimension = [bool]$p.IsDimension
      labelFile = $flf; origin = (Get-Origin $p.Name $p.LabelId).origin
    }
  }
  $relations = foreach ($nav in @($pe.NavigationProperties)) {
    $pairs = @()
    foreach ($c in @($nav.Constraints)) { if ($c.Property -or $c.ReferencedProperty) { $pairs += [ordered]@{ field = $c.Property; relatedField = $c.ReferencedProperty } } }
    [ordered]@{ name = $nav.Name; table = $nav.RelatedEntity; cardinality = $nav.Cardinality; fields = $pairs }
  }
  [ordered]@{
    name = $pe.Name; kind = 'entity'; collection = $pe.EntitySetName; aotName = $de.Name; label = $pe.LabelId
    category = "$($de.EntityCategory)"; dataManagementEnabled = [bool]$de.DataManagementEnabled; isReadOnly = [bool]$pe.IsReadOnly
    saveDataPerCompany = [bool]($props | Where-Object { $_.Name -eq 'dataAreaId' })
    keys = @($props | Where-Object { $_.IsKey } | ForEach-Object { $_.Name })
    fields = @($fields); indexes = @(); relations = @($relations)
    actions = @(@($pe.Actions) | ForEach-Object { $_.Name })
    origin = (Get-Origin $pe.Name $pe.LabelId)
  }
}

# Data entities that are DM-only (no OData contract) still matter for the census of what exists.
$dmOnly = @($dataEntities | Where-Object { -not $_.DataServiceEnabled } | ForEach-Object { [ordered]@{ name = $_.Name; publicName = $_.PublicEntityName; category = "$($_.EntityCategory)"; label = $_.LabelId; origin = (Get-Origin $_.Name $_.LabelId) } })

$model = [ordered]@{
  source = [ordered]@{ kind = 'odata'; environment = $EnvironmentUrl; applicationVersion = "$($appVersion.value)"; platformVersion = "$($platVersion.value)" }
  installedModules = $modules
  publishers = $publishers
  labelFiles = @($labelFileCounts.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { [ordered]@{ labelFile = $_.Key; entities = $_.Value; origin = (Get-Origin '' "@$($_.Key):x").origin } })
  entities = @($entities)
  dataManagementOnlyEntities = $dmOnly
}
$outPath = Join-Path (Resolve-Path $OutDir) 'model.odata.json'
[System.IO.File]::WriteAllText($outPath, ($model | ConvertTo-Json -Depth 10), $utf8)

# entities.csv for the brief
$csv = $entities | ForEach-Object { [pscustomobject]@{ name = $_.name; collection = $_.collection; aotName = $_.aotName; category = $_.category; origin = $_.origin.origin; labelFile = $_.origin.prefix; companyScoped = $_.saveDataPerCompany; readOnly = $_.isReadOnly; fields = $_.fields.Count; customFields = @($_.fields | Where-Object { $_.origin -ne 'standard' }).Count } }
$csv | Export-Csv -Path (Join-Path $OutDir 'entities.csv') -NoTypeInformation -Encoding utf8
Write-Host ("modules={0} (isv={1}) dataEntities={2} publicEntities={3} labelFiles={4} unknownLabelFiles={5} -> {6}" -f $modules.Count, $isvModules.Count, $dataEntities.Count, @($entities).Count, $labelFileCounts.Count, @($model.labelFiles | Where-Object { $_.origin -eq 'unknown' }).Count, $outPath)
