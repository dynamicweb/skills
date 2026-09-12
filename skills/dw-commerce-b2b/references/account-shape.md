# The customer number is the account key — and what a per-contact suffix costs

Field-validated DW10 B2B account modelling: the platform features that resolve "the same customer"
by comparing `AccessUser.AccessUserCustomerNumber` as an exact string, what a per-contact suffix
silently disables, the measured recipe for normalising one away, and the account-wide favourites
pattern that rides the same key.

## Contents

- [What keys on the customer number](#what-keys-on-the-customer-number)
- [A per-contact suffix makes account-wide delivery addresses a silent no-op](#a-per-contact-suffix-makes-account-wide-delivery-addresses-a-silent-no-op)
- [Normalising a per-contact suffix away](#normalising-a-per-contact-suffix-away)
- [Account-wide favourites lists — impersonation plus one retrieval mode](#account-wide-favourites-lists--impersonation-plus-one-retrieval-mode)
- [Cross-references](#cross-references)

## What keys on the customer number

Several stock features answer "is this the same customer?" with an **exact string comparison** of
`AccessUserCustomerNumber`, with no normalisation and no prefix matching:

| Feature | Surface | Effect |
|---|---|---|
| Account-wide order visibility | Customer Experience Center, `RetrieveListBasedOn = UseCustomerNumber` | Every contact on the account sees the account's orders |
| Account-wide delivery addresses | Checkout app setting `IncludeDeliveryAddressesFromUsersWithSameCustomerNumber` | A buyer with no addresses of their own is offered the account's ship-tos |
| The address book | `UserAddresses` app source `OwnAddressesAndAddressesOfUsersWithSameCustomerNumber` | Same rule, on the address-book page |
| Account directory scoping | `UserGroups` app `AccountListScope` | Builds a customer-number set from the acting user's profiles and keeps the groups reachable through `GetGroupsByCustomerNumber` |

So **the customer number identifies the ACCOUNT, not the contact.** Anything that qualifies it per
contact — a role suffix (`…-ADMIN` / `-BUYER` / `-BROWSE`), a site suffix, an appended contact id —
makes two contacts of one account unequal and turns every feature in that table off, with the
setting still reading back as enabled.

## A per-contact suffix makes account-wide delivery addresses a silent no-op

Symptom: the checkout setting is on, the buyers still see only "Same as the billing address", the
address book renders zero cards, and there is no error, warning or log entry anywhere. Measured
both ways on one install in one session: a buyer whose number carried a role suffix was offered one
delivery row, while a buyer on another account sharing the account's unsuffixed number was offered
all of the other contact's ship-tos — with zero `AccessUserAddress` rows of his own. Same setting,
same code path, same release; the only difference is whether the two strings are equal.

**The diagnostic is one read, before anyone spends an afternoon on the setting:** list the account's
contacts with `get_users_by_group_id` (or `get_users_by_customer_numbers` on the account's own
number) and compare the `customerNumber` values that come back. If every contact has its own value,
the feature cannot work and no setting will fix it. The whole-install census is a read-only query —
outside the product: see [dw-data-access](../../dw-data-access/SKILL.md)
`references/recipes-commerce.md` §"Census the customer numbers of one account's contacts".

**Where the numbers cannot be normalised** — they are ERP-owned, or a template keys off the suffix
— scope by the customer GROUP instead: every contact belongs to exactly one group whose customer
number identifies the account, so Razor can enumerate
`UserManagementServices.Users.GetUsersByGroupId(group.ID)` and then
`UserManagementServices.UserAddresses.GetAddressesByUserId(u.ID)`. Those rows **cannot** be posted
back as `UserManagementUserSelectedAddress` — Dynamicweb resolves that id against the signed-in
user — so the form must post the literal `EcomOrderDelivery*` fields, exactly as the shipped "same
as the billing address" row already does.

## Normalising a per-contact suffix away

The cleaner data model, and repeatedly deferred as "too risky" because nobody has measured what it
touches. The measured blast radius on one install: 29 `AccessUser` rows, 19 `EcomOrders` rows, one
ERP cross-reference XSLT and 7 `EndsWith` call sites across 3 templates. Order and guards:

1. **Templates and the ERP cross-reference FIRST, data LAST, and no API re-save afterwards** (an
   MCP or API save on those rows re-writes them from the cached entity — see
   [dw-users-permissions](../../dw-users-permissions/SKILL.md) (`user-group-operations.md` §17b)).
2. **Grep for the suffix without assuming the separator.** Two of the seven call sites tested
   `EndsWith("ADMIN")` with no leading hyphen, so a grep for `-ADMIN` misses them. Search for the
   role word, not the decorated token.
3. **Guard the update so nothing else is caught**: `AccessUserType = 5` plus an explicit
   `LIKE '%-<SUFFIX>'` per known suffix, stripping with
   `LEFT(c, LEN(c) - CHARINDEX('-', REVERSE(c)))`. Staff numbers, unsuffixed ERP numbers, blanks
   and every `AccessUserType = 2` GROUP number must stay untouched — one run rolled back because a
   ship-to group carried the shared number.
4. **Write the revert BEFORE the update**, from a CSV dump of the pre-change rows, as one literal
   `UPDATE` per primary key — never as an expression over post-change values. Prove it by executing
   it inside a transaction and rolling back, asserting that the statement count equals the
   affected-row count so a mistyped key cannot hide.
5. **Rebuild the user index afterwards.** The Lucene directory keeps the old strings until a Full
   build runs; verify zero occurrences of the suffix in the rebuilt index.

This is a **local-install-only** SQL recipe: it exists because no verb reaches a bulk rewrite of a
column across dozens of rows, it bypasses every domain service (hence step 1's no-re-save rule and
step 5's rebuild), and a hosted install has no SQL surface at all — there the equivalent is a
per-user `UserSave` loop through the Management API, one contact at a time, with the same ordering.

The payoff is worth stating when someone asks whether it is worth it: on the install above, the
account-wide delivery-address setting had been on and provably inert for a year of increments, and
with the numbers normalised a buyer with no addresses of her own was offered her account's three
ship-tos at checkout with no template code at all.

## Account-wide favourites lists — impersonation plus one retrieval mode

"A salesperson creates a favourites list for a customer, and everyone on that account sees it"
needs no second app instance, no `IsShared` / `IsPublished` flag and no custom code on a solution
whose contacts share a customer number. Two facts:

- **The favourites app uses the same `RetrieveListBasedOn` key as the order family, and
  `UseCustomerNumber` is the value that shares lists across an account.** A setting named
  `RetrieveMyListsBasedOnCustomerNumber` is accepted, stored and completely inert — remove it from
  the paragraph rather than leaving a config that lies.
- **A list created under impersonation belongs to the impersonated customer.** `Pageview.User.ID`
  is the effective user, so the create command stamps the customer's `AccessUserId`; with
  `UseCustomerNumber` set, every contact on that account sees it immediately. Reading
  `EcomCustomerFavoriteLists` suggests otherwise — `AccessUserId` is the only ownership column and
  `IsShared` exists — which is what sends people looking for a sharing flag.

The `FavoriteCmd` request vocabulary, read from the handler and driven live on 10.28.x:

| Command | Keys |
|---|---|
| `addproducttofavoritelist` | `FavoriteListId`, `ProductId`, `ProductVariantId`, `Note`, `quantity` (lowercase), `UnitId` |
| `removeproductfromfavoritelist` | `FavoriteListId`, `ProductId`, `ProductVariantId` |
| `createfavoritelist` | `Name`, `Description` |
| `removefavoritelist` | `FavoriteListId` |
| `renamefavoritelist` | `FavoriteListId`, `Name`, `Description` |

Three sharp edges: the list key is **`FavoriteListId`**, and a request that says `ListId` converts
to `0` and the add is a silent no-op behind a normal `200` — the same zero-id no-op that bites Swift's own
favourites toggle template, which ships `FavoriteListId=0` for a user with no lists; `addproducttofavoritelist` takes **one product per
request**, so "add the selected cart lines" is a loop and not a batch verb; and
`EcomCustomerFavoriteProducts.ProductVariantId` / `Note` / `ProductReferenceUrl` / `UnitId` are all
NOT NULL, with the platform's own write storing the literal string `False` in `ProductReferenceUrl`
when the request carries no reference url — so a hand-written seed passes empty strings rather than
`NULL`.

## Cross-references

- [`dc-scoping.md`](dc-scoping.md) — the DC-as-user-group pattern and the three price scope columns.
- [dw-users-permissions](../../dw-users-permissions/SKILL.md) (`user-group-operations.md`) — the
  user/group write surfaces, and why an API re-save after a SQL write reverts it.
- [`order-lifecycle.md`](../../dw-commerce-orders/references/order-lifecycle.md) — the order family
  that shares the `RetrieveListBasedOn` key.
