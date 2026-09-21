<#
.SYNOPSIS
    WRITES: runs local SQL statement(s) and then flushes the owning service
    caches, in that order. Dry run by default; -Apply writes.

.DESCRIPTION
    A SQL write to a cached entity is not merely read stale: THE NEXT API SAVE
    OF THAT ENTITY WRITES THE CACHED COPY BACK OVER THE ROW AND ERASES IT,
    with no error and no log line on either side. A SELECT immediately after
    the UPDATE says the write succeeded; a SELECT after the next unrelated
    save says it never happened. That is worse than a stale read, because a
    stale read at least leaves the database telling the truth, and the erasure
    happens at an unpredictable later moment inside code that has nothing to
    do with the change.

    The ordering is always: UPDATE -> flush the owning service -> then run
    anything that touches the entity. This script is that order, made
    unskippable: it refuses to run without at least one -CacheTypeName (or an
    explicit -NoFlush, which has to be justified out loud).

    Three rules it carries that a retyped command line loses:
      - The parameter is CacheTypeName, and CacheName is NOT an alias. The
        wrong key returns 400 {"CacheTypeName":["The value is required."]},
        which inside a try/catch-and-continue script reads as a soft warning
        while the cache is silently never flushed.
      - The type name is the FULLY QUALIFIED storage type and must be one the
        platform actually registers; there is no naming rule to infer it from.
        Enumerate with GetServiceCaches (-ListCaches) rather than guessing.
      - Nothing may re-save the entity between the flush and the read that
        must see the value. Any verb that re-saves an entity — the recalculate
        family included — writes DW's cached model back over what SQL wrote.

    Local installs only: a hosted install has no SQL surface. Statements run
    through Dw.Sql.Local.psm1, which refuses a non-local server.

    Owning reference: dw-data-access/references/cache-invalidation.md
    ("Mixing MCP and SQL on the same rows — UPDATE, flush, then touch"), which
    carries the per-mutation table naming the cache each mutation touches.

.PARAMETER Query
    One or more statements to run, in order.

.PARAMETER File
    A .sql file to run instead of -Query. Read as UTF-8; a batch is NOT split
    on GO, so a statement needing its own batch goes in its own -Query element
    or its own file.

.PARAMETER CacheTypeName
    The fully qualified service cache type name(s) to flush after the SQL, in
    the order given. Required unless -NoFlush.

.PARAMETER NoFlush
    Skip the flush. Valid only when the mutation is documented as
    self-invalidating; state which row of cache-invalidation.md says so.

.PARAMETER ListCaches
    Print the registered service caches (GET /Admin/Api/GetServiceCaches) and
    exit. Nothing is written.

.PARAMETER Apply
    Run. Without it the statements and the flush order are printed and
    nothing runs.

.PARAMETER BaseUrl / ApiToken / SolutionPath
    Connection for the flush; else the DW_* env vars, else launchSettings.json.

.PARAMETER ConnectionString
    Local SQL connection; else $env:DW_SQL_CONNECTION.

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-DwSqlThenFlush.ps1 -ListCaches

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-DwSqlThenFlush.ps1 -Query "UPDATE EcomOrders SET OrderComplete = 1 WHERE OrderId = 'ORDER1'" -CacheTypeName 'Dynamicweb.Ecommerce.Orders.OrderService' -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$Query,
    [string]$File,
    [string[]]$CacheTypeName,
    [switch]$NoFlush,
    [switch]$ListCaches,
    [switch]$Apply,
    [string]$BaseUrl,
    [string]$ApiToken,
    [string]$SolutionPath,
    [string]$ConnectionString
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.Api.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Dw.Sql.Local.psm1') -Force -ErrorAction Stop
Connect-Dw -BaseUrl $BaseUrl -ApiToken $ApiToken -SolutionPath $SolutionPath | Out-Null
Assert-DwConnection | Out-Null

if ($ListCaches) {
    $caches = Invoke-DwApi 'GetServiceCaches'
    foreach ($row in @($caches.data ?? $caches.model ?? $caches)) {
        Write-Host ($row.cacheTypeName ?? $row.name ?? $row.id ?? ($row | ConvertTo-Json -Compress -Depth 3))
    }
    exit 0
}

$statements = [System.Collections.Generic.List[string]]::new()
if ($File) {
    if ($Query) { Write-Error 'Pass -Query or -File, not both.' -ErrorAction Continue; exit 1 }
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { Write-Error "No such file: $File" -ErrorAction Continue; exit 1 }
    $statements.Add([System.IO.File]::ReadAllText($File, [System.Text.Encoding]::UTF8))
}
elseif ($Query) { foreach ($q in $Query) { $statements.Add($q) } }
else {
    Write-Error 'Nothing to run. Pass -Query or -File (or -ListCaches).' -ErrorAction Continue
    exit 1
}
if ($statements | Where-Object { -not $_.Trim() }) {
    Write-Error 'An empty statement was passed.' -ErrorAction Continue
    exit 1
}

if (-not $NoFlush -and -not $CacheTypeName) {
    Write-Error ('No -CacheTypeName. Every SQL write to a cached entity owes a flush, and without one the ' +
        'next API save of that entity writes the cached copy back over the row and erases it silently. ' +
        'Find the owning service in cache-invalidation.md, enumerate names with -ListCaches, or pass ' +
        '-NoFlush and state which row documents the mutation as self-invalidating.') -ErrorAction Continue
    exit 1
}

Write-Host 'Plan (this order is the recipe, not a convenience):'
$i = 0
foreach ($s in $statements) {
    $i++
    $preview = ($s.Trim() -split "`r?`n" | Select-Object -First 3) -join ' '
    if ($preview.Length -gt 160) { $preview = $preview.Substring(0, 160) + ' ...' }
    Write-Host ("  {0}. SQL  {1}" -f $i, $preview)
}
if ($NoFlush) {
    Write-Host '  -. FLUSH SKIPPED (-NoFlush) — only valid for a documented self-invalidating mutation.'
}
else {
    foreach ($name in $CacheTypeName) {
        $i++
        Write-Host ("  {0}. FLUSH CacheInformationRefresh CacheTypeName={1}" -f $i, $name)
    }
}
Write-Host '  then: run nothing that re-saves the entity before the read that must see the value.'

if (-not $Apply) {
    Write-Host ''
    Write-Host 'DRY RUN — nothing run. Re-run with -Apply.'
    exit 0
}
if (-not $PSCmdlet.ShouldProcess('the local Dynamicweb database', "run $($statements.Count) statement(s), then flush $($CacheTypeName.Count) cache(s)")) {
    exit 0
}

Write-Host ''
$n = 0
foreach ($s in $statements) {
    $n++
    $affected = Invoke-DwSqlNonQuery -Sql $s -ConnectionString $ConnectionString
    Write-Host ("Statement {0}: {1} row(s) affected." -f $n, $affected)
}

if ($NoFlush) {
    Write-Host 'Flush skipped by -NoFlush.'
    exit 0
}
foreach ($name in $CacheTypeName) {
    # Clear-DwServiceCache posts CacheInformationRefresh with the CacheTypeName
    # key; a wrong or unregistered name throws here rather than passing quietly.
    try { Clear-DwServiceCache -CacheTypeName $name }
    catch {
        Write-Host "FAILED to flush '$name': $($_.Exception.Message)"
        Write-Host 'The SQL is committed and the cache is NOT flushed — the next API save of the entity will'
        Write-Host 'erase the write. Flush it before anything touches the entity. List valid names with -ListCaches;'
        Write-Host 'the name must be the fully qualified storage type the platform registers, and there is no'
        Write-Host 'naming rule to infer it from.'
        exit 1
    }
    Write-Host "Flushed $name."
}
Write-Host ''
Write-Host 'Done. Nothing may re-save these entities before the read that must see the value — the'
Write-Host 'recalculate family included.'
exit 0
