---
name: dw-feature-request
description: Draft, score and reframe a feature request or a reply on the dynamicweb/DynamicWeb issue tracker so it matches how the maintainer triages. Triggers: writing a GitHub issue against DynamicWeb, answering a "More info needed" or "what is the use case" reply, deciding post, reframe or do not post. Changes to this skills repo -> dw-skill-authoring.
compatibility: Requires Python 3.12+ and the gh CLI for scripts/find_precedent.py
---

# Feature requests against dynamicweb/DynamicWeb

Load this before drafting an issue or a reply on https://github.com/dynamicweb/DynamicWeb.
One maintainer (the platform lead, GitHub handle `nicped`) answers nearly every feature
request himself, usually within a day, and the shape of the request decides the answer more
than its merit. The evidence behind each rule, with the issue numbers to read, is in
[references/maintainer-patterns.md](references/maintainer-patterns.md).

This skill never posts. It produces a draft and a verdict; the user posts.

## Contents

- [How the tracker is run](#how-the-tracker-is-run)
- [What a request must carry](#what-a-request-must-carry)
- [Shapes that get declined](#shapes-that-get-declined)
- [Review step: post, reframe or do not post](#review-step-post-reframe-or-do-not-post)
- [Templates](#templates)
- [Scripts (scripts/)](#scripts-scripts)

## How the tracker is run

- **Short replies, fast.** The median first reply lands within a day. Most accepts are a bare
  link to a DevOps work item on doc.dynamicweb.dev; "Accepted" means a work item exists, not a
  release date. Features ship in new minor versions only and trickle down by the release
  policy; asking for a backport is refused with a link to that policy (#164).
- **Labels carry the verdict.** `Feature request` or `Bug`, an area, then `Accepted`,
  `Rejected`, `Waiting for more votes` or `More info needed`. `More info needed` with a
  question means the ball is with the author; unanswered, the issue goes stale.
- **DW10 only.** A request for Dynamicweb 9 is closed on sight (#692, #151, #21, #249).
- **The original post is what gets read.** Scope added in a comment is missed (#675). Edit
  the post when the scope changes.
- **Every identifier is checked against the code.** "Your ai is referencing a lot of fields
  that does not exist" closed #621. One invented field, class or setting discredits the whole
  request; a report whose "analysis matches the code" (#734) is implemented the same week.
- **Requests are design input, not specifications.** The maintainer decomposes and redesigns
  (#497, #729, #734, #164, #146). State the gap and the smallest change; leave the mechanism
  open and he fills it in, often wider than asked.
- **He proposes the workaround first.** A screenshot of the existing setting, a template
  attachment, a code snippet or repo access closes more requests than a refusal does
  (#609, #607, #425, #533). Name the existing way yourself, with the fact that makes it
  insufficient, or the reply will be that screenshot.

## What a request must carry

Score one point for each item that is present and true.

1. **Use case in two sentences.** The role, the screen or flow or API, how often, and the
   business reason. "A customer wants" is not a reason; "the rep does this for every call" is.
2. **The existing way, named.** The setting, column, action, parameter or template that comes
   closest today, and the one fact that makes it fall short. "None found after checking X
   and Y" counts; silence invites "You can already ...".
3. **Evidence from the product.** The version, a screenshot or a repro on a clean install, or
   a code path that exists. Nothing from memory; nothing a quick grep of the source denies.
4. **The smallest change, as parity.** X exists for A, add it for B: the 404 page is a
   website setting and the denied page is not; the XML provider archives source files and the
   CSV provider does not (#602); standard columns sort and custom columns do not (#679).
   Parity requests are the most accepted shape in the corpus.
5. **Platform-consistent shape.** Mirrors how the product already does the same thing
   elsewhere, keeps today's behaviour when nothing is configured, breaks no URL, ID or stored
   value.
6. **Scale stated.** What the change does with a million products, 1.5 million groups, 6,500
   users in one group, a thousand variants, live inventory. Scale is checked before merit
   (#406, #233, #445, #213, #71).
7. **Precedent checked.** No standing refusal on the concept, no roadmap item already covering
   it, no open or closed issue asking the same. `scripts/find_precedent.py` searches the
   tracker; the reference lists the refusals on record.
8. **Acceptance test.** One line an implementer can check, plus "with nothing configured,
   behaviour is unchanged".

## Shapes that get declined

Each one present subtracts two points.

- **Symptom first.** The request is about the message, label, colour or wording and not the
  gap behind it. "That is what should be fixed. Not the error message." (#739).
- **Institutionalises a misuse.** Per-user permissions, thousands of single products in a
  selector, a segment search in a hot path, impersonation as a security boundary, a longer
  timeout for a slow index (#65, #213, #445, #740, #246). The reply names the right structure
  ("Use groups.... Pls.") and the issue closes.
- **Changes the meaning of something that exists** or breaks URLs, IDs or stored values
  (#164, #332, #388). A new option beside the old one is accepted; a changed default is not.
- **Hypothetical path.** "A link in a mail could lead there" without an observed case. The
  reply is "why is that link there".
- **Area under redesign, unacknowledged.** Customer center, login and impersonation (#390,
  #740), repositories UI (#46), rich text editor (#324), Firehose (#413), translations
  (#143), discounts (#249). The reply is "coming in Swift 2" or "in the making" and the
  issue closes. Acknowledge the redesign and ask for the gap inside it.
- **Constrained dependency.** ImageSharp 2 (#6, #480), the .NET country list (#357), Quill
  (#304, #591), Kestrel synchronous IO (#323). Refused with the constraint named; see the
  reference before asking again.
- **DW9**, or a request that reads as a support case (the reply is "create a case in
  support", #606).
- **Subjective UX preference** with no measurable cost (clicks, minutes, errors). Lands in
  `Waiting for more votes` and stays there (#90, #540, #518).

## Review step: post, reframe or do not post

1. Read the draft as the maintainer would: what is the first sentence about? If it is the
   symptom, the verdict is **reframe** before any scoring.
2. Score the checklist (0 to 8) and subtract the red flags.
3. Search precedent and read every hit that carries `Rejected`, `Waiting for more votes`, or
   a reply with "we will not", "will not happen", "not a priority" or "by design":

   ```
   python3 scripts/find_precedent.py --search "<two or three words from the ask>"
   ```

4. Verdict:
   - **Post**: 6 or more, no red flag, no standing refusal on the concept.
   - **Reframe**: 3 to 5, or one red flag. Rewrite so the first sentence names the gap as a
     missing parity, put the use case before the proposal, cut every paragraph the maintainer
     did not ask for, and name the existing way with its limit.
   - **Do not post**: 2 or less, two red flags, or a standing refusal on the same concept
     ("We will not do this.", "completely off", "That will not happen"). Record the supported
     path instead (a group structure, a template, the Delivery API parameter, the roadmap
     item to follow) and tell the user why.
5. **Replying to a question** ("what is the use case", "please elaborate", "what link"):
   answer the question in the first two sentences, concede what is true, then restate the
   smallest change in one paragraph. Under 200 words. A long thread gets "this is an extremely
   confusing thread to understand" (#130) and a one-line close.
6. **Replying to a refusal**: do not argue the concept. Either accept it in one line (#740's
   author did, and the door to the redesigned flow stayed open) or open a new issue for the
   narrower gap that survives the refusal.

## Templates

Issue body, the shape the recent accepts carried (#734, #729, #725, #724, #718):

```markdown
## Summary
<Who cannot do what, where, today. The parity that exists elsewhere. Two or three sentences,
no file paths, no type names.>

## Acceptance criteria
- [ ] With nothing configured, behaviour is unchanged.
- [ ] <The one observable change, as the user sees it.>
- [ ] <The limit that keeps scale safe, when scale is a risk.>

<details><summary>Technical notes</summary>

- Existing way and why it falls short: <setting, screen or endpoint, verified on 10.x.y>
- Smallest change: <one mechanism, mirrors <existing mechanism>>
- Code: <path, type or member that exists in the current source>

</details>
```

Reply to a "what is the use case" question:

```markdown
<Direct answer: the role, the flow, the observed path to the gap. Two sentences.>
<Concede what the maintainer got right, in one sentence.>
<The smallest change, as parity with an existing mechanism, in one short paragraph.>
```

A worked example of both, built around a denied page for a signed-in user, is in the
reference under "Worked example".

## Scripts (scripts/)

| Script | Reads / writes | What it does |
|---|---|---|
| [find_precedent.py](scripts/find_precedent.py) | READ-ONLY (GitHub, through `gh`) | Lists DynamicWeb issues whose title, body or comments match the search words, with state, labels and the maintainer's replies, so precedent and standing refusals are found before a draft is posted. |

Run it from the skill folder, with `gh` signed in:

```
python3 scripts/find_precedent.py --search "access denied"
python3 scripts/find_precedent.py --search impersonation --rejected-only
python3 scripts/find_precedent.py --search "sort column" --limit 20
```

Refreshing the corpus behind the reference (every issue the maintainer replied to) is a
`gh` one-liner documented in the reference under "Refreshing the corpus".
