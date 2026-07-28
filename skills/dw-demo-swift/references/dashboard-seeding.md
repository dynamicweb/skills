# dashboard-seeding.md

## Contents

- [1. The standing rule — no empty lists on demo day](#1-the-standing-rule--no-empty-lists-on-demo-day)
- [2. When this step runs](#2-when-this-step-runs)
- [3. What the base 2.3.2 dashboard expects](#3-what-the-base-232-dashboard-expects)
- [4. Per-tile seed checklist (buyer)](#4-per-tile-seed-checklist-buyer)
- [5. CSR view seed](#5-csr-view-seed)
- [6. Email-marketing stats seed — the backend Marketing dashboards](#6-email-marketing-stats-seed--the-backend-marketing-dashboards)
- [7. Email flow bootstrap — folders and the fully-prefixed schema](#7-email-flow-bootstrap--folders-and-the-fully-prefixed-schema)
- [8. Keeping seeded dates current — the demo clock](#8-keeping-seeded-dates-current--the-demo-clock)
- [9. Deterministic recipe preference + idempotency](#9-deterministic-recipe-preference--idempotency)

> The demo-context seeding step that makes the Swift Customer Center land. From base **2.3.2**, the Customer Center **Overview** is a tile dashboard (Orders, Quotes, Carts, Favorites, Addresses, Profile, Returns) instead of a bare order list, and a stock **"My returns"** RMA page ships in the buyer tree. Tiles route to real function pages — but a tile that opens onto an empty list reads as a broken demo. This step seeds every list the buyer (and the CSR) will open. The underlying seeding *mechanics* are foundational; this file is the demo-swift *orchestration* that sequences them and states the coverage bar.
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## 1. The standing rule — no empty lists on demo day

**Every dashboard list a persona can open must show real, demo-relevant rows.** No empty Orders tile, no empty Quotes, no "you have no favorites", no blank Returns. An empty list on the projector reads as a bug even when the wiring is perfect — and the tile dashboard makes each list one click from the landing page, so there is nowhere to hide an unseeded section.

The same bar applies to the **backend** dashboards a marketer persona opens — an email campaign with no send/click history, or a flow folder that renders "No results found", is the same defect one screen further back (§6, §7).

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

## 6. Email-marketing stats seed — the backend Marketing dashboards

A campaign email that shows 0 sent / 0 clicked reads exactly like an unfinished build. The stats grids are fed by the send engine and the tracking pixel, and **no MCP or Admin API surface creates send history** — this is a fixture backfill into telemetry tables, not a content edit. Keep it strictly inside the statistics/tracking tables; the emails, flows and pages themselves stay on the API surfaces ([sql-direct-seeding.md](sql-direct-seeding.md)).

**The join keys the grids actually use** (each one was a dead end until proven):

- `RecipientStatisticsByEmail?EmailId=<n>` resolves its recipients through **`EmailMarketingEmail.EmailOriginalMessageId` = `EmailRecipient.RecipientMessageId`** — *not* `EmailMessageId`. Setting `EmailMessageId` and inserting `EmailRecipient` rows returns 0 rows forever; setting `EmailOriginalMessageId` makes the same grid return the recipients **live, without a recycle**.
- Per-recipient **`clicked`** is a COUNT over `OMCLinkClick` joined to `OMCLink` where `OMCLink.LinkReferenceKey = CAST(<MessageId> AS varchar)` **and** `OMCLinkClick.LinkClickClickerKey = CAST(<RecipientId> AS varchar)`. Both halves must match — either key alone yields 0. `LinkClicksByEmail` (per-link performance) reads the same pair, so one correct click row feeds both grids.
- **`opened` is pixel-only.** The per-recipient `opened` column and the `EmailById` opened/clicked aggregates are materialized by the live open-tracking pixel handler / statistics job and are **not reproducible from raw SQL** — proven negative across every `OMCLink` link type and 12 `EmailAction` ActionTypes. Do not burn a build cycle on it: script the demo around sends, bounces, clicks and link performance, or generate real opens by loading the tracking pixel.

**Per campaign email, seed in this order:**

1. One `EmailMessage` row for the email.
2. Set that message id on `EmailMarketingEmail.EmailOriginalMessageId`.
3. One `EmailRecipient` row per send, `RecipientMessageId` = that message id — this is the *sent* count.
4. Bounces: a non-empty `RecipientErrorMessage` on the recipient rows you want to show as failed.
5. Clicks + link performance: `OMCLink` rows for the tracked links (`LinkReferenceKey` = the message id as varchar) plus `OMCLinkClick` rows (`LinkClickClickerKey` = the recipient id as varchar).

Verify by calling `RecipientStatisticsByEmail?EmailId=<n>` and `LinkClicksByEmail` for each seeded email and checking the numbers match the seed — a green insert proves nothing, the grid query is the test.

## 7. Email flow bootstrap — folders and the fully-prefixed schema

Two failure modes that both present as "the flow isn't there":

- **`EmailMarketingFlow` columns are fully table-prefixed.** The real schema is `EmailMarketingFlowId`, `EmailMarketingFlowFolderId`, `EmailMarketingFlowName`, `EmailMarketingFlowRecipientsIds`, … — there are no bare `FolderId` / `Name` / `RecipientsIds` columns. Bare-name SQL is a compile error, and the `RunSql` add-in surfaces it as a **contentless Exception** with no message to diagnose from. Dump `sys.columns` for `OBJECT_ID('EmailMarketingFlow')` before writing anything, and never trust an abbreviated column list in a hand-written schema note.
- **A flow must carry its folder id or the folder node renders empty.** `FlowListScreen` queries `FlowsByFolderId?FolderId=<n>`, so a flow left at folder `0` (top level) shows "No results found" under the folder you created for it — even though the flow exists, is active, and has steps and recipients. Create the `FlowFolder` row **first**, then set `EmailMarketingFlowFolderId` to that folder's id on the flow.

Validate after a recycle: `FlowsByFolderId?FolderId=<folder>` returns `totalCount >= 1` and the admin flow list for that folder shows the row.

## 8. Keeping seeded dates current — the demo clock

Every seeded dashboard decays. Orders, carts, email send/click history and campaign windows all carry absolute dates, so a demo that is a few weeks old shows stale orders and expired campaigns — the §1 bar fails again without anyone touching the build.

The mechanic that fixes it is an **anchor table + a whole-day uniform shift**:

- A one-row `_demoClock(Id, AnchoredTo)` table records the date the fixtures were authored for.
- A recurring task shifts every operational date column by `DATEDIFF(day, AnchoredTo, <today>)`, then re-anchors. A reference build shifted **142 date columns across 49 tables** (order headers/lines, the email statistics, send-log and click tables, campaign windows).
- **Whole-day, uniform** is the whole trick: shifting every column by the same integer number of days preserves intra-day ordering and every relative gap, so order → ship → click sequences stay coherent. It is idempotent and catch-up safe (a `+1` then `-1` test nets zero), and it runs unattended after idle days.
- **Exclude config and logging tables** from the shift — only operational/fixture dates move. Audit and scheduled-task logs must keep their real timestamps or the task's own history becomes unreadable.
- **Discover the date columns from `sys.columns` at build time; never hardcode the list.** Every commerce feature spells its timestamps differently — one pass hardcoded 18 column names and **12 of them were wrong**. Discovery is also what keeps the shifter correct across a platform upgrade.

### Two silent failure modes when a SECOND shifter is added

Both of these produce a task that reports **Success** while doing nothing, and neither raises an error:

- **A second date-shifting task must own its OWN anchor row.** The existing freshener computes its delta from the anchor row and then **re-anchors that row to today**. A second task reading the same row at a later slot therefore sees `delta = 0` and shifts nothing, forever. Give each shifter its own anchor row (`Id=2`, …) and have it re-anchor **only** its own.
- **A manual run right after install proves nothing.** A new task creates its anchor row on first execution, so the delta is legitimately `0` on that pass — "the task ran" is not evidence that "the task shifts". **Make the standard proof a rewind-and-run, never a bare run:** rewind that task's anchor by one day, run it, and assert at least one known timestamp advanced by exactly one day while the *other* task's anchor is untouched. Confirm end-to-end from the rendered screen (the same list captured a demo-day apart must show every date moved by one day), not only from the task's `lastRunState`.

### Per-column guards: some date columns are state markers

**Auto-discovering date columns is right for demo data, but any column that a cancel / void / close operation overloads as a state marker needs its own guard** — a blanket `DATEADD` marches the cancelled thing back to life.

The known instance: **`GiftCardCancel` writes no reversing transaction and sets no status flag — it cancels by rewriting `GiftCardExpiryDate` to now and keeping the balance.** On a cancelled card that column is a *cancellation timestamp*, not an expiry, so the same column means two different things depending on state. A nightly shift over it hands a demo viewer a live balance that is meant to be void.

The guard is to shift only rows that are still in the future:

```sql
UPDATE [EcomGiftCard]
   SET [GiftCardExpiryDate] = DATEADD(day, @d, [GiftCardExpiryDate])
 WHERE [GiftCardExpiryDate] IS NOT NULL
   AND [GiftCardExpiryDate] > GETDATE();
```

Measured across a rewind-and-run cycle: the live cards moved +1 day while the cancelled one stayed frozen and still read `active=False` through the gift-card list query. **Assert it** — a cancelled gift card still reads inactive after the nightly refresher runs. Gift-card storage semantics (encrypted codes, one bad row 500ing the whole family) are owned by [`../../dw-demo-base/references/foundational/promotions-engines.md`](../../dw-demo-base/references/foundational/promotions-engines.md).

Verify by reading order dates back through the delivery API after idle days and confirming the marketing dashboards read as current, and that the recurring task reports Success with `nextRun` advancing. Task creation semantics (`Begin` re-anchoring, the toggling `TaskToggleActive`, `TaskSave` with `Id=0` creating a new task every call) are owned by [sql-direct-seeding.md](sql-direct-seeding.md) "Scheduled-task creation semantics".

## 9. Deterministic recipe preference + idempotency

- Prefer recipes an agent can run **deterministically** and re-run safely: Management API commands and idempotent SQL (`WHERE NOT EXISTS` / stable seed ids) over UI clicking. Several of these have **no MCP surface** (favorites, `AccessUserSecondaryRelation`, order-state backfills) and are SQL-only — see the owners above.
- Make the seed **idempotent**: key rows on stable ids/order numbers (e.g. `OrderID LIKE 'ORDER%'`) so a second run does not double-seed. The demo is re-provisioned often; a seed that only works on a virgin DB is a liability. For the email stats seed (§6) key on the message id — one `EmailMessage` per campaign email — so a re-run replaces its recipient/click rows instead of doubling the counts.
- After seeding orders, **complete them** (`OrderComplete=1` + `OrderCompletedDate`) and, where you raised returns, confirm the RMA row exists — then rebuild the order/products indexes and clear the user cache so the storefront lists and the CSR impersonation views pick the rows up in the same session.
