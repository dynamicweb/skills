---
name: dw-headless-delivery
type: knowledge
group: headless
description: Build decoupled frontends using the Dynamicweb 10 /dwapi/ delivery API. Covers authentication, content, ecommerce, users, navigation, forms, and query endpoints. Triggers: REST API, delivery API, headless frontend, decoupled architecture, /dwapi/, React integration, Vue integration, Angular integration, HTMX integration, web components, fetch content from API, headless CMS, headless commerce. Non-triggers: server-side Razor templates -> dw-render-razor; building traditional Swift storefront -> dw-swift-building.
---

# Dynamicweb Headless Delivery API

The Dynamicweb Delivery API (`/dwapi/`) exposes CMS, Commerce, and PIM data as REST endpoints. Your frontend — React, Vue, Angular, HTMX, Web Components, or plain JavaScript — fetches content and commerce data from these endpoints. The backend remains Dynamicweb; the frontend is hosted wherever you want.

All responses are JSON ViewModels. The base URL is always `https://<your-host>/dwapi/`.

**Find the live OpenAPI schema** at `https://<your-host>/dwapi/api.json`. When the implementer gives you a hostname (e.g. `upwork-poc.dynamicweb.cloud`), fetch `https://upwork-poc.dynamicweb.cloud/dwapi/api.json` to see the exact schema and test against live endpoints.

This SKILL.md owns the gateway concepts — authentication and the headless architecture rules. The full endpoint catalog (content, commerce, users, forms, queries) lives one hop away in [`references/endpoint-reference.md`](references/endpoint-reference.md).

---

## Authentication

Most endpoints require a Bearer JWT. There are two issuance paths.

### User authentication (frontend users)

```http
POST /dwapi/users/authenticate
Content-Type: application/json

{ "userName": "alice@example.com", "password": "secret" }
```

Returns a token valid for 1800 seconds by default. Send it as:

```http
Authorization: Bearer <token>
```

Refresh before expiry:

```http
GET /dwapi/users/authenticate/refresh?expirationInSeconds=600
Authorization: Bearer <current-token>
```

Exchange an existing `Dynamicweb.Extranet` cookie for a JWT (useful for hybrid pages):

```http
POST /dwapi/users/token
```

### Service authorization (server-to-server)

For backend-to-backend calls where no user is involved, use an API key:

```http
POST /dwapi/serviceauth/token
Content-Type: application/json

{ "apiKey": "<your-api-key>" }
```

This issues a short-lived JWT suitable for server-side data fetching (SSR, build-time generation).

### Anonymous access

Content endpoints (pages, paragraphs, navigation, translations) are generally public. Cart and order endpoints require authentication. Check the `401` response — if you get one, the endpoint requires a token.

---

## Endpoint catalog

Every endpoint family lives in [`references/endpoint-reference.md`](references/endpoint-reference.md). Jump to the section you need:

| If you need to... | Section |
|---|---|
| Fetch pages, page views, paragraphs, grid rows, navigation, areas, translations | [Content](references/endpoint-reference.md#content) |
| List/search products, single product, variants, related, groups, BOM | [Products](references/endpoint-reference.md#products) |
| Create/get a cart, add items, update or remove lines, set cart fields | [Cart](references/endpoint-reference.md#cart) |
| Start checkout, set payment/shipping, create order, handle gateway callbacks | [Checkout](references/endpoint-reference.md#checkout) |
| List, get, search, or reorder orders | [Orders](references/endpoint-reference.md#orders) |
| Create users, manage profile/addresses/passwords, multi-profile, impersonation | [Users](references/endpoint-reference.md#users) |
| Manage favorites / wishlists | [Favorites / Wishlists](references/endpoint-reference.md#favorites--wishlists) |
| Read countries, currencies, regions | [Internationalisation](references/endpoint-reference.md#internationalisation) |
| Read loyalty point balance / transactions | [Loyalty Points](references/endpoint-reference.md#loyalty-points) |
| Fetch a form definition and submit it | [Forms](references/endpoint-reference.md#forms) |
| Run a pre-configured backend query (search index / repository) | [Query endpoint](references/endpoint-reference.md#query-endpoint) |
| Health-check the API | [Connectivity check](references/endpoint-reference.md#connectivity-check) |

---

## Headless architecture notes

**Stateless context:** The API has no session. Your frontend owns:
- URL routing (map URL → page ID via `/dwapi/content/pages/url`)
- Cart persistence (store the `secret` in localStorage or a cookie)
- Language/currency selection (pass culture/currency to endpoints or configure via area)
- Authentication state (store and refresh the JWT)

**CORS:** The Dynamicweb backend must be configured to allow your frontend's origin. Confirm CORS headers are set before going to production.

**SSR vs CSR:** For SSR (Next.js, Nuxt, SvelteKit), use `/dwapi/serviceauth/token` with an API key on the server and never expose it to the browser. For CSR, authenticate the user with `/dwapi/users/authenticate` and store the JWT client-side.

**Live schema:** Always fetch `https://<host>/dwapi/api.json` to see the exact request/response shapes for the solution you're working on. The schema includes all custom fields and product/content types configured for that specific solution.
