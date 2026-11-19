# Recipe index

Generated from `assets/recipes/` by `python scripts/validate_recipes.py --write-index`; the repository
validator fails when this file and the recipes disagree, so do not edit it by hand. The contract is
[recipes.md](recipes.md); a whole build runs through
[Invoke-DwRecipeSet.ps1](../scripts/Invoke-DwRecipeSet.ps1).

## Contents

- [Recipes](#recipes)
- [Run order](#run-order)
- [What stays planned](#what-stays-planned)
- [By function](#by-function)

## Recipes

| Recipe | Functions | Input section | Owner skill | MCP-only | Hosted | After a layer delivered it | Proven on |
|---|---|---|---|---|---|---|---|
| `commerce.customer-prices` | commerce.customer-prices, commerce.default-price, commerce.quantity-prices | `prices` | dw-commerce-b2b | yes | yes | verify | dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19 |
| `content.design-styles` | content.design-styles, swift.style-wiring, swift.website-settings | `brand` | dw-swift-building | yes | yes | both | dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19 |
| `content.page-seo` | content.page-seo, swift.header-footer, swift.website-settings | `debrand` | dw-content-modelling | yes | yes | verify | dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19 |
| `content.pages` | content.pages, content.paragraphs, content.grid-rows | `content.pages` | dw-content-modelling | yes | yes | verify | dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19 |
| `orders.completed-orders` | orders.completed-orders, orders.quotes, orders.favorite-lists, orders.order-numbering | `history` | dw-commerce-orders | no | no | verify | dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19 |
| `orders.payment-methods` | orders.payment-methods, orders.shipping-methods, swift.cart-checkout | `checkout` | dw-commerce-orders | no | yes | verify | dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19 |
| `pim.data-models` | pim.data-models, pim.field-scope, pim.field-display-groups, pim.completeness-rules | `catalogue` | dw-demo-pim | no | yes | verify | dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19 |
| `pim.documents` | pim.documents | `catalogue` | dw-demo-pim | no | no | verify | dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19 (MCP-only yes, hosted yes) |
| `pim.identifiers` | pim.identifiers, pim.images, commerce.stock-levels | `catalogue` | dw-demo-pim | yes | yes | verify | dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19 |
| `pim.workflow` | pim.workflow | `pim.workflow` | dw-demo-pim | no | yes | verify | dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19 |
| `users.accounts` | users.accounts, users.user-accounts, users.user-groups, swift.impersonation | `users.accounts` | dw-commerce-b2b | yes | yes | verify | dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19; dw 10.30.6, mcp 0.6.3-BETA, 2026-11-19 (MCP-only yes, hosted yes); dw 10.30.6, mcp 0.6.6-BETA, 2026-11-19 (MCP-only yes, hosted yes) |

## Run order

A recipe set runs the recipes whose input section the customer data file holds, in this order
(dependencies first, ties by id, a recipe that runs last at the end):

1. `content.design-styles`
2. `content.pages`
3. `pim.data-models`
4. `pim.identifiers`. After `pim.data-models`: Products are placed in the data models and write the spec fields that recipe creates.
5. `pim.documents`. After `pim.identifiers`: The documents are attached to the products that recipe creates.
6. `pim.workflow`. After `pim.data-models`: The workflow is attached to data models that recipe creates.
7. `users.accounts`
8. `commerce.customer-prices`. After `pim.identifiers`: The list price is patched onto a product the catalogue created; this recipe finds products by number and creates none. After `users.accounts`: The customer group, the account's customer number and the buyer the probes sign in as are that recipe's objects.
9. `orders.completed-orders`. After `users.accounts`: The orders, quotes and lists belong to the buyer that recipe creates with a password. After `pim.identifiers`: Order and quote lines name products the catalogue created. After `commerce.customer-prices`: A line is charged the buyer's price when it is added, and the order stores that total: prices first, or the history carries list prices.
10. `orders.payment-methods`. After `users.accounts`: The customer groups a method is scoped to, and the signed-in buyer whose offer the probes read, are created by that recipe; this one only names them.
11. `content.page-seo`. Last: A de-brand replaces a forbidden text wherever it shows, so it runs after every recipe that writes text; the forbidden text must not appear in another section of the input, or the next apply writes it back and the set never settles.

## What stays planned

A planned binding never executes; its step is BLOCKED where no other binding serves it, and the
work is done by hand or stays undone. Reasons as the recipes state them:

- `commerce.customer-prices`
  - step list-price write (mcp): A product is created, grouped and indexed by the catalogue recipe; this recipe prices products that exist and never creates one.
  - probe anonymous-list-price, probe anonymous-tier, probe buyer-contract-price, probe buyer-group-price, probe buyer-tier (mcp): No MCP tool returns the price a visitor or a signed-in user is charged: get_prices_by_product_id lists the stored rows, which the steps already read back, and force_price_recalculation prices an order without the frontend user's context.
- `content.design-styles`: nothing planned
- `content.page-seo`
  - probe mail-templates (mcp): read_file reads one template at a time and is not a list or get tool on the read allowlist; the order and notification mail templates under /Files/Templates are checked by hand until a scan over a template folder is allowlisted
- `content.pages`: nothing planned
- `orders.completed-orders`
  - step numbering write (admin-api): The ORDER series exists on every install; a site without it is not a Swift commerce site.
  - step counter write (admin-api): NumberSave answers ok and keeps the stored counter (sent 5000, read back 1); no MCP tool reaches EcomNumbers, so the counter moves only by placing orders or by a local SQL update.
  - step buyer write (mcp): The buyer, its account and its password are created by the users.accounts recipe; this recipe gives an existing buyer a history.
  - step order-states write (mcp): create_order_state needs the id of the order flow the state belongs to, which the input does not name; build the flow with the order-states reference, then name the state here.
  - step owners write, step quote-owners write (mcp): The owners are created by the users.accounts recipe; this recipe gives existing users a history.
  - step order-products write, step quote-products write (mcp): Products are created by the catalogue recipe; a history only names them.
  - step order-date write (mcp): No MCP tool and no Management API command sets an order's date: create_orders and update_orders carry none and OrderSave stamps now. Out of product it is local SQL keyed on the order id, written last.
  - step favourites write (mcp): No MCP tool and no Management API command writes a favourite list (EcomCustomerFavoriteLists). The signed-in buyer creates one with POST /dwapi/ecommerce/favorites/lists {name, description, isDefault} and adds products with POST /dwapi/ecommerce/favorites/items/{listId} {productId, quantity, note}; a recipe writes through MCP or the Management API only.
  - MCP-only: The numbering, completion and quote reads are Management API (GetNumbers, NumberSave, GetOrderList: search_orders leaves quotes out and is_order_complete answers bare text); no MCP or Management API write creates a favourite list or backdates an order.
- `orders.payment-methods`
  - step payment-scope write (mcp): Up to MCP 0.6.3 the MCP payment model carries no country relation and no user groups; from 0.6.6 save_payment_methods and get_payment_methods carry countryCodes (country and country\|region), still no user groups. The group scope is the Management API PaymentSave or the method's admin screen, and that whole-model save writes the country relation in the same call, so an MCP country write alone would not make the step MCP-only.
  - step shipping-scope write (mcp): The MCP shipping model carries no user groups and no default fee (save_shipping_methods, get_shipping_methods), and up to MCP 0.6.3 no country relation (0.6.6 adds countryCodes); the group scope and default fee are the Management API ShippingSave or the method's admin screen, whose whole-model save writes the country relation in the same call.
  - MCP-only: The country relation and the customer-group scope are on the Management API models only (PaymentsAll / PaymentSave, ShippingsAll / ShippingSave); the MCP method models carry neither, nor a shipping method's fee.
- `pim.data-models`
  - step categories find (mcp): No MCP read lists a category: get_product_category_fields returns the fields of CategoryFields categories, so a category without fields is invisible to it.
  - MCP-only: No MCP read lists a product category that has no fields yet (get_product_category_fields lists fields), so the category step needs the Management API read ProductCategoriesAll.
- `pim.documents`
  - MCP-only: On MCP 0.6.3 (the oldest proven release) no MCP tool and no recipe Management API command creates a product asset category, so a new category is made in the admin screen; an existing one is found over MCP and the files and documents are written over MCP. From MCP 0.6.6 save_product_asset_categories creates it and every step runs MCP-only (see provenOn).
- `pim.identifiers`: nothing planned
- `pim.workflow`
  - step workflow write (mcp): No MCP tool creates a workflow: create_or_update_workflow_states refuses workflowId 0.
  - step attach write (mcp): No MCP tool sets a data model's workflow: patch_data_models takes name, description, type and categoryId.
  - MCP-only: No MCP tool creates a workflow or attaches one to a data model; the states and transitions are MCP.
- `users.accounts`: nothing planned

## By function

| Function | Recipe |
|---|---|
| `commerce.customer-prices` | `commerce.customer-prices` |
| `commerce.default-price` | `commerce.customer-prices` |
| `commerce.quantity-prices` | `commerce.customer-prices` |
| `commerce.stock-levels` | `pim.identifiers` |
| `content.design-styles` | `content.design-styles` |
| `content.grid-rows` | `content.pages` |
| `content.page-seo` | `content.page-seo` |
| `content.pages` | `content.pages` |
| `content.paragraphs` | `content.pages` |
| `orders.completed-orders` | `orders.completed-orders` |
| `orders.favorite-lists` | `orders.completed-orders` |
| `orders.order-numbering` | `orders.completed-orders` |
| `orders.payment-methods` | `orders.payment-methods` |
| `orders.quotes` | `orders.completed-orders` |
| `orders.shipping-methods` | `orders.payment-methods` |
| `pim.completeness-rules` | `pim.data-models` |
| `pim.data-models` | `pim.data-models` |
| `pim.documents` | `pim.documents` |
| `pim.field-display-groups` | `pim.data-models` |
| `pim.field-scope` | `pim.data-models` |
| `pim.identifiers` | `pim.identifiers` |
| `pim.images` | `pim.identifiers` |
| `pim.workflow` | `pim.workflow` |
| `swift.cart-checkout` | `orders.payment-methods` |
| `swift.header-footer` | `content.page-seo` |
| `swift.impersonation` | `users.accounts` |
| `swift.style-wiring` | `content.design-styles` |
| `swift.website-settings` | `content.design-styles`, `content.page-seo` |
| `users.accounts` | `users.accounts` |
| `users.user-accounts` | `users.accounts` |
| `users.user-groups` | `users.accounts` |
