# Pre-demo check: every surface the demo uses, not the storefront alone

Run this before every live demo or recording, and again after anything that can take a dependency
away from a running host: a host or VM restart, a machine reinstall, a database restore, a licence
change. It takes a few minutes and is read-only apart from the one form submission.

## Contents

- [Why the storefront is not enough](#why-the-storefront-is-not-enough)
- [1. Storefront, admin and MCP in one run](#1-storefront-admin-and-mcp-in-one-run)
- [2. Mail: the listener, then one real form submission](#2-mail-the-listener-then-one-real-form-submission)
- [Reading the result](#reading-the-result)

## Why the storefront is not enough

A storefront that answers 200 proves the web server and the frontend, nothing else. Two failures leave
it answering while the demo is already broken:

- **The licence is gone.** After a machine reinstall or a lapsed trial, the storefront keeps serving
  while `/Admin/` and `/admin/mcp` both answer `302` to `/admin/license`. The back-office half of the
  demo is lost and every MCP client fails. Seen on several hosts on the same day after one reinstall.
  Installing the licence again restores the admin and MCP at once; clients that poll MCP resume by
  themselves.
- **The mail target is gone.** A demo host that sends its mail to a local listener (`127.0.0.1:25`, the
  usual offline setting, see [`dw-setup-config`](../../dw-setup-config/SKILL.md) "SMTP") loses that
  listener when the machine is reinstalled. Every page renders; the first form that sends mail ends on
  an exception, in front of the audience.

## 1. Storefront, admin and MCP in one run

Run the host readiness harness with the demo's MCP key, so the handshake and tool count run too:

```powershell
pwsh -NoProfile -File ../../dw-setup-install/scripts/Test-DwHostReady.ps1 `
    -BaseUrl "https://<demo-host>" -McpToken $env:DW_MCP_TOKEN -OutFile notes/pre-demo-check.md
```

[`Test-DwHostReady.ps1`](../../dw-setup-install/scripts/Test-DwHostReady.ps1) reports the storefront,
`/admin` licensed (not landing on `/admin/license`), the `/admin/mcp` gate, the MCP `initialize`
handshake, a tool count above 200 and two data reads. Without the MCP key the handshake rows are
skipped, which is not a pass: the check is incomplete until they ran.

`admin licensed` failing with the storefront passing is the licence case above. Install the licence
(the trial step in [`scaffold.md`](scaffold.md) §3 on a local host), then run the harness again; do
not start the demo on the first green storefront.

## 2. Mail: the listener, then one real form submission

Read the mail server the host sends to (`/Globalsettings/System/MailServer/Server` and its port, or
Settings > System > Web and HTTP > SMTP), then prove something accepts mail there:

```powershell
$smtpHost = '127.0.0.1'; $smtpPort = 25          # what the host's settings name
$c = [System.Net.Sockets.TcpClient]::new()
try {
    $c.Connect($smtpHost, $smtpPort)
    $banner = [System.IO.StreamReader]::new($c.GetStream()).ReadLine()
    "SMTP listener: $banner"                     # expect a line starting with 220
} catch { "NO SMTP listener on ${smtpHost}:${smtpPort}: $($_.Exception.Message)" }
finally { $c.Dispose() }
```

A listener alone is not the proof. Submit one real form the demo uses (a contact, quote or request
form; the one in the storyline when there is one) through the browser, and assert:

- the page lands on the form's receipt or thank-you page, not on an error;
- the message reached the listener (its log or drop folder) or the form's own submission list.

**A listener started by hand does not survive a reboot.** A small SMTP sink run from a shell for one
session is gone after the next restart, and the check above is the only thing that notices. Register
the sink as a service or a start-up task on a demo machine, or run this check after every restart.

## Reading the result

The host is ready for the demo when every harness row passes with the MCP key given and the form
submission ended on its receipt page. Anything else is a stop: fix it and run the check again. Write
the harness report and the form result into the demo's `notes/` so the next session can see when the
host was last proven.
