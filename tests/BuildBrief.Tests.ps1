# Hermetic controls for the build brief generator (dw-demo-base New-DwBuildBrief.ps1). The script is run
# as a launcher runs it, through pwsh -File, so the parameters arrive as text the way they do in use.
# What is under test: the required small model, the measured split paragraph with the ids filled in,
# the build construction (top-tier orchestrator, three phases, parallel builders with disjoint ownership,
# independent checkers, a hand-in from their evidence), the lower-tier warning only when a distinct top
# model is given, determinism, and no provider name of its own.

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
        $r = Invoke-Brief @('-OrchestratorModel', 'model-top', '-SmallModel', 'model-small')
        $r.exit | Should -Be 0
        $r.lines | Should -Contain $script:Split
        $r.text | Should -Match 'You run on `model-top`\. You are the build session'
        $r.text | Should -Match 'Invoke-DwRecipeSet\.ps1` in this order'
        $r.text | Should -Match '-RunBy model-small'
        $r.text | Should -Match 'verify .*apply once .*-PayDebts -Apply.*final verify'
        $r.text | Should -Match "Make no write to the site until the delegate's apply has ended"
        $r.text | Should -Match 'Delegating never ends your work'
        # The delegate finds the connection in the demo folder; only the secrets come from the shell it inherits.
        $r.text | Should -Match 'reads the site connection itself from the folder that holds the site''s `\.mcp\.json`.*-SiteFolder'
        $r.text | Should -Match 'Only `DW_RECIPE_SECRETS` and `DW_PERSONA_CREDENTIALS`.*must reach the delegate'
        $r.text | Should -Not -Match 'DW_BASE_URL|DW_MCP_TOKEN|DW_API_TOKEN'
        $r.text | Should -Match 'hand-in names the orchestrator \(`model-top`\), the recipe set''s model \(`model-small`; its summary prints `run by: model-small`\), the model that built each package and the model that checked each moment'
        $r.text | Should -Not -Match 'below the top tier'
        $r.lines.Count | Should -BeLessOrEqual 30
    }
    It 'sets up the three phases: packages while the set runs, parallel builders on their tiers, independent checkers' {
        $r = Invoke-Brief @('-OrchestratorModel', 'model-top', '-SmallModel', 'model-small', '-MidModel', 'model-mid')
        $r.exit | Should -Be 0
        $text = $r.text
        # Phase 1: work packages with disjoint ownership, cut while the delegate runs; no write before its apply ended.
        $text | Should -Match 'Phase 1, from minute one, in parallel'
        $text | Should -Match 'work packages\. Each names the files and templates, pages and platform objects it alone may write, its moment or moments, and its acceptance check'
        $noWrite = "Make no write to the site until the delegate's apply has ended"
        $text.IndexOf('Phase 1') | Should -BeLessThan $text.IndexOf($noWrite)
        $text.IndexOf($noWrite) | Should -BeLessThan $text.IndexOf('Phase 2')
        # Phase 2: one builder per package at once, each tier named, the cap, and the parallel-writer rules.
        $text | Should -Match 'one builder sub-agent per package at the same time, at most 4 at once, and name the model in every call'
        $text | Should -Match 'Custom templates and logic on `model-top`; bulk mechanical writes \(stock rows, page permissions, labels\) on `model-small`; routine content such as translation batches on `model-mid`'
        $text | Should -Match 'ownership is disjoint.*exactly one owner package or is edited only by you at merge'
        $text | Should -Match 'restart or recycle, an index rebuild or a global setting \(currency, language layers, order states, permissions on shared pages\) is yours alone, announced, between waves'
        $text | Should -Match 'no test order or cart it does not remove, and reports every object it created'
        # Phase 3: a checker that did not build the moment, the cross-cutting checker, one return, then a reset.
        $text | Should -Match 'each moment is checked on the live site by a fresh sub-agent on `model-top` that did not build it'
        foreach ($c in @('another account''s data reachable by any persona or by URL', 'documents reachable without sign-in', 'leftover sample content',
                'leftover test orders, carts or stock changes', 'every language''s catalogue non-empty', '390 px width')) { $text | Should -Match ([regex]::Escape($c)) }
        $text | Should -Match 'goes back to its owning builder once\. Then you reset the demo data to the plan''s opening state and verify the reset'
        $text | Should -Match 'a moment holds only when a checker that did not build it saw it; otherwise it is partly or not checked, with the reason'
        $text.IndexOf('Phase 2') | Should -BeLessThan $text.IndexOf('Phase 3')
    }
    It 'takes the builder, checker, mid fallback and cap from the parameters' {
        $r = Invoke-Brief @('-OrchestratorModel', 'model-top', '-SmallModel', 'model-small', '-BuilderModel', 'model-b', '-CheckerModel', 'model-c', '-MaxParallel', '2')
        $r.text | Should -Match 'at most 2 at once'
        $r.text | Should -Match 'Custom templates and logic on `model-b`;.*translation batches on `model-b`'
        $r.text | Should -Match 'fresh sub-agent on `model-c` that did not build it'
        (Invoke-Brief @('-SmallModel', 'model-small', '-MaxParallel', '0')).exit | Should -Be 1
        (Invoke-Brief @('-SmallModel', 'model-small', '-BuilderModel', ' ')).exit | Should -Be 1
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
    It 'warns a lower-tier orchestrator and sends every custom package up, only when a different top model is given' {
        (Invoke-Brief @('-OrchestratorModel', 'model-mid', '-SmallModel', 'model-small')).text | Should -Not -Match 'went up|below the top tier'
        $r = Invoke-Brief @('-OrchestratorModel', 'model-top', '-SmallModel', 'model-small', '-TopModel', 'model-top', '-EscalateFor', 'configurator')
        $r.text | Should -Not -Match 'went up|below the top tier'
        $r.text | Should -Match 'Custom templates and logic \(configurator\) on `model-top`'
        $r = Invoke-Brief @('-OrchestratorModel', 'model-mid', '-SmallModel', 'model-small', '-TopModel', 'model-top', '-EscalateFor', 'configurator,brand page')
        $r.exit | Should -Be 0
        $r.lines | Should -Contain $script:Split
        $r.text | Should -Match 'An orchestrator below the top tier has not completed a build with custom work in measurement: every custom package goes up to a builder on `model-top`'
        $r.text | Should -Match 'Custom templates and logic \(configurator, brand page\) on `model-top`'
        $r.text | Should -Match 'fresh sub-agent on `model-top` that did not build it'
        $r.text | Should -Match 'which packages went up to `model-top`'
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
        $r.text | Should -Match 'Custom templates and logic on your own model'
    }
    It 'prints the same brief for the same input, and writes it to -OutFile' {
        $args1 = @('-OrchestratorModel', 'model-mid', '-SmallModel', 'model-small', '-TopModel', 'model-top', '-MidModel', 'model-mid2')
        $a = Invoke-Brief $args1
        $b = Invoke-Brief $args1
        $a.text | Should -BeExactly $b.text
        $a.text | Should -Match 'routine content such as translation batches on `model-mid2`'
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
