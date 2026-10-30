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

## The critic

Give the screenshots to a fresh agent that has not seen the build notes, together with the goal
("an improved version of the source, not a copy") and last round's issues. Tell it the real
constraints, such as data the source does not publish, so it does not ask for invented content.
A prompt that works:

> You are a strict e-commerce UX critic. Compare the source screenshots with the new site's
> screenshots. The goal is an improved version of the source, not a copy. Score the new site out
> of 10, list the five most important issues with a concrete fix for each, and name any
> regressions since the last round.

Fix the issues, take new screenshots, and run the critic again.

## Stop rule

Stop when the score rises less than 0.3 over two rounds, or after the maximum number of rounds
agreed at intake. Then report the score history, the open issues, links to all pages, and the
tool defect list from `RUN-STATE.md`.

When the client can keep working toward a stated goal on its own, the loop can run unattended.
State a condition the agent's own output shows, such as the critic's score, and cap the rounds,
for example "the critic's latest score is at least 8/10 and it reports no regressions, or stop
after 6 rounds".
