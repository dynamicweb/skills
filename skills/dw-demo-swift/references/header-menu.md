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
- [The shared default: `theme-default`'s `default_custom.css`](#the-shared-default-theme-defaults-default_customcss)
- [Platform truth 1 (LRN-nav-03): the Popper-gap bridge](#platform-truth-1-lrn-nav-03-the-popper-gap-bridge)
- [Platform truth 2 (LRN-nav-04): `::before` = icon, `::after` = underline](#platform-truth-2-lrn-nav-04-before--icon-after--underline)
- [Platform truth 3 (LRN-nav-05): dropdown `min-width`](#platform-truth-3-lrn-nav-05-dropdown-min-width)
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

## The shared default: `theme-default`'s `default_custom.css`

The affordance CSS is not a per-demo copy step — it is a first-class Distribution default, and it
is **not a separate layer**: the former `theme-nav-polish` overlay layer is retired, and the
affordance core (carets, hover states, the reach fixes below) now ships **inside `theme-default`**
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
