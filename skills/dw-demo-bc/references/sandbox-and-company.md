# Sandbox and company isolation

Select an existing BC **Sandbox** with the environment owner. Record tenant GUID,
environment name/type, region, version, active users, extensions and each allowed company
GUID. Use **Companies** and the standard `companies` API to reconcile names with GUIDs.
Treat an unconfirmed type or a production environment as read-only.

Use one or more isolated companies for the demo's selling and fulfilment entities. Provision
or copy through BC's supported company/environment administration with explicit owner approval;
record localization, posting setup, UOM, number series, customers, items and opening inventory.
A new empty company is not a configured business. Country-named companies in a sandbox with
one localisation prove company separation only; they do not validate another country's statutory
localisation. Verify customer posting groups, payment terms, item posting setup and number series
before any financial order. Do not copy an F&O legal-entity recipe.

Company copy, environment copy and installed extensions have different scope. Extensions and
some configuration affect the environment; review neighbouring demos before installing anything.
Donor and existing companies stay read-only. A golden company needs a tested replay manifest
of the setup and data it actually supplies, not an assumption that all transactions were copied.

Use read-only probes from [`dw-integration-bc`](../../dw-integration-bc/SKILL.md). Discover
the model before seed work. Prefix demo-owned records and record their original IDs. Keep
all ERP writes and order exports inside the selected company allowlist.

With no usable sandbox or credentials, continue only the explicitly labelled local mock.
Record the login/permission/environment-choice gap and keep live acceptance pending.

Sources: [sandbox administration](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/tenant-admin-center-environments),
[company setup](https://learn.microsoft.com/en-us/dynamics365/business-central/about-new-company).
