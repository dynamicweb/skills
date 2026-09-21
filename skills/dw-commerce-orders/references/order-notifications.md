# Order notification mail — which template renders, where it resolves, and how to assert it

Three mail settings on one solution resolve against three different roots, a failed template load is
delivered to the customer instead of aborting the send, and the artefact a harness counts decides
whether a committed message is visible at all. All measured on DW 10.28.x with Swift 2.

## Contents

- [Three mail settings, three resolution roots](#three-mail-settings-three-resolution-roots)
- [A template that will not load is MAILED, not aborted](#a-template-that-will-not-load-is-mailed-not-aborted)
- [The confirmation mail body may be a PAGE, not a template file](#the-confirmation-mail-body-may-be-a-page-not-a-template-file)
- [Cart-flow states notify exactly like order-flow states](#cart-flow-states-notify-exactly-like-order-flow-states)
- [Assert on the mail artefact's CONTENT, and snapshot Queue UNION Badmail](#assert-on-the-mail-artefacts-content-and-snapshot-queue-union-badmail)

## Three mail settings, three resolution roots

| Setting | Surface that owns it | The value is | Resolved under |
|---|---|---|---|
| `EcomOrderStates.OrderStateMailTemplate` | order-state / cart-state configuration | a bare **file name** — any directory in the value is **discarded** | `/Files/Templates/eCom/Order/` |
| `EcomRmaEmailConfigurations.RmaEmailConfigurationTemplate` | RMA email configuration | a **relative path** | the `/Files/Templates` **root** |
| `Mail1Template` on the cart app | the checkout app's module settings | a **design-relative** path | the design folder — and see the page route below |

The order-state rule is the one that surprises, because the folder that already holds the shipped
order mails (`eCom7/CartV2/Mail/`) is exactly the reasonable guess and is silently thrown away:
a value of `eCom7/CartV2/Mail/<name>.cshtml` is resolved as
`/Files/Templates/eCom/Order/<name>.cshtml`. Put the file at `/Files/Templates/eCom/Order/` and set
the bare file name.

The RMA rule and its tag set are in [`rma-and-claims.md`](rma-and-claims.md).

After changing the columns directly, flush `Dynamicweb.Ecommerce.Orders.OrderStateService` (and
`…Orders.OrderFlowService` if the flow itself moved) with Admin API `CacheInformationRefresh` —
the whole correction then costs no restart. Writing those columns is SQL because no verb reaches
the ten `EcomOrderStates` mail columns (MCP `create_order_state` exposes none of them); **local
installs only**.

## A template that will not load is MAILED, not aborted

When the template cannot be resolved, `OrderService.SendStateChangedEmail` logs the failure and
**sends the diagnostic as the message body**:

```
Template file not found (in RenderRazorTemplate()): …\Files\Templates\eCom\Order\<name>.cshtml
```

Everything around it is perfect — the queue row, both recipients, the sender, the subject — and the
order state changes normally, so the site shows no error at all and the defect survives review.
The only trace on the site is one event-log entry under
`OrderService.SendStateChangedEmail ← NotifyOrderStateChanged ← OrderService.Save`.

**So an assertion that "a mail was committed" proves nothing.** Assert on the body.

## The confirmation mail body may be a PAGE, not a template file

The cart app's module settings decide which body renders, and the page route leaves **no textual
reference to the real body anywhere on the solution** — grep cannot find the answer:

| `Mail1Template` | `Mail1RedirectType` / `Mail1RedirectPage` | What renders the body |
|---|---|---|
| set | — | that template |
| **empty** | `Page` / `Default.aspx?Id=<n>` | **the page** — typically an email-layout page whose one app paragraph (`eCom_ContextOrderRenderer`) names the template that actually holds the lines, subtotal, fees, taxes and total |

The shipped `eCom7/CartV2/Mail/Orders.cshtml` is then unreferenced dead code that reads exactly
like the live body — right content, right structure, wrong file — so a guard applied to it changes
nothing and the next order's mail is unchanged. **Read the cart app's `Mail1Template` /
`Mail1RedirectPage` settings before editing any confirmation-mail template**, and when the page
route is in use, follow it to the renderer paragraph's own `Template` setting.

That renderer paragraph also carries `RenderInTestMode` and `TestOrderId`, which is **the supported
way to preview a mail body in a browser without placing an order**.

## Cart-flow states notify exactly like order-flow states

Cart-flow states carry and honour the same six mail columns as order-flow states —
`OrderStateMailTemplate`, `OrderStateSendToCustomer`, `OrderStateSendToField`,
`OrderStateCustomRecipientField` and their siblings — and the mail is committed on both legs:
raised from C# (a subscriber setting `order.StateId` and calling `Services.Orders.Save`) and raised
from the frontend (`?CustomerCenterCmd=cartchangestate&CartId=<id>&StateId=<state>`) each commit
exactly one message, to the right single recipient.

State it plainly, because the alternative is a half-wired approval or saved-cart beat built around
"the platform will not mail on a cart state change". `OrderStateCustomRecipientField` resolves a
custom **order field** into the recipient, which is the same mechanism the order states use.

One rendering caveat: a mail has no page context, so any group-based guard in the body (a
hide-prices role, for example) resolves from `order.CustomerAccessUserId` rather than from the
page view — which is usually what you want, and is worth knowing before the body renders a dash
where a total is expected.

## Assert on the mail artefact's CONTENT, and snapshot Queue UNION Badmail

On a development or demo host whose SMTP has no deliverable domains, the two drop folders are
**different artefacts with different timings**:

| Folder | What it is | When it appears |
|---|---|---|
| `…\mailroot\Queue` | the **commit** artefact | immediately, when the platform commits the message |
| `…\mailroot\Badmail` | the **delivery** artefact (a DSN bounce copy) | only after the first delivery attempt fails and the retry timer expires — around a minute later |

A helper that counts only `Badmail` therefore reports **zero** for a message that has definitely
been committed, and then reports it as `+1` a minute later against whatever action happens to be
running — which is the single most common way to conclude a mail was not sent when it was. Two
readings taken seconds after a state change both said "no mail" on a message that was already in
`Queue`.

**The honest assertion surface is `Queue` UNION `Badmail`, snapshotted before and diffed after.**
The body is readable from either; the `Badmail` copy holds the original after the last
`Content-Type: message/rfc822` boundary, quoted-printable. Assert on the rendered content — state
name, order id, totals, the recipient-bearing field — never on the fact that a message exists.
