<#
.SYNOPSIS
    READ-ONLY. Proves a page gate by fetching it as a GRANTED persona and as a
    DENIED persona in the same pass, and comparing the rendered bodies.

.DESCRIPTION
    Three things make a page-gating check pass while the gate is broken, and
    this script exists to close all three:

      1. "ANONYMOUS IS REDIRECTED" PROVES NOTHING. Anonymous is the one
         identity a positive-only grant does deny, which is exactly why the
         broken shape reads as working. A grant written only for the entitled
         groups admits every other signed-in persona, because a group with no
         row inherits its PARENT's permission, and the parent of a root-level
         page is the permissive area default. So this script REFUSES to run
         with only one persona: PASS needs both halves.
      2. A DENIED SIGNED-IN USER GETS NO REDIRECT AND NO 403. The page answers
         HTTP 200 with a near-empty body — a shell of a few hundred bytes — so
         the observation is the RENDERED BODY SIZE, not the status code. The
         comparison here is relative (denied body vs granted body), because no
         absolute byte constant holds across solutions; -MaxDeniedBytes fixes
         an absolute ceiling where you have measured one.
      3. ADDRESS THE PAGE BY ID. A subtree whose friendly url does not resolve
         answers 404 for every identity, granted and denied alike, so a check
         against a composed friendly path passes without ever reaching the
         gate. This script builds /Default.aspx?ID=<pageId> itself.

    A run where both personas receive the same response is a BROKEN CHECK, not
    a pass, and is reported as such.

    Credentials come from the environment only and are never echoed: set
    DW_GRANTED_USER / DW_GRANTED_PASSWORD and DW_DENIED_USER /
    DW_DENIED_PASSWORD. Each persona signs in on its own cookie session.

    Not checked here, and kept in the owning reference: that assets under
    /Files bypass the gate entirely (the static handler never reaches the page
    pipeline), and that gates resolve against the EFFECTIVE user, so an
    impersonation session inherits the impersonated user's gate.

    Owning reference: dw-data-access/references/recipes-users.md
    ("Prove a page gate with two personas"); the row shape, the
    AuthenticatedFrontend-None-plus-group-Read pattern and the enforcement
    points are in dw-users-permissions (`page-gating.md`).

.PARAMETER PageId
    The gated page id. The request is built as /Default.aspx?ID=<PageId>.

.PARAMETER SignInPath
    The path of the sign-in surface that establishes the cookie session
    (a customer-centre or sign-in page path on this solution).

.PARAMETER BaseUrl
    Host base URL; else $env:DW_BASE_URL.

.PARAMETER MaxDeniedBytes
    Optional absolute ceiling for the denied body, where you have measured one
    on this solution. Without it the comparison is relative.

.PARAMETER MinRatio
    The granted body must be at least this many times the denied body.
    Default 4.

.PARAMETER AllowSelfSignedCertificate
    Accept an untrusted certificate. Loopback is trusted automatically.

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwPageGating.ps1 -PageId 8460 -SignInPath /customer-center

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwPageGating.ps1 -PageId 8460 -SignInPath /signin -MaxDeniedBytes 600
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int]$PageId,
    [Parameter(Mandatory = $true)][string]$SignInPath,
    [string]$BaseUrl,
    [int]$MaxDeniedBytes,
    [double]$MinRatio = 4,
    [switch]$AllowSelfSignedCertificate
)

$ErrorActionPreference = 'Stop'

if (-not $BaseUrl) { $BaseUrl = $env:DW_BASE_URL }
if (-not $BaseUrl) {
    Write-Error 'No base URL. Pass -BaseUrl or set $env:DW_BASE_URL.' -ErrorAction Continue
    exit 1
}
$BaseUrl = $BaseUrl.TrimEnd('/')
$skipCert = [bool](($BaseUrl -match '^https?://(localhost|127\.0\.0\.1|\[::1\])([:/]|$)') -or $AllowSelfSignedCertificate)

$missing = @('DW_GRANTED_USER', 'DW_GRANTED_PASSWORD', 'DW_DENIED_USER', 'DW_DENIED_PASSWORD') |
    Where-Object { -not (Get-Item "env:$_" -ErrorAction SilentlyContinue) }
if ($missing) {
    Write-Error ("Set these first, in the environment only: $($missing -join ', '). PASS needs BOTH " +
        "halves — a full page for a granted persona and a near-empty one for a denied persona. " +
        "One persona proves nothing, because a positive-only grant denies exactly Anonymous and " +
        "admits every other signed-in identity.") -ErrorAction Continue
    exit 1
}

function Get-PersonaBody {
    <# Signs one persona in on its own cookie session, then fetches the gated
       page BY ID. The password is read from the environment inside this
       function and never returned, logged or interpolated into a message. #>
    param([string]$UserVar, [string]$PasswordVar, [string]$Label)
    $session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $user = (Get-Item "env:$UserVar").Value
    $common = @{
        WebSession           = $session
        SkipCertificateCheck = $skipCert
        SkipHttpErrorCheck   = $true
        TimeoutSec           = 60
        ErrorAction          = 'Stop'
    }
    # The sign-in surface takes lowercase username/password on a cookie
    # session; /dwapi/users/authenticate issues a token, not a session, so it
    # cannot be used to fetch a gated page.
    $secret = (Get-Item "env:$PasswordVar").Value
    $form = @{ username = $user; password = $secret }
    $signIn = Invoke-WebRequest @common -Uri "$BaseUrl$SignInPath" -Method Post -Body $form
    if ($signIn.StatusCode -ge 400) {
        Write-Host "$Label FAILED to sign in: HTTP $($signIn.StatusCode) on $SignInPath."
        return $null
    }
    # BY ID. A composed friendly path that does not resolve answers 404 for
    # every identity, so the check would pass without reaching the gate.
    $page = Invoke-WebRequest @common -Uri "$BaseUrl/Default.aspx?ID=$PageId" -Method Get
    [pscustomobject]@{
        Label  = $Label
        User   = $user
        Status = [int]$page.StatusCode
        Bytes  = ($page.Content ?? '').Length
    }
}

Write-Host "Gated page: $BaseUrl/Default.aspx?ID=$PageId (by id, never a friendly path)"
Write-Host ''

$granted = Get-PersonaBody -UserVar 'DW_GRANTED_USER' -PasswordVar 'DW_GRANTED_PASSWORD' -Label 'GRANTED'
$denied = Get-PersonaBody -UserVar 'DW_DENIED_USER' -PasswordVar 'DW_DENIED_PASSWORD' -Label 'DENIED '
if (-not $granted -or -not $denied) { exit 1 }

foreach ($p in $granted, $denied) {
    Write-Host ('{0}  user {1,-24} HTTP {2}  {3} bytes' -f $p.Label, $p.User, $p.Status, $p.Bytes)
}
Write-Host ''

if ($granted.Status -eq 404 -or $denied.Status -eq 404) {
    Write-Host 'BROKEN CHECK: 404 for at least one persona. The page id does not resolve, so the gate was'
    Write-Host 'never reached. Fix the id before reading anything into this run.'
    exit 1
}
if ($granted.Bytes -eq $denied.Bytes) {
    Write-Host 'BROKEN CHECK: both personas received the same response. That is not a pass — it means the'
    Write-Host 'two personas are not on opposite sides of this gate, or neither signed in.'
    exit 1
}
if ($granted.Bytes -lt $denied.Bytes) {
    Write-Host 'FAIL: the granted persona received the SMALLER body. The grant is inverted — level 1 is'
    Write-Host 'None, a denial, not the bottom of a ladder.'
    exit 1
}
if ($MaxDeniedBytes -and $denied.Bytes -gt $MaxDeniedBytes) {
    Write-Host "FAIL: the denied persona received $($denied.Bytes) bytes, past the measured ceiling of $MaxDeniedBytes."
    Write-Host 'A denied signed-in user gets HTTP 200 with a near-empty shell, so a full body here means the'
    Write-Host 'gate admits them. A positive-only grant is the usual cause: write an explicit row for EVERY'
    Write-Host 'identity, not only the ones being granted.'
    exit 1
}
$ratio = [math]::Round($granted.Bytes / [math]::Max($denied.Bytes, 1), 1)
if ($ratio -lt $MinRatio) {
    Write-Host "FAIL: the granted body is only ${ratio}x the denied body (needs ${MinRatio}x)."
    Write-Host 'The denied persona is receiving something close to the full page.'
    exit 1
}
Write-Host "PASS: granted ${ratio}x the denied body, both halves observed."
Write-Host 'Note: assets under /Files bypass this gate entirely — the static handler never reaches the'
Write-Host 'page pipeline, so page and role permissions do not apply to them.'
exit 0
