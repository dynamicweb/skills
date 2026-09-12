# rma-claims.md

> Build a warranty, service or claims surface on a content-only budget by renaming the platform's own
> RMA machine — no DLL, no add-in, no notification subscriber, no scheduled task, no stock file
> modified. Plus the one shipped module setting that silently empties the claim form. Companion to
> [`customer-center.md`](customer-center.md) (the section this surface lives in) and
> [`fresh-deserialize-sweep.md`](fresh-deserialize-sweep.md) (the post-deserialize checklist this
> setting belongs on).
>
> Swift 2.x only — never follow `/swift/swift-1/` URLs.

## Contents

- [The claim form silently hides older orders](#the-claim-form-silently-hides-older-orders)
- [Rename the platform's RMA machine, never build a parallel entity](#rename-the-platforms-rma-machine-never-build-a-parallel-entity)
- [Step 1 — rename the states in place](#step-1--rename-the-states-in-place)
- [Step 2 — net-new template copies, stock files untouched](#step-2--net-new-template-copies-stock-files-untouched)
- [Step 3 — the serial-number column exists and the frontend input does not](#step-3--the-serial-number-column-exists-and-the-frontend-input-does-not)
- [Two template deltas worth copying](#two-template-deltas-worth-copying)
- [What to assert](#what-to-assert)

## The claim form silently hides older orders

**`<BoughtFromDate>` in the RMA paragraph's `ParagraphModuleSettings` filters the claim form's order
picker by order date, and a baseline can ship it as the date the paragraph was authored.** On any
install that is not brand new, every order older than that stamp is simply absent from the dropdown:
no message, no empty state, no error, no log entry. The form looks entirely healthy and omits the
orders, so a signed-in buyer cannot file a claim against anything historical, and the window drifts
further shut the older the baseline gets relative to the demo data.

Widen it on any install where historical purchases matter, and add it to the post-deserialize
checklist alongside the other rolling and stamped baseline values. The negative control is exact:
restore the shipped date and the dropdown empties with no message.

`ParagraphModuleSettings` is `nvarchar`, not `xml`, and a module paragraph caches its settings at
application start — read the edit rules and the restart obligation in [`paragraphs.md`](paragraphs.md)
(the module-settings section) before writing this field.

## Rename the platform's RMA machine, never build a parallel entity

**Dynamicweb's RMA machine already IS an individually-reviewed claim machine; it just speaks returns
vocabulary.** The instinct on a warranty or service beat is to model a parallel claim entity, and it
throws away four things the platform ships for free:

- `EcomRmaComments` records every state change with the new state id and a timestamp — that trail is
  the "every one of these was read by a person" story, and it is platform behaviour rather than demo
  theatre.
- The backend RMA screen drives the same transitions, so a presenter can flip a claim live in the
  admin and refresh the buyer's page.
- `EcomNumbers` mints the claim number.
- The states ship with a default-for-new flag, so there is **no auto-approve path** — which is the
  point being demonstrated, not a gap to fill.

Only the vocabulary and two templates are wrong for a warranty story, and both are data. The whole
pattern lands as four net-new files, zero stock files touched and zero compiled code.

## Step 1 — rename the states in place

Admin API `RmaStateSave` over the shipped states, widening each state's `RmaStateTypeRelation` to
every RMA type so the whole lifecycle is reachable whatever claim type is used, and keeping the first
state as `IsDefaultStateForNewRma`. A worked warranty mapping over the seven shipped states:

| Shipped state | Warranty vocabulary |
|---|---|
| Waiting for product(s) from customer | Submitted *(default for new)* |
| Received from customer | Under review |
| Rejected | Denied |
| Sent for repair | Approved |
| Received from repair | Repair completed |
| Returned to customer | Closed — credit issued |
| Sent replacement to customer | Warranty parts shipped |

Two sibling verbs carry the rest of the vocabulary, and one shipped string must be left alone:

- **`RmaStateTranslationSave` is what the storefront actually renders** — renaming the state without
  it changes the backend and nothing the buyer sees.
- `RmaEventTranslationSave` rewords the generic event descriptions.
- **Leave `EcomRmaEvents.RmaEventDescription` for the creation event as the literal shipped string.**
  The stock detail template splits the opening entry out of the history by matching that exact text,
  so rewording it collapses the history's first row into the trail.

## Step 2 — net-new template copies, stock files untouched

The RMA paragraph's `ParagraphModuleSettings` carries `<RMAListTemplate>` and `<RMADetailsTemplate>`.
Copy the two stock templates into the customer-centre template tree under new names and repoint those
two settings at the copies. The stock `RMAList.cshtml` / `RMADetails.cshtml` keep their shipped
mtimes, so a platform upgrade cannot break the demo and a template patch cannot break the upgrade.

Repoint the settings, then **restart the host before verifying**: the customer-experience-centre
module caches its settings at application start, so the change is committed and invisible until the
pool recycles ([`paragraphs.md`](paragraphs.md), the module-settings section). Do not follow the repoint with a
whole-model `ParagraphSave` — that rewrites module settings from cache and reverts them.

## Step 3 — the serial-number column exists and the frontend input does not

`EcomRmaOrderLines.RmaOrderLineSerialNumber` exists and `RmaOrderLineSave` writes it, but **the
frontend RMA module has no serial input and no request key for one** — `serialNumber` appears in the
commerce assembly only as a property and inside the table's own `UPDATE`. The zero-code route uses
the one free-text field the module does persist:

1. Render a format-validated serial field per claimed item on the claim form.
2. On submit, merge it into the REQUIRED fault-description comment as
   `Serial number: <serial> | Fault: …`.
3. On the first render of the finished claim, parse it back out and write it into the platform's own
   column with a guarded idempotent update
   (`… WHERE ISNULL(RmaOrderLineSerialNumber,'') = ''`). This is `SQL` because the write happens
   inside a render with no verb call available to it; it is local-install only, and the guard is what
   makes a repeated render safe. Where the build can call a verb instead, `RmaOrderLineSave` writes
   the same column and is the higher rung.
4. Both templates then read the COLUMN first, with the comment as the fallback.

The finished claim is identical to one created through `RmaOrderLineSave`. Prefer this to a compiled
notification subscriber: a DLL on a content-only budget buys nothing once the free-text field is
carrying the value.

**RMA rows are service-cached.** Any SQL write to `EcomRma*` owes a
`CacheInformationRefresh` on the RMA service — the list view reads SQL directly and shows the new
data while the detail view serves the pre-write object graph, so a correct-looking list hides a stale
detail ([`../../dw-data-access/references/cache-invalidation.md`](../../dw-data-access/references/cache-invalidation.md)).

## Two template deltas worth copying

- **The FILED date is the FIRST comment's date.** The platform's own RMA date tag renders the LAST
  comment date — last activity — which is the wrong column heading for a claim queue.
- **State-coloured badges driven off the state id**, plus a coverage panel resolved live from
  whatever registry the demo carries.

## What to assert

Walk the whole loop as a signed-in buyer, and make the run repeatable across a demo reset:

- The claim form lists **every** historical purchase order back to the oldest one in the data — this
  is the `<BoughtFromDate>` assert, and a form that renders is not evidence.
- The claim POST completes (302 to the new claim's own detail URL), the claim mints its number, and
  it lands in the default state — assert there is **no** auto-approve.
- The serial is in the platform column, the purchase order and purchase date resolve, and the review
  history renders the filing entry.
- Seeded claims render across several states with their full trails, and a state flip in the admin
  moves both the badge and the history on the buyer's page.
