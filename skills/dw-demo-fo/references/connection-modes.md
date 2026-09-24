# Connection modes: OData-only, and the parked F&O plugin

## Contents

- [The standing choice: OData-only](#the-standing-choice-odata-only)
- [Access for the scripts](#access-for-the-scripts)
- [Access for the DW jobs](#access-for-the-dw-jobs)
- [Parked: the F&O plugin package](#parked-the-fo-plugin-package)
- [Deploying the plugin package, when it is unparked](#deploying-the-plugin-package-when-it-is-unparked)
- [The Dataverse guest-access wall](#the-dataverse-guest-access-wall)
- [Plugin mode in a multi-company sandbox](#plugin-mode-in-a-multi-company-sandbox)
- [Saying which one is on screen](#saying-which-one-is-on-screen)

## The standing choice: OData-only

| | **OData-only (the mode in use)** | **F&O plugin (parked)** |
|---|---|---|
| Mechanism | The DW OData provider reads and writes F&O data entities | An X++ model deployed inside F&O answers XML requests from DW natively |
| What DW needs | An Entra app + the endpoint and activities, all configurable from DW Admin | The same, plus the plugin installed and configured in F&O |
| What F&O needs | The app registered and bound to a user with the right roles | A deployable package installed into the environment (tenant-wide) |
| Data freshness | Scheduled or on demand; near-live for small pulls | Near-live pricing and stock by design |
| Throttling exposure | F&O's service-protection limits | Sidesteps the OData layer |
| Effort to stand up | Configuration only | An F&O deployment project per environment |

Every demo runs OData-only: it needs no F&O developer, no package and no downtime, and it fails in ways that
are visible and fixable from DW Admin. The plugin exists for volume and freshness constraints a demo does not
have, and installing it changes every company in the shared sandbox. It stays parked until the environment
owner rules otherwise; the material below keeps the lessons already paid for.

The jobs themselves (endpoint, OData provider, activities, mappings) are built with
[`dw-integration-framework`](../../dw-integration-framework/SKILL.md); field ownership is
[`dw-integration-erp`](../../dw-integration-erp/SKILL.md). This skill adds exactly one thing on top: every job
is pinned to the demo's `dataAreaId` ([dw-wiring.md](dw-wiring.md)).

## Access for the scripts

The scripts share one module, [`Fo.Api.psm1`](../scripts/Fo.Api.psm1), that takes its connection from
parameters first, then from the environment: `FO_ENV_URL`, `FO_TENANT_ID`, `FO_CLIENT_ID`, `FO_TOKEN_CACHE`,
`FO_TOKEN`. Two identities work:

| Identity | When | How |
|---|---|---|
| **S2S app** (client credentials) | the tenant owner registered an app for the demos | the secret comes from `$env:FO_CLIENT_SECRET` (set from a vault for the session), never from a file or a parameter. The app is listed in F&O under *System administration > Setup > Microsoft Entra ID applications*, bound to a user with the roles the scripts need |
| **Delegated, device code** | no app secret is available to this machine, or the work should run as the consultant's own F&O user | sign in once with [`Connect-FoDeviceCode.ps1`](../scripts/Connect-FoDeviceCode.ps1): the refresh token is stored with Windows DPAPI for the current user at `-CachePath`, and every later token renewal rotates it. The client id is a public client app allowed the F&O delegated permission |

Either way the module renews the access token five minutes before it expires, because a copy or a repair run
outlives a one-hour token, and it honours `Retry-After` on HTTP 429. Keep the cache file outside any repository
and any synced folder, and delete it to sign out.

The identity's F&O user has a **default company**. Do not rely on it; every script names the company, and every
count uses `cross-company=true` plus the `dataAreaId` filter.

## Access for the DW jobs

- An Entra app registration (client secret or certificate), registered in F&O under *System administration >
  Setup > Microsoft Entra ID applications* and bound to a user with the roles the jobs need: **write** roles
  where the demo pushes DW to F&O, not just read.
- Token scope is `https://<env>.operations.dynamics.com/.default`.
- The secret goes into the DW endpoint configuration through the admin or the API, never into a file in the
  demo folder.

## Parked: the F&O plugin package

The plugin is an X++ model shipped as a **deployable package**. Inspect the zip before planning anything: a
package built for one application version carries its platform build in `HotfixInstallationInfo.xml`
(`MetadataModuleList`, `PlatformVersion`, `IsCompatibleWithSealedRelease`). Deploying a package built on an
older application version into a newer environment usually works inside the same major line, but "usually" is
not "verified": a recompile against the target version is the clean path, and it needs the F&O development
tooling.

The plugin is a **tenant-wide** artefact: installing it affects every company in the sandbox, and it is exactly
the class of thing [company-profile.md](company-profile.md) says cannot be tailored per demo.

## Deploying the plugin package, when it is unparked

Which route applies depends on the environment class:

| Environment | Route |
|---|---|
| Unified (Power Platform-managed) sandbox | Power Platform CLI: `pac package deploy --package-type erp` |
| Classic cloud-hosted / LCS-managed | Lifecycle Services asset library > apply the deployable package |
| Unified developer environment | Visual Studio D365 extension: *Deploy models* / *Build models* with **Deploy to connected online environment** |

Unified sandbox, CLI route:

```powershell
# 1. Tooling
dotnet tool install --global Microsoft.PowerApps.CLI.Tool     # provides `pac`

# 2. Sign in to the tenant that owns the environment
pac auth create --deviceCode --tenant <tenant-id> --environment https://<org>.crm.dynamics.com

# 3. Deploy the package
pac package deploy --package-type erp --package "<path-to-deployable-package>.zip" `
                   --db-sync Full --logConsole --logFile .\pac-deploy.log
```

Flags worth knowing: `--build-type Full|Incremental|Delete`, `--release-type Dev|Release` (Release forces a full
database sync server-side), `--db-sync None|Full|Module|Incremental` (`Module` needs `--modules`).

If `pac` refuses the legacy package format, convert it first: `ModelUtil.exe -convertToUnifiedPackage
-file=<package>.zip -outputpath=<dir>` produces a `TemplatePackage.dll` plus a `PackageAssets` folder, and
`pac package deploy --logConsole --package <dir>\TemplatePackage.dll` deploys that. `ModelUtil.exe` ships inside
the F&O development tooling's package directory; a machine with only the CLI installed does not have it.
Conversion fails when the original package contains more than one version of the same model.

Verification after deploy: the *Finance and Operation Package Manager App* in the paired Dataverse
organization has an **Operation History** with downloadable operation logs; on the F&O side the model appears
under the installed-models view, and the plugin's own setup/parameters page becomes reachable.

## The Dataverse guest-access wall

`pac` talks to the environment's **Dataverse** organization, and new Dataverse environments restrict Microsoft
Entra B2B guest users by default (`restrictGuestUserAccess = true`). A guest account (a consultant signed in to
a customer's or partner's tenant) authenticates fine and then gets:

```
Guest user access is restricted in the organization.  [HTTP 403 (Forbidden)]
```

on every Dataverse-bound call, `pac package deploy` included. Two facts make this a hard stop rather than a
puzzle:

- The restriction applies regardless of the guest's security role, System Administrator included.
- Reading or changing the flag is itself a Dataverse call, so **a guest cannot lift it for themselves**
  (`pac env list-settings` / `pac env update-settings` return the same 403). Admin-API calls such as
  `pac env list` still work, which makes the failure look inconsistent; it is not.

Either fix must be made by a **member** admin of the tenant that owns the environment:

1. **Allow guests on that environment**: Power Platform admin center > *Security Hub* > *Identity and access* >
   *Guest access* > select the environment > **Off (Allowed)** > Save. Equivalent CLI:
   `pac env update-settings --environment <org-url> --name restrictGuestUserAccess --value false`.
2. **Or register the app as a Dataverse application user**: environment > *Settings* > *Users + permissions* >
   *Application users* > **+ New app user** > add the Entra app > root business unit > System Administrator.
   The deployment then runs as the app (`pac auth create --applicationId <client-id> --clientSecret
   <from the vault> --tenant <tenant-id>`) and the guest restriction stays on.

Route 2 is the better ask when the tenant owner would rather not allow guests at all.

The admin center itself is not a workaround: a guest authenticates against their **home** tenant, and the
admin center commonly lands them in that home directory with no way to reach the other tenant's environment.
Hand the change to a member admin rather than hunting for a UI path.

## Plugin mode in a multi-company sandbox

- The plugin's parameters (*Dynamicweb parameters*, Accounts receivable > Setup) are **company-scoped**: one
  install serves several demo companies, each with its own default language, country, group hierarchy and
  order source code. Set them in every demo company before the first call; the service throws on an empty
  default language before it reads the request.
- The integration identity's **default company** decides which company answers a plugin call that carries no
  company; the same pin rule as the OData jobs applies ([dw-wiring.md](dw-wiring.md)).
- **Post-install gate, in this order:** `GET /soap/services/UserSessionService?wsdl` (SOAP host alive), then
  `GET /soap/services/DWService?wsdl`. `200` = proceed (assign the `DWServiceAccount` role, run the
  `DWServiceTest` menu item, then the real SOAP call with the SoapAction taken from the WSDL); `404` = the
  service group did not deploy (re-run the database sync); `500` = the SOAP host cannot compile the WCF contract
  for this service group. That last state is not an auth, company or request problem: the JSON host
  (`POST /api/services/DWService/DWService/Process` with `{"_request":"<GetEcomData></GetEcomData>"}`) still
  runs the same X++, which proves the model. A unified sandbox exposes no AOS log for the inner compiler error:
  diagnose on a developer environment built on the same application version, and never "fix" it by renaming the
  service or service group, because DW's SoapAction is pinned to the service's external name and a rename turns
  the 500 into a contract-filter mismatch.

## Saying which one is on screen

The demo runs OData-only. If someone asks about live pricing, the honest answer is that the near-live path
exists as a deployable package and is an F&O deployment project, not a switch in DW Admin.
