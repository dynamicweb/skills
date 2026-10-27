# Access and environment inventory

Open the BC admin center at `https://businesscentral.dynamics.com/<tenant-id>/admin` using
the authorised browser session. Record each candidate's environment name, type, region,
application version, state, owner and active users. Existing production or shared demo
environments remain read-only during discovery. Obtain the owner's environment selection
before seeding, installing an extension or enabling exports.

Collect tenant GUID, environment name, application client ID and company GUIDs. Distinguish
the administrator's delegated browser identity from the scheduled application's identity.
An admin-center role may allow environment administration while a company read still fails.
Follow [`dw-integration-bc`](../../dw-integration-bc/SKILL.md) for S2S configuration.

Run [Get-BcInventory.ps1](../scripts/Get-BcInventory.ps1). It imports the BC read-only module
from `dw-integration-bc`, an explicit bundle dependency. Set non-secret connection parameters
or `BC_TENANT_ID` and `BC_ENVIRONMENT`; credentials come only from `BC_ACCESS_TOKEN` or
`BC_CLIENT_ID` plus `BC_CLIENT_SECRET`. It does not acquire a delegated sign-in or create an app.

Without credentials, produce the access checklist and preserve the observed sign-in state.
Do not describe an inaccessible environment as absent, create a replacement tenant, or treat
a historical trial URL as a currently available sandbox.

Done: an owner-selected environment, accessible company GUIDs, application permissions and a
successful company-scoped entity read are on record, or their individual gaps have owners.

Sources: [admin center](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/tenant-admin-center),
[environment inventory](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/tenant-admin-center-environments).
