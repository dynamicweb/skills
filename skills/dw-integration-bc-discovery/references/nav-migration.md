# NAV to Business Central migration

Discover NAV and the target BC system separately. NAV 2017 pages/codeunits and customer
customisations do not become BC API v2 resources automatically. The target BC version,
extensions and partner migration plan decide the supported integration surface.

| Compare | Migration question |
|---|---|
| Identity | Do item/customer numbers survive? Map NAV company/name/record keys to BC company GUID/SystemId. |
| Pricing | Which legacy sales price/discount structures become the new price experience? Keep group/customer/currency/UOM semantics. |
| Contacts and plants | Which ship-to and contact links migrate, and which account is their parent? |
| Stock | Do locations, UOMs, reservations and availability meaning survive? |
| Custom fields | Which remain standard fields, become AL extension fields or are retired? |
| Orders and documents | How will open orders, partial invoices, posted history and external references be accessible? |
| Transport | Which published services and authentication are supported in each system? |
| Cutover | Who owns the key crosswalk, last delta, duplicate prevention, reconciliation and rollback? |

Keep source captures immutable. Ask for sanitised schema exports, extension inventory and
sample records rather than unrestricted copies of production data. Never enable writes in a
new BC sandbox on the assumption that it represents the customer's migrated NAV configuration.

Done: a source-to-target gap matrix records verified parity, mapping work and unverified
assumptions. Target BC acceptance uses target BC evidence, not a NAV screenshot.

Source: [upgrade paths](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/upgrade/upgrade-paths).
