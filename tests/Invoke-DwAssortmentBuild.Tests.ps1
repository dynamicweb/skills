BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Source = Join-Path (Get-RepoRoot) 'skills/dw-data-access/scripts/Invoke-DwAssortmentBuild.ps1'
}

Describe 'Invoke-DwAssortmentBuild' {
    BeforeEach {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
        # Default stub: the build drains immediately and the assortment has items.
        $script:Script = New-StubbedMcpScript -ScriptPath $script:Source -Destination $dir -LogPath $script:Log `
            -PendingIds @() -ItemCount 12 -ShopRelationCount 0
    }

    Context 'the dry run' {
        It 'writes nothing without -Apply' {
            & $script:Script -AssortmentId 'ASRT1' | Out-Null
            $LASTEXITCODE | Should -Be 0
            (Get-StubLog -LogPath $script:Log) -join "`n" | Should -Not -Match 'Invoke-DwMcp'
        }

        It 'prints the sequence including the count gate' {
            $out = & $script:Script -AssortmentId 'ASRT1' -ActivateWhenNonEmpty *>&1 | Out-String
            $out | Should -Match '1\. flag_assortments_for_rebuild'
            $out | Should -Match '2\. build_assortments'
            $out | Should -Match '3\. poll get_assortments_for_build'
            $out | Should -Match '4\. count EcomAssortmentItems'
            $out | Should -Match '5\. save_assortments active = true'
            $out | Should -Match 'DRY RUN'
        }
    }

    Context 'the -Apply path' {
        It 'flags, then builds, then polls, in that order' {
            & $script:Script -AssortmentId 'ASRT1' -Apply | Out-Null
            $LASTEXITCODE | Should -Be 0
            $tools = @(Get-StubLog -LogPath $script:Log | Where-Object { $_ -match '^Invoke-DwMcp ' })
            $tools[0] | Should -Be 'Invoke-DwMcp flag_assortments_for_rebuild'
            $tools[1] | Should -Be 'Invoke-DwMcp build_assortments'
            $tools[2] | Should -Be 'Invoke-DwMcp get_assortments_for_build'
        }

        It 'sends the array-of-request-objects shape, not the flat assortmentIds' {
            & $script:Script -AssortmentId 'ASRT1', 'ASRT2' -Apply | Out-Null
            $args = (Get-StubLog -LogPath $script:Log | Where-Object { $_ -match '^  args ' }) -join "`n"
            $args | Should -Match '"requests"'
            $args | Should -Match '"assortmentId"\s*:\s*"ASRT1"'
            $args | Should -Not -Match 'assortmentIds'
        }

        It 'skips the flag only with -SkipFlag' {
            & $script:Script -AssortmentId 'ASRT1' -SkipFlag -Apply | Out-Null
            (Get-StubLog -LogPath $script:Log) | Should -Not -Contain 'Invoke-DwMcp flag_assortments_for_rebuild'
            (Get-StubLog -LogPath $script:Log) | Should -Contain 'Invoke-DwMcp build_assortments'
        }

        It 'reads the item count and the shop-relation count' {
            $out = & $script:Script -AssortmentId 'ASRT1' -Apply *>&1 | Out-String
            $out | Should -Match 'ASRT1: 12 built item\(s\), 0 shop relation\(s\)'
        }

        It 'warns when a shop relation is present, because the build unions the relation sets' {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
            $s = New-StubbedMcpScript -ScriptPath $script:Source -Destination $dir -LogPath $log -PendingIds @() -ItemCount 9000 -ShopRelationCount 1
            $out = & $s -AssortmentId 'ASRT1' -Apply *>&1 | Out-String
            $out | Should -Match 'a shop relation is present'
        }
    }

    Context 'the count gate' {
        It 'refuses to activate a zero-item assortment and exits 1' {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
            $s = New-StubbedMcpScript -ScriptPath $script:Source -Destination $dir -LogPath $log -PendingIds @() -ItemCount 0
            $out = & $s -AssortmentId 'ASRT1' -ActivateWhenNonEmpty -Apply *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'ZERO items'
            $out | Should -Match 'Nothing activated'
            (Get-StubLog -LogPath $log) | Should -Not -Contain 'Invoke-DwMcp save_assortments'
        }

        It 'activates a non-empty assortment' {
            & $script:Script -AssortmentId 'ASRT1' -ActivateWhenNonEmpty -Apply | Out-Null
            $LASTEXITCODE | Should -Be 0
            (Get-StubLog -LogPath $script:Log) | Should -Contain 'Invoke-DwMcp save_assortments'
        }

        It 'refuses -ActivateWhenNonEmpty together with -SkipCountGate' {
            $out = & $script:Script -AssortmentId 'ASRT1' -ActivateWhenNonEmpty -SkipCountGate -Apply *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'the count IS the gate'
            (Get-StubLog -LogPath $script:Log) -join "`n" | Should -Not -Match 'Invoke-DwMcp'
        }

        It 'reads no SQL at all with -SkipCountGate' {
            $out = & $script:Script -AssortmentId 'ASRT1' -SkipCountGate -Apply *>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            (Get-StubLog -LogPath $script:Log) -join "`n" | Should -Not -Match 'Get-DwSqlScalar'
            $out | Should -Match 'Count gate SKIPPED'
        }
    }

    Context 'the wait' {
        It 'exits 1 without activating when the build does not drain' {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
            $s = New-StubbedMcpScript -ScriptPath $script:Source -Destination $dir -LogPath $log -PendingIds @('ASRT1') -ItemCount 12
            $out = & $s -AssortmentId 'ASRT1' -ActivateWhenNonEmpty -TimeoutMinutes 0 -Apply *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'TIMEOUT'
            $out | Should -Match 'do NOT activate it'
            (Get-StubLog -LogPath $log) | Should -Not -Contain 'Invoke-DwMcp save_assortments'
        }
    }
}
