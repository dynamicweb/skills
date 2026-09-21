BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Script = Join-Path (Get-RepoRoot) 'skills/dw-data-access/scripts/Test-DwJobSchema.ps1'
}

Describe 'Test-DwJobSchema' {
    BeforeEach {
        $script:Dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
        $script:Job = Join-Path $script:Dir 'job.xml'
    }

    It 'passes a clean job' {
        Write-Utf16Job -Path $script:Job -Text (New-JobXml)
        $out = & $script:Script -Path $script:Job *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '0 error\(s\)'
    }

    It 'fails a UTF-8 file on the encoding check and skips the rest' {
        Set-Content -LiteralPath $script:Job -Value (New-JobXml) -Encoding utf8NoBOM
        $out = & $script:Script -Path $script:Job *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'not UTF-16LE with a BOM'
    }

    It 'fails a mapped source column absent from the schema snapshot' {
        Write-Utf16Job -Path $script:Job -Text (New-JobXml -SourceColumn 'OrderCustomField' -SourceSchemaColumns @('OrderId'))
        $out = & $script:Script -Path $script:Job *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match "mapped source column 'Orders.OrderCustomField' is not in the <Schema> snapshot"
        $out | Should -Match 'STALE snapshot first, not a mapping typo'
    }

    It 'fails a mapped destination column absent from the schema snapshot' {
        Write-Utf16Job -Path $script:Job -Text (New-JobXml -DestinationColumn 'Extra' -DestinationSchemaColumns @('OrderId'))
        & $script:Script -Path $script:Job *>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'fails the plain Column shape on a SQL-backed destination' {
        Write-Utf16Job -Path $script:Job -Text (New-JobXml -DestinationColumnType 'Dynamicweb.DataIntegration.Integration.Column')
        $out = & $script:Script -Path $script:Job *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'SqlDestinationWriter casts every schema column'
    }

    It 'fails a connection written under a UI alias node' {
        Write-Utf16Job -Path $script:Job -Text (New-JobXml -AliasNodeName 'SourceServer' -AliasNodeValue 'sqlbox')
        $out = & $script:Script -Path $script:Job *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match '<SourceServer> carries a value and is read by NOTHING'
        $out | Should -Match 'Write <Server> instead'
    }

    It 'fails an empty connection node on a SqlProvider source' {
        Write-Utf16Job -Path $script:Job -Text (New-JobXml -EmptySourceConnection)
        $out = & $script:Script -Path $script:Job *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'empty-node fallback is DESTINATION-ONLY'
    }

    It 'warns on a credential, and fails it with -RequireIntegratedSecurity' {
        Write-Utf16Job -Path $script:Job -Text (New-JobXml -SourceConnection 'Server=.;User Id=sa;Password=hunter2;')
        $out = & $script:Script -Path $script:Job *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'WARN.*a credential is present'

        $out = & $script:Script -Path $script:Job -RequireIntegratedSecurity *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'ERROR.*a credential is present'
    }

    It 'fails a mapping uid shared between two files in one run' {
        $second = Join-Path $script:Dir 'job2.xml'
        Write-Utf16Job -Path $script:Job -Text (New-JobXml)
        Write-Utf16Job -Path $second -Text (New-JobXml)
        $out = & $script:Script -Path $script:Dir *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'mapping uid 11111111-1111-1111-1111-111111111111 is also used by'
    }

    It 'accepts a folder and reports the file count' {
        Write-Utf16Job -Path $script:Job -Text (New-JobXml)
        Write-Utf16Job -Path (Join-Path $script:Dir 'other.xml') -Text (New-JobXml -MappingUid ([guid]::NewGuid().ToString()))
        $out = & $script:Script -Path $script:Dir *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '2 file\(s\)'
    }

    It 'exits 1 on a path that does not exist' {
        & $script:Script -Path (Join-Path $TestDrive 'nowhere') *>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
}
