<#
.SYNOPSIS
    READ-ONLY. Hermetic Pester coverage for Dw.Api.psm1 and Dw.Api.Write.psm1.

.DESCRIPTION
    Every HTTP call and every SQL read is mocked, so this suite needs no host,
    no database and no network. It covers the four behaviours a caller cannot
    check by eye and the one contract that protects a live instance:

      1. Invoke-DwQuery walks the pages and concatenates them, reconciles the
         result against totalCount, and refuses a repeated page rather than
         doubling the rows.
      2. Invoke-DwApi retries a 429 and a read 5xx with exponential backoff,
         and does NOT retry a write 5xx, which may have applied before failing.
      3. ConvertTo-DwApiValue unrolls a DataRow field to a string, maps DBNull
         to $null, keeps typed primitives typed, and walks a payload recursively.
      4. Get-DwSqlCount returns an [int] and throws on a blank, because a blank
         is not a zero.
      5. Every write verb in Dw.Api.Write.psm1 is a reported no-op without
         -Apply, and issues no request at all.

.EXAMPLE
    pwsh -NoProfile -c "Invoke-Pester -Path skills/dw-data-access/scripts/tests/Dw.Api.Tests.ps1 -Output Normal"
#>
#Requires -Version 7.0
param()

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../Dw.Api.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $PSScriptRoot '../Dw.Api.Write.psm1') -Force -Global -ErrorAction Stop
    # A base URL that resolves nowhere: every call below is mocked, and a typo
    # in a mock must fail the test rather than reach a real host.
    Connect-Dw -BaseUrl 'https://dw.invalid' -ApiToken 'test-token' | Out-Null

    function New-HttpFailure([int]$Status) {
        $ex = [System.Exception]::new("HTTP $Status")
        $ex | Add-Member -NotePropertyName Response -NotePropertyValue (
            [pscustomobject]@{ StatusCode = [pscustomobject]@{ value__ = $Status } }) -Force
        $ex
    }
}

Describe 'Invoke-DwQuery: pages are walked, concatenated and reconciled' {
    It 'concatenates the pages and reconciles the total' {
        Mock Invoke-RestMethod -ModuleName 'Dw.Api' {
            if ($Uri -match 'PagingPage=1') {
                return [pscustomobject]@{ model = [pscustomobject]@{
                    totalCount = 3
                    data = @([pscustomobject]@{ id = 1 }, [pscustomobject]@{ id = 2 }) } }
            }
            [pscustomobject]@{ model = [pscustomobject]@{
                totalCount = 3; data = @([pscustomobject]@{ id = 3 }) } }
        }
        $result = Invoke-DwQuery 'UserList' -PagingSize 2
        $result.complete | Should -BeTrue
        $result.pages | Should -Be 2
        $result.totalCount | Should -Be 3
        $result.data.Count | Should -Be 3
        @($result.data.id) | Should -Be @(1, 2, 3)
    }

    It 'always sends PagingSize: a missing page size is how a default page size applies silently' {
        Mock Invoke-RestMethod -ModuleName 'Dw.Api' {
            [pscustomobject]@{ model = [pscustomobject]@{ totalCount = 1; data = @([pscustomobject]@{ id = 9 }) } }
        }
        Invoke-DwQuery 'UserList' -PagingSize 250 | Out-Null
        Should -Invoke Invoke-RestMethod -ModuleName 'Dw.Api' -Times 1 -Exactly `
            -ParameterFilter { $Uri -match 'PagingSize=250' }
    }

    It 'THROWS on a repeated page rather than doubling the rows' {
        Mock Invoke-RestMethod -ModuleName 'Dw.Api' {
            [pscustomobject]@{ model = [pscustomobject]@{
                totalCount = 4; data = @([pscustomobject]@{ id = 1 }, [pscustomobject]@{ id = 2 }) } }
        }
        { Invoke-DwQuery 'UserList' -PagingSize 2 } | Should -Throw '*repeated page*'
    }

    It 'THROWS on a short read: a membership test on a partial page reads present as ABSENT' {
        Mock Invoke-RestMethod -ModuleName 'Dw.Api' {
            [pscustomobject]@{ model = [pscustomobject]@{ totalCount = 96; data = @() } }
        }
        { Invoke-DwQuery 'FieldList' -PagingSize 10 } | Should -Throw '*of totalCount 96*'
    }

    It 'reports complete = $false when the verb answers no totalCount' {
        Mock Invoke-RestMethod -ModuleName 'Dw.Api' {
            [pscustomobject]@{ model = [pscustomobject]@{ data = @([pscustomobject]@{ id = 1 }) } }
        }
        (Invoke-DwQuery 'BareList').complete | Should -BeFalse
    }
}

Describe 'Invoke-DwApi: retry on 429 and a read 5xx, with exponential backoff' {
    BeforeEach {
        $script:delays = [System.Collections.Generic.List[int]]::new()
        Mock Start-Sleep -ModuleName 'Dw.Api' { $script:delays.Add($Milliseconds) }
    }

    It 'retries a read 5xx and backs off exponentially' {
        $script:attempts = 0
        Mock Invoke-RestMethod -ModuleName 'Dw.Api' {
            $script:attempts++
            if ($script:attempts -lt 3) { throw (New-HttpFailure 503) }
            [pscustomobject]@{ ok = $true }
        }
        (Invoke-DwApi 'GetPageById?Id=1' -RetryDelayMs 10).ok | Should -BeTrue
        $script:attempts | Should -Be 3
        @($script:delays) | Should -Be @(10, 20)
    }

    It 'retries a 429 even on a write: the server refused before it acted' {
        $script:attempts = 0
        Mock Invoke-RestMethod -ModuleName 'Dw.Api' {
            $script:attempts++
            if ($script:attempts -lt 2) { throw (New-HttpFailure 429) }
            [pscustomobject]@{ ok = $true }
        }
        (Invoke-DwApi 'UserSave' -Body @{ Model = @{} } -RetryDelayMs 10).ok | Should -BeTrue
        $script:attempts | Should -Be 2
    }

    It 'does NOT retry a write 5xx: it may have applied before it failed' {
        $script:attempts = 0
        Mock Invoke-RestMethod -ModuleName 'Dw.Api' {
            $script:attempts++
            throw (New-HttpFailure 500)
        }
        { Invoke-DwApi 'UserSave' -Body @{ Model = @{} } -RetryDelayMs 10 } | Should -Throw '*[500]*'
        $script:attempts | Should -Be 1
    }

    It 'gives up after -RetryCount attempts and names the status' {
        $script:attempts = 0
        Mock Invoke-RestMethod -ModuleName 'Dw.Api' { $script:attempts++; throw (New-HttpFailure 503) }
        { Invoke-DwApi 'GetPageById?Id=1' -RetryCount 2 -RetryDelayMs 10 } | Should -Throw '*[503]*'
        $script:attempts | Should -Be 3
    }

    It 'honours -RetryCount 0' {
        $script:attempts = 0
        Mock Invoke-RestMethod -ModuleName 'Dw.Api' { $script:attempts++; throw (New-HttpFailure 503) }
        { Invoke-DwApi 'GetPageById?Id=1' -RetryCount 0 } | Should -Throw
        $script:attempts | Should -Be 1
    }
}

Describe 'ConvertTo-DwApiValue: the payload fence' {
    It 'unrolls a DataRow field to a string instead of a JSON object' {
        $table = [System.Data.DataTable]::new('t')
        $null = $table.Columns.Add('Name', [string])
        $row = $table.NewRow(); $row['Name'] = 'Widget'; $table.Rows.Add($row)
        $fenced = ConvertTo-DwApiValue $table.Rows[0]['Name']
        $fenced | Should -BeOfType ([string])
        $fenced | Should -Be 'Widget'
    }

    It 'maps DBNull to $null' { ConvertTo-DwApiValue ([System.DBNull]::Value) | Should -Be $null }

    It 'preserves a bool and an int: the binder wants those typed' {
        (ConvertTo-DwApiValue $true) | Should -BeOfType ([bool])
        (ConvertTo-DwApiValue 42) | Should -BeOfType ([int])
    }

    It 'walks a Model hashtable recursively so a whole payload is fenced in one call' {
        $table = [System.Data.DataTable]::new('t')
        $null = $table.Columns.Add('Label', [string])
        $row = $table.NewRow(); $row['Label'] = 'L'; $table.Rows.Add($row)
        $fenced = ConvertTo-DwApiValue @{ Id = 7; Label = $table.Rows[0]['Label']; Missing = [System.DBNull]::Value }
        $fenced['Id'] | Should -Be 7
        $fenced['Label'] | Should -BeOfType ([string])
        $fenced['Missing'] | Should -Be $null
    }
}

Describe 'Get-DwSqlCount: a blank is not a zero' {
    It 'returns an [int]' {
        Mock Get-DwSqlScalar -ModuleName 'Dw.Api' { '5' }
        $count = Get-DwSqlCount 'SELECT COUNT(*) FROM Page'
        $count | Should -BeOfType ([int])
        $count | Should -Be 5
    }

    It 'THROWS on a blank, the shape that lets a delete gate pass on a read that never ran' {
        Mock Get-DwSqlScalar -ModuleName 'Dw.Api' { '' }
        { Get-DwSqlCount 'SELECT COUNT(*) FROM Page' } | Should -Throw '*blank is NOT a zero*'
    }

    It 'THROWS on a non-integer scalar' {
        Mock Get-DwSqlScalar -ModuleName 'Dw.Api' { 'abc' }
        { Get-DwSqlCount 'SELECT COUNT(*) FROM Page' } | Should -Throw '*not an integer*'
    }
}

Describe 'Dw.Api.Write: every write verb is a no-op without -Apply' {
    BeforeAll {
        $script:TempFile = Join-Path ([IO.Path]::GetTempPath()) ('dw-api-tests-' + [guid]::NewGuid().ToString('N') + '.txt')
        'payload' | Set-Content -LiteralPath $script:TempFile -NoNewline
    }
    AfterAll {
        Remove-Item -LiteralPath $script:TempFile -Force -ErrorAction SilentlyContinue
    }
    BeforeEach {
        Mock Invoke-RestMethod -ModuleName 'Dw.Api' { throw 'a dry run must issue no request' }
        Mock Invoke-WebRequest -ModuleName 'Dw.Api' { throw 'a dry run must issue no request' }
    }

    It 'Remove-DwUser reports and changes nothing' {
        $result = Remove-DwUser -Id 1332 -WarningAction SilentlyContinue
        $result.applied | Should -BeFalse
        $result.deleted | Should -BeFalse
        Should -Invoke Invoke-RestMethod -ModuleName 'Dw.Api' -Times 0 -Exactly
    }

    It 'Remove-DwGroup reports and changes nothing' {
        (Remove-DwGroup -Id 1340 -WarningAction SilentlyContinue).applied | Should -BeFalse
        Should -Invoke Invoke-RestMethod -ModuleName 'Dw.Api' -Times 0 -Exactly
    }

    It 'Remove-DwDynamicStructure reports and changes nothing' {
        $id = [guid]::NewGuid().ToString()
        (Remove-DwDynamicStructure -UniqueId $id -WarningAction SilentlyContinue).applied | Should -BeFalse
        Should -Invoke Invoke-RestMethod -ModuleName 'Dw.Api' -Times 0 -Exactly
    }

    It 'Remove-DwDynamicStructure refuses an integer id before any call: the verb binds the GUID' {
        { Remove-DwDynamicStructure -UniqueId '1' -Apply } | Should -Throw '*is not a GUID*'
    }

    It 'Set-DwGlobalSetting reports and changes nothing' {
        $result = Set-DwGlobalSetting -Key '/Globalsettings/Settings/Auditing/EnableAuditing' `
            -Value 'True' -ConfigFilePath $script:TempFile -EffectProbe { $true } `
            -WarningAction SilentlyContinue
        $result.applied | Should -BeFalse
        Should -Invoke Invoke-RestMethod -ModuleName 'Dw.Api' -Times 0 -Exactly
    }

    It 'Set-DwGlobalSetting refuses a key that is not a full settings path' {
        { Set-DwGlobalSetting -Key 'EnableAuditing' -Value 'True' -ConfigFilePath $script:TempFile `
            -EffectProbe { $true } -Apply } | Should -Throw '*full /Globalsettings/*'
    }

    It 'Send-DwFile reports and changes nothing' {
        $result = Send-DwFile -RelDir 'Templates/Designs' -LocalPath $script:TempFile `
            -DestName 'theme.css' -WarningAction SilentlyContinue
        $result.applied | Should -BeFalse
        Should -Invoke Invoke-WebRequest -ModuleName 'Dw.Api' -Times 0 -Exactly
    }

    It 'Send-DwFile refuses a destination name carrying a path: the name is never inferred' {
        { Send-DwFile -RelDir 'Templates' -LocalPath $script:TempFile -DestName 'sub/theme.css' -Apply } |
            Should -Throw '*bare filename*'
    }

    It 'Clear-DwRecycleBin reports and changes nothing' {
        $result = Clear-DwRecycleBin -EntityType 'Page' -Ids '8944' `
            -SnapshotSql 'SELECT PageId FROM Page WHERE PageDeleted = 1' -WarningAction SilentlyContinue
        $result.applied | Should -BeFalse
        Should -Invoke Invoke-RestMethod -ModuleName 'Dw.Api' -Times 0 -Exactly
    }

    It '-WhatIf also suppresses the write' {
        (Remove-DwUser -Id 1332 -Apply -WhatIf).applied | Should -BeFalse
        Should -Invoke Invoke-RestMethod -ModuleName 'Dw.Api' -Times 0 -Exactly
    }
}
