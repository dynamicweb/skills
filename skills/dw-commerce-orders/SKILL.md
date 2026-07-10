---
name: dw-commerce-orders
type: knowledge
group: commerce
description: 'Handle orders, checkout, and cart functionality in Dynamicweb 10. Triggers: order management, checkout flow, cart handling, pricing. Non-triggers: product catalog -> dw-commerce-catalog; B2B patterns -> dw-commerce-b2b.'
---

# Orders, Checkout, and Cart

## Order Lifecycle

Orders move through configurable **Order Flows**: `Settings > Areas > Commerce > Order Management > Order Flows`. A flow is a named set of states (e.g., Received → Picked → Shipped → Completed). Each state has a name, description, color, a Default flag (applied to newly created orders), and optional notification email configuration.

Orders can be created by:
- Cart checkout
- Subscription auto-generation
- Quote conversion (`AcceptQuote` command)
- External import (ERP/POS)

**Cancellation operations:**
- **Cancel** — uncaptured orders only; cancels payment authorizations and returns stock
- **Delete** — orders not yet completed or cancelled
- **Refund** — full or partial; requires a refund-capable payment provider

## Shopping Cart App

The **Shopping Cart** app handles the checkout flow. Key configuration settings:

| Setting | Description |
|---------|-------------|
| Channel | Ecommerce channel for this cart |
| Context cart | Shared cart across multiple pages |
| Checkout to quote | Convert checkout submission to a quote instead of an order |
| Steps | Multi-step checkout configuration (each step has a label and template) |
| Notification emails | Emails sent on order creation |
| Field validation | Stock check, Terms & Conditions, custom validation |
| User management | Apply user details to order, create user account during checkout |

**Step structure:** One step must be designated the **Checkout step** (system step that converts cart to order; no template). Steps before collect info; the step after is the Receipt step.

## Checkout Form Fields

All checkout data is submitted via a form with `id="ordersubmit"`. These are the standard field names:

### Billing

```html
<input name="EcomOrderCustomerCompany" />
<input name="EcomOrderCustomerFirstName" />
<input name="EcomOrderCustomerSurname" />
<input name="EcomOrderCustomerEmail" />
<input name="EcomOrderCustomerAddress" />
<input name="EcomOrderCustomerZip" />
<input name="EcomOrderCustomerCity" />
<input name="EcomOrderCustomerCountry" />    <!-- ISO country code -->
<input name="EcomOrderCustomerVatRegNumber" />
<input name="EcomOrderCustomerEAN" />
```

### Delivery

```html
<input name="EcomOrderDeliveryFirstName" />
<input name="EcomOrderDeliveryAddress" />
<input name="EcomOrderDeliveryZip" />
<input name="EcomOrderDeliveryCity" />
<input name="EcomOrderDeliveryCountry" />
```

### Payment and Shipping

```html
<!-- Radio buttons: one per payment method -->
<input type="radio" name="EcomCartPaymethodID"
       id="EcomCartPaymethodID_{PaymentMethodID}"
       value="{PaymentMethodID}" />

<!-- Radio buttons: one per shipping method -->
<input type="radio" name="EcomCartShippingmethodID"
       id="EcomCartShippingmethodID_{ShippingMethodID}"
       value="{ShippingMethodID}" />
```

### Other Cart Fields

```html
<input name="EcomOrderCustomerVoucher" />
<input name="EcomOrderPointsToUse" />
<input name="EcomOrderGiftCardCode" />
<input name="EcomOrderSubscribeToNewsletter" value="True" />
<input name="EcomOrderCustomerAccepted" value="True" />   <!-- Terms & Conditions -->
<input name="EcomRecurringOrderCreate" value="True" />
<input name="EcomOrderSavedCardCreate" value="True" />
```

**Custom order line fields:** Submit by system name directly — no prefix needed.

## Cart Commands

Trigger via URL parameter `?CartCmd=` or as a hidden form field `<input name="CartCmd" value="..." />`.

### Product Commands

| Command | Required params | Optional params |
|---------|----------------|----------------|
| `add` | `productid` | `variantid`, `cartid`, `unitid`, `Quantity`, `EcomOrderLineFieldInput_{FieldSystemName}` |
| `addmulti` | `productid`, `Quantity` | Multiple products |
| `setmulti` | `productid1`, `Quantity1`... | Indexed multi-product |
| `incorderline` | `key` (orderline key) | — |
| `decorderline` | `key` | — |
| `delorderline` | `key` | — |
| `updateorderlines` | `QuantityOrderLine{ID}` for each line | — |
| `emptycart` | — | — |
| `deleteallorderlines` | — | — |

### Cart Object Commands

| Command | Required params | Notes |
|---------|----------------|-------|
| `archive` | — | Archive current cart |
| `copy` | `CartId`, `CartName`, `CartUserId` | `CartUserId` must be current or impersonatable user |
| `createnew` | — | Create new empty cart |
| `setcart` | `Cartid` | Switch to a different cart |
| `setdiscount` | `OrderDiscount` or `OrderDiscountPercentage` | Requires impersonation rights |
| `setname` | `CartName` | Rename current cart |
| `loadorder` | `OrderId` | Load a previous order as cart |

## Payment Methods

Admin path: **Settings > Areas > Commerce > Order Management > Payment**

| Tab | Settings |
|-----|---------|
| General | Name, Active, Description |
| Countries | Restrict to specific countries |
| Provider | Select a CheckoutHandler add-in |
| Fees | Fixed or percentage fee, with optional free-above threshold |
| Other | Frontend user groups, icons |

**Fee specificity rule:** A country-restricted fee overrides a global fee for the same payment method.

## Shipping Methods

Admin path: **Settings > Commerce > Order Management > Shipping**

| Tab | Settings |
|-----|---------|
| Provider | GLS, Shipmondo, or other shipping provider add-in |
| Fees | Matrix: weight/volume/user/product/country/currency/zip rules |
| Availability | Countries, Frontend user groups, Product/Group inclusions/exclusions, Weight limits |

## OrderViewModel / OrderListViewModel

### OrderListViewModel — Customer Experience Center

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Ecommerce.Frontend.OrderListViewModel>
```

| Property | Description |
|----------|-------------|
| `Model.Orders` | Collection of orders |
| `Model.PageCount` | Total pages |
| `Model.CurrentPage` | Current page (1-indexed) |

Each order in `Model.Orders`:

| Property | Description |
|----------|-------------|
| `order.Id` | Order ID |
| `order.CreatedAt` | Creation date |
| `order.CustomerName` | Customer display name |
| `order.Price.PriceFormatted` | Total formatted price |
| `order.StateName` | Current order state name |

### CEC Query String Filters

| Parameter | Description |
|-----------|-------------|
| `PageNum` | Page number |
| `PageSize` | Orders per page |
| `SortBy` / `SortOrder` | Sorting |
| `FilterOrderStateId` | Filter by state |
| `FilterFromDate` / `FilterToDate` | Date range |
| `FilterOrderId` | Specific order ID |
| `FilterText` | Free-text search |
| `FilterCustomerName` | Customer name filter |
| `FilterProductId` / `FilterProductNumber` | Product filter |

### OrderViewModel — Order Detail

```razor
@inherits Dynamicweb.Rendering.ViewModelTemplate<Dynamicweb.Ecommerce.Frontend.OrderViewModel>
```

| Property | Description |
|----------|-------------|
| `Model.Id` | Order ID |
| `Model.CompletedDate` | Completion date |
| `Model.StateName` | Current state |
| `Model.OrderLines` | Collection of order lines |
| `Model.ShippingMethod.Name` | Shipping method name |
| `Model.ShippingFee.PriceWithVatFormatted` | Shipping cost |
| `Model.PaymentMethod.Name` | Payment method name |
| `Model.Price.PriceWithVatFormatted` | Order total |

Each order line:

| Property | Description |
|----------|-------------|
| `line.ProductName` | Product name |
| `line.Quantity` | Ordered quantity |
| `line.TotalPriceWithProductDiscounts.PriceWithVatFormatted` | Line total |
| `line.OrderLineFields` | Custom order line field values |

### CustomerCenter Commands

```
?CustomerCenterCmd=Reorder&OrderId={OrderId}
?CustomerCenterCmd=AcceptQuote&QuoteId={QuoteId}
```

Change cart state (B2B quote/cart flows):
```html
<form method="post">
    <input name="CustomerCenterCmd" value="cartchangestate" />
    <input name="CartID" value="{CartID}" />
    <input name="StateId" value="{StateId}" />
</form>
```

## Pitfalls

**Form must have `id="ordersubmit"`** — the Shopping Cart app binds to this ID. A missing or different ID prevents checkout submission from working.

**`EcomOrderCustomerCountry` expects ISO code** — passing a display name ("Germany") instead of the code ("DE") causes country lookup to fail.

**Payment/shipping availability** — if no payment or shipping method is available for the customer's country/group combination, checkout halts. Always test with the target country context.

**Quote vs order** — "Checkout to quote" on the Shopping Cart app changes the checkout step output. The quote appears under Commerce > Quotes, not Commerce > Orders.

## Next Steps

- **Setting up assortments or B2B flows?** See [dw-commerce-b2b](../dw-commerce-b2b)
- **Displaying the product catalog?** See [dw-commerce-catalog](../dw-commerce-catalog)
- **Custom checkout handler / payment gateway?** See [dw-extend-providers](../dw-extend-providers)
- **Reacting to order events in code?** See [dw-extend-providers](../dw-extend-providers)
