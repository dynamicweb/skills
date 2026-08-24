# Promotions engines — discounts, vouchers, loyalty, gift cards

Field-validated DW10 discount / voucher / loyalty / gift-card knowledge (validated on 10.28.x):
two coexisting discount engines, the voucher grid's legacy-row projection, v2 condition/reward
payload shapes, voucher code constraints, and the encrypted gift-card code.

## Contents

- [Two discount engines coexist — and the short verb writes the one the admin screen does not read](#two-discount-engines-coexist--and-the-short-verb-writes-the-one-the-admin-screen-does-not-read)
- [A voucher campaign is load-bearing on BOTH engines at once](#a-voucher-campaign-is-load-bearing-on-both-engines-at-once)
- [v2 conditions and rewards — assembly-qualified types, an error that echoes nothing, and required fields at create time](#v2-conditions-and-rewards--assembly-qualified-types-an-error-that-echoes-nothing-and-required-fields-at-create-time)
- [Legacy discount writes — three traps that compound](#legacy-discount-writes--three-traps-that-compound)
- [Vouchers — code constraints, additive generation, insert-only](#vouchers--code-constraints-additive-generation-insert-only)
- [Loyalty rewards — the name is in the translation table, never in the base column](#loyalty-rewards--the-name-is-in-the-translation-table-never-in-the-base-column)
- [Gift cards — codes are encrypted at rest and one bad row 500s the whole family](#gift-cards--codes-are-encrypted-at-rest-and-one-bad-row-500s-the-whole-family)
- [Cross-references](#cross-references)

## Two discount engines coexist — and the short verb writes the one the admin screen does not read

DW 10.28.x carries **two live discount engines**, with singular/plural table names one character apart and a
read query each. The short name `DiscountSave` belongs to the LEGACY engine; the v2 Adjustments engine — the
one the admin Discounts screen renders — has **no short alias on its parent save** and is reachable only
fully-qualified. So four discounts can be created successfully, a legacy read query returns them, and the
admin screen stays empty.

| | Legacy | v2 (Adjustments) |
|---|---|---|
| Tables | `EcomDiscount` (singular) | `EcomDiscounts` + `EcomDiscountCondition` + `EcomDiscountReward` |
| Read query | `DiscountsAll` (`…UI.Queries.Discounts`) | `DiscountAll` (`…UI.Queries.Adjustments`) |
| Parent save | `DiscountSave` — **the short name** | `Dynamicweb.Ecommerce.UI.Commands.Adjustments.DiscountSaveCommand` — **no short alias** |
| Rendered by | the Vouchers grid's projected columns (below) | admin `Dynamicweb.Ecommerce.UI.Screens.Adjustments.DiscountListScreen?Type=DiscountAll` |

- **The namespace in the API catalogue is the tell.** Two queries whose names differ only by a plural are two
  engines, not an alias pair — read the `Dynamicweb.Ecommerce.UI.Queries.<Area>` tag before picking either.
  Every *other* v2 verb does have a short name (`DiscountConditionSave`, `DiscountRewardSave`,
  `DiscountActivate`, `DiscountToggleFinal`), which is what makes the single exception easy to miss.
- **Prove which engine you wrote, don't infer it.** One throwaway row written with the fully-qualified
  Adjustments command took `DiscountAll.totalCount` from 0 to 1 and appeared in `EcomDiscounts`, while
  `EcomDiscount` stayed at its prior row count. That is the assertion to keep: after any discount seeding,
  `DiscountAll` `totalCount` must equal the row count the Discounts screen renders.

This is the general "short command names are not unique" hazard with a second cause — not an add-in shadowing
a platform verb, but two platform engines sharing a name space (see
[dw-data-access](../../dw-data-access/SKILL.md) for the Management API dispatch model).

## A voucher campaign is load-bearing on BOTH engines at once

**The Vouchers grid projects its Discount name / Value / Value type / Date from / Date to columns from the
LEGACY `EcomDiscount` row** attached through `EcomDiscount.DiscountVoucherListId`, and
`DiscountAddToVoucherList` takes an **integer** `DiscountId` — legacy ids only. A correctly configured v2
voucher discount therefore leaves five columns reading *Not Assigned*, and no amount of v2 configuration
fills them.

The working shape is a **pair**:

- the **v2** discount carries the behaviour (conditions + rewards, i.e. what actually pays out), and
- an **inactive legacy** row is attached to the voucher list purely so the grid has metadata to project.
  Measured: the grid projects Value / Type / Dates from an **inactive** attached discount exactly as it does
  from an active one.

**Never leave both active — the reward pays twice.** Assert exactly one of the paired discounts is active,
and that the Vouchers grid renders a discount name and value at all.

## v2 conditions and rewards — assembly-qualified types, an error that echoes nothing, and required fields at create time

Three blockers land on the same call, and each one reads like the previous one failing:

```
ConditionType: "OrderTotalCondition"                                   -> 400  Invalid condition type:
ConditionType: "Dynamicweb.Ecommerce.Orders.Adjustments.Conditions.OrderTotalCondition, Dynamicweb.Ecommerce"
                                                                       -> ok
UserGroupCondition, created empty                                      -> 400  ConditionFields|User Groups: The value is required.
```

- **`ConditionType` / `RewardType` must be the ASSEMBLY-QUALIFIED .NET type name**, and the namespace carries
  an **`Orders`** segment the XML-doc file drops:
  `Dynamicweb.Ecommerce.Orders.Adjustments.Conditions|Rewards.<Type>, Dynamicweb.Ecommerce`. Composing the
  name from the docs alone produces a value that never binds. 14 condition types and 7 reward types exist —
  enumerate them from the assembly rather than guessing.
- **The error echoes an EMPTY type (`Invalid condition type: `) no matter what you send**, so the message
  cannot be used to tell "my value didn't bind" from "my value is wrong". Bisect against a known-good
  fully-qualified name instead of reading the error.
- **Types with required fields cannot be created blind.** `ShopCondition` and `UserGroupCondition` reject an
  empty create, which breaks the save-then-read-defaults-then-save pattern every other type follows. Supply a
  pre-filled `ConditionSettings` `<Parameters>` XML **at create time** to satisfy the validator.
- **Settings can be written two ways and both persist identically**: raw `*Settings` `<Parameters>` XML, or
  read `DiscountConditionById` and mutate `conditionFields.groups[].fields[].value`. The XML is far cheaper —
  one call instead of three.
- **Parameter names are NOT the C# property names.** `ShopCondition` takes `Shop` (not `ShopId`),
  `UserGroupCondition` takes `UserGroups` (not `UserGroupIds`), `VoucherCondition` takes `VoucherList` (not
  `VoucherListId`). Read one existing condition's settings XML before composing a new one.

Verify a seeded discount through `DiscountConditionByDiscountId` / `DiscountRewardByDiscountId` — the parent
save returning `ok` says nothing about whether a condition attached.

## Legacy discount writes — three traps that compound

**1. The model you read can never be posted back.** `DiscountById` returns a populated `Translations` array,
and a non-empty `Translations` array fails deserialization on the way in:

```
500 System.NotSupportedException: Deserialization of types without a parameterless constructor …
    Type Dynamicweb.Ecommerce.Orders.Discounts.DiscountTranslation
```

So the natural read-modify-write round trip is **structurally impossible**. Compose a hand-built model with
`Translations` omitted, and patch translated text separately. Companion shape trap in the same model:
`MaximumLimits` is a `Dictionary<string,double>` — it must be `{}` or omitted, **never `[]`**.

**2. `DiscountSave` is REPLACE, not PATCH — and it detaches the voucher list.** The legacy save starts from a
blank model and applies only the keys posted, so every field you leave out comes back empty. Separately it
**clears `DiscountVoucherListId` even when `VoucherListId` is present in the posted model**, because
`DiscountAddToVoucherList` owns that link exclusively. Two rules follow: always compose the **full** model,
and make `DiscountAddToVoucherList` the **LAST** call in the sequence — any later `DiscountSave` drops the
link again.

**3. Every legacy write re-persists the CACHED translation, reverting SQL renames.** A discount renamed by SQL
reverts on the next unrelated discount operation — `DiscountSave` *and* `DiscountToggleActive` both trigger
it, because the write verbs re-persist the discount translation from an in-process cache that raw SQL never
invalidated. This sharpens the standing API-first / SQL-last rule with a specific ordering: do **all** API
writes first, patch `EcomDiscountTranslation` by SQL **last**, and then never touch a discount write verb
again. **Minting a NEW legacy row sidesteps the cache entirely** — a fresh row has no stale cache entry, so
the grid projection reads correctly first time. Prefer that to renaming a stale one.

## Vouchers — code constraints, additive generation, insert-only

`VoucherRewardSave` has four independent surprises, and three of them are silent:

- **Code validation accepts `[A-Za-z0-9]` only, 16 characters maximum.** Hyphen **and** underscore both fail
  (`"Only numbers and word characters are allowed"`), through the verb and through the admin UI alike — a
  `<PREFIX>-<CAMPAIGN>-<n>` shape is impossible, so design the campaign inside that envelope rather than
  discovering it at seeding time.
- **`Code` and `NumberOfVouchers` are ADDITIVE, not exclusive.** An explicit `Code` with a non-zero
  `NumberOfVouchers` inserts your row **and** that many random 8-hex codes on top. Correct usage for a known
  code is an explicit `Code` with **`NumberOfVouchers = 0`**.
- **The verb is INSERT-ONLY** — re-posting an existing id is rejected as a duplicate, and redemption state
  (`VoucherDateUsed`, `VoucherUsedOrderId`, `VoucherAccessUserId`, `VoucherStatus`) has **no write path at
  all**. Seeding a used/available split is a SQL step by construction.
- **`SentTo` is accepted and never stored** — `EcomVouchers` has no such column.

Voucher **lists** have their own gaps: there is no `VoucherListNew`, `VoucherListById?Id=0` answers **400**
(so the blank model must be composed by hand), and `VoucherListSave` silently drops `DateFrom` / `DateTo` /
`Value` / `ValueType` because those four columns do not exist in `EcomVoucherLists`. Campaign dates and value
live on the attached discount, not on the list.

## Loyalty rewards — the name is in the translation table, never in the base column

**`LoyaltyPointRewardSave` persists the reward name into `EcomLoyaltyRewardTranslation` only —
`EcomLoyaltyReward.LoyaltyRewardName` is left empty on every row it creates.** Measured across a four-reward
seed: all four base-column values empty, all per-language translation rows correct. Anything that reads the
base table rather than the translation table sees unnamed rewards, so **read (and assert) loyalty reward names
from `EcomLoyaltyRewardTranslation`**. The admin grid reads the translation, which is why the defect only
shows up in scripts and exports.

## Gift cards — codes are encrypted at rest and one bad row 500s the whole family

**`EcomGiftCard.GiftCardCode` is stored ENCRYPTED, and a single plaintext row takes out every verb in the
family.** Writing one row with a plaintext code turned `GiftCardsAll` from `200`/0-rows into an HTTP **500**,
and `GiftCardById` and `GiftCardCancel` died with it — `"not a valid Base-64 string"` thrown out of the shared
read path, with no per-row degradation. The whole Gift cards screen goes down for one bad row.

**Never write `EcomGiftCard` rows by raw SQL with a plaintext code.** Use the platform issuance path, or
encrypt through the platform's own `GiftCardService.EncryptCode` (reachable by reflection against the site
assemblies) before the insert. Assert `GiftCardsAll` returns `200` after any gift-card seeding step — that
single check is what separates "no gift cards yet" from "the screen is down".

## Cross-references

- [`order-lifecycle.md`](order-lifecycle.md) — orders, invoices (an invoice is an `EcomOrders` row),
  subscriptions, and the platform-owns-the-id rule that governs every save in this file.
- [dw-data-access](../../dw-data-access/SKILL.md) — the Management API surface, short-name collisions,
  and the read-model-is-not-a-save-model rule the legacy `Translations` trap above is an instance of.
- In-process caches: the legacy discount verbs re-persist from caches that raw SQL never invalidates —
  the general API-writes-first / SQL-last ordering rule in [`order-lifecycle.md`](order-lifecycle.md)
  "A re-saving verb reverts raw-SQL edits" is the governing form.
