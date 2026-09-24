<#
.SYNOPSIS
    WRITES: nothing on import. Shared Dynamics 365 Finance and Operations (F&O) connection module for the
    dw-demo-fo scripts; each exported function states its own read/write behaviour.

.DESCRIPTION
    One implementation of the plumbing every F&O demo-company script needs: connection discovery, an
    access token that renews itself, and an OData call with throttling retry.

    Owning reference: dw-demo-fo/references/connection-modes.md ("Access for the scripts").

    Connection discovery, in this order, per value:
      EnvironmentUrl  parameter, then $env:FO_ENV_URL
      TenantId        parameter, then $env:FO_TENANT_ID
      ClientId        parameter, then $env:FO_CLIENT_ID
      CachePath       parameter, then $env:FO_TOKEN_CACHE
      Token           parameter, then $env:FO_TOKEN (a ready bearer token; it is not renewed)

    Token sources, first match wins:
      1. a ready token (-Token or $env:FO_TOKEN), used as is;
      2. client credentials, when $env:FO_CLIENT_SECRET is set (the secret is read from the environment
         only, never from a parameter or a file);
      3. a delegated refresh token cached by Connect-FoDeviceCode.ps1 at CachePath, protected with Windows
         DPAPI for the current user. Every renewal rotates the cached refresh token.

    Traps encoded here:
      - A copy or a repair run outlives a one-hour access token: tokens are renewed five minutes before
        expiry on every call, never cached for the whole run.
      - HTTP 429 is service protection, shared by every demo on the tenant: honour Retry-After, retry up to
        five times, never tighten the loop.
      - A $count reply carries a UTF-8 BOM; Get-FoCount trims it before the cast to int.
      - A count without cross-company=true answers for the identity's DEFAULT company; Get-FoCount and
        Get-FoCompanyRows always send cross-company=true plus the dataAreaId filter.
      - Tokens and secrets are never written to the output or a log line.

.EXAMPLE
    Import-Module (Join-Path $PSScriptRoot 'Fo.Api.psm1') -Force -ErrorAction Stop
    Initialize-FoConnection -EnvironmentUrl https://<env>.operations.dynamics.com -TenantId <tenant-id> -ClientId <client-id>
    Get-FoCount -EntitySet CustomersV3 -Company ABC
#>
#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Fo = @{
    EnvironmentUrl = $null; TenantId = $null; ClientId = $null; CachePath = $null
    StaticToken = $null; AccessToken = $null; Expires = [datetime]::MinValue
}

function Protect-FoCacheValue {
    # DPAPI, current user. Stored as hex of the protected UTF-16LE bytes: the same format as
    # ConvertFrom-SecureString, so a cache written by either can be read by either.
    param([Parameter(Mandatory)][string]$Value)
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($Value)
    $protected = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'CurrentUser')
    [System.Convert]::ToHexString($protected)
}

function Unprotect-FoCacheValue {
    param([Parameter(Mandatory)][string]$Hex)
    $protected = [System.Convert]::FromHexString($Hex.Trim())
    [System.Text.Encoding]::Unicode.GetString(
        [System.Security.Cryptography.ProtectedData]::Unprotect($protected, $null, 'CurrentUser'))
}

function Save-FoRefreshToken {
    <# .SYNOPSIS WRITES: the DPAPI-protected refresh-token cache file. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$RefreshToken)
    $dir = Split-Path -Parent $Path
    # -WhatIf:$false: a caller's dry run must still keep the rotated token, or the next renewal fails.
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false | Out-Null }
    Set-Content -LiteralPath $Path -Value (Protect-FoCacheValue -Value $RefreshToken) -NoNewline -Encoding utf8NoBOM -WhatIf:$false
}

function Initialize-FoConnection {
    <#
    .SYNOPSIS
        READ-ONLY. Resolve the connection values (parameter, then environment) and fail with the fix when one
        is missing.
    #>
    param(
        [string]$EnvironmentUrl = $env:FO_ENV_URL,
        [string]$TenantId = $env:FO_TENANT_ID,
        [string]$ClientId = $env:FO_CLIENT_ID,
        [string]$CachePath = $env:FO_TOKEN_CACHE,
        [string]$Token = $env:FO_TOKEN
    )
    if (-not $EnvironmentUrl) {
        throw 'No F&O environment: pass -EnvironmentUrl https://<env>.operations.dynamics.com or set $env:FO_ENV_URL.'
    }
    $script:Fo.EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')
    $script:Fo.TenantId = $TenantId
    $script:Fo.ClientId = $ClientId
    $script:Fo.CachePath = $CachePath
    $script:Fo.StaticToken = $Token
    $script:Fo.AccessToken = $null
    $script:Fo.Expires = [datetime]::MinValue
    if ($Token) { return }
    if (-not ($TenantId -and $ClientId)) {
        throw 'No F&O identity: pass -TenantId and -ClientId (or set $env:FO_TENANT_ID / $env:FO_CLIENT_ID), or set $env:FO_TOKEN.'
    }
    if (-not $env:FO_CLIENT_SECRET -and -not ($CachePath -and (Test-Path -LiteralPath $CachePath))) {
        throw ('No F&O credential: set $env:FO_CLIENT_SECRET for an S2S app, or sign in once with ' +
               'pwsh -NoProfile -File scripts/Connect-FoDeviceCode.ps1 -CachePath <file> and pass the same -CachePath.')
    }
}

function Get-FoEnvironmentUrl {
    <# .SYNOPSIS READ-ONLY. The environment URL resolved by Initialize-FoConnection. #>
    param()
    if (-not $script:Fo.EnvironmentUrl) { throw 'Call Initialize-FoConnection first.' }
    $script:Fo.EnvironmentUrl
}

function Get-FoAccessToken {
    <#
    .SYNOPSIS
        WRITES: the rotated refresh token into the cache file when the delegated route is used; nothing in F&O.
        Returns a bearer token valid for at least five more minutes.
    #>
    param()
    if ($script:Fo.StaticToken) { return $script:Fo.StaticToken }
    if ($script:Fo.AccessToken -and (Get-Date) -lt $script:Fo.Expires) { return $script:Fo.AccessToken }
    $tokenUrl = "https://login.microsoftonline.com/$($script:Fo.TenantId)/oauth2/v2.0/token"
    $scope = "$($script:Fo.EnvironmentUrl)/.default"
    if ($env:FO_CLIENT_SECRET) {
        $body = @{ grant_type = 'client_credentials'; client_id = $script:Fo.ClientId
                   client_secret = $env:FO_CLIENT_SECRET; scope = $scope }
    } else {
        $refresh = Unprotect-FoCacheValue -Hex (Get-Content -LiteralPath $script:Fo.CachePath -Raw)
        $body = @{ grant_type = 'refresh_token'; client_id = $script:Fo.ClientId
                   refresh_token = $refresh; scope = "$scope offline_access" }
    }
    $t = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded'
    if ($t.PSObject.Properties['refresh_token'] -and $t.refresh_token -and $script:Fo.CachePath -and -not $env:FO_CLIENT_SECRET) {
        Save-FoRefreshToken -Path $script:Fo.CachePath -RefreshToken $t.refresh_token
    }
    $script:Fo.AccessToken = $t.access_token
    $script:Fo.Expires = (Get-Date).AddSeconds([int]$t.expires_in - 300)
    $script:Fo.AccessToken
}

function Invoke-FoApi {
    <#
    .SYNOPSIS
        WRITES: whatever the request does (GET is read-only; POST, PATCH and DELETE write). The caller owns the
        dry-run gate.
    .PARAMETER Path
        Path under the environment root, starting with /data/.
    .PARAMETER Raw
        Return the response body as trimmed text (for $count replies).
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get', 'Post', 'Patch', 'Delete')][string]$Method = 'Get',
        $Body,
        [switch]$Raw,
        [int]$TimeoutSec = 180
    )
    $uri = (Get-FoEnvironmentUrl) + $Path
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $headers = @{ Authorization = "Bearer $(Get-FoAccessToken)"; Accept = 'application/json'; 'OData-MaxVersion' = '4.0' }
        $request = @{ Uri = $uri; Method = $Method; Headers = $headers; TimeoutSec = $TimeoutSec }
        if ($null -ne $Body) {
            $request.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 6 }
            $request.ContentType = 'application/json'
        }
        try {
            if ($Raw) {
                return (Invoke-WebRequest @request).Content.Trim([char]0xFEFF, ' ', "`r", "`n")
            }
            return Invoke-RestMethod @request
        } catch {
            $response = $_.Exception.PSObject.Properties['Response'] ? $_.Exception.Response : $null
            $status = if ($response) { [int]$response.StatusCode } else { 0 }
            if ($status -eq 429 -and $attempt -lt 5) {
                $wait = 30
                $retryAfter = $response.Headers.RetryAfter
                if ($retryAfter -and $retryAfter.Delta) { $wait = [int]$retryAfter.Delta.Value.TotalSeconds }
                Write-Warning "throttled (429); waiting ${wait}s"
                Start-Sleep -Seconds $wait
                continue
            }
            throw
        }
    }
}

function Get-FoErrorText {
    <# .SYNOPSIS READ-ONLY. The innermost F&O error message of a caught request error. #>
    param([Parameter(Mandatory)]$ErrorRecord)
    $text = $ErrorRecord.ErrorDetails.Message
    if (-not $text) { return $ErrorRecord.Exception.Message }
    $parsed = $text | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($parsed -and $parsed.PSObject.Properties['error']) {
        $e = $parsed.error
        if ($e.PSObject.Properties['innererror'] -and $e.innererror.PSObject.Properties['message']) { return $e.innererror.message }
        if ($e.PSObject.Properties['message']) { return $e.message }
    }
    if ($parsed -and $parsed.PSObject.Properties['Message']) { return $parsed.Message }
    $text
}

function Get-FoCount {
    <#
    .SYNOPSIS
        READ-ONLY. Row count of an entity set inside one company (cross-company=true plus the dataAreaId
        filter). Returns $null when the set is not readable on this build or not company-scoped.
    #>
    param(
        [Parameter(Mandatory)][string]$EntitySet,
        [Parameter(Mandatory)][string]$Company,
        [string]$CompanyField = 'dataAreaId'
    )
    $path = "/data/$EntitySet/`$count?cross-company=true&`$filter=$CompanyField eq '$Company'"
    try {
        [int](Invoke-FoApi -Path $path -Raw)
    } catch {
        Write-Warning ("{0}: {1} (not readable on this build, or not company-scoped)" -f $EntitySet, (Get-FoErrorText $_))
        $null
    }
}

function Get-FoCompanyRows {
    <# .SYNOPSIS READ-ONLY. All rows of a company-scoped entity set in one company, every page. #>
    param(
        [Parameter(Mandatory)][string]$EntitySet,
        [Parameter(Mandatory)][string]$Company,
        [string]$ExtraFilter
    )
    $filter = "dataAreaId eq '$Company'"
    if ($ExtraFilter) { $filter += " and $ExtraFilter" }
    $path = "/data/$EntitySet`?cross-company=true&`$filter=$filter"
    $rows = [System.Collections.Generic.List[object]]::new()
    while ($path) {
        $page = Invoke-FoApi -Path $path
        foreach ($r in $page.value) { $rows.Add($r) }
        $next = $page.PSObject.Properties['@odata.nextLink'] ? $page.'@odata.nextLink' : $null
        $path = if ($next) { $next.Substring((Get-FoEnvironmentUrl).Length) } else { $null }
    }
    , $rows.ToArray()
}

function ConvertFrom-FoExecutionErrors {
    <#
    .SYNOPSIS
        READ-ONLY. Parse the string GetExecutionErrors returns into RecordId / Field / ErrorMessage objects.
    .DESCRIPTION
        The action returns a JSON array serialised into a string, and the error messages inside it carry
        unescaped quotes and line breaks, so ConvertFrom-Json fails part-way through a large result. Split
        on the record boundary instead and read the three fields with one regex per record (measured on a
        3,506-row result, every record parsed).
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $body = $Text.Trim().TrimStart('[').TrimEnd(']').Trim()
    if (-not $body) { return @() }
    $rx = [regex]::new('^\{?"RecordId":"(?<r>.*?)","Field":"(?<f>.*?)","ErrorMessage":"(?<m>.*)"\s*\}?$', 'Singleline')
    foreach ($chunk in [regex]::Split($body, '\}\s*,\s*\{(?="RecordId")')) {
        $m = $rx.Match($chunk.Trim())
        if ($m.Success) {
            [pscustomobject]@{ RecordId = $m.Groups['r'].Value.Trim(); Field = $m.Groups['f'].Value
                               ErrorMessage = ($m.Groups['m'].Value -replace '\s+', ' ').Trim() }
        } else {
            [pscustomobject]@{ RecordId = $null; Field = $null; ErrorMessage = "unparsed: $($chunk.Trim())" }
        }
    }
}

function Get-FoExecutionErrors {
    <#
    .SYNOPSIS
        READ-ONLY. Row-level errors of one Data management execution (bound action GetExecutionErrors).
    .PARAMETER ExecutionId
        The JobId of DataManagementExecutionJobs / DataManagementExecutionJobDetails.
    #>
    param([Parameter(Mandatory)][string]$ExecutionId)
    $r = Invoke-FoApi -Method Post -Path '/data/DataManagementDefinitionGroups/Microsoft.Dynamics.DataEntities.GetExecutionErrors' -Body @{ executionId = $ExecutionId }
    ConvertFrom-FoExecutionErrors -Text ([string]$r.value)
}

function Get-FoExecutionStatus {
    <#
    .SYNOPSIS
        READ-ONLY. Summary status of one execution: Unknown, NotRun, Executing, Succeeded, PartiallySucceeded,
        Failed or Canceled (bound action GetExecutionSummaryStatus).
    #>
    param([Parameter(Mandatory)][string]$ExecutionId)
    (Invoke-FoApi -Method Post -Path '/data/DataManagementDefinitionGroups/Microsoft.Dynamics.DataEntities.GetExecutionSummaryStatus' -Body @{ executionId = $ExecutionId }).value
}

Export-ModuleMember -Function Initialize-FoConnection, Get-FoEnvironmentUrl, Get-FoAccessToken, Invoke-FoApi,
    Get-FoErrorText, Get-FoCount, Get-FoCompanyRows, Save-FoRefreshToken, ConvertFrom-FoExecutionErrors,
    Get-FoExecutionErrors, Get-FoExecutionStatus
