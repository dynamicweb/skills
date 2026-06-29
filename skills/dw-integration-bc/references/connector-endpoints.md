# connector-endpoints.md

> Demo-facing map of the `/admin/api/BC*` call surface — *which BC call fires when* during a live
> demo, and where to read the full platform reference. The vendor-generic connector product surface
> (single-dispatcher call convention, the suffix rule, 400-vs-401 auth semantics, the full
> 11-query/4-command inventory, the `{"Model":{...}}` wrapper rule, the internal pipeline/provider
> types, and the BC default settings the install seeds) lives in the foundational candidate
> [`integration-bc-connector.md`](../../dw-demo-base/references/foundational/integration-bc-connector.md).
> The assembly-introspection technique for re-deriving the surface yourself is in
> [`source-explorer.md`](../../dw-demo-base/references/foundational/source-explorer.md).

## Which call fires when — the demo arc

Read the call convention and the full endpoint inventory in
[`integration-bc-connector.md`](../../dw-demo-base/references/foundational/integration-bc-connector.md)
first. During a live demo the BC tenant walks the surface in this order — knowing the order lets you
narrate the ngrok inspector (`127.0.0.1:4040`) in real time:

1. **`GET /admin/api/BCLicense`** — handshake. BC's Test Connection calls this first; a 200 with
   `pim:true, ecommerce:true` is the "green checkmark" beat.
2. **`GET /admin/api/BCSettings`** + **`GET /admin/api/BCProductFields`** — BC reads the connector
   config and the PIM field schema so it can offer column mappings.
3. **`GET /admin/api/BCProductCountByLastModified`** — BC sees how many products exist. If the demo
   sticks at "connected but empty", the wire shows *only* steps 1–3 looping (the missing-mapping
   signature — see [bc-side-config.md](bc-side-config.md)).
4. **`GET /admin/api/BCProductIdsByLastModified`** then a burst of **`GET /admin/api/BCProductById`**
   — the healthy first sync, once a mapping exists.
5. **`POST /admin/api/BCProductCreate` / `BCProductUpdate`** — the "push an item from BC, watch it
   land in PIM" beat. Optionally followed by **`POST /admin/api/BCBuildIndex`**.

## Two diagnostics worth memorising for the demo

- **400 `Unknown query: 'X'` vs 401** — 400 means auth succeeded but the route name is wrong
  (usually the `Query`/`Command` suffix wasn't stripped); 401 means the token is wrong/expired.
  Full semantics:
  [`integration-bc-connector.md`](../../dw-demo-base/references/foundational/integration-bc-connector.md)
  "Authentication".
- **400 `Command.Model cannot be null`** on a POST — the `{"Model":{...}}` wrapper was omitted. This
  is the easiest mistake on the first write attempt. Wrapper rule:
  [`integration-bc-connector.md`](../../dw-demo-base/references/foundational/integration-bc-connector.md)
  "Writes".

Token issuance (admin path + reuse-vs-dedicated tradeoff) and rotation are covered in
[bc-side-config.md](bc-side-config.md) §2.
