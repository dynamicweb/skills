# Script tests

Hermetic Pester suites for the shipped scripts under `skills/*/scripts/`. Nothing here reaches a
Dynamicweb host, a database or the network: HTTP is mocked, and a script that imports
`Dw.Api.psm1` / `Dw.Sql.Local.psm1` is copied into `TestDrive:` beside recording stubs of the same
file names, so the `$PSScriptRoot`-relative import resolves to the stub and every call is captured
in order.

**They live here, not under `skills/*/scripts/tests/`.** `scripts/validate-skills.py` applies the
shipped-script contract (a `READ-ONLY.` / `WRITES:` synopsis, `.DESCRIPTION`, a `param()` block,
`#Requires -Version 7.0`) to every file under a skill's `scripts/` folder, recursively — a Pester
file cannot satisfy it and should not pretend to. Keeping the tests outside `skills/` also keeps
them out of the shipped plugin, which is what a consumer wants.

```powershell
Invoke-Pester -Path tests -Output Detailed
```

Requires Pester 5 or later on PowerShell 7.
