# Demo profile

Create an engagement-owned profile from the discovery brief. Record the story and whether
each beat is **live**, **mock**, or **proposed**. Use the same key and ownership contracts
for rehearsal and live integration.

| Profile section | Required contents |
|---|---|
| Environment | Owner selection, Sandbox proof, allowed company GUIDs and freeze windows |
| Companies and locations | Selling/fulfilment map, item/customer crosswalk and intercompany policy |
| Products | Real ERP item, variant/UOM; PIM-owned enrichment and separate marketing bundle |
| Accounts and plants | BC-owned customer/ship-to; buyer roles and address creation policy |
| Prices | Base/group/customer source rows, currency/date/quantity, Commerce promotion |
| Credit | Live admission contract for checkout and every subscription recurrence |
| Documents | One completed order, partial shipment, invoices and buyer authorisation |
| Reset | Owned IDs, input snapshots, restore operations, post-reset assertions |

Build one visible cause-and-effect per beat: ERP changes a base price; the scheduled activity
applies it; the correct buyer sees it; a Commerce promotion applies once; an expanded bundle
exports as real items; ERP documents return to the same account. Keep evidence by beat.

The profile should say which capabilities require an extension or an ERP-owner decision.
Cross-company sourcing, shipping calendars and credit are not established by a working PIM sync.
Customer names and actual environment details belong in the engagement profile, not the skill.
