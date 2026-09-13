<#
.SYNOPSIS
    WRITES: a trial license on the target Dynamicweb install (the host drops a
    *.license file under Files). Activates a free Dynamicweb trial for a local site.

.DESCRIPTION
    Uses Dynamicweb's built-in /admin/license trial flow to issue a trial license and
    verifies that /admin is no longer redirected to /admin/license.
    Owning reference: dw-setup-install/SKILL.md (Degraded Path step 7).
    Traps encoded: the trial ids are scraped from the live license page (they are
    not stable), and success is proven by the redirect disappearing plus a *.license
    file that is new or rewritten by this run, not by the POST's response. A cloned
    Files tree already carries its source site's licence files, so "some *.license
    exists" passes before activation and names the wrong file.

.PARAMETER DynamicwebUrl
    Base URL of the Dynamicweb site, e.g. https://localhost:<port> — read the
    port from Dynamicweb.Host.Suite/Properties/launchSettings.json.

.PARAMETER FilesPath
    Optional path to the Dynamicweb Files folder. When supplied, the script records
    the *.license names and LastWriteTime before the POST, then requires a licence
    file that is new or rewritten after it and prints that file.

.PARAMETER TrialName
    Optional case-insensitive substring used to choose a specific trial by name.
    If omitted, the first available trial is selected.

.EXAMPLE
    pwsh -NoProfile -File scripts/activate-free-trial.ps1 -DynamicwebUrl "https://localhost:<port>" -FilesPath "C:\DwSolutions\Swift2\Files"
#>
#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DynamicwebUrl,
    [string]$FilesPath = "",
    [string]$TrialName = ""
)

$ErrorActionPreference = "Stop"

function Write-Status([string]$Message) {
    Write-Host "[trial] $Message" -ForegroundColor Cyan
}

function Write-Success([string]$Message) {
    Write-Host "[trial] $Message" -ForegroundColor Green
}

function Invoke-DwWebRequest {
    param(
        [string]$Uri,
        [string]$Method = "Get",
        [string]$Body = "",
        [string]$ContentType = ""
    )

    $params = @{
        Uri = $Uri
        Method = $Method
        SkipCertificateCheck = $true
    }

    if ($Body) {
        $params["Body"] = $Body
    }

    if ($ContentType) {
        $params["ContentType"] = $ContentType
    }

    return Invoke-WebRequest @params
}

function Get-TrialsFromHtml {
    param(
        [string]$Html
    )

    $trials = @()
    $trialNodes = [regex]::Matches(
        $Html,
        '<input(?<input>[^>]*)>\s*<label[^>]*>\s*(?<name>.*?)\s*</label>',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)

    foreach ($match in $trialNodes) {
        $inputMarkup = $match.Groups["input"].Value
        if ($inputMarkup -notmatch 'name="trialId"') {
            continue
        }

        if ($inputMarkup -notmatch 'value="(?<id>[^"]+)"') {
            continue
        }

        $trialId = $Matches["id"]

        $trials += [pscustomobject]@{
            Id = $trialId
            Name = [System.Text.RegularExpressions.Regex]::Replace($match.Groups["name"].Value, '\s+', ' ').Trim()
        }
    }

    return $trials
}

function Get-LicenseSnapshot {
    param(
        [string]$RootFilesPath
    )

    $snapshot = @{}
    if ($RootFilesPath) {
        Get-ChildItem -Path $RootFilesPath -Filter "*.license" -File -ErrorAction SilentlyContinue |
            ForEach-Object { $snapshot[$_.Name] = $_.LastWriteTimeUtc }
    }
    return $snapshot
}

function Test-LicenseReady {
    param(
        [string]$BaseUrl,
        [string]$RootFilesPath,
        [hashtable]$Before
    )

    $response = Invoke-DwWebRequest -Uri "$BaseUrl/admin"
    $finalUrl = $response.BaseResponse.ResponseUri.AbsoluteUri

    if ($finalUrl -match '/admin/license($|[/?#])') {
        throw "Dynamicweb is still redirecting to /admin/license after trial activation."
    }

    if ($RootFilesPath) {
        # Only a licence file this run created or rewrote proves activation: a clone
        # carries the source site's licence files, which were there before the POST.
        $changed = @(Get-ChildItem -Path $RootFilesPath -Filter "*.license" -File -ErrorAction SilentlyContinue |
            Where-Object { -not $Before.ContainsKey($_.Name) -or $_.LastWriteTimeUtc -gt $Before[$_.Name] } |
            Sort-Object LastWriteTimeUtc -Descending)
        if ($changed.Count -eq 0) {
            $existing = if ($Before.Count) { $Before.Keys -join ', ' } else { 'none' }
            throw "Dynamicweb admin is reachable, but no *.license file in $RootFilesPath was created or rewritten by this activation (files before the POST: $existing). Check that -FilesPath is this site's own Files folder."
        }

        foreach ($file in $changed) {
            $state = if ($Before.ContainsKey($file.Name)) { 'rewritten' } else { 'created' }
            Write-Success "License file ${state}: $($file.FullName) (LastWriteTime $($file.LastWriteTime))"
        }
    }

    Write-Success "Dynamicweb admin is licensed and reachable: $finalUrl"
}

$trialUrl = "$DynamicwebUrl/admin/license/TrialInstallStep"
Write-Status "Loading available trial types from: $trialUrl"
$trialPage = Invoke-DwWebRequest -Uri $trialUrl
$trials = Get-TrialsFromHtml -Html $trialPage.Content

if (-not $trials -or $trials.Count -eq 0) {
    throw "No trial types were found on the Dynamicweb license page."
}

$selectedTrial = $null
if ($TrialName) {
    $selectedTrial = $trials | Where-Object { $_.Name -like "*$TrialName*" } | Select-Object -First 1
    if (-not $selectedTrial) {
        throw "No Dynamicweb trial matched '$TrialName'. Available trials: $($trials.Name -join ', ')"
    }
}
else {
    $selectedTrial = $trials | Select-Object -First 1
}

$licensesBefore = Get-LicenseSnapshot -RootFilesPath $FilesPath
if ($FilesPath) {
    Write-Status "Licence files before activation: $(if ($licensesBefore.Count) { $licensesBefore.Keys -join ', ' } else { 'none' })"
}

Write-Status "Requesting free trial '$($selectedTrial.Name)' ($($selectedTrial.Id))"
$body = "trialId=$([uri]::EscapeDataString($selectedTrial.Id))"
$response = Invoke-DwWebRequest -Uri $trialUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
$finalUrl = $response.BaseResponse.ResponseUri.AbsoluteUri

if ($finalUrl -notmatch '/admin/license/TrialReadyStep($|[/?#])' -and
    $finalUrl -notmatch '/admin($|[/?#])' -and
    $finalUrl -notmatch '/admin/authentication/login') {
    Write-Status "Trial request returned: $finalUrl"
}

Test-LicenseReady -BaseUrl $DynamicwebUrl -RootFilesPath $FilesPath -Before $licensesBefore

Write-Host ""
Write-Host "Free trial activation complete" -ForegroundColor Green
Write-Host "  Dynamicweb URL : $DynamicwebUrl" -ForegroundColor Green
Write-Host "  Trial          : $($selectedTrial.Name)" -ForegroundColor Green
if ($FilesPath) {
    Write-Host "  Files path     : $FilesPath" -ForegroundColor Green
}
Write-Host ""
