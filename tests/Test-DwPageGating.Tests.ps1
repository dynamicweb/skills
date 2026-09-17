BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Script = Join-Path (Get-RepoRoot) 'skills/dw-data-access/scripts/Test-DwPageGating.ps1'
    # A Pester mock body runs in its own session state, so the recorder and the
    # response plan have to be global.
    $global:DwGateCalls = [System.Collections.Generic.List[object]]::new()
}

Describe 'Test-DwPageGating' {
    BeforeAll {
        Mock Invoke-WebRequest {
            $global:DwGateCalls.Add([pscustomobject]@{ Uri = $Uri; Method = $Method; Body = $Body })
            if ($Uri -notmatch 'Default\.aspx') {
                return [pscustomobject]@{ StatusCode = $global:DwGateSignInStatus; Content = 'signed in' }
            }
            # Which persona this is, is decided by the credential the sign-in on
            # this session carried; the stub keys off call order instead, which
            # is deterministic: granted first, then denied.
            $global:DwGatePageIndex++
            $plan = $global:DwGatePages[$global:DwGatePageIndex - 1]
            [pscustomobject]@{ StatusCode = $plan.Status; Content = ('x' * $plan.Bytes) }
        }
    }

    BeforeEach {
        $global:DwGateCalls.Clear()
        $global:DwGatePageIndex = 0
        $global:DwGateSignInStatus = 200
        $global:DwGatePages = @(
            @{ Status = 200; Bytes = 40000 },   # granted
            @{ Status = 200; Bytes = 300 }      # denied
        )
        $env:DW_GRANTED_USER = 'granted@example.test'
        $env:DW_GRANTED_PASSWORD = 'g-secret'
        $env:DW_DENIED_USER = 'denied@example.test'
        $env:DW_DENIED_PASSWORD = 'd-secret'
    }

    AfterAll {
        foreach ($v in 'DW_GRANTED_USER', 'DW_GRANTED_PASSWORD', 'DW_DENIED_USER', 'DW_DENIED_PASSWORD') {
            Remove-Item "env:$v" -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name DwGateCalls, DwGatePages, DwGatePageIndex, DwGateSignInStatus -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'the pass' {
        It 'passes when the granted body dwarfs the denied one' {
            $out = & $script:Script -PageId 8460 -SignInPath /customer-center -BaseUrl 'https://example.test' *>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            $out | Should -Match 'PASS: granted'
        }

        It 'addresses the page BY ID, never by a friendly path' {
            & $script:Script -PageId 8460 -SignInPath /customer-center -BaseUrl 'https://example.test' *>&1 | Out-Null
            $pageCalls = @($global:DwGateCalls | Where-Object { $_.Uri -match 'Default\.aspx' })
            $pageCalls.Count | Should -Be 2
            foreach ($c in $pageCalls) { $c.Uri | Should -Match 'Default\.aspx\?ID=8460$' }
        }

        It 'signs both personas in, one request each, before fetching' {
            & $script:Script -PageId 8460 -SignInPath /customer-center -BaseUrl 'https://example.test' *>&1 | Out-Null
            @($global:DwGateCalls | Where-Object { $_.Uri -match '/customer-center' }).Count | Should -Be 2
        }

        It 'never echoes a password' {
            $out = & $script:Script -PageId 8460 -SignInPath /customer-center -BaseUrl 'https://example.test' *>&1 | Out-String
            $out | Should -Not -Match 'g-secret'
            $out | Should -Not -Match 'd-secret'
        }
    }

    Context 'the failures' {
        It 'reports a BROKEN CHECK when both personas get the same response' {
            $global:DwGatePages = @(@{ Status = 200; Bytes = 40000 }, @{ Status = 200; Bytes = 40000 })
            $out = & $script:Script -PageId 8460 -SignInPath /c -BaseUrl 'https://example.test' *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'BROKEN CHECK: both personas received the same response'
            $out | Should -Not -Match 'PASS: granted'
        }

        It 'reports a BROKEN CHECK on a 404, because the gate was never reached' {
            $global:DwGatePages = @(@{ Status = 404; Bytes = 500 }, @{ Status = 404; Bytes = 400 })
            $out = & $script:Script -PageId 1 -SignInPath /c -BaseUrl 'https://example.test' *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'BROKEN CHECK: 404'
        }

        It 'fails an inverted grant (the granted persona gets the smaller body)' {
            $global:DwGatePages = @(@{ Status = 200; Bytes = 300 }, @{ Status = 200; Bytes = 40000 })
            $out = & $script:Script -PageId 8460 -SignInPath /c -BaseUrl 'https://example.test' *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'The grant is inverted'
        }

        It 'fails when the denied body is close to the granted one' {
            $global:DwGatePages = @(@{ Status = 200; Bytes = 40000 }, @{ Status = 200; Bytes = 39000 })
            $out = & $script:Script -PageId 8460 -SignInPath /c -BaseUrl 'https://example.test' *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'the denied persona is receiving something close to the full page|denied body'
        }

        It 'fails on a measured absolute ceiling with -MaxDeniedBytes' {
            $global:DwGatePages = @(@{ Status = 200; Bytes = 40000 }, @{ Status = 200; Bytes = 900 })
            $out = & $script:Script -PageId 8460 -SignInPath /c -BaseUrl 'https://example.test' -MaxDeniedBytes 600 *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'past the measured ceiling of 600'
        }

        It 'fails when a persona cannot sign in' {
            $global:DwGateSignInStatus = 401
            $out = & $script:Script -PageId 8460 -SignInPath /c -BaseUrl 'https://example.test' *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'FAILED to sign in: HTTP 401'
        }
    }

    Context 'the refusals' {
        It 'refuses to run with only one persona configured' {
            Remove-Item 'env:DW_DENIED_PASSWORD' -ErrorAction SilentlyContinue
            $out = & $script:Script -PageId 8460 -SignInPath /c -BaseUrl 'https://example.test' *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'DW_DENIED_PASSWORD'
            $global:DwGateCalls.Count | Should -Be 0
        }
    }
}
