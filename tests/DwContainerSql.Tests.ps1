BeforeAll {
    $repo=Split-Path $PSScriptRoot
    Import-Module (Join-Path $repo 'skills/dw-demo-base/scripts/Dw.DemoBuild.psm1') -Force
    Import-Module (Join-Path $repo 'skills/dw-data-access/scripts/Dw.Sql.Local.psm1') -Force
}
Describe 'Explicit SQL credentials and container host boundary' {
    BeforeEach {
        $script:saved=@{}
        foreach($name in 'DW_SQL_USER','DW_SQL_PASSWORD','DW_SQL_CONTAINER_HOST'){
            $script:saved[$name]=[Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name,$null)
        }
    }
    AfterEach { foreach($name in $script:saved.Keys){[Environment]::SetEnvironmentVariable($name,$script:saved[$name])} }
    It 'keeps integrated authentication by default' {
        $b=[System.Data.SqlClient.SqlConnectionStringBuilder]::new((Get-DwBuildConnection localhost fixture))
        $b.IntegratedSecurity|Should -BeTrue
        $b.TrustServerCertificate|Should -BeTrue
        $b.Password|Should -BeNullOrEmpty
    }
    It 'quotes environment credentials safely and never emits them as diagnostics' {
        $env:DW_SQL_USER='fixture-user';$env:DW_SQL_PASSWORD='fixture;"quoted=value'
        $messages=@()
        $value=Get-DwBuildConnection localhost fixture -InformationVariable messages
        $b=[System.Data.SqlClient.SqlConnectionStringBuilder]::new($value)
        $b.IntegratedSecurity|Should -BeFalse
        $b.UserID|Should -Be $env:DW_SQL_USER
        $b.Password|Should -Be $env:DW_SQL_PASSWORD
        $b.TrustServerCertificate|Should -BeTrue
        $messages.Count|Should -Be 0
    }
    It 'refuses partially specified credentials' {
        $env:DW_SQL_USER='fixture-user'
        {Get-DwBuildConnection localhost fixture}|Should -Throw '*both*'
        $env:DW_SQL_USER=$null;$env:DW_SQL_PASSWORD='fixture-value'
        {Get-DwBuildConnection localhost fixture}|Should -Throw '*both*'
    }
    It 'accepts exactly the vouched host with instance and port suffixes' {
        $env:DW_SQL_CONTAINER_HOST='host.docker.internal'
        Assert-DwSqlLocal 'Server=HOST.DOCKER.INTERNAL\FIXTURE,1433;Database=fixture'|Should -BeTrue
        {Assert-DwSqlLocal 'Server=other.example;Database=fixture'}|Should -Throw '*LOCAL INSTALLS ONLY*'
        $env:DW_SQL_CONTAINER_HOST='192.0.2.1'
        Assert-DwSqlLocal 'Server=192.0.2.1,1433;Database=fixture'|Should -BeTrue
    }
    It 'refuses a remote host without opt-in and ignores wildcard opt-ins' {
        {Assert-DwSqlLocal 'Server=host.docker.internal;Database=fixture'}|Should -Throw
        foreach($token in '*.internal','host.docker.internal,1433','host.docker.internal\FIXTURE') {
            $env:DW_SQL_CONTAINER_HOST=$token
            {Assert-DwSqlLocal 'Server=host.docker.internal;Database=fixture'}|Should -Throw
        }
    }
    It 'validates the effective server rather than the first text match' {
        {Assert-DwSqlLocal 'Server=localhost;Data Source=remote.example;Database=fixture'}|Should -Throw
        {Assert-DwSqlLocal 'Application Name="server=localhost";Server=remote.example;Database=fixture'}|Should -Throw
    }
}
