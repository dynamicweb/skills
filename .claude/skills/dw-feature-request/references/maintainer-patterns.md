# How the DynamicWeb maintainer answers feature requests

Evidence for the rules in [SKILL.md](../SKILL.md), read from every issue on
https://github.com/dynamicweb/DynamicWeb that the maintainer (GitHub `nicped`, the platform
lead) replied to, from the tracker's first issues through #740. Issue numbers are the
citations; read the thread before relying on a line here.

## Contents

- [The numbers](#the-numbers)
- [Accepted shapes](#accepted-shapes)
- [Declined shapes and the wording used](#declined-shapes-and-the-wording-used)
- [Standing refusals and constraints](#standing-refusals-and-constraints)
- [Already possible: the answers given with a screenshot](#already-possible-the-answers-given-with-a-screenshot)
- [Areas under redesign](#areas-under-redesign)
- [Norms of the tracker](#norms-of-the-tracker)
- [Worked example](#worked-example)
- [Refreshing the corpus](#refreshing-the-corpus)

## The numbers

| Measure | Value |
|---|---|
| Issues with a maintainer reply | 272 (154 labelled `Feature request`, 46 `Bug`, the rest unlabelled or area-only) |
| Outcome of the 154 feature requests | 102 `Accepted`, 13 `Rejected`, 7 `Waiting for more votes`, 1 `More info needed`, 31 closed or open without a verdict label |
| First reply | median 0.7 days after the issue; 156 of 272 the same day, 219 within a week |
| First reply that is only a work-item link or id | 46 of 272 |
| First reply carrying a work-item reference | 109 of 272 |
| First reply that answers "you can already" | 62 of 272 |
| First reply that asks for the use case or context | 25 of 272 |

Two-thirds of labelled feature requests are accepted. The declined third is declined for
shape, and the shapes repeat.

## Accepted shapes

| Shape | What the request carried | Issues |
|---|---|---|
| **Parity**: X exists for A, add it for B | The sibling named (XML provider archives, CSV does not; standard columns sort, custom do not; users can be copied in DW9, not in DW10; `Update`/`UpdateWithIds` exist for product indexes, not content) | #602, #679, #277, #564, #686, #680, #622, #617, #548, #78, #83 |
| **Missing field, column, filter, parameter or action** in an existing screen or API | A screenshot of the screen and the one thing missing from it; often the SQL or the model property that already holds the value | #691, #675, #610, #581, #449, #532, #586, #605, #538, #209, #86, #118, #153, #66, #27, #475, #544, #147 |
| **Gap that reads as a defect once stated precisely** | "reports success but drops", "label is wrong", "variants should link to master" | #648, #718, #724, #630, #164, #379, #571, #33 |
| **Report whose analysis matches the code** | Root cause verified in source, repro from a clean install, nothing invented | #734 ("The analysis matches the code, and we've implemented the change"), #724 ("Both root causes in the report are correct"), #555 ("Great description"), #617, #30 |
| **Already in motion** | The request lands near a work item in progress and is closed with "already on its way" | #236, #616, #312, #324, #109, #56, #38, #133, #140, #530 |
| **Hook or notification following an existing pattern** | The sibling notification named, the use case given when asked | #592, #663 (accepted after "What is the use case?" was answered), #384 |
| **Logging or diagnostics** | Where the silence hurt and what to log | #75, #262, #501, #414 |
| **Admin productivity with a measurable cost** | "Today: open user, Edit, Fields tab. After: Details tab." | #153, #573, #618, #68, #14 |

What the accepts have in common: the first sentence names the gap, the existing way is
named, the change is small, and the maintainer can verify every claim in the source.

## Declined shapes and the wording used

| Shape | Wording | Issues |
|---|---|---|
| **Fix the setup, not the symptom** | "What link do they follow to that page and why is that link there? That is what should be fixed. Not the error message." / "missing some setup on some of the pages (redirect links and permissions)" / "Something is wrong and should be fixed" / "it is the business logic that is broken ;-)" | #739, #390, #246, #350, #370, #215, #557 |
| **Use the right structure** | "Use groups.... Pls. You will like it in the long run" / "should be avoided at all costs" / "create a group that uses a segment search as source" | #65, #71, #73, #213, #445 |
| **Conceptual veto** | "If you think this through, you will understand this is completely off." / "We will not do this." / "We did have this before and we will not re-introduce it." / "I do not agree on this one." / "I do not think we will make this feature." | #740, #410, #37, #243, #540, #198 |
| **Scale** | "We have customers with million of products and just the other day I saw one with 1.500.000 groups!" / "segment searches are slow" / "will cause significant performance issues" | #406, #445, #233, #213, #71 |
| **Breaking change** | "would break a lot of websites current URL structure" / "Changing the ID format in Dynamicweb would be a breaking change, so we cannot do that" | #164, #332, #388 |
| **Dependency constraint** | ImageSharp 2 cannot decode AVIF or TIFF with unspecified ExtraSamples; `Directory.GetFiles` has no regex; .NET has no XI country; the editor "do not seem to support it" | #6, #480, #334, #357, #591, #304 |
| **Use case not shown** | "Please provide some context. What is the use case?" / "Can you elaborate?" / "Not sure I follow. You have forgotten to specify where you are in the UI" / "I understand what you are trying to **do**. But I do not understand what you are trying to **achieve**" | #663, #283, #333, #159, #381, #90, #89, #479, #501, #294, #207, #591, #130 |
| **Workaround or repo access instead of a feature** | "You can easily implement that using an external service" / "Feel free to pull on the repo" / "Made the repo public" / attached templates | #301, #533, #278, #607, #72, #332, #330, #309, #425, #426 |
| **Roadmap close** | "We are currently working on a major overhaul" / "will mostly be part of Swift 2" / "in the making" | #390, #143, #11, #91, #248, #281, #374, #148, #413, #46, #377 |
| **Not a feature request, wrong tracker** | "That is not a feature request :-)" / "This is not a feature request. I will request a bugfix" / "DW9 - this issue tracker is related to DW10" / "please create a case in support" | #9, #211, #248, #692, #329, #606 |
| **Too big** | "Task is too big an risky..." / "not a priority" | #174, #357 |
| **Subjective UX** | "it is a subjective choice ... Let's see if others agree" / "That would basically mean that we can never change anything" | #90, #207, #488 |

The "use case not shown" rows are the ones that convert: #663, #333, #185 and #164 were
accepted once the answer was concrete. The conceptual vetoes do not convert; #740's author
conceded in one line and the thread stayed civil.

## Standing refusals and constraints

Do not re-file these; a new issue on the same concept is closed with the earlier ruling.

| Concept | Ruling | Issue |
|---|---|---|
| Different permissions for an impersonated session than for the account | "Impersonation is overtaking others permissions. and role. End of story." Direction: a seller acts on behalf of a customer without impersonation. | #740 |
| Separate storage for backend and extranet users | "We will not do this." (Entra provisioning answers the operational risk.) | #410 |
| Permissions on user or group *type* | "This is actually by design... To help you not get into trouble." Use groups and roles. | #65 |
| Global content container (text reused across pages) | "We did have this before and we will not re-introduce it." Use item or query publisher. | #37 |
| Image editing in the CMS beyond cropping | "I do not think we will make this feature. Except maybe cropping." | #540 |
| AVIF output from the image handler | External library, unmanaged decoders; "will of course do it as soon as we can support in managed code". | #6 |
| TIFF with unspecified ExtraSamples | ImageSharp 2 limitation; re-encode the files. | #480 |
| Regex in asset auto-check patterns | `Directory.GetFiles` has no regex; would need a second parameter; not planned. | #334 |
| Northern Ireland (XI) as a country | .NET has no such country; "not a priority". | #357 |
| Store UTC and convert to a server or user time zone | "Task is too big an risky..." | #174 |
| Remove the index build timeout | "No index should take that long - something else is wrong." Max 60 minutes. | #246 |
| Skip the payment gateway by default at amount 0 | Zero-auth for subscriptions needs the gateway. | #243 |
| Restrict the discount channel list to shops | "We would like not to limit when and how it can be used." | #198 |
| Assortments on a segment search or dynamic product list | "That will not happen as segment searches are slow." Use a group fed by the segment task. | #445 |
| Automatic 301 redirects on product or group rename | Not at scale; High Volume Product URLs and a prefilled URL field are the supported paths. | #406 |
| Stock-aware variant selector in standard Swift | "there is not one golden way of doing this"; variants, units, locations and live stock make it "buggy as hell". Customise the template. | #233 |
| Font size in the rich text editor | "a bad idea - and should not be used in modern days"; use typography styles. | #304 |
| Product selector for thousands of products in a discount | "We will remove the option to select this many products." Use a group. | #213 |
| Any DW9 feature | "New features are mainly DW10 only..." | #151, #21, #249, #212, #692, #329 |
| Backport of a feature to an earlier minor | Release policy; features go forward only. | #164, #641 |

`Waiting for more votes`, open or closed without a work item: save-and-close to overview
(#90), image editing (#540), checkbox list as user field (#518), list sub pages (#590), sitemap
per language (#25), order state visualisation (#9), OData per-user limits (#5), permissions on
types (#65).

## Already possible: the answers given with a screenshot

The maintainer answered these with "You can ..." and a screenshot. Check them before filing.

| Ask | Where it already is | Issue |
|---|---|---|
| Group names instead of ids in Prices & Discounts | Column chooser on the list | #609 |
| Active state per language in the product list | Add the language columns to the list | #653 |
| Impersonation for a whole group | The impersonation tab on the group | #471 |
| Custom 404 page | Websites > Domain and URL, the 404 page field (per website, not global) | #129 |
| Date and number format | Region on website settings; integration formats are the connector's job | #557 |
| Limit the countries in checkout and addresses | Delete them from the backend country list (one list for all websites) | #386 |
| Upload target folder in the visual editor | The default folder on the image field | #543 |
| Sender of the DAP download mail | `senderemail` on the export endpoint; the system email setting | #456 |
| Sort rows and paragraphs outside the visual editor | List view on the page | #359 |
| Clear all caches | Settings, the services list | #19 |
| Rows cloned published to sub-sites | The website copy setting | #380 |
| Secondary user (impersonation) on a Delivery API cart | `CustomerUserId` on `POST /dwapi/ecommerce/carts/create`, not on `PATCH` | #422 |
| Fewer properties in a Delivery API response | `?fields=Name,Email` on every view-model endpoint | #622 |
| Language for a Delivery API query | A second expression on `Parameter.LanguageID` beside the context macro | #384 |
| Users without a group | The All users node (angel users, type 0, are never listed) | #260, #14 |
| Version history of a scheduled task | Partly in the task's own history screens | #620 |
| Search in the product selector | Set the index under Products > Advanced | #157 |
| Multiple asset patterns | Concatenate with `;` | #98 |
| Resize list columns | Already in DW10, sticks per browser | #294 |
| Same user in two shops with separate favourites and addresses | Two users with the same username and a `ShopId` each | #211 |
| Refresh a JWT for the Delivery API | The refresh endpoint; later, the extranet cookie | #425 |

## Areas under redesign

A request inside one of these gets "coming in Swift 2" or "in the making" unless it names
the redesign and asks for a gap inside it.

| Area | What the maintainer said | Issues |
|---|---|---|
| Customer center, login, impersonation | "7 new apps for managing authentication, users, accounts, addresses, impersonation"; a profile widget to "go back to be your self or switch to another user"; impersonation itself "an odd solution to a much smaller problem" | #390, #740, #281, #248, #185 |
| Accounts and shared addresses | Account record on the customer number, addresses on the group, address codes from the ERP | #312, #130, #734, #729 |
| Repositories UI | "it will not be as in DW9 :-)"; top-down configuration "we are actually looking into exactly this" | #46, #504 |
| Rich text editor | Configurable modes "for simple, full and product mode" | #324, #64, #304, #156 |
| Firehose | "completely rewritten"; "open up separate feature request" for each ask | #413, #29 |
| Translations and language workflow | "this particular window will change in a release not to far away" | #143 |
| Discounts and price matrix | New discount experience; discounts in the price matrix; collections | #249, #213, #466, #497 |
| PIM completeness in queries | "We are looking at changing the concept of completeness" | #530 |
| Product list as a container of variants and languages | "we have talked about it" | #653 |
| MCP server | "we should work with some use cases that we as a minimum should support" | #377 |

## Norms of the tracker

- **One request per issue.** A list of ten wishes is closed with "open up separate feature
  request instead" (#29).
- **Update the post, not the thread.** "I am assuming your AI only looks at the original
  post" (#675) was right; a later comment with added scope was missed.
- **Feature or bug is decided by the maintainer**, and a feature can be relabelled a bug when
  the current behaviour contradicts a label, a document or a sibling (#630, #164, #248). A
  request that frames the gap as a broken promise travels faster than one that asks for an
  option.
- **A support case needs a solution link**; a public issue does not get one (#606).
- **ETA questions get the release policy** (#164): the work item page on doc.dynamicweb.dev
  shows the ring and version; a merge after the branch cut moves to the next minor.
- **Humour is normal and not hostile.** "Size does not matter - for banners. Only for egos'"
  (#488), "What is fax? Misspelling of Fox?" (#676), "Everything is possible for those who
  bears will in their heart..." (#379). Answer the substance, keep the tone.
- **Standards claims are checked.** "Can you please point to where in the google UCP it
  states ..." (#113); SEO agency claims are met with "Google indexes content - not URLs"
  (#388). Quote the source, not the expert.
- **A reply that concedes keeps the door open.** The author of #740 answered "Yes agreed" in
  one line; the redesigned flow the maintainer described is where the need will be met.

## Worked example

The gap: a signed-in frontend user who opens a page without Read permission gets a fixed,
untranslatable English text, before any template or notification runs. The anonymous branch
redirects to the login page or uses the permission template; the authenticated branch does
not. The first filing led with "customize the access denied response" and the maintainer
asked which link leads there and said the link is what should be fixed.

Scored against the checklist: use case present but second, existing way named, evidence
present, smallest change proposed as a notification (not parity), scale not relevant,
precedent not checked (impersonation ruled on in a sibling issue the same morning),
acceptance test present. Red flags: symptom first; the only scenario sits inside an area
under redesign (impersonation). Verdict: reframe.

The reframe answers the question first, concedes the link, and asks for parity with a
mechanism the maintainer already pointed to in #129:

```markdown
The rep reaches it without a link: back button, a second tab or a typed URL of the service
desk while still impersonating, and the stock "stop impersonating" link, which returns to the
page the rep stood on. Agreed that the stop link is a template fix; we send it to the desk
with a Redirect now.

The gap that remains: a signed-in user who reaches a page they may not read gets a fixed
English text on a Dutch storefront, and the site cannot change it. A missing page gets the
website's 404 page (Websites > Domain and URL) rendered in place with status 404; a denied
page has no such setting.

Request: an "Access denied page" setting beside the 404 page, rendered in place with status
403 through the same middleware path, falling back to today's text when empty. Nothing
configured, nothing changes; the denied page's content never renders either way.
```

Under 200 words, the first sentence answers the question, the ask is one setting that
mirrors an existing one, and the impersonation scenario is the illustration, not the request.

## Refreshing the corpus

```
gh issue list --repo dynamicweb/DynamicWeb --state all --search "commenter:nicped" --limit 500 \
  --json number,title,state,labels,author,createdAt,closedAt > issues.json
gh api "repos/dynamicweb/DynamicWeb/issues/comments?per_page=100&sort=created&direction=asc" \
  --paginate > comments.json
```

Join comments to issues on the issue number at the end of `issue_url`, keep the ones whose
`user.login` is the maintainer, and read the threads behind any label you plan to cite.
`scripts/find_precedent.py` does the join for one search at a time.
