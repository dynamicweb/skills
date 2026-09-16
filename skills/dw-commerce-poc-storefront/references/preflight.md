# Ground truth — deriving it, and when each piece is due

Two facts come from the user: the source site and the target solution. Everything else on this
page you work out for yourself, state in a line, and build on. The checks below produce
evidence; the derivations below replace questions.

## Contents

- [Before crawling](#before-crawling)
- [Before the first write](#before-the-first-write)
- [Deriving the scope instead of asking](#deriving-the-scope-instead-of-asking)
- [Naming the build](#naming-the-build)
- [Reporting as you go](#reporting-as-you-go)
- [The four genuine blockers](#the-four-genuine-blockers)

## Before crawling

Nothing here touches the Dynamicweb solution, so none of it waits on an MCP connection.

**The source origin.** Fetch the URL the user gave you and follow redirects to the canonical
host. `example.com`, `www.example.com` and a regional subdomain frequently serve different
catalogues, different prices and different locales; the one named in passing is not always the
one meant. Record what you land on.

While you have it open, take four readings:

- the **locale path** the catalogue sits under, and whether switching locale changes prices,
- whether `/dwapi/` answers — a Dynamicweb 9 or 10 source exposes a delivery API, which turns
  the crawl from parsing into paging,
- the **listing entry points** and roughly how many products each holds,
- whether a **cookie or region interstitial** blocks first paint, since it will also block
  automated capture.

Read `robots.txt` and keep to a polite rate. On entitlement: a POC built for the site's owner,
from their public pages, at their request, is the ordinary case — note it once and continue.

## Before the first write

Now the solution matters. Six facts, and two of them bite later if skimmed.

| Fact | Call | Ready means |
|---|---|---|
| The frontend answers | `get_frontend_health` | Healthy; a failing frontend makes every later visual check meaningless |
| There is a website to build into | `get_areas` | An area you may use, or room to create one |
| Swift 2 is installed | `get_layouts` | A v2 design folder is present — read its real name, commonly but not always `Swift-v2` |
| A language and a currency exist | `get_languages`, `get_currencies` | The locale the POC will demo in |
| There is a shop, or room for one | `get_shops` | The target shop, plus the PIM structure shop when the solution separates them |
| An index repository exists | `get_index_repositories` | The repository and index the storefront actually queries |

**The index name is per-solution.** The index tools default to a repository and index both named
`Products`, and a Swift storefront frequently queries something else entirely. Record the real
pair here — rebuilding the wrong index looks exactly like "the facet change did not work".

**Swift 2 must be the area's design, not merely installed.** An area on an older design renders
none of the v2 components this flow builds with.

**Prove the MCP server is this solution.** A server pointed at a different install answers every
call happily, and the mistake surfaces hundreds of writes later. Match something visible from
both sides: fetch the public URL for the target and confirm the same site in `get_areas` —
area name, language, front page. Where the solution is reached only by URL and an admin key,
`get_frontend_health` plus `fetch_frontend_page_html` on the front page is the same proof. When
several MCP servers are connected, name the one you are using and use only that one; mixing
servers mid-build splits the catalogue across two installs.

## Deriving the scope instead of asking

Each of these has a defensible default readable from the source or the solution. Take it, say
which you took, and move.

| Decision | Derive it from | Default |
|---|---|---|
| Breadth | The source's own category tree and product counts | The whole catalogue; batch the crawl when it runs to thousands |
| Locale | The locale the source's canonical host serves, matched against `get_languages` | The source's primary locale |
| Currency | The prices the source quotes | The source's currency |
| VAT display | Whether the source quotes incl. or excl. VAT, which also tells you whether it is B2B-oriented | Mirror the source; set the area's `pricesWithVat` to match and say so |
| Where it lands | Whether the solution has a free area and shop | A new area and shop — clean, and trivially deletable afterwards |
| Which attributes become facets | The fill-rate and distinct-value counts from the crawl, per `catalogue.md` | High fill, few distinct values |

The VAT one is worth a sentence in the report because it is visible on every card and is a
single setting to flip. The rest are visible in the result.

## Naming the build

Pick the identifiers once and keep them stable — renaming a group or an area after products are
assigned costs more than it looks.

- **Area** — the brand name, as a person would say it.
- **Shop** — one shop for the catalogue; note the PIM structure shop too when the solution
  separates them.
- **Groups** — mirror the source's own category names, because those names become the
  navigation, the breadcrumb and the page titles the demo audience reads.
- **Field prefix** — one short prefix for every category field the build creates, two to four
  letters from the brand. It keeps this POC's fields separable from the solution's existing
  ones, and makes cleanup a filter rather than an audit.

## Reporting as you go

One line per determination, as you make it, in the flow of the work: what you found, what you
chose, what you are doing next. That gives the user a place to correct a single decision
cheaply without being handed a checklist to approve.

Keep it to the facts that change the result — the source host you settled on, the area and shop
you are building into, the locale and VAT choice, the product count you are importing. A gate
that reads as a wall of tool output buries the one line worth reading.

## The four genuine blockers

Everything above is a judgment call you make. These four are the ones where continuing wastes
the work, so stop and say what you need:

1. **No usable solution** — the frontend does not answer, or there is no Swift 2 design to
   build on. That is a setup task; route it to [dw-setup-install](../../dw-setup-install) or the
   person who owns the install.
2. **The MCP server cannot be shown to be the intended solution.** Ask which server, rather than
   writing a catalogue into someone else's install.
3. **The source does not resolve, or its catalogue is behind a login** you were not given.
4. **No relationship with the site.** When the request is to crawl a site the user does not own
   and is not building for, raise it before crawling rather than after.
