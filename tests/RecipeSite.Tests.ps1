# Hermetic controls for the site a recipe run targets (dw-demo-ledger Recipe.Site.ps1, and its use in
# Invoke-DwRecipeSet.ps1). Temporary demo folders hold fake .mcp.json, demo-host.json and keys files with
# fake tokens; the set runs beside a stub Invoke-DwRecipe.ps1 and a stub Dw.Api.psm1 that answers the
# site reads, so no host is reached. What is under test: the resolve order (parameter and environment win,
# then .mcp.json, then demo-host.json and its keys file), the clear stops, no token in any line or report,
# and the {build.*} values read from a site with one candidate and refused on a site with several.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Source = Join-Path (Get-RepoRoot) 'skills/dw-demo-ledger'
    . (Join-Path $script:Source 'scripts/Ledger.Core.ps1')
    . (Join-Path $script:Source 'scripts/Recipe.Core.ps1')
    . (Join-Path $script:Source 'scripts/Recipe.Site.ps1')
    $script:McpKey = 'fake-mcp-key-7f3a9c1e5b2d'
    $script:AdminKey = 'fake-admin-key-4e8b2a6c9d1f'
    $script:EnvNames = @('DW_BASE_URL', 'DW_MCP_TOKEN', 'DW_API_TOKEN')

    function New-SiteFolder {
        # A demo folder: .mcp.json with the given servers, and optionally demo-host.json beside a keys file.
        param([hashtable]$Servers = @{site = @{type = 'http'; url = 'https://demo.invalid/admin/mcp'; headers = @{Authorization = "Bearer $script:McpKey"}}}, [hashtable]$HostFacts, [hashtable]$Keys)
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Force $dir
        if ($Servers) { @{mcpServers = $Servers} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $dir '.mcp.json') -Encoding utf8 }
        if ($HostFacts) { $HostFacts | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $dir 'demo-host.json') -Encoding utf8 }
        if ($Keys) { $null = New-Item -ItemType Directory -Force (Join-Path $dir 'keys'); $Keys | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'keys/result.json') -Encoding utf8 }
        return $dir
    }
    $script:Facts = @{url = 'https://demo.invalid'; keys = @{resultFile = 'keys/result.json'; adminKeyField = 'adminKey'; mcpKeyField = 'mcpKey'}}
}

Describe 'Resolve-RecipeConnection' {
    BeforeEach {
        $script:Saved = @{}; foreach ($n in $script:EnvNames) { $script:Saved[$n] = [Environment]::GetEnvironmentVariable($n); [Environment]::SetEnvironmentVariable($n, $null) }
    }
    AfterEach { foreach ($n in $script:EnvNames) { [Environment]::SetEnvironmentVariable($n, $script:Saved[$n]) } }

    It 'lets the environment and the parameters win over the folder, and says nothing about them' {
        $dir = New-SiteFolder -HostFacts $script:Facts -Keys @{adminKey = $script:AdminKey}
        $env:DW_BASE_URL = 'https://env.invalid'; $env:DW_MCP_TOKEN = 'env-mcp-0000'; $env:DW_API_TOKEN = 'env-api-0000'
        $c = Resolve-RecipeConnection -SiteFolder $dir
        $c.baseUrl | Should -Be 'https://env.invalid'; $c.mcpToken | Should -Be 'env-mcp-0000'; $c.apiToken | Should -Be 'env-api-0000'
        $c.notes.Count | Should -Be 0
        $env:DW_API_TOKEN = $null
        $c = Resolve-RecipeConnection -SiteFolder $dir -McpToken 'param-mcp-0000'
        $c.mcpToken | Should -Be 'param-mcp-0000'
        $c.apiToken | Should -Be $script:AdminKey
        @($c.notes) | Should -Be @('NOTE connection: Management API token from demo-host.json keys (result.json)')
    }
    It 'reads the base URL and the MCP key from .mcp.json, and the Management API key from the demo-host.json keys file' {
        $dir = New-SiteFolder -HostFacts $script:Facts -Keys @{adminKey = $script:AdminKey; mcpKey = 'unused-mcp-key-0000'}
        $c = Resolve-RecipeConnection -SiteFolder $dir
        $c.baseUrl | Should -Be 'https://demo.invalid'
        $c.mcpToken | Should -Be $script:McpKey
        $c.apiToken | Should -Be $script:AdminKey
        @($c.notes) | Should -Be @('NOTE connection: base URL from .mcp.json (server site)', 'NOTE connection: MCP token from .mcp.json', 'NOTE connection: Management API token from demo-host.json keys (result.json)')
        ($c.notes -join "`n") | Should -Not -Match 'fake-'
        @(Get-RecipeConnectionGaps $c).Count | Should -Be 0
    }
    It 'reads the current directory when no -SiteFolder is given' {
        $dir = New-SiteFolder
        Push-Location $dir
        try { (Resolve-RecipeConnection).mcpToken | Should -Be $script:McpKey } finally { Pop-Location }
    }
    It 'takes the base URL and the MCP key from demo-host.json when .mcp.json carries a placeholder' {
        $dir = New-SiteFolder -Servers $null -HostFacts $script:Facts -Keys @{adminKey = $script:AdminKey; mcpKey = 'fake-host-mcp-0000'}
        $c = Resolve-RecipeConnection -SiteFolder $dir
        $c.baseUrl | Should -Be 'https://demo.invalid'
        $c.mcpToken | Should -Be 'fake-host-mcp-0000'
        $c.notes | Should -Contain 'NOTE connection: base URL from demo-host.json'
        $dir = New-SiteFolder -Servers @{site = @{url = 'https://demo.invalid/admin/mcp'; headers = @{Authorization = 'Bearer <MCP_API_KEY>'}}}
        $c = Resolve-RecipeConnection -SiteFolder $dir
        $c.mcpToken | Should -BeNullOrEmpty
        $c.notes | Should -Contain 'NOTE connection: .mcp.json holds a placeholder, not an MCP key'
    }
    It 'ignores servers that are not a site, and stops on several sites unless demo-host.json names one' {
        $servers = @{
            other = @{url = 'https://tools.invalid/mcp'; headers = @{Authorization = 'Bearer fake-other-0000'}}
            first = @{url = 'https://one.invalid/admin/mcp'; headers = @{Authorization = 'Bearer fake-one-0000'}}
            second = @{url = 'https://two.invalid/Admin/MCP/'; headers = @{Authorization = 'Bearer fake-two-0000'}}
        }
        $dir = New-SiteFolder -Servers $servers
        { Resolve-RecipeConnection -SiteFolder $dir } | Should -Throw -ExpectedMessage '*lists 2 Dynamicweb servers (*first*second*); set DW_BASE_URL and DW_MCP_TOKEN, or name the server in demo-host.json mcp.name.'
        $dir = New-SiteFolder -Servers $servers -HostFacts @{mcp = @{name = 'second'}}
        $c = Resolve-RecipeConnection -SiteFolder $dir
        $c.baseUrl | Should -Be 'https://two.invalid'; $c.mcpToken | Should -Be 'fake-two-0000'
        $dir = New-SiteFolder -Servers $servers -HostFacts @{mcp = @{url = 'https://one.invalid/admin/mcp'}}
        (Resolve-RecipeConnection -SiteFolder $dir).mcpToken | Should -Be 'fake-one-0000'
    }
    It 'resolves nothing in an empty folder and names both ways to supply each credential' {
        $dir = New-SiteFolder -Servers $null
        $c = Resolve-RecipeConnection -SiteFolder $dir
        $c.baseUrl | Should -BeNullOrEmpty; $c.mcpToken | Should -BeNullOrEmpty; $c.apiToken | Should -BeNullOrEmpty
        $gaps = @(Get-RecipeConnectionGaps $c)
        $gaps[0] | Should -Match 'DW_MCP_TOKEN, or run from the folder that holds the site''s \.mcp\.json \(or pass -SiteFolder\)'
        $gaps[1] | Should -Match 'DW_API_TOKEN, or run from the site folder whose demo-host\.json names the keys file'
    }
    It 'names a keys file that is missing or a file that is not JSON, never its content' {
        $dir = New-SiteFolder -HostFacts $script:Facts
        { Resolve-RecipeConnection -SiteFolder $dir } | Should -Throw -ExpectedMessage '*keys.resultFile names result.json, which does not exist.'
        $dir = New-SiteFolder -Servers $null
        Set-Content -LiteralPath (Join-Path $dir '.mcp.json') -Value "{ not json $script:McpKey"
        { Resolve-RecipeConnection -SiteFolder $dir } | Should -Throw -ExpectedMessage 'Runner input: .mcp.json in the site folder is not JSON.'
    }
}

Describe 'Resolve-RecipeBuildDefaults' {
    It 'needs only the members a recipe reads without a default and the build lacks' {
        $docs = @(@{steps = @(@{key = '{build.areaId}'; args = @{lang = '{build.defaultLanguage|null}'; shop = '{text:build.pimShop}'}})})
        Get-RecipeBuildNeeds $docs @{} | Should -Be @('areaId', 'pimShop')
        Get-RecipeBuildNeeds $docs @{areaId = 3} | Should -Be @('pimShop')
    }
    It 'uses the only website, default language and DataStructure shop, and names each value' {
        $site = @{
            get_areas = @{count = 2; data = @(@{id = 3; masterAreaId = 0}, @{id = 4; masterAreaId = 3})}
            get_languages = @{count = 2; data = @(@{languageId = 'LANG1'; isDefault = $true}, @{languageId = 'LANG2'; isDefault = $false})}
            get_shops = @{count = 2; data = @(@{id = 'SHOP1'; usageType = 'Shop'}, @{id = 'SHOP2'; usageType = 'DataStructure'})}
        }
        $r = Resolve-RecipeBuildDefaults @('areaId', 'defaultLanguage', 'pimShop') { param($tool) $site[$tool] }
        $r.values.areaId | Should -Be 3
        $r.values.areaId | Should -BeOfType int
        $r.values.defaultLanguage | Should -Be 'LANG1'
        $r.values.pimShop | Should -Be 'SHOP2'
        $r.notes[0] | Should -Be "NOTE build.areaId: 3, the site's only website (get_areas); add build.areaId to the input to choose another"
    }
    It 'stops once, before any recipe, listing the candidates and the member to add' {
        $site = @{get_areas = @{data = @(@{id = 1}, @{id = 7; masterAreaId = $null})}; get_shops = @{data = @(@{id = 'SHOP1'; usageType = 1})}}
        { Resolve-RecipeBuildDefaults @('areaId', 'pimShop') { param($tool) $site[$tool] } } | Should -Throw -ExpectedMessage "Runner input: the data file's build section lacks build.areaId (the site has 2 candidates from get_areas: 1, 7); build.pimShop (get_shops shows no DataStructure shop)*Add each under `"build`"*"
        { Resolve-RecipeBuildDefaults @('defaultLanguage') $null } | Should -Throw -ExpectedMessage '*build.defaultLanguage (no MCP connection to read get_languages)*'
    }
}

Describe 'Invoke-DwRecipeSet site resolution' {
    BeforeAll {
        function New-SetSandbox {
            # The set and its helpers beside a stub runner that records what each recipe run was given, and a stub transport.
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $skill = Join-Path $root 'skills/dw-demo-ledger'
            $null = New-Item -ItemType Directory -Force (Join-Path $skill 'scripts'), (Join-Path $skill 'assets'), (Join-Path $root 'skills/dw-data-access/scripts')
            foreach ($f in @('Invoke-DwRecipeSet.ps1', 'Ledger.Core.ps1', 'Recipe.Core.ps1', 'Recipe.Site.ps1')) { Copy-Item (Join-Path $script:Source "scripts/$f") (Join-Path $skill 'scripts') }
            foreach ($f in @('recipe.schema.json', 'recipe-input.schema.json', 'recipe-input.example.json')) { Copy-Item (Join-Path $script:Source "assets/$f") (Join-Path $skill 'assets') }
            Copy-Item (Join-Path $script:Source 'assets/recipes') (Join-Path $skill 'assets') -Recurse
            Set-Content -LiteralPath (Join-Path $skill 'scripts/Invoke-DwRecipe.ps1') -Encoding utf8 -Value @'
[CmdletBinding(SupportsShouldProcess)]
param([string]$Recipe, [string]$InputPath, [switch]$Apply, [string]$BaseUrl, [string]$ApiToken, [string]$McpToken, [string]$SiteFolder, [hashtable]$BuildValues, [switch]$McpOnly,
    [string[]]$Surfaces, [switch]$AllowSql, [string]$SqlServer, [string]$Database, [string]$LedgerBuildFile, [string]$Manifest, [string]$SolutionPath,
    [string]$Debts = 'Run', [string[]]$DebtNames, [switch]$SkipVerify, [string]$ReportPath, [switch]$AllowSelfSignedCertificate)
$global:SiteStub.calls.Add(@{recipe = $Recipe; baseUrl = $BaseUrl; apiToken = $ApiToken; mcpToken = $McpToken; build = $BuildValues})
"PASS probe/p"
"${Recipe}: 1 of 1 checks passed"
[IO.File]::WriteAllText($ReportPath, (@{schema = 1; recipe = $Recipe; steps = @(); checks = @(@{name = 'probe/p'; result = 'PASS'}); changed = $false; debtsOwed = @(); blocked = 0; passed = 1; total = 1} | ConvertTo-Json -Depth 5))
exit 0
'@
            Set-Content -LiteralPath (Join-Path $root 'skills/dw-data-access/scripts/Dw.Api.psm1') -Encoding utf8 -Value @'
function Connect-Dw { param($BaseUrl, $ApiToken, $McpToken, $SqlConnection, $SolutionPath, [switch]$AllowSelfSignedCertificate) $global:SiteStub.connected = $McpToken; @{BaseUrl = $BaseUrl} }
function Invoke-DwMcp { param($Tool, [hashtable]$Arguments, [switch]$Raw, $TimeoutSec) $global:SiteStub.reads.Add($Tool); @{structuredContent = $global:SiteStub.site[$Tool]} }
Export-ModuleMember -Function *
'@
            return $root
        }
        function Write-SiteInput([hashtable]$Extra = @{}, [string[]]$Drop = @()) {
            $data = Get-Content -LiteralPath (Join-Path $script:Source 'assets/recipe-input.example.json') -Raw | ConvertFrom-Json -AsHashtable
            foreach ($k in $Drop) { $data.Remove($k) }
            foreach ($k in $Extra.Keys) { $data[$k] = $Extra[$k] }
            $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json')
            $data | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding utf8
            return $path
        }
        function Invoke-SiteSet([string]$Root, [hashtable]$Arguments) {
            $out = & (Join-Path $Root 'skills/dw-demo-ledger/scripts/Invoke-DwRecipeSet.ps1') @Arguments *>&1 | ForEach-Object { "$_" }
            return @{lines = @($out); text = (@($out) -join "`n"); exit = $LASTEXITCODE}
        }
    }
    BeforeEach {
        $script:Saved = @{}; foreach ($n in $script:EnvNames) { $script:Saved[$n] = [Environment]::GetEnvironmentVariable($n); [Environment]::SetEnvironmentVariable($n, $null) }
        $global:SiteStub = @{calls = [Collections.Generic.List[object]]::new(); reads = [Collections.Generic.List[string]]::new(); connected = $null
            site = @{get_areas = @{count = 1; data = @(@{id = 5; masterAreaId = 0})}}}
        $script:Root = New-SetSandbox
    }
    AfterEach { foreach ($n in $script:EnvNames) { [Environment]::SetEnvironmentVariable($n, $script:Saved[$n]) } }
    AfterAll { Remove-Variable -Name SiteStub -Scope Global -ErrorAction SilentlyContinue }

    It 'runs from a demo folder with no environment: every recipe gets the connection, and no token is printed or reported' {
        $dir = New-SiteFolder -HostFacts $script:Facts -Keys @{adminKey = $script:AdminKey}
        $report = Join-Path $TestDrive 'set-report.json'
        Push-Location $dir
        try { $r = Invoke-SiteSet $script:Root @{InputPath = (Write-SiteInput); Only = @('users.accounts', 'content.pages'); ReportPath = $report} } finally { Pop-Location }
        $r.exit | Should -Be 0
        @($r.lines -like 'NOTE connection:*') | Should -Be @('NOTE connection: base URL from .mcp.json (server site)', 'NOTE connection: MCP token from .mcp.json', 'NOTE connection: Management API token from demo-host.json keys (result.json)')
        $global:SiteStub.calls.Count | Should -Be 2
        foreach ($c in $global:SiteStub.calls) { $c.baseUrl | Should -Be 'https://demo.invalid'; $c.mcpToken | Should -Be $script:McpKey; $c.apiToken | Should -Be $script:AdminKey }
        $r.text | Should -Not -Match 'fake-'
        (Get-Content -LiteralPath $report -Raw) | Should -Not -Match 'fake-'
        # The example input carries build.areaId: nothing is read from the site.
        $global:SiteStub.reads.Count | Should -Be 0
    }
    It 'says how to supply what it cannot find, once for the set' {
        $dir = New-SiteFolder -Servers $null
        $r = Invoke-SiteSet $script:Root @{InputPath = (Write-SiteInput); Only = @('users.accounts'); SiteFolder = $dir}
        @($r.lines -like 'NOTE connection: no MCP token: set DW_MCP_TOKEN, or run from the folder that holds the site''s .mcp.json*').Count | Should -Be 1
        @($r.lines -like 'NOTE connection: no Management API token: set DW_API_TOKEN*').Count | Should -Be 1
    }
    It 'reads build.areaId from a single-website site once and hands it to every recipe' {
        $dir = New-SiteFolder
        $r = Invoke-SiteSet $script:Root @{InputPath = (Write-SiteInput -Drop @('build')); Only = @('content.pages', 'users.accounts'); SiteFolder = $dir}
        $r.exit | Should -Be 0
        @($global:SiteStub.reads) | Should -Be @('get_areas')
        $r.lines | Should -Contain "NOTE build.areaId: 5, the site's only website (get_areas); add build.areaId to the input to choose another"
        foreach ($c in $global:SiteStub.calls) { $c.build.areaId | Should -Be 5 }
        $global:SiteStub.connected | Should -Be $script:McpKey
    }
    It 'stops before any recipe on a site with several websites, listing them and the member to add' {
        $global:SiteStub.site.get_areas = @{count = 2; data = @(@{id = 1}, @{id = 2})}
        $dir = New-SiteFolder
        $r = Invoke-SiteSet $script:Root @{InputPath = (Write-SiteInput -Drop @('build')); SiteFolder = $dir}
        $r.exit | Should -Be 1
        ($r.lines -match '^FAIL recipe set: Runner input: the data file''s build section lacks build\.areaId \(the site has 2 candidates from get_areas: 1, 2\)').Count | Should -Be 1
        $global:SiteStub.calls.Count | Should -Be 0
    }
    It 'stops before any recipe when build is missing and MCP is not connected to read it' {
        $dir = New-SiteFolder -Servers $null
        $r = Invoke-SiteSet $script:Root @{InputPath = (Write-SiteInput -Drop @('build')); SiteFolder = $dir; ApiToken = 'fake-api-param-0000'}
        ($r.lines -match 'build\.areaId \(no MCP connection to read get_areas\)').Count | Should -Be 1
        $global:SiteStub.calls.Count | Should -Be 0
        $r.text | Should -Not -Match 'fake-'
    }
}
