<#
.SYNOPSIS
    READ-ONLY. Runs the canvas-fit / legibility / text-overlap probe over a set of
    pages at a set of viewports and prints one JSON result on stdout.

.DESCRIPTION
    The mechanical half of the mobile pass (owning reference:
    dw-demo-swift/references/mobile-pass.md — the canvas-not-viewport method, the
    Swift 2 trap catalogue and the "verify first, theme-default already ships most
    fixes" caveat stay there; this script is the how). It writes nothing: no
    -WhatIf / -Apply pair applies.

    Per page per viewport it asserts, through scripts/overflow-probe.js:
      canvas-fit    window.innerWidth === the REQUESTED width AND
                    document.body.scrollWidth === innerWidth. Both halves matter:
                    body (not documentElement) because `overflow-x: hidden` masks
                    the stretch, and the innerWidth leg because a widened layout
                    viewport makes the scrollWidth equality true by construction.
                    The offender is named by RIGHT EDGE; a closed off-canvas drawer
                    and anything else out of flow is reported as SET ASIDE.
      contrast      every text leaf at or above the WCAG threshold against the
                    nearest opaque ancestor background.
      text-overlap  no two painted line boxes intersect by more than the ratio.

    THE DEFAULTS ARE SWIFT 2 DEFAULTS, NOT THE METHOD. Every threshold below is a
    parameter; the values are what a Swift 2 storefront is held to today. A
    non-Swift site keeps the method and supplies its own numbers.

    A viewport narrower than -DesktopBreakpoint is REFUSED without a device
    descriptor: Dynamicweb picks the header server-side by user-agent, so a bare
    390px viewport measures the desktop document and certifies a layout no phone
    receives. The desktop control viewport is deliberately kept in the default set
    — a narrow desktop browser legitimately gets the 3-row header.

.PARAMETER BaseUrl
    Host base URL. Falls back to $env:DW_BASE_URL. No default host exists.

.PARAMETER Path
    Relative page paths to measure. Default: the site root.

.PARAMETER Viewport
    One or more viewports as hashtables @{ width; height; device; label }. `device`
    is a Playwright device descriptor name and is mandatory below
    -DesktopBreakpoint. Default: iPhone 12 at 390x844, a 430x932 wrap-boundary
    partner (iPhone 14 Pro Max), and a 1440x900 desktop control.

.PARAMETER DesktopBreakpoint
    Width below which a device descriptor is mandatory. Swift 2 default: 992
    (Bootstrap lg).

.PARAMETER ScrollTolerance
    Allowed px difference between body.scrollWidth and innerWidth. Default 1.

.PARAMETER MinContrast
    WCAG ratio for normal text. Swift 2 default: 4.5.

.PARAMETER MinContrastLarge
    WCAG ratio for large text (>=24px, or >=18.66px bold). Swift 2 default: 3.

.PARAMETER MaxOverlapRatio
    Intersection of the smaller line box above which two text boxes collide.
    Default 0.25, the value the Foundry design leg runs.

.PARAMETER TextSelector
    Scope of the contrast sweep. Swift 2 default: 'main *, header *, footer *'.

.PARAMETER ScopeSelector
    Scope of the overlap sweep. Swift 2 default: 'main'.

.PARAMETER MaxReport
    Offenders listed per failing probe. Default 6.

.PARAMETER AllowSelfSignedCertificate
    Skip TLS validation for a non-localhost -BaseUrl. Localhost is bypassed anyway.

.PARAMETER TimeoutSec
    Per-page navigation timeout. Default 60.

.PARAMETER OutFile
    Also write the merged JSON result here.

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwViewportOverflow.ps1 -BaseUrl "https://<host>" -Path /,/products

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwViewportOverflow.ps1 -BaseUrl $env:DW_BASE_URL `
      -Viewport @{ width = 390; height = 844; device = 'iPhone 12'; label = 'phone' } `
      -MinContrast 4.5 -OutFile viewport.json

.NOTES
    Exit 0 = every probe passed, 1 = a probe failed, 2 = the probe could not run
    (node or playwright missing, no base URL). An unrunnable leg is never a pass.
#>
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$BaseUrl = $env:DW_BASE_URL,
    [string[]]$Path = @('/'),
    [hashtable[]]$Viewport = @(
        @{ width = 390;  height = 844; device = 'iPhone 12';         label = 'phone-390' },
        @{ width = 430;  height = 932; device = 'iPhone 14 Pro Max'; label = 'phone-430' },
        @{ width = 1440; height = 900; device = $null;               label = 'desktop-1440' }
    ),
    [int]$DesktopBreakpoint = 992,
    [int]$ScrollTolerance = 1,
    [double]$MinContrast = 4.5,
    [double]$MinContrastLarge = 3,
    [double]$MaxOverlapRatio = 0.25,
    [string]$TextSelector = 'main *, header *, footer *',
    [string]$ScopeSelector = 'main',
    [int]$MaxReport = 6,
    [switch]$AllowSelfSignedCertificate,
    [int]$TimeoutSec = 60,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param([hashtable]$Result, [int]$ExitCode)
    $json = $Result | ConvertTo-Json -Depth 8
    if ($OutFile) { $json | Set-Content -Path $OutFile -Encoding utf8NoBOM }
    Write-Output $json
    exit $ExitCode
}

$result = @{
    status     = 'UNRUNNABLE'
    baseUrl    = $BaseUrl
    thresholds = @{
        desktopBreakpoint = $DesktopBreakpoint
        scrollTolerance   = $ScrollTolerance
        minContrast       = $MinContrast
        minContrastLarge  = $MinContrastLarge
        maxOverlapRatio   = $MaxOverlapRatio
        textSelector      = $TextSelector
        scopeSelector     = $ScopeSelector
    }
    viewports  = @()
    probes     = @()
    detail     = ''
}

if (-not $BaseUrl) {
    $result.detail = 'No base URL. Pass -BaseUrl or set $env:DW_BASE_URL. There is no default host.'
    Write-Result -Result $result -ExitCode 2
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    $result.detail = 'node is not on PATH. The probe drives a headless Chromium through Playwright; install Node 20+ (the demo setup preflight installs it).'
    Write-Result -Result $result -ExitCode 2
}

$probe = Join-Path $PSScriptRoot 'overflow-probe.js'
if (-not (Test-Path $probe)) {
    $result.detail = "overflow-probe.js is missing beside this script (looked in $PSScriptRoot). The probe cannot run; this is not a pass."
    Write-Result -Result $result -ExitCode 2
}

# ESM/CJS module resolution walks up from the SCRIPT's directory and ignores
# NODE_PATH, so playwright must resolve from this scripts/ folder. Say so once,
# with the command that fixes it, rather than letting node fail per viewport.
$playwrightPkg = Join-Path $PSScriptRoot 'node_modules/playwright/package.json'
if (-not (Test-Path $playwrightPkg)) {
    Write-Verbose "no node_modules/playwright beside the probe; node may still resolve it from a parent folder"
}

$allProbes = @()
$anyFail = $false
$anyUnrunnable = $false

foreach ($vp in $Viewport) {
    $width  = [int]$vp.width
    $height = [int]$vp.height
    $device = if ($vp.ContainsKey('device')) { "$($vp.device)" } else { '' }
    $label  = if ($vp.ContainsKey('label') -and $vp.label) { "$($vp.label)" } else { "$($width)x$height" }

    if ($width -lt $DesktopBreakpoint -and -not $device) {
        # Refuse rather than measure the wrong document. A sub-breakpoint viewport
        # with no descriptor is served the DESKTOP header by Dynamicweb.
        $allProbes += [ordered]@{
            name   = "device-descriptor[$label]"
            result = 'FAIL'
            detail = "viewport $label is ${width}px, below the ${DesktopBreakpoint}px desktop breakpoint, and names no device. " +
                     'Dynamicweb picks the header server-side by user-agent, so the desktop document would be measured at phone ' +
                     "width. Add device = 'iPhone 12' to the viewport. Its asserts did not run."
            value  = $null
        }
        $anyFail = $true
        continue
    }

    $probeArgs = @($probe, '--url', $BaseUrl)
    foreach ($p in $Path) { $probeArgs += @('--path', $p) }
    $probeArgs += @(
        '--width', "$width", '--height', "$height",
        '--desktop-breakpoint', "$DesktopBreakpoint",
        '--scroll-tolerance', "$ScrollTolerance",
        '--min-contrast', "$MinContrast",
        '--min-contrast-large', "$MinContrastLarge",
        '--max-overlap-ratio', "$MaxOverlapRatio",
        '--text-selector', $TextSelector,
        '--scope-selector', $ScopeSelector,
        '--max-report', "$MaxReport",
        '--timeout', "$($TimeoutSec * 1000)"
    )
    if ($device) { $probeArgs += @('--device', $device) }
    if ($AllowSelfSignedCertificate) { $probeArgs += '--allow-self-signed' }

    $raw = & $node.Source @probeArgs 2>&1
    $code = $LASTEXITCODE
    $text = ($raw | Out-String)

    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json } catch { $parsed = $null }

    if ($null -eq $parsed) {
        $anyUnrunnable = $true
        $allProbes += [ordered]@{
            name   = "probe[$label]"
            result = 'FAIL'
            detail = "the probe produced no JSON (exit $code): $($text.Trim() -replace '\s+', ' ')"
            value  = $null
        }
        continue
    }

    $result.viewports += [ordered]@{
        label = $label; width = $width; height = $height
        device = $(if ($device) { $device } else { $null })
        status = "$($parsed.status)"
    }
    if ("$($parsed.status)" -eq 'UNRUNNABLE') { $anyUnrunnable = $true }
    foreach ($pr in @($parsed.probes)) {
        $allProbes += [ordered]@{
            name   = "$label/$($pr.name)"
            result = "$($pr.result)"
            detail = "$($pr.detail)"
            value  = $pr.value
        }
        if ("$($pr.result)" -eq 'FAIL') { $anyFail = $true }
    }
    if (@($parsed.probes).Count -eq 0 -and "$($parsed.status)" -ne 'PASS') {
        $anyUnrunnable = $true
        $allProbes += [ordered]@{
            name = "probe[$label]"; result = 'FAIL'; value = $null
            detail = "no probe ran at $label : $($parsed.detail)"
        }
    }
}

$result.probes = $allProbes
$failed = @($allProbes | Where-Object { $_.result -eq 'FAIL' })

if ($anyUnrunnable) {
    $result.status = 'UNRUNNABLE'
    $result.detail = "the probe could not complete for at least one viewport; $($failed.Count) of $($allProbes.Count) row(s) are FAIL. Nothing here is a pass."
    Write-Result -Result $result -ExitCode 2
}
if ($allProbes.Count -eq 0) {
    $result.status = 'UNRUNNABLE'
    $result.detail = 'zero probes ran — nothing was measured, so this is not a pass.'
    Write-Result -Result $result -ExitCode 2
}
if ($anyFail) {
    $result.status = 'FAIL'
    $result.detail = "$($failed.Count) of $($allProbes.Count) probe(s) failed across $(@($Viewport).Count) viewport(s) and $(@($Path).Count) page(s)."
    Write-Result -Result $result -ExitCode 1
}
$result.status = 'PASS'
$result.detail = "$($allProbes.Count) probe(s) passed across $(@($Viewport).Count) viewport(s) and $(@($Path).Count) page(s). An emulated pass is necessary, not sufficient: finish on a real device (mobile-pass.md method step 6)."
Write-Result -Result $result -ExitCode 0
