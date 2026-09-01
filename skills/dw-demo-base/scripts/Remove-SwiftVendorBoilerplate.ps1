<#
.SYNOPSIS
    WRITES: replaces the platform vendor's stock boilerplate in Swift content
    items and module settings (dry run by default; -Apply to write; rows are
    backed up to a _dw_debrand_backup_<timestamp> table first).

.DESCRIPTION
    Stock Swift ships the VENDOR's own PII and legal copy (owning reference:
    dw-demo-base/references/pii-sweep.md Rule 2) — vendor-framed privacy copy,
    OSS licence boilerplate presented as terms of use, a foreign placeholder
    phone number, a noreply@noreply.com mailbox, and the vendor's sender
    identity in module settings. This script rewrites exactly those STOCK
    literals, matched by content (never by item id, which varies per install):

      - vendor-framed privacy phrases -> the customer's name / neutral wording
      - the stock foreign placeholder phone block -> removed, or the
        customer's phone when -CompanyPhone is given
      - noreply@noreply.com -> -CompanyEmail
      - OSS licence boilerplate ("Covered Code") -> a short holding notice
        (never synthesise legally-operative terms for a customer)
      - <SenderName>DynamicWeb</SenderName> in module settings -> -CompanyName

    The de-branding nuance is enforced by construction: only the specific
    stock phrases are replaced — never a blanket vendor-name substitution —
    so technically load-bearing references (the platform's own cookie names
    in the cookie notice) are untouched. After applying, the script re-scans
    and lists what REMAINS for the manual pass (e.g. sub-processor sentences
    that need rewriting by hand, vendor sender EMAIL addresses).

    SQL is LOCAL-ONLY (demo installs; a hosted install has no SQL surface).
    Sanitization note: the vendor literals inside this file are DETECTION
    TARGETS, not leakage — do not strip them.

    After -Apply: flush the caches (Clear-DwServiceCache -All from
    dw-data-access/scripts/Dw.Api.psm1) and re-read the rendered pages — item
    edits are cache-only, no restart needed. Then re-run Invoke-DwPiiScan.ps1.

.PARAMETER CompanyName
    The customer/company name used in rewritten copy.

.PARAMETER CompanyEmail
    Replaces the noreply@noreply.com placeholder mailbox.

.PARAMETER CompanyPhone
    Optional; when given, the stock placeholder phone block is replaced with
    this number instead of removed.

.PARAMETER ConnectionString
    SQL connection string; else $env:DW_SQL_CONNECTION. Local installs only.

.PARAMETER Apply
    Write the changes. Without it the script only reports what would change.

.EXAMPLE
    pwsh -NoProfile -File scripts/Remove-SwiftVendorBoilerplate.ps1 -CompanyName "Acme Tools" -CompanyEmail "service@acme.example"

.EXAMPLE
    pwsh -NoProfile -File scripts/Remove-SwiftVendorBoilerplate.ps1 -CompanyName "Acme Tools" -CompanyEmail "service@acme.example" -CompanyPhone "+1 555 0100" -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$CompanyName,
    [Parameter(Mandatory = $true)][string]$CompanyEmail,
    [string]$CompanyPhone,
    [string]$ConnectionString,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Api.psm1') -Force -ErrorAction Stop

function Convert-ToSqlLiteral([string]$Value) { "N'" + ($Value -replace "'", "''") + "'" }

$phoneReplacement = if ($CompanyPhone) {
    '<p class="dw-h5"><strong>' + $CompanyPhone + '</strong></p>'
} else { '' }
$holdingNotice = '<p>Our terms and conditions of sale are being finalised. For questions about an ' +
    'order, please contact ' + $CompanyName + ' customer service.</p>'

# The stock literals (detection targets — keep verbatim) and their replacements.
$phraseEdits = @(
    @{ Find = 'Dynamicweb Swift';                    ReplaceWith = "the $CompanyName website" },
    @{ Find = 'Dynamicweb is compliant';             ReplaceWith = "$CompanyName is compliant" },
    @{ Find = 'our Dynamicweb backend database';     ReplaceWith = 'our website platform' },
    @{ Find = 'our Dynamicweb backend';              ReplaceWith = 'our website platform' },
    @{ Find = 'Dynamicweb&#39;s latest product announcements, software updates'; ReplaceWith = 'our latest product announcements' },
    @{ Find = '<p class="dw-h5"><strong>+451234567</strong></p>'; ReplaceWith = $phoneReplacement },
    @{ Find = 'noreply@noreply.com';                 ReplaceWith = $CompanyEmail }
)

$tables = (Get-DwSqlRows -ConnectionString $ConnectionString "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'") | ForEach-Object { $_.TABLE_NAME }
$itemTables = @('ItemType_Swift-v2_Text', 'ItemType_Swift-v2_Feature') | Where-Object { $tables -contains $_ }
if ($itemTables.Count -eq 0) {
    throw 'No Swift-v2 text/feature item tables found — is this a Swift 2 database?'
}

$planned = [System.Collections.Generic.List[object]]::new()
foreach ($table in $itemTables) {
    foreach ($edit in $phraseEdits) {
        $like = $edit.Find -replace '([%_\[])', '[$1]'
        $n = [int](Get-DwSqlScalar -ConnectionString $ConnectionString "SELECT COUNT(*) FROM [$table] WHERE CAST(Text AS nvarchar(max)) LIKE '%$($like -replace "'", "''")%'")
        if ($n -gt 0) { $planned.Add([pscustomobject]@{ Table = $table; Kind = 'phrase'; Find = $edit.Find; ReplaceWith = $edit.ReplaceWith; Rows = $n }) }
    }
    # OSS licence boilerplate: replace the WHOLE text with the holding notice.
    $n = [int](Get-DwSqlScalar -ConnectionString $ConnectionString "SELECT COUNT(*) FROM [$table] WHERE CAST(Text AS nvarchar(max)) LIKE '%Covered Code%'")
    if ($n -gt 0) { $planned.Add([pscustomobject]@{ Table = $table; Kind = 'terms-boilerplate'; Find = 'Covered Code'; ReplaceWith = '(holding notice)'; Rows = $n }) }
}
if ($tables -contains 'Paragraph') {
    $n = [int](Get-DwSqlScalar -ConnectionString $ConnectionString "SELECT COUNT(*) FROM Paragraph WHERE CAST(ParagraphModuleSettings AS nvarchar(max)) LIKE '%<SenderName>DynamicWeb</SenderName>%'")
    if ($n -gt 0) { $planned.Add([pscustomobject]@{ Table = 'Paragraph'; Kind = 'sender-name'; Find = '<SenderName>DynamicWeb</SenderName>'; ReplaceWith = "<SenderName>$CompanyName</SenderName>"; Rows = $n }) }
}

if ($planned.Count -eq 0) {
    Write-Host 'Nothing to change — no stock vendor boilerplate found.'
}
else {
    Write-Host 'Planned changes:'
    $planned | Format-Table Table, Kind, Rows, Find -AutoSize | Out-String | Write-Host
}

if (-not $Apply) {
    Write-Host 'DRY RUN (default) — nothing written. Re-run with -Apply to write.'
    exit 0
}

if ($planned.Count -gt 0 -and $PSCmdlet.ShouldProcess("$($planned.Count) change group(s) across $(@($planned.Table | Sort-Object -Unique).Count) table(s)", 'debrand stock vendor boilerplate')) {
    $ts = Get-Date -Format 'yyyyMMddHHmmss'
    $backupTable = "_dw_debrand_backup_$ts"
    $batch = [System.Collections.Generic.List[string]]::new()
    $batch.Add('SET XACT_ABORT ON;')
    $batch.Add("CREATE TABLE [$backupTable] (SourceTable nvarchar(256), SourceId nvarchar(64), OldText nvarchar(max), CapturedUtc datetime2 DEFAULT SYSUTCDATETIME());")
    foreach ($table in $itemTables) {
        $conditions = [System.Collections.Generic.List[string]]::new()
        foreach ($edit in $phraseEdits) {
            $like = ($edit.Find -replace '([%_\[])', '[$1]') -replace "'", "''"
            $conditions.Add("CAST(Text AS nvarchar(max)) LIKE '%$like%'")
        }
        $conditions.Add("CAST(Text AS nvarchar(max)) LIKE '%Covered Code%'")
        $batch.Add("INSERT INTO [$backupTable] (SourceTable, SourceId, OldText) SELECT '$table', CAST(Id AS nvarchar(64)), CAST(Text AS nvarchar(max)) FROM [$table] WHERE $($conditions -join ' OR ');")
        foreach ($edit in $phraseEdits) {
            $findLit = Convert-ToSqlLiteral $edit.Find
            $withLit = Convert-ToSqlLiteral $edit.ReplaceWith
            $like = ($edit.Find -replace '([%_\[])', '[$1]') -replace "'", "''"
            $batch.Add("UPDATE [$table] SET Text = REPLACE(CAST(Text AS nvarchar(max)), $findLit, $withLit) WHERE CAST(Text AS nvarchar(max)) LIKE '%$like%';")
        }
        $batch.Add("UPDATE [$table] SET Text = $(Convert-ToSqlLiteral $holdingNotice) WHERE CAST(Text AS nvarchar(max)) LIKE '%Covered Code%';")
    }
    if ($tables -contains 'Paragraph') {
        $batch.Add("INSERT INTO [$backupTable] (SourceTable, SourceId, OldText) SELECT 'Paragraph', CAST(ParagraphId AS nvarchar(64)), CAST(ParagraphModuleSettings AS nvarchar(max)) FROM Paragraph WHERE CAST(ParagraphModuleSettings AS nvarchar(max)) LIKE '%<SenderName>DynamicWeb</SenderName>%';")
        $batch.Add("UPDATE Paragraph SET ParagraphModuleSettings = REPLACE(CAST(ParagraphModuleSettings AS nvarchar(max)), '<SenderName>DynamicWeb</SenderName>', $(Convert-ToSqlLiteral "<SenderName>$CompanyName</SenderName>")) WHERE CAST(ParagraphModuleSettings AS nvarchar(max)) LIKE '%<SenderName>DynamicWeb</SenderName>%';")
    }

    # One connection, one batch, transactional via SqlClient.
    $conn = [System.Data.SqlClient.SqlConnection]::new((& {
        if ($ConnectionString) { $ConnectionString }
        elseif ($env:DW_SQL_CONNECTION) { $env:DW_SQL_CONNECTION }
        else { throw 'No SQL connection. Pass -ConnectionString or set $env:DW_SQL_CONNECTION (local installs only).' }
    }))
    try {
        $conn.Open()
        $tx = $conn.BeginTransaction()
        try {
            foreach ($stmt in $batch) {
                $cmd = $conn.CreateCommand()
                $cmd.Transaction = $tx
                $cmd.CommandText = $stmt
                $cmd.CommandTimeout = 300
                $cmd.ExecuteNonQuery() | Out-Null
            }
            $tx.Commit()
        }
        catch { $tx.Rollback(); throw }
    }
    finally { $conn.Dispose() }
    Write-Host "Applied. Originals backed up to [$backupTable] (drop it before handover)."
}

# ---- Re-scan: what remains needs the manual pass -----------------------------
Write-Host ''
Write-Host 'Remaining vendor-string rows (manual pass — e.g. sub-processor sentences, cookie-name exemptions):'
$remaining = 0
foreach ($table in $itemTables) {
    $n = [int](Get-DwSqlScalar -ConnectionString $ConnectionString "SELECT COUNT(*) FROM [$table] WHERE CAST(Text AS nvarchar(max)) LIKE '%Dynamicweb%'")
    Write-Host "  ${table}: $n row(s) still containing the vendor name"
    $remaining += $n
}
if ($tables -contains 'Paragraph') {
    $n = [int](Get-DwSqlScalar -ConnectionString $ConnectionString "SELECT COUNT(*) FROM Paragraph WHERE CAST(ParagraphModuleSettings AS nvarchar(max)) LIKE '%SenderEmail%dynamicweb%'")
    Write-Host "  Paragraph module settings: $n row(s) with a vendor SenderEmail (rewrite by hand)"
    $remaining += $n
}
Write-Host ''
Write-Host 'Now: flush caches (Clear-DwServiceCache -All), re-read the rendered legal/contact pages'
Write-Host '(the eyeball pass), and re-run Invoke-DwPiiScan.ps1 — a pass that finds nothing new is the'
Write-Host 'first pass you may believe.'
exit 0
