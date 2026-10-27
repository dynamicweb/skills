# Reset and isolation

Before rehearsal, snapshot integration-owned source rows, external-key mappings, activity
bindings, watermarks and the buyer-visible starting values. Keep a list of the exact
company/record IDs created for the demo. Store credentials only in the vault/environment.

Reset means a declared restoration, not deleting an environment or rolling a shared company
back. Use supported ERP and platform operations on owned records. Posted documents remain
as evidence or use explicitly authorised reversal workflows; they cannot be removed as if
they were unposted test drafts.

Give each native opening-inventory posting a durable, company-local seed receipt keyed by seed
version and item. In one transaction, validate the owned item/location/UOM, post through the native
journal engine and write its receipt. A replay reads the receipt and preserves subsequent BC
inventory changes instead of posting the opening quantity again. Prove the first run against
native item inventory, then repeat unchanged input and assert zero new receipts and unchanged
quantities. Import reset and journal replay are different operations; restoring a Commerce snapshot
cannot reset BC inventory. Freeze seed source/packages through the extension contract in
[`dw-integration-bc`](../../dw-integration-bc/SKILL.md).

| Layer | Restore | Post-reset assertion |
|---|---|---|
| Local mock | Generate `--phase reset --apply` in the owned fixture directory | Business data hash equals baseline |
| BC master data | Restore only owned values using their current keys and concurrency tokens | Source values match snapshot |
| Integration | Restore selected endpoints, run order and appropriate watermark | No donor/foreign company selected; replay still upserts |
| Orders/documents | Preserve ERP IDs and export ledger; create a new attempt only when intended | No duplicate export; invoice links still authorise correctly |
| Commerce | Re-import owned data; refresh declared caches/indexes | Same buyer sees baseline tiers, stock and addresses |

An environment refresh invalidates company GUIDs, Entra-application permissions and copied
endpoint assumptions. Rediscover and rebind before allowing exports again. For retirement,
disable the demo's schedules and live writers, unbind its endpoints and record owned company
IDs as dormant; the environment owner decides lifecycle actions.

Before a freeze, finish reset and a measured acceptance run. Inside the freeze use read-only
checks and preserve the recorded baseline. Honour any active-session lease before touching
the demo folder or host.
