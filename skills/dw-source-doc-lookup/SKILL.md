---
name: dw-source-doc-lookup
type: flow
group: source
mcp: optional
description: 'Consult the live Dynamicweb documentation (doc.dynamicweb.dev) as the source of truth before answering how a feature works, is configured, or fits together, using search_documentation and fetch_documentation_page. Triggers: "how does X work / how do I set up X", verifying an exact field/setting/macro/template-tag/API name, a configured feature that still does not behave as expected. Non-triggers: browsing the Dynamicweb C# source on GitHub for internal APIs/classes -> dw-source-explorer.'
---

# Documentation Lookup

## Without MCP

The `search_documentation` / `fetch_documentation_page` MCP tools are the preferred lookup
path. When no Dynamicweb MCP server is connected, fetch the same content directly from
https://doc.dynamicweb.dev/ over HTTP instead — the source of truth is the documentation
site, not the transport.

Use the live Dynamicweb documentation as the source of truth. When a question is about how a
feature works, how it is configured, or how parts of the platform fit together — and the exact
mechanism isn't certain — look it up before answering. Do not guess at field names, settings,
macros, template tags, or integration behavior.

## When to use this

- "How does X work / how do I set up X / how are X and Y connected?"
- Anything that would otherwise get hedged with "typically", "usually", or "probably".
- Verifying a specific name: an index field, a setting, a macro, a template tag, an API class.
- The user reports that something configured correctly still does not behave as expected — the
  missing piece is often a documented integration step that wasn't known about.

## How to use it

1. Call `search_documentation` with the user's question. Search works in any language — pass
   the question in the language the user used; do not translate it. Phrase it as a clear
   question or topic (feature + the part they care about), not a single vague word. If the
   user's question is NOT in English, also pass an English translation as `englishQuery`: it
   is used only by the built-in fallback (if the AI search is unavailable) so that fallback
   still works for non-English questions. Omit it when the question is already English.
2. It returns an `Answer` synthesized from the docs plus `Results` (the source pages). Ground
   the reply in that Answer and those sources — do not add mechanisms they don't support. If
   `CouldAnswer` is false or the Answer is thin, refine the question and search again before
   giving up.
3. The `Answer` is usually enough to reply directly — do NOT fetch a page on every turn. Only
   call `fetch_documentation_page` when the Answer is empty or thin, or when exact wording or
   more detail than the snippet gives is needed; then read the most relevant Result in full.
4. Answer in the user's own language, from what the docs actually say, and **cite the source
   URL(s)** so the answer can be verified.
5. If the docs genuinely do not cover it, say so plainly instead of inventing an answer — then
   fall back to inspecting the live solution with the other tools (read the relevant entity,
   query, or setting).

## Rules

- Never state a mechanism, field name, or setting as fact unless it's been confirmed — from
  the docs or from a tool result. Confirm first, then assert.
- One good fetched page beats five guessed sentences. Read before writing.
- A correct-looking backend configuration does not prove the frontend honors it; when a user
  says "it doesn't work," check the docs for the integration/rendering step, don't just
  re-confirm the config.
- Keep citing: end a factual answer with the doc URL(s) relied on.
