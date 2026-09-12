# Out-of-product recipes — Commerce: RMA and claims

The out-of-product recipes for the return-merchandise (RMA / warranty-claim) surface: Management API
commands at `/admin/api/...` and direct SQL. The in-product skill for this area
(`dw-commerce-orders`) is `dynamo: true` and carries no instruction on those surfaces, so it keeps a
one-line pointer here instead of the recipe. The rest of the commerce recipes are in
[`recipes-commerce.md`](recipes-commerce.md).

Every recipe names its surface in the repo convention, and every SQL recipe states inline why the
higher surfaces do not cover it, that it is **local installs only**, and the cache flush or host
restart it owes.

## Contents

- [Creating a claim: which surface writes what](#creating-a-claim-which-surface-writes-what)
- [`RmaSave` binds an EMPTY id and a SINGULAR order-line id](#rmasave-binds-an-empty-id-and-a-singular-order-line-id)
- [The customer-center list INNER JOINs three tables](#the-customer-center-list-inner-joins-three-tables)
- [Let the platform mint the claim number — never rename an RMA in SQL](#let-the-platform-mint-the-claim-number--never-rename-an-rma-in-sql)
- [Renaming an RMA state is three writes](#renaming-an-rma-state-is-three-writes)
- [Empties differ by writer: guard with a coalesce, never `IS NULL`](#empties-differ-by-writer-guard-with-a-coalesce-never-is-null)
- [Every save of an existing RMA writes a customer-block comment](#every-save-of-an-existing-rma-writes-a-customer-block-comment)
- [Flush the RMA service after every raw-SQL write](#flush-the-rma-service-after-every-raw-sql-write)

---

## Creating a claim: which surface writes what

An RMA is visible to the customer center only when three things exist: at least one
`EcomRmaComments` row, at least one `EcomRmaOrderLines` row, and an owning order whose customer
identity matches the signed-in user. Management API `RmaSave` (at `/admin/api/RmaSave`) writes the
order-line relation from the singular root `OrderLineId`, writes a `Created` comment, and takes
`RmaCustomerNumber` from the model — so it satisfies all three where MCP `create_rma` satisfies
none. It does not raise the notification mail; only the frontend `CustomerCenterCmd=addrma` does,
which is also the only surface that writes `RmaCustomerNumber` from the order.

## `RmaSave` binds an EMPTY id and a SINGULAR order-line id

`RmaSave` branches on `Model.Id`: a non-empty id means "this is an existing RMA" and routes the
payload down the replacement-order path, re-reading the id you supplied as a replacement order id.
On a create the order-line binding is the singular root `OrderLineId`; the plural `OrderLineIds`
collection is not bound on 10.28.x. Neither error string names the offending field:

```
POST /admin/api/RmaSave {"Model":{"Id":"<claim-number>", ...}}
  -> {"status":"notFound","message":"Selected replacement order is not found. The replacement order id: <claim-number>."}

POST /admin/api/RmaSave {"Model":{"Id":"", ...},"OrderLineIds":["<orderLineId>"]}
  -> "Unable to create RMA. Selected products were not found."

POST /admin/api/RmaSave {"Model":{"Id":"", ...},"OrderLineId":"<orderLineId>"}
  -> created; the platform mints the id from the `EcomNumbers` `RMA` counter
```

**Start from the platform's own model.** `GET /admin/api/RmaNew?OrderId=<orderId>` returns a fully
pre-filled model — customer block, language, default state — and is the right starting point for
the `RmaSave` payload. Send `Model.Id` empty on every create: the platform owns the id.

## The customer-center list INNER JOINs three tables

```sql
-- the shape of the app's own list query (read-only; use it to diagnose an invisible RMA).
-- SQL because no verb exposes the list query; local installs only; owes no flush (read-only).
SELECT r.RmaId, o.OrderID, r.RmaStateId, MAX(c.RmaCommentCreated) AS DateCreated
FROM EcomRmas r
INNER JOIN EcomRmaComments   c  ON r.RmaId = c.RmaCommentRmaId
INNER JOIN EcomRmaOrderLines rl ON r.RmaId = rl.RmaOrderLineRmaId
INNER JOIN EcomOrderLines    ol ON rl.RmaOrderLineOrderLineId = ol.OrderLineID
INNER JOIN EcomOrders        o  ON ol.OrderLineOrderID = o.OrderID
WHERE o.OrderComplete = 1 AND r.RmaDeleted = 0 AND o.OrderCustomerAccessUserID = <userId>
GROUP BY r.RmaID, o.OrderID, r.RmaStateID;
```

Repairing a stub means inserting the missing `EcomRmaOrderLines` and `EcomRmaComments` rows and
setting `RmaCustomerNumber` — SQL is legitimate here because no MCP tool or Management API verb
writes an RMA comment row on an existing claim other than `RmaCommentSave` (which needs the
platform-minted id); it is **local installs only**, and it owes the service flush below.

## Let the platform mint the claim number — never rename an RMA in SQL

The RMA service holds the entity keyed by the id it minted, so a raw-SQL rename moves the row but
not the cached identity:

```
UPDATE EcomRmas SET RmaId = '<new-number>' WHERE RmaId = '<minted-id>'   -- 1 row
POST /admin/api/RmaCommentSave {"RmaId":"<new-number>", ...}
  -> "The RMA is not found. Id: <new-number>"
```

**Publish readable claim numbers through the counter instead**, which also means a claim filed live
through the storefront gets the right number with no SQL in the loop at all:

```sql
-- local installs only; no verb exposes the EcomNumbers counters. Owes no cache flush:
-- the counter is read at mint time. Prefer this to renaming a minted RMA.
UPDATE EcomNumbers SET NumberPrefix = '<prefix>', NumberCounter = <n> WHERE NumberType = 'RMA';
```

If a rename is genuinely unavoidable, make it the last write of the build and restart the
application pool after it, so no later command is keyed on an id the cache does not hold. MCP
`save_comment` is rung 1 for the comment write itself.

## Renaming an RMA state is three writes

| # | Surface | What it sets |
|---|---|---|
| 1 | Management API `RmaStateSave` `{Id, RmaStateTypeRelation, IsDefaultStateForNewRma}` | The flags: which RMA types the state serves, and which state new claims start in |
| 2 | Management API `RmaStateTranslationSave` `{Id, LanguageId, Name, Description}` | What the storefront renders |
| 3 | `SQL` — `UPDATE EcomRmaStates SET RmaStateDefaultName = ... WHERE RmaStateId = ...` | What the backend state list renders |

Step 3 is SQL because no verb writes that column: `RmaStateSave` with `Translated: true` skips it
and there is no untranslated variant that reaches it. **Local installs only**, and it owes the RMA
service flush below. Verify all three by reading the storefront badge, the claim-list column and
the backend state list and asserting they carry the same vocabulary.

## Empties differ by writer: guard with a coalesce, never `IS NULL`

`RmaSave` leaves `EcomRmaOrderLines.RmaOrderLineSerialNumber` NULL; the frontend RMA module writes
an empty string. A self-heal written as `WHERE ... IS NULL` therefore fires on API-created claims
and silently never fires on a storefront-filed one:

```sql
-- guard every "is this RMA field unset" test this way; still idempotent on re-render.
-- SQL because no verb writes the serial number on an existing relation row;
-- local installs only; owes the RMA service flush below.
UPDATE EcomRmaOrderLines SET RmaOrderLineSerialNumber = @s
 WHERE RmaOrderLineId = @id AND ISNULL(RmaOrderLineSerialNumber, '') = '';
```

## Every save of an existing RMA writes a customer-block comment

To delete the rows after a scripted `RmaSave` pass:
`DELETE FROM EcomRmaComments WHERE RmaCommentEvent = 'UserInfoChanged'`. SQL because no verb
deletes an RMA comment; **local installs only**; owes the service flush below, because the RMA
detail view serves the cached object graph and keeps rendering deleted rows without it. Filtering
the event in the details template is the option with no cleanup pass and no restart, and it is the
right one for a live site.

## Flush the RMA service after every raw-SQL write

```
POST /admin/api/CacheInformationRefresh
{ "CacheTypeName": "Dynamicweb.Ecommerce.Orders.ReturnMerchandiseAuthorization.ReturnMerchandiseAuthorizationService" }
```

- **Every raw-SQL write to RMA data is followed by that flush** — no application-pool recycle is
  needed. MCP `get_rma_states` reading back a state row inserted by SQL is the cheap proof that the
  flush landed.
- **Match FULL type names when hunting a cache id.** Filtering the cache list on the substring
  `rma` also matches `inteRMAtional`, `infoRMAtion` and `foRMAt`.
- **A SQL-only scheduled task cannot call that verb**, so a nightly date shift leaves the RMA
  detail view stale by design until the cache turns over.

`EcomRmaEmailConfigurations` is configured the same way: no MCP tool and no Management API verb
reaches that table; **local installs only**; flush the RMA service afterwards.
