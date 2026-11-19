# Hermetic controls for the recipe set (dw-demo-ledger Invoke-DwRecipeSet.ps1). The set script, its
# helpers, the schemas and the real recipes are copied into TestDrive beside a stub Invoke-DwRecipe.ps1
# that records each call and writes the report a run would, so no host, database or network is reached.
# What is under test is the set's own work: selection by input section, the dependency order, the
# three passes, the debts paid once, -Only, -Skip, -PayDebts, -LayerDelivered and the summary.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Source = Join-Path (Get-RepoRoot) 'skills/dw-demo-ledger'

    function New-SetSandbox {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $skill = Join-Path $root 'skills/dw-demo-ledger'
        $null = New-Item -ItemType Directory -Force (Join-Path $skill 'scripts'), (Join-Path $skill 'assets')
        foreach ($f in @('Invoke-DwRecipeSet.ps1', 'Ledger.Core.ps1', 'Recipe.Core.ps1')) { Copy-Item (Join-Path $script:Source "scripts/$f") (Join-Path $skill 'scripts') }
        foreach ($f in @('recipe.schema.json', 'recipe-input.schema.json', 'recipe-input.example.json')) { Copy-Item (Join-Path $script:Source "assets/$f") (Join-Path $skill 'assets') }
        Copy-Item (Join-Path $script:Source 'assets/recipes') (Join-Path $skill 'assets') -Recurse
        # The stub runner: same parameters, one recorded call, a report shaped like the real one.
        Set-Content -LiteralPath (Join-Path $skill 'scripts/Invoke-DwRecipe.ps1') -Encoding utf8 -Value @'
[CmdletBinding(SupportsShouldProcess)]
param([string]$Recipe, [string]$InputPath, [switch]$Apply, [string]$BaseUrl, [string]$ApiToken, [string]$McpToken, [switch]$McpOnly,
    [string[]]$Surfaces, [switch]$AllowSql, [string]$SqlServer, [string]$Database, [string]$LedgerBuildFile, [string]$Manifest, [string]$SolutionPath,
    [string]$Debts = 'Run', [string[]]$DebtNames, [switch]$SkipVerify, [string]$ReportPath, [switch]$AllowSelfSignedCertificate)
$s = $global:SetStub
$area = $Recipe.Split('.')[0]
$doc = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../assets/recipes/$area/$Recipe.json") -Raw | ConvertFrom-Json -AsHashtable
$mode = if ($Debts -eq 'Only') { 'debts' } elseif ($Apply) { 'apply' } else { 'verify' }
$s.calls.Add([ordered]@{recipe = $Recipe; mode = $mode; debts = @($DebtNames | Where-Object { $_ }); skipVerify = [bool]$SkipVerify; defer = ($Debts -eq 'Defer'); mcpOnly = [bool]$McpOnly; apiToken = $ApiToken})
$changed = $mode -eq 'apply' -and -not $s.settled.Contains($Recipe)
$state = if ($mode -eq 'apply') { if ($changed) { 'CREATED' } else { 'UNCHANGED' } } elseif ($s.settled.Contains($Recipe) -or $s.applied.Contains($Recipe)) { 'UNCHANGED' } else { 'WOULD-CREATE' }
if ($mode -eq 'apply') { $null = $s.applied.Add($Recipe) }
$steps = @(); $checks = @()
if ($mode -ne 'debts') { $steps = @([ordered]@{step = 'one'; state = $state; key = 'k'}); $checks = @([ordered]@{name = 'one/k'; result = $(if ($state -like 'WOULD-*') { 'FAIL' } else { 'PASS' }); reason = $null}) }
$notes = @()
foreach ($d in @($DebtNames | Where-Object { $_ })) {
    # A debt the target does not owe is a NOTE line and no check, as the runner reports an index the target lacks.
    if ($s.debtNote.Contains($d)) { $notes += "NOTE debt/${d}: not owed, the target has no index"; continue }
    $checks += [ordered]@{name = "debt/$d"; result = $(if ($s.debtResult.Contains($d)) { $s.debtResult[$d] } else { 'PASS' }); reason = 'stub'}
}
if ($mode -ne 'debts' -and -not $SkipVerify) { $checks += [ordered]@{name = 'probe/p'; result = $(if ($s.probeFail.Contains($Recipe)) { 'FAIL' } else { 'PASS' }); reason = $null} }
$owed = if ($changed -and $Debts -eq 'Defer') { @($doc.debts) } else { @() }
"STEP one $state k"
foreach ($n in $notes) { $n }
foreach ($c in $checks) { "$($c.result) $($c.name)" }
$passed = @($checks | Where-Object { $_.result -eq 'PASS' }).Count
"${Recipe}: $passed of $($checks.Count) checks passed"
$report = [ordered]@{schema = 1; recipe = $Recipe; steps = $steps; checks = $checks; changed = $changed; debtsOwed = $owed; blocked = 0; passed = $passed; total = $checks.Count}
[IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 10))
if ($passed -eq $checks.Count -and $checks.Count) { exit 0 }
if ($mode -eq 'debts' -and -not $checks.Count) { exit 0 }
exit 1
'@
        return $root
    }
    function New-SetStub {
        $global:SetStub = @{calls = [Collections.Generic.List[object]]::new(); applied = [Collections.Generic.HashSet[string]]::new(); settled = [Collections.Generic.HashSet[string]]::new()
            debtResult = @{}; debtNote = [Collections.Generic.HashSet[string]]::new(); probeFail = [Collections.Generic.HashSet[string]]::new()}
    }
    function Write-SetInput([hashtable]$Extra = @{}, [string[]]$Drop = @()) {
        # The repository's example input: users.accounts, content.pages, checkout, prices, brand and history.
        $data = Get-Content -LiteralPath (Join-Path $script:Source 'assets/recipe-input.example.json') -Raw | ConvertFrom-Json -AsHashtable
        foreach ($k in $Drop) { $data.Remove($k) }
        foreach ($k in $Extra.Keys) { $data[$k] = $Extra[$k] }
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json')
        $data | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding utf8
        return $path
    }
    function Invoke-Set([string]$Root, [hashtable]$Arguments) {
        $out = & (Join-Path $Root 'skills/dw-demo-ledger/scripts/Invoke-DwRecipeSet.ps1') @Arguments *>&1 | ForEach-Object { "$_" }
        return @{lines = @($out); exit = $LASTEXITCODE}
    }
    function Get-Calls([string]$Mode) { @($global:SetStub.calls | Where-Object { -not $Mode -or $_.mode -eq $Mode }) }
    function Get-RecipeDocs {
        $docs = @{}
        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $script:Source 'assets/recipes') -Recurse -Filter '*.json') {
            $d = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -AsHashtable
            $docs[$d.id] = $d
        }
        return $docs
    }
    function Get-SelectedIds([string]$InputPath) {
        # The recipes the set must select: every recipe whose input section the file holds. Derived from the
        # recipes themselves, so a recipe added later is expected without editing a count here.
        $sections = @((Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -AsHashtable).Keys)
        $docs = Get-RecipeDocs
        return @($docs.Keys | Where-Object { $docs[$_].inputs.section -in $sections } | Sort-Object)
    }
    function Assert-DependencyOrder([string[]]$Ids) {
        # Every recipe runs after each recipe it depends on that the run includes; a run-last recipe is last.
        $docs = Get-RecipeDocs
        foreach ($id in $Ids) {
            foreach ($dep in @($docs[$id].dependsOn)) {
                if ($dep -and $dep.recipe -in $Ids) { [array]::IndexOf($Ids, $dep.recipe) | Should -BeLessThan ([array]::IndexOf($Ids, $id)) -Because "$id depends on $($dep.recipe)" }
            }
            if ($docs[$id].runsLast) { $Ids[-1] | Should -Be $id }
        }
    }
}

AfterAll { Remove-Variable -Name SetStub -Scope Global -ErrorAction SilentlyContinue }

Describe 'Invoke-DwRecipeSet' {
    BeforeEach { $script:Root = New-SetSandbox; New-SetStub }

    It 'without -Apply runs every recipe the input has a section for once, verify-only, dependencies first' {
        $in = Write-SetInput
        $expected = Get-SelectedIds $in
        $expected | Should -Contain 'orders.payment-methods'
        $r = Invoke-Set $script:Root @{InputPath = $in}
        $calls = Get-Calls
        $ran = @($calls | ForEach-Object { $_.recipe })
        @($ran | Sort-Object) | Should -Be $expected
        @($ran | Select-Object -Unique).Count | Should -Be $ran.Count
        Assert-DependencyOrder $ran
        # The checkout scopes methods to the account groups users.accounts creates, and signs in as its buyer.
        [array]::IndexOf($ran, 'users.accounts') | Should -BeLessThan ([array]::IndexOf($ran, 'orders.payment-methods'))
        @($calls | Where-Object { $_.mode -ne 'verify' }).Count | Should -Be 0
        ($r.lines -match '^NOTE commerce\.customer-prices: depends on pim\.identifiers, which this run does not include').Count | Should -Be 1
        $r.lines | Should -Contain "recipe set: 0 of $($expected.Count) recipes passed"
        $r.exit | Should -Be 1
    }
    It 'with -Apply applies in order with debts deferred, pays each owed debt once (recycle last), then verifies every recipe' {
        $in = Write-SetInput
        $n = (Get-SelectedIds $in).Count
        $r = Invoke-Set $script:Root @{InputPath = $in; Apply = $true}
        $apply = Get-Calls 'apply'
        $apply.Count | Should -Be $n
        Assert-DependencyOrder @($apply | ForEach-Object { $_.recipe })
        @($apply | Where-Object { -not ($_.defer -and $_.skipVerify) }).Count | Should -Be 0
        $debts = Get-Calls 'debts'
        # users.accounts owes a flush, two index builds and a recycle; content.design-styles a recycle: one recycle, after the rest.
        $paid = @($debts | ForEach-Object { $_.debts })
        @($paid | Where-Object { $_ -eq 'recycle' }).Count | Should -Be 1
        $paid[-1] | Should -Be 'recycle'
        $paid | Should -Contain 'index:Secondary users/Users.index'
        $all = @($global:SetStub.calls)
        $firstDebt = $all.IndexOf($debts[0]); $lastApply = $all.IndexOf($apply[-1]); $firstVerify = $all.IndexOf((Get-Calls 'verify')[0])
        $firstDebt | Should -BeGreaterThan $lastApply
        $firstVerify | Should -BeGreaterThan $all.IndexOf($debts[-1])
        (Get-Calls 'verify').Count | Should -Be $n
        $r.lines | Should -Contain "recipe set: $n of $n recipes passed"
        ($r.lines -match '^DEBT PASS recycle').Count | Should -Be 1
        $r.exit | Should -Be 0
    }
    It 'pays no debt when a second apply changes nothing, and still verifies' {
        $in = Write-SetInput
        $ids = Get-SelectedIds $in
        foreach ($id in $ids) { $null = $global:SetStub.settled.Add($id) }
        $r = Invoke-Set $script:Root @{InputPath = $in; Apply = $true}
        (Get-Calls 'debts').Count | Should -Be 0
        $r.lines | Should -Contain 'NOTE recipe set: no debt owed'
        (Get-Calls 'verify').Count | Should -Be $ids.Count
        $r.exit | Should -Be 0
    }
    It 'pays every debt of the selected recipes with -PayDebts even when nothing changed, and nothing without -Apply' {
        $null = $global:SetStub.settled.Add('users.accounts')
        $r = Invoke-Set $script:Root @{InputPath = (Write-SetInput); Apply = $true; Only = @('users.accounts'); PayDebts = $true}
        @(Get-Calls | ForEach-Object { $_.recipe } | Select-Object -Unique) | Should -Be @('users.accounts')
        @((Get-Calls 'debts') | ForEach-Object { $_.debts }) | Should -Be @('flush:Dynamicweb.Security.UserManagement.UserService', 'index:Users/Users.index', 'index:Secondary users/Users.index', 'recycle')
        $r.exit | Should -Be 0
        New-SetStub
        $r = Invoke-Set $script:Root @{InputPath = (Write-SetInput); Only = @('users.accounts'); PayDebts = $true}
        (Get-Calls 'debts').Count | Should -Be 0
        ($r.lines -match '^NOTE recipe set: -PayDebts without -Apply pays nothing; it would pay: flush:').Count | Should -Be 1
    }
    It 'fails the set when a debt stays OPEN, and names it' {
        $global:SetStub.debtResult['recycle'] = 'OPEN'
        $in = Write-SetInput
        $n = (Get-SelectedIds $in).Count
        $r = Invoke-Set $script:Root @{InputPath = $in; Apply = $true}
        ($r.lines -match '^DEBT OPEN recycle').Count | Should -Be 1
        # Every recipe passes its checks; the set still fails, on the debt alone.
        ($r.lines -match "^recipe set: $n of $n recipes passed; a debt is not paid$").Count | Should -Be 1
        $r.exit | Should -Be 1
    }
    It 'keeps a debt the target does not owe a NOTE when another debt of the same owner stays OPEN' {
        # users.accounts owes a flush, two index builds and a recycle; the target lacks one index and the recycle stays open.
        $null = $global:SetStub.debtNote.Add('index:Users/Users.index')
        $global:SetStub.debtResult['recycle'] = 'OPEN'
        $r = Invoke-Set $script:Root @{InputPath = (Write-SetInput); Apply = $true; Only = @('users.accounts')}
        ($r.lines -match '^DEBT NOTE index:Users/Users\.index').Count | Should -Be 1
        ($r.lines -match '^DEBT FAIL').Count | Should -Be 0
        ($r.lines -match '^DEBT OPEN recycle').Count | Should -Be 1
        $r.exit | Should -Be 1
    }
    It 'pays a debt a later recipe names in debtsPaid before that recipe runs, and not again at the end' {
        $file = Join-Path $script:Root 'skills/dw-demo-ledger/assets/recipes/orders/orders.completed-orders.json'
        $doc = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
        $doc.dependsOn[0].debtsPaid = @('flush:Dynamicweb.Security.UserManagement.UserService')
        $doc | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
        $r = Invoke-Set $script:Root @{InputPath = (Write-SetInput); Apply = $true}
        $all = @($global:SetStub.calls)
        $early = @($all | Where-Object { $_.mode -eq 'debts' -and 'flush:Dynamicweb.Security.UserManagement.UserService' -in $_.debts })
        $early.Count | Should -Be 1
        $ordersApply = @($all | Where-Object { $_.mode -eq 'apply' -and $_.recipe -eq 'orders.completed-orders' })[0]
        $all.IndexOf($early[0]) | Should -BeLessThan $all.IndexOf($ordersApply)
        ($r.lines -match '^== users\.accounts debts \(before orders\.completed-orders\)').Count | Should -Be 1
        $r.exit | Should -Be 0
    }
    It 'leaves out -Skip recipes, refuses an unknown id, and runs a layer-delivered section verify-only' {
        $r = Invoke-Set $script:Root @{InputPath = (Write-SetInput); Apply = $true; Skip = @('orders.completed-orders'); LayerDelivered = @('content.pages')}
        @(Get-Calls | Where-Object { $_.recipe -eq 'orders.completed-orders' }).Count | Should -Be 0
        ($r.lines -match '^\s*orders\.completed-orders\s+history\s.*SKIPPED').Count | Should -Be 1
        @(Get-Calls | Where-Object { $_.recipe -eq 'content.pages' } | ForEach-Object { $_.mode }) | Should -Be @('verify', 'verify')
        New-SetStub
        $r = Invoke-Set $script:Root @{InputPath = (Write-SetInput); Only = @('nothing.here')}
        ($r.lines -match "^FAIL recipe set: Runner input: no recipe 'nothing\.here'").Count | Should -Be 1
        (Get-Calls).Count | Should -Be 0
        $r.exit | Should -Be 1
    }
    It 'refuses a de-brand whose forbidden text another section writes, before any call' {
        $in = Write-SetInput @{debrand = @{forbidden = @(@{text = 'Example Trading'; replacement = 'Contoso'})}}
        $r = Invoke-Set $script:Root @{InputPath = $in; Apply = $true}
        ($r.lines -match "^FAIL recipe set: Runner input: the de-brand would never settle: 'Example Trading' is in section ").Count | Should -Be 1
        (Get-Calls).Count | Should -Be 0
        $r.exit | Should -Be 1
    }
    It 'runs the de-brand last, and fails a recipe whose verify pass fails while the others pass' {
        $global:SetStub.probeFail.Add('content.pages') | Out-Null
        $in = Write-SetInput @{debrand = @{forbidden = @(@{text = 'Northwind Legacy'; replacement = 'Contoso'})}}
        $n = (Get-SelectedIds $in).Count
        $r = Invoke-Set $script:Root @{InputPath = $in; Apply = $true; McpOnly = $true; ApiToken = 'stub-api-token-0000'}
        @(Get-Calls 'apply' | ForEach-Object { $_.recipe })[-1] | Should -Be 'content.page-seo'
        Assert-DependencyOrder @(Get-Calls 'apply' | ForEach-Object { $_.recipe })
        @(Get-Calls | Where-Object { -not $_.mcpOnly }).Count | Should -Be 0
        ($r.lines -match '^\s*content\.pages\s.*FAIL\s+failed in: verify').Count | Should -Be 1
        $r.lines | Should -Contain "recipe set: $($n - 1) of $n recipes passed"
        ($r.lines -join "`n") | Should -Not -Match 'stub-api-token'
        $r.exit | Should -Be 1
    }
}
