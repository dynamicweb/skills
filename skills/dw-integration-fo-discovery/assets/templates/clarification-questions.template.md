# <Organisation> — clarification questions (round <n>)

Each question stands on its own — no reading of the brief required. Evidence is stated first, the question
second. Please route to the owner named; redirect freely if someone else knows better.

| # | Owner | Evidence seen | Question |
|---|---|---|---|
| 1 | Process owner | `<identifier>` appears on sales lines, service cases, warranty transactions and custody records. | Walk us through the life of one unit from build to end-customer ownership: which systems and which identifiers does it pass through, and where does each identifier get assigned? |
| 2 | ERP admin | Field `<label>` on `<entity>` is filled on <x>% of rows. | What does `<label>` record, who fills it, and does anything downstream depend on it? |
| 3 | ERP admin | Field `<label>` on `<entity>` is empty on all rows since <date>. | Is `<label>` still in use anywhere, or can an integration ignore it? |
| 4 | Process owner | Legal entities `<A>` and `<B>` carry very different data (A: <summary>; B: <summary>). | What is the business role of each legal entity, and which of them should the portal serve? |
| 5 | IT | A scheduled export `<name>` runs <schedule> to `<destination>`. | What consumes this export today, and what would happen if it stopped? |
| 6 | IT | Objects with prefix `<prefix>` exist in the environment; no publisher could be identified. | Which vendor or team owns `<prefix>`, and is it scheduled for change? |
| 7 | Sales ops | Prices are held in `<structure>`; <x>% of order lines carry a manual override. | How is the price a reseller sees decided, and where are exceptions approved? |
| 8 | Master-data owner | Serialized tracking is active on item groups `<list>` only. | Which product families are tracked per unit, and what should the portal show for the others? |

Answered in earlier rounds (folded into the brief): <list or "none">
