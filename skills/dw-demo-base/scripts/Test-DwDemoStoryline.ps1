<#
.SYNOPSIS
    READ-ONLY. The consumer self-check: every storyline page answers 200 and carries
    no placeholder copy, and every persona actually signs in. Prints one JSON result.

.DESCRIPTION
    What no upstream proof transfers. Once a Distribution edition is gate-proven, a
    consumer inherits every leg that asserts the PLATFORM (admin, dwapi, mcp,
    pim-count, the zero-state design legs) and never reruns them. What stays the
    consumer's own is its material: storyline pages that exist and read as finished
    copy, and personas that can sign in. Those are the two failures a presenter
    meets in front of the prospect instead of before it.

    This is NOT a gate. It writes no verdict contract, carries no leg registry, and
    nothing downstream reads its output; the demo gate stays with the Foundry as the
    attribution instrument. Two checks only:

      storyline  each pages[] entry is fetched ANONYMOUSLY: HTTP 200, and the
                 placeholder regex must not match the VISIBLE TEXT. Visible text,
                 never the markup: Swift 2 ships placeholder="Search here" and a
                 js-async-fetch-placeholder wrapper on every page, so a raw-body
                 match fails every Swift site for a reason no content edit can
                 clear. Copy that says "placeholder" or "TODO" still fails. An
                 object entry adds a length band and substring asserts.

      personas   each account signs in through the real form post AND the session is
                 PROVED to be that persona. A login status code is not an identity:
                 /dwapi/users/authenticate returns a JWT and does not mint the
                 Dynamicweb.Extranet cookie the storefront reads, so a 200 there
                 leaves the session anonymous, and an anonymous session satisfies
                 every denial check for the wrong reason. Without identityPath +
                 identityContains the result SAYS the check was status-only rather
                 than implying a stronger assert than it made.

    ZERO PROBES IS FAIL. A config with no pages and no accounts reports FAIL: nothing
    measured is not a pass. SECRETS: a persona secret is read from an environment
    variable named by the account (`secretEnv`), or from a JSON file passed as
    -SecretsPath keyed by `secretKey`. Never a parameter, never a literal in the
    config, and never printed — every mention is masked to `<set, N chars>`.

.PARAMETER ConfigPath
    Path to the JSON config. Shape (the same table is in the skill's SKILL.md):

      baseUrl           string, else -BaseUrl, else $env:DW_BASE_URL
      placeholderRegex  string, default lorem/TODO/placeholder/sample text/xxxx+
      pages[]           a path string, or an object
                        { path, minBytes, maxBytes, contains[], notContains[] }
      personas.login    { path, method, usernameField, passwordField,
                          contentType: form|json, successCodes[], extraFields{} }
      personas.identityPath      default identity page for every account
      personas.accounts[]        { role, username, secretEnv | secretKey,
                                   identityPath, identityContains }

    Example:

      { "baseUrl": "https://<host>",
        "pages": [ "/", { "path": "/products", "minBytes": 20000,
                          "contains": ["Add to cart"] } ],
        "personas": { "login": { "path": "/api/login" },
                      "identityPath": "/en-us/account",
                      "accounts": [ { "role": "buyer",
                                      "username": "buyer@example.invalid",
                                      "secretEnv": "DW_DEMO_BUYER_SECRET",
                                      "identityContains": "Sign out" } ] } }

.PARAMETER BaseUrl
    Overrides config.baseUrl; else $env:DW_BASE_URL. No default host exists.

.PARAMETER SecretsPath
    JSON file of { "<secretKey>": "<secret>" } for accounts that name a secretKey
    instead of a secretEnv. Keep it out of version control.

.PARAMETER TimeoutSec
    Per-request timeout. Default 30.

.PARAMETER AllowSelfSignedCertificate
    Skip TLS validation for a non-localhost base URL. Localhost is bypassed anyway.

.PARAMETER OutFile
    Also write the JSON result here.

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwDemoStoryline.ps1 -ConfigPath demo-storyline.json

.EXAMPLE
    $env:DW_DEMO_BUYER_SECRET = (Read-Host -AsSecureString | ConvertFrom-SecureString -AsPlainText)
    pwsh -NoProfile -File scripts/Test-DwDemoStoryline.ps1 -ConfigPath demo-storyline.json -OutFile storyline.json

.NOTES
    Exit 0 = PASS, 1 = FAIL (including zero probes), 2 = the check could not run.
    Dot-sourcing this file loads its functions without running the check, which is
    how the Pester suite in scripts/tests/ covers the pure parts.
#>
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$BaseUrl,
    [string]$SecretsPath,
    [int]$TimeoutSec = 30,
    [switch]$AllowSelfSignedCertificate,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

# The shared module is the only plumbing. A blocked import must fail loudly here,
# never silently compare against empty output.
Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Api.psm1') -Force -ErrorAction Stop

$script:DefaultPlaceholderRegex = 'lorem ipsum|\bTODO\b|placeholder|sample[- ]?text|xxxx+'

# Renders a secret as its length only — never a prefix (a prefix is still a secret).
function Format-DwMaskedSecret {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '<unset>' }
    return "<set, $($Value.Length) chars>"
}

# The browser-shaped User-Agent this probe sends, in one named helper, and why: a
# protocol requirement, not evasion. Dynamicweb 10 varies served content by
# user-agent (the mobile/desktop header split) and silently drops storefront cart
# commands for a non-browser agent.
function Get-DwProbeUserAgent {
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
}

# The text a visitor can read: script/style/template/noscript blocks, comments and
# every tag stripped, entities decoded, whitespace collapsed. Attribute values
# (placeholder="Search here") and class names (js-async-fetch-placeholder) are not
# copy and are deliberately out of scope.
function ConvertTo-DwVisibleText {
    param([string]$Html)
    if ([string]::IsNullOrEmpty($Html)) { return '' }
    $t = [regex]::Replace($Html, '(?is)<(script|style|template|noscript)\b[^>]*>.*?</\1\s*>', ' ')
    $t = [regex]::Replace($t, '(?s)<!--.*?-->', ' ')
    $t = [regex]::Replace($t, '(?s)<[^>]+>', ' ')
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    return [regex]::Replace($t, '\s+', ' ').Trim()
}

# One HTTP request, returning { code; body; error } and never throwing. The single
# seam the Pester suite mocks.
function Invoke-DwProbeRequest {
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Method = 'GET',
        $Body,
        [ValidateSet('form', 'json')][string]$BodyFormat = 'form',
        [int]$TimeoutSec = 30,
        [switch]$SkipCertificateCheck,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session
    )
    # NB: PowerShell variables are case-insensitive, so the response accumulator must
    # NOT be named $body — that alias of the $Body parameter would blank the request
    # body before it is sent.
    $code = 0; $respBody = ''; $err = $null
    try {
        $p = @{
            Uri = $Url; Method = $Method; MaximumRedirection = 5
            TimeoutSec = $TimeoutSec; ErrorAction = 'Stop'
            UserAgent = (Get-DwProbeUserAgent)
        }
        if ($SkipCertificateCheck) { $p.SkipCertificateCheck = $true }
        if ($Session) { $p.WebSession = $Session }
        if ($null -ne $Body) {
            if ($Body -is [System.Collections.IDictionary]) {
                if ($BodyFormat -eq 'json') {
                    $p.Body = ($Body | ConvertTo-Json -Compress)
                    $p.ContentType = 'application/json'
                } else {
                    # Encode the form ourselves: the implicit hashtable-body encoding
                    # is not deterministic enough to debug a failing sign-in.
                    $pairs = foreach ($k in $Body.Keys) {
                        "$([uri]::EscapeDataString([string]$k))=$([uri]::EscapeDataString([string]$Body[$k]))"
                    }
                    $p.Body = ($pairs -join '&')
                    $p.ContentType = 'application/x-www-form-urlencoded'
                }
            } else { $p.Body = $Body }
        }
        $resp = Invoke-WebRequest @p
        $code = [int]$resp.StatusCode
        $respBody = "$($resp.Content)"
    } catch {
        $r = $_.Exception.Response
        if ($r -and $null -ne $r.StatusCode) { try { $code = [int]$r.StatusCode } catch { $code = 0 } }
        else { $err = "$($_.Exception.Message)" }
    }
    return [pscustomobject]@{ code = $code; body = $respBody; error = $err }
}

# Status + placeholder (+ optional length/substring) per page; one probe per page.
function Test-DwStorylinePages {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        $Pages,
        [string]$PlaceholderRegex = $script:DefaultPlaceholderRegex,
        [int]$TimeoutSec = 30,
        [switch]$SkipCertificateCheck
    )
    $probes = @()
    foreach ($entry in @($Pages)) {
        $isObj = $entry -isnot [string]
        $page = if ($isObj) { "$($entry.path)" } else { "$entry" }
        if ([string]::IsNullOrWhiteSpace($page)) {
            $probes += [ordered]@{ name = 'storyline[<no path>]'; result = 'FAIL'
                detail = 'a pages[] entry carries no path'; value = $null }
            continue
        }
        $bad = @()
        $r = Invoke-DwProbeRequest -Url "$BaseUrl$page" -TimeoutSec $TimeoutSec -SkipCertificateCheck:$SkipCertificateCheck
        if ($r.code -ne 200) {
            $detail = if ($r.error) { "HTTP $($r.code): $($r.error)" } else { "HTTP $($r.code), expected 200" }
            $probes += [ordered]@{ name = "storyline[$page]"; result = 'FAIL'; detail = $detail; value = $r.code }
            continue
        }
        $visible = ConvertTo-DwVisibleText -Html $r.body
        $m = [regex]::Match($visible, $PlaceholderRegex, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) { $bad += "matched placeholder /$($m.Value)/ in the visible text" }
        if ($isObj) {
            $text = "$($r.body)"; $len = $text.Length
            if ($null -ne $entry.minBytes -and $len -lt [long]$entry.minBytes) { $bad += "$len B < min $($entry.minBytes)" }
            if ($null -ne $entry.maxBytes -and $len -gt [long]$entry.maxBytes) { $bad += "$len B > max $($entry.maxBytes)" }
            foreach ($s in @($entry.contains)) { if ($null -ne $s -and -not $text.Contains("$s")) { $bad += "missing `"$s`"" } }
            foreach ($s in @($entry.notContains)) { if ($null -ne $s -and $text.Contains("$s")) { $bad += "must be absent but present: `"$s`"" } }
        }
        $probes += [ordered]@{
            name = "storyline[$page]"
            result = $(if ($bad.Count) { 'FAIL' } else { 'PASS' })
            detail = $(if ($bad.Count) { $bad -join '; ' } else { "200, $($r.body.Length) B, placeholder-clean" })
            value = $r.code
        }
    }
    return $probes
}

# Resolves one persona secret from the environment or the secrets file. The caller
# never logs the value unmasked.
function Resolve-DwPersonaSecret {
    param([Parameter(Mandatory)]$Account, $Secrets)
    if ($Account.secretEnv) {
        $v = [Environment]::GetEnvironmentVariable("$($Account.secretEnv)")
        if ($v) { return $v }
    }
    if ($Account.secretKey -and $Secrets -and $Secrets.PSObject.Properties[[string]$Account.secretKey]) {
        return "$($Secrets."$($Account.secretKey)")"
    }
    return $null
}

# Signs one persona in and PROVES the session is that persona (no server state
# beyond a session cookie). Returns { ok; detail; identityAsserted }.
function Connect-DwPersona {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        $Login, [Parameter(Mandatory)][string]$Username, [Parameter(Mandatory)][string]$Secret,
        [string]$Role, [string]$IdentityPath, [string]$IdentityContains,
        [int]$TimeoutSec = 30, [switch]$SkipCertificateCheck
    )
    $path = if ($Login -and $Login.path) { "$($Login.path)" } else { '/api/login' }
    $method = if ($Login -and $Login.method) { "$($Login.method)" } else { 'POST' }
    $userF = if ($Login -and $Login.usernameField) { "$($Login.usernameField)" } else { 'Username' }
    $passF = if ($Login -and $Login.passwordField) { "$($Login.passwordField)" } else { 'Password' }
    $okCodes = if ($Login -and $Login.successCodes) { @($Login.successCodes | ForEach-Object { [int]$_ }) } else { @(200) }
    $bodyFmt = if ($Login -and "$($Login.contentType)" -match '^(json|application/json)$') { 'json' } else { 'form' }

    $session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $post = @{ $userF = $Username; $passF = $Secret }
    if ($Login -and $Login.extraFields) {
        foreach ($p in $Login.extraFields.PSObject.Properties) { $post[$p.Name] = "$($p.Value)" }
    }
    $r = Invoke-DwProbeRequest -Url "$BaseUrl$path" -Method $method -BodyFormat $bodyFmt -Body $post `
        -Session $session -TimeoutSec $TimeoutSec -SkipCertificateCheck:$SkipCertificateCheck
    if ($okCodes -notcontains $r.code) {
        return [pscustomobject]@{ ok = $false; identityAsserted = $false
            detail = "${Role}: login $path -> HTTP $($r.code), expected [$($okCodes -join ',')] (secret $(Format-DwMaskedSecret $Secret))" }
    }
    if (-not $IdentityPath -or -not $IdentityContains) {
        return [pscustomobject]@{ ok = $true; identityAsserted = $false
            detail = "${Role}: login $path -> HTTP $($r.code), STATUS ONLY — an anonymous session satisfies this too. Set personas.identityPath + accounts[].identityContains." }
    }
    $idr = Invoke-DwProbeRequest -Url "$BaseUrl$IdentityPath" -Session $session -TimeoutSec $TimeoutSec -SkipCertificateCheck:$SkipCertificateCheck
    if ($idr.code -ne 200) {
        return [pscustomobject]@{ ok = $false; identityAsserted = $true
            detail = "${Role}: identity page $IdentityPath -> HTTP $($idr.code) after a $($r.code) login" }
    }
    if ($idr.body -notmatch [regex]::Escape($IdentityContains)) {
        return [pscustomobject]@{ ok = $false; identityAsserted = $true
            detail = "${Role}: NOT signed in — $IdentityPath rendered $($idr.body.Length) B without the identity marker '$IdentityContains'" }
    }
    return [pscustomobject]@{ ok = $true; identityAsserted = $true
        detail = "${Role}: signed in (identity '$IdentityContains' on $IdentityPath)" }
}

# One probe per configured persona account.
function Test-DwPersonaLogins {
    param(
        [Parameter(Mandatory)][string]$BaseUrl, $Personas, $Secrets,
        [int]$TimeoutSec = 30, [switch]$SkipCertificateCheck
    )
    $probes = @()
    foreach ($a in @($Personas.accounts)) {
        $role = if ($a.role) { "$($a.role)" } else { 'persona' }
        $secret = Resolve-DwPersonaSecret -Account $a -Secrets $Secrets
        if (-not $secret) {
            $probes += [ordered]@{ name = "persona[$role]"; result = 'FAIL'; value = $null
                detail = "no secret: secretEnv '$($a.secretEnv)' is $(Format-DwMaskedSecret $null) and secretKey '$($a.secretKey)' is not in the secrets file" }
            continue
        }
        if (-not $a.username) {
            $probes += [ordered]@{ name = "persona[$role]"; result = 'FAIL'; detail = 'account carries no username'; value = $null }
            continue
        }
        $idPath = if ($a.identityPath) { "$($a.identityPath)" } elseif ($Personas.identityPath) { "$($Personas.identityPath)" } else { $null }
        $c = Connect-DwPersona -BaseUrl $BaseUrl -Login $Personas.login -Username "$($a.username)" -Secret $secret `
            -Role $role -IdentityPath $idPath -IdentityContains "$($a.identityContains)" `
            -TimeoutSec $TimeoutSec -SkipCertificateCheck:$SkipCertificateCheck
        $probes += [ordered]@{
            name = "persona[$role]"; result = $(if ($c.ok) { 'PASS' } else { 'FAIL' })
            detail = $c.detail; value = [bool]$c.identityAsserted
        }
    }
    return $probes
}

# Runs both checks over a parsed config and returns the result object.
# ZERO PROBES IS FAIL.
function Invoke-DwDemoStorylineCheck {
    param(
        [Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$BaseUrl,
        $Secrets, [int]$TimeoutSec = 30, [switch]$SkipCertificateCheck
    )
    $regex = if ($Config.placeholderRegex) { "$($Config.placeholderRegex)" } else { $script:DefaultPlaceholderRegex }
    $probes = @()
    if ($Config.pages) {
        $probes += Test-DwStorylinePages -BaseUrl $BaseUrl -Pages $Config.pages -PlaceholderRegex $regex `
            -TimeoutSec $TimeoutSec -SkipCertificateCheck:$SkipCertificateCheck
    }
    if ($Config.personas -and $Config.personas.accounts) {
        $probes += Test-DwPersonaLogins -BaseUrl $BaseUrl -Personas $Config.personas -Secrets $Secrets `
            -TimeoutSec $TimeoutSec -SkipCertificateCheck:$SkipCertificateCheck
    }
    $failed = @($probes | Where-Object { $_.result -eq 'FAIL' })
    if (@($probes).Count -eq 0) {
        return [ordered]@{ status = 'FAIL'; baseUrl = $BaseUrl; probes = @()
            detail = 'zero probes ran: the config declares no pages[] and no personas.accounts[]. Nothing measured is not a pass.' }
    }
    return [ordered]@{
        status = $(if ($failed.Count) { 'FAIL' } else { 'PASS' })
        baseUrl = $BaseUrl
        probes = @($probes)
        detail = "$(@($probes).Count - $failed.Count)/$(@($probes).Count) probe(s) passed"
    }
}

function Invoke-Main {
    $result = [ordered]@{ status = 'UNRUNNABLE'; baseUrl = $BaseUrl; probes = @(); detail = '' }
    $emit = {
        param($r, $code)
        $json = $r | ConvertTo-Json -Depth 8
        if ($OutFile) { $json | Set-Content -Path $OutFile -Encoding utf8NoBOM }
        Write-Output $json
        exit $code
    }
    if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) {
        $result.detail = "No config. Pass -ConfigPath <file>; the shape is in this script's help and in the skill's SKILL.md."
        & $emit $result 2
    }
    try { $config = Get-Content $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json }
    catch { $result.detail = "config '$ConfigPath' is not valid JSON: $($_.Exception.Message)"; & $emit $result 2 }

    $base = if ($BaseUrl) { $BaseUrl } elseif ($config.baseUrl) { "$($config.baseUrl)" } else { $env:DW_BASE_URL }
    if (-not $base) {
        $result.detail = 'No base URL. Set config.baseUrl, pass -BaseUrl, or set $env:DW_BASE_URL. There is no default host.'
        & $emit $result 2
    }
    $base = $base.TrimEnd('/')
    # Proves the shared module loaded and a connection is resolved; a blocked import
    # fails here rather than silently comparing against empty output.
    Connect-Dw -BaseUrl $base -AllowSelfSignedCertificate:$AllowSelfSignedCertificate | Out-Null
    Assert-DwConnection | Out-Null

    $secrets = $null
    if ($SecretsPath) {
        if (-not (Test-Path $SecretsPath)) { $result.detail = "secrets file '$SecretsPath' not found"; & $emit $result 2 }
        try { $secrets = Get-Content $SecretsPath -Raw -Encoding utf8 | ConvertFrom-Json }
        catch { $result.detail = "secrets file '$SecretsPath' is not valid JSON"; & $emit $result 2 }
    }
    $skipCert = $AllowSelfSignedCertificate -or ($base -match '^https?://(localhost|127\.0\.0\.1)([:/]|$)')
    $result = Invoke-DwDemoStorylineCheck -Config $config -BaseUrl $base -Secrets $secrets `
        -TimeoutSec $TimeoutSec -SkipCertificateCheck:$skipCert
    & $emit $result $(if ($result.status -eq 'PASS') { 0 } else { 1 })
}

# Dot-sourcing loads the functions and runs nothing (that is how the Pester suite
# covers the pure parts); invoking the file runs the check.
if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }
