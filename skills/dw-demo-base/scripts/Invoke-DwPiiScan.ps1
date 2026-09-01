<#
.SYNOPSIS
    READ-ONLY. Scans a Dynamicweb database and rendered pages for PII and
    vendor boilerplate; prints CLASSES AND COUNTS ONLY, never a value.

.DESCRIPTION
    The mechanical half of the blocking pre-demo sweep (owning reference:
    dw-demo-base/references/pii-sweep.md — the rendered-page EYEBALL pass
    stays mandatory and is not replaced by this script). Five sections:
      A. Whole-database string-column census, counting legacy ntext/text
         columns separately (they silently drop out of REPLACE-based sweeps).
      B. Person-PII surface on the platform tables (AccessUser,
         AccessUserAddress, EcomOrders — each skipped when absent): distinct
         mailboxes and names, address rows, phone-shaped rows, real IPv4 rows
         (the 203.0.113.0/24 documentation range is exempt), gateway XML
         snapshots, live password-recovery tokens, migrated password hashes.
      C. Term sweep: every -Term counted across EVERY string column of every
         base table (ntext/text CAST for the LIKE), reported per table.
      D. Rendered-page pass (-BaseUrl + -PagePath): visible text of each page
         counted against the terms and the locale-shaped patterns
         (-ShapePattern) — the shapes catch what no term list contains.
      E. Anonymous-download probe (-ProbePath): every path must NOT answer 200.

    SQL is LOCAL-ONLY (hosted installs expose no SQL surface; run sections
    D/E against them by URL). The counts are the gate, not the exit code:
    exit 1 means the scan itself failed, not that PII was found — read the
    report. Never add value output to this script.

.PARAMETER ConnectionString
    SQL connection string; else $env:DW_SQL_CONNECTION. Local installs only.

.PARAMETER Term
    Identity/vendor terms to sweep (customer brand, personal names, vendor
    name). Default: 'dynamicweb'. Counts only — values are never printed.

.PARAMETER ShapePattern
    Locale-shaped regexes for the rendered pass. Default: a foreign dialling
    code shape ('\+45'), OSS licence boilerplate ('covered code|licensor'),
    and the placeholder mailbox ('noreply@noreply').

.PARAMETER BaseUrl
    Host base URL; enables sections D and E.

.PARAMETER PagePath
    Relative paths of rendered pages to sweep (legal, cookie, terms, contact).

.PARAMETER ProbePath
    Relative file paths that must not be anonymously downloadable.

.PARAMETER OutFile
    Write the report as markdown to this path.

.PARAMETER AllowSelfSignedCertificate
    Skip TLS validation for a non-localhost -BaseUrl.

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-DwPiiScan.ps1 -Term dynamicweb,contoso -OutFile pii-scan.md

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-DwPiiScan.ps1 -BaseUrl "https://localhost:<port>" -PagePath /privacy-policy,/contact -ProbePath /Files/Files/Integration/subscribers.xml
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConnectionString,
    [string[]]$Term = @('dynamicweb'),
    [string[]]$ShapePattern = @('\+45', '(?i)covered code|licensor', '(?i)noreply@noreply'),
    [string]$BaseUrl,
    [string[]]$PagePath = @(),
    [string[]]$ProbePath = @(),
    [string]$OutFile,
    [switch]$AllowSelfSignedCertificate
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Api.psm1') -Force -ErrorAction Stop

$report = [System.Collections.Generic.List[string]]::new()
function Out-Line([string]$Line) { Write-Host $Line; $report.Add($Line) }

function ConvertTo-LikeLiteral([string]$Value) {
    # Escape LIKE wildcards so a term is matched literally.
    ($Value -replace '([%_\[])', '[$1]')
}

$sqlWanted = $PSBoundParameters.ContainsKey('ConnectionString') -or $env:DW_SQL_CONNECTION
if ($sqlWanted) {
    Out-Line '## A. String-column census'
    # Dw.Api contract: assign Get-DwSqlRows output, never wrap the CALL in @()
    # (the result is already unroll-protected; @(call) double-wraps it).
    $census = (Get-DwSqlRows -ConnectionString $ConnectionString @'
SELECT COUNT(*) AS StringColumns,
       COUNT(DISTINCT c.TABLE_NAME) AS Tables,
       SUM(CASE WHEN c.DATA_TYPE IN ('ntext','text') THEN 1 ELSE 0 END) AS LegacyNtextOrText
FROM INFORMATION_SCHEMA.COLUMNS c
JOIN INFORMATION_SCHEMA.TABLES t
  ON t.TABLE_NAME = c.TABLE_NAME AND t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_TYPE = 'BASE TABLE'
WHERE c.DATA_TYPE IN ('nvarchar','varchar','nchar','char','ntext','text')
'@)[0]
    Out-Line "string columns: $($census.StringColumns) across $($census.Tables) tables; legacy ntext/text: $($census.LegacyNtextOrText) (these drop out of REPLACE-based sweeps — sweep them explicitly)"

    Out-Line ''
    Out-Line '## B. Person-PII surface (platform tables; counts only)'
    $tables = (Get-DwSqlRows -ConnectionString $ConnectionString "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'") | ForEach-Object { $_.TABLE_NAME }
    $personChecks = @(
        @{ Table = 'AccessUser'; Sql = "SELECT 'AccessUser distinct mailboxes' AS Class, COUNT(DISTINCT AccessUserEmail) AS N FROM AccessUser WHERE AccessUserEmail LIKE '%@%' UNION ALL SELECT 'AccessUser distinct names', COUNT(DISTINCT AccessUserName) FROM AccessUser WHERE LTRIM(RTRIM(AccessUserName)) <> '' UNION ALL SELECT 'AccessUser live password-recovery tokens', COUNT(*) FROM AccessUser WHERE LTRIM(RTRIM(AccessUserPasswordRecoveryToken)) <> '' UNION ALL SELECT 'AccessUser password hashes populated', COUNT(*) FROM AccessUser WHERE LTRIM(RTRIM(AccessUserPassword)) <> ''" },
        @{ Table = 'AccessUserAddress'; Sql = "SELECT 'Address distinct names' AS Class, COUNT(DISTINCT AccessUserAddressName) AS N FROM AccessUserAddress UNION ALL SELECT 'Address distinct mailboxes', COUNT(DISTINCT AccessUserAddressEmail) FROM AccessUserAddress WHERE AccessUserAddressEmail LIKE '%@%' UNION ALL SELECT 'Address rows with a street', COUNT(*) FROM AccessUserAddress WHERE LTRIM(RTRIM(AccessUserAddressAddress)) <> ''" },
        @{ Table = 'EcomOrders'; Sql = "SELECT 'Order distinct customer mailboxes' AS Class, COUNT(DISTINCT OrderCustomerEmail) AS N FROM EcomOrders WHERE OrderCustomerEmail LIKE '%@%' UNION ALL SELECT 'Order distinct delivery mailboxes', COUNT(DISTINCT OrderDeliveryEmail) FROM EcomOrders WHERE OrderDeliveryEmail LIKE '%@%' UNION ALL SELECT 'Order distinct customer names', COUNT(DISTINCT OrderCustomerName) FROM EcomOrders WHERE LTRIM(RTRIM(OrderCustomerName)) <> '' UNION ALL SELECT 'Order rows with a phone shape', COUNT(*) FROM EcomOrders WHERE OrderCustomerPhone LIKE '%[0-9][0-9][0-9]-[0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]%' UNION ALL SELECT 'Order rows with a real IPv4', COUNT(*) FROM EcomOrders WHERE LTRIM(RTRIM(OrderIP)) <> '' AND OrderIP NOT LIKE '203.0.113.%' UNION ALL SELECT 'Order gateway XML snapshots', COUNT(*) FROM EcomOrders WHERE LTRIM(RTRIM(OrderGatewayResult)) <> ''" }
    )
    foreach ($check in $personChecks) {
        if ($tables -notcontains $check.Table) { Out-Line "($($check.Table) absent — skipped)"; continue }
        $rows = Get-DwSqlRows -ConnectionString $ConnectionString $check.Sql
        foreach ($row in $rows) {
            Out-Line ("{0}: {1}" -f $row.Class, $row.N)
        }
    }

    Out-Line ''
    Out-Line '## C. Term sweep (every string column of every base table; rows counted, values never read out)'
    $columns = Get-DwSqlRows -ConnectionString $ConnectionString @'
SELECT c.TABLE_NAME, c.COLUMN_NAME, c.DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS c
JOIN INFORMATION_SCHEMA.TABLES t
  ON t.TABLE_NAME = c.TABLE_NAME AND t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_TYPE = 'BASE TABLE'
WHERE c.DATA_TYPE IN ('nvarchar','varchar','nchar','char','ntext','text')
'@
    $byTable = $columns | Group-Object TABLE_NAME
    foreach ($t in $Term) {
        $like = ConvertTo-LikeLiteral $t
        $total = 0
        $hits = [System.Collections.Generic.List[string]]::new()
        foreach ($group in $byTable) {
            $predicates = @($group.Group | ForEach-Object {
                    $col = "[$($_.COLUMN_NAME)]"
                    if ($_.DATA_TYPE -in 'ntext', 'text') { $col = "CAST($col AS nvarchar(max))" }
                    "$col LIKE '%$like%'"
                })
            $n = [int](Get-DwSqlScalar -ConnectionString $ConnectionString "SELECT COUNT(*) FROM [$($group.Name)] WHERE $($predicates -join ' OR ')")
            if ($n -gt 0) { $hits.Add("$($group.Name)=$n"); $total += $n }
        }
        Out-Line ("term '{0}': {1} row(s) in {2} table(s){3}" -f $t, $total, $hits.Count,
            $(if ($hits.Count) { ' — ' + ($hits -join ', ') } else { '' }))
    }
}
else {
    Out-Line '(no -ConnectionString / $env:DW_SQL_CONNECTION — SQL sections A-C skipped; SQL is local-only)'
}

if ($BaseUrl) {
    $BaseUrl = $BaseUrl.TrimEnd('/')
    $skipCert = [bool](($BaseUrl -match '^https?://(localhost|127\.0\.0\.1)([:/]|$)') -or $AllowSelfSignedCertificate)

    if ($PagePath.Count -gt 0) {
        Out-Line ''
        Out-Line '## D. Rendered-page pass (visible text; counts only — the eyeball pass is still mandatory)'
        foreach ($path in $PagePath) {
            try {
                $html = (Invoke-WebRequest -Uri "$BaseUrl$path" -SkipCertificateCheck:$skipCert -SkipHttpErrorCheck -TimeoutSec 30).Content
                $text = [regex]::Replace([string]$html, '(?s)<script.*?</script>|<style.*?</style>|<[^>]*>', ' ')
                $parts = [System.Collections.Generic.List[string]]::new()
                foreach ($t in $Term) { $parts.Add(("'{0}'={1}" -f $t, [regex]::Matches($text, [regex]::Escape($t), 'IgnoreCase').Count)) }
                foreach ($p in $ShapePattern) { $parts.Add(("/{0}/={1}" -f $p, [regex]::Matches($text, $p).Count)) }
                Out-Line ("{0}: {1}" -f $path, ($parts -join ' '))
            }
            catch { Out-Line "${path}: FETCH FAILED ($($_.Exception.Message))" }
        }
    }

    if ($ProbePath.Count -gt 0) {
        Out-Line ''
        Out-Line '## E. Anonymous-download probe (200 = STILL SERVED, must be fixed)'
        foreach ($path in $ProbePath) {
            try { $code = (Invoke-WebRequest -Uri "$BaseUrl$path" -Method Head -SkipCertificateCheck:$skipCert -SkipHttpErrorCheck -TimeoutSec 30).StatusCode }
            catch { $code = 'ERR' }
            if ($code -eq 200) { Out-Line "STILL SERVED (200): $path" } else { Out-Line ("{0}: {1}" -f $code, $path) }
        }
    }
}
elseif ($PagePath.Count -gt 0 -or $ProbePath.Count -gt 0) {
    Out-Line '(-PagePath/-ProbePath given without -BaseUrl — sections D/E skipped)'
}

if ($OutFile) {
    $header = @("# PII / vendor-boilerplate scan — $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        '', 'Classes and counts only; values are never recorded (pii-sweep.md rule 7).', '')
    Set-Content -LiteralPath $OutFile -Value (($header + $report) -join "`n") -Encoding UTF8
    Write-Host ''
    Write-Host "Report written: $OutFile"
}
exit 0
