<#
.SYNOPSIS
WRITES: a resumable local Swift demo from one customer JSON, plus gates, receipts and journal.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. Windows local-install only; never touches
IIS or an existing unowned database. Dry run by default; -Apply authorizes the complete chain.
Preflight prints install-grade requirements and performs template/sqlpackage/dev-certificate cheap fixes.
.PARAMETER ConfigPath
Customer JSON. Only slug and customer.name are required.
.PARAMETER DemoRoot
Destination demo directory; contains the host, Distribution and ignored build evidence.
.PARAMETER SqlServer
Local SQL instance with Windows authentication and database-creation rights.
.PARAMETER Port
Explicit free HTTPS port. Never discovered from a different solution.
.PARAMETER Database
Optional new database name; derived from config slug when omitted.
.PARAMETER Apply
Run the build. Without -Apply or with -WhatIf, list steps without side effects.
.EXAMPLE
pwsh -NoProfile -File scripts/Invoke-DwDemoBaseBuild.ps1 -ConfigPath $config -DemoRoot $demo -SqlServer $server -Port $port -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$DemoRoot,[Parameter(Mandatory)][string]$SqlServer,[Parameter(Mandatory)][ValidateRange(1024,65535)][int]$Port,[string]$Database,[switch]$Apply)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
$limitations=@(
    'Install PowerShell 7, .NET 10 SDK, Git and SQL Server once; service installation is outside this command.',
    'Sign into Claude Code and install the complete public presales skills bundle once.',
    'A fresh agent shell is needed to inherit the User-scope TLS environment setting.',
    'Human design sign-off, domain modelling, localization beyond US/USD/en-US and final customer fine-tuning remain the agent phase.',
    'Hosted targets use dw-demo-hosted; this command only provisions a local Windows install.'
)
try {
    $ConfigPath=(Resolve-Path -LiteralPath $ConfigPath).Path;$c=Read-DwBuildConfig $ConfigPath;$p=Get-DwBuildPaths $DemoRoot
    if(-not $Database){$Database='demo-'+$c.slug}
    $null=Get-DwBuildConnection $SqlServer $Database
    $steps=[ordered]@{
        preflight=$null;release='Get-DwDistributionRelease.ps1';scaffold='New-DwDemoHost.ps1';restore='Restore-DwEditionDatabase.ps1';files='Install-DwDemoFiles.ps1';'brand-files'='New-DwBrandFiles.ps1';'brand-content'='Set-DwDemoBrandContent.ps1';'start-license'='Start-DwDemoBuildHost.ps1';access='Grant-DwDemoAccess.ps1';index='Build-DwDemoIndex.ps1';test='Test-DwDemoBaseBuild.ps1';stamps=$null
    }
    if(-not $Apply -or -not $PSCmdlet.ShouldProcess($p.Root,'Build local demo through all gated steps')){foreach($step in $steps.Keys){Write-Host "Plan: $step"};$limitations|ForEach-Object{Write-Host "Remaining: $_"};exit 0}
    $statePath=Join-Path $p.Root ".demo/$($c.slug)/flow-state.json"
    $fingerprint=(Get-FileHash $ConfigPath -Algorithm SHA256).Hash
    $state=if(Test-Path $statePath){Get-Content -Raw $statePath|ConvertFrom-Json -AsHashtable}else{@{slug=$c.slug;flow='dw-demo-base';steps=@{};gates_passed=@();instructions_used=@{};timings=@{};configSha256=$fingerprint;sqlServer=$SqlServer;database=$Database;port=$Port}}
    if($state.configSha256 -ne $fingerprint -or $state.sqlServer -ne $SqlServer -or $state.database -ne $Database -or $state.port -ne $Port){throw 'Build inputs changed. Use a new DemoRoot; do not resume stale gates.'}
    New-Item -ItemType Directory -Force -Path (Join-Path $p.Notes 'logs') | Out-Null
    $buildLock=[IO.File]::Open((Join-Path $p.Notes 'build.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $journal=Join-Path $p.Notes ('logs/build-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.jsonl')
    foreach($step in $steps.Keys){
        # Readiness can change after a completed run; always re-prove it on resume.
        if($state.steps[$step] -eq 'pass' -and $step -notin 'preflight','start-license','test','stamps'){Write-Host "Resume: $step already passed.";continue}
        $start=Get-Date;$state.steps[$step]='running';Write-DwBuildJson $statePath $state
        Write-Host "BUILD $step"
        try {
            if($step -notin 'preflight','release' -and (Test-Path $p.Release)){
                $resolved=Get-Content -Raw $p.Release | ConvertFrom-Json
                $checkout=& git -C $p.Distribution rev-parse HEAD
                if($LASTEXITCODE -ne 0 -or $checkout -ne $resolved.commit){throw 'Distribution checkout moved since release resolution. Use the recorded commit or a new DemoRoot.'}
            }
            if($step -eq 'preflight'){
                foreach($tool in 'dotnet','git','pwsh'){if(-not(Get-Command $tool -ErrorAction SilentlyContinue)){throw "Install $tool; see references/setup-checks.md."}}
                if(-not ((& dotnet --list-sdks) -match '^10\.')){throw 'Install .NET 10 SDK: https://dotnet.microsoft.com/download/dotnet/10.0 . Put its dotnet on PATH and set DOTNET_ROOT.'}
                Invoke-DwBuildCommand dotnet @('--version') -TimeoutSeconds 45
                # An unmatched filtered list exits nonzero. The complete list lets a missing
                # template reach the cheap install path instead of failing before that path.
                $templates=Invoke-DwBuildCommand dotnet @('new','list') -TimeoutSeconds 180 -CaptureOutput
                if($templates -notmatch '\bdw10-suite\b'){
                    Invoke-DwBuildCommand dotnet @('new','install','Dynamicweb.ProjectTemplates')
                    $templates=Invoke-DwBuildCommand dotnet @('new','list') -TimeoutSeconds 180 -CaptureOutput
                    if($templates -notmatch '\bdw10-suite\b'){throw 'Template installation returned without a dw10-suite template. Inspect the SDK template installation.'}
                }
                Invoke-DwBuildCommand dotnet @('dev-certs','https') -TimeoutSeconds 180
                $master=Get-DwBuildConnection $SqlServer 'master';$null=Get-DwBuildRows $master 'SELECT 1 AS ready'
                if(-not(Get-Command sqlpackage -ErrorAction SilentlyContinue)){
                    $toolDir=Join-Path $p.Notes 'tools';$exe=Join-Path $toolDir 'sqlpackage.exe'
                    if(-not(Test-Path $exe)){Invoke-DwBuildCommand dotnet @('tool','install','--tool-path',$toolDir,'microsoft.sqlpackage')}
                    $env:PATH=$toolDir+[IO.Path]::PathSeparator+$env:PATH
                }
                if(-not $c.installMcpBeforeStart){throw 'The complete unattended chain needs installMcpBeforeStart=true (the default). Use the step scripts for a separate AppStore installation.'}
            } elseif($step -eq 'stamps'){
                $r=Get-Content -Raw $p.Release|ConvertFrom-Json
                $stamp=@('','## Scripted base build provenance',"- Distribution commit: $($r.commit)","- DW: $($r.dwVersion)","- Swift: $($r.swiftTag)","- Edition: $($r.edition), $($r.bacpac.editionVersion)","- Bacpac SHA256: $($r.bacpac.sha256)",'- Credentials: notes/credentials.local.md (ignored).','- Palette writes default Style group; re-staging the theme requires re-running brand generation.',("- License expiry: "+(Get-Content -Raw (Join-Path $p.Notes 'license-proof.json')|ConvertFrom-Json).expiry))
                foreach($app in $r.apps){$stamp+="- App pin: $($app.id) $($app.version)"}
                $ledger=Join-Path $p.Root 'CUSTOMISATIONS.md'
                if((Get-Content -Raw $ledger) -notmatch '## Scripted base build provenance'){Add-Content $ledger $stamp -Encoding utf8NoBOM}
                Write-DwBuildJson (Join-Path $p.Notes 'build-report.json') @{outcome='PASS';baseUrl="https://localhost:$Port";remaining=$limitations;timings=$state.timings;release=$r}
            } else {
                $args=@('-NoProfile','-File',(Join-Path $PSScriptRoot $steps[$step]),'-DemoRoot',$p.Root)
                if($step -in 'scaffold','brand-files','brand-content','test'){$args+=@('-ConfigPath',$ConfigPath)}
                if($step -in 'scaffold','start-license'){$args+=@('-Port',"$Port")}
                if($step -in 'restore','files','brand-content'){$args+=@('-SqlServer',$SqlServer,'-Database',$Database)}
                if($step -ne 'test'){$args+='-Apply'}
                Invoke-DwBuildCommand pwsh $args
            }
            $state.steps[$step]='pass';$state.gates_passed=@(@($state.gates_passed)+$step|Select-Object -Unique)
        }catch{
            $state.steps[$step]='fail'
            $state.gates_passed=@($state.gates_passed | Where-Object {$_ -ne $step})
            throw
        }
        finally{
            $state.timings[$step]=[math]::Round(((Get-Date)-$start).TotalSeconds,2)
            $state.instructions_used[$step]=@('dw-demo-base/references/scripted-base-build.md')
            Write-DwBuildJson $statePath $state
            @{step=$step;result=$state.steps[$step];seconds=$state.timings[$step];'Instructions used'=$state.instructions_used[$step]}|ConvertTo-Json -Compress|Add-Content $journal -Encoding utf8NoBOM
        }
    }
    Write-Host "PASS: scripted base build https://localhost:$Port/en-us/home"
    $limitations|ForEach-Object{Write-Host "Remaining: $_"};exit 0
}catch{
    Write-Error $_ -ErrorAction Continue
    if($state -and (Test-Path $p.Notes)){
        Write-DwBuildJson (Join-Path $p.Notes 'build-report.json') @{outcome='NOT READY';failingStep=$step;remaining=$limitations;timings=$state.timings}
    }
    Write-Host 'OUTCOME: NOT READY. Resolve the failing gate and re-run the same command to resume.'
    $limitations|ForEach-Object{Write-Host "Remaining: $_"};exit 1
}finally{
    if($buildLock){$buildLock.Dispose()}
}
