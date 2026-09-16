# Readiness gate — the four preconditions

Run this before the first crawl request and before the first write. Each precondition has a
check that produces evidence, and a stop rule. Report the four results together as a short
block, so the user can see what you are about to build into.

## Contents

- [1. A Dynamicweb 10 solution that is ready to be used](#1-a-dynamicweb-10-solution-that-is-ready-to-be-used)
- [2. The MCP connection points at that solution](#2-the-mcp-connection-points-at-that-solution)
- [3. A source URL, reachable and in scope](#3-a-source-url-reachable-and-in-scope)
- [4. An agreed build scope](#4-an-agreed-build-scope)
- [Reporting the gate](#reporting-the-gate)
- [Naming the build](#naming-the-build)

## 1. A Dynamicweb 10 solution that is ready to be used

"Reachable" is not the bar. The bar is *able to host a storefront*, which is six facts:

| Fact | Call | Ready means |
|---|---|---|
| The frontend answers | `get_frontend_health` | Healthy; a failing frontend makes every later visual check meaningless |
| There is a website to build into | `get_areas` | An area you may use, or agreement to create one |
| Swift 2 is installed | `get_layouts` | A v2 design folder is present — read its real name, commonly but not always `Swift-v2` |
| A language and a currency exist | `get_languages`, `get_currencies` | The locale the POC will demo in |
| There is a shop, or room for one | `get_shops` | The target shop, plus the PIM structure shop if the solution separates them |
| An index repository exists | `get_index_repositories` | The repository and index the storefront actually queries |

Two of these bite later if you skim them.

**The index name is per-solution.** The index tools default to a repository and index both
named `Products`, and a Swift storefront frequently queries something else entirely. Read the
real pair from `get_index_repositories` at gate time and write it down — rebuilding the wrong
index looks exactly like "the facet change did not work".

**Swift 2 must be the area's design, not merely installed.** An area on an older design renders
none of the v2 components this flow builds with.

Stop when: the frontend is unhealthy, no v2 design exists, or there is no shop and no mandate
to create one. Any of those is a setup task, not a POC task — route it to
[dw-setup-install](../../dw-setup-install) or the person who owns the install.

## 2. The MCP connection points at that solution

A server connected to a *different* Dynamicweb install answers every call happily, and the
mistake only surfaces after hundreds of writes. Prove identity before the first write, not
after.

Match something you can see from both sides: the area list and the front-end host. Fetch the
public URL the user gave you for the target solution, then confirm the same site appears in
`get_areas` — matching area name, its language, and its front page. When the solution is
reached only by URL and an admin key with no separate public host, `get_frontend_health` plus
`fetch_frontend_page_html` on the area's front page is the same proof.

When more than one MCP server is connected, name the one you are using in your report, and use
only that one for the whole build. Mixing servers mid-build splits the catalogue across two
installs.

Stop when: the connected server cannot be shown to be the solution the user means.

## 3. A source URL, reachable and in scope

Ask for one canonical origin and confirm it yourself rather than inferring it — `example.com`,
`www.example.com` and a regional subdomain often serve different catalogues, and the one the
user names in passing is not always the one they mean to demo.

Fetch the origin and record:

- the **locale path** the catalogue lives under, and whether switching locale changes prices,
- whether it is a **Dynamicweb 9 or 10 solution** — try `/dwapi/` on the origin. A delivery API
  is a structured product feed and turns the crawl from parsing into paging,
- the **product-listing entry points** and roughly how many products each holds,
- whether a **cookie or region interstitial** blocks first paint, since it will also block
  automated capture.

On entitlement: a POC built for the site's owner, from their public pages, at their request, is
the ordinary case — say so once in the report and continue. Read the origin's `robots.txt`,
keep to a polite request rate, and take only what the build needs. When the request is to crawl
a site the user has no relationship with, raise it before crawling rather than after.

Stop when: the origin does not resolve, or the catalogue sits behind a login the user has not
provided access to.

## 4. An agreed build scope

Four answers, and none of them is safely assumed:

- **Breadth** — the whole catalogue or named families, and the approximate product count. This
  decides whether the crawl is one pass or a batched job.
- **Locale** — language and currency for the demo.
- **Prices with or without VAT** — a single area setting (`pricesWithVat`), and the wrong choice
  is visible on every card. B2B-oriented sources usually quote excluding VAT; mirror the source
  unless the user says otherwise, and state which you chose.
- **Where it lands** — a new area and shop (the clean default for a POC, and trivially
  deletable) or an addition to something that exists.

State the answers back in one line before starting. That line is the authorization for the
whole run: once it is agreed, build to completion without stopping to re-confirm each phase.

## Reporting the gate

Report the four as a compact block naming the solution, the server, the source and the scope —
then start. A gate that reads as a wall of tool output buries the one line the user needs to
correct.

When a precondition is only partly met — a shop exists but has no index, a v2 design exists but
the area uses another — say which half is missing and what you propose, then proceed on the
answer.

## Naming the build

Pick the identifiers once, at the gate, and keep them stable for the whole build. Renaming a
group or an area after products are assigned costs more than it looks.

- **Area** — the brand name, as a person would say it.
- **Shop** — one shop for the catalogue. When the solution keeps a separate PIM structure shop,
  note both ids at the gate.
- **Groups** — mirror the source's own category names, because those names appear in the
  navigation and in the breadcrumb the user will read in the demo.
- **Field prefix** — one short prefix for every category field the build creates (two to four
  letters from the brand). It keeps this POC's fields sortable and separable from the fields
  the solution already has, and it makes cleanup afterwards a filter rather than an audit.
