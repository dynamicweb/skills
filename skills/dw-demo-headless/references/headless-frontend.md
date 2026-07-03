# headless-frontend.md

## Contents

- [1. What the storefront is](#1-what-the-storefront-is)
- [2. Provider-module architecture (the data-layer swap)](#2-provider-module-architecture-the-data-layer-swap)
- [3. Environment-variable wiring](#3-environment-variable-wiring)
- [4. Self-signed-TLS dev bypass](#4-self-signed-tls-dev-bypass)
- [5. Build-time RSC fetch caveat](#5-build-time-rsc-fetch-caveat)
- [6. Slug conventions](#6-slug-conventions)
- [7. `@vercel/*` couplings on self-host](#7-vercel-couplings-on-self-host)
- [8. Run / verify](#8-run--verify)

> Work with the Next.js storefront that fronts a headless DW10 demo. The storefront is a **separate
> app** built from the `vercel/commerce` starter (Next.js App Router) — your team's headless
> storefront repo (vercel/commerce-based), which builds and runs anywhere Node runs (`pnpm dev`,
> `next build && next start`, or a container). **No Vercel account is required** to build, run, or
> validate it; "Vercel" is one hosting option, not a dependency.
>
> **Use AFTER** the backend is verified per [`headless-backend.md`](headless-backend.md) — the
> storefront is only as good as the `/dwapi` surface behind it.

## 1. What the storefront is

`vercel/commerce` is a production Next.js storefront (PLP, PDP, cart, checkout, search, menus) whose
entire UI consumes a small set of **normalized domain types** (`Product`, `Collection`, `Cart`,
`Menu`, `Page`) produced by a single **data-layer module**. The starter ships that module for
Shopify (`lib/shopify/`). A DW headless demo **replaces the data module, keeps every UI component**.
That is the whole architecture: the React layer never learns it is talking to Dynamicweb.

## 2. Provider-module architecture (the data-layer swap)

The starter has no formal plugin SDK. Its "provider contract" is a single folder exporting async
functions that return the normalized types:

```
getProduct, getProducts, getCollection, getCollectionProducts,
getCart, createCart, addToCart, updateCart, removeFromCart,
getMenu, getPage, getPages, …
```

Every UI component consumes only the normalized types from `lib/*/types`. So "conform to the
provider contract" means: **replace `lib/shopify/` with a `lib/dynamicweb/` module implementing the
same function surface**, calling the Delivery API over REST/JSON and **reshaping** DW view-models
into the unchanged domain types. Do not rewrite the domain layer or the components.

Structure of the DW module:

- `lib/dynamicweb/index.ts` — the ~15 exported provider functions.
- `lib/dynamicweb/types.ts` — reshapers: DW view-model → normalized `Product`/`Collection`/`Cart`/
  `Menu`/`Page`.
- `lib/dynamicweb/dwapi.ts` — a thin fetch client (base URL, locale/shop query params, the dev TLS
  bypass of §4, JWT handling for user-scoped calls).

**Mapping (DW source → normalized type), abbreviated:**

| Normalized type | DW source | Key field mapping |
|---|---|---|
| `Product` | `GET /ecommerce/products/{id}`, `products[]` of the search result | `handle ← number`; `title ← name`; `descriptionHtml ← longDescription`; `priceRange ← price`/`prices[]`; `variants ← variantInfo` + `/variants/{id}`; `images ← imagePatternImages`; `availableForSale ← active && (neverOutOfstock || stockLevel>0)` |
| `Collection` | `GET /ecommerce/groups`, `/groups/{groupId}` | `handle ← id` (e.g. `GROUP1`); `title ← name`; `path ← '/search/'+id`; `products ← search?GroupId=id` |
| `Cart` | `carts/create`, `/carts/{secret}`, `/{secret}/items`, `/{secret}/checkout` | `id ← secret`; `checkoutUrl ← /carts/{secret}/checkout`; `lines ← cart lines`; `cost.* ← cart price fields` |
| `Menu` | `GET /frontend/navigations/{areaId}` | `Menu[] ← nodes[]` recursively → `{ title ← node.title, path ← node.link }` |
| `Page` | `GET /content/pages/{id}`, `/pages/url`; body via `/content/rows/{pageId}/{device}` | `handle ← path`; `title ← title`; `body ← rows/paragraphs`; `seo ← {title,description}` |

All DW coupling (endpoints, view-model quirks, price/VAT handling, the search-query dependency)
lives in this one folder — easy to gate, mock, and evolve as the headless baseline matures.

## 3. Environment-variable wiring

`DYNAMICWEB_*` / `DW_*` env vars replace the starter's `SHOPIFY_*`. The provider reads them; nothing
is hardcoded:

| Var | Purpose |
|---|---|
| `DW_API_BASE` | Delivery API base, e.g. `https://<host>/dwapi` |
| `DW_SHOP_ID` | shop context — `SHOP1` (see the locale gotcha, [`headless-backend.md`](headless-backend.md) §4) |
| `DW_LANGUAGE_ID` | language context — `ENU` (**not** `LANG1`) |
| `DW_CURRENCY_CODE` | currency for price display |
| `DW_AREA_ID` | area id for `GET /frontend/navigations/{areaId}` (menu) |

Seed the shop/language/currency/area defaults from `GET /dwapi/content/areas` — the area carries the
`ecomShopId` / `ecomLanguageId` / `ecomCurrencyCode` bindings the provider should default to. Remove
the `SHOPIFY_*` vars and the Shopify webhook revalidation route (`app/api/revalidate` keyed on
Shopify topics) when you delete `lib/shopify/`.

## 4. Self-signed-TLS dev bypass

The demo host serves HTTPS with a self-signed certificate, so the provider's server-side `fetch`
rejects it by default. For **local development only**, set on the Node process running the storefront:

```
NODE_TLS_REJECT_UNAUTHORIZED=0
```

This is the same class of bypass `dynamicweb-demo-base` wires for the MCP/browser layer, and it is
**dev-only**. Never set it on a hosted/production storefront — it disables all TLS verification for
the process. For a hosted demo, terminate TLS with a real certificate and drop this var. Confine it
to the storefront's local `.env`/shell; do not commit it into any deploy config.

## 5. Build-time RSC fetch caveat

The starter's pages are React Server Components that fetch during rendering — and the App Router
executes those fetches **at build time** for static generation. Consequence: **`next build` cannot
complete without a reachable provider.** If the DW backend is down (or `DW_API_BASE` is wrong) when
you build, the build fails on the data fetch, not at runtime.

Handling:

- For a gate/CI build, ensure the backend is up and reachable first (the backend verification gate in
  [`headless-backend.md`](headless-backend.md) §7 is the precondition).
- Or force affected routes to dynamic rendering (`export const dynamic = 'force-dynamic'`) / set
  `revalidate` so they are not statically pre-rendered at build.
- `pnpm dev` does not hit this — it fetches per request — so develop against `dev`, and treat a clean
  `next build` as a separate gate that needs the live backend.

## 6. Slug conventions

`vercel/commerce` routes on `handle` slugs; DW keys numeric/string ids. Use **business-stable**
sources so URLs survive baseline rebuilds:

| Domain type | `handle` source | Provider reverse-resolution |
|---|---|---|
| Product | **product `number`** (`EcomProducts.ProductNumber`) | search `sku` param, or a product-number filter |
| Collection | **group id** (`EcomGroups.GroupId`, e.g. `GROUP1`) | search `GroupID` param (match on `ParentGroupIDs`) |

Product numbers and group ids are business-stable — they survive re-serialization and rebuilds.
Database-assigned auto ids and display names (rename-fragile) are **not** slug sources. The baseline's
menu items follow the same rule: a menu item carries a group id for a product-group link and a product
number for a product link. Page-ref resolution (a menu item pointing at a content page) resolves the
page path — confirm it end-to-end in the provider.

## 7. `@vercel/*` couplings on self-host

The dominant coupling in the starter is **Shopify**, not `@vercel/*` — swapping the provider removes
most of it. For the rest:

- **Removed with `lib/shopify/`:** the GraphQL client/queries/mutations, all `SHOPIFY_*` env, the
  Shopify-topic webhook revalidation route, Shopify GraphQL types.
- **Kept (Next-native, no account needed):** on-demand ISR via `revalidateTag`/`revalidatePath` —
  these are `next/cache`, not `@vercel/*`, and work under `next start` on any Node host. Re-point
  revalidation from Shopify webhooks to a DW-driven trigger, or fall back to time-based `revalidate`.
- **Dropped / opt-in for self-host:** `@vercel/analytics`, `@vercel/speed-insights`, and the Vercel
  Toolbar are optional telemetry — remove them or leave them inert. None are required to build or to
  pass the demo gate.

Reconcile the exact `@vercel/*` list against the actually-scaffolded starter `package.json` — the
starter evolves, so treat the list above as the shape, not a pinned inventory.

## 8. Run / verify

- `pnpm install` then `pnpm dev` — the storefront comes up on its own port (default `3000`),
  fetching live from `DW_API_BASE`.
- Confirm the parity surfaces render **against the backend**, not just that the app compiles: PLP
  lists products, PDP renders a product by its number-slug, a collection page filters by group,
  add-to-cart returns a cart secret, and the menu renders from the navigations endpoint.
- Treat `next build` as a separate gate (needs the live backend per §5).

> **Gate scope note.** The clean-room harness does not provision the server-side product-render index
> the Swift Razor storefront uses, so **storefront HTML render is not provable in the harness gate**.
> Assert catalog/PLP/PDP at the SQL / Delivery-API level (the backend gate) and treat rendered
> storefront output as a real-host UAT item — the same "verify behavior on a real host" posture the
> feature-pack render-proof deferral uses.
