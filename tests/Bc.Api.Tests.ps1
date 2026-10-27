BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module (Join-Path (Get-RepoRoot) 'skills/dw-integration-bc/scripts/Bc.Api.psm1') -Force -ErrorAction Stop
    $script:OldToken = $env:BC_ACCESS_TOKEN
    $script:OldSecret = $env:BC_CLIENT_SECRET
    $env:BC_ACCESS_TOKEN = 'unit-test-bearer'
    $script:Tenant = '00000000-0000-0000-0000-000000000001'
    $script:Company = '00000000-0000-0000-0000-000000000011'
}

AfterAll {
    $env:BC_ACCESS_TOKEN = $script:OldToken
    $env:BC_CLIENT_SECRET = $script:OldSecret
    Remove-Module Bc.Api -ErrorAction SilentlyContinue
    Remove-Variable BcReplies, BcUris, BcSleeps -Scope Global -ErrorAction SilentlyContinue
}

Describe 'BC read-only company and transport contract' {
    BeforeEach {
        $global:BcReplies = [System.Collections.Generic.Queue[object]]::new()
        $global:BcUris = [System.Collections.Generic.List[string]]::new()
        $global:BcSleeps = [System.Collections.Generic.List[int]]::new()
        Mock Invoke-WebRequest -ModuleName Bc.Api {
            param($Uri)
            $global:BcUris.Add([string]$Uri)
            if ($global:BcReplies.Count -eq 0) { throw 'Unplanned network call' }
            $global:BcReplies.Dequeue()
        }
        Mock Invoke-RestMethod -ModuleName Bc.Api { throw 'Unplanned token request' }
        Mock Start-Sleep -ModuleName Bc.Api { param($Seconds) $global:BcSleeps.Add($Seconds) }
        Initialize-BcConnection -TenantId $script:Tenant -Environment Sandbox -CompanyIds $script:Company
    }

    It 'pins the company and limits a sample without following extra pages' {
        $global:BcReplies.Enqueue(@{StatusCode = 200; Content = '{"value":[{"number":"ONE"},{"number":"TWO"}],"@odata.nextLink":"https://foreign.invalid/next"}'; Headers = @{}})
        $rows = @(Get-BcCollection -CompanyId $script:Company -Resource items -SampleSize 1)
        $rows.Count | Should -Be 1
        $rows[0].number | Should -Be ONE
        $global:BcUris[0] | Should -Match ([regex]::Escape("companies($script:Company)/items"))
        $global:BcUris.Count | Should -Be 1
    }

    It 'rejects a company outside the selected allowlist before HTTP' {
        { Get-BcCollection -CompanyId '00000000-0000-0000-0000-000000000012' -Resource items } | Should -Throw '*allowlist*'
        $global:BcUris.Count | Should -Be 0
    }

    It 'reads every page in a full collection' {
        $next = "https://api.businesscentral.dynamics.com/v2.0/$script:Tenant/Sandbox/api/v2.0/companies?`$skiptoken=two"
        $global:BcReplies.Enqueue(@{StatusCode = 200; Content = (@{value = @(@{id='one'}); '@odata.nextLink' = $next} | ConvertTo-Json); Headers = @{}})
        $global:BcReplies.Enqueue(@{StatusCode = 200; Content = '{"value":[{"id":"two"}]}'; Headers = @{}})
        @(Get-BcCompanies).Count | Should -Be 2
        $global:BcUris.Count | Should -Be 2
    }

    It 'rejects a foreign host next link without leaking the bearer' {
        $global:BcReplies.Enqueue(@{StatusCode = 200; Content = '{"value":[],"@odata.nextLink":"https://foreign.invalid/companies"}'; Headers = @{}})
        { Get-BcCompanies } | Should -Throw '*escaped*'
        $global:BcUris.Count | Should -Be 1
    }

    It 'rejects next links to another company on the same BC host' {
        $next = "https://api.businesscentral.dynamics.com/v2.0/$script:Tenant/Sandbox/api/v2.0/companies(00000000-0000-0000-0000-000000000012)/items"
        $global:BcReplies.Enqueue(@{StatusCode = 200; Content = (@{value = @(); '@odata.nextLink' = $next} | ConvertTo-Json); Headers = @{}})
        { Get-BcCollection -CompanyId $script:Company -Resource items } | Should -Throw '*escaped*'
        $global:BcUris.Count | Should -Be 1
    }

    It 'refuses repeated next links' {
        $uri = "https://api.businesscentral.dynamics.com/v2.0/$script:Tenant/Sandbox/api/v2.0/companies"
        $global:BcReplies.Enqueue(@{StatusCode = 200; Content = (@{value = @(); '@odata.nextLink' = $uri} | ConvertTo-Json); Headers = @{}})
        { Get-BcCompanies } | Should -Throw '*repeated*'
    }

    It 'fails on a truncated census instead of returning partial success' {
        Initialize-BcConnection -TenantId $script:Tenant -Environment Sandbox -MaxPages 1
        $next = "https://api.businesscentral.dynamics.com/v2.0/$script:Tenant/Sandbox/api/v2.0/companies?`$skiptoken=two"
        $global:BcReplies.Enqueue(@{StatusCode = 200; Content = (@{value = @(@{id='one'}); '@odata.nextLink' = $next} | ConvertTo-Json); Headers = @{}})
        { Get-BcCompanies } | Should -Throw '*MaxPages*'
    }

    It 'honours Retry-After with bounded retries' {
        $global:BcReplies.Enqueue(@{StatusCode = 429; Content = ''; Headers = @{'Retry-After'='2'}})
        $global:BcReplies.Enqueue(@{StatusCode = 200; Content = '{"value":[]}'; Headers = @{}})
        @(Get-BcCompanies).Count | Should -Be 0
        $global:BcSleeps[0] | Should -Be 2
        $global:BcUris.Count | Should -Be 2
    }

    It 'does not retry a permission denial' {
        $global:BcReplies.Enqueue(@{StatusCode = 403; Content = 'denied'; Headers = @{}})
        { Get-BcCompanies } | Should -Throw '*HTTP 403*'
        $global:BcUris.Count | Should -Be 1
    }

    It 'rejects invalid collection JSON' {
        $global:BcReplies.Enqueue(@{StatusCode = 200; Content = '{"successful":true}'; Headers = @{}})
        { Get-BcCompanies } | Should -Throw '*value array*'
    }

    It 'returns standard API metadata without exposing authentication' {
        $global:BcReplies.Enqueue(@{StatusCode = 200; Content = '<edmx />'; Headers = @{}})
        Get-BcMetadata | Should -Be '<edmx />'
        $global:BcUris[0] | Should -Match '/\$metadata$'
    }

    It 'does not retain a previous connection when reinitialization fails' {
        { Initialize-BcConnection -TenantId 'bad' -Environment Sandbox } | Should -Throw '*tenant GUID*'
        { Assert-BcConnection } | Should -Throw '*Initialize-BcConnection*'
    }

    It 'acquires an S2S token only when an environment token is absent' {
        $env:BC_ACCESS_TOKEN = ''
        $env:BC_CLIENT_SECRET = 'unit-test-secret'
        Mock Invoke-RestMethod -ModuleName Bc.Api { @{access_token='unit-test-acquired-token'} }
        try {
            Initialize-BcConnection -TenantId $script:Tenant -Environment Sandbox -ClientId '00000000-0000-0000-0000-000000000002'
            Assert-BcConnection
            Should -Invoke Invoke-RestMethod -ModuleName Bc.Api -Times 1 -Exactly -ParameterFilter {
                $Body.scope -eq 'https://api.businesscentral.dynamics.com/.default' -and $Body.grant_type -eq 'client_credentials'
            }
        } finally { $env:BC_ACCESS_TOKEN = 'unit-test-bearer' }
    }
}
