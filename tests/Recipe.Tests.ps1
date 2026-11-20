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
    . (Join-Path $script:Source 'scripts/Recipe.Match.ps1')

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
function Get-DwMcpTools { , @($global:RecipeStub.tools.Keys | ForEach-Object { [pscustomobject]@{name = $_; inputSchema = $global:RecipeStub.tools[$_]; outputSchema = $(if ($global:RecipeStub.outputs) { $global:RecipeStub.outputs[$_] })} }) }
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
            fields = @{}; groups = [Collections.Generic.List[object]]::new(); users = [Collections.Generic.List[object]]::new(); files = [Collections.Generic.List[object]]::new()
            members = [Collections.Generic.List[object]]::new(); grants = [Collections.Generic.List[object]]::new()
            repositories = @(@{repository = 'Secondary users'; indexes = @('Users.index')}); refuseButtons = $false; urlReadyAfter = 0
            # The output schemas a target lists; fetch_frontend_page_html reports finalPath on a server that follows redirects.
            outputs = @{fetch_frontend_page_html = @{type = 'object'; properties = @{statusCode = @{type = 'integer'}; finalPath = @{type = @('string', 'null')}}}}
            tools = @{
                get_pages_by_parent_id = Get-Schema @('parentId', 'areaId') @('parentId'); save_pages = Get-Schema @('pages') @('pages'); get_pages_by_ids = Get-Schema @('pageIds') @('pageIds')
                get_page_item_field_values = Get-Schema @('pageId') @('pageId'); set_page_item_fields = Get-Schema @('pageId', 'fields') @('pageId', 'fields')
                get_grid_rows_by_page_id = Get-Schema @('pageId') @('pageId'); save_grid_rows = Get-Schema @('gridRows') @('gridRows')
                get_paragraphs_by_page_id = Get-Schema @('pageId') @('pageId'); save_paragraphs = Get-Schema @('paragraphs') @('paragraphs')
                get_paragraph_item_field_values = Get-Schema @('paragraphId') @('paragraphId'); set_paragraph_item_fields = Get-Schema @('paragraphId', 'fields') @('paragraphId', 'fields')
                fetch_frontend_page_html = Get-Schema @('path') @('path'); inspect_page_render = Get-Schema @('pageId', 'compareWithPageId') @('pageId')
                get_user_groups = Get-Schema @(); save_user_groups = Get-Schema @('groups') @('groups')
                get_users_by_usernames = Get-Schema @('userNames') @('userNames'); create_users = Get-Schema @('users') @('users'); update_users = Get-Schema @('users') @('users')
                get_users_by_group_id = Get-Schema @('groupId') @('groupId'); assign_users_to_group = Get-Schema @('groupId', 'userIds') @('groupId', 'userIds')
                get_impersonatable_users = Get-Schema @('userId', 'groupId'); add_impersonatable_users = Get-Schema @('userId', 'impersonatableUserIds') @('impersonatableUserIds')
                get_index_repositories = Get-Schema @(); delete_pages = Get-Schema @('ids')
                list_files = Get-Schema @('path') @('path'); create_folder = Get-Schema @('path') @('path'); upload_file = Get-Schema @('path', 'content', 'isBase64', 'overwrite') @('path', 'content')
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
                'get_pages_by_ids' { , @($s.pages | Where-Object { $_.id -in @($Arguments.pageIds | ForEach-Object { [int]$_ }) }) }
                'save_pages' {
                    foreach ($p in $Arguments.pages) {
                        if ([int]$p.id -eq 0) { $id = & $mint; $s.pages.Add(@{id = $id; parentPageId = [int]$p.parentPageId; menuText = $p.menuText; urlName = $p.urlName; itemType = $p.itemType; sort = $p.sort}); $s.fields["page$id"] = [ordered]@{Title = $null} }
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
                # A page is served at /en-us/<url name or menu text>; a later page whose address an earlier page holds is
                # served at <address>-1, as measured. /Default.aspx?ID=<id> lands on the page's served path (finalPath).
                'fetch_frontend_page_html' {
                    $s.fetches++
                    $base = { param($p) '/en-us/' + $(if ($p.urlName) { $p.urlName } else { $p.menuText.ToLower().Replace(' ', '-') }) }
                    $served = { param($p) $b = & $base $p; $n = @($s.pages | Where-Object { $_.id -lt $p.id -and (& $base $_) -eq $b }).Count; if ($n) { "$b-$n" } else { $b } }
                    $page = if ($Arguments.path -match '^/Default\.aspx\?ID=(\d+)$') { @($s.pages | Where-Object { $_.id -eq [int]$Matches[1] })[0] } else { @($s.pages | Where-Object { (& $served $_) -eq $Arguments.path })[0] }
                    # An older server does not follow the redirect: it answers 301 and names the target in error.
                    if ($page -and $s.noFollow -and $Arguments.path -like '/Default.aspx*') { return @{structuredContent = @{statusCode = 301; path = $Arguments.path; error = 'Page redirects to: ' + (& $served $page)}} }
                    if (-not $page -or $s.fetches -le $s.urlReadyAfter) { return @{structuredContent = @{statusCode = 404; path = $Arguments.path; finalPath = $Arguments.path}} }
                    return @{structuredContent = @{statusCode = 200; title = $page.menuText; path = $Arguments.path; finalPath = (& $served $page)}}
                }
                # The rendered outline of a page by id, with the issues a stored-field read cannot show; a clean page has none.
                'inspect_page_render' {
                    $page = @($s.pages | Where-Object { $_.id -eq [int]$Arguments.pageId })[0]
                    return @{structuredContent = @{pageId = [int]$Arguments.pageId; statusCode = $(if ($page) { 200 } else { 404 }); outline = @(); issues = @($s.renderIssues)}}
                }
                # The group read returns the type once it is set and leaves the member out while it is null, as measured.
                'get_user_groups' { , @($s.groups | ForEach-Object { $row = @{id = $_.id; name = $_.name; parentGroupId = $_.parentGroupId; customerNumber = $_.customerNumber}; if ($_.type) { $row.userAndGroupType = $_.type }; $row }) }
                'save_user_groups' {
                    foreach ($g in $Arguments.groups) {
                        if ([int]$g.id -eq 0) { $s.groups.Add(@{id = (& $mint); name = $g.name; parentGroupId = [int]$g.parentGroupId; customerNumber = $g.customerNumber; type = $null}) }
                        else { $row = @($s.groups | Where-Object { $_.id -eq [int]$g.id })[0]; if ($g.Contains('userAndGroupType')) { $row.type = $g.userAndGroupType }; if ($null -ne $g.customerNumber) { $row.customerNumber = $g.customerNumber } }
                    }
                    return (& $ok 1)
                }
                'get_users_by_usernames' { , @($s.users | Where-Object { $_.userName -in $Arguments.userNames }) }
                'create_users' { foreach ($u in $Arguments.users) { $s.users.Add(@{id = (& $mint); userName = $u.userName; customerNumber = $u.customerNumber; hasPassword = [bool]$u.password}) }; return (& $ok 1) }
                # Only non-null members are applied, as measured: a null customer number leaves the stored one in place.
                'update_users' { foreach ($u in $Arguments.users) { foreach ($row in $s.users) { if ($row.id -eq $u.id -and $null -ne $u.customerNumber) { $row.customerNumber = $u.customerNumber } } }; return (& $ok 1) }
                'get_users_by_group_id' { $ids = @($s.members | Where-Object { $_.groupId -eq [int]$Arguments.groupId } | ForEach-Object { $_.userId }); , @($s.users | Where-Object { $_.id -in $ids }) }
                'assign_users_to_group' { foreach ($u in $Arguments.userIds) { $s.members.Add(@{groupId = [int]$Arguments.groupId; userId = [int]$u}) }; return (& $ok 1) }
                'get_impersonatable_users' { $ids = @($s.grants | Where-Object { $_.from -eq [int]$Arguments.userId } | ForEach-Object { $_.to }); , @($s.users | Where-Object { $_.id -in $ids }) }
                'add_impersonatable_users' { foreach ($u in $Arguments.impersonatableUserIds) { $s.grants.Add(@{from = [int]$Arguments.userId; to = [int]$u}) }; return (& $ok 1) }
                'get_index_repositories' { , @($s.repositories) }
                # A case-insensitive file system, as on Windows: a row echoes the parent as asked and the name as stored.
                'list_files' {
                    $parent = $Arguments.path.TrimEnd('/')
                    , @($s.files | Where-Object { [string]::Equals(($_.path -replace '/[^/]+$', ''), $parent, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { @{name = ($_.path -split '/')[-1]; path = $parent + '/' + ($_.path -split '/')[-1]; isDirectory = $_.isDirectory; byteSize = [int]$_.byteSize} })
                }
                'create_folder' { if (-not @($s.files | Where-Object { [string]::Equals($_.path, $Arguments.path, [StringComparison]::OrdinalIgnoreCase) }).Count) { $s.files.Add(@{path = $Arguments.path; isDirectory = $true; byteSize = 0}) }; return (& $ok 1) }
                'upload_file' {
                    $hit = @($s.files | Where-Object { [string]::Equals($_.path, $Arguments.path, [StringComparison]::OrdinalIgnoreCase) })[0]
                    $size = [Convert]::FromBase64String($Arguments.content).Length
                    if ($hit) { $hit.byteSize = $size } else { $s.files.Add(@{path = $Arguments.path; isDirectory = $false; byteSize = $size}) }
                    return (& $ok 1)
                }
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
    It 'reads a value a layer delivery produced, and marks a dependant of an unread delivered object as delivered' {
        $ctx = @{item = @{group = 'tools'}; results = @{categories = @{tools = @{state = 'DELIVERED'; values = @{id = 'layer_cat'}}}}; secrets = @{}}
        Resolve-RecipeToken 'step.categories[item.group].id' $ctx | Should -Be 'layer_cat'
        $ctx.results.categories.tools.values = @{}
        $thrown = $null
        try { Resolve-RecipeToken 'step.categories[item.group].id' $ctx } catch { $thrown = $_.Exception }
        $thrown | Should -BeOfType ([Collections.Generic.KeyNotFoundException])
        $thrown.Data['delivered'] | Should -BeTrue
        $thrown.Message | Should -BeLike '*a layer delivered under its own keys*'
        $ctx.results.categories.tools.state = 'WOULD-CREATE'
        try { Resolve-RecipeToken 'step.categories[item.group].id' $ctx } catch { $thrown = $_.Exception }
        $thrown.Data['delivered'] | Should -BeFalse
    }
    It 'splits a list parameter that arrives as one comma-separated, quoted text' {
        $one = Split-LedgerList @("'a.b','c.d'"); $one | Should -Be @('a.b', 'c.d')
        $two = Split-LedgerList @('a.b, c.d', 'e'); $two | Should -Be @('a.b', 'c.d', 'e')
        (Split-LedgerList @()).Count | Should -Be 0
    }
    It 'names a read that ran out of time, so a step ends in a FAIL instead of waiting' {
        . (Join-Path $script:Source 'scripts/Recipe.Transport.ps1')
        Test-RecipeTimeout ([Threading.Tasks.TaskCanceledException]::new('canceled')) | Should -BeTrue
        Test-RecipeTimeout ([Net.Http.HttpRequestException]::new('x', [TimeoutException]::new('late'))) | Should -BeTrue
        Test-RecipeTimeout ([InvalidOperationException]::new('no such tool')) | Should -BeFalse
    }
    It 'matches a member by its ending, ignoring case, and leaves out a row without the member' {
        . (Join-Path $script:Source 'scripts/Recipe.Steps.ps1')
        $rows = @(@{value = '/Files/Images/Layer/Products/A-1.PNG'}, @{value = '/Files/Images/a-1.png.bak'}, @{other = 1})
        $hits = Select-RecipeSuffixMatches $rows @{value = '/a-1.png'}
        $hits.Count | Should -Be 1
        $hits[0].value | Should -Be '/Files/Images/Layer/Products/A-1.PNG'
        (Select-RecipeSuffixMatches $rows @{}).Count | Should -Be 3
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
    It 'walks the entries of an object as key and value items' {
        $items = Get-RecipeItems @{products = @(@{number = 'N1'; specs = @{Voltage = '18 V'}})} 'products[*].specs[*]'
        $items.Count | Should -Be 1
        $items[0].item.key | Should -Be 'Voltage'
        $items[0].item.value | Should -Be '18 V'
        $items[0].parent.number | Should -Be 'N1'
    }
    It 'reads an input file by a path relative to the input file and refuses one that leaves its folder' {
        $dir = Join-Path $TestDrive 'input'; $null = New-Item -ItemType Directory -Force (Join-Path $dir 'images')
        [IO.File]::WriteAllBytes((Join-Path $dir 'images/a.png'), [byte[]](1, 2, 3))
        $ctx = @{item = 'images/a.png'; inputDir = $dir; results = @{}; secrets = @{}}
        Resolve-RecipeToken 'basename:item' $ctx | Should -Be 'a.png'
        Resolve-RecipeToken 'base64:item' $ctx | Should -Be 'AQID'
        $ctx.item = '../outside.png'
        { Resolve-RecipeToken 'base64:item' $ctx } | Should -Throw '*outside the input file*'
        $ctx.item = 'C:/x.png'
        { Resolve-RecipeToken 'base64:item' $ctx } | Should -Throw '*relative to the input file*'
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
    It 'handles a repeated natural key once in a reuse step, and refuses it in any other step' {
        . (Join-Path $script:Source 'scripts/Recipe.Steps.ps1')
        $run = @{section = @{orders = @(@{lines = @(@{product = 'A'}, @{product = 'B'})}, @{lines = @(@{product = 'A'})})}; results = @{}; secrets = @{}; build = @{}; apply = $false
            lines = [Collections.Generic.List[string]]::new(); checks = [Collections.Generic.List[object]]::new(); steps = [Collections.Generic.List[object]]::new(); blocked = 0}
        Mock Invoke-RecipeStepItem { $Run.results[$Step.id][$Key] = @{state = 'UNCHANGED'; values = @{}} }
        Invoke-RecipeStep @{id = 'products'; forEach = 'orders[*].lines[*]'; key = '{item.product}'; repeat = 'reuse'} $run
        Should -Invoke Invoke-RecipeStepItem -Times 2 -Exactly
        $run.checks.Count | Should -Be 0
        Invoke-RecipeStep @{id = 'strict'; forEach = 'orders[*].lines[*]'; key = '{item.product}'} $run
        @($run.checks | Where-Object { $_.name -eq 'strict/A' -and $_.reason -match 'natural key twice' }).Count | Should -Be 1
    }
    It 'refuses a host, a machine path or a credential literal in a recipe' {
        @(Test-RecipeForbidden @{source = 'see https://example.invalid'}).Count | Should -Be 1
        @(Test-RecipeForbidden @{query = 'C:\temp\x'}).Count | Should -Be 1
        @(Test-RecipeForbidden @{arguments = @{password = 'literal'}}).Count | Should -Be 1
        @(Test-RecipeForbidden @{arguments = @{password = '{secret.item.passwordRef}'}}).Count | Should -Be 0
    }
}

Describe 'Recipe bindings gated on the target tools/list schema (requiresSchema)' {
    BeforeAll {
        . (Join-Path $script:Source 'scripts/Recipe.Transport.ps1')
        $script:GateRegistry = @{mcpReadTools = @('get_completion_rules'); recipeRenderedReadTools = @(); recipeWriteTools = @('save_payment_methods')}
        # The rule read as two server releases answer it: the older one lists each rule's fields as objects,
        # the newer one only the field system names.
        $script:OlderRules = @{type = 'object'; properties = @{data = @{type = 'array'; items = @{type = 'object'; properties = @{
            fields = @{type = 'array'; items = @{type = 'object'; properties = @{systemName = @{type = 'string'}}}}; fieldSystemNames = @{type = 'array'}}}}}}
        $script:NewerRules = @{type = 'object'; properties = @{data = @{type = 'array'; items = @{type = 'object'; properties = @{fieldSystemNames = @{type = 'array'}}}}}}
        $script:RuleReads = @(
            @{id = 'objects'; surface = 'mcp'; status = 'implemented'; operation = 'get_completion_rules'; arguments = @{}; requiresSchema = @{output = @('data[*].fields')}},
            @{id = 'names'; surface = 'mcp'; status = 'implemented'; operation = 'get_completion_rules'; arguments = @{}})
        function New-GateCap([hashtable]$Tools, [hashtable]$Outputs) { @{surfaces = @('mcp'); mcp = $true; tools = $Tools; outputs = $Outputs} }
    }
    It 'takes the binding whose output member the server lists, and falls to the next one where it does not' {
        $older = Select-RecipeRead $script:RuleReads (New-GateCap @{get_completion_rules = @{type = 'object'; properties = @{}}} @{get_completion_rules = $script:OlderRules}) $script:GateRegistry
        $older.binding.id | Should -Be 'objects'
        $newer = Select-RecipeRead $script:RuleReads (New-GateCap @{get_completion_rules = @{type = 'object'; properties = @{}}} @{get_completion_rules = $script:NewerRules}) $script:GateRegistry
        $newer.binding.id | Should -Be 'names'
        $newer.reasons | Should -Be @("MCP get_completion_rules's tools/list output schema carries no member 'data[*].fields'")
    }
    It 'reads a capability set without output schemas, or a tool without one, as lacking the member' {
        (Select-RecipeRead $script:RuleReads @{surfaces = @('mcp'); mcp = $true; tools = @{get_completion_rules = @{}}} $script:GateRegistry).binding.id | Should -Be 'names'
        (Select-RecipeRead $script:RuleReads (New-GateCap @{get_completion_rules = @{}} @{get_completion_rules = $null}) $script:GateRegistry).binding.id | Should -Be 'names'
    }
    It 'gates a write on an input member, so an older server takes the fallback write' {
        $read = @{surface = 'mcp'; status = 'implemented'; operation = 'get_completion_rules'; arguments = @{}}
        $writes = @(
            @{id = 'mcp-country'; surface = 'mcp'; status = 'implemented'; requiresSchema = @{input = @('models[*].countryCodes')}; create = @{operation = 'save_payment_methods'; arguments = @{}}; readBack = $read},
            @{id = 'mcp-plain'; surface = 'mcp'; status = 'implemented'; create = @{operation = 'save_payment_methods'; arguments = @{}}; readBack = $read})
        $with = @{type = 'object'; properties = @{models = @{type = 'array'; items = @{type = 'object'; properties = @{name = @{}; countryCodes = @{type = 'array'}}}}}}
        $without = @{type = 'object'; properties = @{models = @{type = 'array'; items = @{type = 'object'; properties = @{name = @{}}}}}}
        (Select-RecipeWrite $writes 'create' (New-GateCap @{save_payment_methods = $with; get_completion_rules = @{}} @{}) $script:GateRegistry).binding.id | Should -Be 'mcp-country'
        $old = Select-RecipeWrite $writes 'create' (New-GateCap @{save_payment_methods = $without; get_completion_rules = @{}} @{}) $script:GateRegistry
        $old.binding.id | Should -Be 'mcp-plain'
        $old.reasons[0] | Should -Match "input schema carries no member 'models\[\*\]\.countryCodes'"
    }
    It 'refuses a path that is not a dotted member path' {
        { Test-RecipeSchemaMember @{} 'data[0].x' } | Should -Throw '*not a dotted member path*'
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
    It 'takes a write that answers a sentence as no data, and a read that does as a fault' {
        function Invoke-DwMcp { param($Tool, $Arguments, [switch]$Raw, $TimeoutSec) @{isError = $false; content = @(@{type = 'text'; text = 'Primary image updated for product PROD5.'})} }
        $cap = @{tools = @{}}
        $answer = Invoke-RecipeMcpCall 'set_product_primary_image' @{request = @{}} $cap 30 -AllowText
        $answer.Count | Should -Be 0
        { Invoke-RecipeMcpCall 'get_product_images' @{} $cap 30 } | Should -Throw '*not JSON*'
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
        # Fetch 1 is the path check before the create; fetch 2 the probe's first read (404), fetch 3 its poll; fetch 4 the page-path probe.
        $global:RecipeStub.urlReadyAfter = 2
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true}
        $r.lines | Should -Contain 'PASS probe/page-renders'
        $r.lines | Should -Contain 'PASS probe/page-path'
        $global:RecipeStub.fetches | Should -Be 4
    }

    It 'blocks a page whose path another page already answers at, instead of creating a sibling served at its path with -1' {
        New-Stub
        # A sample page in a navigation folder holds the address the input gives its own page.
        $global:RecipeStub.pages.Add(@{id = 60; parentPageId = 59; menuText = 'About the shop'; urlName = 'about-us'; itemType = 'Swift-v2_Page'})
        $v = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile}
        $v.lines | Should -Contain 'STEP pages BLOCKED About us'
        ($v.lines -match '^OPEN pages/About us: absent under its natural key, and a create would collide \(fetch_frontend_page_html\): another page already answers at the input''s path').Count | Should -Be 1
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true}
        $r.lines | Should -Contain 'STEP pages BLOCKED About us'
        @($global:RecipeStub.pages | Where-Object menuText -eq 'About us').Count | Should -Be 0
        @($global:RecipeStub.log -match '^mcp save_pages ').Count | Should -Be 0
        $r.exit | Should -Be 1
    }

    It 'RED CONTROL: fails a page served at its path with -1, which the title probe alone passes' {
        New-Stub
        $global:RecipeStub.pages.Add(@{id = 60; parentPageId = 59; menuText = 'About us sample'; urlName = 'about-us'; itemType = 'Swift-v2_Page'})
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true}
        $r.lines | Should -Contain 'STEP pages BLOCKED About us'
        # The sibling a run before the path check made: the same menu text at the root, served at about-us-1.
        $global:RecipeStub.pages.Add(@{id = 70; parentPageId = 0; menuText = 'About us'; urlName = 'about-us'; itemType = 'Swift-v2_Page'})
        $v = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile}
        $v.lines | Should -Contain 'STEP pages UNCHANGED About us'
        $v.lines | Should -Contain 'PASS probe/page-renders'
        ($v.lines -match '^FAIL probe/page-path: 1 failing: subject 1: finalPath does not equal the expected value').Count | Should -Be 1
        $v.exit | Should -Be 1
        # A server whose fetch does not follow the redirect (no finalPath in its output schema) answers 301 and names the target.
        $global:RecipeStub.noFollow = $true; $global:RecipeStub.outputs = @{}
        $old = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile}
        ($old.lines -match '^FAIL probe/page-path: 1 failing: subject 1: error does not equal the expected value').Count | Should -Be 1
        $global:RecipeStub.pages.RemoveAt(0)
        $fixed = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile}
        $fixed.lines | Should -Contain 'PASS probe/page-path'
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

Describe 'Recipe debts: the in-product assortment build and the hosted recycle' {
    BeforeAll {
        . (Join-Path $script:Source 'scripts/Recipe.Steps.ps1')
        . (Join-Path $script:Source 'scripts/Recipe.Debts.ps1')
        $script:Registry = @{mcpReadTools = @('get_assortments', 'get_index_repositories'); recipeWriteTools = @('build_assortments')}
        function New-DebtRun([string[]]$Ids) {
            @{lines = [Collections.Generic.List[string]]::new(); checks = [Collections.Generic.List[object]]::new(); section = @{assortmentIds = $Ids}
                cap = @{surfaces = @('mcp'); mcp = $true; admin = $false; tools = @{get_assortments = @{}; build_assortments = @{}}}; registry = $script:Registry; baseUrl = 'https://stub.invalid'}
        }
    }
    It 'builds assortments through MCP and passes only when each last build date moved with no rebuild owed' {
        $global:AssortmentDate = 'd1'
        function Invoke-RecipeMcpCall { param($Operation, $Arguments, $Capabilities, $TimeoutSec, [switch]$AllowText)
            if ($Operation -eq 'build_assortments') { $global:AssortmentDate = 'd2'; return @{succeeded = 1; failed = 0} }
            return @{data = @(@{id = 'A1'; rebuildRequired = $false; lastBuildDate = $global:AssortmentDate})} }
        $run = New-DebtRun @('A1')
        Invoke-RecipeDebt 'assortments' $run
        $run.checks[0].result | Should -Be 'PASS'
        function Invoke-RecipeMcpCall { param($Operation, $Arguments, $Capabilities, $TimeoutSec, [switch]$AllowText)
            if ($Operation -eq 'build_assortments') { return @{succeeded = 1; failed = 0} }
            return @{data = @(@{id = 'A1'; rebuildRequired = $false; lastBuildDate = 'unchanged'})} }
        $run = New-DebtRun @('A1')
        Invoke-RecipeDebt 'assortments' $run
        $run.checks[0].result | Should -Be 'FAIL'
    }
    It 'leaves a hosted recycle OPEN and names the routes that exist' {
        $run = New-DebtRun @()
        Invoke-RecipeDebt 'recycle' $run
        $run.checks[0].result | Should -Be 'OPEN'
        $run.checks[0].reason | Should -Match 'CloudHosting/recycle.txt'
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

    It 'writes and reads the account type MCP-only: a group without the type matches nothing, the MCP binding sets it' {
        New-Stub
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true; McpOnly = $true}
        @($r.lines -match '^STEP \S+ BLOCKED ').Count | Should -Be 0
        $r.lines | Should -Contain 'STEP account-type CREATED Example Trading'
        @($global:RecipeStub.log -match '^api ').Count | Should -Be 0
        @($global:RecipeStub.groups | Where-Object { $_.name -eq 'Example Trading' })[0].type | Should -Be 'SystemAccount'
        $again = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; McpOnly = $true}
        $again.lines | Should -Contain 'STEP account-type UNCHANGED Example Trading'
        ($again.lines -match '^NOTE users\.accounts: declared not usable MCP-only').Count | Should -Be 0
    }

    It 'clears a customer number the input does not give, with an empty text: update_users and save_user_groups ignore a null' {
        New-Stub
        # A layer delivered the staff group and the representative with a customer's number.
        $global:RecipeStub.groups.Add(@{id = 80; name = 'Representatives'; parentGroupId = 0; customerNumber = 'C-1001'; type = $null})
        $global:RecipeStub.users.Add(@{id = 90; userName = 'rep@example.invalid'; customerNumber = 'C-1001'; hasPassword = $false})
        $verify = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile}
        ($verify.lines -match '^FAIL users/rep@example\.invalid: differs from the input in customerNumber; apply would update it').Count | Should -Be 1
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true}
        $r.lines | Should -Contain 'STEP groups UPDATED Representatives'
        $r.lines | Should -Contain 'PASS groups/Representatives'
        $r.lines | Should -Contain 'STEP users UPDATED rep@example.invalid'
        $r.lines | Should -Contain 'PASS users/rep@example.invalid'
        @($global:RecipeStub.users | Where-Object id -eq 90)[0].customerNumber | Should -BeExactly ''
        @($global:RecipeStub.groups | Where-Object id -eq 80)[0].customerNumber | Should -BeExactly ''
        # The account keeps its number: only an input without one is cleared.
        @($global:RecipeStub.users | Where-Object userName -eq 'buyer@example.invalid')[0].customerNumber | Should -Be 'C-1001'
        $again = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile}
        $again.lines | Should -Contain 'STEP users UNCHANGED rep@example.invalid'
        $again.lines | Should -Contain 'STEP groups UNCHANGED Representatives'
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

Describe 'Invoke-DwRecipe on a site a layer copy already delivered' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        Remove-Item Env:DW_API_TOKEN -ErrorAction SilentlyContinue
        $script:Root = New-RecipeSandbox
        $script:InputFile = Write-Input @{groups = @(
                @{name = 'Example Trading'; kind = 'account'; customerNumber = 'C-1001'; users = @(@{userName = 'buyer@example.invalid'})},
                @{name = 'Fresh Account'; kind = 'account'; customerNumber = 'C-2002'; users = @(@{userName = 'new@example.invalid'})})} 'users.accounts'
        $src = 'skills/x.md'
        $groupRead = @{surface = 'mcp'; status = 'implemented'; operation = 'get_user_groups'; arguments = @{}; rows = 'data'; produces = @{id = 'id'}; source = $src}
        $primary = $groupRead + @{id = 'by-name'; match = @{name = '{item.name}'}}
        # The copy named the account its own way; its customer number is the key both share.
        $layer = $groupRead + @{id = 'by-number'; match = @{customerNumber = '{item.customerNumber}'}}
        $memberRead = @{surface = 'mcp'; status = 'implemented'; operation = 'get_users_by_group_id'; arguments = @{groupId = '{step.groups[parent.name].id}'}; rows = 'data'; match = @{userName = '{item.userName}'}; source = $src}
        $recipe = @{schema = 1; id = 'users.accounts'; name = 'Delivered'; functions = @('users.accounts'); skill = 'dw-users-permissions'; inputs = @{section = 'users.accounts'; required = @('groups')}
            modes = @{mcpOnly = @{usable = $true; reason = 'MCP.'}; hosted = @{usable = $true; reason = 'No SQL.'}; local = @{usable = $true}; layerDelivered = 'verify'}
            steps = @(
                @{id = 'groups'; title = 'Groups'; forEach = 'groups[*]'; key = '{item.name}'; find = @{bindings = @($primary); delivered = @($layer)}; source = $src
                    bindings = @(@{id = 'save'; surface = 'mcp'; status = 'implemented'; source = $src; create = @{operation = 'save_user_groups'; arguments = @{groups = @(@{id = 0; name = '{item.name}'; parentGroupId = 0; customerNumber = '{item.customerNumber}'})}}; readBack = $primary})},
                @{id = 'users'; title = 'Users'; forEach = 'groups[*].users[*]'; key = '{item.userName}'; source = $src; bindings = @()
                    find = @{bindings = @(@{id = 'u'; surface = 'mcp'; status = 'implemented'; operation = 'get_users_by_usernames'; arguments = @{userNames = @('{item.userName}')}; rows = 'data'; match = @{userName = '{item.userName}'}; produces = @{id = 'id'}; source = $src})}},
                @{id = 'members'; title = 'Members'; forEach = 'groups[*].users[*]'; key = '{parent.name}/{item.userName}'; deliveredWith = @{step = 'groups'; key = '{parent.name}'}; find = @{bindings = @($memberRead)}; source = $src
                    bindings = @(@{id = 'assign'; surface = 'mcp'; status = 'implemented'; source = $src; create = @{operation = 'assign_users_to_group'; arguments = @{groupId = '{step.groups[parent.name].id}'; userIds = @('{step.users[item.userName].id}')}}; readBack = $memberRead})})
            debts = @(); provenOn = @(); traps = @()
            verify = @{checkIds = @(); probes = @(@{id = 'named'; title = 'Each group carries the input name'; forEach = 'groups[*]'; minimumSubjects = 1; deliveredWith = @{step = 'groups'; key = '{item.name}'}
                        bindings = @(@{surface = 'mcp'; status = 'implemented'; operation = 'get_user_groups'; arguments = @{}; rows = 'data'; match = @{name = '{item.name}'}; assert = @{kind = 'count'; op = 'eq'; value = 1}; source = $src})})}}
        $script:RecipeFile = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json')
        $recipe | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:RecipeFile -Encoding utf8
    }
    It 'reports the delivered objects DELIVERED and never writes them, while it still builds what the copy lacks' {
        New-Stub
        $global:RecipeStub.groups.Add(@{id = 50; name = 'Example Trading Ltd'; parentGroupId = 0; customerNumber = 'C-1001'})
        $global:RecipeStub.users.Add(@{id = 60; userName = 'buyer@example.invalid'}); $global:RecipeStub.users.Add(@{id = 61; userName = 'new@example.invalid'})
        $v = Invoke-Runner $script:Root @{Recipe = $script:RecipeFile; InputPath = $script:InputFile}
        $v.lines | Should -Contain 'STEP groups DELIVERED Example Trading'
        $v.lines | Should -Contain 'PASS groups/Example Trading'
        $v.lines | Should -Contain 'STEP members DELIVERED Example Trading/buyer@example.invalid'
        @($v.lines -match '^NOTE members/Example Trading/buyer@example.invalid: belongs to groups ''Example Trading'', which a layer delivered; not written').Count | Should -Be 1
        @($v.lines -match '^(PASS|FAIL|OPEN) members/Example Trading').Count | Should -Be 0
        $v.lines | Should -Contain 'STEP groups WOULD-CREATE Fresh Account'
        $v.exit | Should -Be 1
        Get-Writes | Should -BeNullOrEmpty
        $a = Invoke-Runner $script:Root @{Recipe = $script:RecipeFile; InputPath = $script:InputFile; Apply = $true}
        $a.lines | Should -Contain 'STEP groups CREATED Fresh Account'
        $a.lines | Should -Contain 'STEP members CREATED Fresh Account/new@example.invalid'
        $a.lines | Should -Contain 'STEP members DELIVERED Example Trading/buyer@example.invalid'
        @($a.lines -match '^NOTE probe/named: 1 subject\(s\) a layer delivered').Count | Should -Be 1
        $a.lines | Should -Contain 'PASS probe/named'
        $a.exit | Should -Be 0
        $writes = Get-Writes
        @($writes -match 'Example Trading').Count | Should -Be 0
        @($writes -match '"groupId":50').Count | Should -Be 0
        @($global:RecipeStub.groups | Where-Object { $_.customerNumber -eq 'C-1001' }).Count | Should -Be 1
        $global:RecipeStub.log.Clear()
        $again = Invoke-Runner $script:Root @{Recipe = $script:RecipeFile; InputPath = $script:InputFile; Apply = $true}
        $again.lines | Should -Contain 'STEP groups DELIVERED Example Trading'
        $again.lines | Should -Contain 'STEP groups UNCHANGED Fresh Account'
        $again.exit | Should -Be 0
        Get-Writes | Should -BeNullOrEmpty
    }
    It 'never reads the delivered shape when the find matched, so a from-blank build is unchanged' {
        New-Stub
        $global:RecipeStub.users.Add(@{id = 60; userName = 'buyer@example.invalid'}); $global:RecipeStub.users.Add(@{id = 61; userName = 'new@example.invalid'})
        $a = Invoke-Runner $script:Root @{Recipe = $script:RecipeFile; InputPath = $script:InputFile; Apply = $true}
        $a.lines | Should -Contain 'STEP groups CREATED Example Trading'
        $a.lines | Should -Contain 'STEP members CREATED Example Trading/buyer@example.invalid'
        @($a.lines -match 'DELIVERED').Count | Should -Be 0
        $a.exit | Should -Be 0
    }
}

Describe 'Invoke-DwRecipe on users.frontend-sign-in' {
    It 'sets the password only of a user that does not sign in with it, reads it back as a sign-in, and then writes nothing' {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'; $env:DW_API_TOKEN = 'stub-api-token-0000'
        $env:DW_RECIPE_SECRETS = '{"buyer":"Stub-Passw0rd-x"}'
        $root = New-RecipeSandbox
        $in = Write-Input @{groups = @(@{name = 'Example Trading'; kind = 'account'; customerNumber = 'C-1001'; users = @(@{userName = 'buyer@example.invalid'; passwordRef = 'buyer'}, @{userName = 'nopass@example.invalid'})})} 'users.accounts'
        New-Stub
        # A user a layer copy delivered: it exists, and nothing signs in with the input's password until it is set.
        $global:RecipeStub.users.Add(@{id = 70; userName = 'buyer@example.invalid'}); $global:RecipeStub.users.Add(@{id = 71; userName = 'nopass@example.invalid'})
        $global:RecipeStub.passwordSet = $false
        $api = $global:RecipeStub.api
        $global:RecipeStub.api = { param($Command, $Body) if ($Command -eq 'UserSetPassword') { $global:RecipeStub.passwordSet = ($Body.model.userId -eq 70 -and $Body.model.password -eq 'Stub-Passw0rd-x') }; & $api $Command $Body }.GetNewClosure()
        Mock Invoke-WebRequest { if ($global:RecipeStub.passwordSet) { [pscustomobject]@{StatusCode = 200; Content = '{"token":"t"}'} } else { [pscustomobject]@{StatusCode = 401; Content = ''} } }
        $v = Invoke-Runner $root @{Recipe = 'users.frontend-sign-in'; InputPath = $in; Surfaces = @('mcp', 'admin-api', 'dwapi')}
        $v.lines | Should -Contain 'STEP password WOULD-CREATE buyer@example.invalid'
        @($v.lines -match 'nopass@example.invalid').Count | Should -Be 0
        $a = Invoke-Runner $root @{Recipe = 'users.frontend-sign-in'; InputPath = $in; Surfaces = @('mcp', 'admin-api', 'dwapi'); Apply = $true}
        $a.lines | Should -Contain 'STEP password CREATED buyer@example.invalid'
        $a.lines | Should -Contain 'PASS probe/persona-sign-in'
        $a.exit | Should -Be 0
        @($global:RecipeStub.log -match '^api UserSetPassword').Count | Should -Be 1
        ($a.lines -join "`n") | Should -Not -Match 'Stub-Passw0rd-x'
        $again = Invoke-Runner $root @{Recipe = 'users.frontend-sign-in'; InputPath = $in; Surfaces = @('mcp', 'admin-api', 'dwapi'); Apply = $true}
        $again.lines | Should -Contain 'STEP password UNCHANGED buyer@example.invalid'
        @($global:RecipeStub.log -match '^api UserSetPassword').Count | Should -Be 1
        $m = Invoke-Runner $root @{Recipe = 'users.frontend-sign-in'; InputPath = $in; McpOnly = $true}
        @($m.lines -match '^NOTE users.frontend-sign-in: declared not usable MCP-only').Count | Should -Be 1
    }
}

Describe 'Invoke-DwRecipe probes never wait without bound' {
    It 'spends pollSeconds once for the whole probe, not once per failing subject, and names what it waited for' {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        Remove-Item Env:DW_API_TOKEN -ErrorAction SilentlyContinue
        $root = New-RecipeSandbox
        $groups = @(1..6 | ForEach-Object { @{name = "Absent $_"; kind = 'account'; customerNumber = "C-$_"; users = @(@{userName = "u$_@example.invalid"})} })
        $in = Write-Input @{groups = $groups} 'users.accounts'
        $src = 'skills/x.md'
        $recipe = @{schema = 1; id = 'users.accounts'; name = 'Poll'; functions = @('users.accounts'); skill = 'dw-users-permissions'; inputs = @{section = 'users.accounts'; required = @('groups')}
            modes = @{mcpOnly = @{usable = $true; reason = 'MCP.'}; hosted = @{usable = $true; reason = 'No SQL.'}; local = @{usable = $true}; layerDelivered = 'verify'}
            steps = @(@{id = 'groups'; title = 'Groups'; forEach = 'groups[*]'; key = '{item.name}'; bindings = @(); source = $src
                    find = @{bindings = @(@{id = 'g'; surface = 'mcp'; status = 'implemented'; operation = 'get_user_groups'; arguments = @{}; rows = 'data'; match = @{name = '{item.name}'}; source = $src})}})
            debts = @(); provenOn = @(); traps = @()
            verify = @{checkIds = @(); probes = @(@{id = 'late'; title = 'Each group appears'; forEach = 'groups[*]'; minimumSubjects = 1; pollSeconds = 3
                        bindings = @(@{surface = 'mcp'; status = 'implemented'; operation = 'get_user_groups'; arguments = @{}; rows = 'data'; match = @{name = '{item.name}'}; assert = @{kind = 'count'; op = 'eq'; value = 1}; source = $src})})}}
        $file = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json')
        $recipe | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $file -Encoding utf8
        New-Stub
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-Runner $root @{Recipe = $file; InputPath = $in}
        $sw.Stop()
        # Six subjects that never pass: one 3 s budget, not six (18 s and more).
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 12
        @($r.lines -match '^FAIL probe/late: 6 failing: subject 1: .*read again for the probe''s 3 s poll budget: get_user_groups').Count | Should -Be 1
        @($global:RecipeStub.log -match '^mcp get_user_groups').Count | Should -BeLessThan 16
    }
}

Describe 'Invoke-DwRecipe on an asset folder that exists in other letter case' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        Remove-Item Env:DW_API_TOKEN -ErrorAction SilentlyContinue
        $script:Root = New-RecipeSandbox
        $example = Get-Content -LiteralPath (Join-Path $script:Source 'assets/recipe-input.example.json') -Raw | ConvertFrom-Json -AsHashtable
        $brand = $example.brand
        $brand.assetFolder = 'rhino'; $brand.favicon = '/Files/Images/rhino/rhino-favicon.png'
        $brand.files = @(@{file = 'kit/rhino-favicon.png'; name = 'rhino-favicon.png'})
        $script:InputFile = Write-Input $brand 'brand'
        $null = New-Item -ItemType Directory -Force (Join-Path $TestDrive 'kit')
        [IO.File]::WriteAllBytes((Join-Path $TestDrive 'kit/rhino-favicon.png'), [byte[]](1..7))
        $src = 'skills/x.md'
        $folderRead = @{surface = 'mcp'; status = 'implemented'; operation = 'list_files'; arguments = @{path = '/Files/Images'}; rows = 'data'; match = @{name = '{input.assetFolder}'; isDirectory = $true}; ignoreCase = @('name'); produces = @{path = 'path'}; source = $src}
        $fileRead = @{surface = 'mcp'; status = 'implemented'; operation = 'list_files'; arguments = @{path = '{step.folder[input.assetFolder].path}'}; rows = 'data'; match = @{name = '{item.name}'; isDirectory = $false}; ignoreCase = @('name'); source = $src}
        $recipe = @{schema = 1; id = 'content.design-styles'; name = 'Folder'; functions = @('content.design-styles'); skill = 'dw-swift-building'; inputs = @{section = 'brand'; required = @('id')}
            modes = @{mcpOnly = @{usable = $true; reason = 'MCP.'}; hosted = @{usable = $true; reason = 'No SQL.'}; local = @{usable = $true}; layerDelivered = 'both'}
            respell = @{step = 'folder'; from = '/Files/Images/{input.assetFolder}/'; to = '{step.folder[input.assetFolder].path}/'}
            steps = @(
                @{id = 'folder'; title = 'Folder'; key = '{input.assetFolder}'; find = @{bindings = @($folderRead)}; source = $src
                    bindings = @(@{id = 'mk'; surface = 'mcp'; status = 'implemented'; source = $src; create = @{operation = 'create_folder'; arguments = @{path = '/Files/Images/{input.assetFolder}'}}; readBack = $folderRead})},
                @{id = 'files'; title = 'Files'; forEach = 'files[*]'; key = '{item.name}'; find = @{bindings = @($fileRead + @{compare = @{byteSize = '{bytes:item.file}'}})}; source = $src
                    bindings = @(@{id = 'up'; surface = 'mcp'; status = 'implemented'; source = $src; create = @{operation = 'upload_file'; arguments = @{path = '{step.folder[input.assetFolder].path}/{item.name}'; content = '{base64:item.file}'; isBase64 = $true; overwrite = $true}}; readBack = ($fileRead + @{expect = @{byteSize = '{bytes:item.file}'}})})},
                @{id = 'favicon'; title = 'The favicon file the input names'; key = 'favicon'; source = $src
                    find = @{bindings = @(@{surface = 'mcp'; status = 'implemented'; operation = 'list_files'; arguments = @{path = '{step.folder[input.assetFolder].path}'}; rows = 'data'; match = @{path = '{input.favicon}'}; source = $src})}
                    bindings = @(@{id = 'up'; surface = 'mcp'; status = 'implemented'; source = $src; create = @{operation = 'create_folder'; arguments = @{path = '{input.favicon}'}}; readBack = @{surface = 'mcp'; status = 'implemented'; operation = 'list_files'; arguments = @{path = '/Files/Images'}; rows = 'data'; source = $src}})})
            debts = @(); provenOn = @(); traps = @(); verify = @{checkIds = @(); probes = @()}}
        $script:RecipeFile = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json')
        $recipe | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:RecipeFile -Encoding utf8
    }
    It 'finds the folder ignoring case, never creates a second one, and writes and reads every later path in its real spelling' {
        New-Stub
        $global:RecipeStub.files.Add(@{path = '/Files/Images/Rhino'; isDirectory = $true; byteSize = 0})
        $a = Invoke-Runner $script:Root @{Recipe = $script:RecipeFile; InputPath = $script:InputFile; Apply = $true}
        $a.lines | Should -Contain 'STEP folder UNCHANGED rhino'
        @($a.lines -match '^NOTE folder: the folder exists as /Files/Images/Rhino/').Count | Should -Be 1
        $a.lines | Should -Contain 'STEP files CREATED rhino-favicon.png'
        $a.lines | Should -Contain 'PASS files/rhino-favicon.png'
        # The favicon path of the input now names the folder as it is spelt: the existing file is found, nothing else is made.
        $a.lines | Should -Contain 'STEP favicon UNCHANGED favicon'
        $a.exit | Should -Be 0
        @(Get-Writes | Where-Object { $_ -like 'mcp create_folder*' }).Count | Should -Be 0
        @($global:RecipeStub.log | Where-Object { $_ -like 'mcp upload_file*/Files/Images/Rhino/rhino-favicon.png*' }).Count | Should -Be 1
        @($global:RecipeStub.files | Where-Object { $_.isDirectory }).Count | Should -Be 1
    }
}

Describe 'Invoke-DwRecipe on scan steps' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        Remove-Item Env:DW_API_TOKEN -ErrorAction SilentlyContinue
        $script:Root = New-RecipeSandbox
        $script:InputFile = Write-Input @{forbidden = @(@{text = 'Fabrikam'; replacement = 'Contoso'}); renderCheck = @(@{path = '/en-us/story'})} 'debrand'
    }
    It 'lists every place in verify, replaces them in one batched call, reads each back, reports an unwritable place OPEN, then finds nothing' {
        New-Stub
        $s = $global:RecipeStub
        $s.tools.get_translatable_content = Get-Schema @('areaId', 'pageId', 'take', 'skip')
        $s.tools.apply_translation = Get-Schema @('translations') @('translations')
        $s.tools.get_shops = Get-Schema @()
        $s.tools.get_area_by_id = Get-Schema @('areaId') @('areaId')
        $s.tools.get_item_field_values = Get-Schema @('itemType', 'itemId') @('itemType', 'itemId')
        $s.tools.set_item_field_values = Get-Schema @('values') @('values')
        $s.units = [Collections.Generic.List[object]]::new()
        foreach ($u in @(@{pageId = 7; kind = 'PageField'; paragraphId = 0; fieldSystemName = 'MetaTitle'; sourceText = 'FABRIKAM | Story'},
                @{pageId = 7; kind = 'ParagraphItemField'; paragraphId = 3; fieldSystemName = 'Text'; sourceText = '<p>&copy; Fabrikam Ltd.</p>'},
                @{pageId = 8; kind = 'ParagraphField'; paragraphId = 4; fieldSystemName = 'Header'; sourceText = 'Unrelated'})) { $s.units.Add($u) }
        $s.master = @(@{fieldSystemName = 'MetaSiteName'; value = 'Shop'}, @{fieldSystemName = 'Favicon'})
        $inner = $s.mcp
        $s.mcp = {
            param($Tool, $Arguments)
            $s = $global:RecipeStub
            switch ($Tool) {
                # Two units per page of the read, so the scan has to follow hasMore.
                'get_translatable_content' {
                    $all = @($s.units | Where-Object { -not $Arguments.pageId -or $_.pageId -eq [int]$Arguments.pageId })
                    $skip = [int]$Arguments.skip; $page = @($all | Select-Object -Skip $skip -First 2)
                    return @{structuredContent = @{units = $page; hasMore = ($skip + 2 -lt $all.Count); nextSkip = $skip + 2}}
                }
                'apply_translation' {
                    foreach ($t in $Arguments.translations) { foreach ($u in $s.units) { if ($u.pageId -eq [int]$t.pageId -and $u.kind -eq $t.kind -and $u.paragraphId -eq [int]$t.paragraphId -and $u.fieldSystemName -eq $t.fieldSystemName) { $u.sourceText = $t.translatedText } } }
                    return @{structuredContent = @{succeeded = @($Arguments.translations).Count; failed = 0}}
                }
                'get_area_by_id' { return @{structuredContent = @{id = 1; name = 'Fabrikam web'; itemType = 'Swift-v2_Master'; itemId = '1'}} }
                'get_item_field_values' { return @{structuredContent = @{data = $s.master}} }
                'get_shops' { return @{structuredContent = @{count = 1; data = @(@{id = 'SHOP1'; name = 'Main'})}} }
                'fetch_frontend_page_html' {
                    $t = @($s.units | Where-Object { $_.fieldSystemName -eq 'MetaTitle' })[0].sourceText
                    return @{structuredContent = @{statusCode = 200; title = $t; h1Tags = @('Story'); path = $Arguments.path}}
                }
                default { return (& $inner $Tool $Arguments) }
            }
        }.GetNewClosure()
        $v = Invoke-Runner $script:Root @{Recipe = 'content.page-seo'; InputPath = $script:InputFile}
        $v.lines | Should -Contain 'STEP page-texts WOULD-UPDATE Fabrikam@7/PageField/0/MetaTitle'
        $v.lines | Should -Contain 'STEP page-texts WOULD-UPDATE Fabrikam@7/ParagraphItemField/3/Text'
        $v.lines | Should -Contain 'STEP website-name WOULD-UPDATE Fabrikam@1'
        ($v.lines -match '^FAIL website-name/Fabrikam@1: .*apply cannot: no write binding: renaming a website').Count | Should -Be 1
        ($v.lines -match '^FAIL probe/rendered-title: .*excluded').Count | Should -Be 1
        Get-Writes | Should -BeNullOrEmpty
        $a = Invoke-Runner $script:Root @{Recipe = 'content.page-seo'; InputPath = $script:InputFile; Apply = $true}
        @($s.log | Where-Object { $_ -like 'mcp apply_translation *' }).Count | Should -Be 1
        $a.lines | Should -Contain 'PASS page-texts/Fabrikam@7/ParagraphItemField/3/Text'
        $a.lines | Should -Contain 'STEP website-name BLOCKED Fabrikam@1'
        ($a.lines -match '^OPEN website-name/Fabrikam@1: name at 1 holds the text').Count | Should -Be 1
        $a.lines | Should -Contain 'PASS probe/rendered-title'
        @($s.units.sourceText) | Should -Contain 'Contoso | Story'
        @($s.units.sourceText) | Should -Contain '<p>&copy; Contoso Ltd.</p>'
        $a.exit | Should -Be 1
        $again = Invoke-Runner $script:Root @{Recipe = 'content.page-seo'; InputPath = $script:InputFile; Apply = $true}
        $again.lines | Should -Contain 'STEP page-texts UNCHANGED Fabrikam'
        @($s.log | Where-Object { $_ -like 'mcp apply_translation *' }).Count | Should -Be 1
    }
    It 'replaces every occurrence ignoring case, and refuses the replaced token outside a scan' {
        $ctx = @{row = @{text = 'Fabrikam and FABRIKAM'}; replace = @{text = 'fabrikam'; with = 'Contoso'}; results = @{}; secrets = @{}}
        Resolve-RecipeToken 'replaced:row.text' $ctx | Should -Be 'Contoso and Contoso'
        { Resolve-RecipeToken 'replaced:row.text' @{row = @{text = 'x'}; results = @{}; secrets = @{}} } | Should -Throw '*outside a scan step*'
    }
}

Describe 'Invoke-DwRecipe on a prune step' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        Remove-Item Env:DW_API_TOKEN -ErrorAction SilentlyContinue
        $script:Root = New-RecipeSandbox
        $script:History = @{buyer = @{userName = 'buyer@example.invalid'; passwordRef = 'buyer'}; shop = 'SHOP1'; reset = $true
            orders = @(@{reference = 'PO-1'; daysAgo = 3; state = 'completed'; lines = @(@{product = 'P-1'; quantity = 1})})}
        $script:InputFile = Write-Input $script:History 'history'
        $read = @{surface = 'mcp'; status = 'implemented'; operation = 'search_orders'; arguments = @{request = @{userId = '{scope}'; pageSize = 200}}; rows = 'data'; source = 'skills/x.md'}
        $script:Recipe = @{schema = 1; id = 'orders.completed-orders'; name = 'Reset'; functions = @('orders.completed-orders'); skill = 'dw-commerce-orders'; inputs = @{section = 'history'; required = @('buyer')}
            modes = @{mcpOnly = @{usable = $true; reason = 'MCP.'}; hosted = @{usable = $true; reason = 'No SQL.'}; local = @{usable = $true}; layerDelivered = 'verify'}
            steps = @(
                @{id = 'buyer'; title = 'Find the buyer'; key = '{input.buyer.userName}'; find = @{bindings = @(@{surface = 'mcp'; status = 'implemented'; operation = 'get_users_by_usernames'; arguments = @{userNames = @('{input.buyer.userName}')}; rows = 'data'; match = @{userName = '{input.buyer.userName}'}; produces = @{id = 'id'}; source = 'skills/x.md'})}; bindings = @(); source = 'skills/x.md'},
                @{id = 'reset'; title = 'Remove what the input does not name'; key = '{input.buyer.userName}'; skipWhen = @{path = 'input.reset'; notEquals = $true}
                    prune = @{scope = @{values = '{step.buyer[input.buyer.userName].id}'; member = 'customerAccessUserId'}; binding = $read; keep = @{field = 'purchaseOrderNumber'; values = '{input.orders[*].reference|[]}'}; identify = @('id'); max = 5}
                    bindings = @(@{id = 'delete-order'; surface = 'mcp'; status = 'implemented'; source = 'skills/x.md'; delete = @{operation = 'delete_order'; arguments = @{id = '{row.id}'; force = $true}}; readBack = $read})
                    source = 'skills/x.md'})
            debts = @(); verify = @{checkIds = @(); probes = @()}; provenOn = @(); traps = @()}
        function Save-Recipe { $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json'); $script:Recipe | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding utf8; return $path }
        function New-OrderStub {
            New-Stub
            $s = $global:RecipeStub
            $s.tools.search_orders = Get-Schema @('request') @('request'); $s.tools.delete_order = Get-Schema @('id', 'hardDelete', 'force') @('id')
            $s.users.Add(@{id = 7; userName = 'buyer@example.invalid'}); $s.ignoreFilter = $false
            $s.orders = [Collections.Generic.List[object]]::new()
            # The seeded order, two rehearsal orders and a cart of the buyer (a cart has no reference: the member is left out), and another buyer's order.
            foreach ($o in @(@{id = 'ORDER1'; purchaseOrderNumber = 'PO-1'; customerAccessUserId = 7}, @{id = 'ORDER2'; purchaseOrderNumber = 'REHEARSAL'; customerAccessUserId = 7},
                    @{id = 'ORDER3'; purchaseOrderNumber = ''; customerAccessUserId = 7}, @{id = 'CART1'; customerAccessUserId = 7}, @{id = 'ORDER9'; purchaseOrderNumber = 'OTHER'; customerAccessUserId = 8})) { $s.orders.Add($o) }
            $inner = $s.mcp
            $s.mcp = {
                param($Tool, $Arguments)
                $s = $global:RecipeStub
                switch ($Tool) {
                    'search_orders' { $rows = @($s.orders | Where-Object { $s.ignoreFilter -or $_.customerAccessUserId -eq [int]$Arguments.request.userId }); return @{structuredContent = @{count = $rows.Count; total = $rows.Count; data = $rows}} }
                    'delete_order' { $o = @($s.orders | Where-Object { $_.id -eq $Arguments.id })[0]; [void]$s.orders.Remove($o); return @{structuredContent = @{order = $o; forceDeleted = $true}} }
                    default { return (& $inner $Tool $Arguments) }
                }
            }.GetNewClosure()
        }
        function Get-Deletes { @($global:RecipeStub.log | Where-Object { $_ -like 'mcp delete_order *' }) }
    }
    It 'lists what it would delete within the scope, deletes exactly that and reads it back, then finds nothing to delete' {
        New-OrderStub
        $file = Save-Recipe
        $v = Invoke-Runner $script:Root @{Recipe = $file; InputPath = $script:InputFile}
        @($v.lines -match '^STEP reset WOULD-DELETE ') | Should -Be @('STEP reset WOULD-DELETE buyer@example.invalid@ORDER2', 'STEP reset WOULD-DELETE buyer@example.invalid@ORDER3', 'STEP reset WOULD-DELETE buyer@example.invalid@CART1')
        ($v.lines -match '^FAIL reset/buyer@example.invalid@ORDER2: the input does not name it; apply would delete it').Count | Should -Be 1
        Get-Deletes | Should -BeNullOrEmpty
        $v.exit | Should -Be 1
        $a = Invoke-Runner $script:Root @{Recipe = $file; InputPath = $script:InputFile; Apply = $true}
        $a.lines | Should -Contain 'STEP reset DELETED buyer@example.invalid@CART1'
        $a.lines | Should -Contain 'PASS reset/buyer@example.invalid@ORDER3'
        (Get-Deletes).Count | Should -Be 3
        @($global:RecipeStub.log | Where-Object { $_ -like 'mcp delete_order *' }) -join ' ' | Should -Match '"force":true'
        @($global:RecipeStub.orders.id) | Should -Be @('ORDER1', 'ORDER9')
        $a.exit | Should -Be 0
        $again = Invoke-Runner $script:Root @{Recipe = $file; InputPath = $script:InputFile; Apply = $true}
        $again.lines | Should -Contain 'STEP reset UNCHANGED buyer@example.invalid'
        (Get-Deletes).Count | Should -Be 3
        $again.exit | Should -Be 0
    }
    It 'refuses an empty scope before any read and deletes nothing' {
        New-OrderStub
        $global:RecipeStub.users[0].id = 0
        $a = Invoke-Runner $script:Root @{Recipe = (Save-Recipe); InputPath = $script:InputFile; Apply = $true}
        $a.lines | Should -Contain 'STEP reset BLOCKED buyer@example.invalid'
        ($a.lines -match '^OPEN reset/buyer@example.invalid: refused: the prune scope is empty').Count | Should -Be 1
        @($global:RecipeStub.log | Where-Object { $_ -like 'mcp search_orders *' }) | Should -BeNullOrEmpty
        Get-Deletes | Should -BeNullOrEmpty
        $a.exit | Should -Be 1
    }
    It 'refuses the whole set when the read returns a row outside the scope, and a read that does not pass the scope' {
        New-OrderStub
        $global:RecipeStub.ignoreFilter = $true
        $a = Invoke-Runner $script:Root @{Recipe = (Save-Recipe); InputPath = $script:InputFile; Apply = $true}
        ($a.lines -match '^FAIL reset/buyer@example.invalid: refused: 1 row\(s\) of .search_orders. are outside the scope').Count | Should -Be 1
        Get-Deletes | Should -BeNullOrEmpty
        $global:RecipeStub.ignoreFilter = $false
        $script:Recipe.steps[1].prune.binding = @{surface = 'mcp'; status = 'implemented'; operation = 'search_orders'; arguments = @{request = @{pageSize = 200}}; rows = 'data'; source = 'skills/x.md'}
        $b = Invoke-Runner $script:Root @{Recipe = (Save-Recipe); InputPath = $script:InputFile; Apply = $true}
        ($b.lines -match '^OPEN reset/buyer@example.invalid: refused: the prune read does not pass \{scope\}').Count | Should -Be 1
        Get-Deletes | Should -BeNullOrEmpty
    }
    It 'refuses more rows than max, and a delete tool off recipeDeleteTools' {
        New-OrderStub
        $script:Recipe.steps[1].prune.max = 2
        $a = Invoke-Runner $script:Root @{Recipe = (Save-Recipe); InputPath = $script:InputFile; Apply = $true}
        ($a.lines -match '^FAIL reset/buyer@example.invalid: refused: 3 row\(s\) to remove, more than prune.max 2').Count | Should -Be 1
        $script:Recipe.steps[1].prune.max = 5
        $script:Recipe.steps[1].bindings[0].delete.operation = 'delete_pages'
        $b = Invoke-Runner $script:Root @{Recipe = (Save-Recipe); InputPath = $script:InputFile; Apply = $true}
        ($b.lines -match '^OPEN reset/buyer@example.invalid@ORDER2: .*MCP delete_pages is not on the recipe delete allowlist').Count | Should -Be 1
        Get-Deletes | Should -BeNullOrEmpty
        @($global:RecipeStub.log | Where-Object { $_ -like 'mcp delete_pages *' }) | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-DwBrandKit' {
    BeforeAll {
        function New-PngHeader([int]$Width, [int]$Height) {
            # The signature and IHDR chunk a PNG opens with: all the converter reads for the size.
            $b = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52) + [BitConverter]::GetBytes([int]$Width)[3..0] + [BitConverter]::GetBytes([int]$Height)[3..0] + [byte[]](8, 6, 0, 0, 0, 0, 0, 0, 0)
            return , [byte[]]$b
        }
    }
    It 'splits a RenderCheck list that pwsh -File passed as one text, writes LogoWidth, and warns about an icon-shaped logo' {
        $kit = Join-Path $TestDrive 'kit2/swift2'
        foreach ($d in 'ColorSchemes', 'Typography', 'Buttons', 'branding') { $null = New-Item -ItemType Directory -Force (Join-Path $kit $d) }
        @{Id = 'contoso'; Name = 'Contoso'; Schemes = @(@{Id = 'light'; Name = 'Light'; BackgroundColor = '#ffffff'; ForegroundColor = '#111111'; PrimaryButtonColor = '#0b5d4b'; SecondaryButtonColor = '#000000'})} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $kit 'ColorSchemes/contoso.json')
        @{Id = 'contoso'; Name = 'Contoso'; BaseFontSize = 16; BaseFontScale = 1.2; ParagraphFontWeight = 400; ParagraphLineHeight = 1.5; HeadingFontWeight = 700; HeadingLineHeight = 1.2; ButtonFontWeight = 600; ButtonLineHeight = 1.4} | ConvertTo-Json | Set-Content (Join-Path $kit 'Typography/contoso.json')
        @{Id = 'contoso'; Name = 'Contoso'; Shape = 1; PaddingX = 1; PaddingY = 0.5; BorderSize = 1} | ConvertTo-Json | Set-Content (Join-Path $kit 'Buttons/contoso.json')
        [IO.File]::WriteAllBytes((Join-Path $kit 'branding/contoso-logo.png'), (New-PngHeader 420 96))
        [IO.File]::WriteAllBytes((Join-Path $kit 'branding/contoso-social.png'), (New-PngHeader 48 48))
        @{headerDesktop = @{Id = '/Files/Images/branding/contoso-logo.png'; Name = 'contoso-logo.png'}; headerMobile = @{Id = '/Files/Images/branding/contoso-logo.png'; Name = 'contoso-logo.png'; Width = 120}
            footerDesktop = @{Id = '/Files/Images/branding/contoso-social.png'; Name = 'contoso-social.png'}; footerMobile = $null; favicon = $null} | ConvertTo-Json | Set-Content (Join-Path $kit 'logo-fields.json')
        $out = Join-Path $TestDrive 'input2/recipe-input.json'
        $null = New-Item -ItemType Directory -Force (Split-Path $out)
        @{schema = 1; build = @{areaId = 1}} | ConvertTo-Json | Set-Content $out
        # As an operator's shell hands it over: one argument holding the quoted list.
        $lines = & pwsh -NoProfile -File (Join-Path $script:Source 'scripts/ConvertFrom-DwBrandKit.ps1') -KitPath $kit -OutPath $out -RenderCheck "'/en-us/home','/en-us/shop'" 2>&1 | ForEach-Object { "$_" }
        $LASTEXITCODE | Should -Be 0
        $b = (Read-LedgerJson $out (Join-Path $script:Source 'assets/recipe-input.schema.json')).brand
        @($b.renderCheck.path) | Should -Be @('/en-us/home', '/en-us/shop')
        @($b.layout | Where-Object { $_.slot -eq 'HeaderDesktop' })[0].logo.LogoWidth | Should -Be '210'
        @($b.layout | Where-Object { $_.slot -eq 'HeaderMobile' })[0].logo.LogoWidth | Should -Be '120'
        ($lines -match 'logo slot FooterDesktop: contoso-social\.png is only 48x48 px.*square').Count | Should -Be 1
        ($lines -match 'logo slot Header').Count | Should -Be 0
        & (Join-Path $script:Source 'scripts/ConvertFrom-DwBrandKit.ps1') -KitPath $kit -OutPath $out -RenderCheck '/en-us/home, /en-us/shop' -WarningAction SilentlyContinue | Out-Null
        @((Get-Content $out -Raw | ConvertFrom-Json).brand.renderCheck.path) | Should -Be @('/en-us/home', '/en-us/shop')
        { & (Join-Path $script:Source 'scripts/ConvertFrom-DwBrandKit.ps1') -KitPath $kit -OutPath $out -RenderCheck 'en-us/home' -WarningAction SilentlyContinue } | Should -Throw '*not a storefront path*'
    }
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
        $b.layout[0].logo.LogoWidth | Should -Be '210'
    }
    It 'writes letter spacing in em at each role''s own size, and clamps an implausible em with a warning' {
        $root = Join-Path $TestDrive 'kit3'; $kit = Join-Path $root 'swift2'
        foreach ($d in 'ColorSchemes', 'Typography', 'Buttons') { $null = New-Item -ItemType Directory -Force (Join-Path $kit $d) }
        @{Id = 'contoso'; Name = 'Contoso'; Schemes = @(@{Id = 'light'; Name = 'Light'; BackgroundColor = '#ffffff'; ForegroundColor = '#111111'; PrimaryButtonColor = '#0b5d4b'; SecondaryButtonColor = '#000000'})} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $kit 'ColorSchemes/contoso.json')
        # As the extractor writes it: the px it measured over the base size, so a 45 px heading at -2.25 px reads -0.141.
        @{Id = 'contoso'; Name = 'Contoso'; BaseFontSize = 16; BaseFontScale = 1.2; ParagraphFontWeight = 400; ParagraphLineHeight = 1.5; ParagraphLetterSpacing = 0.0125
            HeadingFontWeight = 700; HeadingLineHeight = 1.2; HeadingLetterSpacing = -0.141; ButtonFontWeight = 600; ButtonLineHeight = 1.4; ButtonLetterSpacing = 0.05} | ConvertTo-Json | Set-Content (Join-Path $kit 'Typography/contoso.json')
        @{Id = 'contoso'; Name = 'Contoso'; Shape = 1; PaddingX = 1; PaddingY = 0.5; BorderSize = 1} | ConvertTo-Json | Set-Content (Join-Path $kit 'Buttons/contoso.json')
        $dim = { param($v, $u = 'px') @{'$type' = 'dimension'; '$value' = @{value = $v; unit = $u}} }
        @{typography = @{size = @{base = (& $dim 16); h1 = (& $dim 45)}; letterSpacing = @{body = (& $dim 0.2); heading = (& $dim -2.25); button = '{typography.letterSpacing.spaced}'; spaced = (& $dim 0.05 'rem')}}} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'brand.tokens.json')
        $out = Join-Path $TestDrive 'input3/recipe-input.json'
        $null = New-Item -ItemType Directory -Force (Split-Path $out)
        $lines = & (Join-Path $script:Source 'scripts/ConvertFrom-DwBrandKit.ps1') -KitPath $kit -OutPath $out 3>&1 | ForEach-Object { "$_" }
        $t = (Read-LedgerJson $out (Join-Path $script:Source 'assets/recipe-input.schema.json')).brand.typography
        $t.headingLetterSpacing | Should -Be -0.05
        $t.paragraphLetterSpacing | Should -Be 0.0125
        $t.buttonLetterSpacing | Should -Be 0.05
        @(@($lines) -match 'LetterSpacing').Count | Should -Be 0
        # Without the tokens the swift2 value is all there is: -0.141 em is clamped and said.
        Remove-Item (Join-Path $root 'brand.tokens.json')
        $lines = & (Join-Path $script:Source 'scripts/ConvertFrom-DwBrandKit.ps1') -KitPath $kit -OutPath $out 3>&1 | ForEach-Object { "$_" }
        (Read-LedgerJson $out (Join-Path $script:Source 'assets/recipe-input.schema.json')).brand.typography.headingLetterSpacing | Should -Be -0.06
        @(@($lines) -match 'typography HeadingLetterSpacing: -0\.141 em is outside -0\.06 to 0\.3.*written as -0\.06 em').Count | Should -Be 1
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

Describe 'Shipped recipes against the platform shapes a whole-build set met' {
    BeforeAll {
        . (Join-Path $script:Source 'scripts/Recipe.Transport.ps1')
        . (Join-Path $script:Source 'scripts/Recipe.Write.ps1')
        . (Join-Path $script:Source 'scripts/Recipe.Steps.ps1')
        $script:Registry = Read-LedgerJson (Join-Path $script:Source 'assets/handlers.json')
        function Get-ShippedRecipe([string]$Area, [string]$Id) { Read-LedgerJson (Join-Path $script:Source "assets/recipes/$Area/$Id.json") (Join-Path $script:Source 'assets/recipe.schema.json') }
        function New-StepRun($Section, [hashtable]$Results, [hashtable]$Cap) {
            @{section = $Section; build = @{}; results = $Results; secrets = @{}; inputDir = $TestDrive; cap = $Cap; registry = $script:Registry; apply = $true; changed = $false; blocked = 0
                lines = [Collections.Generic.List[string]]::new(); checks = [Collections.Generic.List[object]]::new(); steps = [Collections.Generic.List[object]]::new()}
        }
    }
    It 'asks completeness in the catalogue''s own shop when the build names no PIM shop' {
        $probe = @((Get-ShippedRecipe 'pim' 'pim.identifiers').verify.probes | Where-Object id -eq 'completeness')[0]
        $ctx = @{input = @{shop = 'SHOP1'}; item = @{number = 'P-1'; group = 'tools'}; build = @{areaId = 1}; secrets = @{}
            results = @{products = @{'P-1' = @{state = 'UNCHANGED'; values = @{id = 'PROD1'}}}; models = @{tools = @{state = 'UNCHANGED'; values = @{id = 'MODEL1'}}}}}
        $arguments = Expand-RecipeValue $probe.bindings[0].arguments $ctx
        $arguments.shopId | Should -Be 'SHOP1'
        $arguments.groupIds | Should -Be @('MODEL1')
        $ctx.build.pimShop = 'PIMSHOP1'
        (Expand-RecipeValue $probe.bindings[0].arguments $ctx).shopId | Should -Be 'PIMSHOP1'
    }
    It 'compares a state''s next states in any order, as get_workflow_states lists them sorted by id, and still sees a missing one' {
        $step = @((Get-ShippedRecipe 'pim' 'pim.workflow').steps | Where-Object id -eq 'transitions')[0]
        $step.bindings[0].readBack.unordered | Should -Contain 'nextStateIds'
        function Read-RecipeRows { param($Binding, $Context, $Run) , @(@{id = 2; name = 'Review'; nextStateIds = @(1, 3)}) }
        $run = New-StepRun @{} @{} @{surfaces = @('mcp'); mcp = $true; tools = @{get_workflow_states = @{type = 'object'; properties = @{}}}}
        $ctx = @{input = @{}; item = @{name = 'Review'; next = @('Copy', 'Draft')}; secrets = @{}; key = 'Review'
            results = @{states = @{Draft = @{state = 'UNCHANGED'; values = @{id = 1}}; Copy = @{state = 'UNCHANGED'; values = @{id = 3}}}}}
        (Find-RecipeObject $step $ctx $run).state | Should -Be 'UNCHANGED'
        $ctx.item.next = @('Copy')
        $found = Find-RecipeObject $step $ctx $run
        $found.state | Should -Be 'UPDATE'
        $found.fields | Should -Be @('nextStateIds')
        # Each element as often: a list with a repeated id is not the same set.
        Test-RecipeEqualUnordered @(1, 3, 3) @(3, 1, 1) | Should -BeFalse
        Test-RecipeEqualUnordered @(10, 2) @(2, 10) | Should -BeTrue
    }
    It 'saves a payment method''s country relation once more when a duplicated stored key survives the first save, and says so' {
        $step = @((Get-ShippedRecipe 'orders' 'orders.payment-methods').steps | Where-Object id -eq 'payment-scope')[0]
        # The platform removes one stored relation per key per save, as measured: a key stored twice needs two saves.
        $state = @{saves = 0; method = @{id = 'PAY9'; name = 'Pay on account'; isActive = $true; countryRelationKeys = @('US|', 'DK|', 'GB|', 'DK|'); userGroups = @()}}
        function Invoke-DwApi { param($Command, $Body, $Method, $TimeoutSec, $RetryCount, $RetryDelayMs)
            if ($Command -like 'PaymentsAll*') { return @{model = @{data = @($state.method)}} }
            if ($Command -ne 'PaymentSave') { throw "unexpected $Command" }
            $state.saves++
            $want = @($Body.Model.countryRelationKeys)
            $kept = [Collections.Generic.List[string]]::new([string[]]@($state.method.countryRelationKeys))
            foreach ($k in @($kept | Where-Object { $_ -notin $want } | Select-Object -Unique)) { $null = $kept.Remove($k) }
            foreach ($k in $want) { if ($k -notin $kept) { $kept.Add($k) } }
            $state.method.countryRelationKeys = $kept.ToArray(); $state.method.userGroups = @($Body.Model.userGroups)
            return @{status = 'ok'}
        }
        $section = @{country = 'US'; language = 'ENU'; methods = @(@{name = 'Pay on account'; kind = 'payment'; active = $true; anonymous = $false})}
        $results = @{'payment-methods' = @{'Pay on account' = @{state = 'UNCHANGED'; values = @{id = 'PAY9'}}}; groups = @{}}
        $run = New-StepRun $section $results @{surfaces = @('admin-api'); admin = $true; tools = @{}}
        Invoke-RecipeStep $step $run
        $state.saves | Should -Be 2
        $state.method.countryRelationKeys | Should -Be @('US|')
        $run.lines | Should -Contain 'STEP payment-scope UPDATED Pay on account'
        @($run.lines -match '^NOTE payment-scope/Pay on account: the read-back differed in countryRelationKeys after one save; saved once more, as declared: PaymentSave removes').Count | Should -Be 1
        $run.lines | Should -Contain 'PASS payment-scope/Pay on account'
        # A relation without a duplicate settles on the first save: one save, no note.
        $state.saves = 0; $state.method.countryRelationKeys = @('US|', 'DK|')
        $run = New-StepRun $section $results @{surfaces = @('admin-api'); admin = $true; tools = @{}}
        Invoke-RecipeStep $step $run
        $state.saves | Should -Be 1
        @($run.lines -match '^NOTE ').Count | Should -Be 0
        $run.lines | Should -Contain 'PASS payment-scope/Pay on account'
    }
    It 'RED CONTROL: a save that still differs after the declared second save FAILs and says so' {
        $step = @((Get-ShippedRecipe 'orders' 'orders.payment-methods').steps | Where-Object id -eq 'payment-scope')[0]
        $state = @{saves = 0; method = @{id = 'PAY9'; name = 'Pay on account'; isActive = $true; countryRelationKeys = @('US|', 'DK|'); userGroups = @()}}
        function Invoke-DwApi { param($Command, $Body, $Method, $TimeoutSec, $RetryCount, $RetryDelayMs)
            if ($Command -like 'PaymentsAll*') { return @{model = @{data = @($state.method)}} }
            $state.saves++; return @{status = 'ok'}
        }
        $section = @{country = 'US'; language = 'ENU'; methods = @(@{name = 'Pay on account'; kind = 'payment'; active = $true; anonymous = $false})}
        $run = New-StepRun $section @{'payment-methods' = @{'Pay on account' = @{state = 'UNCHANGED'; values = @{id = 'PAY9'}}}; groups = @{}} @{surfaces = @('admin-api'); admin = $true; tools = @{}}
        Invoke-RecipeStep $step $run
        $state.saves | Should -Be 2
        @($run.lines -match '^FAIL payment-scope/Pay on account: the read-back differs from the write in countryRelationKeys after a second save$').Count | Should -Be 1
    }
}

Describe 'Invoke-DwRecipe debt modes: deferred, debts only, verification skipped' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        $env:DW_API_TOKEN = 'stub-api-token-0000'
        $env:DW_RECIPE_SECRETS = '{"buyer":"Stub-Passw0rd-x"}'
        $script:Root = New-RecipeSandbox
        $script:InputFile = Write-Input $script:UsersSection 'users.accounts'
    }
    It 'defers the debts of a change to the caller, names them in the report, and runs no probe with -SkipVerify' {
        New-Stub
        $report = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json')
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true; Debts = 'Defer'; SkipVerify = $true; ReportPath = $report}
        ($r.lines -match '^NOTE users\.accounts: debts owed, deferred to the caller: flush:').Count | Should -Be 1
        ($r.lines -match '^(PASS|FAIL|OPEN) (debt|probe|ledger)/').Count | Should -Be 0
        @($global:RecipeStub.log | Where-Object { $_ -like 'flush *' }).Count | Should -Be 0
        $json = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
        $json.changed | Should -BeTrue
        @($json.debtsOwed) | Should -Contain 'recycle'
        $r.exit | Should -Be 0
    }
    It 'splits -DebtNames and -Surfaces that pwsh -File passed as one comma-separated text, and refuses an unknown surface' {
        New-Stub
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true; Debts = 'Only'; SkipVerify = $true
            DebtNames = @("'flush:Dynamicweb.Security.UserManagement.UserService','index:Secondary users/Users.index'"); Surfaces = @('mcp, admin-api')}
        $r.lines | Should -Contain 'PASS debt/flush:Dynamicweb.Security.UserManagement.UserService'
        ($r.lines -match 'debt/recycle').Count | Should -Be 0
        ($r.lines -match 'owes no debt').Count | Should -Be 0
        $r.exit | Should -Be 0
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Surfaces = @('mcp,ftp')}
        ($r.lines -match "^FAIL recipe: Runner input: -Surfaces takes mcp, admin-api, dwapi and sql, not 'ftp'").Count | Should -Be 1
    }
    It 'pays only the named debts with -Debts Only, runs no step, and refuses it without -Apply or for a debt the recipe does not owe' {
        New-Stub
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true; Debts = 'Only'; DebtNames = @('flush:Dynamicweb.Security.UserManagement.UserService'); SkipVerify = $true}
        ($r.lines -match '^STEP ').Count | Should -Be 0
        $r.lines | Should -Contain 'PASS debt/flush:Dynamicweb.Security.UserManagement.UserService'
        ($r.lines -match 'debt/recycle').Count | Should -Be 0
        (Get-Writes).Count | Should -Be 0
        $r.exit | Should -Be 0
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Debts = 'Only'}
        ($r.lines -match '^FAIL recipe: Runner input: -Debts Only pays debts, which writes; add -Apply').Count | Should -Be 1
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true; Debts = 'Only'; DebtNames = @('assortments')}
        ($r.lines -match '^FAIL recipe: Runner input: users\.accounts owes no debt assortments').Count | Should -Be 1
        $r.exit | Should -Be 1
    }
}

Describe 'Invoke-DwRecipe on a retire step (orders.payment-methods retire-payment and retire-shipping)' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        Remove-Item Env:DW_API_TOKEN -ErrorAction SilentlyContinue
        $script:Root = New-RecipeSandbox
        # The shipped steps that ensure the named methods and retire the rest, without the Management API scope steps.
        $shipped = Get-Content -LiteralPath (Join-Path $script:Source 'assets/recipes/orders/orders.payment-methods.json') -Raw | ConvertFrom-Json -AsHashtable
        $script:Recipe = $shipped
        $script:Recipe.steps = @($shipped.steps | Where-Object { $_.id -in @('payment-methods', 'shipping-methods', 'retire-payment', 'retire-shipping') })
        $script:Recipe.dependsOn = @(); $script:Recipe.verify = @{checkIds = @(); probes = @()}
        $script:Checkout = @{country = 'US'; language = 'ENU'; keepMethods = @('Pickup cash'); methods = @(@{name = 'Card'; kind = 'payment'; active = $true; anonymous = $true})}
        function Save-Recipe { $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json'); $script:Recipe | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $path -Encoding utf8; return $path }
        function New-MethodStub([object[]]$Payments, [object[]]$Shippings) {
            New-Stub
            $s = $global:RecipeStub
            $s.tools.get_payment_methods = Get-Schema @(); $s.tools.save_payment_methods = Get-Schema @('paymentMethods') @('paymentMethods')
            $s.tools.get_shipping_methods = Get-Schema @(); $s.tools.save_shipping_methods = Get-Schema @('shippingMethods') @('shippingMethods')
            $s.payments = [Collections.Generic.List[object]]::new(); foreach ($p in $Payments) { $s.payments.Add($p) }
            $s.shippings = [Collections.Generic.List[object]]::new(); foreach ($p in $Shippings) { $s.shippings.Add($p) }
            $inner = $s.mcp
            $s.mcp = {
                param($Tool, $Arguments)
                $s = $global:RecipeStub
                # A save with an id changes only the members it sends, as measured; one without an id creates.
                $save = {
                    param($list, $items, $prefix)
                    foreach ($m in $items) {
                        if ($m.id) { $row = @($list | Where-Object { $_.id -eq $m.id })[0]; foreach ($k in $m.Keys) { $row[$k] = $m[$k] } }
                        else { $list.Add(@{id = "$prefix$($list.Count + 1)"; name = $m.name; active = $m.active; allowAnonymousUsers = $m.allowAnonymousUsers}) }
                    }
                    @{structuredContent = @{succeeded = @($items).Count; failed = 0}}
                }
                switch ($Tool) {
                    'get_payment_methods' { return @{structuredContent = @{count = $s.payments.Count; data = @($s.payments)}} }
                    'get_shipping_methods' { return @{structuredContent = @{count = $s.shippings.Count; data = @($s.shippings)}} }
                    'save_payment_methods' { return (& $save $s.payments $Arguments.paymentMethods 'PAY') }
                    'save_shipping_methods' { return (& $save $s.shippings $Arguments.shippingMethods 'SHIP') }
                    default { return (& $inner $Tool $Arguments) }
                }
            }.GetNewClosure()
        }
        function Get-MethodSaves { @($global:RecipeStub.log | Where-Object { $_ -match '^mcp save_(payment|shipping)_methods ' }) }
        $script:Payments = { @(@{id = 'PAY1'; name = 'Card'; active = $true; allowAnonymousUsers = $true}, @{id = 'PAY2'; name = 'Sample invoice'; active = $true; allowAnonymousUsers = $false},
            @{id = 'PAY3'; name = 'Old method'; active = $false; allowAnonymousUsers = $false}, @{id = 'PAY4'; name = 'Pickup cash'; active = $true; allowAnonymousUsers = $false}) }
        $script:Shippings = { @(@{id = 'SHIP1'; name = 'Sample ground'; active = $true; allowAnonymousUsers = $false}) }
    }
    It 'lists the active unnamed method, sets it inactive with a read-back, keeps the named and listed ones and every other kind, then finds nothing' {
        New-MethodStub (& $script:Payments) (& $script:Shippings)
        $file = Save-Recipe; $in = Write-Input $script:Checkout 'checkout'
        $v = Invoke-Runner $script:Root @{Recipe = $file; InputPath = $in}
        @($v.lines -match '^STEP retire-payment ') | Should -Be @('STEP retire-payment WOULD-RETIRE payment@PAY2/Sample invoice')
        ($v.lines -match '^FAIL retire-payment/payment@PAY2/Sample invoice: active and the input does not name it; apply would set it inactive').Count | Should -Be 1
        Get-MethodSaves | Should -BeNullOrEmpty
        $a = Invoke-Runner $script:Root @{Recipe = $file; InputPath = $in; Apply = $true}
        $a.lines | Should -Contain 'STEP retire-payment RETIRED payment@PAY2/Sample invoice'
        $a.lines | Should -Contain 'PASS retire-payment/payment@PAY2/Sample invoice'
        ($a.lines -match '^NOTE retire-payment/payment: 1 active row\(s\) the input does not name set inactive, none deleted; 2 kept').Count | Should -Be 1
        # No shipping method is named, so no shipping method is retired.
        ($a.lines -match '^STEP retire-shipping ').Count | Should -Be 0
        # One save, of the unnamed method only, and only its active flag (members in any order).
        $saves = @(Get-MethodSaves); $saves.Count | Should -Be 1
        ($saves[0] -replace '"id":"PAY2"', '' -replace '"active":false', '' -replace ',', '') | Should -Be 'mcp save_payment_methods {"paymentMethods":[{}]}'
        @($global:RecipeStub.payments | ForEach-Object { "$($_.id)=$($_.active)" }) | Should -Be @('PAY1=True', 'PAY2=False', 'PAY3=False', 'PAY4=True')
        $global:RecipeStub.shippings[0].active | Should -BeTrue
        $a.exit | Should -Be 0
        $again = Invoke-Runner $script:Root @{Recipe = $file; InputPath = $in; Apply = $true}
        $again.lines | Should -Contain 'STEP retire-payment UNCHANGED payment'
        @(Get-MethodSaves).Count | Should -Be 1
        $again.exit | Should -Be 0
    }
    It 'retires nothing when retireUnnamed is false' {
        New-MethodStub (& $script:Payments) (& $script:Shippings)
        $script:Checkout.retireUnnamed = $false
        $a = Invoke-Runner $script:Root @{Recipe = (Save-Recipe); InputPath = (Write-Input $script:Checkout 'checkout'); Apply = $true}
        ($a.lines -match '^STEP retire-').Count | Should -Be 0
        Get-MethodSaves | Should -BeNullOrEmpty
    }
    It 'refuses when a named method is blocked or when more than max would go, and retires nothing' {
        New-MethodStub (@(& $script:Payments) + @(@{id = 'PAY9'; name = 'Card'; active = $true; allowAnonymousUsers = $true})) (& $script:Shippings)
        $a = Invoke-Runner $script:Root @{Recipe = (Save-Recipe); InputPath = (Write-Input $script:Checkout 'checkout'); Apply = $true}
        ($a.lines -match "^OPEN retire-payment/payment: refused: step 'payment-methods' blocked 1 item\(s\)").Count | Should -Be 1
        Get-MethodSaves | Should -BeNullOrEmpty
        New-MethodStub (@(& $script:Payments) + @(1..30 | ForEach-Object { @{id = "PAYX$_"; name = "Sample $_"; active = $true; allowAnonymousUsers = $false} })) (& $script:Shippings)
        $b = Invoke-Runner $script:Root @{Recipe = (Save-Recipe); InputPath = (Write-Input $script:Checkout 'checkout'); Apply = $true}
        ($b.lines -match '^FAIL retire-payment/payment: refused: 31 active row\(s\) of .get_payment_methods. the input does not name, more than retire.max 25').Count | Should -Be 1
        Get-MethodSaves | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-DwRecipe on content.pages: adopting the page at the input path, and footer links' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        Remove-Item Env:DW_API_TOKEN -ErrorAction SilentlyContinue
        $script:Root = New-RecipeSandbox
        function New-SiteStub {
            # A sample base: the footer column folder Help and info (60) holds the page Delivery (50), served at
            # /en-us/delivery because the folder leaves its segment out; Delivery has two rows and a paragraph in each.
            New-Stub
            $s = $global:RecipeStub
            foreach ($t in @('get_navigation_structure', 'get_pages_by_area_id')) { $s.tools[$t] = Get-Schema @('areaId') @('areaId') }
            $s.tools.get_pages_by_ids = Get-Schema @('pageIds') @('pageIds')
            $s.pages.Add(@{id = 60; parentPageId = 0; menuText = 'Help and info'; urlName = 'help-and-info'; itemType = ''; active = $true})
            $s.pages.Add(@{id = 50; parentPageId = 60; menuText = 'Delivery'; urlName = 'delivery'; itemType = 'Swift-v2_Page'; active = $true})
            $s.fields['page50'] = [ordered]@{Title = 'Delivery'}
            $s.rows.Add(@{id = 70; pageId = 50; sort = 1; definitionId = '1Column'; container = 'Grid'; active = $true})
            $s.rows.Add(@{id = 71; pageId = 50; sort = 2; definitionId = '3Columns'; container = 'Grid'; active = $true})
            $s.paragraphs.Add(@{id = 80; pageId = 50; gridRowId = 70; gridRowColumn = 1; sort = 1; itemType = 'Swift-v2_Text'; active = $true})
            $s.paragraphs.Add(@{id = 81; pageId = 50; gridRowId = 71; gridRowColumn = 1; sort = 2; itemType = 'Swift-v2_Text'; active = $true})
            $s.fields['para80'] = [ordered]@{Title = 'Stock title'}; $s.fields['para81'] = [ordered]@{Title = 'Stock counter'}
            $inner = $s.mcp
            $s.mcp = {
                param($Tool, $Arguments)
                $s = $global:RecipeStub
                $ok = @{structuredContent = @{succeeded = 1; failed = 0; errors = @()}}
                $set = { param($row, $m, [string[]]$skip) foreach ($k in $m.Keys) { if ($k -notin $skip) { $row[$k] = $m[$k] } } }
                switch ($Tool) {
                    'get_navigation_structure' { return @{structuredContent = @{success = $true; items = @($s.pages | Where-Object { $_.active -and $_.urlName } | ForEach-Object { @{pageId = $_.id; name = $_.menuText; url = '/en-us/' + $_.urlName} })}} }
                    'get_pages_by_area_id' { return @{structuredContent = @{count = $s.pages.Count; data = @($s.pages)}} }
                    'get_pages_by_ids' { return @{structuredContent = @{data = @($s.pages | Where-Object { $_.id -in @($Arguments.pageIds | ForEach-Object { [int]$_ }) })}} }
                    'save_pages' {
                        foreach ($p in $Arguments.pages) {
                            if ([int]$p.id -eq 0) {
                                $s.nextId++; $id = $s.nextId
                                $s.pages.Add(@{id = $id; parentPageId = [int]$p.parentPageId; menuText = $p.menuText; urlName = $p.urlName; itemType = $p.itemType; sort = $p.sort; active = [bool]$p.active; shortCut = $p.shortCut}); $s.fields["page$id"] = [ordered]@{Title = $null}
                            } else { & $set @($s.pages | Where-Object { $_.id -eq [int]$p.id })[0] $p @('id') }
                        }
                        return $ok
                    }
                    # An inactive row is left out of the read, as measured on 10.30.6.
                    'get_grid_rows_by_page_id' { return @{structuredContent = @{data = @($s.rows | Where-Object { $_.pageId -eq [int]$Arguments.pageId -and $_.active -ne $false })}} }
                    'save_grid_rows' {
                        foreach ($r in $Arguments.gridRows) {
                            if ([int]$r.id -eq 0) { $s.nextId++; $s.rows.Add(@{id = $s.nextId; pageId = [int]$r.pageId; sort = $r.sort; definitionId = $r.definitionId; container = $r.container; active = $true}) }
                            else { & $set @($s.rows | Where-Object { $_.id -eq [int]$r.id })[0] $r @('id') }
                        }
                        return $ok
                    }
                    'save_paragraphs' {
                        $creates = @($Arguments.paragraphs | Where-Object { [int]$_.id -eq 0 })
                        foreach ($p in @($Arguments.paragraphs | Where-Object { [int]$_.id -ne 0 })) { & $set @($s.paragraphs | Where-Object { $_.id -eq [int]$p.id })[0] $p @('id') }
                        # A grid cell holds one paragraph: a create into an occupied cell is refused, as measured on 10.30.6.
                        $taken = @($creates | Where-Object { $c = $_; @($s.paragraphs | Where-Object { $_.gridRowId -eq [int]$c.gridRowId -and $_.gridRowId -ne 0 -and $_.gridRowColumn -eq $c.gridRowColumn }).Count })
                        if ($taken.Count) { return @{structuredContent = @{succeeded = 0; failed = $taken.Count; errors = @('cell taken')}} }
                        if ($creates.Count) { $null = & $inner $Tool @{paragraphs = $creates}; foreach ($p in $s.paragraphs) { if ($null -eq $p.active) { $p.active = $true } } }
                        return $ok
                    }
                    default { return (& $inner $Tool $Arguments) }
                }
            }.GetNewClosure()
        }
        $script:Page = {
            @{menuText = 'Delivery'; urlName = 'delivery'; itemType = 'Swift-v2_Page'; path = '/en-us/delivery'
                rows = @(@{sort = 1; definitionId = '1Column'; container = 'Grid'; itemType = 'Swift-v2_Row'})
                paragraphs = @(@{row = 1; column = 1; sort = 5; itemType = 'Swift-v2_Text'; fields = @{Title = 'Delivery'; Text = '<p>Copy.</p>'; FirstButton = ''}})}
        }
        function Get-PageWrites { @($global:RecipeStub.log | Where-Object { $_ -match '^mcp (save_|set_)' }) }
    }
    It 'blocks a page at the input path without adopt, and with adopt writes onto it and retires exactly what the input does not name' {
        New-SiteStub
        $page = & $script:Page
        $b = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = (Write-Input @{pages = @($page)} 'content.pages'); Apply = $true}
        $b.lines | Should -Contain 'STEP pages BLOCKED Delivery'
        Get-PageWrites | Should -BeNullOrEmpty
        $page.adopt = $true
        $in = Write-Input @{pages = @($page)} 'content.pages'
        $v = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $in}
        $v.lines | Should -Contain 'STEP pages ADOPTED Delivery'
        @($v.lines -match '^STEP adopt-(paragraphs|rows) ') | Should -Be @('STEP adopt-rows WOULD-RETIRE Delivery@71/2/3Columns', 'STEP adopt-paragraphs WOULD-RETIRE Delivery@80/Swift-v2_Text', 'STEP adopt-paragraphs WOULD-RETIRE Delivery@81/Swift-v2_Text')
        Get-PageWrites | Should -BeNullOrEmpty
        $a = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $in; Apply = $true}
        $a.lines | Should -Contain 'STEP pages ADOPTED Delivery'
        ($a.lines -match '^NOTE pages/Delivery: adopted the object that answers where a create would collide \(get_pages_by_ids id 50\)').Count | Should -Be 1
        $a.lines | Should -Contain 'STEP paragraphs CREATED Delivery/1/5'
        @($a.lines -match '^STEP adopt-(paragraphs|rows) ') | Should -Be @('STEP adopt-rows RETIRED Delivery@71/2/3Columns', 'STEP adopt-paragraphs RETIRED Delivery@80/Swift-v2_Text', 'STEP adopt-paragraphs RETIRED Delivery@81/Swift-v2_Text')
        @(Get-PageWrites | Where-Object { $_ -like 'mcp save_pages *' }) | Should -BeNullOrEmpty
        $s = $global:RecipeStub
        @($s.paragraphs | Where-Object { $_.id -in 80, 81 } | ForEach-Object { "$($_.id):$($_.gridRowId):$($_.active)" }) | Should -Be @('80:0:False', '81:0:False')
        @($s.rows | ForEach-Object { "$($_.id):$($_.active)" }) | Should -Be @('70:True', '71:False')
        $s.pages.Count | Should -Be 2
        $a.exit | Should -Be 0
        $writes = (Get-PageWrites).Count
        $again = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $in; Apply = $true}
        $again.lines | Should -Contain 'STEP adopt-paragraphs UNCHANGED Delivery'
        $again.lines | Should -Contain 'STEP adopt-rows UNCHANGED Delivery'
        (Get-PageWrites).Count | Should -Be $writes
        $again.exit | Should -Be 0
    }
    It 'refuses to retire from an adopted page the input gives no paragraphs, and never adopts a page of another item type' {
        New-SiteStub
        $page = & $script:Page; $page.adopt = $true; $page.Remove('paragraphs')
        $a = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = (Write-Input @{pages = @($page)} 'content.pages'); Apply = $true}
        ($a.lines -match '^OPEN adopt-paragraphs/Delivery: refused: the input names nothing in this set').Count | Should -Be 1
        @($global:RecipeStub.paragraphs | Where-Object { $_.active -eq $false }) | Should -BeNullOrEmpty
        New-SiteStub
        $page = & $script:Page; $page.adopt = $true; $page.itemType = 'Swift-v2_Shop'
        $b = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = (Write-Input @{pages = @($page)} 'content.pages'); Apply = $true}
        $b.lines | Should -Contain 'STEP pages BLOCKED Delivery'
        ($b.lines -match '^OPEN pages/Delivery: .*adopt was asked for, and the object there differs from the input in itemType').Count | Should -Be 1
        Get-PageWrites | Should -BeNullOrEmpty
    }
    It 'links a page from the footer column the input names with a shortcut page, once, and refuses a page that already sits in the column' {
        New-SiteStub
        $warranty = @{menuText = 'Warranty'; urlName = 'warranty'; itemType = 'Swift-v2_Page'; path = '/en-us/warranty'; footer = 'Help and info'}
        $in = Write-Input @{pages = @($warranty)} 'content.pages'
        $a = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $in; Apply = $true}
        $a.lines | Should -Contain 'STEP footer-columns UNCHANGED Help and info'
        $a.lines | Should -Contain 'STEP footer-links CREATED Warranty'
        $a.lines | Should -Contain 'PASS footer-links/Warranty'
        $target = @($global:RecipeStub.pages | Where-Object { $_.menuText -eq 'Warranty' -and $_.parentPageId -eq 0 })[0]
        $link = @($global:RecipeStub.pages | Where-Object { $_.parentPageId -eq 60 -and $_.menuText -eq 'Warranty' })
        $link.Count | Should -Be 1
        $link[0].shortCut | Should -Be "Default.aspx?ID=$($target.id)"
        $link[0].urlName | Should -Be 'warranty-link'
        $link[0].itemType | Should -BeNullOrEmpty
        $again = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $in; Apply = $true}
        $again.lines | Should -Contain 'STEP footer-links UNCHANGED Warranty'
        @($global:RecipeStub.pages | Where-Object { $_.parentPageId -eq 60 }).Count | Should -Be 2
        $page = & $script:Page; $page.adopt = $true; $page.footer = 'Help and info'
        $c = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = (Write-Input @{pages = @($page)} 'content.pages'); Apply = $true}
        ($c.lines -match '^OPEN footer-links/Delivery: .*the page itself already sits in this footer column').Count | Should -Be 1
        @($global:RecipeStub.pages | Where-Object { $_.shortCut -eq 'Default.aspx?ID=50' }) | Should -BeNullOrEmpty
    }
}

Describe 'storefront-links: the links of one region of a rendered storefront page' {
    BeforeAll {
        . (Join-Path $script:Source 'scripts/Recipe.Transport.ps1')
        $script:RecipeTarget = @{baseUrl = 'https://stub.invalid'; insecure = $false}
    }
    It 'returns the footer links only, with their text decoded and tags stripped, and fails a page that does not answer 200' {
        Mock Invoke-WebRequest { [pscustomobject]@{StatusCode = 200; Content = '<header><a href="/en-us/shop">Shop</a></header><main><a href="/x">X</a></main><footer data-x="1"><nav><a class="nav-link" href="/en-us/warranty" id="n1"><span>Warranty &amp; returns</span></a><a href="/en-us/about">About</a></nav></footer>'} }
        $binding = @{surface = 'dwapi'; handler = 'storefront-links'; operation = 'footer'; arguments = @{path = '{item.path}'}}
        $data = Invoke-RecipeStorefrontLinks $binding @{item = @{path = '/en-us/warranty'}}
        @($data.links | ForEach-Object { "$($_.href)|$($_.text)" }) | Should -Be @('/en-us/warranty|Warranty & returns', '/en-us/about|About')
        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Uri -eq 'https://stub.invalid/en-us/warranty' -and -not $Headers.Contains('Authorization') }
        Mock Invoke-WebRequest { [pscustomobject]@{StatusCode = 404; Content = ''} }
        { Invoke-RecipeStorefrontLinks $binding @{item = @{path = '/en-us/warranty'}} } | Should -Throw '*answered HTTP 404*'
        { Invoke-RecipeStorefrontLinks $binding @{item = @{path = 'https://elsewhere.invalid/'}} } | Should -Throw '*reads a site path*'
    }
}

Describe 'Invoke-DwRecipe on content.pages: the home page copy' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        Remove-Item Env:DW_API_TOKEN -ErrorAction SilentlyContinue
        $script:Root = New-RecipeSandbox
        function New-HomeStub {
            # A sample base home page: the hero poster row and a counters row of three stock paragraphs. Its browser title is
            # the website's, not its menu text, as on the sample base.
            New-Stub
            $s = $global:RecipeStub
            foreach ($t in @('get_navigation_structure', 'get_pages_by_area_id')) { $s.tools[$t] = Get-Schema @('areaId') @('areaId') }
            $s.tools.get_pages_by_ids = Get-Schema @('pageIds') @('pageIds')
            $s.pages.Add(@{id = 40; parentPageId = 0; menuText = 'Home'; urlName = 'home'; itemType = 'Swift-v2_Page'; active = $true})
            $s.fields['page40'] = [ordered]@{Title = 'Home'}
            $s.rows.Add(@{id = 41; pageId = 40; sort = 1; definitionId = '1Column'; container = 'Grid'; active = $true})
            $s.rows.Add(@{id = 42; pageId = 40; sort = 9; definitionId = '3Columns'; container = 'Grid'; active = $true})
            $s.paragraphs.Add(@{id = 43; pageId = 40; gridRowId = 41; gridRowColumn = 1; sort = 18; itemType = 'Swift-v2_Poster'; active = $true})
            foreach ($i in 1..3) { $s.paragraphs.Add(@{id = 43 + $i; pageId = 40; gridRowId = 42; gridRowColumn = $i; sort = 10 + $i; itemType = 'Swift-v2_Text'; active = $true}); $s.fields["para$(43 + $i)"] = [ordered]@{Title = "Stock counter $i"} }
            $s.fields['para43'] = [ordered]@{Title = 'Stock hero'; Text = 'Stock text'; Image = '/Files/Images/stock.jpg'}
            $inner = $s.mcp
            $s.mcp = {
                param($Tool, $Arguments)
                $s = $global:RecipeStub
                $ok = @{structuredContent = @{succeeded = 1; failed = 0; errors = @()}}
                $set = { param($row, $m) foreach ($k in $m.Keys) { if ($k -ne 'id') { $row[$k] = $m[$k] } } }
                switch ($Tool) {
                    'fetch_frontend_page_html' { $r = & $inner $Tool $Arguments; if ($r.structuredContent.statusCode -eq 200) { $r.structuredContent.title = 'Example Store' }; return $r }
                    'get_grid_rows_by_page_id' { return @{structuredContent = @{data = @($s.rows | Where-Object { $_.pageId -eq [int]$Arguments.pageId -and $_.active -ne $false })}} }
                    'save_grid_rows' {
                        foreach ($r in $Arguments.gridRows) {
                            if ([int]$r.id -eq 0) { $s.nextId++; $s.rows.Add(@{id = $s.nextId; pageId = [int]$r.pageId; sort = $r.sort; definitionId = $r.definitionId; container = $r.container; active = $true}) }
                            else { & $set @($s.rows | Where-Object { $_.id -eq [int]$r.id })[0] $r }
                        }
                        return $ok
                    }
                    'save_paragraphs' {
                        $creates = @($Arguments.paragraphs | Where-Object { [int]$_.id -eq 0 })
                        foreach ($p in @($Arguments.paragraphs | Where-Object { [int]$_.id -ne 0 })) { & $set @($s.paragraphs | Where-Object { $_.id -eq [int]$p.id })[0] $p }
                        if ($creates.Count) { $null = & $inner $Tool @{paragraphs = $creates}; foreach ($p in $s.paragraphs) { if ($null -eq $p.active) { $p.active = $true } } }
                        return $ok
                    }
                    default { return (& $inner $Tool $Arguments) }
                }
            }.GetNewClosure()
        }
    }
    It 'writes the input hero and intro onto the home page, retires the stock counters, and does not hold the home page to its menu text as browser title' {
        New-HomeStub
        $homePage = @{menuText = 'Home'; urlName = 'home'; itemType = 'Swift-v2_Page'; path = '/en-us/home'; adopt = $true
            rows = @(@{sort = 1; definitionId = '1Column'; container = 'Grid'; itemType = 'Swift-v2_Row'}, @{sort = 2; definitionId = '1Column'; container = 'Grid'; itemType = 'Swift-v2_Row'})
            paragraphs = @(@{row = 1; column = 1; sort = 18; itemType = 'Swift-v2_Poster'; fields = @{Title = 'Built for daily work'; Text = '<p>Hero copy.</p>'}},
                @{row = 2; column = 1; sort = 2; itemType = 'Swift-v2_Text'; fields = @{Title = 'Who we serve'; Text = '<p>Intro copy.</p>'; FirstButton = ''}})}
        $in = Write-Input @{pages = @($homePage)} 'content.pages'
        $a = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $in; Apply = $true}
        $a.lines | Should -Contain 'STEP pages UNCHANGED Home'
        @($a.lines -match '^STEP adopt-') | Should -Be @('STEP adopt-rows RETIRED Home@42/9/3Columns', 'STEP adopt-paragraphs RETIRED Home@44/Swift-v2_Text', 'STEP adopt-paragraphs RETIRED Home@45/Swift-v2_Text', 'STEP adopt-paragraphs RETIRED Home@46/Swift-v2_Text')
        $s = $global:RecipeStub
        # The hero paragraph is reused: the input's copy on it, the stock image it does not name kept.
        $s.fields['para43'].Title | Should -Be 'Built for daily work'
        $s.fields['para43'].Image | Should -Be '/Files/Images/stock.jpg'
        @($s.paragraphs | Where-Object { $_.active -ne $false -and $_.gridRowId -ne 0 }).Count | Should -Be 2
        ($a.lines -match '^(PASS|FAIL|OPEN) probe/page-renders').Count | Should -Be 0
        $a.lines | Should -Contain 'PASS probe/page-path'
        $a.exit | Should -Be 0
    }
}
