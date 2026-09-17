BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Source = Join-Path (Get-RepoRoot) 'skills/dw-data-access/scripts/Set-DwPermission.ps1'
}

Describe 'Set-DwPermission' {
    BeforeEach {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
        $script:Script = New-StubbedApiScript -ScriptPath $script:Source -Destination $dir -LogPath $script:Log -Config @{
            api = @{
                'PermissionSave'           = @{ status = 'ok'; model = @{ modelIdentifier = '97|$|Page|$||$|9' } }
                'PermissionsByIdentifier'  = @{ totalCount = 1; data = @(@{ ownerId = '9'; level = 'read' }) }
            }
        }
    }

    Context 'the dry run' {
        It 'writes nothing without -Apply' {
            & $script:Script -Key 97 -Name Page -OwnerId 9 -Level Read | Out-Null
            $LASTEXITCODE | Should -Be 0
            (Get-StubLog -LogPath $script:Log) -join "`n" | Should -Not -Match 'Invoke-DwApi'
        }

        It 'prints the nested Model body, the level number and the composite identifier' {
            $out = & $script:Script -Key 97 -Name Page -OwnerId 9 -Level Read *>&1 | Out-String
            $out | Should -Match '"Model"'
            $out | Should -Match 'Level:\s+Read = 4'
            $out | Should -Match ([regex]::Escape('Identifier: 97|$|Page|$||$|9'))
            $out | Should -Match 'DRY RUN'
        }

        It 'flags None as a denial, not the bottom of a ladder' {
            $out = & $script:Script -Key 97 -Name Page -OwnerId 9 -Level None *>&1 | Out-String
            $out | Should -Match 'None = 1'
            $out | Should -Match 'a DENIAL, not the bottom of a ladder'
        }
    }

    Context 'the -Apply path' {
        It 'posts PermissionSave with the body nested under Model, then reads back' {
            & $script:Script -Key 97 -Name Page -OwnerId 9 -Level Read -Apply | Out-Null
            $LASTEXITCODE | Should -Be 0
            $calls = @(Get-StubLog -LogPath $script:Log | Where-Object { $_ -match '^Invoke-DwApi ' })
            $calls[0] | Should -Be 'Invoke-DwApi PermissionSave'
            $calls[1] | Should -Match '^Invoke-DwApi PermissionsByIdentifier'
            $body = (Get-StubLog -LogPath $script:Log | Where-Object { $_ -match '^  body ' }) -join "`n"
            $body | Should -Match '"Model":\{'
            $body | Should -Match '"Key":"97"'
            $body | Should -Match '"IsExplicitPermission":true'
        }

        It 'sends every level as its sparse numeric value' {
            $expected = @{ None = 1; Read = 4; Edit = 20; Create = 84; Delete = 340; All = 1364 }
            foreach ($name in $expected.Keys) {
                $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
                $log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
                $s = New-StubbedApiScript -ScriptPath $script:Source -Destination $dir -LogPath $log -Config @{
                    api = @{ 'PermissionsByIdentifier' = @{ data = @(@{ ownerId = '9'; level = $name }) } }
                }
                & $s -Key 97 -Name Page -OwnerId 9 -Level $name -Apply | Out-Null
                ((Get-StubLog -LogPath $log) -join "`n") | Should -Match "`"Level`":$($expected[$name])"
            }
        }

        It 'OMITS SubName from the read-back (an empty SubName returns an empty data array)' {
            & $script:Script -Key 97 -Name Page -OwnerId 9 -Level Read -SubName '' -Apply | Out-Null
            $read = @(Get-StubLog -LogPath $script:Log | Where-Object { $_ -match 'PermissionsByIdentifier' })[0]
            $read | Should -Match 'Key=97'
            $read | Should -Match 'Name=Page'
            $read | Should -Not -Match 'SubName'
        }

        It 'still sends SubName on the WRITE side' {
            & $script:Script -Key 42 -Name UserGroup -OwnerId 9 -Level Delete -SubName 'User' -Apply | Out-Null
            ((Get-StubLog -LogPath $script:Log) -join "`n") | Should -Match '"SubName":"User"'
        }

        It 'fails when the read-back has no row for the owner' {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
            $s = New-StubbedApiScript -ScriptPath $script:Source -Destination $dir -LogPath $log -Config @{
                api = @{ 'PermissionsByIdentifier' = @{ data = @() } }
            }
            $out = & $s -Key 97 -Name Page -OwnerId 9 -Level Read -Apply *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'does not return a row for owner 9'
        }

        It 'skips the read-back with -NoVerify' {
            & $script:Script -Key 97 -Name Page -OwnerId 9 -Level Read -Apply -NoVerify | Out-Null
            $LASTEXITCODE | Should -Be 0
            (Get-StubLog -LogPath $script:Log) -join "`n" | Should -Not -Match 'PermissionsByIdentifier'
        }
    }

    Context 'the identifier' {
        It 'doubles the separator on an empty SubName and keeps four parts in order' {
            $out = & $script:Script -Key Content -Name Section -OwnerId 42 -Level Edit *>&1 | Out-String
            $out | Should -Match ([regex]::Escape('Identifier: Content|$|Section|$||$|42'))
        }
    }

    Context 'the refusals' {
        It 'rejects a level outside the enum' {
            { & $script:Script -Key 97 -Name Page -OwnerId 9 -Level Write } | Should -Throw
        }
    }
}
