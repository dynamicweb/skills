# Demo storytelling tactics (generic)

Universal tactics for any Dynamicweb 10 demo, regardless of vertical or domain. Sister skills (`dynamicweb-pim-demo`, `dynamicweb-swift-demo`, future sister skills) cross-reference this file rather than restating these tactics inline. Domain-specific demo tactics live in each sister skill's own `references/demo-storytelling.md` (e.g. PIM-flavoured tactics around governance-gap framing and hero-SKU walkthroughs stay in `dynamicweb-pim-demo/references/demo-storytelling.md`).

## Generic tactics

- **Audience shapes the narrative**: ecom/data leads want day-in-the-life ops demos; CFO/CIO want migration + governance ROI. Open every demo with a one-sentence framing tuned to the audience in the room -- "we'll walk through a CSR taking an EDI order from receipt to invoice" reads differently from "we'll walk through how the platform absorbs a Navision migration without a custom-controllers tax."
- **Speak the customer's words**: demo copy reads as "built for us" only when it uses the customer's own vocabulary. At demo start, read `<demo>\customer-context\` for their terminology — what they call customers / branches / orders / roles, their product nouns, their channel names, and the terms they avoid — and extract a wording glossary to `<demo>\notes\wording.md` (customer-context is read-only; transformed output goes to `notes\` per `references/customer-context.md`). Apply the glossary everywhere copy is authored: page names, paragraph copy, seeded personas, product data, the cheat-sheet page. A demo that says "branch" where the customer says "location" reads generic; matching their vocabulary is the cheapest realism win in the build.
- **Channel-specific groups + feeds (one source, N shapes)**: one SKU visible in multiple channel trees with different published shapes demonstrates "one source, N shapes" without requiring real connectors. The pattern: define one product in the catalog, create one feed per channel, and let the channel-specific group tree shape what each downstream consumer sees. The demo moment is "the same SKU shows here as DOT-WIDGET-BLACK-72 with the wholesale-partner copy and there as RES-WIDGET-ZWART-72 with the retailer-friendly copy -- same row, two reads, no custom code."

## How to consume this file

This is a routable reference: load it when planning a demo storyline, or cross-reference it from a sister skill's `references/demo-storytelling.md`. Sister skills may also paste individual bullets into their own demo-storytelling reference and add domain-flavoured cousins as needed. The two-source pattern (PIM-flavoured tactics in `dynamicweb-pim-demo/references/demo-storytelling.md` + generic tactics here) keeps both narrow and reusable.

If you're adding a new sister skill, grab whichever bullets apply, cross-reference or paste them, and add domain-flavoured cousins as needed. No need to mutate this file when adding sister skills -- it's deliberately closed.
