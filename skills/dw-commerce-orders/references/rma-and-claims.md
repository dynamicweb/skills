# RMA and claims — creating, states, the customer-center app, and the notification mail

The return-merchandise (RMA / warranty-claim) surface on DW 10.28.x, field-validated end to end:
which surface actually creates a claim, why an RMA that exists can still be invisible to the
customer center, the three-write state rename, the service cache that every raw-SQL write owes a
flush to, and the notification mail's own resolution and tag rules.

Surfaces used below: MCP tools (`snake_case`) and the frontend `CustomerCenterCmd` commands. The
out-of-product recipes for this area — the Management API claim and state verbs, the three tables
no verb reaches, and the service flush each raw write owes — live in
[`recipes-commerce-rma.md`](../../dw-data-access/references/recipes-commerce-rma.md).

## Contents

- [Creating a claim: which surface writes what](#creating-a-claim-which-surface-writes-what)
- [The platform owns the claim id](#the-platform-owns-the-claim-id)
- [The customer-center list INNER JOINs three tables](#the-customer-center-list-inner-joins-three-tables)
- [Let the platform mint the claim number — never rename an RMA in SQL](#let-the-platform-mint-the-claim-number--never-rename-an-rma-in-sql)
- [Renaming an RMA state is three writes](#renaming-an-rma-state-is-three-writes)
- [Empties differ by writer: guard with a coalesce, never `IS NULL`](#empties-differ-by-writer-guard-with-a-coalesce-never-is-null)
- [Every save of an existing RMA writes a customer-block comment](#every-save-of-an-existing-rma-writes-a-customer-block-comment)
- [The RMA list and the RMA detail read from different places](#the-rma-list-and-the-rma-detail-read-from-different-places)
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
| Management API `RmaSave` (outside the product) | Yes, from the singular root `OrderLineId` | Yes (`Created`) | From the model | No |
| Frontend `CustomerCenterCmd=addrma` | Yes, `OrderLineId` repeatable | Yes, but `RMAComment`'s text is dropped | Yes, from the order | **Yes** |

**MCP `create_rma` produces a backend-only stub.** It copies the customer name, email and company
from the order and satisfies none of the three visibility prerequisites, so the RMA is real,
readable through MCP `get_rmas_by_order_id`, and unreachable from the customer center for ever,
with no error anywhere. When a claim must appear on the storefront, drive the frontend command —
in-product that is the only surface that produces a complete claim. (Outside the product, the
Management API `RmaSave` + comment-row recipe is in
[`recipes-commerce-rma.md`](../../dw-data-access/references/recipes-commerce-rma.md) "Creating a claim:
which surface writes what".)

**The frontend command is the complete model, and it is also the silent one.**
`CustomerExperienceCenterHelper.AddRmaFromRequest` reads `OrderLineId`, `RMATypeId` and
`RMAComment`, resolves the order for the current user, gates on `CanRegisterNewRma` (any order
line still available to return), then hands off to the RMA helper — whose creation loop is skipped
outright when its per-type dictionary is empty. Every refusal on that path answers the normal
post-command 302 and writes nothing: no exception, no log line, no validation message. **A command
that answers 302 and writes nothing is indistinguishable from one that worked**, so assert on
`EcomRmas` row count (or an `RmaList` read) after any scripted `addrma`, never on the redirect.

## The platform owns the claim id

**The platform mints the claim id from the `EcomNumbers` `RMA` counter**, exactly as it does for
orders and invoices (see [`order-lifecycle.md`](order-lifecycle.md) "The platform OWNS ids and
timestamps"). MCP `create_rma` never takes an id, and supplying one to the out-of-product save verb
re-reads it as a *replacement order* id, which is what makes "the id I sent was rejected" read as a
missing order.

Outside the product: see
[`recipes-commerce-rma.md`](../../dw-data-access/references/recipes-commerce-rma.md) "`RmaSave` binds an
EMPTY id and a SINGULAR order-line id".

## The customer-center list INNER JOINs three tables

The customer-center list query joins `EcomRmas` to `EcomRmaComments`, `EcomRmaOrderLines`,
`EcomOrderLines` and `EcomOrders` with **INNER** joins, filters on `OrderComplete = 1` and
`RmaDeleted = 0`, and takes the identity from the **order** (`OrderCustomerAccessUserID`, or
`OrderCustomerNumber` in the customer-number variant) — never from the RMA:

So **an RMA with no comment row does not exist as far as the list is concerned**, and that is not
deducible from the schema. In-product, diagnose an invisible claim by reading the RMA back with MCP
`get_rmas_by_order_id` and checking its comment and order-line collections against the owning
order's customer identity: an empty comment collection is the whole answer. Repairing a stub means
writing the missing relation and comment rows, which no MCP tool does — name the backend RMA screen
to the user, or, outside the product, see
[`recipes-commerce-rma.md`](../../dw-data-access/references/recipes-commerce-rma.md) "The customer-center
list INNER JOINs three tables" for the list query and the repair.

## Let the platform mint the claim number — never rename an RMA in SQL

The RMA service holds the entity keyed by **the id it minted**. A raw-SQL rename moves the row but
not the cached identity, so a renamed claim is unreachable by both ids: every command keyed on the
new id misses, and every command keyed on the old id is inconsistent with the database.

**Readable claim numbers come from the counter instead.** `EcomNumbers` holds `NumberPrefix` and
`NumberCounter` for `NumberType = 'RMA'`; with those set the platform mints the readable number
itself, so a claim filed live through the storefront gets the right number with nothing else in the
loop. No MCP tool exposes the counters — the backend number-series screen is where a person sets
them. Outside the product: see
[`recipes-commerce-rma.md`](../../dw-data-access/references/recipes-commerce-rma.md)
"Let the platform mint the claim number".

## Renaming an RMA state is three writes

The state-save verb with `Translated: true` writes `RmaStateTypeRelation` and
`IsDefaultStateForNewRma` onto `EcomRmaStates` but routes `Name` and `Description` into the
**translation** store, leaving `EcomRmaStates.RmaStateDefaultName` untouched. The storefront reads
`EcomRmaStateTranslations`; the backend state list reads `RmaStateDefaultName`. One verb, two
stores, no warning — and the result is a backend and a storefront that disagree on every state
name, which is only visible to someone looking at both at once.

Treat a state rename as three writes:

| # | What it sets | In-product |
|---|---|---|
| 1 | The flags: which RMA types the state serves, and which state new claims start in | The backend RMA-states screen |
| 2 | The translated name and description, which is what the storefront renders | The backend RMA-states screen, per language |
| 3 | `EcomRmaStates.RmaStateDefaultName`, which is what the backend state list renders | No MCP tool and no verb writes this column — say so and name the screen |

Verify all three by reading the storefront badge, the claim-list column and the backend state list
with MCP `get_rma_states` and asserting they carry the same vocabulary. Outside the product, the
three writes are in
[`recipes-commerce-rma.md`](../../dw-data-access/references/recipes-commerce-rma.md) "Renaming an RMA state
is three writes".

Give every state an `RmaStateTypeRelation` covering all RMA types, or part of the lifecycle is
unreachable for whichever claim type the buyer picks.

## Empties differ by writer: guard with a coalesce, never `IS NULL`

The API path and the frontend RMA module disagree about what "unset" means on the same column:
the save verb leaves `EcomRmaOrderLines.RmaOrderLineSerialNumber` **NULL**, the frontend module
writes an **empty string**. Any "is this field unset" test therefore has to coalesce; a test for
NULL alone matches API-created claims and silently never matches a storefront-filed one. Outside the
product, the guarded repair is in
[`recipes-commerce-rma.md`](../../dw-data-access/references/recipes-commerce-rma.md) "Empties differ by
writer".

Same family, same cause: **the first `EcomRmaComments` row on any RMA is the platform's own
`Created` event and carries no text**, so `SELECT TOP 1 ... ORDER BY RmaCommentId` looking for the
customer's own words returns an empty string. Scan the whole comment trail instead of taking the
first row.

## Every save of an existing RMA writes a customer-block comment

Any save of an **existing** RMA writes an `EcomRmaComments` row with
`RmaCommentEvent = 'UserInfoChanged'` whose text is a serialisation of the whole customer block —
name, company, address, email. It fires on every save, **including a pure state transition where
nothing about the customer was touched**, and `EcomRmaComments` is exactly what a customer-facing
claim-history template renders.

Budget for it on any solution whose claim history is customer-facing. Two ways out:

- **Filter the event in the details template** — render only the comment events the buyer should
  see. This is the option with no cleanup pass and no restart, it is the right one for a live site,
  and it is the one an in-product reader can do: the template is under `Files/`.
- **Delete the rows after a scripted save pass** — no MCP tool and no verb deletes an RMA comment,
  so this is out of product: see
  [`recipes-commerce-rma.md`](../../dw-data-access/references/recipes-commerce-rma.md)
  "Every save of an existing RMA writes a customer-block comment".

## The RMA list and the RMA detail read from different places

`RmaList` queries SQL directly. `RmaById` and `RmaComments` serve a **persistent
`ReturnMerchandiseAuthorizationService` cache that no direct write invalidates**, so after a write
made outside the domain service the list grid shows the new data while the detail view keeps
serving the pre-write object graph — including rows that were deleted. **The correct-looking list
is what hides the stale detail**, which is why this reads as a rendering bug rather than a cache.

Only an explicit flush of that service turns the detail view over. No application-pool recycle is
needed, and a scheduled task that only runs SQL cannot raise the flush at all, so a nightly date
shift leaves the detail view stale by design. Say so when designing the job.

In-product, MCP `get_rma_states` and MCP `get_rmas_by_ids` read through the same cache, so a value
that one of them keeps returning after a change made elsewhere is this, not a rendering bug. The
flush itself is out of product: see
[`recipes-commerce-rma.md`](../../dw-data-access/references/recipes-commerce-rma.md)
"Flush the RMA service after every raw-SQL write", and the per-entity flush table in
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
the MCP RMA tools nor any out-of-product command reaches it — they write the entity and return — so
MCP `set_rma_state` and MCP `create_rma` commit no mail at all, and a subscriber on that
notification cannot be exercised from a script. Plan an RMA-notification build around the frontend
`addrma` and the admin RMA state-change UI. `EcomRmaEmailConfigurations` itself has no MCP tool:
name the backend RMA e-mail screen, or see
[`recipes-commerce-rma.md`](../../dw-data-access/references/recipes-commerce-rma.md)
"Flush the RMA service after every raw-SQL write" for the out-of-product write.
