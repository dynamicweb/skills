# Provider behaviour: what each shipped provider does on the destination side

## Contents

- [Reading this reference](#reading-this-reference)
- [Mapping mechanics that apply to every provider](#mapping-mechanics-that-apply-to-every-provider)
- [EcomProvider as a destination](#ecomprovider-as-a-destination)
- [UserProvider as a destination](#userprovider-as-a-destination)
- [OrderProvider](#orderprovider)
- [SqlProvider](#sqlprovider)
- [XmlProvider and the XSLT seam](#xmlprovider-and-the-xslt-seam)
- [Restores and resets built on activities](#restores-and-resets-built-on-activities)

> What the shipped providers actually do when they write, measured on 10.28.x. The SKILL.md
> "Choosing a destination provider" table says which provider to pick; this reference says what it
> does once picked. The job file that carries these settings is in
> [`job-file-format.md`](job-file-format.md).

## Reading this reference

Everything here is the **job surface** — provider settings and mappings as configured through MCP
`create_integration_activity` / `save_integration_activity_mapping`, through the admin activity
editor, or in the job file. Where a behaviour differs from the C# API, that is stated on the row.
Where a repair needs `SQL`, the row says why the job surface does not cover it.

## Mapping mechanics that apply to every provider

- **Key columns decide insert-versus-update.** Without an `IsKey` column every run inserts.
- **Column mapping has no value-lookup or conversion mechanism.** `ScriptType` is the fixed set
  `None | Append | Prepend | Constant | Substring | NewGuid | CurrentTime | Invert`, and none of
  them expresses a value → value lookup table. For translating a source system's codes into the
  site's own ids, the only seam is an **XSLT applied to the source document** (see below) — it runs
  before the reader and the column mapper see a single row. That keeps the staged payload fully
  source-system-native, which is what makes an "the external system owns this data" story honest.
- **`NullEmptyActionType` is `None | Default | Constant | SkipRow`, and `SkipRow` skips the whole
  row.** There is no per-column "leave this column alone when the source is empty", so a per-row
  exception to a mapping has to be expressed in the source data itself.
- **Conditionals filter rows** on the table mapping; `@Request()` / `@Session()` / `@User()` tokens
  in them are replaced only if the provider calls
  `ReplaceMappingConditionalsWithValuesFromRequest(job)`.

## EcomProvider as a destination

First choice for product imports; costs roughly three times the memory of the DynamicwebProvider.

**Match order and minted ids.** `GetExistingProductDataRow` resolves an incoming row against
existing products in the order **ProductId, then ProductNumber, then ProductName**. With no
`ProductId` in the feed, mapping the external natural key to **`ProductNumber`** makes the feed
update hand-authored products in place instead of duplicating them — this is the default keying
recipe for any feed running against an existing catalogue, and a second identical run then diffs
zero.

Anything the provider **creates** gets a minted sequential `ImportedPROD<n>` / `ImportedGROUP<n>`
id. The `CreateMissing*` flags control whether the row is created at all, never what id it
receives. If a stable source-derived id is wanted, map the source key onto `ProductId` / `GroupId`
**before the first load**: re-keying afterwards is a cross-table migration, not an `UPDATE`.

**Re-keying orphans category field values.** Mapping a new value onto `ProductId` for an existing
row does re-key it in place and carries `EcomGroupProductRelation` across — but
`EcomProductCategoryFieldValue` is not in that cascade, so every category field value for that
product stays pointed at the old id and the re-keyed product has none. Re-key by delete-and-reload,
or migrate `FieldValueProductId` in the same batch.

**Primary group.** `PrimaryGroup` writes `GroupProductRelationIsPrimary` only when the product
resolves to exactly one group relation, and it never matches the provider's own quoted-CSV export
form (`"GROUP14"`) even though `Groups` accepts both forms. Author the value as a **plain unquoted
group id**. Worse, a run actively **clears** an existing primary flag on any product that sits in
more than one group — including products that also sit in a PIM data-model group — so the flag is
not merely unset, it is lost. Where breadcrumbs or a canonical group matter, snapshot
`GroupProductRelationIsPrimary` before the run and replay it afterwards (`SQL`: no job-surface
setting preserves it; local installs only; the replay is a plain `UPDATE` on a relation table the
product read path does not cache, but flush `Dynamicweb.Ecommerce.Products.ProductService` if a
storefront read follows).

**Group imports and a second language layer.** The temp-table merge for `EcomGroups` joins on
`GroupId` alone while putting `GroupLanguageId` on the `SET` list, so it tries to rewrite every
language row of a group to the job's `DefaultLanguage`. The composite primary key
`(GroupId, GroupLanguageId)` is the only thing that rejects the collision — the job fails with
`Violation of PRIMARY KEY constraint 'DW_PK_EcomGroups'` and, running `asTransaction=True`, rolls
back cleanly. Run group imports while the taxonomy carries a single `EcomLanguage`; with a second
language layered on, the same job would be one missing constraint away from silently destroying it.

**`EcomPrices` needs the whole price identity.** `AddMappingsToJobThatNeedsToBeThereForMoveToMainTables`
reads a fixed set of price keys when it promotes the temp tables, and a missing one is an unhandled
`KeyNotFoundException` **after the temp tables have already loaded** — so the log reads as a clean
row load immediately followed by an unexplained crash. Map all of:

`PriceProductId`, `PriceProductVariantId`, `PriceProductLanguageId`, `PriceCurrency`,
`PriceQuantity`, `PriceUserGroupId`, `PriceIsInformative`, `PriceShopId`, `PriceValidFrom`,
`PriceValidTo` — plus `PriceAmount`.

Map all of them even for an update-only sync. Read a `KeyNotFoundException` from that method as
"a required price key is missing from the mapping", not as bad data. These are the same identity
columns that make group-scoped audience pricing work.

**Safety settings for an update-only feed.** `UpdateOnlyExistingProducts` + `UpdateOnlyExistingRecords`
+ `UseStrictPrimaryKeyMatching = True`, with every `RemoveMissing*` / `DeactivateMissingProducts` =
`False`, gives an inbound activity that cannot create, delete or deactivate a product.

**The domain product cache is not flushed for product-field writes.** `DisableCacheClearingAndIndexUpdates=False`
buys the provider's own clearing, which does **not** reach the read-through cache in front of
`ProductService` for extended or global product fields. The measured shape: the job reports rows
affected and completes, a page reading those columns with raw SQL shows the new values on the next
request, and the PDP reading the same fields through the product service keeps showing the old ones
indefinitely. A *scheduled* import inherits this silently, so any nightly activity whose effect must
be visible on the storefront carries the staleness into every run.

Re-saving the affected products with `update_products` or `patch_products_safe` invalidates the
entry on the write path, which is the in-product repair; verify with `get_product_by_id` reading the
field the job wrote. The cache-storage flush itself is out of product: see dw-data-access
`management-api-and-sql.md` §Flushing the product read-through cache after a Data Integration write,
and [`../../dw-data-access/references/cache-invalidation.md`](../../dw-data-access/references/cache-invalidation.md)
for the full per-surface table.

## UserProvider as a destination

**Its real destination is five tables**, and the two that matter most are reachable only if you
already know they are there: `AccessUser`, `AccessUserGroup`, `AccessUserAddress`,
`AccessUserGroupRelation`, `AccessUserSecondaryRelation`.

- **An account modelled as a group targets `AccessUserGroup`** (which sets `AccessUserType=2`).
  Sending it to `AccessUser` produces a user row with a parent id and no group.
- **Group membership rides `AccessUser.AccessUserGroups`**, an `NVARCHAR(255)` CSV of group **names
  or ids**, which the provider expands into `AccessUserGroupRelation` rows via
  `INSERT ... WHERE NOT EXISTS`. It is therefore purely **additive** unless
  `ImportUsersBelongExactlyImportGroups` is on. Overflow past 255 characters is *logged*
  (`Can not update AccessUserGroups column. Check if your import data is not making its length more
  than 255`), not thrown — so a wide membership list drops quietly. A membership that has to be
  derived from another value belongs in the source XSLT, not in a column mapping.
- **Unresolvable address and impersonation rows are DELETED, silently.** Before the merge the
  provider runs `delete from AccessUserAddressTempTableForBulkImport where AccessUserAddressUserId
  not in (select ... from AccessUser)`, and the same pattern for both ends of
  `AccessUserSecondaryRelation`. A mis-keyed feed — one whose only user link is a data column such
  as a customer number rather than the resolver — reports **Completed** with a plausible
  rows-affected count and writes nothing. **Always assert the destination row count in `SQL` after
  an address or impersonation import** (a read, not a write; the job surface reports no removal
  count of its own).
- **Group names are the matching key for a customer import** (`AccessGroupGroupName`). Keep the
  exact characters the source system emits, punctuation included: normalising a name to plainer
  ASCII forks a duplicate account tree on the next run rather than matching the existing group.
- **`EncryptUserPasswords=True` mints DW-native password hashes** from a plaintext feed value (or a
  `ScriptType=Constant` on the mapping), byte-identical to the hashes the site's own users carry —
  so an import can produce working logins with no post-processing. The cost is a plaintext password
  in the payload, which is a file that lives in the anonymously-served archive.

## OrderProvider

### As a destination: update-capable, insert-incapable

The provider builds an `UPDATE ... FROM` a temp table plus an `INSERT` whose column list is
**exactly the mapped columns**. Nothing mints an id from `EcomNumbers`, so a row it has to create
dies on the NOT NULL primary key: first `Cannot insert the value NULL into column 'OrderId'`,
then, once that is supplied, the same on `OrderLineId`.

Worse on the line mapping: the destination schema advertises `OrderIntegrationOrderId` as an
`EcomOrderLines` column, which reads as a resolvable parent key — the provider renames it to
`OrderLineOrderId` **without a lookup**, so the line arrives carrying the external document number
and violates `DW_FK_EcomOrderLines_EcomOrders`.

The working shape for a job that must create orders:

| Mapping | Column | Key? |
|---|---|---|
| Header | a derived order id → `OrderId` | **no** — the key stays the external number, so a re-run updates instead of duplicating |
| Header | the external number → `OrderIntegrationOrderId` | **yes** |
| Line | a derived line id → `OrderLineId` | **yes** |
| Line | the parent order id → `OrderLineOrderId` | no — mapped explicitly, never inferred |

Take the id prefixes from `EcomNumbers` so they never collide with the platform's own, and advance
those counters immediately after the run. A job that only ever *updates* — keyed on `OrderId` or on
`OrderIntegrationOrderId` — succeeds first time and never meets any of this.

### As an export source: the switches, and the one that is missing

The export settings are exactly `ExportNotYetExportedOrders`, `ExportOnlyOrdersWithoutExtID`,
`DoNotExportCarts`, `OrderStateAfterExport` and `RemoveMissingOrderLines`.

`DoNotExportCarts` (labelled "Export completed orders only") excludes carts and quotes because they
are not complete. **A ledger entry is complete and is not a cart, so nothing holds it back**: a
plain not-yet-exported export posts imported customer invoices back to the external system as
sales orders, and stamps `OrderIsExported = 1` on them on the way out. `IsLedgerEntries` exists on
`OrderSearchFilter` in the C# API and is **not** exposed on the job.

The fix that needs no filter, and is the semantically correct one: have the ledger **import** map a
derived `True` onto `OrderIsExported`. An invoice that came from the external system is already
exported by definition, and `ExportNotYetExportedOrders` then skips it forever.

`OrderStateAfterExport` moves the order to a chosen state the moment the export succeeds, with no
subscriber — which is how an order-state flip is shown on a storefront order list with no template
change.

### A state written by a job notifies nobody

Order-state notifications fire on **`OrderService.Save` only**
(`OrderService.Save` → `NotifyOrderStateChanged` → `SendStateChangedEmail`). The OrderProvider
destination writes `EcomOrders` through a temp-table update/insert and never calls it, and the same
is true of any `SQL` write to `OrderStateId`. Measured: fifteen orders moved through notifying
states in one import run and the mail spool did not move at all, while a single
MCP `set_order_state` on the same states committed two mails within seconds.

For a bulk backfill this is the behaviour you want. For the beat everyone asks for — "the external
system flips the status and the customer is emailed" — the import cannot deliver it: the state has
to be re-applied through the order service by a scheduled task or a subscriber on the provider's
save. That is code, and it belongs in the estimate.

## SqlProvider

A SqlProvider destination writes a **plain custom table** with no Dynamicweb ownership of any kind,
and upserts on the mapping's `isKey` columns — a second identical run leaves row count, checksum
and max identity unchanged. Two traps sit behind that.

**Staging clones drop index filters.** The writer bulk-copies the whole source into a clone of the
destination table (`<YourTable>TempTableForSqlProviderImport<n>`) before merging, and the clone is
built from the destination's indexes **with the filters dropped**. A
`UNIQUE (ShipmentId) WHERE Result = 'Success'` becomes a plain `UNIQUE (ShipmentId)` — strictly
stronger — so exactly the history the filter exists to permit (a failed attempt plus a successful
retry) is rejected as a duplicate key, in an object that no longer exists by the time you look for
it. Nothing in the error mentions filtering, so it reads as data corruption.

`SkipFailingRows` is not a workaround: it drops precisely the rows a restore exists to put back,
and a delete-missing pass then removes them permanently. A failed run also **leaves the staging
table behind** in the schema. Until the clone carries the filter, a destination table with a
filtered unique index cannot be written by SqlProvider — move those tables to a named operator step
with an explicit reconcile, and say so in the runbook.

**A round trip truncates datetime to whole seconds.** Values are carried as text and re-parsed on
the way in, with no fractional-seconds component in the format, so `01:07:23.893` arrives as
`01:07:23.000`. Nothing reports it: the row is written, the count is right, the job succeeds. It
looks like a per-table bug rather than a per-type one because the tables that come back identical
are exactly the ones with no datetime column, or whose datetimes are already whole. Only a
**whole-table checksum** against a baseline reveals it.

Where a restore or mirror is built on this provider, the honest minimum is: run it once to settle
the values, **re-capture the baselines from the settled state**, and record the one-time sub-second
change as an enumerated delta. Every subsequent restore is then byte-identical and the idempotency
proof is real rather than approximate.

## XmlProvider and the XSLT seam

`<xslfile>` on the source applies a stylesheet to the source **document**, before the reader or the
column mapper sees anything. That is the only place a value → value translation can live, so it is
where a source system's codes become the site's own ids. Prove the ordering with a throwaway
identity stylesheet that renames one key value: the destination row is created under the **renamed**
value.

Keep the payload itself source-system-native and put every cross-reference in the stylesheet — a
hand-rewritten payload breaks the claim that the external system owns the data.

The XmlProvider destination block, its schema requirement and the folder/file-name split are in
[`job-file-format.md`](job-file-format.md#file-destinations-folder-file-name-and-what-neither-of-them-does).

## Restores and resets built on activities

**Purge the entities the session created FIRST, then restore the tables.** A
delete-rows-missing-from-source pass is not reliable while a parent row the child points at is
still live: the measured case left one child row behind while the same pass deleted the extras from
two other tables, and a derived total on an unrelated table stayed wrong with it. Re-running the
identical task after the purge cleared it — which makes the second pass load-bearing, so an
interrupted reset leaves state behind and reports success. Ordering the chain purge-first makes a
single pass sufficient, which is what a reset has to be.

**The activity log counts rows written, never rows removed**, so a pass that deleted nothing and a
pass that deleted two look identical. Prove a restore with a whole-table checksum against a
baseline you captured yourself, not with the log.

**Never null an integration key as a reset step.** An integration key (`OrderIntegrationOrderId`
and its equivalents) *is* the "already processed" flag, so clearing it re-arms the integration for
every row it touches — the next export sweeps the whole seeded history and advances the external
number series by its length. Give seeded rows a plausible historical key instead, so they are
already processed, and **scope every reset by a marker column the generator stamps on every row it
creates** — never by an id range, an id list or a date, all of which seeded history also matches.
The two assertions that catch a re-arming reset are: after the reset the seeded-history row count
is unchanged **and** the export-eligible count is exactly zero. Either one alone passes.
