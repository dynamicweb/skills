# CPQ pages, item types and the runtime

How a configurator reaches the frontend, and what happens on every keystroke.

## Contents

- [Assembling a page](#assembling-a-page)
- [The item types](#the-item-types)
- [How a model finds its page](#how-a-model-finds-its-page)
- [Themes](#themes)
- [The popup pattern](#the-popup-pattern)
- [The request cycle](#the-request-cycle)
- [The HTTP surface](#the-http-surface)
- [Selections and client storage](#selections-and-client-storage)
- [Customising without forking the frontend](#customising-without-forking-the-frontend)

## Assembling a page

1. Create a page of type **`CPQ_Page`** and set its two fields: the **model version** and the
   **theme**. Both matter — see [Themes](#themes) and the versioning warning below.
2. Give it a CPQ layout — the standard one, or the **clean** one for a popup or an iframe.
3. Add **`CPQ_Row`** grid rows. These are CPQ's own row definitions, not the storefront's.
4. **Add a `CPQ_Tabs` paragraph.** Do this with the first row, not at the end.
5. Add the content paragraphs: `CPQ_Inputs` per input group, `CPQ_Items` for the BOM, plus whichever
   of the summary, actions, menu and table paragraphs the design calls for.

> **A page with no `CPQ_Tabs` paragraph renders blank.** Every `CPQ_Row` starts at `display:none`
> and the tab script is what reveals it. The page will look correctly built and show nothing.

Two more things `CPQ_Row` does that the storefront row does not: it sanitises its tab name down to
letters, digits and underscores, and it uses tighter default spacing. And the CPQ row definitions
**omit the mobile layout and mobile sort controls** the standard rows carry, so responsive work on a
CPQ page is CSS rather than row configuration.

## The item types

Eighteen item types install. One is a page type, one is a grid row, the rest are paragraphs.

| Item type | Kind | Purpose |
|---|---|---|
| `CPQ_Page` | page | binds the page to a model version and a theme |
| `CPQ_Row` | grid row | a row scoped to one tab |
| `CPQ_Inputs` | paragraph | renders one input group; section title, subgroups, collapsed state, column count |
| `CPQ_Step_Inputs` | paragraph | stepped/wizard presentation of inputs |
| `CPQ_Table` | paragraph | an input group as a table; optional auto-save on change |
| `CPQ_QuickConfigure` | paragraph | the compact inline editor |
| `CPQ_Items` | paragraph | the BOM, with pricing, cost-up, totals, actions, simple-BOM and document toggles |
| `CPQ_BOM_Table` | paragraph | BOM as a table |
| `CPQ_Routes`, `CPQ_Route_Table` | paragraph | routing lines |
| `CPQ_Summary` | paragraph | chosen input groups plus BOM and route totals, with optional category subtotals |
| `CPQ_Card` | paragraph | the card view — the page a configuration is opened *from* |
| `CPQ_Actions` | paragraph | reset, visual and generate-document buttons, with configurable labels |
| `CPQ_ListProducts` | paragraph | product-selector output; filters a product list by the configuration |
| `CPQ_Visual` | paragraph | 3D visualisation |
| `CPQ_Tabs` | paragraph | the tab bar — **required for any row to be visible** |
| `CPQ_Side_Menu`, `CPQ_Sticky_Menu` | paragraph | navigation chrome |

`CPQ_Tabs` pairs its tab names with a user-group access list positionally, so a tab can be limited to
a group — useful for a dealer-only or internal-only section of a configuration.

`CPQ_Summary` takes its input groups as a **comma-separated list where order matters**, so the
summary can present the configuration in a different order from the form.


**`CPQ_Items` is either/or, and the wrong branch is the default-looking one.** With *Show Totals*
ticked, the template renders **only** the cost / margin / total-sell summary table: no BOM lines, no
Add-to-Quote or Create-Project buttons, no document action, because the whole of the rest of the
template sits in the `else` branch. That summary is a dealer's internal view, so a page built with
Show Totals on shows a customer a margin sheet and no way to proceed. For a customer-facing page
ticking *Pricing* and *Simple BOM* with Show Totals **off** is what gives priced lines plus the
actions. The paragraph's values are item values and therefore cached — changing them needs a
restart before the frontend reflects it.

Note two shipped defects. The `CPQ_Card` paragraph declares a card-template field that its template
never reads, so whatever is authored there has no effect and the paragraph always falls back to the
model's own cards. And the inline quick-configure loader re-executes script nodes from fetched HTML,
which is a script-injection surface if model data ever reaches rendered output unescaped — worth
knowing before customer-authored strings flow into a configuration.

## How a model finds its page

**There is no naming convention that binds a page to a model**, despite what the vendor tutorial
implies. The mechanism is a **navigation tag stored in the model version** —
`QuickConfigurePageNavigationTag`, with `DefaultPageNavigationTag` as the general case, resolved at
render time against the current area.

So: set a navigation tag on the page, then register that same tag in the model version's settings.
The name itself is free.

Cards and card items also store a page navigation tag of their own, and there is a global setting for
the card page, giving a resolution ladder from card, to model default, to global fallback. When a
configuration opens on an unexpected page, that ladder is where to look.

The product-selector paragraph resolves the standard cart service tag to post its add-to-cart, so a
solution using that paragraph needs the usual cart service page in place.

## Themes

The page's theme field is interpolated **verbatim as a stylesheet filename stem**. Two consequences:

- **Always set the theme explicitly.** The fallback value does not match any shipped file, so an
  unset theme silently loads **no theme stylesheet at all** and the configurator renders unstyled.
- The value stored is a CSS filename stem, and the two shipped themes are whole-file swaps rather
  than scoping classes — they define the same selectors with different values. A custom theme is a
  new stylesheet, not an override class.

There is no themes management screen; the theme rows are seeded once at install and are editable
only in the database.

## The popup pattern

The configurator is designed to open **in a popup from the card page**. On submit it posts a refresh
message to its opener and closes itself. The clean layout exists for exactly this: no chrome, plus a
single-paragraph mode and a content-only switch for embedding.

Build the flow that way — card page, opening a configurator, closing back to a refreshed card. Built
as a full-page wizard instead, the close-and-refresh behaviour has nothing to talk to and the
customer is left on a dead page after submitting.

## The request cycle

There is no client-side rule engine. On **every input change** the client:

1. Aborts any in-flight request and increments a request counter, so late responses are dropped.
2. Serialises the whole form as `[{name, type, value, valuetext, visible}]`.
3. POSTs it to the model endpoint.
4. Reads the response and fans it out to around fourteen DOM updaters — image, BOM, summary, routes,
   3D model, inputs, output actions and so on.

The focused input is snapshotted and skipped on re-render so typing is not clobbered, and there is no
page reload in the normal loop.

Two implications for rule authors. **`visible` is transmitted per input**, so a rule can condition on
whether a control is currently shown. And **a hidden input still sends its value** — hiding a control
does not clear it, so if hiding should also reset, set the value explicitly in the same rule.

## The HTTP surface

The add-in registers one controller under **`/cpqapi`**. Nothing is added under the admin or delivery
API paths.

| Endpoint | Purpose |
|---|---|
| `model` | the main recalculation call, on every change |
| `model/lookup` | Lookup List options, with search key and paging |
| `model/CreateSalesQuote` | the submit path |
| `model/ToCart`, `CartToOrder`, `ToOrder`, `ToQuote` | cart, order and quote creation |
| `model/SaveCardItem`, `CardTemplateItem`, `CreateNewRevision` | card operations |
| `model/RefreshCardCustomerInfo` | pulls customer header data — **reaches the ERP** |
| `model/DownloadDocx`, `PrintCardProposalDocx`, `DownloadCardOutput`, `UploadGeneratedDocument` | documents |
| `model/AttachDocumentToBC` | stores a document in the ERP |
| `model/CompareRevisionExcel` | revision comparison |

Card mutations from the card page go through post-redirect-get on a card action parameter rather than
this API — adding a card to a quote, deleting or duplicating a card item, saving card details,
creating a quote.

> The quote paths are worth distinguishing before wiring a submit button: the cart/order/quote
> endpoints create Dynamicweb records, while the sales-quote path is the one associated with ERP
> sales documents. Confirm which one a given build should call.

## Selections and client storage

In-progress selections ride in a **cookie**, URI-encoded JSON with a one-day expiry, cleared
explicitly when a configuration is reset. It is also read **server-side** — the product-selector
paragraph reads the cookie to filter its product list.

The client additionally keeps step state in local storage — current step, per-step selections and
dimensions.

Two consequences worth planning for. A configuration **persists across page loads and between
sessions within the day**, which surprises people demonstrating repeatedly: reset explicitly between
runs. And because the cookie is read server-side, a stale cookie can influence a rendered product
list, so clearing it is part of reproducing a reported problem.

Durable persistence is not the cookie — it is the card item's stored inputs and the configuration
rows.

## Customising without forking the frontend

CPQ's file update provider rewrites every `CPQ_*.cshtml` and `Assets/js/cpq*.js` in the design
folder **at each application start**, so a change made in a vendor template survives until the next
restart and no further. It cannot be relied on, and the loss is silent.

Two seams exist instead, and between them they carry a complete visual and behavioural
customisation:

- **`Assets/js/cpq-custom.js`.** The master template loads this file *if it exists*, deferred, after
  every vendor script. Nothing else references it — it is offered purely as a customisation hook.
- **The theme stylesheet.** A custom theme is a Northwind-owned file the update provider does not
  touch, selected by the page's theme field (see [Themes](#themes)).

Prefer wrapping the vendor's own functions over watching the DOM. `updateBOM()` and
`updateModelForm()` are declared as top-level functions in a classic script, so both are properties
of `window` and can be replaced with a wrapper that calls the original:

```js
var orig = window.updateBOM;
window.updateBOM = function () { try { return orig.apply(this, arguments); } finally { redraw(); } };
```

`updateBOM` fires exactly once per priced configuration, and by the time it runs the parsed BOM is
already on `window._cpqLatestBomItems` (routes likewise on `window._cpqLatestRouteItems`). Each line
carries `bomgroup`, `item_no`, `description`, `uom`, `qty`, `unit_cost`, `unit_sell`, `line_sell`
and `discounted_line_sell`. That array is the right source for anything that has to restate the
build — a persistent price bar, a summary drawer, a customer-facing offer — because it cannot drift
from what the engine priced.

Two DOM facts worth knowing before writing such a layer:

- A tab's step is reached by **clicking its own `.nav-link`**. The template's `showTab()` lives
  inside a `DOMContentLoaded` closure and is not reachable; clicking is also what keeps the vendor's
  per-tab scroll memory correct.
- A rule that clears an input's `visible` flag results in `display: none` on the
  `#<Tab>_visible_<InputName>` wrapper — the node stays in the document. That is the hook for
  replacing a silently-vanishing question with a stated reason.
- `.input-control` holds the `.invalid-feedback` message as a plain `div` alongside the options, so
  an option must be identified by the radio or checkbox it wraps, never by position.
