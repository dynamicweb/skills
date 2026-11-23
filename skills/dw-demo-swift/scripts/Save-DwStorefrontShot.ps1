<#
.SYNOPSIS
    READ-ONLY. Reads the storefront and saves full-page screenshots, signed out or
    signed in as one user, then prints one JSON result. Writes PNG files under
    -OutDir and nothing on the site.

.DESCRIPTION
    The screenshot half of a storefront check, so a session does not write its own
    shot script. One PNG per path per viewport, named <viewport label>-<path>.png
    (with -signed-in when a user is given), through scripts/storefront-shot.mjs on
    Node and Playwright, found and launched the way Test-DwViewportOverflow.ps1
    launches its probe.

    Owning reference: dw-demo-swift/references/storefront-browser-checks.md (the
    sign-in form and the consent banner as measured). The consent cookie
    Dynamicweb.CookieOptInLevel=2 is seeded before the first navigation and the
    banner is still accepted if it shows; each page is scroll-swept before the
    full-page capture so lazy images are in it (dw-demo-base
    references/browser-automation.md, "Generic verify-flow recipe").

    Signed in: the password is read by the runner from the environment variable
    named by -PasswordEnv; it is never a parameter, never on the node command line
    and masked in every message. The sign-in is PROVEN, not assumed: -IdentityPath
    must answer below 400, not land on the sign-in page and carry no password field,
    and carry -IdentityText when it is given. An unproven sign-in takes no shots.

    A viewport narrower than -DesktopBreakpoint needs a Playwright device
    descriptor: Dynamicweb picks the header by user-agent, so a bare narrow
    viewport photographs the desktop document.

.PARAMETER BaseUrl
    Site base URL. Falls back to $env:DW_BASE_URL. No default host exists.

.PARAMETER Path
    One or more site-relative paths. Default: /en-us/home.

.PARAMETER Viewport
    Hashtables @{ width; height; device; label }. Default: a 1440x900 desktop and
    a 390x844 phone (device 'iPhone 12').

.PARAMETER OutDir
    Folder for the PNG files. Default: notes/qa under the current directory.

.PARAMETER AllowSelfSignedCertificate
    Skip TLS validation for a non-localhost site. Localhost is bypassed anyway.

.PARAMETER SignInPath
    The storefront sign-in page. Default: /en-us/sign-in/sign-in.

.PARAMETER UserName
    Sign in as this user before the shots. Without it the shots are signed out.

.PARAMETER PasswordEnv
    Name of the environment variable holding that user's password.

.PARAMETER IdentityPath
    The page that proves the sign-in. Default: /en-us/customer-center.

.PARAMETER IdentityText
    Text the identity page shows only to that user (a name, a company).

.PARAMETER DesktopBreakpoint
    Width below which a device descriptor is required. Swift 2 default: 992.

.PARAMETER TimeoutSec
    Per-page navigation timeout. Default 60.

.EXAMPLE
    pwsh -NoProfile -File scripts/Save-DwStorefrontShot.ps1 -BaseUrl "https://<host>" -Path /en-us/home,/en-us/shop

.EXAMPLE
    $env:DW_SHOT_PASSWORD = '<from the vault>'
    pwsh -NoProfile -File scripts/Save-DwStorefrontShot.ps1 -Path /en-us/customer-center -UserName <buyer> -IdentityText '<company>'

.NOTES
    Exit 0 = every shot saved below 400 (and the sign-in proven), 1 = a shot or the
    sign-in failed, 2 = could not run (no base URL, node or playwright missing).
#>
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$BaseUrl = $env:DW_BASE_URL,
    [string[]]$Path = @('/en-us/home'),
    [hashtable[]]$Viewport = @(
        @{ width = 1440; height = 900; device = $null;       label = 'desktop-1440' },
        @{ width = 390;  height = 844; device = 'iPhone 12'; label = 'phone-390' }
    ),
    [string]$OutDir = (Join-Path (Get-Location).Path 'notes/qa'),
    [switch]$AllowSelfSignedCertificate,
    [string]$SignInPath = '/en-us/sign-in/sign-in',
    [string]$UserName,
    [string]$PasswordEnv = 'DW_SHOT_PASSWORD',
    [string]$IdentityPath = '/en-us/customer-center',
    [string]$IdentityText,
    [int]$DesktopBreakpoint = 992,
    [int]$TimeoutSec = 60
)

$ErrorActionPreference = 'Stop'

# { label; width; height; device; error } per viewport; a narrow one without a device is refused.
function Resolve-DwShotViewport {
    param([hashtable[]]$Viewport, [int]$DesktopBreakpoint)
    foreach ($vp in @($Viewport)) {
        $width = [int]$vp.width; $height = [int]$vp.height
        $device = if ($vp.ContainsKey('device') -and $vp.device) { "$($vp.device)" } else { $null }
        $label = if ($vp.ContainsKey('label') -and $vp.label) { "$($vp.label)" } else { "${width}x$height" }
        $err = $null
        if ($width -le 0 -or $height -le 0) { $err = "viewport $label has no width or height." }
        elseif ($width -lt $DesktopBreakpoint -and -not $device) {
            $err = "viewport $label is ${width}px, below the ${DesktopBreakpoint}px desktop breakpoint, and names no device. " +
                "Dynamicweb picks the header by user-agent, so it would photograph the desktop document. Add device = 'iPhone 12'."
        }
        [pscustomobject]@{ label = $label; width = $width; height = $height; device = $device; error = $err }
    }
}

# The node arguments for one viewport. The password is never one of them: only the NAME
# of the variable that holds it.
function Get-DwShotRunnerArgs {
    param(
        [Parameter(Mandatory)][string]$Runner, [Parameter(Mandatory)][string]$BaseUrl,
        [string[]]$Path, [Parameter(Mandatory)]$Viewport, [Parameter(Mandatory)][string]$OutDir,
        [string]$UserName, [string]$PasswordEnv, [string]$SignInPath, [string]$IdentityPath,
        [string]$IdentityText, [switch]$AllowSelfSignedCertificate, [int]$TimeoutSec = 60
    )
    $a = @($Runner, '--url', $BaseUrl.TrimEnd('/'))
    # pwsh -File hands "-Path /a,/b" over as ONE string, so a comma separates paths here too.
    foreach ($p in @($Path | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $a += @('--path', $(if ($p.StartsWith('/')) { $p } else { "/$p" }))
    }
    $a += @('--width', "$($Viewport.width)", '--height', "$($Viewport.height)", '--label', $Viewport.label,
        '--out-dir', $OutDir, '--timeout', "$($TimeoutSec * 1000)")
    if ($Viewport.device) { $a += @('--device', $Viewport.device) }
    if ($UserName) {
        $a += @('--user', $UserName, '--password-env', $PasswordEnv, '--sign-in-path', $SignInPath,
            '--identity-path', $IdentityPath)
        if ($IdentityText) { $a += @('--identity-text', $IdentityText) }
    }
    if ($AllowSelfSignedCertificate) { $a += '--allow-self-signed' }
    , $a
}

# One result from the per-viewport runner results. Any UNRUNNABLE wins, then any FAIL.
function Merge-DwShotResult {
    param([object[]]$Runs, [string]$BaseUrl, [string]$OutDir, [string]$UserName)
    $runs = @($Runs | Where-Object { $_ })
    $shots = @(foreach ($r in $runs) {
        foreach ($s in @($r.shots)) {
            if (-not $s) { continue }
            [ordered]@{ viewport = "$($r.viewport.label)"; path = $s.path; status = $s.status; file = $s.file; error = $s.error }
        }
    })
    $signIn = $null
    if ($UserName) {
        $per = @(foreach ($r in $runs) { [ordered]@{ viewport = "$($r.viewport.label)"; proven = [bool]($r.signIn -and $r.signIn.proven); detail = $(if ($r.signIn) { $r.signIn.detail } else { $r.detail }) } })
        $signIn = [ordered]@{ user = $UserName; proven = ($per.Count -gt 0 -and @($per | Where-Object { -not $_.proven }).Count -eq 0); perViewport = $per }
    }
    $status = 'PASS'
    if ($runs.Count -eq 0 -or @($runs | Where-Object { "$($_.status)" -eq 'UNRUNNABLE' }).Count) { $status = 'UNRUNNABLE' }
    elseif (@($runs | Where-Object { "$($_.status)" -ne 'PASS' }).Count) { $status = 'FAIL' }
    $saved = @($shots | Where-Object { $_.file -and -not $_.error -and $null -ne $_.status -and $_.status -lt 400 })
    [ordered]@{
        status  = $status
        baseUrl = $BaseUrl
        outDir  = $OutDir
        signIn  = $signIn
        files   = @($saved | ForEach-Object { $_.file })
        shots   = $shots
        detail  = "$($saved.Count) of $($shots.Count) shot(s) saved below HTTP 400 across $($runs.Count) viewport run(s)" +
            $(if ($UserName) { "; sign-in as $UserName $(if ($signIn.proven) { 'proven' } else { 'NOT proven' })." } else { '; signed out.' })
        runs    = @($runs | ForEach-Object { [ordered]@{ viewport = "$($_.viewport.label)"; status = "$($_.status)"; detail = "$($_.detail)" } })
    }
}

function Invoke-Main {
    $emit = {
        param($Result, [int]$Code)
        Write-Output ($Result | ConvertTo-Json -Depth 8)
        exit $Code
    }
    $fail = { param([string]$Detail) & $emit ([ordered]@{ status = 'UNRUNNABLE'; baseUrl = $BaseUrl; detail = $Detail }) 2 }

    if (-not $BaseUrl) { & $fail 'No base URL. Pass -BaseUrl or set $env:DW_BASE_URL. There is no default host.' }
    if ($UserName -and -not [Environment]::GetEnvironmentVariable($PasswordEnv)) {
        & $fail "-UserName was given but `$env:$PasswordEnv is empty. Put the password in that variable; it is never a parameter."
    }
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) { & $fail 'node is not on PATH. The shots run a headless Chromium through Playwright; install Node 20+.' }
    $runner = Join-Path $PSScriptRoot 'storefront-shot.mjs'
    if (-not (Test-Path $runner)) { & $fail "storefront-shot.mjs is missing beside this script (looked in $PSScriptRoot)." }

    $viewports = @(Resolve-DwShotViewport -Viewport $Viewport -DesktopBreakpoint $DesktopBreakpoint)
    $refused = @($viewports | Where-Object { $_.error })
    if ($refused.Count) { & $fail (($refused | ForEach-Object { $_.error }) -join ' ') }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $runs = @(foreach ($vp in $viewports) {
        $runnerArgs = Get-DwShotRunnerArgs -Runner $runner -BaseUrl $BaseUrl -Path $Path -Viewport $vp -OutDir $OutDir `
            -UserName $UserName -PasswordEnv $PasswordEnv -SignInPath $SignInPath -IdentityPath $IdentityPath `
            -IdentityText $IdentityText -AllowSelfSignedCertificate:$AllowSelfSignedCertificate -TimeoutSec $TimeoutSec
        # stdout carries the JSON; a node warning on stderr must not break the parse.
        $all = & $node.Source @runnerArgs 2>&1
        $text = ($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Out-String)
        $errText = ($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | Out-String)
        $parsed = $null
        try { $parsed = $text | ConvertFrom-Json } catch { $parsed = $null }
        if ($null -eq $parsed) {
            [pscustomobject]@{ status = 'UNRUNNABLE'; viewport = [pscustomobject]@{ label = $vp.label }; shots = @()
                detail = "the runner produced no JSON (exit $LASTEXITCODE): $("$text $errText".Trim() -replace '\s+', ' ')" }
        }
        else { $parsed }
    })
    $result = Merge-DwShotResult -Runs $runs -BaseUrl $BaseUrl -OutDir $OutDir -UserName $UserName
    $code = switch ($result.status) { 'PASS' { 0 } 'FAIL' { 1 } default { 2 } }
    & $emit $result $code
}

# Dot-sourcing loads the functions and runs nothing (that is how the Pester suite covers
# the pure parts); invoking the file takes the shots.
if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }
