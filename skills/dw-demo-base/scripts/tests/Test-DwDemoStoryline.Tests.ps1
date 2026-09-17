<#
.SYNOPSIS
    READ-ONLY. Hermetic Pester suite for the pure parts of
    ../Test-DwDemoStoryline.ps1: the visible-text projection, the placeholder
    verdict, the zero-probes FAIL, the persona identity assert, the secret masking
    and the JSON result shape.

.DESCRIPTION
    No host, no network, no credential. The script is dot-sourced (which runs no
    check by design) and its single HTTP seam, Invoke-DwProbeRequest, is mocked, so
    every case here is decided by the script's own logic.

.EXAMPLE
    pwsh -NoProfile -Command "Invoke-Pester ./skills/dw-demo-base/scripts/tests -Output Detailed"
#>
#Requires -Version 7.0

param()

BeforeAll {
    . (Join-Path $PSScriptRoot '../Test-DwDemoStoryline.ps1')

    # A page as Swift 2 actually serves it: the word "placeholder" lives in an
    # attribute and a class name, never in copy a visitor reads.
    $script:SwiftLikeHtml = @'
<html><head><style>.js-async-fetch-placeholder{display:none}</style>
<script>var x = "placeholder";</script></head>
<body><div class="js-async-fetch-placeholder"></div>
<input type="search" placeholder="Search here">
<!-- TODO: this comment is not copy either -->
<main><h1>Nordic Marine Supply</h1><p>Chandlery for working boats.</p></main>
</body></html>
'@
    $script:PlaceholderCopyHtml =
        '<html><body><main><h1>Our story</h1><p>Lorem ipsum dolor sit amet.</p></main></body></html>'
}

Describe 'ConvertTo-DwVisibleText' {
    It 'drops script, style, comments and attribute values' {
        $t = ConvertTo-DwVisibleText -Html $script:SwiftLikeHtml
        $t | Should -Not -Match 'placeholder'
        $t | Should -Not -Match 'TODO'
        $t | Should -Match 'Nordic Marine Supply'
    }

    It 'keeps placeholder words that are real copy' {
        (ConvertTo-DwVisibleText -Html $script:PlaceholderCopyHtml) | Should -Match 'Lorem ipsum'
    }

    It 'decodes entities and collapses whitespace' {
        (ConvertTo-DwVisibleText -Html '<p>Rope   &amp;   chain</p>') | Should -Be 'Rope & chain'
    }

    It 'returns an empty string for empty input' {
        (ConvertTo-DwVisibleText -Html '') | Should -Be ''
    }
}

Describe 'Test-DwStorylinePages' {
    It 'passes a page whose only "placeholder" is an attribute or a class name' {
        Mock Invoke-DwProbeRequest { [pscustomobject]@{ code = 200; body = $script:SwiftLikeHtml; error = $null } }
        $p = @(Test-DwStorylinePages -BaseUrl 'https://example.invalid' -Pages @('/'))
        $p.Count | Should -Be 1
        $p[0].result | Should -Be 'PASS'
        $p[0].name | Should -Be 'storyline[/]'
    }

    It 'fails a page whose visible copy matches the placeholder regex' {
        Mock Invoke-DwProbeRequest { [pscustomobject]@{ code = 200; body = $script:PlaceholderCopyHtml; error = $null } }
        $p = @(Test-DwStorylinePages -BaseUrl 'https://example.invalid' -Pages @('/story'))
        $p[0].result | Should -Be 'FAIL'
        $p[0].detail | Should -Match 'placeholder'
    }

    It 'fails a page that does not answer 200' {
        Mock Invoke-DwProbeRequest { [pscustomobject]@{ code = 404; body = ''; error = $null } }
        $p = @(Test-DwStorylinePages -BaseUrl 'https://example.invalid' -Pages @('/missing'))
        $p[0].result | Should -Be 'FAIL'
        $p[0].value | Should -Be 404
    }

    It 'applies the object form: length band and substring asserts' {
        Mock Invoke-DwProbeRequest { [pscustomobject]@{ code = 200; body = '<main>Add to cart</main>'; error = $null } }
        $entry = [pscustomobject]@{ path = '/p'; minBytes = 10000; contains = @('Add to cart'); notContains = @('Add to cart') }
        $p = @(Test-DwStorylinePages -BaseUrl 'https://example.invalid' -Pages @($entry))
        $p[0].result | Should -Be 'FAIL'
        $p[0].detail | Should -Match 'min 10000'
        $p[0].detail | Should -Match 'must be absent'
    }

    It 'fails an entry with no path rather than skipping it' {
        Mock Invoke-DwProbeRequest { throw 'must not be called' }
        $p = @(Test-DwStorylinePages -BaseUrl 'https://example.invalid' -Pages @([pscustomobject]@{ minBytes = 1 }))
        $p[0].result | Should -Be 'FAIL'
    }
}

Describe 'Persona sign-in' {
    BeforeEach {
        $script:Secret = 'not-a-real-secret-value'
    }

    It 'passes when the identity page carries the marker, and never echoes the secret' {
        Mock Invoke-DwProbeRequest {
            if ($Url -match '/account') { [pscustomobject]@{ code = 200; body = '<a>Sign out</a>'; error = $null } }
            else { [pscustomobject]@{ code = 200; body = 'ok'; error = $null } }
        }
        $c = Connect-DwPersona -BaseUrl 'https://example.invalid' -Login ([pscustomobject]@{ path = '/api/login' }) `
            -Username 'buyer@example.invalid' -Secret $script:Secret -Role 'buyer' `
            -IdentityPath '/account' -IdentityContains 'Sign out'
        $c.ok | Should -BeTrue
        $c.identityAsserted | Should -BeTrue
        $c.detail | Should -Not -Match ([regex]::Escape($script:Secret))
    }

    It 'fails when the login succeeds but the session is still anonymous' {
        Mock Invoke-DwProbeRequest {
            if ($Url -match '/account') { [pscustomobject]@{ code = 200; body = '<a>Sign in</a>'; error = $null } }
            else { [pscustomobject]@{ code = 200; body = 'ok'; error = $null } }
        }
        $c = Connect-DwPersona -BaseUrl 'https://example.invalid' -Login ([pscustomobject]@{ path = '/api/login' }) `
            -Username 'buyer@example.invalid' -Secret $script:Secret -Role 'buyer' `
            -IdentityPath '/account' -IdentityContains 'Sign out'
        $c.ok | Should -BeFalse
        $c.detail | Should -Match 'NOT signed in'
    }

    It 'says so when only the login status was checked' {
        Mock Invoke-DwProbeRequest { [pscustomobject]@{ code = 200; body = 'ok'; error = $null } }
        $c = Connect-DwPersona -BaseUrl 'https://example.invalid' -Login $null `
            -Username 'buyer@example.invalid' -Secret $script:Secret -Role 'buyer'
        $c.ok | Should -BeTrue
        $c.identityAsserted | Should -BeFalse
        $c.detail | Should -Match 'STATUS ONLY'
    }

    It 'fails a persona with no resolvable secret, masking the absence' {
        Mock Invoke-DwProbeRequest { throw 'must not be called' }
        $personas = [pscustomobject]@{
            accounts = @([pscustomobject]@{ role = 'csr'; username = 'csr@example.invalid'; secretEnv = 'DW_TEST_SECRET_THAT_IS_UNSET' })
        }
        $p = @(Test-DwPersonaLogins -BaseUrl 'https://example.invalid' -Personas $personas -Secrets $null)
        $p[0].result | Should -Be 'FAIL'
        $p[0].detail | Should -Match '<unset>'
    }
}

Describe 'Format-DwMaskedSecret' {
    It 'reports length only, never any of the value' {
        $m = Format-DwMaskedSecret -Value 'abcdefgh'
        $m | Should -Be '<set, 8 chars>'
        $m | Should -Not -Match 'abcd'
    }
    It 'reports an unset secret as the unset marker' {
        (Format-DwMaskedSecret -Value $null) | Should -Be '<unset>'
    }
}

Describe 'Invoke-DwDemoStorylineCheck' {
    It 'FAILS when the config declares no pages and no personas (zero probes)' {
        Mock Invoke-DwProbeRequest { throw 'must not be called' }
        $r = Invoke-DwDemoStorylineCheck -Config ([pscustomobject]@{}) -BaseUrl 'https://example.invalid'
        $r.status | Should -Be 'FAIL'
        @($r.probes).Count | Should -Be 0
        $r.detail | Should -Match 'zero probes'
    }

    It 'returns the documented JSON shape and round-trips' {
        Mock Invoke-DwProbeRequest { [pscustomobject]@{ code = 200; body = $script:SwiftLikeHtml; error = $null } }
        $r = Invoke-DwDemoStorylineCheck -Config ([pscustomobject]@{ pages = @('/', '/about') }) -BaseUrl 'https://example.invalid'
        $r.status | Should -Be 'PASS'
        $r.detail | Should -Be '2/2 probe(s) passed'
        $back = $r | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $back.baseUrl | Should -Be 'https://example.invalid'
        @($back.probes).Count | Should -Be 2
        foreach ($probe in @($back.probes)) {
            $probe.PSObject.Properties.Name | Should -Contain 'name'
            $probe.PSObject.Properties.Name | Should -Contain 'result'
            $probe.PSObject.Properties.Name | Should -Contain 'detail'
            $probe.PSObject.Properties.Name | Should -Contain 'value'
        }
    }

    It 'is FAIL when any single probe fails' {
        Mock Invoke-DwProbeRequest {
            if ($Url -match '/about') { [pscustomobject]@{ code = 500; body = ''; error = $null } }
            else { [pscustomobject]@{ code = 200; body = $script:SwiftLikeHtml; error = $null } }
        }
        $r = Invoke-DwDemoStorylineCheck -Config ([pscustomobject]@{ pages = @('/', '/about') }) -BaseUrl 'https://example.invalid'
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -Be '1/2 probe(s) passed'
    }
}
