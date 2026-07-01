---
name: dw-setup-install
type: flow
group: setup
description: Install Dynamicweb Swift 2 from scratch — download and import the database, extract files, install the temporary MCP add-ins payload, and write the first-run bootstrap manifest. Triggers: a fresh or empty Dynamicweb instance needs Swift 2 installed, bootstrap the MCP connection on a new install, download and import the Swift 2 baseline. Non-triggers: install exists and needs business configuration -> dw-setup-config; presales demo host scaffolding, TLS, and MCP wiring -> the presales demo bundle.
---

# DynamicWeb Swift 2 Installer

## Objective
Go from "fresh DynamicWeb 10 application" to "fully working Swift 2 website" by downloading
and installing the latest Swift 2 packages from the official Dynamicweb downloads portal.

If the workflow continues into MCP bootstrap, the Dynamicweb MCP server must be added to the
config used by the current agent before the environment is considered ready.

If MCP attachment fails, the agent must pause, tell the user exactly what to update, and resume
after the config has been fixed and connectivity has been verified.

## What Gets Installed
The Swift 2 packages (downloaded from `https://doc.dynamicweb.com/downloads/swift`) include:

1. **Database (.bacpac)** - complete Swift 2 solution: website, pages, navigation, shop,
   checkout flow, account pages, item types, color schemes, order flows, demo products
2. **Files folder** - Swift 2 templates (Razor .cshtml), CSS, JS, images, grid layouts
3. **Demo data** - product images and sample content
4. **Custom.Mcp add-ins** - copied into `Files/System/AddIns/Installed/Custom.Mcp.10.0.0`
5. **Bootstrap manifest** - one-time secret file at `Files/System/mcp-bootstrap.json`

After install you have a complete, working e-commerce website with the MCP bootstrap handoff prepared.

---

## Happy Path - Automated Installation

### Prerequisites
- `sqlpackage` CLI tool: `dotnet tool install -g microsoft.sqlpackage`
- SQL Server instance running (Express is fine)
- Internet access to download from `doc.dynamicweb.com`

### Run the Script
```powershell
powershell -ExecutionPolicy Bypass -File "scripts/install-swift2.ps1"
```

### Custom server/database
```powershell
powershell -ExecutionPolicy Bypass -File "scripts/install-swift2.ps1" `
  -TargetServer ".\SQLEXPRESS" `
  -TargetDatabase "mybusiness" `
  -FilesPath "C:\MyProject\wwwroot\Files"
```

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| TargetServer | `localhost` | SQL Server instance |
| TargetDatabase | `swift2` | Database name to create |
| IntegratedSecurity | `true` | Use Windows auth |
| SqlUser / SqlPassword | empty | SQL credentials |
| FilesPath | `C:\DwSolutions\Swift2\Files` | Where to put the Files folder |
| CustomMcpAddInsSourcePath | bundled skill asset | Override source for the MCP add-ins payload |
| BootstrapSecretTtlMinutes | `30` | How long the bootstrap secret stays valid |
| SkipDownload | false | Skip download if files already exist |

### What the script does
1. Downloads the latest Swift 2 package set from `doc.dynamicweb.com`
2. Extracts the `.bacpac` from the database ZIP
3. Runs `sqlpackage /Action:Import` to create the database
4. Extracts Swift 2 files to the target `FilesPath`
5. Extracts demo product images
6. Copies the temporary `Custom.Mcp` add-ins into `Files/System/AddIns/Installed/Custom.Mcp.10.0.0`
7. Writes a one-time bootstrap manifest to `Files/System/mcp-bootstrap.json`
8. Writes `GlobalSettings.Database.config` with the database connection

---

## Degraded Path - Manual Installation

If the automated script fails (no sqlpackage, download blocked, wrong SQL Server), follow these manual steps:

1. **Install DynamicWeb 10 application**:
   ```
   dotnet new install Dynamicweb.ProjectTemplates
   mkdir MyProject && cd MyProject
   dotnet new dw10-suite --name Dynamicweb.Host.Suite
   ```

2. **Download Swift 2** from `https://doc.dynamicweb.com/downloads/swift`:
   - Database ZIP -> extract `.bacpac`
   - Files ZIP -> extract to `wwwroot/Files/`
   - Demo data ZIP -> extract to `Files/Images/`

3. **Import database** via SSMS "Import Data-tier Application" or:
   ```
   sqlpackage /Action:Import /TargetServerName:localhost /TargetDatabaseName:swift2 /SourceFile:swift2.bacpac
   ```

4. **Copy Custom.Mcp add-ins** into `Files/System/AddIns/Installed/Custom.Mcp.10.0.0`

5. **Configure database**: edit `GlobalSettings.Database.config` in the Files folder

6. **Start the application on .NET 10**: `dotnet run --framework net10.0`

7. **Install license** at `/admin`
   - For a free trial, prefer:
   ```powershell
   powershell -ExecutionPolicy Bypass -File "scripts/activate-free-trial.ps1" `
     -DynamicwebUrl "https://localhost:5001" `
     -FilesPath "C:\MyProject\wwwroot\Files"
   ```
   - Continue only once `/admin` no longer redirects to `/admin/license`

8. **Bootstrap MCP**: `POST /admin/mcp/bootstrap` with the secret from `Files/System/mcp-bootstrap.json`

---

## After Installation - Bootstrap and Attach

### Happy Path (auto-attach)
Run the bootstrap-and-attach script:
```powershell
powershell -ExecutionPolicy Bypass -File "scripts/bootstrap-and-attach.ps1" `
  -DynamicwebUrl "https://localhost:5001" `
  -FilesPath "C:\DwSolutions\Swift2\Files" `
  -ConfigurationName "My Business MCP"
```
This bootstraps, persists credentials, writes MCP config, and validates connectivity.
For agent-driven setup, this means writing the Dynamicweb MCP server into the config used by the
current agent and verifying the connection before continuing.

This step is mandatory. Treat the installation as ready for agent use only once the MCP server
entry exists in the active agent config.

If the script cannot attach automatically, stop the automation, explain the exact manual config
change needed for the current agent, and resume only after the server entry is present and working.

### Degraded Path (manual attach)
1. Read the secret from `Files/System/mcp-bootstrap.json`
2. Call bootstrap manually:
   ```bash
   curl -X POST https://localhost:5001/admin/mcp/bootstrap \
     -H "Content-Type: application/json" \
     -d '{"secret":"...","configurationName":"My MCP","permissionPreset":"All"}'
   ```
3. Copy the returned bearerToken
4. Add the Dynamicweb MCP server to the config used by the current agent
5. Verify the active agent can call the MCP endpoint before continuing

Agent-specific expectation:
- in Codex, update `.codex/config.toml`
- in Claude Code, update the config file Claude uses for MCP servers

If this manual step is required, pause the workflow and tell the user to come back after updating
the config. Resume only after verifying the entry exists and the agent can connect.

---

## Verification

After installation, verify with these checks:
1. `GET /admin` returns a Dynamicweb admin page
2. the host is running on `net10.0` before testing MCP routes
3. `GET /admin/mcp` returns `401 Unauthorized`
4. `HEAD /admin/mcp/bootstrap` returns `405 Method Not Allowed`
5. `GetAreas` returns at least one area with a Swift 2 LayoutTemplate
6. `GetShops` returns at least one shop
7. `GetPagesByArea` returns the standard Swift 2 page structure
8. the config used by the current agent contains the Dynamicweb MCP server entry

---

## Error Handling

### `sqlpackage` not found
```powershell
dotnet tool install -g microsoft.sqlpackage
```
Then restart the terminal.

### Database already exists
Drop it first:
```powershell
sqlcmd -S localhost -Q "DROP DATABASE [swift2]"
```
Or use a different database name.

### Download fails
Visit `https://doc.dynamicweb.com/downloads/swift` manually and download the packages.

### Bootstrap secret expired
Use `reset-mcp-bootstrap-manifest.ps1` when you only need a fresh secret and do not want to rerun the full installer.

### `/admin/mcp` returns `404`
Confirm both of these before debugging anything else:
```powershell
dotnet run --framework net10.0
```
- `Custom.Mcp` is deployed under `Files/System/AddIns/Installed/Custom.Mcp.10.0.0`
- `GET /admin/mcp` returns `401` and `HEAD /admin/mcp/bootstrap` returns `405`

