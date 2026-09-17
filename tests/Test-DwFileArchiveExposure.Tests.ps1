BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Script = Join-Path (Get-RepoRoot) 'skills/dw-setup-config/scripts/Test-DwFileArchiveExposure.ps1'
    # A Pester mock body runs in its own session state, so the recorder has to
    # be global: a $script: variable written inside the mock never reaches here.
    $global:DwProbeCalls = [System.Collections.Generic.List[object]]::new()
}

Describe 'Test-DwFileArchiveExposure' {
    BeforeEach {
        $global:DwProbeCalls.Clear()
        $global:DwProbeStatus = @{}
        $global:DwProbeDefault = 404
    }

    BeforeAll {
        Mock Invoke-WebRequest -Verifiable {
            $global:DwProbeCalls.Add([pscustomobject]@{ Uri = $Uri; Method = $Method; Headers = $Headers; SkipCert = $SkipCertificateCheck })
            $path = ([uri]$Uri).AbsolutePath
            $code = if ($global:DwProbeStatus.ContainsKey($path)) { $global:DwProbeStatus[$path] } else { $global:DwProbeDefault }
            if ($code -eq 'throw') { throw 'connection refused' }
            [pscustomobject]@{ StatusCode = $code }
        }
    }

    Context 'the verdicts' {
        It 'exits 0 when every default path is blocked' {
            & $script:Script -BaseUrl 'https://example.test' *>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It 'exits 1 and names the served path when one answers 200' {
            $global:DwProbeStatus['/Files/Files/Integration/jobs/'] = 200
            $out = & $script:Script -BaseUrl 'https://example.test' *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'SERVED\s+200\s+/Files/Files/Integration/jobs/'
            $out | Should -Match 'SourceServerSSPI'
        }

        It 'reports EXPECTED and exits 0 for a declared caveat' {
            $global:DwProbeStatus['/Files/System/Items/'] = 200
            $out = & $script:Script -BaseUrl 'https://example.test' -ExpectServed '/Files/System/Items/' *>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            $out | Should -Match 'EXPECTED\s+200\s+/Files/System/Items/'
        }

        It 'reports CLOSED, not a failure, for a caveat that has lapsed' {
            $out = & $script:Script -BaseUrl 'https://example.test' -ExpectServed '/Files/System/Items/' *>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            $out | Should -Match 'CLOSED'
        }

        It 'exits 1 when a path does not answer at all — the probe proved nothing' {
            $global:DwProbeStatus['/Files/System/Items/'] = 'throw'
            $out = & $script:Script -BaseUrl 'https://example.test' *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'ERROR'
        }
    }

    Context 'the request shape' {
        It 'probes the measured default set with HEAD and no credential' {
            & $script:Script -BaseUrl 'https://example.test' *>&1 | Out-Null
            $paths = @($global:DwProbeCalls | ForEach-Object { ([uri]$_.Uri).AbsolutePath })
            $paths | Should -Contain '/Files/Files/Integration/jobs/'
            $paths | Should -Contain '/Files/System/Items/'
            $paths | Should -Contain '/Files/System/Serializer/Serializer.config.json'
            $paths | Should -Contain '/Files/GlobalSettings.Database.config'
            $paths | Should -Contain '/admin/public/webservices/integrationv2/JobRunner.aspx'
            @($global:DwProbeCalls | Where-Object { $_.Method -ne 'Head' }) | Should -BeNullOrEmpty
            foreach ($call in $global:DwProbeCalls) {
                $call.Headers.Keys | Should -Not -Contain 'Authorization'
                $call.Headers.Keys | Should -Not -Contain 'Cookie'
            }
        }

        It 'sends no User-Agent by default and one only with -BrowserUserAgent' {
            & $script:Script -BaseUrl 'https://example.test' -SkipDefaultPaths -Path '/Files/x.xml' *>&1 | Out-Null
            $global:DwProbeCalls[0].Headers.Keys | Should -Not -Contain 'User-Agent'

            $global:DwProbeCalls.Clear()
            & $script:Script -BaseUrl 'https://example.test' -SkipDefaultPaths -Path '/Files/x.xml' -BrowserUserAgent *>&1 | Out-Null
            $global:DwProbeCalls[0].Headers['User-Agent'] | Should -Match 'Mozilla'
        }

        It 're-asks with GET when the handler refuses HEAD' {
            $global:DwProbeStatus['/Files/x.xml'] = 405
            & $script:Script -BaseUrl 'https://example.test' -SkipDefaultPaths -Path '/Files/x.xml' *>&1 | Out-Null
            @($global:DwProbeCalls | Where-Object { $_.Method -eq 'Get' }).Count | Should -Be 1
        }

        It 'gates the TLS bypass on a loopback host or the explicit opt-in' {
            & $script:Script -BaseUrl 'https://example.test' -SkipDefaultPaths -Path '/Files/x.xml' *>&1 | Out-Null
            [bool]$global:DwProbeCalls[0].SkipCert | Should -BeFalse

            $global:DwProbeCalls.Clear()
            & $script:Script -BaseUrl 'https://127.0.0.1:8080' -SkipDefaultPaths -Path '/Files/x.xml' *>&1 | Out-Null
            [bool]$global:DwProbeCalls[0].SkipCert | Should -BeTrue

            $global:DwProbeCalls.Clear()
            & $script:Script -BaseUrl 'https://example.test' -SkipDefaultPaths -Path '/Files/x.xml' -AllowSelfSignedCertificate *>&1 | Out-Null
            [bool]$global:DwProbeCalls[0].SkipCert | Should -BeTrue
        }
    }

    Context 'the refusals' {
        It 'exits 1 with no base URL' {
            $saved = $env:DW_BASE_URL
            $env:DW_BASE_URL = $null
            try {
                & $script:Script *>&1 | Out-Null
                $LASTEXITCODE | Should -Be 1
            }
            finally { $env:DW_BASE_URL = $saved }
        }

        It 'exits 1 when -SkipDefaultPaths leaves nothing to probe' {
            & $script:Script -BaseUrl 'https://example.test' -SkipDefaultPaths *>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            $global:DwProbeCalls.Count | Should -Be 0
        }
    }
    AfterAll {
        Remove-Variable -Name DwProbeCalls, DwProbeStatus, DwProbeDefault -Scope Global -ErrorAction SilentlyContinue
    }
}
