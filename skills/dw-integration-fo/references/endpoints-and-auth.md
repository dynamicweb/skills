# Endpoints and authentication

## Contents

- [The identity](#the-identity)
- [F&O side: map the app to a user](#fo-side-map-the-app-to-a-user)
- [The endpoint collection](#the-endpoint-collection)
- [The S2S authentication, parameter by parameter](#the-s2s-authentication-parameter-by-parameter)
- [Testing: what each answer means](#testing-what-each-answer-means)
- [Building before the secret exists](#building-before-the-secret-exists)
- [Moving the connection between environments](#moving-the-connection-between-environments)

## The identity

The Integration Framework talks to F&O as an **Entra application** with a client secret (OAuth 2.0 client
credentials, "service-to-service"). A delegated sign-in (device code, a user's browser session) is fine for a
person reading `$metadata` from a script, but a scheduled activity cannot use it: the endpoint's authentication
add-in takes a client id and a secret.

Minimum facts to collect before building anything:

| Fact | Where it comes from |
|---|---|
| Tenant id | the Entra tenant that owns the F&O environment |
| Application (client) id | the app registration that will call F&O |
| Client secret | created on that app registration; stored in a vault, never in a file |
| Environment URL | `https://<env>.operations.dynamics.com` (the resource; see below for the trailing slash) |
| Legal entity code | the `dataAreaId` every company-scoped job pins |

## F&O side: map the app to a user

A token for the environment is not access. The app has to be listed in **System administration > Setup >
Microsoft Entra applications**, bound to an F&O user whose security roles can read (and, for the order export,
write) the entities. Until then every entity read answers **403** while `/data/$metadata` still answers 200 with
the same token. This mapping lives in the environment's database: a database refresh or a copy from another
environment removes it.

Verify it outside the platform first, with one token and one entity read against the company you will pin
(the discovery skill's `Get-FoToken.ps1` does the token; a single `GET /data/CustomersV3?cross-company=true&
$filter=dataAreaId eq '<CODE>'&$top=1` does the read).

## The endpoint collection

One **collection** per environment, one **endpoint** per entity set, created with MCP `save_integration_endpoint`
(`collectionName` creates the collection on first use):

| Field | Value |
|---|---|
| `url` | `https://<env>.operations.dynamics.com/data/<EntitySet>` with no query string |
| `parameters` | the query options as `name=value` strings: `cross-company=true`, `$filter=dataAreaId eq '<CODE>'`, `$select=<the staged columns>` |
| `requestType` | `GET` for sources. An OData **destination** uses the same endpoint shape; the provider issues the writes itself |
| `authenticationAddInType` | `Dynamicweb.DataIntegration.EndpointManagement.AuthenticationAddIns.S2SEndpointAuthenticationAddIn` |

Each `save_integration_endpoint` that carries authentication parameters creates **its own authentication
record**; endpoints do not share one unless you give the collection an authentication and leave the endpoint's
empty. Per-endpoint authentication is the shape that has been run; rotating the secret then means re-saving
every endpoint, which is what a runner script is for.

Keep `$select` on every read endpoint: F&O entities are wide (`CustomersV3` has about 300 properties), and the
payload and the log both shrink by an order of magnitude.

## The S2S authentication, parameter by parameter

The add-in's parameters are addressed by their **labels**, and the save call rejects anything else, listing the
valid ones:

| Label | Value |
|---|---|
| `Directory (tenant) Id` | tenant id |
| `Application (client) Id` | client id |
| `Client Secret` | the secret, resolved from the vault into the calling process only |
| `URL (only for On-Premise server connection or custom scope)` | the environment root **with a trailing slash**, `https://<env>.operations.dynamics.com/`; this is the token resource |

The secret is encrypted at rest and never returned: `get_integration_endpoints` reports only the authentication
name and type. A runner that attaches authentication reads the secret from the vault, passes it in the save
call, and drops the variable; it never logs the request body.

## Testing: what each answer means

MCP `test_integration_endpoint` executes the endpoint's request once with its authentication.

| Answer | Meaning | Next step |
|---|---|---|
| `succeeded: true` with rows | the whole chain works for this entity and company | build or run the activity |
| `succeeded: true`, empty `value` | authentication fine, the filter matches nothing | check the `dataAreaId` exists and holds data (census) |
| `Unauthorized` | no token, or a token the environment rejects | the Entra error is **not** surfaced here: request a token directly to see the `AADSTS` code (bad secret, wrong tenant, app not consented) |
| `Forbidden` | token accepted, app not mapped to an F&O user, or the user's roles cannot read the entity | fix the *Microsoft Entra applications* mapping or the roles |
| hangs | the entity carries a binary/image column and `$select` is missing | add `$select` |

The OData source's own readiness probe, run at the start of every job, is `GET <entity>?$top=1` without the
endpoint's other parameters. On failure it retries **ten times** with a growing delay (5, 15, 30, 45, 60, 180, 300 s
and on), so a job queued against a broken credential blocks the run queue for many minutes before it fails. Test
the endpoint first; never discover a credential problem by running a job.

## Building before the secret exists

MCP `create_integration_activity` validates the OData provider by calling the endpoint: without authentication it
answers *Credentials not set for endpoint*, with a placeholder secret *Endpoint returned statuscode:
Unauthorized*. Nothing OData-backed can be created over MCP until the credential works.

What can be built before it:

- the endpoint collection and every endpoint (URL, query options, no authentication);
- the staging tables and every stage-2 view (SQL);
- every stage-2 and export-marking activity whose source is the Dynamicweb provider (MCP);
- the OData activities themselves, as generated job files
  ([`fo_job_files.py`](../scripts/fo_job_files.py), [staging-pattern.md](staging-pattern.md#job-files-for-odata-activities));
- a runner that attaches the authentication from the vault, tests the connection endpoint, and runs the chain.

The day the secret lands, the runner is the only step left.

## Moving the connection between environments

A dev-to-staging promotion re-creates the endpoint collection with the target environment's URL and secret; the
activities reference endpoints by **id**, so either keep the ids stable (create the endpoints in the same order)
or re-point each activity's `Predefined endpoint` / `Destination endpoint` parameter with MCP
`update_integration_activity`. Company pins travel inside the endpoint parameters, so re-pointing a demo to
another legal entity is an endpoint save, not an activity edit.
