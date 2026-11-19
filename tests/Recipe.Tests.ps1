# Hermetic controls for the recipe runner (dw-demo-ledger Invoke-DwRecipe.ps1, Find-DwRecipe.ps1 and
# the Recipe.*.ps1 helpers). The runner and its assets are copied into TestDrive beside a recording
# stub of Dw.Api.psm1 and stub child scripts, so no host, database or network is reached. The stub
# target answers in the shapes measured on a live site: lists under one member for writes,
# {count, data} for reads, null members left out, and no group type on the MCP group reads.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:RepoRoot = Get-RepoRoot
    $script:Source = Join-Path $script:RepoRoot 'skills/dw-demo-ledger'
    . (Join-Path $script:Source 'scripts/Ledger.Core.ps1')
    . (Join-Path $script:Source 'scripts/Recipe.Core.ps1')

    function New-RecipeSandbox {
        # A copy of the skill's scripts and assets (no release snapshots) with stub transport and child scripts.
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $skill = Join-Path $root 'skills/dw-demo-ledger'
        $null = New-Item -ItemType Directory -Force (Join-Path $skill 'scripts'), (Join-Path $skill 'assets'), (Join-Path $root 'skills/dw-data-access/scripts'), (Join-Path $root 'skills/dw-demo-base/scripts')
        Copy-Item (Join-Path $script:Source 'scripts/*.ps1') (Join-Path $skill 'scripts')
        Get-ChildItem (Join-Path $script:Source 'assets') | Where-Object { $_.Name -ne 'releases' } | Copy-Item -Destination (Join-Path $skill 'assets') -Recurse
        Set-Content -LiteralPath (Join-Path $root 'skills/dw-data-access/scripts/Dw.Api.psm1') -Encoding utf8 -Value @'
function Write-StubLog([string]$Line) { $global:RecipeStub.log.Add($Line) }
function Connect-Dw { param($BaseUrl, $ApiToken, $McpToken, $SqlConnection, $SolutionPath, [switch]$AllowSelfSignedCertificate)
    Write-StubLog 'Connect-Dw'
    @{BaseUrl = $(if ($BaseUrl) { $BaseUrl } else { 'https://stub.invalid' }); ApiToken = $(if ($ApiToken) { $ApiToken } else { $env:DW_API_TOKEN }); McpToken = $(if ($McpToken) { $McpToken } else { $env:DW_MCP_TOKEN }); SkipCert = $false} }
function Assert-DwConnection { $true }
function Get-DwMcpTools { , @($global:RecipeStub.tools.Keys | ForEach-Object { [pscustomobject]@{name = $_; inputSchema = $global:RecipeStub.tools[$_]} }) }
function Invoke-DwMcp { param($Tool, [hashtable]$Arguments, [switch]$Raw, $TimeoutSec)
    Write-StubLog ("mcp $Tool " + ($Arguments | ConvertTo-Json -Compress -Depth 10)); & $global:RecipeStub.mcp $Tool $Arguments }
function Invoke-DwApi { param($Command, $Body, $Method, $TimeoutSec, $RetryCount, $RetryDelayMs)
    Write-StubLog ("api $Command " + $(if ($null -ne $Body) { $Body | ConvertTo-Json -Compress -Depth 10 })); & $global:RecipeStub.api $Command $Body }
function Clear-DwServiceCache { param([string[]]$CacheTypeName, [switch]$All) Write-StubLog ("flush " + ($CacheTypeName -join ',')) }
Export-ModuleMember -Function *
'@
        # A shipped child script stub logs its arguments; no param block, so every argument is in $args.
        $child = 'Add-Content -LiteralPath $env:RECIPE_TEST_CHILDLOG -Value ("{0} {1}" -f (Split-Path -Leaf $PSCommandPath), ($args -join '' ''))'
        foreach ($path in @('skills/dw-data-access/scripts/Build-DwProductIndex.ps1', 'skills/dw-data-access/scripts/Invoke-DwAssortmentBuild.ps1', 'skills/dw-demo-base/scripts/Restart-DwHost.ps1')) {
            Set-Content -LiteralPath (Join-Path $root $path) -Value ($child + "`nexit 0") -Encoding utf8
        }
        return $root
    }
    function Get-Schema([string[]]$Properties, [string[]]$Required = @()) {
        $p = @{}; foreach ($n in $Properties) { $p[$n] = @{type = 'string'} }
        return @{type = 'object'; properties = $p; required = $Required}
    }
    function New-Stub {
        # An in-memory target. Ids are minted from 100; every read is {count, data}; a null value is left out.
        $global:RecipeStub = @{
            log = [Collections.Generic.List[string]]::new(); nextId = 100
            pages = [Collections.Generic.List[object]]::new(); rows = [Collections.Generic.List[object]]::new(); paragraphs = [Collections.Generic.List[object]]::new()
            fields = @{}; groups = [Collections.Generic.List[object]]::new(); users = [Collections.Generic.List[object]]::new()
            members = [Collections.Generic.List[object]]::new(); grants = [Collections.Generic.List[object]]::new()
            repositories = @(@{repository = 'Secondary users'; indexes = @('Users.index')}); refuseButtons = $false; urlReadyAfter = 0
            tools = @{
                get_pages_by_parent_id = Get-Schema @('parentId', 'areaId') @('parentId'); save_pages = Get-Schema @('pages') @('pages')
                get_page_item_field_values = Get-Schema @('pageId') @('pageId'); set_page_item_fields = Get-Schema @('pageId', 'fields') @('pageId', 'fields')
                get_grid_rows_by_page_id = Get-Schema @('pageId') @('pageId'); save_grid_rows = Get-Schema @('gridRows') @('gridRows')
                get_paragraphs_by_page_id = Get-Schema @('pageId') @('pageId'); save_paragraphs = Get-Schema @('paragraphs') @('paragraphs')
                get_paragraph_item_field_values = Get-Schema @('paragraphId') @('paragraphId'); set_paragraph_item_fields = Get-Schema @('paragraphId', 'fields') @('paragraphId', 'fields')
                fetch_frontend_page_html = Get-Schema @('path') @('path')
                get_user_groups = Get-Schema @(); save_user_groups = Get-Schema @('groups') @('groups')
                get_users_by_usernames = Get-Schema @('userNames') @('userNames'); create_users = Get-Schema @('users') @('users'); update_users = Get-Schema @('users') @('users')
                get_users_by_group_id = Get-Schema @('groupId') @('groupId'); assign_users_to_group = Get-Schema @('groupId', 'userIds') @('groupId', 'userIds')
                get_impersonatable_users = Get-Schema @('userId', 'groupId'); add_impersonatable_users = Get-Schema @('userId', 'impersonatableUserIds') @('impersonatableUserIds')
                get_index_repositories = Get-Schema @(); delete_pages = Get-Schema @('ids')
            }
        }
        $global:RecipeStub.api = {
            param($Command, $Body)
            $s = $global:RecipeStub
            if ($Command -like 'IndexBuildersByRepositoryAndIndexName*') { return [pscustomobject]@{model = @{data = @(@{name = 'Users'})}} }
            if ($Command -match '^GroupById\?Id=(\d+)$') {
                $g = @($s.groups | Where-Object { $_.id -eq [int]$Matches[1] })[0]
                return [pscustomobject]@{model = @{id = $g.id; parentId = $g.parentGroupId; userAndGroupTypeSystemName = $g.type; customerNumber = $g.customerNumber}}
            }
            [pscustomobject]@{status = 'ok'}
        }
        $global:RecipeStub.mcp = {
            param($Tool, $Arguments)
            $s = $global:RecipeStub
            $ok = { param($n) @{structuredContent = @{succeeded = $n; failed = 0; errors = @()}} }
            $mint = { $s.nextId++; $s.nextId }
            $rowsOf = { param($fieldMap) , @(foreach ($k in $fieldMap.Keys) { $r = @{fieldSystemName = $k}; if ($null -ne $fieldMap[$k]) { $r.value = $fieldMap[$k] }; $r }) }
            $data = switch ($Tool) {
                'get_pages_by_parent_id' { , @($s.pages | Where-Object { $_.parentPageId -eq [int]$Arguments.parentId }) }
                'save_pages' {
                    foreach ($p in $Arguments.pages) {
                        if ([int]$p.id -eq 0) { $id = & $mint; $s.pages.Add(@{id = $id; parentPageId = [int]$p.parentPageId; menuText = $p.menuText; itemType = $p.itemType; sort = $p.sort}); $s.fields["page$id"] = [ordered]@{Title = $null} }
                    }
                    return (& $ok 1)
                }
                'get_page_item_field_values' { & $rowsOf $s.fields["page$($Arguments.pageId)"] }
                'set_page_item_fields' { foreach ($k in $Arguments.fields.Keys) { $s.fields["page$($Arguments.pageId)"][$k] = $Arguments.fields[$k] }; return (& $ok 1) }
                'get_grid_rows_by_page_id' { , @($s.rows | Where-Object { $_.pageId -eq [int]$Arguments.pageId }) }
                'save_grid_rows' { foreach ($r in $Arguments.gridRows) { if ([int]$r.id -eq 0) { $s.rows.Add(@{id = (& $mint); pageId = [int]$r.pageId; sort = $r.sort; definitionId = $r.definitionId; container = $r.container}) } }; return (& $ok 1) }
                'get_paragraphs_by_page_id' { , @($s.paragraphs | Where-Object { $_.pageId -eq [int]$Arguments.pageId }) }
                'save_paragraphs' {
                    foreach ($p in $Arguments.paragraphs) {
                        if ([int]$p.id -eq 0) { $id = & $mint; $s.paragraphs.Add(@{id = $id; pageId = [int]$p.pageId; gridRowId = [int]$p.gridRowId; gridRowColumn = $p.gridRowColumn; sort = $p.sort; itemType = $p.itemType}); $s.fields["para$id"] = [ordered]@{Title = $null; Text = $null; FirstButton = 'default'} }
                    }
                    return (& $ok 1)
                }
                'get_paragraph_item_field_values' { & $rowsOf $s.fields["para$($Arguments.paragraphId)"] }
                'set_paragraph_item_fields' {
                    $failed = 0
                    foreach ($k in $Arguments.fields.Keys) {
                        if ($s.refuseButtons -and $k -like '*Button') { $failed++; continue }
                        $s.fields["para$($Arguments.paragraphId)"][$k] = $Arguments.fields[$k]
                    }
                    return @{structuredContent = @{succeeded = $Arguments.fields.Count - $failed; failed = $failed}}
                }
                'fetch_frontend_page_html' {
                    $s.fetches++
                    $page = @($s.pages | Where-Object { "/en-us/$($_.menuText.ToLower().Replace(' ', '-'))" -eq $Arguments.path })[0]
                    if (-not $page -or $s.fetches -le $s.urlReadyAfter) { return @{structuredContent = @{statusCode = 404; path = $Arguments.path}} }
                    return @{structuredContent = @{statusCode = 200; title = $page.menuText; path = $Arguments.path}}
                }
                # The group read leaves the type out, as measured: only GroupById on the Management API returns it.
                'get_user_groups' { , @($s.groups | ForEach-Object { @{id = $_.id; name = $_.name; parentGroupId = $_.parentGroupId; customerNumber = $_.customerNumber} }) }
                'save_user_groups' {
                    foreach ($g in $Arguments.groups) {
                        if ([int]$g.id -eq 0) { $s.groups.Add(@{id = (& $mint); name = $g.name; parentGroupId = [int]$g.parentGroupId; customerNumber = $g.customerNumber; type = $null}) }
                        else { $row = @($s.groups | Where-Object { $_.id -eq [int]$g.id })[0]; if ($g.Contains('userAndGroupType')) { $row.type = $g.userAndGroupType }; if ($g.Contains('customerNumber')) { $row.customerNumber = $g.customerNumber } }
                    }
                    return (& $ok 1)
                }
                'get_users_by_usernames' { , @($s.users | Where-Object { $_.userName -in $Arguments.userNames }) }
                'create_users' { foreach ($u in $Arguments.users) { $s.users.Add(@{id = (& $mint); userName = $u.userName; customerNumber = $u.customerNumber; hasPassword = [bool]$u.password}) }; return (& $ok 1) }
                'update_users' { foreach ($u in $Arguments.users) { foreach ($row in $s.users) { if ($row.id -eq $u.id) { $row.customerNumber = $u.customerNumber } } }; return (& $ok 1) }
                'get_users_by_group_id' { $ids = @($s.members | Where-Object { $_.groupId -eq [int]$Arguments.groupId } | ForEach-Object { $_.userId }); , @($s.users | Where-Object { $_.id -in $ids }) }
                'assign_users_to_group' { foreach ($u in $Arguments.userIds) { $s.members.Add(@{groupId = [int]$Arguments.groupId; userId = [int]$u}) }; return (& $ok 1) }
                'get_impersonatable_users' { $ids = @($s.grants | Where-Object { $_.from -eq [int]$Arguments.userId } | ForEach-Object { $_.to }); , @($s.users | Where-Object { $_.id -in $ids }) }
                'add_impersonatable_users' { foreach ($u in $Arguments.impersonatableUserIds) { $s.grants.Add(@{from = [int]$Arguments.userId; to = [int]$u}) }; return (& $ok 1) }
                'get_index_repositories' { , @($s.repositories) }
                default { return @{isError = $true; content = @(@{text = 'unknown tool'})} }
            }
            return @{structuredContent = @{count = @($data).Count; data = $data}}
        }
        $global:RecipeStub.fetches = 0
    }
    function Write-Input([hashtable]$Section, [string]$Name, [hashtable]$Build = @{areaId = 1}) {
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json')
        @{schema = 1; build = $Build; $Name = $Section} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
        return $path
    }
    function Invoke-Runner {
        param([string]$Root, [hashtable]$Arguments)
        $script:ChildLog = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.log')
        $env:RECIPE_TEST_CHILDLOG = $script:ChildLog
        # No delivery reads leave the process: the hermetic runs permit MCP and the Management API only.
        if (-not $Arguments.Contains('Surfaces') -and -not $Arguments.Contains('McpOnly')) { $Arguments.Surfaces = @('mcp', 'admin-api') }
        $out = & (Join-Path $Root 'skills/dw-demo-ledger/scripts/Invoke-DwRecipe.ps1') @Arguments *>&1 | ForEach-Object { "$_" }
        return @{lines = @($out); exit = $LASTEXITCODE}
    }
    function Get-Writes { @($global:RecipeStub.log | Where-Object { $_ -match '^mcp (save_|set_|create_|update_|assign_|add_)|^api (UsersAddToGroups|UserImpersonateAdd|UserSetPassword)' }) }
    $script:PagesSection = @{pages = @(
        @{menuText = 'About us'; urlName = 'about-us'; itemType = 'Swift-v2_Page'; path = '/en-us/about-us'
            rows = @(@{sort = 1; definitionId = '1Column'; container = 'Grid'; itemType = 'Swift-v2_Row'})
            paragraphs = @(@{row = 1; column = 1; sort = 100; itemType = 'Swift-v2_Text'; fields = @{Title = 'About us'; Text = '<p>Copy.</p>'; FirstButton = ''}})},
        @{menuText = 'Our history'; urlName = 'our-history'; itemType = 'Swift-v2_Page'; parent = 'About us'}
    )}
    $script:UsersSection = @{
        groups = @(
            @{name = 'Example Trading'; kind = 'account'; customerNumber = 'C-1001'; users = @(@{userName = 'buyer@example.invalid'; passwordRef = 'buyer'})},
            @{name = 'Representatives'; kind = 'staff'; users = @(@{userName = 'rep@example.invalid'})})
        impersonation = @(@{impersonator = 'rep@example.invalid'; customer = 'buyer@example.invalid'})
    }
}

AfterAll {
    Remove-Variable -Name RecipeStub -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:RECIPE_TEST_CHILDLOG, Env:DW_MCP_TOKEN, Env:DW_API_TOKEN, Env:DW_RECIPE_SECRETS -ErrorAction SilentlyContinue
}

Describe 'Recipe engine: paths, tokens and matching' {
    It 'walks a nested forEach and hands each item its enclosing item as parent' {
        # Regression: a parameter named ForEach is the automatic enumerator inside a foreach loop.
        $section = @{groups = @(@{name = 'A'; users = @(@{userName = 'a1'}, @{userName = 'a2'})}, @{name = 'B'; users = @(@{userName = 'b1'})})}
        $items = Get-RecipeItems $section 'groups[*].users[*]'
        $items.Count | Should -Be 3
        $items[2].item.userName | Should -Be 'b1'
        $items[2].parent.name | Should -Be 'B'
        (Get-RecipeItems $section 'groups[*]')[0].parent | Should -BeNullOrEmpty
    }
    It 'keeps the type of a whole-value token and makes text of a token inside text' {
        $ctx = @{item = @{id = 7; name = 'x'}; results = @{}; secrets = @{}}
        $value = Expand-RecipeValue @{n = '{item.id}'; t = 'id-{item.id}'; s = '{text:item.id}'} $ctx
        $value.n | Should -Be 7
        $value.n -is [string] | Should -BeFalse
        $value.t | Should -Be 'id-7'
        $value.s | Should -BeOfType [string]
    }
    It 'uses a default only when the key or path is absent, never for a missing step result' {
        $ctx = @{item = @{parent = 'About us'}; results = @{pages = @{}}; secrets = @{}; key = 'x'}
        { Resolve-RecipeToken 'step.pages[item.parent].id|0' $ctx } | Should -Throw '*produced no value*'
        $ctx.item = @{}
        Resolve-RecipeToken 'step.pages[item.parent].id|0' $ctx | Should -Be 0
        $ctx.results.pages['About us'] = @{state = 'UNCHANGED'; values = @{id = 10}}
        $ctx.item = @{parent = 'About us'}
        Resolve-RecipeToken 'step.pages[item.parent].id|0' $ctx | Should -Be 10
    }
    It 'names a dependency that apply would create, so a verify run reports the dependant as WOULD-CREATE' {
        $ctx = @{item = @{parent = 'About us'}; results = @{pages = @{'About us' = @{state = 'WOULD-CREATE'; values = @{}}}}; secrets = @{}}
        { Resolve-RecipeToken 'step.pages[item.parent].id|0' $ctx } | Should -Throw -ExceptionType ([Collections.Generic.KeyNotFoundException])
    }
    It 'reads a secret by reference from DW_RECIPE_SECRETS, takes a default only when no reference is given' {
        $secrets = Read-RecipeSecrets '{"buyer":"s3cret-value"}'
        $ctx = @{item = @{passwordRef = 'buyer'}; secrets = $secrets; results = @{}}
        Resolve-RecipeToken 'secret.item.passwordRef' $ctx | Should -Be 's3cret-value'
        $ctx.item.passwordRef = 'nobody'
        { Resolve-RecipeToken 'secret.item.passwordRef|null' $ctx } | Should -Throw "*'nobody'*"
        $ctx.item = @{}
        Resolve-RecipeToken 'secret.item.passwordRef|null' $ctx | Should -BeNullOrEmpty
        { Read-RecipeSecrets '["x"]' } | Should -Throw '*JSON object*'
    }
    It 'flattens a [*] level across nested lists and object values, leaving out elements without the rest' {
        # get_shops nests models under folders under shops; a shop of type Shop has no dataModels at all.
        $shops = @{data = @(@{dataModels = @(@{name = 'F'; dataModels = @(@{id = 'G1'}, @{id = 'G2'})})}, @{topLevelProductGroups = @()}, @{dataModels = @(@{name = 'E'; dataModels = @(@{id = 'G3'})})})}
        $models = (Get-RecipeValue $shops 'data[*].dataModels[*].dataModels').value
        $models.Count | Should -Be 3
        $models[2].id | Should -Be 'G3'
        (Get-RecipeValue $shops 'data[*].dataModels').value.Count | Should -Be 2
        (Get-RecipeValue @{groups = @{a = @{id = 1}; b = @{id = 2}}} 'groups[*].id').value | Sort-Object | Should -Be @(1, 2)
        (Get-RecipeValue @{data = 'text'} 'data[*].x').found | Should -BeFalse
    }
    It 'fans text around one list-valued token out into a list, spliced into an enclosing list' {
        $ctx = @{item = @{key = 'k'; specFields = @(@{key = 'a'}, @{key = 'b'})}; results = @{categories = @{k = @{state = 'UNCHANGED'; values = @{id = 'cat'}}}}; secrets = @{}; key = 'k'}
        $value = Expand-RecipeValue @{one = 'P|{step.categories.id}|{item.specFields[*].key}'; many = @('ProductName', 'P|{item.specFields[*].key}'); ids = @('{step.categories.id}')} $ctx
        $value.one | Should -Be @('P|cat|a', 'P|cat|b')
        $value.many | Should -Be @('ProductName', 'P|a', 'P|b')
        $value.ids | Should -Be @('cat')
        { Expand-RecipeValue '{item.specFields[*].key}-{item.specFields[*].key}' $ctx } | Should -Throw '*more than one list-valued token*'
    }
    It 'keeps a one-element list a list through a token and a row field' {
        $ctx = @{item = @{specFields = @(@{key = 'a'})}; results = @{}; secrets = @{}; key = 'k'}
        $value = Expand-RecipeValue @{ids = 'P|{item.specFields[*].key}'; whole = '{item.specFields[*].key}'} $ctx
        , $value.ids | Should -BeOfType [Array]
        $value.ids.Count | Should -Be 1
        , $value.whole | Should -BeOfType [Array]
        $row = @{languageIds = @('ENU'); rules = @(@{ruleId = 7})}
        Get-RecipeDifferences $row (Expand-RecipeValue @{languageIds = @('ENU'); 'rules[*].ruleId' = @('{item.n}')} @{item = @{n = 7}; results = @{}; secrets = @{}}) 'read' | Should -BeNullOrEmpty
    }
    It 'maps a list-valued step key to the list of the values of those keys' {
        $ctx = @{item = @{next = @('B', 'C')}; results = @{states = @{B = @{state = 'UNCHANGED'; values = @{id = 2}}; C = @{state = 'CREATED'; values = @{id = 3}}}}; secrets = @{}; key = 'A'}
        (Expand-RecipeValue @{ids = '{step.states[item.next[*]].id|[]}'} $ctx).ids | Should -Be @(2, 3)
        $ctx.item = @{}
        , (Expand-RecipeValue @{ids = '{step.states[item.next[*]].id|[]}'} $ctx).ids | Should -BeOfType [Array]
        $ctx.item = @{next = @('D')}; $ctx.results.states.D = @{state = 'WOULD-CREATE'; values = @{}}
        { Expand-RecipeValue '{step.states[item.next[*]].id}' $ctx } | Should -Throw -ExceptionType ([Collections.Generic.KeyNotFoundException])
    }
    It 'compares lists element by element and in order' {
        Test-RecipeEqual @('a', 'b') @('a', 'b') | Should -BeTrue
        Test-RecipeEqual @('a', 'b') @('b', 'a') | Should -BeFalse
        Test-RecipeEqual @(5) @('5') | Should -BeTrue
        Test-RecipeEqual @('a') 'a' | Should -BeFalse
    }
    It 'takes an input path as a default, read only when the key is absent' {
        $ctx = @{item = @{name = 'Tools'}; results = @{models = @{top = @{state = 'UNCHANGED'; values = @{name = 'Top'}}}}; secrets = @{}; key = 'x'}
        Resolve-RecipeToken 'step.models[item.parent].name|item.name' $ctx | Should -Be 'Tools'
        $ctx.item.parent = 'top'
        Resolve-RecipeToken 'step.models[item.parent].name|item.name' $ctx | Should -Be 'Top'
        { Resolve-RecipeToken 'item.missing|not json' $ctx } | Should -Throw '*neither a JSON literal nor an input path*'
    }
    It 'compares typed values, and an absent value as empty text' {
        Test-RecipeEqual 5 '5' | Should -BeTrue
        Test-RecipeEqual 5 5.0 | Should -BeTrue
        Test-RecipeEqual 'Grid' 'grid' | Should -BeFalse
        Test-RecipeEqual $null '' | Should -BeTrue
        Test-RecipeEqual $null 0 | Should -BeFalse
    }
    It 'compares item-field rows name by name, an absent value member as null, a missing field as different' {
        $rows = @(@{fieldSystemName = 'Title'; value = 'About'}, @{fieldSystemName = 'Subtitle'})
        $spec = @{from = '{item.fields}'; key = 'fieldSystemName'; value = 'value'}
        (Get-RecipeMapDifferences $rows $spec @{item = @{fields = @{Title = 'About'; Subtitle = ''}}}).Count | Should -Be 0
        $differs = Get-RecipeMapDifferences $rows $spec @{item = @{fields = @{Title = 'Other'; Misspelt = 'x'}}}
        @($differs | Sort-Object) | Should -Be @('Misspelt', 'Title')
    }
    It 'fails loudly on a field the response does not carry, rather than reading it as a mismatch' {
        { Get-RecipeDifferences @{id = 1} @{customerNumber = 'C1'} 'get_user_groups' } | Should -Throw '*carries no field*'
    }
    It 'reads an absent member as null only where the recipe expects null, so price rows of other scopes do not match' {
        # The MCP price read leaves out every null scope member: a tier row has no userCustomerNumber member.
        $tier = @{id = 'P1'; quantity = 10; amount = 6}
        $contract = @{id = 'P2'; quantity = 0; amount = 7; userCustomerNumber = 'C-1'}
        (Get-RecipeDifferences $tier @{quantity = 10; userCustomerNumber = $null} 'get_prices_by_product_id').Count | Should -Be 0
        (Get-RecipeDifferences $contract @{userCustomerNumber = $null} 'get_prices_by_product_id') | Should -Be @('userCustomerNumber')
        $hits = Select-RecipeMatches @($tier, $contract) @{userCustomerNumber = 'C-1'} 'get_prices_by_product_id'
        @($hits).Count | Should -Be 1
        $hits[0].id | Should -Be 'P2'
        @(Select-RecipeMatches @($tier, $contract) @{quantity = 10; userCustomerNumber = $null} 'get_prices_by_product_id')[0].id | Should -Be 'P1'
        { Get-RecipeDifferences $tier @{amount = 6; customerNumber = 'C1'} 'get_prices_by_product_id' } | Should -Throw '*carries no field*'
    }
    It 'skips on any of a list of conditions, and compares a condition with a token of the input' {
        $ctx = @{input = @{buyer = @{account = 'C-1'}}; item = @{account = 'C-2'; quantity = 5}; results = @{}; secrets = @{}}
        Test-RecipeCondition @{path = 'item.account'; notEquals = '{input.buyer.account}'} $ctx | Should -BeTrue
        $ctx.item.account = 'C-1'
        Test-RecipeCondition @{path = 'item.account'; notEquals = '{input.buyer.account}'} $ctx | Should -BeFalse
        Test-RecipeCondition @(@{path = 'item.account'; notEquals = '{input.buyer.account}'}, @{path = 'item.quantity'; exists = $true}) $ctx | Should -BeTrue
        $ctx.item.Remove('quantity')
        Test-RecipeCondition @(@{path = 'item.account'; notEquals = '{input.buyer.account}'}, @{path = 'item.quantity'; exists = $true}) $ctx | Should -BeFalse
    }
    It 'reads a file the input names, relative to the input file, as base64 or as its size, and never outside that folder' {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Force (Join-Path $dir 'kit')
        [IO.File]::WriteAllBytes((Join-Path $dir 'kit/logo.svg'), [byte[]](60, 115, 118, 103, 62))
        Set-Content -LiteralPath (Join-Path $TestDrive 'outside.txt') -Value 'x'
        $ctx = @{item = @{file = 'kit/logo.svg'}; results = @{}; secrets = @{}; inputDir = $dir}
        Resolve-RecipeToken 'base64:item.file' $ctx | Should -Be 'PHN2Zz4='
        Resolve-RecipeToken 'bytes:item.file' $ctx | Should -Be 5
        $ctx.item.file = '../outside.txt'
        { Resolve-RecipeToken 'base64:item.file' $ctx } | Should -Throw '*outside the input file*'
        $ctx.item.file = (Join-Path $TestDrive 'outside.txt')
        { Resolve-RecipeToken 'bytes:item.file' $ctx } | Should -Throw '*not a path relative*'
        $ctx.item.file = 'kit/absent.svg'
        { Resolve-RecipeToken 'bytes:item.file' $ctx } | Should -Throw '*does not exist*'
    }
    It 'reads a typography member the read model leaves out as equal to an expected null, and to nothing else' {
        (Get-RecipeDifferences @{id = 't'; paragraphFont = 'Inter'} @{paragraphFont = 'Inter'; paragraphCustomFontId = $null; headingFontStyle = $null} 'get_typographies').Count | Should -Be 0
        { Get-RecipeDifferences @{id = 't'} @{paragraphCustomFontId = 'brand-400'} 'get_typographies' } | Should -Throw '*carries no field*'
        { Get-RecipeDifferences @{id = 't'} @{paragraphLetterSpacing = 0} 'get_typographies' } | Should -Throw '*carries no field*'
    }
    It 'refuses a host, a machine path or a credential literal in a recipe' {
        @(Test-RecipeForbidden @{source = 'see https://example.invalid'}).Count | Should -Be 1
        @(Test-RecipeForbidden @{query = 'C:\temp\x'}).Count | Should -Be 1
        @(Test-RecipeForbidden @{arguments = @{password = 'literal'}}).Count | Should -Be 1
        @(Test-RecipeForbidden @{arguments = @{password = '{secret.item.passwordRef}'}}).Count | Should -Be 0
    }
}

Describe 'Recipe reads: the SQL guard and the sign-in read-back' {
    BeforeAll {
        . (Join-Path $script:Source 'scripts/Ledger.Sql.ps1')
        . (Join-Path $script:Source 'scripts/Recipe.Transport.ps1')
    }
    It 'refuses anything but one local SELECT before a connection is opened' {
        $cap = @{sqlServer = '.'; database = 'Db'}
        { Invoke-RecipeSqlRows @{query = 'DELETE FROM AccessUser'} @{} $cap } | Should -Throw '*single local SELECT*'
        { Invoke-RecipeSqlRows @{query = 'SELECT 1; DROP TABLE x'} @{} $cap } | Should -Throw '*single local SELECT*'
        { Invoke-RecipeSqlRows @{query = 'SELECT 1'} @{} @{sqlServer = 'db.example.invalid'; database = 'Db'} } | Should -Throw '*explicit local server*'
    }
    It 'reads a password write back as a sign-in, and keeps neither the password nor the token' {
        $script:RecipeTarget = @{baseUrl = 'https://stub.invalid'; insecure = $false}
        Mock Invoke-WebRequest { [pscustomobject]@{StatusCode = 200; Content = '{"token":"issued-token-value"}'} }
        $ctx = @{item = @{userName = 'buyer@example.invalid'; passwordRef = 'buyer'}; secrets = @{buyer = 'pw-value-1'}; results = @{}}
        $rows = Invoke-RecipeSignIn @{operation = 'users/authenticate'; arguments = @{username = '{item.userName}'; password = '{secret.item.passwordRef}'}} $ctx
        $rows[0].signedIn | Should -BeTrue
        ($rows | ConvertTo-Json -Compress) | Should -Not -Match 'issued-token-value|pw-value-1'
        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Method -eq 'Post' -and $Uri -eq 'https://stub.invalid/dwapi/users/authenticate' -and $Body -match '"password":"pw-value-1"' }
        Mock Invoke-WebRequest { [pscustomobject]@{StatusCode = 401; Content = ''} }
        (Invoke-RecipeSignIn @{operation = 'users/authenticate'; arguments = @{username = 'u'; password = 'p'}} $ctx)[0].signedIn | Should -BeFalse
    }
    It 'reads a delivery route as the signed-in user, fills route placeholders from the arguments, and keeps the token' {
        $script:RecipeTarget = @{baseUrl = 'https://stub.invalid'; insecure = $false}
        $registry = @{dwapiSignInRoutes = @('users/authenticate')}
        Mock Invoke-WebRequest { [pscustomobject]@{StatusCode = 200; Content = '{"token":"issued-token-value"}'} } -ParameterFilter { $Method -eq 'Post' }
        Mock Invoke-WebRequest { [pscustomobject]@{StatusCode = 200; Content = '{"price":{"price":7}}'} } -ParameterFilter { $Method -eq 'Get' }
        $ctx = @{input = @{buyer = @{userName = 'buyer@example.invalid'; passwordRef = 'buyer'}}; item = @{}; secrets = @{buyer = 'pw-value-1'}; results = @{}}
        $binding = @{handler = 'dwapi-signed-in-get'; operation = 'ecommerce/products/{productId}'; arguments = @{productId = 'PROD 1'; CurrencyCode = 'USD'}; signIn = @{username = '{input.buyer.userName}'; password = '{secret.input.buyer.passwordRef}'}}
        $data = Invoke-RecipeDeliveryGet $binding $ctx $registry
        $data.price.price | Should -Be 7
        ($data | ConvertTo-Json -Compress) | Should -Not -Match 'issued-token-value|pw-value-1'
        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Method -eq 'Post' -and $Body -match '"password":"pw-value-1"' }
        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Method -eq 'Get' -and $Uri -eq 'https://stub.invalid/dwapi/ecommerce/products/PROD%201?CurrencyCode=USD' -and $Headers.Authorization -eq 'Bearer issued-token-value' }
        # An anonymous read sends no credential and needs every placeholder argument.
        $data = Invoke-RecipeDeliveryGet @{handler = 'dwapi-get'; operation = 'ecommerce/products/{productId}'; arguments = @{productId = 'P2'}} $ctx $registry
        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Method -eq 'Get' -and $Uri -eq 'https://stub.invalid/dwapi/ecommerce/products/P2' -and -not $Headers.Authorization }
        { Invoke-RecipeDeliveryGet @{handler = 'dwapi-get'; operation = 'ecommerce/products/{productId}'; arguments = @{}} $ctx $registry } | Should -Throw '*needs the argument productId*'
        Mock Invoke-WebRequest { [pscustomobject]@{StatusCode = 401; Content = ''} } -ParameterFilter { $Method -eq 'Post' }
        { Invoke-RecipeDeliveryGet $binding $ctx $registry } | Should -Throw '*could not sign in*'
    }
}

Describe 'Invoke-DwRecipe on content.pages' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        Remove-Item Env:DW_API_TOKEN -ErrorAction SilentlyContinue
        $script:Root = New-RecipeSandbox
        $script:InputFile = Write-Input $script:PagesSection 'content.pages'
    }

    It 'reports WOULD-CREATE for every object, dependants included, and writes nothing on an empty host' {
        New-Stub
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile}
        foreach ($line in @('STEP pages WOULD-CREATE About us', 'STEP pages WOULD-CREATE Our history', 'STEP page-title WOULD-CREATE About us', 'STEP rows WOULD-CREATE About us/1', 'STEP paragraphs WOULD-CREATE About us/1/100', 'STEP paragraph-fields WOULD-CREATE About us/1/100')) { $r.lines | Should -Contain $line }
        ($r.lines -match '^FAIL pages/Our history: absent: depends on pages ''About us'', which is would-create').Count | Should -Be 1
        ($r.lines -match '^STEP .* BLOCKED').Count | Should -Be 0
        $r.exit | Should -Be 1
        Get-Writes | Should -BeNullOrEmpty
    }

    It 'creates everything, reads every write back, then a verify and a second apply change nothing (build path A)' {
        New-Stub
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true}
        foreach ($line in @('STEP pages CREATED About us', 'PASS pages/About us', 'STEP pages CREATED Our history', 'STEP page-title UPDATED About us', 'STEP page-slug CREATED About us', 'STEP rows CREATED About us/1', 'STEP paragraphs CREATED About us/1/100', 'STEP paragraph-fields UPDATED About us/1/100', 'PASS paragraph-fields/About us/1/100', 'PASS probe/page-renders')) { $r.lines | Should -Contain $line }
        @($global:RecipeStub.log | Where-Object { $_ -match '^mcp save_pages .*"id":0' })[1] | Should -Match '"parentPageId":101'
        $r.exit | Should -Be 0
        $before = (Get-Writes).Count
        $v = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile}
        ($v.lines -match '^STEP ').Count | Should -Be (($v.lines -match '^STEP \S+ UNCHANGED ').Count)
        $v.lines[-1] | Should -Match '^content\.pages: (\d+) of \1 checks passed$'
        $v.exit | Should -Be 0
        $a = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true}
        $a.exit | Should -Be 0
        (Get-Writes).Count | Should -Be $before
    }

    It 'polls a probe whose state the platform publishes late or drops for a moment' {
        New-Stub
        $global:RecipeStub.urlReadyAfter = 1
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true}
        $r.lines | Should -Contain 'PASS probe/page-renders'
        $global:RecipeStub.fetches | Should -Be 2
    }

    It 'fails a field write the tool counts as failed, such as an empty button JSON' {
        New-Stub
        $global:RecipeStub.refuseButtons = $true
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true}
        ($r.lines -match '^FAIL paragraph-fields/About us/1/100: MCP set_paragraph_item_fields reported 1 failed item').Count | Should -Be 1
        $r.exit | Should -Be 1
    }

    It 'treats -WhatIf as verify-only even with -Apply' {
        New-Stub
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true; WhatIf = $true}
        Get-Writes | Should -BeNullOrEmpty
        $r.lines | Should -Contain 'STEP pages WOULD-CREATE About us'
    }

    It 'blocks a step whose tool the target does not offer, naming the tool' {
        New-Stub
        $global:RecipeStub.tools.Remove('get_pages_by_parent_id')
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile}
        $r.lines | Should -Contain 'STEP pages BLOCKED About us'
        ($r.lines -match "^OPEN pages/About us: no eligible find binding: MCP get_pages_by_parent_id is not offered by this target's tools/list").Count | Should -Be 1
        $r.exit | Should -Be 1
    }

    It 'refuses a call whose argument names disagree with the tool''s tools/list input schema' {
        New-Stub
        $global:RecipeStub.tools.get_pages_by_parent_id = Get-Schema @('parentPageId', 'areaId') @('parentPageId')
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile}
        ($r.lines -match 'disagree with its tools/list input schema; not in the schema: parentId').Count | Should -BeGreaterThan 0
        @($global:RecipeStub.log | Where-Object { $_ -match '^mcp get_pages_by_parent_id' }).Count | Should -Be 0
    }

    It 'blocks rather than writes when two objects match one natural key' {
        New-Stub
        $global:RecipeStub.pages.Add(@{id = 10; parentPageId = 0; menuText = 'About us'; itemType = 'Swift-v2_Page'})
        $global:RecipeStub.pages.Add(@{id = 12; parentPageId = 0; menuText = 'About us'; itemType = 'Swift-v2_Page'})
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true}
        $r.lines | Should -Contain 'STEP pages BLOCKED About us'
        ($r.lines -match '^OPEN pages/About us: 2 objects match the natural key').Count | Should -Be 1
        ($r.lines -match '^FAIL probe/page-unique').Count | Should -Be 1
        @($global:RecipeStub.log | Where-Object { $_ -match '^mcp save_pages' }).Count | Should -Be 0
    }

    It 'refuses an operation off the recipe allowlist before any call, even when the target offers it' {
        New-Stub
        $file = Join-Path $script:Root 'skills/dw-demo-ledger/assets/recipes/content/content.pages.json'
        $doc = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
        $doc.steps[0].bindings[0].create.operation = 'delete_pages'
        $doc | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $file -Encoding utf8
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true}
        ($r.lines -match 'MCP delete_pages is not on the recipe write allowlist').Count | Should -BeGreaterThan 0
        @($global:RecipeStub.log | Where-Object { $_ -match '^mcp delete_pages' }).Count | Should -Be 0
    }

    It 'writes a report without values or tokens' {
        New-Stub
        $report = Join-Path $TestDrive 'report.json'
        $null = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true; ReportPath = $report}
        $json = Get-Content -LiteralPath $report -Raw
        $data = $json | ConvertFrom-Json -AsHashtable
        $data.result | Should -Be 'PASS'
        $data.mode | Should -Be 'apply'
        $json | Should -Not -Match 'stub-mcp-token'
    }

    It 'fails on an input that does not match the input schema, before any call' {
        New-Stub
        $bad = Write-Input @{pages = @(@{menuText = 'x'})} 'content.pages'
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $bad}
        ($r.lines -match '^FAIL recipe: .*does not match recipe-input\.schema\.json').Count | Should -Be 1
        $r.lines[-1] | Should -Be 'content.pages: 0 of 1 checks passed'
        $r.exit | Should -Be 1
        $global:RecipeStub.log.Count | Should -Be 0
    }
}

Describe 'Invoke-DwRecipe on users.accounts' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        $env:DW_API_TOKEN = 'stub-api-token-0000'
        $env:DW_RECIPE_SECRETS = '{"buyer":"Stub-Passw0rd-x"}'
        $script:Root = New-RecipeSandbox
        $script:InputFile = Write-Input $script:UsersSection 'users.accounts'
    }

    It 'creates groups, the account type, users with a password, memberships and the grant, then pays and owes its debts' {
        New-Stub
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true}
        foreach ($line in @('STEP groups CREATED Example Trading', 'STEP account-type UPDATED Example Trading', 'PASS account-type/Example Trading', 'STEP users CREATED buyer@example.invalid', 'STEP membership CREATED Example Trading/buyer@example.invalid', 'STEP impersonation CREATED rep@example.invalid/buyer@example.invalid', 'PASS probe/grant-direction', 'PASS probe/grant-not-reversed', 'PASS probe/user-in-group')) { $r.lines | Should -Contain $line }
        # The password goes on create, only for a user that names one; the staff user is created without.
        @($global:RecipeStub.users | Where-Object { $_.hasPassword }).userName | Should -Be 'buyer@example.invalid'
        # The grant's subject is the impersonator.
        $rep = @($global:RecipeStub.users | Where-Object userName -eq 'rep@example.invalid')[0].id
        $global:RecipeStub.grants[0].from | Should -Be $rep
        $r.lines | Should -Contain 'PASS debt/flush:Dynamicweb.Security.UserManagement.UserService'
        ($r.lines -match '^NOTE debt/index:Users/Users.index: not owed, the target has no index').Count | Should -Be 1
        $r.lines | Should -Contain 'PASS debt/index:Secondary users/Users.index'
        ($r.lines -match '^OPEN debt/recycle: owed: recycle the host').Count | Should -Be 1
        (Get-Content -LiteralPath $script:ChildLog) -join "`n" | Should -Match 'Build-DwProductIndex\.ps1 -Repository Secondary users -IndexName Users\.index -BuildName Users -SkipCacheFlush'
        ($r.lines -match '^OPEN probe/persona-sign-in: .*dwapi is not a permitted surface').Count | Should -Be 1
        ($r.lines -join "`n") | Should -Not -Match 'stub-api-token|stub-mcp-token|Stub-Passw0rd'
        $r.exit | Should -Be 1
    }

    It 'changes nothing and runs no debt when a second apply finds every object in place' {
        New-Stub
        $null = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true}
        $before = (Get-Writes).Count
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true}
        ($r.lines -match '^STEP ').Count | Should -Be (($r.lines -match '^STEP \S+ UNCHANGED ').Count)
        ($r.lines -match '^NOTE users\.accounts: debts not run \(nothing changed\)').Count | Should -Be 1
        (Get-Writes).Count | Should -Be $before
    }

    It 'blocks only the account type MCP-only, because no MCP group read returns the type' {
        New-Stub
        $null = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true}
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; McpOnly = $true}
        @($r.lines -match '^STEP \S+ BLOCKED ') | Should -Be @('STEP account-type BLOCKED Example Trading')
        ($r.lines -match '^NOTE users\.accounts: declared not usable MCP-only').Count | Should -Be 1
    }

    It 'reports a write the Management API refuses with HTTP 200 as FAIL, not as success' {
        New-Stub
        . (Join-Path $script:Root 'skills/dw-demo-ledger/scripts/Recipe.Transport.ps1')
        . (Join-Path $script:Root 'skills/dw-demo-ledger/scripts/Recipe.Write.ps1')
        Import-Module (Join-Path $script:Root 'skills/dw-data-access/scripts/Dw.Api.psm1') -Force
        $global:RecipeStub.api = { param($Command, $Body) [pscustomobject]@{status = 'invalid'; message = 'No items selected'} }
        $registry = Read-LedgerJson (Join-Path $script:Root 'skills/dw-demo-ledger/assets/handlers.json')
        $run = @{cap = @{surfaces = @('admin-api'); admin = $true; tools = @{}}; registry = $registry}
        $binding = @{surface = 'admin-api'; status = 'implemented'; create = @{operation = 'UsersAddToGroups'; arguments = @{GroupIds = @(50); Ids = @('60')}}}
        { Invoke-RecipeWrite $binding 'create' @{results = @{}; secrets = @{}} $run } | Should -Throw "*answered status 'invalid'*"
        Remove-Module Dw.Api -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-DwRecipe on a lookup step' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        Remove-Item Env:DW_API_TOKEN -ErrorAction SilentlyContinue
        $script:Root = New-RecipeSandbox
        $script:InputFile = Write-Input @{pages = @(@{menuText = 'Header / Footer'; urlName = 'header-footer'; itemType = 'Swift-v2_Page'})} 'content.pages'
        $find = @{id = 'mcp-root'; surface = 'mcp'; status = 'implemented'; operation = 'get_pages_by_parent_id'; arguments = @{parentId = 0; areaId = '{build.areaId}'}; rows = 'data'; match = @{menuText = '{item.menuText}'}; produces = @{id = 'id'}; source = 'skills/x.md'}
        $recipe = @{schema = 1; id = 'content.pages'; name = 'Lookup'; functions = @('content.pages'); skill = 'dw-content-modelling'; inputs = @{section = 'content.pages'; required = @('pages')}
            modes = @{mcpOnly = @{usable = $true; reason = 'MCP.'}; hosted = @{usable = $true; reason = 'No SQL.'}; local = @{usable = $true}; layerDelivered = 'verify'}
            steps = @(@{id = 'folder'; title = 'Find the folder'; forEach = 'pages[*]'; key = '{item.menuText}'; find = @{bindings = @($find)}; bindings = @(); source = 'skills/x.md'})
            debts = @(); verify = @{checkIds = @(); probes = @()}; provenOn = @(); traps = @()}
        $script:RecipeFile = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json')
        $recipe | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:RecipeFile -Encoding utf8
    }
    It 'finds an existing object, writes nothing, and blocks an absent one instead of creating it' {
        New-Stub
        $r = Invoke-Runner $script:Root @{Recipe = $script:RecipeFile; InputPath = $script:InputFile}
        $r.lines | Should -Contain 'STEP folder WOULD-CREATE Header / Footer'
        ($r.lines -match 'a lookup step never writes').Count | Should -Be 1
        $a = Invoke-Runner $script:Root @{Recipe = $script:RecipeFile; InputPath = $script:InputFile; Apply = $true}
        $a.lines | Should -Contain 'STEP folder BLOCKED Header / Footer'
        $a.exit | Should -Be 1
        Get-Writes | Should -BeNullOrEmpty
        $global:RecipeStub.pages.Add(@{id = 89; parentPageId = 0; menuText = 'Header / Footer'})
        $f = Invoke-Runner $script:Root @{Recipe = $script:RecipeFile; InputPath = $script:InputFile; Apply = $true}
        $f.lines | Should -Contain 'STEP folder UNCHANGED Header / Footer'
        $f.exit | Should -Be 0
        Get-Writes | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-DwBrandKit' {
    It 'turns a kit''s swift2 folder into a brand section the input schema accepts, enums by name and files under /Files/Images' {
        $kit = Join-Path $TestDrive 'kit/swift2'
        foreach ($d in 'ColorSchemes', 'Typography', 'Buttons', 'Fonts', 'branding') { $null = New-Item -ItemType Directory -Force (Join-Path $kit $d) }
        $scheme = {param($id) @{Id = $id; Name = $id; GroupId = 'fabrikam'; BackgroundColor = '#ffffff'; ForegroundColor = '#1a1a1a'; PrimaryButtonColor = '#0b5d4b'; SecondaryButtonColor = '#000000'; CustomColors = @()}}
        @{Id = 'fabrikam'; Name = 'Fabrikam'; Schemes = @((& $scheme 'light'), (& $scheme 'dark'))} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $kit 'ColorSchemes/fabrikam.json')
        @{Id = 'fabrikam'; Name = 'Fabrikam'; BaseFontSize = 16; BaseFontScale = 1.2; ParagraphFont = 'Body Sans'; ParagraphCustomFontId = 'fabrikam-body-400'; ParagraphFontWeight = 400; ParagraphLineHeight = 1.5; ParagraphTextTransformation = 0
            HeadingFont = 'Display'; HeadingCustomFontId = $null; HeadingFontWeight = 700; HeadingLineHeight = 1.2; HeadingTextTransformation = 1; ButtonFont = 'Body Sans'; ButtonFontWeight = 600; ButtonLineHeight = 1.4} | ConvertTo-Json | Set-Content (Join-Path $kit 'Typography/fabrikam.json')
        @{Id = 'fabrikam'; Name = 'Fabrikam'; Shape = 2; PaddingX = 1.5; PaddingY = 0.75; BorderSize = 1} | ConvertTo-Json | Set-Content (Join-Path $kit 'Buttons/fabrikam.json')
        @{Id = 'fabrikam-body-400'; Name = 'Body 400'; Family = 'Body Sans'; FilePath = '/Files/Templates/Designs/Swift-v2/Custom/fonts/fabrikam-body-400.woff2'; Style = 'normal'; Weight = 400} | ConvertTo-Json | Set-Content (Join-Path $kit 'Fonts/fabrikam-body-400.json')
        Set-Content (Join-Path $kit 'Fonts/fabrikam-body-400.woff2') 'font'
        Set-Content (Join-Path $kit 'branding/fabrikam-logo.svg') '<svg/>'
        @{headerDesktop = @{Id = '/Files/Images/branding/fabrikam-logo.svg'; Name = 'fabrikam-logo.svg'}; headerMobile = $null; footerDesktop = $null; footerMobile = $null; favicon = $null} | ConvertTo-Json | Set-Content (Join-Path $kit 'logo-fields.json')
        @{saveAreas = @{ColorSchemeId = 'light'}} | ConvertTo-Json | Set-Content (Join-Path $kit 'area.json')
        $out = Join-Path $TestDrive 'input/recipe-input.json'
        $null = New-Item -ItemType Directory -Force (Split-Path $out)
        @{schema = 1; build = @{areaId = 1}} | ConvertTo-Json | Set-Content $out
        & (Join-Path $script:Source 'scripts/ConvertFrom-DwBrandKit.ps1') -KitPath $kit -OutPath $out -RenderCheck '/en-us/home' | Should -Match '2 schemes, 1 fonts, 2 files, 1 logo slots'
        $doc = Read-LedgerJson $out (Join-Path $script:Source 'assets/recipe-input.schema.json')
        $doc.build.areaId | Should -Be 1
        $b = $doc.brand
        $b.id | Should -Be 'fabrikam'
        $b.typography.paragraphFontWeight | Should -Be 'Regular'
        $b.typography.headingTextTransformation | Should -Be 'Uppercase'
        $b.typography.buttonFontWeight | Should -Be 'SemiBold'
        $b.typography.Contains('paragraphFont') | Should -BeFalse
        $b.typography.headingFont | Should -Be 'Display'
        $b.buttonStyle.shape | Should -Be 'Pill'
        $b.fonts[0].filePath | Should -Be '/Files/Images/fabrikam/fabrikam-body-400.woff2'
        $b.fonts[0].weight | Should -Be 'Regular'
        @($b.files.file) | Should -Contain '../kit/swift2/Fonts/fabrikam-body-400.woff2'
        $b.layout[0].slot | Should -Be 'HeaderDesktop'
        $b.layout[0].logo.Image | Should -Be '/Files/Images/fabrikam/fabrikam-logo.svg'
    }
}

Describe 'Find-DwRecipe' {
    BeforeAll { $script:Find = Join-Path $script:Source 'scripts/Find-DwRecipe.ps1' }
    It 'lists the recipes that deliver a function, with modes and proven state' {
        $out = & $script:Find -Function users.user-groups
        $LASTEXITCODE | Should -Be 0
        $out[0] | Should -Match '^users\.accounts'
        ($out -match '^\s+proven:\s+').Count | Should -Be 1
        ($out -match '^\s+hosted:\s+yes$').Count | Should -Be 1
    }
    It 'says plainly when no recipe delivers a function, and exits 0' {
        $out = & $script:Find -Function search.user-index
        $LASTEXITCODE | Should -Be 0
        $out | Should -Be 'no recipe for function search.user-index'
    }
}
