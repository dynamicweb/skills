# DW wiring: pointing a Dynamicweb demo at exactly one F&O company

## Contents

- [The one rule](#the-one-rule)
- [Pinning a job to the company](#pinning-a-job-to-the-company)
- [Hosted (online-mode) DW installs](#hosted-online-mode-dw-installs)
- [What lands where on the DW side](#what-lands-where-on-the-dw-side)
- [Verifying the wiring, not just the job](#verifying-the-wiring-not-just-the-job)
- [Failure shapes specific to a shared tenant](#failure-shapes-specific-to-a-shared-tenant)

## The one rule

**Every job that touches F&O names the demo's `dataAreaId`.** Without it, F&O answers for the *default company
of the identity the integration authenticates as*; in a shared sandbox that is the donor or whatever company
was set when the app user was created. The job succeeds, rows arrive, counts look reasonable, and the demo is
showing another company's data. There is no error to notice.

This is the inverse of the advice that applies to a dedicated single-company tenant, where cross-company is an
edge case. In a shared demo sandbox it is the default posture.

```
?cross-company=true&$filter=dataAreaId eq '<CODE>'
```

Both halves matter: `cross-company=true` lifts the implicit default-company scope, the `$filter` puts the
intended scope back. One without the other is either the wrong company or every company.

## Pinning a job to the company

Per direction:

| Direction | Where the company goes |
|---|---|
| F&O > DW (products, prices, stock, customers, orders) | On the OData source: the query/filter that carries `cross-company=true` + the `dataAreaId` predicate. Do it on **every** job in the chain, not just the first: a variant or price job reading unfiltered re-introduces the donor's rows |
| DW > F&O (product master, attributes, orders) | On the destination mapping: the field carrying the company/`dataAreaId` on the target entity, set to the demo's code. Shared (tenant-wide) entities have no such field (see below) |

Entities with **no** `dataAreaId` are tenant-wide (products, attributes, categories, workers). Filtering them
by company is rejected, not ignored; the fix is a naming prefix and a filter on that prefix, never a
company predicate ([shared-sandbox.md](shared-sandbox.md)).

The identity's default company is worth setting to the demo company anyway, as a second line of defence: it
turns a forgotten filter into the right answer instead of the wrong one. It does not replace the filter, and
it cannot when one app serves several demo companies.

Job mechanics themselves (endpoint, OData provider, activities, mappings) belong to
[`dw-integration-framework`](../../dw-integration-framework/SKILL.md); this file only adds the company pin.

## Hosted (online-mode) DW installs

A hosted DW install (site URL + Management API key, no machine to scaffold on) reaches F&O over the public
internet like any other client. Consequences:

- **No tunnel.** There is nothing to expose: DW calls F&O outbound. The ngrok pattern belongs to connectors
  where the ERP calls *into* DW: a different mechanism and a different sister skill.
- **The Entra S2S app is the whole access story.** Same client id and secret, same scope, configured in the job's
  provider settings. The demo host's outbound IP is not usually restricted, but check if the tenant has IP
  firewalling on the F&O side before promising a live pull.
- **Probe the DW surfaces first.** The probe order (Management API catalogue, MCP, admin UI, database
  reachability) is owned by [`../../dw-demo-hosted/references/online-mode.md`](../../dw-demo-hosted/references/online-mode.md).
  Which surfaces exist decides how the jobs get created (MCP vs Management API) and how results get verified.
- **Secrets discipline is stricter, not looser.** A hosted install is shared infrastructure; the F&O client
  secret goes into the job configuration through the API, never into a file in the demo folder or an extract.
- **Scheduling**: the job runs on the host's scheduled-task clock. For a live demo beat, trigger the activity
  on demand and confirm it completed rather than trusting a schedule to have fired.

## What lands where on the DW side

Nothing here is F&O-specific (it is the ownership split), but the mapping is worth stating once so the demo's
story matches its data:

| F&O (per demo company) | DW |
|---|---|
| Released products | Products in the PIM / shop the demo sells from |
| Product master, attributes, categories (tenant-wide) | PIM structure, prefixed so two demos in one sandbox do not collide |
| Sales prices, trade agreements | Prices, customer/group prices |
| On-hand | Stock |
| Customers, customer groups | Users / user groups (B2B), price group membership |
| Sales orders and quotations | Orders written back from DW, status polled forward |
| The spine identifier (serials/units) | The lookup the demo's front end is built around |

Which system owns which field is `dw-integration-erp`'s ownership split; the ERP is a **source and a target**,
never a channel ([`../../dw-demo-erp/SKILL.md`](../../dw-demo-erp/SKILL.md)).

## Verifying the wiring, not just the job

A green job run proves the pipe works, not that it drank from the right tap. Check both ends:

1. F&O side: [`Test-DemoCompany.ps1`](../scripts/Test-DemoCompany.ps1): counts **in the demo company**.
2. DW side: count the imported rows and compare. A mismatch that is a multiple of the donor's volume is the
   missing-filter signature.
3. Spot-check one identifier end to end: a released product number, a customer account, one serial/unit id.
   Type it into the demo's own search and confirm the record that comes back is the seeded one.
4. Re-run the job. A correct pin is idempotent; a wrong one grows the row count.

## Failure shapes specific to a shared tenant

| Symptom | Cause |
|---|---|
| Row counts far larger than what was seeded | Missing `dataAreaId` filter: reading every company |
| Row counts plausible but the names are wrong | `cross-company=true` missing: reading the identity's default company |
| Products import, prices do not | Prices filtered per company but the product job pulled tenant-wide rows that have no price in this company |
| A second demo's products appear in this demo's catalog | Tenant-wide product/category/attribute records without a naming prefix |
| A job that used to return rows now returns none | The sandbox was refreshed and the demo company is gone ([demo-company.md](demo-company.md) §6) |
| Throttling (HTTP 429) during a demo | Another demo or a census is running against the same tenant; pace the jobs and honour `Retry-After` |
