# Staged sync rehearsal

Run [bc_demo_fixture.py](../scripts/bc_demo_fixture.py) to produce a deterministic local,
normalised JSON fixture. It is a **mock contract**, not a captured BC response. Baseline and
reset produce identical business data. Changed mode alters a tier price and one location's
stock while preserving keys. No network calls or ERP/Commerce writes occur in this script.

The fixture includes two companies sharing item and customer numbers, a ship-to per account,
base/group/customer prices, location inventory, a marketing bundle with real item components,
and a sample order/status/invoice link. Credit rows are labelled proposed contract examples;
they never prove BC's admission logic.

To rehearse real Integration Framework jobs:

1. Generate baseline outside the installed skill, with the demo's own IDs in its mapping spec.
2. Use a JSON source provider only if installed and its schema is measured; otherwise reshape
   the fixture into XML/CSV using an engagement-owned adapter and explicit provider mappings.
   Do not label the normalised fixture as a vendor SOAP payload.
3. Import into demo-owned records with actual Integration Framework activities. Read back
   products, account/address parents, tier prices and stock locations. Build indexes and
   inspect the buyer's PDP/cart.
4. Generate changed inputs and run the same activities. Prove only the intended tier/location
   changed. Repeat unchanged input and compare IDs, counts and values.
5. Generate reset inputs and rerun imports; verify the original buyer prices and inventory.
   Mark the evidence mode `mock`.

For live mode capture the selected BC endpoint contracts and bind activities through
[`dw-integration-bc`](../../dw-integration-bc/SKILL.md). Repeat every required acceptance
scenario against BC and the rendered storefront. The offline verifier rejects a mock report
when live acceptance was requested.
