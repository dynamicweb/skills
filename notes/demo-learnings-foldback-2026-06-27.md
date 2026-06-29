# Skill learnings mined from two external projects — fold-back report

**Date:** 2026-06-27
**Sources analysed:**
- `C:\VibeCode\Truvio.Commerce.BuildOptimization` — a meta-analysis of four past demos (cabp / kjl / idealwarehouse / stpauli).
- `C:\Projects\Solutions\centercon` — a freshly built presales demo (brands Heytec / Centercon / Reiss).

**Status:** Candidate fold-backs only. No skills were edited. Each fold-back below must follow
the one-way boundary (`CLAUDE.md` → "Skill categories") and the sanitized fold-back workflow
(`dw-demo-base/references/iterate-plugin.md`) before landing — strip every demo/customer
specific first. Each lands as **one atomic PR** per the contributing rules.

---

## Headline finding

The **BuildOptimization** project mostly *corroborates* existing skill content rather than
adding to it: its "DemoVerifier" integrity checks (reference_category parent row, query-GUID
dedup, feed template walk, `Database.*` in Swift templates, icon-set probe) map almost 1:1 onto
what `dw-demo-swift/references/integrity-sweep.md` already encodes. That independent validation
is valuable, but it yields only **two** net-new generic learnings (index-rebuild staleness;
version-pin / schema-drift).

The **centercon** build is where the real new material is — especially headless (CORS/BFF) and
index-build verification.

---

## Shortlist — genuine gaps / corrections (sanitized kernels)

Ordered by value. ★★★ = strong, clearly novel, foundational. ★★ = real gap, narrower or
caveated. ★ = generic pattern worth a mention.

### 1. Index build returning `Idle` does NOT prove a rebuild happened — ★★★
- **Kernel:** `build_product_index` / Management-API `BuildIndex` can report success/`Idle`
  while silently no-opping. Verify a *new* build-state folder appeared under
  `Files/System/Indexes/<repo>/Products/` (its mtime must advance); poll to `Idle` with a
  hard-bounded timeout (e.g. 15 min). Products are invisible to dashboards / feeds / storefront
  until the index is genuinely rebuilt — and the page still returns 200, so the failure is silent.
- **Corroboration:** Surfaced **independently in both projects** (BuildOpt: "poll Status=Idle,
  15-min hard bound"; centercon: "Idle ≠ rebuilt, check new build-state folder").
- **Target:** `dw-search-indexing` (foundational). **Status: GAP** — no current coverage of
  build verification / staleness.

### 2. DW10 Delivery API has no CORS and needs a BFF proxy — ★★★ (correction)
- **Kernel:** The Delivery API sends **no CORS headers** and returns **405 to OPTIONS
  preflight**, so direct browser calls fail (`TypeError: Failed to fetch`). A **server-side BFF
  proxy is mandatory** — you cannot "just configure CORS." Companion rules: product calls that
  omit `CountryCode` return **HTTP 500**; **`204 No Content` = zero matches**, not an error; a
  binary proxy (images/PDFs) must **preserve the upstream `Content-Type`** (never force
  `application/json`).
- **Why a correction:** `dw-headless-delivery/SKILL.md:565` currently says only *"the backend
  must be configured to allow your frontend's origin"* — which is insufficient/misleading given
  the API emits no CORS at all.
- **Target:** `dw-headless-delivery` (foundational). **Status: CORRECTION + GAP.**

### 3. `User.Groups` is obsolete; use `User.GetGroups()` — ★★
- **Kernel:** For membership gating in Swift/Razor templates use `User.GetGroups()` (returns
  `Group` objects with `.ID`). The legacy `User.Groups` property is obsolete and may not return
  the correct list.
- **Target:** `dw-extend-csharp-api` (lists `GetGroups` in the services table at SKILL.md:185 but
  does not flag the obsolete property). **Status: ENRICH** (one line).

### 4. Custom global product fields aren't reliably indexable via hand-edited XML — ★★
- **Kernel:** A custom global product field often won't resolve as an index `Source` when added
  by hand-editing the index XML. Workaround: store the token in an analyzed freetext source
  already wired (e.g. `MetaKeywords` / `seoKeywords`) and add the index field against *that*
  source, then query the index field name. Avoids writing a custom `.cs` index provider.
- **Caveat:** Flagged as instance-variance in the source — present as "verify on target host."
- **Target:** `dw-search-indexing` (foundational). **Status: GAP** (caveated).

### 5. B2B contract price scoped by `PriceUserId`, applied at checkout — ★★
- **Kernel:** Contract pricing resolves via a `Price` row scoped to the user (`PriceUserId`) and
  renders at **cart/checkout time, not on PLP/PDP**. The exact param (`PriceUserId` vs
  `PriceUserCustomerNumber`) is **instance-variant — verify live** before relying on it. A
  net-new price-gate template can show a "log in for your price" nudge to anonymous users.
- **Target:** `dw-commerce-b2b` (no pricing coverage today) or `dw-commerce-orders`.
  **Status: GAP** (caveated).

### 6. Floating `Dynamicweb.Suite 10.*` pins are a schema-drift risk — ★★
- **Kernel:** Pin `Dynamicweb.Suite` to the **baseline-capture version** (e.g. the version the
  YAML was round-tripped against), never float `10.*` — a floating pin resolves to the latest
  10.x at restore time and can carry schema columns the YAML was never captured against. On a
  deliberate cross-version deserialize, **drop the columns absent on the target from the staged
  YAML** before deserializing (re-apply on every fresh re-stage).
- **Target:** `dw-setup-upgrade` and/or `dw-demo-swift/references/deserialize-flow.md`.
  **Status: ENRICH.**

### 7. Model product lifecycle as fields, never `Name.Contains` — ★
- **Kernel:** Represent discontinued/phased-out state as global fields (`Lifecycle`,
  `SubstituteProductId`) and render the banner + substitute link in a net-new template that gates
  on the field value and resolves the substitute via `Services.Products.GetProductById(...)` +
  `Linking.GetProductLink(...)`. Zero `Name.Contains` routing, zero `Database.*` SQL.
- **Target:** `dw-pim-modelling` or `dw-commerce-catalog`. **Status: ENRICH** (generic pattern).

---

## Already covered — confirmed accurate by these builds (no action)

These appeared in the source material but are already encoded in skills; the builds independently
validate them:

- `reference_category` load-bearing parent row → `dw-demo-swift/references/integrity-sweep.md`
  (Check 2) and `dw-demo-pim/references/structural-model.md` §2.8 / `canonical-setup-order.md`.
- CSR impersonation via `AccessUserSecondaryRelation` + mandatory cache-restart →
  `dw-demo-swift/references/customer-center.md` §5.
- `EncryptPassword=False` plaintext escape hatch → `dw-demo-pim/references/permissions-recipes.md`.
- `excludeAreaColumns` seed-import guard → `dw-demo-swift/references/deserialize-flow.md`.
- Serializer rebranding + net8-library-back-loaded-into-net10-host nuance →
  `dw-demo-base/references/serializer-reference.md` and the `dw-setup-*` skills.
- "Any render-time composition tree (paragraphs/users/groups/nav) is cached at startup → restart
  after direct SQL" → `dw-demo-swift/references/paragraphs.md`.
- Quote Flows / "Checkout to quote" → `dw-commerce-orders/SKILL.md` (lines 17, 220, 240). The
  centercon MCP-level detail (`create_order_state orderType=Quote`, `OrderComplete` flag,
  `set_module_settings CheckoutToQuote 0→1`) could *enrich* this but is not a gap.
- Surface priority MCP → API → UI → SQL → `dw-demo-base/references/surface-priority.md`.
- The whole "DemoVerifier" check set from BuildOptimization → `dw-demo-swift/references/integrity-sweep.md`.

---

## Demo-specific — must NOT fold up (one-way boundary)

These only make sense with customer/brand/engagement context, or are demo-workflow concerns.
They stay in demo notes (`dw-demo-*`) at most — never in a foundational skill:

- ngrok static-domain budgeting + `--host-header=rewrite` (already in
  `dw-integration-bc/references/tunnel.md` / `forwarded-headers.md`).
- Lovable React 18 + Vite + Tailwind + shadcn stack specifics; `VITE_`-prefixed env baked at
  build time; `set_project_knowledge` / `set_workspace_knowledge` persistence.
- ETIM 10.0 as *the demo's* product domain (HVAC classes EC0120xx etc.). The generic kernel —
  "render `productCategories` generically, never hard-code class/feature codes" — is the only
  foundational-worthy part and is minor.
- All persona/brand identifiers: Heytec, Centercon, Reiss, KKVB-Group; Daan Bakker, Lisa Jansen,
  Sanne de Vries, Van den Berg; HEY-10001, VDB-3000, HP-2000/HP-3000, PROD1–PROD14; demo names
  cabp / kjl / idealwarehouse / stpauli.
- Per-phase `.bak` reversibility checkpoints and the proof-as-artifact (Playwright harness +
  recorded fallback) — demo-build workflow, belong in `dw-demo-base` if anywhere.
- Hardcoded absolute paths (`C:\VibeCode\DynamicWeb.Serializer` legacy drift, demo roots) — the
  generic lesson "resolve via slot/env, never hardcode" is already implicit in the skills.

---

## Suggested PR order if/when actioned

1. `dw-search-indexing` ← #1 index-build verification (highest confidence, foundational gap).
2. `dw-headless-delivery` ← #2 CORS/BFF correction (corrects an inaccurate line).
3. Then #3–#7 individually, each its own atomic PR, sanitized per `iterate-plugin.md`, with a
   CHANGELOG entry and `metadata.version` bump, validated by `scripts/validate-skills.py`.
