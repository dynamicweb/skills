# Foundational candidate → dw-render-viewmodels

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 frontend viewmodel knowledge — the model/viewmodel
> accessors templates read at render time — staged here for a future fold-up into
> `dw-render-viewmodels`. No demo/customer content. When folded, move this body into
> `dw-render-viewmodels` and re-target the pointers in the demo skills. Until then, the demo skills
> reference this file.

## User identity / groups

- **Read user**: `Pageview.User` (the model; not a viewmodel). Public properties include `ID`,
  `Name`, `FirstName`, `LastName`, `UserName`, `Email`, `CustomerNumber`, `PointBalance`.
- **Read user groups**: `Pageview.User.GetGroups()` returns `IEnumerable<UserGroup>`. Non-obsolete on
  10.25+ — see `src/Core/Dynamicweb.Core/Security/UserManagement/User.cs:717`. `User.HasGroup(int)`
  (User.cs:1329) is `[Obsolete]` but compiles.
- **From the viewmodel side**: `UserViewModelExtensions.GetDirectUserGroups()`
  (`Frontend/UserViewModelExtensions.cs:54`).
- **Read user groups via `Pageview.User.GetGroups()`, never a raw `SELECT FROM
  AccessUserGroupRelation` in Razor.** The raw query fails the discipline grep-pack and bypasses the
  group-resolution caching.

This accessor is what any template-level role check should use — e.g. resolving a presentation role
(badge, avatar ring) or deciding whether to render an editor-only affordance. Gating *visibility of a
page or paragraph* is a different concern owned by the Permission entity store
([`users-permissions.md`](users-permissions.md)); use `GetGroups()` only for presentation logic, not
as a security gate.

## The `ProductViewModel` field inventory

When escalating to a NEW content layout of a product paragraph (e.g. a richer PDP header) and the
missing context is **per-product data already on the `ProductViewModel`** (manufacturer, SKU, stock
pill, short description), read it directly off the view model rather than resolving the underlying
entity. The flattening is the trap — several relations surface under different names than the entity
uses.

**Fields that ARE available** (verified on `Dynamicweb.Ecommerce.ProductCatalog.ProductViewModel`):

- `Name`, `Number` (SKU), `ShortDescription`, `LongDescription`
- `ManufacturerName` — **NOT** `Manufacturer.Name`. The manufacturer relation flattens to a single
  string on the view model; there is no `Manufacturer` navigation property.
- `Stock` (decimal), `StockLevel` (string), `NeverOutOfStock` (bool)
- `DefaultImage` (image VM), `Images` (collection)
- `Price` (price VM with `.Formatted`)

**Fields that look like they should exist but DON'T:**

- `product.DefaultUnit` / `product.DefaultUnitName` — neither resolves on `ProductViewModel`. Unit
  data lives on `product.PriceUnitDescription` if at all; for "per box / each" suffixes prefer a
  static string in the layout or a custom field via `product.GetField("...")`.
- `Manufacturer` as a navigation property — use `ManufacturerName` directly.
- `product.ProductFieldValues` — this lives on the underlying
  `Dynamicweb.Ecommerce.Products.Product` **entity**, not on the view model. Reading it off
  `Model.Product` (a view model) compiles but renders raw Razor source as page text on the PDP. To
  read the field collection, resolve the entity:
  `Dynamicweb.Ecommerce.Services.Products.GetProductById(product.Id, product.VariantId ?? "", true)`
  (the `true` materialises `ProductFieldValues`). See [`render-razor.md`](render-razor.md) for the
  Razor-side pitfall and the canonical accessor.

**Inline-styles vs CSS file (one-paragraph enrichment):** for a single content-layout enrichment,
prefer inline `style="..."` that consumes the project's CSS variables (e.g.
`style="color: var(--brand)"`) over adding more rules to a project CSS file. The layout file becomes
self-contained and the upgrade diff stays one file.

## Cross-references

- [`render-razor.md`](render-razor.md) — the Razor-execution side: `ViewModelTemplate<>` pitfalls
  (`@Html.Raw` absent, `ProductFieldValues` resolution), the canonical `Services.*` accessors, and
  URL/redirect/stylesheet surfaces.
- [`users-permissions.md`](users-permissions.md) — the Permission entity store; use that, not
  `GetGroups()`, to gate page/paragraph visibility.
