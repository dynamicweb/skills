# Hermetic controls for the recipe runner (dw-demo-ledger Invoke-DwRecipe.ps1, Find-DwRecipe.ps1 and
# the Recipe.*.ps1 helpers). The runner and its assets are copied into TestDrive beside a recording
# stub of Dw.Api.psm1 and stub child scripts, so no host, database or network is reached.

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
        $child = @'
Add-Content -LiteralPath $env:RECIPE_TEST_CHILDLOG -Value ("{0} {1}" -f (Split-Path -Leaf $PSCommandPath), ($args -join ' '))
exit 0
'@
        foreach ($path in @('skills/dw-data-access/scripts/Build-DwProductIndex.ps1', 'skills/dw-data-access/scripts/Invoke-DwAssortmentBuild.ps1', 'skills/dw-demo-base/scripts/Restart-DwHost.ps1')) {
            Set-Content -LiteralPath (Join-Path $root $path) -Value $child -Encoding utf8
        }
        return $root
    }
    function Get-Schema([string[]]$Properties, [string[]]$Required = @()) {
        $p = @{}; foreach ($n in $Properties) { $p[$n] = @{type = 'string'} }
        return @{type = 'object'; properties = $p; required = $Required}
    }
    function New-Stub {
        # A target: MCP tools with input schemas, pages, rows and users held in memory, a fake Management API.
        param([hashtable]$Pages = @{}, [hashtable]$Rows = @{}, [object[]]$Groups = @(), [object[]]$Users = @())
        $global:RecipeStub = @{
            log = [Collections.Generic.List[string]]::new(); pages = $Pages; rows = $Rows; groups = $Groups; users = [Collections.Generic.List[object]]::new(); nextId = 100
            tools = @{
                get_pages_by_parent_id = Get-Schema @('parentId', 'areaId') @('parentId', 'areaId')
                save_pages = Get-Schema @('pages') @('pages')
                set_page_item_fields = Get-Schema @('pageId', 'fields') @('pageId', 'fields')
                get_grid_rows_by_page_id = Get-Schema @('pageId') @('pageId')
                get_paragraphs_by_page_id = Get-Schema @('pageId') @('pageId')
                get_user_groups = Get-Schema @()
                get_users_by_usernames = Get-Schema @('userNames') @('userNames')
                update_users = Get-Schema @('users') @('users')
                delete_pages = Get-Schema @('ids')
            }
            api = { param($Command, $Body) if ($Command -like 'IndexBuildersByRepositoryAndIndexName*') { return [pscustomobject]@{model = @{data = @(@{name = 'Users'})}} }; [pscustomobject]@{status = 'ok'} }
        }
        foreach ($u in $Users) { $global:RecipeStub.users.Add($u) }
        $global:RecipeStub.mcp = {
            param($Tool, $Arguments)
            $s = $global:RecipeStub
            $data = switch ($Tool) {
                'get_pages_by_parent_id' { , @($s.pages.Values | Where-Object { $_.parentId -eq [int]$Arguments.parentId }) }
                'save_pages' {
                    foreach ($p in $Arguments.pages) {
                        if ([int]$p.id -eq 0) { $s.nextId++; $s.pages[$s.nextId] = @{id = $s.nextId; parentId = [int]$p.parentPageId; menuText = $p.menuText} }
                    }
                    # The create path answers the input model with id 0, as the platform does.
                    return @{structuredContent = @{succeeded = 1; failed = 0; data = @(@{id = 0})}}
                }
                'set_page_item_fields' { return @{structuredContent = @{succeeded = 1; failed = 0}} }
                'get_grid_rows_by_page_id' { , @($s.rows.Values | Where-Object { $_.pageId -eq [int]$Arguments.pageId }) }
                'get_paragraphs_by_page_id' { , @() }
                'get_user_groups' { , @($s.groups) }
                'get_users_by_usernames' { , @($s.users | Where-Object { $_.userName -in $Arguments.userNames }) }
                'update_users' {
                    foreach ($u in $Arguments.users) { foreach ($row in $s.users) { if ($row.id -eq $u.id) { $row.customerNumber = $u.customerNumber } } }
                    return @{structuredContent = @{succeeded = 1; failed = 0}}
                }
                default { return @{isError = $true; content = @(@{text = 'unknown tool'})} }
            }
            return @{structuredContent = @{data = $data}}
        }
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
        $out = & (Join-Path $Root 'skills/dw-demo-ledger/scripts/Invoke-DwRecipe.ps1') @Arguments *>&1 | ForEach-Object { "$_" }
        return @{lines = @($out); exit = $LASTEXITCODE}
    }
    $script:PagesSection = @{pages = @(
        @{menuText = 'About us'; urlName = 'about-us'; itemType = 'Swift-v2_Page'; public = $true; rows = @(@{sort = 1; definitionId = '1Column'; container = 'Grid'; itemType = 'Swift-v2_Row'})},
        @{menuText = 'Our history'; urlName = 'our-history'; itemType = 'Swift-v2_Page'; parent = 'About us'}
    )}
}

AfterAll {
    Remove-Variable -Name RecipeStub -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:RECIPE_TEST_CHILDLOG, Env:DW_MCP_TOKEN, Env:DW_API_TOKEN, Env:DW_RECIPE_SECRETS -ErrorAction SilentlyContinue
}

Describe 'Recipe engine: paths, tokens and matching' {
    It 'walks a nested forEach and hands each item its enclosing item as parent' {
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
    It 'reads a secret by reference from DW_RECIPE_SECRETS and refuses a missing one by key, not value' {
        $secrets = Read-RecipeSecrets '{"buyer":"s3cret-value"}'
        $ctx = @{item = @{passwordRef = 'buyer'}; secrets = $secrets; results = @{}}
        Resolve-RecipeToken 'secret.item.passwordRef' $ctx | Should -Be 's3cret-value'
        $ctx.item.passwordRef = 'nobody'
        { Resolve-RecipeToken 'secret.item.passwordRef' $ctx } | Should -Throw "*'nobody'*"
        { Read-RecipeSecrets '["x"]' } | Should -Throw '*JSON object*'
    }
    It 'compares typed values, and an absent value as empty text' {
        Test-RecipeEqual 5 '5' | Should -BeTrue
        Test-RecipeEqual 5 5.0 | Should -BeTrue
        Test-RecipeEqual 'Grid' 'grid' | Should -BeFalse
        Test-RecipeEqual $null '' | Should -BeTrue
        Test-RecipeEqual $null 0 | Should -BeFalse
    }
    It 'fails loudly on a field the response does not carry, rather than reading it as a mismatch' {
        { Get-RecipeDifferences @{id = 1} @{customerNumber = 'C1'} 'get_user_groups' } | Should -Throw '*carries no field*'
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
}

Describe 'Invoke-DwRecipe on content.pages' {
    BeforeEach {
        $env:DW_MCP_TOKEN = 'stub-mcp-token-0000'
        Remove-Item Env:DW_API_TOKEN -ErrorAction SilentlyContinue
        $script:Root = New-RecipeSandbox
        $script:InputFile = Write-Input $script:PagesSection 'content.pages'
    }

    It 'reports every object UNCHANGED and exits 0 on a host a layer already delivered (build path A)' {
        New-Stub -Pages @{10 = @{id = 10; parentId = 0; menuText = 'About us'}; 11 = @{id = 11; parentId = 10; menuText = 'Our history'}} -Rows @{5 = @{id = 5; pageId = 10; sort = 1; definitionId = '1Column'; container = 'Grid'}}
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile}
        $r.lines | Should -Contain 'STEP pages UNCHANGED About us'
        $r.lines | Should -Contain 'STEP pages UNCHANGED Our history'
        $r.lines | Should -Contain 'STEP rows UNCHANGED About us/1'
        $r.lines | Should -Contain 'PASS probe/page-unique'
        $r.lines | Should -Contain 'PASS probe/row-container'
        ($r.lines -match '^NOTE content\.pages: unproven').Count | Should -Be 1
        ($r.lines -match '^NOTE probe/page-renders: planned').Count | Should -Be 1
        ($r.lines -match '^NOTE ledger/content\.pages\.exist: run with the ledger').Count | Should -Be 1
        $r.lines[-1] | Should -Be 'content.pages: 5 of 5 checks passed'
        $r.exit | Should -Be 0
        @($global:RecipeStub.log | Where-Object { $_ -match '^mcp (save_pages|set_page_item_fields)' }).Count | Should -Be 0
    }

    It 'writes nothing without -Apply on an empty host and reports what apply would do' {
        New-Stub
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile}
        $r.lines | Should -Contain 'STEP pages WOULD-CREATE About us'
        ($r.lines -match '^FAIL pages/About us: absent; apply would create it').Count | Should -Be 1
        # The child page's parent has no id yet, so it cannot even be looked for: BLOCKED, never skipped.
        $r.lines | Should -Contain 'STEP pages BLOCKED Our history'
        $r.exit | Should -Be 1
        @($global:RecipeStub.log | Where-Object { $_ -match '^mcp (save_|set_)' }).Count | Should -Be 0
    }

    It 'creates, reads the new id back by natural key (the create answers id 0) and passes it to the child' {
        New-Stub
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true}
        $r.lines | Should -Contain 'STEP pages CREATED About us'
        $r.lines | Should -Contain 'PASS pages/About us'
        $r.lines | Should -Contain 'STEP pages CREATED Our history'
        $creates = @($global:RecipeStub.log | Where-Object { $_ -match '^mcp save_pages .*"id":0' })
        $creates.Count | Should -Be 2
        $creates[1] | Should -Match '"parentPageId":101'
        $r.lines | Should -Contain 'STEP page-title CREATED About us'
        $r.lines | Should -Contain 'STEP page-slug CREATED About us'
        # Rows have only planned create bindings: the item is BLOCKED with the reason, and the run cannot pass.
        $r.lines | Should -Contain 'STEP rows BLOCKED About us/1'
        ($r.lines -match '^OPEN rows/About us/1: absent; no eligible create binding: .*planned').Count | Should -Be 1
        $r.exit | Should -Be 1
    }

    It 'treats -WhatIf as verify-only even with -Apply' {
        New-Stub
        $r = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; Apply = $true; WhatIf = $true}
        @($global:RecipeStub.log | Where-Object { $_ -match '^mcp save_pages' }).Count | Should -Be 0
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
        New-Stub -Pages @{10 = @{id = 10; parentId = 0; menuText = 'About us'}; 12 = @{id = 12; parentId = 0; menuText = 'About us'}}
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
        New-Stub -Pages @{10 = @{id = 10; parentId = 0; menuText = 'About us'}; 11 = @{id = 11; parentId = 10; menuText = 'Our history'}} -Rows @{5 = @{id = 5; pageId = 10; sort = 1; definitionId = '1Column'; container = 'Grid'}}
        $report = Join-Path $TestDrive 'report.json'
        $null = Invoke-Runner $script:Root @{Recipe = 'content.pages'; InputPath = $script:InputFile; ReportPath = $report}
        $json = Get-Content -LiteralPath $report -Raw
        $data = $json | ConvertFrom-Json -AsHashtable
        $data.result | Should -Be 'PASS'
        $data.mode | Should -Be 'verify'
        $data.plannedProbes | Should -Contain 'page-renders'
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
        $script:Root = New-RecipeSandbox
        $script:InputFile = Write-Input @{groups = @(@{name = 'Example Trading'; kind = 'account'; customerNumber = 'C-1001'; users = @(@{userName = 'buyer@example.invalid'; passwordRef = 'buyer'})})} 'users.accounts'
    }

    It 'updates a differing user, reads it back, then pays the debts it can and states the ones it owes' {
        New-Stub -Groups @(@{id = 50; name = 'Example Trading'; customerNumber = 'C-1001'}) -Users @(@{id = 60; userName = 'buyer@example.invalid'; customerNumber = 'OLD'})
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true}
        $r.lines | Should -Contain 'STEP groups UNCHANGED Example Trading'
        $r.lines | Should -Contain 'STEP users UPDATED buyer@example.invalid'
        $r.lines | Should -Contain 'PASS users/buyer@example.invalid'
        @($global:RecipeStub.log | Where-Object { $_ -match '^mcp update_users .*"customerNumber":"C-1001"' }).Count | Should -Be 1
        # The password is set only on create: an existing login is never re-passworded.
        @($global:RecipeStub.log | Where-Object { $_ -match 'UserSetPassword' }).Count | Should -Be 0
        # Group type and membership are read through local SQL only, which this run does not enable.
        $r.lines | Should -Contain 'STEP account-type BLOCKED Example Trading'
        ($r.lines -match '^OPEN account-type/Example Trading: no eligible find binding: .*SQL is not enabled').Count | Should -Be 1
        $r.lines | Should -Contain 'PASS debt/flush:Dynamicweb.Security.UserManagement.UserService'
        $r.lines | Should -Contain 'PASS debt/index:Users/Users.index'
        ($r.lines -match '^OPEN debt/recycle: owed: recycle the host').Count | Should -Be 1
        $global:RecipeStub.log | Should -Contain 'flush Dynamicweb.Security.UserManagement.UserService'
        (Get-Content -LiteralPath $script:ChildLog) -join "`n" | Should -Match 'Build-DwProductIndex\.ps1 -Repository Secondary users -IndexName Users\.index -BuildName Users -SkipCacheFlush'
        $r.lines | Should -Contain 'PASS probe/users-carry-account-number'
        ($r.lines -match '^NOTE probe/grant-direction: no input item asks for it').Count | Should -Be 1
        ($r.lines -match '^OPEN probe/persona-sign-in: .*DW_PERSONA_CREDENTIALS').Count | Should -Be 1
        $r.exit | Should -Be 1
        ($r.lines -join "`n") | Should -Not -Match 'stub-api-token|stub-mcp-token'
    }

    It 'runs no debt when nothing changed' {
        New-Stub -Groups @(@{id = 50; name = 'Example Trading'; customerNumber = 'C-1001'}) -Users @(@{id = 60; userName = 'buyer@example.invalid'; customerNumber = 'C-1001'})
        $r = Invoke-Runner $script:Root @{Recipe = 'users.accounts'; InputPath = $script:InputFile; Apply = $true}
        $r.lines | Should -Contain 'STEP users UNCHANGED buyer@example.invalid'
        ($r.lines -match '^NOTE users\.accounts: debts not run \(nothing changed\)').Count | Should -Be 1
        @($global:RecipeStub.log | Where-Object { $_ -match '^flush' }).Count | Should -Be 0
    }

    It 'reports a write the Management API refuses with HTTP 200 as FAIL, not as success' {
        New-Stub -Groups @(@{id = 50; name = 'Example Trading'; customerNumber = 'C-1001'}) -Users @(@{id = 60; userName = 'buyer@example.invalid'; customerNumber = 'C-1001'})
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

Describe 'Find-DwRecipe' {
    BeforeAll { $script:Find = Join-Path $script:Source 'scripts/Find-DwRecipe.ps1' }
    It 'lists the recipes that deliver a function, with modes and proven state' {
        $out = & $script:Find -Function users.user-groups
        $LASTEXITCODE | Should -Be 0
        $out[0] | Should -Match '^users\.accounts'
        ($out -match '^\s+proven:\s+unproven$').Count | Should -Be 1
        ($out -match '^\s+mcpOnly:\s+no - ').Count | Should -Be 1
    }
    It 'says plainly when no recipe delivers a function, and exits 0' {
        $out = & $script:Find -Function search.user-index
        $LASTEXITCODE | Should -Be 0
        $out | Should -Be 'no recipe for function search.user-index'
    }
}
