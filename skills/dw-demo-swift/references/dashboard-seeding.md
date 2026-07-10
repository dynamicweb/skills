# dashboard-seeding.md

## Contents

- [1. The standing rule — no empty lists on demo day](#1-the-standing-rule--no-empty-lists-on-demo-day)
- [2. When this step runs](#2-when-this-step-runs)
- [3. What the base 2.3.2 dashboard expects](#3-what-the-base-232-dashboard-expects)
- [4. Per-tile seed checklist (buyer)](#4-per-tile-seed-checklist-buyer)
- [5. CSR view seed](#5-csr-view-seed)
- [6. Deterministic recipe preference + idempotency](#6-deterministic-recipe-preference--idempotency)

> The demo-context seeding step that makes the Swift Customer Center land. From base **2.3.2**, the Customer Center **Overview** is a tile dashboard (Orders, Quotes, Carts, Favorites, Addresses, Profile, Returns) instead of a bare order list, and a stock **"My returns"** RMA page ships in the buyer tree. Tiles route to real function pages — but a tile that opens onto an empty list reads as a broken demo. This step seeds every list the buyer (and the CSR) will open. The underlying seeding *mechanics* are foundational; this file is the demo-swift *orchestration* that sequences them and states the coverage bar.
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## 1. The standing rule — no empty lists on demo day

**Every dashboard list a persona can open must show real, demo-relevant rows.** No empty Orders tile, no empty Quotes, no "you have no favorites", no blank Returns. An empty list on the projector reads as a bug even when the wiring is perfect — and the tile dashboard makes each list one click from the landing page, so there is nowhere to hide an unseeded section.

This is the demo-day acceptance bar for the Customer Center. Treat a tile that opens onto an empty list as a build defect, not a cosmetic gap. The rebuild-the-section trap that [customer-center.md](customer-center.md) §1 inoculates against is almost always triggered by exactly this symptom — see [customer-center.md](customer-center.md) §4 for the "looks empty" diagnosis before you seed.

## 2. When this step runs

Run this **after** the demo's products and users exist, never before:

1. The customer-flavoured baseline is deserialized (base 2.3.2 + the demo's catalog/sample layers) — see [deserialize-flow.md](deserialize-flow.md).
2. Products are seeded and the Products index is built (favorites and cart lines reference real product ids).
3. The demo identities exist: at least one **buyer** and one **CSR**, the CSR in a CSR-permission group, with the impersonation grants wired ([customer-center.md](customer-center.md) §3 → [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) "`AccessUserSecondaryRelation`").

Seeding before products/users exist produces orphan rows (favorites pointing at absent products, orders with no customer) and is the usual cause of a list that renders but shows nothing.

## 3. What the base 2.3.2 dashboard expects

The base ships **zero custom code** — the dashboard is stock Swift building blocks, so seeding is pure data:

- **Overview tiles** are `Swift-v2_Feature` (`IconBoxTop`) cards whose buttons deep-link to the stock function pages under `Customer center/Customer center/{My orders, My quotes, My carts, My favorites, My addresses, My profile, My returns}`. The tiles carry no data of their own — each target page runs a stock `eCom_CustomerExperienceCenter*` web-app that reads the signed-in user's rows.
- **My returns** runs the stock `eCom_CustomerExperienceCenterRma` app (templates `eCom/CustomerCenter/RMAList.cshtml` + `RMADetails.cshtml`). A return is raised against a **completed** order, so the Returns list stays empty until at least one completed order exists *and* one RMA request is raised against it.
- Role separation is by **page permission** (CSR subtree gated to the CSR group, buyer subtree to Customers; the NL area inherits via the language-version master link — no per-area permission rows). Seed each persona's rows under the identity that actually owns that subtree.

## 4. Per-tile seed checklist (buyer)

Seed the signed-in buyer so every tile lands. Exact SQL/API mechanics are foundational — this table is the coverage contract and the pointer.

| Tile | Minimum to seed | Key mechanic | Owner |
|---|---|---|---|
| My orders | ≥3 completed orders, **mixed order states** (e.g. New / Processing / Completed via `EcomOrderStates`) | `OrderComplete=1` + `OrderCompletedDate`; `create_orders` seeds `OrderComplete=0` and is otherwise skipped by the list | [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) "Order completion", "Seeding the CSR/account section's demo data" |
| My quotes | ≥1 quote | `OrderIsQuote=1` discriminator (no `OrderComplete` needed) | [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) |
| My carts | ≥1 saved cart with lines | `OrderCart=1` discriminator | [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) |
| My favorites | 1 default list + several products | SQL-only: `EcomCustomerFavoriteLists` (`IsDefault=1`) + `EcomCustomerFavoriteProducts` (NOT-NULL `ProductVariantId`, `Note`); read via `Pageview.User.GetFavoriteLists()` | [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) "Favorites seeded via SQL" |
| My addresses | ≥2 addresses | seed as `UserAddress` rows; mind the profile-address-vs-`UserAddress` checkout gotcha | [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) |
| My profile | complete profile fields | populate name / company / email / phone + the address fields the checkout "Continue" gate reads | [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) |
| My returns | ≥1 RMA request against a completed order | raise a return from a completed order (stock RMA add flow) so `RMAList.cshtml` has a row; depends on the My-orders seed landing first | stock `eCom_CustomerExperienceCenterRma`; base `EcomOrderFlow`/`EcomOrderStates`/`EcomOrderStateRules` supply the return-eligible states |

"Mixed states" matters for the Orders tile specifically — a list where every row says the same status looks synthetic. Spread the seeded orders across the states the base's `EcomOrderStates` ships so the status column tells a story (placed → in progress → shipped/completed).

## 5. CSR view seed

The CSR persona opens `Customer center/CSR/{Accounts, Orders, Carts, Users}` (and, from 2.3.2, a CSR tile dashboard on the CSR landing). Seed so the CSR has something to act on:

- **≥2 customer accounts**, each with **activity** — orders/carts/quotes owned by a buyer the CSR can impersonate (reuse the buyer seed from §4 for account #1; add a second buyer for account #2).
- The **impersonation grants** (`AccessUserSecondaryRelation`) wired both directions, plus the Secondary-user index rebuild + user-cache clear — see [customer-center.md](customer-center.md) §3 and [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) "CSR sales-on-behalf".
- The impersonation entry point is **`CSR/Users/`**, not `CSR/Accounts/` (Accounts is a company directory with no impersonate button) — [customer-center.md](customer-center.md) §2.

Do **not** rebuild the CSR section to force data into it — the empty-section symptom is a seeding gap, never a structural one ([customer-center.md](customer-center.md) §1, §4).

## 6. Deterministic recipe preference + idempotency

- Prefer recipes an agent can run **deterministically** and re-run safely: Management API commands and idempotent SQL (`WHERE NOT EXISTS` / stable seed ids) over UI clicking. Several of these have **no MCP surface** (favorites, `AccessUserSecondaryRelation`, order-state backfills) and are SQL-only — see the owners above.
- Make the seed **idempotent**: key rows on stable ids/order numbers (e.g. `OrderID LIKE 'ORDER%'`) so a second run does not double-seed. The demo is re-provisioned often; a seed that only works on a virgin DB is a liability.
- After seeding orders, **complete them** (`OrderComplete=1` + `OrderCompletedDate`) and, where you raised returns, confirm the RMA row exists — then rebuild the order/products indexes and clear the user cache so the storefront lists and the CSR impersonation views pick the rows up in the same session.
