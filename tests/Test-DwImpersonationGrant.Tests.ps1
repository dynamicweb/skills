BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Source = Join-Path (Get-RepoRoot) 'skills/dw-data-access/scripts/Test-DwImpersonationGrant.ps1'

    # The SQL stub keys on the id ORDER inside the WHERE clause, which is the
    # whole point of the check: UserId is the impersonator, SecondaryUserId the
    # customer, and the wrong direction is otherwise silent.
    function New-Grant {
        param([ValidateSet('forward', 'reverse', 'none')][string]$Direction, [string]$IndexState = 'Success')
        $rules = switch ($Direction) {
            'forward' { @(@{ match = 'RelationUserId = 1270 AND AccessUserSecondaryRelationSecondaryUserId = 1292'; value = 1 }) }
            'reverse' { @(@{ match = 'RelationUserId = 1292 AND AccessUserSecondaryRelationSecondaryUserId = 1270'; value = 1 }) }
            'none' { @() }
        }
        New-StubbedApiScript -ScriptPath $script:Source -Destination $script:Dir -LogPath $script:Log -Config @{
            sqlScalar = $rules
            api       = @{ 'IndexStatusByRepositoryAndIndexName' = @{ model = @{ state = $IndexState; lastRun = '2026-09-17T09:00:00' } } }
        }
    }
}

Describe 'Test-DwImpersonationGrant' {
    BeforeEach {
        $script:Dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
    }

    Context 'the direction' {
        It 'passes a grant in the right direction' {
            $s = New-Grant -Direction forward
            $out = & $s -ImpersonatorUserId 1270 -CustomerUserId 1292 *>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            $out | Should -Match 'GRANTED: user 1270 \(impersonator\) may impersonate 1292 \(customer\)'
        }

        It 'fails and names the reversed row rather than reporting no grant' {
            $s = New-Grant -Direction reverse
            $out = & $s -ImpersonatorUserId 1270 -CustomerUserId 1292 *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'WRONG DIRECTION: the row reads 1292 -> 1270'
            $out | Should -Match 'Swap the two ids'
        }

        It 'fails when no row exists in either direction' {
            $s = New-Grant -Direction none
            $out = & $s -ImpersonatorUserId 1270 -CustomerUserId 1292 *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'NO GRANT'
        }

        It 'reads both directions, never just one' {
            $s = New-Grant -Direction forward
            & $s -ImpersonatorUserId 1270 -CustomerUserId 1292 *>&1 | Out-Null
            @(Get-StubLog -LogPath $script:Log | Where-Object { $_ -match 'Get-DwSqlScalar' }).Count | Should -Be 2
        }
    }

    Context 'the index read' {
        It 'reports the Users.index state and the rebuild debt' {
            $s = New-Grant -Direction forward
            $out = & $s -ImpersonatorUserId 1270 -CustomerUserId 1292 *>&1 | Out-String
            $out | Should -Match 'Users\s+state Success'
            $out | Should -Match 'run a FULL build of the Users index'
            $out | Should -Match 'grant was REMOVED'
        }

        It 'asks both repository names, with Repository + IndexName on this verb' {
            $s = New-Grant -Direction forward
            & $s -ImpersonatorUserId 1270 -CustomerUserId 1292 *>&1 | Out-Null
            $calls = (Get-StubLog -LogPath $script:Log | Where-Object { $_ -match 'IndexStatus' }) -join "`n"
            $calls | Should -Match 'Repository=Users&IndexName=Users.index'
            $calls | Should -Match 'Repository=Secondary%20users&IndexName=Users.index'
            $calls | Should -Not -Match 'RepositoryName='
        }

        It 'falls back to IndexStatusesAll when the per-index verb is unavailable' {
            $s = New-StubbedApiScript -ScriptPath $script:Source -Destination $script:Dir -LogPath $script:Log -Config @{
                sqlScalar = @(@{ match = 'RelationUserId = 1270 AND AccessUserSecondaryRelationSecondaryUserId = 1292'; value = 1 })
                api       = @{
                    'IndexStatusByRepositoryAndIndexName' = 'throw'
                    'IndexStatusesAll'                    = @{ model = @(@{ repository = 'Users'; indexName = 'Users.index'; state = 'Success'; lastRun = '2026-09-17' }) }
                }
            }
            $out = & $s -ImpersonatorUserId 1270 -CustomerUserId 1292 *>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            (Get-StubLog -LogPath $script:Log) | Should -Contain 'Invoke-DwApi IndexStatusesAll'
            $out | Should -Match 'state Success'
        }

        It 'skips the index read with -SkipIndexRead' {
            $s = New-Grant -Direction forward
            & $s -ImpersonatorUserId 1270 -CustomerUserId 1292 -SkipIndexRead *>&1 | Out-Null
            (Get-StubLog -LogPath $script:Log) -join "`n" | Should -Not -Match 'IndexStatus'
        }
    }

    Context 'the hosted path' {
        It 'reads no SQL with -SkipRowRead and names the in-product reads instead' {
            $s = New-Grant -Direction none
            $out = & $s -ImpersonatorUserId 1270 -CustomerUserId 1292 -SkipRowRead *>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            (Get-StubLog -LogPath $script:Log) -join "`n" | Should -Not -Match 'Get-DwSqlScalar'
            $out | Should -Match 'get_impersonatable_users'
        }
    }
}
