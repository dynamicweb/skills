<#
.SYNOPSIS
    READ-ONLY. Hermetic Pester suite for the parts of ../Save-DwStorefrontShot.ps1
    that need no browser: viewport resolution, the runner argument list (the
    password never on it), the merged result, and the refusals before any run.

.DESCRIPTION
    No host, no network, no browser, no credential. The script is dot-sourced (which
    runs nothing by design); the refusal cases invoke it in a child pwsh, which exits
    before node is started.

.EXAMPLE
    pwsh -NoProfile -Command "Invoke-Pester ./skills/dw-demo-swift/scripts/tests -Output Detailed"
#>
#Requires -Version 7.0

param()

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '../Save-DwStorefrontShot.ps1'
    . $script:Script
    $script:Vp = [pscustomobject]@{ label = 'phone-390'; width = 390; height = 844; device = 'iPhone 12' }
}

Describe 'Resolve-DwShotViewport' {
    It 'keeps the defaults: a desktop and a phone with a device' {
        $v = @(Resolve-DwShotViewport -Viewport @(
            @{ width = 1440; height = 900; device = $null; label = 'desktop-1440' },
            @{ width = 390; height = 844; device = 'iPhone 12'; label = 'phone-390' }) -DesktopBreakpoint 992)
        $v.Count | Should -Be 2
        @($v | Where-Object { $_.error }).Count | Should -Be 0
        $v[1].device | Should -Be 'iPhone 12'
    }
    It 'refuses a narrow viewport with no device, and labels an unlabelled one' {
        $v = @(Resolve-DwShotViewport -Viewport @(@{ width = 390; height = 844 }) -DesktopBreakpoint 992)
        $v[0].label | Should -Be '390x844'
        $v[0].error | Should -Match 'names no device'
    }
    It 'refuses a viewport with no size' {
        (Resolve-DwShotViewport -Viewport @(@{ label = 'x' }) -DesktopBreakpoint 992).error | Should -Match 'no width'
    }
}

Describe 'Get-DwShotRunnerArgs' {
    It 'passes paths, viewport, device and output folder' {
        $a = Get-DwShotRunnerArgs -Runner 'r.mjs' -BaseUrl 'https://h.example/' -Path @('/en-us/home', 'en-us/shop') `
            -Viewport $script:Vp -OutDir 'C:\out' -TimeoutSec 30
        $a[0] | Should -Be 'r.mjs'
        $a[$a.IndexOf('--url') + 1] | Should -Be 'https://h.example'
        @($a | Where-Object { $_ -eq '--path' }).Count | Should -Be 2
        $a | Should -Contain '/en-us/shop'
        $a[$a.IndexOf('--device') + 1] | Should -Be 'iPhone 12'
        $a[$a.IndexOf('--timeout') + 1] | Should -Be '30000'
        $a | Should -Not -Contain '--user'
        $a | Should -Not -Contain '--allow-self-signed'
    }
    It 'splits a comma-joined -Path, the way pwsh -File hands it over' {
        $a = Get-DwShotRunnerArgs -Runner 'r' -BaseUrl 'https://h' -Path @('/en-us/home,/en-us/shop') -Viewport $script:Vp -OutDir 'o'
        @($a | Where-Object { $_ -eq '--path' }).Count | Should -Be 2
    }
    It 'names the password VARIABLE, never its value' {
        $env:DW_SHOT_TEST_SECRET = 'value-that-must-not-appear'
        try {
            $a = Get-DwShotRunnerArgs -Runner 'r' -BaseUrl 'https://h' -Path '/' -Viewport $script:Vp -OutDir 'o' `
                -UserName 'buyer' -PasswordEnv 'DW_SHOT_TEST_SECRET' -SignInPath '/s' -IdentityPath '/cc' -IdentityText 'Acme'
            $a[$a.IndexOf('--password-env') + 1] | Should -Be 'DW_SHOT_TEST_SECRET'
            ($a -join ' ') | Should -Not -Match 'value-that-must-not-appear'
            $a[$a.IndexOf('--identity-text') + 1] | Should -Be 'Acme'
        }
        finally { Remove-Item Env:DW_SHOT_TEST_SECRET }
    }
    It 'has no parameter that takes a password value' {
        $p = (Get-Command $script:Script).Parameters.Keys
        $p | Should -Not -Contain 'Password'
        $p | Should -Contain 'PasswordEnv'
    }
}

Describe 'Merge-DwShotResult' {
    BeforeAll {
        function New-Run([string]$Label, [string]$Status, [object[]]$Shots, $SignIn) {
            [pscustomobject]@{ status = $Status; viewport = [pscustomobject]@{ label = $Label }; shots = $Shots; signIn = $SignIn; detail = "$Label $Status" }
        }
        $script:Ok = [pscustomobject]@{ path = '/a'; status = 200; file = 'd-a.png'; error = $null }
        $script:NotFound = [pscustomobject]@{ path = '/b'; status = 404; file = 'd-b.png'; error = $null }
    }
    It 'passes when every run passed, and lists only the files saved below 400' {
        $r = Merge-DwShotResult -Runs @((New-Run 'd' 'PASS' @($script:Ok) $null)) -BaseUrl 'https://h' -OutDir 'o'
        $r.status | Should -Be 'PASS'
        $r.files | Should -Be @('d-a.png')
        $r.signIn | Should -BeNullOrEmpty
    }
    It 'fails on a failed run and keeps the 404 out of files' {
        $r = Merge-DwShotResult -Runs @((New-Run 'd' 'PASS' @($script:Ok) $null), (New-Run 'p' 'FAIL' @($script:NotFound) $null)) -BaseUrl 'h' -OutDir 'o'
        $r.status | Should -Be 'FAIL'
        @($r.files).Count | Should -Be 1
        @($r.shots).Count | Should -Be 2
    }
    It 'is UNRUNNABLE when any run could not run, or nothing ran' {
        (Merge-DwShotResult -Runs @((New-Run 'd' 'PASS' @($script:Ok) $null), (New-Run 'p' 'UNRUNNABLE' @() $null)) -BaseUrl 'h' -OutDir 'o').status |
            Should -Be 'UNRUNNABLE'
        (Merge-DwShotResult -Runs @() -BaseUrl 'h' -OutDir 'o').status | Should -Be 'UNRUNNABLE'
    }
    It 'proves the sign-in only when every viewport proved it' {
        $yes = [pscustomobject]@{ proven = $true; detail = 'ok' }
        $no = [pscustomobject]@{ proven = $false; detail = 'redirected' }
        $r = Merge-DwShotResult -Runs @((New-Run 'd' 'PASS' @($script:Ok) $yes), (New-Run 'p' 'FAIL' @() $no)) -BaseUrl 'h' -OutDir 'o' -UserName 'buyer'
        $r.signIn.proven | Should -BeFalse
        $r.detail | Should -Match 'NOT proven'
        $r2 = Merge-DwShotResult -Runs @((New-Run 'd' 'PASS' @($script:Ok) $yes)) -BaseUrl 'h' -OutDir 'o' -UserName 'buyer'
        $r2.signIn.proven | Should -BeTrue
    }
}

Describe 'Refusals before any run' {
    It 'refuses without a base URL (exit 2)' {
        $saved = $env:DW_BASE_URL; $env:DW_BASE_URL = $null
        try {
            $out = pwsh -NoProfile -File $script:Script -OutDir (Join-Path $TestDrive 'o')
            $LASTEXITCODE | Should -Be 2
            (($out -join "`n") | ConvertFrom-Json).detail | Should -Match 'No base URL'
        }
        finally { $env:DW_BASE_URL = $saved }
    }
    It 'refuses a user whose password variable is empty (exit 2), naming the variable' {
        $out = pwsh -NoProfile -File $script:Script -BaseUrl 'https://h.invalid' -UserName 'buyer' `
            -PasswordEnv 'DW_SHOT_TEST_UNSET' -OutDir (Join-Path $TestDrive 'o')
        $LASTEXITCODE | Should -Be 2
        (($out -join "`n") | ConvertFrom-Json).detail | Should -Match 'DW_SHOT_TEST_UNSET is empty'
    }
}
