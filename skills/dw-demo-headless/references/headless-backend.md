# headless-backend.md

## Contents

- [1. What "configure the backend for headless" means](#1-what-configure-the-backend-for-headless-means)
- [2. Delivery API surface map](#2-delivery-api-surface-map)
- [3. The two-token trap (admin token vs frontend JWT)](#3-the-two-token-trap-admin-token-vs-frontend-jwt)
- [4. The locale gotcha (ENU, not LANG1)](#4-the-locale-gotcha-enu-not-lang1)
- [5. Product search needs a repository + named query](#5-product-search-needs-a-repository--named-query)
- [6. Item types materialize from XML at host startup](#6-item-types-materialize-from-xml-at-host-startup)
- [7. Verification gate](#7-verification-gate)

> Configure and verify a Dynamicweb 10 host so a headless storefront can read it. DW10 ships a
> single first-class headless surface — the **Delivery API** (`/dwapi/**`), a REST/JSON API. There
> is **no GraphQL and no OData** (`/graphql`, `/odata`, `/api`, bare `/dwapi/content` all 404); the
> Delivery API is the only contract. A live OpenAPI 3.0 document sits at `https://<host>/dwapi/api.json`
> (Swagger UI at `/dwapi/docs/`). This reference is demo-facing backend config; for the full raw
> endpoint catalog and response shapes see [`../../dw-headless-delivery/SKILL.md`](../../dw-headless-delivery/SKILL.md).
>
> **Use AFTER `dynamicweb-demo-base`.** Assumes a running host and the localhost TLS bypass wired.

## 1. What "configure the backend for headless" means

For a headless demo the DW host is a pure JSON backend — there is no server-side storefront to
theme. "Configuring it" is three things, each verified before the frontend is wired:

1. The Delivery API is reachable and you know its **auth model** (§2–§3).
2. The **locale/shop context** the storefront will pass is the one the catalog data actually lives
   under (§4).
3. A **product-search surface** (repository + named query) exists so the PLP/faceted-navigation
   path resolves (§5).

Everything the storefront reads flows through `/dwapi/**`; nothing requires custom C# on the host.

## 2. Delivery API surface map

The endpoints a storefront consumes, and whether each needs a token. **Catalog, groups,
navigation, content, areas, and cart are anonymous** — the storefront reads the full catalog with
no credential. Only user-scoped endpoints (orders, profile, favorites, loyalty, impersonation)
require a Bearer JWT.

| Concern | Method + path | Auth |
|---|---|---|
| Product detail | `GET /dwapi/ecommerce/products/{id}` (+ `/{id}/{variantId}`) | anonymous |
| Product list / facets | `GET /dwapi/ecommerce/products/search` (see §5) | anonymous |
| Product list (index-free) | `GET /dwapi/ecommerce/products/search?ProductIds=…` | anonymous |
| Variants | `GET /dwapi/ecommerce/variants/{productId}` | anonymous |
| Related / BOM | `GET /dwapi/ecommerce/products/{id}/related` · `/{id}/bom` | anonymous |
| Groups (collections) | `GET /dwapi/ecommerce/groups` · `/groups/{groupId}` | anonymous |
| Navigation / menu | `GET /dwapi/frontend/navigations/{areaId}` | anonymous |
| Content pages | `GET /dwapi/content/pages/{id}` · `/pages/url` | anonymous |
| Page rows / paragraphs | `GET /dwapi/content/rows/{pageId}/{device}` · `/content/paragraphs` | anonymous |
| Areas (site/domain map) | `GET /dwapi/content/areas` · `/areas/{id}` · `/areas/domain/{domain}` | anonymous |
| Cart | `POST /dwapi/ecommerce/carts/create` · `GET/PATCH/DELETE /carts/{secret}` · `/{secret}/items` · `/{secret}/createOrder` · `/{secret}/checkout` | cart secret (anon ok) |
| Countries / currencies | `GET /dwapi/ecommerce/International/countries` · `/currencies` | anonymous |
| Orders | `GET /dwapi/ecommerce/orders` · `/orders/{secret}` · `/orders/search` | **Bearer JWT** |
| Addresses / profile | `GET/PATCH /dwapi/users/addresses…` · `/users/info…` | **Bearer JWT** |
| Favorites (wishlist) | `GET/POST /dwapi/ecommerce/favorites/lists…` | Bearer JWT |
| Loyalty points | `GET /dwapi/ecommerce/loyaltyPoints/balance` · `/transactions` | Bearer JWT |
| CSR impersonation (B2B) | `GET /dwapi/users/impersonatees` · `/users/impersonate` | Bearer JWT |
| User auth | `POST /dwapi/users/token` · `POST/GET /dwapi/users/authenticate` · `/authenticate/refresh` | credentials → JWT |
| Password flows | `POST /dwapi/users/password/{change,reset,recover…}` | mixed |

**Cart** uses an opaque per-cart `secret` returned by `carts/create`; a cart can start anonymous
and later bind to the authenticated user. **B2B price/permission gating is server-side** — a
user-scoped price/permission is applied when the JWT (or `PriceSettings.UserId`) is supplied.

> Two content-list routes are **not** routes on this platform version: `GET /dwapi/content/pages`
> (no id) returns 404 — read a page by id (`/pages/{id}` or `/pages?pageId={id}`) or by URL
> (`/pages/url`). Do not build the provider around a bare page-list call.

## 3. The two-token trap (admin token vs frontend JWT)

The single most common wiring failure. **There are two different tokens and they are not
interchangeable:**

- The **admin / Management-API token** (minted at `/Admin/TokenAuthentication/authenticate`,
  format `CLAUDE.<hex>` when captured for MCP/Serializer work) authenticates the admin/index/
  Serializer APIs (`/admin/api/**`). **It 401s on `/dwapi/**`.** Passing the admin bearer to
  `GET /dwapi/ecommerce/products` returns `401`, while anonymous returns `200`. Confirmed live.
- The **frontend JWT** authenticates the `/dwapi` user scope. Mint it from **frontend user
  credentials**:

```http
POST /dwapi/users/authenticate
Content-Type: application/json

{ "UserName": "<frontend-user>", "Password": "<password>" }
```

Response: `{ "token": "<jwt>" }`. Send it as `Authorization: Bearer <jwt>`. (`POST /dwapi/users/token`
is the equivalent path; it also exchanges an existing `Dynamicweb.Extranet` cookie for a JWT.)

**Symptom → cause:** anonymous catalog reads work but every user-scoped call fails → you are sending
the admin token (or no token) instead of a frontend JWT. Mint the JWT via `/dwapi/users/authenticate`
first. Never write either token to disk; keep it in conversation/session state only.

> **Don't pin the failure to a code — it is version-dependent.** The exact non-success status a
> wrong/absent token (or an unsupported request shape) returns on `/dwapi` **moves across DW
> versions** — the same trap was observed as **404 on 10.26.x** and **400 on 10.27.x**, not a stable
> 401. Detect the trap by "**a non-401 error**" (equivalently: anything but the anonymous `200`), and
> assert the *shape* — auth works vs it doesn't — rather than matching a fixed HTTP code that a minor
> platform bump will change out from under the check.

For SSR/build-time server fetches where no user is involved, `POST /dwapi/serviceauth/token`
`{ "apiKey": "…" }` issues a short-lived service JWT — keep the API key server-side, never expose it
to the browser.

## 4. The locale gotcha (ENU, not LANG1)

Product data does **not** live under the language you may expect. On the reference host the catalog
sits under language **`ENU`** and shop **`SHOP1`** — passing `LANG1` returns an empty/short product
set even though the products exist.

**Rule: the storefront must establish an explicit locale + shop context on every Delivery API
call** — pass `LanguageId=ENU` and `ShopId=SHOP1` (the canonical storefront defaults) rather than
relying on a host default. The product-search query scopes by the runtime
`Dynamicweb.Ecommerce.Context:LanguageID` / `:ShopID`, so an unset context yields the wrong (or no)
data.

Areas carry the shop/language/currency bindings (`AreaEcomShopId` / `AreaEcomLanguageId` /
`AreaEcomCurrencyId`). Those binding columns are **per-environment** and are excluded from
serialization — set them at provisioning, do not expect them to arrive in a baseline. An EN area and
its NL sibling each bind to the same shop and their own language.

**An area can ship with the ecom bindings empty** (`ecomShopId=""`, and likewise language/currency) —
provisioning simply never set them, and nothing forces them non-empty. So the provider **must pass
`LanguageId` and `ShopId` explicitly on every Delivery API call** and must **never** fall back to "the
area's default context", because that default may be blank. Treat the storefront's configured
`ShopId`/`LanguageId` (the `DW_SHOP_ID` / `DW_LANGUAGE_ID` env of
[`headless-frontend.md`](headless-frontend.md) §3) as authoritative and send them on each request; read
the area bindings only as a *seed* for those env values, not as a runtime source of truth.

## 5. Product search needs a repository + named query

The PLP, faceted navigation, and text search all go through the search endpoint, which requires a
**`RepositoryName` + `QueryName`** pair pointing at a provisioned repository index + named query:

```
GET /dwapi/ecommerce/products/search?RepositoryName=<repo>&QueryName=<query>&LanguageId=ENU&ShopId=SHOP1&PageSize=N
```

Returns `200` with:
`{ "products":[…], "pageSize", "pageCount", "currentPage", "totalProductsCount", "sortOrder", "facetGroups" }`.

- **Product count JSON path: `totalProductsCount`** (not `products.length`, which is one page).
- **Facets JSON path: `facetGroups[i].facets[j]`.** Each facet carries
  `{ name, queryParameter, facetField, facetType, facetValue, options, optionCount, … }`. A facet
  group with `optionCount=0` is defined but unpopulated (e.g. a Manufacturer facet when the data set
  has no manufacturer rows) — present, but nothing to click.
- **Use GET, not POST.** The sibling `POST /dwapi/ecommerce/products` returns **400 for every probed
  body shape** on this platform version — its request model is unresolved. The `GET
  /products/search` endpoint is the query-resolution proof; build the provider on it.
- A stock/harness `Products` repository typically ships an index with **no resolvable query** (probes
  → 400/404). A headless demo ships its **own** complete search surface (index + query + facets) —
  see [`headless-baseline.md`](headless-baseline.md) §"Product search surface".
- **`RepositoryName` and `QueryName` are per-environment — the storefront must read them from env, not
  hardcode them.** Pass the `QueryName` **without** the `.query` file extension (the endpoint wants the
  bare query name). Wiring them as env (`DW_REPOSITORY_NAME` / `DW_QUERY_NAME`, see
  [`headless-frontend.md`](headless-frontend.md) §3) is what makes a swap to a second backend a
  pure-env change with no code edit.

**Index-free fallback:** `GET /dwapi/ecommerce/products/search?ProductIds=…` (and `GroupId=…`)
returns products without any repository query — use it for PDP-by-id and simple collection lists
before the faceted query is provisioned, behind the same provider function so no component changes
when the query lands.

## 6. Item types materialize from XML at host startup

A durable platform fact that shapes how a headless baseline is staged: **DW10 materializes item
types from `wwwroot\Files\System\Items\ItemType_<systemName>.xml` at host startup** — the
ItemManager creates/updates the backing `ItemType_<systemName>` SQL table from that XML. **DW10 does
not consume standalone item-type JSON files.** If a baseline ships item-type definitions as JSON,
they must be rendered to the DW item XML shape and staged into `Files/System/Items` **before the host
starts** (a disk-overlay step, zero custom code). Content that references an item type whose XML is
not on disk fails to deserialize. See [`headless-baseline.md`](headless-baseline.md) §"Item-type
staging".

## 7. Verification gate

Before wiring the frontend, confirm all of these against the running host (anonymous unless noted):

- `GET https://<host>/dwapi/api.json` → 200 (Delivery API is up; note the operation count).
- `GET /dwapi/ecommerce/products/{knownId}` → 200 with a full product model.
- `GET /dwapi/ecommerce/groups` → 200 with the collection list.
- `GET /dwapi/content/areas` → 200; confirm the storefront's area and its shop/language binding.
- Admin token on `/dwapi/ecommerce/products` → **401** (proves the two-token trap is understood),
  anonymous on the same → **200**.
- `POST /dwapi/users/authenticate` with a frontend user → `{ "token": … }`; that JWT on a user-scoped
  endpoint (e.g. `/dwapi/ecommerce/orders`) → 200.
- `GET /dwapi/ecommerce/products/search?RepositoryName=…&QueryName=…&LanguageId=ENU&ShopId=SHOP1` →
  200 with non-zero `totalProductsCount`.

If any fails, resolve it here before touching the storefront — a provider wired against an unverified
backend fails in ways that look like frontend bugs.
