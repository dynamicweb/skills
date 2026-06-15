# Business Setup Guide — Payload Shapes & Conventions

## Core Principle: Patch, Don't Create

The Swift 2 BACPAC already contains:
- 1 website area (already configured with Swift 2 design)
- 1 eCommerce shop (with default language and currency)
- All pages (Home, Shop, Cart, Checkout, Account, etc.)
- Navigation tags on all key pages

**Always discover first, then patch. Only create what genuinely doesn't exist.**

---

## Phase 2: Discover Current State

### get_areas
Returns the existing Swift 2 website. Note:
- `Id` → use as `areaId` throughout
- `EcomShopId` → note the existing shop ID
- `EcomLanguageId` → note the existing language ID
- `EcomCurrencyId` → note the existing currency

### get_shops
Returns all shops. The Swift 2 BACPAC has one shop.
- `Id` → use as `shopId` when creating groups and products

### get_languages
The Swift 2 BACPAC has at least one language (usually English, ID: "LANG1" or "ENG").
- Note the existing ID — use it if it matches the business's language
- Only create a new language if the business needs a different one

### get_currencies
The Swift 2 BACPAC has at least one currency (often DKK or USD).
- Use existing if it matches the business
- Only create a new currency if needed

---

## Phase 3: Foundation — Only What's Missing

### save_language (only if new language needed)
```json
{
  "LanguageId": "",
  "Name": "English",
  "NativeName": "English",
  "Culture": "en-US",
  "IsDefault": true
}
```
Common culture codes: en-US, en-GB, da-DK, sv-SE, nb-NO, de-DE, fr-FR, nl-NL

### save_currency (only if new currency needed)
```json
{
  "CurrencyCode": "USD",
  "Name": "US Dollar",
  "Symbol": "$",
  "IsDefault": true,
  "Rate": 1.0
}
```
Common codes: USD, EUR, GBP, DKK, SEK, NOK, CHF, JPY, AUD, CAD

### save_country (only if new country needed)
```json
{
  "CountryCode2": "US",
  "Name": "United States",
  "CurrencyCode": "USD",
  "CultureInfo": "en-US"
}
```

---

## Phase 4: Update Shop (PATCH, not create)

```json
{
  "Id": "{existingShopId}",
  "Name": "{businessName}",
  "DefaultLanguageId": "{languageId}",
  "DefaultCurrencyId": "{currencyId}",
  "CountryCode": "{countryCode}"
}
```

---

## Phase 6: Product Groups

Create NEW groups for the business's product types:
```json
[
  {
    "Id": "",
    "Name": "Running Shoes",
    "ShopId": "{shopId}",
    "LanguageId": "{languageId}",
    "Description": "Running and trail shoes for all levels"
  },
  {
    "Id": "",
    "Name": "Gym Equipment",
    "ShopId": "{shopId}",
    "LanguageId": "{languageId}",
    "Description": "Home and professional gym equipment"
  }
]
```

---

## Phase 8: Sample Products

```json
[
  {
    "name": "Running Shoe Pro X1",
    "number": "RSH-001",
    "shortDescription": "Lightweight high-performance running shoe",
    "longDescription": "Full description here...",
    "defaultPrice": 129.99,
    "isActive": true,
    "languageId": "{languageId}"
  }
]
```

---

## Phase 9: Commerce Config

### save_units
```json
[
  { "Id": "", "Name": "pcs", "Description": "Pieces" },
  { "Id": "", "Name": "kg", "Description": "Kilograms" }
]
```
Industry guide: apparel → pcs; food → kg/l/g; furniture → pcs; electronics → pcs

### save_manufacturers (retailers only)
```json
[
  { "Id": "", "Name": "Nike" },
  { "Id": "", "Name": "Adidas" }
]
```

### save_prices
```json
[
  {
    "ProductId": "{productId}",
    "CurrencyCode": "{currencyCode}",
    "Quantity": 1,
    "Amount": 129.99
  }
]
```

---

## Industry Presets

### Apparel / Fashion
Groups: Men's, Women's, Kids', Accessories, Sale
Key custom fields: size (List), colour (List), material (Text), fit_type (List), season (List)
Units: pcs

### Electronics / Tech
Groups: Smartphones, Laptops, Audio, Smart Home, Accessories
Key custom fields: connectivity (Text), warranty_months (Number), power_watts (Number)
Units: pcs

### Furniture / Home
Groups: Living Room, Bedroom, Dining, Office, Outdoor
Key custom fields: width_cm (Number), depth_cm (Number), height_cm (Number), material (List)
Units: pcs

### Food & Beverage
Groups: Fresh, Frozen, Pantry, Beverages, Snacks
Key custom fields: ingredients (LongText), allergens (List), storage_instructions (Text), weight_g (Number)
Units: kg, g, l, ml, pcs

### Sports & Outdoors
Groups: Running, Cycling, Gym, Water Sports, Team Sports
Key custom fields: sport_type (List), activity_level (List), gender (List), size (List)
Units: pcs

### B2B / Industrial
Groups: by product line or department
Key custom fields: technical_specs (LongText), certifications (Text), moq (Number), lead_time_days (Number)
Units: pcs, m, m2, kg, set

---

## Completeness Rules (Defaults)

### Minimum Viable
Required: ProductName, ProductNumber, ProductShortDescription, ProductDefaultPrice

### Ready to Publish
Required: ProductName, ProductNumber, ProductShortDescription, ProductLongDescription, ProductDefaultPrice, ProductImageFileName

### Fully Enriched
Required: all of the above + key category-specific fields (colour, size, material, etc.)

---

## Setup Execution Checklist

Before reporting completion:
- [ ] Swift 2 is confirmed installed (get_areas returns area with Swift-v2 template)
- [ ] Existing area ID stored
- [ ] Existing shop ID stored and shop renamed
- [ ] Language ID confirmed (existing or new)
- [ ] Currency ID confirmed (existing or new)
- [ ] Area patched with business name, domain, shop link
- [ ] All key pages have correct navigation tags
- [ ] Product groups created for each product type
- [ ] Sample products created and assigned to groups
- [ ] PIM structure created (data models, fields, completeness rules)
- [ ] At least one product query created
- [ ] Dashboard created
