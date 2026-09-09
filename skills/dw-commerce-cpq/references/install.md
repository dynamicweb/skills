# Installing CPQ

What the two packages contain, what installing them produces, and how to prove an install worked.

## Contents

- [The two packages](#the-two-packages)
- [Installing](#installing)
- [What installation produces](#what-installation-produces)
- [Verifying](#verifying)
- [Version drift](#version-drift)

## The two packages

CPQ ships as two independent NuGet packages, each carrying a single `net8.0` assembly:

| Package | Role | Non-platform dependencies |
|---|---|---|
| `CPQ_Admin` | The backend: admin screens, the update providers that create the schema, and the embedded frontend files | `Newtonsoft.Json` |
| `DW_CPQ_API` | The runtime: rule evaluation, the `/cpqapi` controller, document generation | **`DocumentFormat.OpenXml`**, `Newtonsoft.Json` |

Both declare the `Dynamicweb.*` assemblies as dependencies, which the host already provides. The
consequence worth knowing: **`DocumentFormat.OpenXml` is the one dependency a solution does not
already have**, and it is what document generation runs on.

Installing both is normal. `CPQ_Admin` alone gives an admin with no runtime; `DW_CPQ_API` alone gives
a runtime with no schema and no screens.

## Installing

Drop both `.nupkg` files into the solution's local add-in folder, then install them through the
management API's add-in install command rather than by hand.

**Let the marketplace provider resolve the dependencies — do not extract the DLLs yourself.** The
documented alternative of copying a built `.dll` into the local folder installs a bare assembly and
resolves nothing, which for `DW_CPQ_API` means an assembly whose OpenXml dependency is missing. The
add-in manager enumerating its types is then how a solution ends up returning HTTP 500 on every path.

The install call takes the add-in identifiers; read them from the available-add-ins query rather than
composing them, because they are serialised keys combining package, extension, installed version,
latest version and provider.

Equally, **do not install a package that is already present in another version or already compiled
into the shared runtime**. Two copies of the same assembly make the add-in manager throw a
duplicate-key exception on every request.

## What installation produces

**Installing produces nothing by itself.** Everything is created at the next application start by
two update providers shipped inside `CPQ_Admin`: one writes files, one applies database steps. So the
sequence is **drop the packages, install, restart, then look**.

That start creates:

- **24 `CPQ*` tables** — the model hierarchy (`CPQModel`, `CPQModelVersion`, `CPQGroup`, `CPQInput`,
  `CPQModelVariable`, `CPQModelImportTemp`), the rule families (`CPQInputRule`, `CPQBOMRule`,
  `CPQRouteRule`, `CPQPriceRule`, `CPQOutputRule`, `CPQOutputAction`, `CPQJobRule`, `CPQJobTemplate`),
  the cards (`CPQCard`, `CPQCardItem`, `CPQCardItemBomLines`, `CPQCardTemplate`,
  `CPQCardTemplateItem`, `CPQCardOutputAction`), and the rest (`CPQConfiguration`, `CPQConnector`,
  `CPQQuickConfigure`, `CPQTheme`).
- **Two seeded theme rows**, inserted only if the theme table is empty.
- **18 item type definitions**, registered as ordinary Dynamicweb item types. No per-type CPQ table
  is created; values live in the standard item value tables.
- **The frontend files**, written into the Swift design folder: the CPQ masters and page layouts,
  around fifteen paragraph templates, the CPQ row definitions and row template, the stylesheets and
  scripts, and the shared components.

The database provider is also the migration channel — it carries renames and data fixes for earlier
CPQ versions, so it runs again on upgrade.

Two structural facts that shape everything downstream: the CPQ tables carry **only two foreign keys**
(card item to card, BOM line to card item) and **no check constraints**. Referential integrity is by
convention, so a delete can leave dangling references and nothing will object.

## Verifying

Four checks, in order. Each fails distinctly, which is why all four are worth doing:

1. **The schema exists.** Query for tables named `CPQ%` — expect 24, all empty except the theme table
   with two rows. Nothing here means the application has not restarted since the install.
2. **The add-ins are loaded.** Query the installed add-ins through the management API and confirm
   both report a version. That version is read from the loaded assembly, so it proves the runtime has
   them rather than proving files are on disk.
3. **The item types are registered.** List item types and expect the eighteen `CPQ_*` entries. If the
   XML files are on disk but the types are absent, the file provider ran and the registration did
   not.
4. **The site still answers.** A duplicate-assembly failure shows as HTTP 500 on *every* path, so a
   simple request for the front page distinguishes "CPQ did not install" from "the solution is down".

If the site is down, recover by moving the added add-in folder out and recycling. The management API
is unavailable while the site is down, so recycle locally rather than through an upload.

## Version drift

A CPQ release pins its `Dynamicweb.*` dependencies to a particular platform version. NuGet treats
those as minimums, so the assemblies load happily against a newer platform — but an install does not
exercise the API surface, and drift only shows when a code path calls something that changed.

So a CPQ build several minor versions behind the host is worth noting at the start of a project and
treating as the first hypothesis when a failure looks like a platform call rather than a modelling
mistake. Ask the vendor for a build against the host's version rather than debugging it in place.
