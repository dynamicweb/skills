# Endpoints and authentication

Collect tenant GUID, environment name and type, company GUIDs, BC version, extension versions,
application client ID and secret reference. Obtain the secret from the environment or a vault
into process memory. Keep tokens and endpoint authentication payloads out of evidence files.

## Contents

- [BC identity](#bc-identity)
- [Installed posting dependencies](#installed-posting-dependencies)
- [Read the actual surfaces](#read-the-actual-surfaces)
- [Integration Framework endpoint](#integration-framework-endpoint)
- [Failure interpretation](#failure-interpretation)

## BC identity

For unattended reads, use Entra client credentials with scope
`https://api.businesscentral.dynamics.com/.default` and token endpoint
`https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token`.
Grant the BC `API.ReadWrite.All` application permission and admin consent. Add
`Automation.ReadWrite.All` only if company automation is needed. Enable that same client ID
in BC's **Microsoft Entra applications** page with company-scoped permission sets for the
required objects. Applications cannot use `SUPER`.

The BC ERP plug-in unit also needs its installed permission set, documented as
`DYNAMICWEBPERMISSION`; verify it against the extension in that environment. A token alone
does not prove either permission layer.

Assign each role separately in every allowed company and inspect the complete permission grid
before enabling writers. A blank company scope broadens access beyond the selected company.
Use the denied object and read/insert/modify/indirect operation to identify a narrower missing
permission; a successful item read does not establish customer creation, price access or financial
posting rights. Retain unrelated assignments. Prove the companies allowlist and an explicit
request to a known excluded company: BC may return HTTP400 with `Internal_DataNotFoundFilter`
and an access-denied message rather than HTTP403. Record the error body as well as the status.

Keep Admin Center, Automation and unrelated Graph permissions outside an ordinary commerce
integration unless their specific administration operation is authorised. For a custom extension,
review its objects and executable permission surface through
[extension-contracts.md](extension-contracts.md) before assigning a financial role.

## Installed posting dependencies

Native sales posting executes installed subscribers as the same application identity. A missing
read on an installed dependency is not evidence that the integration needs a broad financial
role. Resolve the exact table, operation, extension version and public native permission set,
then assign its narrow role separately in each authorised supplying company.

For BC29 E-Document Core, native permission set `6101 "E-Doc. Core - Read"` includes read access to
`TableData 6121 "E-Document"` and the dependency's execution surface. It is a narrower candidate for
an E-Document read failure than a broad business/admin role. Verify the installed role before
assignment. Reusing that native read role also avoids adding an extension dependency merely to
name its table; a PTE that does reference the table needs the actual installed dependency and
symbols in a new reviewed build. Continue testing native post and correction, because another
subscriber can require a different exact operation. Keep direct and indirect permissions distinct.

A first native posting can also require creation of a technical cost-staging row. On a
measured BC29 path, `TableData 5804 "Avg. Cost Adjmt. Entry Point"` needed explicitly approved
application R/I/M, without Delete; indirect-only access and a codeunit elevation did not satisfy
that call chain. Keep financial-ledger writes indirect and company scope narrow. Inspect the
installed path, approve the exact operation, then repeat application-identity post and rollback
proof. An existing administrator's successful post does not establish the application's rights.

Source: [Microsoft BC29 E-Document Core read role](https://github.com/microsoft/BCApps/blob/releases/29.0/src/Apps/W1/EDocument/App/Permissions/EDocCoreRead.PermissionSet.al).

## Read the actual surfaces

| Surface | URL or configuration | Proof |
|---|---|---|
| BC standard API | `https://api.businesscentral.dynamics.com/v2.0/<tenant>/<environment>/api/v2.0/companies` | Company list with the intended GUID |
| BC company API | Same root plus `/companies(<guid>)/items?$top=1` | An entity read, including empty/denied distinction |
| BC published OData page | Copy the URL from BC **Web Services**, including the selected company | Metadata and one row from that page |
| BC ERP plug-in unit | Copy its SOAP URL from **Web Services** for the selected company | A saved, supported request returns expected XML tables |
| Commerce Management API | `/admin/api/BC*`, using a Commerce API token | PIM connector only; a separate identity and data direction |

Select a GUID from `companies`, never the first returned company. API v2 company URLs use
GUIDs. Published OData page URLs may use escaped company names; use the published URL and
retain the GUID in the local connection manifest. Capture each custom publisher/group/version
and `$metadata` independently; API v2 metadata does not describe arbitrary custom APIs.

## Integration Framework endpoint

Use MCP `save_integration_endpoint` or **Integration > Endpoints**. Create a collection per
tenant/environment; make the company visible in every request name. For authentication select
`Dynamicweb.DataIntegration.EndpointManagement.AuthenticationAddIns.S2SEndpointAuthenticationAddIn`:

| Parameter label | Value |
|---|---|
| `Directory (tenant) Id` | Tenant GUID |
| `Application (client) Id` | Client GUID |
| `Client Secret` | Resolved secret, never logged |
| `URL (only for On-Premise server connection or custom scope)` | `https://api.businesscentral.dynamics.com` |

For SOAP select **Connects to standard Dynamicweb ERP service** so the platform supplies
the SOAP envelope, POST method and headers. For a live request also select **Use in Live
Integration**. For OData use the copied page URL and its own source schema.
MCP `test_integration_endpoint` proves that request only. Re-read the entity and company.

## Failure interpretation

- Token failure: inspect client, tenant, consent and secret expiry without logging the secret.
- HTTP 403: inspect BC application object permissions and company scope.
- HTTP 404: verify environment, company, installed extension and published page/API path.
- HTTP 200 with no rows: retain the empty result; check company selection and population.
- HTTP 429/503: bounded retry, honour numeric `Retry-After`, preserve the failed run.

The [read-only module](../scripts/Bc.Api.psm1) uses `BC_TENANT_ID`, `BC_ENVIRONMENT`,
`BC_CLIENT_ID`, `BC_CLIENT_SECRET`, or an already acquired `BC_ACCESS_TOKEN`. Explicit
non-secret parameters take precedence. It does not register apps or alter permissions.

Sources: [Microsoft S2S](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/automation-apis-using-s2s-authentication),
[endpoint shapes](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/endpoints-apis-for-dynamics),
[S2S add-in labels](https://doc.dynamicweb.dev/api/Dynamicweb.DataIntegration.EndpointManagement.AuthenticationAddIns.S2SEndpointAuthenticationAddIn.html),
[plug-in setup](https://doc.dynamicweb.dev/manual/dynamicweb10/integration/guides/s2s-guide.html).
