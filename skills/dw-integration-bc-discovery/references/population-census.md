# Population and key census

Sample each required entity in each selected company. Record read time, source URL, HTTP
outcome, count completeness and join coverage; follow every server-provided next link for a
full census. The inventory script deliberately samples at most one row and labels that limit.
Its sample count must not become a claimed full entity count.

| Population | Joins and negative example |
|---|---|
| Items / variants / units | Item SystemId, item number, variant and sales UOM; missing UOM |
| Customers / contacts | Sold-to, bill-to, login relation, blocked account; same number in two companies |
| Plants / ship-to | Customer + ship-to code + location; address owned by another customer |
| Base and tier prices | All/group/customer, currency, UOM, quantity, dates; overlapping and expired rows |
| Locations / stock | Company + item + variant + location; missing SKU row and stale company |
| Orders / shipments | Source order reference, line IDs and partial quantities; posted order no longer present |
| Invoices / credits | Many documents per order; order-line linkage, PDF and account authorisation |

Count duplicate natural keys before deciding IDs. Compare the same item and customer numbers
across companies. If canonical products span companies, build a reversible cross-reference;
keep company-qualified customer and document identities regardless.

Distinguish empty, denied, unavailable and not queried. Record evidence of deletes or blocked
records before choosing mirror/delete behaviour. Prefer incremental upsert until a full-source
snapshot and an integration-owned deletion scope are proved.

Done: the proposed key spine joins the actual populated records, and unknown populations have
an owner. The review can explain why each proposed activity is needed.
