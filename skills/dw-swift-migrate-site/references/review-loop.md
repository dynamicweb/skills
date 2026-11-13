# Review loop: screenshots, a critic agent, and a stop rule

Step 7 of [dw-swift-migrate-site](../SKILL.md). Judge the new site the way a customer would, by
looking at it, and improve it in rounds.

## Screenshots

Take full-page screenshots of the same page set on the source and the new site:

- The home page, a category page, and a product page; for a content-only scope, the home page and
  two typical content pages
- At a 1440px desktop viewport and a 390px phone viewport
- With a phone user agent for the phone shots: Swift picks the mobile header and footer from the
  visitor's device type, not the window width, so a desktop user agent in a narrow window shows
  the desktop layout
- After scrolling the page once to load lazy images, and after declining the cookie banner

Use the same pages and products every round, so scores compare.

Measure on the phone pages, besides the screenshots: the page does not scroll sideways (its scroll
width equals the viewport width; if not, name the element that sticks out), tap targets in the
menu and the buying path are at least 44 px, add-to-cart can be reached from the product page's
first screen or a sticky bar, and the phone menu reaches as many levels as the desktop menu.

All browser tabs share one cart: a critic or check that adds products changes the cart for every
tab.

## The critic

Give the screenshots to a fresh agent that has not seen the build notes, together with the brief
(the brand, its customers and visitors, the type of site, and the design decisions with their
reasons) and last round's issues. Tell it the real
constraints, such as data the source does not publish, so it does not ask for invented content.
A prompt that works:

> You are a strict UX critic for this type of site. Compare the source screenshots with the new
> site's screenshots, and judge the new site against the brief. The goal is a better site for this
> brand's visitors, not a copy of the source. Score the new site out of 10, list the five most
> important issues with a concrete fix for each, and name any regressions since the last round.

Fix the issues, take new screenshots, and run the critic again. After each round, state the
round number and the score in the conversation (for example "Round 3: 7.4/10"), so the user, and
a goal evaluator that only reads the conversation, can follow the loop.

## Stop rule

Stop when the score rises less than 0.3 over two rounds, or after the maximum number of rounds
agreed at intake. Then report the score history, the open issues, links to all pages, and the
tool defect list from `RUN-STATE.md`.

When the client can keep working toward a stated goal on its own, the loop can run unattended.
State a condition the agent's own output shows, such as the critic's score, and cap the rounds,
for example "the critic's latest score is at least 8/10 and it reports no regressions, or stop
after 6 rounds".
