# Ownership and process questions

Review these with the ERP and commerce owners. Record the answer, source, decision owner and
acceptance test. Use [`dw-integration-erp`](../../dw-integration-erp/SKILL.md) for the general
source/target rule. BC is never a product channel or a merchandising feed target by default.

| Topic | Decision to resolve |
|---|---|
| Item lifecycle | Who creates the item and controls web eligibility, variants and units? |
| Product enrichment | Which descriptions, translations, assets and workflow fields belong to PIM? Which return to BC? |
| Pricing | Does BC or a CRM own MSRP/group/customer terms? Which price engine, currencies, dates and stacking policy apply? |
| Promotions | Which modifiers belong to marketing, and how are accepted discounts preserved on the BC order? |
| Plants | Which BC customer and ship-to records define a plant? Who can add/change them? Which buyer roles may select them? |
| Inventory | On-hand, available or ATP? Which reservations, locations, item cross-references and latency count? |
| Legal entities | Which company sells/invoices, which fulfils, and how does intercompany routing work? Who owns tax and legal policy? |
| Bundles | Operational assembly or marketing phantom SKU? Where does expansion occur and how are amounts allocated? |
| Credit | Which ERP operation decides on-account admission, including outstanding exposure and concurrent recurrences? |
| Orders | Approval/credit trigger, export writer, duplicate handling, partial failure and reprice policy? |
| Documents | Required shipment/invoice/payment/credit history and cross-account access rules? |
| Operations | Watermarks, deletes, rate limits, monitoring, reset/refresh, credentials and recovery owner? |

A process gap becomes an implementation dependency, not an invented connector capability.
Cross-company fulfilment and atomic credit admission in particular need a measured ERP
contract. Keep requirements separate from a proposed mechanism until the owner accepts it.

Done: each field and operation has one writer, one reader contract and a reproducible test;
unanswered decisions remain visibly pending.
