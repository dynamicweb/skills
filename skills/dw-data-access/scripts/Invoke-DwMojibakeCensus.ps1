<#
.SYNOPSIS
    READ-ONLY. Censuses double-encoded UTF-8 (mojibake) damage across a
    Dynamicweb database, per table.column, with masked context samples.

.DESCRIPTION
    Counts, for every string column of every base table (or the -Table
    subset), rows containing the classic UTF-8-read-as-Windows-1252 marker
    sequences plus U+FFFD (data already lost), alongside the HEALTHY typographic
    characters for contrast (a column with healthy curly quotes AND broken
    markers is partially damaged; one with only markers was damaged wholesale).
    For columns carrying U+FFFD it then samples the damaged rows and reports
    the top before/after context spans with every non-ASCII character escaped
    to <U+XXXX> — forensics, never readable content.

    Every marker string is BUILT FROM CODE POINTS in this file, so the
    script's own encoding can never corrupt the needles (and the repo's
    mojibake validator does not trip on its own detector).

    U+FFFD is unrecoverable (the data is gone — restore from the source);
    the marker sequences are mechanically repairable. Repair is a separate,
    deliberate step — this script only measures.

    SQL is LOCAL-ONLY (a hosted install has no SQL surface). Owning
    reference: dw-data-access/references/management-api-and-sql.md; the
    detection markers match scripts/validate-skills.py's file-side list.

.PARAMETER ConnectionString
    SQL connection string; else $env:DW_SQL_CONNECTION. Local installs only.

.PARAMETER Table
    Restrict the census to these tables (default: every base table).

.PARAMETER Top
    Context spans reported per damaged column (default 5).

.PARAMETER SampleRows
    Damaged rows fetched per column for context analysis (default 200).

.PARAMETER OutFile
    Write the full census as JSON to this path.

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-DwMojibakeCensus.ps1 -Table EcomProducts

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-DwMojibakeCensus.ps1 -OutFile mojibake-census.json
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConnectionString,
    [string[]]$Table,
    [int]$Top = 5,
    [int]$SampleRows = 200,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.Api.psm1') -Force -ErrorAction Stop

# --- markers, built from code points only -------------------------------------
$FFFD = [string][char]0xFFFD
$needles = [ordered]@{
    'FFFD (replacement char — data lost)' = $FFFD
    'a-circ + euro (broken punctuation)'  = [string]([char]0xE2 + [char]0x20AC)
    'A-tilde + copyright (broken e-acute)' = [string]([char]0xC3 + [char]0xA9)
    'A-tilde + cent (double encoding)'    = [string]([char]0xC3 + [char]0xA2)
    'stray A-circumflex (broken nbsp/degree)' = [string][char]0xC2
    'BOM read as 1252'                    = [string]([char]0xEF + [char]0xBB + [char]0xBF)
    'healthy right single quote'          = [string][char]0x2019
    'healthy em dash'                     = [string][char]0x2014
    'healthy ellipsis'                    = [string][char]0x2026
}
$brokenKeys = @($needles.Keys | Where-Object { $_ -notlike 'healthy*' })

function Show-Span([string]$s) {
    (($s.ToCharArray() | ForEach-Object {
            $c = [int]$_
            if ($c -eq 10) { '\n' } elseif ($c -eq 13) { '\r' } elseif ($c -eq 9) { '\t' }
            elseif ($c -lt 32 -or $c -gt 126) { '<U+{0:X4}>' -f $c }
            else { [string]$_ }
        }) -join '')
}

function Convert-ToSqlNeedle([string]$Needle) { "N'" + ($Needle -replace "'", "''") + "'" }

$columns = Get-DwSqlRows -ConnectionString $ConnectionString @'
SELECT c.TABLE_NAME, c.COLUMN_NAME, c.DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS c
JOIN INFORMATION_SCHEMA.TABLES t
  ON t.TABLE_NAME = c.TABLE_NAME AND t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_TYPE = 'BASE TABLE'
WHERE c.DATA_TYPE IN ('nvarchar','varchar','nchar','char','ntext','text')
ORDER BY c.TABLE_NAME, c.COLUMN_NAME
'@
if ($Table) { $columns = @($columns | Where-Object { $Table -contains $_.TABLE_NAME }) }
if (-not $columns) { throw 'No string columns matched — check -Table against the database.' }

$damaged = [System.Collections.Generic.List[object]]::new()
foreach ($group in ($columns | Group-Object TABLE_NAME)) {
    # One scan per table: a row-count CASE term per column x needle.
    $terms = [System.Collections.Generic.List[string]]::new()
    $index = @{}
    $i = 0
    foreach ($col in $group.Group) {
        $expr = "[$($col.COLUMN_NAME)]"
        if ($col.DATA_TYPE -in 'ntext', 'text') { $expr = "CAST($expr AS nvarchar(max))" }
        # BIN2: exact codepoint comparison. The default CI collation case-folds
        # the stray-Â marker onto healthy â, and gives U+FFFD an undefined
        # weight so CHARINDEX never finds it at all (measured).
        $expr = "$expr COLLATE Latin1_General_BIN2"
        $k = 0
        foreach ($needleKey in $needles.Keys) {
            $alias = "n${i}_${k}"
            $terms.Add("SUM(CASE WHEN CHARINDEX($(Convert-ToSqlNeedle $needles[$needleKey]), $expr) > 0 THEN 1 ELSE 0 END) AS $alias")
            $index[$alias] = @{ Column = $col.COLUMN_NAME; Needle = $needleKey }
            $k++
        }
        $i++
    }
    $row = (Get-DwSqlRows -ConnectionString $ConnectionString "SELECT $($terms -join ', ') FROM [$($group.Name)]")[0]
    foreach ($alias in $index.Keys) {
        $n = [int]($row.$alias ?? 0)
        if ($n -gt 0) {
            $damaged.Add([pscustomobject]@{
                    Table = $group.Name; Column = $index[$alias].Column
                    Needle = $index[$alias].Needle; Rows = $n
                })
        }
    }
}

$broken = @($damaged | Where-Object { $brokenKeys -contains $_.Needle })
$healthy = @($damaged | Where-Object { $brokenKeys -notcontains $_.Needle })

Write-Host "## Mojibake census — $(@($columns).Count) string columns scanned"
if ($broken.Count -eq 0) {
    Write-Host 'No mojibake markers found.'
}
else {
    $broken | Sort-Object Table, Column, Needle |
        Format-Table Table, Column, Needle, Rows -AutoSize | Out-String | Write-Host
}
Write-Host "(healthy typographic characters present in $(@($healthy | Select-Object Table, Column -Unique).Count) column(s) — contrast for partial-vs-wholesale damage)"

# --- FFFD context sampling (masked spans only) --------------------------------
$contextReport = [System.Collections.Generic.List[object]]::new()
$fffdColumns = @($broken | Where-Object { $_.Needle -like 'FFFD*' })
foreach ($hit in $fffdColumns) {
    $expr = "CAST([$($hit.Column)] AS nvarchar(max))"
    $rows = Get-DwSqlRows -ConnectionString $ConnectionString `
        "SELECT TOP ($SampleRows) $expr AS T FROM [$($hit.Table)] WHERE CHARINDEX($(Convert-ToSqlNeedle $FFFD), $expr COLLATE Latin1_General_BIN2) > 0"
    $ctx = @{}
    foreach ($r in $rows) {
        $t = [string]$r.T
        $pos = 0
        while (($pos = $t.IndexOf($FFFD, $pos)) -ge 0) {
            $before = $t.Substring([Math]::Max(0, $pos - 3), [Math]::Min(3, $pos))
            $afterLen = [Math]::Min(3, $t.Length - $pos - 1)
            $after = if ($afterLen -gt 0) { $t.Substring($pos + 1, $afterLen) } else { '' }
            $key = (Show-Span $before) + ' [FFFD] ' + (Show-Span $after)
            $ctx[$key] = ($ctx[$key] ?? 0) + 1
            $pos++
        }
    }
    $topCtx = $ctx.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top
    Write-Host ''
    Write-Host "FFFD contexts in $($hit.Table).$($hit.Column) (top $Top of $($ctx.Count), from up to $SampleRows damaged rows; spans are escaped, never readable content):"
    foreach ($entry in $topCtx) {
        Write-Host ("  {0,6}x  {1}" -f $entry.Value, $entry.Key)
        $contextReport.Add([pscustomobject]@{ Table = $hit.Table; Column = $hit.Column; Context = $entry.Key; Occurrences = $entry.Value })
    }
}

if ($broken.Count -gt 0) {
    Write-Host ''
    Write-Host 'FFFD damage is unrecoverable in place — restore those values from the source system.'
    Write-Host 'Marker-sequence damage is mechanically repairable; repair is a separate deliberate step with its own backup.'
}

if ($OutFile) {
    [ordered]@{
        generatedAt    = (Get-Date).ToString('o')
        columnsScanned = @($columns).Count
        findings       = @($broken)
        healthyContrast = @($healthy)
        fffdContexts   = @($contextReport)
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutFile -Encoding UTF8
    Write-Host "Census written: $OutFile"
}
exit 0
