BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Script = Join-Path (Get-RepoRoot) 'skills/dw-data-access/scripts/Copy-DwIntegrationJob.ps1'
}

Describe 'Copy-DwIntegrationJob' {
    BeforeEach {
        # TestDrive persists across tests in one file, so each case gets its
        # own pair — the script deliberately refuses an existing destination.
        $case = [guid]::NewGuid().ToString('n')
        $script:Src = Join-Path $TestDrive "Orders export $case.xml"
        $script:Dst = Join-Path $TestDrive "Orders export $case nightly.xml"
        Write-Utf16Job -Path $script:Src -Text (New-JobXml)
    }

    Context 'the dry run' {
        It 'writes nothing without -Apply' {
            & $script:Script -SourcePath $script:Src -DestinationPath $script:Dst | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath $script:Dst | Should -BeFalse
        }

        It 'prints the diff and the dry-run banner' {
            $out = & $script:Script -SourcePath $script:Src -DestinationPath $script:Dst *>&1 | Out-String
            $out | Should -Match 'DRY RUN'
            $out | Should -Match 'Diff \(decoded source vs decoded copy\)'
        }
    }

    Context 'the -Apply path' {
        It 'writes UTF-16LE with a BOM and round-trips' {
            & $script:Script -SourcePath $script:Src -DestinationPath $script:Dst -Apply | Out-Null
            $LASTEXITCODE | Should -Be 0
            $bytes = [System.IO.File]::ReadAllBytes($script:Dst)
            $bytes[0] | Should -Be 0xFF
            $bytes[1] | Should -Be 0xFE
            (Read-Utf16Job -Path $script:Dst) | Should -Match '<Job>'
        }

        It 're-mints the mapping uid' {
            & $script:Script -SourcePath $script:Src -DestinationPath $script:Dst -Apply | Out-Null
            $copy = Read-Utf16Job -Path $script:Dst
            $copy | Should -Not -Match '11111111-1111-1111-1111-111111111111'
            [regex]::Match($copy, 'uid="([^"]+)"').Groups[1].Value | Should -Match '^[0-9a-f-]{36}$'
        }

        It 'keeps the mapping uid with -KeepMappingUids' {
            & $script:Script -SourcePath $script:Src -DestinationPath $script:Dst -Apply -KeepMappingUids | Out-Null
            (Read-Utf16Job -Path $script:Dst) | Should -Match '11111111-1111-1111-1111-111111111111'
        }

        It 're-points a named element with -SetNode' {
            & $script:Script -SourcePath $script:Src -DestinationPath $script:Dst -Apply -SetNode @{ SqlConnectionString = 'Server=.;Catalog=Other;' } | Out-Null
            $copy = Read-Utf16Job -Path $script:Dst
            $copy | Should -Match 'Catalog=Other'
            $copy | Should -Not -Match 'Catalog=Dw'
        }

        It 'escapes a -SetNode value rather than injecting markup' {
            & $script:Script -SourcePath $script:Src -DestinationPath $script:Dst -Apply -SetNode @{ SqlConnectionString = 'a<b&c' } | Out-Null
            $copy = Read-Utf16Job -Path $script:Dst
            $copy | Should -Match 'a&lt;b&amp;c'
            { [xml]$copy } | Should -Not -Throw
        }
    }

    Context 'the refusals' {
        It 'refuses a UTF-8 source' {
            $utf8 = Join-Path $TestDrive "utf8 $case.xml"
            Set-Content -LiteralPath $utf8 -Value (New-JobXml) -Encoding utf8NoBOM
            { & $script:Script -SourcePath $utf8 -DestinationPath $script:Dst -Apply } |
                Should -Throw '*UTF-16LE BOM*'
            Test-Path -LiteralPath $script:Dst | Should -BeFalse
        }

        It 'refuses a -SetNode element the document does not carry' {
            { & $script:Script -SourcePath $script:Src -DestinationPath $script:Dst -SetNode @{ NoSuchNode = 'x' } } |
                Should -Throw '*carries no <NoSuchNode> element*'
        }

        It 'refuses to overwrite an existing destination' {
            Write-Utf16Job -Path $script:Dst -Text (New-JobXml)
            { & $script:Script -SourcePath $script:Src -DestinationPath $script:Dst -Apply } |
                Should -Throw '*already exists*'
        }

        It 'refuses a missing source' {
            { & $script:Script -SourcePath (Join-Path $TestDrive 'nope.xml') -DestinationPath $script:Dst } |
                Should -Throw '*No such job file*'
        }
    }

    Context 'the credential warning' {
        It 'warns on a credential found in the DECODED text' {
            Write-Utf16Job -Path $script:Src -Text (New-JobXml -SourceConnection 'Server=.;User Id=sa;Password=hunter2;')
            $out = & $script:Script -SourcePath $script:Src -DestinationPath $script:Dst *>&1 | Out-String
            $out | Should -Match 'carries a credential'
            $out | Should -Match 'SourceServerSSPI'
        }
    }
}
