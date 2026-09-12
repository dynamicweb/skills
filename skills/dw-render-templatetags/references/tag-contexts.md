# Tag contexts: proving a tag name, and tags that lie

Two failure shapes that look identical in a rendered template and are not: a tag name that is
**wrong** (returns an empty string, so a whole table renders blank) and a tag name that is **right
but means something other than its position suggests** (returns a plausible value on every row).
Both are read through the **template surface** — `GetString` / `GetBoolean` / `GetLoop` in a
`.cshtml`.

## Contents

- [1. A blank table is not an unpopulated context](#1-a-blank-table-is-not-an-unpopulated-context)
- [2. The RMA notification email context](#2-the-rma-notification-email-context)
- [3. Tags whose value is not per-row](#3-tags-whose-value-is-not-per-row)

## 1. A blank table is not an unpopulated context

`Template.GetString` returns an **empty string for an unknown tag**. There is no error, no log
entry and no visual difference between "the platform does not populate this context" and "every one
of these five names is misspelled". A table of blanks reads as the former and is usually the latter.

**Prove the names from the renderer before concluding the context is empty.** Each notification and
module context is built by one renderer class that sets its tags by literal string; enumerate those
literals (read the renderer in the Dynamicweb source, or its IL) and compare them with what the
template asks for. See [dw-source-explorer](../../dw-source-explorer/SKILL.md) for reaching the
source.

The names do not follow one convention across entities, so guessing from the entity name is the
trap rather than the shortcut — §2 is the worked case.

## 2. The RMA notification email context

`ReturnMerchandiseAuthorizationEmailRenderer.RenderEmail` populates this context **fully**. The
prefix is `Ecom:Rma.` — **mixed case**, and the only prefix on the platform that is not the
upper-cased entity name — and two of the names differ from the obvious guess.

| Asked for (wrong) | Actual tag | Why |
|---|---|---|
| `Ecom:RMA.*` | `Ecom:Rma.*` | Prefix casing |
| `Ecom:Rma.OrderID` | `Ecom:Rma.OriginalOrderId` | Derived from the first RMA order line — `EcomRmas` carries no order column at all |
| `Ecom:Rma.Status` | `Ecom:Rma.StateName` (the name) / `Ecom:Rma.State` (the description) | The status splits in two |

The full tag set:

| Group | Tags |
|---|---|
| Header | `Ecom:Rma.ID`, `Ecom:Rma.OriginalOrderId`, `Ecom:Rma.State`, `Ecom:Rma.StateName`, `Ecom:Rma.Created`, `Ecom:Rma.Type`, `Ecom:Rma.ReplacementOrderId` |
| Customer | `Ecom:Rma.Customer.{Address, Address2, Name, Number, Company, Zip, City, Country, Region, Phone, Fax, Email, Cell, RefID, EAN, VatRegNumber}` |
| Delivery | `Ecom:Rma.Delivery.{Company, Address, Address2, Name, Zip, City, Country, Region, Phone, Fax, Email, Cell}` |
| Comments loop | `GetLoop("Ecom:Rma.Comments")` → `Ecom:Rma.Comment.{id, Text, CreatedDate, NewState, Event, Event.isStateChanged}` |
| Lines loop | `GetLoop("Ecom:Rma.RmaOrderLines")` → `Ecom:Rma.RmaOrderLine.SerialNumber`, plus the order-line tag set |

**This is the notification-email context only.** The customer-center RMA app renders from its own
context (`Ecom:CustomerCenter.RMA.*` and its own `Ecom:RMA.*` names) — a different renderer, a
different tag set. Do not port names between the two.

**Two things the renderer does not give a template**, and which therefore need a notification
subscriber on `Ecommerce.Rma.BeforeRmaEmailSend` (whose args expose the whole
`System.Net.Mail.MailMessage`, so the body is writable — see
[dw-extend-providers](../../dw-extend-providers/SKILL.md)):

- the returned lines with their **quantities** in any usable shape: the `RmaOrderLines` loop names
  only `SerialNumber`;
- a single **"the customer's note"** tag, as opposed to the whole comment history including
  state-change rows.

## 3. Tags whose value is not per-row

Inside a loop, a tag that carries the parent entity's value returns the **same** value on every
iteration. It is correct-looking, so the defect ships.

| Loop | Tag | What it actually resolves to |
|---|---|---|
| `Shippingmethods` | `Ecom:Cart.ShippingMethod.Price` (and `.Price.IsZero`) | the **order's** current shipping fee, identical on every row. There is no per-method price tag in the loop at all |

**Why it hides:** Swift 2's shipped `eCom7/CartV2/Step/Helpers/ShippingMethods.cshtml` prints that
tag per row and falls back to `Translate("Free")` when `IsZero`. On a stock install — every method
fee `0`, `EcomFees` empty — every row reads "Free" and the bug is invisible. It appears the first
time anything (a fee provider, a fee-matrix row, a shipping provider) makes the order's fee
non-zero: selecting the one expensive method makes every other method display that same price, so
the cheapest-looking option is whichever one the buyer has not selected. It reads as a pricing
defect, not a template defect.

**Render the platform's figure only on the row that is currently selected**, and render each other
row's real cost from its own source:

```cshtml
@if (!method.GetBoolean("Ecom:Cart.ShippingMethod.Price.IsZero") && isActive)
{
    <span class="text-price">@method.GetString("Ecom:Cart.ShippingMethod.Price")</span>
}
else if (thisRowHasAFee) { <span class="text-price">@Translate("Fee applies")</span> }
else                     { <span class="text-price">@Translate("Free")</span> }
```

*Assert:* render the same page with each radio selected in turn and compare the price column across
selections. A per-row price is stable; an order-level one moves with the selection.

**The general test for any in-loop tag:** change the parent entity's value and re-read the loop. If
every row moved, the tag is parent-scoped.

## Cross-references

- [dw-commerce-orders](../../dw-commerce-orders/SKILL.md) (`order-lifecycle.md`) — the order, cart
  and RMA state machines behind these contexts.
- [dw-extend-providers](../../dw-extend-providers/SKILL.md) — notification subscribers, including
  `Ecommerce.Rma.BeforeRmaEmailSend`.
- [dw-source-explorer](../../dw-source-explorer/SKILL.md) — reading a renderer's own tag literals.
