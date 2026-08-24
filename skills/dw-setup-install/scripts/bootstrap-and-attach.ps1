<#
.SYNOPSIS
    Bootstraps a Dynamicweb MCP configuration and writes MCP client config.

.DESCRIPTION
    Reads Files/System/mcp-bootstrap.json, calls /admin/mcp/bootstrap, persists
    the response safely outside the repo, writes or updates the local MCP client
    config for Claude Code or Codex, and validates connectivity.

.PARAMETER DynamicwebUrl
    Base URL of the Dynamicweb site (e.g. https://localhost:5001).

.PARAMETER FilesPath
    Path to the Dynamicweb Files folder that contains System/mcp-bootstrap.json.

.PARAMETER ConfigurationName
    Name for the MCP configuration.

.PARAMETER PermissionPreset
    Permission preset: All, NonDestructive, or ReadOnly.

.PARAMETER CredentialsPath
    Where to save the credentials file.

.PARAMETER McpConfigTarget
    Which MCP client config to write: claude or codex.

.PARAMETER SkipAttach
    Skip writing MCP client config and only bootstrap plus save credentials.

.PARAMETER ResumeFromCredentials
    Path to an existing credentials file to resume from.
#>

[CmdletBinding()]
param(
    [string]$DynamicwebUrl = "https://localhost:5001",
    [string]$FilesPath = "C:\DwSolutions\Swift2\Files",
    [string]$ConfigurationName = "Dynamicweb MCP",
    [ValidateSet("All", "NonDestructive", "ReadOnly")]
    [string]$PermissionPreset = "All",
    [string]$CredentialsPath = "$env:TEMP\dw-mcp-credentials.json",
    [ValidateSet("claude", "codex")]
    [string]$McpConfigTarget = "claude",
    [switch]$SkipAttach,
    [string]$ResumeFromCredentials = ""
)

$ErrorActionPreference = "Stop"

function Write-Status([string]$Message) {
    Write-Host "[bootstrap] $Message" -ForegroundColor Cyan
}

function Write-Success([string]$Message) {
    Write-Host "[bootstrap] $Message" -ForegroundColor Green
}

function Write-Fail([string]$Message) {
    Write-Host "[bootstrap] $Message" -ForegroundColor Red
}

function Invoke-DwWebRequest {
    param(
        [string]$Uri,
        [string]$Method = "Get",
        [hashtable]$Headers,
        [string]$Body,
        [string]$ContentType = ""
    )

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $params = @{
            Uri = $Uri
            Method = $Method
            SkipCertificateCheck = $true
        }

        if ($Headers) {
            $params["Headers"] = $Headers
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
    $requestBodyFile = $null
    try {
        $writeOut = "__CURL_META__%{url_effective}|%{content_type}|%{http_code}"
        $args = @("-k", "-sS", "-L", "-o", $bodyFile, "-w", $writeOut, "-X", $Method)

        if ($Headers) {
            foreach ($header in $Headers.GetEnumerator()) {
                $args += @("-H", "$($header.Key): $($header.Value)")
            }
        }

        if ($ContentType) {
            $args += @("-H", "Content-Type: $ContentType")
        }

        if ($Body) {
            $requestBodyFile = [System.IO.Path]::GetTempFileName()
            Set-Content -Path $requestBodyFile -Value $Body -Encoding UTF8
            $args += @("--data-binary", "@$requestBodyFile")
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

        if ($requestBodyFile -and (Test-Path $requestBodyFile)) {
            Remove-Item -Path $requestBodyFile -Force
        }
    }
}

function Test-LicenseInstalled {
    param(
        [string]$BaseUrl
    )

    $adminUrl = "$BaseUrl/admin"
    Write-Status "Checking Dynamicweb admin readiness: $adminUrl"
    $response = Invoke-DwWebRequest -Uri $adminUrl
    $finalUrl = $response.BaseResponse.ResponseUri.AbsoluteUri

    if ($finalUrl -match '/admin/license($|[/?#])') {
        throw "Dynamicweb is redirecting to /admin/license. Install a license first, or run activate-free-trial.ps1 before bootstrap."
    }

    Write-Success "Dynamicweb admin is licensed and reachable: $finalUrl"
}

function Get-BootstrapCredentials {
    param(
        [string]$BaseUrl,
        [string]$RootFilesPath,
        [string]$ConfigName,
        [string]$Preset
    )

    $manifestPath = Join-Path $RootFilesPath "System\mcp-bootstrap.json"
    if (-not (Test-Path $manifestPath)) {
        throw "Bootstrap manifest not found at: $manifestPath"
    }

    Write-Status "Reading bootstrap manifest from: $manifestPath"
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

    if (-not $manifest.secret) {
        throw "Bootstrap manifest is missing the secret field."
    }

    $expiresUtc = [DateTime]::Parse($manifest.expiresUtc).ToUniversalTime()
    if ($expiresUtc -le [DateTime]::UtcNow) {
        throw "Bootstrap secret has expired (expired: $expiresUtc). Re-run the installer or reset-mcp-bootstrap-manifest.ps1."
    }

    Write-Status "Bootstrap secret valid until: $expiresUtc"

    $bootstrapUrl = "$BaseUrl/admin/mcp/bootstrap"
    $body = @{
        secret = $manifest.secret
        configurationName = $ConfigName
        configurationDescription = "Bootstrapped by bootstrap-and-attach.ps1"
        permissionPreset = $Preset
    } | ConvertTo-Json -Depth 5

    Write-Status "Calling bootstrap endpoint: $bootstrapUrl"
    Test-LicenseInstalled -BaseUrl $BaseUrl

    try {
        $response = Invoke-DwWebRequest -Uri $bootstrapUrl -Method Post -Body $body -ContentType "application/json"
        $contentType = [string]$response.Headers["Content-Type"]
        $parsedResponse = $null

        if ($contentType -match 'application/json' -and $response.Content) {
            try {
                $parsedResponse = $response.Content | ConvertFrom-Json
            }
            catch {
                if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                    throw
                }
            }
        }

        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
            $serverError = if ($parsedResponse -and $parsedResponse.error) {
                $parsedResponse.error
            }
            elseif ($response.Content) {
                $response.Content
            }
            else {
                "Dynamicweb returned HTTP $($response.StatusCode) without a response body."
            }

            switch ($response.StatusCode) {
                403 { throw "Bootstrap returned 403 Forbidden. $serverError" }
                409 { throw "Bootstrap returned 409 Conflict. $serverError" }
                default { throw "Bootstrap failed with HTTP $($response.StatusCode). $serverError" }
            }
        }

        if ($contentType -notmatch 'application/json') {
            throw "Bootstrap returned unexpected content type '$contentType'. This usually means Dynamicweb returned HTML instead of bootstrap JSON."
        }

        $credentials = if ($parsedResponse) { $parsedResponse } else { $response.Content | ConvertFrom-Json }
        if ($credentials.error) {
            throw "Bootstrap failed: $($credentials.error)"
        }

        if (-not $credentials.BearerToken -or -not $credentials.ConfigurationId -or -not $credentials.ConfigurationName) {
            throw "Bootstrap returned JSON, but mandatory fields were missing. Refusing to write MCP config."
        }

        return $credentials
    }
    catch {
        if ($_.Exception.Message) {
            throw
        }

        throw "Bootstrap failed for an unknown reason."
    }
}

function Save-CredentialsFile {
    param(
        [object]$Credentials,
        [string]$BaseUrl,
        [string]$Path
    )

    $credentialData = [ordered]@{
        BearerToken = $Credentials.BearerToken
        ConfigurationId = $Credentials.ConfigurationId
        ConfigurationName = $Credentials.ConfigurationName
        ServiceUserName = $Credentials.ServiceUserName
        ServiceUserPassword = $Credentials.ServiceUserPassword
        PermissionPreset = $Credentials.PermissionPreset
        GrantedToolCount = $Credentials.GrantedToolCount
        DynamicwebUrl = $BaseUrl
        CreatedUtc = [DateTime]::UtcNow.ToString("o")
    }

    $credentialData | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
    Write-Success "Credentials saved to: $Path"
}

function Write-ClaudeConfig {
    param(
        [string]$Endpoint,
        [string]$Token
    )

    $projectMcpPath = ".mcp.json"
    $mcpConfig = @{}

    if (Test-Path $projectMcpPath) {
        try {
            $mcpConfig = Get-Content $projectMcpPath -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            $mcpConfig = @{}
        }
    }

    if (-not $mcpConfig.ContainsKey("mcpServers")) {
        $mcpConfig["mcpServers"] = @{}
    }

    $mcpConfig["mcpServers"]["dynamicweb"] = @{
        type = "streamable-http"
        url = $Endpoint
        headers = @{
            Authorization = "Bearer $Token"
        }
    }

    $mcpConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $projectMcpPath -Encoding UTF8
    Write-Success "Wrote MCP config to: $projectMcpPath"
}

function Write-CodexConfig {
    param(
        [string]$Endpoint,
        [string]$Token
    )

    $codexConfigDir = ".codex"
    $codexConfigPath = Join-Path $codexConfigDir "config.toml"

    if (-not (Test-Path $codexConfigDir)) {
        New-Item -ItemType Directory -Path $codexConfigDir -Force | Out-Null
    }

    $configContent = ""
    if (Test-Path $codexConfigPath) {
        $configContent = Get-Content $codexConfigPath -Raw
    }

    $tomlBlock = @(
        "",
        "[mcp_servers.dynamicweb]",
        'type = "streamable-http"',
        "url = `"$Endpoint`"",
        "",
        "[mcp_servers.dynamicweb.headers]",
        "Authorization = `"Bearer $Token`""
    ) -join "`n"

    if ($configContent -match '\[mcp_servers\.dynamicweb\]') {
        $configContent = $configContent -replace '(?s)\[mcp_servers\.dynamicweb\].*?(?=(\r?\n\[)|$)', ''
    }

    $configContent = $configContent.TrimEnd()
    if ($configContent.Length -gt 0) {
        $configContent += "`n"
    }
    $configContent += $tomlBlock.TrimStart("`r", "`n")

    Set-Content -Path $codexConfigPath -Value $configContent -Encoding UTF8
    Write-Success "Wrote MCP config to: $codexConfigPath"
}

function Test-McpConnectivity {
    param(
        [string]$BaseUrl,
        [string]$Token
    )

    Write-Status "Validating MCP connectivity..."

    $headers = @{
        Authorization = "Bearer $Token"
        "Content-Type" = "application/json"
        Accept = "application/json"
    }

    $initBody = @{
        jsonrpc = "2.0"
        id = 1
        method = "initialize"
        params = @{
            protocolVersion = "2025-03-26"
            capabilities = @{}
            clientInfo = @{
                name = "bootstrap-validator"
                version = "1.0.0"
            }
        }
    } | ConvertTo-Json -Depth 10

    $testUrl = "$BaseUrl/admin/mcp"

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $response = Invoke-RestMethod -Uri $testUrl -Method Post -Headers $headers -Body $initBody -SkipCertificateCheck
    }
    else {
        $response = Invoke-RestMethod -Uri $testUrl -Method Post -Headers $headers -Body $initBody
    }

    if ($response.result) {
        Write-Success "MCP connectivity validated. Server: $($response.result.serverInfo.name) v$($response.result.serverInfo.version)"
        return
    }

    Write-Status "MCP responded but initialize returned an unexpected result."
}

function Write-StatusFile {
    param(
        [object]$Credentials,
        [string]$BaseUrl,
        [string]$Path,
        [string]$ConfigTarget,
        [bool]$ConfigWritten
    )

    $statusPath = Join-Path (Split-Path $Path) "dw-mcp-bootstrap-status.json"
    $statusData = [ordered]@{
        status = "complete"
        dynamicwebUrl = $BaseUrl
        mcpEndpoint = "$BaseUrl/admin/mcp"
        configurationName = $Credentials.ConfigurationName
        credentialsFile = $Path
        mcpConfigTarget = $ConfigTarget
        mcpConfigWritten = $ConfigWritten
        validatedAt = [DateTime]::UtcNow.ToString("o")
    }

    $statusData | ConvertTo-Json -Depth 5 | Set-Content -Path $statusPath -Encoding UTF8
    Write-Success "Status file written: $statusPath"
    return $statusPath
}

try {
    $credentials = $null

    if ($ResumeFromCredentials -and (Test-Path $ResumeFromCredentials)) {
        Write-Status "Resuming from existing credentials: $ResumeFromCredentials"
        $credentials = Get-Content $ResumeFromCredentials -Raw | ConvertFrom-Json
        if (-not $credentials.BearerToken) {
            throw "Credentials file is missing BearerToken. Cannot resume."
        }

        Write-Success "Loaded credentials for configuration: $($credentials.ConfigurationName)"
    }
    else {
        $credentials = Get-BootstrapCredentials -BaseUrl $DynamicwebUrl -RootFilesPath $FilesPath -ConfigName $ConfigurationName -Preset $PermissionPreset
        Write-Success "Bootstrap successful. Configuration: $($credentials.ConfigurationName). Tools granted: $($credentials.GrantedToolCount)"
        Save-CredentialsFile -Credentials $credentials -BaseUrl $DynamicwebUrl -Path $CredentialsPath
    }

    $effectiveUrl = if ($credentials.DynamicwebUrl) { $credentials.DynamicwebUrl } else { $DynamicwebUrl }
    $bearerToken = $credentials.BearerToken

    if (-not $bearerToken) {
        throw "Bootstrap did not return a bearer token. Refusing to attach an invalid MCP configuration."
    }

    if (-not $SkipAttach) {
        switch ($McpConfigTarget) {
            "claude" {
                Write-Status "Writing MCP server config for Claude Code..."
                Write-ClaudeConfig -Endpoint "$effectiveUrl/admin/mcp" -Token $bearerToken
            }
            "codex" {
                Write-Status "Writing MCP server config for Codex..."
                Write-CodexConfig -Endpoint "$effectiveUrl/admin/mcp" -Token $bearerToken
            }
        }
    }
    else {
        Write-Status "Skipping MCP client config (--SkipAttach)"
    }

    Test-McpConnectivity -BaseUrl $effectiveUrl -Token $bearerToken
    $statusPath = Write-StatusFile -Credentials $credentials -BaseUrl $effectiveUrl -Path $CredentialsPath -ConfigTarget $McpConfigTarget -ConfigWritten (-not $SkipAttach)

    Write-Host ""
    Write-Host "Bootstrap and attach complete" -ForegroundColor Green
    Write-Host "  Dynamicweb URL : $effectiveUrl" -ForegroundColor Green
    Write-Host "  MCP Endpoint   : $effectiveUrl/admin/mcp" -ForegroundColor Green
    Write-Host "  Config Target  : $McpConfigTarget" -ForegroundColor Green
    Write-Host "  Credentials    : $CredentialsPath" -ForegroundColor Green
    Write-Host "  Status         : $statusPath" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Fail $_.Exception.Message
    exit 1
}
