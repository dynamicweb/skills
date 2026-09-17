<#
.SYNOPSIS
    WRITES: nothing. Validator fixture only - never run this file.

.DESCRIPTION
    Deliberately non-conforming input for `validate-skills.py --self-test`.
    It lives OUTSIDE skills/ so the normal validation run does not scan it,
    and every line below is inert: no real host, no real credential, no call
    that reaches a network. Each numbered block trips exactly one AV rule
    from dw-skill-authoring ("Shipping scripts" -> "AV-safe scripts").

    This block also proves the exemption: naming Invoke-Expression and Add-Type
    in prose must NOT fail a file, because the rules score code, not
    documentation.

.EXAMPLE
    python scripts/validate-skills.py --self-test
#>
#Requires -Version 7.0
param()

# 1. invoke-expression: a command built as a string.
$command = 'Get-Date'
Invoke-Expression $command

# 2. add-type: inline compilation.
Add-Type -TypeDefinition 'public class Fixture { }'

# 3. base64: an encoded payload instead of a literal.
$decoded = [Convert]::FromBase64String('Zml4dHVyZQ==')

# 4. web-client: the legacy client instead of the cmdlets.
$client = New-Object System.Net.WebClient
$body = $client.DownloadString('https://example.invalid/probe')

# 5. credential: a literal, and a connection string carrying one.
$password = 'not-a-real-secret'
$connection = 'Server=.;Database=Fixture;User Id=sa;Password=nope;'
$secure = ConvertTo-SecureString 'nope' -AsPlainText -Force

# 6. tls-ungated: nothing in this file gates the bypass on a loopback base
#    URL or on an opt-in switch, so every call disables validation.
$response = Invoke-RestMethod -Uri 'https://example.invalid/admin/api/Ping' -SkipCertificateCheck

# 7. user-agent: a browser UA with no `# why` comment stating the protocol
#    reason, so it reads as evasion rather than as a requirement.
$headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }

$null = $decoded, $body, $password, $connection, $secure, $response, $headers
