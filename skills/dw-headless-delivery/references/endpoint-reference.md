# Dynamicweb Delivery API — endpoint reference

The full `/dwapi/` endpoint catalog for headless builds. The conceptual overview,
authentication paths, and architecture notes live in the parent
[`SKILL.md`](../SKILL.md). Always cross-check exact request/response shapes against the
live schema at `https://<host>/dwapi/api.json` — it includes the custom fields and
product/content types configured for the specific solution.

## Contents

- [Content](#content) — pages, page views, paragraphs, grid rows, navigation, areas, translations
- [Products](#products) — listing/search, single product, variants, related, groups, BOM
- [Cart](#cart) — create/get, add items, update/remove lines, cart fields
- [Checkout](#checkout) — start, payment/shipping, create order, gateway callbacks
- [Orders](#orders) — list, get, search, reorder
- [Users](#users) — create, profile, addresses, passwords, multi-profile/impersonation
- [Favorites / Wishlists](#favorites--wishlists)
- [Internationalisation](#internationalisation)
- [Loyalty Points](#loyalty-points)
- [Forms](#forms)
- [Query endpoint](#query-endpoint)
- [Connectivity check](#connectivity-check)

---

## Content

### Pages and page views

Get a page by ID:

```http
GET /dwapi/content/pages/{id}
```

Get a page by URL path (the preferred approach for routing):

```http
GET /dwapi/content/pages/url?url=/my-page&hostname=mysite.com
```

Get the full rendered page view (page + all paragraphs + items):

```http
GET /dwapi/frontend/pageViews/{id}
GET /dwapi/frontend/pageViews/url?url=/my-page&hostname=mysite.com
```

`pageViews` is the primary endpoint for content rendering — it returns a single response containing everything needed to render a page. Use `pages` when you only need metadata.

### Paragraphs

Paragraphs are content blocks attached to pages. Fetch all for a page:

```http
GET /dwapi/content/paragraphs?pageId={pageId}
```

Or by URL:

```http
GET /dwapi/content/paragraphs/url?url=/my-page&hostname=mysite.com
```

### Grid rows

Get the layout grid for a page (columns, templates, paragraph positions):

```http
GET /dwapi/content/rows/{pageId}/{device}
```

`device` is typically `Desktop`, `Tablet`, or `Mobile`.

### Navigation

Get the navigation tree for an area:

```http
GET /dwapi/frontend/navigations/{areaId}?ExpandMode=all&StartLevel=1&StopLevel=3
```

Returns a hierarchical list of nodes with IDs, paths, levels, and menu/sitemap/breadcrumb visibility flags.

### Areas

Get all areas (websites/channels):

```http
GET /dwapi/content/areas
```

Get a specific area (includes language config, e-commerce settings, default currency, VAT settings):

```http
GET /dwapi/content/areas/{id}
GET /dwapi/content/areas/domain/{domain}
```

### Translations

Fetch all translations for a design layout:

```http
GET /dwapi/translations/{designName}
GET /dwapi/translations/area/{areaId}
GET /dwapi/translations/{designName}/{culture}
```

Translation endpoints require no authentication.

---

## Products

### Listing and searching

Search with query parameters:

```http
GET /dwapi/ecommerce/products/search?GroupId=&ProductName=chair&PageSize=24&CurrentPage=1
```

POST-based search with a request body (supports advanced filtering):

```http
POST /dwapi/ecommerce/products
Content-Type: application/json

{
  "groupId": "Furniture",
  "pageSize": 24,
  "currentPage": 1
}
```

### Single product

```http
GET /dwapi/ecommerce/products/{id}
GET /dwapi/ecommerce/products/{id}/{variantId}
```

### Variants

```http
GET /dwapi/ecommerce/variants/{productId}
```

Returns all variant combinations and their availability.

### Related products

```http
GET /dwapi/ecommerce/products/{id}/related
GET /dwapi/ecommerce/products/{id}/related/{relatedGroupId}
```

### Product groups (categories)

```http
GET /dwapi/ecommerce/groups
GET /dwapi/ecommerce/groups/{groupId}
```

### BOM (Bill of Materials)

```http
GET /dwapi/ecommerce/products/{id}/bom
```

---

## Cart

Carts are identified by a `secret` — a string token returned when a cart is created.

### Create or get active cart

```http
POST /dwapi/ecommerce/carts/create
Authorization: Bearer <token>
```

Get the active cart secret for the logged-in user:

```http
GET /dwapi/ecommerce/carts/active
Authorization: Bearer <token>
```

Get the cart by secret (works without authentication):

```http
GET /dwapi/ecommerce/carts/{secret}
```

### Add items

Add a single line:

```http
POST /dwapi/ecommerce/carts/{secret}/items
Content-Type: application/json

{ "productId": "PROD001", "variantId": "", "quantity": 2 }
```

Add or update a line (upsert by productId+variantId):

```http
PATCH /dwapi/ecommerce/carts/{secret}/items
Content-Type: application/json

{ "productId": "PROD001", "quantity": 3 }
```

Add multiple items at once:

```http
POST /dwapi/ecommerce/carts/additems
Content-Type: application/json

{
  "secret": "{secret}",
  "lines": [
    { "productId": "PROD001", "quantity": 1 },
    { "productId": "PROD002", "quantity": 2 }
  ]
}
```

### Update or remove lines

```http
PATCH /dwapi/ecommerce/carts/{secret}/items/{itemId}
DELETE /dwapi/ecommerce/carts/{secret}/items/{itemId}
DELETE /dwapi/ecommerce/carts/{secret}/items   ← removes all lines
```

### Update cart fields

Patch the cart to set customer info, discount codes, comments, or addresses:

```http
PATCH /dwapi/ecommerce/carts/{secret}
Content-Type: application/json

{
  "customerComment": "Leave at door",
  "voucherCode": "SAVE10"
}
```

---

## Checkout

### Start checkout

Transitions the cart to checkout state and returns available payment/shipping options:

```http
GET /dwapi/ecommerce/carts/{secret}/checkout
```

### Set payment and shipping

```http
PATCH /dwapi/ecommerce/carts/{secret}/payment/{paymentId}
PATCH /dwapi/ecommerce/carts/{secret}/shipping/{shippingId}
```

Get available options:

```http
GET /dwapi/ecommerce/payments
GET /dwapi/ecommerce/shippings
```

Find service points (parcel lockers, pickup points):

```http
GET /dwapi/ecommerce/shippings/FindServicePoints?shippingId=&countryCode=DK&zipCode=2100
```

### Create order

```http
POST /dwapi/ecommerce/carts/{secret}/createOrder
```

Returns the order ViewModel. If a payment gateway is involved, the ViewModel will include a redirect URL.

### Payment gateway callbacks

For server-to-server payment callbacks from the gateway:

```http
POST /dwapi/ecommerce/carts/{secret}/callback
POST /dwapi/ecommerce/carts/callback/{checkoutHandlerName}
```

---

## Orders

```http
GET /dwapi/ecommerce/orders
Authorization: Bearer <token>
```

```http
GET /dwapi/ecommerce/orders/{secret}
Authorization: Bearer <token>
```

Search with filters:

```http
GET /dwapi/ecommerce/orders/search?fromDate=2024-01-01&toDate=2024-12-31
Authorization: Bearer <token>
```

Reorder (adds previous order lines to active cart):

```http
POST /dwapi/ecommerce/carts/reorder
Content-Type: application/json

{ "orderSecret": "{orderSecret}" }
```

---

## Users

### Create user

```http
POST /dwapi/users/create
Content-Type: application/json

{
  "firstName": "Alice",
  "lastName": "Smith",
  "email": "alice@example.com",
  "userName": "alice@example.com",
  "password": "Secure123!"
}
```

### Get and update current user

```http
GET /dwapi/users/info
PATCH /dwapi/users/info           ← partial update (safe, only changes what you send)
PUT /dwapi/users/info             ← full replace (nulls any field not in the body)
```

Use `PATCH` for profile updates — `PUT` overwrites all unmapped fields with null.

### Addresses

```http
GET /dwapi/users/addresses
GET /dwapi/users/addresses/delivery
GET /dwapi/users/addresses/billing
POST /dwapi/users/address
PATCH /dwapi/users/address/{id}
DELETE /dwapi/users/address/{id}
```

### Password management

Forgot password flow:

```http
POST /dwapi/users/password/recover/request
Content-Type: application/json

{ "email": "alice@example.com" }
```

Complete reset with the token from the email:

```http
POST /dwapi/users/password/recover/confirm
Content-Type: application/json

{ "recoveryToken": "abc123", "newPassword": "NewSecure456!" }
```

Change password while logged in:

```http
POST /dwapi/users/password/change
Authorization: Bearer <token>
Content-Type: application/json

{ "currentPassword": "old", "newPassword": "new" }
```

### Multi-profile users and impersonation

Switch between profiles (shared username):

```http
GET /dwapi/users/info/profiles
GET /dwapi/users/info/profiles/switch?profileId={id}
```

B2B impersonation:

```http
GET /dwapi/users/impersonatees
Authorization: Bearer <token>

GET /dwapi/users/impersonate?userId=87
Authorization: Bearer <token>
```

---

## Favorites / Wishlists

```http
GET /dwapi/ecommerce/favorites/lists
POST /dwapi/ecommerce/favorites/lists
GET /dwapi/ecommerce/favorites/lists/{id}
PATCH /dwapi/ecommerce/favorites/lists/{id}
DELETE /dwapi/ecommerce/favorites/lists/{id}

GET /dwapi/ecommerce/favorites/items/{listId}
POST /dwapi/ecommerce/favorites/items/{listId}
PATCH /dwapi/ecommerce/favorites/items/{listId}/{id}
DELETE /dwapi/ecommerce/favorites/items/{listId}/{id}
```

---

## Internationalisation

```http
GET /dwapi/ecommerce/International/countries
GET /dwapi/ecommerce/International/currencies
GET /dwapi/ecommerce/International/regions/{countryCode}
```

---

## Loyalty Points

```http
GET /dwapi/ecommerce/loyaltyPoints/balance
GET /dwapi/ecommerce/loyaltyPoints/transactions
```

---

## Forms

Fetch a form definition (use to render fields dynamically):

```http
GET /dwapi/forms/{formId}
```

Submit a form (requires the form token returned in the form definition):

```http
POST /dwapi/forms/{formId}
Content-Type: application/json

{
  "formToken": "<token-from-form-definition>",
  "fields": {
    "Name": "Alice",
    "Email": "alice@example.com"
  }
}
```

---

## Query endpoint

Run a pre-configured backend query (search index / repository):

```http
GET /dwapi/query?QueryName=Products&RepositoryName=ProductsIndex&PageSize=10&CurrentPage=1
```

Additional parameters defined in the query can be passed as extra query string parameters. Macros are not available in headless — use custom parameters instead.

Pagination and sorting:

```http
GET /dwapi/query?QueryName=Products&RepositoryName=ProductsIndex&SortBy=Price&SortOrder=DESC&PageSize=24&CurrentPage=2
```

---

## Connectivity check

```http
GET /dwapi/feeds/VerifyConnection
```

Returns 200 if the API is reachable. Use as a health check or ping.
