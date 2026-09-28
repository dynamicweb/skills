<#
.SYNOPSIS
    WRITES: starts/stops the Dynamicweb host process it OWNS (never a
    sibling's), a lock file, and timestamped log files under the log folder.

.DESCRIPTION
    The enforced host-lifecycle form (owning reference:
    dw-demo-base/references/host-lifecycle.md — flush first, a restart is the
    last resort). Self-contained on purpose: it needs no token and must work
    when the host is down. Traps encoded:
      - BINDING SAFETY: the PID is resolved ONLY from the port
        (Get-NetTCPConnection -State Listen) and stopped ONLY after the owning
        process's command line proves it belongs to THIS solution — never by
        process name, never by enumerating dotnet processes. A mismatch stops
        nothing and tells you to rediscover the port. (A name-based restart
        has killed a sibling demo's host.)
      - Index-build guard: a Lucene build in flight (state.json heartbeat
        under wwwroot/Files/System/Diagnostics/IndexBuildState) refuses the
        stop — force-killing mid-build corrupts the instance into a
        "must be recovered" state a single rebuild does not clear. -Force
        overrides only this guard, never the ownership check.
      - Lock file (<solution>/notes/host.lock) serializes restarts between
        agents; a lock older than 10 minutes is taken over as stale.
      - Durable start: stdout/stderr redirected to log files (an unredirected
        hidden start has proven flaky), launched via `dotnet run` only (the
        bin/ apphost exe boots a silently degraded host). The PID variable is
        $hostPid — $pid is read-only in PowerShell.
      - Detached start: the host is launched through the shell (cmd.exe does
        the log redirection), so it inherits NONE of the caller's handles.
        A Start-Process -RedirectStandardOutput child inherits the caller's
        stdout pipe, so an agent's foreground shell tool waits for the HOST to
        exit, not for this script (measured: a piped caller returned after
        its child's 25 s lifetime instead of at once). With the detached
        start the script is safe in the foreground and returns on the probe.
      - Port release: Stop waits (bounded, -PortReleaseSeconds) until no
        Listen socket remains on the port, not only until the process exits;
        Start treats a listener whose process is gone, or whose command line
        is empty, as a host still stopping and re-checks instead of refusing
        it as a foreign owner. An immediate Start after Stop used to refuse.
      - Readiness = /Admin answering 200/302 within -ReadyTimeoutMinutes,
        polled; never assumed from the process starting.

.PARAMETER Action
    Start, Stop, or Restart.

.PARAMETER Port
    THIS solution's HTTPS port, from
    Dynamicweb.Host.Suite/Properties/launchSettings.json. Mandatory — no
    default port exists on purpose.

.PARAMETER SolutionPath
    Absolute path of THIS solution's root folder (the one containing
    Dynamicweb.Host.Suite/). Mandatory — the ownership check verifies the
    process command line against it.

.PARAMETER Reason
    One-line reason recorded in the lock file and the restart log.

.PARAMETER LogDirectory
    Where host stdout/stderr logs land; default <SolutionPath>/notes/logs.

.PARAMETER LaunchProfile
    dotnet run launch profile; default Dynamicweb.Host.Suite.

.PARAMETER Framework
    Optional --framework TFM for multi-target hosts (bare `dotnet run` blocks
    on framework ambiguity with no log).

.PARAMETER ReadyTimeoutMinutes
    How long to poll /Admin after a start before failing.

.PARAMETER PortReleaseSeconds
    How long Stop waits for the port's Listen socket to go, and Start waits
    for a stopping (gone or unreadable) owner to release it. Default 30.

.PARAMETER Force
    Override the index-build-in-flight guard (never the ownership check).

.EXAMPLE
    pwsh -NoProfile -File scripts/Restart-DwHost.ps1 -Action Restart -Port 43210 -SolutionPath C:\Dev\my-solution -Reason "AddIn deploy"

.EXAMPLE
    pwsh -NoProfile -File scripts/Restart-DwHost.ps1 -Action Stop -Port 43210 -SolutionPath C:\Dev\my-solution
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Start', 'Stop', 'Restart')]
    [string]$Action,
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $true)][string]$SolutionPath,
    [string]$Reason = "$Action requested",
    [string]$LogDirectory,
    [string]$LaunchProfile = 'Dynamicweb.Host.Suite',
    [string]$Framework,
    [int]$ReadyTimeoutMinutes = 8,
    [int]$PortReleaseSeconds = 30,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$SolutionPath = (Resolve-Path -LiteralPath $SolutionPath).Path
$suiteDir = Join-Path $SolutionPath 'Dynamicweb.Host.Suite'
if (-not (Test-Path $suiteDir)) {
    throw "No Dynamicweb.Host.Suite folder under $SolutionPath — is -SolutionPath the solution root?"
}
if (-not $LogDirectory) { $LogDirectory = Join-Path $SolutionPath 'notes/logs' }
$lockFile = Join-Path $SolutionPath 'notes/host.lock'
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $lockFile) | Out-Null

function Test-IndexBuildInFlight {
    $stateDir = Join-Path $suiteDir 'wwwroot/Files/System/Diagnostics/IndexBuildState'
    if (-not (Test-Path $stateDir)) { return $false }
    foreach ($f in Get-ChildItem $stateDir -Recurse -Filter 'state.json' -ErrorAction SilentlyContinue) {
        try { $s = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { continue }
        if ($s.State -eq 'Running' -and ((Get-Date) - $f.LastWriteTime).TotalMinutes -lt 3) {
            return "$($s.Repository)/$($s.InstanceName) (heartbeat $($f.LastWriteTime))"
        }
    }
    $false
}

# Every Listen socket on the port with its owner: alive or gone, and its command line.
function Get-PortListener {
    foreach ($procId in @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique)) {
        $alive = [bool](Get-Process -Id $procId -ErrorAction SilentlyContinue)
        $cmd = if ($alive) { (Get-CimInstance Win32_Process -Filter "ProcessId=$procId").CommandLine } else { $null }
        [pscustomobject]@{ Pid = $procId; Alive = $alive; Cmd = "$cmd" }
    }
}

# Bounded wait until nothing listens on the port. Returns the listeners still there.
function Wait-PortReleased {
    $deadline = (Get-Date).AddSeconds($PortReleaseSeconds)
    do {
        $left = @(Get-PortListener)
        if ($left.Count -eq 0) { return @() }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    @(Get-PortListener)
}

function Stop-OwnedHost {
    $owners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    if (-not $owners) { Write-Host "Nothing listening on port $Port."; return }
    $build = Test-IndexBuildInFlight
    if ($build -and -not $Force) {
        throw "Index build in flight ($build) — force-killing mid-build corrupts the instance. Wait for it, or pass -Force if the host is genuinely wedged."
    }
    foreach ($procId in @($owners)) {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$procId").CommandLine
        if ($cmd -notlike "*$SolutionPath*") {
            throw "Port $Port is owned by: $cmd — NOT this solution's host. Re-check the port against THIS solution's launchSettings.json; refusing to stop anything."
        }
        if (-not $PSCmdlet.ShouldProcess("pid $procId ($cmd)", 'stop host process')) { continue }
        Write-Host "Stopping pid $procId (ownership verified)."
        Stop-Process -Id $procId
        $deadline = (Get-Date).AddSeconds(45)
        while ((Get-Process -Id $procId -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
        }
        if (Get-Process -Id $procId -ErrorAction SilentlyContinue) {
            Write-Host "pid $procId survived a graceful stop — escalating to -Force."
            Stop-Process -Id $procId -Force
            Start-Sleep -Seconds 3
        }
    }
    # The process exiting is not the port being free: wait for the Listen socket too.
    $left = @(Wait-PortReleased)
    $live = @($left | Where-Object { $_.Alive })
    if ($live.Count -gt 0) {
        throw "Port $Port still has a live listener $PortReleaseSeconds s after the stop: pid $($live[0].Pid) ($($live[0].Cmd)). Stop it or rediscover the port before starting."
    }
    if ($left.Count -gt 0) { Write-Host "Port $Port lists a listener whose process is gone (pid $($left[0].Pid)); treating the port as released." }
}

function Start-OwnedHost {
    $deadline = (Get-Date).AddSeconds($PortReleaseSeconds)
    while ($true) {
        $owners = @(Get-PortListener)
        if ($owners.Count -eq 0) { break }
        $mine = @($owners | Where-Object { $_.Alive -and $_.Cmd -like "*$SolutionPath*" })
        if ($mine.Count -gt 0) { Write-Host "This solution's host already listens on $Port."; return }
        $foreign = @($owners | Where-Object { $_.Alive -and $_.Cmd })
        if ($foreign.Count -gt 0) {
            throw "Port $Port is already owned by: $($foreign[0].Cmd) — NOT this solution. Refusing to start on top of it."
        }
        # Only gone or unreadable owners left: a host that is still stopping. Wait, then re-check.
        if ((Get-Date) -ge $deadline) {
            $stuck = @($owners | Where-Object { $_.Alive })
            if ($stuck.Count -gt 0) {
                throw "Port $Port is held by pid $($stuck[0].Pid) whose command line is unreadable, $PortReleaseSeconds s on. Identify it before starting."
            }
            Write-Host "Port $Port lists a listener whose process is gone; starting anyway."
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $PSCmdlet.ShouldProcess("$suiteDir on port $Port", 'start host')) { return }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outLog = Join-Path $LogDirectory "host-out-$ts.log"
    $errLog = Join-Path $LogDirectory "host-err-$ts.log"
    foreach ($v in $outLog, $errLog, $LaunchProfile, $Framework) {
        if ("$v" -match '["%^&|<>]') { throw "'$v' carries a character cmd.exe would interpret; use a plain path or profile name." }
    }
    $dotnet = "dotnet run --launch-profile `"$LaunchProfile`""
    if ($Framework) { $dotnet += " --framework `"$Framework`"" }
    $cmdLine = "`"$dotnet 1> `"$outLog`" 2> `"$errLog`"`""
    # why: a shell launch (no -Redirect* parameters) hands the child none of this process's
    # handles, so a caller reading our stdout is not held open for the host's lifetime.
    $hostPid = (Start-Process -FilePath $env:ComSpec -ArgumentList '/d', '/s', '/c', $cmdLine `
            -WorkingDirectory $suiteDir -WindowStyle Hidden -PassThru).Id
    Write-Host "Started launcher pid $hostPid, logs: $outLog"

    $deadline = (Get-Date).AddMinutes($ReadyTimeoutMinutes)
    do {
        Start-Sleep -Seconds 5
        $listening = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue).Count
        if ($listening -gt 0) {
            try {
                $r = Invoke-WebRequest -Uri ('https://localhost:' + $Port + '/Admin') `
                    -SkipCertificateCheck -SkipHttpErrorCheck -TimeoutSec 20
                if ($r.StatusCode -in 200, 302) { Write-Host 'Host up (/Admin answers).'; return }
            }
            catch { }
        }
    } while ((Get-Date) -lt $deadline)
    throw "Host did not answer /Admin within $ReadyTimeoutMinutes minutes — read $outLog / $errLog."
}

# ---- lock: serialize restarts between agents; stale after 10 minutes --------
if (Test-Path $lockFile) {
    $age = (Get-Date) - (Get-Item $lockFile).LastWriteTime
    if ($age.TotalMinutes -lt 10) {
        throw "host.lock held ($([int]$age.TotalMinutes) min old): $(Get-Content $lockFile -Raw). Wait, or delete the lock if its holder is gone."
    }
    Write-Host "Stale lock ($([int]$age.TotalMinutes) min) — taking over."
}
"$(Get-Date -Format o) $Action port=$Port — $Reason" | Set-Content $lockFile -Encoding UTF8

try {
    switch ($Action) {
        'Stop'    { Stop-OwnedHost }
        'Start'   { Start-OwnedHost }
        'Restart' { Stop-OwnedHost; Start-OwnedHost }
    }
    $coordination = Join-Path $SolutionPath 'notes/coordination.md'
    if (Test-Path $coordination) {
        Add-Content $coordination "- $(Get-Date -Format o) Restart-DwHost ${Action}: $Reason"
    }
    exit 0
}
finally {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}
