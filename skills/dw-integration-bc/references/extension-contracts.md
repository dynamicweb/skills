# Reviewed BC extension contracts

Use an approved, company-scoped BC extension when the installed standard or vendor surfaces do
not expose the required contract. Keep its application ID, publisher, object ranges and API
publisher/group/version stable. Describe the gap and each operation before publishing it.
A custom stock read API and an atomic financial writer have different risk and acceptance scope.

## Build and freeze

1. Record the target tenant/environment/type, BC build and installed dependencies. Resolve symbols
   with the official Microsoft AL tooling for the target application generation. A downloaded
   newer hotfix symbol package is a compilation input, not proof of that exact tenant build.
2. Review the exact source for company/record allowlists, object permissions, event subscribers,
   external HTTP, commit behaviour and destructive operations. Keep financial subscribers out of
   a release intended only to expose stock or master data.
3. Build a new immutable application version and require compiler success from the structured
   result. A tool wrapper returning successfully does not override an inner `succeeded: false`.
4. Freeze the `.app`, source archive and a manifest with app ID, publisher, version, package
   filename/SHA256, source-file hashes, build proof and the declared subscriber surface. Verify
   every archived source is named in the manifest and every named source exists.
5. Publish the frozen package through Microsoft's supported AL publishing tool with the selected
   tenant and Sandbox environment. Require the exact manifest identity/hash before publishing;
   use ordinary additive schema synchronization for an additive release. A build or publish
   failure is not permission to force schema synchronization, publish dependencies or upgrade an
   unrelated application.

A frozen manifest states `compiled`, with installation still pending. Keep publish receipt and
installed-version read-back as separate evidence; do not mutate the release bytes after approval.
Change the application version and repeat the freeze when any reviewed source changes.

## Runtime boundary

Guard each mutating entry point with the permitted sandbox and company allowlist, then enforce
the owned record keys. Scope assigned BC permission sets independently; a runtime name guard is
not a replacement for application permissions. Read-only custom APIs should declare their read
surface and refuse inserts, modifications and deletions.

Prove a successful owned-company call, excluded-company denial, idempotent replay and rollback
before enabling a dependent schedule. For an environment-wide event subscriber, inspect and test
its effect on neighbouring companies even when the integration API itself is company-qualified.
Compilation, publication and read-only API success do not establish order, credit or invoice
acceptance. Use [the business verification ladder](verification.md) for each required operation.

Source: [Microsoft AL development environment](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-dev-overview).
