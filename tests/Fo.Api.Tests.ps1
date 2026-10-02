BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module (Join-Path (Get-RepoRoot) 'skills/dw-demo-fo/scripts/Fo.Api.psm1') -Force -ErrorAction Stop

    function New-FoErrorRecord {
        # A caught request error as Invoke-FoApi rethrows it: the exception message, plus the response body
        # in ErrorDetails when the reply carried one.
        param([string]$Message = 'Response status code does not indicate success: 404 (Not Found).', [string]$Body)
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($Message), 'WebCmdletWebResponseException',
            [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
        if ($PSBoundParameters.ContainsKey('Body')) {
            $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Body)
        }
        $record
    }
}

AfterAll {
    Remove-Module Fo.Api -ErrorAction SilentlyContinue
}

Describe 'Get-FoErrorText under strict mode' {
    It 'returns the exception message for a 404 with no body (no ErrorDetails)' {
        Get-FoErrorText (New-FoErrorRecord) | Should -Be 'Response status code does not indicate success: 404 (Not Found).'
    }

    It 'returns the inner error message of an OData error body' {
        $body = '{"error":{"code":"","message":"An error has occurred.","innererror":{"message":"Resource not found for the segment ''DataManagementDefinitionGroups''.","type":"","stacktrace":""}}}'
        Get-FoErrorText (New-FoErrorRecord -Body $body) | Should -Be "Resource not found for the segment 'DataManagementDefinitionGroups'."
    }

    It 'returns error.message when there is no innererror' {
        Get-FoErrorText (New-FoErrorRecord -Body '{"error":{"code":"","message":"Not found."}}') | Should -Be 'Not found.'
    }

    It 'returns Message of a Web API error body' {
        Get-FoErrorText (New-FoErrorRecord -Body '{"Message":"No HTTP resource was found that matches the request URI."}') |
            Should -Be 'No HTTP resource was found that matches the request URI.'
    }

    It 'returns the body text for <name>' -ForEach @(
        @{ name = 'a JSON object with none of the known members'; body = '{"code":"404"}' }
        @{ name = 'an error member that is null'; body = '{"error":null}' }
        @{ name = 'a JSON array'; body = '[1,2]' }
        @{ name = 'a body that is not JSON'; body = 'Not Found' }
    ) {
        Get-FoErrorText (New-FoErrorRecord -Body $body) | Should -Be $body
    }

    It 'returns a string error member as is' {
        Get-FoErrorText (New-FoErrorRecord -Body '{"error":"invalid_client"}') | Should -Be 'invalid_client'
    }
}
