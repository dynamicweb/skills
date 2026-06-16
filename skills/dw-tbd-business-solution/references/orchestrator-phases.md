# Orchestrator Phase Reference

## Phase Definitions

Each phase is designed to be **idempotent** — running it again when already complete should
produce no new side effects (it detects existing state and skips).

| # | Phase | Idempotent | Depends On | Key Tools |
|---|-------|-----------|------------|-----------|
| 0 | Parse Business Request | Yes | — | None (LLM only) |
| 1 | Permission Prompt | Yes | 0 | None |
| 2 | Install Swift 2 | Yes* | 1 | `GetAreas` to detect, script to install |
| 3 | Bootstrap MCP | No** | 2 | POST /admin/mcp/bootstrap |
| 4 | Attach MCP | Yes | 3 | bootstrap-and-attach.ps1 |
| 5 | Discover State | Yes | 4 | GetAreas, GetShops, GetLanguages, GetCurrencies, GetPagesByArea |
| 6 | Foundation (Lang/Curr/Country) | Yes | 5 | SaveLanguages, SaveCurrencies, SaveCountries |
| 7 | Update Shop | Yes | 6 | SaveShops |
| 8 | Site Branding | Yes | 7 | PatchArea, PatchPage, GetPageByNavigationTag |
| 9 | Product Groups | Yes | 7 | SaveGroups |
| 10 | PIM / DataModels | Yes | 7 | CreateDataModelStructure |
| 11 | Products | Partial | 9, 10 | CreateProducts, AssignProductsToGroup |
| 12 | Images | Yes | 11 | DownloadRemoteImages, ImportProductImagesFromUrls, SaveShops (image patterns) |
| 13 | Commerce (Units/Manufacturers/Prices) | Yes | 11 | SaveUnits, SaveManufacturers, SavePrices |
| 14 | Checkout (Payment/Shipping/OrderFlow) | Yes | 7 | GetPayments, CreatePayment, GetShippings, CreateShipping, GetOrderFlows, CreateOrderFlow |
| 15 | Build Product Index | Partial | 11 | BuildProductIndex(synchronous=true) |
| 16 | Queries & Dashboard | Yes | 15 | CreateOrUpdateProductQueries, CreateDashboards |
| 17 | Verification | Yes | 15 | FetchFrontendPageHtml, VerifyProductVisibility, GetProductsByQuery |
| 18 | Summary | Yes | all | None (LLM only) |

*Install is idempotent in detection (GetAreas checks), but installing twice creates issues.
**Bootstrap is one-shot by design (endpoint returns 409 after first use).

## Run Manifest Schema

Saved at `{workspace}/.dw-setup-run.json`:

```json
{
  "schemaVersion": 1,
  "businessName": "DWinery",
  "businessType": "B2C",
  "industry": "food-beverage",
  "productTypes": ["Red Wine", "White Wine", "Rosé"],
  "primaryLanguage": "en",
  "primaryCurrency": "EUR",
  "primaryCountry": "DK",

  "phases": {
    "0_parse":       { "status": "completed", "timestamp": "..." },
    "1_permission":  { "status": "completed", "timestamp": "...", "preset": "All" },
    "2_install":     { "status": "completed", "timestamp": "..." },
    "3_bootstrap":   { "status": "completed", "timestamp": "...", "credentialsFile": "..." },
    "4_attach":      { "status": "completed", "timestamp": "..." },
    "5_discover":    { "status": "completed", "timestamp": "...",
                       "areaId": 1, "shopId": "SHOP1",
                       "languageId": "LANG1", "currencyId": "EUR" },
    "6_foundation":  { "status": "completed", "timestamp": "...",
                       "languageId": "LANG1", "currencyId": "EUR", "countryCode": "DK" },
    "7_shop":        { "status": "completed", "timestamp": "..." },
    "8_branding":    { "status": "completed", "timestamp": "...", "mode": "degraded" },
    "9_groups":      { "status": "completed", "timestamp": "...",
                       "groupIds": {"Red Wine": "GRP1", "White Wine": "GRP2"} },
    "10_pim":        { "status": "completed", "timestamp": "..." },
    "11_products":   { "status": "completed", "timestamp": "...",
                       "productIds": ["PROD1", "PROD2"], "count": 6 },
    "12_images":     { "status": "completed", "timestamp": "...", "mode": "convention" },
    "13_commerce":   { "status": "completed", "timestamp": "..." },
    "14_checkout":   { "status": "completed", "timestamp": "..." },
    "15_index":      { "status": "completed", "timestamp": "..." },
    "16_queries":    { "status": "completed", "timestamp": "..." },
    "17_verify":     { "status": "completed", "timestamp": "...", "mode": "backend-only" },
    "18_summary":    { "status": "completed", "timestamp": "..." }
  },

  "lastCompletedPhase": 18,
  "overallStatus": "completed",
  "residualGaps": ["Item-level branding requires admin UI"],
  "startedAt": "...",
  "completedAt": "..."
}
```

## Resume Logic

```
1. Check if {workspace}/.dw-setup-run.json exists
2. If yes:
   a. Read the manifest
   b. Find the last completed phase
   c. Offer: "Found an in-progress {businessName} setup (phase {N}/{total} complete). Resume?"
   d. If resume: start from phase N+1, carrying forward all stored IDs
   e. If restart: delete the manifest, start from phase 0
3. If no: start from phase 0
```

## Phase Status Values
- `pending` — not yet started
- `in_progress` — currently executing
- `completed` — finished successfully
- `completed_degraded` — finished with fallback behavior
- `failed` — failed, needs manual intervention
- `skipped` — intentionally skipped (e.g., install when already installed)
- `awaiting_user` — waiting for user action (e.g., manual config paste)
