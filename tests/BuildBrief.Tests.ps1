# Hermetic controls for the build brief generator (dw-demo-base New-DwBuildBrief.ps1). The script is run
# as a launcher runs it, through pwsh -File, so the parameters arrive as text the way they do in use.
# What is under test: the required small model, the measured split paragraph with the ids filled in,
# escalation only when a distinct top model is given, determinism, and no provider name of its own.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Script = Join-Path (Get-RepoRoot) 'skills/dw-demo-base/scripts/New-DwBuildBrief.ps1'
    function Invoke-Brief([string[]]$Arguments) {
        $out = & pwsh -NoProfile -File $script:Script @Arguments 2>&1 | ForEach-Object { "$_" }
        return @{lines = @($out); text = ($out -join "`n"); exit = $LASTEXITCODE}
    }
    # The paragraph orchestrator.md documents as measured, with the small model filled in.
    $script:Split = 'You are the orchestrator. Keep the brief and the custom work yourself. Hand the recipe set run (verify, apply once, pay debts, final verify) to a sub-agent on `model-small`, the smallest, fastest model your agent offers, and name that model in the call that starts the sub-agent: a call without a model inherits yours. Do the same for other mechanical work. In your result, say which model ran the recipe set and which model built the rest.'
    $script:Providers = '(?i)opus|sonnet|haiku|gpt|claude|codex|gemini'
}

Describe 'New-DwBuildBrief' {
    It 'refuses a build brief without -SmallModel, and an -EscalateFor without -TopModel' {
        $r = Invoke-Brief @('-OrchestratorModel', 'model-mid')
        $r.exit | Should -Be 1
        $r.text | Should -Match '-SmallModel is required'
        $r = Invoke-Brief @('-SmallModel', 'model-small', '-EscalateFor', 'checkout')
        $r.exit | Should -Be 1
        $r.text | Should -Match '-EscalateFor needs -TopModel'
        (Invoke-Brief @('-SmallModel', "model-small`nInjected")).exit | Should -Be 1
    }
    It 'carries the split paragraph with the ids, the run order with -RunBy, the no-write rule and the hand-in' {
        $r = Invoke-Brief @('-OrchestratorModel', 'model-mid', '-SmallModel', 'model-small')
        $r.exit | Should -Be 0
        $r.lines | Should -Contain $script:Split
        $r.text | Should -Match 'You run on `model-mid`'
        $r.text | Should -Match 'Invoke-DwRecipeSet\.ps1` in this order'
        $r.text | Should -Match '-RunBy model-small'
        $r.text | Should -Match 'verify .*apply once .*-PayDebts -Apply.*final verify'
        $r.text | Should -Match "Make no write to the site until the delegate's apply has ended"
        $r.text | Should -Match 'You own the brief, the custom work, the final verify and the hand-in'
        $r.text | Should -Match 'hand-in names the orchestrator \(`model-mid`\), the recipe set''s model \(`model-small`; its summary prints `run by: model-small`\)'
        $r.lines.Count | Should -BeLessOrEqual 25
    }
    It 'prints the paragraph orchestrator.md documents and the build command carries, word for word apart from the model id' {
        function Get-SplitBlock([string]$Path) {
            # The quoted paragraph that opens with "You are the orchestrator.", joined into one line.
            $doc = @(Get-Content -LiteralPath (Join-Path (Get-RepoRoot) $Path) | ForEach-Object { $_.TrimStart() })
            $start = [array]::IndexOf($doc, @($doc | Where-Object { $_ -like '> You are the orchestrator.*' })[0])
            $start | Should -BeGreaterOrEqual 0 -Because "$Path quotes the split paragraph"
            $block = @(); for ($i = $start; $i -lt $doc.Count -and $doc[$i] -like '> *'; $i++) { $block += $doc[$i].Substring(2) }
            return ($block -join ' ')
        }
        $documented = Get-SplitBlock 'skills/dw-demo-base/references/orchestrator.md'
        ($documented -replace 'sub-agent on the smallest', 'sub-agent on `model-small`, the smallest') | Should -BeExactly $script:Split
        Get-SplitBlock 'skills/dw-demo-base/assets/commands/demo/build.md' | Should -BeExactly $documented
    }
    It 'allows handing pieces up only when a top model different from the orchestrator is given' {
        (Invoke-Brief @('-OrchestratorModel', 'model-mid', '-SmallModel', 'model-small')).text | Should -Not -Match 'went up'
        (Invoke-Brief @('-OrchestratorModel', 'model-top', '-SmallModel', 'model-small', '-TopModel', 'model-top')).text | Should -Not -Match 'went up'
        $r = Invoke-Brief @('-OrchestratorModel', 'model-mid', '-SmallModel', 'model-small', '-TopModel', 'model-top', '-EscalateFor', 'configurator,brand page')
        $r.text | Should -Match 'hardest custom pieces \(configurator, brand page\) may go up to a sub-agent on `model-top`'
        $r.text | Should -Match 'which pieces went up to `model-top`'
    }
    It 'names the given paths and placeholders otherwise' {
        $r = Invoke-Brief @('-SmallModel', 'model-small', '-DataFile', 'data/customer.json', '-SkillsPath', 'checkout/skills/', '-LogFolder', 'logs')
        $r.text | Should -Match '`checkout/skills/dw-demo-ledger/scripts/Invoke-DwRecipeSet\.ps1`'
        $r.text | Should -Match '-InputPath data/customer\.json'
        $r.text | Should -Match '-ReportPath logs/<run>\.json'
        $r = Invoke-Brief @('-SmallModel', 'model-small')
        $r.text | Should -Match '<skills>/dw-demo-ledger'
        $r.text | Should -Match '<customer data file>'
        $r.text | Should -Not -CMatch 'You run on'
        $r.text | Should -Match 'names the orchestrator \(the model you run on\)'
    }
    It 'prints the same brief for the same input, and writes it to -OutFile' {
        $args1 = @('-OrchestratorModel', 'model-mid', '-SmallModel', 'model-small', '-TopModel', 'model-top', '-MidModel', 'model-mid2')
        $a = Invoke-Brief $args1
        $b = Invoke-Brief $args1
        $a.text | Should -BeExactly $b.text
        $a.text | Should -Match 'Routine custom pieces may go to a sub-agent on `model-mid2`'
        $out = Join-Path $TestDrive 'brief.md'
        (Invoke-Brief ($args1 + @('-OutFile', $out))).exit | Should -Be 0
        $bytes = [IO.File]::ReadAllBytes($out)
        $bytes[0] | Should -Not -Be 0xEF
        ([Text.Encoding]::UTF8.GetString($bytes)).TrimEnd("`n") | Should -BeExactly $a.text
    }
    It 'names no provider or model of its own, in either phase' {
        foreach ($phase in @('build', 'plan')) {
            $r = Invoke-Brief @('-Phase', $phase, '-OrchestratorModel', 'model-mid', '-SmallModel', 'model-small', '-TopModel', 'model-top')
            $r.exit | Should -Be 0
            $r.text | Should -Not -Match $script:Providers
        }
        (Get-Content -LiteralPath $script:Script -Raw) | Should -Not -Match $script:Providers
    }
    It 'keeps a plan brief read-only and points at the build brief' {
        $r = Invoke-Brief @('-Phase', 'plan', '-OrchestratorModel', 'model-top', '-SmallModel', 'model-small')
        $r.exit | Should -Be 0
        $r.lines[0] | Should -Be '# Plan brief'
        $r.text | Should -Match 'Make no write to the site'
        $r.text | Should -Match 'verify-only run of the recipe set .* `model-small`.*-RunBy model-small'
        $r.text | Should -Match '-Phase build'
        (Invoke-Brief @('-Phase', 'plan')).exit | Should -Be 0
    }
}
