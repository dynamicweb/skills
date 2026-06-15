<#
.SYNOPSIS
    Activates a free Dynamicweb trial license for a local site.

.DESCRIPTION
    Uses Dynamicweb's built-in /admin/license trial flow to issue a trial license and
    verifies that /admin is no longer redirected to /admin/license.

.PARAMETER DynamicwebUrl
    Base URL of the Dynamicweb site (e.g. https://localhost:5001).

.PARAMETER FilesPath
    Optional path to the Dynamicweb Files folder. When supplied, the script also
    verifies that a *.license file exists after activation.

.PARAMETER TrialName
    Optional case-insensitive substring used to choose a specific trial by name.
    If omitted, the first available trial is selected.
#>

[CmdletBinding()]
param(
    [string]$DynamicwebUrl = "https://localhost:5001",
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

    if ($PSVersionTable.PSVersion.Major -ge 7) {
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

    $bodyFile = [System.IO.Path]::GetTempFileName()
    try {
        $writeOut = "__CURL_META__%{url_effective}|%{content_type}|%{http_code}"
        $args = @("-k", "-sS", "-L", "-o", $bodyFile, "-w", $writeOut, "-X", $Method)

        if ($ContentType) {
            $args += @("-H", "Content-Type: $ContentType")
        }

        if ($Body) {
            $args += @("--data", $Body)
        }

        $args += $Uri
        $rawOutput = & curl.exe @args
        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe failed while calling $Uri"
        }

        $content = Get-Content -Path $bodyFile -Raw
        if ($rawOutput -notmatch '__CURL_META__(?<url>[^|]*)\|(?<contentType>[^|]*)\|(?<statusCode>\d+)$') {
            throw "Could not parse curl.exe response metadata for $Uri"
        }

        return [pscustomobject]@{
            Content = $content
            Headers = @{
                "Content-Type" = $matches["contentType"]
            }
            StatusCode = [int]$matches["statusCode"]
            BaseResponse = [pscustomobject]@{
                ResponseUri = [Uri]$matches["url"]
            }
        }
    }
    finally {
        if (Test-Path $bodyFile) {
            Remove-Item -Path $bodyFile -Force
        }
    }
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

function Test-LicenseReady {
    param(
        [string]$BaseUrl,
        [string]$RootFilesPath
    )

    $response = Invoke-DwWebRequest -Uri "$BaseUrl/admin"
    $finalUrl = $response.BaseResponse.ResponseUri.AbsoluteUri

    if ($finalUrl -match '/admin/license($|[/?#])') {
        throw "Dynamicweb is still redirecting to /admin/license after trial activation."
    }

    if ($RootFilesPath) {
        $licenseFile = Get-ChildItem -Path $RootFilesPath -Filter "*.license" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $licenseFile) {
            throw "Dynamicweb admin is reachable, but no *.license file was found in $RootFilesPath."
        }

        Write-Success "License file created: $($licenseFile.FullName)"
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

Write-Status "Requesting free trial '$($selectedTrial.Name)' ($($selectedTrial.Id))"
$body = "trialId=$([uri]::EscapeDataString($selectedTrial.Id))"
$response = Invoke-DwWebRequest -Uri $trialUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
$finalUrl = $response.BaseResponse.ResponseUri.AbsoluteUri

if ($finalUrl -notmatch '/admin/license/TrialReadyStep($|[/?#])' -and
    $finalUrl -notmatch '/admin($|[/?#])' -and
    $finalUrl -notmatch '/admin/authentication/login') {
    Write-Status "Trial request returned: $finalUrl"
}

Test-LicenseReady -BaseUrl $DynamicwebUrl -RootFilesPath $FilesPath

Write-Host ""
Write-Host "Free trial activation complete" -ForegroundColor Green
Write-Host "  Dynamicweb URL : $DynamicwebUrl" -ForegroundColor Green
Write-Host "  Trial          : $($selectedTrial.Name)" -ForegroundColor Green
if ($FilesPath) {
    Write-Host "  Files path     : $FilesPath" -ForegroundColor Green
}
Write-Host ""
