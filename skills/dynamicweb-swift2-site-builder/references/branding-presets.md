# Swift 2 Branding Presets

Industry-specific branding guidance for Swift 2 site customisation.
Use these presets to create visually coherent storefronts that match the business type.

---

## Winery / Food & Beverage

### Visual Identity
- **Palette**: Deep burgundy (#722F37), cream (#FFF8E7), charcoal (#2C2C2C), gold accent (#C5A55A)
- **Typography feel**: Serif for headings (elegant, timeless), sans-serif for body
- **Imagery**: Vineyards, bottles on dark backgrounds, close-ups of labels, rustic wood textures
- **Mood**: Warm, sophisticated, artisanal

### Homepage Content Suggestions
- Hero: Full-width vineyard or cellar image with business name overlay
- Tagline: "{businessName} — [region] wines crafted with passion"
- Featured section: "Our Collection" with 3-4 hero wines
- Story section: "Our Heritage" / "The Vineyard" narrative block

### Category Pages
| Category | Suggested Name | SEO Description Pattern |
|----------|---------------|------------------------|
| Red Wine | Red Wines | "Explore our selection of {region} red wines. From bold Cabernet to elegant Pinot Noir." |
| White Wine | White Wines | "Discover our {region} white wines. Fresh, crisp, and beautifully balanced." |
| Rosé | Rosé Wines | "Light, refreshing rosé wines perfect for any occasion." |
| Sparkling | Sparkling | "Celebrate with our sparkling wines and champagne." |
| Accessories | Wine Accessories | "Complete your wine experience with our curated accessories." |

### Product Number Convention
- `RED-001`, `WHT-001`, `RSE-001`, `SPK-001`
- Image naming: `RED-001.jpg`, `RED-001_front.jpg`, `RED-001_label.jpg`

### Shop Image Pattern
```
ImageFolder: /Images/wines
ImagePatternMain: {ProductNumber}.jpg
ImagePatternVariant: {ProductNumber}_{VariantId}.jpg
UseAlternativeImages: true
ImageSearchInSubfolders: true
```

### Stock Images (Pexels keywords)
- "wine bottle dark background"
- "vineyard landscape"
- "wine cellar barrels"
- "wine glass pour"
- "wine label close up"

---

## Fashion / Apparel

### Visual Identity
- **Palette**: Black (#000000), white (#FFFFFF), light grey (#F5F5F5), accent color per brand
- **Typography feel**: Clean sans-serif, bold headings, light body
- **Imagery**: Model shots on white/neutral backgrounds, flat lays, lifestyle
- **Mood**: Modern, clean, aspirational

### Homepage Content Suggestions
- Hero: Seasonal campaign image with collection name
- Featured: "New Arrivals" grid
- Categories: Visual grid with lifestyle imagery per category

### Category Pages
- Tops, Bottoms, Outerwear, Accessories, New Arrivals, Sale

### Shop Image Pattern
```
ImageFolder: /Images/products
ImagePatternMain: {ProductNumber}.jpg
UseAlternativeImages: true
ImageSearchInSubfolders: true
```

---

## Electronics / Tech

### Visual Identity
- **Palette**: Dark blue (#1A1A2E), white, electric blue accent (#0066FF), grey (#E0E0E0)
- **Typography feel**: Technical sans-serif, compact
- **Imagery**: Product on white/gradient, hero shots, detail close-ups
- **Mood**: Technical, precise, premium

### Homepage Content Suggestions
- Hero: Featured product spotlight
- Grid: "Shop by Category" with icon-style imagery
- Spec highlight sections

---

## Furniture / Home

### Visual Identity
- **Palette**: Warm neutrals (#F5F0EB), forest green (#2D5016), warm wood (#8B6914), white
- **Typography feel**: Elegant serif headings, readable body
- **Imagery**: Room settings, lifestyle, texture close-ups
- **Mood**: Comfortable, quality, design-forward

### Homepage Content Suggestions
- Hero: Styled room scene
- Collections: "Living Room", "Bedroom", "Office"
- Inspiration gallery

---

## Adding New Presets

When creating a new preset:
1. Define color palette (primary, secondary, accent, background, text)
2. Suggest typography character (serif/sans-serif/mixed, weight)
3. List 5-8 Pexels search terms for free stock imagery
4. Define 3-5 category page templates with SEO patterns
5. Set product number convention
6. Set shop image folder and pattern
7. Write homepage section suggestions (hero, featured, story, categories)
