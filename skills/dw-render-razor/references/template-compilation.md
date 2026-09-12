# Template compilation, resolution and render order

How a Dynamicweb 10 Razor template compiles, which template a request actually resolves to, and
what the render is still allowed to decide by the time it runs. Every surface named here is the
**template surface** — `.cshtml` files on disk under `Files/Templates/Designs/<design>/` — except
where a row names an MCP tool, an Admin API verb or SQL explicitly.

## Contents

- [1. The compile contract — every message is fatal](#1-the-compile-contract--every-message-is-fatal)
- [2. Which members exist on which template base](#2-which-members-exist-on-which-template-base)
- [3. `@Include` shares the includer's compiled scope](#3-include-shares-the-includers-compiled-scope)
- [4. Sharing one file between a ViewModel template and a classic template](#4-sharing-one-file-between-a-viewmodel-template-and-a-classic-template)
- [5. Which template a request resolves to](#5-which-template-a-request-resolves-to)
- [6. What the render can decide — and what it cannot](#6-what-the-render-can-decide--and-what-it-cannot)

## 1. The compile contract — every message is fatal

Templates compile **warnings-as-errors** at render time, and there is no earlier build step in
which a bad call site surfaces. So an `[Obsolete]` call — whose message is phrased as advice —
takes the whole surface down: `dw-error` block, zero template output.

Read the symptom table before reading your own file. The error page renders the *generated*
source below the message, which is why the first instinct is to suspect a stale compile, a caching
problem, or a file served as text.

| What the page shows | What it means | What to do |
|---|---|---|
| `dw-error` carrying `'X' is obsolete: 'Use Y instead.'` | Warnings are errors; the deprecated call is a render failure, not a hint | Call `Y`. Treat every compile message from a template as fatal regardless of the word "obsolete" |
| `The name 'X' does not exist in the current context` for a method you can see in the docs | Either an **extension method** whose namespace has no `@using`, or a member of the *other* template base (§2) | Add `@using` for the namespace of every extension method used, not only for the types named; or use the base-appropriate substitute |
| The template's own C# printed as HTML-escaped text | A compile error — the error page dumps the generated listing | Read the one-line compiler message **above** the listing, not the listing |
| `The using directive for 'X' appeared previously in this namespace`, once per included file | The compile unit is shared across `@Include`s (§3) | Expect a scope collision immediately below it |
| `A local variable or function named 'X' is already defined in this scope`, naming a file you did not edit | Same cause (§3) | Rename the local in the file you *did* edit, with a per-file prefix |

The replacements met most often in Swift templates on DW 10.28.x:

| Obsolete call | Working substitute |
|---|---|
| `Dynamicweb.Security.UserManagement.User.GetCurrentExtranetUser()` | `Dynamicweb.Security.UserManagement.UserContext.Current.User` |
| `Group` | `UserGroup` |
| `User.GetUsersByGroupID(int)` | `UserManagementServices.Users.GetUsersByGroupId(int)` |
| `UserAddress.GetUserAddresses(int)` | `UserManagementServices.UserAddresses.GetAddressesByUserId(int)` |
| `IRequest.Cookies` | `Request.GetCookie(name)`, whose result carries `.Value` |

Extension methods are the quieter half of the same rule: `product.GetDefaultGroupByShopId(shopId)`
needs `@using Dynamicweb.Ecommerce.Products` even though `Product` itself resolves without it, so a
missing `@using` reads as "the method does not exist".

## 2. Which members exist on which template base

A template's generated class derives from whatever its `@inherits` line names, and the two families
carry different helper sets. The tag-template helpers are what every older sample uses, so a
ViewModel template that copies one fails to compile.

| Family | `@inherits` | Carries |
|---|---|---|
| ViewModel template | `Dynamicweb.Rendering.ViewModelTemplate<T>` | `Model`, `RenderPartial<T>`, `Translate`, `AddStylesheet` / `AddScript`, `Pageview` |
| Classic tag template | `Dynamicweb.Rendering.RazorTemplateBase<RazorTemplateModel<Template>>` | `GetString` / `GetBoolean` / `GetLoop` (see [dw-render-templatetags](../../dw-render-templatetags/SKILL.md)), `GetGlobalValue` |

Members that do **not** carry over to `ViewModelTemplate<T>`, with the substitute that does work
there:

| Missing member | Substitute on `ViewModelTemplate<T>` |
|---|---|
| `GetGlobalValue("Key")` (a `TemplateBase` member) | `Dynamicweb.Configuration.SystemConfiguration.Instance.GetValue(path)`, where `path` is a `/Globalsettings/System/<Key>` or `/Globalsettings/Ecom/<Key>` shape. A key absent from `GlobalSettings.config` returns an empty string, so confirm the key exists before building a banner on it |
| `@Html.Raw(value)` (the MVC `Html` helper) | Plain `@value`. Razor's encoding is a no-op for content with no HTML-special characters, and `ShortDescription` / `LongDescription` are already HTML strings that DW emits un-escaped. Pre-escape in C# when a value can legitimately carry `<`, `>`, `&`, `"` or `'` |

`@Html.Raw`'s error surfaces under the **wrong file** — reported against the page layout as a flood
of duplicate-using / nullable warnings, with the real `'Html' does not exist` line at the bottom.

One more member that is not where it looks: `product.ProductFieldValues` lives on the underlying
`Dynamicweb.Ecommerce.Products.Product` entity, not on `ProductViewModel`. Reading it off a view
model renders raw Razor source as page text on the PDP. Resolve the entity first:

```cshtml
@{
    var entity = Dynamicweb.Ecommerce.Services.Products.GetProductById(
        product.Id, product.VariantId ?? "", true);
    var fields = entity?.ProductFieldValues;
}
```

The third argument (`true`) materialises `ProductFieldValues`; without it the property is `null`
even on a valid entity. (Which fields surface where: see
[dw-render-viewmodels](../../dw-render-viewmodels/SKILL.md).)

## 3. `@Include` shares the includer's compiled scope

**The generated unit is one class per page-level template.** Every `@Include` is inlined into that
class's single `ExecuteAsync` body, with all the included files' `@using` directives hoisted to the
top of the same generated file. **The file boundary is not a scope boundary.**

Consequences, all of which read as something else:

- **Two partials the same page pulls in may not declare a local of the same name** — including
  partials written years apart, and including an includer and its includee. The compiler reports
  the collision against the *page-level* file at a line number in the *generated* source, so the
  error names a file nobody edited and omits the file that was.
- **Duplicate-`@using` warnings are the tell**, one per included file: they prove the compilation
  unit is shared before the real error is reached.
- **The same collision can appear on one page and not another**, because a partial included from
  several page templates collides only where both declarations land in the same unit. That
  data-dependent shape is what makes it look like a stale compile or a cache problem.

**The rule: name locals defensively — a per-file prefix on every local and every `@functions`
member.** A natural name is a hazard: a Swift 2 cart step composes a dozen partials, and a guard
variable added to one of them is exactly the change that collides with a guard added to another
partial earlier. Rename the local in the file you edited (`hidePrices` → `hidePricesOnToggle`),
not in the file the error names.

## 4. Sharing one file between a ViewModel template and a classic template

`RenderPartial<T>` is constrained to `T : Dynamicweb.Rendering.ViewModelBase` **and** needs a real
instance, so it cannot reach a classic step template (an eCom7 `CartV2` step, for instance) which
has no view model at all. The attempts fail with four different and misleading messages in
sequence: type arguments cannot be inferred → `cannot convert from 'method group' to 'object'`
(Razor parsing `RenderPartial < object > (` as two comparisons) → no implicit conversion from
`object` to `ViewModelBase` → at runtime, `Unable to render view model template because no view
model has been set`.

**`@Include` works from both families.** Write the shared file to three rules that follow directly
from §3:

1. **No `@using` directives anywhere in the shared file** — a duplicate using is a hard compile
   error in the caller. Fully qualify every type. The file's own `@inherits` line is tolerated and
   ignored.
2. **Parameters travel in `Dynamicweb.Context.Current.Items`**, staged by the caller immediately
   before the include, because `@Include` takes no arguments:

   ```cshtml
   @{ Dynamicweb.Context.Current.Items["ShipTo_Mode"] = "checkout"; }
   @Include("../../Components/<Project>/ShipTo.cshtml")
   ```

3. **Prefix every `@functions` member and every local**, because they all land in the caller's
   scope and the shipped CartV2 helpers already own names like `userAddressLoop`, `isChecked` and
   `disabledHidden`.

The path is relative to the including file, and `../` works. One shared file rendering from a
paragraph template, a header partial and a CartV2 step is the point of the exercise: duplicating
the resolution logic per surface is what the compile errors push you towards, and it guarantees the
surfaces disagree later.

## 5. Which template a request resolves to

**A relative `ParagraphTemplate` resolves against `/Files/Templates/`, not against the
`Designs/<design>/` folder of the layout rendering it.** Whether the short form works therefore
depends on which page the paragraph sits on, which is how one solution ends up carrying both forms
with both appearing to work.

**Write the fully-qualified form every time:**

```
Designs/<design>/Paragraph/<ItemType>/<ItemType>.cshtml
```

The failure mode is the expensive part. A miss returns **HTTP 200 with zero `dw-error` nodes**, and
the page gets *bigger*, not smaller: the layout prints the literal sentence
`Template file not found (in RenderRazorTemplate()): <absolute path>` inside the grid column where
the paragraph should be. It reaches `Files/System/Log/Templates` as a WARNING and
`Files/System/Log/EventViewer` as one file, and nothing else. Every check a storefront gate
normally runs — status code, `dw-error` count, byte size — reports success or, at worst, "my
markers are missing", which sends you to the paragraph's logic, its item type, its grid row and its
permissions in turn.

**So assert on a marker the template itself emits, and grep the served markup for
`Template file not found`** whenever a paragraph's markers are absent at HTTP 200.

## 6. What the render can decide — and what it cannot

### `Context.Current.Items["ProductDetails"]` is the last product *rendered*, not the page's product

The item is written **per rendered product**, not per page type. After a list of twelve cards it
holds card twelve, so it is populated on a product **list** page exactly as it is on a PDP.

`product != null` is therefore not a test for "this is a product detail page". A template that uses
it as one takes the detail branch on a list page and applies whatever it does with "the current
product" to a product the visitor is not looking at — silently, and only when the affected item
happens to be the last card, which makes it data-dependent and invisible in review.

**Branch on the page's own item type, or on an explicit view parameter the calling template
passes** (`Mode=list` staged in `Context.Current.Items` per §4), and read the context item only on
the arm where it means what its name says.

### A template guard is a UI affordance, not an authorisation rule

**A Dynamicweb app handles its POST before its template renders.** By the time Razor runs, the
write has happened, so a template that renders a refusal instead of a form can only decide what is
*drawn*. A scripted POST to the same endpoint in the same session goes straight through — and the
response then carries the refusal block and the app's own success message on the same page.

That still earns its place: it removes the action from every real browser session and it names who
is acting for whom. **Ship it as the interim half and pair it with a notification subscriber on the
save** ([dw-extend-providers](../../dw-extend-providers/SKILL.md)), which is where the rule that
holds against a script lives.

**The test that tells the two apart:** a scripted POST to the same endpoint inside the same
session, with a **before/after read of the protected value** (the password hash, the saved-card
row) — never a re-read of the page. A re-read of the page shows the refusal and proves nothing.

**Detecting who is acting** is the part that is easy to get wrong under impersonation: `Pageview.User`
is the *effective* user and is already the impersonated customer, so it cannot see the condition at
all. The real signed-in identity is
`Dynamicweb.Security.UserManagement.UserContext.Current.ImpersonatingUser`.

## Cross-references

- [`paragraph-endpoints.md`](paragraph-endpoints.md) — serving a non-page payload from a paragraph:
  the response contract, addressing, and what reaches the wire.
- [`razor-surfaces-and-pitfalls.md`](razor-surfaces-and-pitfalls.md) — canonical `Services.*`
  surfaces, head-include wiring, color schemes, and the CSS pitfalls that bite re-skins.
- [dw-render-viewmodels](../../dw-render-viewmodels/SKILL.md) — which fields surface on a view model
  versus the underlying entity, and which of them are nullable.
- [dw-users-permissions](../../dw-users-permissions/SKILL.md) (`permission-layers.md`) — the
  Permission entity store, the canonical gate for page and paragraph visibility.
