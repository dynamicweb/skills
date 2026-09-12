# RMA and claims — creating, states, the customer-center app, and the notification mail

The return-merchandise (RMA / warranty-claim) surface on DW 10.28.x, field-validated end to end:
which surface actually creates a claim, why an RMA that exists can still be invisible to the
customer center, the three-write state rename, the service cache that every raw-SQL write owes a
flush to, and the notification mail's own resolution and tag rules.

Surfaces used below, in ladder order: MCP tools (`snake_case`), Admin API verbs (`PascalCase`, at
`/Admin/Api/<Verb>`), the frontend `CustomerCenterCmd` commands, and direct SQL — which on this
surface is legitimate for the three tables no verb reaches, and is **local-install only** (a
hosted install has no SQL rung) and always owes the service flush in
[Flush the RMA service after every raw-SQL write](#flush-the-rma-service-after-every-raw-sql-write).

## Contents

- [Creating a claim: which surface writes what](#creating-a-claim-which-surface-writes-what)
- [`RmaSave` binds an EMPTY id and a SINGULAR order-line id](#rmasave-binds-an-empty-id-and-a-singular-order-line-id)
- [The customer-center list INNER JOINs three tables](#the-customer-center-list-inner-joins-three-tables)
- [Let the platform mint the claim number — never rename an RMA in SQL](#let-the-platform-mint-the-claim-number--never-rename-an-rma-in-sql)
- [Renaming an RMA state is three writes](#renaming-an-rma-state-is-three-writes)
- [Empties differ by writer: guard with a coalesce, never `IS NULL`](#empties-differ-by-writer-guard-with-a-coalesce-never-is-null)
- [Every save of an existing RMA writes a customer-block comment](#every-save-of-an-existing-rma-writes-a-customer-block-comment)
- [Flush the RMA service after every raw-SQL write](#flush-the-rma-service-after-every-raw-sql-write)
- [The customer-center RMA app is ViewModel-driven](#the-customer-center-rma-app-is-viewmodel-driven)
- [The RMA app keys on the signed-in user, not the customer number](#the-rma-app-keys-on-the-signed-in-user-not-the-customer-number)
- [The RMA notification mail: template root, tag set, and the only route that raises it](#the-rma-notification-mail-template-root-tag-set-and-the-only-route-that-raises-it)

## Creating a claim: which surface writes what

An RMA is visible to the customer center only when three things exist: at least one
`EcomRmaComments` row, at least one `EcomRmaOrderLines` row, and an owning order whose customer
identity matches the signed-in user. The three creation surfaces satisfy different subsets, so
pick by what you need rather than by convenience:

| Surface | Writes the order-line relation | Writes a `Created` comment | Writes `RmaCustomerNumber` | Raises the notification mail |
|---|---|---|---|---|
| MCP `create_rma` | No (`orderLineCount` is `0` in its own response) | No — the `comment` argument is accepted and dropped | No | No |
| Admin API `RmaSave` (`/Admin/Api/RmaSave`) | Yes, from the singular root `OrderLineId` | Yes (`Created`) | From the model | No |
| Frontend `CustomerCenterCmd=addrma` | Yes, `OrderLineId` repeatable | Yes, but `RMAComment`'s text is dropped | Yes, from the order | **Yes** |

**MCP `create_rma` produces a backend-only stub.** It copies the customer name, email and company
from the order and satisfies none of the three visibility prerequisites, so the RMA is real,
readable through MCP `get_rmas_by_order_id`, and unreachable from the customer center for ever,
with no error anywhere. When a claim must appear on the storefront, create it with Admin API
`RmaSave` and add the comment row, or drive the frontend command.

**The frontend command is the complete model, and it is also the silent one.**
`CustomerExperienceCenterHelper.AddRmaFromRequest` reads `OrderLineId`, `RMATypeId` and
`RMAComment`, resolves the order for the current user, gates on `CanRegisterNewRma` (any order
line still available to return), then hands off to the RMA helper — whose creation loop is skipped
outright when its per-type dictionary is empty. Every refusal on that path answers the normal
post-command 302 and writes nothing: no exception, no log line, no validation message. **A command
that answers 302 and writes nothing is indistinguishable from one that worked**, so assert on
`EcomRmas` row count (or an `RmaList` read) after any scripted `addrma`, never on the redirect.

## `RmaSave` binds an EMPTY id and a SINGULAR order-line id

Admin API `RmaSave` branches on `Model.Id`: a non-empty id means "this is an existing RMA" and
routes the payload down the replacement-order path, re-reading the id you supplied as a
*replacement order* id. And on a create the order-line binding is the **singular root
`OrderLineId`** — the plural `OrderLineIds` collection is not bound on 10.28.x. Neither error
string names the offending field:

```
POST /Admin/Api/RmaSave {"Model":{"Id":"<claim-number>", ...}}
  -> {"status":"notFound","message":"Selected replacement order is not found. The replacement order id: <claim-number>."}

POST /Admin/Api/RmaSave {"Model":{"Id":"", ...},"OrderLineIds":["<orderLineId>"]}
  -> "Unable to create RMA. Selected products were not found."

POST /Admin/Api/RmaSave {"Model":{"Id":"", ...},"OrderLineId":"<orderLineId>"}
  -> created; the platform mints the id from the `EcomNumbers` `RMA` counter
```

**Start from the platform's own model.** `GET /Admin/Api/RmaNew?OrderId=<orderId>` returns a
fully pre-filled model — customer block, language, default state — and is the right starting
point for the `RmaSave` payload. Send `Model.Id` empty on every create: the platform owns the id,
exactly as it does for `OrderSave` and `InvoiceSave` (see
[`order-lifecycle.md`](order-lifecycle.md) "The platform OWNS ids and timestamps").

## The customer-center list INNER JOINs three tables

The customer-center list query joins `EcomRmas` to `EcomRmaComments`, `EcomRmaOrderLines`,
`EcomOrderLines` and `EcomOrders` with **INNER** joins, filters on `OrderComplete = 1` and
`RmaDeleted = 0`, and takes the identity from the **order** (`OrderCustomerAccessUserID`, or
`OrderCustomerNumber` in the customer-number variant) — never from the RMA:

```sql
-- the shape of the app's own list query (read-only; use it to diagnose an invisible RMA)
SELECT r.RmaId, o.OrderID, r.RmaStateId, MAX(c.RmaCommentCreated) AS DateCreated
FROM EcomRmas r
INNER JOIN EcomRmaComments   c  ON r.RmaId = c.RmaCommentRmaId
INNER JOIN EcomRmaOrderLines rl ON r.RmaId = rl.RmaOrderLineRmaId
INNER JOIN EcomOrderLines    ol ON rl.RmaOrderLineOrderLineId = ol.OrderLineID
INNER JOIN EcomOrders        o  ON ol.OrderLineOrderID = o.OrderID
WHERE o.OrderComplete = 1 AND r.RmaDeleted = 0 AND o.OrderCustomerAccessUserID = <userId>
GROUP BY r.RmaID, o.OrderID, r.RmaStateID;
```

So **an RMA with no comment row does not exist as far as the list is concerned**, and that is not
deducible from the schema. Repairing a stub means inserting the missing `EcomRmaOrderLines` and
`EcomRmaComments` rows and setting `RmaCustomerNumber` — SQL is legitimate here because no MCP
tool or Admin API verb writes an RMA comment row on an existing claim other than `RmaCommentSave`
(which needs the platform-minted id, below), it is **local-install only**, and it owes the service
flush in [Flush the RMA service](#flush-the-rma-service-after-every-raw-sql-write).

## Let the platform mint the claim number — never rename an RMA in SQL

The RMA service holds the entity keyed by **the id it minted**. A raw-SQL rename moves the row but
not the cached identity, so every subsequent command keyed on the new id misses while every
command keyed on the old id is now inconsistent with the database:

```
UPDATE EcomRmas SET RmaId = '<new-number>' WHERE RmaId = '<minted-id>'   -- 1 row
POST /Admin/Api/RmaCommentSave {"RmaId":"<new-number>", ...}
  -> "The RMA is not found. Id: <new-number>"
```

**Publish readable claim numbers through the counter instead.** `EcomNumbers` holds
`NumberPrefix` and `NumberCounter` for `NumberType = 'RMA'`; set them and the platform mints the
readable number itself, which also means a claim filed live through the storefront gets the right
number with no SQL in the loop at all:

```sql
-- local installs only; no verb exposes the EcomNumbers counters. Owes no cache flush:
-- the counter is read at mint time. Prefer this to renaming a minted RMA.
UPDATE EcomNumbers SET NumberPrefix = '<prefix>', NumberCounter = <n> WHERE NumberType = 'RMA';
```

If a rename is genuinely unavoidable, make it the **last** write of the build and restart the
application pool after it, so no later Admin API command is keyed on an id the cache does not
hold.

## Renaming an RMA state is three writes

Admin API `RmaStateSave` with `Translated: true` writes `RmaStateTypeRelation` and
`IsDefaultStateForNewRma` onto `EcomRmaStates` but routes `Name` and `Description` into the
**translation** store, leaving `EcomRmaStates.RmaStateDefaultName` untouched. The storefront reads
`EcomRmaStateTranslations`; the backend state list reads `RmaStateDefaultName`. One verb, two
stores, no warning — and the result is a backend and a storefront that disagree on every state
name, which is only visible to someone looking at both at once.

Treat a state rename as three writes:

| # | Surface | What it sets |
|---|---|---|
| 1 | Admin API `RmaStateSave` `{Id, RmaStateTypeRelation, IsDefaultStateForNewRma}` | The flags: which RMA types the state serves, and which state new claims start in |
| 2 | Admin API `RmaStateTranslationSave` `{Id, LanguageId, Name, Description}` | What the storefront renders |
| 3 | `SQL` — `UPDATE EcomRmaStates SET RmaStateDefaultName = ... WHERE RmaStateId = ...` | What the backend state list renders |

Step 3 is SQL because no verb writes that column: `RmaStateSave` with `Translated: true` skips it
and there is no untranslated variant that reaches it. **Local installs only**, and it owes the RMA
service flush below. Verify all three by reading the storefront badge, the claim-list column and
the backend state list and asserting they carry the same vocabulary.

Give every state an `RmaStateTypeRelation` covering all RMA types, or part of the lifecycle is
unreachable for whichever claim type the buyer picks.

## Empties differ by writer: guard with a coalesce, never `IS NULL`

The API path and the frontend RMA module disagree about what "unset" means on the same column:
`RmaSave` leaves `EcomRmaOrderLines.RmaOrderLineSerialNumber` **NULL**, the frontend module writes
an **empty string**. A guarded self-heal written as `WHERE ... IS NULL` therefore fires on
API-created claims and silently never fires on a storefront-filed one — same statement, same code
path, zero rows affected, no error.

```sql
-- guard every "is this RMA field unset" test this way; still idempotent on re-render
UPDATE EcomRmaOrderLines SET RmaOrderLineSerialNumber = @s
 WHERE RmaOrderLineId = @id AND ISNULL(RmaOrderLineSerialNumber, '') = '';
```

Same family, same cause: **the first `EcomRmaComments` row on any RMA is the platform's own
`Created` event and carries no text**, so `SELECT TOP 1 ... ORDER BY RmaCommentId` looking for the
customer's own words returns an empty string. Scan the whole comment trail instead of taking the
first row.

## Every save of an existing RMA writes a customer-block comment

Any `RmaSave` of an **existing** RMA writes an `EcomRmaComments` row with
`RmaCommentEvent = 'UserInfoChanged'` whose text is a serialisation of the whole customer block —
name, company, address, email. It fires on every save, **including a pure state transition where
nothing about the customer was touched**, and `EcomRmaComments` is exactly what a customer-facing
claim-history template renders.

Budget for it on any solution whose claim history is customer-facing. Two ways out:

- **Filter the event in the details template** — render only the comment events the buyer should
  see. This is the option with no cleanup pass and no restart, and it is the right one for a live
  site.
- **Delete the rows after a scripted `RmaSave` pass** —
  `DELETE FROM EcomRmaComments WHERE RmaCommentEvent = 'UserInfoChanged'`. SQL because no verb
  deletes an RMA comment; **local installs only**; owes the service flush below, because the RMA
  detail view serves the cached object graph and keeps rendering deleted rows without it.

## Flush the RMA service after every raw-SQL write

`RmaList` queries SQL directly. `RmaById` and `RmaComments` serve a **persistent
`ReturnMerchandiseAuthorizationService` cache that no SQL write invalidates**, so after a raw-SQL
edit the list grid shows the new data while the detail view keeps serving the pre-write object
graph — including rows that were deleted. **The correct-looking list is what hides the stale
detail**, which is why this reads as a rendering bug rather than a cache.

```
POST /Admin/Api/CacheInformationRefresh
{ "CacheTypeName": "Dynamicweb.Ecommerce.Orders.ReturnMerchandiseAuthorization.ReturnMerchandiseAuthorizationService" }
```

- **Every raw-SQL write to RMA data is followed by that flush** — no application-pool recycle is
  needed. MCP `get_rma_states` reading back a state row inserted by SQL is the cheap proof that
  the flush landed.
- **Match FULL type names when hunting a cache id.** Filtering the cache list on the substring
  `rma` also matches `inteRMAtional`, `infoRMAtion` and `foRMAt`, which is what makes the right
  entry hard to find.
- **A SQL-only scheduled task cannot call that verb**, so a nightly date shift leaves the RMA
  detail view stale by design until the cache turns over. Say so when designing the job.

Assert `RmaById` returns the same values as the `RmaList` row after a SQL edit **plus** the flush.
The per-entity flush table is in
[`cache-invalidation.md`](../../dw-data-access/references/cache-invalidation.md).

## The customer-center RMA app is ViewModel-driven

The DW10 app `eCom_CustomerExperienceCenterRma` passes a **view model**. The only RMA templates
shipped on a Swift 2 solution (`eCom/CustomerCenter/RMAList.cshtml` and `RMADetails.cshtml`) are
DW9 tag templates — `@inherits RazorTemplateBase<RazorTemplateModel<Template>>`, driven by
`GetInteger("Ecom:CustomerCenter.RMA.Count")` and `GetLoop("RMAs")` — so those tags resolve empty
and the template takes its own empty branch. The page answers 200 with no error, nothing in the
event log and nothing in `Templates/Errors`: the template is found, compiled and executed, and is
simply reading a vocabulary nobody filled. Every other candidate (retrieval mode, sort field,
cache, customer number, order-line relations) looks equally plausible, so **replay the app's own
list query by hand first** — two rows back from SQL against an empty page separates "no data" from
"no tags" in one step.

Write the pair against the real models:

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Ecommerce.Frontend.ReturnMerchandiseAuthorization.RmaListViewModel>
```

| Model | Members |
|---|---|
| `RmaListViewModel` | `Rmas` (`IList<RmaViewModel>`), `CurrentPage`, `PageCount`, `PageSize`, `TotalRmasCount` |
| `RmaViewModel` | `Id`, `OrderId`, `Date`, `Type`, `State` (`RmaStateViewModel`: `Id`, `Name`), `RmaOrderLines`, `RmaComments`, plus the full `Customer*` / `Delivery*` address block |
| `RmaOrderLineViewModel` | `Id`, `SerialNumber`, `OrderLine` (`OrderLineViewModel`) |
| `RmaCommentViewModel` | `CommentText`, `Created`, `Event`, `Images` |
| `RmaEventViewModel` | `Type`, `DefaultDescription` — **not `Name`**; a template using `.Name` fails to compile at request time |

**The app's own settings keys are `RmaListTemplate`, `RmaDetailTemplate`, `RmaByField`, `SortRma`
and `PageSize`.** The lookalikes `RMAListTemplate`, `RMADetailsTemplate`, `RMASource` and
`DefaultView` live in the same assembly and belong to the DW9 `eCom_CustomerCenter` app. The app's
system name is also absent from MCP `get_content_apps`; it is registered in the Ecommerce
assembly's add-in table as `eCom_CustomerExperienceCenterRma`.

## The RMA app keys on the signed-in user, not the customer number

The RMA app **declares no retrieval mode at all** — its settings block is `RmaListTemplate` /
`RmaDetailTemplate` / `RmaByField` / `SortRma` — and the list query's identity clause is
`EcomOrders.OrderCustomerAccessUserID`. `RetrieveListBasedOn` is *accepted* into the settings XML
(MCP `set_module_settings` merges unknown keys without complaint) and read by nobody, so setting
it to `UseCustomerNumber` changes nothing: two contacts on one customer number get byte-identical
responses, and only the contact who raised a claim can see it.

Measured on one solution across the whole customer-center family: **orders, carts, quotes, ledger
entries and favourites all honour `UseCustomerNumber`; RMA does not.** On a B2B portal "your
colleague raised a return" is therefore not expressible without a change order — surface that at
scope time. The app does still follow impersonation, so a CSR impersonating the raiser sees the
claims. The per-app matrix lives in
[`customer-center-surfaces.md`](customer-center-surfaces.md).

## The RMA notification mail: template root, tag set, and the only route that raises it

**The template value is a path from the `/Files/Templates` ROOT.**
`EcomRmaEmailConfigurations.RmaEmailConfigurationTemplate` resolves with no folder of its own, so a
bare file name resolves to `/Files/Templates/<name>.cshtml` and a relative path such as
`eCom/Rma/<name>.cshtml` resolves correctly. This is **a different rule from
`OrderStateMailTemplate` on the same solution** — three mail settings, three roots, catalogued in
[`order-notifications.md`](order-notifications.md). A template that cannot be loaded is not an
aborted send: the platform logs the failure and **mails the "Template file not found …" text to
the customer as the message body**, with the recipients, sender and subject all perfect, which is
what makes it survive review.

**The mail context is fully populated — under the prefix `Ecom:Rma.`, mixed case.** It is the only
tag prefix on the platform that is not the upper-cased entity name, and two of the names differ
from the obvious guess, so a template written against `Ecom:RMA.ID` / `.OrderID` / `.Status`
renders a table of blanks. `Template.GetString` returns an empty string for an unknown tag, so an
unpopulated context and a misspelled prefix are indistinguishable from the rendered mail.

| Tag | Note |
|---|---|
| `Ecom:Rma.ID` | |
| `Ecom:Rma.OriginalOrderId` | **not** `OrderID` — derived from the first RMA order line, because `EcomRmas` carries no order column at all |
| `Ecom:Rma.State` / `Ecom:Rma.StateName` | the description and the name — **not** `Status` |
| `Ecom:Rma.Created`, `Ecom:Rma.Type`, `Ecom:Rma.ReplacementOrderId` | |
| `Ecom:Rma.Customer.*` | `Address`, `Address2`, `Name`, `Number`, `Company`, `Zip`, `City`, `Country`, `Region`, `Phone`, `Fax`, `Email`, `Cell`, `RefID`, `EAN`, `VatRegNumber` |
| `Ecom:Rma.Delivery.*` | `Company`, `Address`, `Address2`, `Name`, `Zip`, `City`, `Country`, `Region`, `Phone`, `Fax`, `Email`, `Cell` |
| loop `Ecom:Rma.Comments` | each row: `Ecom:Rma.Comment.{id, Text, CreatedDate, NewState, Event, Event.isStateChanged}` |
| loop `Ecom:Rma.RmaOrderLines` | `Ecom:Rma.RmaOrderLine.SerialNumber` plus the order-line tag set |

Two things the renderer does **not** give a template, and which therefore need a subscriber on
`Ecommerce.Rma.BeforeRmaEmailSend` (its args expose the whole `MailMessage`, so the body is
writable): the returned lines with their **quantities** in any usable shape — the
`RmaOrderLines` loop names only `SerialNumber` — and a single "the customer's note" tag, as
opposed to the whole comment history including state-change rows.

**Only the frontend raises the mail.** `DWN.ECOM.RMA.BEFORERMAEMAILSEND` is raised from exactly one
member in the whole bin, `ReturnMerchandiseAuthorizationEmailConfiguration.SendMail(rma)`. Neither
the MCP RMA tools nor any Admin API command reaches it — they write the entity and return — so MCP
`set_rma_state` and MCP `create_rma` commit no mail at all, and a subscriber on that notification
cannot be exercised from a script. Plan an RMA-notification build around the frontend `addrma` and
the admin RMA state-change UI, and configure `EcomRmaEmailConfigurations` by SQL (no MCP tool or
Admin API verb reaches that table; **local installs only**; flush the RMA service afterwards).
