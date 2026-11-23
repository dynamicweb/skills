<#
.SYNOPSIS
    READ-ONLY. Hermetic Pester suite for the pure parts of ../Invoke-DwDemoMcp.ps1:
    .mcp.json parsing, server selection, the connection order, mode and argument
    handling, the tool list summary, the result projection and the secret masking.

.DESCRIPTION
    No host, no network, no credential. The script is dot-sourced (which runs no
    mode by design); every .mcp.json here is written to the Pester TestDrive and
    holds a dummy key.

.EXAMPLE
    pwsh -NoProfile -Command "Invoke-Pester ./skills/dw-demo-base/scripts/tests -Output Detailed"
#>
#Requires -Version 7.0

param()

BeforeAll {
    . (Join-Path $PSScriptRoot '../Invoke-DwDemoMcp.ps1')

    function New-McpJson([string]$Dir, [string]$Json) {
        New-Item -ItemType Directory -Force -Path $Dir | Out-Null
        Set-Content -LiteralPath (Join-Path $Dir '.mcp.json') -Value $Json -Encoding utf8NoBOM
        $Dir
    }
    $script:DummyKey = 'dummy-key-for-tests'
    $script:TwoServers = @"
{ "mcpServers": {
    "playwright": { "type": "stdio", "command": "npx" },
    "other":      { "type": "http", "url": "https://other.example/admin/mcp", "headers": { "Authorization": "Bearer other-key" } },
    "dw-demo-acme": { "type": "http", "url": "https://acme.example/admin/mcp/", "headers": { "Authorization": "Bearer $($script:DummyKey)" } }
} }
"@
}

Describe 'Read-DwMcpJson' {
    It 'returns only the servers that carry a url, in file order' {
        $dir = New-McpJson (Join-Path $TestDrive 'a') $script:TwoServers
        $s = Read-DwMcpJson -Path (Join-Path $dir '.mcp.json')
        @($s).Count | Should -Be 2
        $s[0].name | Should -Be 'other'
        $s[1].authorization | Should -Be "Bearer $($script:DummyKey)"
    }

    It 'refuses a missing file, invalid JSON and a file with no mcpServers' {
        { Read-DwMcpJson -Path (Join-Path $TestDrive 'none/.mcp.json') } | Should -Throw '*No .mcp.json*'
        $bad = New-McpJson (Join-Path $TestDrive 'b') '{ not json'
        { Read-DwMcpJson -Path (Join-Path $bad '.mcp.json') } | Should -Throw '*not valid JSON*'
        $empty = New-McpJson (Join-Path $TestDrive 'c') '{ "other": {} }'
        { Read-DwMcpJson -Path (Join-Path $empty '.mcp.json') } | Should -Throw '*no mcpServers*'
    }

    It 'finds the Authorization header whatever its case' {
        $dir = New-McpJson (Join-Path $TestDrive 'd') '{ "mcpServers": { "x": { "url": "https://x.example/admin/mcp", "headers": { "authorization": "Bearer k1" } } } }'
        (Read-DwMcpJson -Path (Join-Path $dir '.mcp.json'))[0].authorization | Should -Be 'Bearer k1'
    }
}

Describe 'Select-DwMcpServer' {
    BeforeAll {
        $script:Servers = @(
            [pscustomobject]@{ name = 'other'; url = 'https://o/admin/mcp'; authorization = 'Bearer o' },
            [pscustomobject]@{ name = 'dw-demo-acme'; url = 'https://a/admin/mcp'; authorization = 'Bearer a' }
        )
    }
    It 'prefers a dw-demo- server over an earlier one' {
        (Select-DwMcpServer -Servers $script:Servers).name | Should -Be 'dw-demo-acme'
    }
    It 'falls back to the first server' {
        (Select-DwMcpServer -Servers @($script:Servers[0])).name | Should -Be 'other'
    }
    It 'picks a named server, and names the choices when it is absent' {
        (Select-DwMcpServer -Servers $script:Servers -Name 'other').name | Should -Be 'other'
        { Select-DwMcpServer -Servers $script:Servers -Name 'nope' } | Should -Throw '*other, dw-demo-acme*'
    }
    It 'refuses an empty list' {
        { Select-DwMcpServer -Servers @() } | Should -Throw '*no server*'
    }
}

Describe 'ConvertTo-DwBaseUrl and ConvertFrom-DwAuthorization' {
    It 'strips /admin/mcp and trailing slashes' {
        ConvertTo-DwBaseUrl 'https://h.example/admin/mcp' | Should -Be 'https://h.example'
        ConvertTo-DwBaseUrl 'https://h.example/Admin/MCP/' | Should -Be 'https://h.example'
        ConvertTo-DwBaseUrl 'https://h.example/' | Should -Be 'https://h.example'
    }
    It 'strips Bearer and reads a ${NAME} reference from the environment' {
        ConvertFrom-DwAuthorization 'Bearer abc' | Should -Be 'abc'
        ConvertFrom-DwAuthorization 'abc' | Should -Be 'abc'
        $env:DW_DEMO_MCP_TEST_KEY = 'from-env'
        try { ConvertFrom-DwAuthorization 'Bearer ${DW_DEMO_MCP_TEST_KEY}' | Should -Be 'from-env' }
        finally { Remove-Item Env:DW_DEMO_MCP_TEST_KEY }
        ConvertFrom-DwAuthorization 'Bearer ${DW_DEMO_MCP_TEST_UNSET}' | Should -BeNullOrEmpty
        ConvertFrom-DwAuthorization '' | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-DwDemoMcpConnection' {
    It 'uses -BaseUrl with the token from the named environment variable first' {
        $dir = New-McpJson (Join-Path $TestDrive 'e') $script:TwoServers
        $env:DW_DEMO_MCP_TEST_TOKEN = 'env-key'
        try {
            $c = Resolve-DwDemoMcpConnection -BaseUrl 'https://explicit.example/' -TokenEnv 'DW_DEMO_MCP_TEST_TOKEN' -SolutionDir $dir
            $c.BaseUrl | Should -Be 'https://explicit.example'
            $c.Token | Should -Be 'env-key'
        }
        finally { Remove-Item Env:DW_DEMO_MCP_TEST_TOKEN }
    }
    It 'refuses -BaseUrl when the environment variable is empty, naming the variable and no value' {
        { Resolve-DwDemoMcpConnection -BaseUrl 'https://x.example' -TokenEnv 'DW_DEMO_MCP_TEST_UNSET' -SolutionDir $TestDrive } |
            Should -Throw '*DW_DEMO_MCP_TEST_UNSET is empty*'
    }
    It 'reads .mcp.json otherwise, and the source names the server, not the key' {
        $dir = New-McpJson (Join-Path $TestDrive 'f') $script:TwoServers
        $c = Resolve-DwDemoMcpConnection -TokenEnv 'DW_MCP_TOKEN' -SolutionDir $dir
        $c.BaseUrl | Should -Be 'https://acme.example'
        $c.Token | Should -Be $script:DummyKey
        $c.Source | Should -Match 'dw-demo-acme'
        $c.Source | Should -Not -Match $script:DummyKey
    }
    It 'refuses a server with no key' {
        $dir = New-McpJson (Join-Path $TestDrive 'g') '{ "mcpServers": { "dw-demo-x": { "url": "https://x.example/admin/mcp" } } }'
        { Resolve-DwDemoMcpConnection -SolutionDir $dir } | Should -Throw "*'dw-demo-x'*no Authorization*"
    }
}

Describe 'Assert-DwDemoMcpMode' {
    It 'accepts exactly one mode' {
        { Assert-DwDemoMcpMode -List } | Should -Not -Throw
        { Assert-DwDemoMcpMode -Schema 'get_areas' } | Should -Not -Throw
        { Assert-DwDemoMcpMode -Call 'get_areas' -Arguments '{}' } | Should -Not -Throw
    }
    It 'refuses none, two, and arguments outside -Call' {
        { Assert-DwDemoMcpMode } | Should -Throw '*exactly one*'
        { Assert-DwDemoMcpMode -List -Call 'x' } | Should -Throw '*exactly one*'
        { Assert-DwDemoMcpMode -Schema 'x' -Arguments '{}' } | Should -Throw '*go with -Call*'
        { Assert-DwDemoMcpMode -Call 'x' -Filter 'y' } | Should -Throw '*goes with -List*'
        { Assert-DwDemoMcpMode -Call 'x' -Arguments '{}' -ArgumentsFile 'a.json' } | Should -Throw '*not both*'
    }
}

Describe 'ConvertFrom-DwToolArguments' {
    It 'parses a JSON object into a hashtable, nested values kept' {
        $h = ConvertFrom-DwToolArguments -Arguments '{"id": 7, "request": {"name": "x", "ids": [1, 2]}}'
        $h | Should -BeOfType [hashtable]
        $h.id | Should -Be 7
        $h.request.name | Should -Be 'x'
        @($h.request.ids).Count | Should -Be 2
    }
    It 'reads a file, and treats empty input as an empty object' {
        $f = Join-Path $TestDrive 'args.json'
        Set-Content -LiteralPath $f -Value '{ "areaId": 1 }' -Encoding utf8NoBOM
        (ConvertFrom-DwToolArguments -ArgumentsFile $f).areaId | Should -Be 1
        (ConvertFrom-DwToolArguments -Arguments '').Count | Should -Be 0
    }
    It 'refuses a non-object, invalid JSON and a missing file' {
        { ConvertFrom-DwToolArguments -Arguments '[1,2]' } | Should -Throw '*JSON object*'
        { ConvertFrom-DwToolArguments -Arguments '{"a":' } | Should -Throw '*not valid JSON*'
        { ConvertFrom-DwToolArguments -ArgumentsFile (Join-Path $TestDrive 'none.json') } | Should -Throw '*No arguments file*'
    }
}

Describe 'Get-DwFirstSentence and Select-DwToolSummary' {
    It 'keeps the first sentence, past an abbreviation' {
        Get-DwFirstSentence 'Returns all groups (e.g. Color, Size). More text.' | Should -Be 'Returns all groups (e.g. Color, Size).'
        Get-DwFirstSentence "First line without stop`nsecond line" | Should -Be 'First line without stop'
        Get-DwFirstSentence '' | Should -Be ''
    }
    It 'filters by name or description and sorts by name' {
        $tools = @(
            [pscustomobject]@{ name = 'save_color_schemes'; description = 'Creates color schemes. Writes.' },
            [pscustomobject]@{ name = 'get_areas'; description = 'Returns websites.' },
            [pscustomobject]@{ name = 'get_variant_groups'; description = 'Returns groups (e.g. Color).' }
        )
        $rows = @(Select-DwToolSummary -Tools $tools -Filter '(?i)color')
        $rows.name | Should -Be @('get_variant_groups', 'save_color_schemes')
        $rows[1].summary | Should -Be 'Creates color schemes.'
        @(Select-DwToolSummary -Tools $tools).Count | Should -Be 3
    }
}

Describe 'ConvertFrom-DwToolResult' {
    It 'returns structuredContent when present' {
        $r = [pscustomobject]@{ structuredContent = [pscustomobject]@{ count = 1 }; content = @() }
        (ConvertFrom-DwToolResult $r).count | Should -Be 1
    }
    It 'parses JSON text content, and keeps plain text as text' {
        $json = [pscustomobject]@{ content = @([pscustomobject]@{ type = 'text'; text = '{"count": 2}' }) }
        (ConvertFrom-DwToolResult $json).count | Should -Be 2
        $plain = [pscustomobject]@{ content = @([pscustomobject]@{ type = 'text'; text = 'done' }) }
        ConvertFrom-DwToolResult $plain | Should -Be 'done'
    }
    It 'throws the tool''s own message on isError' {
        $r = [pscustomobject]@{ isError = $true; content = @([pscustomobject]@{ type = 'text'; text = 'Page 9 not found' }) }
        { ConvertFrom-DwToolResult $r } | Should -Throw 'Page 9 not found'
        { ConvertFrom-DwToolResult ([pscustomobject]@{ isError = $true }) } | Should -Throw '*no message*'
    }
}

Describe 'Hide-DwSecret' {
    It 'replaces every occurrence of the token' {
        Hide-DwSecret "401 for Bearer $($script:DummyKey) at $($script:DummyKey)" $script:DummyKey |
            Should -Be '401 for Bearer **** at ****'
        Hide-DwSecret 'no token here' $null | Should -Be 'no token here'
    }
}

Describe 'The token stays off every argument list' {
    It 'has no parameter that takes a token value' {
        $params = (Get-Command (Join-Path $PSScriptRoot '../Invoke-DwDemoMcp.ps1')).Parameters.Keys
        $params | Should -Not -Contain 'Token'
        $params | Should -Not -Contain 'McpToken'
        $params | Should -Contain 'TokenEnv'
    }
}
