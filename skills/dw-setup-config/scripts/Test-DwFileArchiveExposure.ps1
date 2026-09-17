<#
.SYNOPSIS
    READ-ONLY. Enumerates what under /Files a Dynamicweb 10 install serves to
    an anonymous request, and fails on anything served that was not declared.

.DESCRIPTION
    The file archive is public by EXTENSION, not by permission. The static-file
    middleware serves `wwwroot/Files/Files/**` and blocks `.config`, `.cshtml`,
    `.query` and `.index` by extension; `.xml` and `.json` are NOT on that
    blocklist. A `/Files` request is answered by the static handler without
    ever reaching the page pipeline, so page and role permissions never enter
    it — a gated page whose assets live under `/Files` gates the browser and
    not a single byte.

    This script sends one anonymous, cookie-free, bearer-free HEAD (GET on a
    405) per path and prints the status. No credential of any kind is sent:
    the whole point is what an anonymous internet client sees.

    Classification:
      SERVED     — 200 on a path that was not declared with -ExpectServed.
                   This is the finding; exit code 1.
      EXPECTED   — 200 on a path passed to -ExpectServed. The go-live rule is
                   that an exposure which cannot be closed is asserted
                   deliberately as a known caveat, so nobody discovers it in
                   front of a customer.
      BLOCKED    — any non-200 (404 is what a blocked extension returns).

    The default path set is the one measured on a stock 10.28.x install: the
    job folder (a SqlProvider activity embeds its connection string, so a 200
    there publishes a database username and password), the item XML, the
    serializer config, the blocked-extension control, and the legacy
    Data Integration job runner, which executes ANY job on an anonymous GET.

    Two rules this script cannot check, kept in the owning reference:
      - Job files are UTF-16LE with a BOM, so a naive byte grep for a
        credential is a FALSE CLEAN. Decode before asserting.
      - The archive path doubles `Files\Files`: a stored archive path keeps
        its own leading `/Files` segment, so a single-`Files` URL 404s and a
        reachable folder gets written off as unreachable.

    Owning reference: dw-setup-config/references/host-exposure-and-paths.md
    ("The file archive is public by extension, not by permission"), whose
    go-live checklist item 8 this script performs.

.PARAMETER BaseUrl
    Host base URL (scheme and authority only). Falls back to $env:DW_BASE_URL.
    No default host or port exists; with neither the script fails with the
    one-liner that fixes it.

.PARAMETER Path
    Extra archive paths to probe, in addition to the default set. Each is
    appended to -BaseUrl verbatim, so it carries its own leading slash and,
    for the archive, its doubled `/Files/Files` prefix.

.PARAMETER ExpectServed
    Paths whose 200 is a known, accepted caveat. They report EXPECTED instead
    of SERVED and do not fail the run. A path listed here that is NOT served
    reports CLOSED and does not fail either — the caveat simply lapsed.

.PARAMETER SkipDefaultPaths
    Probe only -Path, dropping the measured default set.

.PARAMETER BrowserUserAgent
    Send a browser-shaped User-Agent. Off by default. The stock-install
    measurement behind the default path set was taken with a browser agent,
    so this exists to reproduce it exactly; content negotiation on some
    handlers varies by agent.

.PARAMETER AllowSelfSignedCertificate
    Accept an untrusted certificate. Certificates are skipped automatically
    for a loopback base URL; anything else needs this explicit opt-in.

.PARAMETER TimeoutSec
    Per-request timeout.

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwFileArchiveExposure.ps1 -BaseUrl "https://localhost:<port>"

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwFileArchiveExposure.ps1 -BaseUrl "https://<host>" -Path /Files/Files/Integration/jobs/nightly-orders.xml -ExpectServed /Files/System/Items/Article.xml
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$BaseUrl,
    [string[]]$Path = @(),
    [string[]]$ExpectServed = @(),
    [switch]$SkipDefaultPaths,
    [switch]$BrowserUserAgent,
    [switch]$AllowSelfSignedCertificate,
    [int]$TimeoutSec = 30
)

$ErrorActionPreference = 'Stop'

# The set measured anonymously on a stock 10.28.x install. Each is a separate
# finding, and the blocked-extension control proves the probe itself works.
$defaultPaths = @(
    '/Files/Files/Integration/jobs/',
    '/Files/System/Items/',
    '/Files/System/Serializer/Serializer.config.json',
    '/Files/GlobalSettings.Database.config',
    '/admin/public/webservices/integrationv2/JobRunner.aspx'
)

if (-not $BaseUrl) { $BaseUrl = $env:DW_BASE_URL }
if (-not $BaseUrl) {
    Write-Error 'No base URL. Pass -BaseUrl or set $env:DW_BASE_URL (scheme and authority, e.g. https://<host>).' -ErrorAction Continue
    exit 1
}
$BaseUrl = $BaseUrl.TrimEnd('/')

# Gated TLS bypass: loopback, or an explicit opt-in. Never unconditional.
$skipCert = [bool](($BaseUrl -match '^https?://(localhost|127\.0\.0\.1|\[::1\])([:/]|$)') -or $AllowSelfSignedCertificate)

$headers = @{}
if ($BrowserUserAgent) {
    # why: the stock-install exposure measurement in host-exposure-and-paths.md
    # was taken with a browser agent and no cookie. Some handlers negotiate on
    # the agent, so reproducing the measurement needs the same agent. This is a
    # protocol requirement for reproducing a documented result, not evasion,
    # and it is off by default.
    $headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
}

$targets = @()
if (-not $SkipDefaultPaths) { $targets += $defaultPaths }
$targets += $Path
$targets = @($targets | Where-Object { $_ } | Select-Object -Unique)
if ($targets.Count -eq 0) {
    Write-Error 'No paths to probe: -SkipDefaultPaths was given with no -Path.' -ErrorAction Continue
    exit 1
}

function Get-ProbeStatus {
    param([string]$Uri)
    $common = @{
        Uri                  = $Uri
        Headers              = $headers
        TimeoutSec           = $TimeoutSec
        SkipCertificateCheck = $skipCert
        SkipHttpErrorCheck   = $true
        MaximumRedirection   = 0
        ErrorAction          = 'Stop'
    }
    try {
        $response = Invoke-WebRequest @common -Method Head
        # A handler that refuses HEAD says so; re-ask with GET before
        # recording "blocked", or a served file reads as closed.
        if ($response.StatusCode -in 405, 501) {
            $response = Invoke-WebRequest @common -Method Get
        }
        return [int]$response.StatusCode
    }
    catch {
        return $null
    }
}

$expected = @($ExpectServed | Where-Object { $_ })
$results = [System.Collections.Generic.List[object]]::new()

Write-Host "Anonymous archive-exposure probe against $BaseUrl"
Write-Host 'No cookie, no bearer, no API key is sent — this is what the internet sees.'
Write-Host ''

foreach ($target in $targets) {
    $status = Get-ProbeStatus -Uri "$BaseUrl$target"
    $isExpected = $expected -contains $target
    $verdict =
        if ($null -eq $status) { 'ERROR' }
        elseif ($status -eq 200 -and $isExpected) { 'EXPECTED' }
        elseif ($status -eq 200) { 'SERVED' }
        elseif ($isExpected) { 'CLOSED' }
        else { 'BLOCKED' }
    $results.Add([pscustomobject]@{ Path = $target; Status = $status; Verdict = $verdict })
    Write-Host ('{0,-9} {1,-5} {2}' -f $verdict, ($status ?? 'n/a'), $target)
}

$served = @($results | Where-Object { $_.Verdict -eq 'SERVED' })
$errored = @($results | Where-Object { $_.Verdict -eq 'ERROR' })

Write-Host ''
Write-Host ("{0} probed, {1} served unexpectedly, {2} accepted caveat(s), {3} unreachable." -f
    $results.Count, $served.Count, @($results | Where-Object { $_.Verdict -eq 'EXPECTED' }).Count, $errored.Count)

if ($served.Count -gt 0) {
    Write-Host ''
    Write-Host 'SERVED paths are anonymously downloadable. Next steps, in order:'
    Write-Host '  1. A SqlProvider activity: switch it to integrated security (SourceServerSSPI /'
    Write-Host '     DestinationServerSSPI beside Server / Catalog). It survives the re-serialization'
    Write-Host '     of job files on every run, which a one-off hand edit does not.'
    Write-Host '  2. Assert the job folder carries no credential by DECODING UTF-16LE first — a naive'
    Write-Host '     byte grep over a job file is a false clean.'
    Write-Host '  3. Move the archive off the web root, or put the assets behind an authenticated'
    Write-Host '     handler. A site-level web.config requestFiltering deny is not available on a'
    Write-Host '     typical shared host and answers 500 on every URL including /Admin.'
    Write-Host '  4. Where the exposure genuinely cannot be closed, re-run with -ExpectServed so it'
    Write-Host '     is a declared caveat rather than a surprise.'
    exit 1
}
if ($errored.Count -gt 0) {
    Write-Host 'One or more paths did not answer at all — the probe proved nothing about them.'
    exit 1
}
exit 0
