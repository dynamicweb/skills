# Swift 2 Page Structure Reference

## What the BACPAC Contains

The `swift2.bacpac` database backup contains a **complete, working Dynamicweb website**.
After import you will have pages, navigation, shop, checkout, account flows — everything.

The key job is **discovery then customisation**, not creation.

---

## Expected Page Hierarchy (After BACPAC Import)

The Swift 2 solution installs with a standard page tree. The exact page names may vary
slightly but the structure and navigation tags are standard.

```
Area (Website)
│
├── Home / Frontpage              tag: homepage
├── Webshop / Shop / Products     tag: shop
│   ├── [Demo category 1]         (replace with business categories)
│   ├── [Demo category 2]
│   └── [Demo category N]
├── My Account                    tag: myaccount
│   ├── Sign In / Login           tag: login        (hidden from menu)
│   ├── Create User / Register    tag: register     (hidden from menu)
│   ├── Edit Profile              tag: editprofile  (hidden from menu)
│   ├── Manage Addresses          tag: manageaddresses (hidden)
│   ├── Order History             tag: orderhistory (hidden)
│   └── Change Password           tag: changepassword (hidden)
├── Cart / Basket                 tag: cart         (hidden from main menu)
├── Checkout                      tag: checkout     (hidden from main menu)
│   └── Order Confirmation        tag: orderconfirmation (hidden)
├── About Us / About              (optional — may not be in all BACPAC versions)
└── Contact                       (optional)
```

---

## Navigation Tag Reference

These tags are **hardcoded into Swift 2 Razor templates**. Missing tags break the checkout flow.

| NavigationTag | What it controls | Priority |
|--------------|-----------------|----------|
| `cart` | Mini-cart links, "View Cart" button | **Critical** |
| `checkout` | "Proceed to Checkout" button | **Critical** |
| `orderconfirmation` | Order receipt redirect after payment | **Critical** |
| `login` | "Sign In" links, redirect after auth | **Critical** |
| `register` | "Create Account" links | **Critical** |
| `homepage` | Logo links, "Back to home" | High |
| `shop` | "Back to Shop" navigation | High |
| `myaccount` | "My Account" menu item | High |
| `editprofile` | Profile edit links | Medium |
| `manageaddresses` | Address book links | Medium |
| `orderhistory` | Order history links | Medium |
| `changepassword` | Change password links | Low |

---

## Layout Template Path

The Swift 2 BACPAC has the layout template path stored in the database.
You can read it from the area's `LayoutTemplate` property after calling `get_areas`.

If `LayoutTemplate` is empty or needs updating:
```
Designs/Swift-v2/MasterPages/Master.cshtml
```
This is the standard Swift 2 master layout path relative to the `Templates/` folder.

---

## Category Pages — What to Expect

The Swift 2 BACPAC includes **demo category pages** under the Shop page.
These are generic placeholders (e.g. "Furniture", "Electronics", "Fashion").

Your job:
1. Identify the demo pages that DON'T match the business's product types → `patch_page` with `Active: false`
2. Identify any existing pages that DO match → `patch_page` to rename and re-brand
3. Create NEW pages only for product types that have no matching existing page

### URL Name Convention for Category Pages
```
Running Shoes  →  running-shoes
Gym Equipment  →  gym-equipment
Men's Apparel  →  mens-apparel
```
Always: lowercase, hyphens instead of spaces/apostrophes, no special characters.

---

## Swift 2 Item Types (Per-Page Settings)

Swift 2 pages use "item types" to store per-page configuration visible in the admin UI
(header variant, theme color, background, spacing, etc.).

The BACPAC already has item type instances configured. You generally don't need to set
`ItemType` when creating new category pages — they will inherit the shop page settings.

If a newly created page needs explicit item type configuration, use:
- `ItemType: "Swift_Page"` — standard content page with configurable header/footer

---

## After Customisation — What Still Needs Manual Configuration

These require the Dynamicweb backend admin UI (not available via MCP tools):

| Task | Location in Admin |
|------|------------------|
| Payment provider setup | eCommerce → Orders → Payment methods |
| Shipping provider setup | eCommerce → Orders → Shipping providers |
| Brand colours and typography | Content → Design → Color Schemes |
| Email templates (order confirmation) | eCommerce → Communication → Email |
| Product images upload | Products → [product] → Images |
| Page content / hero images | Content → [page] → Edit |
| Grid layout and paragraph content | Content → [page] → Edit → Grid |
| SEO sitemap settings | Settings → SEO |

These are intentionally out of scope for MCP — they require visual editing or file uploads.
The MCP agent sets up all the structural and data configuration so the site is immediately functional;
the above are polish items the business owner does once.
