# Foundational candidate → dw-integration-framework

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 Integration Framework taxonomy (the three integration
> approaches and the data-integration / provider definitions, sourced from the DW docs), staged here for a
> future fold-up into `dw-integration-framework`. No demo/customer content. The `dw-integration-framework`
> skill already owns the *architecture* (Activity = source provider + destination provider + field
> mapping); this candidate stages the named taxonomy and doc quotes that skill currently lacks. When
> folded, move this body into `dw-integration-framework` and re-target the pointers in the demo skills.

## What the DW docs say about data integration

From [doc.dynamicweb.com](https://doc.dynamicweb.com/) (Integration area, Integration Framework v2):

- **Data integration** is "the process of importing and exporting data to and from your Dynamicweb
  solution, either on an ad-hoc basis, on a schedule or in real-time."
- The Integration Framework v2 is "a collection of components for transferring data and maintaining
  data consistency between a Dynamicweb solution and a remote system."
- An **integration provider** is "a piece of software for moving data between Dynamicweb and an
  external data source, like an XML file, a CSV file or an SQL database."
- An activity requires two provider types: "**a source provider matching the data source**" and
  "**a destination provider matching the data destination**."

## The three integration approaches (by name)

The framework supports three approaches, distinguished by *when* the data moves:

1. **Ad-hoc activities** — run on demand (a manual import/export of a data set, one execution at a time).
2. **Batch (scheduled) integration** — activities run by scheduled tasks at fixed intervals
   (hourly / daily / weekly), moving accumulated changes on each run.
3. **Live (real-time) integration** — "retrieves data from a remote system in real-time, and uses it
   to show for instance live prices or stock states." The remote system is queried per request rather
   than on a schedule, so the displayed value is always current.

The same activity shape (source provider + destination provider + field mapping) underlies all three;
only the trigger differs — manual, scheduled, or per-request.
