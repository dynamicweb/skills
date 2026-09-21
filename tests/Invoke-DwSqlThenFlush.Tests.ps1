BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Source = Join-Path (Get-RepoRoot) 'skills/dw-data-access/scripts/Invoke-DwSqlThenFlush.ps1'
    $script:OrderService = 'Dynamicweb.Ecommerce.Orders.OrderService'
}

Describe 'Invoke-DwSqlThenFlush' {
    BeforeEach {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
        $script:Script = New-StubbedScript -ScriptPath $script:Source -Destination $dir -LogPath $script:Log `
            -CachesResponseJson '{"data":[{"cacheTypeName":"Dynamicweb.Ecommerce.Orders.OrderService"}]}'
    }

    Context 'the dry run' {
        It 'runs nothing without -Apply' {
            & $script:Script -Query 'UPDATE EcomOrders SET OrderComplete = 1' -CacheTypeName $script:OrderService | Out-Null
            $LASTEXITCODE | Should -Be 0
            ((Get-StubLog -LogPath $script:Log) -join "`n") | Should -Not -Match 'Invoke-DwSqlNonQuery|Clear-DwServiceCache'
        }

        It 'prints the SQL and the flush in the order they will run' {
            $out = & $script:Script -Query 'UPDATE EcomOrders SET OrderComplete = 1' -CacheTypeName $script:OrderService *>&1 | Out-String
            $out | Should -Match '1\. SQL\s+UPDATE EcomOrders'
            $out | Should -Match "2\. FLUSH CacheInformationRefresh CacheTypeName=$([regex]::Escape($script:OrderService))"
            $out | Should -Match 'DRY RUN'
        }
    }

    Context 'the -Apply path' {
        It 'runs every statement, then every flush, in order' {
            & $script:Script -Query 'UPDATE A SET x = 1', 'UPDATE B SET y = 2' `
                -CacheTypeName $script:OrderService, 'Dynamicweb.Ecommerce.Shops.ShopService' -Apply | Out-Null
            $LASTEXITCODE | Should -Be 0
            $calls = @(Get-StubLog -LogPath $script:Log | Where-Object { $_ -match '^(Invoke-DwSqlNonQuery|Clear-DwServiceCache)' })
            $calls[0] | Should -Be 'Invoke-DwSqlNonQuery UPDATE A SET x = 1'
            $calls[1] | Should -Be 'Invoke-DwSqlNonQuery UPDATE B SET y = 2'
            $calls[2] | Should -Be "Clear-DwServiceCache $script:OrderService"
            $calls[3] | Should -Be 'Clear-DwServiceCache Dynamicweb.Ecommerce.Shops.ShopService'
        }

        It 'reads statements from -File' {
            $sql = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).sql"
            Set-Content -LiteralPath $sql -Value 'UPDATE FromFile SET z = 3' -Encoding utf8NoBOM
            & $script:Script -File $sql -CacheTypeName $script:OrderService -Apply | Out-Null
            ((Get-StubLog -LogPath $script:Log) -join "`n") | Should -Match 'Invoke-DwSqlNonQuery UPDATE FromFile SET z = 3'
        }

        It 'skips the flush only with -NoFlush' {
            & $script:Script -Query 'UPDATE A SET x = 1' -NoFlush -Apply | Out-Null
            $LASTEXITCODE | Should -Be 0
            ((Get-StubLog -LogPath $script:Log) -join "`n") | Should -Not -Match 'Clear-DwServiceCache'
        }

        It 'fails loudly when a flush is rejected, rather than leaving a committed write behind a stale cache' {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
            $s = New-StubbedScript -ScriptPath $script:Source -Destination $dir -LogPath $log -FailFlush
            $out = & $s -Query 'UPDATE A SET x = 1' -CacheTypeName 'Nope.Service' -Apply *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'FAILED to flush'
            $out | Should -Match 'The SQL is committed and the cache is NOT flushed'
        }
    }

    Context 'the refusals' {
        It 'refuses to run without a -CacheTypeName' {
            $out = & $script:Script -Query 'UPDATE A SET x = 1' -Apply *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'No -CacheTypeName'
            ((Get-StubLog -LogPath $script:Log) -join "`n") | Should -Not -Match 'Invoke-DwSqlNonQuery'
        }

        It 'refuses -Query and -File together' {
            $sql = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).sql"
            Set-Content -LiteralPath $sql -Value 'SELECT 1' -Encoding utf8NoBOM
            & $script:Script -Query 'SELECT 1' -File $sql -CacheTypeName $script:OrderService -Apply *>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
        }

        It 'refuses an empty statement' {
            & $script:Script -Query '   ' -CacheTypeName $script:OrderService -Apply *>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
        }

        It 'refuses a run with neither -Query nor -File' {
            & $script:Script -CacheTypeName $script:OrderService -Apply *>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context '-ListCaches' {
        It 'enumerates the registered names and writes nothing' {
            $out = & $script:Script -ListCaches *>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            $out | Should -Match ([regex]::Escape($script:OrderService))
            (Get-StubLog -LogPath $script:Log) | Should -Contain 'Invoke-DwApi GetServiceCaches'
            ((Get-StubLog -LogPath $script:Log) -join "`n") | Should -Not -Match 'Invoke-DwSqlNonQuery'
        }
    }
}
