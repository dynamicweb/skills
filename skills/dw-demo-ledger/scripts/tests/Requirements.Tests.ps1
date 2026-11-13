<#
.SYNOPSIS
READ-ONLY. Red controls for requirement facts, evaluation order, cited functions, the digest and the delivery read.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/contract.md. Isolated fixtures and
mocked reads only: no host, no database and no credential.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Requirements.Tests.ps1
#>
#Requires -Version 7.0
param()
BeforeAll {
    foreach($file in @('Ledger.Core.ps1','Ledger.Observations.ps1','Ledger.Sql.ps1','Ledger.Transport.ps1','Ledger.Facts.ps1','Ledger.Execute.ps1','Ledger.Run.ps1')){. (Join-Path $PSScriptRoot "../$file")}
    $script:assets=Join-Path $PSScriptRoot '../../assets'
    function New-Capabilities([bool]$Local=$true){
        return @{mcp=@{available=$false;tools=@()};adminApi=@{authenticated=$false;queries=@()};dwapi=@{available=$true};file=@{available=$Local;local=$Local};sql=@{available=$false};facts=@{};errors=@()}
    }
}
Describe 'A flag is found by its class name or its settings path' {
    It 'matches a class name against the one full type name that ends with it' {
        $facts=@{'Dynamicweb.Core.CapabilityControl.CapabilityControlFeature'=$true;'Dynamicweb.Other.SomeFeature'=$false}
        Get-LedgerRequirementState @{kind='flag';id='CapabilityControlFeature';expected=$true} $facts | Should -BeNullOrEmpty
        (Get-LedgerRequirementState @{kind='flag';id='SomeFeature';expected=$true} $facts).result | Should -Be DISABLED
        (Get-LedgerRequirementState @{kind='flag';id='ControlFeature';expected=$true} $facts).result | Should -Be UNVERIFIED
    }
    It 'RED CONTROL: leaves a class name that two feature types share unverified' {
        $facts=@{'A.GateFeature'=$true;'B.GateFeature'=$true}
        $state=Get-LedgerRequirementState @{kind='flag';id='GateFeature';expected=$true} $facts
        $state.result | Should -Be UNVERIFIED
        $state.reason | Should -Match 'matches 2 feature types'
    }
    It 'reads a settings path from the settings layers at the Files root' {
        $files=Join-Path $TestDrive 'settings';$null=New-Item -ItemType Directory $files
        $key='/Globalsettings/Settings/Auditing/EnableAuditing';$requirement=@{kind='flag';id=$key;expected=$true}
        function Get-State([string[]]$Layers){
            Get-ChildItem $files -Filter '*.config'|Remove-Item
            for($i=0;$i -lt $Layers.Count;$i++){Set-Content (Join-Path $files $(if($i){"GlobalSettings.Layer$i.config"}else{'GlobalSettings.config'})) $Layers[$i]}
            $cap=New-Capabilities;Add-LedgerRequirementFacts -Capabilities $cap -Requirements @($requirement) -FilesPath $files
            return Get-LedgerRequirementState $requirement $cap.facts
        }
        $on='<Globalsettings><Settings><Auditing><EnableAuditing>True</EnableAuditing></Auditing></Settings></Globalsettings>'
        $off=$on.Replace('True','False')
        Get-State @($on) | Should -BeNullOrEmpty
        Get-State @($on,$on) | Should -BeNullOrEmpty
        (Get-State @($off)).result | Should -Be DISABLED
        # No default is assumed, layers that disagree are not resolved, and a duplicate or non-boolean key is no fact.
        (Get-State @('<Globalsettings/>')).result | Should -Be UNVERIFIED
        (Get-State @($on,$off)).result | Should -Be UNVERIFIED
        (Get-State @($on.Replace('True','maybe'))).result | Should -Be UNVERIFIED
        (Get-State @('<Globalsettings><Settings><Auditing><EnableAuditing>True</EnableAuditing><EnableAuditing>True</EnableAuditing></Auditing></Settings></Globalsettings>')).result | Should -Be UNVERIFIED
    }
    It 'RED CONTROL: has no settings fact without a local Files root' {
        $cap=New-Capabilities $false
        Add-LedgerRequirementFacts -Capabilities $cap -Requirements @(@{kind='flag';id='/Globalsettings/Settings/Auditing/EnableAuditing';expected=$true}) -FilesPath ''
        $cap.facts.Count | Should -Be 0
    }
}
Describe 'An app requirement is established from the installed add-in folders' {
    BeforeAll {
        $script:files=Join-Path $TestDrive 'apps'
        foreach($name in @('CPQ_Admin.10.24.2','DW_CPQ_API.10.24.3','Truvio.Commerce.Serializer.1.0.8-beta','Twice.1.0.0','Twice.2.0.0','Customer.Private.1.0.0','notes')){
            $null=New-Item -ItemType Directory -Force (Join-Path $files "System/AddIns/Installed/$name")
        }
        $script:requirements=@(
            @{kind='app';id='CPQ_Admin';expected='10.24.2'},@{kind='app';id='DW_CPQ_API';expected='10.24.2'}
            @{kind='app';id='Truvio.Commerce.Serializer';expected=@{min='1.0.8-beta'}},@{kind='app';id='Twice';expected=$true}
            @{kind='app';id='Absent.App';expected=$true},@{kind='app';id='PIM for Business Central connector';expected=$true}
        )
        $script:cap=New-Capabilities;Add-LedgerRequirementFacts -Capabilities $cap -Requirements $requirements -FilesPath $files
    }
    It 'records the version of each required app and nothing else' {
        $cap.facts['app:CPQ_Admin'] | Should -Be '10.24.2'
        $cap.facts['app:Truvio.Commerce.Serializer'] | Should -Be '1.0.8-beta'
        @($cap.facts.Keys|Sort-Object) | Should -Be @('app:CPQ_Admin','app:DW_CPQ_API','app:Truvio.Commerce.Serializer')
    }
    It 'establishes an exact version, a minimum and plain presence' {
        Get-LedgerRequirementState $requirements[0] $cap.facts | Should -BeNullOrEmpty
        Get-LedgerRequirementState $requirements[2] $cap.facts | Should -BeNullOrEmpty
        Get-LedgerRequirementState @{kind='app';id='cpq_admin';expected=$true} $cap.facts | Should -BeNullOrEmpty
    }
    It 'RED CONTROL: another version or a version below the minimum is UNSUPPORTED' {
        (Get-LedgerRequirementState $requirements[1] $cap.facts).result | Should -Be UNSUPPORTED
        (Get-LedgerRequirementState @{kind='app';id='Truvio.Commerce.Serializer';expected=@{min='1.0.8'}} $cap.facts).result | Should -Be UNSUPPORTED
        (Get-LedgerRequirementState @{kind='app';id='Truvio.Commerce.Serializer';expected=@{min='1.0.7'}} $cap.facts) | Should -BeNullOrEmpty
    }
    It 'RED CONTROL: an absent folder, two versions of one app and a descriptive name stay UNVERIFIED' {
        foreach($index in 3,4,5){(Get-LedgerRequirementState $requirements[$index] $cap.facts).result | Should -Be UNVERIFIED}
    }
    It 'RED CONTROL: refuses an expectation that is not true, a version or {min}' {
        (Get-LedgerRequirementState @{kind='app';id='CPQ_Admin';expected=@{max='11.0.0'}} $cap.facts).result | Should -Be ERROR
        (Get-LedgerRequirementState @{kind='app';id='CPQ_Admin';expected=$false} $cap.facts).result | Should -Be UNSUPPORTED
        $function=@{id='fx.one';area='fx';name='One';skill='dw-demo-ledger';status='candidate';requires=@(@{kind='app';id='A';expected=@{max='1.0.0'}});inputs=@();checks=@();notApplicable=@();sources=@()}
        $file=Join-Path $TestDrive 'app.json'
        foreach($case in @(@{expected=@{max='1.0.0'};valid=$false},@{expected=$false;valid=$false},@{expected='';valid=$false},@{expected=$true;valid=$true},@{expected='10.24.2';valid=$true},@{expected=@{min='0.6.0-beta'};valid=$true})){
            $function.requires[0].expected=$case.expected
            @{schema=1;area='fx';functions=@($function)}|ConvertTo-Json -Depth 10|Set-Content $file
            if($case.valid){{Read-LedgerJson $file (Join-Path $assets 'ledger.schema.json')} | Should -Not -Throw}
            else{{Read-LedgerJson $file (Join-Path $assets 'ledger.schema.json')} | Should -Throw '*ledger.schema.json*'}
        }
    }
    It 'compares versions with three or four numbers and a prerelease label' {
        Compare-LedgerVersion '1.0.8-beta' '1.0.8' | Should -Be -1
        Compare-LedgerVersion '10.24.2' '10.24.2' | Should -Be 0
        Compare-LedgerVersion '10.24.10' '10.24.9' | Should -Be 1
        Compare-LedgerVersion '1.2.3.4' '1.2.3' | Should -Be 1
        Compare-LedgerVersion 'latest' '1.2.3' | Should -BeNullOrEmpty
    }
    It 'reads the folders through the MCP file listing when there is no local Files root' {
        Mock Read-LedgerMcp {@{data=@(@{name='CPQ_Admin.10.24.2';isDirectory=$true},@{name='CPQ_Admin.9.0.0.nupkg';isDirectory=$false})}} -ParameterFilter {$Operation -eq 'list_files' -and $Arguments.path -eq '/Files/System/AddIns/Installed'}
        $remote=New-Capabilities $false;$remote.mcp=@{available=$true;tools=@('list_files')}
        Add-LedgerRequirementFacts -Capabilities $remote -Requirements $requirements -FilesPath ''
        $remote.facts['app:CPQ_Admin'] | Should -Be '10.24.2'
    }
    It 'RED CONTROL: a refused MCP listing gives no fact and a note' {
        Mock Read-LedgerMcp {throw [UnauthorizedAccessException]::new('denied')}
        $remote=New-Capabilities $false;$remote.mcp=@{available=$true;tools=@('list_files')}
        Add-LedgerRequirementFacts -Capabilities $remote -Requirements $requirements -FilesPath ''
        $remote.facts.Count | Should -Be 0
        $remote.errors | Should -Contain 'Installed app listing is unavailable over MCP.'
    }
}
Describe 'Rulings come first and a named function must pass' {
    BeforeAll {
        function New-Run([hashtable]$Outcomes,[string[]]$CheckIds,[string[]]$FunctionIds,[hashtable]$Rulings=@{},[hashtable]$Facts=@{}){
            $functions=@{
                'fx.base'=@{id='fx.base';requires=@();notApplicable=@()}
                'fx.dependent'=@{id='fx.dependent';requires=@(@{kind='capability';id='fx.base';expected=$true});notApplicable=@()}
                'fx.app'=@{id='fx.app';requires=@(@{kind='app';id='Absent.App';expected=$true});notApplicable=@(@{id='catalogue-does-not-use';when='Not used'})}
                'fx.replaced'=@{id='fx.replaced';requires=@();notApplicable=@(@{id='classic-engine';when='The build uses fx.base instead';requiresFunction='fx.base'})}
                'fx.loop-a'=@{id='fx.loop-a';requires=@(@{kind='capability';id='fx.loop-b';expected=$true});notApplicable=@()}
                'fx.loop-b'=@{id='fx.loop-b';requires=@(@{kind='capability';id='fx.loop-a';expected=$true});notApplicable=@()}
                'fx.text'=@{id='fx.text';requires=@(@{kind='capability';id='external identity tenant supplied at runtime';expected=$true});notApplicable=@()}
            }
            $checks=@{};foreach($id in $functions.Keys){$checks["$id.one"]=@{id="$id.one";functionId=$id;intent=@{level='configured';proves='p'}}}
            $checks['fx.base.two']=@{id='fx.base.two';functionId='fx.base';intent=@{level='configured';proves='p'}}
            $script:outcomes=$Outcomes
            $cap=New-Capabilities;$cap.facts=$Facts
            return Get-LedgerRows @{build=@{lock=@{checkIds=$CheckIds};functions=$FunctionIds;rulings=$Rulings};functions=$functions;checks=$checks;capabilities=$cap;profile=@{expectations=@{}};surfaces=@('file');root=$TestDrive;assets=$assets;blocked=$null}
        }
        function Get-Result($Rows,[string]$Id){return @($Rows|Where-Object {$_.id -eq $Id})[0]}
    }
    BeforeEach {Mock Invoke-LedgerCheck {$row=New-LedgerRow $Check;$row.result=$script:outcomes[$Check.id];$row.reason='observed';return $row}}
    It 'applies a ruling although the function has a requirement that cannot be established' {
        $rows=New-Run @{'fx.base.one'='PASS'} @('fx.app.one','fx.base.one') @('fx.app','fx.base') @{'fx.app'=@{applies=$false;rule='catalogue-does-not-use';evidence='Census reviewed.'}}
        (Get-Result $rows 'fx.app.one').result | Should -Be 'NOT-APPLICABLE'
        Get-LedgerVerdict $rows.ToArray() | Should -Be PASS
    }
    It 'RED CONTROL: without a ruling the unknown requirement still blocks the check' {
        $rows=New-Run @{'fx.app.one'='PASS'} @('fx.app.one') @('fx.app')
        (Get-Result $rows 'fx.app.one').result | Should -Be UNVERIFIED
        Should -Invoke Invoke-LedgerCheck -Times 0 -Exactly
    }
    It 'runs a check whose required function passed, so its own FAIL is reported' {
        $rows=New-Run @{'fx.base.one'='PASS';'fx.base.two'='PASS';'fx.dependent.one'='FAIL'} @('fx.dependent.one','fx.base.one','fx.base.two') @('fx.dependent','fx.base')
        (Get-Result $rows 'fx.dependent.one').result | Should -Be FAIL
        @($rows|ForEach-Object {$_.id}) | Should -Be @('fx.dependent.one','fx.base.one','fx.base.two')
        Should -Invoke Invoke-LedgerCheck -Times 3 -Exactly
    }
    It 'RED CONTROL: a required function with a failing check blocks its dependants and names itself' {
        $rows=New-Run @{'fx.base.one'='PASS';'fx.base.two'='FAIL';'fx.dependent.one'='PASS'} @('fx.base.one','fx.base.two','fx.dependent.one') @('fx.dependent','fx.base')
        $row=Get-Result $rows 'fx.dependent.one'
        $row.result | Should -Be UNVERIFIED
        $row.reason | Should -Be "Required capability: function 'fx.base' is FAIL in this run."
        Get-LedgerVerdict $rows.ToArray() | Should -Be FAIL
    }
    It 'RED CONTROL: a required function that the build does not lock is not established' {
        $rows=New-Run @{'fx.dependent.one'='PASS'} @('fx.dependent.one') @('fx.dependent')
        (Get-Result $rows 'fx.dependent.one').reason | Should -Be "Required capability: function 'fx.base' has no locked check in this build."
        $rows=New-Run @{'fx.dependent.one'='PASS'} @('fx.dependent.one') @('fx.dependent','fx.base') @{'fx.base'=@{applies=$true}}
        (Get-Result $rows 'fx.dependent.one').result | Should -Be UNVERIFIED
    }
    It 'RED CONTROL: a circular capability requirement is ERROR, not a hang' {
        $rows=New-Run @{'fx.loop-a.one'='PASS';'fx.loop-b.one'='PASS'} @('fx.loop-a.one','fx.loop-b.one') @('fx.loop-a','fx.loop-b')
        @($rows|Where-Object {$_.result -eq 'ERROR' -and $_.reason -match 'Circular'}).Count | Should -Be 1
        @($rows|Where-Object {$_.result -eq 'PASS'}).Count | Should -Be 0
    }
    It 'keeps a capability that is not a function id a fact to be measured' {
        $rows=New-Run @{'fx.text.one'='PASS'} @('fx.text.one') @('fx.text')
        (Get-Result $rows 'fx.text.one').result | Should -Be UNVERIFIED
        $rows=New-Run @{'fx.text.one'='PASS'} @('fx.text.one') @('fx.text') @{} @{'external identity tenant supplied at runtime'=$true}
        (Get-Result $rows 'fx.text.one').result | Should -Be PASS
    }
    It 'accepts a ground that cites another function only while that function passes' {
        $ruling=@{'fx.replaced'=@{applies=$false;rule='classic-engine';evidence='The build uses the classic engine.'}}
        $rows=New-Run @{'fx.base.one'='PASS'} @('fx.replaced.one','fx.base.one') @('fx.replaced','fx.base') $ruling
        (Get-Result $rows 'fx.replaced.one').result | Should -Be 'NOT-APPLICABLE'
        (Get-Result $rows 'fx.replaced.one').reason | Should -Match "cited function 'fx\.base' passed"
    }
    It 'RED CONTROL: a ground that cites a failing or unbuilt function does not certify' {
        $ruling=@{'fx.replaced'=@{applies=$false;rule='classic-engine';evidence='The build uses the classic engine.'}}
        $rows=New-Run @{'fx.base.one'='FAIL'} @('fx.replaced.one','fx.base.one') @('fx.replaced','fx.base') $ruling
        $row=Get-Result $rows 'fx.replaced.one'
        $row.result | Should -Be UNVERIFIED
        $row.reason | Should -Be "Ruling ground 'classic-engine' cites another function, and function 'fx.base' is FAIL in this run."
        $rows=New-Run @{} @('fx.replaced.one') @('fx.replaced') $ruling
        (Get-Result $rows 'fx.replaced.one').reason | Should -Match "function 'fx\.base' has no locked check in this build"
    }
    It 'accepts requiresFunction on a ground in a function file' {
        $function=@{id='fx.one';area='fx';name='One';skill='dw-demo-ledger';status='candidate';requires=@();inputs=@();checks=@();notApplicable=@(@{id='classic-engine';when='Uses the other one';requiresFunction='fx.two'});sources=@()}
        $file=Join-Path $TestDrive 'ground.json';@{schema=1;area='fx';functions=@($function)}|ConvertTo-Json -Depth 10|Set-Content $file
        {Read-LedgerJson $file (Join-Path $assets 'ledger.schema.json')} | Should -Not -Throw
        $function.notApplicable[0].requiresFunction='Not An Id';@{schema=1;area='fx';functions=@($function)}|ConvertTo-Json -Depth 10|Set-Content $file
        {Read-LedgerJson $file (Join-Path $assets 'ledger.schema.json')} | Should -Throw '*ledger.schema.json*'
    }
}
Describe 'The digest covers every file and names a line-ending cause' {
    BeforeEach {
        $script:root=Join-Path $TestDrive ([guid]::NewGuid().ToString('n'));$null=New-Item -ItemType Directory (Join-Path $root 'probes')
        [IO.File]::WriteAllText((Join-Path $root 'manifest.json'),"{`n  `"schema`": 1`n}`n")
        [IO.File]::WriteAllText((Join-Path $root 'probes/a.json'),"{`n  `"id`": `"a`"`n}`n")
    }
    It 'RED CONTROL: a change to a hidden file changes the digest' {
        $hidden=Join-Path $root 'probes/.hidden.json';[IO.File]::WriteAllText($hidden,'{"a":1}')
        if($IsWindows){(Get-Item -LiteralPath $hidden -Force).Attributes='Hidden'}
        $before=Get-LedgerDigest $root
        if($IsWindows){(Get-Item -LiteralPath $hidden -Force).Attributes='Normal'};[IO.File]::WriteAllText($hidden,'{"a":2}')
        if($IsWindows){(Get-Item -LiteralPath $hidden -Force).Attributes='Hidden'}
        Get-LedgerDigest $root | Should -Not -Be $before
    }
    It 'names both digests and the converted line endings' {
        $locked=Get-LedgerDigest $root
        foreach($file in Get-ChildItem $root -Recurse -File){[IO.File]::WriteAllText($file.FullName,[IO.File]::ReadAllText($file.FullName).Replace("`n","`r`n"))}
        $now=Get-LedgerDigest $root
        $now | Should -Not -Be $locked
        $text=Get-LedgerDigestFault $root $locked $now
        $text | Should -Match ([regex]::Escape("lock.digest is $locked, the snapshot beside the manifest is $now"))
        $text | Should -Match '2 of 2 snapshot files have CRLF line endings, and with LF endings this snapshot has the locked digest'
        $text | Should -Match 'core\.autocrlf'
    }
    It 'RED CONTROL: does not blame line endings for a change of content' {
        $locked=Get-LedgerDigest $root
        [IO.File]::WriteAllText((Join-Path $root 'probes/a.json'),"{`r`n  `"id`": `"b`"`r`n}`r`n")
        $text=Get-LedgerDigestFault $root $locked (Get-LedgerDigest $root)
        $text | Should -Match 'line endings alone do not explain this difference'
        $text | Should -Match 'Update-DwLedgerLock\.ps1'
        [IO.File]::WriteAllText((Join-Path $root 'probes/a.json'),"{`n  `"id`": `"b`"`n}`n")
        Get-LedgerDigestFault $root $locked (Get-LedgerDigest $root) | Should -Not -Match 'CRLF'
    }
}
Describe 'The descriptor read is retried' {
    BeforeEach {Mock Start-Sleep {}}
    It 'reads the version after one failed attempt' {
        $script:calls=0
        Mock Invoke-RestMethod {$script:calls++;if($script:calls -eq 1){throw 'timeout'};@{info=@{version='1.0.0'}}}
        Get-LedgerObservedVersion -BaseUrl 'http://stub.invalid' | Should -Be '1.0.0'
        Should -Invoke Invoke-RestMethod -Times 2 -Exactly
    }
    It 'RED CONTROL: gives no version after three failed attempts' {
        Mock Invoke-RestMethod {throw 'timeout'}
        Get-LedgerObservedVersion -BaseUrl 'http://stub.invalid' | Should -BeNullOrEmpty
        Should -Invoke Invoke-RestMethod -Times 3 -Exactly
    }
}
Describe 'A delivery read is one anonymous GET on an allowlisted route' {
    BeforeAll {
        $script:cap=New-Capabilities $false
        function New-DeliveryCheck([hashtable]$Change=@{},[hashtable]$Assertion=@{kind='scalar';op='ge';value=1}){
            $binding=@{id='d';surface='dwapi';status='implemented';handler='dwapi-count';operation='ecommerce/products/search';arguments=@{LanguageId='{lang}'};projection=@{rowsPath='products'}}
            foreach($key in $Change.Keys){$binding[$key]=$Change[$key]}
            return @{id='fx.delivery';functionId='fx';intent=@{proves='Served';level='behavioural'};assertion=$Assertion;bindings=@($binding)}
        }
        function Invoke-Delivery($Check,[hashtable]$Build=@{defaultLanguage='LANG1';areaId=3}){return Invoke-LedgerCheck $Check $Build $cap @{expectations=@{}} @('dwapi') '' '' ''}
        function New-Response([int]$Status,$Body){return @{StatusCode=$Status;Content=($Body|ConvertTo-Json -Depth 10 -Compress)}}
    }
    BeforeEach {$script:LedgerTarget=@{baseUrl='http://stub.invalid';insecure=$false}}
    It 'counts the projected rows, sends GET and no credential' {
        Mock Invoke-WebRequest {New-Response 200 @{products=@(@{id='P1'},@{id='P2'});totalPages=1}}
        $row=Invoke-Delivery (New-DeliveryCheck)
        $row.result | Should -Be PASS
        $row.measured | Should -Be 2
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {$Method -eq 'Get' -and $Uri -eq 'http://stub.invalid/dwapi/ecommerce/products/search?LanguageId=LANG1' -and -not $Headers.ContainsKey('Authorization')}
    }
    It 'RED CONTROL: refuses <route> before any request' -TestCases @(
        @{route='users/info/profiles/switch'},@{route='users/authenticate/refresh'},@{route='ecommerce/carts/create'},@{route='content/areas/../../admin/api/ProductSave'}
    ) {
        param($route)
        Mock Invoke-WebRequest {New-Response 200 @{products=@(@{id='P1'})}}
        (Invoke-Delivery (New-DeliveryCheck @{operation=$route})).result | Should -Be ERROR
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }
    It 'RED CONTROL: a rendered value that still carries the source unit FAILs' {
        $check=New-DeliveryCheck @{projection=@{rowsPath='products';filter=@{field='fields.Width.value';op='contains';value=' cm'}}} @{kind='scalar';op='eq';value=1}
        Mock Invoke-WebRequest {New-Response 200 @{products=@(@{id='P1';fields=@{Width=@{value='12 in'}}})}}
        (Invoke-Delivery $check).result | Should -Be FAIL
        Mock Invoke-WebRequest {New-Response 200 @{products=@(@{id='P1';fields=@{Width=@{value='30.5 cm'}}})}}
        (Invoke-Delivery $check).result | Should -Be PASS
    }
    It 'leaves <name> UNVERIFIED' -TestCases @(
        @{name='a route the target does not serve';status=404;body=@{};change=@{}}
        @{name='a refused read';status=401;body=@{};change=@{}}
        @{name='a paged response';status=200;body=@{products=@(@{id='P1'});totalPages=4};change=@{}}
        @{name='a response without the projected rows';status=200;body=@{items=@()};change=@{}}
        @{name='a binding without a row projection';status=200;body=@{products=@()};change=@{projection=@{}}}
    ) {
        param($name,$status,$body,$change)
        Mock Invoke-WebRequest {New-Response $status $body}
        (Invoke-Delivery (New-DeliveryCheck $change)).result | Should -Be UNVERIFIED
    }
    It 'reports a server error and a body that is not JSON as ERROR' {
        Mock Invoke-WebRequest {New-Response 500 @{}}
        (Invoke-Delivery (New-DeliveryCheck)).result | Should -Be ERROR
        Mock Invoke-WebRequest {@{StatusCode=200;Content='<html>'}}
        (Invoke-Delivery (New-DeliveryCheck)).result | Should -Be ERROR
    }
    It 'fills a route input from the build and refuses one that is not a plain id' {
        Mock Invoke-WebRequest {New-Response 200 @(@{id=1},@{id=2})}
        $check=New-DeliveryCheck @{operation='frontend/navigations/{areaId}';arguments=@{};projection=@{rowsPath='$'}}
        (Invoke-Delivery $check).result | Should -Be PASS
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {$Uri -eq 'http://stub.invalid/dwapi/frontend/navigations/3'}
        (Invoke-Delivery $check @{}).result | Should -Be UNVERIFIED
        (Invoke-Delivery $check @{areaId='3/../../admin'}).result | Should -Be ERROR
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }
    It 'lists read routes only' {
        $routes=@((Read-LedgerJson (Join-Path $assets 'handlers.json')).dwapiReadRoutes)
        $routes.Count | Should -BeGreaterThan 0
        @($routes|Where-Object {$_ -cnotmatch '^[A-Za-z]+(/([A-Za-z]+|\{(areaId|lang|pimShop)\}))*$'}) | Should -BeNullOrEmpty
        @($routes|Where-Object {$_ -match '(?i)users|auth|cart|order|token|password|impersonat|switch|favorites|create'}) | Should -BeNullOrEmpty
    }
}
