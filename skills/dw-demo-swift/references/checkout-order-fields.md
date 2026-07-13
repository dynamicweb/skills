# checkout-order-fields.md — delivery date and custom order fields

> Owns the checkout order-field recipe for Swift demos: the stock delivery-date beat (needs no
> custom order field) and the platform contract a custom `EcomOrderField` definition must honor.
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs.

## The delivery-date beat needs NO custom order field

Stock Swift already carries it: enable **`EnableDeliveryDate`** on the `Swift-v2_CheckoutApp`
paragraph — checkout then renders a delivery-date picker and posts `EcomOrderShippingDate` into
the **native `OrderShippingDate` column** on the order row. Recent base layers ship the checkout
paragraph with it enabled; verify on the deserialized checkout page before authoring anything.
Reach for a custom order field only when the beat genuinely needs a field the order schema does
not already carry.

**Verify:** enable delivery date on checkout, place an order with a specific date, assert
`OrderShippingDate` is set on the order row and both the storefront My-orders list and the admin
order list render without exceptions.

## Custom order fields: the `EcomOrders` column contract

Order-field **values live in per-system-name columns on `EcomOrders`**, not in `OrderFieldsXML`.
An `EcomOrderField` definition row without a matching `EcomOrders.<SystemName>` column breaks
**every order read** — `OrderRepository.ExtractOrderFieldValues` throws
`System.IndexOutOfRangeException: <SystemName>`, taking down storefront My-orders AND the admin
order lists in one stroke.

When a custom order field is genuinely needed via SQL, create both halves in the same batch, then
flush:

```sql
INSERT INTO EcomOrderField (OrderFieldName, OrderFieldSystemName, OrderFieldTypeId, ...)
    VALUES (...);  -- OrderFieldTypeId MUST exist in EcomFieldType
ALTER TABLE EcomOrders ADD [<SystemName>] <type> NULL;
```

Flush the `OrderFieldService`/`OrderService` caches (or restart the host) before reading any
order.

## MCP `create_order_field` fails on a foreign-key violation (version-pinned)

`create_order_field` errors on every call: its MERGE into `EcomOrderField` passes an
`OrderFieldTypeID` not present in `EcomFieldType`, violating the
`DW_FK_EcomOrderField_EcomFieldType` constraint (verified DW 10.27.x — an upstream tool bug).
Until it is fixed, create the definition via the SQL contract above — and first ask whether the
beat needs a custom field at all (see the delivery-date rule).
