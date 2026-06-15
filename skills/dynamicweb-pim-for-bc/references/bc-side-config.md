# bc-side-config.md

> Configure the **Business Central** side of the integration -- the BC tenant that's calling our public ngrok URL. Loaded from `~/.claude/skills/dynamicweb-pim-for-bc/SKILL.md` "Where to find things" table.

## Scope

This reference covers what BC needs configured to talk to a Dynamicweb host. It does NOT cover BC tenant provisioning or licencing -- assumes you have a BC environment (sandbox or production) where you can install extensions and edit setup pages.

## Prerequisites on the BC side

- A BC environment (Cloud SaaS, on-prem, or sandbox) with admin rights.
- The "Dynamicweb PIM Connector" extension installed in BC. Available in the BC AppStore (Microsoft AppSource) -- search for "Dynamicweb". This is the BC-side counterpart to the dynamicweb-side "PIM for Business Central connector" AppStore app.
- The dynamicweb-side app installed and `BCSettings` corrected (see [dynamicweb-connector-settings.md](dynamicweb-connector-settings.md)).
- Dynamicweb host running; tunnel up at the reserved domain (see [tunnel.md](tunnel.md)).

## Two configuration values BC needs

### 1. The PIM URL

In BC, navigate to: **Setup -> Dynamicweb PIM Setup** (or "PIM Connection Setup" -- exact label varies by extension version).

Set:

- **PIM URL**: `https://<your-reserved>.ngrok.app` -- the ngrok-exposed URL, NOT `localhost`. Trailing slash optional (BC trims it).
- **API path**: usually defaulted to `/admin/api/` -- leave as-is unless your DW host serves the management API at a non-standard path.

### 2. The bearer token

Issue or reuse a Dynamicweb Management API token:

- **Issue dedicated**: in DW admin -> Settings -> Integration -> Management API tokens, create a new token labelled "BC Connector" with full-access permissions. Copy the token string immediately (DW only shows it once).
- **Reuse existing**: paste the same token from `.claude/settings.local.json -> env.DW_API_TOKEN`. Simpler for a one-off demo; revocation isn't independent.

In BC, paste the token into:

- **Authentication Token** (or "Bearer Token" -- field label varies). BC stores this securely in its tenant config.

## First-call test in BC

The BC connector extension typically exposes a **Test Connection** button on the setup page. Hit it and watch:

| Result | Meaning | Fix |
|---|---|---|
| "Connected -- PIM v2 (PIM:true, Ecom:true)" | Public URL + token + ngrok tunnel + ForwardedHeaders all working | None, you're done |
| "Connection failed: 401 Unauthorized" | Token is wrong, expired, or BC is sending it in a non-Bearer format | Re-issue token; double-check BC's auth-header format setting |
| "Connection failed: 400 Unknown query" | URL is reaching DW but BC is hitting a non-existent endpoint | Check the BC extension's expected endpoint version vs what's installed on the Dynamicweb side |
| "Connection failed: timeout / DNS error" | ngrok tunnel down, or BC's outbound HTTP is blocked | `ngrok config check` + retry tunnel; check BC tenant outbound firewall |
| "HTML received instead of JSON" | ngrok interstitial fired (free tier) OR Host header issue routing to a non-API page | Confirm paid plan is in use; inspect via `127.0.0.1:4040` to see what BC's request looks like |

Test Connection ultimately calls `GET /admin/api/BCLicense` under the hood. If it succeeds, the entire chain is verified end-to-end.

## Field mapping setup -- REQUIRED, not optional

**BC will not pull product rows until column mappings are saved.** Test Connection green is not enough; field schema fetched is not enough; the language picker filled in is not enough. Without at least one BC item field mapped to a PIM field, BC stays in a discovery-only loop -- it polls `BCLicense`, `BCSettings`, `BCProductFields`, `GetLanguages`, and `BCProductCountByLastModified` repeatedly, but never calls `BCProductIdsByLastModified` or `BCProductById`. The PIM list page in BC stays empty even though `BCProductCount` returns `totalCount=35` (or whatever your catalog size is).

This is the single most common stuck-state for first-time setups. The connector requires mappings to exist before it knows how to materialise an item locally; without that, fetching IDs is pointless.

In BC, navigate to the PIM column-mapping page (label varies by extension version -- "PIM Field Mapping", "Item Field Mapping", or similar in the Dynamicweb PIM Setup card's Related actions). The extension fetches the schema from `GET /admin/api/BCProductFields` -- the response includes:

- 50+ fields in a typical demo (10 standard + 40+ category-specific).
- Each field carries `name`, `label`, `systemName`, `type`, `category`, `categoryType`, `options[]` (for list fields).
- Category-specific field system names follow `ProductCategory|<CategoryId>|<FieldId>` -- e.g. `ProductCategory|<CategoryName>Attributes|<CategoryName>_HeroImageUrl`.

Map BC's standard item fields (No., Description, Unit Cost, Item Category, etc.) to the corresponding PIM fields. **A minimal mapping (just No. -> ProductNumber + Description -> ProductName) is enough to unblock the pull;** you can flesh out the full mapping after products are flowing. The mapping is BC-side configuration; it doesn't write back to PIM.

### Diagnostic pattern when sync sits idle

If BC says "Connected" but no product data ever appears, watch the ngrok inspector at `127.0.0.1:4040` while BC is running. Categorise the calls:

| Calls you see | What it means |
|---|---|
| `BCLicense` + `BCSettings` + `BCProductFields` + `GetLanguages` + `BCProductCountByLastModified` only | **Mappings missing or invalid.** BC is in discovery loop. Save column mappings in BC, then retry. |
| Above PLUS `BCProductIdsByLastModified` (one call) PLUS a burst of `BCProductById?id=...` | Healthy first sync in progress |
| `BCProductIdsByLastModified` returns 35 IDs but no `BCProductById` follow-ups fire | Mapping exists but BC's per-item resolver is failing -- check BC's job queue / activity log for errors |

The Count-only-no-IDs signature is the canonical missing-mapping fingerprint. Save it as the first thing to check whenever a BC PIM connector demo "connects but shows nothing".

## First sync

Trigger the first sync from BC -- typically a **Sync All** or **Initial Load** button. BC walks:

1. `GET /admin/api/BCProductFields` -- field schema.
2. `GET /admin/api/BCProductIdsByLastModified?lastModified=1900-01-01T00:00:00Z` -- get all product ids ever modified (effectively "everything").
3. For each id BC doesn't yet know about, BC pushes via `POST /admin/api/BCProductCreate` (or pulls via `GET /admin/api/BCProductById?id=...` to populate BC fields, depending on direction of sync).
4. Optionally `POST /admin/api/BCBuildIndex` to refresh the Products index after the bulk operation.

Watch the ngrok inspector at `127.0.0.1:4040` -- you'll see every BC request fly by, with status, latency, and response shape.

## Demo narrative

Three crisp beats once everything is up:

1. **"This is a real BC tenant"** -- show the BC web client, the Dynamicweb PIM Setup page with the ngrok URL filled in.
2. **"Click Test Connection"** -- the green checkmark, response shows `PIM:true, Ecom:true` from a real running PIM instance.
3. **"Push an item from BC"** -- create or modify an item in BC, watch it appear in the Dynamicweb admin UI within seconds. Switch to the dashboard, point out the "New Product From BC" workflow state -- governance baked into the integration.

If the demo audience is the BC team specifically, also show: BC pulling the PIM field schema, mapping a BC item category to a PIM data model. This is where BC's role as the operational system meets PIM's role as the master data system -- the demo's punchline.

## Bidirectional vs unidirectional flows

The BC connector supports both directions, but the choice is configured BC-side:

- **BC -> PIM** (BC is master): BC pushes item changes via `BCProductCreate` / `BCProductUpdate`. PIM acts as the publishing layer. Common for orgs where BC's item master is canonical.
- **PIM -> BC** (PIM is master): BC pulls via `BCProductBy*` queries on a schedule. PIM is canonical; BC consumes. Common for orgs where the PIM team owns the master data and BC is purely operational.
- **Mixed**: most orgs run mixed -- BC owns some fields (price, stock), PIM owns others (descriptions, hero images, category attributes). The connector supports field-level direction via BC-side mapping config.

The dynamicweb-side endpoints support both directions transparently -- the API surface is the same.

## Token rotation

When the demo is over and the reserved domain is no longer needed, revoke the BC's Dynamicweb token in DW admin -> Settings -> Integration -> Management API tokens. The BC tenant's stored token becomes invalid; subsequent calls return 401. This is the right cleanup for shared-account demos -- prevents stale credentials lingering in BC tenants.
