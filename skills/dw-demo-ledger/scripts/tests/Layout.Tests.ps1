<#
.SYNOPSIS
READ-ONLY. Green and red controls for the product edit layout and global field placement rules.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/edit-layout.md. Every rule is a pure
function over an in-memory layout or fill, so no database is needed; the SQL reads are exercised
through mocks only. Red controls: a short screen type, a dangling editor, a family field on no tab, a
tab that mixes two families, a family tab that also carries a standard field, a family above the tab
limit, a group and a tab above their limits, a tab named after the mechanism, no catch-all and two, a
duplicate group name, an undeclared division, a declared tab that is not on the layout, a tab declared
twice, and binding arguments with no limit. Field placement: Placement.Tests.ps1.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Layout.Tests.ps1
#>
#Requires -Version 7.0
param()
BeforeDiscovery {
    $script:versions = @('10.30.6', '10.29.8', '10.28.15')
}
BeforeAll {
    foreach ($file in @('Ledger.Core.ps1', 'Ledger.Observations.ps1', 'Ledger.Sql.ps1', 'Pim.Fields.ps1', 'Pim.Layout.ps1', 'Ledger.Transport.ps1', 'Ledger.Execute.ps1')) { . (Join-Path $PSScriptRoot "../$file") }
    $script:assets = Join-Path $PSScriptRoot '../../assets'
    $script:full = 'Dynamicweb.Products.UI.Screens.ProductEditScreen'
    function Get-Snapshot([string]$Version) {
        $root = Join-Path $assets "releases/$Version"
        $fs = @{}; foreach ($f in (Read-LedgerJson (Join-Path $root 'functions/pim.json')).functions) { $fs[$f.id] = $f }
        return @{ functions = $fs; root = $root }
    }
    function Get-SnapshotProbe($Snapshot, [string]$Path) { Read-LedgerJson (Join-Path $Snapshot.root $Path) (Join-Path $assets 'check.schema.json') }
    # New-TestLayout: tabs as an ordered map  tab name -> ordered map  group name -> editor system names.
    # A group name that starts with * is the catch-all group.
    function New-TestLayout {
        param([System.Collections.Specialized.OrderedDictionary]$Tabs, [string]$ScreenType = $script:full, [bool]$Active = $true)
        $l = [pscustomobject]@{ layouts = @([pscustomobject]@{ id = '1'; active = $Active; screenType = $ScreenType; name = 'Editor' }); tabs = @(); groups = @(); editors = @() }
        $ti = 0; $gi = 0
        foreach ($tn in $Tabs.Keys) {
            $ti++
            $l.tabs += [pscustomobject]@{ id = "$ti"; layoutId = '1'; order = $ti; name = $tn }
            foreach ($gn in $Tabs[$tn].Keys) {
                $gi++
                $l.groups += [pscustomobject]@{ id = "$gi"; tabId = "$ti"; catchAll = $gn.StartsWith('*'); order = $gi; name = $gn.TrimStart('*') }
                foreach ($e in @($Tabs[$tn][$gn])) { $l.editors += [pscustomobject]@{ groupId = "$gi"; systemName = $e } }
            }
        }
        return $l
    }
    function CatEd { param([string]$Category, [string[]]$Field) $Field | ForEach-Object { "CategoryFields|ProductCategory|$Category|$_" } }
    $script:stored = @{ 'Press|platen' = 1; 'Press|pressure' = 1; 'Film|width' = 1; 'Film|finish' = 1; 'Passport|gtin' = 1 }
    # The runner reads the build file as a hashtable; the rules are exercised on that shape.
    function New-Build2 {
        param($EditLayout)
        $b = @{ schema = 1; defaultLanguage = 'ENU'; pimShop = 'SHOP1'
                families = @(@{ name = 'Presses'; category = 'Press' }, @{ name = 'Films'; category = 'Film' })
                attributes = @(); rulings = @{}; productScope = @{ exclude = @() } }
        if ($EditLayout) { $b.editLayout = $EditLayout }
        return $b
    }
    $script:build2 = New-Build2
    # The good layout: General (shared, with the catch-all), one tab per family, a shared passport tab.
    $script:good = New-TestLayout -Tabs ([ordered]@{
        'General'          = [ordered]@{ 'Identity' = @('Name', 'Number'); '*Other fields' = @() }
        'Heat press'       = [ordered]@{ 'Platen' = @(CatEd Press platen, pressure) }
        'Transfer film'    = [ordered]@{ 'Roll' = @(CatEd Film width, finish) }
        'Product passport' = [ordered]@{ 'Identification' = @(CatEd Passport gtin) }
    })
    function Test-Aspect {
        param([string]$Aspect, $Layout, $Check, $Build = $script:build2, $Stored = $script:stored)
        Test-PimEditLayoutAspect -Aspect $Aspect -Layout $Layout -Build $Build -Check $Check -Stored $Stored
    }
}

Describe 'Snapshot entries for the edit layout and field placement (<_>)' -ForEach $versions {
    BeforeAll { $s = Get-Snapshot $_ }
    It 'keeps the function id pim.screen-layouts with one check per edit-layout aspect, limits as binding arguments' {
        $f = $s.functions['pim.screen-layouts']
        $f.name | Should -Be 'Product edit layout: a tab per family, shared tabs by a declared division, list presets'
        $f.inputs | Should -Contain 'editLayout'
        $checks = @($f.checks | ForEach-Object { Get-SnapshotProbe $s $_ })
        $checks.id | Should -Not -Contain 'pim.screen-layouts.layout'
        $checks.id | Should -Contain 'pim.screen-layouts.preset'
        $sql = @{}; foreach ($c in $checks) { $b = $c.bindings | Where-Object handler -EQ 'pim-edit-layout'; if ($b) { $sql[$b.arguments.aspect] = $b; $c.assertion.kind | Should -Be offenders; $b.localOnly | Should -BeTrue } }
        foreach ($a in 'screen-type', 'editors-resolve', 'family-tabs', 'tabs-per-family', 'scannable', 'names', 'catch-all', 'unique-group-names', 'division') { $sql.Keys | Should -Contain $a }
        $sql['tabs-per-family'].arguments.maxTabs | Should -Be 5
        $sql['scannable'].arguments.maxEditorsPerGroup | Should -Be 12
        $sql['scannable'].arguments.maxEditorsPerTab | Should -Be 30
        $sql['names'].arguments.bannedNames | Should -Contain 'Categories'
        foreach ($b in $sql.Values) { @(Test-PimLayoutArguments -Handler 'pim-edit-layout' -Arguments $b.arguments) | Should -BeNullOrEmpty }
    }
    It 'no longer lets a build rule the layout out because every family is small' {
        $f = $s.functions['pim.screen-layouts']
        @($f.notApplicable | ForEach-Object id) | Should -Be @('one-attribute-family')
        (Get-SnapshotProbe $s $f.notApplicable[0].probe).assertion.value | Should -Be 1
        Test-Path (Join-Path $s.root 'probes/pim/screen-layouts.ruling.max-fields.json') | Should -BeFalse
    }
    It 'adds pim.field-placement with one share check at 50 and the ground single-family-catalogue' {
        $f = $s.functions['pim.field-placement']
        @($f.notApplicable | ForEach-Object id) | Should -Be @('single-family-catalogue')
        $c = Get-SnapshotProbe $s $f.checks[0]
        $c.id | Should -Be 'pim.field-placement.global-fields-filled'
        ($c.bindings | Where-Object handler -EQ 'pim-field-placement').arguments.minSharePct | Should -Be 50
        @($c.bindings | Where-Object { $_.surface -ne 'sql' } | Where-Object status -NE 'planned') | Should -BeNullOrEmpty
    }
    It 'records the replaced check id in the migration map' {
        $m = Read-LedgerJson (Join-Path $s.root 'migration/pim-registry.json')
        $m.checks.ContainsKey('screen-layouts/layout') | Should -BeFalse
        $m.replaced['screen-layouts/layout'].replacedBy.Count | Should -Be 9
        $m.features['field-placement'] | Should -Be 'pim.field-placement'
    }
}

Describe 'Test-PimLayoutArguments' {
    It 'refuses an unknown aspect, a missing limit, a banned pattern that is not a regex, and a field-placement binding with no share' {
        (Test-PimLayoutArguments -Handler 'pim-edit-layout' -Arguments @{ aspect = 'pretty' }) -join ';' | Should -Match "unknown edit-layout aspect 'pretty'"
        (Test-PimLayoutArguments -Handler 'pim-edit-layout' -Arguments @{ aspect = 'tabs-per-family' }) -join ';' | Should -Match 'states no maxTabs'
        (Test-PimLayoutArguments -Handler 'pim-edit-layout' -Arguments @{ aspect = 'scannable'; maxEditorsPerGroup = 12 }) -join ';' | Should -Match 'states no maxEditorsPerGroup and maxEditorsPerTab'
        (Test-PimLayoutArguments -Handler 'pim-edit-layout' -Arguments @{ aspect = 'names' }) -join ';' | Should -Match 'lists no banned name or pattern'
        (Test-PimLayoutArguments -Handler 'pim-edit-layout' -Arguments @{ aspect = 'names'; bannedPatterns = @('(unclosed') }) -join ';' | Should -Match 'not a regular expression'
        (Test-PimLayoutArguments -Handler 'pim-field-placement' -Arguments @{}) -join ';' | Should -Match 'states no minSharePct'
        (Test-PimLayoutArguments -Handler 'pim-field-placement' -Arguments @{ minSharePct = 101 }) -join ';' | Should -Match 'states no minSharePct'
        @(Test-PimLayoutArguments -Handler 'pim-field-placement' -Arguments @{ minSharePct = [long]50 }) | Should -BeNullOrEmpty
    }
}

Describe 'Build schema: editLayout' {
    BeforeAll {
        $script:schema = Join-Path $assets 'build.schema.json'
        function Test-Build($EditLayout) {
            $b = @{ schema = 1; slug = 'x'; functions = @('pim.screen-layouts'); editLayout = $EditLayout
                    lock = @{ commit = ('a' * 40); manifest = 'm'; digest = 'sha256:' + ('b' * 64); checkIds = @() } }
            Test-Json -Json ($b | ConvertTo-Json -Depth 10) -SchemaFile $schema -ErrorAction SilentlyContinue
        }
    }
    It 'accepts a division with a reason and declared tabs' {
        Test-Build @{ division = 'role'; reason = 'marketing and engineering maintain different fields'
                      tabs = @(@{ name = 'General'; for = 'shared'; owner = 'product data' }, @{ name = 'Heat press'; for = 'Press' }) } | Should -BeTrue
    }
    It 'refuses an unknown division, a blank reason, a tab with no name and a tab with no for' {
        Test-Build @{ division = 'colour'; reason = 'r' } | Should -BeFalse
        Test-Build @{ division = 'role'; reason = ' ' } | Should -BeFalse
        Test-Build @{ division = 'role' } | Should -BeFalse
        Test-Build @{ division = 'role'; reason = 'r'; tabs = @(@{ name = ''; for = 'shared' }) } | Should -BeFalse
        Test-Build @{ division = 'role'; reason = 'r'; tabs = @(@{ name = 'A'; for = '' }) } | Should -BeFalse
        Test-Build @{ division = 'role'; reason = 'r'; tabs = @(@{ name = 'A' }) } | Should -BeFalse
    }
}

Describe 'Test-PimEditLayoutAspect' {
    It 'the good layout passes every aspect that needs no editLayout' {
        $limits = @{ maxTabs = 5; maxEditorsPerGroup = 12; maxEditorsPerTab = 30; bannedNames = @('Categories', 'Other'); bannedPatterns = @('_', 'Attrs$') }
        foreach ($a in 'screen-type', 'editors-resolve', 'family-tabs', 'tabs-per-family', 'scannable', 'names', 'catch-all', 'unique-group-names') {
            (Test-Aspect $a $script:good $limits).offenders | Should -BeNullOrEmpty -Because $a
        }
    }

    It 'screen-type: refuses a short screen type, an inactive layout, a layout with no tab and two active layouts' {
        $short = New-TestLayout -ScreenType 'ProductEditScreen' -Tabs ([ordered]@{ 'General' = [ordered]@{ 'Identity' = @('Name') } })
        $r = Test-Aspect 'screen-type' $short $null
        $r.offenders -join ';' | Should -Match "has screen type 'ProductEditScreen'"
        $r.offenders -join ';' | Should -Match 'no active layout with a tab'
        $inactive = New-TestLayout -Active $false -Tabs ([ordered]@{ 'General' = [ordered]@{ 'Identity' = @('Name') } })
        (Test-Aspect 'screen-type' $inactive $null).offenders -join ';' | Should -Match 'no active layout with a tab'
        (Test-Aspect 'screen-type' (New-TestLayout -Tabs ([ordered]@{})) $null).offenders -join ';' | Should -Match 'has no tab'
        $two = New-TestLayout -Tabs ([ordered]@{ 'General' = [ordered]@{ 'Identity' = @('Name') } })
        $two.layouts += [pscustomobject]@{ id = '2'; active = $true; screenType = $script:full; name = 'Second' }
        $two.tabs += [pscustomobject]@{ id = '9'; layoutId = '2'; order = 1; name = 'General' }
        (Test-Aspect 'screen-type' $two $null).offenders -join ';' | Should -Match '2 active layouts name the product edit screen'
    }
    It 'screen-type: does not flag an active layout of another, fully named screen' {
        $l = New-TestLayout -Tabs ([ordered]@{ 'General' = [ordered]@{ 'Identity' = @('Name') } })
        $l.layouts += [pscustomobject]@{ id = '2'; active = $true; screenType = 'Dynamicweb.Products.UI.Screens.GroupEditScreen'; name = 'Groups' }
        (Test-Aspect 'screen-type' $l $null).offenders | Should -BeNullOrEmpty
    }
    It 'every other aspect FAILs when no active layout names the product edit screen' {
        $short = New-TestLayout -ScreenType 'ProductEditScreen' -Tabs ([ordered]@{ 'General' = [ordered]@{ '*Other fields' = @() } })
        foreach ($a in 'editors-resolve', 'family-tabs', 'tabs-per-family', 'scannable', 'names', 'catch-all', 'unique-group-names') {
            (Test-Aspect $a $short @{ maxTabs = 5; maxEditorsPerGroup = 12; maxEditorsPerTab = 30 }).offenders -join ';' | Should -Match 'nothing was measured' -Because $a
        }
    }

    It 'editors-resolve: refuses a dangling category editor, a malformed one and a layout with no category editor; leaves standard names alone' {
        $eds = @(CatEd Press platen, gone) + @('CategoryFields|Press|platen', 'Name', 'CompletenessFields|CompletionRule|7')
        $l = New-TestLayout -Tabs ([ordered]@{ 'Heat press' = [ordered]@{ 'Platen' = $eds } })
        $r = Test-Aspect 'editors-resolve' $l $null
        $r.offenders.Count | Should -Be 2
        $r.offenders -join ';' | Should -Match "Press\|gone' matches no category field"
        $r.offenders -join ';' | Should -Match 'is not of the form'
        $r.measured | Should -Match '2 other editor\(s\) not judged'
        $none = New-TestLayout -Tabs ([ordered]@{ 'General' = [ordered]@{ 'Identity' = @('Name') } })
        (Test-Aspect 'editors-resolve' $none $null).offenders -join ';' | Should -Match 'nothing was proved'
    }

    It 'family-tabs: refuses a family field that is on no tab' {
        $l = New-TestLayout -Tabs ([ordered]@{ 'Heat press' = [ordered]@{ 'Platen' = @(CatEd Press platen) }; 'Film roll' = [ordered]@{ 'Roll' = @(CatEd Film width, finish) } })
        $r = Test-Aspect 'family-tabs' $l $null
        $r.offenders.Count | Should -Be 1
        $r.offenders[0] | Should -Match "family 'Presses': 1 of 2 field\(s\) of Press are on no tab \(pressure\)"
    }
    It 'family-tabs: refuses a tab that mixes two families' {
        $l = New-TestLayout -Tabs ([ordered]@{ 'Specifications' = [ordered]@{ 'Press specifications' = @(CatEd Press platen, pressure); 'Film specifications' = @(CatEd Film width, finish) } })
        (Test-Aspect 'family-tabs' $l $null).offenders -join ';' | Should -Match "tab 'Specifications' mixes the fields of 2 families \(Film, Press\)"
    }
    It 'family-tabs: refuses a family tab that also carries a standard field, a shared-category field or the catch-all' {
        foreach ($extra in @{ 'Extra' = @('Weight') }, @{ 'Extra' = @(CatEd Passport gtin) }, @{ '*Other fields' = @() }) {
            $groups = [ordered]@{ 'Platen' = @(CatEd Press platen, pressure) }
            foreach ($k in $extra.Keys) { $groups[$k] = $extra[$k] }
            $l = New-TestLayout -Tabs ([ordered]@{ 'Heat press' = $groups; 'Film roll' = [ordered]@{ 'Roll' = @(CatEd Film width, finish) } })
            (Test-Aspect 'family-tabs' $l $null).offenders -join ';' | Should -Match "tab 'Heat press' carries the fields of Press together with"
        }
    }
    It 'family-tabs: a shared category on its own tab is not a family and offends nothing; a build with no stored family field proves nothing' {
        (Test-Aspect 'family-tabs' $script:good $null).offenders | Should -BeNullOrEmpty
        (Test-Aspect 'family-tabs' $script:good $null -Stored @{ 'Passport|gtin' = 1 }).offenders -join ';' | Should -Match 'nothing was proved'
    }

    It 'tabs-per-family: counts the shared tabs plus the tabs of the family, and refuses a family above the limit' {
        $r = Test-Aspect 'tabs-per-family' $script:good @{ maxTabs = 3 }      # General + Passport shared, 1 own = 3
        $r.offenders | Should -BeNullOrEmpty
        $r.measured | Should -Match 'at most 3 tab'
        $r = Test-Aspect 'tabs-per-family' $script:good @{ maxTabs = 2 }
        $r.offenders.Count | Should -Be 2
        $r.offenders[0] | Should -Match "family 'Presses' sees 3 tabs \(2 shared, 1 that carry its fields\); the limit is 2"
    }

    It 'scannable: refuses a group above the group limit and a tab above the tab limit' {
        $many = 1..5 | ForEach-Object { "Std$_" }
        $l = New-TestLayout -Tabs ([ordered]@{ 'General' = [ordered]@{ 'A' = $many; 'B' = @('Name', 'Number') } })
        (Test-Aspect 'scannable' $l @{ maxEditorsPerGroup = 5; maxEditorsPerTab = 7 }).offenders | Should -BeNullOrEmpty
        $r = Test-Aspect 'scannable' $l @{ maxEditorsPerGroup = 4; maxEditorsPerTab = 6 }
        $r.offenders.Count | Should -Be 2
        $r.offenders -join ';' | Should -Match "group 'A' on tab 'General' holds 5 editors; the limit is 4"
        $r.offenders -join ';' | Should -Match "tab 'General' holds 7 editors; the limit is 6"
    }

    It 'names: refuses the mechanism words, a category id, an underscore and an Attrs suffix; exempts the catch-all group' {
        $c = @{ bannedNames = @('Categories', 'Custom', 'Other'); bannedPatterns = @('_', 'Attrs$', '\b(attributes?|misc)\b') }
        $l = New-TestLayout -Tabs ([ordered]@{
            'Categories'           = [ordered]@{ 'Press' = @('Name'); 'equipment_common' = @('Number') }
            'Equipment attributes' = [ordered]@{ 'PressAttrs' = @('EAN'); 'custom' = @('Weight'); ' ' = @('Volume') }
            'Heat press'           = [ordered]@{ 'Platen' = @('Active'); '*Other' = @() }
        })
        $r = Test-Aspect 'names' $l $c
        $o = $r.offenders -join ';'
        $r.offenders.Count | Should -Be 7
        $o | Should -Match "tab 'Categories' is named after the mechanism"
        $o | Should -Match "'Press' is a category id"
        $o | Should -Match "'equipment_common' matches the banned pattern '_'"
        $o | Should -Match "tab 'Equipment attributes' matches the banned pattern"
        $o | Should -Match "'PressAttrs' matches the banned pattern 'Attrs\$'"
        $o | Should -Match "'custom' is named after the mechanism"
        $o | Should -Match 'has no name'
        $o | Should -Not -Match "'Other'"
    }

    It 'catch-all: refuses none and refuses two' {
        $none = New-TestLayout -Tabs ([ordered]@{ 'General' = [ordered]@{ 'Identity' = @('Name') } })
        (Test-Aspect 'catch-all' $none $null).offenders -join ';' | Should -Match 'no catch-all group'
        $two = New-TestLayout -Tabs ([ordered]@{ 'General' = [ordered]@{ '*Other fields' = @() }; 'More' = [ordered]@{ '*Remaining' = @() } })
        (Test-Aspect 'catch-all' $two $null).offenders -join ';' | Should -Match '2 catch-all groups'
    }

    It 'unique-group-names: refuses the same group name on two tabs, whatever its case' {
        $l = New-TestLayout -Tabs ([ordered]@{ 'Heat press' = [ordered]@{ 'Dimensions' = @('Name') }; 'Film roll' = [ordered]@{ 'dimensions' = @('Number') } })
        $r = Test-Aspect 'unique-group-names' $l $null
        $r.offenders.Count | Should -Be 1
        $r.offenders[0] | Should -Match "'dimensions' is used 2 times \(tabs: Heat press, Film roll\)"
    }

    It 'division: FAILs when the build file states no editLayout, and passes a stated division with no tabs' {
        (Test-Aspect 'division' $script:good $null).offenders -join ';' | Should -Match 'has no editLayout'
        $b = New-Build2 -EditLayout @{ division = 'role'; reason = 'r' }
        $r = Test-Aspect 'division' $script:good $null -Build $b
        $r.offenders | Should -BeNullOrEmpty
        $r.measured | Should -Match "division 'role' stated, no tabs declared"
    }
    It 'division: declared tabs must be the layout tabs, shared tabs carry no family field, a category tab carries that category only' {
        $tabs = @(@{ name = 'General'; for = 'shared'; owner = 'product data' }, @{ name = 'Heat press'; for = 'Press' },
                  @{ name = 'Transfer film'; for = 'Film' }, @{ name = 'Product passport'; for = 'Passport'; owner = 'compliance' })
        $b = New-Build2 -EditLayout @{ division = 'source'; reason = 'r'; tabs = $tabs }
        (Test-Aspect 'division' $script:good $null -Build $b).offenders | Should -BeNullOrEmpty

        $bad = @(@{ name = 'General'; for = 'Press' }, @{ name = 'Heat press'; for = 'shared' },
                 @{ name = 'Transfer film'; for = 'Press' }, @{ name = 'Pricing'; for = 'shared' }, @{ name = 'Pricing'; for = 'shared' })
        $b2 = New-Build2 -EditLayout @{ division = 'role'; reason = 'r'; tabs = $bad }
        $o = (Test-Aspect 'division' $script:good $null -Build $b2).offenders -join ';'
        $o | Should -Match "tab 'General' is declared for Press and carries none of its fields"
        $o | Should -Match "tab 'Heat press' is declared shared and carries the fields of Press"
        $o | Should -Match "tab 'Transfer film' is declared for Press and also carries the fields of Film"
        $o | Should -Match "declared tab 'Pricing' is not on the layout"
        $o | Should -Match "editLayout declares tab 'Pricing' twice"
        $o | Should -Match "layout tab 'Product passport' is not declared"
    }
}

Describe 'Edit layout through the runner' {
    BeforeAll {
        $script:cap = @{ sql = @{ available = $true } }
        function New-LayoutCheck([string]$Aspect, [hashtable]$Limits = @{}) {
            $arguments = @{ aspect = $Aspect } + $Limits
            @{ schema = 1; id = "pim.screen-layouts.$Aspect"; functionId = 'pim.screen-layouts'
               intent = @{ proves = 'p'; level = 'applied'; scope = 's' }; assertion = @{ kind = 'offenders' }
               bindings = @(@{ id = 'admin-layout'; surface = 'admin-api'; status = 'planned'; handler = 'admin-pim-edit-layout'; reason = 'r' },
                            @{ id = 'local-sql'; surface = 'sql'; status = 'implemented'; handler = 'pim-edit-layout'; localOnly = $true; arguments = $arguments }) }
        }
    }
    BeforeEach { $script:LedgerPimLayout = @{}; $script:LedgerStoredFields = $null }
    It 'is a PASS row, a FAIL row with its offenders and measured text, and an ERROR when the layout cannot be read' {
        Mock Get-PimStoredField { $script:stored }
        Mock Get-PimEditLayout { $script:good }
        $c = New-LayoutCheck 'catch-all'
        $r = Invoke-LedgerCheck $c $script:build2 $cap @{ expectations = @{} } @('mcp', 'admin-api', 'sql') '.' 'pass-db' ''
        $r.result | Should -Be PASS; $r.surface | Should -Be sql; $r.measured | Should -Be '1 catch-all group(s)'
        Mock Get-PimEditLayout { New-TestLayout -Tabs ([ordered]@{ 'General' = [ordered]@{ 'Identity' = @('Name') } }) }
        $r = Invoke-LedgerCheck $c $script:build2 $cap @{ expectations = @{} } @('sql') '.' 'fail-db' ''
        $r.result | Should -Be FAIL; $r.measured | Should -Be '0 catch-all group(s)'
        $r.offenders -join ';' | Should -Match 'no catch-all group'
        Mock Get-PimEditLayout { throw "Invalid object name 'ScreenLayout'" }
        (Invoke-LedgerCheck $c $script:build2 $cap @{ expectations = @{} } @('sql') '.' 'broken-db' '').result | Should -Be ERROR
    }
    It 'reads the layout once per database for every aspect' {
        Mock Get-PimStoredField { $script:stored }
        Mock Get-PimEditLayout { $script:good }
        foreach ($a in 'catch-all', 'unique-group-names', 'family-tabs') { $null = Invoke-LedgerCheck (New-LayoutCheck $a) $script:build2 $cap @{ expectations = @{} } @('sql') '.' 'once-db' '' }
        Should -Invoke Get-PimEditLayout -Times 1 -Exactly
    }
    It 'refuses a binding whose limits are missing instead of judging with no limit' {
        Mock Get-PimStoredField { $script:stored }
        Mock Get-PimEditLayout { $script:good }
        (Invoke-LedgerCheck (New-LayoutCheck 'tabs-per-family') $script:build2 $cap @{ expectations = @{} } @('sql') '.' 'limits-db' '').result | Should -Be ERROR
        (Invoke-LedgerCheck (New-LayoutCheck 'tabs-per-family' @{ maxTabs = 5 }) $script:build2 $cap @{ expectations = @{} } @('sql') '.' 'limits-db' '').result | Should -Be PASS
    }
    It 'is UNVERIFIED without a local SQL capability: the planned Admin binding never runs' {
        (Invoke-LedgerCheck (New-LayoutCheck 'catch-all') $script:build2 @{} @{ expectations = @{} } @('mcp', 'admin-api', 'sql') '' '' '').result | Should -Be UNVERIFIED
    }
    It 'Get-PimEditLayout: keeps the pipes of an editor system name and of a tab name' {
        Mock Invoke-Sqlcmd-Rows {
            if ($Query -match 'FROM ScreenLayoutEditor') { return @('7|CategoryFields|ProductCategory|Press|platen~') }
            if ($Query -match 'FROM ScreenLayoutGroup') { return @('7|3|1|2|Other fields~') }
            if ($Query -match 'FROM ScreenLayoutTab') { return @('3|1|1|Press | heat~') }
            return @('1|1|Dynamicweb.Products.UI.Screens.ProductEditScreen|Editor~')
        }
        $l = Get-PimEditLayout -Server s -Database d
        $l.editors[0].systemName | Should -Be 'CategoryFields|ProductCategory|Press|platen'
        $l.tabs[0].name | Should -Be 'Press | heat'
        $l.groups[0].catchAll | Should -BeTrue
        (Resolve-PimEditLayout -Layout $l).tabs[0].groups[0].editors[0].field | Should -Be 'platen'
    }
    It 'Get-PimEditLayout: every read passes the local SELECT guard' {
        Mock Invoke-Sqlcmd-Rows { Assert-LedgerSelect $Query; @() }
        { Get-PimEditLayout -Server s -Database d } | Should -Not -Throw
        Should -Invoke Invoke-Sqlcmd-Rows -Times 4 -Exactly
    }
}
