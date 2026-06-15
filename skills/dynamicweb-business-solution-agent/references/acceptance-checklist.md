# Acceptance Checklist

Deterministic validation checklist for verifying a one-prompt Dynamicweb store setup.
Based on failures discovered during the DWinery pilot run.

---

## How to Use

After the orchestrator completes (or claims to complete), run through this checklist.
Each check uses available MCP tools — no browser or Playwright required.

Mark each check as: PASS, FAIL (with reason), or SKIP (tool not available).

---

## Checklist

### 1. Swift 2 Installed
```
Tool: GetAreas
Check: At least one area exists
Check: Area.LayoutTemplate contains "Swift-v2"
Expected: PASS
```

### 2. MCP Attached and Callable
```
Tool: GetAreas (acts as connectivity test)
Check: Tool returns data without auth errors
Expected: PASS
```

### 3. Shop Renamed
```
Tool: GetShops
Check: At least one shop.Name matches the business name (not "Swift" or "Demo")
Expected: PASS
```

### 4. Languages Configured
```
Tool: GetLanguages
Check: At least one language matching the business's primary language exists
Expected: PASS
```

### 5. Currencies Configured
```
Tool: GetCurrencies
Check: At least one currency matching the business's primary currency exists
Expected: PASS
```

### 6. Countries Configured
```
Tool: GetCountries
Check: At least one country matching the business's primary market exists
Expected: PASS
```

### 7. PIM Structure Created
```
Tool: GetShops (UsageType=DataStructure)
Check: At least one DataStructure shop exists with DataModel folders
Alternative: GetProductCategoryFields returns custom fields
Expected: PASS
```

### 8. Product Groups / Categories Created
```
Tool: GetGroups
Check: Groups exist with names matching the business's product types
Check: Groups are linked to the correct shop
Expected: PASS (count >= number of product types)
```

### 9. Products Created
```
Tool: GetProducts
Check: At least N products exist (N = product types × 2)
Check: Products have names, numbers, and prices
Expected: PASS (count >= {expectedMinimum})
```

### 10. Products Assigned to Groups
```
Tool: GetProductsByGroupId (for each group)
Check: Each product group has at least 1 product
Expected: PASS
```

### 11. Product Images Wired
```
Tool: GetShop (the main shop)
Check: Shop.ImageFolder is set (not null/empty)
Check: Shop.ImagePatternMain is set
Alternative: GetProductById for sample products — check image fields
Expected: PASS or DEGRADED (convention-based)
```

### 12. Product Index Built
```
Tool: GetProductsByQuery or GetProductsBySearchFilter
Check: Returns products (not empty)
Alternative: GetProductsBySku with a known product number
Expected: PASS
Failure mode: Products created but index not built — this was the #1 DWinery failure
```

### 13. Area/Website Renamed
```
Tool: GetAreas
Check: Area.Name matches the business name (not "Swift" or default)
Expected: PASS
```

### 14. Area Linked to Shop
```
Tool: GetAreas
Check: Area.EcomShopId is set and matches the main shop ID
Expected: PASS
```

### 15. Homepage Updated
```
Tool: GetPageByNavigationTag(areaId, "homepage")
Check: Page exists
Check: Page.MetaTitle contains the business name
Expected: PASS
```

### 16. Navigation Tags Set
```
Tool: GetPageByNavigationTag for each critical tag
Tags to check: homepage, shop, cart, checkout, login, register
Check: All return a page (not null)
Expected: PASS (6/6 critical tags found)
Failure mode: Missing tags break Swift 2 checkout — this was a DWinery issue
```

### 17. Category Pages Exist
```
Tool: GetPagesByArea(areaId)
Check: Pages exist under the Shop page for each product type
Check: Pages are Active and Published
Expected: PASS
```

### 18. Payment Methods Configured
```
Tool: GetPayments
Check: At least one active payment method exists
Expected: PASS
```

### 19. Shipping Methods Configured
```
Tool: GetShippings
Check: At least one active shipping method exists
Expected: PASS
```

### 20. Order Flow Exists
```
Tool: GetOrderFlows
Check: At least one order flow exists with states
Expected: PASS
```

### 21. Storefront Renders (if verification tools available)
```
Tool: FetchFrontendPageHtml(path="/")
Check: Status 200, title contains business name
Check: No error pages or blank responses
Expected: PASS or SKIP (tool not available)
```

### 22. Products Visible on Storefront (if verification tools available)
```
Tool: VerifyProductVisibility(productNumbers=[...])
Check: Products found in index
Expected: PASS or SKIP (tool not available)
```

---

## Scoring

```
Total checks: 22
Critical (must pass): 1-6, 8-9, 12-16, 18-20 (16 checks)
Important (should pass): 7, 10-11, 17 (4 checks)
Optional (nice to have): 21-22 (2 checks)

Score: {passed}/{total} ({critical_passed}/{critical_total} critical)
```

---

## Winery Scenario Specific Checks

For a winery business setup, additionally verify:

| Check | Tool | Expected |
|-------|------|----------|
| Red Wine group exists | GetGroups | Name contains "Red" or "Wine" |
| White Wine group exists | GetGroups | Name contains "White" |
| Wine products have prices | GetPricesByProductId | At least one price per product |
| Shop image folder set | GetShop | ImageFolder contains "wine" or business slug |
| EUR currency exists | GetCurrencies | Code = "EUR" |

---

## Running the Checklist Programmatically

The orchestrator should run this checklist as Phase 17 (Verification).
For each check:
1. Call the specified tool
2. Evaluate the condition
3. Record PASS/FAIL/SKIP with details
4. Include in the final summary

Example output:
```
## Acceptance Results: DWinery

✓ 1. Swift 2 installed (area ID: 1, template: Swift-v2/MasterPages/Master.cshtml)
✓ 2. MCP callable (GetAreas returned 1 area)
✓ 3. Shop renamed (DWinery, ID: SHOP1)
✓ 4. Languages (English, LANG1)
✓ 5. Currencies (EUR)
✓ 6. Countries (DK)
✓ 7. PIM structure (2 folders, 3 models)
✓ 8. Groups (3 groups: Red Wine, White Wine, Rosé)
✓ 9. Products (6 created)
✓ 10. Products in groups (2 per group)
⚠ 11. Images (convention-based, verify in admin)
✓ 12. Index built (6 products found in search)
✓ 13. Area renamed (DWinery)
✓ 14. Area linked (SHOP1)
✓ 15. Homepage (MetaTitle: "DWinery — Danish Wines")
✓ 16. Nav tags (6/6 critical)
✓ 17. Category pages (3 active)
✓ 18. Payment (Invoice)
✓ 19. Shipping (Standard)
✓ 20. Order flow (DWinery Orders, 4 states)
- 21. Frontend render (SKIP — tool not available)
- 22. Product visibility (SKIP — tool not available)

Score: 20/22 (16/16 critical) — 1 degraded, 2 skipped
```
