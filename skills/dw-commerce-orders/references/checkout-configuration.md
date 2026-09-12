# Checkout configuration — methods, fees, validation, custom fields, saved cards

What has to be true on the data side before a checkout can complete, and the traps in each piece:
country binding on payment and shipping methods, the fee-rules contract, the posted field names,
validation groups (which have no admin UI), custom order-line fields, and saved payment cards.

Surfaces below: MCP tools in `snake_case`, Admin API verbs in `PascalCase` at `/Admin/Api/<Verb>`,
posted form fields as frontend names, and `SQL` in fenced blocks — always with why the higher
rungs do not reach it, that it is **local-install only**, and what it owes afterwards.

## Contents

- [Method country binding is what decides whether checkout can complete](#method-country-binding-is-what-decides-whether-checkout-can-complete)
- [`ShippingSave` takes two fee sources, and the flat-rate recipe](#shippingsave-takes-two-fee-sources-and-the-flat-rate-recipe)
- [The payment radio's posted name drops a syllable the element id carries](#the-payment-radios-posted-name-drops-a-syllable-the-element-id-carries)
- [Validation groups: a dangling reference validates nothing, silently](#validation-groups-a-dangling-reference-validates-nothing-silently)
- [Validation fires on the step the field is posted on](#validation-fires-on-the-step-the-field-is-posted-on)
- [Writing `EcomValidation*` rows by hand](#writing-ecomvalidation-rows-by-hand)
- [An unset DATE custom order field reads back as a 1970 sentinel](#an-unset-date-custom-order-field-reads-back-as-a-1970-sentinel)
- [Order-LINE fields need no storage column — but they need a relation row](#order-line-fields-need-no-storage-column--but-they-need-a-relation-row)
- [Saved payment cards are service-only](#saved-payment-cards-are-service-only)
- [The zero-value "add a card" journey needs one global setting](#the-zero-value-add-a-card-journey-needs-one-global-setting)

## Method country binding is what decides whether checkout can complete

A payment or shipping method whose country-relation set does not contain the order's delivery
country is filtered out of the checkout step. With no method left, the delivery step renders **zero
radios, no error and no empty-state message**, the order summary says the delivery cost will be
calculated in the next step for ever, and the order can never complete. Nothing looks wrong from
the backend: every method is active, named and priced.

This bites hardest on a storefront moved off the baseline's country, because **payment masks it** —
the baseline payment methods often already carry the target country while none of the shipping
methods do, so the payment step looks healthy and only delivery is dead.

- **Re-point `countryRelationKeys` on the shipping methods AND the payment methods as a
  first-class setup step** whenever the storefront serves a country the shipped methods do not
  relate to. Relating the countries explicitly is the honest shape; a method with no relations at
  all behaves inconsistently.
- **Gate it: assert a non-zero delivery-option count for the target country, per persona.** A
  checkout that cannot complete is otherwise invisible until somebody walks the whole flow by hand.

Writing the relation rows directly (`EcomMethodCountryRelation`) is legitimate when the method
verbs are not in play, and carries one schema trap: **`MethodCountryRelRegionCode` is `NOT NULL`**,
unlike every other optional column on that table. A country-only relation with no region
restriction must supply `''`, not `NULL`; `NULL` terminates the whole `INSERT` and nothing in the
shape of the table hints at it. That write is **local-install only** and owes an order-method cache
flush before the storefront reflects it — prefer Admin API `ShippingSave` / `PaymentSave` with
`countryRelationKeys`, which writes the same rows through the domain service.

## `ShippingSave` takes two fee sources, and the flat-rate recipe

`EcomShippings.ShippingFeeRulesSource` is an int with **exactly two API strings on 10.28.x**:
`provider` (1) and `matrix` (2). Anything else — `default`, `fixed` — throws inside the invocation
and surfaces as a bare `HTTP 500 "Exception has been thrown by the target of an invocation"` with
no field name, indistinguishable from a broken model, a bad id or a sick host.

**To publish a flat freight rate with no fee matrix authored**, save with `feeRulesSource: "matrix"`,
`maxWeight: 0` and the fee in `defaultFee`:

```
POST /Admin/Api/ShippingSave
{ …, "feeRulesSource": "matrix", "maxWeight": 0, "defaultFee": 18.50,
     "countryRelationKeys": [ … ] }
-> ok.  EcomShippings.ShippingFeeRulesSource = 2, ShippingPriceOverMaxWeight = 18.50, no EcomFees rows
```

With an empty `EcomFees` matrix and `maxWeight = 0`, `defaultFee` (stored as
`ShippingPriceOverMaxWeight`) is what the cart charges. Re-point the countries first, then the
fee — a method the delivery step filters out is invisible whatever its fee says.

## The payment radio's posted name drops a syllable the element id carries

The `eCom/CartV2` payment radio renders as:

```html
<input type="radio" id="EcomCartPaymentmethodID_{PaymentMethodID}"
                  name="EcomCartPaymethodID" value="{PaymentMethodID}">
```

The element **id** carries `Paymentmethod`; the **posted name** is `EcomCartPaymethodID`. Shipping
is **not** symmetrical — there the name is `EcomCartShippingmethodID` — so assuming the pattern
from the shipping step produces a wrong guess on payment, and a post under the wrong name answers
`200` with the payment step re-rendered and a validation alert, leaving `EcomOrderPaymentMethod`
unset. It reads exactly like "the payment method is misconfigured" and nothing in the response
names the field.

**A checkout walker posts the radio's parsed `name` attribute, read out of the rendered step** —
never the id, and never by analogy with the shipping step. Two further silent gates sit on the same
flow: the final step needs `EcomOrderCustomerAccepted=True` (the terms checkbox) or it silently
re-renders the same step, and a plain follow-redirects flag on that POST turns the receipt redirect
into an HTTP 411 (the order still completes; only the receipt body is lost — preserve the method
across the redirect instead).

## Validation groups: a dangling reference validates nothing, silently

A cart app whose `ValidationGroups` setting names a group id with **no rows behind it validates
nothing at all** — no error, no warning, every field optional, checkout proceeds with every
required field empty. A database restore or a site copy that drops `EcomValidationGroups`,
`EcomValidations`, `EcomValidationRules` and `EcomValidationGroupsTranslation` leaves the paragraph
settings pointing at rows that no longer exist and reports nothing.

**Add a post-restore check:** for every cart-app paragraph with a non-empty `ValidationGroups`
setting, confirm the referenced group id exists in `EcomValidationGroups` with at least one
`EcomValidations` row, and fail the check if the reference dangles.

## Validation fires on the step the field is posted on

**A validated field gates the step it is rendered and posted on**, not a fixed Checkout step.
Measured on two adjacent steps of one cart app: fields bound to a group and rendered on the second
step were **not** caught moving from step one (where those inputs are absent from the form) and
**were** caught moving off step two, with each rule's configured message in the step's alert block.
Bind validation to the step where you want the buyer stopped, and test it there.

## Writing `EcomValidation*` rows by hand

There is no admin UI for validation groups, so the rows are written directly into the three tables.
This is one of the narrow sanctioned SQL cases — no MCP tool and no Admin API verb reaches these
tables at all — and it is **local-install only**; after the insert, the cart app picks the rows up
on the next request with no flush, but a paragraph-settings change alongside it owes the usual
paragraph cache turnover.

The column contracts are not obvious from the schema:

| Column | Contract |
|---|---|
| `EcomValidations.ValidationFieldType` | the C# **enum member NAME** as a string: `CustomOrderField` (0), `StandardOrderField` (1), `OrderLineField` (2) |
| `EcomValidationRules.ValidationRuleType` | the **fully-qualified** rule class name, e.g. `Dynamicweb.Ecommerce.Orders.Validation.Rules.RequiredRule` |
| every `*AutoId` column | `IDENTITY` — never supply one |
| `EcomValidations.ValidationUseAndOperator` | `1` = all rules on the field must validate |
| `EcomValidationGroups.ValidationGroupDoNotValidateIfAllFieldsAreEmpty` | `0` to validate even when the whole group is blank |

```sql
INSERT INTO EcomValidationGroups
  (ValidationGroupId, ValidationGroupName, ValidationGroupDoNotValidateIfAllFieldsAreEmpty)
VALUES ('VALIDATIONGROUP10', 'Checkout', 0);

INSERT INTO EcomValidations
  (ValidationId, ValidationGroupId, ValidationFieldName, ValidationUseAndOperator, ValidationFieldType)
VALUES ('VALIDATION30', 'VALIDATIONGROUP10', '<CustomOrderFieldSystemName>', 1, 'CustomOrderField');

INSERT INTO EcomValidationRules
  (ValidationRuleId, ValidationRuleValidationId, ValidationRuleType, ValidationRuleParameters)
VALUES ('VALIDATIONRULE30', 'VALIDATION30',
        'Dynamicweb.Ecommerce.Orders.Validation.Rules.RequiredRule', '0');
```

Bind the group to the cart app's `ValidationGroups` setting and list the individual validation ids
in `SelectedValidations`. Prove it by submitting the step with the field empty and asserting the
step blocks.

## An unset DATE custom order field reads back as a 1970 sentinel

`OrderFieldValue.Value` for a never-set date-type custom order field is a **1970-01-01 sentinel**,
not `null` or `DBNull`. A template that binds it straight into an `<input type="date">` value
pre-fills every picker with 1970-01-01 instead of leaving it blank.

**Guard it: treat any date before the year 2000 as empty** before binding a custom date field to a
date input, and assert the rendered input value is empty on a cart where the buyer never set it.

## Order-LINE fields need no storage column — but they need a relation row

**The `EcomOrderField` storage-column rule does not generalise to order-LINE fields**, and knowing
that changes the cost of a whole class of customisation from "needs a maintenance window" to "is a
row". The two shapes differ in where the values live, and the difference is invisible from the
definition tables:

| | Order fields (`EcomOrderField`) | Order-line fields (`EcomOrderLineFields`) |
|---|---|---|
| Value storage | a **real column on `EcomOrders`** per field | one shared `nvarchar(max)` blob, `EcomOrderLines.OrderLineFieldValues`, already present on every line |
| A definition with no backing storage | throws on **every** order read, on every surface, immediately | harmless — no read ever selects a column named after it; an absent entry is simply not in the collection |

So adding an order-line field is safe with no schema change and no restart. Writing a **value**
takes three things, and the third is the one that costs a day:

1. **The definition** — an `EcomOrderLineFields` row (`OrderLineFieldSystemName`,
   `OrderLineFieldName`, `OrderLineFieldLength`). SQL, because no MCP tool or Admin API verb
   creates one; **local installs only**; flush `Dynamicweb.Ecommerce.Orders.OrderService` and
   `…Orders.OrderLineFieldService` with Admin API `CacheInformationRefresh` afterwards. **A
   definition alone is inert:** the cart asks the order-line field service which fields apply to
   the shop or group it is working in, and with no relation row the answer is none, so a posted
   value is dropped in silence.
2. **An `EcomOrderLineFieldGroupRelation` row** for the shop (a shop relation alone is sufficient;
   group relations behave identically).
3. **The cart input name `OrderLineFieldValue_<orderLineId>_<systemName>`**, posted on
   `cartcmd=updateorderlines`. The platform's own helper produces it
   (`OrderLineFieldValue.GetCartInputFieldName(orderLineId)`). No add-time shape works: the
   unqualified, bare and double-underscore variants on `cartcmd=add` all materialise an entry with
   an **empty** value.

**The entry is materialised when the ORDER LINE is created, from the relation set as it stood at
that moment.** Adding the relation afterwards fixes every future line and no existing one — the
line you have been testing against will never accept a value, however many times you post, while
the identical post on a line created five seconds later works. **Re-add the line** after adding the
relation; the natural debugging loop (keep posting at the same line while changing things) can
never succeed.

Practical build shape: `cartcmd=setmulti` to create the lines (it materialises the entries too),
then one `cartcmd=updateorderlines` to write the values — two posts for an N-line pad. From Razor
the same values are readable and writable through `line.OrderLineFieldValues` followed by
`Services.Orders.Save(order)`; the write **returns false when the entry is absent**, which is the
only way to notice the missing-relation failure without reading the database.

## Saved payment cards are service-only

The entity naming hides the surface: the entity is
`Dynamicweb.Ecommerce.Cart.PaymentCardToken` over the table `AccessUserCard` (the `SavedCard*`
types are view models, and there is no `SavedCard` entity), and the service is
`Dynamicweb.Ecommerce.Services.PaymentCard`.

**No SQL `INSERT` can produce a usable card row.** `PaymentCardRepository` inserts the row and then
runs a second statement setting `AccessUserCardCheckSum` to a SHA-512 hash over
`ID;UserID;Token;PaymentID;CardType` — and `ID` is the identity the `INSERT` has just assigned, so
the checksum is not knowable before the row exists. `PaymentCardToken.CheckSum` has an internal
setter for the same reason, and a card with a wrong checksum is unusable.

```csharp
var card = Services.PaymentCard.CreatePaymentCard(userId, order.PaymentMethodId,
                                                  cardName, cardType, maskedIdentifier, token);
card.ExpirationMonth = month; card.ExpirationYear = year; card.IsDefault = true;
Services.PaymentCard.Save(card);
```

The service also carries `Delete`, `GetById`, `GetByToken`, `GetByUserId`, `GetByCustomerNumber`,
`RenamePaymentCard` and `SetDefaultPaymentCard`; cards written this way render in the shipped
saved-card list with working rename, set-default and delete modals and are selectable at checkout.
`AccessUserCardLanguageID` has no CLR property and is always written as an empty string.

**There is no notification for a card create or delete anywhere in the platform** — no card-related
notification name in any shipped assembly, and no `Notify` call on the repository path. Any policy
about who may save a card therefore has to live inside the checkout handler that mints it.

## The zero-value "add a card" journey needs one global setting

The shipped "Add credit card" page is a cart app whose steps are name-the-card → checkout →
receipt redirect, and whose whole purpose is a **zero-value order that mints a gateway token
without buying anything** — the shape a tokenising gateway wants. On a stock install it can never
leave step one: the order has no order lines, so every request logs
`No orderlines exist - emptying cart` in `EcomOrderDebuggingInfo` and resets the step index with
it. The page re-renders the first step for ever, with no error and no validation message, and it
reads as a broken step-advance button. **That log line is the only trace there is.**

One write turns the journey on:

```
POST /Admin/Api/GlobalSettingSave
{"Model":{"key":"/Globalsettings/Ecom/Cart/DoNotDeleteCartsWithZeroOrderlines","value":"True"}}
GET  /Admin/Api/GlobalSettingByKey?key=/Globalsettings/Ecom/Cart/DoNotDeleteCartsWithZeroOrderlines
  -> {"value":"True"}
```

The setting is absent from a stock `GlobalSettings.config`, and therefore `False`.

**Second trap on the same journey: the card page's payment-method whitelist does not decide the
method.** A buyer whose terms group also offers an on-account method had the zero-value order
completed by that method — no checkout handler, sort order 0 — so it completed at 0.00 and
redirected to the card list with **no token minted**, which looks exactly like success. Prove the
journey with a buyer whose groups leave exactly one payment method available, or set the cart's
payment method explicitly before the checkout step.
