<#
.SYNOPSIS
READ-ONLY. PIM observation helpers; definitions only on import.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. Preserves declared-field and relation assertions without a database write. SQL reads need no cache flush. Caller supplies all paths and connections.
.EXAMPLE
. ./Pim.Fields.ps1
#>
#Requires -Version 7.0
function New-PimFeatureCheckRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('PASS', 'FAIL', 'ERROR', 'UNVERIFIED')][string]$Result,
        [string]$Measured = '',
        [string]$Expected = '',
        [string]$Proves = '',
        [string[]]$Offenders = @()
    )
    return [ordered]@{ id = $Id; result = $Result; measured = $Measured; expected = $Expected
                       proves = $Proves; offenders = @($Offenders) }
}

function Get-PimWidgetQueryId {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ("$Value" -split '"')[0].Trim()
}

# Get-PimQueryFileIndex: the id GUIDs and the file names of every .query file in the named folders.

function Get-PimQueryFileIndex {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$FilesPath, [string[]]$Folder)
    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $files = 0
    if ([string]::IsNullOrWhiteSpace($FilesPath)) { return @{ readable = $false; ids = $ids; files = 0 } }
    $guid = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    $any = $false
    foreach ($rel in @($Folder)) {
        $dir = Join-Path $FilesPath $rel
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        $any = $true
        $dirs = @($dir) + @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction Stop | ForEach-Object FullName)
        foreach ($d in $dirs) {
            foreach ($f in @(Get-ChildItem -LiteralPath $d -Filter '*.query' -File -ErrorAction Stop)) {
                $files++
                $null = $ids.Add($f.BaseName)
                $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8 -ErrorAction Stop
                foreach ($m in [regex]::Matches("$text", "(?i)\bid\s*=\s*`"($guid)`"")) { $null = $ids.Add($m.Groups[1].Value) }
            }
        }
    }
    return @{ readable = $any; ids = $ids; files = $files }
}

function Invoke-PimFeatureCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Check,
        [Parameter(Mandatory)]$Build,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$Database,
        [AllowNull()][AllowEmptyString()][string]$FilesPath,
        [hashtable]$Stored
    )
    $id = "$($Check.id)"; $proves = "$($Check.proves)"
    try {
        switch ("$($Check.kind)") {
            'sql-scalar' {
                $n = Invoke-Sqlcmd-Scalar -Server $Server -Database $Database -Query (Expand-PimSql -Sql "$($Check.sql)" -Build $Build)
                $ok = Test-PimOp -Measured $n -Op "$($Check.op)" -Value ([int]$Check.value)
                return New-PimFeatureCheckRow -Id $id -Result $(if ($ok) { 'PASS' } else { 'FAIL' }) -Measured "$n" -Expected "$($Check.op) $($Check.value)" -Proves $proves
            }
            'sql-offenders' {
                $rows = @(Invoke-Sqlcmd-Rows -Server $Server -Database $Database -Query (Expand-PimSql -Sql "$($Check.sql)" -Build $Build))
                return New-PimFeatureCheckRow -Id $id -Result $(if ($rows.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Measured "$($rows.Count) offender(s)" -Expected '0 offenders' -Proves $proves -Offenders @($rows | Select-Object -First 25)
            }
            'files-count' {
                if ([string]::IsNullOrWhiteSpace($FilesPath)) {
                    return New-PimFeatureCheckRow -Id $id -Result 'FAIL' -Measured 'no filesPath' -Expected "$($Check.op) $($Check.value)" -Proves $proves -Offenders @('the build file names no filesPath, so the folder was not read; an unread disk is never a pass')
                }
                $dir = Join-Path $FilesPath "$($Check.folder)"
                $n = 0
                if (Test-Path -LiteralPath $dir -PathType Container) {
                    $dirs = @($dir)
                    if ($Check.includeSubfolders -eq $true) { $dirs += @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction Stop | ForEach-Object FullName) }
                    foreach ($d in $dirs) { $n += @(Get-ChildItem -LiteralPath $d -Filter "$($Check.filter)" -File -ErrorAction Stop).Count }
                }
                $ok = Test-PimOp -Measured $n -Op "$($Check.op)" -Value ([int]$Check.value)
                return New-PimFeatureCheckRow -Id $id -Result $(if ($ok) { 'PASS' } else { 'FAIL' }) -Measured "$n file(s) in $($Check.folder)" -Expected "$($Check.op) $($Check.value)" -Proves $proves
            }
            'attributes' {
                $r = Test-PimAttributeAspect -Aspect "$($Check.aspect)" -Attribute @($Build.attributes) -Stored $Stored
                $min = if ($null -ne $Check.minScanned) { [int]$Check.minScanned } else { 1 }
                if ($r.scanned -lt $min) {
                    return New-PimFeatureCheckRow -Id $id -Result 'FAIL' -Measured "$($r.scanned) declared attribute(s) in scope" -Expected "at least $min declared, 0 offenders" -Proves $proves -Offenders @("the build file declares $($r.scanned) attribute(s) this check applies to; it needs $min, so nothing was proved")
                }
                return New-PimFeatureCheckRow -Id $id -Result $(if ($r.offenders.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Measured "$($r.scanned) scanned, $($r.offenders.Count) offender(s)" -Expected "at least $min declared, 0 offenders" -Proves $proves -Offenders @($r.offenders | Select-Object -First 25)
            }
            'families' {
                $have = @{}
                foreach ($line in @(Invoke-Sqlcmd-Rows -Server $Server -Database $Database -Query ("SELECT CAST(g.ProductCategoryId AS nvarchar(100)) + N'|' + CAST(COUNT(DISTINCT r.GroupProductRelationProductId) AS nvarchar(12)) FROM EcomGroups g LEFT JOIN EcomGroupProductRelation r ON r.GroupProductRelationGroupId = g.GroupId WHERE g.GroupType = 2 AND ISNULL(g.ProductCategoryId, N'') <> N'' GROUP BY g.ProductCategoryId"))) {
                    $p = "$line".Split('|'); if ($p.Count -eq 2) { $have[$p[0]] = [int]$p[1] }
                }
                $off = @()
                # An absent families input is no declaration, not one family without a name.
                $families = @($Build.families | Where-Object { $null -ne $_ })
                foreach ($f in $families) {
                    if (-not $have.ContainsKey("$($f.category)")) { $off += "family '$($f.name)' has no data model on category '$($f.category)'" }
                    elseif ($have["$($f.category)"] -lt 1) { $off += "family '$($f.name)' has a data model and no product" }
                }
                $min = if ($null -ne $Check.minFamilies) { [int]$Check.minFamilies } else { 1 }
                $n = $families.Count
                if ($n -lt $min) { $off += "the build file declares $n family(ies); this check needs $min" }
                return New-PimFeatureCheckRow -Id $id -Result $(if ($off.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Measured "$n declared, $($off.Count) offender(s)" -Expected "at least $min declared, each with a data model and products" -Proves $proves -Offenders $off
            }
            'widget-queries' {
                                $key = "N'name=' + CHAR(34) + N'Query' + CHAR(34) + N' value=' + CHAR(34)"
                $total = Invoke-Sqlcmd-Scalar -Server $Server -Database $Database -Query "SELECT COUNT(*) FROM DashboardWidget w JOIN Dashboard d ON d.DashboardID = w.DashboardWidgetDashboardID WHERE d.DashboardType = N'Products'"
                $queries = @(Invoke-Sqlcmd-Rows -Server $Server -Database $Database -Query ("SELECT SUBSTRING(x.xml, CHARINDEX($key, x.xml) + LEN($key), 36) FROM (SELECT CAST(w.DashboardWidgetXml AS nvarchar(max)) xml FROM DashboardWidget w JOIN Dashboard d ON d.DashboardID = w.DashboardWidgetDashboardID WHERE d.DashboardType = N'Products') x WHERE CHARINDEX($key, x.xml) > 0"))
                $index = Get-PimQueryFileIndex -FilesPath $FilesPath -Folder @('System\SmartSearches\Ecommerce\Shared', 'System\Repositories\Products', 'System\Repositories\ProductsBackend')
                if (-not $index.readable) {
                    return New-PimFeatureCheckRow -Id $id -Result 'UNVERIFIED' -Measured 'query folders not readable' -Expected 'every widget query resolves' -Proves $proves -Offenders @('no query folder under filesPath was readable; an unread disk is never a pass')
                }
                $off = @(); $withQuery = 0
                foreach ($x in $queries) {
                    $q = Get-PimWidgetQueryId -Value "$x"
                    if (-not $q) { continue }
                    $withQuery++
                    if (-not $index.ids.Contains($q)) { $off += "widget query '$q' matches no .query file" }
                }
                if ($withQuery -eq 0) { $off += "none of the $total widget(s) on a Products dashboard carries a query" }
                return New-PimFeatureCheckRow -Id $id -Result $(if ($off.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Measured "$withQuery widget(s) with a query against $($index.files) query file(s), $($off.Count) offender(s)" -Expected 'every widget query resolves' -Proves $proves -Offenders @($off | Select-Object -First 25)
            }
        }
        throw "unknown check kind '$($Check.kind)'"
    } catch {
        return New-PimFeatureCheckRow -Id $id -Result 'ERROR' -Measured 'check could not run' -Expected '' -Proves $proves -Offenders @('Read failed; inspect the local target without exposing connection details.')
    }
}
