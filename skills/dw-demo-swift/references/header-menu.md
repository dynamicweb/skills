# header-menu.md

> Make the Swift 2 header nav **read as a menu**: dropdown carets, hover/active states, and
> reachable dropdowns. Owns the mechanism (why a fresh bar is flat), the `save_groups`
> child-authoring recipe (the data prerequisite), the three interaction platform-truths that each
> cost real debugging time, and the pointer to the shared default that ships the fix.
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs.

## Contents

- [The default is flat — why](#the-default-is-flat--why)
- [Data prerequisite: author nav depth (`save_groups`)](#data-prerequisite-author-nav-depth-save_groups)
- [The merged page+group tree — how a content page joins a group-driven menu](#the-merged-pagegroup-tree--how-a-content-page-joins-a-group-driven-menu)
- [Nav visibility is not access control — a hidden group still serves a live PLP](#nav-visibility-is-not-access-control--a-hidden-group-still-serves-a-live-plp)
- [The shared default: `theme-default`'s `default_custom.css`](#the-shared-default-theme-defaults-default_customcss)
- [Platform truth 1 (LRN-nav-03): the Popper-gap bridge](#platform-truth-1-lrn-nav-03-the-popper-gap-bridge)
- [Platform truth 2 (LRN-nav-04): `::before` = icon, `::after` = underline](#platform-truth-2-lrn-nav-04-before--icon-after--underline)
- [Platform truth 3 (LRN-nav-05): dropdown `min-width`](#platform-truth-3-lrn-nav-05-dropdown-min-width)
- [Header height: count grid rows before hunting padding](#header-height-count-grid-rows-before-hunting-padding)
- [Icons: opt-in, keyed on `data-nav-icon`](#icons-opt-in-keyed-on-data-nav-icon)
- [How to verify (probes)](#how-to-verify-probes)

## The default is flat — why

A fresh Swift storefront's header nav renders as flat text next to text: no carets, no hover
states, no dropdown reach. Every demo re-discovers this. Two stacked stock defaults cause it:

- **Data.** The stock menu template `Swift-v2_MenuRelatedContent/Menu.cshtml` (~line 132,
  `bool nodesExist = rootNode.Nodes.Any() || hasRelatedContent;`) only emits the dropdown
  affordance attributes (`data-bs-toggle="dropdown"`, the megamenu panel) when a top node has
  **children**. Fresh demos start childless → every top item takes the bare `nav-link` branch.
- **Style.** Stock Swift ships **no** affordance styling for the bar — no caret, no hover/active
  treatment. There is nothing to make it look like a menu even once depth exists.

Do **not** fix this by editing `Navigation.cshtml` / `Menu.cshtml` to render an affordance for
childless items: a template fork is an upgrade burden, violates the zero-custom posture, and a
caret on an item with no dropdown is a lie. Fix the data (add depth) + add the style overlay.

## Data prerequisite: author nav depth (`save_groups`)

The dropdown/megamenu only renders when top nav nodes have children. For a group-driven bar,
author child ecom groups under the top groups via the Backend MCP `save_groups` recipe
(`parentGroupId`), then cross-assign products:

```jsonc
// save_groups — create children under a top group (parentGroupId = the top group's id)
{
  "groups": [
    { "name": "Sub A", "parentGroupId": "GROUP1", "showInMenu": true },
    { "name": "Sub B", "parentGroupId": "GROUP1", "showInMenu": true }
  ]
}
// then assign_products_to_group to populate each child so the landing isn't empty
```

Group nodes carry a `GroupId`, not a page `PropertyItem["Icon"]`, so the page-`Icon` mechanism
does **not** apply to a group-driven bar (this is why icons are keyed on a neutral hook, below).
After authoring depth, restart the host (nav is cached at startup). The obligation is recorded
machine-readably in the Distribution `layers/surface-swift/surface.contract-notes.json` →
`navDepth` (content-scoped contract bits moved there in the Swift 2.4 base split): an edition
that promises a menu-bar default must ship or author nav depth; the base stays framework-only.

## The merged page+group tree — how a content page joins a group-driven menu

A group-driven bar is **one paragraph** (`Swift-v2_MenuRelatedContent`) whose `NavigationRoot` points at
a `Swift-v2_Shop` page. `Navigation.GetNavigationViewModel(<navRootPageId>, ExpandMode.All)` **merges**
that page's child PAGES and its ecom GROUPS into a single tree — so the bar is not "groups only", and
there is a supported way to put a content page in it that needs no template fork.

**A content page joins the menu by being an UNTAGGED child of the `NavigationRoot` page.** The
suppression flag is `navigationTag`: a child carrying one (`ProductDetailPage`, `ProductListPage`, …) is
withheld from the rendered nav; a child carrying **none** is published to it. So the recipe for surfacing
an existing top-level page without moving it in the tree is a **shortcut child**:

```
PageSave  parentPageId = <navRootPageId>
          navigationTag = ""                       // empty is what publishes it
          shortCut      = "Default.aspx?ID=<targetPageId>"
```

The anchor then renders with the *target's* friendly URL, resolved through the shortcut. Verify by
fetching `/` and extracting the header anchors in DOM order: the new label must be present with an
`href` resolving to the shortcut target.

**Pages always precede groups — a page sort value can never push a content page past the catalogue.**
Sort orders pages among PAGES; the two node classes are not interleaved by one key, and the page block is
emitted first regardless. A content page given a sort above every group still renders immediately after
the other content pages. Do not promise a brief a specific menu slot for a content page in a group-driven
bar, and do not reach for CSS `order` or a template hack to force one — **if a specific slot is genuinely
required that is a template change, not a sort value.** Assert it the honest way: fetch the rendered
header anchor list and assert the node's index, expecting it ahead of the first group node.

**One `NavigationRoot` feeds every paragraph that names it — an addition is never a single-surface
change.** The same shop page is routinely the root of three different paragraphs: the desktop header
(`Swift-v2_MenuRelatedContent`, `NavigationRoot`), the mobile off-canvas (`Swift-v2_OffCanvasNavigation`,
`MainNavigationRoot` + a separate `SecondaryNavigationRoot`) and a footer column
(`Swift-v2_Navigation`, `NavigationRoot`, `ShowOnlyFirstNavLevel=true`). **Any untagged child of that page
appears in all three.** The usual damage is a footer that now names the same destination twice, one column
away from an existing heading with the same word.

- **Before adding a node, enumerate every paragraph whose `NavigationRoot` / `MainNavigationRoot` points
  at the same page, and state the intended outcome per surface.** There is no per-page exclusion to fall
  back on: `showInLegend` is inert ([admin-ui-authoring.md](admin-ui-authoring.md)) and a `navigationTag`
  suppresses the node from **all** the surfaces, including the one you wanted. De-duplication is therefore
  a CSS or information-architecture decision, not a page-flag one.
- Validation is per surface, not per page: assert the rendered node list of the header anchors, the
  off-canvas anchors and each footer column against the intended outcome for that surface.

**Nav MEMBERSHIP is the startup-cached part.** Adding or removing a node needs a host recycle before the
bar reflects it. Label and URL changes do **not** — see the group-rename rule in
[admin-ui-authoring.md](admin-ui-authoring.md), which is the truth earlier passes mis-attributed to the
recycle they happened to run in the same session.

## Nav visibility is not access control — a hidden group still serves a live PLP

**`navigationShowInMenu=false` (and every other menu flag) hides a group from the rendered nav and does
nothing to its URL.** Reachability and nav membership are independent: the group's URL keeps resolving
**200** for anyone who has it, so a catalogue tidied by hiding nodes still publishes them. One audit found
**14** empty groups hidden from the nav, every one of them serving a live PLP reading "0 products" — the
kind of page that surfaces in a search result or a shared link during a demo.

- **Treat every nav-hidden group as a live surface.** If it must not be reachable, **delete it** (the URL
  then 404s); hiding is presentation, not removal.
- Probe shape: enumerate the shop's groups, request each group URL, and report any that answers 200 with a
  zero-product list — the count is the finding, not the nav flag.
- The same split applies to pages: a `navigationTag` withholds a page from the bar and leaves it served
  (see the shortcut-child recipe above, which relies on exactly that).

## The shared default: `theme-default`'s `default_custom.css`

The affordance CSS is not a per-demo copy step — it is a first-class Distribution default, and it
is **not a separate layer**: the header-nav affordance core (carets, hover states, the reach
fixes below) ships **inside `theme-default`**
at `Templates/Designs/Swift-v2/Custom/default_custom.css`. There is no overlay concept in the
Distribution anymore — `theme-default` is the ONE presentation layer every edition composes
(`themes: ["default"]`), and the customer re-skin ladder starts FROM it ([`re-skin.md`](re-skin.md)).
Every Swift demo inherits carets/hover/reachable-dropdowns with zero per-demo CSS. Point new demos
at `theme-default`; only re-author the three truths below if building a bespoke skin that cannot
use it.

## Platform truth 1 (LRN-nav-03): the Popper-gap bridge

Hover opens the dropdown, but moving the mouse **down** toward it closes the panel mid-travel —
the submenu is unreachable at human mouse speed (Playwright's synthetic jump masks it, which is
why a first "verified" pass is often wrong). The panel is opened by Bootstrap/Popper, which
positions it with an inline `transform: translate3d(0, 56px, 0)` ≈ **16px below** the trigger.
That gap is dead space: the cursor entering it leaves the item's `:hover`, Swift's JS closes the
panel. `margin-top:0` cannot beat an inline transform, and any `:hover`-gated bridge is
self-defeating (`:hover` is already lost inside the gap).

Fix: bridge the gap with the **item's own `::after`, gated on the OPEN state** (`:has(> .show)`),
never on `:hover`. As the item's pseudo it hit-tests as the item, so the JS mouseleave-close never
fires while the cursor crosses:

```css
.megamenu-wrapper > nav > .nav-item.dropdown:has(> .dropdown-menu.show)::after,
.megamenu-wrapper > nav > .nav-item.dropdown:has(> .megamenu.show)::after {
  content: ""; position: absolute; left: 0; right: 0; top: 100%;
  height: 1.25rem;   /* must exceed the ~16px Popper offset */
  z-index: 1001;     /* above the header layout */
}
```

Requires CSS `:has()` (evergreen browsers 2023+). Rejected (all tried, all failed): `margin-top:0`
(inline transform wins); a `:hover`-gated `::before` bridge; a panel-anchored `.show::before`
bridge (out-stacked by header layout — hit-tests `DIV.flex-fill`).

## Platform truth 2 (LRN-nav-04): `::before` = icon, `::after` = underline

A CSS caret drawn on `::after` renders closed, rotates on open — and **disappears the moment the
panel opens**. An element has exactly one `::after`, and Swift's link utility classes
(`text-decoration-underline-hover` / `-accent-hover`, present on every `Menu.cshtml` nav-link)
implement their animated underline on that **same `::after`**. In the open state their rule wins:
it collapses the caret's side borders to 0 (the pseudo still exists and rotates, it just draws
nothing) and re-positions it absolutely at the link's bottom-left (the underline's geometry), so a
border-restored caret then renders **below** the item.

Fix: the caret rule must re-assert its box **and its position** in **every** open signal with
`!important` — border alone is not enough:

```css
.megamenu-wrapper > nav > .nav-item.dropdown:hover > .nav-link::after,
.megamenu-wrapper > nav > .nav-item.dropdown > .nav-link.show::after,
.megamenu-wrapper > nav > .nav-item.dropdown > .nav-link[aria-expanded="true"]::after {
  position: static !important; inset: auto !important;   /* undo the underline's absolute bottom-left */
  display: inline-block !important;
  width: .42em !important; height: .42em !important;
  border: 0 !important;
  border-right: 1.5px solid currentColor !important;
  border-bottom: 1.5px solid currentColor !important;
  transform: translateY(1px) rotate(-135deg);
}
```

Rule of thumb: **on Swift nav links, `::before` belongs to the icon and `::after` belongs to the
underline** — a third pseudo-consumer must fight or relocate. Alternative for a bespoke skin: draw
the caret as a `background-image`/mask on the link and side-step the collision. Debug trap: CSSOM
sheet-walking (`document.styleSheets` rule enumeration) returns empty for these colliding rules —
go straight to computed-style state diffs (closed vs real-JS-open) for pseudo-element fights.

## Platform truth 3 (LRN-nav-05): dropdown `min-width`

With long top-category labels, hover-open works but a straight-down move from the **right half** of
the label loses the panel. The stock `.dropdown-menu` `min-width` (~192px Bootstrap default) is
narrower than a long label (254px measured), and the panel is left-aligned, leaving a right-side
dead strip (31px measured) a downward path lands in.

```css
.megamenu-wrapper > nav > .nav-item.dropdown > .dropdown-menu,
.megamenu-wrapper > nav > .nav-item.dropdown > .megamenu { min-width: 100%; }  /* 100% of the trigger */
```

This is the **horizontal** half of the reach fix; LRN-nav-03 is the **vertical** half. Neither
alone suffices — the pair is the complete reach fix.

## Header height: count grid rows before hunting padding

A tall header pill that is **width-invariant** (e.g. 157px of chrome around 44px of real content, so
no breakpoint work shrinks it) is not a padding problem. Row COUNT is the dominant term: every extra
grid row on the header page costs its own row spacing plus container padding regardless of content
height, so squeezing container padding to ~2px per row buys nothing. The classic shape is the nav
and the search field each sitting in their OWN row (a `2ColumnsFlex`) beneath the logo/icons row;
the same root cause produces the ~470px mobile header (a cart icon alone in its own row).

So before writing CSS, `GET /Admin/Api/GridRowsByPageId?pageId=<header page>` and count the rows,
then look for a multi-column row with EMPTY columns sized for exactly the paragraphs that force the
extra row — empty columns come back as synthetic `id=0` placeholder paragraphs, not as nothing (see
[`paragraphs.md`](paragraphs.md)). The fix is a paragraph MOVE (`ParagraphSave` with `gridRowId` +
`gridRowColumn`) plus `GridRowDelete`: folding nav + search into the empty columns of a
`6ColumnsFlex` row took a measured pill from 157.3px to 84.6px with ZERO CSS changed. Column widths
inside the merged row are then governed by `flexibleColumns`, whose `0`/`1` semantics are inverted —
see [`admin-ui-authoring.md`](admin-ui-authoring.md).

Verify by asserting the count of `<section>` children under `[data-swift-page-header]` equals the
intended row count, and that the pill height drops **before** any stylesheet is deployed.

## Icons: opt-in, keyed on `data-nav-icon`

Icons are **not** in the default (keying them on customer href slugs breaks on every catalog).
They are an opt-in add-on keyed on a neutral `data-nav-icon="<name>"` hook set on the nav node's
CSS-class/attributes field, painted with `background-color: currentColor` via `mask-image` so each
icon inherits the nav text colour. `theme-default` ships **no custom icon set** — the mask SVGs
bind to the DW stock icons already on disk under `/Files/Images/Icons` (deployed with the Swift
design package). The `default_custom.css` core supplies the `[data-nav-icon]::before` box ready to
bind; a new icon is one `mask-image` line (pointing at a stock icon path) + the node field.

## How to verify (probes)

The Foundry gate's affordance leg runs four probes against the live storefront (proven green in
the source session); mirror them when hand-checking:

1. **Caret DOM** — every top `.nav-item.dropdown` carries `data-bs-toggle="dropdown"` AND
   `getComputedStyle(link,'::after').borderRightWidth !== '0px'`.
2. **Vertical reach (03)** — open a dropdown; `elementFromPoint(linkCenterX, (linkBottom+menuTop)/2)`
   is contained in the `.nav-item` subtree (the bridge hit-tests as the item).
3. **Open-state caret (04)** — with `aria-expanded="true"`, `::after` border-right ≠ 0 AND
   `::after` position is `static`.
4. **Horizontal reach (05)** — `menu.getBoundingClientRect().right >= link.right` for the
   longest-label item.

A synthetic click-jump masks the vertical-reach bug — verify with a real hover → move-down → click
of a submenu link, or the `elementFromPoint` midpoint probe above.
