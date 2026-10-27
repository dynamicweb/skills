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

Run one suite with `Invoke-Pester -Path tests/<Name>.Tests.ps1`.

Two mechanics worth knowing before adding a suite:

- **A Pester mock body runs in its own session state.** A `$script:` variable written inside a
  `Mock Invoke-WebRequest` block never reaches the test that reads it, so the recorder and the
  response plan are `$global:` and are removed in `AfterAll`.
- **A function defined in a `Describe` body exists only during discovery.** Helpers used by tests
  go in the file-level `BeforeAll`.

Requires Pester 5 or later on PowerShell 7.

The BC suites additionally exercise company isolation, paging, retry, acceptance coverage,
mock/live separation and fixture reset. Run the offline Python suite with Python 3.12+:

```powershell
python -m unittest discover -s tests -p "test_bc_*.py" -v
pwsh -NoProfile -Command "Invoke-Pester -Path tests/Bc.Api.Tests.ps1 -Output Detailed"
```

These checks make no live compatibility claim. BC acceptance still requires source,
platform and buyer evidence from the selected environment.
