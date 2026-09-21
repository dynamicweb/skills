# Price providers, fee providers, and custom order-validation rules

Contracts for the three provider families that decide what an order costs and whether it may be
placed, measured on DW 10.27/10.28. Reached from [SKILL.md](../SKILL.md).

## Contents

- [Providers activate by attribute, not by a UI selection](#providers-activate-by-attribute-not-by-a-ui-selection)
- [An exclusive price provider honours only what its own scope test reads](#an-exclusive-price-provider-honours-only-what-its-own-scope-test-reads)
- [FeeProvider.FindFee must return null](#feeproviderfindfee-must-return-null)
- [Where a shipping fee result lands, and what it does not name](#where-a-shipping-fee-result-lands-and-what-it-does-not-name)
- [A payment surcharge is the payment-fee notification, not a FeeProvider](#a-payment-surcharge-is-the-payment-fee-notification-not-a-feeprovider)
- [A custom order-validation Rule](#a-custom-order-validation-rule)

## Providers activate by attribute, not by a UI selection

`FeeManager.InitializeFeeProviderTypes` is `AddInManager.GetTypes<FeeProvider>()`, and the price
family resolves the same way. **A `FeeProvider` or `PriceProvider` decorated `[AddInActive(true)]`
is live the moment its assembly loads** — there is no admin-UI step to perform and no
`GlobalSettings` node to write (`/Globalsettings/Ecom/**` carries no provider node of any kind).
Deploying the assembly is the whole activation step for these two families.

The corollary is that deploying a second provider of the same family silently joins an ordering you
did not choose — see the null contract below.

## An exclusive price provider honours only what its own scope test reads

A `PriceProvider` that declares `HandlePricesExclusively => true` replaces the platform's own price
resolution wholesale. **Every price column outside its own scope test becomes inert**, whatever the
data says. On one solution the provider's `ScopeMatches()` tested currency, country, shop, variant,
unit, user id, user group id, customer group id and validity — and never read
`PriceStockLocationID` or `PricePriority`. Stock-location-only rows all matched, so the cheapest won
at every location, and the priority column did nothing at all: the provider ranked candidates by
quantity, then a hard-coded specificity score, then lowest amount.

Two rules follow for any catalogue built on such a provider:

- **Resolve a scoped price through whatever the provider actually reads.** Where per-location pricing
  must work and the provider reads a user group, carry the location as a user group and populate the
  location column as well (it is the ERP-owned truth) rather than expecting the location column to
  drive anything.
- **Leave `PriceUnitId` empty on a single-unit catalogue.** A scope test that rejects any row
  carrying a unit id when the caller passes none kills that row for **every storefront lookup**,
  because the Swift storefront passes no unit on a price lookup — the whole catalogue renders as
  zero. A genuinely multi-unit catalogue needs the provider extended to handle a unit-less caller
  first.

Before assuming a price column is load-bearing, read the provider's scope test. It is the
specification.

## FeeProvider.FindFee must return null

`Dynamicweb.Ecommerce.Orders.FeeManager.FindFee(Order)` iterates `GetFeeProviders()` and **breaks on
the first non-null result**:

```
loc0 = null
foreach (p in GetFeeProviders())
    loc0 = p.FindFee(order)
    if (loc0 != null) break
return loc0
```

**Return `null` for the orders you do not price.** `null` means "no opinion, ask the next one". A
provider that returns `new PriceRaw(0, currency)` for the methods it does not care about is
returning a perfectly good answer, so it **suppresses every later fee provider and the fee matrix**
for the whole solution. The XML docs only show the free-shipping case, where returning null happens
to be the fallback, which is why the zero looks harmless.

Recognise the method the fee applies to by its **code**, not by a shipping id, so the provider
survives a re-created method.

## Where a shipping fee result lands, and what it does not name

`ShippingCalculator.Calculate` reaches `FeeManager.FindFee` only after three earlier arms:

| Order | Arm | `CalculationType` |
|---|---|---|
| 1 | `Shipping.FreeFeeAmount` reached | `FreeFee` (1), price 0 |
| 2 | `CalculateShippingDiscount` — a free-shipping reward short-circuit | — |
| 3 | `FeeRulesSource == 1` and a non-empty `ServiceSystemName` → `ShippingProvider.CalculateShippingFee` | 2 |
| 4 | otherwise, with a shipping method selected: `FeeManager.FindFee`, wrapped through `PriceCalculated` | `FeeProvider` (3) |
| 5 | else `TryFindFeeFromMatrix` | `Matrix` (5), or `PriceOverMaxWeight` (4) |

`Order.RecalculateShipping` sets **`Order.ShippingFeeRuleName` from `result.Fee.Name` only on
`Matrix` (5)**. The `FeeProvider` arm has no rule name by construction, so a template that expects
`Ecom:Order.ShippingFeeRuleName` to label the line renders an empty label — **name the line in the
template** when the fee comes from a provider.

## A payment surcharge is the payment-fee notification, not a FeeProvider

`FeeProvider.FindFee(Order)` is documented as **the shipping fee**, so using it for a card surcharge
quietly displaces whatever shipping fee the solution already computes there. A payment surcharge
belongs on `Ecommerce.Order.BeforePaymentFeeCalculation` instead — and that notification **is
writable**, despite documentation that reads otherwise:

| Member | XML doc says | Metadata says |
|---|---|---|
| `BeforePaymentFeeCalculationArgs.Order` | "Gets the order" | getter public, setter non-public |
| `BeforePaymentFeeCalculationArgs.PaymentFee` | "Gets the payment fee" | getter public, **setter public** |
| `PriceInfo.PriceWithVAT` / `.PriceWithoutVAT` / `.VAT` | — | **setters public** |
| `PriceInfo.Price` | — | no setter |

**Mutate the `PriceInfo` the args hand out, in place.** `PriceInfo.Add` / `Substract` / `Multiply`
are non-mutating — each **returns a new instance**, as their own doc says — so `fee.Add(surcharge)`
compiles, runs and changes nothing, with no error. `Add` is the method whose name matches the intent
and the one method that cannot serve it.

```csharp
fee.PriceWithoutVAT += amount;
fee.PriceWithVAT    += amount;
fee.VAT              = fee.PriceWithVAT - fee.PriceWithoutVAT;
payload.PaymentFee   = fee;
```

`Order` also exposes `AllowOverridePaymentFee` and `ExternalPaymentFee`, both with public setters,
as a separate order-level override channel.

For anyone asserting against a compiled binary: the emitted `SubscribeAttribute` value is
`DWN_ECOM_ORDER_BEFORE_PAYMENT_FEE_CALCULATION`, which is not derivable from the C# constant path.

## A custom order-validation Rule

**Every shipped ordering rule is numeric.** `GreaterThanRule` and `LessThanRule` run the value
through `Rule.TryParse`, which is `Double.TryParse`, so a date string parses to nothing and the rule
is vacuously false; `RegexRule` cannot express "today or later" because today moves. **Any date or
time comparison needs a custom rule.**

Registration is **by discovery**: `Rule.GetRuleTypes()` is a straight
`AddInManager.GetTypes<Rule>()`, so a public concrete subclass of
`Dynamicweb.Ecommerce.Orders.Validation.Rules.Rule` with a parameterless constructor is offered in
the backend the moment its assembly loads.

```csharp
[AddInName("Date not in the past")]
[AddInUseParameters(false)]
public class FutureDateRule : Rule
{
    public override string? Parameters { get; set; } = string.Empty;   // abstract on Rule
    public override bool Validates(string? value) { /* ... */ }        // abstract on Rule
}
```

Wiring is two rows, in `EcomValidations` (the field, its group and its type — `CustomOrderField` for
a custom order field) and `EcomValidationRules` (the validation id plus the rule's type name).
Neither table has an MCP tool or a Management API verb, so this is `SQL`, **local-install only**, and
the rows are read at validation time rather than cached, so nothing is owed beyond the write itself.

**Write `EcomValidationRules.ValidationRuleType` assembly-qualified.** `Rule.Create` resolves it
through `AddInManager.GetInstance<Rule>(typeName)`, which takes the deterministic `Type.GetType` path
for a qualified name and a fuzzy map/alias/search ladder for a bare one, throwing `Could not create
an instance of rule with type ...` when it loses. The built-in rows carry bare names only because
they live in `Dynamicweb.Ecommerce`.

Then add the validation to the CartV2 app's `SelectedValidations`, where it gets its own
`ErrorMessage_<id>`. **A second message needs a second `EcomValidations` row**, not a second rule on
the existing one — rules inside one validation share the message.

Leave emptiness to `RequiredRule` where one is already bound to the same field, or the two rules
double the message.

**Proving a server rule through a browser needs care.** A Swift-style step template installs its own
`submit` listener that calls `preventDefault`, so a real click never becomes a request and can
neither prove nor disprove the server rule. Post with
`HTMLFormElement.prototype.submit.call(form)` (which does not fire the submit event) with the forward
button's name injected as a hidden input on that form, or with `curl`.
