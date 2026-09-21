BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Source = Join-Path (Get-RepoRoot) 'skills/dw-data-access/scripts/Register-DwScheduledTask.ps1'
    $script:AddIn = 'Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn, Dynamicweb.DataIntegration'
}

Describe 'Register-DwScheduledTask' {
    BeforeEach {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
        $script:Script = New-StubbedScript -ScriptPath $script:Source -Destination $dir -LogPath $script:Log `
            -TasksResponseJson '{"data":[{"taskName":"Nightly orders export"}]}'
    }

    Context 'the dry run' {
        It 'writes nothing without -Apply' {
            & $script:Script -TaskName 'Nightly orders export' -AddInTypeName $script:AddIn -Parameter @{ Activity = 'Orders export' } | Out-Null
            $LASTEXITCODE | Should -Be 0
            $log = Get-StubLog -LogPath $script:Log
            $log | Should -Not -Contain 'Invoke-DwSqlScalarWrite'
            ($log -join "`n") | Should -Not -Match 'Invoke-DwSqlScalarWrite|Clear-DwServiceCache'
        }

        It 'prints the plan and the literal settings XML' {
            $out = & $script:Script -TaskName 'T' -AddInTypeName $script:AddIn -Parameter @{ Activity = 'Orders export' } *>&1 | Out-String
            $out | Should -Match 'DRY RUN'
            $out | Should -Match '<Parameters addin="Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn">'
            $out | Should -Match 'name="Activity" value="Orders export"'
        }
    }

    Context 'the -Apply path' {
        It 'inserts, flushes TaskService, then verifies from the task list, in that order' {
            & $script:Script -TaskName 'Nightly orders export' -AddInTypeName $script:AddIn -Parameter @{ Activity = 'Orders export' } -Apply | Out-Null
            $LASTEXITCODE | Should -Be 0
            $calls = @(Get-StubLog -LogPath $script:Log | Where-Object { $_ -notmatch '^\s+param ' })
            $order = @($calls | Where-Object { $_ -match '^(Invoke-DwSqlScalarWrite|Clear-DwServiceCache|Invoke-DwApi)' })
            $order[0] | Should -Match '^Invoke-DwSqlScalarWrite'
            $order[1] | Should -Be 'Clear-DwServiceCache Dynamicweb.Scheduling.TaskService'
            $order[2] | Should -Match '^Invoke-DwApi Tasks'
        }

        It 'reads the task list with an explicit page size (the ten-row default hides a new task)' {
            & $script:Script -TaskName 'Nightly orders export' -AddInTypeName $script:AddIn -Apply | Out-Null
            (Get-StubLog -LogPath $script:Log) | Should -Contain 'Invoke-DwApi Tasks?PageSize=1000&Page=1'
        }

        It 'binds TaskParentId as NULL and every schedule column as -1' {
            & $script:Script -TaskName 'Nightly orders export' -AddInTypeName $script:AddIn -Apply | Out-Null
            $log = (Get-StubLog -LogPath $script:Log) -join "`n"
            $log | Should -Match 'TaskParentId, TaskBegin'
            $log | Should -Match 'VALUES \(@TaskName, NULL,'
            foreach ($p in 'Minute', 'Hour', 'Day', 'Wday') { $log | Should -Match "param $p=-1" }
            $log | Should -Match 'param TaskEnabled=0'
        }

        It 'registers enabled only when -Enabled is given' {
            & $script:Script -TaskName 'T' -AddInTypeName $script:AddIn -Apply -Enabled | Out-Null
            ((Get-StubLog -LogPath $script:Log) -join "`n") | Should -Match 'param TaskEnabled=1'
        }

        It 'fails when the task list does not return the task, despite the INSERT' {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $log = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).log"
            $s = New-StubbedScript -ScriptPath $script:Source -Destination $dir -LogPath $log -TasksResponseJson '{"data":[]}'
            $out = & $s -TaskName 'Missing' -AddInTypeName $script:AddIn -Apply *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'the row exists but GET /Admin/Api/Tasks does not return'
        }
    }

    Context 'the refusals' {
        It 'refuses a RunSql add-in (roadmap rule 10, no arbitrary SQL through a task)' {
            & $script:Script -TaskName 'T' -AddInTypeName 'Dynamicweb.Scheduling.RunSqlScheduledTaskAddIn, Dynamicweb' -Apply *>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            (Get-StubLog -LogPath $script:Log) | Should -Not -Contain 'Invoke-DwSqlScalarWrite'
        }

        It 'refuses a type name that is not assembly-qualified' {
            & $script:Script -TaskName 'T' -AddInTypeName 'Ns.Type' -Apply *>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
        }

        It 'refuses a comment past the nvarchar(255) limit rather than letting SQL Server refuse it' {
            $out = & $script:Script -TaskName 'T' -AddInTypeName $script:AddIn -Comment ('x' * 256) -Apply *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'nvarchar\(255\) and SQL Server'
        }
    }

    Context 'the settings XML' {
        It 'escapes only the parameter value, leaving the document markup literal' {
            $out = & $script:Script -TaskName 'T' -AddInTypeName $script:AddIn -Parameter @{ Activity = 'A & B' } *>&1 | Out-String
            $out | Should -Match 'value="A &amp; B"'
            $out | Should -Match '<Parameters addin='
            $out | Should -Not -Match '&lt;Parameters'
        }

        It 'repeats the type name WITHOUT the assembly inside the settings document' {
            $out = & $script:Script -TaskName 'T' -AddInTypeName $script:AddIn *>&1 | Out-String
            $out | Should -Not -Match '<Parameters addin="[^"]*, Dynamicweb.DataIntegration"'
        }
    }
}
